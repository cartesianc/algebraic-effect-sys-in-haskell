module MyFramework.Graph
  ( ApplicationOccurrence (..)
  , ApplicationOccurrenceId (..)
  , AstBranchKind (..)
  , AstGraph (..)
  , AstGraphEdge (..)
  , AstGraphNode (..)
  , AstGraphNodeKind (..)
  , AstNodeKey (..)
  , AstPath (..)
  , AstPathSegment (..)
  , AstPlan (..)
  , CompiledGraphs (..)
  , ContinuationId (..)
  , GraphError (..)
  , InputEdge (..)
  , InputGraph (..)
  , InputNode (..)
  , InputNodeId (..)
  , ValueEdge (..)
  , ValueEdgeKind (..)
  , ValueGraph (..)
  , ValueNode (..)
  , ValueNodeId (..)
  , ValueNodeRole (..)
  , compileGraphs
  , renderAstPath
  ) where

import Data.List
  ( group
  , nub
  , sort
  , sortOn
  )
import qualified Data.Map.Strict as Map

import MyFramework.Effect
import MyFramework.TrustBase.Digest
  ( sha256
  )

newtype AstNodeKey = AstNodeKey
  { astNodeKeyText :: String
  }
  deriving (Eq, Ord, Read, Show)

data AstBranchKind
  = AstChain
  | AstParallel
  | AstFallback
  | AstRace
  | AstChoice
  | AstWait
  | AstLoop
  | AstMiddleware
  | AstCallback
  | AstSuspense
  | AstContext
  deriving (Eq, Ord, Read, Show)

-- | Serializable resolved scheduling tree.  The AST contains applications;
-- it contains no input or value dependency edges.
data AstPlan
  = AstPlanBranch AstNodeKey AstBranchKind [AstPlan]
  | AstPlanApplication AstNodeKey EffectApplication
  deriving (Eq, Ord, Read, Show)

data AstPathSegment = AstPathSegment
  { astPathSegmentKey :: AstNodeKey
  , astPathSegmentOrdinal :: Int
  }
  deriving (Eq, Ord, Read, Show)

newtype AstPath = AstPath
  { astPathSegments :: [AstPathSegment]
  }
  deriving (Eq, Ord, Read, Show)

renderAstPath :: AstPath -> String
renderAstPath (AstPath currentSegments) =
  concatMap renderSegment currentSegments
  where
    renderSegment currentSegment =
      let currentKey = astNodeKeyText (astPathSegmentKey currentSegment)
       in show (length currentKey)
            ++ ":"
            ++ currentKey
            ++ "#"
            ++ show (astPathSegmentOrdinal currentSegment)

newtype ApplicationOccurrenceId = ApplicationOccurrenceId
  { applicationOccurrenceIdText :: String
  }
  deriving (Eq, Ord, Read, Show)

data ApplicationOccurrence = ApplicationOccurrence
  { applicationOccurrenceId :: ApplicationOccurrenceId
  , applicationOccurrencePath :: AstPath
  , applicationOccurrenceApplication :: EffectApplication
  }
  deriving (Eq, Ord, Read, Show)

data AstGraphNodeKind
  = AstGraphBranch AstBranchKind
  | AstGraphApplication ApplicationOccurrenceId
  deriving (Eq, Ord, Read, Show)

data AstGraphNode = AstGraphNode
  { astGraphNodePath :: AstPath
  , astGraphNodeKind :: AstGraphNodeKind
  }
  deriving (Eq, Ord, Read, Show)

data AstGraphEdge = AstGraphEdge
  { astGraphEdgeParent :: AstPath
  , astGraphEdgeChild :: AstPath
  }
  deriving (Eq, Ord, Read, Show)

data AstGraph = AstGraph
  { astGraphRoot :: AstPath
  , astGraphNodes :: [AstGraphNode]
  , astGraphEdges :: [AstGraphEdge]
  }
  deriving (Eq, Ord, Read, Show)

newtype InputNodeId = InputNodeId
  { inputNodeIdText :: String
  }
  deriving (Eq, Ord, Read, Show)

data InputNode = InputNode
  { inputNodeId :: InputNodeId
  , inputNodeOccurrence :: ApplicationOccurrenceId
  , inputNodeScope :: AstPath
  , inputNodeEffect :: SomeEffectRef
  }
  deriving (Eq, Ord, Read, Show)

