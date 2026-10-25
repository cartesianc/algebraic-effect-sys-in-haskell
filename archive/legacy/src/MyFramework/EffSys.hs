module MyFramework.EffSys
  ( EffSysError (..)
  , EffSysIR (..)
  , EffSysRef (..)
  , EffSysRegistryId (..)
  , EffSysSnapshot (..)
  , EffSysSnapshotEntry (..)
  , EffSysStats (..)
  , EffSysView
  , buildEffSysIR
  , declaredEffSysRef
  , effSysSnapshotFromRuntime
  , effSysView
  , queryEffSysEffect
  , queryEffSysFailure
  , queryEffSysInputPipeline
  , queryEffSysObservation
  , queryEffSysState
  , queryEffSysStats
  , readEffSysView
  , validateEffSysReferences
  ) where

import Data.IORef
  ( IORef
  , readIORef
  )
import Data.List
  ( nub
  , sort
  , sortOn
  )
import qualified Data.Map.Strict as Map

import MyFramework.Effect
import MyFramework.EffSys.Types
import MyFramework.Graph
import MyFramework.Runtime.V52
import MyFramework.TrustBase.Digest
  ( sha256
  )

data EffSysError
  = EffSysRegistryMismatch EffSysRegistryId EffSysRegistryId
  | EffSysAstRootMissing String
  | EffSysAstRootAmbiguous String [AstPath]
  | EffSysReferenceOutsideScope EffSysRef AstPath
  deriving (Eq, Ord, Read, Show)

-- | Static, closure-free view of one scope.  Dependency occurrences reached
-- through InputGraph remain explicit alongside the AST subtree.
data EffSysIR = EffSysIR
  { effSysIrRef :: EffSysRef
  , effSysIrResolvedRoot :: AstPath
  , effSysIrAstGraph :: AstGraph
  , effSysIrInputGraph :: InputGraph
  , effSysIrValueGraph :: ValueGraph
  , effSysIrContinuationPlan :: ContinuationPlan
  , effSysIrEffects :: EffectRegistry
  , effSysIrTransforms :: TransformRegistry
  , effSysIrOccurrences :: [ApplicationOccurrence]
  , effSysIrDigest :: String
  }
  deriving (Eq, Ord, Read, Show)

data EffSysSnapshotEntry = EffSysSnapshotEntry
  { effSysSnapshotPath :: AstPath
  , effSysSnapshotEffect :: SomeEffectRef
  , effSysSnapshotStatus :: ContinuationOutcome
  , effSysSnapshotObservation :: Maybe RuntimeValue
  , effSysSnapshotFailure :: Maybe RuntimeFault
  }
  deriving (Eq, Ord, Read, Show)

data EffSysSnapshot = EffSysSnapshot
  { effSysSnapshotRef :: EffSysRef
  , effSysSnapshotRevision :: StateRevision
  , effSysSnapshotEntries :: [EffSysSnapshotEntry]
  }
  deriving (Eq, Ord, Read, Show)

data EffSysStats = EffSysStats
  { effSysStatsDormant :: Int
  , effSysStatsSucceeded :: Int
  , effSysStatsFailed :: Int
  , effSysStatsCancelled :: Int
  , effSysStatsSuspended :: Int
  }
  deriving (Eq, Ord, Read, Show)

-- | The getter is the live boundary.  Calling it reads a projection and has
-- no path to Runtime demand or Handler registration.
data EffSysView = EffSysView
  { effSysViewRef :: EffSysRef
  , effSysViewSnapshotRef :: IORef EffSysSnapshot
  }

declaredEffSysRef :: String -> String -> EffSysRef
declaredEffSysRef currentRegistry currentAstRoot =
  EffSysRef
    { effSysRefAstRoot = currentAstRoot
    , effSysRefRegistry = EffSysRegistryId currentRegistry
    }

buildEffSysIR ::
  EffSysRegistryId ->
  EffectRegistry ->
  TransformRegistry ->
  CompiledGraphs ->
  ContinuationPlan ->
  EffSysRef ->
  Either [EffSysError] EffSysIR
