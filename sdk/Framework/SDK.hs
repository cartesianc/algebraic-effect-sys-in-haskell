{-# LANGUAGE DuplicateRecordFields #-}

-- Demo 的统一入口；Effect、recursion scheme、workflow 与代码生成分别实现。
module Framework.SDK
  ( module Framework.Effect
  , AST, EffectNode, node, chained, parallel, interpreter
  , Generic, runDemo, runDemoIO
  ) where

import Framework.Effect
import Framework.Workflow.AST (AST, EffectNode, node, chained, parallel)
import Framework.Workflow.Execution (runAST)
import Control.Exception (evaluate)
import Control.Monad (unless)
import GHC.Fingerprint (fingerprintString)
import GHC.Generics (Generic)
import System.Environment (getArgs)
import System.FilePath ((</>), pathSeparator)
import System.IO (IOMode(ReadMode), hGetContents, hSetEncoding, hSetNewlineMode, stdout, universalNewlineMode, utf8, withFile)
import System.IO.Error (tryIOError)
import System.Process (callProcess)

-- 生成的 facade 绑定编译期注册与末端方法，用户只传 ast 和 effects。
-- Node 只登记末端句柄；algebra lower 后才具备具体执行入口。
interpreter
  :: (Show cause, Show value)
  => String
  -> [EffectSpec] -> Maybe String -> IO [Target IO environment cause value] -> AST -> [EffectSpec] -> IO ()
interpreter namespace registered sourceFingerprint createEntries tree specifications = do
  hSetEncoding stdout utf8
  arguments <- getArgs
  case arguments of
    []
      | specifications /= registered ->
          staleGenerated "workflow" namespace "Registrations changed"
      | otherwise -> do
          verifyHandlerSource "workflow" namespace sourceFingerprint
          entries <- createEntries
          runAST tree entries >>= print
    ["--generate"] -> generate "workflow" namespace
    _ -> ioError (userError "Usage: crawler-demo [--generate]")

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
