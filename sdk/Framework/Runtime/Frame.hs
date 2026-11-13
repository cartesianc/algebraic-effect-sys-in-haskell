-- 一次有限执行的节点进度；交付游标由 Runtime 的 DeliveryFrame 单独保存。
-- 本模块不依赖 Scope 或 Graph，scope 在同一协调锁内只读这些事实。
module Framework.Runtime.Frame
  ( ExecutionFrame, NodeProgress(..), newExecutionFrame, newChildFrame, frameParent, frameDepth
  , frameNodes, framePendingNodes, framePendingViews, captureFrameDeliveries, DeliveryIdentity, owningFrame
  , frameNodeProgress, frameSignal, notifyFrame
  , startFrameNode, completeFrameNode, skipFrameSubtree, finishExecutionFrame
  ) where

import Control.Concurrent.MVar (MVar, newEmptyMVar, putMVar, withMVar)
import Control.Exception (uninterruptibleMask_)
import Control.Monad (forM_, when)
import Data.IORef (IORef, atomicModifyIORef', modifyIORef', newIORef, readIORef, writeIORef)
import Data.List (isPrefixOf, nub, nubBy)
import Framework.Prototype (NodeId)
import Framework.Runtime.Identity (ActivationId)

data NodeProgress = Pending | Running | Completed | Skipped
  deriving (Eq, Show)

-- 只有已领取普通伴随资产的生产身份；不保存值、资源引用或未领取的历史。
type DeliveryIdentity = (NodeId, String, ActivationId)

data ExecutionFrame = ExecutionFrame
  { frameParent :: Maybe ExecutionFrame
  , frameDepth :: Int
  , frameCoordinator :: MVar ()
  , frameProgress :: IORef [(NodeId, NodeProgress)]
  , frameDelivered :: IORef [DeliveryIdentity]
  , frameChildren :: IORef [ExecutionFrame]
  -- 根帧和子帧共用一个变化信号；普通发布与节点退休都叫醒缺值读取。
  , frameChanged :: IORef (MVar ())
  }

instance Eq ExecutionFrame where
  left == right = frameProgress left == frameProgress right

newExecutionFrame :: MVar () -> Maybe ExecutionFrame -> [NodeId] -> IO ExecutionFrame
newExecutionFrame coordinator parent nodes = uninterruptibleMask_ $ do
  changed <- maybe (newEmptyMVar >>= newIORef) (pure . frameChanged) parent
  frame <- ExecutionFrame parent (maybe 0 ((+ 1) . frameDepth) parent) coordinator
    <$> newIORef [(node, Pending) | node <- nub nodes]
    <*> newIORef [] <*> newIORef [] <*> pure changed
  withMVar coordinator $ \_ ->
    forM_ parent $ \ancestor -> modifyIORef' (frameChildren ancestor) (frame :)
  pure frame

newChildFrame :: ExecutionFrame -> [NodeId] -> IO ExecutionFrame
newChildFrame parent = newExecutionFrame (frameCoordinator parent) (Just parent)

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
framePendingViews :: ExecutionFrame -> IO [([NodeId], [DeliveryIdentity])]
framePendingViews frame = do
  nodes <- framePendingNodes frame
  delivered <- readIORef (frameDelivered frame)
  children <- readIORef (frameChildren frame)
  descendants <- concat <$> mapM framePendingViews children
  pure ((nodes, delivered) : descendants)

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
    writeIORef (frameChildren frame) []
    forM_ (frameParent frame) $ \parent -> do
      siblings <- filter (/= frame) <$> readIORef (frameChildren parent)
      length siblings `seq` writeIORef (frameChildren parent) siblings
    notifyFrame frame
    pure [node | (node, progress) <- previous, pending progress]
