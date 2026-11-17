{-# LANGUAGE ExistentialQuantification #-}

-- 只读 Prototype 的运行实例：活动 chain、Origin 资产表、scope 引用和发布信号。
-- 同时持有唯一的会话登记表；登记／停止的原子边界在这里，生产线程由 Runtime 启动。
-- 生命周期：Execution 创建并安装树关系；App 更新调用与发布；Execution 退出时
-- 关闭会话登记并等待任务，再退休根帧；Program 只报告清理中记录的问题。
-- 运行不解释图边；业务仍由已经装配的闭包执行。
module Framework.Runtime.Graph
  ( RuntimeGraph(..), PrototypeReference(..), ChainReference(..), Activation(..)
  , newRuntimeGraph, configureRuntimeScopes, collectRuntimeScopes, finishRuntime, newOrigin
  , beginActivation, endActivation, withRuntimeRetention, collectRetainedScopes
  , publishAsset, publicationSignal, readVisibleAsset, contextMayPublish, resetOrigins
  , installSessionLauncher, obtainSession, endedSession, stopSessions, currentPublications, reusesOutputAt
  ) where

import Control.Concurrent.MVar (MVar, modifyMVar, modifyMVar_, newMVar, readMVar, tryReadMVar)
import Control.Exception (SomeAsyncException, SomeException, evaluate, finally, fromException, mask, onException, throwIO, try, uninterruptibleMask_)
import Control.Monad (forM, forM_, void)
import Data.IORef (IORef, atomicModifyIORef', newIORef, readIORef, writeIORef)
import Data.List (isPrefixOf, nub)
import Data.Maybe (fromMaybe, isJust)
import qualified Data.Sequence as Seq
import Framework.Runtime.Protocol (ContextFault(..))
import Framework.Prototype.Graph (MethodRole(..))
import Framework.Runtime.Identity
import Framework.Runtime.Frame
import Framework.Runtime.Binding (Binding(..), readBindingOwner)
import Framework.Runtime.Retention
import Framework.Runtime.Session (Session, SessionKey, View, newSession, stopSession, currentView
  , attachReader, leaveSession, feedSession, breakSession, upstreamOf, awaitUpstream, pendingBindings)
import Framework.Runtime.Scope
  ( Scopes, ScopeBinding, ScopeBindings, ScopeUser(..), ScopeHandler(..), ScopeInstance(..), ScopeRecord(..), ScopeInput(..)
  , configureScopeRelations, cleanupAvailable, saveCleanupFailures )
import Framework.Prototype
import Framework.Prototype.Structure (scopeRelations)

-- 保存生成区真正的 MethodGen 身份及同一份 Prototype；不复制成字符串图。
data PrototypeReference = forall method. (Eq method, Show method) =>
  PrototypeReference (Prototype method)

data ChainReference = forall method. Show method =>
  ChainReference (ChainDefinition method)

instance Show ChainReference where
  showsPrec precedence (ChainReference definition) = showsPrec precedence definition

data Activation environment cause = Activation
  { activationId :: ActivationId
  , activationParent :: Maybe ActivationId
  , activationBoot :: Boot
  , activationExecution :: Execution
  , activationDefinition :: ChainReference
  , activationBindings :: IORef (ScopeBindings environment cause)
  , activationUser :: ScopeUser environment cause
  }

data RuntimeGraph environment cause = RuntimeGraph
  { runtimePrototype :: PrototypeReference
  , runtimeScopes :: Scopes environment cause
  , runtimeRootFrame :: ExecutionFrame
  , runtimeRetentions :: Retentions environment cause
  -- 发布时无归属的资产按 Origin 分组；后续认领保留同一引用，读取再检查共享 owner。
  -- 同一来源内只替换该入口自己的最新绑定，旧引用不会指向后来的 request 产物。
  , runtimeAssets :: IORef [((Origin, String), ScopeBinding environment cause)]
  -- 有限 AST 每个挂载只启动一次；完成后只保留身份，供后继读取，不保留其 activation。
  , runtimeOrigins :: IORef [(NodeId, Origin)]
  , runtimeActivations :: MVar [(ActivationId, Activation environment cause)]
  , runtimeOriginSequence :: IORef Integer
  , runtimeActivationSequence :: IORef Integer
  -- 生产会话按（lifelong 边界，资产）共享；生产任务由运行层安装的启动函数创建。
  -- Nothing：运行正在结束，会话已经全部交给停止，不再创建新会话。
  , runtimeSessions :: MVar (Maybe [(SessionKey, Session environment cause)])
  , runtimeLauncher :: IORef (Session environment cause -> IO ())
  -- lifelong 会话的生产挂载：其普通发布只作为交付的伴随发布读取。
  , runtimeSessionMounts :: [NodeId]
  -- 已装配的原始链输出路由；从 Prototype 投影一次，发布时不重新遍历整张图。
  , runtimeOutputSites :: [(NodeId, String)]
  -- lifelong 单元各位置在先前各轮的最新发布（每个位置、每个来源一份）。新一轮开始时，
  -- 上一轮的发布移到这里，轮内读取看不到它；只有 lifelong 之外的读取（后继）才查这里。
  , runtimeRetained :: IORef [((NodeId, String), ScopeBinding environment cause)]
  }

newRuntimeGraph
  :: (Eq method, Show method)
  => Prototype method -> Scopes environment cause -> IO (RuntimeGraph environment cause)
newRuntimeGraph prototype scopes = do
  coordinator <- case scopes of
    first : _ -> readIORef (scopeCoordinator first)
    [] -> newMVar ()
  frame <- newExecutionFrame coordinator Nothing Nothing
    [chainNode chain | chain <- protoChains prototype, chainRole chain /= SessionChain]
  retentions <- newRetentions coordinator
  RuntimeGraph (PrototypeReference prototype) scopes frame retentions
    <$> newIORef [] <*> newIORef [] <*> newMVar [] <*> newIORef 0 <*> newIORef 0
    <*> newMVar (Just []) <*> newIORef (const (ioError (userError "No session launcher is installed")))
    <*> pure [mount | (_, described) <- workflowLifelongs (protoWorkflow prototype)
           , session <- lifelongSessions described, mount <- sessionMounts session]
    <*> pure [(node, effectName effect) | (_, described) <- workflowLifelongs (protoWorkflow prototype)
           , session <- lifelongSessions described, ReuseOutput nodes <- [sessionPlan session], node <- nodes
           , effect <- protoEffects prototype, effectProduces effect == Just (sessionAsset session)]
    <*> newIORef []

-- ScopeTree 的独立构建与校验仍在 Prototype；这里只把同一树的关系装入现有控制对象。
configureRuntimeScopes :: RuntimeGraph environment cause -> IO ()
configureRuntimeScopes graph = case runtimePrototype graph of
  PrototypeReference prototype -> do
    configureScopeRelations (scopeRelations prototype) (runtimeScopes graph)
    forM_ (runtimeScopes graph) $ \family ->
      writeIORef (scopeReachable family) $ \slot -> do
        held <- retainedInstance graph slot
        if held then pure True else reachableInstance graph slot

-- Binding 保留 v1（2026-11-18）：实际交付/捕获、未领取队列、仍合法可读的最新值。
-- 仅检查共享 ownership，既不解释业务字段，也不把持有关系加入 ScopeTree。
-- 调用方已经持有 scope/frame 协调锁；会话目录忙时保守保留，不反向等待启动锁。
retainedInstance :: RuntimeGraph environment cause -> ScopeInstance environment cause -> IO Bool
retainedInstance graph slot = case runtimePrototype graph of
  PrototypeReference prototype -> do
    active <- retainedBindings (runtimeRetentions graph)
    held <- ownsAny active
    if held then pure True else do
      registry <- tryReadMVar (runtimeSessions graph)
      case registry of
        Nothing -> pure True
        Just registered -> do
          let sessions = fromMaybe [] registered
          queued <- concat <$> mapM (pendingBindings . snd) sessions
          inQueue <- ownsAny queued
          if inQueue then pure True else do
            frames <- framePendingViews (runtimeRootFrame graph)
            publications@(Publications origins assets _) <- readPublications graph
            let selected frame point source plan = case plan of
                  FromSession
                    -- 根帧的 lifelong 预约代表未来轮次，不能拿最新一条代替尚未领取的交付。
                    | frameParent frame == Nothing
                    , any (\(boundary, _) -> boundary `isPrefixOf` readNode point)
                        (workflowLifelongs (protoWorkflow prototype)) -> pure []
                    | otherwise -> do
                        let session = case frameBoundary frame >>= \boundary -> lookup (Just boundary, source) sessions of
                              Just local -> Just local
                              Nothing -> sessionForReader prototype sessions (readNode point) source
                        case session of
                          Nothing -> pure []
                          Just found -> do
                            value <- currentView found
                            case value >>= lastBinding of
                              Nothing -> pure []
                              Just bound -> do
                                pending <- maybe (pure Nothing) (pendingSessionInput frame source) (bindingProduction bound)
                                pure [bound | pending /= Just False]
                  FromOwnChain -> pure [value | Just origin <- [lookup (readNode point) origins]
                    , Just value <- [lookup (origin, source) assets]]
                  FromChains nodes -> pure $ case selectPublication (runtimePrototype graph) (readNode point) source
                    [value | node <- nodes, node `notElem` runtimeSessionMounts graph
                      , Just value <- [publicationAt (runtimePrototype graph) publications (readNode point) source node]] of
                    Right (Just value) -> [value]
                    _ -> []
            future <- concat <$> sequence [selected frame point source plan
              | (frame, pending, _) <- frames, (point, plan) <- protoSources prototype, readNode point `elem` pending
              , effect <- protoEffects prototype, effectProduces effect == Just (readContract point)
              , let source = effectName effect]
            ownsAny future
  where
    ownsAny values = or <$> mapM (fmap (maybe False ((== scopeRecord slot) . scopeRecord . snd)) . readBindingOwner) values
    lastBinding view = case Seq.viewr view of
      Seq.EmptyR -> Nothing
      _ Seq.:> value -> Just value

-- 保留根的寿命由调用/轮帧/派生步骤包围，不由 Haskell 对象何时 GC 决定。
withRuntimeRetention :: RuntimeGraph environment cause -> (Retention environment cause -> IO value) -> IO value
withRuntimeRetention graph = withRetention (runtimeRetentions graph) (collectRetainedScopes graph)

-- 释放交付可能涉及本节点 Input 链外的已知 owner，不能只检查该节点的开启计划。
-- 仍复用既有 close 预约、父子顺序、错误报告与取消协议。
collectRetainedScopes :: RuntimeGraph environment cause -> [ScopeBinding environment cause] -> IO ()
collectRetainedScopes _ [] = pure ()
collectRetainedScopes graph values = case runtimePrototype graph of
  PrototypeReference prototype -> do
    owners <- mapM readBindingOwner values
    let selected = nub [name | Just (name, _) <- owners]
        relations = scopeRelations prototype
        ancestors names = let expanded = nub (names ++ concat [parents | (name, parents) <- relations, name `elem` names])
                          in if expanded == names then names else ancestors expanded
        relevant = ancestors selected
    collectScopes graph (filter ((`elem` relevant) . scopeName) (runtimeScopes graph))

-- 待用查询 v3（2026-11-17）：普通参数沿发布表匹配；持续参数沿固定视图/游标匹配。
-- 查询在 scope 协调锁内，不领取、不生产。会话目录正在启动时保守保留，不能等目录锁：
-- 启动步骤会取得同一帧协调锁。会话状态锁内没有反向取得帧锁或执行业务的操作。
reachableInstance :: RuntimeGraph environment cause -> ScopeInstance environment cause -> IO Bool
reachableInstance graph slot = case runtimePrototype graph of
  PrototypeReference prototype -> do
    local <- framePendingViews (scopeFrame slot)
    root <- framePendingViews (runtimeRootFrame graph)
    let following = case frameBoundary (scopeFrame slot) of
          Nothing -> []
          Just boundary -> [(frame, filter (precedes (protoWorkflow prototype) boundary) pending, delivered)
            | (frame, pending, delivered) <- root]
        -- 同一持续交付可以被多个单元领取；沿各自的游标判断，不把资源归属提升到根帧。
        continuous source = any (\effect -> effectName effect == source && effectContinuous effect) (protoEffects prototype)
        -- 资源参数沿已有 owner 开启计划追到持续输入；子 scope 与父实例使用同一查询范围。
        fromSession seen source
          | continuous source = True
          | source `elem` seen = False
          | otherwise = or [any (fromSession (source : seen)) (effectOpeningInputs owner)
              | owner <- protoEffects prototype, effectResource owner == Just source]
        shared = if any (\(ScopeInput source _) -> fromSession [] source) (scopeInputs slot)
          then [view | view@(frame, _, _) <- root, isJust (frameParent frame)] else []
    publications <- readPublications graph
    registry <- tryReadMVar (runtimeSessions graph)
    instances <- concat <$> mapM (readMVar . scopeInstances) (runtimeScopes graph)
    snapshots <- forM instances $ \instance' -> do
      values <- scopeBindings <$> readIORef (scopeRecord instance')
      pure (instance', values)
    let candidates = [(frame, opening, delivered) | (frame, pending, delivered) <- nub (local ++ following ++ shared)
          , opening <- protoScopeOpenings prototype
          , openingNode opening `elem` pending, openingScope opening == scopeName (scopeFamily slot)]
        matches instance' frame delivered opening =
          and <$> mapM (matchesInput frame delivered opening) (scopeInputs instance')
        matchesInput frame delivered opening (ScopeInput source production) = case lookup source (openingSources opening) of
          Nothing -> pure False
          Just FromSession -> matchesSession frame opening source production
          Just FromOwnChain -> pure False -- 原型校验拒绝不明确的开启来源。
          Just (FromChains nodes)
            | any ((== Just source) . effectResource) (protoEffects prototype) ->
                -- 资源复用不重新发布：按原生产身份找到 owner，再验证同一入口会开启它。
                -- ScopeTree 已保证无环，不能用同注册的其他实例代替这个 owner。
                or <$> sequence [matches parent frame delivered parentOpening | (parent, values) <- snapshots
                   , scopeContextSource (scopeFamily parent) == Just source
                   , Just value <- [lookup source values], bindingProduction value == Just production
                   , parentOpening <- protoScopeOpenings prototype
                   , openingNode parentOpening == openingNode opening
                   , openingScope parentOpening == scopeName (scopeFamily parent)]
            | all (outsideLifelong (runtimePrototype graph) (openingNode opening)) nodes ->
                -- 后继先按真实读取规则选最新候选，再比较身份；不能让已被覆盖的旧值保活。
                pure $ case selectPublication (runtimePrototype graph) (openingNode opening) source
                  [value | node <- nodes
                    , Just value <- [publicationAt (runtimePrototype graph) publications (openingNode opening) source node]] of
                  Right (Just value) -> bindingProduction value == Just production
                  _ -> False
            | otherwise -> pure (any (matchesPublication delivered (openingNode opening) source production) nodes)
        matchesPublication delivered reader source production node =
          case [captured | (publishedAt, context, captured) <- delivered, publishedAt == node, context == source] of
            captured : _ -> captured == production
            [] -> case publicationAt (runtimePrototype graph) publications reader source node of
              Just value -> bindingProduction value == Just production
              Nothing -> False
        matchesSession frame opening source production = do
          captured <- capturedSessionInputs frame
          let reader = openingNode opening
              -- 只有 alternative 把捕获交给候选；chained 不隐式传递前一调用的视图。
              selectors = [alternativeSelector choice
                | AlternativeAt _ choice children <- allWorkflow (protoWorkflow prototype)
                , any (\child -> workflowNode child `isPrefixOf` reader) children]
              selected = [value | at <- reader : reverse selectors
                , (node, context, value) <- captured, node == at, context == source]
          case selected of
            value : _ -> pure (value == production)
            [] -> do
              pending <- pendingSessionInput frame source production
              case pending of
                Just result -> pure result
                Nothing
                  -- 根帧里的未来轮次不是旧交付的读取方；实际活动轮帧有自己的游标。
                  | any (\(boundary, _) -> boundary `isPrefixOf` reader)
                      (workflowLifelongs (protoWorkflow prototype)) -> pure False
                  | otherwise -> case registry of
                      Nothing -> pure True
                      Just registered -> case sessionForReader prototype (fromMaybe [] registered) reader source of
                        Nothing -> pure False
                        Just session -> do
                          view <- currentView session
                          pure $ case view >>= lastProduction of
                            Just current -> current == production
                            Nothing -> False
    or <$> mapM (\(frame, opening, delivered) -> matches slot frame delivered opening) candidates
  where
    lastProduction view = case Seq.viewr view of
      Seq.EmptyR -> Nothing
      _ Seq.:> value -> bindingProduction value

-- 节点退休后只检查其开启位置及 ScopeTree 祖先。预约在进度写入的锁外进行，
-- 业务 close 失败和普通 IO 异常留作汇总；只有取消停止后续执行。
collectRuntimeScopes :: RuntimeGraph environment cause -> [NodeId] -> IO ()
collectRuntimeScopes _ [] = pure ()
collectRuntimeScopes graph retired = case runtimePrototype graph of
  PrototypeReference prototype -> do
    let selected = nub [openingScope opening | opening <- protoScopeOpenings prototype
          , openingNode opening `elem` retired]
        relations = scopeRelations prototype
        ancestors names = let expanded = nub (names ++ concat [parents | (name, parents) <- relations, name `elem` names])
                          in if expanded == names then names else ancestors expanded
        relevant = ancestors selected
        handlers = filter ((`elem` relevant) . scopeName) (runtimeScopes graph)
    collectScopes graph handlers

-- 所有受控任务已退出、根帧已退休；与节点结束使用同一个可达性条件。
-- 卸下回调，生成句柄不再通过它保留整次已结束运行的资产表。
finishRuntime :: RuntimeGraph environment cause -> IO ()
finishRuntime graph = (clearRetentions (runtimeRetentions graph) >> collectScopes graph (runtimeScopes graph)) `finally`
  forM_ (runtimeScopes graph) (\family -> writeIORef (scopeReachable family) (const (pure False)))

collectScopes :: RuntimeGraph environment cause -> Scopes environment cause -> IO ()
collectScopes graph handlers = do
  failures <- cleanupAvailable handlers
  saveCleanupFailures (runtimeScopes graph) failures
  -- 关闭失败是资源问题：raise 与普通 IO 异常都已经过 Error 诊断并记录，由运行结束汇总，
  -- 不改变节点结果，也不停止后续执行。只有取消向外传播。
  case [exception | (Just exception, _) <- failures
       , isJust (fromException exception :: Maybe SomeAsyncException)] of
    exception : _ -> throwIO exception
    [] -> pure ()

-- 活动身份与来源绑定 -----------------------------------------------------------

nextSequence :: IORef Integer -> IO Integer
nextSequence counter = atomicModifyIORef' counter (\previous -> (previous + 1, previous))

-- 同一挂载的执行彼此先后（有限 AST 只执行一次，重复单元与会话步骤逐次执行）；
-- 被替换的 Origin 不再能经来源表读到，其无归属发布随之移出，避免重复执行累积。
newOrigin :: RuntimeGraph environment cause -> NodeId -> IO Origin
newOrigin graph node = mask $ \restore -> do
  (origin, released) <- withFrameLock (runtimeRootFrame graph) $ do
    origin <- Origin node <$> nextSequence (runtimeOriginSequence graph)
    replaced <- atomicModifyIORef' (runtimeOrigins graph) $ \origins ->
      let updated = (node, origin) : filter ((/= node) . fst) origins
      in length updated `seq` (updated, lookup node origins)
    removed <- maybe (pure []) (dropPublications graph . (: [])) replaced
    pure (origin, removed)
  restore (collectRetainedScopes graph released)
  pure origin

-- 新 frame 开始前移出该子树上一次执行的 Origin：本次没有执行的位置不能读到上一次的普通产物。
-- 移出的发布按位置与来源保留最新一份，供 lifelong 结束后的后继读取（require 读最新值）。
resetOrigins :: RuntimeGraph environment cause -> NodeId -> IO ()
resetOrigins graph prefix = mask $ \restore -> do
  released <- withFrameLock (runtimeRootFrame graph) $ do
    origins <- readIORef (runtimeOrigins graph)
    assets <- readIORef (runtimeAssets graph)
    let removed = [origin | (node, origin) <- origins, prefix `isPrefixOf` node]
        kept = [(node, origin) | (node, origin) <- origins, not (prefix `isPrefixOf` node)]
        carried = [((originNode origin, source), value) | ((origin, source), value) <- assets, origin `elem` removed]
    -- 先建立后继保留，再撤销当前来源；整个交接与 scope 关闭预约共用协调锁。
    -- Binding / ActivationId / owner 不变，也不使单元内读取看到上一轮。
    replaced <- atomicModifyIORef' (runtimeRetained graph) $ \retained ->
      let updated = carried ++ [entry | entry@(key, _) <- retained, key `notElem` map fst carried]
          previous = [value | (key, value) <- retained, key `elem` map fst carried, bindingResource value]
      in length updated `seq` (updated, previous)
    length kept `seq` writeIORef (runtimeOrigins graph) kept
    _ <- dropPublications graph removed
    pure replaced
  restore (collectRetainedScopes graph released)

dropPublications :: RuntimeGraph environment cause -> [Origin] -> IO [ScopeBinding environment cause]
dropPublications _ [] = pure []
dropPublications graph origins = atomicModifyIORef' (runtimeAssets graph) $ \assets ->
  let kept = filter ((`notElem` origins) . fst . fst) assets
      removed = [value | ((origin, _), value) <- assets, origin `elem` origins, bindingResource value]
  in length kept `seq` (kept, removed)

-- 活动记录与 App 共享同一个绑定 IORef 和入口使用登记；ctx 不另建 scope 使用者。
-- parent 只表达启动关系，不参与 ScopeTree 父边或资产可见性推导。
beginActivation
  :: RuntimeGraph environment cause -> Maybe ActivationId -> Execution -> Boot
  -> IORef (ScopeBindings environment cause) -> ScopeUser environment cause
  -> IO (Activation environment cause)
beginActivation graph parent execution boot bindings user = do
  definition <- either (ioError . userError) pure (resolveDefinition (runtimePrototype graph) boot)
  identifier <- ActivationId <$> nextSequence (runtimeActivationSequence graph)
  let activation = Activation identifier parent boot execution definition bindings user
  -- 只在短临界区更新内存引用；取消期间也不留下半登记的活动节点。
  uninterruptibleMask_ $ modifyMVar_ (runtimeActivations graph) $ \active -> case parent of
    Just predecessor | predecessor `notElem` map fst active ->
      ioError (userError "Runtime activation has no active parent")
    _ -> pure ((identifier, activation) : active)
  pure activation

-- 退出即撤销活动记录；不把完成链积累为无限的调用历史。
endActivation :: RuntimeGraph environment cause -> ActivationId -> IO ()
endActivation graph identifier = uninterruptibleMask_ $
  modifyMVar_ (runtimeActivations graph) $ \active -> do
    let remaining = filter ((/= identifier) . fst) active
    -- 只强制表的脊，避免 filter thunk 持续引用已经结束的 frame；不求值业务绑定。
    _ <- evaluate (length remaining)
    pure remaining

resolveDefinition :: PrototypeReference -> Boot -> Either String ChainReference
resolveDefinition (PrototypeReference prototype) boot = do
  entry <- case boot of
    TargetedBoot node -> either (Left . show) (Right . chainEntry) (lookupChain prototype node)
    -- 解析器与 request 一样发布一次资产；同一 Context 至多有其中一种生产入口。
    RequestBoot source -> case
      [method | effect <- protoEffects prototype, effectName effect == source
        , (role, method) <- effectMethods effect, role `elem` [ContextRequest, ContextStream]] of
      [method] -> Right method
      _ -> Left ("Runtime request has no Context production entry: " ++ source)
  case [definition | definition <- protoChainDefinitions prototype, definitionEntry definition == entry] of
    [definition] -> Right (ChainReference definition)
    _ -> Left "Runtime activation has no unique static chain definition"

-- 先写资产表再换信号：等待者醒来重新读取时一定能看到这次发布。
publishAsset :: RuntimeGraph environment cause -> Origin -> String
             -> ScopeBinding environment cause -> IO ()
publishAsset graph origin source value = mask $ \restore -> do
  released <- withFrameLock (runtimeRootFrame graph) $ do
    previous <- atomicModifyIORef' (runtimeAssets graph) $ \assets ->
      let key = (origin, source)
          updated = (key, value) : filter ((/= key) . fst) assets
          replaced = [old | Just old <- [lookup key assets], bindingResource old]
      in length updated `seq` (updated, replaced)
    notifyFrame (runtimeRootFrame graph)
    pure previous
  restore (collectRetainedScopes graph released)

-- 读取之前取得的信号；普通发布和执行帧退休都会填满它。
publicationSignal :: RuntimeGraph environment cause -> IO (MVar ())
publicationSignal = frameSignal . runtimeRootFrame

-- 最低限度的耗尽证明：许可来源都已退休。
-- 本链自己的潜在生产不算继续等待的理由：一个节点的链在 App 载体里顺序执行，
-- require 缺值时阻塞当前线程、不让出执行权；读取之前的生产已经结束，之后的生产要等这次读取返回。
-- 载体若改为可让出执行权，或节点内出现并发驱动，这条判断须重新核对。
-- 会话来源与未知位置不能按有限 AST 的退休判定，仍保持原交付／等待协议；
-- 等待者自己在会话链上时保留本链的静态生产上界，待 Stream 的结束与失败语义确定。
contextMayPublish :: RuntimeGraph environment cause -> ExecutionFrame -> Origin -> String -> IO Bool
contextMayPublish graph frame origin source = case runtimePrototype graph of
  PrototypeReference prototype -> case
    [effect | effect <- protoEffects prototype, effectName effect == source] of
    [producer] -> case lookupChain prototype (originNode origin) of
      Left _ -> pure True
      Right current -> do
        let ownProduction = chainRole current == SessionChain
              && (maybe False (`elem` chainDrives current) (effectProduces producer)
                || any (\(role, method) -> role `elem` [ContextRequest, ContextStream]
                  && method `elem` chainReaches current) (effectMethods producer))
            candidates = case sourcePlan (runtimePrototype graph) (originNode origin) source of
              FromOwnChain -> Just []
              FromChains nodes -> Just nodes
              FromSession -> Nothing
            canPublish node = case lookupChain prototype node of
              Right chain | chainRole chain /= SessionChain -> do
                progress <- frameNodeProgress frame node
                pure (maybe True (\status -> status == Pending || status == Running) progress)
              _ -> pure True
        case candidates of
          Nothing -> pure True
          Just nodes -> or <$> mapM canPublish
            (nub (nodes ++ [originNode origin | ownProduction]))
    _ -> pure True

-- 先按生成表定位来源入口，再读取本次实际发布；不按并发完成时序或全局最新值挑选。
-- 缺少发布只返回空值，由 Context 协议继续等待或在已证明耗尽后报缺值。
-- lifelong 之外的读取（后继）对单元内的位置读它最新一次发布：本轮没有执行到时取先前各轮保留的那份。
-- 生成期只在同一单元的互斥位置之间允许多个候选；它们按轮次先后发布，取 Origin 序号最大的一份。
readVisibleAsset :: RuntimeGraph environment cause -> Origin -> String
                 -> IO (Either ContextFault (Maybe (ScopeBinding environment cause)))
readVisibleAsset graph origin source = withFrameLock (runtimeRootFrame graph) $ do
  publications@(Publications _ assets _) <- readPublications graph
  let reader = originNode origin
      candidates = case sourcePlan (runtimePrototype graph) reader source of
        FromOwnChain -> [value | Just value <- [lookup (origin, source) assets]]
        -- 会话普通伴随值只由固定交付读取，不能从后台步骤的最新 Origin 读取。
        FromChains nodes -> [value | node <- nodes, node `notElem` runtimeSessionMounts graph
          , Just value <- [publicationAt (runtimePrototype graph) publications reader source node]]
        FromSession -> []
  pure (selectPublication (runtimePrototype graph) reader source candidates)

-- 只在共同协调锁内取得一致的发布快照；scope 待用回调已持锁，不重复获取。
-- 这是本次查询的视图，不另建资产表，也不保留完整历史。
data Publications environment cause = Publications
  [(NodeId, Origin)]
  [((Origin, String), ScopeBinding environment cause)]
  [((NodeId, String), ScopeBinding environment cause)]

readPublications :: RuntimeGraph environment cause -> IO (Publications environment cause)
readPublications graph = Publications <$> readIORef (runtimeOrigins graph)
  <*> readIORef (runtimeAssets graph) <*> readIORef (runtimeRetained graph)

-- 实际读取与待用判断共用：本位置当前发布优先，只有 lifelong 外的合法读取才用保留值。
-- 来源许可由调用方的 protoSources / openingSources 给出；本函数不放宽可见性。
publicationAt :: PrototypeReference -> Publications environment cause -> NodeId -> String -> NodeId
              -> Maybe (ScopeBinding environment cause)
publicationAt prototype (Publications origins assets retained) reader source node =
  case lookup node origins >>= \origin -> lookup (origin, source) assets of
    Just value -> Just value
    Nothing | outsideLifelong prototype reader node -> lookup (node, source) retained
    Nothing -> Nothing

outsideLifelong :: PrototypeReference -> NodeId -> NodeId -> Bool
outsideLifelong (PrototypeReference prototype) reader node =
  any (\(boundary, _) -> boundary `isPrefixOf` node && not (boundary `isPrefixOf` reader))
    (workflowLifelongs (protoWorkflow prototype))

-- 只在已证明可并存的跨轮候选中选最新的 Origin；不能让“还有旧候选”保活已被替换的实例。
-- 普通并存来源仍报歧义；不会按并行完成时序任选一个。
selectPublication :: PrototypeReference -> NodeId -> String -> [ScopeBinding environment cause]
                  -> Either ContextFault (Maybe (ScopeBinding environment cause))
selectPublication _ _ _ [] = Right Nothing
selectPublication _ _ _ [value] = Right (Just value)
selectPublication prototype reader source values
  | all (outsideLifelong prototype reader . originNode . executionOrigin . bindingOrigin) values =
      Right (Just (foldr1 newer values))
  | otherwise = Left (AmbiguousContextBinding source)
  where
    sequenceOf = originSequence . executionOrigin . bindingOrigin
    newer left right = if sequenceOf left >= sequenceOf right then left else right

sourcePlan :: PrototypeReference -> NodeId -> String -> Source
sourcePlan (PrototypeReference prototype) node source = case
  [contract | effect <- protoEffects prototype, effectName effect == source
    , Just contract <- [effectProduces effect]] of
  [contract] -> fromMaybe FromOwnChain (lookup (ReadPoint node contract) (protoSources prototype))
  _ -> FromOwnChain

-- 会话登记与停止 ---------------------------------------------------------------

-- 运行层装配后安装：为新会话启动生产任务并登记到会话中。
installSessionLauncher :: RuntimeGraph environment cause -> (Session environment cause -> IO ()) -> IO ()
installSessionLauncher graph = writeIORef (runtimeLauncher graph)

-- 会话装配协议 v2（2026-11-17）：统一登记下执行 gen 的连接计划。
-- lifelong 的连接仍由边界统一登记；有限需求只建立所需 Receive/Derive 上游闭包。
-- 先建会话、接游标，再启动全部新任务，最后提交目录。上游不能在游标接入之前丢掉首条交付。
-- 目录锁与取消保护覆盖整个提交；失败时仍提交失败的会话，再在锁外停止已启动任务，避免孤儿线程。
-- 读取者只等待一次当前绑定；下面的派生任务持续运行，不把读取者改造成 lifelong。
obtainSession :: RuntimeGraph environment cause -> SessionKey -> ScopeBindings environment cause
              -> [(String, View environment cause)] -> IO (Session environment cause)
obtainSession graph key bindings views = uninterruptibleMask_ $ do
  (session, created, problem) <- modifyMVar (runtimeSessions graph) $ \registry -> case registry of
    Nothing -> ioError (userError ("Sessions have stopped; the session for " ++ snd key
      ++ " is not started while the run is ending"))
    Just sessions -> case lookup key sessions of
      Just session -> pure (registry, (session, [], Nothing))
      Nothing -> do
        added <- newIORef []
        attached <- newIORef []
        let assemble known selected = case lookup selected known of
              Just existing -> pure (known, existing)
              Nothing -> do
                upstream <- either (ioError . userError) pure (sessionUpstreamSource (runtimePrototype graph) selected)
                (prepared, parent) <- case upstream of
                  Nothing -> pure (known, Nothing)
                  Just source -> do
                    (updated, previous) <- assemble known (Nothing, source)
                    pure (updated, Just previous)
                fresh <- newSession (notifyFrame (runtimeRootFrame graph)) (collectRetainedScopes graph) selected
                  (if selected == key then bindings else []) (if selected == key then views else [])
                forM_ parent $ \previous -> do
                  cursor <- attachReader previous
                  modifyIORef attached ((previous, cursor) :)
                  feedSession fresh previous cursor
                modifyIORef added (fresh :)
                pure ((selected, fresh) : prepared, fresh)
            detach = readIORef attached >>= mapM_ (\(parent, cursor) -> void (leaveSession parent cursor))
        (updated, selected) <- assemble sessions key `onException` detach
        created <- readIORef added
        launch <- readIORef (runtimeLauncher graph)
        outcome <- trySessionLaunch (mapM_ launch (reverse created))
        -- 失败会话留在目录内，使其他读取方看到同一个失败；整次运行的停止也仍能找到所有任务。
        forM_ outcome $ \exception -> mapM_ (\fresh -> breakSession fresh (Left exception)) created
        pure (Just updated, (selected, created, outcome))
  case problem of
    Nothing -> pure session
    Just exception -> do
      mapM_ stopSession created
      -- 没有启动的派生任务不能自行离开上游；停止后的统一撤销是幂等的。
      forM_ created $ \fresh -> do
        upstream <- upstreamOf fresh
        case upstream of
          Nothing -> pure ()
          Just _ -> do
            (parent, cursor) <- awaitUpstream fresh
            void (leaveSession parent cursor)
      throwIO exception
  where
    modifyIORef reference update = atomicModifyIORef' reference (\current -> (update current, ()))
    trySessionLaunch action = either Just (const Nothing) <$> (try action :: IO (Either SomeException ()))

-- 只投影已生成计划的上游引用，不从 handler、资产内容或运行时状态推断生产方式。
-- 有限会话的依赖图已经过 gen 校验；有边界的会话由 Execution 一次连接全部读取方。
sessionUpstreamSource :: PrototypeReference -> SessionKey -> Either String (Maybe String)
sessionUpstreamSource _ (Just _, _) = Right Nothing
sessionUpstreamSource (PrototypeReference prototype) (Nothing, source) = do
  asset <- case [asset | effect <- protoEffects prototype, effectName effect == source
      , Just asset <- [effectProduces effect]] of
    [asset] -> Right asset
    _ -> Left ("No unique continuous producer for " ++ source)
  plan <- case [sessionPlan session | session <- protoSessions prototype, sessionAsset session == asset] of
    [plan] -> Right plan
    _ -> Left ("No interpreter session plan for " ++ asset ++ "; regenerate the program")
  case plan of
    Receive _ -> Right Nothing
    Derive upstream -> case [effectName effect | effect <- protoEffects prototype, effectProduces effect == Just upstream] of
      [parent] -> Right (Just parent)
      _ -> Left ("No unique upstream producer for " ++ upstream)
    ReuseOutput _ -> Left "An interpreter session cannot reuse an AST output"

-- lifelong 之后读取持续资产：取已经结束、且在 AST 中先于读取位置的那个 lifelong 的会话，不另行启动来源。
-- 生成期保证这样的 lifelong 彼此先后；登记表按创建先后倒序，第一个即最近结束的。
endedSession :: RuntimeGraph environment cause -> NodeId -> String -> IO (Maybe (Session environment cause))
endedSession graph reader source = case runtimePrototype graph of
  PrototypeReference prototype -> do
    registry <- readMVar (runtimeSessions graph)
    pure (priorSession prototype (fromMaybe [] registry) reader source)

-- 实际读取与 scope 待用共用同一个会话选择：最近合法的已结束边界优先；
-- 没有此前边界时才考虑 interpreter 托管会话。查询从不创建会话。
priorSession :: Prototype method -> [(SessionKey, Session environment cause)] -> NodeId -> String
             -> Maybe (Session environment cause)
priorSession prototype registry reader source = case
  [session | ((Just boundary, selected), session) <- registry
    , selected == source, precedes (protoWorkflow prototype) boundary reader] of
  session : _ -> Just session
  [] -> Nothing

sessionForReader :: Prototype method -> [(SessionKey, Session environment cause)] -> NodeId -> String
                 -> Maybe (Session environment cause)
sessionForReader prototype registry reader source = case priorSession prototype registry reader source of
  Just session -> Just session
  Nothing -> lookup (Nothing, source) registry

-- interpreter 退出前关闭登记并取消全部生产任务，等待步骤内的受控收尾完成。
-- 关闭与取出在同一临界区，此后尚未停止的会话不能再创建依赖会话；后创建的排在前面，依赖方先停止。
stopSessions :: RuntimeGraph environment cause -> IO ()
stopSessions graph = uninterruptibleMask_ $ do
  sessions <- modifyMVar (runtimeSessions graph) (\registry -> pure (Nothing, fromMaybe [] registry))
  mapM_ (stopSession . snd) sessions

-- 这些挂载当前一次执行已经发布的普通资产；会话在交付时把它们存为伴随发布。
currentPublications :: RuntimeGraph environment cause -> [NodeId] -> IO (ScopeBindings environment cause)
currentPublications graph nodes = withFrameLock (runtimeRootFrame graph) $ do
  origins <- readIORef (runtimeOrigins graph)
  assets <- readIORef (runtimeAssets graph)
  let current = [origin | node <- nodes, Just origin <- [lookup node origins]]
  pure [(source, value) | ((origin, source), value) <- assets, origin `elem` current]

-- 同一 effect 的其他挂载不因此成为这份会话的发布者。会话接线已经由 gen 固定到 NodeId。
reusesOutputAt :: RuntimeGraph environment cause -> NodeId -> String -> Bool
reusesOutputAt graph node source = (node, source) `elem` runtimeOutputSites graph
