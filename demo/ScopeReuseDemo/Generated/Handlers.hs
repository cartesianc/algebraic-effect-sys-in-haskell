-- 自动生成的编译副本；请修改上级 Handlers.hs 后重新生成。
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}
-- 原生 Haskell 取值；SDK 生成方法入口包装，运行编译 Generated 副本。
{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE UndecidableInstances #-}

{-# OPTIONS_GHC -Werror=missing-methods #-}

module ScopeReuseDemo.Generated.Handlers (handlerSourceFingerprint, newScopeHandlers, scopeCleanups, errorHandlers, contextInjections) where

import qualified Framework.SDK as FrameworkRuntime
import qualified Framework.Effect.Contract as FrameworkRoot
import qualified ScopeReuseDemo.Generated.Effects as FrameworkGenerated
import Framework.SDK (Effect(..))
import ScopeReuseDemo.Generated.Effects
import ScopeReuseDemo.Types
import Control.Exception (bracketOnError, displayException)
import Control.Monad (unless)
import Control.Monad.IO.Class (liftIO)
import Data.List (sort)
import System.Directory (createDirectoryIfMissing)
import System.FilePath ((</>), takeDirectory)
import System.IO
  ( IOMode(AppendMode)
  , hClose, hFlush, hPutStr
  , hSetEncoding, openFile, readFile', utf8 )
import System.IO.Error (tryIOError)

instance FileLocationsInputs m => FileLocationsEffect m where
  filePaths =
    (FrameworkRoot.withErrorPath [] . FrameworkRoot.handler @FrameworkGenerated.Root . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.callContext "FileLocations" FrameworkGenerated.ContextBindingError
      [("PrepareProbe", FrameworkRuntime.RequestValue), ("FileResource", FrameworkRuntime.RequireValue), ("WriteFirst", FrameworkRuntime.RequestValue), ("WriteSecond", FrameworkRuntime.RequestValue), ("WriteThird", FrameworkRuntime.RequestValue), ("VerifyReuse", FrameworkRuntime.RequestValue)]
      (Just (FrameworkRuntime.ScopeInput "FileLocations"))
      FrameworkGenerated.boundFileLocations
      (\value bindings -> bindings { FrameworkGenerated.boundFileLocations = Just value })) $
      let
        filePaths :: (m) (FrameworkGenerated.FilePaths)
        filePaths = pure (FilePaths (SharedPaths
          ("demo" </> "ScopeReuseDemo" </> "output" </> "shared.txt")
          ("demo" </> "ScopeReuseDemo" </> "output" </> "events.txt")))
      in filePaths

instance PrepareProbeInputs m => PrepareProbeEffect m where
  prepareProbe =
    (FrameworkRoot.withErrorPath [] . FrameworkRoot.handler @FrameworkGenerated.Root . FrameworkRuntime.atomicHandle "prepareProbe" . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.enterHandler "PrepareProbe") $
      let
        prepareProbe :: (m) (Maybe String)
        prepareProbe = do
          FilePaths (SharedPaths path journal) <- request @FilePaths
          outcome <- liftIO $ tryIOError $ do
            createDirectoryIfMissing True (takeDirectory path)
            -- 仅重置本 demo 的两份产物，在三个分支启动前完成。
            writeFile path ""
            writeFile journal ""
          either (raise . PrepareProbeError . displayException) pure outcome
          pure Nothing
      in prepareProbe

instance FileResourceInputs m => FileResourceEffect m where
  openedFile =
    (FrameworkRoot.withErrorPath [] . FrameworkRoot.handler @FrameworkGenerated.Root . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.callContext "FileResource" FrameworkGenerated.ContextBindingError
      [("SharedFileScope", FrameworkRuntime.RequestValue), ("WriteFirst", FrameworkRuntime.RequireValue), ("WriteSecond", FrameworkRuntime.RequireValue), ("WriteThird", FrameworkRuntime.RequireValue)]
      Nothing
      FrameworkGenerated.boundFileResource
      (\value bindings -> bindings { FrameworkGenerated.boundFileResource = Just value })) $
      let
        openedFile :: (m) (FrameworkGenerated.OpenedFile)
        openedFile = do
          FilePaths paths@(SharedPaths path journal) <- require @FilePaths
          outcome <- liftIO $ tryIOError $
            bracketOnError (openFile path AppendMode) hClose $ \file -> do
              hSetEncoding file utf8
              -- 记录真实资源获取；日志独立于 Context，重新产值不会清零它。
              appendFile journal "file-open\n"
              pure (OpenedFile (SharedFile paths file))
          either (raise . FileResourceError . displayException) pure outcome
      in openedFile

instance SharedFileScopeInputs m => SharedFileScopeEffect m where
  openSharedFile =
    (FrameworkRoot.withErrorPath ["SharedFileScope"] . FrameworkRoot.handler @FrameworkGenerated.Root . FrameworkRuntime.atomicScope "openSharedFile" . FrameworkRuntime.openScope "SharedFileScope" FrameworkGenerated.ScopeBindingError . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.enterHandler "SharedFileScope") $
      let
        openSharedFile :: (m) (Maybe String)
        openSharedFile = do
          OpenedFile (SharedFile (SharedPaths _ journal) _) <- request @OpenedFile
          outcome <- liftIO (tryIOError (appendFile journal "open-body\n"))
          either (raise . SharedFileScopeError . displayException) pure outcome
          pure Nothing
      in openSharedFile

  closeSharedFile =
    (FrameworkRoot.withErrorPath ["SharedFileScope"] . FrameworkRoot.handler @FrameworkGenerated.Root . FrameworkRuntime.atomicScope "closeSharedFile" . FrameworkRuntime.closeScope "SharedFileScope" FrameworkGenerated.ScopeBindingError . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.enterHandler "SharedFileScope") $
      let
        closeSharedFile :: (m) (Maybe String)
        closeSharedFile = do
          OpenedFile (SharedFile (SharedPaths _ journal) file) <- require @OpenedFile
          outcome <- liftIO $ tryIOError $ do
            appendFile journal "close-body\n"
            hClose file
            appendFile journal "file-close\n"
          either (raise . SharedFileScopeError . displayException) pure outcome
          pure Nothing
      in closeSharedFile

-- 每条链先 request 参数；scope 内 require 稳定参数，重叠使用时可共享实例。
-- 不在业务中加打开标志或互斥锁，也不为尚未开始的 Node 预留资源。
instance WriteFirstInputs m => WriteFirstEffect m where
  writeFirst =
    (FrameworkRoot.withErrorPath ["SharedFileScope"] . FrameworkRoot.handler @FrameworkGenerated.Root . FrameworkRuntime.atomicHandle "writeFirst" . FrameworkRuntime.withScopeDependencies ["SharedFileScope"] . FrameworkRuntime.enterHandler "WriteFirst") $
      let
        writeFirst :: (m) (Maybe String)
        writeFirst = do
          _ <- request @FilePaths
          openSharedFile
          OpenedFile (SharedFile _ file) <- require @OpenedFile
          outcome <- liftIO $ tryIOError $ do
            hPutStr file "first\n"
            hFlush file
          either (raise . WriteFirstError . displayException) pure outcome
          pure Nothing
      in writeFirst

instance WriteSecondInputs m => WriteSecondEffect m where
  writeSecond =
    (FrameworkRoot.withErrorPath ["SharedFileScope"] . FrameworkRoot.handler @FrameworkGenerated.Root . FrameworkRuntime.atomicHandle "writeSecond" . FrameworkRuntime.withScopeDependencies ["SharedFileScope"] . FrameworkRuntime.enterHandler "WriteSecond") $
      let
        writeSecond :: (m) (Maybe String)
        writeSecond = do
          _ <- request @FilePaths
          openSharedFile
          OpenedFile (SharedFile _ file) <- require @OpenedFile
          outcome <- liftIO $ tryIOError $ do
            hPutStr file "second\n"
            hFlush file
          either (raise . WriteSecondError . displayException) pure outcome
          pure Nothing
      in writeSecond

instance WriteThirdInputs m => WriteThirdEffect m where
  writeThird =
    (FrameworkRoot.withErrorPath ["SharedFileScope"] . FrameworkRoot.handler @FrameworkGenerated.Root . FrameworkRuntime.atomicHandle "writeThird" . FrameworkRuntime.withScopeDependencies ["SharedFileScope"] . FrameworkRuntime.enterHandler "WriteThird") $
      let
        writeThird :: (m) (Maybe String)
        writeThird = do
          _ <- request @FilePaths
          openSharedFile
          OpenedFile (SharedFile _ file) <- require @OpenedFile
          outcome <- liftIO $ tryIOError $ do
            hPutStr file "third\n"
            hFlush file
          either (raise . WriteThirdError . displayException) pure outcome
          pure Nothing
      in writeThird

instance VerifyReuseInputs m => VerifyReuseEffect m where
  verifyReuse =
    (FrameworkRoot.withErrorPath [] . FrameworkRoot.handler @FrameworkGenerated.Root . FrameworkRuntime.atomicHandle "verifyReuse" . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.enterHandler "VerifyReuse") $
      let
        verifyReuse :: (m) (Maybe String)
        verifyReuse = do
          FilePaths (SharedPaths path journal) <- request @FilePaths
          -- parallel 已等待各链退出及自动清理；此处只读日志和文件，不 require 旧资源。
          outcome <- liftIO $ tryIOError $ do
            events <- readFile' journal
            content <- readFile' path
            pure (lines events, lines content)
          (events, content) <- either (raise . VerifyReuseError . displayException) pure outcome
          let openBodies = length (filter (== "open-body") events)
              fileOpens = length (filter (== "file-open") events)
              closeBodies = length (filter (== "close-body") events)
              fileCloses = length (filter (== "file-close") events)
              labels = ["first", "second", "third"]
          unless (fileOpens > 0 && openBodies == fileOpens
                  && closeBodies == fileOpens && fileCloses == fileOpens) $
            raise (VerifyReuseError ("Acquisition and cleanup counts differ: " ++ show events))
          unless (sort content == labels) $
            raise (VerifyReuseError ("Unexpected file contents: " ++ show content))
          liftIO $ do
            putStrLn ("[check] actual resource opens/closes: " ++ show fileOpens ++ "/" ++ show fileCloses)
            putStrLn "[check] all writer chains released their resources; each line written exactly once"
          pure Nothing
      in verifyReuse

-- 记录本编译副本实际使用的手写源码；启动前检查，避免执行过期方法体。
handlerSourceFingerprint :: Maybe String
handlerSourceFingerprint = Just "b69accce6e9de4b107e3760ea002973e"


-- SDK 内部：scope 按上游到下游登记，退出时逆序收尾；创建不执行业务方法。
newScopeHandlers :: IO [FrameworkRuntime.ScopeHandler FrameworkGenerated.ContextValues FrameworkGenerated.Errors]
newScopeHandlers = sequence
  [ FrameworkRuntime.newScopeHandler "SharedFileScope" ["FileLocations"] (Just "FileResource")
  ]

-- SDK 自动收尾入口；安装时不关闭资源。
scopeCleanups :: [(String, FrameworkGenerated.App ())]
scopeCleanups =
  [ ("SharedFileScope", () <$ closeSharedFile)
  ]

-- Error 回调登记：按 handles 匹配故障来源与分类；关联 scope 由 Input 链推导。
errorHandlers :: [(Maybe String, FrameworkRoot.ErrorHandler FrameworkGenerated.Errors FrameworkGenerated.App)]
errorHandlers =
  [
  ]

-- 挂在原子句柄下的 Context：句柄的输出交给它解析并发布为资产；没有挂接时输出被丢弃。
contextInjections :: [(String, [(String, FrameworkGenerated.App ())])]
contextInjections =
  [
  ]
