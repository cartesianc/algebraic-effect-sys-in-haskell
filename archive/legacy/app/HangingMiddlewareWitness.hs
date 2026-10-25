{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DeriveGeneric #-}

module Main (main) where

import Control.Monad
  ( unless
  )
import Data.IORef
  ( IORef
  , modifyIORef'
  , newIORef
  , readIORef
  )
import Data.List
  ( intercalate
  , isInfixOf
  )
import GHC.Generics
  ( Generic
  )
import System.Exit
  ( exitFailure
  )
import Text.Read
  ( readMaybe
  )

import MyFramework

data Source = Source
  { sourceText :: String
  }
  deriving (Eq, Generic, Read, Show)

instance HasSchema Source

data Params = Params
  { paramsText :: String
  }
  deriving (Eq, Generic, Read, Show)

instance HasSchema Params

data Observation = Observation
  { observationOk :: Bool
  }
  deriving (Eq, Generic, Read, Show)

instance HasSchema Observation

data BusinessMode
  = BusinessSucceeds
  | BusinessFails
  | BusinessCancels
  deriving (Eq, Show)

data Check = Check
  { checkName :: String
  , checkPassed :: Bool
  , checkObserved :: String
  }

main :: IO ()
main =
  case hookedProgram of
    Left currentErrors -> do
      putStrLn (renderReport [Check "hanging-middleware-program-valid" False (show currentErrors)] False)
      exitFailure
    Right currentPrepared -> do
      successLog <- newIORef []
      successStats <- newIORef []
      successCount <- newIORef 0
      successRun <- runHooked BusinessSucceeds successLog successStats successCount currentPrepared
      failureLog <- newIORef []
      failureStats <- newIORef []
      failureCount <- newIORef 0
      failureRun <- runHooked BusinessFails failureLog failureStats failureCount currentPrepared
      cancelLog <- newIORef []
      cancelStats <- newIORef []
      cancelCount <- newIORef 0
      cancelRun <- runHooked BusinessCancels cancelLog cancelStats cancelCount currentPrepared
      missingCount <- newIORef 0
      let missingHandlers = handlersFor BusinessSucceeds missingCount currentPrepared
      missingRun <-
        case missingHandlers of
          Left _ -> pure (Left [RuntimeHandlerMissing (EffectKey "missing-registry")])
          Right currentHandlers -> runPreparedRuntime currentHandlers currentPrepared
      missingInvocations <- readIORef missingCount
      successOrder <- readIORef successLog
      failureOrder <- readIORef failureLog
      cancelOrder <- readIORef cancelLog
      successSnapshots <- readIORef successStats
      let currentHookPlan = preparedRuntimeHookPlan currentPrepared
          currentEvents = runEvents successRun
          currentChecks =
            [ Check
                "hanging-middleware-hook-plan-roundtrip"
                (readMaybe (show currentHookPlan) == Just currentHookPlan)
                (show (map hookPlanEntryRef (hookPlanEntries currentHookPlan)))
            , Check
                "hanging-middleware-no-boot-root"
                ( baseOccurrenceCount currentPrepared == 1
                    && detachedOccurrenceCount currentHookPlan == 1
                )
                (show (baseOccurrenceCount currentPrepared, detachedOccurrenceCount currentHookPlan))
            , Check
                "hanging-middleware-scope-and-declaration-order"
                ( successOrder
                    == [ "outer-before"
                       , "inner-first-before"
                       , "inner-second-before"
                       , "inner-second-after:Succeeded"
                       , "inner-first-after:Succeeded"
                       , "outer-after:Succeeded"
                       ]
                )
                (show successOrder)
            , Check
                "hanging-middleware-success-failure-cancelled-observed"
                ( runOutcome successRun == Just Succeeded
                    && isFailed (runOutcome failureRun)
                    && runOutcome cancelRun == Just (Cancelled "business cancelled")
                    && any (isInfixOf "Failed") failureOrder
                    && any (isInfixOf "Cancelled") cancelOrder
                )
                (show (runOutcome successRun, runOutcome failureRun, runOutcome cancelRun))
            , Check
                "hanging-middleware-scoped-snapshot-and-stats"
                ( not (null successSnapshots)
                    && maximum successSnapshots > minimum successSnapshots
                )
                (show successSnapshots)
            , Check
                "hanging-middleware-own-effect-occurrence"
                ( any isOwnApplication currentEvents
                    && ownApplicationHandlersRan currentEvents
                )
                (show (filter isOwnApplication currentEvents))
            , Check
                "hanging-middleware-runtime-events-provenance"
                ( length [() | RuntimeHookEntered {} <- currentEvents] == 3
                    && length [() | RuntimeHookExited {} <- currentEvents] == 3
                )
                (show (hookEventCount currentEvents))
            , Check
                "hanging-middleware-missing-registry-fails-before-handler-io"
                ( hasMissingMiddleware missingRun
                    && missingInvocations == 0
                )
                (show (missingRun, missingInvocations))
            , Check
                "hanging-middleware-prestart-continuation-provenance"
                ( all ((== HookPreStart) . hookPlanEntryPhase) (hookPlanEntries currentHookPlan)
                    && all (not . null . hookPlanEntryContinuationIds) (hookPlanEntries currentHookPlan)
                )
                (show (map hookPlanEntryContinuationIds (hookPlanEntries currentHookPlan)))
            ]
          succeeded = all checkPassed currentChecks
      putStrLn (renderReport currentChecks succeeded)
      unless succeeded exitFailure

dependencyCommand :: EffectRef 'U Params Observation
dependencyCommand = u "dependency" none

dependencyRead :: R Source
dependencyRead = r "dependency-source"

dependencyMap :: EffectRef 'MAP Source Params
dependencyMap = mapping "dependency-map"

dependencyApplication :: Application
dependencyApplication = apply dependencyCommand dependencyMap dependencyRead

businessCommand :: EffectRef 'C Params Observation
businessCommand = c "business" (after dependencyApplication)

businessRead :: R Source
businessRead = r "business-source"

businessMap :: EffectRef 'MAP Source Params
businessMap = mapping "business-map"

businessApplication :: Application
businessApplication = apply businessCommand businessMap businessRead

auditCommand :: EffectRef 'E Params Observation
auditCommand = e "audit" none

auditRead :: R Source
auditRead = r "audit-source"

auditMap :: EffectRef 'MAP Source Params
auditMap = mapping "audit-map"

auditApplication :: Application
auditApplication = apply auditCommand auditMap auditRead

rootScope, innerScope :: EffSysRef
rootScope = effSys (name "root") (name "root")
innerScope = effSys (name "root") (name "inner")

hookedProgram :: Either [ProgramError] PreparedRuntime
hookedProgram =
  programWithHanging
    (name "root")
    [ chain (name "root") [name "inner"]
    , chain (name "inner") [businessApplication]
    ]
    [effects (name "inner") [dependencyApplication, businessApplication]]
    ( astBlueprintHanging
        [ middleware (name "inner-first") innerScope Nothing
        , middleware (name "outer") rootScope (Just auditApplication)
        , middleware (name "inner-second") innerScope Nothing
        ]
    )

runHooked ::
  BusinessMode ->
  IORef [String] ->
  IORef [Int] ->
  IORef Int ->
  PreparedRuntime ->
  IO (Either [RuntimePreparationError] UnifiedRuntimeRun)
runHooked currentMode currentLog currentStats currentCount currentPrepared =
  case (handlersFor currentMode currentCount currentPrepared, middlewareFor currentLog currentStats) of
    (Right currentHandlers, Right currentMiddleware) ->
      runPreparedRuntimeWithMiddleware currentHandlers currentMiddleware currentPrepared
    _ -> pure (Left [RuntimeHandlerMissing (EffectKey "hook-registry-construction")])

handlersFor ::
  BusinessMode ->
  IORef Int ->
  PreparedRuntime ->
  Either [RuntimeHandlerRegistryError] RuntimeHandlerRegistry
handlersFor currentMode currentCount currentPrepared =
  runtimeHandlerRegistry
    [ registrationFor currentEffect
    | currentEffect <- effectRegistryEffects (effectRegistryOf currentPrepared)
    ]
  where
    registrationFor currentEffect =
      case effectIrSpec currentEffect of
        ReadEffect currentSpec ->
          runtimeHandler
            (effectIrRef currentEffect)
            Nothing
            (Just (readSpecValueSchema currentSpec))
            (counted (HandlerSucceeded (Just (RuntimeValue (readSpecValueSchema currentSpec) (show (Source "source"))))))
        MapEffect currentSpec ->
          runtimeHandler
            (effectIrRef currentEffect)
            (Just (mapSpecInputSchema currentSpec))
            (Just (paramsSchemaFor currentEffect currentPrepared))
            (counted (HandlerSucceeded (Just (RuntimeValue (paramsSchemaFor currentEffect currentPrepared) (show (Params "params"))))))
        CommandEffect currentSpec ->
          runtimeHandler
            (effectIrRef currentEffect)
            (Just (commandSpecArgumentSchema currentSpec))
            (Just (commandSpecObservationSchema currentSpec))
            (commandResult currentEffect currentSpec)
    counted currentResult _ = do
      modifyIORef' currentCount (+ 1)
      pure currentResult
    commandResult currentEffect currentSpec currentInvocation = do
      modifyIORef' currentCount (+ 1)
      let currentKey = effectKeyText (someEffectRefKey (effectIrRef currentEffect))
      if runtimeInvocationPhase currentInvocation == RuntimeInputPhase
        then pure (HandlerSucceeded Nothing)
        else
          if "business" `isInfixOf` currentKey
            then
              pure
                ( case currentMode of
                    BusinessSucceeds -> observationResult currentSpec
                    BusinessFails -> HandlerFailed "business failed"
                    BusinessCancels -> HandlerCancelled "business cancelled"
                )
            else pure (observationResult currentSpec)
    observationResult currentSpec =
      HandlerSucceeded
        (Just (RuntimeValue (commandSpecObservationSchema currentSpec) (show (Observation True))))

paramsSchemaFor :: EffectIR -> PreparedRuntime -> ValueSchemaId
paramsSchemaFor currentEffect currentPrepared =
  case
      [ commandSpecArgumentSchema currentSpec
      | currentOccurrence <-
          compiledOccurrences
            (graphProgramOf (preparedRuntimeProgram currentPrepared))
            ++ compiledOccurrences
              (hookPlanDetachedGraphs (preparedRuntimeHookPlan currentPrepared))
      , let currentApplication = applicationOccurrenceApplication currentOccurrence
      , someEffectRefKey (effectApplicationMap currentApplication)
          == someEffectRefKey (effectIrRef currentEffect)
      , currentCommand <- effectRegistryEffects (effectRegistryOf currentPrepared)
      , someEffectRefKey (effectIrRef currentCommand)
          == someEffectRefKey (effectApplicationCommand currentApplication)
      , CommandEffect currentSpec <- [effectIrSpec currentCommand]
      ] of
    currentSchema : _ -> currentSchema
    [] -> error "MAP application schema missing"

middlewareFor ::
  IORef [String] ->
  IORef [Int] ->
  Either [RuntimeMiddlewareRegistryError] RuntimeMiddlewareRegistry
middlewareFor currentLog currentStats =
  runtimeMiddlewareRegistry
    [ runtimeMiddleware (MiddlewareRef "outer") outerMiddleware
    , runtimeMiddleware (MiddlewareRef "inner-first") (simpleMiddleware "inner-first")
    , runtimeMiddleware (MiddlewareRef "inner-second") (simpleMiddleware "inner-second")
    ]
  where
    outerMiddleware currentContext currentChild = do
      appendLog "outer-before"
      recordSnapshot currentContext
      ownOutcome <-
        case middlewareContextOwnApplication currentContext of
          Nothing -> pure Succeeded
          Just currentOwn -> runRuntimeActionV52 currentOwn
      currentOutcome <-
        case ownOutcome of
          Succeeded -> runRuntimeActionV52 currentChild
          _ -> pure ownOutcome
      recordSnapshot currentContext
      appendLog ("outer-after:" ++ outcomeTag currentOutcome)
      pure currentOutcome
    simpleMiddleware currentName currentContext currentChild = do
      appendLog (currentName ++ "-before")
      recordSnapshot currentContext
      currentOutcome <- runRuntimeActionV52 currentChild
      recordSnapshot currentContext
      appendLog (currentName ++ "-after:" ++ outcomeTag currentOutcome)
      pure currentOutcome
    appendLog currentMessage =
      modifyIORef' currentLog (++ [currentMessage])
    recordSnapshot currentContext = do
      currentSnapshot <- middlewareContextSnapshot currentContext
      modifyIORef'
        currentStats
        (++ [length (runtimeSnapshotStatuses currentSnapshot)])

outcomeTag :: ContinuationOutcome -> String
outcomeTag currentOutcome =
  case currentOutcome of
    Succeeded -> "Succeeded"
    Failed _ -> "Failed"
    Cancelled _ -> "Cancelled"
    Suspended _ -> "Suspended"

runOutcome :: Either [RuntimePreparationError] UnifiedRuntimeRun -> Maybe ContinuationOutcome
runOutcome = either (const Nothing) (Just . unifiedRuntimeOutcome)

runEvents :: Either [RuntimePreparationError] UnifiedRuntimeRun -> [RuntimeEvent]
runEvents = either (const []) (runtimeSnapshotEvents . unifiedRuntimeSnapshot)

isFailed :: Maybe ContinuationOutcome -> Bool
isFailed (Just Failed {}) = True
isFailed _ = False

isOwnApplication :: RuntimeEvent -> Bool
isOwnApplication RuntimeHookOwnApplicationStarted {} = True
isOwnApplication _ = False

ownApplicationHandlersRan :: [RuntimeEvent] -> Bool
ownApplicationHandlersRan currentEvents =
  length
    [ ()
    | RuntimeHandlerStarted currentInstance _ <- currentEvents
    , "audit" `isInfixOf`
        effectKeyText (someEffectRefKey (executionInstanceEffect currentInstance))
    ]
    == 3

hookEventCount :: [RuntimeEvent] -> (Int, Int, Int)
hookEventCount currentEvents =
  ( length [() | RuntimeHookEntered {} <- currentEvents]
  , length [() | RuntimeHookExited {} <- currentEvents]
  , length [() | RuntimeHookOwnApplicationStarted {} <- currentEvents]
  )

baseOccurrenceCount :: PreparedRuntime -> Int
baseOccurrenceCount =
  length
    . compiledOccurrences
    . graphProgramOf
    . preparedRuntimeProgram

detachedOccurrenceCount :: HookPlan -> Int
detachedOccurrenceCount = length . compiledOccurrences . hookPlanDetachedGraphs

hasMissingMiddleware :: Either [RuntimePreparationError] UnifiedRuntimeRun -> Bool
hasMissingMiddleware currentRun =
  case currentRun of
    Left currentErrors -> any isMissing currentErrors
    Right _ -> False
  where
    isMissing RuntimeMiddlewareMissing {} = True
    isMissing _ = False

renderReport :: [Check] -> Bool -> String
renderReport currentChecks succeeded =
  "{"
    ++ jsonField "schema" (jsonString "hanging-middleware-witness.v1")
    ++ ","
    ++ jsonField
      "claims"
      ( jsonArray
          [ "{"
              ++ jsonField "name" (jsonString (checkName currentCheck))
              ++ ","
              ++ jsonField "passed" (jsonBool (checkPassed currentCheck))
              ++ ","
              ++ jsonField "observed" (jsonString (checkObserved currentCheck))
              ++ "}"
          | currentCheck <- currentChecks
          ]
      )
    ++ ","
    ++ jsonField "claimManifest" (jsonArray (map (jsonString . checkName) currentChecks))
    ++ ","
    ++ jsonField "passed" (jsonBool succeeded)
    ++ "}"

jsonField :: String -> String -> String
jsonField currentKey currentValue = jsonString currentKey ++ ":" ++ currentValue

jsonArray :: [String] -> String
jsonArray currentValues = "[" ++ intercalate "," currentValues ++ "]"

jsonBool :: Bool -> String
jsonBool True = "true"
jsonBool False = "false"

jsonString :: String -> String
jsonString currentText = "\"" ++ concatMap escapeJson currentText ++ "\""

escapeJson :: Char -> String
escapeJson currentCharacter =
  case currentCharacter of
    '"' -> "\\\""
    '\\' -> "\\\\"
    '\n' -> "\\n"
    '\r' -> "\\r"
    '\t' -> "\\t"
    _ -> [currentCharacter]
