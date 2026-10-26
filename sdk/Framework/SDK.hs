{-# LANGUAGE DuplicateRecordFields #-}

-- Demo 的统一入口；Effect、recursion scheme、workflow 与代码生成分别实现。
module Framework.SDK
  ( module Framework.Effect
  , module Framework.Effect.Graph
  , module Framework.Workflow.Structure
  , AST, EffectNode, node, chained, parallel, interpreter
  , Generic, NFData, runDemo, runDemoIO
  ) where

import Framework.Effect
import Framework.Effect.Graph
import Framework.Effect.Runtime (cleanupTargets)
import Framework.Workflow.AST (AST, EffectNode, node, chained, parallel)
import Framework.Workflow.Execution (runInitializedAST)
import Framework.Workflow.Structure
import Control.DeepSeq (NFData, force)
import Control.Exception (SomeException, evaluate, mask, throwIO, try)
import Control.Monad (unless, void)
import GHC.Fingerprint (fingerprintString)
import GHC.Generics (Generic)
import System.Environment (getArgs)
import System.FilePath ((</>), pathSeparator)
import System.IO (IOMode(ReadMode), hGetContents, hPrint, hSetEncoding, hSetNewlineMode, stderr, stdout, universalNewlineMode, utf8, withFile)
import System.IO.Error (tryIOError)
import System.Process (callProcess)

-- 生成的 facade 绑定编译期注册与末端方法，用户只传 ast 和 effects。
-- Node 只登记末端句柄；algebra lower 后才具备具体执行入口。
interpreter
  :: (Show cause, Show value, Show method, Eq method, NFData method)
  => String
  -> [EffectSpec] -> Maybe String
  -> (AST -> Either (StructureError method) (ProgramStructure method))
  -> IO [Target IO environment cause value] -> AST -> [EffectSpec] -> IO ()
interpreter namespace registered sourceFingerprint initialize createEntries tree specifications = do
  hSetEncoding stdout utf8
  arguments <- getArgs
  case arguments of
    []
      | specifications /= registered ->
          staleGenerated "workflow" namespace "Registrations changed"
      | otherwise -> do
          verifyHandlerSource "workflow" namespace sourceFingerprint
          structure <- initializeBeforeBusiness
          entries <- createEntries
          mask $ \restore -> do
            completed <- tryAny $ restore $ do
              output <- runInitializedAST structure entries
              let rendered = show output
              -- 各 Node 已在释放使用前消费自己的结果；这里完成汇总错误的显示。
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
                  exception : _ -> do
                    report result
                    throwIO exception
                  [] -> restore $ if null failures then putStrLn rendered else print result
    ["--generate"] -> generate "workflow" namespace
    ["--structure"]
      | specifications /= registered -> staleRegistrations
      | otherwise -> do
          verifyHandlerSource "workflow" namespace sourceFingerprint
          initializeBeforeBusiness >>= putStr . renderStructure
    _ -> ioError (userError "Usage: demo [--generate|--structure]")
  where
    staleRegistrations = ioError (userError
      ("Registrations changed; run: cabal run effect-codegen -- workflow " ++ namespace))
    initializeBeforeBusiness = do
      result <- evaluate (force (initialize tree))
      either (ioError . userError . ("Cannot initialize effect structure: " ++) . show) pure result

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

-- 命令行处理属于 SDK，facade 只传入自己的声明和结果。
runDemo :: Show value => String -> [EffectSpec] -> String -> Maybe String
        -> [EffectSpec] -> String -> value -> IO ()
runDemo namespace registered registeredTarget sourceFingerprint specifications selected result =
  runDemoIO namespace registered registeredTarget sourceFingerprint specifications selected (pure result)

-- --generate 只生成源码，不执行传入的 IO 动作。
runDemoIO :: Show value => String -> [EffectSpec] -> String -> Maybe String
          -> [EffectSpec] -> String -> IO value -> IO ()
runDemoIO namespace registered registeredTarget sourceFingerprint specifications selected action = do
  hSetEncoding stdout utf8
  arguments <- getArgs
  case arguments of
    [] -> do
      unless (specifications == registered && selected == registeredTarget) $
        staleGenerated "target" namespace "Registrations or target changed"
      verifyHandlerSource "target" namespace sourceFingerprint
      action >>= print
    ["--generate"] -> generate "target" namespace
    _ -> ioError (userError "Usage: demo [--generate]")

-- 与生成时使用相同的 UTF-8 和换行读取方式；比对源码与本编译副本保存的指纹。
verifyHandlerSource :: String -> String -> Maybe String -> IO ()
verifyHandlerSource mode namespace expected = do
  let path = "demo" </> map (\character -> if character == '.' then pathSeparator else character) namespace </> "Handlers.hs"
  actual <- tryIOError $ withFile path ReadMode $ \handle -> do
    hSetEncoding handle utf8
    hSetNewlineMode handle universalNewlineMode
    source <- hGetContents handle
    _ <- evaluate (length source)
    pure (show (fingerprintString source))
  case actual of
    Right fingerprint | expected == Just fingerprint -> pure ()
    Right _ -> staleGenerated mode namespace (path ++ " changed or has not been generated")
    Left problem -> staleGenerated mode namespace ("Cannot verify " ++ path ++ ": " ++ show problem)

staleGenerated :: String -> String -> String -> IO value
staleGenerated mode namespace reason = ioError (userError
  (reason ++ "; run from the repository root: cabal run effect-codegen -- " ++ mode ++ " " ++ namespace))

-- 统一经过 SDK 生成命令；业务运行载体不依赖 GHC 的源码解析 API。
generate :: String -> String -> IO ()
generate mode namespace = callProcess "cabal" ["run", "effect-codegen", "--", mode, namespace]
