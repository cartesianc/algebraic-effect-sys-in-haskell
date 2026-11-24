{-# LANGUAGE DuplicateRecordFields #-}
-- 驱动合成 v1（2026-11-18）：从 Composition 的已解析事实构造挂载与会话，
-- 之后补全运行所需静态标记；不执行 handler，不读取业务源码。
module Framework.Gen.Booter (numberWorkflow, checkMiddleware, assembleProgram, completeDriving, entryPlans, controlReads, decidingAssets, linkedAssets, publishedWithin) where
import Control.Monad (forM_, unless)
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

-- 输入是已通过 Gen.Workflow 结构检查的规范形式；这里只做要读注册的检查。
-- 编号之后在回调图上查环：订阅回调经自身执行再次发布所订阅的资产时会无限递归。
numberWorkflow :: [EffectProto String] -> Fix WorkflowF -> Either (PrototypeError String) WorkflowTree
numberWorkflow effects tree = do
  numbered <- cata number tree [] False
  checkReactions effects numbered
  pure numbered
  where
    -- inside：是否位于 lifelong 内。持续订阅只能挂在 lifelong 内。
    number (Node selected) path inside = do
      effect <- findEffectProto effects selected
      valid (effectKind effect `notElem` [PureKind, ContextKind, ErrorKind, StreamKind, MiddlewareKind])
        ("AST terminal must be an Excu or Scoped handle: " ++ selected
          ++ " (Pure, Context, Stream and Error run only inside their chains; Middleware is mounted with middleware)")
      _ <- ordinaryEntry effect
      -- lifelong 之外的 streams 是 history：同一 effect requests 它启动或加入 interpreter 托管的会话，
      -- stream @T 读整段已发布的历史；没有 requests 时没有会话可读。
      let unstarted = [asset | asset <- streamedAssets effects selected, asset `notElem` requestedBy effect]
      unless (inside || null unstarted) $ Left (InvalidLifelong path ("Node " ++ selected
        ++ " subscribes to " ++ intercalate ", " unstarted ++ " with streams outside lifelong;"
        ++ " mount it inside lifelong, or also requests it to read its history"))
      pure (NodeAt path selected)
    number (Chain children) path inside = ChainAt path <$> descend path inside children
    number (Parallel children) path inside = ParallelAt path <$> descend path inside children
    -- lifelong 是给 gen 的标记：每个直接子项是一个单元，单元是它的驱动资产每次发布后执行一次的回调；
    -- 子项里的 parallel 只在一次回调之内并发。单元里的 target 由同一份资产驱动。
    -- 一个 lifelong 至多一个 Stream 来源；多个独立来源须显式写成 parallel 的多个 lifelong（并发须显式）。
    number (Lifelong children) path _ = do
      parts <- descend path True children
      let units = map workflowNode parts
      subscriptions <- mapM subscription [(node', selected) | part <- parts, NodeAt node' selected <- allWorkflow part]
      forM_ units $ \unit -> case nub [asset | (node', asset) <- subscriptions, unit `isPrefixOf` node'] of
        several@(_ : _ : _) -> Left (InvalidLifelong unit ("Unit is driven by several assets " ++ intercalate ", " several
          ++ "; a unit runs once per publication of one asset, so put targets driven by different assets in different units"))
        _ -> pure ()
      -- 先沿用本边界已经挂载的操作输出，再为其余订阅建立独立生产；副产物也登记为持续资产。
      sessions <- planSessions effects path parts subscriptions
      case [sessionAsset session | session <- sessions, Receive _ <- [sessionPlan session]] of
        several@(_ : _ : _) -> Left (InvalidLifelong path ("Lifelong is driven by several Stream sources ("
          ++ intercalate ", " several ++ "); write one lifelong per source and run them in parallel"))
        _ -> pure ()
      pure (LifelongAt path (LifelongProto units subscriptions sessions) parts)
    -- option v1（2026-11-21）：分叉点是同一个 Excu 的输出。每个候选恰好 requires 一份由它的输出解析出的
    -- 资产，判定这些资产的 Context 互不相同；选择时按候选的声明顺序取第一个解析成功的。
    -- 分叉来自不同上游的真 race 尚未实现，这里拒绝。
    number (Alternative children) path inside = do
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
    -- 一个挂载的 target 恰好由一份资产驱动，驱动方式由组合决定：
    -- streams 一份持续资产是 socket；requests 一份 behavior（挂在 Stream 下、stream = False）是 behavior；
    -- requests 一份普通资产是 event。lifelong 内的 requires 只采样，不驱动。
    -- 链内不再读取其他持续资产的快照，否则执行结果取决于读取时刻（多个来源的触发组合另行设计）。
    subscription (node', selected) = case drivers selected of
      _ | (asset : _) <- requestedStreams selected -> Left (InvalidLifelong node' ("Node " ++ selected ++ " requests the stream asset "
          ++ asset ++ " inside lifelong; requests takes a static history outside lifelong, subscribe with streams here"))
      [contractType] -> do
        let others = [other | other <- continuousReads effects selected, other /= contractType]
        unless (null others) $ Left (InvalidLifelong node' ("Node " ++ selected ++ " is driven by " ++ contractType
          ++ " and also reads continuous assets " ++ intercalate ", " others ++ "; read only its driving asset"))
        pure (node', contractType)
      [] -> Left (InvalidLifelong node' ("Node " ++ selected
        ++ " inside lifelong must be driven by exactly one asset: streams a continuous asset (socket),"
        ++ " or requests a behavior or an ordinary asset (event)"))
      several -> Left (InvalidLifelong node' ("Node " ++ selected ++ " is driven by several assets "
        ++ intercalate ", " several ++ "; one lifelong target is driven by one asset"))
    drivers selected = nub (streamedAssets effects selected ++ case findEffectProto effects selected of
      Right effect -> [asset | asset <- requestedBy effect, asset `notElem` continuousOnly]
      Left _ -> [])
    -- lifelong 内不能 requests stream = True 的资产：requests 是 lifelong 之外的静态历史，这里订阅要写 streams。
    requestedStreams selected = case findEffectProto effects selected of
      Right effect -> [asset | asset <- requestedBy effect, asset `elem` continuousOnly]
      Left _ -> []
    -- behavior 与普通资产的 requests 是订阅。
    continuousOnly = [asset | producer <- effects, effectContinuous producer, not (effectSampled producer)
      , Just asset <- [effectProduces producer]]
    -- target 自己声明的 requests；Scoped 请求的资源 Context 是开启输入，不是订阅。
    requestedBy effect = [demandContract demand | demand <- effectDemands effect, demandAccess demand == RequestAccess
      , Just (demandProvider demand) /= effectResource effect]
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
planSessions effects boundary children subscriptions = mapM plan (zip [0 ..] assets)
  where
    mounted = [(node', effect) | NodeAt node' selected <- concatMap allWorkflow children
      , effect <- effects, effectName effect == selected]
    -- 匹配 original chain 的 target/Input，不扫描它请求的独立 Context 链。
    positions producer = [node' | Just anchor <- [effectAnchor producer], (node', target) <- mounted
      , anchor `elem` (effectName target : effectInputChain target)]
    continuous = [contractType | producer <- effects, effectContinuous producer, Just contractType <- [effectProduces producer]]
    outputs = [contractType | producer <- effects, effectContinuous producer
      , Just contractType <- [effectProduces producer], not (null (positions producer))]
    -- event 订阅的普通资产没有生产方式：回调接在它的锚点后面，不进入这里。
    assets = sessionAssets effects (nub ([asset | (_, asset) <- subscriptions, asset `elem` continuous] ++ outputs))
    plan (index, contractType) = do
      producer <- case [effect | effect <- effects, effectProduces effect == Just contractType] of
        [effect] -> pure effect
        _ -> Left (UnknownPrototypeTarget contractType)
      let nodes = positions producer
          selected = if null nodes then bootPlan effects producer else ReuseOutput nodes
      pure (SessionProto contractType selected
        [boundary ++ [-1, index, step] | step <- [0 .. sessionSteps selected - 1]])

-- 回调图：资产 → 它的回调执行时可能发布的资产。订阅单元执行它的 target（连同 Input 链与 requests 的传递闭包），
-- 其中的锚点经输出联立发布挂在下面的资产；派生资产由上游的发布驱动。图上有环时回调会无限递归，拒绝。
-- 按注册保守计算：不区分回调是否同时有效，也不证明条件分支。
checkReactions :: [EffectProto method] -> WorkflowTree -> Either (PrototypeError method) ()
checkReactions effects tree = case [cycle' | CyclicSCC cycle' <- stronglyConnComp graph] of
  [] -> pure ()
  cycle' : _ -> Left (InvalidLifelong (locate cycle') ("Subscription cycle " ++ intercalate " -> " (cycle' ++ take 1 cycle')
    ++ ": a callback publishes the asset it is subscribed to again, so it would run forever;"
    ++ " run the publishing anchor outside the subscribing lifelong"))
  where
    graph = [(asset, asset, reactionPublishes effects tree asset)
      | asset <- nub (map snd (subscriptionsOf tree) ++ [asset | effect <- effects, Just asset <- [effectProduces effect]])]
    locate cycle' = case [node' | (node', asset) <- subscriptionsOf tree, asset `elem` cycle'] of
      node' : _ -> node'
      [] -> []

