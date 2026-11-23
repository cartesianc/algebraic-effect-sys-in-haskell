-- 只读的原型结构查询。NodeId 的先后与互斥只来自既有 workflow，
-- 先后只约束启动；普通发布的共享不由这些关系过滤，也不在这里修改运行状态。
module Framework.Prototype.Query
  ( nodeDriveAt, unitDriveAt, sessionDriveAt, describedSession
  , workflowNode, workflowChildren, workflowTerminals, workflowLifelongs, workflowSelectors
  , allWorkflow, lookupChain, lookupWorkflow, precedes, exclusive
  , driveSet, readPoints, scopeOpeningsAt, drivingAssets, bootPlan, sessionSteps, sessionAssets
  , finiteSessions, candidateCases, findEffectProto, ordinaryEntry, calledMethods, reachableMethods
  , hooksAt, variantLabel, entryLabel
  ) where

import Data.List (intercalate, isPrefixOf, nub)
import Data.Maybe (listToMaybe)
import Framework.Language.Registration (Access(..), EffectKind(..))
import Framework.Prototype.Graph
import Framework.Prototype.Types

workflowNode :: WorkflowTree -> NodeId
workflowNode (NodeAt identifier _) = identifier
workflowNode (ChainAt identifier _) = identifier
workflowNode (ParallelAt identifier _) = identifier
workflowNode (AlternativeAt identifier _ _) = identifier
workflowNode (LifelongAt identifier _ _) = identifier

workflowChildren :: WorkflowTree -> [WorkflowTree]
workflowChildren (NodeAt _ _) = []
workflowChildren (ChainAt _ children) = children
workflowChildren (ParallelAt _ children) = children
workflowChildren (AlternativeAt _ _ children) = children
workflowChildren (LifelongAt _ _ children) = children

workflowTerminals :: WorkflowTree -> [String]
workflowTerminals (NodeAt _ selected) = [selected]
workflowTerminals tree = concatMap workflowTerminals (workflowChildren tree)

workflowLifelongs :: WorkflowTree -> [(NodeId, LifelongProto)]
workflowLifelongs tree = [(identifier, described) | LifelongAt identifier described _ <- allWorkflow tree]

workflowSelectors :: WorkflowTree -> [String]
workflowSelectors tree = case tree of
  AlternativeAt _ selected children -> alternativeSource selected : concatMap workflowSelectors children
  _ -> concatMap workflowSelectors (workflowChildren tree)

allWorkflow :: WorkflowTree -> [WorkflowTree]
allWorkflow tree = tree : concatMap allWorkflow (workflowChildren tree)

knownWorkflowPosition :: WorkflowTree -> NodeId -> Bool
knownWorkflowPosition tree selected = any ((== selected) . workflowNode) nodes
  || selected `elem` [alternativeSelector choice | AlternativeAt _ choice _ <- nodes]
  || selected `elem` [mount | LifelongAt _ described _ <- nodes
       , session <- lifelongSessions described, mount <- sessionMounts session]
  where nodes = allWorkflow tree

lookupChain :: Prototype method -> NodeId -> Either (PrototypeError method) (ChainProto method)
lookupChain prototype identifier = case filter ((== identifier) . chainNode) (protoChains prototype) of
  [chain] -> pure chain
  _ -> Left (InvalidPrototype ("Missing or duplicate chain at " ++ show identifier))

