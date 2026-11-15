-- 持续会话的生成期装配：先定位已挂载的原子输出，再安排独立生产，并检查启动依赖。
-- 只产生 Prototype 数据；运行时按该计划安装交付关系，不重新分链或选择生产者。
module Framework.Gen.Sessions (planSessions) where

import Control.Monad (unless)
import Data.Graph (SCC(..), stronglyConnComp)
import Data.List (intercalate, isPrefixOf, nub)
import Framework.Language.Registration (EffectKind(..))
import Framework.Prototype.Query
import Framework.Prototype.Types

-- 本边界的装配先定位已由 AST 执行的原子句柄，再决定哪些资产需要独立生产。
-- 同名 effect 的不同挂载仍是不同执行；多个供值位置只允许同一单元内互斥的候选。
-- 连续副产物即使只有后继 requires，也有交付状态，不能因没有订阅而丢掉发布。
planSessions :: [EffectProto method] -> NodeId -> [WorkflowTree] -> [(NodeId, String)]
                   -> Either (PrototypeError method) [SessionProto]
planSessions effects boundary children subscriptions = do
  sessions <- mapM plan (zip [0 ..] assets)
  checkStartup sessions
  checkCoverage sessions
  pure sessions
  where
    units = concat [case child of
      ParallelAt _ inner -> map workflowNode inner
      _ -> [workflowNode child] | child <- children]
    workflow = LifelongAt boundary (LifelongProto units subscriptions []) children
    mounted = [(node', effect) | NodeAt node' selected <- concatMap allWorkflow children
      , effect <- effects, effectName effect == selected]
    positions producer = [node' | Just anchor <- [effectAnchor producer], (node', target) <- mounted
      , anchor `elem` (effectName target : effectInputChain target)]
    outputs = [contractType | producer <- effects, effectContinuous producer
      , Just contractType <- [effectProduces producer], not (null (positions producer))]
    assets = sessionAssets effects (nub (map snd subscriptions ++ outputs))
    unitOf node' = [unit | unit <- units, unit `isPrefixOf` node']
    plan (index, contractType) = do
      producer <- case [effect | effect <- effects, effectProduces effect == Just contractType] of
        [effect] -> pure effect
        _ -> Left (UnknownPrototypeTarget contractType)
      let nodes = positions producer
      unless (and [unitOf left == unitOf right && exclusive workflow left right
          | (offset, left) <- zip [0 :: Int ..] nodes, right <- drop (offset + 1) nodes]) $
        Left (InvalidLifelong boundary ("Continuous asset " ++ contractType
          ++ " has several AST output positions " ++ show nodes
          ++ "; use one position, mutually exclusive positions in one unit, or refine the asset"))
      let selected = if null nodes then bootPlan effects producer else ReuseOutput nodes
      pure (SessionProto contractType selected
        [boundary ++ [-1, index, step] | step <- [0 .. sessionSteps selected - 1]])
    -- 订阅边之外，还要计入 workflow 的启动前置。否则 chained [读 A, 产 A]
    -- 虽然注册关系无环，第一条增量仍只能由正在等待它的后继产生。
    -- 保守地纳入所有候选前驱：不依赖运行时恰好选中某个分支才具有进展。
    checkStartup sessions = case [cycle' | CyclicSCC cycle' <- stronglyConnComp graph] of
      [] -> pure ()
      cycle' : _ -> Left (InvalidLifelong boundary ("Continuous startup cycle: "
        ++ intercalate " -> " (map describe cycle')
        ++ "; a producer cannot wait for a target that needs its own publication"))
      where
        graph = [(key, key, dependencies) | (key, dependencies) <- edges]
        edges = [(Left node', nub (Right asset : previous node' ++ selectors node'))
          | (node', asset) <- subscriptions]
          ++ [(Right (sessionAsset session), case sessionPlan session of
              Receive _ -> []
              Derive upstream -> [Right upstream]
              ReuseOutput nodes -> map Left nodes) | session <- sessions]
        previous node' = [Left before | (before, _) <- mounted, precedes workflow before node']
        selectors node' = [Right (alternativeContract choice)
          | AlternativeAt _ choice branches <- allWorkflow workflow
          , any (\branch -> workflowNode branch `isPrefixOf` node') branches
          , alternativeContract choice `elem` map sessionAsset sessions]
        describe (Left node') = "target " ++ show node'
        describe (Right asset) = "asset " ++ asset
    -- 同一单元只有完成本轮后才能进入下一轮。每条能到达订阅的路径都必须
    -- 已经生产，或同时启动了一条必经的生产路径，不能等本单元的下一轮来补值。
    -- 其他单元独立推进，允许等待其未来发布；这里不证明原子 IO 的进展。
    checkCoverage sessions = mapM_ check
      [(node', asset, output, nodes, unit) | (node', asset) <- subscriptions
      , (output, nodes@(source : _)) <- outputOf [] asset
      , unit <- unitOf node', unit `elem` unitOf source]
      where
        outputOf seen asset
          | asset `elem` seen = []
          | otherwise = concat [case sessionPlan session of
              ReuseOutput nodes -> [(sessionAsset session, nodes)]
              Derive upstream -> outputOf (asset : seen) upstream
              Receive _ -> []
            | session <- sessions, sessionAsset session == asset]
        check (node', asset, output, nodes, unit) = do
          -- open 复用已有实例时不执行原子方法，也没有新输出。经过该位置不能
          -- 证明本轮有交付；独立单元可以等待以后真正开启产生的输出或正常结束。
          unless (null [() | producer <- effects, effectProduces producer == Just output
              , Just anchorName <- [effectAnchor producer], anchor <- effects
              , effectName anchor == anchorName, effectKind anchor == ScopedKind]) $
            Left (InvalidLifelong node' ("Subscription to " ++ asset
              ++ " waits for a Scoped output within the same unit; reusing an open scope produces no new output"))
          case lookupWorkflow workflow unit of
            Just tree -> unless (covered nodes node' False tree) $
              Left (InvalidLifelong node' ("Subscription to " ++ asset
                ++ " has a workflow path without an output from " ++ show nodes
                ++ " in the same unit; that unit cannot reach its next execution while waiting"))
            Nothing -> Left (InvalidLifelong unit "Missing unit for an output subscription")
        covered sources target available tree = case tree of
          NodeAt node' _ -> node' /= target || available
          ChainedAt _ parts -> sequenceCovered parts available
          ParallelAt _ parts -> and
            [covered sources target (available || any (produces sources) others) child
            | child <- parts, let others = filter ((/= workflowNode child) . workflowNode) parts]
          _ -> all (covered sources target available) (workflowChildren tree)
          where
            sequenceCovered [] _ = True
            sequenceCovered (child : rest) ready = covered sources target ready child
              && sequenceCovered rest (ready || produces sources child)
        produces sources tree = case tree of
          NodeAt node' _ -> node' `elem` sources
          AlternativeAt _ _ parts -> not (null parts) && all (produces sources) parts
          _ -> any (produces sources) (workflowChildren tree)