subscriptionsOf :: WorkflowTree -> [(NodeId, String)]
subscriptionsOf tree = [(node', asset) | (_, described) <- workflowLifelongs tree, (node', asset) <- lifelongSubscriptions described]

-- 资产发布之后，回调表接着可能发布的资产：订阅它的单元执行一次可能发布的，以及由它驱动的派生资产。
reactionPublishes :: [EffectProto method] -> WorkflowTree -> String -> [String]
reactionPublishes effects tree asset = nub $
  concat [executionPublishes effects (Just asset) selected | (node', subscribed) <- subscriptionsOf tree, subscribed == asset
    , Just (NodeAt _ selected) <- [lookupWorkflow tree node']]
  ++ [derived | producer <- effects, effectContinuous producer, asset `elem` drivingAssets effects producer
     , Just derived <- [effectProduces producer]]

-- 一次执行 selected 可能发布的资产：自身与 Input 链，以及 requests 拉取的生产链（传递闭包）里的 requests 产物
-- 与锚点经输出联立发布的资产。回调交付的资产（delivered）在本次执行里已记为发布，对它的 requests 直接读交付，
-- 不执行它的生产链。
executionPublishes :: [EffectProto method] -> Maybe String -> String -> [String]
executionPublishes effects delivered selected = nub
  ([demandContract demand | effect <- executed, demand <- effectDemands effect
     , demandAccess demand == RequestAccess, Just (demandContract demand) /= delivered]
   ++ [asset | producer <- effects, Just anchor <- [effectAnchor producer], anchor `elem` map effectName executed
      , Just asset <- [effectProduces producer]])
  where
    executed = closure [] [selected]
    closure seen [] = [effect | effect <- effects, effectName effect `elem` seen]
    closure seen (name : rest)
      | name `elem` seen = closure seen rest
      | otherwise = closure (name : seen) (rest ++ chainOf name ++ requested name)
    chainOf name = concat [effectInputChain effect | effect <- effects, effectName effect == name]
    requested name = [effectName producer | effect <- effects, effectName effect == name, demand <- effectDemands effect
      , demandAccess demand == RequestAccess, Just (demandContract demand) /= delivered
      , producer <- effects, effectProduces producer == Just (demandContract demand)]

-- 一棵 workflow 子树执行期间可能发布的资产（gen 写在 parallel 的每个分支上，供其他分支的 require 判断是否等待）：
-- 子树里的节点与选择读取执行一次可能发布的；子树里 lifelong 的持续资产，以及它的来源与 parser 入口执行时
-- 可能发布的（例如 Stream 来源 requests 的普通资产）；再沿回调表取传递闭包。
-- 按注册保守计算：不区分条件分支是否执行，多算只会让读取方多等到该分支退出。
publishedWithin :: [EffectProto method] -> WorkflowTree -> WorkflowTree -> [String]
publishedWithin effects tree subtree = grow [] direct
  where
    direct = nub $
      concat [executionPublishes effects Nothing selected | NodeAt _ selected <- allWorkflow subtree]
      ++ concat [executionPublishes effects Nothing (alternativeSource choice)
                   ++ [asset | (_, judge) <- alternativeCases choice, effect <- effects, effectName effect == judge
                      , Just asset <- [effectProduces effect]]
                | AlternativeAt _ choice _ <- allWorkflow subtree]
      ++ concat [sessionAsset session : concat [executionPublishes effects Nothing (effectName producer)
                   | producer <- effects, effectProduces producer == Just (sessionAsset session)]
                | (_, described) <- workflowLifelongs subtree, session <- lifelongSessions described]
    grow seen [] = reverse seen
    grow seen (asset : rest)
      | asset `elem` seen = grow seen rest
      | otherwise = grow (asset : seen) (rest ++ reactionPublishes effects tree asset ++ drivenFrom asset)
    -- 持续资产的生产总是从根来源开始（静态运行与 lifelong 都是）：驱动它的上游资产，以及各自的来源与 parser
    -- 入口执行时可能发布的。例如 requests 派生资产 RunningTotal 的静态运行会发布根资产 TextLine。
    drivenFrom asset = concat
      [ upstream : concat [executionPublishes effects Nothing (effectName source)
          | source <- effects, effectProduces source == Just upstream]
      | producer <- effects, effectContinuous producer, effectProduces producer == Just asset
      , upstream <- sessionAssets effects [asset], upstream /= asset ]

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
    -- 输出联立：锚点每次执行，挂在它下面的生产分支都读这次输出。普通分支只在资产有人读取时挂接，
    -- alternative 的判定资产由选择读取生产，不挂接；持续分支只在原型指定的发布位置生效。
    -- 同一 anchor 内先普通 Context，再持续 Context，各自按注册顺序。
    outputs =
      [ OutputConnection anchorMethod parser (effectName producer) role
      | anchor <- effects, (anchorRole, anchorMethod) <- effectMethods anchor
      , anchorRole `elem` [HandlerMethod, ScopeOpen]
      , role <- [ContextRequest, ContextStream], producer <- effects
      , effectAnchor producer == Just (effectName anchor)
      , role == ContextStream || maybe False (`elem` linkedAssets effects workflow) (effectProduces producer)
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

-- alternative 的判定资产：由选择读取（chooseCase）依次解析共同句柄的输出产生，不经句柄注入。
decidingAssets :: [EffectProto method] -> WorkflowTree -> [String]
decidingAssets effects workflow = nub
  [contractType | AlternativeAt _ choice _ <- allWorkflow workflow, (_, caseName) <- alternativeCases choice
  , effect <- effects, effectName effect == caseName, Just contractType <- [effectProduces effect]]

-- 输出联立的普通资产：挂在锚点下、有人读取、且不是判定资产。锚点每次执行都解析并写入最新值。
linkedAssets :: [EffectProto method] -> WorkflowTree -> [String]
linkedAssets effects workflow = nub
  [contractType | producer <- effects, Just _ <- [effectAnchor producer], not (effectContinuous producer)
  , Just contractType <- [effectProduces producer]
  , contractType `elem` [demandContract demand | effect <- effects, demand <- effectDemands effect]
  , contractType `notElem` decidingAssets effects workflow]
