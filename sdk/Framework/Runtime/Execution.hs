{-# LANGUAGE ScopedTypeVariables #-}

-- Node 按原型中的挂载位置 lower 末端句柄；branch 组合执行闭包。
-- Workflow 执行与受管理任务边界。这里装配 branch、重复消费单元并监督整次运行；
-- Runtime 负责末端及生产任务，Session 负责交付日志，App 负责单次调用的资源协议。
-- 退出先取消并等待 AST 子任务，再停止生产会话；scope 最终兜底由 Program 负责。
module Framework.Runtime.Execution (runStructuredAST) where

import Framework.Language.Handler (Failure, Output(..))
import Framework.Runtime
  ( Target, Handoff, SessionSteps, Frame, noHandoff, targetName, lowerTarget, scopeHandlers
  , newFrame, frameDelivery, boundarySession, sessionLauncher )
import Framework.Runtime.Graph
  ( RuntimeGraph, newRuntimeGraph, configureRuntimeScopes, installSessionLauncher
  , stopSessions, resetOrigins )
import Framework.Runtime.Session (Broken, newCursor)
import Framework.Prototype
import Framework.Recursion (Algebra)
import Framework.Language.AST (AST, WorkflowF(..), foldAST)
import Control.Concurrent (MVar, ThreadId, forkIOWithUnmask, killThread, newEmptyMVar, putMVar, readMVar, tryPutMVar)
import Control.Exception (SomeAsyncException, SomeException, bracket, finally, fromException, throwIO, try, uninterruptibleMask_)
import Control.Monad (unless, void)
import Control.Monad.Except (ExceptT(..), runExceptT)

-- 执行期环境：lifelong 单元的本次 frame，以及运行监督。
-- 临时规则（lifelong 的 close 语义设计前）：AST 含 lifelong 时，任何失败（Error 协议诊断之后）
-- 或原生异常都在发生处报告监督，终止整次运行；不含 lifelong 时监督不做任何事。
data Run environment cause = Run
  { runFrame :: Maybe (Frame environment cause)
  , runFatal :: Broken cause -> IO ()
  }

-- Handoff 是已经捕获的绑定；alternative 的候选承接选择阶段的同一份值。
type Execution environment cause value =
  Run environment cause -> Handoff environment cause -> ExceptT (Failure cause) IO [value]

-- 作为 lifelong 子项时的单元划分：直接子项是 parallel 时拆这一层，其余子树整体是一个单元。
data Compiled environment cause value = Compiled
  { compiledRun :: Execution environment cause value
  , compiledUnits :: [(NodeId, Execution environment cause value)]
  }

type Prepared method environment cause value =
  WorkflowTree -> Either (PrototypeError method) (Compiled environment cause value)

type Worker value = (ThreadId, MVar (Either SomeException value))

-- 保持既有并发汇合：等待全部分支；父执行退出时取消并等待子线程清理。
withWorkers :: [IO value] -> ([Worker value] -> IO result) -> IO result
withWorkers [] use = use []
withWorkers (action : rest) use =
  bracket (spawn action) stop $ \worker ->
    withWorkers rest $ \workers -> use (worker : workers)
  where
    spawn work = do
      finished <- newEmptyMVar
      thread <- forkIOWithUnmask $ \unmask ->
        try (unmask work) >>= putMVar finished
      pure (thread, finished)
    stop (thread, finished) = uninterruptibleMask_ $ do
      killThread thread
      void (readMVar finished)

runParalleled :: [IO value] -> IO [value]
runParalleled actions = withWorkers actions $ \workers -> do
  outcomes <- mapM (readMVar . snd) workers
  either throwIO pure (sequence outcomes)

-- 失败照常向上传播，同时报告监督；取消不是失败。
supervised :: Run environment cause -> IO (Either (Failure cause) value) -> IO (Either (Failure cause) value)
supervised run action = do
  outcome <- try action
  case outcome of
    Left (exception :: SomeException)
      | Just (_ :: SomeAsyncException) <- fromException exception -> throwIO exception
      | otherwise -> runFatal run (Left exception) >> throwIO exception
    Right (Left problem) -> runFatal run (Right problem) >> pure (Left problem)
    Right value -> pure value

-- 回调 boot 的就绪条件：本次 frame 已有该位置所订阅资产的交付。
-- 已有积压时立即领取，没有新发布时挂起；不通过反复调用 handler 试探数据。
awaitDeliveries :: Run environment cause -> [String] -> IO (Either (Failure cause) ())
awaitDeliveries run sources = case runFrame run of
  Nothing -> pure (Right ())
  Just frame -> go [deliver | source <- sources, Just deliver <- [frameDelivery frame source]]
  where
    go [] = pure (Right ())
    go (deliver : rest) = do
      outcome <- deliver
      case outcome of
        Left (Left exception) -> throwIO exception
        Left (Right problem) -> pure (Left problem)
        Right _ -> go rest

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
      single execution = pure (Compiled execution [(location, execution)])
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
      entry <- resolve entries (chainTerminal chain)
      subscribed <- mapM producerOf [asset | (_, described) <- workflowLifelongs (protoWorkflow prototype)
        , (mounted, asset) <- lifelongSubscriptions described, mounted == location]
      single $ \run handoff -> ExceptT $ supervised run $ do
        ready <- awaitDeliveries run subscribed
        case ready of
          Left problem -> pure (Left problem)
          Right () -> fmap (: []) . fst <$> lowerTarget store location (runFrame run) handoff entry
    (Chained _, _) -> do
      parts <- map compiledRun <$> compiledChildren
      single (\run handoff -> concat <$> sequence [part run handoff | part <- parts])
    (Parallel _, _) -> do
      parts <- map compiledRun <$> compiledChildren
      let execution run handoff = ExceptT $ do
            outcomes <- runParalleled [runExceptT (part run handoff) | part <- parts]
            pure (concat <$> sequence outcomes)
      pure (Compiled execution (zip (map workflowNode expectedChildren) parts))
    (Alternative _, AlternativeAt _ description _) -> do
      parts <- map compiledRun <$> compiledChildren
      chain <- lookupChain prototype (alternativeSelector description)
      unless (chainRole chain == SelectorChain
          && chainTerminal chain == alternativeContract description) $
        Left (InvalidAlternative location "Selector chain differs from its alternative")
      selector <- resolve selectors (chainTerminal chain)
      source <- producerOf (alternativeContract description)
      constructors <- mapM (constructorAt description . workflowNode) expectedChildren
      let candidates = zip constructors parts
      -- 转折资产是本 lifelong 的会话资产时，选择读取先领取本次交付，候选共享这次领取。
      single $ \run handoff -> ExceptT $ do
        chosen <- supervised run $ do
          ready <- awaitDeliveries run [source]
          case ready of
            Left problem -> pure (Left problem)
            Right () -> do
              (selected, captured) <- lowerTarget store (alternativeSelector description) (runFrame run) handoff selector
              pure (fmap (\constructor -> (constructor, captured)) selected)
        case chosen of
          Left problem -> pure (Left problem)
          Right (constructor, captured) -> case lookup constructor candidates of
            Just candidate -> runExceptT (candidate run captured)
            Nothing -> ioError (userError ("No alternative candidate for case " ++ constructor
              ++ "; regenerate with the SDK effect-codegen command"))
    -- 进入 lifelong 时取得本边界的会话（按需启动生产），各单元并发、互不等待地重复执行；
    -- lifelong 没有正常结束，只会随失败或取消退出。
    (Lifelong _, LifelongAt _ description _) -> do
      units <- concatMap compiledUnits <$> compiledChildren
      sources <- mapM (producerOf . sessionAsset) (lifelongSessions description)
      single $ \run handoff -> ExceptT $ do
        sessions <- mapM (\source -> (,) source <$> boundarySession store location source handoff) sources
        outcomes <- runParalleled [repeatUnit run handoff sessions unit | unit <- units]
        pure (concat <$> sequence outcomes)
    _ -> Left PrototypeWorkflowMismatch
  where
    resolve compiled selected =
      maybe (Left (UnknownPrototypeTarget selected)) Right (lookup selected compiled)
    constructorAt description location =
      maybe (Left (InvalidAlternative location "Missing candidate constructor")) Right
        (lookup location (alternativeCases description))
    -- 运行时以生产该资产的 Context 注册名识别绑定来源与会话。
    producerOf asset = case [effectName effect | effect <- protoEffects prototype, effectProduces effect == Just asset] of
      [source] -> Right source
      _ -> Left (UnknownPrototypeTarget asset)
    -- 单元的游标属于（单元，会话），进入 lifelong 时从会话首条开始。
    -- 每次执行是新的 frame：先移出该单元上一次执行的 Origin，执行结果不累积；
    -- 同一单元逐次处理，本次结束后才领取下一条。
    repeatUnit run handoff sessions (unit, execute) = do
      cursors <- mapM (\(source, session) -> (,) source . (,) session <$> newCursor) sessions
      let loop = do
            resetOrigins store unit
            frame <- newFrame cursors
            outcome <- runExceptT (execute run { runFrame = Just frame } handoff)
            case outcome of
              Left problem -> pure (Left problem)
              Right _ -> loop
      loop

-- Prototype 已在 SDK 入口完整求值并校验；这里一次 fold 核对当前 AST 并装配全部入口。
-- 所有 Either 分支完成后才安装独立 ScopeTree 的关系、执行业务。
-- 两类 boot、资产和实例使用共享 RuntimeGraph；方法体仍由已装配的闭包执行。
-- 生产会话按需启动；AST 结束（或被取消）后先取消全部会话并等待其步骤收尾，再交给 interpreter 的退出清理。
runStructuredAST
  :: (Eq method, Show method)
  => Prototype method -> AST
  -> [Target environment cause value]
  -> [Target environment cause String]
  -> [(String, SessionSteps environment cause)]
  -> IO (Output cause [value])
runStructuredAST prototype tree entries selectors sessions = do
  store <- newRuntimeGraph prototype (scopeHandlers entries)
  prepared <- either (ioError . userError . show) pure $
    foldAST (executionAlgebra prototype store compiled readers) tree (protoWorkflow prototype)
  configureRuntimeScopes store
  if null (workflowLifelongs (protoWorkflow prototype))
    then do
      installSessionLauncher store (sessionLauncher store sessions (const (pure ())))
      (either Failed Succ <$> runExceptT (compiledRun prepared (Run Nothing (const (pure ()))) noHandoff))
        `finally` stopSessions store
    else do
      -- 第一个失败或原生异常结束整次运行：取消 AST 中的全部任务并等待其收尾，再停止会话，
      -- 最后以最初的那个失败报告；AST 未进入 lifelong 而正常结束时照常返回。
      settled <- newEmptyMVar
      let settle = void . tryPutMVar settled
          run = Run Nothing (settle . Left)
          work = do
            outcome <- try (runExceptT (compiledRun prepared run noHandoff))
            settle (either (Left . Left) Right outcome)
      installSessionLauncher store (sessionLauncher store sessions (settle . Left))
      result <- withWorkers [work] (const (readMVar settled)) `finally` stopSessions store
      case result of
        Left (Left exception) -> throwIO exception
        Left (Right problem) -> pure (Failed problem)
        Right (Left problem) -> pure (Failed problem)
        Right (Right values) -> pure (Succ values)
  where
    compiled = [(targetName entry, entry) | entry <- entries]
    readers = [(targetName entry, entry) | entry <- selectors]
