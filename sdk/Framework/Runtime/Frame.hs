{-# OPTIONS_GHC -fexpose-all-unfoldings -fspecialise-aggressively #-}
-- 一次有限执行的节点进度与已固定的输入身份；scope 在同一协调锁内只读这些事实，判断实例的待用。
-- 本模块不依赖 Scope 或 Graph。帧只服务资源回收，不是等待或调度的依据。
module Framework.Runtime.Frame
  ( ExecutionFrame, NodeProgress(..), newExecutionFrame, newChildFrame, frameParent, frameDepth, withFrameLock
  , frameNodes, framePendingNodes, framePendingViews, captureFrameDeliveries, DeliveryIdentity, owningFrame
  , captureFrameInput, captureFrameInputLocked, resetFrameInputsLocked, capturedFrameInputs
  , startFrameNode, completeFrameNode, skipFrameSubtree, finishExecutionFrame
  ) where

import Control.Concurrent.MVar (MVar, withMVar)
import Control.Exception (uninterruptibleMask_)
import Control.Monad (forM_, when)
import Data.IORef (IORef, modifyIORef', newIORef, readIORef, writeIORef)
import Data.List (nub, nubBy)
import Framework.Prototype.Coordinate (Coord, within)
import Framework.Runtime.Identity (ActivationId)
import Framework.Prototype.Slot (Slot)

data NodeProgress = Pending | Running | Completed | Skipped
  deriving (Eq, Show)

-- 身份记录，不保存值、资源引用或历史。frameDelivered 的 Coord 是本次回调交付及其伴随资产的
-- 发布位置；frameCaptures 的 Coord 是固定该值的读取位置，两张表不混用。
type DeliveryIdentity = (Coord, Slot, ActivationId)

data ExecutionFrame = ExecutionFrame
  { frameParent :: Maybe ExecutionFrame
  , frameDepth :: Int
  , frameCoordinator :: MVar ()
  , frameProgress :: IORef [(Coord, NodeProgress)]
  , frameDelivered :: IORef [DeliveryIdentity]
  , frameChildren :: IORef [ExecutionFrame]
  -- 普通读取、持续读取与 alternative 交接已固定的值；只保留身份，不保留历史。
  , frameCaptures :: IORef [DeliveryIdentity]
  }

instance Eq ExecutionFrame where
  left == right = frameProgress left == frameProgress right

newExecutionFrame :: MVar () -> Maybe ExecutionFrame -> [Coord] -> [DeliveryIdentity] -> IO ExecutionFrame
newExecutionFrame coordinator parent nodes delivered = uninterruptibleMask_ $ do
  frame <- ExecutionFrame parent (maybe 0 ((+ 1) . frameDepth) parent) coordinator
    <$> newIORef [(node, Pending) | node <- nub nodes]
    <*> newIORef delivered <*> newIORef [] <*> newIORef []
  withMVar coordinator $ \_ ->
    forM_ parent $ \ancestor -> modifyIORef' (frameChildren ancestor) (frame :)
  pure frame

-- 一次回调（单元的一次执行）或一次来源运行：交付身份在帧创建时一并登记，回收看到帧时就看得到它们。
newChildFrame :: ExecutionFrame -> [Coord] -> [DeliveryIdentity] -> IO ExecutionFrame
newChildFrame parent = newExecutionFrame (frameCoordinator parent) (Just parent)

-- 执行帧与 scope 归属共用的内存协调锁。Graph 的发布/保留交接也在这里串行化，
-- 不能只屏蔽取消而让另一线程的回收看见交接空窗。锁内不执行 IO handler、不等任务。
withFrameLock :: ExecutionFrame -> IO value -> IO value
withFrameLock frame action = uninterruptibleMask_ $
  withMVar (frameCoordinator frame) (const action)

-- 只读，不再获取协调锁；scope 的可达性检查在锁内调用。
frameNodes :: ExecutionFrame -> IO [(Coord, NodeProgress)]
frameNodes = readIORef . frameProgress

framePendingNodes :: ExecutionFrame -> IO [Coord]
framePendingNodes frame = map fst . filter (pending . snd) <$> frameNodes frame

-- 根帧描述整次 workflow 的未来位置；活动子帧另带本次已经固定的交付身份。
-- 与 frameNodes 一样只读，调用者在 scope 协调锁内取得一致视图。
framePendingViews :: ExecutionFrame -> IO [(ExecutionFrame, [Coord], [DeliveryIdentity])]
framePendingViews frame = do
  nodes <- framePendingNodes frame
  delivered <- readIORef (frameDelivered frame)
  children <- readIORef (frameChildren frame)
  descendants <- concat <$> mapM framePendingViews children
  pure ((frame, nodes, delivered) : descendants)

capturedFrameInputs :: ExecutionFrame -> IO [DeliveryIdentity]
capturedFrameInputs = readIORef . frameCaptures

captureFrameInput :: ExecutionFrame -> Coord -> Slot -> ActivationId -> IO ()
captureFrameInput frame node source production = withFrameLock frame $
  captureFrameInputLocked frame node source production

-- 普通共享值的选择与捕获在同一协调锁内提交，避免覆盖发布后的回收抢先关闭参数实例。
captureFrameInputLocked :: ExecutionFrame -> Coord -> Slot -> ActivationId -> IO ()
captureFrameInputLocked frame node source production = do
  current <- readIORef (frameCaptures frame)
  let updated = (node, source, production) : filter (\(at, context, _) -> at /= node || context /= source) current
  -- 来源步骤可反复写同一静态位置；只强制身份表的脊，防止 filter thunk 保留旧身份链。
  length updated `seq` writeIORef (frameCaptures frame) updated

-- 一个静态挂载会重复调用；新根调用安装自己的捕获，不能沿用上一步身份。
-- 调用者已经持有协调锁。
resetFrameInputsLocked :: ExecutionFrame -> Coord -> IO ()
resetFrameInputsLocked frame node = do
  current <- readIORef (frameCaptures frame)
  let kept = filter (\(at, _, _) -> at /= node) current
  length kept `seq` writeIORef (frameCaptures frame) kept

-- 同一次执行的交付固定不变；重复 lower 只补入此前没有的来源。
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

-- 参数来自当前帧或其祖先；无参实例归根帧，跨回调读取不改变原生产的帧。
owningFrame :: ExecutionFrame -> [ExecutionFrame] -> ExecutionFrame
owningFrame root = foldl deeper root
  where deeper selected candidate
          | frameDepth candidate > frameDepth selected = candidate
          | otherwise = selected

updateFrame :: ExecutionFrame -> (Coord -> NodeProgress -> NodeProgress) -> IO [Coord]
updateFrame frame advance = uninterruptibleMask_ $
  withMVar (frameCoordinator frame) $ \_ -> do
    previous <- frameNodes frame
    let updated = [(node, advance node progress) | (node, progress) <- previous]
        retired = [node | ((node, old), (_, new)) <- zip previous updated, pending old, not (pending new)]
    foldr (\(_, progress) rest -> progress `seq` rest) () updated `seq`
      writeIORef (frameProgress frame) updated
    pure retired

startFrameNode :: ExecutionFrame -> Coord -> IO ()
startFrameNode frame selected = do
  _ <- updateFrame frame $ \node progress ->
    if node == selected && progress == Pending then Running else progress
  pure ()

completeFrameNode :: ExecutionFrame -> Coord -> IO [Coord]
completeFrameNode frame selected = updateFrame frame $ \node progress ->
  if node == selected && pending progress then Completed else progress

-- 分支退出前已经等待其受控子任务；只撤销尚未进入的节点，不碰其他正在执行的分支。
skipFrameSubtree :: ExecutionFrame -> Coord -> IO [Coord]
skipFrameSubtree frame prefix = updateFrame frame $ \node progress ->
  if node `within` prefix && progress == Pending then Skipped else progress

-- 调用方先等受控任务退出。帧结束释放进度与交付身份，并从父帧摘除，不累计历史帧。
finishExecutionFrame :: ExecutionFrame -> IO [Coord]
finishExecutionFrame frame = uninterruptibleMask_ $
  withMVar (frameCoordinator frame) $ \_ -> do
    previous <- frameNodes frame
    writeIORef (frameProgress frame) []
    writeIORef (frameDelivered frame) []
    writeIORef (frameCaptures frame) []
    writeIORef (frameChildren frame) []
    forM_ (frameParent frame) $ \parent -> do
      siblings <- filter (/= frame) <$> readIORef (frameChildren parent)
      length siblings `seq` writeIORef (frameChildren parent) siblings
    pure [node | (node, progress) <- previous, pending progress]
