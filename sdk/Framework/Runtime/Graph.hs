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
  , publishAsset, publicationSignal, readPublishedAsset, contextMayPublish, resetOrigins
  , installSessionLauncher, obtainSession, endedSession, stopSessions, currentPublications, reusesOutputAt
  ) where

import Control.Concurrent.MVar (MVar, modifyMVar, modifyMVar_, newMVar, readMVar)
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
  , activationFrame :: ExecutionFrame
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
  -- 这份按 Origin 的索引服务同一步的交付；普通读取使用下面的 runtimeLatest。
  , runtimeAssets :: IORef [((Origin, String), ScopeBinding environment cause)]
  -- 有限 AST 每个挂载只启动一次；完成后只保留身份，供后继读取，不保留其 activation。
  , runtimeOrigins :: IORef [(NodeId, Origin)]
  , runtimeActivations :: MVar [(ActivationId, Activation environment cause)]
  , runtimeOriginSequence :: IORef Integer
  , runtimeActivationSequence :: IORef Integer
  -- 生产会话按（lifelong 边界，资产）共享；生产任务由运行层安装的启动函数创建。
  -- Nothing：运行正在结束，会话已经全部交给停止，不再创建新会话。
  , runtimeSessions :: MVar (Maybe [(SessionKey, Session environment cause)])
  -- 目录的只读投影；在 scope/frame 协调锁内先登记，再启动 worker。
  -- GC 已持有协调锁，直接读此表，不反向等待会话装配锁。
  , runtimeSessionSnapshot :: IORef [(SessionKey, Session environment cause)]
  , runtimeLauncher :: IORef (Session environment cause -> IO ())
  -- 已装配的原始链输出路由；从 Prototype 投影一次，发布时不重新遍历整张图。
  , runtimeOutputSites :: [(NodeId, String)]
  -- 普通资产 v1（2026-11-18）：每个 Context 一份运行级最新发布；帧不是可见性边界。
  -- Origin 表只保存当前步骤的伴随输出；切轮不撤销这份共享值，不累积历史。
  , runtimeLatest :: IORef (ScopeBindings environment cause)
  -- 每个启动位置生效的 hook 集合；从 Prototype 投影一次，启动时按位置查表。
  , runtimeHooks :: [(NodeId, [String])]
  }

newRuntimeGraph
  :: (Eq method, Show method)
  => Prototype method -> Scopes environment cause -> IO (RuntimeGraph environment cause)
newRuntimeGraph prototype scopes = do
  coordinator <- case scopes of
    first : _ -> readIORef (scopeCoordinator first)
    [] -> newMVar ()
  frame <- newExecutionFrame coordinator Nothing Nothing
    (drivingRootNodes (protoDriving prototype))
  retentions <- newRetentions coordinator
  RuntimeGraph (PrototypeReference prototype) scopes frame retentions
    <$> newIORef [] <*> newIORef [] <*> newMVar [] <*> newIORef 0 <*> newIORef 0
    <*> newMVar (Just []) <*> newIORef [] <*> newIORef (const (ioError (userError "No session launcher is installed")))
    <*> pure (drivingOutputSites (protoDriving prototype))
    <*> newIORef []
    <*> pure (drivingHooks (protoDriving prototype))

-- ScopeTree 的独立构建与校验仍在 Prototype；这里只把同一树的关系装入现有控制对象。
configureRuntimeScopes :: RuntimeGraph environment cause -> IO ()
configureRuntimeScopes graph = case runtimePrototype graph of
  PrototypeReference prototype -> do
    configureScopeRelations (scopeRelations prototype) (runtimeScopes graph)
    forM_ (runtimeScopes graph) $ \family ->
      writeIORef (scopeReachable family) $ \slot -> do
        held <- retainedInstance graph slot
        if held then pure True else reachableInstance graph slot

