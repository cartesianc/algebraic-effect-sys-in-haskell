{-# LANGUAGE GADTs #-}
{-# LANGUAGE ScopedTypeVariables #-}

-- 执行装配：把生成的 Target lower 到 App，并为持续执行连接 DeliveryFrame 和生产步骤。
-- Target 只保存末端句柄与共享 scope；Handoff 交接捕获值；DeliveryFrame 固定一轮的交付。
-- sessionLauncher 负责生产线程，Runtime/Session 保存交付日志并停止线程，
-- Runtime/Graph 负责唯一会话登记，Workflow/Execution 负责消费单元和整次运行监督。
-- 程序只经 AST 启动，业务方法不管理这些线程、游标和交接对象。
module Framework.Runtime
  ( App, Target, targetApp
  , targetName, lowerTarget, Handoff, noHandoff, scopeHandlers, cleanupTargets
  , DeliveryFrame, LocalSource(..), newDeliveryFrame, frameDelivery, framePublishes, haltFrame, frameStopping, frameAdmits, boundarySession
  , SessionSteps, receiveSteps, deriveSteps, sessionLauncher
  ) where

import Framework.Language.Handler (Failure)
import Framework.Runtime.App (App, Launch(..), runAppWith)
import Framework.Runtime.Graph
  ( RuntimeGraph, PrototypeReference(..), runtimePrototype, runtimeScopes, runtimeRootFrame, newOrigin, obtainSession
  , currentPublications, collectRuntimeScopes )
import Framework.Runtime.Identity (Execution(..), Origin(..), executionOrigin)
import Framework.Runtime.Frame (ExecutionFrame, NodeProgress(..), captureFrameDeliveries, frameNodeProgress, frameSignal)
import Framework.Runtime.Binding (Binding(..))
import Framework.Runtime.Session
import Framework.Runtime.Scope
import Framework.Prototype
import Control.Concurrent (forkIOWithUnmask, threadDelay)
import Control.Concurrent.MVar (MVar, modifyMVar, newEmptyMVar, newMVar, putMVar, readMVar, tryReadMVar)
import Control.Exception
  (SomeAsyncException, SomeException, evaluate, finally, fromException, mask, onException, throwIO, try, uninterruptibleMask_)
import Control.Monad (forM, forM_, forever, void, when)
import Data.IORef (IORef, newIORef, readIORef, writeIORef)
import Data.List (nubBy)

-- 末端句柄与调用交接 -----------------------------------------------------------

-- 一个生成程序的 Node 共用同一存储契约。
data Target environment cause value where
  AppTarget :: (Show cause, Show value) => String -> environment -> Scopes environment cause -> App environment cause value
            -> Target environment cause value

targetName :: Target environment cause value -> String
targetName (AppTarget selected _ _ _) = selected

-- 生成区只登记句柄，不组合上游操作。
targetApp :: (Show cause, Show value) => String -> environment -> Scopes environment cause -> App environment cause value
          -> Target environment cause value
targetApp = AppTarget

-- 交给下一段调用的已捕获绑定（只含无 scope 归属的资产）与持续资产的交付视图；内容不对外公开。
-- alternative 用它把选择时读到的资产交给候选，使两段读同一份值。
data Handoff environment cause = Handoff (ScopeBindings environment cause) [(String, View environment cause)]

noHandoff :: Handoff environment cause
noHandoff = Handoff [] []

-- lifelong 单元的一次执行：本 lifelong 的各会话及该单元的游标。每个会话资产在一次执行中只领取一次，
-- 第一个需要它的调用领取，其余调用（包括同一执行内并行的节点）共享同一份固定视图与伴随发布；
-- 单元内挂接的持续 parser 将本次输出的产物发布到对应会话。
-- 本轮稳定协议 v1（2026-11-17）：gen 允许“此前发布”和“同轮必经并行发布”，不能仅凭同单元
-- 就不等待。PublishedAt 等全部发布位置退休；DerivedFrom 另等派生步骤处理完本轮上游发布。
-- 只记录从本单元 ReuseOutput 可达的来源，其他单元与 Receive 仍通过未来增量驱动本单元。
data LocalSource = PublishedAt [NodeId] | DerivedFrom String

data DeliveryFrame environment cause = DeliveryFrame
  { frameLocal :: [(String, LocalSource)]
  , frameExecution :: ExecutionFrame
  -- 稳定性查询保留本边界的会话引用；单元撤销自己的游标后，派生 worker 仍可能读取该上游。
  , frameSources :: [(String, Session environment cause)]
  , frameSessions :: [(String, (Session environment cause, Cursor))]
  , frameTaken :: MVar [(String, MVar (Either (Stopped cause) (Delivery environment cause)))]
  -- 本次执行所需的某个外部来源已结束并排空：单元正在结束，不再允许新的位置启动。
  , frameHalted :: IORef Bool
  }

newDeliveryFrame :: ExecutionFrame -> [(String, LocalSource)] -> [(String, Session environment cause)]
                 -> [(String, (Session environment cause, Cursor))] -> IO (DeliveryFrame environment cause)
newDeliveryFrame execution local sources sessions = DeliveryFrame local execution sources sessions <$> newMVar [] <*> newIORef False

-- 本单元直接或经 Derive 发布的会话：耗尽只结束订阅该来源的位置，不结束整个单元。
framePublishes :: DeliveryFrame environment cause -> String -> Bool
framePublishes frame source = source `elem` map fst (frameLocal frame)

-- 顺序是证明的一部分：先确认上游稳定，再读取发布总数和派生完成水位。
-- 查询实际轮帧，不用根帧的未来轮次预约；未知位置保守地继续等待。
frameStable :: DeliveryFrame environment cause -> String -> IO Bool
frameStable frame source = case lookup source (frameLocal frame) of
  Just (PublishedAt nodes) -> all finished <$> mapM (frameNodeProgress (frameExecution frame)) nodes
  Just (DerivedFrom upstream) -> do
    stable <- frameStable frame upstream
    if not stable then pure False else case (lookup source (frameSources frame), lookup upstream (frameSources frame)) of
      (Just session, Just parent) -> sessionCaughtUp session parent
      _ -> pure False
  Nothing -> pure False
  where
    finished (Just Completed) = True
    finished (Just Skipped) = True
    finished _ = False

-- 单元结束通知：先置位，再唤醒本 frame 各会话上的等待者重新检查。
-- 同一单元内仍在等另一个来源的并行路径由此退出等待；其他单元的等待者只是重查后继续等待。
-- 置位之后不再有位置取得启动许可（frameAdmits）。
haltFrame :: DeliveryFrame environment cause -> IO ()
haltFrame frame = do
  writeIORef (frameHalted frame) True
  mapM_ (wakeSession . fst . snd) (frameSessions frame)

frameStopping :: DeliveryFrame environment cause -> IO Bool
frameStopping = readIORef . frameHalted

-- 启动许可：“单元结束”与“启动一个位置”之间唯一的判定点，在交付到手之后、boot 之前读取一次。
-- 读到尚未结束即视作已启动，之后的结束通知不撤回它，单元等它完成；结束通知在先则不启动，
-- 即使其他来源恰好在这时发布了新交付。来源结束后的排空不经过这里：那只取决于会话里是否还有积压。
frameAdmits :: DeliveryFrame environment cause -> IO Bool
frameAdmits frame = not <$> frameStopping frame

-- 进入 lifelong 时取得本边界的会话：生产步骤从进入时的交接开始，与来源分析给会话挂载的环境一致。
boundarySession :: RuntimeGraph environment cause -> NodeId -> String -> Handoff environment cause
                -> IO (Session environment cause)
boundarySession graph boundary source (Handoff given views) = obtainSession graph (Just boundary, source) given views

-- 不是本 lifelong 的会话资产时为 Nothing。没有新发布时挂起；有积压时立即领取下一条。
-- 来源结束并排空时返回 Drained。单元正在结束时：已有交付照常取得（已经启动的调用继续用它完成），
-- 需要等待才返回 Drained。是否允许启动新的位置不在这里决定，见 frameAdmits。
-- 本单元直接/间接发布的会话等到本轮稳定；此后仍无新增量才返回 Undriven。
frameDelivery :: DeliveryFrame environment cause -> String -> Maybe (IO (Either (Stopped cause) (View environment cause)))
frameDelivery frame source = fmap (fmap fst) <$> frameTake frame source

frameTake :: DeliveryFrame environment cause -> String -> Maybe (IO (Either (Stopped cause) (Delivery environment cause)))
frameTake frame source = do
  (session, cursor) <- lookup source (frameSessions frame)
  pure $ mask $ \restore -> do
    -- 登记到装上异常收尾在同一屏蔽区，首次领取方不能留下无人填写的空槽。
    (slot, fresh) <- modifyMVar (frameTaken frame) $ \taken -> case lookup source taken of
      Just slot -> pure (taken, (slot, False))
      Nothing -> do
        slot <- newEmptyMVar
        pure ((source, slot) : taken, (slot, True))
    if not fresh then restore (readMVar slot) else do
      outcome <- try (restore (takeDeliveryOn (frameSignal (frameExecution frame)) session cursor waiting))
      -- 领取被取消时也填入结果，同一 DeliveryFrame 的其他等待方不会悬挂。
      putMVar slot (either (Left . Broke . Left) id outcome)
      either throwIO pure outcome
  where
    waiting = do
      halted <- frameStopping frame
      if halted then pure (Just Drained) else do
        stable <- frameStable frame source
        pure (if stable then Just Undriven else Nothing)

-- 方法体内第一次读取时领取（require 等不在节点订阅中的读取）。本单元发布的会话本轮没有新发布、
-- 或已封口并排空时，读已有的那一条：require 读的是当作不变的值，不要求本轮更新，也不推进游标。
-- 一条都没有发布过时为 Undriven，读取方按缺值处理。
frameRead :: DeliveryFrame environment cause -> String -> Maybe (IO (Either (Stopped cause) (View environment cause)))
frameRead frame source = do
  deliver <- frameDelivery frame source
  (session, _) <- lookup source (frameSessions frame)
  pure $ do
    outcome <- deliver
    case outcome of
      Left Undriven -> existing session
      Left Drained | framePublishes frame source -> existing session
      _ -> pure outcome
  where existing session = maybe (Left Undriven) Right <$> currentHistory session

frameDeliveries :: DeliveryFrame environment cause -> IO [(String, Delivery environment cause)]
frameDeliveries frame = do
  taken <- readMVar (frameTaken frame)
  fmap concat $ forM taken $ \(source, slot) -> do
    filled <- tryReadMVar slot
    pure [(source, delivery) | Just (Right delivery) <- [filled]]

-- Node algebra 只 lower 末端；scope 引用已绑定在句柄中。
-- 受控结果消费在撤销入口使用登记前完成，惰性读取不会落在自动 close 之后。
-- 末端共享同一次 interpreter 运行的资产 state，使 require 可读取先前 Node 产出的资产。
-- 在 lifelong 单元的 DeliveryFrame 中，已领取的交付优先于交接视图，尚未领取的会话资产在第一次读取时领取。
-- 已领取交付的伴随发布作为已捕获绑定交给本次调用，交接中已经捕获的值优先（与来源分析一致）；
-- 生成期保证读取伴随资产的位置在调用前已经领取了对应会话的交付。
-- 原始链挂接只交付持续资产自身；普通产物保持其 AST Origin 的既有来源可见性，不随流跨链透传。
lowerTarget :: RuntimeGraph environment cause -> NodeId -> ExecutionFrame -> Maybe (DeliveryFrame environment cause) -> Handoff environment cause
            -> Target environment cause value -> IO (Either (Failure cause) value, Handoff environment cause)
lowerTarget graph location executionFrame frame (Handoff given views) target = do
  taken <- maybe (pure []) frameDeliveries frame
  let merged = [(source, view) | (source, (view, _)) <- taken]
        ++ [entry | entry@(source, _) <- views, source `notElem` map fst taken]
      companions = [entry | (_, (_, published)) <- taken, entry@(source, _) <- published, source `notElem` map fst given]
      sinks = [(source, appendDelivery session []) | Just current <- [frame], (source, (session, _)) <- frameSessions current]
      launch = Launch
        { launchBindings = given ++ companions, launchViews = merged, launchInput = Nothing
        , launchSinks = sinks, launchDeliver = \source -> frame >>= (`frameRead` source)
        , launchUser = Nothing, launchFrame = executionFrame }
  captureFrameDeliveries executionFrame
    [(originNode (executionOrigin (bindingOrigin value)), source, production)
      | (source, value) <- companions, Just production <- [bindingProduction value]
      , source `notElem` [resource | family <- runtimeScopes graph, Just resource <- [scopeContextSource family]]]
  (outcome, captured, delivered) <- lowerWith graph location launch target
  pure (outcome, Handoff captured delivered)

lowerWith :: RuntimeGraph environment cause -> NodeId -> Launch environment cause -> Target environment cause value
          -> IO (Either (Failure cause) value, ScopeBindings environment cause, [(String, View environment cause)])
lowerWith graph location launch (AppTarget _ environment _ action) =
  runAppWith (\value -> evaluate (foldr seq () (show value))) graph location launch environment action

-- 各末端通常捕获同批 scope；按控制对象身份去重，不按业务名称合并独立批次。
scopeHandlers :: [Target environment cause value] -> Scopes environment cause
scopeHandlers entries = nubBy sameHandler (concatMap targetScopes entries)
  where
    targetScopes :: Target environment cause value -> Scopes environment cause
    targetScopes (AppTarget _ _ scopes _) = scopes
    sameHandler left right = scopeInstances left == scopeInstances right

cleanupTargets :: [Target environment cause value] -> IO [(Maybe SomeException, Failure cause)]
cleanupTargets = cleanupScopes . scopeHandlers

-- 持续生产的装配与退出 ---------------------------------------------------------

-- 生成区按资产登记的生产步骤。parser 的入口发布一次资产；会话不再次发布返回值。
-- ReceiveSteps：Stream 单步取得原始输入，再由 parser 解析。
-- DeriveSteps：领取一条上游持续资产的交付后执行 parser，它沿 Input 链执行被驱动的句柄。
data SessionSteps environment cause
  = ReceiveSteps (Target environment cause String) (Target environment cause ())
  | DeriveSteps (Target environment cause ())

receiveSteps :: Target environment cause String -> Target environment cause () -> SessionSteps environment cause
receiveSteps = ReceiveSteps

deriveSteps :: Target environment cause () -> SessionSteps environment cause
deriveSteps = DeriveSteps

-- 为新会话启动生产任务：按原型找到该边界的会话挂载，逐次执行生产步骤，把发布写入会话历史。
-- 每条交付带上本次生产步骤（各挂载当前一次执行）已经发布的普通资产，作为伴随发布。
-- 各步骤共用会话的 scope 使用登记，生产资源跨步骤保持；会话停止时撤销登记，根帧退休后统一回收。
-- 生产失败（已经过 Error 协议诊断）或原生异常使会话失败并停止，并通知运行监督；
-- Stream handler 的 streamEnd 正常结束会话：封住发布、唤醒等待者，不通知监督，已发布的交付仍可领取；
-- 由上游驱动的会话在上游结束并排空、或被驱动链上的 Excu 调用 endStream 时同样正常结束，
-- 并离开上游（上游的读取方计数减一）；上游失败时以同一个原因失败；
-- 取消只结束任务，步骤内照常收尾。
-- lifelong 的会话另外安装退役动作：读取方全部离开（引用计数归零）时停止任务、封住发布，
-- 撤销会话的使用登记后回收只在会话挂载中开启的 scope；派生会话退役后，上游若也没有读取方，随之退役。
-- 启动到登记在不可中断区内完成，取消不会落在任务已启动、尚未登记之间。任务继承这一屏蔽，只在生产时解除：
-- 报告失败、撤销使用登记和填写完成信号都不会被停止请求打断，stopSession 一定等得到完成信号。
sessionLauncher :: RuntimeGraph environment cause -> [(String, SessionSteps environment cause)]
                -> (Broken cause -> IO ()) -> Session environment cause -> IO ()
sessionLauncher graph steps onBroken session
  -- 已挂载的原始链提供输出：只登记会话的交付状态，不创建第二个驱动或资源使用者。
  | Just (ReuseOutput _) <- sessionPlan <$> description = pure ()
  | otherwise = launch
  where
    launch = uninterruptibleMask_ $ do
      finished <- newEmptyMVar
      owner <- case mounts of
        Just (mount : _) -> newOrigin graph mount >>= newScopeUser (runtimeScopes graph) . BusinessExecution
        _ -> ioError (userError ("No session steps for " ++ source ++ " at " ++ show boundary
          ++ "; regenerate with the SDK effect-codegen command"))
      thread <- forkIOWithUnmask $ \unmask -> (`finally` putMVar finished ()) $ (`finally` detachScopeUser owner) $ do
        outcome <- try (unmask (produce owner))
        case outcome of
          Left (exception :: SomeException)
            | Just (_ :: SomeAsyncException) <- fromException exception -> pure ()
            | otherwise -> broken (Left exception)
          Right (Just problem) -> broken (Right problem)
          -- 正常结束后任务留在原地，直到会话退役（读取方全部离开、lifelong 返回）或运行结束：
          -- 排空期间仍有读取方，会话的使用登记继续持有生产资源；生产停止且计数归零才撤销。
          Right Nothing -> do
            endSession session
            void (try (unmask (forever (threadDelay 3600000000))) :: IO (Either SomeException ()))
      setSessionWorker session thread finished
      -- interpreter 托管的会话没有读取方登记，不按计数退役，仍由运行结束统一停止。
      forM_ boundary $ \_ -> setSessionRetirement session retire
    -- 先停任务再封口：停止等待任务撤销使用登记，此后回收才看得到这些实例已经没有使用者。
    -- 回收仍按可达性判定，后继还会以同样参数开启的实例保留。
    retire = do
      stopSession session
      endSession session
      collectRuntimeScopes graph (maybe [] id mounts)
      upstream <- upstreamOf session
      forM_ upstream $ \selected -> do
        idle <- sessionIdle selected
        when idle (retireSession selected)
    (boundary, source) = sessionKey session
    description = sessionDescriptionOf (runtimePrototype graph) boundary source
    mounts = sessionMounts <$> description
    produce owner = case (lookup source steps, mounts) of
      (Just (ReceiveSteps stream parser), Just [streamMount, parserMount]) -> loop $ do
        -- streamEnd 只来自 Stream 单步：这一步没有原始输入，parser 不执行，也不发布。
        taken <- try (lowerWith graph streamMount (step owner Nothing []) stream)
        case taken of
          Left SourceEnded -> pure (Just Nothing)
          Right (Left problem, _, _) -> pure (Just (Just problem))
          Right (Right text, _, _) ->
            either (Just . Just) (const Nothing) . first <$> lowerWith graph parserMount (step owner (Just text) sink) parser
      -- 每一步先领取一条上游交付，把到这一条为止的历史作为本步的视图；上游结束并排空即正常结束。
      -- 被驱动链上的 Excu 调用 endStream：这一步放弃，不发布，派生会话不再消费上游，同样正常结束。
      -- 正常退出时离开上游，计数归零则退役上游；失败或取消只离开，停止交给收尾或本会话的退役。
      (Just (DeriveSteps parser), Just [mount]) -> mask $ \restore -> do
        (upstream, cursor) <- awaitUpstream session
        -- 游标的撤销覆盖整个生产/退役过程，取消不能落在正常结束与离开上游之间。
        restore (do
          outcome <- loop $ do
            taken <- takeDelivery upstream cursor (pure Nothing)
            case taken of
              Left Drained -> pure (Just Nothing)
              Left Undriven -> pure (Just Nothing)
              Left (Broke (Right problem)) -> pure (Just (Just problem))
              Left (Broke (Left exception)) -> throwIO exception
              Right (view, _) -> do
                stepped <- try (lowerWith graph mount (driven owner (snd (sessionKey upstream)) view) parser)
                case stepped of
                  Left SubscriptionEnded -> pure (Just Nothing)
                  Right result -> case first result of
                    Left problem -> pure (Just (Just problem))
                    Right () -> completeSessionStep session >> pure Nothing
          -- 正常结束先封口，后退役上游：下游可以排空，不用等上游业务 close 才获知结束。
          -- 失败只离开，先由生产任务报告监督；不推进完成水位，不把失败短暂伪装成本轮稳定。
          case outcome of
            Nothing -> endSession session >> departSession upstream cursor
            Just _ -> void (leaveSession upstream cursor)
          pure outcome) `onException` leaveSession upstream cursor
      _ -> ioError (userError ("Session steps differ from the prototype mounts for " ++ source
        ++ "; regenerate with the SDK effect-codegen command"))
    sink = [(source, \value -> do
      companions <- currentPublications graph (maybe [] id mounts)
      appendDelivery session companions value)]
    -- 每一步从边界交接的新副本开始，共用会话的使用登记。
    step owner input sinks = Launch
      { launchBindings = sessionBindings session, launchViews = sessionViews session, launchInput = input
      , launchSinks = sinks, launchDeliver = noDelivery, launchUser = Just owner
      , launchFrame = runtimeRootFrame graph }
    -- 被驱动的一步：上游这条交付的视图盖过交接中同一来源的视图。
    driven owner upstream view = (step owner Nothing sink)
      { launchViews = (upstream, view) : filter ((/= upstream) . fst) (sessionViews session) }
    noDelivery = const Nothing
    first (outcome, _, _) = outcome
    broken reason = breakSession session reason >> onBroken reason
    -- 逐次执行直到来源结束（Nothing）或第一次失败（Just problem）；结果交回不可中断区登记。
    loop step = step >>= maybe (loop step) pure

-- 会话计划与挂载只来自同一份原型；复用原始链输出的会话没有独立生产挂载。
sessionDescriptionOf :: PrototypeReference -> Maybe NodeId -> String -> Maybe SessionProto
sessionDescriptionOf (PrototypeReference prototype) boundary source =
  case [session | session <- candidates
       , Just (sessionAsset session) == lookup source produced] of
    [description] -> Just description
    _ -> Nothing
  where
    produced = [(effectName effect, contractType) | effect <- protoEffects prototype
      , Just contractType <- [effectProduces effect]]
    candidates = case boundary of
      Nothing -> protoSessions prototype
      Just lifelong -> [session | (identifier, described) <- workflowLifelongs (protoWorkflow prototype)
        , identifier == lifelong, session <- lifelongSessions described]
