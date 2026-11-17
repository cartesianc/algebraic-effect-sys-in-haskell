-- 生产会话的交付队列、广播通知、消费游标及停止句柄。
-- 只保留尚未领取的积压和最新一条；值的内部结构由业务资产定义，SDK 不累计业务历史。
-- Runtime 启动并登记生产线程；本模块不执行生产方法，只保存交付并取消／等待该线程。
-- Runtime/Graph 控制会话的唯一登记和整体停止；Workflow/Execution 持有各单元游标。
-- 会话按（lifelong 边界，生产该资产的 Context 注册名）区分；注册名与运行时绑定来源同名。
-- Nothing 边界是 interpreter 托管的会话。
module Framework.Runtime.Session
  ( SessionKey, View, Delivery, Broken, Stopped(..), SourceEnded(..), SubscriptionEnded(..), DeliveryDrained(..)
  , Session, sessionKey, sessionBindings, sessionViews
  , newSession, appendDelivery, breakSession, endSession, wakeSession, setSessionWorker, stopSession
  , setSessionRetirement, retireSession, departSession, sessionIdle
  , awaitView, currentView, pendingDelivery, Cursor, admitReaders, attachReader, leaveSession, takeDelivery, takeDeliveryOn, completeSessionStep, sessionCaughtUp, feedSession, awaitUpstream, upstreamOf
  ) where

import Control.Concurrent (ThreadId, killThread)
import Control.Concurrent.MVar
  (MVar, newEmptyMVar, newMVar, modifyMVar, modifyMVar_, putMVar, readMVar, takeMVar, tryPutMVar, tryReadMVar)
import Control.Exception (Exception, SomeException, finally, mask, onException, uninterruptibleMask_)
import Control.Monad (forM, void, when)
import Data.IORef (IORef, atomicModifyIORef', newIORef, readIORef)
import Data.Maybe (isJust)
import Data.Sequence (Seq, (|>))
import qualified Data.Sequence as Seq
import Framework.Language.Handler (Failure)
import Framework.Runtime.Scope (ScopeBinding, ScopeBindings)
import Framework.Prototype (NodeId)

type SessionKey = (Maybe NodeId, String)

-- 固定交付视图，只含本次选中的 Binding；容器用于已有捕获与交接协议，不表示业务序列。
-- 绑定保留自己的生产身份、执行帧和共享归属。
type View environment cause = Seq (ScopeBinding environment cause)

-- 一次交付：本次 Binding，以及产生这一条的生产步骤的其他普通发布（伴随发布）。
-- lifelong 单元读取以会话生产步骤为来源的普通资产时，读的是所处理交付的伴随发布，与交付同出一步。
type Delivery environment cause = (View environment cause, ScopeBindings environment cause)

-- 生产失败（Error 协议诊断后的 Failure）或生产任务的原生异常；会话不再产出。
type Broken cause = Either SomeException (Failure cause)

-- 领取不到交付的原因。Drained：来源已正常结束，且已发布的交付都已领取（或所在单元正在结束）；
-- 这是正常终止，不是失败。Broke：会话失败。
-- Undriven：本轮发布位置及其派生处理已稳定，没有未领取的发布；不是暂时缺值。
data Stopped cause = Drained | Broke (Broken cause) | Undriven

-- SDK 内部的正常结束信号，以异常形式越过方法体；不是业务 Failure，不进入 Error 协议，
-- 也不被方法体内的 catchError 接住。
-- SourceEnded：Stream handler 调用 streamEnd，由生产任务接住并结束会话。
data SourceEnded = SourceEnded
instance Show SourceEnded where show _ = "SDK stream source ended"
instance Exception SourceEnded

-- SubscriptionEnded：消费方 handler 调用 endStream。lifelong 节点由单元调度接住，记为该节点的订阅结束；
-- Derive 会话的被驱动链由生产任务接住，派生会话不再消费上游并结束自己的发布。
data SubscriptionEnded = SubscriptionEnded
instance Show SubscriptionEnded where show _ = "SDK stream subscription ended"
instance Exception SubscriptionEnded

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
  -- Derive 已完整处理的上游交付数。领取游标在业务执行前推进，不能充当完成水位。
  , stateProcessed :: !Int
  -- 会话不再接受新发布：来源正常结束（Drained）或失败（Broke）。已有条目保留。
  , stateStopped :: Maybe (Stopped cause)
  -- 下一次变化时填入；等待方读到后重新取状态。每次变化换上新的空信号。
  , stateSignal :: MVar ()
  -- 仍可能领取交付的游标。Nothing：读取方尚未登记（lifelong 的会话在进入边界时启动，
  -- 各单元随后登记），此前的发布全部保留。interpreter 托管的会话没有游标，从创建起就是空表。
  , stateReaders :: Maybe [Cursor]
  }

