
-- Node 只 lower 末端句柄；branch 组合其执行函数。
module Framework.Workflow.Execution (runStructuredAST) where

import Framework.Effect.Contract (Failure, Output(..))
import Framework.Effect.Runtime (Target, RunStore, newRunStore, targetName, lowerTarget, configureTargets)
import Framework.Recursion (Algebra)
import Framework.Workflow.AST (AST, WorkflowF(..), foldAST)
import Framework.Workflow.Structure (ProgramStructure(..), StructureError(..), scopeRelations, validateWorkflowEntries)
import Control.Concurrent (MVar, ThreadId, forkIOWithUnmask, killThread, newEmptyMVar, putMVar, readMVar)
import Control.Exception (SomeException, bracket, throwIO, try, uninterruptibleMask_)
import Control.Monad (void)
import Control.Monad.Except (ExceptT(..), runExceptT)
import Data.List (nub)

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

-- 装配结果：子树中的 Node 名、入口方法身份与尚未执行的动作。
data Prepared method cause value = Prepared [String] [method] (Execution cause value)

-- fold 得到尚未执行的动作，父分支控制何时启动子动作。
-- 先解析全部 Node 引用；装配失败时不执行任何业务动作。
-- 不预先生产 Context，也不在外部补出 Input 链；运行时不保存或重组 effect chain，
-- 只在已装配的闭包之间按 Haskell 逻辑选择启动哪一个。
executionAlgebra
  :: RunStore environment cause
  -> (String -> Either problem (method, Target environment cause value))
  -> ([String] -> Either problem (Target environment cause String, String))
  -> Algebra WorkflowF (Either problem (Prepared method cause value))
executionAlgebra store resolve _ (Node selected) = do
  (method, entry) <- resolve selected
  pure (Prepared [selected] [method] ((: []) <$> ExceptT (lowerTarget store entry)))
executionAlgebra _ _ _ (Chained children) = do
  parts <- sequence children
  pure (Prepared (concatMap names parts) (concatMap methods parts) (concat <$> sequence (map action parts)))
executionAlgebra _ _ _ (Parallel children) = do
  parts <- sequence children
  pure (Prepared (concatMap names parts) (concatMap methods parts) $ ExceptT $ do
    outcomes <- runParalleled (map (runExceptT . action) parts)
    pure (concat <$> sequence outcomes))
-- 两段启动：先运行转折资产的读取末端（require：state 中已有值直接用，否则按需求值一次），
-- 得到它当前的构造器；再启动对应的候选。未选中的候选不执行，也不出现在结果中。
executionAlgebra store _ caseOf (Alternative children) = do
  parts <- sequence children
  cases <- mapM (caseOf . names) parts
  let candidates = [(constructor, action part) | ((_, constructor), part) <- zip cases parts]
  selector <- case cases of
    (target, _) : _ -> pure target
    [] -> fst <$> caseOf []
  pure (Prepared (concatMap names parts) (concatMap methods parts) $ ExceptT $ do
    selected <- lowerTarget store selector
    case selected of
      Left problem -> pure (Left problem)
      Right constructor -> case lookup constructor candidates of
        Just chosen -> runExceptT chosen
        Nothing -> ioError (userError ("No alternative candidate for case " ++ constructor
          ++ "; regenerate with the SDK effect-codegen command")))

names :: Prepared method cause value -> [String]
names (Prepared selected _ _) = selected

methods :: Prepared method cause value -> [method]
methods (Prepared _ selected _) = selected

action :: Prepared method cause value -> Execution cause value
action (Prepared _ _ prepared) = prepared

-- 末端内部与 AST 均传播原始 Failure，只有最终边界包装 Output。
-- chained 失败即停止；parallel 等待全部子分支，按声明顺序取首个失败或汇总产物。
-- 一次运行共享一份资产 state；各 Node 的 require 可读取先前 Node 产出的资产。
-- 一次 AST fold 同时解析 Node、收集入口和装配动作，不创建初始化中间树。
-- Either 在进入 IO action 前检查全部分支及入口集合；闭包中的业务值保持惰性。
-- 同一份 ScopeTree 的祖先关系同时用于实例回收和 Error 导航，不重排业务。
-- alternativeCases 是 gencode 写定的静态表：候选末端 → (转折契约, 构造器)；
-- selectors 是各转折契约的读取末端，返回资产当前的构造器名。
runStructuredAST
  :: (Ord method, Show method) => ProgramStructure method
  -> [(String, (String, String))]
  -> AST
  -> [Target environment cause value]
  -> [Target environment cause String]
  -> IO (Output cause [value])
runStructuredAST structure alternativeCases tree entries selectors = do
  store <- newRunStore
  prepared <- either (ioError . userError . show) pure $ do
    Prepared _ roots prepared <- foldAST (executionAlgebra store resolve caseOf) tree
    validateWorkflowEntries structure roots
    pure prepared
  configureTargets (scopeRelations structure) entries
  either Failed Succ <$> runExceptT prepared
  where
    compiled = [(targetName entry, entry) | entry <- entries]
    resolve selected = case (lookup selected (structureEntries structure), lookup selected compiled) of
      (Just method, Just entry) -> Right (method, entry)
      _ -> Left (UnknownStructureTarget selected)
    -- 一个候选的全部末端须登记同一分支；gencode 已检查，这里只拒绝过期的生成结果。
    caseOf selected = case nub [lookup terminal alternativeCases | terminal <- selected] of
      [Just (contract, constructor)] -> case [target | target <- selectors, targetName target == contract] of
        target : _ -> Right (target, constructor)
        [] -> Left (InvalidAlternative selected)
      _ -> Left (InvalidAlternative selected)
