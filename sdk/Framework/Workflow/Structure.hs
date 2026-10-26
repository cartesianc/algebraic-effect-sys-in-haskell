{-# LANGUAGE DeriveFunctor #-}
{-# LANGUAGE DeriveGeneric #-}

-- 第一次 fold 的只读结果；不创建 Target、不生产 Context、不打开 scope。
module Framework.Workflow.Structure
  ( InitializedF(..), ProgramStructure(..), StructureError(..)
  , initializeStructure, initializeGeneratedStructure, scopeRelations, renderStructure
  ) where

import Control.DeepSeq (NFData(..))
import Data.List (intercalate, nub, sort, (\\))
import GHC.Generics (Generic)
import Framework.Effect.Graph
import Framework.Recursion (Fix(..), Algebra, cata)
import Framework.Workflow.AST (AST, WorkflowF(..), foldAST)

-- 保留 workflow 控制结构和每个调用位置，方法定义身份可跨位置共享。
data InitializedF method next
  = InitializedNode String method
  | InitializedChained [next]
  | InitializedParallel [next]
  deriving (Functor, Show, Read)

data StructureError method
  = UnknownStructureTarget String
  | InvalidEffectGraph (GraphError method)
  | DuplicateScopeIdentity method
  | DuplicateScopeName String
  | MissingScopeIdentity method
  | InvalidScopeIdentity method
  | UnknownScopeParent String String
  | InvalidGeneratedStructure String
  | GeneratedEntriesMismatch [method] [method]
  deriving (Eq, Show, Read, Generic)

instance NFData method => NFData (StructureError method)

data ProgramStructure method = ProgramStructure
  { structureWorkflow :: Fix (InitializedF method)
  , structureEffects :: EffectGraph method
  , structureScopes :: ScopeTree method
  -- 仅把生成方法身份连接到现有运行 scope 名；依赖仍只保存在 ScopeTree。
  , structureScopeNames :: [(method, String)]
  } deriving Show

instance NFData method => NFData (ProgramStructure method) where
  rnf structure = forceWorkflow (structureWorkflow structure)
    `seq` rnf (structureEffects structure)
    `seq` rnf (structureScopes structure)
    `seq` rnf (structureScopeNames structure)
    where
      forceWorkflow = cata $ \layer -> case layer of
        InitializedNode target method -> rnf target `seq` rnf method
        InitializedChained children -> rnf children
        InitializedParallel children -> rnf children

initializeStructure
  :: Ord method
  => [(method, method, method)]
  -> [MethodDefinition method]
  -> [(method, String, [String])]
  -> [(String, method)]
  -> AST
  -> Either (StructureError method) (ProgramStructure method)
initializeStructure routes definitions scopeDeclarations entries tree = do
  (workflow, roots) <- initializeWorkflow entries tree
  graph <- either (Left . InvalidEffectGraph) Right
    (buildEffectGraph routes definitions (Choice (map Call roots)))
  validateNames [] [] scopeDeclarations
  mapM_ requireIdentity (graphScopes graph)
  declared <- mapM scopeParentsByIdentity scopeDeclarations
  scopes <- either (Left . InvalidEffectGraph) Right
    (completeScopeTree declared (buildScopeTree graph))
  pure (ProgramStructure workflow graph scopes names)
  where
    names = [(method, name) | (method, name, _) <- scopeDeclarations]
    validateNames _ _ [] = Right ()
    validateNames identities labels ((method, name, _) : rest)
      | method `elem` identities = Left (DuplicateScopeIdentity method)
      | name `elem` labels = Left (DuplicateScopeName name)
      | not (any (\definition -> methodIdentity definition == method
          && methodRole definition == ScopeOpen) definitions) = Left (InvalidScopeIdentity method)
      | otherwise = validateNames (method : identities) (name : labels) rest
    requireIdentity method
      | method `elem` map fst names = Right ()
      | otherwise = Left (MissingScopeIdentity method)
    scopeParentsByIdentity (method, name, parents) = do
      selected <- mapM (\parent -> case lookup parent [(label, identity) | (identity, label) <- names] of
        Nothing -> Left (UnknownScopeParent name parent)
        Just identity -> Right identity) parents
      pure (method, selected)

-- gencode 已完成方法图与 scope 树；这里只校验常量和当前 AST 的入口集合。
-- 不重新解释方法 body，不推导或修正父边，保留生成源码中的树作为运行依据。
initializeGeneratedStructure
  :: Ord method
  => [(String, method)]
  -> [(method, String)]
  -> EffectGraph method
  -> ScopeTree method
  -> AST
  -> Either (StructureError method) (ProgramStructure method)
initializeGeneratedStructure entries names graph scopes tree = do
  (workflow, roots) <- initializeWorkflow entries tree
  validateGeneratedStructure entries names graph scopes
  if sameSet roots (graphRoots graph)
    then pure (ProgramStructure workflow graph scopes names)
    else Left (GeneratedEntriesMismatch (graphRoots graph) (nub roots))

initializeWorkflow
  :: [(String, method)]
  -> AST
  -> Either (StructureError method) (Fix (InitializedF method), [method])
initializeWorkflow entries = foldAST (initializationAlgebra entries)

-- 校验只读取显式字段。未被当前方法图访问的声明 scope 仍可出现在生成树中。
validateGeneratedStructure
  :: Ord method
  => [(String, method)] -> [(method, String)]
  -> EffectGraph method -> ScopeTree method
  -> Either (StructureError method) ()
validateGeneratedStructure entries names graph tree = do
  valid (unique (map fst entries)) "Duplicate target name"
  valid (unique methodIds) "Duplicate graph method identity"
  valid (unique (graphRoots graph)) "Duplicate graph root"
  valid (all (`elem` methodIds) (graphRoots graph)) "Unknown graph root"
  valid (all (knownPair methodIds) (graphReferences graph)) "Unknown method reference"
  valid (unique observedScopes) "Duplicate graph scope identity"
  valid (sameSet observedScopes [methodIdentity method | method <- graphMethods graph, methodRole method == ScopeOpen])
    "Graph scope identities do not match its open methods"
  valid (all (`elem` observedScopes) (concat (graphScopePaths graph))) "Unknown scope in graph path"
  valid (sameSet observedScopes (concat (graphScopePaths graph))) "Graph scope path coverage differs"
  valid (sameSet (map fst (graphRootPaths graph)) (graphRoots graph)) "Graph entry path coverage differs"
  valid (all (all (all (`elem` observedScopes)) . snd) (graphRootPaths graph)) "Unknown scope in entry path"
  valid (sameSet (concatMap snd (graphRootPaths graph)) (graphScopePaths graph)
    || null (graphRoots graph) && graphScopePaths graph == [[]]) "Graph paths differ from entry paths"
  valid (all (knownPair observedScopes) (graphScopeOrder graph)) "Unknown scope in graph order"
  mapM_ uniqueNameIdentity names
  valid (unique (map snd names)) "Duplicate scope name"
  valid (unique nodeIds) "Duplicate scope node"
  valid (sameSet (map fst names) nodeIds) "Scope names do not cover exactly the tree nodes"
  mapM_ requireObserved observedScopes
  mapM_ validateNode (scopeNodes tree)
  valid (sameSet parentEdges childEdges) "Scope parent and child references disagree"
  expectedLayers <- layers nodeIds
  valid (unique (scopeRoots tree) && sameSet (scopeRoots tree) [scopeIdentity node | node <- scopeNodes tree, null (scopeParents node)])
    "Scope roots disagree with parent references"
  valid (length expectedLayers == length (scopeLayers tree)
    && and (zipWith sameSet expectedLayers (scopeLayers tree))
    && unique (concat (scopeLayers tree))) "Scope layers disagree with parent references"
  valid (sameSet (scopePaths tree) (graphScopePaths graph)) "Scope tree paths differ from the generated graph"
  valid (sameSet (scopeCandidates tree) (graphScopeOrder graph)) "Scope candidates differ from the generated graph"
  valid (all (knownPair nodeIds) (scopeOpposed tree ++ scopeUndetermined tree)) "Unknown scope in order evidence"
  where
    methodIds = map methodIdentity (graphMethods graph)
    observedScopes = graphScopes graph
    nodeIds = map scopeIdentity (scopeNodes tree)
    parentEdges = [(parent, scopeIdentity node) | node <- scopeNodes tree, parent <- scopeParents node]
    childEdges = [(scopeIdentity node, child) | node <- scopeNodes tree, child <- scopeChildren node]
    knownPair known (left, right) = left `elem` known && right `elem` known
    unique values = length values == length (nub values)
    valid condition reason = if condition then Right () else Left (InvalidGeneratedStructure reason)
    uniqueNameIdentity (method, _)
      | length (filter ((== method) . fst) names) /= 1 = Left (DuplicateScopeIdentity method)
      | otherwise = case [definition | definition <- graphMethods graph, methodIdentity definition == method] of
          definition : _ | methodRole definition /= ScopeOpen -> Left (InvalidScopeIdentity method)
          _ -> Right ()
    requireObserved method
      | method `elem` nodeIds = Right ()
      | otherwise = Left (MissingScopeIdentity method)
    validateNode node = do
      let linked = scopeParents node ++ scopeChildren node
      valid (all (`elem` nodeIds) linked) "Unknown scope parent or child"
      valid (scopeIdentity node `notElem` linked) "Scope node refers to itself"
      valid (unique (scopeParents node) && unique (scopeChildren node)) "Duplicate scope parent or child"
    parents selected = [parent | (parent, child) <- parentEdges, child == selected]
    layers [] = Right []
    layers remaining =
      let ready = [selected | selected <- remaining, all (`notElem` remaining) (parents selected)]
      in if null ready
        then Left (InvalidEffectGraph (CyclicScopeRelations remaining))
        else (ready :) <$> layers (remaining \\ ready)

sameSet :: Ord value => [value] -> [value] -> Bool
sameSet left right = sort (nub left) == sort (nub right)

-- 初始化已校验每个 scope 的名字和父节点；投影同树的全部祖先，不另存依赖图。
-- 中间 scope 尚无活实例时，末端仍必须保留它的上游前提。
scopeRelations :: Eq method => ProgramStructure method -> [(String, [String])]
scopeRelations structure =
  [(name, [parentName | parent <- ancestors (scopeIdentity node), Just parentName <- [lookup parent names]])
    | node <- scopeNodes (structureScopes structure)
    , Just name <- [lookup (scopeIdentity node) names]]
  where
    names = structureScopeNames structure
    parents = [(scopeIdentity node, scopeParents node) | node <- scopeNodes (structureScopes structure)]
    ancestors selected = case lookup selected parents of
      Nothing -> []
      Just direct -> nub (direct ++ concatMap ancestors direct)

-- Chained/Parallel 控制 Node 的执行；两者都只汇总独立的 effect chain。
-- 不能把跨 Node 的时间顺序误作 scope 之间的必要前序。
initializationAlgebra
  :: [(String, method)]
  -> Algebra WorkflowF
       (Either (StructureError method) (Fix (InitializedF method), [method]))
initializationAlgebra entries (Node selected) = case lookup selected entries of
  Nothing -> Left (UnknownStructureTarget selected)
  Just method -> Right (Fix (InitializedNode selected method), [method])
initializationAlgebra _ (Chained children) = combine InitializedChained children
initializationAlgebra _ (Parallel children) = combine InitializedParallel children

combine constructor children = do
  parts <- sequence children
  pure (Fix (constructor (map fst parts)), concatMap snd parts)

-- 可直接查看的只读初始化结果；展示名不参与图的身份比较。
renderStructure :: Show method => ProgramStructure method -> String
renderStructure structure = unlines $
  ["Workflow", "  " ++ show (structureWorkflow structure), "", "Effect methods"]
  ++ ["  " ++ show (methodIdentity method) ++ " [" ++ show (methodRole method)
       ++ ", effect=" ++ show (methodEffect method) ++ "]"
     | method <- graphMethods graph]
  ++ ["", "Effect references"] ++ map edge (graphReferences graph)
  ++ ["", "Scope layers"]
  ++ ["  " ++ show index ++ ": " ++ intercalate ", " (map show layer)
     | (index, layer) <- zip [0 :: Int ..] (scopeLayers tree)]
  ++ ["", "Scope parents (shared nodes; observed order and registered prerequisites)"]
  ++ ["  " ++ show (scopeIdentity node) ++ " <- " ++ show (scopeParents node)
     | node <- scopeNodes tree]
  ++ ["", "Scope paths by entry"]
  ++ ["  " ++ show entry ++ ": " ++ intercalate " -> " (map show path)
     | (entry, paths) <- graphRootPaths graph, path <- paths]
  ++ ["", "Opposed order evidence"] ++ map edge (scopeOpposed tree)
  ++ ["", "Order-undetermined observed pairs"]
  ++ ["  " ++ show left ++ " / " ++ show right | (left, right) <- scopeUndetermined tree]
  where
    graph = structureEffects structure
    tree = structureScopes structure
    edge (before, after) = "  " ++ show before ++ " -> " ++ show after