-- 生产任务的停止状态，与 stateStopped 的“发布已结束”分开。
-- 首次 stop 取走取消权，但保留同一完成信号；并发 stop 也必须等到任务撤销使用登记。
-- StoppingWorker 的信号填满后仍保留，重复 stop 只读该信号，不重复取消或持有旧 ThreadId。
data SessionWorker
  = NoWorker
  | RunningWorker ThreadId (MVar ())
  | StoppingWorker (MVar ())

-- 读取方全部离开后的退役：停止生产任务、封住发布、回收只在会话中开启的 scope。
-- 动作由 Runtime 在启动生产任务时安装；没有独立生产任务的会话（ReuseOutput、interpreter 托管）不安装，
-- 退役是空操作。成功完成后不再执行；并发调用等待当前尝试，未完成的尝试可以接续重试。
data Retirement = Unretired (IO ()) | Retiring (MVar ()) | Retired

-- 边界的交接：进入 lifelong 时已经捕获的绑定与视图（例如外层 alternative 选择时读到的值）。
-- 每个生产步骤都从这份交接开始；interpreter 托管的会话没有交接。
data Session environment cause = Session
  { sessionKey :: SessionKey
  , sessionBindings :: ScopeBindings environment cause
  , sessionViews :: [(String, View environment cause)]
  , sessionState :: MVar (SessionState environment cause)
  , sessionWorker :: MVar SessionWorker
  -- 由另一份持续资产驱动的会话：上游会话，以及本会话在其中的游标。上游在进入 lifelong 时登记读取方，
  -- 或在有限需求首次装配时登记；生产任务取得它之前不执行。由 Stream 驱动的会话不使用。
  , sessionUpstream :: MVar (Session environment cause, Cursor)
  , sessionRetirement :: MVar Retirement
  -- 同一次运行的执行帧通知：发布、派生完成与节点退休共用它，局部等待不会丢失进度变化。
  , sessionNotify :: IO ()
  }

newSession :: IO () -> SessionKey -> ScopeBindings environment cause -> [(String, View environment cause)]
           -> IO (Session environment cause)
newSession notify key bindings views = do
  signal <- newEmptyMVar
  let readers = maybe (Just []) (const Nothing) (fst key)
  Session key bindings views <$> newMVar (SessionState 0 Seq.empty Seq.empty 0 0 Nothing signal readers) <*> newMVar NoWorker
    <*> newEmptyMVar <*> newMVar (Unretired (pure ())) <*> pure notify

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
    Just changed -> do
      putMVar (stateSignal state) ()
      putMVar (sessionState session) changed
      sessionNotify session
  where
    settle changed = do
      fresh <- newEmptyMVar
      release changed { stateSignal = fresh }

-- 放掉没有读取义务的发布：只留最早未领取位置之后的积压，以及最新一条。
-- 最新一条供有限读取与后继读取；保存全部业务历史的节点应自己生产相应资产。
-- 伴随发布只随交付领取：全部读取方都领取过的那些换成空值，与条目是否保留无关。
-- 游标由各读取方自己推进，这里读到的位置只会偏早，保留的只会偏多。
-- 新状态在写回前求值，不让旧序列挂在未求值的计算上。
release :: SessionState environment cause -> IO (SessionState environment cause)
release state = case stateReaders state of
  Nothing -> pure state
  Just readers -> do
    positions <- forM readers $ \reader -> case reader of
      Reading position -> readIORef position
      Idle -> pure maxBound
    let base = stateBase state
        total = base + Seq.length (stateEntries state)
        pending = minimum (total : positions)
        kept = max base (min pending (total - 1))
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