lookupWorkflow :: WorkflowTree -> NodeId -> Maybe WorkflowTree
lookupWorkflow tree identifier = listToMaybe [node' | node' <- allWorkflow tree, workflowNode node' == identifier]

-- 以下关系给出结构上的启动先后与互斥；不作为普通共享资产的读取许可。
precedes :: WorkflowTree -> NodeId -> NodeId -> Bool
precedes tree before after = knownWorkflowPosition tree before && knownWorkflowPosition tree after
  && any orders (allWorkflow tree)
  where
    orders (ChainAt _ children) = or
      [workflowNode left `isPrefixOf` before && workflowNode right `isPrefixOf` after
      | (index, left) <- zip [0 :: Int ..] children, right <- drop (index + 1) children]
    orders (AlternativeAt _ selected children) = before == alternativeSelector selected
      && any (\child -> workflowNode child `isPrefixOf` after) children
    -- 会话是 lifelong 的共同上游；交付与普通共享值分别遵循自己的读取协议。
    orders (LifelongAt identifier _ children) = (identifier ++ [-1]) `isPrefixOf` before
      && any (\child -> workflowNode child `isPrefixOf` after) children
    orders _ = False

exclusive :: WorkflowTree -> NodeId -> NodeId -> Bool
exclusive tree left right = knownWorkflowPosition tree left && knownWorkflowPosition tree right
  && any separate (allWorkflow tree)
  where
    separate (AlternativeAt _ _ children) = or
      [workflowNode first `isPrefixOf` left && workflowNode second `isPrefixOf` right
      | first <- children, second <- children, workflowNode first /= workflowNode second]
    separate _ = False

driveSet :: Prototype method -> NodeId -> Either (PrototypeError method) [String]
driveSet prototype selected = chainDrives <$> lookupChain prototype selected

readPoints :: Prototype method -> [ReadPoint]
readPoints = map fst . protoSources

scopeOpeningsAt :: Prototype method -> NodeId -> [ScopeOpening]
scopeOpeningsAt prototype node = filter ((== node) . openingNode) (protoScopeOpenings prototype)

-- 驱动这个持续资产生产的持续资产：生产方 Input 链上的 streams demand。
-- 注册校验保证至多一个，且与直接挂在 Stream 下互斥。
drivingAssets :: [EffectProto method] -> EffectProto method -> [String]
drivingAssets effects producer = nub
  [ demandContract demand | effect <- effects, effectName effect `elem` effectInputChain producer
  , demand <- effectDemands effect, demandAccess demand == StreamAccess ]

-- 持续资产注册给出的独立生产方式：Input 链被另一份持续资产驱动时是 Derive，否则直接 input 是 Stream。
-- 某个 lifelong 已挂载生产操作时，gen 会把该边界的计划改为 ReuseOutput；此查询不重新规划。
bootPlan :: [EffectProto method] -> EffectProto method -> BootPlan
bootPlan effects producer = case drivingAssets effects producer of
  upstream : _ -> Derive upstream
  [] -> Receive (effectInput producer)

sessionSteps :: BootPlan -> Int
sessionSteps (Receive _) = 2
sessionSteps (Derive _) = 1
sessionSteps (ReuseOutput _) = 0

-- 一个 lifelong 需要的会话：被订阅的资产，以及驱动它们的上游资产，上游排在前面。
-- 注册校验已经拒绝派生关系成环；seen 只防止不一致的原型使遍历不终止。
sessionAssets :: [EffectProto method] -> [String] -> [String]
sessionAssets effects = nub . concatMap (visit [])
  where
    visit seen asset
      | asset `elem` seen = []
      | otherwise = concat [ visit (asset : seen) upstream
          | producer <- effects, effectProduces producer == Just asset
          , Derive upstream <- [bootPlan effects producer] ] ++ [asset]

-- 有限读取也能惰性建立持续生产：Receive 或 Derive 的注册关系保持不变，读取方不加入订阅。
-- 挂载 [-2, 序号, 步骤] 不属于 AST，也不是普通资产的可见前驱。上游排在前面，便于统一登记/逆序收尾。
-- 此查询只投影已校验的注册关系；gen 将结果写入 Assembly/Prototype，runtime 只执行计划。
finiteSessions :: [EffectProto method] -> [SessionProto]
finiteSessions effects =
  [ SessionProto contractType plan [[-2, index, step] | step <- [0 .. sessionSteps plan - 1]]
  | (index, (contractType, plan)) <- zip [0 ..] selected ]
  where
    assets = sessionAssets effects [contractType | effect <- effects, effectContinuous effect
      , Just contractType <- [effectProduces effect]]
    selected = [(contractType, bootPlan effects effect) | contractType <- assets, effect <- effects
      , effectProduces effect == Just contractType]

-- 候选可用的判定：候选各末端（连同 Input 祖先）requires 的、由某个 Excu 的输出直接（或经 Pure）解析出的
-- 非持续资产，记为（该 Excu，解析它的 Context）。各末端共有的才算；生成和加载校验共用。
candidateCases :: [EffectProto method] -> NodeId -> WorkflowTree
               -> Either (PrototypeError method) [(String, String)]
candidateCases effects path subtree = do
  options <- mapM terminalCases (workflowTerminals subtree)
  case options of
    [] -> Left (InvalidAlternative path "Candidate has no terminal")
    first : rest -> pure (foldr (\other kept -> filter (`elem` other) kept) first rest)
  where
    terminalCases selected = do
      effect <- findEffectProto effects selected
      let inherited = selected : effectInputChain effect
      pure (nub [ (anchorName, effectName producer)
        | consumer <- effects, effectName consumer `elem` inherited
        , demand <- effectDemands consumer, demandAccess demand == RequireAccess
        , producer <- effects, effectProduces producer == Just (demandContract demand)
        , not (effectContinuous producer), Just anchorName <- [effectAnchor producer]
        , anchor <- effects, effectName anchor == anchorName, effectKind anchor == ExcuKind ])

findEffectProto :: [EffectProto method] -> String -> Either (PrototypeError method) (EffectProto method)
findEffectProto effects selected = case filter ((== selected) . effectName) effects of
  [effect] -> Right effect
  _ -> Left (UnknownPrototypeTarget selected)

ordinaryEntry :: EffectProto method -> Either (PrototypeError method) method
ordinaryEntry effect = case [method | (role, method) <- effectMethods effect, role `elem` [HandlerMethod, ScopeOpen]] of
  method : _ -> pure method
  [] -> Left (InvalidPrototype ("Effect has no callable entry (no handler or open handler): " ++ effectName effect))

calledMethods :: MethodShape method -> [method]
calledMethods Empty = []
calledMethods (Call method) = [method]
calledMethods (Sequence children) = concatMap calledMethods children
calledMethods (Choice children) = concatMap calledMethods children
calledMethods (Recover body recovery) = calledMethods body ++ calledMethods recovery

reachableMethods :: Eq method => [MethodDefinition method] -> [method] -> [method]
reachableMethods definitions = visit []
  where
    visit seen [] = seen
    visit seen (method : rest)
      | method `elem` seen = visit seen rest
      | otherwise = visit (seen ++ [method])
          (concat [calledMethods (methodBody definition) | definition <- definitions, methodIdentity definition == method] ++ rest)

-- 查询只按身份读取 Booter 的标记；没有标记表示生成产物失配，不重跑结构推导兜底。
nodeDriveAt :: Prototype method -> NodeId -> NodeDrive
nodeDriveAt prototype node = case filter ((== node) . driveNode) (drivingNodes (protoDriving prototype)) of
  [plan] -> plan
  _ -> error ("Missing or duplicate generated node driver at " ++ show node ++ "; regenerate")

unitDriveAt :: Prototype method -> NodeId -> UnitDrive
unitDriveAt prototype node = case filter ((== node) . driveUnit) (drivingUnits (protoDriving prototype)) of
  [plan] -> plan
  _ -> error ("Missing or duplicate generated unit driver at " ++ show node ++ "; regenerate")

sessionDriveAt :: Prototype method -> Maybe NodeId -> String -> Maybe SessionDrive
sessionDriveAt prototype boundary source = case [plan | plan <- drivingSessions (protoDriving prototype)
  , driveSessionBoundary plan == boundary, driveSessionSource plan == source] of
  [plan] -> Just plan
  _ -> Nothing

describedSession :: Prototype method -> SessionDrive -> Maybe SessionProto
describedSession prototype route = case [session | session <- candidates, sessionAsset session == driveSessionAsset route] of
  [session] -> Just session
  _ -> Nothing
  where
    candidates = case driveSessionBoundary route of
      Nothing -> protoSessions prototype
      Just node -> case lookupWorkflow (protoWorkflow prototype) node of
        Just (LifelongAt _ description _) -> lifelongSessions description
        _ -> []

-- Middleware 标注 v2（2026-11-19）：注入发生在生成期。一个启动位置被哪些标注覆盖只看路径前缀，
-- 会话步骤的位置在所属 lifelong 路径下，同一规则适用；结果按 Middleware 的注册顺序排列、去重。
-- gen 按这份集合特化入口，运行时只按 entryLabel 选取已编译的 Target，不再分发。
hooksAt :: [String] -> [(NodeId, [String])] -> NodeId -> [String]
hooksAt order marks position = [selected | selected <- order
  , or [selected `elem` hooks | (root, hooks) <- marks, root `isPrefixOf` position]]

-- 特化 Target 的登记名：没有 Middleware 时就是原名。
variantLabel :: String -> [String] -> String
variantLabel base [] = base
variantLabel base hooks = base ++ "@" ++ intercalate "+" hooks

entryLabel :: DrivingPlan method -> NodeId -> String -> String
entryLabel plan position base = variantLabel base (maybe [] id (lookup position (drivingHooks plan)))