newtype ContinuationId = ContinuationId
  { continuationIdText :: String
  }
  deriving (Eq, Ord, Read, Show)

-- | This edge contains lifecycle continuation identity only.  No business
-- value or schema travels through InputGraph.
data InputEdge = InputEdge
  { inputEdgePredecessor :: InputNodeId
  , inputEdgeTarget :: InputNodeId
  , inputEdgeContinuation :: ContinuationId
  }
  deriving (Eq, Ord, Read, Show)

data InputGraph = InputGraph
  { inputGraphNodes :: [InputNode]
  , inputGraphEdges :: [InputEdge]
  }
  deriving (Eq, Ord, Read, Show)

newtype ValueNodeId = ValueNodeId
  { valueNodeIdText :: String
  }
  deriving (Eq, Ord, Read, Show)

data ValueNodeRole
  = ValueReadRole
  | ValueMapRole
  | ValueCommandParamsRole
  | ValueObservationRole
  deriving (Eq, Ord, Read, Show)

data ValueNode = ValueNode
  { valueNodeId :: ValueNodeId
  , valueNodeOccurrence :: ApplicationOccurrenceId
  , valueNodeScope :: AstPath
  , valueNodeEffect :: SomeEffectRef
  , valueNodeRole :: ValueNodeRole
  }
  deriving (Eq, Ord, Read, Show)

data ValueEdgeKind
  = ValueReadDependency
  | ValueMapInput
  | ValueParamBinding
  | ValueObservation
  deriving (Eq, Ord, Read, Show)

data ValueEdge = ValueEdge
  { valueEdgeFrom :: ValueNodeId
  , valueEdgeTo :: ValueNodeId
  , valueEdgeKind :: ValueEdgeKind
  }
  deriving (Eq, Ord, Read, Show)

data ValueGraph = ValueGraph
  { valueGraphNodes :: [ValueNode]
  , valueGraphEdges :: [ValueEdge]
  }
  deriving (Eq, Ord, Read, Show)

data CompiledGraphs = CompiledGraphs
  { compiledAstGraph :: AstGraph
  , compiledInputGraph :: InputGraph
  , compiledValueGraph :: ValueGraph
  , compiledOccurrences :: [ApplicationOccurrence]
  }
  deriving (Eq, Ord, Read, Show)

data GraphError
  = DuplicateEffectKey [EffectKey]
  | DuplicateTransformRef [TransformRef]
  | EffectKindSpecMismatch EffectKey EffectKind
  | EffectReferenceMissing EffectKey
  | EffectReferenceKindMismatch EffectKey EffectKind EffectKind
  | EffectInputCycle [EffectKey]
  | ValueReferenceMustBeR EffectKey EffectKind
  | ValueReferenceCycle [EffectKey]
  | ApplicationDefinitionConflict ApplicationKey
  | ApplicationCommandKindInvalid ApplicationKey EffectKind
  | ApplicationMapMissing ApplicationKey EffectKey
  | ApplicationReadMissing ApplicationKey EffectKey
  | TransformMissing ApplicationKey TransformRef
  | TransformInputMismatch ApplicationKey
  | TransformOutputMismatch ApplicationKey
  | ApplicationInputSchemaMismatch ApplicationKey
  | ApplicationParamArityMismatch ApplicationKey Int Int
  | ApplicationParamMismatch ApplicationKey [ParamSpec] [ParamSpec]
  deriving (Eq, Ord, Read, Show)

compileGraphs ::
  EffectRegistry ->
  TransformRegistry ->
  AstPlan ->
  Either [GraphError] CompiledGraphs
compileGraphs currentRegistry currentTransforms currentPlan
  | null currentErrors =
      Right
        CompiledGraphs
          { compiledAstGraph = currentAstGraph
          , compiledInputGraph = buildInputGraph effectIndex occurrences
          , compiledValueGraph = buildValueGraph effectIndex occurrences
          , compiledOccurrences = occurrences
          }
  | otherwise = Left currentErrors
  where
    currentEffects = effectRegistryEffects currentRegistry
    currentTransformDecls = transformRegistryDecls currentTransforms
    effectIndex =
      Map.fromList
        [ (someEffectRefKey (effectIrRef currentEffect), currentEffect)
        | currentEffect <- currentEffects
        ]
    transformIndex =
      Map.fromList
        [ (transformDeclRef currentTransform, currentTransform)
        | currentTransform <- currentTransformDecls
        ]
    (currentAstGraph, occurrences) = flattenAst currentPlan
    currentApplications = map applicationOccurrenceApplication occurrences
    currentErrors =
      sort . nub $
        duplicateRegistryErrors currentEffects currentTransformDecls
          ++ concatMap validateEffectSpec currentEffects
          ++ concatMap (validateEffectReferences effectIndex) currentEffects
          ++ map EffectInputCycle (inputCycles effectIndex)
          ++ map ValueReferenceCycle (valueCycles effectIndex)
          ++ applicationDefinitionErrors currentApplications
          ++ concatMap
            (validateApplication effectIndex transformIndex)
            currentApplications

