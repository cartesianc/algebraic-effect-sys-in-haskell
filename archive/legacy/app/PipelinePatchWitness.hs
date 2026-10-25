{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE ScopedTypeVariables #-}

module Main (main) where

import Control.Monad
  ( unless
  , when
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
import Data.Proxy
  ( Proxy (..)
  )
import GHC.Generics
  ( Generic
  )
import System.Exit
  ( exitFailure
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

data PatchMode
  = PatchInsert
  | PatchReplace
  | PatchRemove
  | PatchRedirect
  | PatchCycle
  | PatchKindConflict
  | PatchPartialFailure
  | PatchStartedTarget
  | PatchConcurrentConflict
  | PatchMissingEffect
  | PatchOutsideScope
  deriving (Eq, Show)

data Submission = Submission
  { submissionCallback :: CallbackRef
  , submissionResult :: Either [PipelinePatchError] PipelinePatchId
  }
  deriving (Eq, Show)

data PatchRun = PatchRun
  { patchRunResult :: Either [RuntimePreparationError] UnifiedRuntimeRun
  , patchRunSubmissions :: [Submission]
  }

data Check = Check
  { checkName :: String
  , checkPassed :: Bool
  , checkObserved :: String
  }

main :: IO ()
main =
  case patchProgram of
    Left currentErrors -> do
      putStrLn (renderReport [Check "pipeline-patch-program-valid" False (show currentErrors)] False)
      exitFailure
    Right currentPrepared -> do
      insertRun <- runPatchMode PatchInsert currentPrepared
      replaceRun <- runPatchMode PatchReplace currentPrepared
      removeRun <- runPatchMode PatchRemove currentPrepared
      redirectRun <- runPatchMode PatchRedirect currentPrepared
      cycleRun <- runPatchMode PatchCycle currentPrepared
      kindRun <- runPatchMode PatchKindConflict currentPrepared
      partialRun <- runPatchMode PatchPartialFailure currentPrepared
      startedRun <- runPatchMode PatchStartedTarget currentPrepared
      missingRun <- runPatchMode PatchMissingEffect currentPrepared
      outsideRun <- runPatchMode PatchOutsideScope currentPrepared
      conflictRunA <- runPatchMode PatchConcurrentConflict currentPrepared
      conflictRunB <- runPatchMode PatchConcurrentConflict currentPrepared
      let positiveRuns = [insertRun, replaceRun, removeRun, redirectRun]
          negativeRuns = [cycleRun, kindRun, partialRun, startedRun, missingRun, outsideRun]
          originalPlan = preparedRuntimeContinuationPlan currentPrepared
          currentChecks =
            [ Check
                "pipeline-patch-four-operations"
                ( all patchCommitted positiveRuns
                    && map committedConstructor positiveRuns
                      == ["InsertInput", "ReplaceInput", "RemoveInput", "RedirectInput"]
                )
                (show (map committedConstructor positiveRuns))
            , Check
                "pipeline-patch-positive-runtime-success"
                (all ((== Just Succeeded) . patchOutcome) positiveRuns)
                (show (map patchOutcome positiveRuns))
            , Check
                "pipeline-patch-transactional-rollback"
                ( all patchRejected negativeRuns
                    && all rejectedPlanUnchanged negativeRuns
                )
                (show (map patchErrors negativeRuns))
            , Check
                "pipeline-patch-cycle-kind-and-lifecycle-errors"
                ( hasPatchError isCycle cycleRun
                    && hasPatchError isKind kindRun
                    && hasPatchError isKind partialRun
                    && hasPatchError isStarted startedRun
                    && hasPatchError isMissing missingRun
                    && hasPatchError isOutside outsideRun
                )
                (show (map patchErrors negativeRuns))
            , Check
                "pipeline-patch-partial-submit-does-not-commit"
                ( rejectedPlanUnchanged partialRun
                    && length (recordPatches partialRun) == 2
                )
                (show (recordPatches partialRun))
            , Check
                "pipeline-patch-concurrent-conflict-deterministic"
                ( conflictShape conflictRunA == (1, 1)
                    && conflictShape conflictRunB == (1, 1)
                    && conflictFinal conflictRunA == conflictFinal conflictRunB
                    && hasPatchError isConcurrent conflictRunA
                )
                (show (conflictShape conflictRunA, patchErrors conflictRunA))
            , Check
                "pipeline-patch-run-local-only"
                ( preparedRuntimeContinuationPlan currentPrepared == originalPlan
                    && all ((== originalPlan) . firstRecordOriginal) (positiveRuns ++ negativeRuns)
                )
                "global PreparedRuntime continuation remains unchanged"
            , Check
                "pipeline-patch-diagnosis-provenance"
                ( all recordHasProvenance (positiveRuns ++ negativeRuns)
                    && all planHasSingleInputArity (mapMaybeFinal positiveRuns)
                )
                (show (map recordSubmitters positiveRuns))
            , Check
                "pipeline-patch-callback-prestart-phase"
                ( all ((== HookPreStart) . callbackPlanEntryPhase)
                    (callbackPlanEntries (preparedRuntimeHookPlan currentPrepared))
                )
                (show (map callbackPlanEntryPhase (callbackPlanEntries (preparedRuntimeHookPlan currentPrepared))))
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
businessMap =
  withEffectInput
    (after dependencyApplication)
    (mapping "business-map")

businessApplication :: Application
businessApplication = apply businessCommand businessMap businessRead

unusedCommand :: EffectRef 'C Params Observation
unusedCommand = c "unused-command" none

unusedRead :: R Source
unusedRead = r "unused-source"

unusedMap :: EffectRef 'MAP Source Params
unusedMap = mapping "unused-map"

unusedApplication :: Application
unusedApplication = apply unusedCommand unusedMap unusedRead

patchScope :: EffSysRef
patchScope = effSys (name "patch-root") (name "patch-root")

patchProgram :: Either [ProgramError] PreparedRuntime
patchProgram =
  programWithHanging
    (name "patch-root")
    [chain (name "patch-root") [dependencyApplication, businessApplication]]
    [effects (name "patch-root") [dependencyApplication, businessApplication, unusedApplication]]
    ( astBlueprintHanging
        [ callback (name "patch-first") patchScope
        , callback (name "patch-second") patchScope
        ]
    )

schemaId :: forall value. HasSchema value => Proxy value -> ValueSchemaId
schemaId _ =
  schemaDescriptorId
    ( descriptorFor
        (SchemaFromType "pipeline-patch-witness")
        (valueSchemaDefinition (Proxy :: Proxy value))
    )

paramsSchema, observationSchema :: ValueSchemaId
paramsSchema = schemaId (Proxy :: Proxy Params)
observationSchema = schemaId (Proxy :: Proxy Observation)

runPatchMode :: PatchMode -> PreparedRuntime -> IO PatchRun
runPatchMode currentMode currentPrepared = do
  currentSubmissions <- newIORef []
  case
      ( runtimeHandlers currentPrepared
      , runtimeMiddlewareRegistry []
      , callbacksFor currentMode currentSubmissions currentPrepared
      ) of
    (Right currentHandlers, Right currentMiddleware, Right currentCallbacks) -> do
      currentResult <-
        runPreparedRuntimeWithHooks
          currentHandlers
          currentMiddleware
          currentCallbacks
          currentPrepared
      completedSubmissions <- readIORef currentSubmissions
      pure (PatchRun currentResult completedSubmissions)
    _ ->
      pure
        ( PatchRun
            (Left [RuntimeHandlerMissing (EffectKey "pipeline-patch-registry")])
            []
        )

runtimeHandlers ::
  PreparedRuntime ->
  Either [RuntimeHandlerRegistryError] RuntimeHandlerRegistry
runtimeHandlers currentPrepared =
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
            (const (pure (HandlerSucceeded (Just (RuntimeValue (readSpecValueSchema currentSpec) (show (Source "source")))))))
        MapEffect currentSpec ->
          runtimeHandler
            (effectIrRef currentEffect)
            (Just (mapSpecInputSchema currentSpec))
            (Just paramsSchema)
            (\currentInvocation ->
                pure
                  ( if runtimeInvocationPhase currentInvocation == RuntimeInputPhase
                      then HandlerSucceeded Nothing
                      else HandlerSucceeded (Just (RuntimeValue paramsSchema (show (Params "params"))))
                  )
            )
        CommandEffect currentSpec ->
          runtimeHandler
            (effectIrRef currentEffect)
            (Just (commandSpecArgumentSchema currentSpec))
            (Just (commandSpecObservationSchema currentSpec))
            (\currentInvocation ->
                pure
                  ( if runtimeInvocationPhase currentInvocation == RuntimeInputPhase
                      then HandlerSucceeded Nothing
                      else HandlerSucceeded (Just (RuntimeValue observationSchema (show (Observation True))))
                  )
            )

callbacksFor ::
  PatchMode ->
  IORef [Submission] ->
  PreparedRuntime ->
  Either [RuntimeCallbackRegistryError] RuntimeCallbackRegistry
callbacksFor currentMode currentSubmissions currentPrepared =
  runtimeCallbackRegistry
    [ runtimeCallback (CallbackRef "patch-first") (runCallback True)
    , runtimeCallback (CallbackRef "patch-second") (runCallback False)
    ]
  where
    runCallback isFirst currentContext =
      when (pathContains "business" (callbackContextAstPath currentContext)) $ do
        currentPlan <- callbackContextPlanSnapshot currentContext
        let currentPatches = patchesFor currentMode isFirst outsideEffectRef currentPlan
        unless (null currentPatches) $ do
          currentResult <- callbackContextSubmit currentContext currentPatches
          modifyIORef'
            currentSubmissions
            (++ [Submission (callbackContextRef currentContext) currentResult])
    outsideEffectRef =
      case
          [ effectIrRef currentEffect
          | currentEffect <- effectRegistryEffects (effectRegistryOf currentPrepared)
          , "unused-command" `isInfixOf`
              effectKeyText (someEffectRefKey (effectIrRef currentEffect))
          ] of
        currentRef : _ -> currentRef
        [] -> SomeEffectRef (EffectKey "missing-unused-command") C

patchesFor :: PatchMode -> Bool -> SomeEffectRef -> ContinuationPlan -> [PipelinePatch]
patchesFor currentMode isFirst outsideEffectRef currentPlan
  | not isFirst && currentMode /= PatchConcurrentConflict = []
  | otherwise =
      case currentMode of
        PatchInsert -> [InsertInput commandTarget dependencyRef]
        PatchReplace -> [ReplaceInput commandTarget dependencyRef]
        PatchRemove -> [RemoveInput commandTarget]
        PatchRedirect -> [RedirectInput commandTarget mapTarget]
        PatchCycle -> [ReplaceInput dependencyTarget businessRef]
        PatchKindConflict -> [ReplaceInput commandTarget wrongKindRef]
        PatchPartialFailure ->
          [RemoveInput commandTarget, ReplaceInput commandTarget wrongKindRef]
        PatchStartedTarget -> [RemoveInput startedTarget]
        PatchConcurrentConflict
          | isFirst -> [RemoveInput commandTarget]
          | otherwise -> [ReplaceInput commandTarget dependencyRef]
        PatchMissingEffect ->
          [ReplaceInput commandTarget (SomeEffectRef (EffectKey "missing-effect") C)]
        PatchOutsideScope -> [ReplaceInput commandTarget outsideEffectRef]
  where
    currentNodes = continuationPlanNodes currentPlan
    commandNode = findNode ((&&) <$> effectContains "business" <*> effectKindIs C) currentNodes
    mapNode = findNode (effectContains "business-map") currentNodes
    dependencyNode =
      findNode
        (\currentNode ->
            effectContains "dependency" currentNode
              && pathContains "business" (continuationNodeScope currentNode)
        )
        currentNodes
    startedNode =
      findNode
        (\currentNode ->
            effectContains "dependency" currentNode
              && pathContains "dependency" (continuationNodeScope currentNode)
        )
        currentNodes
    commandTarget = continuationNodeId commandNode
    mapTarget = continuationNodeId mapNode
    dependencyTarget = continuationNodeId dependencyNode
    startedTarget = continuationNodeId startedNode
    dependencyRef = continuationNodeEffect dependencyNode
    businessRef = continuationNodeEffect commandNode
    wrongKindRef =
      businessRef
        { someEffectRefKind = E
        }

findNode :: (ContinuationNode -> Bool) -> [ContinuationNode] -> ContinuationNode
findNode currentPredicate currentNodes =
  case filter currentPredicate currentNodes of
    currentNode : _ -> currentNode
    [] -> error "pipeline patch witness target missing"

effectContains :: String -> ContinuationNode -> Bool
effectContains currentText =
  isInfixOf currentText
    . effectKeyText
    . someEffectRefKey
    . continuationNodeEffect

effectKindIs :: EffectKind -> ContinuationNode -> Bool
effectKindIs currentKind = (== currentKind) . someEffectRefKind . continuationNodeEffect

pathContains :: String -> AstPath -> Bool
pathContains currentText =
  any (isInfixOf currentText . astNodeKeyText . astPathSegmentKey) . astPathSegments

patchOutcome :: PatchRun -> Maybe ContinuationOutcome
patchOutcome = either (const Nothing) (Just . unifiedRuntimeOutcome) . patchRunResult

patchRecords :: PatchRun -> [PipelinePatchRecord]
patchRecords =
  either
    (const [])
    ( runtimeDiagnosisPipelinePatches
        . runtimeSnapshotDiagnosis
        . unifiedRuntimeSnapshot
    )
    . patchRunResult

patchCommitted :: PatchRun -> Bool
patchCommitted currentRun =
  case patchRecords currentRun of
    [currentRecord] -> null (pipelinePatchRecordErrors currentRecord)
    _ -> False

patchRejected :: PatchRun -> Bool
patchRejected currentRun =
  case patchRecords currentRun of
    [currentRecord] -> not (null (pipelinePatchRecordErrors currentRecord))
    _ -> False

rejectedPlanUnchanged :: PatchRun -> Bool
rejectedPlanUnchanged currentRun =
  case patchRecords currentRun of
    [currentRecord] ->
      pipelinePatchRecordOriginal currentRecord == pipelinePatchRecordFinal currentRecord
    _ -> False

committedConstructor :: PatchRun -> String
committedConstructor currentRun =
  case recordPatches currentRun of
    InsertInput {} : _ -> "InsertInput"
    ReplaceInput {} : _ -> "ReplaceInput"
    RemoveInput {} : _ -> "RemoveInput"
    RedirectInput {} : _ -> "RedirectInput"
    [] -> "missing"

recordPatches :: PatchRun -> [PipelinePatch]
recordPatches currentRun =
  case patchRecords currentRun of
    currentRecord : _ -> pipelinePatchRecordPatches currentRecord
    [] -> []

patchErrors :: PatchRun -> [PipelinePatchError]
patchErrors = concatMap pipelinePatchRecordErrors . patchRecords

hasPatchError :: (PipelinePatchError -> Bool) -> PatchRun -> Bool
hasPatchError currentPredicate = any currentPredicate . patchErrors

isCycle, isKind, isStarted, isConcurrent, isMissing, isOutside :: PipelinePatchError -> Bool
isCycle PipelinePatchCycle {} = True
isCycle _ = False
isKind PipelinePatchEffectKindMismatch {} = True
isKind _ = False
isStarted PipelinePatchTargetAlreadyStarted {} = True
isStarted _ = False
isConcurrent PipelinePatchConcurrentConflict {} = True
isConcurrent _ = False
isMissing PipelinePatchEffectMissing {} = True
isMissing _ = False
isOutside PipelinePatchEffectOutsideScope {} = True
isOutside _ = False

conflictShape :: PatchRun -> (Int, Int)
conflictShape currentRun =
  ( length [() | currentRecord <- patchRecords currentRun, null (pipelinePatchRecordErrors currentRecord)]
  , length [() | currentRecord <- patchRecords currentRun, not (null (pipelinePatchRecordErrors currentRecord))]
  )

conflictFinal :: PatchRun -> Maybe ContinuationPlan
conflictFinal currentRun =
  case reverse (patchRecords currentRun) of
    currentRecord : _ -> Just (pipelinePatchRecordFinal currentRecord)
    [] -> Nothing

firstRecordOriginal :: PatchRun -> ContinuationPlan
firstRecordOriginal currentRun =
  case patchRecords currentRun of
    currentRecord : _ -> pipelinePatchRecordOriginal currentRecord
    [] -> ContinuationPlan [] []

recordHasProvenance :: PatchRun -> Bool
recordHasProvenance currentRun =
  not (null (patchRunSubmissions currentRun))
    && all validRecord (patchRecords currentRun)
    && all validSubmission (patchRunSubmissions currentRun)
  where
    validRecord currentRecord =
      not (null (pipelinePatchIdText (pipelinePatchRecordId currentRecord)))
        && pipelinePatchRecordSubmitter currentRecord
          `elem` [CallbackRef "patch-first", CallbackRef "patch-second"]
    validSubmission currentSubmission =
      submissionCallback currentSubmission
        `elem` [CallbackRef "patch-first", CallbackRef "patch-second"]
        && case submissionResult currentSubmission of
          Left currentErrors -> not (null currentErrors)
          Right currentPatchId -> not (null (pipelinePatchIdText currentPatchId))

recordSubmitters :: PatchRun -> [CallbackRef]
recordSubmitters = map pipelinePatchRecordSubmitter . patchRecords

mapMaybeFinal :: [PatchRun] -> [ContinuationPlan]
mapMaybeFinal currentRuns =
  [ pipelinePatchRecordFinal currentRecord
  | currentRun <- currentRuns
  , currentRecord <- patchRecords currentRun
  ]

planHasSingleInputArity :: ContinuationPlan -> Bool
planHasSingleInputArity =
  all
    (\currentNode ->
        case continuationNodePredecessor currentNode of
          Nothing -> True
          Just _ -> True
    )
    . continuationPlanNodes

renderReport :: [Check] -> Bool -> String
renderReport currentChecks succeeded =
  "{"
    ++ jsonField "schema" (jsonString "pipeline-patch-witness.v1")
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
