{-# LANGUAGE DuplicateRecordFields #-}
-- 驱动合成 v1（2026-11-18）：从 Composition 的已解析事实构造挂载与会话，
-- 之后补全运行所需静态标记；不执行 handler，不读取业务源码。
module Framework.Gen.Booter (numberWorkflow, checkMiddleware, assembleProgram, completeDriving, entryPlans, controlReads) where
import Control.Monad (forM_, unless, when)
import Data.Maybe (listToMaybe)
import Data.Graph (SCC(..), stronglyConnComp)
import Data.List (intercalate, intersect, isPrefixOf, nub, nubBy, sort)
import Framework.Gen.Plan
import Framework.Language.AST (WorkflowF(..))
import Framework.Language.Registration (EffectKind(..), Access(..))
import Framework.Prototype.Graph
import Framework.Prototype.Query
import qualified Framework.Prototype as Prototype
import Framework.Prototype.Types
import Framework.Prototype.Validate (valid, unique)
import Framework.Recursion (Fix, cata)

numberWorkflow :: [EffectProto String] -> Fix WorkflowF -> Either (PrototypeError String) WorkflowTree
numberWorkflow effects tree = cata number tree [] False
  where
    -- inside：是否位于 lifelong 内。持续订阅只能挂在 lifelong 内；lifelong 不嵌套。
    number (Node selected) path inside = do
      effect <- findEffectProto effects selected
      valid (effectKind effect `notElem` [PureKind, ContextKind, ErrorKind, StreamKind, MiddlewareKind])
        ("AST terminal must be an Excu or Scoped handle: " ++ selected
          ++ " (Pure, Context, Stream and Error run only inside their chains; Middleware is mounted with middleware)")
      _ <- ordinaryEntry effect
      let subscribed = streamedAssets effects selected
      unless (inside || null subscribed) $ Left (InvalidLifelong path ("Node " ++ selected
        ++ " subscribes to " ++ intercalate ", " subscribed ++ " with streams; mount it inside lifelong"))
      pure (NodeAt path selected)
    number (Chain children) path inside = do
      nonEmpty path inside children
      ChainAt path <$> descend path inside children
    number (Parallel children) path inside = do
      nonEmpty path inside children
      ParallelAt path <$> descend path inside children
    number (Lifelong children) path inside = do
      when inside $ Left (InvalidLifelong path "lifelong cannot be nested")
      nonEmpty path True children
      parts <- descend path True children
      -- 直接子项各为一个单元；直接子项是 parallel 时拆这一层，不穿透更深的结构。
      let units = concat [case part of
            ParallelAt _ inner -> map workflowNode inner
            _ -> [workflowNode part] | part <- parts]
      subscriptions <- mapM subscription [(node', selected) | part <- parts, NodeAt node' selected <- allWorkflow part]
      -- 先沿用本边界已经挂载的操作输出，再为其余订阅建立独立生产；副产物也登记为会话资产。
      sessions <- planSessions effects path parts subscriptions
      pure (LifelongAt path (LifelongProto units subscriptions sessions) parts)
    -- option v1（2026-11-21）：分叉点是同一个 Excu 的输出。每个候选恰好 requires 一份由它的输出解析出的
    -- 资产，判定这些资产的 Context 互不相同；选择时按候选的声明顺序取第一个解析成功的。
    -- 分叉来自不同上游的真 race 尚未实现，这里拒绝。
    number (Alternative children) path inside = do
      nonEmpty path inside children
      parts <- descend path inside children
      options <- mapM (candidateCases effects path) parts
      source <- case foldr intersect (nub (concatMap (map fst) options)) (map (nub . map fst) options) of
        [selected] -> Right selected
        [] -> invalid path ("Candidates must each require an asset parsed from the output of the same Excu"
          ++ "; alternatives over different upstreams (race) are not supported yet")
        several -> invalid path ("Candidates require assets parsed from several shared outputs ("
          ++ intercalate ", " several ++ "); the decisive output is ambiguous")
      cases <- mapM (\(part, option) -> case [context | (anchor, context) <- option, anchor == source] of
          [selected] -> Right selected
          _ -> invalid (workflowNode part) ("Candidate must require exactly one asset parsed from the output of " ++ source))
        (zip parts options)
      unless (unique cases) $
        invalid path "Candidates must require different assets; the first candidate would always be chosen"
      pure (AlternativeAt path (AlternativeProto source (path ++ [-1])
        (zip (map workflowNode parts) cases)) parts)
    descend path inside children = sequence [child (path ++ [index]) inside | (index, child) <- zip [0 ..] children]
    invalid path reason = Left (InvalidAlternative path reason)
    -- lifelong 内每条成功路径都要领取新交付；挂载的 target 都订阅持续资产，所以只需拒绝空分支。
    nonEmpty path inside children = when (inside && null children) $
      Left (InvalidLifelong path "an empty branch inside lifelong never takes a delivery")
    -- 一个挂载的 target 恰好由一份持续资产驱动；链内不再读取其他持续资产的快照，
    -- 否则执行结果取决于读取时刻（多个来源的触发组合另行设计）。
    subscription (node', selected) = case streamedAssets effects selected of
      [contractType] -> do
        let others = [other | other <- continuousReads effects selected, other /= contractType]
        unless (null others) $ Left (InvalidLifelong node' ("Node " ++ selected ++ " is driven by " ++ contractType
          ++ " and also reads continuous assets " ++ intercalate ", " others ++ "; read only its driving asset"))
        pure (node', contractType)
      [] -> Left (InvalidLifelong node' ("Node " ++ selected
        ++ " inside lifelong must subscribe to exactly one continuous asset with streams"))
      several -> Left (InvalidLifelong node' ("Node " ++ selected ++ " subscribes to several continuous assets "
        ++ intercalate ", " several ++ "; one lifelong target is driven by one asset"))
    -- 挂载解释的私有查询；仅用于当前编号与订阅检查。
    -- 一条 original chain 由末端及其 Input 祖先组成；只看这些 effect 自己声明的 streams，
    -- 不汇总 Context 生产链内部的依赖。
    originEffects :: [EffectProto method] -> String -> [EffectProto method]
    originEffects effects selected =
      [effect | effect <- effects, effectName effect `elem` (selected : concat
        [effectInputChain terminal | terminal <- effects, effectName terminal == selected])]

    streamedAssets :: [EffectProto method] -> String -> [String]
    streamedAssets effects selected = nub
      [demandContract demand | effect <- originEffects effects selected, demand <- effectDemands effect
      , demandAccess demand == StreamAccess]

    continuousReads :: [EffectProto method] -> String -> [String]
    continuousReads effects selected = nub
      [demandContract demand | effect <- originEffects effects selected, demand <- effectDemands effect
      , producer <- effects, effectContinuous producer, effectProduces producer == Just (demandContract demand)]

-- ========================================================================
-- 持续生产连接及启动证明
-- ========================================================================

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
    -- 匹配 original chain 的 target/Input，不扫描它请求的独立 Context 链。
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
      -- p 个位置要做 p*(p-1)/2 次同单元/互斥检查；exclusive 自身还遍历 workflow。
      -- 并行或顺序中都可能发生的两次输出不能靠“谁先生产”合并成同一个来源。
      unless (and [unitOf left == unitOf right && exclusive workflow left right
          | (offset, left) <- zip [0 :: Int ..] nodes, right <- drop (offset + 1) nodes]) $
        Left (InvalidLifelong boundary ("Continuous asset " ++ contractType
          ++ " has several AST output positions " ++ show nodes
          ++ "; use one position, mutually exclusive positions in one unit, or refine the asset"))
      let selected = if null nodes then bootPlan effects producer else ReuseOutput nodes
      pure (SessionProto contractType selected
        [boundary ++ [-1, index, step] | step <- [0 .. sessionSteps selected - 1]])
    -- 订阅边之外，还要计入 workflow 的启动前置。否则 chain [读 A, 产 A]
    -- 虽然注册关系无环，第一条增量仍只能由正在等待它的后继产生。
    -- 保守地纳入所有候选前驱：不依赖运行时恰好选中某个分支才具有进展。
    -- SCC 只检测这份启动依赖图；发现环就拒绝，不删边来强行安排运行。
    -- 纯 SCC 阶段与图规模相关，构边前的 precedes/selectors 查询和后面的覆盖遍历另计。
    checkStartup sessions = case [cycle' | CyclicSCC cycle' <- stronglyConnComp graph] of
      [] -> pure ()
      cycle' : _ -> Left (InvalidLifelong boundary ("Continuous startup cycle: "
        ++ intercalate " -> " (map describe cycle')
        ++ "; a producer cannot wait for a target that needs its own publication"))
      where
        graph = [(key, key, dependencies) | (key, dependencies) <- edges]
        edges = [(Left node', nub (Right asset : previous node'))
          | (node', asset) <- subscriptions]
          ++ [(Right (sessionAsset session), case sessionPlan session of
              Receive _ -> []
              Derive upstream -> [Right upstream]
              ReuseOutput nodes -> map Left nodes) | session <- sessions]
        previous node' = [Left before | (before, _) <- mounted, precedes workflow before node']
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
          ChainAt _ parts -> sequenceCovered parts available
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

