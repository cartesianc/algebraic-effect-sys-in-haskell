
-- Node 只 lower 末端句柄；branch 组合其执行函数。
module Framework.Workflow.Execution (runAST, runStructuredAST) where

import Framework.Effect.Contract (Failure, Output(..))
import Framework.Effect.Runtime (Target, RunStore, newRunStore, targetName, lowerTargetIn, configureTargets)
import Framework.Recursion (Algebra)
import Framework.Workflow.AST (AST, WorkflowF(..), foldAST)
import Framework.Workflow.Structure (ProgramStructure(..), StructureError(..), scopeRelations, validateWorkflowEntries)
import Control.Concurrent (MVar, ThreadId, forkIOWithUnmask, killThread, newEmptyMVar, putMVar, readMVar)
import Control.Exception (SomeException, bracket, throwIO, try, uninterruptibleMask_)
import Control.Monad (void)
import Control.Monad.Except (ExceptT(..), runExceptT)

type Execution cause value = ExceptT (Failure cause) IO [value]

type Worker value = (ThreadId, MVar (Either SomeException value))

-- base 线程负责并发；父执行退出时取消并等待子线程清理。
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
    -- 取消期间再次收到取消也必须等到子线程真正退出，才能进入外层资源收尾。
    -- 只保护 cancel/join，不屏蔽业务动作本身的取消。
    stop (thread, finished) = uninterruptibleMask_ $ do
      killThread thread
      void (readMVar finished)

runParalleled :: [IO value] -> IO [value]
runParalleled actions = withWorkers actions $ \workers -> do
  outcomes <- mapM (readMVar . snd) workers
  either throwIO pure (sequence outcomes)

-- fold 得到尚未执行的动作，父分支控制何时启动子动作。
-- 先解析全部 Node 引用；装配失败时不执行任何业务动作。
-- 不预先生产 Context，也不在外部补出 Input 链。
executionAlgebra
  :: RunStore environment cause
  -> (String -> Either problem (method, Target IO environment cause value))
  -> Algebra WorkflowF (Either problem ([method], Execution cause value))
executionAlgebra store resolve (Node selected) = do
  (method, entry) <- resolve selected
  pure ([method], (: []) <$> ExceptT (lowerTargetIn store entry))
executionAlgebra _ _ (Chained children) = do
  parts <- sequence children
  pure (concatMap fst parts, concat <$> sequence (map snd parts))
executionAlgebra _ _ (Parallel children) = do
  parts <- sequence children
  pure (concatMap fst parts, ExceptT $ do
    outcomes <- runParalleled (map (runExceptT . snd) parts)
    pure (concat <$> sequence outcomes))

-- target 内部与 AST 均传播原始 Failure，只有最终边界包装 Output。
-- chained 失败即停止；parallel 等待全部子分支，按声明顺序取首个失败或汇总产物。
runAST
  :: AST -> [Target IO environment cause value]
  -> IO (Output cause [value])
runAST tree entries = do
  -- 一次运行共享一份资产 state；各 Node 的 require 可读取先前 Node 产出的资产。
  store <- newRunStore
  (_, action) <- either (ioError . userError) pure (foldAST (executionAlgebra store resolve) tree)
  configureTargets [] entries
  either Failed Succ <$> runExceptT action
  where
    compiled = [(targetName entry, entry) | entry <- entries]
    resolve selected = case lookup selected compiled of
      Nothing -> Left ("No compiled entry for effect: " ++ selected ++ "; regenerate with the SDK effect-codegen command")
      Just entry -> Right ((), entry)

-- 一次 AST fold 同时解析 Node、收集入口和装配动作，不创建初始化中间树。
-- Either 在进入 IO action 前检查全部分支及入口集合；闭包中的业务值保持惰性。
-- 同一份 ScopeTree 的祖先关系同时用于实例回收和 Error 导航，不重排业务。
runStructuredAST
  :: (Ord method, Show method) => ProgramStructure method
  -> AST
  -> [Target IO environment cause value]
  -> IO (Output cause [value])
runStructuredAST structure tree entries = do
  store <- newRunStore
  action <- either (ioError . userError . show) pure $ do
    (roots, prepared) <- foldAST (executionAlgebra store resolve) tree
    validateWorkflowEntries structure roots
    pure prepared
  configureTargets (scopeRelations structure) entries
  either Failed Succ <$> runExceptT action
  where
    compiled = [(targetName entry, entry) | entry <- entries]
    resolve selected = case (lookup selected (structureEntries structure), lookup selected compiled) of
      (Just method, Just entry) -> Right (method, entry)
      _ -> Left (UnknownStructureTarget selected)
