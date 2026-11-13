-- 已生成程序的执行边界：强制并校验 Prototype，执行 workflow，最后收尾资源。
-- 不读取命令行、源码文件或项目目录；这些适配属于 Framework.Generated。
-- Execution 先停止受管理任务并撤销执行帧，再沿统一可达性规则回收；这里报告关闭故障。
module Framework.Program (initializePrototype, runProgram) where

import Framework.Language.Handler (Output)
import Framework.Runtime (Target, SessionSteps, cleanupTargets)
import Framework.Prototype (Prototype, validatePrototype)
import Framework.Language.AST (AST)
import Framework.Runtime.Execution (runStructuredAST)
import Control.DeepSeq (NFData, force)
import Control.Exception (SomeAsyncException, SomeException, evaluate, fromException, mask, throwIO, try)
import Control.Monad (unless)
import Data.Maybe (isJust)
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
    reported <- tryAny $ unless (null failures) (hPrint stderr (map snd failures))
    -- 普通报告故障不盖过业务结果；取消无论发生在执行、关闭或报告中都须传播。
    let exceptions = either (: []) (const []) completed
          ++ [exception | (Just exception, _) <- failures]
          ++ [exception | Left exception <- [reported], isCancellation exception]
    case filter isCancellation exceptions ++ exceptions of
      exception : _ -> throwIO exception
      [] -> either throwIO pure completed

tryAny :: IO value -> IO (Either SomeException value)
tryAny = try

isCancellation :: SomeException -> Bool
isCancellation exception = isJust (fromException exception :: Maybe SomeAsyncException)
