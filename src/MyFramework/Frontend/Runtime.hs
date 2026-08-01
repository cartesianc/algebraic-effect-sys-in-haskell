module MyFramework.Frontend.Runtime
  ( RuntimeData (..)
  , RuntimeValueError (..)
  , FrontendReadHandler
  , FrontendEffectHandler
  , FrontendHandlers
  , FrontendRegistryError (..)
  , EffectOccurrence (..)
  , FrontendExecutionStatus (..)
  , FrontendRuntimeFailure (..)
  , FrontendRuntimeSnapshot (..)
  , FrontendRunResult (..)
  , emptyFrontendHandlers
  , registerFrontendRead
  , registerFrontendEffect
  , runReferencedProgram
  ) where

import Control.Concurrent
  ( forkIO )
import Control.Concurrent.MVar
  ( MVar
  , modifyMVar
  , modifyMVar_
  , newEmptyMVar
  , newMVar
  , putMVar
  , readMVar
  )
import Control.Exception
  ( SomeException
  , try
  )
import Control.Monad
  ( foldM )
import qualified Data.Map.Strict as Map

import MyFramework.Frontend
import MyFramework.Handler
  ( RuntimeData (..)
  , RuntimeValueError (..)
  , validateRuntimeData
  )

type FrontendReadHandler =
  IO (Either String RuntimeData)

type FrontendEffectHandler =
  RuntimeData -> IO (Either String ())

data FrontendHandlers = FrontendHandlers
  { frontendReadHandlers ::
      Map.Map ReadKey FrontendReadHandler
  , frontendEffectHandlers ::
      Map.Map EffectAddress FrontendEffectHandler
  }

data FrontendRegistryError
  = DuplicateFrontendReadHandler ReadKey
  | DuplicateFrontendEffectHandler EffectAddress
  deriving (Eq, Ord, Read, Show)

data EffectOccurrence = EffectOccurrence
  { effectOccurrenceModulePath :: OccurrencePath
  , effectOccurrenceAddress :: EffectAddress
  }
  deriving (Eq, Ord, Read, Show)

data FrontendExecutionStatus
  = FrontendPending
  | FrontendRunning
  | FrontendSucceeded
  | FrontendFailed
  deriving (Eq, Ord, Read, Show)

data FrontendRuntimeFailure
  = FrontendValidationFailed [FrontendError]
  | FrontendEffectHandlerMissing EffectAddress
  | FrontendReadHandlerMissing ReadKey
  | FrontendReadValueInvalid ReadKey RuntimeValueError
  | FrontendParamValueInvalid
      EffectAddress
      [ParamKey]
      RuntimeValueError
  | FrontendReadHandlerFailed ReadKey String
  | FrontendEffectHandlerFailed EffectOccurrence String
  | FrontendHandlerThrew String
  | FrontendFallbackExhausted OccurrencePath [FrontendRuntimeFailure]
  | FrontendParallelFailed OccurrencePath [FrontendRuntimeFailure]
  | FrontendControlUnsupported OccurrencePath ControlKind
  deriving (Eq, Show)

data FrontendRuntimeSnapshot = FrontendRuntimeSnapshot
  { frontendSnapshotEffects ::
      [(EffectOccurrence, FrontendExecutionStatus)]
  , frontendSnapshotReads ::
      [(ReadKey, FrontendExecutionStatus)]
  }
  deriving (Eq, Show)

data FrontendRunResult = FrontendRunResult
  { frontendRunOutcome :: Either FrontendRuntimeFailure ()
  , frontendRunSnapshot :: FrontendRuntimeSnapshot
  }
  deriving (Eq, Show)

data RuntimeEnvironment = RuntimeEnvironment
  { runtimeProgram :: ReferencedProgram
  , runtimeHandlers :: FrontendHandlers
  , runtimeEffectFlights ::
      MVar
        ( Map.Map
            EffectOccurrence
            (MVar (Either FrontendRuntimeFailure ()))
        )
  , runtimeReadFlights ::
      MVar
        ( Map.Map
            ReadKey
            (MVar (Either FrontendRuntimeFailure RuntimeData))
        )
  , runtimeEffectStatuses ::
      MVar (Map.Map EffectOccurrence FrontendExecutionStatus)
  , runtimeReadStatuses ::
      MVar (Map.Map ReadKey FrontendExecutionStatus)
  }

emptyFrontendHandlers :: FrontendHandlers
emptyFrontendHandlers =
  FrontendHandlers
    { frontendReadHandlers = Map.empty
    , frontendEffectHandlers = Map.empty
    }

