-- 一次有限执行的节点进度；交付游标由 Runtime 的 DeliveryFrame 单独保存。
-- 本模块不依赖 Scope 或 Graph，scope 在同一协调锁内只读这些事实。
module Framework.Runtime.Frame
  ( ExecutionFrame, NodeProgress(..), newExecutionFrame, newChildFrame, newSessionFrame, frameParent, frameDepth, frameBoundary, withFrameLock
  , frameNodes, framePendingNodes, framePendingViews, captureFrameDeliveries, DeliveryIdentity, owningFrame
  , frameNodeProgress, frameSignal, notifyFrame
  , installSessionInputs, pendingSessionInput, captureFrameInput, captureFrameInputLocked, resetFrameInputsLocked, capturedFrameInputs
  , startFrameNode, completeFrameNode, skipFrameSubtree, finishExecutionFrame
  ) where

import Control.Concurrent.MVar (MVar, newEmptyMVar, putMVar, withMVar)
import Control.Exception (uninterruptibleMask_)
import Control.Monad (forM_, when)
import Data.IORef (IORef, atomicModifyIORef', modifyIORef', newIORef, readIORef, writeIORef)
import Data.List (isPrefixOf, nub, nubBy)
import Framework.Prototype (NodeId)
import Framework.Runtime.Identity (ActivationId)
import Framework.Prototype.Slot (Slot)

data NodeProgress = Pending | Running | Completed | Skipped
  deriving (Eq, Show)

-- 身份记录，不保存值、资源引用或历史。frameDelivered 的 NodeId 是普通伴随资产的
-- 发布位置；frameCaptures 的 NodeId 是固定该视图的读取位置，两张表不混用。
type DeliveryIdentity = (NodeId, Slot, ActivationId)

data ExecutionFrame = ExecutionFrame
  { frameParent :: Maybe ExecutionFrame
  , frameDepth :: Int
  -- 轮帧的所属 lifelong 挂载；退休后仍可定位合法外部后继，不把实例提升到根帧。
  , frameBoundary :: Maybe NodeId
  , frameCoordinator :: MVar ()
  , frameProgress :: IORef [(NodeId, NodeProgress)]
  , frameDelivered :: IORef [DeliveryIdentity]
  , frameChildren :: IORef [ExecutionFrame]
  -- v1（2026-11-17）：本轮会话的已选/下一条身份查询；不领取、不启动来源。
  -- 查询只读领取槽与会话状态，不能获取帧协调锁或运行 handler。
  , frameSessionInputs :: IORef (Slot -> ActivationId -> IO (Maybe Bool))
  -- 普通读取、持续读取与 alternative 交接已固定的值；只保留身份，不保留历史。
  , frameCaptures :: IORef [DeliveryIdentity]
  -- 根帧和子帧共用一个变化信号；普通发布与节点退休都叫醒缺值读取。
  , frameChanged :: IORef (MVar ())
  }

instance Eq ExecutionFrame where
  left == right = frameProgress left == frameProgress right

newExecutionFrame :: MVar () -> Maybe ExecutionFrame -> Maybe NodeId -> [NodeId] -> IO ExecutionFrame
newExecutionFrame coordinator parent boundary nodes =
  -- 一般子帧随后安装交付查询；准备期间只对持续参数保守持有。
  newPreparedFrame coordinator parent boundary nodes []
    (\_ _ -> pure (case parent of Nothing -> Nothing; Just _ -> Just True))

-- 初始化捕获和查询后才发布到父帧，避免并行回收观察到不完整的会话预约。
newPreparedFrame :: MVar () -> Maybe ExecutionFrame -> Maybe NodeId -> [NodeId] -> [DeliveryIdentity]
                 -> (Slot -> ActivationId -> IO (Maybe Bool)) -> IO ExecutionFrame
newPreparedFrame coordinator parent boundary nodes delivered query = uninterruptibleMask_ $ do
  changed <- maybe (newEmptyMVar >>= newIORef) (pure . frameChanged) parent
  frame <- ExecutionFrame parent (maybe 0 ((+ 1) . frameDepth) parent) boundary coordinator
    <$> newIORef [(node, Pending) | node <- nub nodes]
    <*> newIORef delivered <*> newIORef [] <*> newIORef query <*> newIORef [] <*> pure changed
  withMVar coordinator $ \_ ->
    forM_ parent $ \ancestor -> modifyIORef' (frameChildren ancestor) (frame :)
  pure frame