-- Binding 保留 v2（2026-11-18）：实际交付/捕获、未领取队列、仍合法可读的最新值。
-- 仅检查共享 ownership，既不解释业务字段，也不把持有关系加入 ScopeTree。
-- 调用方已经持有 scope/frame 协调锁；从已登记快照查询，不因其他会话正在装配而保留全部实例。
retainedInstance :: RuntimeGraph environment cause -> ScopeInstance environment cause -> IO Bool
retainedInstance graph slot = case runtimePrototype graph of
  PrototypeReference prototype -> do
    active <- retainedBindings (runtimeRetentions graph)
    held <- ownsAny active
    if held then pure True else do
      sessions <- readIORef (runtimeSessionSnapshot graph)
      queued <- concat <$> mapM (pendingBindings . snd) sessions
      inQueue <- ownsAny queued
      if inQueue then pure True else do
        frames <- framePendingViews (runtimeRootFrame graph)
        assets <- readIORef (runtimeLatest graph)
        let selected frame point source plan = case plan of
              FromSession
                -- 根帧的 lifelong 预约代表未来轮次，不能拿最新一条代替尚未领取的交付。
                | frameParent frame == Nothing
                , isJust (driveBoundary (nodeDriveAt prototype (readNode point))) -> pure []
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
              FromOwnChain -> pure [value | Just value <- [lookup source assets]]
              FromChains _ -> pure [value | Just value <- [lookup source assets]]
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
collectRetainedScopes graph values = do
  owners <- mapM readBindingOwner values
  collectNamedScopes graph (nub [name | Just (name, _) <- owners])

-- 原参数被共享新值覆盖，也可能撤销某实例的最后一份待用；复用同一回收入口。
-- 只检查开启计划明确依赖该参数的 Scoped 及其祖先，不扫描无关实例。
collectParameterScopes :: RuntimeGraph environment cause -> String -> IO ()
collectParameterScopes graph source = case runtimePrototype graph of
  PrototypeReference prototype -> collectNamedScopes graph
    [openingScope opening | opening <- protoScopeOpenings prototype, source `elem` map fst (openingSources opening)]

collectNamedScopes :: RuntimeGraph environment cause -> [String] -> IO ()
collectNamedScopes _ [] = pure ()
collectNamedScopes graph selected = case runtimePrototype graph of
  PrototypeReference prototype -> do
    let relations = scopeRelations prototype
        ancestors names = let expanded = nub (names ++ concat [parents | (name, parents) <- relations, name `elem` names])
                          in if expanded == names then names else ancestors expanded
        relevant = ancestors (nub selected)
    collectScopes graph (filter ((`elem` relevant) . scopeName) (runtimeScopes graph))