registerFrontendRead ::
  ReadKey ->
  FrontendReadHandler ->
  FrontendHandlers ->
  Either FrontendRegistryError FrontendHandlers
registerFrontendRead currentKey currentHandler currentHandlers
  | Map.member currentKey (frontendReadHandlers currentHandlers) =
      Left (DuplicateFrontendReadHandler currentKey)
  | otherwise =
      Right
        currentHandlers
          { frontendReadHandlers =
              Map.insert
                currentKey
                currentHandler
                (frontendReadHandlers currentHandlers)
          }

registerFrontendEffect ::
  EffectAddress ->
  FrontendEffectHandler ->
  FrontendHandlers ->
  Either FrontendRegistryError FrontendHandlers
registerFrontendEffect currentAddress currentHandler currentHandlers
  | Map.member currentAddress (frontendEffectHandlers currentHandlers) =
      Left (DuplicateFrontendEffectHandler currentAddress)
  | otherwise =
      Right
        currentHandlers
          { frontendEffectHandlers =
              Map.insert
                currentAddress
                currentHandler
                (frontendEffectHandlers currentHandlers)
          }

runReferencedProgram ::
  ReferencedProgram ->
  FrontendHandlers ->
  IO FrontendRunResult
runReferencedProgram currentProgram currentHandlers =
  case resolveProgram currentProgram of
    Left currentErrors ->
      pure
        FrontendRunResult
          { frontendRunOutcome =
              Left (FrontendValidationFailed currentErrors)
          , frontendRunSnapshot =
              FrontendRuntimeSnapshot [] []
          }
    Right currentRoot -> do
      currentEnvironment <-
        newRuntimeEnvironment currentProgram currentHandlers
      currentOutcome <-
        executeNode currentEnvironment currentRoot
      currentSnapshot <-
        snapshotRuntime currentEnvironment
      pure
        FrontendRunResult
          { frontendRunOutcome = currentOutcome
          , frontendRunSnapshot = currentSnapshot
          }

newRuntimeEnvironment ::
  ReferencedProgram ->
  FrontendHandlers ->
  IO RuntimeEnvironment
newRuntimeEnvironment currentProgram currentHandlers = do
  currentEffectFlights <- newMVar Map.empty
  currentReadFlights <- newMVar Map.empty
  currentEffectStatuses <- newMVar Map.empty
  currentReadStatuses <- newMVar Map.empty
  pure
    RuntimeEnvironment
      { runtimeProgram = currentProgram
      , runtimeHandlers = currentHandlers
      , runtimeEffectFlights = currentEffectFlights
      , runtimeReadFlights = currentReadFlights
      , runtimeEffectStatuses = currentEffectStatuses
      , runtimeReadStatuses = currentReadStatuses
      }

snapshotRuntime ::
  RuntimeEnvironment ->
  IO FrontendRuntimeSnapshot
snapshotRuntime currentEnvironment = do
  currentEffects <-
    Map.toAscList <$> readMVar (runtimeEffectStatuses currentEnvironment)
  currentReads <-
    Map.toAscList <$> readMVar (runtimeReadStatuses currentEnvironment)
  pure
    FrontendRuntimeSnapshot
      { frontendSnapshotEffects = currentEffects
      , frontendSnapshotReads = currentReads
      }

executeNode ::
  RuntimeEnvironment ->
  ResolvedNode ->
  IO (Either FrontendRuntimeFailure ())
executeNode currentEnvironment currentNode =
  case currentNode of
    ResolvedEffectLeaf currentPath currentAddress currentEffect ->
      executeEffect
        currentEnvironment
        (moduleOccurrencePath currentPath)
        currentAddress
        currentEffect
    ResolvedControl currentPath _ currentKind currentChildren ->
      case currentKind of
        ControlChain ->
          executeChain currentEnvironment currentChildren
        ControlParallel ->
          executeParallel
            currentEnvironment
            currentPath
            currentChildren
        ControlFallback ->
          executeFallback
            currentEnvironment
            currentPath
            currentChildren
        ControlRace ->
          pure
            ( Left
                (FrontendControlUnsupported currentPath ControlRace)
            )

executeChain ::
  RuntimeEnvironment ->
  [ResolvedNode] ->
  IO (Either FrontendRuntimeFailure ())
executeChain currentEnvironment =
  foldM executeOne (Right ())
  where
    executeOne currentOutcome currentNode =
      case currentOutcome of
        Left currentFailure ->
          pure (Left currentFailure)
        Right () ->
          executeNode currentEnvironment currentNode