buildEffSysIR currentRegistry currentEffects currentTransforms currentGraphs currentPlan currentRef = do
  currentRoot <- resolveEffSysRoot currentRegistry currentGraphs currentRef
  let currentIr = scopeIr currentRoot
  pure currentIr {effSysIrDigest = effSysDigest currentIr}
  where
    scopeIr currentRoot =
      EffSysIR
        { effSysIrRef = currentRef
        , effSysIrResolvedRoot = currentRoot
        , effSysIrAstGraph = scopedAstGraph currentRoot (compiledAstGraph currentGraphs)
        , effSysIrInputGraph = scopedInputGraph reachableOccurrences (compiledInputGraph currentGraphs)
        , effSysIrValueGraph = scopedValueGraph reachableOccurrences (compiledValueGraph currentGraphs)
        , effSysIrContinuationPlan = scopedContinuationPlan reachableOccurrences currentPlan
        , effSysIrEffects = scopedEffects reachableOccurrences currentEffects currentGraphs
        , effSysIrTransforms = scopedTransforms reachableOccurrences currentEffects currentTransforms currentGraphs
        , effSysIrOccurrences =
            sortOn applicationOccurrenceId
              [ currentOccurrence
              | currentOccurrence <- compiledOccurrences currentGraphs
              , applicationOccurrenceId currentOccurrence `elem` reachableOccurrences
              ]
        , effSysIrDigest = ""
        }
      where
        initialOccurrences =
          [ applicationOccurrenceId currentOccurrence
          | currentOccurrence <- compiledOccurrences currentGraphs
          , pathWithin currentRoot (applicationOccurrencePath currentOccurrence)
          ]
        reachableOccurrences =
          occurrenceClosure currentPlan initialOccurrences

effSysDigest :: EffSysIR -> String
effSysDigest currentIr =
  sha256
    ( show
        ( effSysIrRef currentIr
        , effSysIrResolvedRoot currentIr
        , effSysIrAstGraph currentIr
        , effSysIrInputGraph currentIr
        , effSysIrValueGraph currentIr
        , effSysIrContinuationPlan currentIr
        , effSysIrEffects currentIr
        , effSysIrTransforms currentIr
        , effSysIrOccurrences currentIr
        )
    )

validateEffSysReferences ::
  EffSysRegistryId ->
  EffectRegistry ->
  CompiledGraphs ->
  [EffSysError]
validateEffSysReferences currentRegistry currentEffects currentGraphs =
  sort . nub . concatMap validateOccurrence $
    compiledOccurrences currentGraphs
  where
    effectIndex =
      Map.fromList
        [ (someEffectRefKey (effectIrRef currentEffect), currentEffect)
        | currentEffect <- effectRegistryEffects currentEffects
        ]
    validateOccurrence currentOccurrence =
      concatMap
        (validateRefAt (applicationOccurrencePath currentOccurrence))
        (applicationEffSysRefs effectIndex currentOccurrence)
    validateRefAt currentPath currentRef =
      case resolveEffSysRoot currentRegistry currentGraphs currentRef of
        Left currentErrors -> currentErrors
        Right currentRoot ->
          [EffSysReferenceOutsideScope currentRef currentPath | not (pathWithin currentRoot currentPath)]

resolveEffSysRoot ::
  EffSysRegistryId ->
  CompiledGraphs ->
  EffSysRef ->
  Either [EffSysError] AstPath
resolveEffSysRoot currentRegistry currentGraphs currentRef
  | effSysRefRegistry currentRef /= currentRegistry =
      Left [EffSysRegistryMismatch currentRegistry (effSysRefRegistry currentRef)]
  | otherwise =
      case currentCandidates of
        [] -> Left [EffSysAstRootMissing (effSysRefAstRoot currentRef)]
        [currentRoot] -> Right currentRoot
        _ -> Left [EffSysAstRootAmbiguous (effSysRefAstRoot currentRef) currentCandidates]
  where
    currentCandidates =
      sort
        [ astGraphNodePath currentNode
        | currentNode <- astGraphNodes (compiledAstGraph currentGraphs)
        , pathTerminalKey (astGraphNodePath currentNode) == effSysRefAstRoot currentRef
        ]