-- 待用查询 v5（2026-11-18）：普通参数先固定捕获、再共享最新值；持续参数沿固定视图/游标匹配。
-- 查询在 scope 协调锁内，不领取、不生产；会话沿只读目录快照定位。
-- 装配先在同一协调锁内写入快照，业务启动在锁外；会话状态锁内不反向取得帧锁。
reachableInstance :: RuntimeGraph environment cause -> ScopeInstance environment cause -> IO Bool
reachableInstance graph slot = case runtimePrototype graph of
  PrototypeReference prototype -> do
    -- 普通参数的使用者可位于任意活动帧；仍按具体 Binding 的生产身份匹配。
    -- 根帧的常驻预约与实际轮帧共用这些开启计划，不提升实例的归属帧。
    reservations <- framePendingViews (runtimeRootFrame graph)
    -- 活动 SessionChain 的业务出身仍是根帧，预约帧只表示未来步骤。
    -- 同一锁内纳入正在执行的根调用及其捕获，覆盖“已读参数、尚未认领实例”的交接。
    active <- readMVar (runtimeActivations graph)
    let pendingFrames = reservations ++ [(activationFrame call, [node], [])
          | (_, call) <- active, TargetedBoot node <- [activationBoot call]]
    assets <- readIORef (runtimeLatest graph)
    let producerMounts = [chainNode chain | chain <- protoChains prototype, chainRole chain == SessionChain]
    sessions <- readIORef (runtimeSessionSnapshot graph)
    instances <- concat <$> mapM (readMVar . scopeInstances) (runtimeScopes graph)
    snapshots <- forM instances $ \instance' -> do
      values <- scopeBindings <$> readIORef (scopeRecord instance')
      pure (instance', values)
    let candidates = [(frame, opening, delivered)
          | (frame, pending, delivered) <- pendingFrames
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
            | otherwise -> do
                captured <- capturedFrameInputs frame
                let reader = openingNode opening
                    selectors = driveCaptures (nodeDriveAt prototype reader)
                    local = [identity | at <- reader : selectors
                      , (node, context, identity) <- captured, node == at, context == source]
                    deliveredHere = [identity | (publishedAt, context, identity) <- delivered
                      , context == source, publishedAt `elem` nodes]
                pure $ case local ++ deliveredHere of
                  identity : _ -> identity == production
                  -- 必定以新参数开启而尚未捕获的调用，不会复用上一轮的旧参数实例。
                  [] | openingKinds opening == [ExecutionMultiple] -> False
                     | otherwise -> maybe False ((== Just production) . bindingProduction) (lookup source assets)
        matchesSession frame opening source production = do
          captured <- capturedFrameInputs frame
          let reader = openingNode opening
              -- 只有 alternative 把捕获交给候选；chained 不隐式传递前一调用的视图。
              selectors = driveCaptures (nodeDriveAt prototype reader)
              selected = [value | at <- reader : selectors
                , (node, context, value) <- captured, node == at, context == source]
          case selected of
            value : _ -> pure (value == production)
            [] -> do
              pending <- pendingSessionInput frame source production
              case pending of
                Just result -> pure result
                Nothing
                  -- 根帧里的未来轮次不是旧交付的读取方；实际活动轮帧有自己的游标。
                  | openingNode opening `notElem` producerMounts
                  , isJust (driveBoundary (nodeDriveAt prototype reader)) -> pure False
                  -- 会话步骤的普通 requires 沿 App 的有限读取路由，不冒充本单元订阅。
                  -- 启动捕获和 Derive 固定交付已由上面的 pending 查询优先处理。
                  | otherwise -> case sessionForReader prototype sessions reader source of
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
  PrototypeReference prototype -> collectNamedScopes graph
    [openingScope opening | opening <- protoScopeOpenings prototype, openingNode opening `elem` retired]

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
-- 被替换的 Origin 移出步骤输出索引；runtimeLatest 保留每份普通资产的最新值。
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

-- 清除上一步的伴随输出索引，避免交付误用旧步骤；共享最新值和已捕获 Binding 不动。
resetOrigins :: RuntimeGraph environment cause -> NodeId -> IO ()
resetOrigins graph prefix = mask $ \restore -> do
  released <- withFrameLock (runtimeRootFrame graph) $ do
    origins <- readIORef (runtimeOrigins graph)
    let removed = [origin | (node, origin) <- origins, prefix `isPrefixOf` node]
        kept = [(node, origin) | (node, origin) <- origins, not (prefix `isPrefixOf` node)]
    length kept `seq` writeIORef (runtimeOrigins graph) kept
    dropPublications graph removed
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
  :: RuntimeGraph environment cause -> Maybe ActivationId -> ExecutionFrame -> Execution -> Boot
  -> IORef (ScopeBindings environment cause) -> ScopeUser environment cause
  -> IO (Activation environment cause)
beginActivation graph parent frame execution boot bindings user = do
  definition <- either (ioError . userError) pure (resolveDefinition (runtimePrototype graph) boot)
  identifier <- ActivationId <$> nextSequence (runtimeActivationSequence graph)
  let activation = Activation identifier parent boot execution frame definition bindings user
      register = modifyMVar_ (runtimeActivations graph) $ \active -> case parent of
        Just predecessor | predecessor `notElem` map fst active ->
          ioError (userError "Runtime activation has no active parent")
        _ -> pure ((identifier, activation) : active)
  -- 锁序始终是 coordinator -> activation 目录；目录锁内不取得 coordinator。
  -- 新根调用的初始捕获和活动登记一同提交，Context 嵌套生产不重置调用捕获。
  case boot of
    TargetedBoot node -> withFrameLock frame $ do
      resetFrameInputsLocked frame node
      captured <- readIORef bindings
      forM_ captured $ \(source, value) -> forM_ (bindingProduction value) $ \production ->
        captureFrameInputLocked frame node source production
      register
    RequestBoot _ -> uninterruptibleMask_ register
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
    RequestBoot source -> maybe (Left ("Runtime request has no Context production entry: " ++ source)) Right
      (lookup source (drivingRequests (protoDriving prototype)))
  case [definition | definition <- protoChainDefinitions prototype, definitionEntry definition == entry] of
    [definition] -> Right (ChainReference definition)
    _ -> Left "Runtime activation has no unique static chain definition"

-- 先写资产表再换信号：等待者醒来重新读取时一定能看到这次发布。
publishAsset :: RuntimeGraph environment cause -> Origin -> String
             -> ScopeBinding environment cause -> IO ()
publishAsset graph origin source value = mask $ \restore -> do
  (released, replacedParameter) <- withFrameLock (runtimeRootFrame graph) $ do
    previous <- atomicModifyIORef' (runtimeAssets graph) $ \assets ->
      let key = (origin, source)
          updated = (key, value) : filter ((/= key) . fst) assets
          replaced = [old | Just old <- [lookup key assets], bindingResource old]
      in length updated `seq` (updated, replaced)
    -- 资源仍只沿 owner 协议读取；普通值共享同一份 Binding，不重发生产身份。
    replaced <- if bindingResource value then pure False else do
      existed <- atomicModifyIORef' (runtimeLatest graph) $ \assets ->
        let updated = (source, value) : filter ((/= source) . fst) assets
        in length updated `seq` (updated, isJust (lookup source assets))
      forM_ (bindingProduction value) $ \production ->
        captureFrameInputLocked (bindingFrame value) (originNode origin) source production
      pure existed
    notifyFrame (runtimeRootFrame graph)
    pure (previous, replaced)
  restore $ do
    collectRetainedScopes graph released
    if replacedParameter then collectParameterScopes graph source else pure ()

-- 读取之前取得的信号；普通发布和执行帧退休都会填满它。
publicationSignal :: RuntimeGraph environment cause -> IO (MVar ())
publicationSignal = frameSignal . runtimeRootFrame

-- 耗尽证明 v2（2026-11-18）：候选是 gen 给出的可启动供值位置，不是 AST 可见前驱。
-- 当前顺序调用不能在阻塞期间继续生产；其他位置从根帧的全部活动/待用帧查询。
-- 静态后继也在等当前节点时不提供进展；lifelong 的未来轮次保守保留。
-- 会话位置的启动/耗尽仍交给会话协议，本项不声称完整等待环检测。
contextMayPublish :: RuntimeGraph environment cause -> ExecutionFrame -> Origin -> String -> IO Bool
contextMayPublish graph _ origin source = case runtimePrototype graph of
  PrototypeReference prototype -> withFrameLock (runtimeRootFrame graph) $ do
    pendingFrames <- framePendingViews (runtimeRootFrame graph)
    let reader = originNode origin
        excluded = driveBlockedPublishers (nodeDriveAt prototype reader)
        canPublish node = case lookupChain prototype node of
          Right chain | chainRole chain == SessionChain -> True
          Right _ -> any (\(_, pending, _) -> node `elem` pending) pendingFrames
            && node `notElem` excluded
          Left _ -> True
    pure $ case sourcePlan (runtimePrototype graph) reader source of
      FromOwnChain -> False
      FromChains nodes -> any canPublish nodes
      FromSession -> True

-- 选中共享最新值与登记本次捕获身份在同一短临界区完成；普通业务 IO 不在锁内。
-- 没有值只返回 Nothing，Context 继续等待通知。资源不从这张表取得。
readPublishedAsset :: RuntimeGraph environment cause -> ExecutionFrame -> Origin -> String
                   -> IO (Either ContextFault (Maybe (ScopeBinding environment cause)))
readPublishedAsset graph frame origin source = withFrameLock (runtimeRootFrame graph) $ do
  value <- lookup source <$> readIORef (runtimeLatest graph)
  forM_ (value >>= bindingProduction) $ \production ->
    captureFrameInputLocked frame (originNode origin) source production
  pure (Right value)

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

-- 会话装配协议 v3（2026-11-18）：统一登记下执行 gen 的连接计划。
-- lifelong 的连接仍由边界统一登记；有限需求只建立所需 Receive/Derive 上游闭包。
-- 先建会话、接游标，再提交 GC 快照并启动新任务，最后提交对外目录。上游不能在游标接入之前丢掉首条交付。
-- 目录锁与取消保护覆盖整个提交；启动失败也提交会话，再在锁外封口并停止任务，避免回滚留下孤儿线程。
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
        -- GC 先能看到全部新会话，worker 才能发布。快照只由目录写者维护；
        -- 写入与关闭预约串行，读取快照不需要目录锁，也没有未知即全部保留的分支。
        withFrameLock (runtimeRootFrame graph) $ do
          length updated `seq` writeIORef (runtimeSessionSnapshot graph) updated
        launch <- readIORef (runtimeLauncher graph)
        outcome <- trySessionLaunch (mapM_ launch (reverse created))
        -- 封口可能触发 scope 回收；放到目录提交之后，异常不能回滚已经启动的会话。
        pure (Just updated, (selected, created, outcome))
  case problem of
    Nothing -> pure session
    Just exception -> do
      -- 每个动作都完成尝试：封口/撤销可能触发 close，某次收尾的异常不能阻止
      -- 其余任务停止，也不能让未启动的派生任务遗留上游游标。取消仍向外传播。
      sealed <- mapM (trySessionLaunch . (\fresh -> breakSession fresh (Left exception))) created
      stopped <- mapM (trySessionLaunch . stopSession) created
      detached <- forM created $ \fresh -> trySessionLaunch $ do
        upstream <- upstreamOf fresh
        case upstream of
          Nothing -> pure ()
          Just _ -> do
            (parent, cursor) <- awaitUpstream fresh
            void (leaveSession parent cursor)
      case [cancelled | Just cancelled <- sealed ++ stopped ++ detached
             , isJust (fromException cancelled :: Maybe SomeAsyncException)] of
        cancelled : _ -> throwIO cancelled
        [] -> throwIO exception
  where
    modifyIORef reference update = atomicModifyIORef' reference (\current -> (update current, ()))
    trySessionLaunch action = either Just (const Nothing) <$> (try action :: IO (Either SomeException ()))

-- 只投影已生成计划的上游引用，不从 handler、资产内容或运行时状态推断生产方式。
-- 有限会话的依赖图已经过 gen 校验；有边界的会话由 Execution 一次连接全部读取方。
sessionUpstreamSource :: PrototypeReference -> SessionKey -> Either String (Maybe String)
sessionUpstreamSource _ (Just _, _) = Right Nothing
sessionUpstreamSource (PrototypeReference prototype) (Nothing, source) = case sessionDriveAt prototype Nothing source of
  Just route -> Right (driveSessionUpstream route)
  Nothing -> Left ("No interpreter session driver for " ++ source ++ "; regenerate the program")

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
    , selected == source, boundary `elem` drivePriorBoundaries (nodeDriveAt prototype reader)] of
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
  sessions <- modifyMVar (runtimeSessions graph) $ \registry -> do
    -- 退出放弃未领取义务；执行中的捕获仍由 Retention/ScopeUser 保护，任务随后全部停止。
    withFrameLock (runtimeRootFrame graph) (writeIORef (runtimeSessionSnapshot graph) [])
    pure (Nothing, fromMaybe [] registry)
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