-- 等待协议 v2（2026-11-17）：先取得变化信号，再检查发布和停止条件。局部交付使用执行帧
-- 的共享信号，同时观察节点退休与派生完成；普通会话读取仍只等自己的状态变化。
-- 稳定判据可能晚于第一次状态快照，返回 Undriven 前必须重读：判据已经看到的发布不能被跳过。
-- 交付优先于终态，终态优先于等待方的退出原因；启动许可仍由 Runtime.frameAdmits 判定。
awaitState :: Session environment cause -> IO (Maybe (Stopped cause)) -> (SessionState environment cause -> Maybe result)
           -> IO (Either (Stopped cause) result)
awaitState session = awaitStateOn (stateSignal <$> readMVar (sessionState session)) session

awaitStateOn :: IO (MVar ()) -> Session environment cause -> IO (Maybe (Stopped cause))
             -> (SessionState environment cause -> Maybe result) -> IO (Either (Stopped cause) result)
awaitStateOn signal session interrupted ready = do
  changed <- signal
  state <- readMVar (sessionState session)
  case select state of
    Just outcome -> pure outcome
    Nothing -> do
      halted <- interrupted
      case halted of
        Just reason -> do
          latest <- readMVar (sessionState session)
          pure (maybe (Left reason) id (select latest))
        Nothing -> readMVar changed >> awaitStateOn signal session interrupted ready
  where
    select state = case (ready state, stateStopped state) of
      (Just result, _) -> Just (Right result)
      (Nothing, Just reason) -> Just (Left reason)
      (Nothing, Nothing) -> Nothing

-- 仅在 Derive 一步成功返回后推进；失败和 endStream 走封口/失败协议，不提前宣告处理完成。
completeSessionStep :: Session environment cause -> IO ()
completeSessionStep session = changeState session $ \state ->
  Just state { stateProcessed = stateProcessed state + 1 }

-- 调用方先证明上游本轮稳定，再读取上游累计发布数，最后比较本会话的完成水位。
-- stateBase + 长度不受队列裁剪影响；不能把“已领取”误作“解析和发布已经完成”。
sessionCaughtUp :: Session environment cause -> Session environment cause -> IO Bool
sessionCaughtUp session upstream = do
  total <- (\state -> stateBase state + Seq.length (stateEntries state)) <$> readMVar (sessionState upstream)
  (\state -> stateProcessed state >= total) <$> readMVar (sessionState session)

-- lifelong 外的有限读取：至少有一条发布后取最新 Binding；之后的发布不改写本次视图。
-- 来源结束后仍读到最后一条；一条都没有发布就结束时返回 Drained。
awaitView :: Session environment cause -> IO (Either (Stopped cause) (View environment cause))
awaitView session = awaitState session (pure Nothing) $ \state ->
  latestView (stateEntries state)

-- 不等待地取当前保留的视图：一条都没有发布时为 Nothing。本单元发布的会话本轮没有新发布时，
-- 只读最新一条的读取（require）用它读已有的一条，不推进游标。
currentView :: Session environment cause -> IO (Maybe (View environment cause))
currentView session = (\state -> latestView (stateEntries state))
  <$> readMVar (sessionState session)

-- 固定最后一个绑定，不让一次有限读取持有整条交付队列。
latestView :: Seq value -> Maybe (Seq value)
latestView entries = case Seq.viewr entries of
  Seq.EmptyR -> Nothing
  _ Seq.:> value -> Just (Seq.singleton value)

-- 消费游标属于（单元，会话）：记录已经交付的条数，每次交付推进一条。
-- 单元逐轮推进同一个游标；一轮内并发读取由 Runtime.Frame 的领取槽合并，
-- 不能绕过 Frame 并发调用同一游标的 takeDelivery。
-- Idle 属于原型中不读取这个会话的单元：它不占用保留，也不能领取。
data Cursor = Reading (IORef Int) | Idle

instance Eq Cursor where
  Reading left == Reading right = left == right
  Idle == Idle = True
  _ == _ = False

-- 待用查询 v1（2026-11-17）：只看游标下一条，不推进游标、不等待新发布。
-- scope 回收使用同一读取位置；不能以会话全局最新值覆盖尚未领取的积压。
pendingDelivery :: Session environment cause -> Cursor -> IO (Maybe (ScopeBinding environment cause))
pendingDelivery _ Idle = pure Nothing
pendingDelivery session (Reading position) = do
  delivered <- readIORef position
  state <- readMVar (sessionState session)
  pure (Seq.lookup (delivered - stateBase state) (stateEntries state))

