{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE ScopedTypeVariables #-}

module Main (main) where

import Control.Monad (unless)
import Data.IORef
  ( IORef
  , modifyIORef'
  , newIORef
  , readIORef
  )
import Data.List (intercalate, isInfixOf)
import Data.Proxy (Proxy (..))
import GHC.Generics (Generic)
import System.Exit (exitFailure)
import Text.Read (readMaybe)

import MyFramework

data Source = Source {sourceText :: String}
  deriving (Eq, Generic, Read, Show)

instance HasSchema Source

data Params = Params {paramsText :: String}
  deriving (Eq, Generic, Read, Show)

instance HasSchema Params

data Observation = Observation {observationOk :: Bool}
  deriving (Eq, Generic, Read, Show)

instance HasSchema Observation

data RunMode
  = Stable
  | Feedback
  | AlwaysChanging
  deriving (Eq, Show)

data Check = Check
  { checkName :: String
  , checkPassed :: Bool
  , checkObserved :: String
  }

main :: IO ()
main =
  case (stableProgram, feedbackProgram, limitProgram, nestedProgram) of
    (Right currentStable, Right currentFeedback, Right currentLimit, Right currentNested) -> do
      stableRun <- runMode Stable False False currentStable
      feedbackRun <- runMode Feedback False False currentFeedback
      limitRun <- runMode AlwaysChanging False False currentLimit
      nestedRun <- runMode Feedback False False currentNested
      (cleanupRun, cleanupOrder) <- runWithCleanup False currentStable
      (cleanupFailureRun, _) <- runWithCleanup True currentStable
      opaqueCounter <- newIORef []
      opaqueRun <- runPrepared opaqueCounter Stable False True currentStable
      opaqueInvocations <- readIORef opaqueCounter
      let feedbackEvents = eventsOf feedbackRun
          nestedEvents = eventsOf nestedRun
          feedbackIterations = countEvents isIteration feedbackEvents
          feedbackRevisions = countEvents isRevision feedbackEvents
          outsideStarts = countEvents isOutsideStart feedbackEvents
          innerRevisionBeforeOuter = revisionOrderValid nestedEvents
          policyRegistry = preparedRuntimeLoopPolicyRegistry currentFeedback
          cycleRejected = either (any isGraphCycle) (const False) inputCycleProgram
          checks =
            [ Check
                "loop-policy-versioned-roundtrip"
                (readMaybe (show policyRegistry) == Just policyRegistry)
                (show policyRegistry)
            , Check
                "loop-first-iteration-and-stable-settle"
                ( outcomeOf stableRun == Just Succeeded
                    && countEvents isIteration (eventsOf stableRun) == 1
                    && countEvents isSettled (eventsOf stableRun) == 1
                )
                (show (outcomeOf stableRun, eventsOf stableRun))
            , Check
                "loop-value-change-replays-once"
                ( outcomeOf feedbackRun == Just Succeeded
                    && feedbackIterations == 2
                    && feedbackRevisions == 1
                )
                (show (feedbackIterations, feedbackRevisions))
            , Check
                "loop-batches-updates-into-one-revision"
                (diagnosisRevisionCount feedbackRun == 1)
                (show (diagnosisRevisions feedbackRun))
            , Check
                "loop-outside-application-runs-once"
                (outsideStarts == 1)
                (show outsideStarts)
            , Check
                "loop-iteration-limit-is-diagnosed"
                ( isFailed (outcomeOf limitRun)
                    && countEvents isLimit (eventsOf limitRun) == 1
                    && not (null (diagnosisFailures limitRun))
                )
                (show (outcomeOf limitRun, diagnosisFailures limitRun))
            , Check
                "loop-cleanup-is-lifo"
                ( outcomeOf cleanupRun == Just Succeeded
                    && map terminalEffect (take 3 cleanupOrder)
                      == ["command", "map", "read"]
                )
                (show cleanupOrder)
            , Check
                "loop-cleanup-failure-fails-scope"
                (isFailed (outcomeOf cleanupFailureRun) && not (null (diagnosisFailures cleanupFailureRun)))
                (show (outcomeOf cleanupFailureRun, diagnosisFailures cleanupFailureRun))
            , Check
                "loop-nested-settles-before-parent-revision"
                ( outcomeOf nestedRun == Just Succeeded
                    && innerRevisionBeforeOuter
                    && countEvents isRevision nestedEvents == 2
                )
                (show (filter isRevision nestedEvents))
            , Check
                "loop-missing-equivalence-fails-before-handler-io"
                ( either (any isEquivalenceMissing) (const False) opaqueRun
                    && null opaqueInvocations
                )
                (show (opaqueRun, opaqueInvocations))
            , Check
                "loop-does-not-authorize-input-cycle"
                cycleRejected
                (show inputCycleProgram)
            ]
          succeeded = all checkPassed checks
      putStrLn (renderReport checks succeeded)
      unless succeeded exitFailure
    currentPrograms -> do
      putStrLn ("loop-feedback-witness: program construction failed: " ++ show currentPrograms)
      exitFailure

stableApplication, feedbackApplication, outsideApplication, innerApplication :: Application
stableApplication = application "command" "map" "read" none
feedbackApplication = application "command" "map" "read" none
outsideApplication = application "outside-command" "outside-map" "outside-read" none
innerApplication = application "command" "map" "read" none

application :: String -> String -> String -> Maybe SomeEffectRef -> Application
application currentCommand currentMap currentRead currentInput =
  apply
    (c currentCommand currentInput :: EffectRef 'C Params Observation)
    (mapping currentMap :: EffectRef 'MAP Source Params)
    (r currentRead :: R Source)

stableProgram, feedbackProgram, limitProgram, nestedProgram :: Either [ProgramError] PreparedRuntime
stableProgram =
  program
    (name "stable-loop")
    [loop (name "stable-loop") stableApplication]
    [effects (name "stable-loop") [stableApplication]]

feedbackProgram =
  program
    (name "root")
    [ chain (name "root") [name "outside-command", name "feedback-loop"]
    , loop (name "feedback-loop") feedbackApplication
    ]
    [ effects (name "root") [outsideApplication]
    , effects (name "feedback-loop") [feedbackApplication]
    ]

limitProgram =
  program
    (name "limit-loop")
    [ loopWith
        (name "limit-loop")
        (VersionedLoopPolicy (LoopPolicyRef "until-quiescent/test") (LoopPolicyVersion 1) (UntilQuiescent 2))
        stableApplication
    ]
    [effects (name "limit-loop") [stableApplication]]

nestedProgram =
  program
    (name "outer-loop")
    [ loop (name "outer-loop") (name "inner-loop")
    , loop (name "inner-loop") innerApplication
    ]
    [effects (name "inner-loop") [innerApplication]]

inputCycleProgram :: Either [ProgramError] PreparedRuntime
inputCycleProgram =
  program
    (name "cycle")
    [chain (name "cycle") [applicationA, applicationB]]
    [effects (name "cycle") [applicationA, applicationB]]
  where
    commandA = c "a" (after commandB) :: EffectRef 'C Params Observation
    commandB = c "b" (after commandA) :: EffectRef 'C Params Observation
    applicationA =
      apply commandA (mapping "a-map" :: EffectRef 'MAP Source Params) (r "a-read" :: R Source)
    applicationB =
      apply commandB (mapping "b-map" :: EffectRef 'MAP Source Params) (r "b-read" :: R Source)

runMode :: RunMode -> Bool -> Bool -> PreparedRuntime -> IO (Either [RuntimePreparationError] UnifiedRuntimeRun)
runMode currentMode currentCleanupFailure currentOpaque currentPrepared = do
  currentCounts <- newIORef []
  runPrepared currentCounts currentMode currentCleanupFailure currentOpaque currentPrepared

runWithCleanup :: Bool -> PreparedRuntime -> IO (Either [RuntimePreparationError] UnifiedRuntimeRun, [String])
runWithCleanup currentFailure currentPrepared = do
  currentCounts <- newIORef []
  currentCleanupOrder <- newIORef []
  currentRun <- runPreparedWithCleanup currentCounts currentCleanupOrder currentFailure currentPrepared
  currentOrder <- readIORef currentCleanupOrder
  pure (currentRun, currentOrder)

runPrepared ::
  IORef [(String, Int)] ->
  RunMode ->
  Bool ->
  Bool ->
  PreparedRuntime ->
  IO (Either [RuntimePreparationError] UnifiedRuntimeRun)
runPrepared currentCounts currentMode currentCleanupFailure currentOpaque currentPrepared = do
  currentCleanupOrder <- newIORef []
  runPreparedUsing currentCounts currentCleanupOrder currentMode currentCleanupFailure currentOpaque currentPrepared

runPreparedWithCleanup ::
  IORef [(String, Int)] ->
  IORef [String] ->
  Bool ->
  PreparedRuntime ->
  IO (Either [RuntimePreparationError] UnifiedRuntimeRun)
runPreparedWithCleanup currentCounts currentCleanupOrder currentFailure =
  runPreparedUsing currentCounts currentCleanupOrder Stable currentFailure False

runPreparedUsing ::
  IORef [(String, Int)] ->
  IORef [String] ->
  RunMode ->
  Bool ->
  Bool ->
  PreparedRuntime ->
  IO (Either [RuntimePreparationError] UnifiedRuntimeRun)
runPreparedUsing currentCounts currentCleanupOrder currentMode currentCleanupFailure currentOpaque currentPrepared =
  case
      runtimeHandlerRegistry
        [ registrationFor currentCounts currentCleanupOrder currentMode currentCleanupFailure currentOpaque currentEffect
        | currentEffect <- effectRegistryEffects (effectRegistryOf currentPrepared)
        ] of
    Left _ -> pure (Left [RuntimeHandlerMissing (EffectKey "loop-registry-construction")])
    Right currentHandlers -> runPreparedRuntime currentHandlers currentPrepared

registrationFor ::
  IORef [(String, Int)] ->
  IORef [String] ->
  RunMode ->
  Bool ->
  Bool ->
  EffectIR ->
  RuntimeHandlerRegistration
registrationFor currentCounts currentCleanupOrder currentMode currentCleanupFailure currentOpaque currentEffect =
  runtimeHandlerWithLifecycle
    currentRef
    currentInput
    currentOutput
    (if currentOpaque && isRead then Nothing else Just (==))
    (Just cleanup)
    invoke
  where
    currentRef = effectIrRef currentEffect
    currentKey = effectKeyText (someEffectRefKey currentRef)
    isRead = someEffectRefKind currentRef == R
    (currentInput, currentOutput) =
      case effectIrSpec currentEffect of
        ReadEffect currentSpec -> (Nothing, Just (readSpecValueSchema currentSpec))
        MapEffect currentSpec -> (Just (mapSpecInputSchema currentSpec), Just paramsSchema)
        CommandEffect currentSpec ->
          (Just (commandSpecArgumentSchema currentSpec), Just (commandSpecObservationSchema currentSpec))
    invoke currentInvocation
      | runtimeInvocationPhase currentInvocation == RuntimeInputPhase = do
          _ <- increment currentCounts currentKey
          pure (HandlerSucceeded Nothing)
      | otherwise = do
          currentCount <- increment currentCounts currentKey
          pure
            ( case effectIrSpec currentEffect of
                ReadEffect currentSpec ->
                  readResult currentKey currentCount (readSpecValueSchema currentSpec)
                MapEffect _ -> HandlerSucceeded (Just (RuntimeValue paramsSchema "Params {paramsText = \"mapped\"}"))
                CommandEffect currentSpec ->
                  HandlerSucceeded
                    (Just (RuntimeValue (commandSpecObservationSchema currentSpec) "Observation {observationOk = True}"))
            )
    readResult currentName currentCount currentSchema
      | "outside" `isInfixOf` currentName = value "outside"
      | currentMode == Feedback && currentCount == 1 =
          HandlerSucceededBatch [runtimeValue "v0", runtimeValue "v1", runtimeValue "v1"]
      | currentMode == Feedback = HandlerSucceededBatch [runtimeValue "v1", runtimeValue "v1"]
      | currentMode == AlwaysChanging =
          HandlerSucceededBatch [runtimeValue (show currentCount), runtimeValue (show (currentCount + 1))]
      | otherwise = value "stable"
      where
        runtimeValue currentPayload = RuntimeValue currentSchema currentPayload
        value currentPayload = HandlerSucceeded (Just (runtimeValue currentPayload))
    cleanup = do
      modifyIORef' currentCleanupOrder (++ [currentKey])
      if currentCleanupFailure && someEffectRefKind currentRef == C
        then pure (Left "cleanup failure witness")
        else pure (Right ())

increment :: IORef [(String, Int)] -> String -> IO Int
increment currentRef currentKey = do
  currentCounts <- readIORef currentRef
  let nextCount = maybe 1 (+ 1) (lookup currentKey currentCounts)
  modifyIORef' currentRef (\currentValues -> (currentKey, nextCount) : filter ((/= currentKey) . fst) currentValues)
  pure nextCount

schemaId :: forall value. HasSchema value => Proxy value -> ValueSchemaId
schemaId _ =
  schemaDescriptorId
    (descriptorFor (SchemaFromType "loop-feedback-witness") (valueSchemaDefinition (Proxy :: Proxy value)))

paramsSchema :: ValueSchemaId
paramsSchema = schemaId (Proxy :: Proxy Params)

eventsOf :: Either [RuntimePreparationError] UnifiedRuntimeRun -> [RuntimeEvent]
eventsOf = either (const []) (runtimeSnapshotEvents . unifiedRuntimeSnapshot)

outcomeOf :: Either [RuntimePreparationError] UnifiedRuntimeRun -> Maybe ContinuationOutcome
outcomeOf = either (const Nothing) (Just . unifiedRuntimeOutcome)

diagnosisRevisions :: Either [RuntimePreparationError] UnifiedRuntimeRun -> [(AstPath, StateRevision)]
diagnosisRevisions =
  either (const []) (runtimeDiagnosisLoopRevisions . runtimeSnapshotDiagnosis . unifiedRuntimeSnapshot)

diagnosisRevisionCount :: Either [RuntimePreparationError] UnifiedRuntimeRun -> Int
diagnosisRevisionCount = sum . map (fromInteger . stateRevisionValue . snd) . diagnosisRevisions

diagnosisFailures :: Either [RuntimePreparationError] UnifiedRuntimeRun -> [RuntimeFault]
diagnosisFailures =
  either (const []) (runtimeDiagnosisLoopFailures . runtimeSnapshotDiagnosis . unifiedRuntimeSnapshot)

isIteration, isRevision, isSettled, isLimit, isOutsideStart :: RuntimeEvent -> Bool
isIteration RuntimeLoopIterationStarted {} = True
isIteration _ = False
isRevision RuntimeLoopRevisionAdvanced {} = True
isRevision _ = False
isSettled RuntimeLoopSettled {} = True
isSettled _ = False
isLimit RuntimeLoopLimitExceeded {} = True
isLimit _ = False
isOutsideStart (RuntimeApplicationStarted _ currentPath) = "outside-command" `isInfixOf` renderAstPath currentPath
isOutsideStart _ = False

revisionOrderValid :: [RuntimeEvent] -> Bool
revisionOrderValid currentEvents =
  case [currentPath | RuntimeLoopRevisionAdvanced currentPath _ <- currentEvents] of
    [currentInner, currentOuter] -> length (astPathSegments currentInner) > length (astPathSegments currentOuter)
    _ -> False

countEvents :: (RuntimeEvent -> Bool) -> [RuntimeEvent] -> Int
countEvents currentPredicate = length . filter currentPredicate

isFailed :: Maybe ContinuationOutcome -> Bool
isFailed (Just Failed {}) = True
isFailed _ = False

isEquivalenceMissing :: RuntimePreparationError -> Bool
isEquivalenceMissing RuntimeLoopEquivalenceMissing {} = True
isEquivalenceMissing _ = False

isGraphCycle :: ProgramError -> Bool
isGraphCycle (ProgramGraphFailed (EffectInputCycle _)) = True
isGraphCycle _ = False

terminalEffect :: String -> String
terminalEffect currentKey
  | "command" `isInfixOf` currentKey = "command"
  | "map" `isInfixOf` currentKey = "map"
  | otherwise = "read"

renderReport :: [Check] -> Bool -> String
renderReport currentChecks succeeded =
  "{"
    ++ jsonField "schema" (jsonString "loop-feedback-witness.v1")
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