pathTerminalKey :: AstPath -> String
pathTerminalKey (AstPath currentSegments) =
  case reverse currentSegments of
    currentSegment : _ -> astNodeKeyText (astPathSegmentKey currentSegment)
    [] -> ""

pathWithin :: AstPath -> AstPath -> Bool
pathWithin (AstPath currentRoot) (AstPath currentPath) =
  currentRoot == take (length currentRoot) currentPath

applicationEffSysRefs ::
  Map.Map EffectKey EffectIR ->
  ApplicationOccurrence ->
  [EffSysRef]
applicationEffSysRefs effectIndex currentOccurrence =
  case
      Map.lookup
        ( someEffectRefKey
            ( effectApplicationRead
                (applicationOccurrenceApplication currentOccurrence)
            )
        )
        effectIndex of
    Just currentEffect ->
      case effectIrSpec currentEffect of
        ReadEffect currentRead -> valueEffSysRefs (readSpecSource currentRead)
        _ -> []
    Nothing -> []

valueEffSysRefs :: ValueSourceSpec -> [EffSysRef]
valueEffSysRefs currentSource =
  case currentSource of
    ValueExternal _ -> []
    ValueLiteral _ -> []
    ValueFromR _ -> []
    ValueRecord currentFields -> concatMap (valueEffSysRefs . snd) currentFields
    ValueProduct currentItems -> concatMap valueEffSysRefs currentItems
    ValueEffSysRef currentRef -> [currentRef]

occurrenceClosure ::
  ContinuationPlan ->
  [ApplicationOccurrenceId] ->
  [ApplicationOccurrenceId]
occurrenceClosure currentPlan initialOccurrences =
  settle (sort (nub initialOccurrences))
  where
    settle currentOccurrences =
      let nextOccurrences =
            sort . nub $
              currentOccurrences
                ++ [ currentDependency
                   | currentNode <- continuationPlanNodes currentPlan
                   , continuationNodeOccurrence currentNode `elem` currentOccurrences
                   , Just currentDependency <- [continuationNodeExecutionOccurrence currentNode]
                   ]
       in if nextOccurrences == currentOccurrences
            then currentOccurrences
            else settle nextOccurrences

scopedAstGraph :: AstPath -> AstGraph -> AstGraph
scopedAstGraph currentRoot currentGraph =
  AstGraph
    { astGraphRoot = currentRoot
    , astGraphNodes =
        filter (pathWithin currentRoot . astGraphNodePath) (astGraphNodes currentGraph)
    , astGraphEdges =
        filter
          (\currentEdge ->
              pathWithin currentRoot (astGraphEdgeParent currentEdge)
                && pathWithin currentRoot (astGraphEdgeChild currentEdge)
          )
          (astGraphEdges currentGraph)
    }

scopedInputGraph :: [ApplicationOccurrenceId] -> InputGraph -> InputGraph
scopedInputGraph currentOccurrences currentGraph =
  InputGraph
    { inputGraphNodes = currentNodes
    , inputGraphEdges =
        [ currentEdge
        | currentEdge <- inputGraphEdges currentGraph
        , inputEdgePredecessor currentEdge `elem` currentNodeIds
        , inputEdgeTarget currentEdge `elem` currentNodeIds
        ]
    }
  where
    currentNodes =
      [ currentNode
      | currentNode <- inputGraphNodes currentGraph
      , inputNodeOccurrence currentNode `elem` currentOccurrences
      ]
    currentNodeIds = map inputNodeId currentNodes

scopedValueGraph :: [ApplicationOccurrenceId] -> ValueGraph -> ValueGraph
scopedValueGraph currentOccurrences currentGraph =
  ValueGraph
    { valueGraphNodes = currentNodes
    , valueGraphEdges =
        [ currentEdge
        | currentEdge <- valueGraphEdges currentGraph
        , valueEdgeFrom currentEdge `elem` currentNodeIds
        , valueEdgeTo currentEdge `elem` currentNodeIds
        ]
    }
  where
    currentNodes =
      [ currentNode
      | currentNode <- valueGraphNodes currentGraph
      , valueNodeOccurrence currentNode `elem` currentOccurrences
      ]
    currentNodeIds = map valueNodeId currentNodes

