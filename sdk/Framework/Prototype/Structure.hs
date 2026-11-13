-- 原型的只读查询与展示；不重新展开方法或推导链结构。
module Framework.Prototype.Structure (scopeRelations, renderStructure) where

import Data.List (intercalate, nub)
import Framework.Prototype.Graph
import Framework.Prototype
import Framework.Language.AST (AST)

-- 静态 ScopeTree 的祖先投影供运行实例的收尾与 Error 导航使用。
-- 这里只读取已经完成的父边，不重新推导资源依赖。
scopeRelations :: Eq method => Prototype method -> [(String, [String])]
scopeRelations prototype =
  [(name, [parentName | parent <- ancestors (scopeIdentity node), Just parentName <- [lookup parent names]])
    | node <- scopeNodes (protoScopes prototype)
    , Just name <- [lookup (scopeIdentity node) names]]
  where
    names = protoScopeNames prototype
    parents = [(scopeIdentity node, scopeParents node) | node <- scopeNodes (protoScopes prototype)]
    ancestors selected = case lookup selected parents of
      Nothing -> []
      Just direct -> nub (direct ++ concatMap ancestors direct)

-- 当前 AST 只与生成快照核对；所有结构信息均来自同一 Prototype。
-- 不创建 Target、scope 实例或执行任何业务。
renderStructure
  :: (Ord method, Show method)
  => Prototype method -> AST -> Either (PrototypeError method) String
renderStructure prototype workflowAST = do
  validateWorkflow prototype workflowAST
  pure (unlines rendered)
  where
    graph = protoGraph prototype
    tree = protoScopes prototype
    rendered =
      ["Workflow"] ++ renderWorkflow 1 (protoWorkflow prototype)
      ++ ["", "Interpreter sessions (booted by a finite require of a Receive asset; kept until exit)"]
      ++ ["  session " ++ sessionAsset session ++ " " ++ describePlan (sessionPlan session)
           ++ " mounts " ++ show (sessionMounts session)
         | session <- protoSessions prototype]
      ++ ["", "Chain definitions"]
      ++ ["  " ++ show (definitionKind definition) ++ " " ++ definitionEffect definition
           ++ " (" ++ show (definitionEntry definition) ++ ")"
           ++ " reaches " ++ show (definitionReaches definition)
         | definition <- protoChainDefinitions prototype]
      ++ ["", "Chain mounts"]
      ++ concat
         [ ["  " ++ show (chainNode chain) ++ " " ++ show (chainRole chain)
              ++ " " ++ chainTerminal chain ++ " (" ++ show (chainEntry chain) ++ ")"
           ,"    reaches " ++ show (chainReaches chain)
           ,"    drives " ++ show (chainDrives chain)
           ,"    reads " ++ show (chainReads chain)]
           ++ ["    scopes " ++ intercalate " -> " (map show path) | path <- chainScopePaths chain]
         | chain <- protoChains prototype]
      ++ ["", "Asset sources (for paths without a captured binding)"]
      ++ ["  " ++ show (readNode point) ++ " " ++ readContract point ++ " <- " ++ sourceDescription source
         | (point, source) <- protoSources prototype]
      ++ ["  Unowned assets follow the missing-value request rule; resource, diagnostic and cleanup exceptions remain."
         ,"  Where cross-chain lookup is needed, generation proves at most one visible source; runtime checks actual uniqueness."]
      ++ ["", "Scope openings (parameter production candidates; actual bindings determine the category)"]
      ++ concat
         [ ["  " ++ show (openingNode opening) ++ " " ++ openingScope opening
              ++ ": " ++ intercalate " / " (map scopeKindDescription (openingKinds opening))]
           ++ ["    " ++ source ++ " <- " ++ intercalate ", " (map describeNode nodes)
              | (source, nodes) <- openingSources opening]
         | opening <- protoScopeOpenings prototype]
      ++ ["", "Effect methods"]
      ++ ["  " ++ show (methodIdentity method) ++ " [" ++ show (methodRole method)
           ++ ", effect=" ++ show (methodEffect method) ++ "]"
         | method <- protoMethods prototype]
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
      ++ map edge [(before, after) | (before, after) <- scopeCandidates tree
                    , after `elem` ancestors before]
      ++ ["", "Order-undetermined observed pairs"]
      ++ ["  " ++ show left ++ " / " ++ show right | (left, right) <- scopeUndetermined tree]
    ancestors selected = case [scopeParents node | node <- scopeNodes tree, scopeIdentity node == selected] of
      direct : _ -> nub (direct ++ concatMap ancestors direct)
      [] -> []
    edge (before, after) = "  " ++ show before ++ " -> " ++ show after
    sourceDescription FromOwnChain = "own chain (no external candidates)"
    sourceDescription FromSession = "interpreter session (current history)"
    sourceDescription (FromChains nodes) = "visible candidates " ++ intercalate ", " (map describeNode nodes)
    scopeKindDescription RegistrationSingleton = "registration singleton"
    scopeKindDescription ProductionSingleton = "production singleton"
    scopeKindDescription ExecutionMultiple = "execution multiple"
    describeNode node = case lookupChain prototype node of
      Right chain -> show node ++ " " ++ chainTerminal chain
      Left _ -> show node
    renderWorkflow depth workflow =
      let prefix = replicate (depth * 2) ' '
          branch node label children =
            (prefix ++ show node ++ " " ++ label) : concatMap (renderWorkflow (depth + 1)) children
      in case workflow of
        NodeAt node selected -> [prefix ++ show node ++ " Node " ++ show selected]
        ChainedAt node children -> branch node "Chained" children
        ParallelAt node children -> branch node "Parallel" children
        AlternativeAt node description children ->
          branch node ("Alternative on " ++ alternativeContract description
            ++ " (selector " ++ show (alternativeSelector description)
            ++ ", cases " ++ show (alternativeCases description) ++ ")") children
        LifelongAt node description children ->
          let inner = prefix ++ "  "
          in (prefix ++ show node ++ " Lifelong (units " ++ show (lifelongUnits description) ++ ")")
            : [inner ++ "session " ++ sessionAsset session ++ " " ++ describePlan (sessionPlan session)
                ++ " mounts " ++ show (sessionMounts session)
              | session <- lifelongSessions description]
            ++ [inner ++ "subscribes " ++ show target ++ " <- " ++ asset
               | (target, asset) <- lifelongSubscriptions description]
            ++ concatMap (renderWorkflow (depth + 1)) children
    describePlan (Receive source) = "Receive from " ++ source