newChildFrame :: ExecutionFrame -> NodeId -> [NodeId] -> IO ExecutionFrame
newChildFrame parent boundary = newExecutionFrame (frameCoordinator parent) (Just parent) (Just boundary)

-- 会话待用帧 v1（2026-11-18）：保存 gen 已给出的生产挂载，覆盖步骤之间的复用。
-- 它只预约未来使用，不作为发布的归属帧；interpreter 托管会话没有 AST 边界。
-- 生产停止后仍按既有排空规则保留预约，直到会话退役才摘除。
newSessionFrame :: ExecutionFrame -> Maybe NodeId -> [NodeId] -> [DeliveryIdentity]
                -> (Slot -> ActivationId -> IO (Maybe Bool)) -> IO ExecutionFrame
newSessionFrame parent = newPreparedFrame (frameCoordinator parent) (Just parent)

-- 执行帧与 scope 归属共用的内存协调锁。Graph 的发布/保留交接也在这里串行化，
-- 不能只屏蔽取消而让另一线程的回收看见交接空窗。锁内不执行 IO handler、不等任务。
withFrameLock :: ExecutionFrame -> IO value -> IO value
withFrameLock frame action = uninterruptibleMask_ $
  withMVar (frameCoordinator frame) (const action)

-- 只读，不再获取协调锁；scope 的可达性检查在锁内调用。
frameNodes :: ExecutionFrame -> IO [(NodeId, NodeProgress)]
frameNodes = readIORef . frameProgress

framePendingNodes :: ExecutionFrame -> IO [NodeId]
framePendingNodes frame = map fst . filter (pending . snd) <$> frameNodes frame

-- 等待读取从实际子帧向外查找，先命中本轮节点；根帧的 lifelong 常驻预约不能覆盖它。
-- 未知位置保持 Nothing，调用方不能把它当作已经完成。
frameNodeProgress :: ExecutionFrame -> NodeId -> IO (Maybe NodeProgress)
frameNodeProgress frame node = uninterruptibleMask_ $
  withMVar (frameCoordinator frame) $ \_ -> lookupIn frame
  where
    lookupIn current = do
      progress <- lookup node <$> frameNodes current
      case progress of
        Just found -> pure (Just found)
        Nothing -> maybe (pure Nothing) lookupIn (frameParent current)

-- 等待者先取信号再读取绑定及进度；此后的变化都填满这份信号，不丢失唤醒。
frameSignal :: ExecutionFrame -> IO (MVar ())
frameSignal = readIORef . frameChanged

-- 不获取协调锁，既可在节点退休的锁内调用，也可在普通资产发布后调用。
notifyFrame :: ExecutionFrame -> IO ()
notifyFrame frame = uninterruptibleMask_ $ do
  fresh <- newEmptyMVar
  previous <- atomicModifyIORef' (frameChanged frame) (\current -> (fresh, current))
  putMVar previous ()

-- 根帧的常驻位置描述未来轮次；活动子帧另带本轮已经固定的交付身份。
-- 与 frameNodes 一样只读，调用者在 scope 协调锁内取得一致视图。
framePendingViews :: ExecutionFrame -> IO [(ExecutionFrame, [NodeId], [DeliveryIdentity])]
framePendingViews frame = do
  nodes <- framePendingNodes frame
  delivered <- readIORef (frameDelivered frame)
  children <- readIORef (frameChildren frame)
  descendants <- concat <$> mapM framePendingViews children
  pure ((frame, nodes, delivered) : descendants)

-- 安装发生在本轮启动前；查询在 scope 协调锁内执行，结束时清掉闭包。
installSessionInputs :: ExecutionFrame -> (Slot -> ActivationId -> IO (Maybe Bool)) -> IO ()
installSessionInputs frame = writeIORef (frameSessionInputs frame)

pendingSessionInput :: ExecutionFrame -> Slot -> ActivationId -> IO (Maybe Bool)
pendingSessionInput frame source production = do
  query <- readIORef (frameSessionInputs frame)
  query source production

capturedFrameInputs :: ExecutionFrame -> IO [DeliveryIdentity]
capturedFrameInputs = readIORef . frameCaptures

captureFrameInput :: ExecutionFrame -> NodeId -> Slot -> ActivationId -> IO ()
captureFrameInput frame node source production = withFrameLock frame $
  captureFrameInputLocked frame node source production

