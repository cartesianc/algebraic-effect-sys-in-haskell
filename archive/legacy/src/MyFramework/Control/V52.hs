module MyFramework.Control.V52
  ( ContextRefV52 (..)
  , ControlGate (..)
  , ControlPolicy (..)
  , ControlPolicyError (..)
  , ControlPolicyRegistry (..)
  , ControlPolicyVersion (..)
  , VersionedContext (..)
  , VersionedControlGate (..)
  , compileControlPolicyRegistry
  , defaultReadyGate
  , identityContext
  ) where

import Data.List (nub, sort)
import qualified Data.Map.Strict as Map

import MyFramework.Effect
import MyFramework.Graph

newtype ControlPolicyVersion = ControlPolicyVersion
  { controlPolicyVersionMajor :: Int
  }
  deriving (Eq, Ord, Read, Show)

data ControlGate
  = ControlGateReady
  | ControlGateBlocked String
  | ControlGateFailed String
  deriving (Eq, Ord, Read, Show)

data VersionedControlGate = VersionedControlGate
  { versionedControlGateVersion :: ControlPolicyVersion
  , versionedControlGateValue :: ControlGate
  }
  deriving (Eq, Ord, Read, Show)

newtype ContextRefV52 = ContextRefV52
  { contextRefV52Text :: String
  }
  deriving (Eq, Ord, Read, Show)

data VersionedContext = VersionedContext
  { versionedContextRef :: ContextRefV52
  , versionedContextVersion :: ControlPolicyVersion
  }
  deriving (Eq, Ord, Read, Show)

data ControlPolicy
  = ChoiceControl String
  | WaitControl VersionedControlGate
  | SuspenseControl SomeEffectRef VersionedControlGate
  | ContextControl VersionedContext
  deriving (Eq, Ord, Read, Show)

newtype ControlPolicyRegistry = ControlPolicyRegistry
  { controlPolicyRegistryEntries :: [(AstPath, ControlPolicy)]
  }
  deriving (Eq, Ord, Read, Show)

data ControlPolicyError
  = ControlPolicyMissing AstPath AstBranchKind
  | ControlPolicyKindMismatch AstPath AstBranchKind ControlPolicy
  | ControlChildArityInvalid AstPath AstBranchKind Int
  | ControlChoiceSelectionMissing AstPath String [String]
  | ControlSuspenseEffectMissing AstPath EffectKey
  | ControlContextUnknown AstPath VersionedContext
  | ControlPolicyPathDuplicate [AstPath]
  deriving (Eq, Ord, Read, Show)

defaultReadyGate :: VersionedControlGate
defaultReadyGate =
  VersionedControlGate (ControlPolicyVersion 1) ControlGateReady

identityContext :: VersionedContext
identityContext =
  VersionedContext (ContextRefV52 "identity") (ControlPolicyVersion 1)

compileControlPolicyRegistry ::
  [(String, AstBranchKind, Maybe ControlPolicy)] ->
  EffectRegistry ->
  AstGraph ->
  Either [ControlPolicyError] ControlPolicyRegistry
compileControlPolicyRegistry currentDeclarations currentEffects currentGraph
  | null currentErrors = Right (ControlPolicyRegistry (sort currentEntries))
  | otherwise = Left (sort (nub currentErrors))
  where
    declarationIndex =
      Map.fromList
        [ (currentName, (currentKind, currentPolicy))
        | (currentName, currentKind, currentPolicy) <- currentDeclarations
        ]
    effectKeys =
      map (someEffectRefKey . effectIrRef) (effectRegistryEffects currentEffects)
    controlledNodes =
      [ (astGraphNodePath currentNode, currentKind)
      | currentNode <- astGraphNodes currentGraph
      , AstGraphBranch currentKind <- [astGraphNodeKind currentNode]
      , currentKind `elem` [AstChoice, AstWait, AstSuspense, AstContext]
      ]
    currentEntries =
      [ (currentPath, currentPolicy)
      | (currentPath, currentKind) <- controlledNodes
      , Just (declaredKind, Just currentPolicy) <-
          [Map.lookup (terminalKey currentPath) declarationIndex]
      , currentKind == declaredKind
      ]
    currentErrors =
      concatMap validateNode controlledNodes
        ++ [ ControlPolicyPathDuplicate currentDuplicates
           | let currentDuplicates = duplicates (map fst currentEntries)
           , not (null currentDuplicates)
           ]
    validateNode (currentPath, currentKind) =
      case Map.lookup (terminalKey currentPath) declarationIndex of
        Nothing -> [ControlPolicyMissing currentPath currentKind]
        Just (_, Nothing) -> [ControlPolicyMissing currentPath currentKind]
        Just (declaredKind, Just currentPolicy) ->
          [ ControlPolicyKindMismatch currentPath currentKind currentPolicy
          | declaredKind /= currentKind || not (policyMatches currentKind currentPolicy)
          ]
            ++ arityErrors currentPath currentKind
            ++ policyErrors currentPath currentPolicy
    arityErrors currentPath currentKind =
      [ ControlChildArityInvalid currentPath currentKind currentArity
      | let currentArity = length (childrenOf currentPath)
      , not (validArity currentKind currentArity)
      ]
    policyErrors currentPath currentPolicy =
      case currentPolicy of
        ChoiceControl currentSelection ->
          [ ControlChoiceSelectionMissing currentPath currentSelection currentChildren
          | let currentChildren = map terminalKey (childrenOf currentPath)
          , currentSelection `notElem` currentChildren
          ]
        SuspenseControl currentRef _ ->
          [ ControlSuspenseEffectMissing currentPath (someEffectRefKey currentRef)
          | someEffectRefKey currentRef `notElem` effectKeys
          ]
        ContextControl currentContext ->
          [ControlContextUnknown currentPath currentContext | currentContext /= identityContext]
        WaitControl _ -> []
    childrenOf currentPath =
      [ astGraphEdgeChild currentEdge
      | currentEdge <- astGraphEdges currentGraph
      , astGraphEdgeParent currentEdge == currentPath
      ]

policyMatches :: AstBranchKind -> ControlPolicy -> Bool
policyMatches AstChoice ChoiceControl {} = True
policyMatches AstWait WaitControl {} = True
policyMatches AstSuspense SuspenseControl {} = True
policyMatches AstContext ContextControl {} = True
policyMatches _ _ = False

validArity :: AstBranchKind -> Int -> Bool
validArity AstChoice currentArity = currentArity > 0
validArity AstWait currentArity = currentArity == 1
validArity AstSuspense currentArity = currentArity == 0
validArity AstContext currentArity = currentArity == 1
validArity _ _ = True

terminalKey :: AstPath -> String
terminalKey (AstPath currentSegments) =
  case reverse currentSegments of
    currentSegment : _ -> astNodeKeyText (astPathSegmentKey currentSegment)
    [] -> ""

duplicates :: Ord item => [item] -> [item]
duplicates currentItems =
  [ currentItem
  | currentItem <- nub currentItems
  , length (filter (== currentItem) currentItems) > 1
  ]