-- ========================================================================
-- 入口与输出连接事实
assembleProgram :: PrototypePlan -> Either (PrototypeError String) (Assembly String)
assembleProgram plan = do
  mounted <- concat <$> mapM mountedNode (allWorkflow workflow)
  -- 选择入口按共同 Excu 登记一次；同一 Excu 上的多个 alternative 必须判定同一组 Context。
  forM_ (nub [alternativeSource choice | AlternativeAt _ choice _ <- allWorkflow workflow]) $ \source ->
    case nub [map snd (alternativeCases choice) | AlternativeAt _ choice _ <- allWorkflow workflow
        , alternativeSource choice == source] of
      [_] -> pure ()
      _ -> Left (InvalidPrototype ("Alternatives over the output of " ++ source
        ++ " decide different Contexts; use the same candidates in the same order, or another Excu"))
  selectors <- mapM mountedSelector [selected | selected@AlternativeAt {} <- allWorkflow workflow]
  sessions <- concat <$> mapM mountedSession
    describedSessions
  pure (Assembly (mounted ++ selectors ++ sessions) outputs describedSessions finite)
  where
    effects = plannedEffects plan
    workflow = plannedWorkflow plan
    finite = finiteSessions effects
    describedSessions = concatMap (lifelongSessions . snd) (workflowLifelongs workflow) ++ finite
    mountedNode (NodeAt identifier selected) = do
      effect <- findEffectProto effects selected
      method <- ordinaryEntry effect
      pure [EntryMount identifier NodeChain selected selected method]
    mountedNode _ = pure []
    -- 选择入口执行共同的 Excu；它的输出由运行时逐个交给判定 Context。
    mountedSelector (AlternativeAt _ selected _) = do
      effect <- findEffectProto effects (alternativeSource selected)
      method <- ordinaryEntry effect
      pure (EntryMount (alternativeSelector selected) SelectorChain
        (alternativeSource selected) (alternativeSource selected) method)
    mountedSelector _ = Left (InvalidPrototype "Expected alternative selector")
    mountedSession described = do
      producer <- case [effect | effect <- effects, effectProduces effect == Just (sessionAsset described)] of
        [effect] -> pure effect
        _ -> Left (UnknownPrototypeTarget (sessionAsset described))
      let entry effect role = case lookup role (effectMethods effect) of
            Just method -> pure (effectName effect, method)
            Nothing -> Left (InvalidPrototype ("Session for " ++ sessionAsset described
              ++ " has no " ++ show role ++ " method"))
      steps <- case sessionPlan described of
        Receive source -> do
          streamEffect <- findEffectProto effects source
          handle <- entry streamEffect StreamHandler
          parser <- entry producer ContextStream
          pure [handle, parser]
        Derive _ -> (: []) <$> entry producer ContextStream
        -- 沿用 AST 输出，不另建生产步骤；位置证据已经在 planSessions 的 BootPlan 中检查。
        ReuseOutput _ -> pure []
      valid (length steps == length (sessionMounts described)) ("Session steps differ for " ++ sessionAsset described)
      pure [EntryMount mount SessionChain (sessionAsset described) target method
        | (mount, (target, method)) <- zip (sessionMounts described) steps]
    -- 保留原注入顺序：同一 anchor 内先普通 Context，再持续 Context，各自按注册顺序。
    outputs =
      [ OutputConnection anchorMethod parser (effectName producer) role
      | anchor <- effects, (anchorRole, anchorMethod) <- effectMethods anchor
      , anchorRole `elem` [HandlerMethod, ScopeOpen]
      , role <- [ContextRequest, ContextStream], producer <- effects
      , effectAnchor producer == Just (effectName anchor)
      , Just parser <- [lookup role (effectMethods producer)] ]