duplicateRegistryErrors :: [EffectIR] -> [TransformDecl] -> [GraphError]
duplicateRegistryErrors currentEffects currentTransforms =
  [DuplicateEffectKey currentDuplicates | not (null currentDuplicates)]
    ++ [DuplicateTransformRef transformDuplicates | not (null transformDuplicates)]
  where
    currentDuplicates =
      duplicates (map (someEffectRefKey . effectIrRef) currentEffects)
    transformDuplicates =
      duplicates (map transformDeclRef currentTransforms)

validateEffectSpec :: EffectIR -> [GraphError]
validateEffectSpec currentEffect =
  [ EffectKindSpecMismatch currentKey currentKind
  | not (kindMatchesSpec currentKind (effectIrSpec currentEffect))
  ]
  where
    currentRef = effectIrRef currentEffect
    currentKey = someEffectRefKey currentRef
    currentKind = someEffectRefKind currentRef

kindMatchesSpec :: EffectKind -> EffectSpec -> Bool
kindMatchesSpec currentKind currentSpec =
  case (currentKind, currentSpec) of
    (C, CommandEffect _) -> True
    (U, CommandEffect _) -> True
    (R, ReadEffect _) -> True
    (D, CommandEffect _) -> True
    (E, CommandEffect _) -> True
    (MAP, MapEffect _) -> True
    _ -> False

validateEffectReferences ::
  Map.Map EffectKey EffectIR ->
  EffectIR ->
  [GraphError]
validateEffectReferences effectIndex currentEffect =
  inputErrors ++ sourceErrors
  where
    inputErrors =
      maybe [] (validateRef effectIndex) (effectIrInput currentEffect)
    sourceErrors =
      case effectIrSpec currentEffect of
        ReadEffect currentRead ->
          concatMap
            (validateRRef effectIndex)
            (valueSourceRefs (readSpecSource currentRead))
        _ -> []

validateRef ::
  Map.Map EffectKey EffectIR ->
  SomeEffectRef ->
  [GraphError]
validateRef effectIndex currentRef =
  case Map.lookup currentKey effectIndex of
    Nothing -> [EffectReferenceMissing currentKey]
    Just currentEffect
      | actualKind /= expectedKind ->
          [EffectReferenceKindMismatch currentKey expectedKind actualKind]
      | otherwise -> []
      where
        actualKind = someEffectRefKind (effectIrRef currentEffect)
  where
    currentKey = someEffectRefKey currentRef
    expectedKind = someEffectRefKind currentRef

validateRRef ::
  Map.Map EffectKey EffectIR ->
  SomeEffectRef ->
  [GraphError]
validateRRef effectIndex currentRef =
  case Map.lookup currentKey effectIndex of
    Nothing -> [EffectReferenceMissing currentKey]
    Just currentEffect
      | actualKind /= R -> [ValueReferenceMustBeR currentKey actualKind]
      | expectedKind /= R -> [ValueReferenceMustBeR currentKey expectedKind]
      | otherwise -> []
      where
        actualKind = someEffectRefKind (effectIrRef currentEffect)
  where
    currentKey = someEffectRefKey currentRef
    expectedKind = someEffectRefKind currentRef

applicationDefinitionErrors :: [EffectApplication] -> [GraphError]
applicationDefinitionErrors currentApplications =
  [ ApplicationDefinitionConflict currentKey
  | currentGroup <- groupOn effectApplicationKey currentApplications
  , let currentKey = effectApplicationKey (head currentGroup)
  , length (nub currentGroup) > 1
  ]

validateApplication ::
  Map.Map EffectKey EffectIR ->
  Map.Map TransformRef TransformDecl ->
  EffectApplication ->
  [GraphError]
