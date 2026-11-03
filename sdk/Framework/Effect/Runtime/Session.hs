-- 生产会话的发布历史、广播通知、消费游标及停止句柄。
-- Runtime 启动并登记生产线程；本模块不执行生产方法，只保存交付并取消／等待该线程。
-- Runtime/Graph 控制会话的唯一登记和整体停止；Workflow/Execution 持有各单元游标。
-- 会话按（lifelong 边界，生产该资产的 Context 注册名）区分；注册名与运行时绑定来源同名。
-- Nothing 边界是 interpreter 托管的会话。
module Framework.Effect.Runtime.Session
  ( SessionKey, View, Delivery, Broken, Session, sessionKey, sessionBindings, sessionViews
  , newSession, appendDelivery, breakSession, setSessionWorker, stopSession
  , awaitHistory, Cursor, newCursor, takeDelivery
  ) where

import Control.Concurrent (ThreadId, killThread)
import Control.Concurrent.MVar (MVar, newEmptyMVar, newMVar, modifyMVar_, putMVar, readMVar, swapMVar)
import Control.Exception (SomeException, uninterruptibleMask_)
import Control.Monad (void)
import Data.IORef (IORef, atomicModifyIORef', newIORef, readIORef)
import Data.Sequence (Seq, (|>))
import qualified Data.Sequence as Seq
import Framework.Effect.Contract (Failure)
import Framework.Effect.Scope (ScopeBinding, ScopeBindings)
import Framework.Prototype (NodeId)

type SessionKey = (Maybe NodeId, String)

-- 交付视图：从会话首条发布到交付位置的绑定序列；每条保留自己的出身与共享归属。
type View environment cause = Seq (ScopeBinding environment cause)

-- 一次交付：到这一条为止的视图，以及产生这一条的生产步骤的其他普通发布（伴随发布）。
-- lifelong 单元读取以会话生产步骤为来源的普通资产时，读的是所处理交付的伴随发布，与交付同出一步。
type Delivery environment cause = (View environment cause, ScopeBindings environment cause)

-- 生产失败（Error 协议诊断后的 Failure）或生产任务的原生异常；会话不再产出。
type Broken cause = Either SomeException (Failure cause)

data SessionState environment cause = SessionState
  { stateEntries :: Seq (ScopeBinding environment cause)
  -- 与 stateEntries 逐条对应。
  , stateCompanions :: Seq (ScopeBindings environment cause)
  , stateBroken :: Maybe (Broken cause)
  -- 下一次变化时填入；等待方读到后重新取状态。每次变化换上新的空信号。
  , stateSignal :: MVar ()
  }

-- 边界的交接：进入 lifelong 时已经捕获的绑定与视图（例如外层 alternative 选择时读到的值）。
-- 每个生产步骤都从这份交接开始；interpreter 托管的会话没有交接。
data Session environment cause = Session
  { sessionKey :: SessionKey
  , sessionBindings :: ScopeBindings environment cause
  , sessionViews :: [(String, View environment cause)]
  , sessionState :: MVar (SessionState environment cause)
  , sessionWorker :: MVar (Maybe (ThreadId, MVar ()))
  }

newSession :: SessionKey -> ScopeBindings environment cause -> [(String, View environment cause)]
           -> IO (Session environment cause)
newSession key bindings views = do
  signal <- newEmptyMVar
  Session key bindings views <$> newMVar (SessionState Seq.empty Seq.empty Nothing signal) <*> newMVar Nothing

-- 两次相等的值仍是两条发布；会话已经失败时不再接受新条目。
appendDelivery :: Session environment cause -> ScopeBindings environment cause -> ScopeBinding environment cause -> IO ()
appendDelivery session companions value = changeState session $ \state -> case stateBroken state of
  Just _ -> Nothing
  Nothing -> Just state { stateEntries = stateEntries state |> value
                        , stateCompanions = stateCompanions state |> companions }

breakSession :: Session environment cause -> Broken cause -> IO ()
breakSession session reason = changeState session $ \state -> case stateBroken state of
  Just _ -> Nothing
  Nothing -> Just state { stateBroken = Just reason }

changeState :: Session environment cause
            -> (SessionState environment cause -> Maybe (SessionState environment cause)) -> IO ()
changeState session update = modifyMVar_ (sessionState session) $ \state -> case update state of
  Nothing -> pure state
  Just changed -> do
    fresh <- newEmptyMVar
    putMVar (stateSignal state) ()
    pure changed { stateSignal = fresh }

-- 等到状态满足条件；会话失败且条件仍不满足时返回失败。
awaitState :: Session environment cause -> (SessionState environment cause -> Maybe result)
           -> IO (Either (Broken cause) result)
awaitState session ready = do
  state <- readMVar (sessionState session)
  case (ready state, stateBroken state) of
    (Just result, _) -> pure (Right result)
    (Nothing, Just reason) -> pure (Left reason)
    (Nothing, Nothing) -> readMVar (stateSignal state) >> awaitState session ready

-- lifelong 外的有限读取：至少有一条发布后取当时的完整历史；之后的发布不改写这次视图。
awaitHistory :: Session environment cause -> IO (Either (Broken cause) (View environment cause))
awaitHistory session = awaitState session $ \state ->
  if Seq.null (stateEntries state) then Nothing else Just (stateEntries state)

-- 消费游标属于（单元，会话）：记录已经交付的条数，每次交付推进一条。
-- 单元逐轮推进同一个游标；一轮内并发读取由 Runtime.Frame 的领取槽合并，
-- 不能绕过 Frame 并发调用同一游标的 takeDelivery。
newtype Cursor = Cursor (IORef Int)

newCursor :: IO Cursor
newCursor = Cursor <$> newIORef 0

-- 领取下一条尚未交付的发布；视图是到这一条为止的历史，另带这一条的伴随发布。
-- 有积压时立即返回，没有时挂起等待。
takeDelivery :: Session environment cause -> Cursor -> IO (Either (Broken cause) (Delivery environment cause))
takeDelivery session (Cursor position) = do
  delivered <- readIORef position
  outcome <- awaitState session $ \state ->
    if Seq.length (stateEntries state) > delivered
      then Just (Seq.take (delivered + 1) (stateEntries state), Seq.index (stateCompanions state) delivered)
      else Nothing
  case outcome of
    Right _ -> atomicModifyIORef' position (\current -> (current + 1, ()))
    Left _ -> pure ()
  pure outcome

-- 运行层启动生产任务后登记；停止时取消并等待它退出，包括其中步骤的受控收尾。
setSessionWorker :: Session environment cause -> ThreadId -> MVar () -> IO ()
setSessionWorker session thread finished = void (swapMVar (sessionWorker session) (Just (thread, finished)))

stopSession :: Session environment cause -> IO ()
stopSession session = uninterruptibleMask_ $ do
  worker <- swapMVar (sessionWorker session) Nothing
  case worker of
    Nothing -> pure ()
    Just (thread, finished) -> killThread thread >> readMVar finished