-- 进入 lifelong 时一次登记本会话的全部读取方，每个单元一项：False 表示不读取。
-- 游标从会话首条开始；登记之前的发布都还保留着。
admitReaders :: Session environment cause -> [Bool] -> IO [Cursor]
admitReaders session accesses = modifyMVar (sessionState session) $ \state -> do
  cursors <- forM accesses (\reads -> if reads then Reading <$> newIORef 0 else pure Idle)
  settled <- release state { stateReaders = Just [cursor | cursor@(Reading _) <- cursors] }
  pure (settled, cursors)

-- 有限需求首次建立一个派生关系：原来源若已发布，先交付登记瞬间的最新值，随后逐条推进。
-- 起点和登记在同一状态锁下；不重放已释放发布，也不把积压误当作新读取方的历史。
-- 新来源尚未发布时从第 0 条开始。lifelong 的统一登记仍使用 admitReaders。
attachReader :: Session environment cause -> IO Cursor
attachReader session = modifyMVar (sessionState session) $ \state -> do
  let position = stateBase state + max 0 (Seq.length (stateEntries state) - 1)
  cursor <- Reading <$> newIORef position
  settled <- release state { stateReaders = Just (cursor : maybe [] id (stateReaders state)) }
  pure (settled, cursor)

-- 读取方离开：它不会再领取这个会话的交付，为它保留的积压可以放掉。
-- 单元不再有读取这个会话的活节点、单元结束、Derive 会话不再消费上游时调用；重复离开不改变状态。
-- 返回 True 表示这次离开使已登记的读取方从有到无（引用计数归零）：调用方据此在锁外退役会话。
-- 失败或取消路径只离开、不退役，停止交给 lifelong 返回或运行结束的既有收尾。
leaveSession :: Session environment cause -> Cursor -> IO Bool
leaveSession session cursor = modifyMVar (sessionState session) $ \state -> do
  let before = stateReaders state
      after = filter (/= cursor) <$> before
  settled <- release state { stateReaders = after }
  pure (settled, fmap null before == Just False && fmap null after == Just True)

-- 正常路径上的离开：计数归零时退役会话。退役等待生产任务收尾，不能在会话状态锁内调用。
departSession :: Session environment cause -> Cursor -> IO ()
departSession session cursor = do
  idle <- leaveSession session cursor
  when idle (retireSession session)

-- lifelong 的已登记读取方全部离开。interpreter 托管会话也可登记派生游标，但不按计数退役。
sessionIdle :: Session environment cause -> IO Bool
sessionIdle session = (\state -> fmap null (stateReaders state) == Just True && isJust (fst (sessionKey session)))
  <$> readMVar (sessionState session)

setSessionRetirement :: Session environment cause -> IO () -> IO ()
setSessionRetirement session action = modifyMVar_ (sessionRetirement session) $ \retirement -> case retirement of
  Unretired _ -> pure (Unretired action)
  _ -> pure retirement

-- 只有成功跑完退役才标记 Retired；取消或异常恢复待退役状态，等待方醒来后重新争取执行权。
-- 取得执行权到装上收尾在同一屏蔽区内；状态提交与唤醒不可中断，不把“尝试退出”当成“退役完成”。
-- 退役动作可接续重试：stop/end 幂等，scope 回收在每次 close 尝试后消费登记，不重试该 close。
retireSession :: Session environment cause -> IO ()
retireSession session = mask $ \restore -> do
  selected <- modifyMVar (sessionRetirement session) $ \retirement -> case retirement of
    Unretired action -> do
      done <- newEmptyMVar
      pure (Retiring done, Just (Just action, done))
    Retiring done -> pure (retirement, Just (Nothing, done))
    Retired -> pure (Retired, Nothing)
  case selected of
    Nothing -> pure ()
    Just (Just retire, done) -> do
      restore retire `onException` complete (Unretired retire) done
      complete Retired done
    Just (Nothing, done) -> restore (readMVar done >> retireSession session)
  where
    complete retirement done = uninterruptibleMask_ $ do
      modifyMVar_ (sessionRetirement session) (const (pure retirement))
      void (tryPutMVar done ())