validateApplication effectIndex transformIndex currentApplication =
  commandRefErrors
    ++ mapRefErrors
    ++ readRefErrors
    ++ alignmentErrors
  where
    currentKey = effectApplicationKey currentApplication
    currentCommandRef = effectApplicationCommand currentApplication
    currentMapRef = effectApplicationMap currentApplication
    currentReadRef = effectApplicationRead currentApplication
    commandRefErrors =
      validateRef effectIndex currentCommandRef
        ++ [ ApplicationCommandKindInvalid currentKey currentKind
           | let currentKind = someEffectRefKind currentCommandRef
           , currentKind `notElem` [C, U, D, E]
           ]
    mapRefErrors =
      case Map.lookup (someEffectRefKey currentMapRef) effectIndex of
        Nothing ->
          [ApplicationMapMissing currentKey (someEffectRefKey currentMapRef)]
        Just _ -> validateRef effectIndex currentMapRef
    readRefErrors =
      case Map.lookup (someEffectRefKey currentReadRef) effectIndex of
        Nothing ->
          [ApplicationReadMissing currentKey (someEffectRefKey currentReadRef)]
        Just _ -> validateRef effectIndex currentReadRef
    alignmentErrors =
      case
          ( Map.lookup (someEffectRefKey currentCommandRef) effectIndex
          , Map.lookup (someEffectRefKey currentMapRef) effectIndex
          , Map.lookup (someEffectRefKey currentReadRef) effectIndex
          ) of
        ( Just commandIr
          , Just mapIr
          , Just readIr
          ) ->
            validateAlignment
              transformIndex
              currentApplication
              commandIr
              mapIr
              readIr
        _ -> []

validateAlignment ::
  Map.Map TransformRef TransformDecl ->
  EffectApplication ->
  EffectIR ->
  EffectIR ->
  EffectIR ->
  [GraphError]
validateAlignment transformIndex currentApplication commandIr mapIr readIr =
  case (effectIrSpec commandIr, effectIrSpec mapIr, effectIrSpec readIr) of
    (CommandEffect commandSpec, MapEffect mapSpec, ReadEffect readSpec) ->
      inputErrors
        ++ arityErrors
        ++ paramErrors
        ++ transformErrors
      where
        currentKey = effectApplicationKey currentApplication
        commandParams = commandSpecParams commandSpec
        mapParams = mapSpecOutput mapSpec
        inputErrors =
          [ApplicationInputSchemaMismatch currentKey | readSpecValueSchema readSpec /= mapSpecInputSchema mapSpec]
        arityErrors =
          [ ApplicationParamArityMismatch
              currentKey
              (length commandParams)
              (length mapParams)
          | length commandParams /= length mapParams
          ]
        paramErrors =
          [ApplicationParamMismatch currentKey commandParams mapParams | commandParams /= mapParams]
        transformErrors =
          case Map.lookup (mapSpecTransform mapSpec) transformIndex of
            Nothing -> [TransformMissing currentKey (mapSpecTransform mapSpec)]
            Just currentTransform ->
              [ TransformInputMismatch currentKey
              | transformDeclInputSchema currentTransform /= mapSpecInputSchema mapSpec
              ]
                ++ [ TransformOutputMismatch currentKey
                   | transformDeclOutput currentTransform /= mapSpecOutput mapSpec
                   ]
    _ -> []

flattenAst :: AstPlan -> (AstGraph, [ApplicationOccurrence])
flattenAst currentPlan =
  ( AstGraph
      { astGraphRoot = rootPath
      , astGraphNodes = currentNodes
      , astGraphEdges = currentEdges
      }
  , currentOccurrences
  )
  where
    rootPath = AstPath [AstPathSegment (planKey currentPlan) 0]
    (currentNodes, currentEdges, currentOccurrences) =
      flattenNode rootPath currentPlan

flattenNode ::
  AstPath ->
  AstPlan ->
  ([AstGraphNode], [AstGraphEdge], [ApplicationOccurrence])