executeParallel ::
  RuntimeEnvironment ->
  OccurrencePath ->
  [ResolvedNode] ->
  IO (Either FrontendRuntimeFailure ())
executeParallel currentEnvironment currentPath currentChildren = do
  currentWaiters <-
    mapM startChild currentChildren
  currentOutcomes <-
    mapM readMVar currentWaiters
  let currentFailures =
        [ currentFailure
        | Left currentFailure <- currentOutcomes
        ]
  pure
    ( case currentFailures of
        [] ->
          Right ()
        _ ->
          Left
            (FrontendParallelFailed currentPath currentFailures)
    )
  where
    startChild currentChild = do
      currentWaiter <- newEmptyMVar
      _ <-
        forkIO $ do
          currentOutcome <-
            executeNode currentEnvironment currentChild
          putMVar currentWaiter currentOutcome
      pure currentWaiter

executeFallback ::
  RuntimeEnvironment ->
  OccurrencePath ->
  [ResolvedNode] ->
  IO (Either FrontendRuntimeFailure ())
executeFallback currentEnvironment currentPath =
  tryChildren []
  where
    tryChildren currentFailures remainingChildren =
      case remainingChildren of
        [] ->
          pure
            ( Left
                ( FrontendFallbackExhausted
                    currentPath
                    (reverse currentFailures)
                )
            )
        currentChild : laterChildren -> do
          currentOutcome <-
            executeNode currentEnvironment currentChild
          case currentOutcome of
            Right () ->
              pure (Right ())
            Left currentFailure ->
              tryChildren
                (currentFailure : currentFailures)
                laterChildren

executeEffect ::
  RuntimeEnvironment ->
  OccurrencePath ->
  EffectAddress ->
  EffectDecl ->
  IO (Either FrontendRuntimeFailure ())
executeEffect
  currentEnvironment
  currentModulePath
  currentAddress
  currentEffect = do
    let currentOccurrence =
          EffectOccurrence
            { effectOccurrenceModulePath = currentModulePath
            , effectOccurrenceAddress = currentAddress
            }
    (currentOwner, currentFlight) <-
      acquireEffectFlight currentEnvironment currentOccurrence
    if currentOwner
      then do
        setEffectStatus
          currentEnvironment
          currentOccurrence
          FrontendRunning
        currentOutcome <-
          safely
            (runEffectOwner currentEnvironment currentOccurrence currentEffect)
        setEffectStatus
          currentEnvironment
          currentOccurrence
          ( either
              (const FrontendFailed)
              (const FrontendSucceeded)
              currentOutcome
          )
        putMVar currentFlight currentOutcome
        pure currentOutcome
      else
        readMVar currentFlight

runEffectOwner ::
  RuntimeEnvironment ->
  EffectOccurrence ->
  EffectDecl ->
  IO (Either FrontendRuntimeFailure ())
runEffectOwner currentEnvironment currentOccurrence currentEffect = do
  currentInputOutcome <-
    executeEffectInput currentEnvironment currentOccurrence currentEffect
  case currentInputOutcome of
    Left currentFailure ->
      pure (Left currentFailure)
    Right () -> do
      currentArguments <-
        evaluateEffectParams
          currentEnvironment
          (effectOccurrenceAddress currentOccurrence)
          (effectDeclParams currentEffect)
      case currentArguments of
        Left currentFailure ->
          pure (Left currentFailure)
        Right currentData ->
          case
              Map.lookup
                (effectOccurrenceAddress currentOccurrence)
                ( frontendEffectHandlers
                    (runtimeHandlers currentEnvironment)
                ) of
            Nothing ->
              pure
                ( Left
                    ( FrontendEffectHandlerMissing
                        (effectOccurrenceAddress currentOccurrence)
                    )
                )
            Just currentHandler -> do
              currentResult <-
                currentHandler currentData
              pure
                ( case currentResult of
                    Left currentMessage ->
                      Left
                        ( FrontendEffectHandlerFailed
                            currentOccurrence
                            currentMessage
                        )
                    Right () ->
                      Right ()
                )

executeEffectInput ::
  RuntimeEnvironment ->
  EffectOccurrence ->
  EffectDecl ->
  IO (Either FrontendRuntimeFailure ())
