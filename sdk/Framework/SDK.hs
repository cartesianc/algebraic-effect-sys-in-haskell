{-# LANGUAGE DuplicateRecordFields #-}

-- Demo 的统一入口；Effect、recursion scheme、workflow 与代码生成分别实现。
module Framework.SDK
  ( module Framework.Effect
  , AST, node, chained, parallel, interpreter
  , Generic, runDemo, runDemoIO
  ) where

import Framework.Effect
import Framework.Workflow.AST (AST, node, chained, parallel)
import Framework.Workflow.Execution (runAST)
import GHC.Generics (Generic)
import System.Environment (getArgs)
import System.IO (hSetEncoding, stdout, utf8)
import System.Process (callProcess)

-- 生成的 facade 绑定编译期注册与末端方法，用户只传 ast 和 effects。
-- Node 只登记末端句柄；algebra lower 后才具备具体执行入口。
interpreter
  :: (Show cause, Show value)
  => String
  -> [EffectSpec] -> IO [Target IO environment cause value] -> AST -> [EffectSpec] -> IO ()
interpreter namespace registered createEntries tree specifications = do
  hSetEncoding stdout utf8
  arguments <- getArgs
  case arguments of
    []
      | specifications /= registered ->
          ioError (userError ("Registrations changed; run: cabal run effect-codegen -- workflow " ++ namespace))
      | otherwise -> do
          entries <- createEntries
          runAST tree entries >>= print
    ["--generate"] -> generate "workflow" namespace
    _ -> ioError (userError "Usage: crawler-demo [--generate]")

-- 命令行处理属于 SDK，facade 只传入自己的声明和结果。
runDemo :: Show value => String -> [EffectSpec] -> String -> value -> IO ()
runDemo namespace specifications selected result =
  runDemoIO namespace specifications selected (pure result)

-- --generate 只生成源码，不执行传入的 IO 动作。
runDemoIO :: Show value => String -> [EffectSpec] -> String -> IO value -> IO ()
runDemoIO namespace specifications selected action = do
  hSetEncoding stdout utf8
  arguments <- getArgs
  case arguments of
    [] -> action >>= print
    ["--generate"] -> generate "target" namespace
    _ -> ioError (userError "Usage: demo [--generate]")

-- 统一经过 SDK 生成命令；业务运行载体不依赖 GHC 的源码解析 API。
generate :: String -> String -> IO ()
generate mode namespace = callProcess "cabal" ["run", "effect-codegen", "--", mode, namespace]