flattenNode currentPath currentPlan =
  case currentPlan of
    AstPlanApplication _ currentApplication ->
      ( [ AstGraphNode
            { astGraphNodePath = currentPath
            , astGraphNodeKind = AstGraphApplication currentOccurrenceId
            }
        ]
      , []
      , [ ApplicationOccurrence
            { applicationOccurrenceId = currentOccurrenceId
            , applicationOccurrencePath = currentPath
            , applicationOccurrenceApplication = currentApplication
            }
        ]
      )
      where
        currentOccurrenceId = occurrenceId currentPath currentApplication
    AstPlanBranch _ currentKind currentChildren ->
      ( AstGraphNode currentPath (AstGraphBranch currentKind)
          : concatMap first childResults
      , childEdges ++ concatMap second childResults
      , concatMap third childResults
      )
      where
        indexedChildren = zip [0 ..] currentChildren
        childPaths =
          [ appendAstPath currentPath (planKey currentChild) currentIndex
          | (currentIndex, currentChild) <- indexedChildren
          ]
        childResults =
          [ flattenNode currentChildPath currentChild
          | (currentChildPath, (_, currentChild)) <- zip childPaths indexedChildren
          ]
        childEdges = map (AstGraphEdge currentPath) childPaths

first :: (firstItem, secondItem, thirdItem) -> firstItem
first (currentItem, _, _) = currentItem

second :: (firstItem, secondItem, thirdItem) -> secondItem
second (_, currentItem, _) = currentItem

third :: (firstItem, secondItem, thirdItem) -> thirdItem
third (_, _, currentItem) = currentItem

planKey :: AstPlan -> AstNodeKey
planKey currentPlan =
  case currentPlan of
    AstPlanBranch currentKey _ _ -> currentKey
    AstPlanApplication currentKey _ -> currentKey

appendAstPath :: AstPath -> AstNodeKey -> Int -> AstPath
appendAstPath (AstPath currentSegments) currentKey currentOrdinal =
  AstPath (currentSegments ++ [AstPathSegment currentKey currentOrdinal])

occurrenceId :: AstPath -> EffectApplication -> ApplicationOccurrenceId
occurrenceId currentPath currentApplication =
  ApplicationOccurrenceId
    ( sha256
        ( renderAstPath currentPath
            ++ show (effectApplicationKey currentApplication)
        )
    )

buildInputGraph ::
  Map.Map EffectKey EffectIR ->
  [ApplicationOccurrence] ->
  InputGraph
buildInputGraph effectIndex occurrences =
  InputGraph
    { inputGraphNodes = sortOn inputNodeId (nub (concatMap occurrenceNodes occurrences))
    , inputGraphEdges = sort (nub (concatMap occurrenceEdges occurrences))
    }
  where
    occurrenceNodes currentOccurrence =
      [ inputNodeFor currentOccurrence currentRef
      | currentRef <- occurrenceInputRefs effectIndex currentOccurrence
      ]
    occurrenceEdges currentOccurrence =
      [ InputEdge
          { inputEdgePredecessor = inputNodeIdFor currentOccurrence currentPredecessor
          , inputEdgeTarget = inputNodeIdFor currentOccurrence currentTarget
          , inputEdgeContinuation =
              continuationIdFor currentOccurrence currentPredecessor currentTarget
          }
      | currentTarget <- occurrenceInputRefs effectIndex currentOccurrence
      , Just currentIr <- [Map.lookup (someEffectRefKey currentTarget) effectIndex]
      , Just currentPredecessor <- [effectIrInput currentIr]
      ]

occurrenceInputRefs ::
  Map.Map EffectKey EffectIR ->
  ApplicationOccurrence ->
  [SomeEffectRef]
occurrenceInputRefs effectIndex currentOccurrence =
  sort . nub . concatMap (inputClosure effectIndex []) $
    [ effectApplicationCommand currentApplication
    , effectApplicationMap currentApplication
    , effectApplicationRead currentApplication
    ]
  where
    currentApplication = applicationOccurrenceApplication currentOccurrence

inputClosure ::
  Map.Map EffectKey EffectIR ->
  [EffectKey] ->
  SomeEffectRef ->
  [SomeEffectRef]
inputClosure effectIndex visited currentRef
  | currentKey `elem` visited = []
  | otherwise =
      currentRef
        : case Map.lookup currentKey effectIndex >>= effectIrInput of
          Nothing -> []
          Just currentInput ->
            inputClosure effectIndex (currentKey : visited) currentInput
  where
    currentKey = someEffectRefKey currentRef

inputNodeFor :: ApplicationOccurrence -> SomeEffectRef -> InputNode
inputNodeFor currentOccurrence currentRef =
  InputNode
    { inputNodeId = inputNodeIdFor currentOccurrence currentRef
    , inputNodeOccurrence = applicationOccurrenceId currentOccurrence
    , inputNodeScope = applicationOccurrencePath currentOccurrence
    , inputNodeEffect = currentRef
    }

