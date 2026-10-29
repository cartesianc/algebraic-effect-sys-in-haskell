{-# LANGUAGE DeriveGeneric #-}

-- gencode 生成的只读结构；运行时校验常量，不复制 workflow 或执行 handler。
module Framework.Workflow.Structure
  ( ProgramStructure(..), StructureError(..)
  , initializeStructure, initializeGeneratedStructure, validateWorkflowEntries, checkAlternative, scopeRelations, renderStructure
  ) where

import Control.DeepSeq (NFData(..))
import Control.Monad (unless)
import Data.List (intercalate, nub, sort, (\\))
import GHC.Generics (Generic)
import Framework.Effect.Graph
import Framework.Workflow.AST (AST, WorkflowF(..), foldAST)

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
  -- alternative 的候选末端没有登记分支，或候选不共用同一转折资产。
  | InvalidAlternative [String]
  deriving (Eq, Show, Read, Generic)

instance NFData method => NFData (StructureError method)

data ProgramStructure method = ProgramStructure
  { structureEntries :: [(String, method)]
  , structureEffects :: EffectGraph method
  , structureScopes :: ScopeTree method
  -- 仅把生成方法身份连接到现有运行 scope 名；依赖仍只保存在 ScopeTree。
  , structureScopeNames :: [(method, String)]
  } deriving (Show, Generic)

instance NFData method => NFData (ProgramStructure method)

-- 生成期直接枚举各独立入口，不把不同 Node 串成 scope 路径。
initializeStructure
  :: Ord method
  => [MethodDefinition method]
  -> [(method, String, [String])]
  -> [(String, method)]
  -> Either (StructureError method) (ProgramStructure method)
initializeStructure definitions scopeDeclarations entries = do
  graph <- either (Left . InvalidEffectGraph) Right
    (buildEffectGraph definitions (Choice (map (Call . snd) entries)))
  validateNames [] [] scopeDeclarations
  mapM_ requireIdentity (graphScopes graph)
  declared <- mapM scopeParentsByIdentity scopeDeclarations
  scopes <- either (Left . InvalidEffectGraph) Right
    (completeScopeTree declared (buildScopeTree graph))
  pure (ProgramStructure entries graph scopes names)
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

-- gencode 已完成方法图与 scope 树；这里只校验生成常量，不遍历当前 AST。
-- 不重新解释方法 body，不推导或修正父边，保留生成源码中的树作为运行依据。
initializeGeneratedStructure
  :: Ord method
  => [(String, method)]
  -> [(method, String)]
  -> EffectGraph method
  -> ScopeTree method
  -> Either (StructureError method) (ProgramStructure method)
initializeGeneratedStructure entries names graph scopes = do
  validateGeneratedStructure entries names graph scopes
  pure (ProgramStructure entries graph scopes names)

resolveEntry :: [(String, method)] -> String -> Either (StructureError method) method
resolveEntry entries selected = maybe (Left (UnknownStructureTarget selected)) Right (lookup selected entries)

-- 按生成表核对一组 alternative 候选（各候选的 Node 名）：共用同一转折契约，构造器不重复且覆盖全部。
-- 返回转折契约、各候选对应的构造器，以及转折读取末端在结构中的入口身份（该 alternative 的额外根）。
-- 执行装配与 --structure 共用这一纯校验，两个入口对同一 AST 给出一致判断。
checkAlternative
  :: ProgramStructure method -> [(String, (String, String))] -> [(String, [String])]
  -> [[String]] -> Either (StructureError method) (String, [String], method)
checkAlternative structure cases constructorTable candidates = do
  found <- mapM (\selected -> case nub (map (`lookup` cases) selected) of
    [Just pair] -> Right pair
    _ -> invalid) candidates
  contract <- case nub (map fst found) of
    [selected] -> Right selected
    _ -> invalid
  let constructors = map snd found
  declared <- maybe invalid Right (lookup contract constructorTable)
  unless (length constructors == length (nub constructors) && sort constructors == sort declared) invalid
  method <- maybe invalid Right (lookup contract (structureEntries structure))
  pure (contract, constructors, method)
  where
    invalid :: Either (StructureError method) value
    invalid = Left (InvalidAlternative (concat candidates))

-- roots 由执行装配的同一次 AST fold 提供，不为检查入口再遍历 AST。
validateWorkflowEntries :: Ord method => ProgramStructure method -> [method] -> Either (StructureError method) ()
validateWorkflowEntries structure roots
  | sameSet roots expected = Right ()
  | otherwise = Left (GeneratedEntriesMismatch expected (nub roots))
  where expected = graphRoots (structureEffects structure)

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
  valid (sameSet (map snd entries) (graphRoots graph)) "Generated entry table differs from graph roots"
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

-- --structure 仅 fold 出展示文本与入口，不创建 Target 或装配业务动作。
-- alternative 按与执行相同的 checkAlternative 核对，并把转折读取末端记为根。
renderStructure
  :: (Ord method, Show method) => ProgramStructure method
  -> [(String, (String, String))] -> [(String, [String])] -> AST -> Either (StructureError method) String
renderStructure structure cases constructorTable workflowAST = do
  (_, roots, workflow) <- foldAST describe workflowAST
  validateWorkflowEntries structure roots
  pure (unlines (render workflow))
  where
    describe (Node selected) = do
      method <- resolveEntry (structureEntries structure) selected
      pure ([selected], [method], "Node " ++ show selected ++ " (" ++ show method ++ ")")
    describe (Chained children) = branch "Chained" children
    describe (Parallel children) = branch "Parallel" children
    describe (Alternative children) = do
      parts <- sequence children
      (contract, _, method) <- checkAlternative structure cases constructorTable [selected | (selected, _, _) <- parts]
      pure ( concat [selected | (selected, _, _) <- parts]
           , method : concat [entries | (_, entries, _) <- parts]
           , "Alternative on " ++ contract ++ " [" ++ intercalate ", " [text | (_, _, text) <- parts] ++ "]" )
    branch name children = do
      parts <- sequence children
      pure ( concat [selected | (selected, _, _) <- parts]
           , concat [entries | (_, entries, _) <- parts]
           , name ++ " [" ++ intercalate ", " [text | (_, _, text) <- parts] ++ "]" )
    render workflow =
      ["Workflow", "  " ++ workflow, "", "Effect methods"]
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
      ++ ["", "Observed order reversed by registered prerequisites"]
      ++ map edge [(before, after) | (before, after) <- scopeCandidates tree, after `elem` ancestors before]
      ++ ["", "Order-undetermined observed pairs"]
      ++ ["  " ++ show left ++ " / " ++ show right | (left, right) <- scopeUndetermined tree]
    graph = structureEffects structure
    tree = structureScopes structure
    ancestors selected = case [scopeParents node | node <- scopeNodes tree, scopeIdentity node == selected] of
      direct : _ -> nub (direct ++ concatMap ancestors direct)
      [] -> []
    edge (before, after) = "  " ++ show before ++ " -> " ++ show after