executeEffectInput currentEnvironment currentOccurrence currentEffect =
  case effectDeclInput currentEffect of
    Nothing ->
      pure (Right ())
    Just currentInput ->
      case
          lookupEffect
            (runtimeProgram currentEnvironment)
            (effectAddressModule (effectOccurrenceAddress currentOccurrence))
            currentInput of
        Nothing ->
          pure
            ( Left
                ( FrontendEffectHandlerMissing
                    EffectAddress
                      { effectAddressModule =
                          effectAddressModule
                            (effectOccurrenceAddress currentOccurrence)
                      , effectAddressKey = currentInput
                      }
                )
            )
        Just currentInputEffect ->
          executeEffect
            currentEnvironment
            (effectOccurrenceModulePath currentOccurrence)
            EffectAddress
              { effectAddressModule =
                  effectAddressModule
                    (effectOccurrenceAddress currentOccurrence)
              , effectAddressKey = currentInput
              }
            currentInputEffect

lookupEffect ::
  ReferencedProgram ->
  ModuleName ->
  LocalKey ->
  Maybe EffectDecl
lookupEffect currentProgram currentModule currentKey =
  case
      [ currentEffect
      | currentEffectModule <- referencedProgramEffects currentProgram
      , effectModuleName currentEffectModule == currentModule
      , (currentFieldKey, currentEffect) <-
          effectRecordFields (effectModuleRecord currentEffectModule)
      , currentFieldKey == currentKey
      ] of
    currentEffect : _ ->
      Just currentEffect
    [] ->
      Nothing

evaluateEffectParams ::
  RuntimeEnvironment ->
  EffectAddress ->
  [(ParamKey, ParamBinding)] ->
  IO (Either FrontendRuntimeFailure RuntimeData)
evaluateEffectParams currentEnvironment currentAddress currentParams = do
  currentFields <-
    evaluateBindings
      currentEnvironment
      currentAddress
      []
      currentParams
  pure (RuntimeRecord <$> currentFields)

evaluateBindings ::
  RuntimeEnvironment ->
  EffectAddress ->
  [ParamKey] ->
  [(ParamKey, ParamBinding)] ->
  IO
    ( Either
        FrontendRuntimeFailure
        [(FieldName, RuntimeData)]
    )
evaluateBindings currentEnvironment currentAddress currentPath =
  foldM evaluateOne (Right [])
  where
    evaluateOne currentOutcome (currentKey, currentBinding) =
      case currentOutcome of
        Left currentFailure ->
          pure (Left currentFailure)
        Right currentFields -> do
          currentValue <-
            evaluateBinding
              currentEnvironment
              currentAddress
              (currentPath ++ [currentKey])
              currentBinding
          pure
            ( fmap
                ( \currentData ->
                    currentFields
                      ++ [(FieldName (paramKeyText currentKey), currentData)]
                )
                currentValue
            )

evaluateBinding ::
  RuntimeEnvironment ->
  EffectAddress ->
  [ParamKey] ->
  ParamBinding ->
  IO (Either FrontendRuntimeFailure RuntimeData)
evaluateBinding
  currentEnvironment
  currentAddress
  currentPath
  currentBinding = do
    currentValue <-
      case paramBindingSource currentBinding of
        ParamFromRead currentRead ->
          resolveRead currentEnvironment currentRead
        ParamFromLiteral currentLiteral ->
          pure (Right (literalRuntimeData currentLiteral))
        ParamFromRecord currentChildren -> do
          currentFields <-
            evaluateBindings
              currentEnvironment
              currentAddress
              currentPath
              currentChildren
          pure (RuntimeRecord <$> currentFields)
    pure
      ( currentValue >>= \currentData ->
          case
              validateRuntimeData
                (paramBindingSchema currentBinding)
                currentData of
            Left currentError ->
              Left
                ( FrontendParamValueInvalid
                    currentAddress
                    currentPath
                    currentError
                )
            Right () ->
              Right currentData
      )

resolveRead ::
  RuntimeEnvironment ->
  ReadKey ->
  IO (Either FrontendRuntimeFailure RuntimeData)
resolveRead currentEnvironment currentKey = do
  (currentOwner, currentFlight) <-
    acquireReadFlight currentEnvironment currentKey
  if currentOwner
    then do
      setReadStatus currentEnvironment currentKey FrontendRunning
      currentOutcome <-
        safely (runReadOwner currentEnvironment currentKey)
      setReadStatus
        currentEnvironment
        currentKey
        ( either
            (const FrontendFailed)
            (const FrontendSucceeded)
            currentOutcome
        )
      putMVar currentFlight currentOutcome
      pure currentOutcome
    else
      readMVar currentFlight