inputNodeIdFor :: ApplicationOccurrence -> SomeEffectRef -> InputNodeId
inputNodeIdFor currentOccurrence currentRef =
  InputNodeId
    ( sha256
        ( applicationOccurrenceIdText (applicationOccurrenceId currentOccurrence)
            ++ show currentRef
        )
    )

continuationIdFor ::
  ApplicationOccurrence ->
  SomeEffectRef ->
  SomeEffectRef ->
  ContinuationId
continuationIdFor currentOccurrence currentPredecessor currentTarget =
  ContinuationId
    ( sha256
        ( applicationOccurrenceIdText (applicationOccurrenceId currentOccurrence)
            ++ show currentPredecessor
            ++ "->"
            ++ show currentTarget
        )
    )

buildValueGraph ::
  Map.Map EffectKey EffectIR ->
  [ApplicationOccurrence] ->
  ValueGraph
buildValueGraph effectIndex occurrences =
  ValueGraph
    { valueGraphNodes = sortOn valueNodeId (nub (concatMap occurrenceValueNodes occurrences))
    , valueGraphEdges = sort (nub (concatMap occurrenceValueEdges occurrences))
    }
  where
    occurrenceValueNodes currentOccurrence =
      let currentApplication = applicationOccurrenceApplication currentOccurrence
          currentReadRefs = occurrenceReadRefs effectIndex currentApplication
          currentReadNodes =
            map (valueNodeFor currentOccurrence ValueReadRole) currentReadRefs
          currentMapNode =
            valueNodeFor currentOccurrence ValueMapRole (effectApplicationMap currentApplication)
          currentParamNode =
            valueNodeFor currentOccurrence ValueCommandParamsRole (effectApplicationCommand currentApplication)
          currentObservationNode =
            valueNodeFor currentOccurrence ValueObservationRole (effectApplicationCommand currentApplication)
       in currentReadNodes ++ [currentMapNode, currentParamNode, currentObservationNode]
    occurrenceValueEdges currentOccurrence =
      readDependencyEdges effectIndex currentOccurrence
        ++ applicationValueEdges currentOccurrence

occurrenceReadRefs ::
  Map.Map EffectKey EffectIR ->
  EffectApplication ->
  [SomeEffectRef]
occurrenceReadRefs effectIndex currentApplication =
  sort . nub $
    readClosure effectIndex [] (effectApplicationRead currentApplication)

readClosure ::
  Map.Map EffectKey EffectIR ->
  [EffectKey] ->
  SomeEffectRef ->
  [SomeEffectRef]
readClosure effectIndex visited currentRef
  | currentKey `elem` visited = []
  | otherwise =
      currentRef
        : concatMap
          (readClosure effectIndex (currentKey : visited))
          currentDependencies
  where
    currentKey = someEffectRefKey currentRef
    currentDependencies =
      case Map.lookup currentKey effectIndex of
        Just currentEffect ->
          case effectIrSpec currentEffect of
            ReadEffect currentRead -> valueSourceRefs (readSpecSource currentRead)
            _ -> []
        Nothing -> []

readDependencyEdges ::
  Map.Map EffectKey EffectIR ->
  ApplicationOccurrence ->
  [ValueEdge]
readDependencyEdges effectIndex currentOccurrence =
  [ ValueEdge
      { valueEdgeFrom = valueNodeIdFor currentOccurrence ValueReadRole currentDependency
      , valueEdgeTo = valueNodeIdFor currentOccurrence ValueReadRole currentReadRef
      , valueEdgeKind = ValueReadDependency
      }
  | currentReadRef <- occurrenceReadRefs effectIndex currentApplication
  , Just currentEffect <- [Map.lookup (someEffectRefKey currentReadRef) effectIndex]
  , ReadEffect currentRead <- [effectIrSpec currentEffect]
  , currentDependency <- valueSourceRefs (readSpecSource currentRead)
  ]
  where
    currentApplication = applicationOccurrenceApplication currentOccurrence

