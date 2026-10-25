{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE ScopedTypeVariables #-}

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
  , nub
  , sort
  )
import Data.Proxy
  ( Proxy (..)
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
  { sourceBody :: String
  }
  deriving (Eq, Generic, Read, Show)

instance HasSchema Source

data Params = Params
  { paramsBody :: String
  }
  deriving (Eq, Generic, Read, Show)

instance HasSchema Params

data Observation = Observation
  { observationAccepted :: Bool
  }
  deriving (Eq, Generic, Read, Show)

instance HasSchema Observation

data InputMode
  = InputSucceeds
  | InputFails
  | InputCancels
  | InputSuspends
  deriving (Eq, Show)

data Check = Check
  { checkName :: String
  , checkPassed :: Bool
  , checkObserved :: String
  }

main :: IO ()
main =
  case (runtimeProgram, independentProgram, typedAdapterProgram) of
    (Left currentErrors, _, _) -> do
      putStrLn (renderReport [Check "input-cps-program-valid" False (show currentErrors)] False)
      exitFailure
    (_, Left currentErrors, _) -> do
      putStrLn (renderReport [Check "input-cps-independent-program-valid" False (show currentErrors)] False)
      exitFailure
    (_, _, Left currentErrors) -> do
      putStrLn (renderReport [Check "input-cps-typed-adapter-program-valid" False (show currentErrors)] False)
      exitFailure
    (Right currentPrepared, Right currentIndependent, Right currentTyped) -> do
      successCounter <- newIORef 0
      successRun <- runMode successCounter InputSucceeds currentPrepared
      failureCounter <- newIORef 0
      failureRun <- runMode failureCounter InputFails currentPrepared
      cancelCounter <- newIORef 0
      cancelRun <- runMode cancelCounter InputCancels currentPrepared
      suspendCounter <- newIORef 0
      suspendRun <- runMode suspendCounter InputSuspends currentPrepared
      independentCounter <- newIORef 0
      independentRun <- runMode independentCounter InputSucceeds currentIndependent
      typedCounter <- newIORef 0
      typedRun <- runTypedAdapters typedCounter currentTyped
      typedInvocations <- readIORef typedCounter
      preparationCounter <- newIORef 0
      preparationRun <- runMissingHandler preparationCounter currentPrepared
      preparationInvocations <- readIORef preparationCounter
      let currentPlan = preparedRuntimeContinuationPlan currentPrepared
          currentChecks =
            [ Check
                "input-cps-plan-defunctionalized-roundtrip"
                (readMaybe (show currentPlan) == Just currentPlan)
                (continuationPlanDigest currentPlan)
            , Check
                "input-cps-continuation-carries-status-only"
                (not ("RuntimeValue" `isInfixOf` show currentPlan))
                "ContinuationNode/Segment contain ids, scope, refs, and lifecycle edges"
            , Check
                "input-cps-success"
                (runOutcome successRun == Just Succeeded)
                (show (runOutcome successRun))
            , Check
                "input-cps-failure-short-circuit"
                ( isFailed (runOutcome failureRun)
                    && not (consumeCommandStarted failureRun)
                )
                (show (runOutcome failureRun, consumeCommandStarted failureRun))
            , Check
                "input-cps-cancelled"
                (runOutcome cancelRun == Just (Cancelled "input cancelled"))
                (show (runOutcome cancelRun))
            , Check
                "input-cps-suspended"
                (runOutcome suspendRun == Just (Suspended "input suspended"))
                (show (runOutcome suspendRun))
            , Check
                "input-cps-runtime-order"
                (runtimeOrderValid successRun)
                (show (runtimePhases successRun))
            , Check
                "input-cps-diagnosis-trace-matches-input-graph"
                (diagnosisMatchesGraph currentPrepared successRun)
                (show (diagnosisTrace successRun))
            , Check
                "input-cps-single-flight-same-occurrence"
                (singleFlightObserved successRun)
                "the second demand for prime in the consume occurrence reused the first flight"
            , Check
                "input-cps-occurrences-remain-independent"
                (independentOccurrences independentRun)
                "two AST occurrences of prime produced separate execution instances"
            , Check
                "input-cps-business-values-use-value-phases"
                (businessValuesStayOutOfInput successRun)
                (show (runtimePhases successRun))
            , Check
                "input-cps-typed-handler-adapter"
                (runOutcome typedRun == Just Succeeded && typedInvocations == 3)
                (show (runOutcome typedRun, typedInvocations))
            , Check
                "input-cps-preparation-errors-before-handler-io"
                ( either (not . null) (const False) preparationRun
                    && preparationInvocations == 0
                )
                (show (either length (const 0) preparationRun, preparationInvocations))
            ]
          succeeded = all checkPassed currentChecks
      putStrLn (renderReport currentChecks succeeded)
      unless succeeded exitFailure

primeCommand :: EffectRef 'C Params Observation
primeCommand = c "prime" none

primeRead :: R Source
primeRead = r "prime-source"

primeMap :: EffectRef 'MAP Source Params
primeMap = mapping "prime-map"

primeApplication :: Application
primeApplication = apply primeCommand primeMap primeRead

consumeCommand :: EffectRef 'C Params Observation
consumeCommand = c "consume" (after primeApplication)

consumeRead :: R Source
consumeRead = r "consume-source"

consumeMap :: EffectRef 'MAP Source Params
consumeMap =
  withEffectInput
    (after primeApplication)
    (mapping "consume-map")

consumeApplication :: Application
consumeApplication = apply consumeCommand consumeMap consumeRead

runtimeProgram :: Either [ProgramError] PreparedRuntime
runtimeProgram =
  program
    (name "flow")
    [chain (name "flow") [consumeApplication]]
    [effects (name "flow") [primeApplication, consumeApplication]]

independentProgram :: Either [ProgramError] PreparedRuntime
independentProgram =
  program
    (name "independent")
    [parallel (name "independent") [primeApplication, primeApplication]]
    [effects (name "independent") [primeApplication]]

typedAdapterProgram :: Either [ProgramError] PreparedRuntime
typedAdapterProgram =
  program
    (name "typed")
    [chain (name "typed") [primeApplication]]
    [effects (name "typed") [primeApplication]]

schemaId :: forall value. HasSchema value => Proxy value -> ValueSchemaId
schemaId _ =
  schemaDescriptorId
    ( descriptorFor
        (SchemaFromType "input-cps-witness")
        (valueSchemaDefinition (Proxy :: Proxy value))
    )

sourceSchema, paramsSchema, observationSchema :: ValueSchemaId
sourceSchema = schemaId (Proxy :: Proxy Source)
paramsSchema = schemaId (Proxy :: Proxy Params)
observationSchema = schemaId (Proxy :: Proxy Observation)

unitCodec :: Codec ()
unitCodec =
  Codec
    { codecName = "unit.v1"
    , codecVersion = ValueSchemaVersion 1
    , codecSchema = valueSchemaDefinition (Proxy :: Proxy ())
    , codecEncode = const (Right "")
    , codecDecode = const (Right ())
    , codecEquivalent = (==)
    , codecSerializable = True
    }

sourceCodec :: Codec Source
sourceCodec =
  Codec
    { codecName = "source.v1"
    , codecVersion = ValueSchemaVersion 1
    , codecSchema = valueSchemaDefinition (Proxy :: Proxy Source)
    , codecEncode = Right . show
    , codecDecode = maybe (Left "Source decode failed") Right . readMaybe
    , codecEquivalent = (==)
    , codecSerializable = True
    }

paramsCodec :: Codec Params
paramsCodec =
  Codec
    { codecName = "params.v1"
    , codecVersion = ValueSchemaVersion 1
    , codecSchema = valueSchemaDefinition (Proxy :: Proxy Params)
    , codecEncode = Right . show
    , codecDecode = maybe (Left "Params decode failed") Right . readMaybe
    , codecEquivalent = (==)
    , codecSerializable = True
    }

observationCodec :: Codec Observation
observationCodec =
  Codec
    { codecName = "observation.v1"
    , codecVersion = ValueSchemaVersion 1
    , codecSchema = valueSchemaDefinition (Proxy :: Proxy Observation)
    , codecEncode = Right . show
    , codecDecode = maybe (Left "Observation decode failed") Right . readMaybe
    , codecEquivalent = (==)
    , codecSerializable = True
    }

runTypedAdapters ::
  IORef Int ->
  PreparedRuntime ->
  IO (Either [RuntimePreparationError] UnifiedRuntimeRun)
runTypedAdapters currentCounter currentPrepared =
  case
      runtimeHandlerRegistry
        ( map (typedRegistration currentCounter)
            (effectRegistryEffects (effectRegistryOf currentPrepared))
        ) of
    Left _ -> pure (Left [RuntimeHandlerMissing (EffectKey "typed-registry-construction")])
    Right currentHandlers -> runPreparedRuntime currentHandlers currentPrepared

typedRegistration :: IORef Int -> EffectIR -> RuntimeHandlerRegistration
typedRegistration currentCounter currentEffect =
  case effectIrSpec currentEffect of
    ReadEffect _ ->
      runtimeHandlerFromAdapter
        ( handlerAdapter
            (r (effectKeyText currentKey) :: R Source)
            unitCodec
            sourceCodec
            (\() -> countTyped (Right (Source "typed-source")))
        )
    MapEffect _ ->
      runtimeHandlerFromAdapter
        ( handlerAdapter
            (mapping (effectKeyText currentKey) :: EffectRef 'MAP Source Params)
            sourceCodec
            paramsCodec
            (\currentSource -> countTyped (Right (Params (sourceBody currentSource))))
        )
    CommandEffect _ ->
      runtimeHandlerFromAdapter
        ( handlerAdapter
            (c (effectKeyText currentKey) none :: EffectRef 'C Params Observation)
            paramsCodec
            observationCodec
            (\_ -> countTyped (Right (Observation True)))
        )
  where
    currentKey = someEffectRefKey (effectIrRef currentEffect)
    countTyped currentResult = do
      modifyIORef' currentCounter (+ 1)
      pure currentResult

runMode ::
  IORef Int ->
  InputMode ->
  PreparedRuntime ->
  IO (Either [RuntimePreparationError] UnifiedRuntimeRun)
runMode currentCounter currentMode currentPrepared =
  case handlersFor currentCounter currentMode Nothing currentPrepared of
    Left _ -> pure (Left [RuntimeHandlerMissing (EffectKey "registry-construction")])
    Right currentHandlers -> runPreparedRuntime currentHandlers currentPrepared

runMissingHandler ::
  IORef Int ->
  PreparedRuntime ->
  IO (Either [RuntimePreparationError] UnifiedRuntimeRun)
runMissingHandler currentCounter currentPrepared =
  case handlersFor currentCounter InputSucceeds (Just "consume-map") currentPrepared of
    Left _ -> pure (Left [RuntimeHandlerMissing (EffectKey "registry-construction")])
    Right currentHandlers -> runPreparedRuntime currentHandlers currentPrepared

handlersFor ::
  IORef Int ->
  InputMode ->
  Maybe String ->
  PreparedRuntime ->
  Either [RuntimeHandlerRegistryError] RuntimeHandlerRegistry
handlersFor currentCounter currentMode skippedSuffix currentPrepared =
  runtimeHandlerRegistry
    [ registrationFor currentCounter currentMode currentEffect
    | currentEffect <- effectRegistryEffects (effectRegistryOf currentPrepared)
    , maybe True (not . (`isInfixOf` effectKeyText (someEffectRefKey (effectIrRef currentEffect)))) skippedSuffix
    ]

registrationFor ::
  IORef Int ->
  InputMode ->
  EffectIR ->
  RuntimeHandlerRegistration
registrationFor currentCounter currentMode currentEffect =
  case effectIrSpec currentEffect of
    ReadEffect currentSpec ->
      runtimeHandler
        currentRef
        Nothing
        (Just (readSpecValueSchema currentSpec))
        (counted (HandlerSucceeded (Just (RuntimeValue sourceSchema "source"))))
    MapEffect currentSpec ->
      runtimeHandler
        currentRef
        (Just (mapSpecInputSchema currentSpec))
        (Just paramsSchema)
        (counted (HandlerSucceeded (Just (RuntimeValue paramsSchema "params"))))
    CommandEffect currentSpec ->
      runtimeHandler
        currentRef
        (Just (commandSpecArgumentSchema currentSpec))
        (Just (commandSpecObservationSchema currentSpec))
        commandHandler
  where
    currentRef = effectIrRef currentEffect
    counted currentResult _ = do
      modifyIORef' currentCounter (+ 1)
      pure currentResult
    commandHandler currentInvocation = do
      modifyIORef' currentCounter (+ 1)
      if runtimeInvocationPhase currentInvocation == RuntimeInputPhase
        && "prime" `isInfixOf` effectKeyText (someEffectRefKey currentRef)
        then
          pure
            ( case currentMode of
                InputSucceeds -> HandlerSucceeded Nothing
                InputFails -> HandlerFailed "input failed"
                InputCancels -> HandlerCancelled "input cancelled"
                InputSuspends -> HandlerSuspended "input suspended"
            )
        else
          pure
            (HandlerSucceeded (Just (RuntimeValue observationSchema "accepted")))

runOutcome ::
  Either [RuntimePreparationError] UnifiedRuntimeRun ->
  Maybe ContinuationOutcome
runOutcome = either (const Nothing) (Just . unifiedRuntimeOutcome)

runEvents ::
  Either [RuntimePreparationError] UnifiedRuntimeRun ->
  [RuntimeEvent]
runEvents =
  either
    (const [])
    (runtimeSnapshotEvents . unifiedRuntimeSnapshot)

isFailed :: Maybe ContinuationOutcome -> Bool
isFailed (Just Failed {}) = True
isFailed _ = False

consumeCommandStarted ::
  Either [RuntimePreparationError] UnifiedRuntimeRun ->
  Bool
consumeCommandStarted currentRun =
  any isConsumeCommand (runEvents currentRun)
  where
    isConsumeCommand (RuntimeHandlerStarted currentInstance RuntimeCommandPhase) =
      "consume" `isInfixOf`
        effectKeyText
          (someEffectRefKey (executionInstanceEffect currentInstance))
    isConsumeCommand _ = False

runtimePhases ::
  Either [RuntimePreparationError] UnifiedRuntimeRun ->
  [(String, RuntimeHandlerPhase)]
runtimePhases currentRun =
  [ ( effectKeyText
        (someEffectRefKey (executionInstanceEffect currentInstance))
    , currentPhase
    )
  | RuntimeHandlerStarted currentInstance currentPhase <- runEvents currentRun
  ]

runtimeOrderValid ::
  Either [RuntimePreparationError] UnifiedRuntimeRun ->
  Bool
runtimeOrderValid currentRun =
  case
      [ currentPhase
      | (currentKey, currentPhase) <- runtimePhases currentRun
      , "consume" `isInfixOf` currentKey || "prime" `isInfixOf` currentKey
      ] of
    currentPhases ->
      ordered RuntimeInputPhase RuntimeReadPhase currentPhases
        && ordered RuntimeReadPhase RuntimeMapPhase currentPhases
        && ordered RuntimeMapPhase RuntimeCommandPhase currentPhases
  where
    ordered currentBefore currentAfter currentValues =
      case
          ( firstIndex currentBefore currentValues
          , lastIndex currentAfter currentValues
          ) of
        (Just beforeIndex, Just afterIndex) -> beforeIndex < afterIndex
        _ -> False

firstIndex :: Eq value => value -> [value] -> Maybe Int
firstIndex currentTarget currentValues =
  case [currentIndex | (currentIndex, currentValue) <- zip [0 ..] currentValues, currentValue == currentTarget] of
    currentIndex : _ -> Just currentIndex
    [] -> Nothing

lastIndex :: Eq value => value -> [value] -> Maybe Int
lastIndex currentTarget currentValues =
  case [currentIndex | (currentIndex, currentValue) <- zip [0 ..] currentValues, currentValue == currentTarget] of
    [] -> Nothing
    currentIndexes -> Just (last currentIndexes)

diagnosisTrace ::
  Either [RuntimePreparationError] UnifiedRuntimeRun ->
  [ContinuationId]
diagnosisTrace =
  either
    (const [])
    ( runtimeDiagnosisInputTrace
        . runtimeSnapshotDiagnosis
        . unifiedRuntimeSnapshot
    )

diagnosisMatchesGraph ::
  PreparedRuntime ->
  Either [RuntimePreparationError] UnifiedRuntimeRun ->
  Bool
diagnosisMatchesGraph currentPrepared currentRun =
  sort (diagnosisTrace currentRun) == sort expectedContinuations
  where
    expectedContinuations =
      map inputEdgeContinuation
        ( inputGraphEdges
            (compiledInputGraph (graphProgramOf (preparedRuntimeProgram currentPrepared)))
        )

singleFlightObserved ::
  Either [RuntimePreparationError] UnifiedRuntimeRun ->
  Bool
singleFlightObserved currentRun =
  any isReuse (runEvents currentRun)
  where
    isReuse RuntimeSingleFlightReused {} = True
    isReuse _ = False

independentOccurrences ::
  Either [RuntimePreparationError] UnifiedRuntimeRun ->
  Bool
independentOccurrences currentRun =
  length
    ( nub
        [ executionInstanceAstPath currentInstance
        | RuntimeHandlerStarted currentInstance _ <- runEvents currentRun
        , "prime" `isInfixOf`
            effectKeyText
              (someEffectRefKey (executionInstanceEffect currentInstance))
        ]
    )
    >= 2

businessValuesStayOutOfInput ::
  Either [RuntimePreparationError] UnifiedRuntimeRun ->
  Bool
businessValuesStayOutOfInput currentRun =
  all inputHasNoValue
    [ (currentPhase, currentResult)
    | RuntimeHandlerFinished _ currentPhase currentResult <- runEvents currentRun
    ]
  where
    inputHasNoValue (RuntimeInputPhase, HandlerSucceeded currentValue) = currentValue == Nothing
    inputHasNoValue (RuntimeInputPhase, _) = True
    inputHasNoValue _ = True

renderReport :: [Check] -> Bool -> String
renderReport currentChecks succeeded =
  "{"
    ++ jsonField "schema" (jsonString "input-cps-witness.v2")
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
