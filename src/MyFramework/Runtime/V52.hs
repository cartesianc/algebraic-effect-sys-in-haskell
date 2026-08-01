{-# LANGUAGE ScopedTypeVariables #-}

module MyFramework.Runtime.V52
  ( BootRunId (..)
  , ContinuationNode (..)
  , ContinuationOutcome (..)
  , ContinuationPlan (..)
  , ContinuationPlanError (..)
  , ContinuationSegment (..)
  , ExecutionInstanceId (..)
  , RuntimeDiagnosis (..)
  , RuntimeEvent (..)
  , RuntimeFault (..)
  , RuntimeHandler
  , RuntimeHandlerPhase (..)
  , RuntimeHandlerRegistration
  , RuntimeHandlerRegistry
  , RuntimeHandlerRegistryError (..)
  , RuntimeHandlerResult (..)
  , RuntimeInvocation (..)
  , RuntimePreparationError (..)
  , MiddlewareContext (..)
  , RuntimeActionV52
  , RuntimeMiddleware
  , RuntimeMiddlewareRegistration
  , RuntimeMiddlewareRegistry
  , RuntimeMiddlewareRegistryError (..)
  , RuntimeSnapshot (..)
  , RuntimeValue (..)
  , UnifiedRuntimeRun (..)
  , compileContinuationPlan
  , continuationPlanDigest
  , executeRuntime
  , executeRuntimeWithHooks
  , runtimeHandler
  , runtimeHandlerRegistry
  , runRuntimeActionV52
  , runtimeMiddleware
  , runtimeMiddlewareRegistry
  ) where

import Control.Concurrent
  ( forkIO
  , newEmptyMVar
  , newMVar
  , putMVar
  , readMVar
  , takeMVar
  )
import Control.Concurrent.MVar
  ( MVar
  , modifyMVar
  , modifyMVar_
  )
import Control.Exception
  ( SomeException
  , displayException
  , try
  )
import Control.Monad
  ( foldM
  , forM
  , forM_
  )
import Data.List
  ( group
  , nub
  , sort
  , sortOn
  )
import qualified Data.Map.Strict as Map
import Data.Maybe
  ( mapMaybe
  )

import MyFramework.Effect
import MyFramework.EffSys.Types
  ( EffSysRef
  )
import MyFramework.Graph
import MyFramework.Hook.Types
import MyFramework.Runtime.Types
  ( BootRunId (..)
  , newBootRunId
  )
import MyFramework.Schema
import MyFramework.TrustBase.Digest
  ( sha256
  )

-- | A serializable, defunctionalized input continuation node.  It contains
-- lifecycle control only; business values cannot inhabit this type.
data ContinuationNode = ContinuationNode
  { continuationNodeId :: InputNodeId
  , continuationNodeOccurrence :: ApplicationOccurrenceId
  , continuationNodeScope :: AstPath
  , continuationNodeEffect :: SomeEffectRef
  , continuationNodePredecessor :: Maybe (ContinuationId, InputNodeId)
  , continuationNodeExecutionOccurrence :: Maybe ApplicationOccurrenceId
  }
  deriving (Eq, Ord, Read, Show)

-- | One lookup segment per target node.  The ordered ids run from the oldest
-- predecessor to the target.  Runtime stops before invoking the target; its
-- own R, MAP, or command phase owns that invocation.
data ContinuationSegment = ContinuationSegment
  { continuationSegmentTarget :: InputNodeId
  , continuationSegmentOrder :: [InputNodeId]
  , continuationSegmentEdges :: [ContinuationId]
  }
  deriving (Eq, Ord, Read, Show)

data ContinuationPlan = ContinuationPlan
  { continuationPlanNodes :: [ContinuationNode]
  , continuationPlanSegments :: [ContinuationSegment]
  }
  deriving (Eq, Ord, Read, Show)

data ContinuationPlanError
  = ContinuationNodeDuplicate [InputNodeId]
  | ContinuationIdDuplicate [ContinuationId]
  | ContinuationEdgeNodeMissing ContinuationId InputNodeId
  | ContinuationMultiplePredecessors InputNodeId [InputNodeId]
  | ContinuationCycle [InputNodeId]
  | ContinuationApplicationAmbiguous
      InputNodeId
      EffectKey
      [ApplicationOccurrenceId]
  deriving (Eq, Ord, Read, Show)

continuationPlanDigest :: ContinuationPlan -> String
continuationPlanDigest = sha256 . show

compileContinuationPlan ::
  CompiledGraphs ->
  Either [ContinuationPlanError] ContinuationPlan
compileContinuationPlan currentGraphs
  | null currentErrors =
      Right
        ContinuationPlan
          { continuationPlanNodes = currentNodes
          , continuationPlanSegments =
              map (buildSegment continuationIndex) currentNodes
          }
  | otherwise = Left (sort (nub currentErrors))
  where
    currentInputGraph = compiledInputGraph currentGraphs
    graphNodes = inputGraphNodes currentInputGraph
    graphEdges = inputGraphEdges currentInputGraph
    occurrences = compiledOccurrences currentGraphs
    nodeIds = map inputNodeId graphNodes
    continuationIds = map inputEdgeContinuation graphEdges
    nodeIndex = Map.fromList [(inputNodeId currentNode, currentNode) | currentNode <- graphNodes]
    incomingIndex =
      Map.fromListWith
        (++)
        [ ( inputEdgeTarget currentEdge
          , [(inputEdgeContinuation currentEdge, inputEdgePredecessor currentEdge)]
          )
        | currentEdge <- graphEdges
        ]
    occurrenceIndex =
      Map.fromList
        [ (applicationOccurrenceId currentOccurrence, currentOccurrence)
        | currentOccurrence <- occurrences
        ]
    commandOccurrenceIndex =
      Map.fromListWith
        (++)
        [ ( someEffectRefKey
              ( effectApplicationCommand
                  (applicationOccurrenceApplication currentOccurrence)
              )
          , [currentOccurrence]
          )
        | currentOccurrence <- occurrences
        ]
    currentNodes =
      sortOn continuationNodeId
        [ ContinuationNode
            { continuationNodeId = inputNodeId currentNode
            , continuationNodeOccurrence = inputNodeOccurrence currentNode
            , continuationNodeScope = inputNodeScope currentNode
            , continuationNodeEffect = inputNodeEffect currentNode
            , continuationNodePredecessor =
                case Map.findWithDefault [] (inputNodeId currentNode) incomingIndex of
                  [currentPredecessor] -> Just currentPredecessor
                  _ -> Nothing
            , continuationNodeExecutionOccurrence =
                fmap applicationOccurrenceId
                  ( resolveNodeOccurrence
                      occurrenceIndex
                      commandOccurrenceIndex
                      currentNode
                  )
            }
        | currentNode <- graphNodes
        ]
    continuationIndex =
      Map.fromList
        [ (continuationNodeId currentNode, currentNode)
        | currentNode <- currentNodes
        ]
    missingErrors =
      concatMap
        (\currentEdge ->
            [ ContinuationEdgeNodeMissing
                (inputEdgeContinuation currentEdge)
                currentNode
            | currentNode <-
                [ inputEdgePredecessor currentEdge
                , inputEdgeTarget currentEdge
                ]
            , Map.notMember currentNode nodeIndex
            ]
        )
        graphEdges
    multipleErrors =
      [ ContinuationMultiplePredecessors
          currentTarget
          (sort (map snd currentPredecessors))
      | (currentTarget, currentPredecessors) <- Map.toList incomingIndex
      , length currentPredecessors > 1
      ]
    cycleErrors =
      map ContinuationCycle
        (continuationCycles incomingIndex nodeIds)
    ambiguityErrors =
      [ ContinuationApplicationAmbiguous
          (inputNodeId currentNode)
          currentKey
          (sort (map applicationOccurrenceId currentCandidates))
      | currentNode <- graphNodes
      , let currentKey = someEffectRefKey (inputNodeEffect currentNode)
      , let currentCandidates = Map.findWithDefault [] currentKey commandOccurrenceIndex
      , not (isOwnCommand occurrenceIndex currentNode)
      , length currentCandidates > 1
      ]
    currentErrors =
      [ContinuationNodeDuplicate currentDuplicates | not (null currentDuplicates)]
        ++ [ContinuationIdDuplicate idDuplicates | not (null idDuplicates)]
        ++ missingErrors
        ++ multipleErrors
        ++ cycleErrors
        ++ ambiguityErrors
    currentDuplicates = duplicates nodeIds
    idDuplicates = duplicates continuationIds

resolveNodeOccurrence ::
  Map.Map ApplicationOccurrenceId ApplicationOccurrence ->
  Map.Map EffectKey [ApplicationOccurrence] ->
  InputNode ->
  Maybe ApplicationOccurrence
resolveNodeOccurrence occurrenceIndex commandOccurrenceIndex currentNode
  | isOwnCommand occurrenceIndex currentNode =
      Map.lookup (inputNodeOccurrence currentNode) occurrenceIndex
  | otherwise =
      case
          Map.findWithDefault
            []
            (someEffectRefKey (inputNodeEffect currentNode))
            commandOccurrenceIndex of
        [currentOccurrence] -> Just currentOccurrence
        _ -> Nothing

isOwnCommand ::
  Map.Map ApplicationOccurrenceId ApplicationOccurrence ->
  InputNode ->
  Bool
isOwnCommand occurrenceIndex currentNode =
  case Map.lookup (inputNodeOccurrence currentNode) occurrenceIndex of
    Nothing -> False
    Just currentOccurrence ->
      someEffectRefKey
        ( effectApplicationCommand
            (applicationOccurrenceApplication currentOccurrence)
        )
        == someEffectRefKey (inputNodeEffect currentNode)

buildSegment ::
  Map.Map InputNodeId ContinuationNode ->
  ContinuationNode ->
  ContinuationSegment
buildSegment nodeIndex currentTarget =
  ContinuationSegment
    { continuationSegmentTarget = continuationNodeId currentTarget
    , continuationSegmentOrder = currentReverseNodes
    , continuationSegmentEdges = currentReverseEdges
    }
  where
    (currentReverseNodes, currentReverseEdges) =
      walk [] [] (continuationNodeId currentTarget)
    predecessorIndex =
      Map.mapMaybe continuationNodePredecessor nodeIndex
    -- Every node is recovered from the graph index so malformed references
    -- cannot silently enter a segment.  compileContinuationPlan rejects them.
    walk currentNodes currentEdges currentNode =
      case Map.lookup currentNode nodeIndex of
        Nothing -> (currentNodes, currentEdges)
        Just _ ->
          case Map.lookup currentNode predecessorIndex of
            Nothing -> (currentNode : currentNodes, currentEdges)
            Just (currentContinuation, currentPredecessor) ->
              walk
                (currentNode : currentNodes)
                (currentContinuation : currentEdges)
                currentPredecessor

continuationCycles ::
  Map.Map InputNodeId [(ContinuationId, InputNodeId)] ->
  [InputNodeId] ->
  [[InputNodeId]]
continuationCycles incomingIndex currentNodes =
  sort . nub . map canonicalCycle $
    mapMaybe (walk []) currentNodes
  where
    walk currentPath currentNode
      | currentNode `elem` currentPath =
          Just (dropWhile (/= currentNode) currentPath ++ [currentNode])
      | otherwise =
          case Map.findWithDefault [] currentNode incomingIndex of
            [(_, currentPredecessor)] ->
              walk (currentPath ++ [currentNode]) currentPredecessor
            _ -> Nothing

canonicalCycle :: Ord item => [item] -> [item]
canonicalCycle [] = []
canonicalCycle currentCycle =
  minimum
    [ currentRotation ++ [head currentRotation]
    | currentRotation <- rotations withoutClosing
    ]
  where
    withoutClosing
      | length currentCycle > 1 && head currentCycle == last currentCycle = init currentCycle
      | otherwise = currentCycle

rotations :: [item] -> [[item]]
rotations [] = [[]]
rotations currentItems =
  [ drop currentIndex currentItems ++ take currentIndex currentItems
  | currentIndex <- [0 .. length currentItems - 1]
  ]

duplicates :: Ord item => [item] -> [item]
duplicates currentItems =
  [ head currentGroup
  | currentGroup <- group (sort currentItems)
  , length currentGroup > 1
  ]

data RuntimeValue = RuntimeValue
  { runtimeValueSchema :: ValueSchemaId
  , runtimeValuePayload :: String
  }
  deriving (Eq, Ord, Read, Show)

data RuntimeFault = RuntimeFault
  { runtimeFaultEffect :: Maybe SomeEffectRef
  , runtimeFaultPhase :: RuntimeHandlerPhase
  , runtimeFaultMessage :: String
  }
  deriving (Eq, Ord, Read, Show)

-- | The entire CPS payload.  No constructor carries RuntimeValue.
data ContinuationOutcome
  = Succeeded
  | Failed RuntimeFault
  | Cancelled String
  | Suspended String
  deriving (Eq, Ord, Read, Show)

data RuntimeHandlerPhase
  = RuntimeInputPhase
  | RuntimeReadPhase
  | RuntimeMapPhase
  | RuntimeCommandPhase
  deriving (Eq, Ord, Read, Show)

data ExecutionInstanceId = ExecutionInstanceId
  { executionInstanceBootRun :: BootRunId
  , executionInstanceAstPath :: AstPath
  , executionInstanceEffect :: SomeEffectRef
  }
  deriving (Eq, Ord, Show)

data RuntimeInvocation = RuntimeInvocation
  { runtimeInvocationInstance :: ExecutionInstanceId
  , runtimeInvocationPhase :: RuntimeHandlerPhase
  , runtimeInvocationValue :: Maybe RuntimeValue
  }
  deriving (Eq, Ord, Show)

data RuntimeHandlerResult
  = HandlerSucceeded (Maybe RuntimeValue)
  | HandlerFailed String
  | HandlerCancelled String
  | HandlerSuspended String
  deriving (Eq, Ord, Read, Show)

type RuntimeHandler = RuntimeInvocation -> IO RuntimeHandlerResult

data RuntimeHandlerRegistration = RuntimeHandlerRegistration
  { handlerRegistrationEffect :: SomeEffectRef
  , handlerRegistrationInputSchema :: Maybe ValueSchemaId
  , handlerRegistrationOutputSchema :: Maybe ValueSchemaId
  , handlerRegistrationFunction :: RuntimeHandler
  }

newtype RuntimeHandlerRegistry = RuntimeHandlerRegistry
  { runtimeHandlerRegistryMap :: Map.Map EffectKey RuntimeHandlerRegistration
  }

data RuntimeHandlerRegistryError
  = RuntimeHandlerDuplicate EffectKey
  deriving (Eq, Ord, Read, Show)

newtype RuntimeActionV52 = RuntimeActionV52
  { runRuntimeActionV52 :: IO ContinuationOutcome
  }

data MiddlewareContext = MiddlewareContext
  { middlewareContextRef :: MiddlewareRef
  , middlewareContextScope :: EffSysRef
  , middlewareContextAstPath :: AstPath
  , middlewareContextSnapshot :: IO RuntimeSnapshot
  , middlewareContextOwnApplication :: Maybe RuntimeActionV52
  }

type RuntimeMiddleware =
  MiddlewareContext ->
  RuntimeActionV52 ->
  IO ContinuationOutcome

data RuntimeMiddlewareRegistration = RuntimeMiddlewareRegistration
  { runtimeMiddlewareRegistrationRef :: MiddlewareRef
  , runtimeMiddlewareRegistrationFunction :: RuntimeMiddleware
  }

newtype RuntimeMiddlewareRegistry = RuntimeMiddlewareRegistry
  { runtimeMiddlewareRegistryMap :: Map.Map MiddlewareRef RuntimeMiddlewareRegistration
  }

data RuntimeMiddlewareRegistryError
  = RuntimeMiddlewareDuplicate MiddlewareRef
  deriving (Eq, Ord, Read, Show)

runtimeMiddleware ::
  MiddlewareRef ->
  RuntimeMiddleware ->
  RuntimeMiddlewareRegistration
runtimeMiddleware currentRef currentFunction =
  RuntimeMiddlewareRegistration
    { runtimeMiddlewareRegistrationRef = currentRef
    , runtimeMiddlewareRegistrationFunction = currentFunction
    }

runtimeMiddlewareRegistry ::
  [RuntimeMiddlewareRegistration] ->
  Either [RuntimeMiddlewareRegistryError] RuntimeMiddlewareRegistry
runtimeMiddlewareRegistry currentRegistrations
  | null currentErrors =
      Right
        ( RuntimeMiddlewareRegistry
            ( Map.fromList
                [ (runtimeMiddlewareRegistrationRef currentRegistration, currentRegistration)
                | currentRegistration <- currentRegistrations
                ]
            )
        )
  | otherwise = Left currentErrors
  where
    currentErrors =
      map RuntimeMiddlewareDuplicate
        (duplicates (map runtimeMiddlewareRegistrationRef currentRegistrations))

runtimeHandler ::
  SomeEffectRef ->
  Maybe ValueSchemaId ->
  Maybe ValueSchemaId ->
  RuntimeHandler ->
  RuntimeHandlerRegistration
runtimeHandler currentEffect currentInput currentOutput currentFunction =
  RuntimeHandlerRegistration
    { handlerRegistrationEffect = currentEffect
    , handlerRegistrationInputSchema = currentInput
    , handlerRegistrationOutputSchema = currentOutput
    , handlerRegistrationFunction = currentFunction
    }

runtimeHandlerRegistry ::
  [RuntimeHandlerRegistration] ->
  Either [RuntimeHandlerRegistryError] RuntimeHandlerRegistry
runtimeHandlerRegistry currentRegistrations
  | null currentErrors =
      Right
        ( RuntimeHandlerRegistry
            ( Map.fromList
                [ (someEffectRefKey (handlerRegistrationEffect currentRegistration), currentRegistration)
                | currentRegistration <- currentRegistrations
                ]
            )
        )
  | otherwise = Left currentErrors
  where
    currentErrors =
      map RuntimeHandlerDuplicate
        ( duplicates
            (map (someEffectRefKey . handlerRegistrationEffect) currentRegistrations)
        )

data RuntimePreparationError
  = RuntimeHandlerMissing EffectKey
  | RuntimeHandlerKindMismatch EffectKey EffectKind EffectKind
  | RuntimeHandlerInputSchemaMismatch EffectKey (Maybe ValueSchemaId) (Maybe ValueSchemaId)
  | RuntimeHandlerOutputSchemaMismatch EffectKey (Maybe ValueSchemaId) (Maybe ValueSchemaId)
  | RuntimeMapOutputSchemaAmbiguous EffectKey [ValueSchemaId]
  | RuntimeMiddlewareMissing MiddlewareRef
  | RuntimeHookContinuationInvalid ContinuationPlanError
  | RuntimeAstOccurrenceMissing AstPath
  | RuntimeContinuationNodeMissing ApplicationOccurrenceId EffectKey
  deriving (Eq, Ord, Read, Show)

data RuntimeEvent
  = RuntimeApplicationStarted ApplicationOccurrenceId AstPath
  | RuntimeApplicationFinished ApplicationOccurrenceId AstPath ContinuationOutcome
  | RuntimeContinuationAdvanced ContinuationId InputNodeId InputNodeId ContinuationOutcome
  | RuntimeHandlerStarted ExecutionInstanceId RuntimeHandlerPhase
  | RuntimeHandlerFinished ExecutionInstanceId RuntimeHandlerPhase RuntimeHandlerResult
  | RuntimeSingleFlightReused ExecutionInstanceId
  | RuntimeValueProduced ExecutionInstanceId RuntimeHandlerPhase ValueSchemaId
  | RuntimeHookEntered MiddlewareRef EffSysRef AstPath
  | RuntimeHookExited MiddlewareRef EffSysRef AstPath ContinuationOutcome
  | RuntimeHookOwnApplicationStarted MiddlewareRef ApplicationOccurrenceId AstPath
  deriving (Eq, Ord, Show)

data RuntimeDiagnosis = RuntimeDiagnosis
  { runtimeDiagnosisInputTrace :: [ContinuationId]
  , runtimeDiagnosisFailures :: [RuntimeFault]
  }
  deriving (Eq, Ord, Show)

data RuntimeSnapshot = RuntimeSnapshot
  { runtimeSnapshotStatuses :: [(ExecutionInstanceId, ContinuationOutcome)]
  , runtimeSnapshotObservations :: [(ExecutionInstanceId, RuntimeValue)]
  , runtimeSnapshotEvents :: [RuntimeEvent]
  , runtimeSnapshotDiagnosis :: RuntimeDiagnosis
  }
  deriving (Eq, Ord, Show)

data UnifiedRuntimeRun = UnifiedRuntimeRun
  { unifiedRuntimeBootRunId :: BootRunId
  , unifiedRuntimeOutcome :: ContinuationOutcome
  , unifiedRuntimeSnapshot :: RuntimeSnapshot
  }
  deriving (Eq, Ord, Show)

data MutableRuntime = MutableRuntime
  { mutableStatuses :: Map.Map ExecutionInstanceId ContinuationOutcome
  , mutableObservations :: Map.Map ExecutionInstanceId RuntimeValue
  , mutableEvents :: [RuntimeEvent]
  , mutableTrace :: [ContinuationId]
  }

emptyMutableRuntime :: MutableRuntime
emptyMutableRuntime =
  MutableRuntime Map.empty Map.empty [] []

data RuntimeEnvironment = RuntimeEnvironment
  { environmentBootRun :: BootRunId
  , environmentEffects :: Map.Map EffectKey EffectIR
  , environmentHandlers :: RuntimeHandlerRegistry
  , environmentContinuationNodes :: Map.Map InputNodeId ContinuationNode
  , environmentContinuationLookup :: Map.Map (ApplicationOccurrenceId, EffectKey) InputNodeId
  , environmentOccurrences :: Map.Map AstPath ApplicationOccurrence
  , environmentOccurrencesById :: Map.Map ApplicationOccurrenceId ApplicationOccurrence
  , environmentState :: MVar MutableRuntime
  , environmentFlights :: MVar (Map.Map ExecutionInstanceId (MVar RuntimeHandlerResult))
  , environmentHookPlan :: HookPlan
  , environmentMiddlewareRegistry :: RuntimeMiddlewareRegistry
  }

executeRuntime ::
  EffectRegistry ->
  AstPlan ->
  CompiledGraphs ->
  ContinuationPlan ->
  RuntimeHandlerRegistry ->
  IO (Either [RuntimePreparationError] UnifiedRuntimeRun)
executeRuntime currentEffects currentAst currentGraphs currentPlan currentHandlers =
  executeRuntimeWithHooks
    currentEffects
    currentAst
    currentGraphs
    currentPlan
    emptyHookPlan
    currentHandlers
    (RuntimeMiddlewareRegistry Map.empty)

executeRuntimeWithHooks ::
  EffectRegistry ->
  AstPlan ->
  CompiledGraphs ->
  ContinuationPlan ->
  HookPlan ->
  RuntimeHandlerRegistry ->
  RuntimeMiddlewareRegistry ->
  IO (Either [RuntimePreparationError] UnifiedRuntimeRun)
executeRuntimeWithHooks currentEffects currentAst baseGraphs basePlan currentHookPlan currentHandlers currentMiddleware =
  case compileContinuationPlan (hookPlanDetachedGraphs currentHookPlan) of
    Left currentContinuationErrors ->
      pure (Left (map RuntimeHookContinuationInvalid currentContinuationErrors))
    Right detachedPlan ->
      runPrepared mergedGraphs (mergeContinuationPlans basePlan detachedPlan)
  where
    mergedGraphs = mergeRuntimeGraphs baseGraphs (hookPlanDetachedGraphs currentHookPlan)
    runPrepared currentGraphs currentPlan =
      case
          validateRuntimePreparation currentEffects currentGraphs currentHandlers
            ++ validateRuntimeMiddleware currentHookPlan currentMiddleware of
        [] -> do
          currentBootRun <- newBootRunId
          currentState <- newMVar emptyMutableRuntime
          currentFlights <- newMVar Map.empty
          let currentEnvironment =
                RuntimeEnvironment
                  { environmentBootRun = currentBootRun
                  , environmentEffects =
                      Map.fromList
                        [ (someEffectRefKey (effectIrRef currentEffect), currentEffect)
                        | currentEffect <- effectRegistryEffects currentEffects
                        ]
                  , environmentHandlers = currentHandlers
                  , environmentContinuationNodes =
                      Map.fromList
                        [ (continuationNodeId currentNode, currentNode)
                        | currentNode <- continuationPlanNodes currentPlan
                        ]
                  , environmentContinuationLookup =
                      Map.fromList
                        [ ( (continuationNodeOccurrence currentNode, someEffectRefKey (continuationNodeEffect currentNode))
                          , continuationNodeId currentNode
                          )
                        | currentNode <- continuationPlanNodes currentPlan
                        ]
                  , environmentOccurrences =
                      Map.fromList
                        [ (applicationOccurrencePath currentOccurrence, currentOccurrence)
                        | currentOccurrence <- compiledOccurrences currentGraphs
                        ]
                  , environmentOccurrencesById =
                      Map.fromList
                        [ (applicationOccurrenceId currentOccurrence, currentOccurrence)
                        | currentOccurrence <- compiledOccurrences currentGraphs
                        ]
                  , environmentState = currentState
                  , environmentFlights = currentFlights
                  , environmentHookPlan = currentHookPlan
                  , environmentMiddlewareRegistry = currentMiddleware
                  }
          currentOutcome <- executeAst currentEnvironment (AstPath []) currentAst
          currentFinal <- readMVar currentState
          pure
            ( Right
                UnifiedRuntimeRun
                  { unifiedRuntimeBootRunId = currentBootRun
                  , unifiedRuntimeOutcome = currentOutcome
                  , unifiedRuntimeSnapshot = snapshotRuntime currentFinal
                  }
            )
        currentErrors -> pure (Left (sort (nub currentErrors)))

mergeRuntimeGraphs :: CompiledGraphs -> CompiledGraphs -> CompiledGraphs
mergeRuntimeGraphs currentBase currentDetached =
  CompiledGraphs
    { compiledAstGraph = compiledAstGraph currentBase
    , compiledInputGraph =
        InputGraph
          { inputGraphNodes =
              nub
                ( inputGraphNodes (compiledInputGraph currentBase)
                    ++ inputGraphNodes (compiledInputGraph currentDetached)
                )
          , inputGraphEdges =
              nub
                ( inputGraphEdges (compiledInputGraph currentBase)
                    ++ inputGraphEdges (compiledInputGraph currentDetached)
                )
          }
    , compiledValueGraph =
        ValueGraph
          { valueGraphNodes =
              nub
                ( valueGraphNodes (compiledValueGraph currentBase)
                    ++ valueGraphNodes (compiledValueGraph currentDetached)
                )
          , valueGraphEdges =
              nub
                ( valueGraphEdges (compiledValueGraph currentBase)
                    ++ valueGraphEdges (compiledValueGraph currentDetached)
                )
          }
    , compiledOccurrences =
        nub (compiledOccurrences currentBase ++ compiledOccurrences currentDetached)
    }

mergeContinuationPlans :: ContinuationPlan -> ContinuationPlan -> ContinuationPlan
mergeContinuationPlans currentBase currentDetached =
  ContinuationPlan
    { continuationPlanNodes =
        nub (continuationPlanNodes currentBase ++ continuationPlanNodes currentDetached)
    , continuationPlanSegments =
        nub (continuationPlanSegments currentBase ++ continuationPlanSegments currentDetached)
    }

validateRuntimeMiddleware ::
  HookPlan ->
  RuntimeMiddlewareRegistry ->
  [RuntimePreparationError]
validateRuntimeMiddleware currentPlan (RuntimeMiddlewareRegistry currentRegistry) =
  [ RuntimeMiddlewareMissing (hookPlanEntryRef currentEntry)
  | currentEntry <- hookPlanEntries currentPlan
  , Map.notMember (hookPlanEntryRef currentEntry) currentRegistry
  ]

validateRuntimePreparation ::
  EffectRegistry ->
  CompiledGraphs ->
  RuntimeHandlerRegistry ->
  [RuntimePreparationError]
validateRuntimePreparation currentEffects currentGraphs (RuntimeHandlerRegistry handlerIndex) =
  sort . nub $
    mapOutputErrors
      ++ concatMap
        validateOne
        [ currentEffect
        | currentEffect <- effectRegistryEffects currentEffects
        , someEffectRefKey (effectIrRef currentEffect) `elem` requiredEffectKeys
        ]
  where
    requiredEffectKeys =
      nub
        ( [ someEffectRefKey (inputNodeEffect currentNode)
          | currentNode <- inputGraphNodes (compiledInputGraph currentGraphs)
          ]
            ++ [ someEffectRefKey (valueNodeEffect currentNode)
               | currentNode <- valueGraphNodes (compiledValueGraph currentGraphs)
               ]
        )
    mapOutputCandidates =
      Map.fromListWith
        (++)
        [ (someEffectRefKey (effectApplicationMap currentApplication), [currentSchema])
        | currentOccurrence <- compiledOccurrences currentGraphs
        , let currentApplication = applicationOccurrenceApplication currentOccurrence
        , Just currentSchema <- [commandArgumentSchema effectIndex currentApplication]
        ]
    applicationMapOutputs =
      Map.map
        (\currentSchemas ->
            case nub currentSchemas of
              [currentSchema] -> Just currentSchema
              _ -> Nothing
        )
        mapOutputCandidates
    mapOutputErrors =
      [ RuntimeMapOutputSchemaAmbiguous currentKey currentSchemas
      | (currentKey, rawSchemas) <- Map.toList mapOutputCandidates
      , let currentSchemas = sort (nub rawSchemas)
      , length currentSchemas > 1
      ]
    effectIndex =
      Map.fromList
        [ (someEffectRefKey (effectIrRef currentEffect), currentEffect)
        | currentEffect <- effectRegistryEffects currentEffects
        ]
    validateOne currentEffect =
      case expectedHandlerContract applicationMapOutputs currentEffect of
        Nothing -> []
        Just (currentInput, currentOutput) ->
          case Map.lookup currentKey handlerIndex of
            Nothing -> [RuntimeHandlerMissing currentKey]
            Just currentHandler ->
              [ RuntimeHandlerKindMismatch currentKey expectedKind actualKind
              | expectedKind /= actualKind
              ]
                ++ [ RuntimeHandlerInputSchemaMismatch
                       currentKey
                       currentInput
                       (handlerRegistrationInputSchema currentHandler)
                   | currentInput /= handlerRegistrationInputSchema currentHandler
                   ]
                ++ [ RuntimeHandlerOutputSchemaMismatch
                       currentKey
                       currentOutput
                       (handlerRegistrationOutputSchema currentHandler)
                   | currentOutput /= handlerRegistrationOutputSchema currentHandler
                   ]
              where
                actualKind = someEffectRefKind (handlerRegistrationEffect currentHandler)
      where
        currentKey = someEffectRefKey (effectIrRef currentEffect)
        expectedKind = someEffectRefKind (effectIrRef currentEffect)

expectedHandlerContract ::
  Map.Map EffectKey (Maybe ValueSchemaId) ->
  EffectIR ->
  Maybe (Maybe ValueSchemaId, Maybe ValueSchemaId)
expectedHandlerContract applicationMapOutputs currentEffect =
  case effectIrSpec currentEffect of
    CommandEffect currentSpec ->
      Just
        ( Just (commandSpecArgumentSchema currentSpec)
        , Just (commandSpecObservationSchema currentSpec)
        )
    MapEffect currentSpec ->
      Just
        ( Just (mapSpecInputSchema currentSpec)
        , Map.findWithDefault Nothing
            (someEffectRefKey (effectIrRef currentEffect))
            applicationMapOutputs
        )
    ReadEffect currentSpec ->
      case readSpecSource currentSpec of
        ValueExternal _ ->
          Just (Nothing, Just (readSpecValueSchema currentSpec))
        _ -> Nothing

commandArgumentSchema ::
  Map.Map EffectKey EffectIR ->
  EffectApplication ->
  Maybe ValueSchemaId
commandArgumentSchema effectIndex currentApplication =
  case Map.lookup (someEffectRefKey (effectApplicationCommand currentApplication)) effectIndex of
    Just currentEffect ->
      case effectIrSpec currentEffect of
        CommandEffect currentSpec -> Just (commandSpecArgumentSchema currentSpec)
        _ -> Nothing
    Nothing -> Nothing

executeAst :: RuntimeEnvironment -> AstPath -> AstPlan -> IO ContinuationOutcome
executeAst currentEnvironment parentPath currentPlan =
  case currentPlan of
    AstPlanApplication currentKey _ ->
      executeApplicationAt
        currentEnvironment
        (appendPath parentPath currentKey 0)
    AstPlanBranch currentKey currentKind currentChildren ->
      let currentPath = appendPath parentPath currentKey 0
          indexedChildren = zip [0 ..] currentChildren
          runChild (currentIndex, currentChild) =
            executeAstAt currentEnvironment currentPath currentIndex currentChild
       in case currentKind of
            AstChain -> executeChain runChild indexedChildren
            AstParallel -> executeParallel runChild indexedChildren
            AstFallback -> executeFallback runChild indexedChildren
            AstRace -> executeRace runChild indexedChildren
            _ ->
              pure
                ( Failed
                    RuntimeFault
                      { runtimeFaultEffect = Nothing
                      , runtimeFaultPhase = RuntimeInputPhase
                      , runtimeFaultMessage =
                          "AST branch is reserved for a later v5.2 stage: "
                            ++ show currentKind
                      }
                )

executeAstAt ::
  RuntimeEnvironment ->
  AstPath ->
  Int ->
  AstPlan ->
  IO ContinuationOutcome
executeAstAt currentEnvironment currentParent currentOrdinal currentPlan =
  case currentPlan of
    AstPlanApplication currentKey _ ->
      executeApplicationAt
        currentEnvironment
        (appendPath currentParent currentKey currentOrdinal)
    AstPlanBranch currentKey currentKind currentChildren ->
      let currentPath = appendPath currentParent currentKey currentOrdinal
          indexedChildren = zip [0 ..] currentChildren
          runChild (currentIndex, currentChild) =
            executeAstAt currentEnvironment currentPath currentIndex currentChild
       in case currentKind of
            AstChain -> executeChain runChild indexedChildren
            AstParallel -> executeParallel runChild indexedChildren
            AstFallback -> executeFallback runChild indexedChildren
            AstRace -> executeRace runChild indexedChildren
            _ ->
              pure
                ( Failed
                    RuntimeFault
                      { runtimeFaultEffect = Nothing
                      , runtimeFaultPhase = RuntimeInputPhase
                      , runtimeFaultMessage =
                          "AST branch is reserved for a later v5.2 stage: "
                            ++ show currentKind
                      }
                )

appendPath :: AstPath -> AstNodeKey -> Int -> AstPath
appendPath (AstPath currentSegments) currentKey currentOrdinal =
  AstPath (currentSegments ++ [AstPathSegment currentKey currentOrdinal])

executeChain ::
  (item -> IO ContinuationOutcome) ->
  [item] ->
  IO ContinuationOutcome
executeChain currentRun = foldM step Succeeded
  where
    step currentOutcome currentItem =
      case currentOutcome of
        Succeeded -> currentRun currentItem
        _ -> pure currentOutcome

executeParallel ::
  (item -> IO ContinuationOutcome) ->
  [item] ->
  IO ContinuationOutcome
executeParallel currentRun currentItems = do
  currentResults <-
    forM currentItems $ \currentItem -> do
      currentResult <- newEmptyMVar
      _ <- forkIO (currentRun currentItem >>= putMVar currentResult)
      pure currentResult
  outcomes <- mapM takeMVar currentResults
  pure (firstNonSuccess outcomes)

executeFallback ::
  (item -> IO ContinuationOutcome) ->
  [item] ->
  IO ContinuationOutcome
executeFallback _ [] =
  pure
    ( Failed
        RuntimeFault
          { runtimeFaultEffect = Nothing
          , runtimeFaultPhase = RuntimeInputPhase
          , runtimeFaultMessage = "fallback exhausted"
          }
    )
executeFallback currentRun (currentItem : remaining) = do
  currentOutcome <- currentRun currentItem
  case currentOutcome of
    Failed _ -> executeFallback currentRun remaining
    _ -> pure currentOutcome

executeRace ::
  (item -> IO ContinuationOutcome) ->
  [item] ->
  IO ContinuationOutcome
executeRace _ [] =
  pure
    ( Failed
        RuntimeFault
          { runtimeFaultEffect = Nothing
          , runtimeFaultPhase = RuntimeInputPhase
          , runtimeFaultMessage = "race has no branches"
          }
    )
executeRace currentRun currentItems = do
  completionQueue <- newEmptyMVar
  completionAck <- newEmptyMVar
  forM_ currentItems $ \currentItem -> do
    _ <-
      forkIO $ do
        currentOutcome <- currentRun currentItem
        putMVar completionQueue currentOutcome
        takeMVar completionAck
    pure ()
  firstOutcome <- takeMVar completionQueue
  putMVar completionAck ()
  remainingOutcomes <-
    forM [2 .. length currentItems] $ \_ -> do
      currentOutcome <- takeMVar completionQueue
      putMVar completionAck ()
      pure currentOutcome
  let _ = remainingOutcomes
  pure firstOutcome

firstNonSuccess :: [ContinuationOutcome] -> ContinuationOutcome
firstNonSuccess currentOutcomes =
  case [currentOutcome | currentOutcome <- currentOutcomes, currentOutcome /= Succeeded] of
    currentOutcome : _ -> currentOutcome
    [] -> Succeeded

executeApplicationAt ::
  RuntimeEnvironment ->
  AstPath ->
  IO ContinuationOutcome
executeApplicationAt currentEnvironment currentPath =
  runRuntimeActionV52
    ( foldr
        (wrapMiddleware currentEnvironment currentPath)
        (RuntimeActionV52 (executeApplicationCoreAt currentEnvironment currentPath))
        (hooksForPath currentEnvironment currentPath)
    )

executeApplicationCoreAt ::
  RuntimeEnvironment ->
  AstPath ->
  IO ContinuationOutcome
executeApplicationCoreAt currentEnvironment currentPath =
  case Map.lookup currentPath (environmentOccurrences currentEnvironment) of
    Nothing ->
      pure
        ( Failed
            RuntimeFault
              { runtimeFaultEffect = Nothing
              , runtimeFaultPhase = RuntimeInputPhase
              , runtimeFaultMessage = "AST occurrence missing: " ++ renderAstPath currentPath
              }
        )
    Just currentOccurrence -> do
      appendRuntimeEvent
        currentEnvironment
        (RuntimeApplicationStarted (applicationOccurrenceId currentOccurrence) currentPath)
      currentOutcome <- executeApplication currentEnvironment currentOccurrence
      appendRuntimeEvent
        currentEnvironment
        (RuntimeApplicationFinished (applicationOccurrenceId currentOccurrence) currentPath currentOutcome)
      pure currentOutcome

hooksForPath :: RuntimeEnvironment -> AstPath -> [HookPlanEntry]
hooksForPath currentEnvironment currentPath =
  sortOn hookOrder
    [ currentEntry
    | currentEntry <- hookPlanEntries (environmentHookPlan currentEnvironment)
    , astPathWithin (hookPlanEntryResolvedRoot currentEntry) currentPath
    ]
  where
    hookOrder currentEntry =
      ( pathDepth (hookPlanEntryResolvedRoot currentEntry)
      , hookPlanEntryDeclarationOrder currentEntry
      )

pathDepth :: AstPath -> Int
pathDepth = length . astPathSegments

astPathWithin :: AstPath -> AstPath -> Bool
astPathWithin (AstPath currentRoot) (AstPath currentPath) =
  currentRoot == take (length currentRoot) currentPath

wrapMiddleware ::
  RuntimeEnvironment ->
  AstPath ->
  HookPlanEntry ->
  RuntimeActionV52 ->
  RuntimeActionV52
wrapMiddleware currentEnvironment currentPath currentEntry currentChild =
  RuntimeActionV52 $ do
    appendRuntimeEvent
      currentEnvironment
      ( RuntimeHookEntered
          (hookPlanEntryRef currentEntry)
          (hookPlanEntryScope currentEntry)
          currentPath
      )
    currentOutcome <-
      case
          Map.lookup
            (hookPlanEntryRef currentEntry)
            (runtimeMiddlewareRegistryMap (environmentMiddlewareRegistry currentEnvironment)) of
        Nothing ->
          pure
            ( Failed
                RuntimeFault
                  { runtimeFaultEffect = Nothing
                  , runtimeFaultPhase = RuntimeInputPhase
                  , runtimeFaultMessage =
                      "middleware missing after preparation: "
                        ++ middlewareRefText (hookPlanEntryRef currentEntry)
                  }
            )
        Just currentRegistration -> do
          attempted <-
            try
              ( runtimeMiddlewareRegistrationFunction currentRegistration
                  MiddlewareContext
                    { middlewareContextRef = hookPlanEntryRef currentEntry
                    , middlewareContextScope = hookPlanEntryScope currentEntry
                    , middlewareContextAstPath = currentPath
                    , middlewareContextSnapshot =
                        snapshotRuntime <$> readMVar (environmentState currentEnvironment)
                    , middlewareContextOwnApplication =
                        ownApplicationAction currentEnvironment currentEntry
                    }
                  currentChild
              )
          pure
            ( case attempted of
                Left (currentException :: SomeException) ->
                  Failed
                    RuntimeFault
                      { runtimeFaultEffect = Nothing
                      , runtimeFaultPhase = RuntimeInputPhase
                      , runtimeFaultMessage = displayException currentException
                      }
                Right currentResult -> currentResult
            )
    appendRuntimeEvent
      currentEnvironment
      ( RuntimeHookExited
          (hookPlanEntryRef currentEntry)
          (hookPlanEntryScope currentEntry)
          currentPath
          currentOutcome
      )
    pure currentOutcome

ownApplicationAction ::
  RuntimeEnvironment ->
  HookPlanEntry ->
  Maybe RuntimeActionV52
ownApplicationAction currentEnvironment currentEntry =
  case
      ( hookPlanEntryApplicationOccurrence currentEntry
      , hookPlanEntryApplicationPath currentEntry
      ) of
    (Just currentOccurrence, Just currentPath) ->
      Just
        ( RuntimeActionV52 $ do
            appendRuntimeEvent
              currentEnvironment
              ( RuntimeHookOwnApplicationStarted
                  (hookPlanEntryRef currentEntry)
                  currentOccurrence
                  currentPath
              )
            executeApplicationCoreAt currentEnvironment currentPath
        )
    _ -> Nothing

executeApplication ::
  RuntimeEnvironment ->
  ApplicationOccurrence ->
  IO ContinuationOutcome
executeApplication currentEnvironment currentOccurrence = do
  let currentApplication = applicationOccurrenceApplication currentOccurrence
  commandInputOutcome <-
    executeInputBefore currentEnvironment currentOccurrence (effectApplicationCommand currentApplication)
  case commandInputOutcome of
    Succeeded -> do
      readInputOutcome <-
        executeInputBefore currentEnvironment currentOccurrence (effectApplicationRead currentApplication)
      case readInputOutcome of
        Succeeded -> do
          currentRead <- evaluateRead currentEnvironment currentOccurrence (effectApplicationRead currentApplication)
          case currentRead of
            Left currentOutcome -> pure currentOutcome
            Right currentValue -> do
              mapInputOutcome <-
                executeInputBefore currentEnvironment currentOccurrence (effectApplicationMap currentApplication)
              case mapInputOutcome of
                Succeeded -> do
                  currentMapped <-
                    evaluateMap currentEnvironment currentOccurrence (effectApplicationMap currentApplication) currentValue
                  case currentMapped of
                    Left currentOutcome -> pure currentOutcome
                    Right currentParams ->
                      evaluateCommand
                        currentEnvironment
                        currentOccurrence
                        (effectApplicationCommand currentApplication)
                        currentParams
                _ -> pure mapInputOutcome
        _ -> pure readInputOutcome
    _ -> pure commandInputOutcome

executeInputBefore ::
  RuntimeEnvironment ->
  ApplicationOccurrence ->
  SomeEffectRef ->
  IO ContinuationOutcome
executeInputBefore currentEnvironment currentOccurrence currentTarget =
  case
      Map.lookup
        (applicationOccurrenceId currentOccurrence, someEffectRefKey currentTarget)
        (environmentContinuationLookup currentEnvironment) of
    Nothing -> pure Succeeded
    Just currentTargetNode -> walk currentTargetNode
  where
    walk currentNodeId =
      case Map.lookup currentNodeId (environmentContinuationNodes currentEnvironment) of
        Nothing ->
          pure
            ( Failed
                RuntimeFault
                  { runtimeFaultEffect = Just currentTarget
                  , runtimeFaultPhase = RuntimeInputPhase
                  , runtimeFaultMessage = "continuation node missing"
                  }
            )
        Just currentNode ->
          case continuationNodePredecessor currentNode of
            Nothing -> pure Succeeded
            Just (currentContinuation, currentPredecessorId) -> do
              predecessorInput <- walk currentPredecessorId
              case predecessorInput of
                Succeeded ->
                  case Map.lookup currentPredecessorId (environmentContinuationNodes currentEnvironment) of
                    Nothing -> pure predecessorInput
                    Just currentPredecessor -> do
                      currentOutcome <-
                        executeContinuationNode
                          currentEnvironment
                          currentPredecessor
                      recordContinuation
                        currentEnvironment
                        currentContinuation
                        currentPredecessorId
                        currentNodeId
                        currentOutcome
                      pure currentOutcome
                _ -> pure predecessorInput

executeContinuationNode ::
  RuntimeEnvironment ->
  ContinuationNode ->
  IO ContinuationOutcome
executeContinuationNode currentEnvironment currentNode =
  case continuationNodeExecutionOccurrence currentNode of
    Just currentOccurrenceId ->
      case Map.lookup currentOccurrenceId (environmentOccurrencesById currentEnvironment) of
        Just currentOccurrence ->
          executeApplicationAt
            currentEnvironment
            (applicationOccurrencePath currentOccurrence)
        Nothing ->
          pure
            ( Failed
                RuntimeFault
                  { runtimeFaultEffect = Just (continuationNodeEffect currentNode)
                  , runtimeFaultPhase = RuntimeInputPhase
                  , runtimeFaultMessage = "continuation application occurrence missing"
                  }
            )
    Nothing -> do
      currentResult <-
        invokeEffect
          currentEnvironment
          (continuationNodeScope currentNode)
          (continuationNodeEffect currentNode)
          RuntimeInputPhase
          Nothing
      pure
        ( outcomeFromHandlerResult
            (continuationNodeEffect currentNode)
            RuntimeInputPhase
            currentResult
        )

evaluateRead ::
  RuntimeEnvironment ->
  ApplicationOccurrence ->
  SomeEffectRef ->
  IO (Either ContinuationOutcome RuntimeValue)
evaluateRead currentEnvironment currentOccurrence currentRef =
  case lookupEffect currentEnvironment currentRef of
    Nothing -> pure (Left (missingEffect currentRef RuntimeReadPhase))
    Just currentEffect ->
      case effectIrSpec currentEffect of
        ReadEffect currentSpec ->
          evaluateSource
            currentEnvironment
            currentOccurrence
            currentRef
            (readSpecValueSchema currentSpec)
            (readSpecSource currentSpec)
        _ -> pure (Left (wrongEffect currentRef RuntimeReadPhase))

evaluateSource ::
  RuntimeEnvironment ->
  ApplicationOccurrence ->
  SomeEffectRef ->
  ValueSchemaId ->
  ValueSourceSpec ->
  IO (Either ContinuationOutcome RuntimeValue)
evaluateSource currentEnvironment currentOccurrence currentRef currentSchema currentSource =
  case currentSource of
    ValueExternal _ -> do
      currentResult <-
        invokeEffect
          currentEnvironment
          (applicationOccurrencePath currentOccurrence)
          currentRef
          RuntimeReadPhase
          Nothing
      pure (requireValue currentRef RuntimeReadPhase currentSchema currentResult)
    ValueLiteral currentLiteral ->
      pure (Right (RuntimeValue currentSchema (show currentLiteral)))
    ValueFromR currentDependency ->
      evaluateRead currentEnvironment currentOccurrence currentDependency
    ValueRecord currentFields -> do
      currentValues <-
        mapM
          (\(currentName, currentChild) -> do
              currentValue <-
                evaluateSource currentEnvironment currentOccurrence currentRef currentSchema currentChild
              pure (currentName, currentValue)
          )
          currentFields
      pure
        ( RuntimeValue currentSchema . show
            <$> sequence
              [ fmap ((,) (paramNameText currentName) . runtimeValuePayload) currentValue
              | (currentName, currentValue) <- currentValues
              ]
        )
    ValueProduct currentItems -> do
      currentValues <-
        mapM
          (evaluateSource currentEnvironment currentOccurrence currentRef currentSchema)
          currentItems
      pure
        ( RuntimeValue currentSchema . show . map runtimeValuePayload
            <$> sequence currentValues
        )
    ValueEffSysRef currentEffSysRef ->
      pure (Right (RuntimeValue currentSchema (show currentEffSysRef)))

evaluateMap ::
  RuntimeEnvironment ->
  ApplicationOccurrence ->
  SomeEffectRef ->
  RuntimeValue ->
  IO (Either ContinuationOutcome RuntimeValue)
evaluateMap currentEnvironment currentOccurrence currentRef currentValue =
  case lookupEffect currentEnvironment currentRef of
    Nothing -> pure (Left (missingEffect currentRef RuntimeMapPhase))
    Just currentEffect ->
      case effectIrSpec currentEffect of
        MapEffect currentSpec -> do
          currentResult <-
            invokeEffect
              currentEnvironment
              (applicationOccurrencePath currentOccurrence)
              currentRef
              RuntimeMapPhase
              (Just currentValue)
          pure
            ( requireValue
                currentRef
                RuntimeMapPhase
                ( expectedMapOutputSchema
                    currentEnvironment
                    currentOccurrence
                    currentSpec
                )
                currentResult
            )
        _ -> pure (Left (wrongEffect currentRef RuntimeMapPhase))

expectedMapOutputSchema ::
  RuntimeEnvironment ->
  ApplicationOccurrence ->
  MapSpec ->
  ValueSchemaId
expectedMapOutputSchema currentEnvironment currentOccurrence currentSpec =
  case
      lookupEffect
        currentEnvironment
        ( effectApplicationCommand
            (applicationOccurrenceApplication currentOccurrence)
        ) of
    Just currentCommand ->
      case effectIrSpec currentCommand of
        CommandEffect currentCommandSpec ->
          commandSpecArgumentSchema currentCommandSpec
        _ -> mapSpecInputSchema currentSpec
    Nothing -> mapSpecInputSchema currentSpec

evaluateCommand ::
  RuntimeEnvironment ->
  ApplicationOccurrence ->
  SomeEffectRef ->
  RuntimeValue ->
  IO ContinuationOutcome
evaluateCommand currentEnvironment currentOccurrence currentRef currentValue =
  case lookupEffect currentEnvironment currentRef of
    Just currentEffect ->
      case effectIrSpec currentEffect of
        CommandEffect currentSpec -> do
          currentResult <-
            invokeEffect
              currentEnvironment
              (applicationOccurrencePath currentOccurrence)
              currentRef
              RuntimeCommandPhase
              (Just currentValue)
          pure
            ( case requireValue
                currentRef
                RuntimeCommandPhase
                (commandSpecObservationSchema currentSpec)
                currentResult of
                Left currentOutcome -> currentOutcome
                Right _ -> Succeeded
            )
        _ -> pure (wrongEffect currentRef RuntimeCommandPhase)
    Nothing -> pure (missingEffect currentRef RuntimeCommandPhase)

lookupEffect :: RuntimeEnvironment -> SomeEffectRef -> Maybe EffectIR
lookupEffect currentEnvironment currentRef =
  Map.lookup (someEffectRefKey currentRef) (environmentEffects currentEnvironment)

invokeEffect ::
  RuntimeEnvironment ->
  AstPath ->
  SomeEffectRef ->
  RuntimeHandlerPhase ->
  Maybe RuntimeValue ->
  IO RuntimeHandlerResult
invokeEffect currentEnvironment currentPath currentRef currentPhase currentValue = do
  let currentInstance =
        ExecutionInstanceId
          { executionInstanceBootRun = environmentBootRun currentEnvironment
          , executionInstanceAstPath = currentPath
          , executionInstanceEffect = currentRef
          }
  (isLeader, currentFlight) <-
    modifyMVar (environmentFlights currentEnvironment) $ \currentFlights ->
      case Map.lookup currentInstance currentFlights of
        Just currentExisting -> pure (currentFlights, (False, currentExisting))
        Nothing -> do
          currentCreated <- newEmptyMVar
          pure (Map.insert currentInstance currentCreated currentFlights, (True, currentCreated))
  if isLeader
    then do
      appendRuntimeEvent currentEnvironment (RuntimeHandlerStarted currentInstance currentPhase)
      currentResult <-
        case
            Map.lookup
              (someEffectRefKey currentRef)
              (runtimeHandlerRegistryMap (environmentHandlers currentEnvironment)) of
          Nothing ->
            pure (HandlerFailed "runtime handler missing after preparation")
          Just currentHandler -> do
            attempted <-
              try
                ( handlerRegistrationFunction currentHandler
                    RuntimeInvocation
                      { runtimeInvocationInstance = currentInstance
                      , runtimeInvocationPhase = currentPhase
                      , runtimeInvocationValue = currentValue
                      }
                )
            pure
              ( case attempted of
                  Left (currentException :: SomeException) ->
                    HandlerFailed (displayException currentException)
                  Right currentOutcome -> currentOutcome
              )
      putMVar currentFlight currentResult
      recordHandlerResult currentEnvironment currentInstance currentPhase currentResult
      pure currentResult
    else do
      appendRuntimeEvent currentEnvironment (RuntimeSingleFlightReused currentInstance)
      readMVar currentFlight

recordHandlerResult ::
  RuntimeEnvironment ->
  ExecutionInstanceId ->
  RuntimeHandlerPhase ->
  RuntimeHandlerResult ->
  IO ()
recordHandlerResult currentEnvironment currentInstance currentPhase currentResult =
  modifyMVar_ (environmentState currentEnvironment) $ \currentState ->
    pure
      currentState
        { mutableStatuses =
            Map.insert
              currentInstance
              (outcomeFromHandlerResult (executionInstanceEffect currentInstance) currentPhase currentResult)
              (mutableStatuses currentState)
        , mutableObservations =
            case currentResult of
              HandlerSucceeded (Just currentValue) ->
                Map.insert currentInstance currentValue (mutableObservations currentState)
              _ -> mutableObservations currentState
        , mutableEvents =
            mutableEvents currentState
              ++ [RuntimeHandlerFinished currentInstance currentPhase currentResult]
              ++ case currentResult of
                HandlerSucceeded (Just currentValue) ->
                  [RuntimeValueProduced currentInstance currentPhase (runtimeValueSchema currentValue)]
                _ -> []
        }

appendRuntimeEvent :: RuntimeEnvironment -> RuntimeEvent -> IO ()
appendRuntimeEvent currentEnvironment currentEvent =
  modifyMVar_ (environmentState currentEnvironment) $ \currentState ->
    pure currentState {mutableEvents = mutableEvents currentState ++ [currentEvent]}

recordContinuation ::
  RuntimeEnvironment ->
  ContinuationId ->
  InputNodeId ->
  InputNodeId ->
  ContinuationOutcome ->
  IO ()
recordContinuation currentEnvironment currentContinuation currentFrom currentTo currentOutcome =
  modifyMVar_ (environmentState currentEnvironment) $ \currentState ->
    pure
      currentState
        { mutableEvents =
            mutableEvents currentState
              ++ [ RuntimeContinuationAdvanced
                     currentContinuation
                     currentFrom
                     currentTo
                     currentOutcome
                 ]
        , mutableTrace = mutableTrace currentState ++ [currentContinuation]
        }

requireValue ::
  SomeEffectRef ->
  RuntimeHandlerPhase ->
  ValueSchemaId ->
  RuntimeHandlerResult ->
  Either ContinuationOutcome RuntimeValue
requireValue currentRef currentPhase expectedSchema currentResult =
  case currentResult of
    HandlerSucceeded (Just currentValue)
      | runtimeValueSchema currentValue == expectedSchema -> Right currentValue
      | otherwise ->
          Left
            ( Failed
                RuntimeFault
                  { runtimeFaultEffect = Just currentRef
                  , runtimeFaultPhase = currentPhase
                  , runtimeFaultMessage =
                      "handler value schema mismatch: expected "
                        ++ show expectedSchema
                        ++ ", received "
                        ++ show (runtimeValueSchema currentValue)
                  }
            )
    HandlerSucceeded Nothing ->
      Left
        ( Failed
            RuntimeFault
              { runtimeFaultEffect = Just currentRef
              , runtimeFaultPhase = currentPhase
              , runtimeFaultMessage = "handler did not produce a required value"
              }
        )
    _ -> Left (outcomeFromHandlerResult currentRef currentPhase currentResult)

outcomeFromHandlerResult ::
  SomeEffectRef ->
  RuntimeHandlerPhase ->
  RuntimeHandlerResult ->
  ContinuationOutcome
outcomeFromHandlerResult currentRef currentPhase currentResult =
  case currentResult of
    HandlerSucceeded _ -> Succeeded
    HandlerFailed currentMessage ->
      Failed (RuntimeFault (Just currentRef) currentPhase currentMessage)
    HandlerCancelled currentMessage -> Cancelled currentMessage
    HandlerSuspended currentMessage -> Suspended currentMessage

missingEffect :: SomeEffectRef -> RuntimeHandlerPhase -> ContinuationOutcome
missingEffect currentRef currentPhase =
  Failed
    RuntimeFault
      { runtimeFaultEffect = Just currentRef
      , runtimeFaultPhase = currentPhase
      , runtimeFaultMessage = "effect is absent from the runtime registry"
      }

wrongEffect :: SomeEffectRef -> RuntimeHandlerPhase -> ContinuationOutcome
wrongEffect currentRef currentPhase =
  Failed
    RuntimeFault
      { runtimeFaultEffect = Just currentRef
      , runtimeFaultPhase = currentPhase
      , runtimeFaultMessage = "effect kind does not match runtime phase"
      }

snapshotRuntime :: MutableRuntime -> RuntimeSnapshot
snapshotRuntime currentState =
  RuntimeSnapshot
    { runtimeSnapshotStatuses = Map.toAscList (mutableStatuses currentState)
    , runtimeSnapshotObservations = Map.toAscList (mutableObservations currentState)
    , runtimeSnapshotEvents = mutableEvents currentState
    , runtimeSnapshotDiagnosis =
        RuntimeDiagnosis
          { runtimeDiagnosisInputTrace = mutableTrace currentState
          , runtimeDiagnosisFailures =
              [ currentFailure
              | Failed currentFailure <- Map.elems (mutableStatuses currentState)
              ]
          }
    }