applicationValueEdges :: ApplicationOccurrence -> [ValueEdge]
applicationValueEdges currentOccurrence =
  [ ValueEdge
      { valueEdgeFrom = valueNodeIdFor currentOccurrence ValueReadRole currentRead
      , valueEdgeTo = valueNodeIdFor currentOccurrence ValueMapRole currentMap
      , valueEdgeKind = ValueMapInput
      }
  , ValueEdge
      { valueEdgeFrom = valueNodeIdFor currentOccurrence ValueMapRole currentMap
      , valueEdgeTo = valueNodeIdFor currentOccurrence ValueCommandParamsRole currentCommand
      , valueEdgeKind = ValueParamBinding
      }
  , ValueEdge
      { valueEdgeFrom = valueNodeIdFor currentOccurrence ValueCommandParamsRole currentCommand
      , valueEdgeTo = valueNodeIdFor currentOccurrence ValueObservationRole currentCommand
      , valueEdgeKind = ValueObservation
      }
  ]
  where
    currentApplication = applicationOccurrenceApplication currentOccurrence
    currentRead = effectApplicationRead currentApplication
    currentMap = effectApplicationMap currentApplication
    currentCommand = effectApplicationCommand currentApplication

valueNodeFor ::
  ApplicationOccurrence ->
  ValueNodeRole ->
  SomeEffectRef ->
  ValueNode
valueNodeFor currentOccurrence currentRole currentRef =
  ValueNode
    { valueNodeId = valueNodeIdFor currentOccurrence currentRole currentRef
    , valueNodeOccurrence = applicationOccurrenceId currentOccurrence
    , valueNodeScope = applicationOccurrencePath currentOccurrence
    , valueNodeEffect = currentRef
    , valueNodeRole = currentRole
    }

valueNodeIdFor ::
  ApplicationOccurrence ->
  ValueNodeRole ->
  SomeEffectRef ->
  ValueNodeId
valueNodeIdFor currentOccurrence currentRole currentRef =
  ValueNodeId
    ( sha256
        ( applicationOccurrenceIdText (applicationOccurrenceId currentOccurrence)
            ++ show currentRole
            ++ show currentRef
        )
    )

valueSourceRefs :: ValueSourceSpec -> [SomeEffectRef]
valueSourceRefs currentSource =
  case currentSource of
    ValueExternal _ -> []
    ValueLiteral _ -> []
    ValueFromR currentRef -> [currentRef]
    ValueRecord currentFields ->
      concatMap (valueSourceRefs . snd) currentFields
    ValueProduct currentItems -> concatMap valueSourceRefs currentItems

inputCycles :: Map.Map EffectKey EffectIR -> [[EffectKey]]
inputCycles effectIndex =
  canonicalCycles
    [ currentCycle
    | currentKey <- Map.keys effectIndex
    , Just currentCycle <- [walkInput [] currentKey]
    ]
  where
    walkInput currentPath currentKey
      | currentKey `elem` currentPath =
          Just (cycleFrom currentKey currentPath)
      | otherwise =
          case Map.lookup currentKey effectIndex >>= effectIrInput of
            Nothing -> Nothing
            Just currentInput ->
              walkInput (currentPath ++ [currentKey]) (someEffectRefKey currentInput)

valueCycles :: Map.Map EffectKey EffectIR -> [[EffectKey]]
valueCycles effectIndex =
  canonicalCycles
    (concatMap (walkValue []) rKeys)
  where
    rKeys =
      [ currentKey
      | (currentKey, currentEffect) <- Map.toList effectIndex
      , someEffectRefKind (effectIrRef currentEffect) == R
      ]
    walkValue currentPath currentKey
      | currentKey `elem` currentPath =
          [cycleFrom currentKey currentPath]
      | otherwise =
          concatMap
            (walkValue (currentPath ++ [currentKey]) . someEffectRefKey)
            (readDependencies currentKey)
    readDependencies currentKey =
      case Map.lookup currentKey effectIndex of
        Just currentEffect ->
          case effectIrSpec currentEffect of
            ReadEffect currentRead -> valueSourceRefs (readSpecSource currentRead)
            _ -> []
        Nothing -> []

cycleFrom :: Eq item => item -> [item] -> [item]
cycleFrom currentItem currentPath =
  dropWhile (/= currentItem) currentPath ++ [currentItem]

canonicalCycles :: Ord item => [[item]] -> [[item]]
canonicalCycles = sort . nub . map canonicalCycle

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

groupOn :: Ord key => (item -> key) -> [item] -> [[item]]
groupOn currentKey =
  groupByKey . sortOn currentKey
  where
    groupByKey [] = []
    groupByKey (currentItem : remaining) =
      let (same, rest) = span ((== currentKey currentItem) . currentKey) remaining
       in (currentItem : same) : groupByKey rest