-- 领取下一条尚未交付的发布，固定为这一条 Binding，并带上同一次生产的伴随发布。
-- 有积压时立即返回，没有时挂起等待（interrupted 给出原因时不等待，返回该原因）；
-- 来源结束后先排空积压，游标到达末尾才返回 Drained。游标前进只表示领取，不表示处理完成。
takeDelivery :: Session environment cause -> Cursor -> IO (Maybe (Stopped cause))
             -> IO (Either (Stopped cause) (Delivery environment cause))
takeDelivery session = takeDeliveryOn (stateSignal <$> readMVar (sessionState session)) session

-- DeliveryFrame 用同一执行帧的通知同时等待发布、派生步骤完成和本轮节点退休。
takeDeliveryOn :: IO (MVar ()) -> Session environment cause -> Cursor -> IO (Maybe (Stopped cause))
               -> IO (Either (Stopped cause) (Delivery environment cause))
takeDeliveryOn _ session Idle _ = ioError (userError ("A lifelong unit takes a delivery of " ++ snd (sessionKey session)
  ++ " without a read point in the prototype; regenerate with the SDK effect-codegen command"))
takeDeliveryOn signal session (Reading position) interrupted = do
  delivered <- readIORef position
  outcome <- awaitStateOn signal session interrupted $ \state ->
    let offset = delivered - stateBase state
    in if Seq.length (stateEntries state) > offset
      then Just (Seq.singleton (Seq.index (stateEntries state) offset), Seq.index (stateCompanions state) offset)
      else Nothing
  case outcome of
    -- 视图与伴随发布先求值，不让这次交付挂住整份会话状态；游标前进后放掉不再需要的部分。
    Right (view, companions) -> view `seq` companions `seq` do
      atomicModifyIORef' position (\current -> (current + 1, ()))
      modifyMVar_ (sessionState session) release
    Left _ -> pure ()
  pure outcome

-- 把上游会话和已经登记的游标交给由它驱动的会话；只交一次。
feedSession :: Session environment cause -> Session environment cause -> Cursor -> IO ()
feedSession session upstream cursor = void (tryPutMVar (sessionUpstream session) (upstream, cursor))

-- 由上游驱动的生产任务在第一步之前等待交接。
awaitUpstream :: Session environment cause -> IO (Session environment cause, Cursor)
awaitUpstream = readMVar . sessionUpstream

-- 退役时查看上游：尚未交接（Stream 驱动或还没进入 lifelong）时为 Nothing。
upstreamOf :: Session environment cause -> IO (Maybe (Session environment cause))
upstreamOf session = fmap fst <$> tryReadMVar (sessionUpstream session)

-- Graph 在会话登记锁与不可中断区内启动并登记任务，再把 Session 交给使用方。
-- 一个会话只登记一次；ReuseOutput 不登记 worker。finished 由 Runtime 在撤销 ScopeUser 后填满。
setSessionWorker :: Session environment cause -> ThreadId -> MVar () -> IO ()
setSessionWorker session thread finished = modifyMVar_ (sessionWorker session) $ \worker -> case worker of
  NoWorker -> pure (RunningWorker thread finished)
  _ -> ioError (userError ("Session worker already registered for " ++ show (sessionKey session)))

-- 收尾协议 v1（2026-11-16）：所有调用都等待同一次完成，只有第一个调用负责发送取消。
-- 不能先清空目录再等待，否则并发 stop 会把“已有人负责停止”误认成“已经收尾”。
-- 目录锁内只转移取消权；发送取消与等待都在锁外，不持有发布状态锁或 scope 协调锁。
-- 屏蔽沿用现有停止契约，避免拿到取消权的调用方中断后，其余等待方永远收不到完成信号。
stopSession :: Session environment cause -> IO ()
stopSession session = uninterruptibleMask_ $ do
  finish <- modifyMVar (sessionWorker session) $ \worker -> case worker of
    NoWorker -> pure (NoWorker, pure ())
    RunningWorker thread finished ->
      pure (StoppingWorker finished, killThread thread >> readMVar finished)
    StoppingWorker finished -> pure (worker, readMVar finished)
  finish
