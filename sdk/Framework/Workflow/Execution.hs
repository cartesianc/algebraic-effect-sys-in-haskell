
-- Node 只 lower 末端句柄；branch 组合其执行函数。
module Framework.Workflow.Execution (runAST) where

import Framework.Effect.Contract (Failure, Output(..))
import Framework.Effect.Runtime (Target, targetName, lowerTarget)
import Framework.Recursion (Algebra, cata)
import Framework.Workflow.AST (AST, WorkflowF(..))
import Control.Concurrent (MVar, ThreadId, forkIOWithUnmask, killThread, newEmptyMVar, putMVar, readMVar)
import Control.Exception (SomeException, bracket, throwIO, try)
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
    stop (thread, finished) = do
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
  :: [Target IO environment cause value]
  -> Algebra WorkflowF (Either String (Execution cause value))
executionAlgebra entries (Node selected) = case lookup selected [(targetName entry, entry) | entry <- entries] of
  Nothing -> Left ("No compiled entry for effect: " ++ selected ++ "; regenerate with the SDK effect-codegen command")
  Just entry -> Right ((: []) <$> ExceptT (lowerTarget entry))
executionAlgebra _ (Chained children) = do
  actions <- sequence children
  pure (concat <$> sequence actions)
executionAlgebra _ (Parallel children) = do
  actions <- sequence children
  pure $ ExceptT $ do
    outcomes <- runParalleled (map runExceptT actions)
    pure (concat <$> sequence outcomes)

-- target 内部与 AST 均传播原始 Failure，只有最终边界包装 Output。
-- chained 失败即停止；parallel 等待全部子分支，按声明顺序取首个失败或汇总产物。
runAST
  :: AST -> [Target IO environment cause value]
  -> IO (Output cause [value])
runAST tree entries = do
  action <- either (ioError . userError) pure (cata (executionAlgebra entries) tree)
  either Failed Succ <$> runExceptT action
