module MyFramework.Loop
  ( LoopError (..)
  , LoopPolicy (..)
  , LoopPolicyRef (..)
  , LoopPolicyRegistry (..)
  , LoopPolicyVersion (..)
  , VersionedLoopPolicy (..)
  , compileLoopPolicyRegistry
  , defaultLoopPolicy
  ) where

import Data.List
  ( nub
  , sort
  )

import MyFramework.Graph

newtype LoopPolicyRef = LoopPolicyRef
  { loopPolicyRefText :: String
  }
  deriving (Eq, Ord, Read, Show)

newtype LoopPolicyVersion = LoopPolicyVersion
  { loopPolicyVersionMajor :: Int
  }
  deriving (Eq, Ord, Read, Show)

data LoopPolicy
  = UntilQuiescent
      { loopPolicyMaxIterations :: Int
      }
  deriving (Eq, Ord, Read, Show)

data VersionedLoopPolicy = VersionedLoopPolicy
  { versionedLoopPolicyRef :: LoopPolicyRef
  , versionedLoopPolicyVersion :: LoopPolicyVersion
  , versionedLoopPolicyValue :: LoopPolicy
  }
  deriving (Eq, Ord, Read, Show)

newtype LoopPolicyRegistry = LoopPolicyRegistry
  { loopPolicyRegistryEntries :: [(AstPath, VersionedLoopPolicy)]
  }
  deriving (Eq, Ord, Read, Show)

data LoopError
  = LoopChildArityInvalid AstPath Int
  | LoopPolicyMissing AstPath
  | LoopPolicyMaxIterationsInvalid AstPath Int
  | LoopPolicyPathDuplicate [AstPath]
  deriving (Eq, Ord, Read, Show)

defaultLoopPolicy :: VersionedLoopPolicy
defaultLoopPolicy =
  VersionedLoopPolicy
    { versionedLoopPolicyRef = LoopPolicyRef "until-quiescent/default"
    , versionedLoopPolicyVersion = LoopPolicyVersion 1
    , versionedLoopPolicyValue = UntilQuiescent 1024
    }

compileLoopPolicyRegistry ::
  [(String, VersionedLoopPolicy)] ->
  AstGraph ->
  Either [LoopError] LoopPolicyRegistry
compileLoopPolicyRegistry currentDeclarations currentGraph
  | null currentErrors =
      Right (LoopPolicyRegistry (sort currentEntries))
  | otherwise = Left (sort (nub currentErrors))
  where
    currentEntries =
      [ (astGraphNodePath currentNode, currentPolicy)
      | currentNode <- astGraphNodes currentGraph
      , AstGraphBranch AstLoop <- [astGraphNodeKind currentNode]
      , Just currentPolicy <- [lookup (terminalKey (astGraphNodePath currentNode)) currentDeclarations]
      ]
    loopPaths =
      [ astGraphNodePath currentNode
      | currentNode <- astGraphNodes currentGraph
      , AstGraphBranch AstLoop <- [astGraphNodeKind currentNode]
      ]
    currentErrors =
      [ LoopPolicyMissing currentPath
      | currentPath <- loopPaths
      , currentPath `notElem` map fst currentEntries
      ]
        ++ [ LoopChildArityInvalid currentPath currentArity
           | currentPath <- loopPaths
           , let currentArity =
                   length
                     [ ()
                     | currentEdge <- astGraphEdges currentGraph
                     , astGraphEdgeParent currentEdge == currentPath
                     ]
           , currentArity /= 1
           ]
        ++ [ LoopPolicyMaxIterationsInvalid currentPath currentMaximum
           | (currentPath, currentPolicy) <- currentEntries
           , let currentMaximum =
                   loopPolicyMaxIterations
                     (versionedLoopPolicyValue currentPolicy)
           , currentMaximum <= 0
           ]
        ++ [LoopPolicyPathDuplicate currentDuplicates | let currentDuplicates = duplicates (map fst currentEntries), not (null currentDuplicates)]

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