-- 标注只能列出已注册的 Middleware；一处标注的 hook 是集合，不能为空或重复。
checkMiddleware :: [EffectProto String] -> [(NodeId, [String])] -> Either (PrototypeError String) ()
checkMiddleware effects marks = mapM_ check marks
  where
    check (path, hooks) = do
      valid (not (null hooks) && length hooks == length (nub hooks))
        ("middleware at " ++ show path ++ " lists a non-empty set of distinct hooks")
      mapM_ (\selected -> do
          effect <- findEffectProto effects selected
          valid (effectKind effect == MiddlewareKind) ("middleware lists " ++ selected ++ ", which is not a Middleware"))
        hooks

completeDriving :: Prototype method -> Prototype method
completeDriving prototype = prototype { protoDriving = DrivingPlan nodes units sessions rootNodes outputs requests
    (drivingMiddleware (protoDriving prototype)) hooks }
  where
    -- 每个启动位置（含会话步骤）的 Middleware 集合，gen 据此特化入口；不为会话另设规则。
    hooks = [(position, active) | position <- nub (map chainNode chains)
      , let active = hooksAt [effectName effect | effect <- effects, effectKind effect == MiddlewareKind]
              (drivingMiddleware (protoDriving prototype)) position
      , not (null active)]
    tree = protoWorkflow prototype
    workflow = allWorkflow tree
    effects = protoEffects prototype
    chains = protoChains prototype
    lifelongs = workflowLifelongs tree
    provider asset = case [effectName effect | effect <- effects, effectProduces effect == Just asset] of
      [source] -> source
      _ -> error ("Validated asset has no unique provider: " ++ asset)
    descriptions = [(Nothing, session) | session <- protoSessions prototype]
      ++ [(Just boundary, session) | (boundary, description) <- lifelongs, session <- lifelongSessions description]
    sessions = [SessionDrive boundary (provider (sessionAsset session)) (sessionAsset session)
      (case sessionPlan session of Derive upstream -> Just (provider upstream); _ -> Nothing)
      | (boundary, session) <- descriptions]
    requests = [(effectName effect, method) | effect <- effects, (role, method) <- effectMethods effect
      , role `elem` [ContextRequest, ContextStream]]
    positions = nub (map workflowNode workflow ++ map chainNode chains)
    rootNodes = [chainNode chain | chain <- chains, chainRole chain /= SessionChain]
    boundaryOf node = listToMaybe [boundary | (boundary, _) <- lifelongs, boundary `isPrefixOf` node]
    members position = [node | NodeAt node _ <- workflow, position `isPrefixOf` node]
    captures reader = reverse [alternativeSelector choice | AlternativeAt _ choice children <- workflow
      , any (\child -> workflowNode child `isPrefixOf` reader) children]
    candidates reader = nub (concat [candidates' | (point, FromChains candidates') <- protoSources prototype, readNode point == reader])
    blocked reader = [node | node <- candidates reader, boundaryOf node == Nothing
      , Right chain <- [lookupChain prototype node], chainRole chain /= SessionChain
      , node == reader || precedes tree reader node || exclusive tree reader node]
    nodes = [NodeDrive position (members position)
      [provider asset | (_, description) <- lifelongs, (node, asset) <- lifelongSubscriptions description, node == position]
      (boundaryOf position) (captures position)
      [boundary | (boundary, _) <- lifelongs, precedes tree boundary position] (blocked position)
      | position <- positions]
    units = [UnitDrive unit [node | node <- rootNodes, unit `isPrefixOf` node]
      [(provider asset, readers unit description asset) | session <- lifelongSessions description, let asset = sessionAsset session]
      [(provider (sessionAsset session), local session) | session <- lifelongSessions description, rooted unit description (sessionAsset session)]
      | (_, description) <- lifelongs, unit <- lifelongUnits description]
    readers unit description asset = nub $
      [ReadAt node | (node, selected) <- lifelongSubscriptions description, selected == asset, unit `isPrefixOf` node]
      ++ [ReadAt (readNode point) | (point, FromSession) <- protoSources prototype
         , readContract point == asset, unit `isPrefixOf` readNode point]
    rooted unit description asset = case [sessionPlan session | session <- lifelongSessions description, sessionAsset session == asset] of
      [ReuseOutput publishers] -> not (null publishers) && all (unit `isPrefixOf`) publishers
      [Derive upstream] -> rooted unit description upstream
      _ -> False
    local session = case sessionPlan session of
      ReuseOutput publishers -> PublishedAt publishers
      Derive upstream -> DerivedFrom (provider upstream)
      Receive _ -> error "A Receive source cannot be local to a consumer unit"
    outputs = [(node, provider (sessionAsset session)) | (Just _, session) <- descriptions
      , ReuseOutput publishers <- [sessionPlan session], node <- publishers]

