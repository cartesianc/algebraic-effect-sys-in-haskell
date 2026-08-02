{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE ScopedTypeVariables #-}

module Main (main) where

import Control.Monad (unless)
import Data.IORef (IORef, modifyIORef', newIORef)
import Data.List (intercalate, isInfixOf)
import Data.Proxy (Proxy (..))
import GHC.Generics (Generic)
import System.Exit (exitFailure)
import Text.Read (readMaybe)

import MyFramework
import MyFramework.Self.CoreModel

data Source = Source {sourceText :: String}
  deriving (Eq, Generic, Read, Show)

instance HasSchema Source

data Params = Params {paramsText :: String}
  deriving (Eq, Generic, Read, Show)

instance HasSchema Params

data Observation = Observation {observationOk :: Bool}
  deriving (Eq, Generic, Read, Show)

instance HasSchema Observation

data Check = Check
  { checkName :: String
  , checkPassed :: Bool
  , checkObserved :: String
  }

main :: IO ()
main =
  case (choiceProgram, waitReadyProgram, waitBlockedProgram, waitFailedProgram, suspenseProgram, contextProgram) of
    (Right currentChoice, Right currentWaitReady, Right currentWaitBlocked, Right currentWaitFailed, Right currentSuspense, Right currentContext) -> do
      choiceRun <- runProgram currentChoice
      waitReadyRun <- runProgram currentWaitReady
      waitBlockedRun <- runProgramWithControlHooks waitBlockedHooks currentWaitBlocked
      waitFailedRun <- runProgramWithControlHooks waitFailedHooks currentWaitFailed
      suspenseRun <- runProgramWithControlHooks suspenseBlockedHooks currentSuspense
      contextRun <- runProgram currentContext
      emptyRun <- runEmpty
      let currentPolicyRegistry = preparedRuntimeControlPolicyRegistry currentChoice
          frameworkV52Only =
            case frameworkAsBusiness of
              Right currentFramework ->
                "myframework-framework-as-business.v6" == frameworkAsBusinessSchema currentFramework
                  && not ("ReferencedProgram" `isInfixOf` encodeFrameworkAsBusiness currentFramework)
              Left _ -> False
          checks =
            [ Check
                "semantic-closure-choice-selected-only"
                ( outcomeOf choiceRun == Just Succeeded
                    && startedApplication "b-command" choiceRun == 1
                    && startedApplication "a-command" choiceRun == 0
                )
                (show (eventsOf choiceRun))
            , Check
                "semantic-closure-wait-ready-runs-child"
                (outcomeOf waitReadyRun == Just Succeeded && startedApplication "a-command" waitReadyRun == 1)
                (show (outcomeOf waitReadyRun))
            , Check
                "semantic-closure-wait-blocked-suspends"
                (outcomeOf waitBlockedRun == Just (Suspended "wait-blocked"))
                (show (outcomeOf waitBlockedRun))
            , Check
                "semantic-closure-wait-failure-is-diagnosed"
                (isFailed (outcomeOf waitFailedRun))
                (show (outcomeOf waitFailedRun))
            , Check
                "semantic-closure-suspense-uses-gate-contract"
                (outcomeOf suspenseRun == Just (Suspended "suspense-blocked"))
                (show (outcomeOf suspenseRun))
            , Check
                "semantic-closure-context-identity-runs-child"
                ( outcomeOf contextRun == Just Succeeded
                    && any isContextEvent (eventsOf contextRun)
                )
                (show (eventsOf contextRun))
            , Check
                "semantic-closure-unknown-context-fails-before-runtime"
                (either (any isUnknownContext) (const False) unknownContextProgram)
                (show unknownContextProgram)
            , Check
                "semantic-closure-choice-selection-validates"
                (either (any isMissingChoice) (const False) missingChoiceProgram)
                (show missingChoiceProgram)
            , Check
                "semantic-closure-control-policy-roundtrip"
                (readMaybe (show currentPolicyRegistry) == Just currentPolicyRegistry)
                (show currentPolicyRegistry)
            , Check
                "semantic-closure-framework-as-business-v52-only"
                frameworkV52Only
                (either show frameworkAsBusinessSchema frameworkAsBusiness)
            , Check
                "semantic-closure-empty-business-zero-effects-handlers-io"
                emptyRun
                (show emptyBusinessProgram)
            , Check
                "semantic-closure-control-events-in-diagnosis-stream"
                ( any isChoiceEvent (eventsOf choiceRun)
                    && any isGateEvent (eventsOf waitReadyRun)
                    && any isGateEvent (eventsOf suspenseRun)
                )
                "choice/wait/suspense/context provenance is present in RuntimeEvent"
            ]
          succeeded = all checkPassed checks
      putStrLn (renderReport checks succeeded)
      unless succeeded exitFailure
    currentPrograms -> do
      putStrLn (renderReport [Check "semantic-closure-programs" False (show currentPrograms)] False)
      exitFailure

appA, appB :: Application
appA = application "a-command" "a-map" "a-read"
appB = application "b-command" "b-map" "b-read"

application :: String -> String -> String -> Application
application currentCommand currentMap currentRead =
  apply
    (c currentCommand none :: EffectRef 'C Params Observation)
    (mapping currentMap :: EffectRef 'MAP Source Params)
    (r currentRead :: R Source)

choiceProgram, waitReadyProgram, waitBlockedProgram, waitFailedProgram, suspenseProgram, contextProgram :: Either [ProgramError] PreparedRuntime
choiceProgram =
  program
    (name "choice")
    [choice (name "choice") (name "b-command") [appA, appB]]
    [effects (name "choice") [appA, appB]]

waitReadyProgram = waitProgram "wait-ready" defaultReadyGate
waitBlockedProgram = waitProgram "wait-blocked" defaultReadyGate
waitFailedProgram = waitProgram "wait-failed" defaultReadyGate

waitProgram :: String -> VersionedControlGate -> Either [ProgramError] PreparedRuntime
waitProgram currentName currentGate =
  program
    (name currentName)
    [wait (name currentName) currentGate appA]
    [effects (name currentName) [appA]]

suspenseProgram =
  program
    (name "suspense")
    [ suspense
        (name "suspense")
        appA
        defaultReadyGate
    ]
    [effects (name "suspense") [appA]]

contextProgram =
  program
    (name "context")
    [context (name "context") identityContext appA]
    [effects (name "context") [appA]]

unknownContextProgram :: Either [ProgramError] PreparedRuntime
unknownContextProgram =
  program
    (name "unknown-context")
    [ context
        (name "unknown-context")
        (VersionedContext (ContextRefV52 "unknown") (ControlPolicyVersion 1))
        appA
    ]
    [effects (name "unknown-context") [appA]]

missingChoiceProgram :: Either [ProgramError] PreparedRuntime
missingChoiceProgram =
  program
    (name "missing-choice")
    [choice (name "missing-choice") (name "missing") [appA, appB]]
    [effects (name "missing-choice") [appA, appB]]

runProgram :: PreparedRuntime -> IO (Either [RuntimePreparationError] UnifiedRuntimeRun)
runProgram currentProgram = do
  currentCounts <- newIORef []
  case handlersFor currentCounts currentProgram of
    Left _ -> pure (Left [RuntimeHandlerMissing (EffectKey "semantic-closure-registry")])
    Right currentHandlers -> runPreparedRuntime currentHandlers currentProgram

runProgramWithControlHooks ::
  RuntimeControlHooks ->
  PreparedRuntime ->
  IO (Either [RuntimePreparationError] UnifiedRuntimeRun)
runProgramWithControlHooks currentControlHooks currentProgram = do
  currentCounts <- newIORef []
  case
      ( handlersFor currentCounts currentProgram
      , runtimeMiddlewareRegistry []
      , runtimeCallbackRegistry []
      ) of
    (Right currentHandlers, Right currentMiddleware, Right currentCallbacks) ->
      runPreparedRuntimeWithControlHooks
        currentHandlers
        currentMiddleware
        currentCallbacks
        currentControlHooks
        currentProgram
    _ -> pure (Left [RuntimeHandlerMissing (EffectKey "semantic-closure-control-hook")])

waitBlockedHooks, waitFailedHooks, suspenseBlockedHooks :: RuntimeControlHooks
waitBlockedHooks =
  defaultRuntimeControlHooks
    { runtimeControlHookWait = \_ _ _ -> pure (ControlGateBlocked "wait-blocked")
    }
waitFailedHooks =
  defaultRuntimeControlHooks
    { runtimeControlHookWait = \_ _ _ -> pure (ControlGateFailed "wait-failed")
    }
suspenseBlockedHooks =
  defaultRuntimeControlHooks
    { runtimeControlHookSuspense =
        \_ _ _ _ -> pure (ControlGateBlocked "suspense-blocked")
    }

handlersFor :: IORef [(String, Int)] -> PreparedRuntime -> Either [RuntimeHandlerRegistryError] RuntimeHandlerRegistry
handlersFor currentCounts currentProgram =
  runtimeHandlerRegistry
    [ registrationFor currentCounts currentEffect
    | currentEffect <- effectRegistryEffects (effectRegistryOf currentProgram)
    ]

registrationFor :: IORef [(String, Int)] -> EffectIR -> RuntimeHandlerRegistration
registrationFor currentCounts currentEffect =
  runtimeHandler currentRef currentInput currentOutput invoke
  where
    currentRef = effectIrRef currentEffect
    currentKey = effectKeyText (someEffectRefKey currentRef)
    (currentInput, currentOutput) =
      case effectIrSpec currentEffect of
        ReadEffect currentSpec -> (Nothing, Just (readSpecValueSchema currentSpec))
        MapEffect currentSpec -> (Just (mapSpecInputSchema currentSpec), Just paramsSchema)
        CommandEffect currentSpec ->
          (Just (commandSpecArgumentSchema currentSpec), Just (commandSpecObservationSchema currentSpec))
    invoke currentInvocation = do
      modifyIORef' currentCounts (\currentValues -> (currentKey, 1) : currentValues)
      pure
        ( case (runtimeInvocationPhase currentInvocation, effectIrSpec currentEffect) of
            (RuntimeInputPhase, _) -> HandlerSucceeded Nothing
            (_, ReadEffect currentSpec) ->
              HandlerSucceeded (Just (RuntimeValue (readSpecValueSchema currentSpec) "source"))
            (_, MapEffect _) -> HandlerSucceeded (Just (RuntimeValue paramsSchema "params"))
            (_, CommandEffect currentSpec) ->
              HandlerSucceeded (Just (RuntimeValue (commandSpecObservationSchema currentSpec) "ok"))
        )

schemaId :: forall value. HasSchema value => Proxy value -> ValueSchemaId
schemaId _ =
  schemaDescriptorId
    (descriptorFor (SchemaFromType "semantic-closure-witness") (valueSchemaDefinition (Proxy :: Proxy value)))

paramsSchema :: ValueSchemaId
paramsSchema = schemaId (Proxy :: Proxy Params)

runEmpty :: IO Bool
runEmpty =
  case (emptyBusinessProgram, runtimeHandlerRegistry []) of
    (Right currentProgram, Right currentHandlers) -> do
      currentRun <- runPreparedRuntime currentHandlers currentProgram
      pure
        ( effectRegistryEffects (effectRegistryOf currentProgram) == []
            && outcomeOf currentRun == Just Succeeded
            && not (any isHandlerStart (eventsOf currentRun))
        )
    _ -> pure False

eventsOf :: Either [RuntimePreparationError] UnifiedRuntimeRun -> [RuntimeEvent]
eventsOf = either (const []) (runtimeSnapshotEvents . unifiedRuntimeSnapshot)

outcomeOf :: Either [RuntimePreparationError] UnifiedRuntimeRun -> Maybe ContinuationOutcome
outcomeOf = either (const Nothing) (Just . unifiedRuntimeOutcome)

startedApplication :: String -> Either [RuntimePreparationError] UnifiedRuntimeRun -> Int
startedApplication currentKey =
  length
    . filter
      (\currentEvent ->
          case currentEvent of
            RuntimeApplicationStarted _ currentPath -> currentKey `isInfixOf` renderAstPath currentPath
            _ -> False
      )
    . eventsOf

isFailed :: Maybe ContinuationOutcome -> Bool
isFailed (Just Failed {}) = True
isFailed _ = False

isUnknownContext, isMissingChoice :: ProgramError -> Bool
isUnknownContext (ProgramControlPolicyFailed ControlContextUnknown {}) = True
isUnknownContext _ = False
isMissingChoice (ProgramControlPolicyFailed ControlChoiceSelectionMissing {}) = True
isMissingChoice _ = False

isContextEvent, isChoiceEvent, isGateEvent, isHandlerStart :: RuntimeEvent -> Bool
isContextEvent RuntimeContextEntered {} = True
isContextEvent _ = False
isChoiceEvent RuntimeChoiceSelected {} = True
isChoiceEvent _ = False
isGateEvent RuntimeControlGateEvaluated {} = True
isGateEvent _ = False
isHandlerStart RuntimeHandlerStarted {} = True
isHandlerStart _ = False

renderReport :: [Check] -> Bool -> String
renderReport currentChecks succeeded =
  "{"
    ++ jsonField "schema" (jsonString "semantic-closure-witness.v1")
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
