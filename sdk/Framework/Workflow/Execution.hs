-- Node 按原型中的挂载位置 lower 末端句柄；branch 组合执行闭包。
module Framework.Workflow.Execution (runStructuredAST) where

import Framework.Effect.Contract (Failure, Output(..))
import Framework.Effect.Runtime (Target, Handoff, noHandoff, targetName, lowerTarget, scopeHandlers)
import Framework.Effect.Runtime.Graph (RuntimeGraph, newRuntimeGraph, configureRuntimeScopes)
import Framework.Prototype
import Framework.Recursion (Algebra)
import Framework.Workflow.AST (AST, WorkflowF(..), foldAST)
import Control.Concurrent (MVar, ThreadId, forkIOWithUnmask, killThread, newEmptyMVar, putMVar, readMVar)
import Control.Exception (SomeException, bracket, throwIO, try, uninterruptibleMask_)
import Control.Monad (unless, void)
import Control.Monad.Except (ExceptT(..), runExceptT)

-- Handoff 是已经捕获的绑定；alternative 的候选承接选择阶段的同一份值。
type Execution environment cause value = Handoff environment cause -> ExceptT (Failure cause) IO [value]
type Prepared method environment cause value =
  WorkflowTree -> Either (PrototypeError method) (Execution environment cause value)

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
  case (layer, expected) of
    (Node selected, NodeAt location _) -> do
      chain <- lookupChain prototype location
      unless (chainRole chain == NodeChain && chainTerminal chain == selected) $
        Left (InvalidPrototype ("Node chain differs at " ++ show location))
      entry <- resolve entries (chainTerminal chain)
      pure (\handoff -> (: []) <$> ExceptT (fst <$> lowerTarget store location handoff entry))
    (Chained children, _) -> do
      parts <- sequence (zipWith ($) children expectedChildren)
      pure (\handoff -> concat <$> sequence [part handoff | part <- parts])
    (Parallel children, _) -> do
      parts <- sequence (zipWith ($) children expectedChildren)
      pure $ \handoff -> ExceptT $ do
        outcomes <- runParalleled [runExceptT (part handoff) | part <- parts]
        pure (concat <$> sequence outcomes)
    (Alternative children, AlternativeAt location description _) -> do
      parts <- sequence (zipWith ($) children expectedChildren)
      chain <- lookupChain prototype (alternativeSelector description)
      unless (chainRole chain == SelectorChain
          && chainTerminal chain == alternativeContract description) $
        Left (InvalidAlternative location "Selector chain differs from its alternative")
      selector <- resolve selectors (chainTerminal chain)
      constructors <- mapM (constructorAt description . workflowNode) expectedChildren
      let candidates = zip constructors parts
      pure $ \handoff -> ExceptT $ do
        (selected, captured) <- lowerTarget store (alternativeSelector description) handoff selector
        case selected of
          Left problem -> pure (Left problem)
          Right constructor -> case lookup constructor candidates of
            Just chosen -> runExceptT (chosen captured)
            Nothing -> ioError (userError ("No alternative candidate for case " ++ constructor
              ++ "; regenerate with the SDK effect-codegen command"))
    _ -> Left PrototypeWorkflowMismatch
  where
    resolve compiled selected =
      maybe (Left (UnknownPrototypeTarget selected)) Right (lookup selected compiled)
    constructorAt description location =
      maybe (Left (InvalidAlternative location "Missing candidate constructor")) Right
        (lookup location (alternativeCases description))

-- Prototype 已在 SDK 入口完整求值并校验；这里一次 fold 核对当前 AST 并装配全部入口。
-- 所有 Either 分支完成后才安装独立 ScopeTree 的关系、执行业务。
-- 两类 boot、资产和实例使用共享 RuntimeGraph；方法体仍由已装配的闭包执行。
runStructuredAST
  :: (Eq method, Show method)
  => Prototype method -> AST
  -> [Target environment cause value]
  -> [Target environment cause String]
  -> IO (Output cause [value])
runStructuredAST prototype tree entries selectors = do
  store <- newRuntimeGraph prototype (scopeHandlers entries)
  prepared <- either (ioError . userError . show) pure $
    foldAST (executionAlgebra prototype store compiled readers) tree (protoWorkflow prototype)
  configureRuntimeScopes store
  either Failed Succ <$> runExceptT (prepared noHandoff)
  where
    compiled = [(targetName entry, entry) | entry <- entries]
    readers = [(targetName entry, entry) | entry <- selectors]
