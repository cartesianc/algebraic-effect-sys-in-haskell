{-# LANGUAGE ExistentialQuantification #-}
{-# LANGUAGE ViewPatterns #-}

-- 只读 Prototype 的运行实例：活动 chain、Origin 资产表、运行级最新值与持续资产的历史、scope 引用。
-- 发布后的订阅回调与 lifelong 外的静态运行由 Execution 按生成的回调表安装；这里只保存入口，不调度。
-- 生命周期：Execution 创建并安装树关系；App 更新调用与发布；Execution 退出时退休根帧；
-- Program 只报告清理中记录的问题。运行不解释图边；业务仍由已经装配的闭包执行。
module Framework.Runtime.Graph
  ( RuntimeGraph(..), PrototypeReference(..), ChainReference(..), Activation(..), Reaction, Place(..), rootPlace
  , newRuntimeGraph, configureRuntimeScopes, collectRuntimeScopes, finishRuntime, newOrigin
  , beginActivation, endActivation, withRuntimeRetention, collectRetainedScopes
  , publishAsset, readPublishedAsset, resetOrigins
  , readHistory, dropHistory, installReactions, react, installStatic, runStatic
  , openBranches, leaveBranch, rejoinBranches, publicationTicket, awaitPublication
  , StaticRun, newStaticRun, finishStatic, awaitStatic
  ) where

import Control.Concurrent.MVar (MVar, modifyMVar_, newMVar, readMVar)
import Control.Concurrent.STM (STM, TVar, atomically, check, modifyTVar', newTVarIO, readTVar, readTVarIO, retry, writeTVar)
import Control.Exception (SomeAsyncException, evaluate, finally, fromException, mask, onException, throwIO, uninterruptibleMask_)
import Control.Monad (forM, forM_, when)
import Data.IORef (IORef, atomicModifyIORef', newIORef, readIORef, writeIORef)
import qualified Data.IntMap.Strict as IntMap
import qualified Data.Map.Strict as Map
import Data.List (nub)
import Data.Maybe (isJust, isNothing)
import Data.Sequence ((|>))
import qualified Data.Sequence as Seq
import Framework.Language.Handler (Failure)
import Framework.Runtime.Protocol (ContextFault(..))
import Framework.Runtime.Identity
import Framework.Runtime.Frame
import Framework.Runtime.Binding (Binding(..), readBindingOwner)
import Framework.Runtime.Retention
import Framework.Runtime.Delivery (View)
import Framework.Runtime.Scope
  ( Scopes, ScopeBinding, ScopeBindings, ScopeUser(..), ScopeHandler(..), ScopeInstance(..), ScopeRecord(..), ScopeInput(..)
  , configureScopeRelations, cleanupAvailable, saveCleanupFailures )
import Framework.Prototype
import Framework.Prototype.Index
import Framework.Prototype.Coordinate (Coord, within)
import Framework.Prototype.Slot (Slot(..))
import Framework.Prototype.Structure (scopeRelations)

-- 保存生成区真正的 MethodGen 身份及同一份 Prototype 的运行索引；不复制成字符串图。
data PrototypeReference = forall method. (Eq method, Show method) =>
  PrototypeReference (PrototypeIndex method)

-- 同时取得索引与原型；按身份的查询走索引，其余字段仍读原型。
indexed :: PrototypeIndex method -> (PrototypeIndex method, Prototype method)
indexed index = (index, indexedPrototype index)

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
  , runtimeAssets :: IORef (Map.Map (Origin, Slot) (ScopeBinding environment cause))
  -- 有限 AST 每个挂载只启动一次；完成后只保留身份，供后继读取，不保留其 activation。
  , runtimeOrigins :: IORef [(Coord, Origin)]
  , runtimeActivations :: MVar [(ActivationId, Activation environment cause)]
  , runtimeOriginSequence :: IORef Integer
  , runtimeActivationSequence :: IORef Integer
  -- 每个 Context 一份运行级最新发布（持续资产也写这里）；帧不是可见性边界。按 Context 编号寻址。
  , runtimeLatest :: IORef (IntMap.IntMap (ScopeBinding environment cause))
  -- 每个作用范围（lifelong 或静态运行）里持续资产的发布：有 handler 以 stream @T 读取 x:xs 的（原型 effectHistory）
  -- 保存从首条起的全部发布，其余只保存本作用范围的最后一条。每个作用范围各有一份，互不混入；
  -- lifelong 的来源开始与结束时放掉自己的一份，静态运行保留到运行结束。作用范围之外的发布只为 effectHistory 追加。
  , runtimeHistory :: IORef (Map.Map (Int, Maybe NodeId) (View environment cause))
  -- 发布即回调：生成的回调表由 Execution 安装。参数是发布方的位置、发布的资产、这次 Binding 与发布方调用已捕获的普通绑定。
  , runtimeReactions :: IORef (Reaction environment cause)
  -- lifelong 外 requests 一份持续资产：同步运行它的来源直到 streamEnd，同一次运行只跑一次；返回这次静态运行的作用范围。
  , runtimeStatic :: IORef (Place -> Slot -> IO (Either (Failure cause) NodeId))
  -- 发布与 parallel 分支的变化（开始、退出、汇合）时加一：require 在查值前取得这个编号，编号变了就重查，
  -- 查值与开始等待之间的发布不会漏掉。
  , runtimeVersion :: TVar Int
  -- 正在运行的 parallel 分支 → gen 写明它可能发布的资产。require 缺值时只在别的分支仍可能发布时等待。
  , runtimeBranches :: TVar (IntMap.IntMap [Slot])
  , runtimeBranchSequence :: IORef Int
  -- 正在执行的线程数：根线程与 parallel 的各分支，不含等待子分支的父线程；最后一个子分支退出时把名额直接交还父线程。
  , runtimeRunning :: TVar Int
  -- 其中挂起的线程：等待 require 的（每次编号变化都同时放行并清零，放行后尚未重查的不再计入）与等待别人的静态运行结束的。
  -- 挂起数达到执行数说明没有线程还能发布：等待者放弃，按缺值报错，不留下永远阻塞的调用。
  , runtimeWaiting :: TVar Int
  , runtimeStaticWaiting :: TVar Int
  }

-- 一次发布之后要执行的回调；Just 是回调中的失败，沿发布方的调用传播。
type Reaction environment cause =
  Place -> Slot -> ScopeBinding environment cause -> ScopeBindings environment cause -> IO (Maybe (Failure cause))

-- 一次执行所在的位置：它所在的 parallel 分支（从内到外），以及持续资产的作用范围（lifelong 的路径或静态运行的标识）。
-- 读取等待时不等自己所在的分支；历史与 behavior 的比较按作用范围分开。回调继承发布方的位置。
data Place = Place { placeBranches :: [Int], placeScope :: Maybe NodeId }

rootPlace :: Place
rootPlace = Place [] Nothing

newRuntimeGraph
  :: (Eq method, Show method)
  => PrototypeIndex method -> Scopes environment cause -> IO (RuntimeGraph environment cause)
newRuntimeGraph index scopes = do
  coordinator <- case scopes of
    first : _ -> readIORef (scopeCoordinator first)
    [] -> newMVar ()
  frame <- newExecutionFrame coordinator Nothing (rootNodesOf index) []
  retentions <- newRetentions coordinator
  RuntimeGraph (PrototypeReference index) scopes frame retentions
    <$> newIORef Map.empty <*> newIORef [] <*> newMVar [] <*> newIORef 0 <*> newIORef 0
    <*> newIORef IntMap.empty <*> newIORef Map.empty
    <*> newIORef (\_ _ _ _ -> pure Nothing)
    <*> newIORef (\_ source -> ioError (userError ("No static run is installed for " ++ slotName source)))
    <*> newTVarIO 0 <*> newTVarIO IntMap.empty <*> newIORef 0 <*> newTVarIO 1 <*> newTVarIO 0 <*> newTVarIO 0

-- ScopeTree 的独立构建与校验仍在 Prototype；这里只把同一树的关系装入现有控制对象。
configureRuntimeScopes :: RuntimeGraph environment cause -> IO ()
configureRuntimeScopes graph = case runtimePrototype graph of
  PrototypeReference (indexedPrototype -> prototype) -> do
    configureScopeRelations (scopeRelations prototype) (runtimeScopes graph)
    forM_ (runtimeScopes graph) $ \family ->
      writeIORef (scopeReachable family) $ \slot -> do
        held <- retainedInstance graph slot
        if held then pure True else reachableInstance graph slot

-- Binding 保留：实际交付/捕获，以及将来的读取位置仍合法可读的最新值。
-- 仅检查共享 ownership，既不解释业务字段，也不把持有关系加入 ScopeTree。
-- 调用方已经持有 scope/frame 协调锁。
retainedInstance :: RuntimeGraph environment cause -> ScopeInstance environment cause -> IO Bool
retainedInstance graph slot = case runtimePrototype graph of
  PrototypeReference index -> do
    active <- retainedBindings (runtimeRetentions graph)
    held <- ownsAny active
    if held then pure True else do
        frames <- framePendingViews (runtimeRootFrame graph)
        assets <- readIORef (runtimeLatest graph)
        -- 将来的读取位置读运行级最新值；lifelong 单元的未来回调读将来的交付，不能拿最新一条代替。
        let selected point source plan = case plan of
              SessionSourced | isJust (nodeBoundary (driveAt index point)) -> []
              _ -> [value | Just value <- [IntMap.lookup (slotNumber source) assets]]
            future = concat [selected node source plan
              | (_, pending, _) <- frames, node <- pending, (source, plan) <- sourcesAt index node]
        ownsAny future
  where
    ownsAny values = or <$> mapM (fmap (maybe False ((== scopeRecord slot) . scopeRecord . snd)) . readBindingOwner) values

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
collectParameterScopes :: RuntimeGraph environment cause -> Slot -> IO ()
collectParameterScopes graph source = case runtimePrototype graph of
  PrototypeReference index -> collectNamedScopes graph (parameterScopesOf index source)

collectNamedScopes :: RuntimeGraph environment cause -> [Slot] -> IO ()
collectNamedScopes _ [] = pure ()
collectNamedScopes graph selected = case runtimePrototype graph of
  PrototypeReference index -> do
    let relevant = scopeClosureOf index selected
    collectScopes graph (filter ((`elem` relevant) . scopeSlot) (runtimeScopes graph))

-- 待用查询：普通参数先固定捕获、再共享最新值；持续参数先本次交付、再最新值。
-- 查询在 scope 协调锁内，不生产。
reachableInstance :: RuntimeGraph environment cause -> ScopeInstance environment cause -> IO Bool
reachableInstance graph slot = case runtimePrototype graph of
  PrototypeReference index -> do
    -- 普通参数的使用者可位于任意活动帧；仍按具体 Binding 的生产身份匹配。
    -- 根帧的常驻预约与实际轮帧共用这些开启计划，不提升实例的归属帧。
    reservations <- framePendingViews (runtimeRootFrame graph)
    -- 同一锁内纳入正在执行的根调用及其捕获，覆盖“已读参数、尚未认领实例”的交接。
    active <- readMVar (runtimeActivations graph)
    let pendingFrames = reservations ++ [(activationFrame call, [node], [])
          | (_, call) <- active, TargetedBoot node <- [activationBoot call]]
    assets <- readIORef (runtimeLatest graph)
    instances <- concat <$> mapM (readMVar . scopeInstances) (runtimeScopes graph)
    snapshots <- forM instances $ \instance' -> do
      values <- scopeBindings <$> readIORef (scopeRecord instance')
      pure (instance', values)
    let candidates = [(frame, opening, delivered)
          | (frame, pending, delivered) <- pendingFrames
          , node <- pending, opening <- openingsAt index node
          , indexedOpeningScope opening == scopeSlot (scopeFamily slot)]
        matches instance' frame delivered opening =
          and <$> mapM (matchesInput frame delivered opening) (scopeInputs instance')
        matchesInput frame delivered opening (ScopeInput source production) = case lookup source (indexedOpeningSources opening) of
          Nothing -> pure False
          Just SessionSourced -> matchesSession frame opening source production
          Just OwnChainAt -> pure False -- 原型校验拒绝不明确的开启来源。
          Just (ChainsAt nodes)
            | isResourceSlot index source ->
                -- 资源复用不重新发布：按原生产身份找到 owner，再验证同一入口会开启它。
                -- ScopeTree 已保证无环，不能用同注册的其他实例代替这个 owner。
                or <$> sequence [matches parent frame delivered parentOpening | (parent, values) <- snapshots
                   , scopeContextSource (scopeFamily parent) == Just source
                   , Just value <- [lookup source values], bindingProduction value == Just production
                   , parentOpening <- openingsAt index (indexedOpeningNode opening)
                   , indexedOpeningScope parentOpening == scopeSlot (scopeFamily parent)]
            | otherwise -> do
                captured <- capturedFrameInputs frame
                let reader = indexedOpeningNode opening
                    selectors = nodeCaptures (driveAt index reader)
                    local = [identity | at <- reader : selectors
                      , (node, context, identity) <- captured, node == at, context == source]
                    deliveredHere = [identity | (publishedAt, context, identity) <- delivered
                      , context == source, publishedAt `elem` nodes]
                pure $ case local ++ deliveredHere of
                  identity : _ -> identity == production
                  -- 必定以新参数开启而尚未捕获的调用，不会复用上一轮的旧参数实例。
                  [] | indexedOpeningKinds opening == [ExecutionMultiple] -> False
                     | otherwise -> maybe False ((== Just production) . bindingProduction) (IntMap.lookup (slotNumber source) assets)
        -- 持续参数：本次回调已固定的交付优先；lifelong 单元的未来回调读将来的交付，不保留旧实例；
        -- 其余位置读运行级最新值。
        matchesSession frame opening source production = do
          captured <- capturedFrameInputs frame
          let reader = indexedOpeningNode opening
              -- 只有 alternative 把捕获交给候选；chain 不隐式传递前一调用的视图。
              selectors = nodeCaptures (driveAt index reader)
              selected = [value | at <- reader : selectors
                , (node, context, value) <- captured, node == at, context == source]
          pure $ case selected of
            value : _ -> value == production
            [] | isJust (nodeBoundary (driveAt index reader)) -> False
               | otherwise -> maybe False ((== Just production) . bindingProduction) (IntMap.lookup (slotNumber source) assets)
    or <$> mapM (\(frame, opening, delivered) -> matches slot frame delivered opening) candidates

-- 节点退休后只检查其开启位置及 ScopeTree 祖先。预约在进度写入的锁外进行，
-- 业务 close 失败和普通 IO 异常留作汇总；只有取消停止后续执行。
collectRuntimeScopes :: RuntimeGraph environment cause -> [Coord] -> IO ()
collectRuntimeScopes _ [] = pure ()
collectRuntimeScopes graph retired = case runtimePrototype graph of
  PrototypeReference index -> collectNamedScopes graph
    [indexedOpeningScope opening | node <- retired, opening <- openingsAt index node]

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
newOrigin :: RuntimeGraph environment cause -> Coord -> IO Origin
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
resetOrigins :: RuntimeGraph environment cause -> Coord -> IO ()
resetOrigins graph prefix = mask $ \restore -> do
  released <- withFrameLock (runtimeRootFrame graph) $ do
    origins <- readIORef (runtimeOrigins graph)
    let removed = [origin | (node, origin) <- origins, node `within` prefix]
        kept = [(node, origin) | (node, origin) <- origins, not (node `within` prefix)]
    length kept `seq` writeIORef (runtimeOrigins graph) kept
    dropPublications graph removed
  restore (collectRetainedScopes graph released)

dropPublications :: RuntimeGraph environment cause -> [Origin] -> IO [ScopeBinding environment cause]
dropPublications _ [] = pure []
dropPublications graph origins = atomicModifyIORef' (runtimeAssets graph) $ \assets ->
  let (gone, kept) = Map.partitionWithKey (\(origin, _) _ -> origin `elem` origins) assets
  in (kept, filter bindingResource (Map.elems gone))

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
resolveDefinition (PrototypeReference (indexed -> (index, prototype))) boot = do
  entry <- case boot of
    TargetedBoot node -> either (Left . show) (Right . chainEntry) (chainAt index node)
    -- 解析器与 request 一样发布一次资产；同一 Context 至多有其中一种生产入口。
    RequestBoot source -> maybe (Left ("Runtime request has no Context production entry: " ++ slotName source)) Right
      (requestEntryOf index source)
  case [definition | definition <- protoChainDefinitions prototype, definitionEntry definition == entry] of
    [definition] -> Right (ChainReference definition)
    _ -> Left "Runtime activation has no unique static chain definition"

-- 写入最新值表（持续资产另追加历史）；回调由 App 在发布之后调用 react，不在这里执行。
publishAsset :: RuntimeGraph environment cause -> Maybe NodeId -> Origin -> Slot
             -> ScopeBinding environment cause -> IO ()
publishAsset graph scope origin source value = mask $ \restore -> do
  (released, replacedParameter) <- withFrameLock (runtimeRootFrame graph) $ do
    previous <- atomicModifyIORef' (runtimeAssets graph) $ \assets ->
      let (old, updated) = Map.insertLookupWithKey (\_ new _ -> new) (origin, source) value assets
      in (updated, [replaced | Just replaced <- [old], bindingResource replaced])
    -- 资源仍只沿 owner 协议读取；普通值共享同一份 Binding，不重发生产身份。
    replaced <- if bindingResource value then pure False else do
      existed <- atomicModifyIORef' (runtimeLatest graph) $ \assets ->
        let (old, updated) = IntMap.insertLookupWithKey (\_ new _ -> new) (slotNumber source) value assets
        in (updated, isJust old)
      forM_ (bindingProduction value) $ \production ->
        captureFrameInputLocked (bindingFrame value) (originNode origin) source production
      let kept earlier
            | keepsHistory graph source = Just (maybe (Seq.singleton value) (|> value) earlier)
            | isJust scope = Just (Seq.singleton value)
            | otherwise = earlier
      atomicModifyIORef' (runtimeHistory graph) $ \histories ->
        (Map.alter kept (slotNumber source, scope) histories, ())
      pure existed
    pure (previous, replaced)
  notifyChange graph
  restore $ do
    collectRetainedScopes graph released
    if replacedParameter then collectParameterScopes graph source else pure ()

keepsHistory :: RuntimeGraph environment cause -> Slot -> Bool
keepsHistory graph source = case runtimePrototype graph of
  PrototypeReference index -> historyOf index source

-- 选中共享最新值与登记本次捕获身份在同一短临界区完成；普通业务 IO 不在锁内。
-- 没有值返回 Nothing，读取方立即按缺值处理。资源不从这张表取得。
readPublishedAsset :: RuntimeGraph environment cause -> ExecutionFrame -> Origin -> Slot
                   -> IO (Either ContextFault (Maybe (ScopeBinding environment cause)))
readPublishedAsset graph frame origin source = withFrameLock (runtimeRootFrame graph) $ do
  value <- IntMap.lookup (slotNumber source) <$> readIORef (runtimeLatest graph)
  forM_ (value >>= bindingProduction) $ \production ->
    captureFrameInputLocked frame (originNode origin) source production
  pure (Right value)

-- 持续资产在这个作用范围里到目前为止的发布，最新在后。isolated（静态运行的读取）只读本作用范围：
-- 一条都没有发布就是 Nothing，不拿别处的值顶替。否则本作用范围没有时读运行级最新一条（lifelong 之后的后继）。
readHistory :: RuntimeGraph environment cause -> Bool -> Maybe NodeId -> Slot -> IO (Maybe (View environment cause))
readHistory graph isolated scope source = do
  kept <- Map.lookup (slotNumber source, scope) <$> readIORef (runtimeHistory graph)
  case kept of
    Just history | not (Seq.null history) -> pure (Just history)
    _ | isolated -> pure Nothing
    _ -> fmap Seq.singleton . IntMap.lookup (slotNumber source) <$> readIORef (runtimeLatest graph)

-- lifelong 的来源开始或结束：放掉这个作用范围里这些资产的历史，最新值保留给后继的 require。
dropHistory :: RuntimeGraph environment cause -> NodeId -> [Slot] -> IO ()
dropHistory graph scope sources = atomicModifyIORef' (runtimeHistory graph) $ \histories ->
  (foldr (\source -> Map.delete (slotNumber source, Just scope)) histories sources, ())

notifyChange :: RuntimeGraph environment cause -> IO ()
notifyChange graph = atomically (changed graph)

-- 编号加一并放行所有等待 require 的线程：它们都会重查，在同一事务里清零，放行后尚未调度的线程不被当成仍在等待。
changed :: RuntimeGraph environment cause -> STM ()
changed graph = do
  modifyTVar' (runtimeVersion graph) (+ 1)
  writeTVar (runtimeWaiting graph) 0

-- 一个 parallel 的各分支开始前一次登记全部分支（各自可能发布的资产），避免先开始的分支看不到后开始的兄弟。
-- 父线程转为等待子分支：执行中的线程数加上分支数再减去父线程自己。
openBranches :: RuntimeGraph environment cause -> [[Slot]] -> IO [Int]
openBranches graph publishes = do
  first <- atomicModifyIORef' (runtimeBranchSequence graph) (\next -> (next + length publishes, next))
  let identities = zip [first ..] publishes
  when (not (null publishes)) $ atomically $ do
    modifyTVar' (runtimeBranches graph) (\live -> foldr (uncurry IntMap.insert) live identities)
    modifyTVar' (runtimeRunning graph) (+ (length publishes - 1))
    changed graph
  pure (map fst identities)

-- 一个分支退出（含失败与取消）：撤销它的登记；还有兄弟分支在执行时执行数少一个，它是最后一个时
-- 名额直接交还父线程（父线程接着执行汇合后的步骤，中间没有执行数偏少的时刻）。等待的 require 重查。
leaveBranch :: RuntimeGraph environment cause -> [Int] -> Int -> IO ()
leaveBranch graph siblings identity = atomically $ do
  live <- readTVar (runtimeBranches graph)
  when (IntMap.member identity live) $ do
    writeTVar (runtimeBranches graph) (IntMap.delete identity live)
    when (any (\other -> other /= identity && IntMap.member other live) siblings) $
      modifyTVar' (runtimeRunning graph) (subtract 1)
    changed graph

-- 父线程不再等待子分支：仍在登记表中的分支（没来得及退出就被取消的）一并撤销，名额交还父线程。
rejoinBranches :: RuntimeGraph environment cause -> [Int] -> IO ()
rejoinBranches graph identities = atomically $ do
  live <- readTVar (runtimeBranches graph)
  let remaining = filter (`IntMap.member` live) identities
  when (not (null remaining)) $ do
    writeTVar (runtimeBranches graph) (foldr IntMap.delete live remaining)
    modifyTVar' (runtimeRunning graph) (+ (1 - length remaining))
    changed graph

-- require 查值之前取得的编号。
publicationTicket :: RuntimeGraph environment cause -> IO Int
publicationTicket graph = readTVarIO (runtimeVersion graph)

-- require 缺值后：编号已变（查值之后有发布或分支退出）就重查；本次位置之外仍有运行中的分支可能发布这些资产，
-- 且不是所有执行中的线程都在等待，就挂起到下一次变化再重查（返回 True）。没有这样的分支，或所有线程都在等待
-- （互相等待对方将来的生产），返回 False，读取方按缺值报错。
awaitPublication :: RuntimeGraph environment cause -> Place -> [Slot] -> Int -> IO Bool
awaitPublication graph place sources ticket = do
  decision <- atomically $ do
    version <- readTVar (runtimeVersion graph)
    possible <- publishable
    waiting <- suspended
    running <- readTVar (runtimeRunning graph)
    if version /= ticket then pure (Just True)
      else if not possible || waiting + 1 >= running then pure (Just False)
      else Nothing <$ modifyTVar' (runtimeWaiting graph) (+ 1)
  case decision of
    Just answer -> pure answer
    Nothing -> do
      atomically (do
          version <- readTVar (runtimeVersion graph)
          possible <- publishable
          waiting <- suspended
          running <- readTVar (runtimeRunning graph)
          check (version /= ticket || not possible || waiting >= running))
        `finally` withdraw
      pure True
  where
    suspended = (+) <$> readTVar (runtimeWaiting graph) <*> readTVar (runtimeStaticWaiting graph)
    -- 编号变化时已经清零放行；只有因放弃或取消醒来（编号未变）时自己退出计数。
    withdraw = atomically $ do
      version <- readTVar (runtimeVersion graph)
      when (version == ticket) (modifyTVar' (runtimeWaiting graph) (subtract 1))
    publishable = do
      live <- readTVar (runtimeBranches graph)
      pure (or [any (`elem` sources) publishes | (identity, publishes) <- IntMap.toList live
        , identity `notElem` placeBranches place])

-- 一次共享的静态运行：结果，以及等它结束的调用数（计入挂起数，运行结束时在同一事务里放行）。
data StaticRun cause = StaticRun (TVar (Maybe (Maybe (Failure cause)))) (TVar Int)

newStaticRun :: IO (StaticRun cause)
newStaticRun = StaticRun <$> newTVarIO Nothing <*> newTVarIO 0

-- 运行方填入结果（Nothing 表示成功），放行全部等待者。
finishStatic :: RuntimeGraph environment cause -> StaticRun cause -> Maybe (Failure cause) -> IO ()
finishStatic graph (StaticRun result waiters) outcome = atomically $ do
  writeTVar result (Just outcome)
  count <- readTVar waiters
  writeTVar waiters 0
  modifyTVar' (runtimeStaticWaiting graph) (subtract count)
  changed graph

-- 别的调用正在运行同一来源：等它结束。等待期间计为挂起，所有线程都挂起时其中等待 require 的一方会按缺值放弃，
-- 运行方因此失败并填入结果，这里不会永远阻塞。
awaitStatic :: RuntimeGraph environment cause -> StaticRun cause -> IO (Maybe (Failure cause))
awaitStatic graph (StaticRun result waiters) = do
  ready <- atomically $ readTVar result >>= \found -> case found of
    Just outcome -> pure (Just outcome)
    Nothing -> do
      modifyTVar' waiters (+ 1)
      modifyTVar' (runtimeStaticWaiting graph) (+ 1)
      pure Nothing
  case ready of
    Just outcome -> pure outcome
    Nothing -> atomically (readTVar result >>= maybe retry pure) `onException` atomically (do
      found <- readTVar result
      when (isNothing found) $ do
        modifyTVar' waiters (subtract 1)
        modifyTVar' (runtimeStaticWaiting graph) (subtract 1))

installReactions :: RuntimeGraph environment cause -> Reaction environment cause -> IO ()
installReactions graph = writeIORef (runtimeReactions graph)

-- 发布之后执行生成的回调；在发布方的调用栈里同步运行。
react :: RuntimeGraph environment cause -> Reaction environment cause
react graph place source value captured = do
  reaction <- readIORef (runtimeReactions graph)
  reaction place source value captured

installStatic :: RuntimeGraph environment cause -> (Place -> Slot -> IO (Either (Failure cause) NodeId)) -> IO ()
installStatic graph = writeIORef (runtimeStatic graph)

runStatic :: RuntimeGraph environment cause -> Place -> Slot -> IO (Either (Failure cause) NodeId)
runStatic graph place source = do
  run <- readIORef (runtimeStatic graph)
  run place source
