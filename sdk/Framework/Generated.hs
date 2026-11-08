{-# LANGUAGE DuplicateRecordFields #-}

-- 生成代码专用入口。业务声明、Handlers 和 Workflow 只需 Framework.SDK。
-- 本模块集中导出生成包装需要的原型、访问协议和生命周期装配操作，
-- 并适配可执行程序的运行／生成／结构查看命令；真正执行交给 Framework.Program。
module Framework.Generated
  ( module Framework.SDK
  , module Framework.Prototype
  , module Framework.Prototype.Structure
  , App, TypeRef(..)
  , Target, targetApp, SessionSteps, receiveSteps
  , failEffect, handleFailure, withErrorPath, withErrorHandlers, ErrorHandler(..)
  , ContextAccess(..), readContext, latestContext
  , callContext, projectContext, enterHandler, withAnchoredContexts
  , atomicHandle, atomicScope, readHistory, streamHandle
  , ScopeInput(..), openScope, closeScope, withScopeDependencies
  , ScopeHandler, newScopeHandler, withScopeCleanups
  , Generic, NFData, interpreter
  ) where

import Framework.SDK
import Framework.Runtime.Protocol
  ( failEffect, ErrorStore(handleFailure, withErrorPath, withErrorHandlers), ErrorHandler(..)
  , ContextStore(enterHandler, withAnchoredContexts)
  , ScopeInput(..), ScopeStore(openScope, closeScope, withScopeDependencies) )
import Framework.Runtime.Context
  ( ContextAccess(..), readContext, latestContext, callContext
  , projectContext, atomicHandle, atomicScope, readHistory, streamHandle )
import Framework.Language.Registration (TypeRef(..))
import Framework.Runtime (App, Target, targetApp, SessionSteps, receiveSteps)
import Framework.Runtime.App (withScopeCleanups)
import Framework.Runtime.Scope (ScopeHandler, newScopeHandler)
import Framework.Program (initializePrototype, runProgram)
import Framework.Prototype
import Framework.Prototype.Structure
import Control.DeepSeq (NFData)
import Control.Exception (evaluate)
import GHC.Fingerprint (fingerprintString)
import GHC.Generics (Generic)
import System.Environment (getArgs)
import System.IO (IOMode(ReadMode), hGetContents, hSetEncoding, hSetNewlineMode, stdout, universalNewlineMode, utf8, withFile)
import System.IO.Error (tryIOError)
import System.Process (callProcess)

-- Generated.Program 提供 namespace、真实手写源文件路径与编译副本指纹。
-- 路径可以是绝对路径，或相对于启动目录；SDK 不从 namespace 推导 demo 布局。
-- 业务仍只看到已绑定这些参数的 interpreter ast effects。
interpreter
  :: (Show cause, Show value, Show method, Ord method, NFData method)
  => String -> FilePath
  -> Maybe String -> Prototype method
  -> IO ([Target environment cause value], [Target environment cause String], [(String, SessionSteps environment cause)])
  -> AST -> [EffectSpec] -> IO ()
interpreter namespace sourcePath sourceFingerprint prototype createEntries tree specifications = do
  hSetEncoding stdout utf8
  arguments <- getArgs
  case arguments of
    [] -> do
      verifyRegistrations
      verifyHandlerSource namespace sourcePath sourceFingerprint
      (_, rendered) <- runProgram prototype createEntries tree
      putStrLn rendered
    ["--generate"] -> generate namespace
    ["--structure"] -> do
      verifyRegistrations
      verifyHandlerSource namespace sourcePath sourceFingerprint
      initialized <- initializePrototype prototype
      rendered <- either (ioError . userError . show) pure (renderStructure initialized tree)
      putStr rendered
    _ -> ioError (userError "Usage: program [--generate|--structure]")
  where
    verifyRegistrations
      | specifications == protoRegistrations prototype = pure ()
      | otherwise = staleGenerated namespace "Registrations changed"

-- 与生成时使用相同的 UTF-8 和换行读取方式；只校验生成器交来的源文件。
verifyHandlerSource :: String -> FilePath -> Maybe String -> IO ()
verifyHandlerSource namespace path expected = do
  actual <- tryIOError $ withFile path ReadMode $ \handle -> do
    hSetEncoding handle utf8
    hSetNewlineMode handle universalNewlineMode
    source <- hGetContents handle
    _ <- evaluate (length source)
    pure (show (fingerprintString source))
  case actual of
    Right fingerprint | expected == Just fingerprint -> pure ()
    Right _ -> staleGenerated namespace (path ++ " changed or has not been generated")
    Left problem -> staleGenerated namespace ("Cannot verify " ++ path ++ ": " ++ show problem)

staleGenerated :: String -> String -> IO value
staleGenerated namespace reason = ioError (userError
  (reason ++ "; run from the repository root: cabal run effect-codegen -- workflow " ++ namespace))

-- 仓库的生成命令适配；执行核心不启动编译器，也不依赖 GHC 源码解析 API。
generate :: String -> IO ()
generate namespace = callProcess "cabal" ["run", "effect-codegen", "--", "workflow", namespace]
