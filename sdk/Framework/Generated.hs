{-# LANGUAGE DuplicateRecordFields #-}

-- 生成代码专用入口。业务声明、Handlers 和 Workflow 只需 Framework.SDK。
-- 本模块集中导出生成包装需要的原型、访问协议和生命周期装配操作，
-- 并适配可执行程序的运行／生成／结构查看命令；真正执行交给 Framework.Program。
module Framework.Generated
  ( module Framework.SDK
  , module Framework.Prototype
  , module Framework.Prototype.Structure
  , App, TypeRef(..), typeRef, MonadThrow, MonadCatch, MonadMask
  , Target, targetApp, SessionSteps, receiveSteps, behaviorSteps, deriveSteps
  , failEffect, handleFailure, withErrorPath, withErrorHandlers, ErrorHandler(..)
  , readContext, readStreamContext, readStreamHistory, requestStreamContext, unlessDelivered
  , callContext, runOnce, producingFor, chooseCase, enterHandler
  , atomicHandle, atomicScope, emittedInput, emitToParser, endSource, endSubscription
  , openScope, closeScope, withScopeDependencies
  , ScopeHandler, newScopeHandler, Slot(..)
  , Root(..), HandlerError(..), superWith, superClosing, HookApp, runHookApp, liftHookApp, currentOperation
  , Generic, NFData, coerce, interpreter
  ) where

import Framework.SDK
import Framework.Runtime.Protocol
  ( Root(..), HandlerError(..), failEffect, ErrorStore(handleFailure, withErrorPath, withErrorHandlers), ErrorHandler(..)
  , ContextStore(enterHandler, endSource, endSubscription, producingFor)
  , ScopeStore(openScope, closeScope, withScopeDependencies) )
import Framework.Runtime.Context
  ( readContext, readStreamContext, readStreamHistory, requestStreamContext, unlessDelivered, callContext, runOnce
  , chooseCase, atomicHandle, atomicScope )
import Framework.Language.Registration (TypeRef(..), typeRef)
import Framework.Runtime (App, Target, targetApp, SessionSteps, receiveSteps, behaviorSteps, deriveSteps)
import Framework.Runtime.App
  ( emittedInput, emitToParser, superWith, superClosing, HookApp, runHookApp, liftHookApp, currentOperation )
import Framework.Runtime.Scope (ScopeHandler, newScopeHandler)
import Framework.Prototype.Slot (Slot(..))
import Framework.Program (initializePrototype, runProgram)
import Framework.Prototype
import Framework.Prototype.Structure
import Control.DeepSeq (NFData)
import Control.Monad.Catch (MonadThrow, MonadCatch, MonadMask)
import Control.Exception (evaluate)
-- 生成的读取入口用它把资产的名义类型解成表示类型。
import Data.Coerce (coerce)
import GHC.Fingerprint (fingerprintString)
import GHC.Generics (Generic)
import System.Environment (getArgs, lookupEnv)
import System.FilePath (takeDirectory, takeFileName)
import System.IO (BufferMode(LineBuffering), IOMode(ReadMode), hGetContents, hSetBuffering, hSetEncoding, hSetNewlineMode, stdout, universalNewlineMode, utf8, withFile)
import System.IO.Error (isDoesNotExistError, tryIOError)
import System.Process (callProcess)

-- Generated.Program 提供本次生成引用的手写源文件路径与指纹。
-- 路径可以是绝对路径，或相对于启动目录；SDK 不从 namespace 推导 demo 布局。
-- 业务仍只看到已绑定这些参数的 interpreter ast effects。
interpreter
  :: (Show cause, Show value, Show method, Ord method, NFData method)
  => String -> [(FilePath, Maybe String)] -> Prototype method
  -> IO ([Target environment cause value], [Target environment cause String], [(String, SessionSteps environment cause)])
  -> AST -> [EffectSpec] -> IO ()
interpreter namespace sources prototype createEntries tree specifications = do
  hSetEncoding stdout utf8
  streaming <- lookupEnv "EFFECT_CONSOLE_STREAM"
  case streaming of
    Just "1" -> hSetBuffering stdout LineBuffering
    _ -> pure ()
  arguments <- getArgs
  case arguments of
    [] -> do
      verifyInputs
      (_, rendered) <- runProgram prototype createEntries tree
      putStrLn rendered
    ["--generate"] -> generate namespace [file | (file, _) <- sources, takeFileName file == "Handlers.hs"]
    ["--structure"] -> do
      verifyInputs
      initialized <- initializePrototype prototype
      rendered <- either (ioError . userError . show) pure (renderStructure initialized tree)
      putStr rendered
    _ -> ioError (userError "Usage: program [--generate|--structure]")
  where
    verifyInputs
      | specifications == protoRegistrations prototype = mapM_ (uncurry (verifySource namespace)) sources
      | otherwise = staleGenerated namespace "Registrations changed"

-- 与生成时使用相同的 UTF-8 和换行读取方式；只校验生成器交来的源文件。
verifySource :: String -> FilePath -> Maybe String -> IO ()
verifySource namespace path expected = do
  actual <- tryIOError $ withFile path ReadMode $ \handle -> do
    hSetEncoding handle utf8
    hSetNewlineMode handle universalNewlineMode
    source <- hGetContents handle
    _ <- evaluate (length source)
    pure (show (fingerprintString source))
  case actual of
    Right fingerprint | expected == Just fingerprint -> pure ()
    Right _ -> staleGenerated namespace (path ++ " changed or has not been generated")
    Left problem | takeFileName path == "Hanging.hs" && expected == Nothing && isDoesNotExistError problem -> pure ()
    Left problem -> staleGenerated namespace ("Cannot verify " ++ path ++ ": " ++ show problem)

staleGenerated :: String -> String -> IO value
staleGenerated namespace reason = ioError (userError
  (reason ++ "; run from the repository root: cabal run effect-codegen -- compiler " ++ namespace))

-- 仓库的生成命令适配；执行核心不启动编译器，也不依赖 GHC 源码解析 API。
generate :: String -> [FilePath] -> IO ()
generate namespace handlerFiles = callProcess "cabal" (["run", "effect-codegen", "--"] ++ options ++ ["compiler", namespace])
  where
    -- The generated source check names the actual file below the namespace's module root.
    options = case handlerFiles of
      [path] -> ["--source-dir", iterate takeDirectory path !! (2 + length (filter (== '.') namespace))]
      _ -> []