runReadOwner ::
  RuntimeEnvironment ->
  ReadKey ->
  IO (Either FrontendRuntimeFailure RuntimeData)
runReadOwner currentEnvironment currentKey =
  case
      Map.lookup
        currentKey
        (frontendReadHandlers (runtimeHandlers currentEnvironment)) of
    Nothing ->
      pure (Left (FrontendReadHandlerMissing currentKey))
    Just currentHandler -> do
      currentResult <- currentHandler
      case currentResult of
        Left currentMessage ->
          pure
            (Left (FrontendReadHandlerFailed currentKey currentMessage))
        Right currentData ->
          case lookupReadSchema (runtimeProgram currentEnvironment) currentKey of
            Nothing ->
              pure (Left (FrontendReadHandlerMissing currentKey))
            Just currentSchema ->
              pure
                ( case validateRuntimeData currentSchema currentData of
                    Left currentError ->
                      Left
                        ( FrontendReadValueInvalid
                            currentKey
                            currentError
                        )
                    Right () ->
                      Right currentData
                )

lookupReadSchema ::
  ReferencedProgram ->
  ReadKey ->
  Maybe SchemaIdentity
lookupReadSchema currentProgram currentKey =
  lookup
    currentKey
    (readRegistryFields (referencedProgramReads currentProgram))

literalRuntimeData :: ParamLiteral -> RuntimeData
literalRuntimeData currentLiteral =
  case currentLiteral of
    ParamText currentText ->
      RuntimeText currentText
    ParamInteger currentInteger ->
      RuntimeInteger currentInteger
    ParamBoolean currentBoolean ->
      RuntimeBool currentBoolean
    ParamUnit ->
      RuntimeUnit

acquireEffectFlight ::
  RuntimeEnvironment ->
  EffectOccurrence ->
  IO
    ( Bool
    , MVar (Either FrontendRuntimeFailure ())
    )
acquireEffectFlight currentEnvironment currentOccurrence =
  modifyMVar
    (runtimeEffectFlights currentEnvironment)
    ( \currentFlights ->
        case Map.lookup currentOccurrence currentFlights of
          Just currentFlight ->
            pure
              ( currentFlights
              , (False, currentFlight)
              )
          Nothing -> do
            currentFlight <- newEmptyMVar
            pure
              ( Map.insert
                  currentOccurrence
                  currentFlight
                  currentFlights
              , (True, currentFlight)
              )
    )

acquireReadFlight ::
  RuntimeEnvironment ->
  ReadKey ->
  IO
    ( Bool
    , MVar (Either FrontendRuntimeFailure RuntimeData)
    )
acquireReadFlight currentEnvironment currentKey =
  modifyMVar
    (runtimeReadFlights currentEnvironment)
    ( \currentFlights ->
        case Map.lookup currentKey currentFlights of
          Just currentFlight ->
            pure
              ( currentFlights
              , (False, currentFlight)
              )
          Nothing -> do
            currentFlight <- newEmptyMVar
            pure
              ( Map.insert currentKey currentFlight currentFlights
              , (True, currentFlight)
              )
    )

setEffectStatus ::
  RuntimeEnvironment ->
  EffectOccurrence ->
  FrontendExecutionStatus ->
  IO ()
setEffectStatus currentEnvironment currentOccurrence currentStatus =
  modifyMVar_
    (runtimeEffectStatuses currentEnvironment)
    (pure . Map.insert currentOccurrence currentStatus)

setReadStatus ::
  RuntimeEnvironment ->
  ReadKey ->
  FrontendExecutionStatus ->
  IO ()
setReadStatus currentEnvironment currentKey currentStatus =
  modifyMVar_
    (runtimeReadStatuses currentEnvironment)
    (pure . Map.insert currentKey currentStatus)

moduleOccurrencePath :: OccurrencePath -> OccurrencePath
moduleOccurrencePath (OccurrencePath currentSegments) =
  OccurrencePath
    ( case reverse currentSegments of
        [] -> []
        _ : remainingSegments -> reverse remainingSegments
    )

safely ::
  IO (Either FrontendRuntimeFailure value) ->
  IO (Either FrontendRuntimeFailure value)
safely currentAction = do
  currentResult <-
    try currentAction
  pure
    ( case currentResult of
        Left currentException ->
          Left (FrontendHandlerThrew (showException currentException))
        Right currentOutcome ->
          currentOutcome
    )
  where
    showException :: SomeException -> String
    showException =
      show
