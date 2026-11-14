-- 生产会话的发布历史、广播通知、消费游标及停止句柄。
-- 会话只保留仍有读取义务的发布：历史只为按历史读取（streams）且尚未离开的读取方保留，
-- 其余情况只留尚未领取的积压和最新一条。保留多少由读取方登记决定，不改变任何一次读取的结果。
-- Runtime 启动并登记生产线程；本模块不执行生产方法，只保存交付并取消／等待该线程。
-- Runtime/Graph 控制会话的唯一登记和整体停止；Workflow/Execution 持有各单元游标。
-- 会话按（lifelong 边界，生产该资产的 Context 注册名）区分；注册名与运行时绑定来源同名。
-- Nothing 边界是 interpreter 托管的会话。
module Framework.Runtime.Session
  ( SessionKey, View, Delivery, Broken, Stopped(..), SourceEnded(..), DeliveryDrained(..)
  , Session, sessionKey, sessionBindings, sessionViews
  , newSession, appendDelivery, breakSession, endSession, wakeSession, setSessionWorker, stopSession
  , awaitHistory, Cursor, admitReaders, leaveSession, takeDelivery
  ) where

import Control.Concurrent (ThreadId, killThread)
import Control.Concurrent.MVar (MVar, newEmptyMVar, newMVar, modifyMVar, modifyMVar_, putMVar, readMVar, swapMVar, takeMVar)
import Control.Exception (Exception, SomeException, mask, onException, uninterruptibleMask_)
import Control.Monad (forM, void)
import Data.IORef (IORef, atomicModifyIORef', newIORef, readIORef)
import Data.Sequence (Seq, (|>))
import qualified Data.Sequence as Seq
import Framework.Language.Handler (Failure)
import Framework.Runtime.Scope (ScopeBinding, ScopeBindings)
import Framework.Prototype (NodeId)

type SessionKey = (Maybe NodeId, String)

-- 交付视图：到交付位置为止的绑定序列；每条保留自己的出身与共享归属。
-- 交给按历史读取的读取方时从会话首条发布开始；其余读取只用它的最新一条，较早的条目可能已经放掉。
type View environment cause = Seq (ScopeBinding environment cause)

-- 一次交付：到这一条为止的视图，以及产生这一条的生产步骤的其他普通发布（伴随发布）。
-- lifelong 单元读取以会话生产步骤为来源的普通资产时，读的是所处理交付的伴随发布，与交付同出一步。
type Delivery environment cause = (View environment cause, ScopeBindings environment cause)

-- 生产失败（Error 协议诊断后的 Failure）或生产任务的原生异常；会话不再产出。
type Broken cause = Either SomeException (Failure cause)

-- 领取不到交付的原因。Drained：来源已正常结束，且已发布的交付都已领取（或所在单元正在结束）；
-- 这是正常终止，不是失败。Broke：会话失败。
data Stopped cause = Drained | Broke (Broken cause)

-- SDK 内部的正常结束信号，以异常形式越过方法体；不是业务 Failure，不进入 Error 协议，
-- 也不被方法体内的 catchError 接住。
-- SourceEnded：Stream handler 调用 end，由生产任务接住并结束会话。
data SourceEnded = SourceEnded
instance Show SourceEnded where show _ = "SDK stream source ended"
instance Exception SourceEnded

-- DeliveryDrained：调用内第一次读取才领取交付，而会话已结束并排空；由单元调度接住并结束单元。
data DeliveryDrained = DeliveryDrained
instance Show DeliveryDrained where show _ = "SDK stream delivery drained"
instance Exception DeliveryDrained

data SessionState environment cause = SessionState
  -- 已经放掉的条目数：stateEntries 的首条是会话的第 stateBase 条发布。游标记录的是不随之变化的发布序号。
  { stateBase :: Int
  , stateEntries :: Seq (ScopeBinding environment cause)
  -- 与 stateEntries 逐条对应，只在领取那一条交付时使用。
  -- 发布序号小于 stateCleared 的伴随发布已被全部读取方领取，换成了空值。
  , stateCompanions :: Seq (ScopeBindings environment cause)
  , stateCleared :: Int
  -- 会话不再接受新发布：来源正常结束（Drained）或失败（Broke）。已有条目保留。
  , stateStopped :: Maybe (Stopped cause)
  -- 下一次变化时填入；等待方读到后重新取状态。每次变化换上新的空信号。
  , stateSignal :: MVar ()
  -- 仍可能领取交付的游标。Nothing：读取方尚未登记（lifelong 的会话在进入边界时启动，
  -- 各单元随后登记），此前的发布全部保留。interpreter 托管的会话没有游标，从创建起就是空表。
  , stateReaders :: Maybe [Cursor]
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
  let readers = maybe (Just []) (const Nothing) (fst key)
  Session key bindings views <$> newMVar (SessionState 0 Seq.empty Seq.empty 0 Nothing signal readers) <*> newMVar Nothing

-- 两次相等的值仍是两条发布；会话已经结束或失败时不再接受新条目。
appendDelivery :: Session environment cause -> ScopeBindings environment cause -> ScopeBinding environment cause -> IO ()
appendDelivery session companions value = changeState session $ \state -> case stateStopped state of
  Just _ -> Nothing
  Nothing -> Just state { stateEntries = stateEntries state |> value
                        , stateCompanions = stateCompanions state |> companions }

breakSession :: Session environment cause -> Broken cause -> IO ()
breakSession session reason = stopState session (Broke reason)

-- 来源正常结束：封住发布并唤醒等待者。登记结束与禁止追加在同一临界区；
-- 已发布的条目仍可领取，领取方排空后才得到 Drained。
endSession :: Session environment cause -> IO ()
endSession session = stopState session Drained

-- 第一个原因生效：已经结束或失败的会话不改写原因。
stopState :: Session environment cause -> Stopped cause -> IO ()
stopState session reason = changeState session $ \state -> case stateStopped state of
  Just _ -> Nothing
  Nothing -> Just state { stateStopped = Just reason }

-- 新状态（含保留范围）先算完，再在屏蔽区内通知并写回：两个 putMVar 的目标此时都是空的，不会阻塞，
-- 取消不能落在二者之间。否则旧状态带着已经填入的信号被恢复，下一次变化会卡在同一个信号上。
changeState :: Session environment cause
            -> (SessionState environment cause -> Maybe (SessionState environment cause)) -> IO ()
changeState session update = mask $ \restore -> do
  state <- takeMVar (sessionState session)
  settled <- restore (traverse settle (update state)) `onException` putMVar (sessionState session) state
  case settled of
    Nothing -> putMVar (sessionState session) state
    Just changed -> putMVar (stateSignal state) () >> putMVar (sessionState session) changed
  where
    settle changed = do
      fresh <- newEmptyMVar
      release changed { stateSignal = fresh }

-- 放掉没有读取义务的发布。按历史读取的读取方还在时条目全部保留；否则只留最早一个尚未领取的
-- 位置之后的积压，以及最新一条（lifelong 之外的 require 与 lifelong 的后继读它）。
-- 伴随发布只随交付领取：全部读取方都领取过的那些换成空值，与条目是否保留无关。
-- 游标由各读取方自己推进，这里读到的位置只会偏早，保留的只会偏多。
-- 新状态在写回前求值，不让旧序列挂在未求值的计算上。
release :: SessionState environment cause -> IO (SessionState environment cause)
release state = case stateReaders state of
  Nothing -> pure state
  Just readers -> do
    positions <- forM readers $ \reader -> case reader of
      Reading history position -> (,) history <$> readIORef position
      Idle -> pure (False, maxBound)
    let base = stateBase state
        total = base + Seq.length (stateEntries state)
        pending = minimum (total : map snd positions)
        kept | any fst positions = base
             | otherwise = max base (min pending (total - 1))
        cleared = max (stateCleared state) pending
        blanked = max kept (stateCleared state)
        entries = Seq.drop (kept - base) (stateEntries state)
        companions = Seq.drop (kept - base) (stateCompanions state)
        emptied
          | cleared <= blanked = companions
          | otherwise = Seq.take (blanked - kept) companions
              <> Seq.replicate (cleared - blanked) [] <> Seq.drop (cleared - kept) companions
    kept `seq` cleared `seq` entries `seq` emptied `seq` (pure $! state
      { stateBase = kept, stateEntries = entries, stateCompanions = emptied, stateCleared = cleared })

-- 状态不变，只让等待者重新检查自己的打断条件（所在单元正在结束）。
wakeSession :: Session environment cause -> IO ()
wakeSession session = changeState session Just

-- 等到状态满足条件。条件优先：结束或失败的会话仍先交出已有的结果（来源结束后的排空）；
-- 条件不满足且会话已停止时返回原因。interrupted 是等待方自己的打断条件（所在单元正在结束），
-- 只在需要等待时检查，由 wakeSession 唤醒后生效，按 Drained 返回。
-- 它只让等待退出，不决定拿到交付的位置能否启动：被新数据唤醒的等待者仍会取得交付，
-- 是否 boot 由调用方在交付到手后另行判定（Runtime.frameAdmits）。
awaitState :: Session environment cause -> IO Bool -> (SessionState environment cause -> Maybe result)
           -> IO (Either (Stopped cause) result)
awaitState session interrupted ready = do
  state <- readMVar (sessionState session)
  case (ready state, stateStopped state) of
    (Just result, _) -> pure (Right result)
    (Nothing, Just reason) -> pure (Left reason)
    (Nothing, Nothing) -> do
      -- 状态快照先于检查：之后的 wakeSession 要么填入这份快照的信号，要么发生在检查之前。
      halted <- interrupted
      if halted then pure (Left Drained)
        else readMVar (stateSignal state) >> awaitState session interrupted ready

-- lifelong 外的有限读取：至少有一条发布后取当时保留的视图，读取方只用它的最新一条；之后的发布不改写这次视图。
-- 来源结束后仍读到最后一条；一条都没有发布就结束时返回 Drained。
awaitHistory :: Session environment cause -> IO (Either (Stopped cause) (View environment cause))
awaitHistory session = awaitState session (pure False) $ \state ->
  if Seq.null (stateEntries state) then Nothing else Just (stateEntries state)

-- 消费游标属于（单元，会话）：记录已经交付的条数，每次交付推进一条。
-- 单元逐轮推进同一个游标；一轮内并发读取由 Runtime.Frame 的领取槽合并，
-- 不能绕过 Frame 并发调用同一游标的 takeDelivery。
-- Reading 带上读取方式：True 是按历史读取（该单元有 streams 订阅），False 只读交付的最新一条。
-- Idle 属于原型中不读取这个会话的单元：它不占用保留，也不能领取。
data Cursor = Reading Bool (IORef Int) | Idle

instance Eq Cursor where
  Reading _ left == Reading _ right = left == right
  Idle == Idle = True
  _ == _ = False

-- 进入 lifelong 时一次登记本会话的全部读取方，每个单元一项：Nothing 表示该单元不读取这个会话。
-- 游标从会话首条开始；登记之前的发布都还保留着。
admitReaders :: Session environment cause -> [Maybe Bool] -> IO [Cursor]
admitReaders session accesses = modifyMVar (sessionState session) $ \state -> do
  cursors <- forM accesses (maybe (pure Idle) (\history -> Reading history <$> newIORef 0))
  settled <- release state { stateReaders = Just [cursor | cursor@(Reading _ _) <- cursors] }
  pure (settled, cursors)

-- 读取方离开：它不会再领取这个会话的交付，为它保留的历史与积压可以放掉。
-- 目前在单元结束时调用（所需来源结束并排空、失败或取消）；消费方主动结束单元时走同一个入口。
-- 这里只决定保留多少数据，不停止生产：没有读取方的来源是否停止属于消费方结束的规则，尚未确定。
leaveSession :: Session environment cause -> Cursor -> IO ()
leaveSession session cursor = modifyMVar_ (sessionState session) $ \state ->
  release state { stateReaders = filter (/= cursor) <$> stateReaders state }

-- 领取下一条尚未交付的发布；视图是到这一条为止保留的条目（按历史读取时是完整历史），另带这一条的伴随发布。
-- 有积压时立即返回，没有时挂起等待；来源结束后先排空积压，游标到达末尾才返回 Drained。
-- 游标前进只表示领取，不表示处理完成。
takeDelivery :: Session environment cause -> Cursor -> IO Bool
             -> IO (Either (Stopped cause) (Delivery environment cause))
takeDelivery session Idle _ = ioError (userError ("A lifelong unit takes a delivery of " ++ snd (sessionKey session)
  ++ " without a read point in the prototype; regenerate with the SDK effect-codegen command"))
takeDelivery session (Reading _ position) interrupted = do
  delivered <- readIORef position
  outcome <- awaitState session interrupted $ \state ->
    let offset = delivered - stateBase state
    in if Seq.length (stateEntries state) > offset
      then Just (Seq.take (offset + 1) (stateEntries state), Seq.index (stateCompanions state) offset)
      else Nothing
  case outcome of
    -- 视图与伴随发布先求值，不让这次交付挂住整份会话状态；游标前进后放掉不再需要的部分。
    Right (view, companions) -> view `seq` companions `seq` do
      atomicModifyIORef' position (\current -> (current + 1, ()))
      modifyMVar_ (sessionState session) release
    Left _ -> pure ()
  pure outcome

-- 运行层启动生产任务后登记；停止时取消并等待它退出，包括其中步骤的受控收尾。
-- 任务已经自行结束时只等待它的完成信号。
setSessionWorker :: Session environment cause -> ThreadId -> MVar () -> IO ()
setSessionWorker session thread finished = void (swapMVar (sessionWorker session) (Just (thread, finished)))

stopSession :: Session environment cause -> IO ()
stopSession session = uninterruptibleMask_ $ do
  worker <- swapMVar (sessionWorker session) Nothing
  case worker of
    Nothing -> pure ()
    Just (thread, finished) -> killThread thread >> readMVar finished
