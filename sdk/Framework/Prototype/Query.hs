-- 只读的原型结构查询。NodeId 的先后与互斥只来自既有 workflow，
-- 不根据线程完成时序推断旁支可见性，也不修改资产、scope 或会话状态。
module Framework.Prototype.Query
  ( workflowNode, workflowChildren, workflowTerminals, workflowLifelongs, workflowSelectors
  , allWorkflow, lookupChain, lookupWorkflow, precedes, exclusive, visibleFrom
  , driveSet, readPoints, scopeOpeningsAt, bootPlan, sessionSteps
  , finiteSessions, candidateCase, findEffectProto, ordinaryEntry, selectorMethod, calledMethods, reachableMethods
  ) where

import Data.List (isPrefixOf, nub)
import Data.Maybe (listToMaybe)
import Framework.Language.Registration (Access(..))
import Framework.Prototype.Graph
import Framework.Prototype.Types

workflowNode :: WorkflowTree -> NodeId
workflowNode (NodeAt identifier _) = identifier
workflowNode (ChainedAt identifier _) = identifier
workflowNode (ParallelAt identifier _) = identifier
workflowNode (AlternativeAt identifier _ _) = identifier
workflowNode (LifelongAt identifier _ _) = identifier

workflowChildren :: WorkflowTree -> [WorkflowTree]
workflowChildren (NodeAt _ _) = []
workflowChildren (ChainedAt _ children) = children
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
  AlternativeAt _ selected children -> alternativeContract selected : concatMap workflowSelectors children
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

-- 以下关系只给出结构上的先后、互斥与可见性；实际读取仍须核对本次发布与捕获。
precedes :: WorkflowTree -> NodeId -> NodeId -> Bool
precedes tree before after = knownWorkflowPosition tree before && knownWorkflowPosition tree after
  && any orders (allWorkflow tree)
  where
    orders (ChainedAt _ children) = or
      [workflowNode left `isPrefixOf` before && workflowNode right `isPrefixOf` after
      | (index, left) <- zip [0 :: Int ..] children, right <- drop (index + 1) children]
    orders (AlternativeAt _ selected children) = before == alternativeSelector selected
      && any (\child -> workflowNode child `isPrefixOf` after) children
    -- 会话是 lifelong 的共同上游：会话挂载先于全部单元；单元之间、各次执行之间互不可见。
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

visibleFrom :: WorkflowTree -> NodeId -> NodeId -> Bool
visibleFrom tree source target = source == target && knownWorkflowPosition tree source
  || precedes tree source target

driveSet :: Prototype method -> NodeId -> Either (PrototypeError method) [String]
driveSet prototype selected = chainDrives <$> lookupChain prototype selected

readPoints :: Prototype method -> [ReadPoint]
readPoints = map fst . protoSources

scopeOpeningsAt :: Prototype method -> NodeId -> [ScopeOpening]
scopeOpeningsAt prototype node = filter ((== node) . openingNode) (protoScopeOpenings prototype)

-- 持续资产的 Input 一定是 Stream（注册校验保证）；会话从它接收。
bootPlan :: [EffectProto method] -> EffectProto method -> BootPlan
bootPlan _ producer = Receive (effectInput producer)

sessionSteps :: BootPlan -> Int
sessionSteps (Receive _) = 2

-- 每个 Receive 资产一份 interpreter 托管的会话，挂载为 [-2, 序号, 步骤]；不属于 AST，
-- 不作为任何读取点的可见前驱，只在 lifelong 外的有限 require 缺少交付时惰性启动。
finiteSessions :: [EffectProto method] -> [SessionProto]
finiteSessions effects =
  [ SessionProto contractType plan [[-2, index, step] | step <- [0 .. sessionSteps plan - 1]]
  | (index, (contractType, plan)) <- zip [0 ..] receiving ]
  where
    receiving = [(contractType, plan) | effect <- effects, effectContinuous effect
      , Just contractType <- [effectProduces effect], let plan = bootPlan effects effect]

-- 候选对应只读 effect 原型中的 requires 与 Input 祖先；生成和加载校验共用。
candidateCase :: [EffectProto method] -> NodeId -> WorkflowTree
              -> Either (PrototypeError method) (String, String)
candidateCase effects path subtree = do
  cases <- mapM terminalCase (workflowTerminals subtree)
  case nub cases of
    [selected] -> pure selected
    _ -> invalid "Every candidate terminal must select the same constructor"
  where
    terminalCase selected = do
      effect <- findEffectProto effects selected
      let inherited = selected : effectInputChain effect
          cases = nub [(base, constructor)
            | consumer <- effects, effectName consumer `elem` inherited
            , demand <- effectDemands consumer, demandAccess demand == RequireAccess
            , producer <- effects, Just base <- [effectProduces producer]
            , (branch, constructor) <- effectBranches producer, branch == demandContract demand]
      case cases of
        [selectedCase] -> pure selectedCase
        _ -> invalid ("Candidate must require exactly one branch contract: " ++ selected)
    invalid reason = Left (InvalidAlternative path reason)

findEffectProto :: [EffectProto method] -> String -> Either (PrototypeError method) (EffectProto method)
findEffectProto effects selected = case filter ((== selected) . effectName) effects of
  [effect] -> Right effect
  _ -> Left (UnknownPrototypeTarget selected)

ordinaryEntry :: EffectProto method -> Either (PrototypeError method) method
ordinaryEntry effect = case [method | (role, method) <- effectMethods effect, role `elem` [HandlerMethod, ScopeOpen]] of
  method : _ -> pure method
  [] -> Left (InvalidPrototype ("Effect has no callable entry (no handler or open handler): " ++ effectName effect))

-- alternative 选择读取的入口：自己驱动转折资产（生产入口，相当于 requests）；
-- 持续资产由会话驱动，选择读取它的读取入口，领取本次交付。
selectorMethod :: EffectProto method -> Maybe method
selectorMethod effect = lookup (if effectContinuous effect then ContextRequire else ContextRequest) (effectMethods effect)

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