scopedContinuationPlan ::
  [ApplicationOccurrenceId] ->
  ContinuationPlan ->
  ContinuationPlan
scopedContinuationPlan currentOccurrences currentPlan =
  ContinuationPlan
    { continuationPlanNodes = currentNodes
    , continuationPlanSegments =
        [ currentSegment
        | currentSegment <- continuationPlanSegments currentPlan
        , continuationSegmentTarget currentSegment `elem` currentNodeIds
        ]
    }
  where
    currentNodes =
      [ currentNode
      | currentNode <- continuationPlanNodes currentPlan
      , continuationNodeOccurrence currentNode `elem` currentOccurrences
      ]
    currentNodeIds = map continuationNodeId currentNodes

scopedEffects ::
  [ApplicationOccurrenceId] ->
  EffectRegistry ->
  CompiledGraphs ->
  EffectRegistry
scopedEffects currentOccurrences currentEffects currentGraphs =
  EffectRegistry
    [ currentEffect
    | currentEffect <- effectRegistryEffects currentEffects
    , someEffectRefKey (effectIrRef currentEffect) `elem` currentKeys
    ]
  where
    currentKeys =
      nub
        ( [ someEffectRefKey (inputNodeEffect currentNode)
          | currentNode <- inputGraphNodes (compiledInputGraph currentGraphs)
          , inputNodeOccurrence currentNode `elem` currentOccurrences
          ]
            ++ [ someEffectRefKey (valueNodeEffect currentNode)
               | currentNode <- valueGraphNodes (compiledValueGraph currentGraphs)
               , valueNodeOccurrence currentNode `elem` currentOccurrences
               ]
        )

scopedTransforms ::
  [ApplicationOccurrenceId] ->
  EffectRegistry ->
  TransformRegistry ->
  CompiledGraphs ->
  TransformRegistry
scopedTransforms currentOccurrences currentEffects currentTransforms currentGraphs =
  TransformRegistry
    [ currentTransform
    | currentTransform <- transformRegistryDecls currentTransforms
    , transformDeclRef currentTransform `elem` currentRefs
    ]
  where
    EffectRegistry currentScopedEffects =
      scopedEffects currentOccurrences currentEffects currentGraphs
    currentRefs =
      [ mapSpecTransform currentMap
      | currentEffect <- currentScopedEffects
      , MapEffect currentMap <- [effectIrSpec currentEffect]
      ]

effSysSnapshotFromRuntime :: EffSysIR -> UnifiedRuntimeRun -> EffSysSnapshot
effSysSnapshotFromRuntime currentIr currentRun =
  EffSysSnapshot
    { effSysSnapshotRef = effSysIrRef currentIr
    , effSysSnapshotRevision = StateRevision 0
    , effSysSnapshotEntries =
        sortOn entryKey
          [ EffSysSnapshotEntry
              { effSysSnapshotPath = executionInstanceAstPath currentInstance
              , effSysSnapshotEffect = executionInstanceEffect currentInstance
              , effSysSnapshotStatus = currentStatus
              , effSysSnapshotObservation = Map.lookup currentInstance observationIndex
              , effSysSnapshotFailure =
                  case currentStatus of
                    Failed currentFailure -> Just currentFailure
                    _ -> Nothing
              }
          | (currentInstance, currentStatus) <- runtimeSnapshotStatuses currentSnapshot
          , executionInScope currentInstance
          ]
    }
  where
    currentSnapshot = unifiedRuntimeSnapshot currentRun
    observationIndex = Map.fromList (runtimeSnapshotObservations currentSnapshot)
    scopedPaths = map applicationOccurrencePath (effSysIrOccurrences currentIr)
    scopedKeys = map (someEffectRefKey . effectIrRef) (effectRegistryEffects (effSysIrEffects currentIr))
    executionInScope currentInstance =
      executionInstanceAstPath currentInstance `elem` scopedPaths
        && someEffectRefKey (executionInstanceEffect currentInstance) `elem` scopedKeys
    entryKey currentEntry =
      (effSysSnapshotPath currentEntry, effSysSnapshotEffect currentEntry)

