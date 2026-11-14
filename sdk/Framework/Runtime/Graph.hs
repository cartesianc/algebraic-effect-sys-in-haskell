{-# LANGUAGE ExistentialQuantification #-}

-- 只读 Prototype 的运行实例：活动 chain、Origin 资产表、scope 引用和发布信号。
-- 同时持有唯一的会话登记表；登记／停止的原子边界在这里，生产线程由 Runtime 启动。
-- 生命周期：Execution 创建并安装树关系；App 更新调用与发布；Execution 退出时
-- 关闭会话登记并等待任务，再退休根帧；Program 只报告清理中记录的问题。
-- 运行不解释图边；业务仍由已经装配的闭包执行。
module Framework.Runtime.Graph
  ( RuntimeGraph(..), PrototypeReference(..), ChainReference(..), Activation(..)
  , newRuntimeGraph, configureRuntimeScopes, collectRuntimeScopes, finishRuntime, newOrigin
  , beginActivation, endActivation
  , publishAsset, publicationSignal, readVisibleAsset, contextMayPublish, resetOrigins
  , installSessionLauncher, obtainSession, endedSession, stopSessions, currentPublications
  ) where

import Control.Concurrent.MVar (MVar, modifyMVar, modifyMVar_, newMVar, readMVar)
import Control.Exception (SomeAsyncException, evaluate, finally, fromException, throwIO, uninterruptibleMask_)
import Control.Monad (forM, forM_)
import Data.IORef (IORef, atomicModifyIORef', newIORef, readIORef, writeIORef)
import Data.List (isPrefixOf, nub)
import Data.Maybe (fromMaybe, isJust)
import Framework.Runtime.Protocol (ContextFault(..))
import Framework.Prototype.Graph (MethodRole(..))
import Framework.Runtime.Identity
import Framework.Runtime.Frame
import Framework.Runtime.Binding (Binding(..))
import Framework.Runtime.Session (Session, SessionKey, View, newSession, stopSession)
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
  frame <- newExecutionFrame coordinator Nothing
    [chainNode chain | chain <- protoChains prototype, chainRole chain /= SessionChain]
  RuntimeGraph (PrototypeReference prototype) scopes frame
    <$> newIORef [] <*> newIORef [] <*> newMVar [] <*> newIORef 0 <*> newIORef 0
    <*> newMVar (Just []) <*> newIORef (const (ioError (userError "No session launcher is installed")))
    <*> pure [mount | (_, described) <- workflowLifelongs (protoWorkflow prototype)
           , session <- lifelongSessions described, mount <- sessionMounts session]
    <*> newIORef []

-- ScopeTree 的独立构建与校验仍在 Prototype；这里只把同一树的关系装入现有控制对象。
configureRuntimeScopes :: RuntimeGraph environment cause -> IO ()
configureRuntimeScopes graph = case runtimePrototype graph of
  PrototypeReference prototype -> do
    configureScopeRelations (scopeRelations prototype) (runtimeScopes graph)
    forM_ (runtimeScopes graph) $ \family ->
      writeIORef (scopeReachable family) (reachableInstance graph)

-- 在 scope 协调锁内只读进度及权威发布。候选记录可能出处，实际生产身份决定匹配；
-- 同一节点多次发布只留下当前一份，读到同一生产的后继才保留同一个实例。
reachableInstance :: RuntimeGraph environment cause -> ScopeInstance environment cause -> IO Bool
reachableInstance graph slot = case runtimePrototype graph of
  PrototypeReference prototype -> do
    views <- framePendingViews (scopeFrame slot)
    origins <- readIORef (runtimeOrigins graph)
    assets <- readIORef (runtimeAssets graph)
    instances <- concat <$> mapM (readMVar . scopeInstances) (runtimeScopes graph)
    snapshots <- forM instances $ \instance' -> do
      values <- scopeBindings <$> readIORef (scopeRecord instance')
      pure (instance', values)
    let candidates = [(opening, delivered) | (pending, delivered) <- views, opening <- protoScopeOpenings prototype
          , openingNode opening `elem` pending, openingScope opening == scopeName (scopeFamily slot)]
        matches instance' delivered opening = all (matchesInput delivered opening) (scopeInputs instance')
        matchesInput delivered opening (ScopeInput source production) = case lookup source (openingSources opening) of
          Nothing -> False
          Just nodes
            | any ((== Just source) . effectResource) (protoEffects prototype) ->
                -- 参数本身是其他 scope 的资源：复用不重新发布，按资源原生产身份
                -- 找到父实例，再验证同一待用入口确实会开启它。ScopeTree 已保证无环。
                or [matches parent delivered parentOpening | (parent, values) <- snapshots
                   , scopeContextSource (scopeFamily parent) == Just source
                   , Just value <- [lookup source values], bindingProduction value == Just production
                   , parentOpening <- protoScopeOpenings prototype
                   , openingNode parentOpening == openingNode opening
                   , openingScope parentOpening == scopeName (scopeFamily parent)]
            | otherwise -> any (matchesPublication delivered source production) nodes
        matchesPublication delivered source production node =
          case [captured | (publishedAt, context, captured) <- delivered, publishedAt == node, context == source] of
            captured : _ -> captured == production
            [] -> case lookup node origins >>= \origin -> lookup (origin, source) assets of
              Just value -> bindingProduction value == Just production
              Nothing -> False
    pure (any (\(opening, delivered) -> matches slot delivered opening) candidates)

-- 节点退休后只检查其开启位置及 ScopeTree 祖先。预约在进度写入的锁外进行，
-- 业务 close 失败留作汇总；原生异常（包括取消）仍停止后续执行。
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
finishRuntime graph = collectScopes graph (runtimeScopes graph) `finally`
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
newOrigin graph node = do
  origin <- Origin node <$> nextSequence (runtimeOriginSequence graph)
  replaced <- atomicModifyIORef' (runtimeOrigins graph) $ \origins ->
    let updated = (node, origin) : filter ((/= node) . fst) origins
    in length updated `seq` (updated, lookup node origins)
  mapM_ (dropPublications graph . (: [])) replaced
  pure origin

-- 新 frame 开始前移出该子树上一次执行的 Origin：本次没有执行的位置不能读到上一次的普通产物。
-- 移出的发布按位置与来源保留最新一份，供 lifelong 结束后的后继读取（require 读最新值）。
resetOrigins :: RuntimeGraph environment cause -> NodeId -> IO ()
resetOrigins graph prefix = do
  removed <- atomicModifyIORef' (runtimeOrigins graph) $ \origins ->
    let (dropped, kept) = (filter selected origins, filter (not . selected) origins)
    in length kept `seq` (kept, map snd dropped)
  assets <- readIORef (runtimeAssets graph)
  let carried = [((originNode origin, source), value) | ((origin, source), value) <- assets, origin `elem` removed]
  atomicModifyIORef' (runtimeRetained graph) $ \retained ->
    let updated = carried ++ [entry | entry@(key, _) <- retained, key `notElem` map fst carried]
    in length updated `seq` (updated, ())
  dropPublications graph removed
  where selected = (prefix `isPrefixOf`) . fst

dropPublications :: RuntimeGraph environment cause -> [Origin] -> IO ()
dropPublications _ [] = pure ()
dropPublications graph origins = atomicModifyIORef' (runtimeAssets graph) $ \assets ->
  let kept = filter ((`notElem` origins) . fst . fst) assets
  in length kept `seq` (kept, ())

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
publishAsset graph origin source value = uninterruptibleMask_ $ do
  atomicModifyIORef' (runtimeAssets graph) $ \assets ->
    let key = (origin, source)
        updated = (key, value) : filter ((/= key) . fst) assets
    in length updated `seq` (updated, ())
  notifyFrame (runtimeRootFrame graph)

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
readVisibleAsset graph origin source = do
  origins <- readIORef (runtimeOrigins graph)
  assets <- readIORef (runtimeAssets graph)
  retained <- readIORef (runtimeRetained graph)
  let reader = originNode origin
      current node = lookup node origins >>= \produced -> lookup (produced, source) assets
      carried node
        | outsideLifelong node = lookup (node, source) retained
        | otherwise = Nothing
      outsideLifelong node = case runtimePrototype graph of
        PrototypeReference prototype -> or [not (boundary `isPrefixOf` reader)
          | (boundary, _) <- workflowLifelongs (protoWorkflow prototype), boundary `isPrefixOf` node]
      candidates = case sourcePlan (runtimePrototype graph) reader source of
        FromOwnChain -> [value | Just value <- [lookup (origin, source) assets]]
        -- 会话生产步骤反复执行，挂载的当前 Origin 不对应消费者所处理的交付；
        -- 这些发布随交付作为伴随发布交给单元，这里不再读取。
        FromChains nodes -> [value | node <- nodes, node `notElem` runtimeSessionMounts graph
          , Just value <- [maybe (carried node) Just (current node)]]
        -- 会话交付不经普通来源表。
        FromSession -> []
      sequenceOf = originSequence . executionOrigin . bindingOrigin
  pure $ case candidates of
    [] -> Right Nothing
    [value] -> Right (Just value)
    many | all (outsideLifelong . originNode . executionOrigin . bindingOrigin) many ->
      Right (Just (snd (maximumOn many)))
      where maximumOn values = foldr1 (\left right -> if fst left >= fst right then left else right)
              [(sequenceOf value, value) | value <- values]
    _ -> Left (AmbiguousContextBinding source)

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

-- 同一边界与资产只创建一份会话并只启动一次生产；在登记表锁内启动，停止时一定能看到它。
-- 交接只在创建时使用：一个 lifelong 在一次运行中只进入一次，interpreter 会话没有交接。
-- 停止开始后不再创建：请求方（正被停止的生产步骤）得到异常，不会留下逃出停止集合的任务。
-- 启动与写回登记表在同一个不可中断区内完成：modifyMVar 的回调会恢复调用方的屏蔽状态，
-- 否则取消可能落在任务已经启动、登记表尚未写回之间，登记表回滚而任务无人停止。
obtainSession :: RuntimeGraph environment cause -> SessionKey -> ScopeBindings environment cause
              -> [(String, View environment cause)] -> IO (Session environment cause)
obtainSession graph key bindings views = uninterruptibleMask_ $ modifyMVar (runtimeSessions graph) $ \registry -> case registry of
  Nothing -> ioError (userError ("Sessions have stopped; the session for " ++ snd key
    ++ " is not started while the run is ending"))
  Just sessions -> case lookup key sessions of
    Just session -> pure (registry, session)
    Nothing -> do
      session <- newSession key (case runtimePrototype graph of
        PrototypeReference prototype -> readsHistoryInChains prototype (snd key)) bindings views
      launch <- readIORef (runtimeLauncher graph)
      launch session
      pure (Just ((key, session) : sessions), session)

-- lifelong 之后读取持续资产：取已经结束、且在 AST 中先于读取位置的那个 lifelong 的会话，不另行启动来源。
-- 生成期保证这样的 lifelong 彼此先后；登记表按创建先后倒序，第一个即最近结束的。
endedSession :: RuntimeGraph environment cause -> NodeId -> String -> IO (Maybe (Session environment cause))
endedSession graph reader source = case runtimePrototype graph of
  PrototypeReference prototype -> do
    registry <- readMVar (runtimeSessions graph)
    pure $ case [session | ((Just boundary, selected), session) <- fromMaybe [] registry
                 , selected == source, precedes (protoWorkflow prototype) boundary reader] of
      session : _ -> Just session
      [] -> Nothing

-- interpreter 退出前关闭登记并取消全部生产任务，等待步骤内的受控收尾完成。
-- 关闭与取出在同一临界区，此后尚未停止的会话不能再创建依赖会话；后创建的排在前面，依赖方先停止。
stopSessions :: RuntimeGraph environment cause -> IO ()
stopSessions graph = uninterruptibleMask_ $ do
  sessions <- modifyMVar (runtimeSessions graph) (\registry -> pure (Nothing, fromMaybe [] registry))
  mapM_ (stopSession . snd) sessions

-- 这些挂载当前一次执行已经发布的普通资产；会话在交付时把它们存为伴随发布。
currentPublications :: RuntimeGraph environment cause -> [NodeId] -> IO (ScopeBindings environment cause)
currentPublications graph nodes = do
  origins <- readIORef (runtimeOrigins graph)
  assets <- readIORef (runtimeAssets graph)
  let current = [origin | node <- nodes, Just origin <- [lookup node origins]]
  pure [(source, value) | ((origin, source), value) <- assets, origin `elem` current]