sessionEntries :: (NodeId -> [String]) -> [EffectProto String] -> Assembly String -> [SessionEntry]
sessionEntries hooksAtMount effects assembly = nubBy sameEntry
  [ entry
  | effect <- effects, effectKind effect == ContextKind
  , session <- assemblySessions assembly
  , Just (sessionAsset session) == effectProduces effect
  , let entries = [mount | position <- sessionMounts session
              , mount <- assemblyMounts assembly, mountNode mount == position]
  , entry <- case (sessionPlan session, entries) of
      (Receive _, [source, parser]) -> [ReceiveEntry (effectName effect) source parser]
      (Derive _, [parser]) -> [DeriveEntry (effectName effect) parser]
      _ -> [] ]
  where
    -- 相同方法只在挂载的 Middleware 列表也相同时共享闭包。运行时按这个列表选择登记名。
    -- NodeId 留在 Assembly/Prototype；把路径本身计入身份会重复登记同一特化。
    key entry = (mountTarget entry, mountMethod entry, hooksAtMount (mountNode entry))
    sameEntry (ReceiveEntry owner a b) (ReceiveEntry owner' a' b') =
      owner == owner' && key a == key a' && key b == key b'
    sameEntry (DeriveEntry owner a) (DeriveEntry owner' a') = owner == owner' && key a == key a'
    sameEntry _ _ = False

-- workflow 控制流已经使用的读取：lifelong 订阅的 streams，以及 alternative 判定候选所依据的资产。
-- 输入链上的声明参与选择／交付，因此这些 demand 不要求 handler 方法体再读一次。
controlReads :: [Prototype.EffectProto method] -> Prototype.WorkflowTree -> [(String, String)]
controlReads effects tree = nub (walk tree ++ driven)
  where
    -- 持续资产生产链上的 streams 由上游交付驱动这条链，同样已被控制流使用。
    driven = [ (Prototype.effectName effect, demandContract demand) | producer <- effects, Prototype.effectContinuous producer
      , effect <- effects, Prototype.effectName effect `elem` Prototype.effectInputChain producer
      , demand <- Prototype.effectDemands effect, demandAccess demand == StreamAccess ]
    inherited selectedName = selectedName : concat
      [Prototype.effectInputChain effect | effect <- effects, Prototype.effectName effect == selectedName]
    demandsOf selectedName = [(Prototype.effectName effect, demand) | effect <- effects
      , Prototype.effectName effect `elem` inherited selectedName, demand <- Prototype.effectDemands effect]
    walk node' = here node' ++ concatMap walk (Prototype.workflowChildren node')
    here (Prototype.LifelongAt _ description _) =
      [ (consumer, demandContract demand) | (path, contractType) <- Prototype.lifelongSubscriptions description
      , Just (Prototype.NodeAt _ selectedName) <- [Prototype.lookupWorkflow tree path]
      , (consumer, demand) <- demandsOf selectedName
      , demandAccess demand == StreamAccess, demandContract demand == contractType ]
    here (Prototype.AlternativeAt _ description _) =
      [ (consumer, demandContract demand) | (path, context) <- Prototype.alternativeCases description
      , Just subtree <- [Prototype.lookupWorkflow tree path]
      , selectedName <- Prototype.workflowTerminals subtree
      , (consumer, demand) <- demandsOf selectedName, readsAccess (demandAccess demand)
      , producer <- effects, Prototype.effectName producer == context
      , Prototype.effectProduces producer == Just (demandContract demand) ]
    here _ = []


-- 选择入口按共同 Excu 登记：同一 Excu 上的 alternative 须判定同一组 Context（gen 在此拒绝不一致）。
entryPlans :: (NodeId -> [String]) -> [EffectProto String] -> WorkflowTree -> Assembly String -> ([SelectorPlan], [SessionEntry])
entryPlans hooksAtMount effects workflow assembly =
  ( [ SelectorPlan source method
        [ (context, request) | context <- concat (take 1 cases), effect <- effects, effectName effect == context
        , Just request <- [lookup ContextRequest (effectMethods effect)] ]
    | (source, method) <- nub [(mountTerminal mount, mountMethod mount) | mount <- assemblyMounts assembly, mountRole mount == SelectorChain]
    , let cases = nub [map snd (alternativeCases choice) | AlternativeAt _ choice _ <- allWorkflow workflow
            , alternativeSource choice == source] ]
  , sessionEntries hooksAtMount effects assembly )
