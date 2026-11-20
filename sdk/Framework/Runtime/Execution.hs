{-# LANGUAGE ScopedTypeVariables #-}

-- Node 按原型中的挂载位置 lower 末端句柄；branch 组合执行闭包。
-- Workflow 执行与受管理任务边界。这里装配 branch、重复消费单元并监督整次运行；
-- Runtime 负责末端及生产任务，Session 负责待交付队列，App 负责单次调用的资源协议。
-- 退出先取消并等待 AST 子任务，再停止生产会话，最后撤销根帧并回收不可达实例。
module Framework.Runtime.Execution (runStructuredAST) where

import Framework.Language.Handler (Failure, Output(..))
import Framework.Runtime
  ( Target, Handoff, SessionSteps, DeliveryFrame, LocalSource(..), noHandoff, targetName, lowerTarget, scopeHandlers
  , newDeliveryFrame, frameDelivery, framePublishes, haltFrame, frameStopping, frameAdmits, boundarySession, sessionLauncher )
import Framework.Runtime.Graph
  ( RuntimeGraph, newRuntimeGraph, configureRuntimeScopes, installSessionLauncher
  , stopSessions, resetOrigins, runtimeRootFrame, collectRuntimeScopes, finishRuntime, withRuntimeRetention )
import Framework.Runtime.Frame
import Framework.Runtime.Session
  ( Broken, Stopped(..), DeliveryDrained(..), SubscriptionEnded(..), admitReaders, leaveSession, departSession
  , retireSession, feedSession, endSession, breakSession )
import Framework.Prototype
import Framework.Recursion (Algebra)
import Framework.Language.AST (AST, WorkflowF(..), foldAST)
import Control.Concurrent (MVar, ThreadId, forkIOWithUnmask, killThread, newEmptyMVar, putMVar, readMVar, tryPutMVar)
import Control.Concurrent.MVar (newMVar, modifyMVar)
import Control.Exception
  (SomeAsyncException, SomeException, finally, fromException, mask, mask_, onException, throwIO, try, uninterruptibleMask_)
import Control.Monad (forM, forM_, unless, void)
import Control.Monad.Except (ExceptT(..), runExceptT)
import Data.IORef (IORef, atomicModifyIORef', modifyIORef', newIORef, readIORef, writeIORef)
import Data.List (isPrefixOf, partition)

-- 执行期环境：lifelong 单元的本次 frame，以及运行监督。
-- 临时规则（局部失败恢复尚未实现）：AST 含 lifelong 时，任何失败（Error 协议诊断之后）
-- 或原生异常都在发生处报告监督，终止整次运行；不含 lifelong 时监督不做任何事。
data Run environment cause = Run
  { runExecutionFrame :: ExecutionFrame
  , runDeliveryFrame :: Maybe (DeliveryFrame environment cause)
  , runFatal :: Broken cause -> IO ()
  -- lifelong 单元中已经结束订阅（endStream）的节点；之后各轮跳过它们。lifelong 之外为 Nothing。
  , runEnded :: Maybe (IORef [NodeId])
  -- 订阅永久结束时立即撤下发布位置，不能等到下一轮才通知当前轮的等待者。
  , runWithdraw :: [NodeId] -> IO ()
  }

endedNodes :: Run environment cause -> IO [NodeId]
endedNodes run = maybe (pure []) readIORef (runEnded run)

-- 执行树内部的两种提前退出。Problem 是业务失败，沿现有协议传播并报告监督。
-- Finished 是 lifelong 单元的正常结束：本次执行所需的来源已结束并排空。它停止本次执行中尚未启动的后继，
-- 只传到单元边界，不进入 Error 协议，也不通知监督；lifelong 之外不会出现。
data Halt cause = Finished | Problem (Failure cause)

-- Handoff 是已经捕获的绑定；alternative 的候选承接选择阶段的同一份值。
type Execution environment cause value =
  Run environment cause -> Handoff environment cause -> ExceptT (Halt cause) IO [value]

-- 作为 lifelong 子项时的单元划分：直接子项是 parallel 时拆这一层，其余子树整体是一个单元。
data Compiled environment cause value = Compiled
  { compiledRun :: Execution environment cause value
  , compiledUnits :: [(NodeId, Execution environment cause value)]
  }

type Prepared method environment cause value =
  WorkflowTree -> Either (PrototypeError method) (Compiled environment cause value)

type Worker value = (ThreadId, MVar (Either SomeException value))

-- 保持既有并发汇合：等待全部分支；父执行退出时先通知全部子任务停止，再等待清理。
-- killThread 同步等待异常被接收，因此每次投递有独立任务和完成信号，慢 close 不挡住其他投递。
withWorkers :: [IO value] -> ([Worker value] -> IO result) -> IO result
withWorkers actions use = mask $ \restore -> do
  owned <- newIORef []
  let acquire action = do
        worker <- spawn action
        modifyIORef' owned (worker :)
        pure worker
  (mapM acquire actions >>= restore . use)
    `finally` (readIORef owned >>= stop)
  where
    spawn work = do
      finished <- newEmptyMVar
      thread <- forkIOWithUnmask $ \unmask ->
        try (unmask work) >>= putMVar finished
      pure (thread, finished)
    stop workers = uninterruptibleMask_ $ do
      deliveries <- forM workers $ \(thread, _) -> do
        delivered <- newEmptyMVar
        _ <- forkIOWithUnmask $ \_ -> killThread thread `finally` putMVar delivered ()
        pure delivered
      mapM_ readMVar deliveries
      mapM_ (readMVar . snd) workers

runParalleled :: [IO value] -> IO [value]
runParalleled actions = withWorkers actions $ \workers -> do
  outcomes <- mapM (readMVar . snd) workers
  either throwIO pure (sequence outcomes)

-- 收尾照常完成，原操作的异常／取消优先；收尾中的取消也必须停止后续业务。
-- SDK Failure 是返回值，因此同步 close 的业务失败不会改变它。
retireAfter :: IO value -> ((IO () -> IO ()) -> IO ()) -> IO value
retireAfter action retirement = mask $ \restore -> do
  outcome <- try (restore action)
  retired <- try (retirement restore)
  case (outcome, retired) of
    (Left (exception :: SomeException), _)
      | Just (_ :: SomeAsyncException) <- fromException exception -> throwIO exception
    (_, Left (exception :: SomeException))
      | Just (_ :: SomeAsyncException) <- fromException exception -> throwIO exception
    (Left exception, _) -> throwIO exception
    (_, Left exception) -> throwIO exception
    (Right value, Right ()) -> pure value

withFrameNode :: RuntimeGraph environment cause -> Run environment cause -> NodeId -> IO value -> IO value
withFrameNode graph run node action = mask $ \restore -> do
  startFrameNode (runExecutionFrame run) node
  retireAfter (restore action) $ \_ -> do
    retired <- completeFrameNode (runExecutionFrame run) node
    restore (collectRuntimeScopes graph retired)

-- 失败照常向上传播，同时报告监督；取消与单元的正常结束都不是失败。
supervised :: Run environment cause -> IO (Either (Halt cause) value) -> IO (Either (Halt cause) value)
supervised run action = do
  outcome <- try action
  case outcome of
    Left (exception :: SomeException)
      | Just (_ :: SomeAsyncException) <- fromException exception -> throwIO exception
      | otherwise -> runFatal run (Left exception) >> throwIO exception
    Right (Left (Problem problem)) -> runFatal run (Right problem) >> pure (Left (Problem problem))
    Right value -> pure value

-- 回调 boot 的就绪条件：本次 frame 已有该位置所订阅资产的交付。
-- 已有积压时立即领取，没有新发布时挂起；不通过反复调用 handler 试探数据。
-- 来源已结束并排空时不 boot 这个位置：通知本单元（唤醒仍在等其他来源、尚未启动的并行路径），
-- 以 Finished 结束本次执行。
-- 单元结束与来源结束是两件事：来源结束后已发布的交付继续交付；单元结束后不再启动新的位置，
-- 即使它等的来源随后又发布了数据。交付到手之后还要取得启动许可（frameAdmits）才 boot：
-- 等待者无论被结束通知还是被新数据唤醒，都在这里重新判定；通过的视作已启动，单元等它完成。
-- 发布位置在本单元（含派生）的会话等待本轮稳定：确定没有新发布时位置本轮不执行（Quiet），
-- 已封口并排空时只结束这个位置的订阅（Exhausted），不结束单元。
awaitDeliveries :: Run environment cause -> [String] -> IO (Either (Halt cause) Drive)
awaitDeliveries run sources = case runDeliveryFrame run of
  Nothing -> pure (Right Driven)
  Just frame -> do
    -- 已经在结束的单元不必再领取；这只是提前返回，判定以下面的启动许可为准。
    stopping <- frameStopping frame
    if stopping then pure (Left Finished) else do
      claimed <- go frame [(source, deliver) | source <- sources, Just deliver <- [frameDelivery frame source]]
      case claimed of
        Right Driven -> do
          admitted <- frameAdmits frame
          pure (if admitted then Right Driven else Left Finished)
        other -> pure other
  where
    go _ [] = pure (Right Driven)
    go frame ((source, deliver) : rest) = do
      outcome <- deliver
      case outcome of
        Left (Broke (Left exception)) -> throwIO exception
        Left (Broke (Right problem)) -> pure (Left (Problem problem))
        Left Undriven -> pure (Right Quiet)
        Left Drained | framePublishes frame source -> pure (Right Exhausted)
        Left Drained -> haltFrame frame >> pure (Left Finished)
        Right _ -> go frame rest

-- 一个位置本轮是否被驱动。Driven：所订阅资产的交付都已领取；Quiet：本单元发布的会话本轮没有新发布，
-- 位置本轮不执行；Exhausted：本单元发布的会话已封口并排空，位置的订阅随之结束。
data Drive = Driven | Quiet | Exhausted

-- 把节点记为本单元已结束订阅并立即撤下发布位置；之后各轮跳过，两轮之间离开不再读取的会话。
endNodes :: Run environment cause -> [NodeId] -> IO ()
endNodes run nodes = mask_ $ forM_ (runEnded run) $ \ended -> do
  atomicModifyIORef' ended (\current -> (nodes ++ current, ()))
  runWithdraw run nodes

-- 已经 boot 的调用在第一次读取时才领取交付、而来源已结束并排空：这次调用放弃，单元正常结束。
-- 调用自身的收尾已由 App 完成；这里只把内部信号换成 Finished 并通知本单元。
draining :: Run environment cause -> IO (Either (Failure cause) value) -> IO (Either (Halt cause) value)
draining run action = do
  outcome <- try action
  case outcome of
    Left DeliveryDrained -> mapM_ haltFrame (runDeliveryFrame run) >> pure (Left Finished)
    Right result -> pure (either (Left . Problem) Right result)

-- 节点的调用中 endStream：本次调用放弃、不交出结果，本节点的订阅结束；同一轮中其余位置照常执行。
-- endStream 表示之后不再被驱动：立即撤下发布位置，最后一个位置退出则封口，派生会话可随之排空。
-- 同单元读取还会等待其他并行发布位置及派生处理；两轮之间离开不再有活节点读取的会话。
subscribing :: Run environment cause -> NodeId -> IO (Either (Halt cause) [value]) -> IO (Either (Halt cause) [value])
subscribing run location action = do
  outcome <- try action
  case (outcome, runEnded run) of
    (Right result, _) -> pure result
    (Left SubscriptionEnded, Just _) -> do
      endNodes run [location]
      pure (Right [])
    (Left SubscriptionEnded, Nothing) -> ioError (userError ("endStream at " ++ show location
      ++ " outside a lifelong subscription; regenerate with the SDK effect-codegen command"))

-- 并行分支汇合：失败优先；没有失败而某一路正常结束时，整组按正常结束返回。
joined :: [Either (Halt cause) value] -> Either (Halt cause) [value]
joined outcomes = case ([problem | Left (Problem problem) <- outcomes], [() | Left Finished <- outcomes]) of
  (problem : _, _) -> Left (Problem problem)
  ([], _ : _) -> Left Finished
  ([], []) -> Right [value | Right value <- outcomes]

-- 一次 cata 得到等待原型位置的装配函数：同一层同时核对 AST 骨架和装配动作。
-- 父节点把已经生成的子树描述交给各子闭包；运行时没有另一份链展开或 alternative 推导。
executionAlgebra
  :: Prototype method
  -> RuntimeGraph environment cause
  -> [(String, Target environment cause value)]
  -> [(String, Target environment cause String)]
  -> Algebra WorkflowF (Prepared method environment cause value)
executionAlgebra prototype store entries selectors layer expected = do
  expectedChildren <- matchWorkflowLayer layer expected
  let location = workflowNode expected
      -- 每棵子树退出都撤销未进入的后继；parallel 的退出发生在等待所有子任务之后。
      managed execution run handoff = ExceptT $ supervised run $
        retireAfter (runExceptT (execution run handoff)) $ \restore -> do
          retired <- skipFrameSubtree (runExecutionFrame run) location
          restore (collectRuntimeScopes store retired)
      single execution = let wrapped = managed execution in pure (Compiled wrapped [(location, wrapped)])
      compiledChildren = sequence (zipWith ($) children expectedChildren)
      children = case layer of
        Node _ -> []
        Chained selected -> selected
        Parallel selected -> selected
        Alternative selected -> selected
        Lifelong selected -> selected
  case (layer, expected) of
    (Node selected, NodeAt _ _) -> do
      chain <- lookupChain prototype location
      unless (chainRole chain == NodeChain && chainTerminal chain == selected) $
        Left (InvalidPrototype ("Node chain differs at " ++ show location))
      -- 被 middleware 标注覆盖的挂载使用 gen 特化的 Target；运行时只按静态登记名选取。
      entry <- resolve entries (entryLabel (protoDriving prototype) location (chainTerminal chain))
      let subscribed = driveSubscriptions (nodeDriveAt prototype location)
      -- 已经结束订阅的节点不再执行，也不领取交付；退出时由 managed 把它记为跳过。
      single $ \run handoff -> ExceptT $ do
        ended <- endedNodes run
        if location `elem` ended then pure (Right []) else withFrameNode store run location $ do
          ready <- awaitDeliveries run subscribed
          case ready of
            Left halt -> pure (Left halt)
            Right Quiet -> pure (Right [])
            Right Exhausted -> endNodes run [location] >> pure (Right [])
            Right Driven -> withRuntimeRetention store $ \retention ->
              subscribing run location $ draining run $ fmap (: []) . fst <$>
                lowerTarget store retention location (runExecutionFrame run) (runDeliveryFrame run) handoff entry
    (Chained _, _) -> do
      parts <- map compiledRun <$> compiledChildren
      single (\run handoff -> concat <$> sequence [part run handoff | part <- parts])
    (Parallel _, _) -> do
      parts <- map compiledRun <$> compiledChildren
      let execution run handoff = ExceptT $ do
            outcomes <- runParalleled [runExceptT (part run handoff) | part <- parts]
            pure (concat <$> joined outcomes)
      pure (Compiled (managed execution) (zip (map workflowNode expectedChildren) parts))
    (Alternative _, AlternativeAt _ description _) -> do
      parts <- map compiledRun <$> compiledChildren
      chain <- lookupChain prototype (alternativeSelector description)
      unless (chainRole chain == SelectorChain
          && chainTerminal chain == alternativeSource description) $
        Left (InvalidAlternative location "Selector chain differs from its alternative")
      selector <- resolve selectors (entryLabel (protoDriving prototype) (alternativeSelector description) (chainTerminal chain))
      constructors <- mapM (constructorAt description . workflowNode) expectedChildren
      let candidates = zip constructors (zip (map workflowNode expectedChildren) parts)
          members = driveMembers (nodeDriveAt prototype location)
      -- 选择读取执行共同的 Excu 一次，按声明顺序取第一个判定成功的候选；它的捕获交给该候选。
      -- 候选中的节点都已结束订阅时，选择读取不再执行，整个 alternative 跳过。
      single $ \run handoff -> ExceptT $ withRuntimeRetention store $ \retention -> do
       ended <- endedNodes run
       if not (null members) && all (`elem` ended) members then pure (Right []) else do
        chosen <- withFrameNode store run (alternativeSelector description) $ draining run $ do
          (selected, captured) <- lowerTarget store retention (alternativeSelector description)
            (runExecutionFrame run) (runDeliveryFrame run) handoff selector
          pure (fmap (\context -> Just (context, captured)) selected)
        case chosen of
          -- 选择读取失败或来源耗尽时不启动候选。
          Left halt -> pure (Left halt)
          Right Nothing -> pure (Right [])
          Right (Just (constructor, captured)) -> case lookup constructor candidates of
            Just (selectedNode, candidate) -> do
              retired <- concat <$> mapM (skipFrameSubtree (runExecutionFrame run))
                [node | (_, (node, _)) <- candidates, node /= selectedNode]
              collectRuntimeScopes store retired
              runExceptT (candidate run captured)
            Nothing -> ioError (userError ("No alternative candidate for the Context " ++ constructor
              ++ "; regenerate with the SDK effect-codegen command"))
    -- 进入 lifelong 时取得本边界的会话（按需启动生产），各单元并发、互不等待地重复执行。
    -- 单元在所需来源结束并排空后各自正常结束；全部单元结束后，停止本边界的生产任务并等待其收尾，
    -- lifelong 才成功返回，外层后继继续执行。执行结果不累积，成功时不带结果。
    -- 失败与取消保持原规则：失败在发生处已经报告监督，随整次运行终止。
    -- 每个会话在进入时登记它的读取方与游标，会话据此保留尚未领取的发布；
    -- 单元结束即离开。全部单元离开后会话只剩最新一条，留给 lifelong 的后继读取。
    -- 由某份资产驱动的会话也是它的读取方，与单元一同登记，游标交给那份会话的生产任务，
    -- 它在上游结束并排空后结束并离开。
    (Lifelong _, LifelongAt _ description _) -> do
      compiled <- concatMap compiledUnits <$> compiledChildren
      units <- mapM (\unit -> (,) unit <$> maybe (Left (InvalidLifelong unit "Missing compiled unit")) Right (lookup unit compiled))
        (lifelongUnits description)
      sources <- mapM (\session -> case [route | route <- drivingSessions (protoDriving prototype)
          , driveSessionBoundary route == Just location, driveSessionAsset route == sessionAsset session] of
        [route] -> Right (sessionAsset session, sessionPlan session, driveSessionSource route)
        _ -> Left (InvalidLifelong location "Missing generated session driver")) (lifelongSessions description)
      -- 读取位置与派生关联由 Booter 给出；这里只检查本单元实际结束的位置。
      let access ended _ source unit = any (available ended)
            (maybe [] id (lookup source (driveReaders (unitDriveAt prototype unit))))
          available ended (ReadAt position) = live ended position
          available ended (ChooseAmong members) = any (live ended) members
          live ended position = not (any (`isPrefixOf` position) ended)
          needs unit ended source = access ended "" source unit
      single $ \run handoff -> ExceptT $ do
        opened <- forM sources $ \(asset, plan, source) ->
          (,,,) asset plan source <$> boundarySession store location source handoff
        sessions <- forM opened $ \(asset, _, source, session) -> do
          let driven = [dependent | (_, Derive upstream, _, dependent) <- opened, upstream == asset]
          cursors <- admitReaders session
            ([access [] asset source unit | (unit, _) <- units] ++ map (const True) driven)
          sequence_ (zipWith (\dependent -> feedSession dependent session) driven (drop (length units) cursors))
          pure (source, session, take (length units) cursors)
        -- 接收原始链输出的会话随发布位置结束，不等所有下游一起结束：
        -- 否则下游正在等本会话的结束，整个 lifelong 就永远无法汇合。
        -- 发布位置按节点计：节点 endStream 或所在单元结束都撤下它，全部撤下才封口；逐轮完成不撤下。
        -- 单元失败时，它尚未撤下的发布位置使会话失败。
        publishers <- forM [(nodes, session) | (_, ReuseOutput nodes, _, session) <- opened] $ \(nodes, session) -> do
          pending <- newMVar nodes
          pure (session, pending)
        let withdraw positions result = forM_ publishers $ \(session, pending) -> do
              remaining <- modifyMVar pending $ \owners ->
                let rest = filter (\owner -> not (any (`isPrefixOf` owner) positions)) owners
                in pure (rest, if length rest == length owners then Nothing else Just rest)
              case (remaining, result) of
                (Just _, Left problem) -> breakSession session (Right problem)
                (Just [], Right ()) -> endSession session
                _ -> pure ()
        -- 本单元发布及其 Derive 后继已在 gen 标出；运行时等待协议只读该关系。
        let local unit = driveLocalSources (unitDriveAt prototype unit)
        outcomes <- runParalleled
          [ do
              outcome <- repeatUnit location run handoff
                [(source, (session, cursors !! index)) | (source, session, cursors) <- sessions]
                (local (fst unit)) (needs (fst unit)) (\ended -> withdraw ended (Right ())) unit
              withdraw [fst unit] (() <$ outcome)
              pure outcome
          | (index, unit) <- zip [0 ..] units ]
        -- 读取方都已离开：计数归零时多数会话已经退役，这里补上其余的并等待任务退出。此后不再接受发布。
        -- 上游排在前面，逆序退役：被驱动的会话先停并离开上游。
        mapM_ (\(_, session, _) -> retireSession session >> endSession session) (reverse sessions)
        pure (either (Left . Problem) Right (concat <$> sequence outcomes))
    _ -> Left PrototypeWorkflowMismatch
  where
    resolve compiled selected =
      maybe (Left (UnknownPrototypeTarget selected)) Right (lookup selected compiled)
    constructorAt description location =
      maybe (Left (InvalidAlternative location "Missing candidate Context")) Right
        (lookup location (alternativeCases description))
    -- 单元的游标属于（单元，会话），进入 lifelong 时从会话首条开始。
    -- 每次执行是新的 frame：先移出该单元上一次执行的 Origin，执行结果不累积；
    -- 同一单元逐次处理，本次结束后才领取下一条。所需来源结束并排空时单元正常结束，不再开始下一次执行；
    -- 发生在一次执行中途时，已完成的部分不回滚，尚未启动的部分放弃。
    -- 消费方结束按引用计数逐层传递：节点 endStream 时立即撤下发布位置，之后各轮跳过它；
    -- 单元不再有活节点读取的会话立即离开（计数归零的会话随之退役），之后的 frame 不再领取它；
    -- 单元的节点全部结束订阅时单元正常结束。parallel 的其他单元不受影响。
    -- 本地会话（local）包含 Derive 间接依赖；等待实际轮帧及派生完成水位，
    -- 本轮稳定后没有新发布才跳过，会话封口并排空后读取位置的订阅随之结束。
    -- 单元正常结束时离开仍持有的会话并按计数退役；失败或取消只离开，停止交给 lifelong 返回或运行结束。
    -- Stage 3 执行边界 v1（2026-11-18）：每轮的 ExecutionFrame 表达有限待用，
    -- DeliveryFrame 固定本轮领取，Retention 覆盖整轮交接；退出依次撤销，再调用既有 scope GC。
    -- 与 Runtime.withStep 共用底层协议，但不共用循环：消费等待交付，生产按自己的来源推进。
    -- Finished 结束单元，endStream 只撤销相应节点；来源封口和生产任务退役由 Session 协调。
    repeatUnit boundary run handoff cursors local needed withdraw (unit, execute) = do
      ended <- newIORef []
      held <- newIORef cursors
      let members = driveMembers (nodeDriveAt prototype unit)
          settle seen = do
            current <- readIORef ended
            let fresh = filter (`notElem` seen) current
            unless (null fresh) $ do
              taken <- readIORef held
              -- 只离开本单元登记为读取方的会话；不读取的会话仍留在 frame 中，作为本单元发布位置的出口。
              let (kept, left) = partition (\(source, _) -> needed current source || not (needed [] source)) taken
              writeIORef held kept
              mapM_ (\(_, (session, cursor)) -> departSession session cursor) left
            pure current
          loop seen = do
            current <- settle seen
            if all (`elem` current) members then pure (Right []) else do
              resetOrigins store unit
              outcome <- withRuntimeRetention store $ \retention -> mask $ \restore -> do
                frame <- newChildFrame (runExecutionFrame run) boundary
                  (driveFrameNodes (unitDriveAt prototype unit))
                delivery <- readIORef held >>= newDeliveryFrame retention frame local [(source, session) | (source, (session, _)) <- cursors]
                retireAfter
                  (restore (runExceptT (execute run { runExecutionFrame = frame, runDeliveryFrame = Just delivery
                                                    , runEnded = Just ended, runWithdraw = withdraw } handoff))) $ \_ -> do
                    retired <- finishExecutionFrame frame
                    restore (collectRuntimeScopes store retired)
              case outcome of
                Left (Problem problem) -> pure (Left problem)
                Left Finished -> pure (Right [])
                Right _ -> loop current
      outcome <- loop [] `onException` mapM_ (\(_, (session, cursor)) -> leaveSession session cursor) cursors
      remaining <- readIORef held
      forM_ remaining $ \(_, (session, cursor)) -> case outcome of
        Right _ -> departSession session cursor
        Left _ -> void (leaveSession session cursor)
      pure outcome

-- Prototype 已在 SDK 入口完整求值并校验；这里一次 fold 核对当前 AST 并装配全部入口。
-- 所有 Either 分支完成后才安装独立 ScopeTree 的关系、执行业务。
-- 两类 boot、资产和实例使用共享 RuntimeGraph；方法体仍由已装配的闭包执行。
-- 生产会话按需启动；AST 结束（或被取消）后先取消全部会话并等待其步骤收尾，再退休根帧。
runStructuredAST
  :: (Eq method, Show method)
  => Prototype method -> AST
  -> [Target environment cause value]
  -> [Target environment cause String]
  -> [(String, SessionSteps environment cause)]
  -> IO (Output cause [value])
runStructuredAST prototype tree entries selectors sessions = do
  store <- newRuntimeGraph prototype (scopeHandlers entries)
  -- 挂载来自已校验的 Prototype；运行时只折叠实际的业务树。
  prepared <- either (ioError . userError . show) pure $
    foldAST (executionAlgebra prototype store compiled readers) tree (protoWorkflow prototype)
  configureRuntimeScopes store
  retireAfter (if null (drivingUnits (protoDriving prototype))
    then do
      installSessionLauncher store (sessionLauncher store sessions (const (pure ())))
      runExceptT (compiledRun prepared (Run (runtimeRootFrame store) Nothing (const (pure ())) Nothing (const (pure ()))) noHandoff)
        >>= completed
    else do
      -- 第一个失败或原生异常结束整次运行：取消 AST 中的全部任务并等待其收尾，再停止会话，
      -- 最后以最初的那个失败报告；AST 未进入 lifelong 而正常结束时照常返回。
      settled <- newEmptyMVar
      let settle = void . tryPutMVar settled
          run = Run (runtimeRootFrame store) Nothing (settle . Left) Nothing (const (pure ()))
          work = do
            outcome <- try (runExceptT (compiledRun prepared run noHandoff))
            settle (either (Left . Left) Right outcome)
      installSessionLauncher store (sessionLauncher store sessions (settle . Left))
      result <- withWorkers [work] (const (readMVar settled))
      case result of
        Left (Left exception) -> throwIO exception
        Left (Right problem) -> pure (Failed problem)
        Right outcome -> completed outcome)
    (\_ -> stopSessions store `finally` do
      _ <- finishExecutionFrame (runtimeRootFrame store)
      finishRuntime store)
  where
    compiled = [(targetName entry, entry) | entry <- entries]
    readers = [(targetName entry, entry) | entry <- selectors]
    -- Finished 只在 lifelong 单元内产生，并在单元边界换成单元的正常结束；到达这里说明装配与原型不一致。
    completed (Right values) = pure (Succ values)
    completed (Left (Problem problem)) = pure (Failed problem)
    completed (Left Finished) = ioError (userError
      "A stream delivery ended outside a lifelong unit; regenerate with the SDK effect-codegen command")
