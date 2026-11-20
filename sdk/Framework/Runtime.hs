{-# LANGUAGE GADTs #-}
{-# LANGUAGE ScopedTypeVariables #-}

-- 执行装配：把生成的 Target lower 到 App，并为持续执行连接 DeliveryFrame 和生产步骤。
-- Target 只保存末端句柄与共享 scope；Handoff 交接捕获值；DeliveryFrame 固定一轮的交付。
-- sessionLauncher 负责生产线程，Runtime/Session 保存待领取交付并停止线程，
-- Runtime/Graph 负责唯一会话登记，Runtime/Execution 负责消费单元和整次运行监督。
-- 程序只经 AST 启动，业务方法不管理这些线程、游标和交接对象。
module Framework.Runtime
  ( App, Target, targetApp
  , targetName, lowerTarget, Handoff, noHandoff, scopeHandlers, cleanupTargets
  , DeliveryFrame, LocalSource(..), newDeliveryFrame, frameDelivery, framePublishes, haltFrame, frameStopping, frameAdmits, boundarySession
  , SessionSteps, receiveSteps, deriveSteps, sessionLauncher
  ) where

import Framework.Language.Handler (Failure)
import Framework.Runtime.App (App, Launch(..), StreamPort(..), runAppWith)
import Framework.Runtime.Graph
  ( RuntimeGraph, PrototypeReference(..), runtimePrototype, runtimeScopes, runtimeRootFrame, newOrigin, obtainSession
  , currentPublications, collectRuntimeScopes, withRuntimeRetention )
import Framework.Runtime.Identity (ActivationId, Execution(..), Origin(..), executionOrigin)
import Framework.Runtime.Frame (ExecutionFrame, NodeProgress(..), captureFrameDeliveries, frameNodeProgress, frameSignal, installSessionInputs
  , newSessionFrame, finishExecutionFrame, withFrameLock)
import Framework.Runtime.Binding (Binding(..), readBindingOwner)
import Framework.Runtime.Retention (Retention, keepBindings)
import Framework.Runtime.Session
import Framework.Runtime.Scope
import Framework.Prototype
import Control.Concurrent (forkIOWithUnmask, threadDelay)
import Control.Concurrent.MVar (MVar, modifyMVar, newEmptyMVar, newMVar, putMVar, readMVar, tryReadMVar)
import Control.Exception
  (SomeAsyncException, SomeException, evaluate, finally, fromException, mask, onException, throwIO, try, uninterruptibleMask_)
import Control.Monad (filterM, forM, forM_, forever, void, when)
import Data.IORef (IORef, newIORef, readIORef, writeIORef)
import Data.List (nubBy)
import Data.Maybe (isJust, isNothing, mapMaybe)

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

data DeliveryFrame environment cause = DeliveryFrame
  { frameLocal :: [(String, LocalSource)]
  , frameExecution :: ExecutionFrame
  , frameRetention :: Retention environment cause
  -- 稳定性查询保留本边界的会话引用；单元撤销自己的游标后，派生 worker 仍可能读取该上游。
  , frameSources :: [(String, Session environment cause)]
  , frameSessions :: [(String, (Session environment cause, Cursor))]
  , frameTaken :: MVar [(String, MVar (Either (Stopped cause) (Delivery environment cause)))]
  -- 本次执行所需的某个外部来源已结束并排空：单元正在结束，不再允许新的位置启动。
  , frameHalted :: IORef Bool
  }

newDeliveryFrame :: Retention environment cause -> ExecutionFrame -> [(String, LocalSource)] -> [(String, Session environment cause)]
                 -> [(String, (Session environment cause, Cursor))] -> IO (DeliveryFrame environment cause)
newDeliveryFrame retention execution local sources sessions = do
  frame <- DeliveryFrame local execution retention sources sessions <$> newMVar [] <*> newIORef False
  installSessionInputs execution (pendingInput frame)
  pure frame

-- 本轮已领取时比较固定视图；尚未领取时查看自己的游标，不看别的单元的进度。
-- 领取进行中（槽尚空）保守持有，覆盖游标已推进、交付尚未填槽的交接窗口。
-- 两把被读取的锁中都不运行 handler，也不获取 scope 协调锁。
pendingInput :: DeliveryFrame environment cause -> String -> ActivationId -> IO (Maybe Bool)
pendingInput frame source production = case lookup source (frameSessions frame) of
  Nothing -> pure Nothing
  Just (session, cursor) -> do
    taken <- readMVar (frameTaken frame)
    case lookup source taken of
      Just slot -> do
        filled <- tryReadMVar slot
        case filled of
          Nothing -> pure (Just True)
          Just (Right (view, _)) -> pure (Just (matchesView view))
          Just (Left _) -> fallback session
      Nothing -> do
        next <- pendingDelivery session cursor
        -- 预览期间可能刚登记了首次领取；它随后才推进游标。重新检查槽，
        -- 避免把“游标已经前进”误解成旧交付已无人使用。
        now <- readMVar (frameTaken frame)
        case lookup source now of
          Just _ -> pendingInput frame source production
          Nothing -> case next of
            Just value -> pure (Just (bindingProduction value == Just production))
            Nothing -> fallback session
  where
    matchesView view = (lastBinding view >>= bindingProduction) == Just production
    fallback session
      | framePublishes frame source = Just . maybe False matchesView <$> currentView session
      | otherwise = pure (Just False)

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
      outcome <- try (restore (takeDeliveryOn (frameSignal (frameExecution frame)) session cursor (frameRetention frame) waiting))
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
  where existing session = maybe (Left Undriven) Right <$> retainedView session (frameRetention frame)

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
-- 原始链挂接只交付持续资产自身；普通产物仍写入运行级共享最新值，不作为该交付的伴随捕获。
lowerTarget :: RuntimeGraph environment cause -> Retention environment cause -> NodeId -> ExecutionFrame -> Maybe (DeliveryFrame environment cause) -> Handoff environment cause
            -> Target environment cause value -> IO (Either (Failure cause) value, Handoff environment cause)
lowerTarget graph retention location executionFrame frame (Handoff given views) target = do
  taken <- maybe (pure []) frameDeliveries frame
  let merged = [(source, view) | (source, (view, _)) <- taken]
        ++ [entry | entry@(source, _) <- views, source `notElem` map fst taken]
      companions = [entry | (_, (_, published)) <- taken, entry@(source, _) <- published, source `notElem` map fst given]
      sinks = [(source, appendDelivery session []) | Just current <- [frame], (source, (session, _)) <- frameSessions current]
      launch = Launch
        { launchBindings = given ++ companions, launchViews = merged, launchPort = NoStreamPort
        , launchSinks = sinks, launchDeliver = \source -> frame >>= (`frameRead` source)
        , launchUser = Nothing, launchFrame = executionFrame, launchRetention = retention }
  keepBindings retention (map snd (given ++ companions) ++ mapMaybe (lastBinding . snd) merged)
  captureFrameDeliveries executionFrame
    [(originNode (executionOrigin (bindingOrigin value)), source, production)
      | (source, value) <- companions, Just production <- [bindingProduction value]
      , source `notElem` [resource | family <- runtimeScopes graph, Just resource <- [scopeContextSource family]]]
  (outcome, captured, delivered) <- lowerWith graph location launch target
  -- 普通跨入口交接仍不传资源；同次 Receive 的内部交接在 sessionLauncher 中处理。
  handoffBindings <- filterM (fmap isNothing . readBindingOwner . snd) captured
  pure (outcome, Handoff handoffBindings delivered)

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

-- Stage 3 执行边界 v1（2026-11-18）：Booter 只提供生产挂载和驱动关系。
-- 本模块管理独立生产步骤，Execution.repeatUnit 管理消费轮次；两者独立推进，
-- 共用 App 的调用身份与捕获、Retention 的绑定保留、Frame 的待用以及 Graph 的 scope GC。
-- 一步结束只撤销本步实际使用；source end 封口并允许排空，会话退役才撤销未来使用预约。
-- ReuseOutput 已属于原消费轮次，不建立第二份循环、ScopeUser 或会话待用帧。

-- 生成区按资产登记的生产步骤。parser 的入口发布一次资产；会话不再次发布返回值。
-- ReceiveSteps：Stream 每次 rawemit 都在返回前驱动一次 parser。
-- DeriveSteps：领取一条上游持续资产的交付后执行 parser，它沿 Input 链执行被驱动的句柄。
data SessionSteps environment cause
  = ReceiveSteps (Target environment cause ()) (Target environment cause ())
  | DeriveSteps (Target environment cause ())

receiveSteps :: Target environment cause () -> Target environment cause () -> SessionSteps environment cause
receiveSteps = ReceiveSteps

deriveSteps :: Target environment cause () -> SessionSteps environment cause
deriveSteps = DeriveSteps

-- 为新会话启动生产任务：按原型找到该边界的会话挂载，逐次执行生产步骤，把发布写入会话交付队列。
-- 每条交付带上本次生产步骤（各挂载当前一次执行）已经发布的普通资产，作为伴随发布。
-- 每步登记实际 scope 使用，会话帧预约后续使用；步骤完成与会话退役都沿现有可达性条件回收。
-- 生产失败（已经过 Error 协议诊断）或原生异常使会话失败并停止，并通知运行监督；
-- Stream handler 的 streamEnd 正常结束会话：封住发布、唤醒等待者，不通知监督，已发布的交付仍可领取；
-- 由上游驱动的会话在上游结束并排空、或被驱动链上的 Excu 调用 endStream 时同样正常结束，
-- 并离开上游（上游的读取方计数减一）；上游失败时以同一个原因失败；
-- 主动停止的取消只结束任务；步骤清理中的意外取消进入既有失败通知，步骤内照常收尾。
-- lifelong 的会话另外安装退役动作：读取方全部离开（引用计数归零）时停止任务、封住发布，
-- 撤销会话的待用预约后回收只在会话挂载中开启的 scope；派生会话退役后，上游若也没有读取方，随之退役。
-- 启动到登记在不可中断区内完成，取消不会落在任务已启动、尚未登记之间。任务继承这一屏蔽，只在生产时解除：
-- 报告失败、撤销使用登记和填写完成信号都不会被停止请求打断，stopSession 一定等得到完成信号。
sessionLauncher :: forall environment cause. RuntimeGraph environment cause -> [(String, SessionSteps environment cause)]
                -> (Broken cause -> IO ()) -> Session environment cause -> IO ()
sessionLauncher graph steps onBroken session
  -- 已挂载的原始链提供输出：只登记会话的交付状态，不创建第二个驱动或资源使用者。
  | Just (ReuseOutput _) <- sessionPlan <$> description = pure ()
  | otherwise = launch
  where
    launch = uninterruptibleMask_ $ do
      (firstMount, locations) <- case mounts of
        Just nodes@(mount : _) -> pure (mount, nodes)
        _ -> ioError (userError ("No session steps for " ++ source ++ " at " ++ show boundary
          ++ "; regenerate with the SDK effect-codegen command"))
      execution <- BusinessExecution <$> newOrigin graph firstMount
      -- 会话待用 v1（2026-11-18）：Composition 已确定挂载与参数来源，运行时只登记
      -- 固定启动捕获和本步实际身份，不根据业务 IO 猜测 socket、event 或轮询。
      selected <- newIORef (sessionViews session)
      upcoming <- newIORef Nothing
      let captured = [(originNode (executionOrigin (bindingOrigin value)), name, production)
            | (name, value) <- sessionBindings session, Just production <- [bindingProduction value]]
          pending name production = do
            views <- readIORef selected
            next <- readIORef upcoming >>= maybe (pure Nothing)
              (\(sourceName, peek) -> if sourceName == name then peek else pure Nothing)
            let fixed = fmap (\view -> (lastBinding view >>= bindingProduction) == Just production) (lookup name views)
                queued = (== Just production) . bindingProduction <$> next
            -- 固定的本步身份与游标下一条都是具体义务；等待不把所有旧实例都保活。
            pure $ case (fixed, queued) of
              (Nothing, Nothing) -> Nothing
              _ -> Just (maybe False id fixed || maybe False id queued)
      future <- newSessionFrame (runtimeRootFrame graph) boundary locations captured pending
      let withdraw = void (finishExecutionFrame future)
      (do
        finished <- newEmptyMVar
        thread <- forkIOWithUnmask $ \unmask -> (`finally` putMVar finished ()) $ (`finally` withdraw) $ do
          outcome <- try $ unmask $ do
            produced <- produce execution future selected upcoming
            case produced of
              Just problem -> broken (Right problem)
              -- end 只封口；最后一份待用仍保留到既有的会话退役边界。
              -- 不再用跨全部步骤的 ScopeUser 把所有历史实例一起保留。
              Nothing -> endSession session >> forever (threadDelay 3600000000)
          case outcome of
            Left (exception :: SomeException) -> do
              stopping <- sessionStopping session
              -- 只有 stopSession 已登记的取消是本会话的正常退役；close/诊断的取消
              -- 仍须通知监督，不能令生产线程悄悄消失而让消费者永远等待。
              case fromException exception :: Maybe SomeAsyncException of
                Just _ | stopping -> pure ()
                _ -> broken (Left exception)
            Right () -> pure ()
        setSessionWorker session thread finished
        -- interpreter 托管的会话没有读取方登记，仍在运行结束时统一停止。
        forM_ boundary $ \_ -> setSessionRetirement session retire) `onException` withdraw
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
    -- 会话的各步骤位置被同一组标注覆盖；按首个步骤取 gen 特化的步骤。
    label = maybe source (\nodes -> case nodes of
      first : _ -> referenceLabel (runtimePrototype graph) first source
      [] -> source) mounts
    produce execution future selected upcoming = case (lookup label steps, mounts) of
      (Just (ReceiveSteps stream parser), Just [streamMount, parserMount]) -> loop $ withStep execution $ \owner retention -> do
        -- 来源拥有本次调用的资源。每条 emit 在独立的 parser 调用与保留范围中发布，
        -- parser 完成后立即释放该次使用；长时间未返回的来源不会积累历次 parser 的捕获。
        let deliver text captured = withStep execution $ \parserOwner parserRetention -> do
              inheritScopeUse owner parserOwner
              resources <- filterM (fmap isJust . readBindingOwner . snd) captured
              let parseStep = (step parserOwner parserRetention (ParserInput text) sink)
                    { launchBindings = resources ++ [entry | entry@(name, _) <- sessionBindings session
                      , name `notElem` map fst resources] }
              first <$> lowerWith graph parserMount parseStep parser
        taken <- try (lowerWith graph streamMount (step owner retention (SourcePort deliver) []) stream)
        pure $ case taken of
          Left SourceEnded -> Just Nothing
          Right (Left problem, _, _) -> Just (Just problem)
          Right (Right (), _, _) -> Nothing
      -- 每一步先领取一条上游交付，把该 Binding 作为本步的固定视图；上游结束并排空即正常结束。
      -- 被驱动链上的 Excu 调用 endStream：这一步放弃，不发布，派生会话不再消费上游，同样正常结束。
      -- 正常退出时离开上游，计数归零则退役上游；失败或取消只离开，停止交给收尾或本会话的退役。
      (Just (DeriveSteps parser), Just [mount]) -> mask $ \restore -> do
        (upstream, cursor) <- awaitUpstream session
        withFrameLock future $ writeIORef upcoming (Just (snd (sessionKey upstream), pendingDelivery upstream cursor))
        -- 游标的撤销覆盖整个生产/退役过程，取消不能落在正常结束与离开上游之间。
        restore (do
          outcome <- loop $ withStep execution $ \owner retention -> do
            -- 在同一领取临界区内先固定身份、再推进游标。等待期间查询具体下一条，
            -- 不用全称保活填补“游标已前进、身份还没写入”的窗口。
            taken <- takeDeliveryWith upstream cursor retention (pure Nothing)
              (\(view, _) -> writeIORef selected ((snd (sessionKey upstream), view) :
                filter ((/= snd (sessionKey upstream)) . fst) (sessionViews session)))
            case taken of
              Left Drained -> pure (Just Nothing)
              Left Undriven -> pure (Just Nothing)
              Left (Broke (Right problem)) -> pure (Just (Just problem))
              Left (Broke (Left exception)) -> throwIO exception
              Right (view, _) -> do
                stepped <- try (lowerWith graph mount (driven owner retention (snd (sessionKey upstream)) view) parser)
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
    -- 每步实际使用 v1（2026-11-18）：Receive 的来源与逐条 parser 分别持有活跃使用，Derive
    -- 每条交付使用一次；诊断与解析完成后撤销，再由现有 GC 核对长期预约及其他使用者。
    -- 新参数只产生新实例；另一订阅/调用仍持有的旧实例不因本步骤结束而关闭。
    withStep :: Execution -> (ScopeUser environment cause -> Retention environment cause -> IO a) -> IO a
    withStep execution action = mask $ \restore -> do
      owner <- newScopeUser (runtimeScopes graph) execution
      restore (withRuntimeRetention graph (action owner)) `finally` (do
        detachScopeUser owner
        collectRuntimeScopes graph (maybe [] id mounts))
    -- 发布的原帧不变；future 只表达后续生产步骤的待用，不改变 Binding 出身。
    step owner retention input sinks = Launch
      { launchBindings = sessionBindings session, launchViews = sessionViews session, launchPort = input
      , launchSinks = sinks, launchDeliver = noDelivery, launchUser = Just owner
      , launchFrame = runtimeRootFrame graph, launchRetention = retention }
    -- 被驱动的一步：上游这条交付的视图盖过交接中同一来源的视图。
    driven owner retention upstream view = (step owner retention NoStreamPort sink)
      { launchViews = (upstream, view) : filter ((/= upstream) . fst) (sessionViews session) }
    noDelivery = const Nothing
    first (outcome, _, _) = outcome
    broken reason = breakSession session reason `finally` onBroken reason
    -- 逐次执行直到来源结束（Nothing）或第一次失败（Just problem）；结果交回不可中断区登记。
    loop step = step >>= maybe (loop step) pure

-- 会话计划与挂载只来自同一份原型；复用原始链输出的会话没有独立生产挂载。
referenceLabel :: PrototypeReference -> NodeId -> String -> String
referenceLabel (PrototypeReference prototype) = entryLabel (protoDriving prototype)

sessionDescriptionOf :: PrototypeReference -> Maybe NodeId -> String -> Maybe SessionProto
sessionDescriptionOf (PrototypeReference prototype) boundary source =
  sessionDriveAt prototype boundary source >>= describedSession prototype