effSysView :: EffSysRef -> IORef EffSysSnapshot -> EffSysView
effSysView currentRef currentSnapshotRef =
  EffSysView
    { effSysViewRef = currentRef
    , effSysViewSnapshotRef = currentSnapshotRef
    }

readEffSysView :: EffSysView -> IO EffSysSnapshot
readEffSysView = readIORef . effSysViewSnapshotRef

queryEffSysEffect :: EffectKey -> EffSysIR -> Maybe EffectIR
queryEffSysEffect currentKey currentIr =
  case
      [ currentEffect
      | currentEffect <- effectRegistryEffects (effSysIrEffects currentIr)
      , someEffectRefKey (effectIrRef currentEffect) == currentKey
      ] of
    currentEffect : _ -> Just currentEffect
    [] -> Nothing

queryEffSysInputPipeline :: EffectKey -> EffSysIR -> [ContinuationNode]
queryEffSysInputPipeline currentKey currentIr =
  sortOn continuationNodeId
    [ currentNode
    | currentNode <- continuationPlanNodes (effSysIrContinuationPlan currentIr)
    , someEffectRefKey (continuationNodeEffect currentNode) == currentKey
    ]

queryEffSysState ::
  AstPath ->
  EffectKey ->
  EffSysSnapshot ->
  Maybe ContinuationOutcome
queryEffSysState currentPath currentKey currentSnapshot =
  effSysSnapshotStatus
    <$> findSnapshotEntry currentPath currentKey currentSnapshot

queryEffSysObservation ::
  AstPath ->
  EffectKey ->
  EffSysSnapshot ->
  Maybe RuntimeValue
queryEffSysObservation currentPath currentKey currentSnapshot =
  findSnapshotEntry currentPath currentKey currentSnapshot
    >>= effSysSnapshotObservation

queryEffSysFailure ::
  AstPath ->
  EffectKey ->
  EffSysSnapshot ->
  Maybe RuntimeFault
queryEffSysFailure currentPath currentKey currentSnapshot =
  findSnapshotEntry currentPath currentKey currentSnapshot
    >>= effSysSnapshotFailure

findSnapshotEntry ::
  AstPath ->
  EffectKey ->
  EffSysSnapshot ->
  Maybe EffSysSnapshotEntry
findSnapshotEntry currentPath currentKey currentSnapshot =
  case
      [ currentEntry
      | currentEntry <- effSysSnapshotEntries currentSnapshot
      , effSysSnapshotPath currentEntry == currentPath
      , someEffectRefKey (effSysSnapshotEffect currentEntry) == currentKey
      ] of
    currentEntry : _ -> Just currentEntry
    [] -> Nothing

queryEffSysStats :: EffSysIR -> EffSysSnapshot -> EffSysStats
queryEffSysStats currentIr currentSnapshot =
  EffSysStats
    { effSysStatsDormant = max 0 (declaredCount - length currentEntries)
    , effSysStatsSucceeded = length [() | currentEntry <- currentEntries, effSysSnapshotStatus currentEntry == Succeeded]
    , effSysStatsFailed = length [() | currentEntry <- currentEntries, Failed _ <- [effSysSnapshotStatus currentEntry]]
    , effSysStatsCancelled = length [() | currentEntry <- currentEntries, Cancelled _ <- [effSysSnapshotStatus currentEntry]]
    , effSysStatsSuspended = length [() | currentEntry <- currentEntries, Suspended _ <- [effSysSnapshotStatus currentEntry]]
    }
  where
    currentEntries = effSysSnapshotEntries currentSnapshot
    declaredCount =
      length . nub $
        [ (inputNodeScope currentNode, inputNodeEffect currentNode)
        | currentNode <- inputGraphNodes (effSysIrInputGraph currentIr)
        ]
          ++ [ (valueNodeScope currentNode, valueNodeEffect currentNode)
             | currentNode <- valueGraphNodes (effSysIrValueGraph currentIr)
             ]