-- 普通共享值的选择与捕获在同一协调锁内提交，避免覆盖发布后的回收抢先关闭参数实例。
captureFrameInputLocked :: ExecutionFrame -> NodeId -> Slot -> ActivationId -> IO ()
captureFrameInputLocked frame node source production = do
  current <- readIORef (frameCaptures frame)
  let updated = (node, source, production) : filter (\(at, context, _) -> at /= node || context /= source) current
  -- 会话步骤可反复写同一静态位置；只强制身份表的脊，防止 filter thunk 保留旧身份链。
  length updated `seq` writeIORef (frameCaptures frame) updated

-- 一个静态会话挂载会重复调用；新根调用安装自己的捕获，不能沿用上一步身份。
-- 调用者已经持有协调锁。
resetFrameInputsLocked :: ExecutionFrame -> NodeId -> IO ()
resetFrameInputsLocked frame node = do
  current <- readIORef (frameCaptures frame)
  let kept = filter (\(at, _, _) -> at /= node) current
  length kept `seq` writeIORef (frameCaptures frame) kept

-- 同一轮的交付固定不变；重复 lower 只补入此前尚未领取的来源。
captureFrameDeliveries :: ExecutionFrame -> [DeliveryIdentity] -> IO ()
captureFrameDeliveries _ [] = pure ()
captureFrameDeliveries frame deliveries = uninterruptibleMask_ $
  withMVar (frameCoordinator frame) $ \_ -> do
    current <- readIORef (frameDelivered frame)
    let key (node, source, _) = (node, source)
        updated = nubBy (\left right -> key left == key right) (current ++ deliveries)
    when (length updated /= length current) $ writeIORef (frameDelivered frame) updated

pending :: NodeProgress -> Bool
pending progress = progress == Pending || progress == Running

-- 参数来自当前帧或其祖先；无参实例归根帧，跨轮读取不改变原生产的帧。
owningFrame :: ExecutionFrame -> [ExecutionFrame] -> ExecutionFrame
owningFrame root = foldl deeper root
  where deeper selected candidate
          | frameDepth candidate > frameDepth selected = candidate
          | otherwise = selected

updateFrame :: ExecutionFrame -> (NodeId -> NodeProgress -> NodeProgress) -> IO [NodeId]
updateFrame frame advance = uninterruptibleMask_ $
  withMVar (frameCoordinator frame) $ \_ -> do
    previous <- frameNodes frame
    let updated = [(node, advance node progress) | (node, progress) <- previous]
        retired = [node | ((node, old), (_, new)) <- zip previous updated, pending old, not (pending new)]
    foldr (\(_, progress) rest -> progress `seq` rest) () updated `seq`
      writeIORef (frameProgress frame) updated
    when (not (null retired)) (notifyFrame frame)
    pure retired

startFrameNode :: ExecutionFrame -> NodeId -> IO ()
startFrameNode frame selected = do
  _ <- updateFrame frame $ \node progress ->
    if node == selected && progress == Pending then Running else progress
  pure ()

completeFrameNode :: ExecutionFrame -> NodeId -> IO [NodeId]
completeFrameNode frame selected = updateFrame frame $ \node progress ->
  if node == selected && pending progress then Completed else progress

-- 分支退出前已经等待其受控子任务；只撤销尚未进入的节点，不碰其他正在执行的分支。
skipFrameSubtree :: ExecutionFrame -> NodeId -> IO [NodeId]
skipFrameSubtree frame prefix = updateFrame frame $ \node progress ->
  if prefix `isPrefixOf` node && progress == Pending then Skipped else progress

-- 调用方先等受控任务退出。帧结束释放进度与交付身份，并从父帧摘除，不累计历史帧。
finishExecutionFrame :: ExecutionFrame -> IO [NodeId]
finishExecutionFrame frame = uninterruptibleMask_ $
  withMVar (frameCoordinator frame) $ \_ -> do
    previous <- frameNodes frame
    writeIORef (frameProgress frame) []
    writeIORef (frameDelivered frame) []
    writeIORef (frameSessionInputs frame) (\_ _ -> pure Nothing)
    writeIORef (frameCaptures frame) []
    writeIORef (frameChildren frame) []
    forM_ (frameParent frame) $ \parent -> do
      siblings <- filter (/= frame) <$> readIORef (frameChildren parent)
      length siblings `seq` writeIORef (frameChildren parent) siblings
    notifyFrame frame
    pure [node | (node, progress) <- previous, pending progress]
