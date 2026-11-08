-- 已生成程序的执行边界：强制并校验 Prototype，执行 workflow，最后收尾资源。
-- 不读取命令行、源码文件或项目目录；这些适配属于 Framework.Generated。
-- Workflow.Execution 先停止并等待受管理任务，再返回到这里做 scope 退出兜底。
module Framework.Program (initializePrototype, runProgram) where

import Framework.Language.Handler (Failure(..), Output(..))
import Framework.Runtime (Target, SessionSteps, cleanupTargets)
import Framework.Prototype (Prototype, validatePrototype)
import Framework.Language.AST (AST)
import Framework.Runtime.Execution (runStructuredAST)
import Control.DeepSeq (NFData, force)
import Control.Exception (SomeException, evaluate, mask, throwIO, try)
import Control.Monad (unless, void)
import System.IO (hPrint, stderr)

-- 生成结果与 --structure 共用的初始化；不运行 handler 或预生产 Context。
initializePrototype :: (Ord method, Show method, NFData method)
                    => Prototype method -> IO (Prototype method)
initializePrototype generated = do
  prototype <- evaluate (force generated)
  either (ioError . userError . ("Cannot initialize effect prototype: " ++) . show) pure
    (validatePrototype prototype)
  pure prototype

-- Target 创建只分配空控制对象；原型通过后才创建，业务只在 AST 装配完成后开始。
-- 主执行及其受控结果消费受到退出清理保护；清理失败不覆盖原始业务故障或异常。
runProgram
  :: (Show cause, Show value, Show method, Ord method, NFData method)
  => Prototype method
  -> IO ([Target environment cause value], [Target environment cause String], [(String, SessionSteps environment cause)])
  -> AST -> IO (Output cause [value], String)
runProgram generated createEntries tree = do
  prototype <- initializePrototype generated
  (entries, selectors, sessions) <- createEntries
  mask $ \restore -> do
    completed <- tryAny $ restore $ do
      output <- runStructuredAST prototype tree entries selectors sessions
      -- Node 已在撤销使用前消费自己的结果；这里保留并强制汇总文本，
      -- 正常打印直接复用，不能在资源释放后重新调用业务值的 Show。
      let rendered = show output
      evaluate (foldr seq () rendered)
      pure (output, rendered)
    failures <- cleanupTargets entries
    case completed of
      Left exception -> do
        unless (null failures) (report (map snd failures))
        throwIO exception
      Right (output, rendered) -> do
        let result = appendCleanup (map snd failures) output
        case [exception | (Just exception, _) <- failures] of
          exception : _ -> report result >> throwIO exception
          -- 有清理故障时按原协议显示合并结果；正常路径保留收尾前的文本。
          [] -> pure (result, if null failures then rendered else show result)

-- 保留原始业务故障；主执行成功时，首个清理故障成为完成失败。
appendCleanup :: [Failure cause] -> Output cause value -> Output cause value
appendCleanup [] output = output
appendCleanup failures (Failed original) =
  Failed (original { cleanupFailures = cleanupFailures original ++ failures })
appendCleanup (first : rest) (Succ _) =
  Failed (first { cleanupFailures = cleanupFailures first ++ rest })

tryAny :: IO value -> IO (Either SomeException value)
tryAny = try

-- 报告失败不能覆盖已经选定的主异常或取消异常。
report :: Show value => value -> IO ()
report = void . tryAny . hPrint stderr
