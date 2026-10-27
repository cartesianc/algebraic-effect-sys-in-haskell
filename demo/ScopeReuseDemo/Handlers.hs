-- 原生 Haskell 取值；SDK 生成方法入口包装，运行编译 Generated 副本。
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE UndecidableInstances #-}

{-# OPTIONS_GHC -Werror=missing-methods #-}

module ScopeReuseDemo.Handlers () where

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

instance FileLocationsEffect App where
  filePaths = pure (FilePaths (SharedPaths
    ("demo" </> "ScopeReuseDemo" </> "output" </> "shared.txt")
    ("demo" </> "ScopeReuseDemo" </> "output" </> "events.txt")))

instance PrepareProbeEffect App where
  prepareProbe = do
    FilePaths (SharedPaths path journal) <- request @FilePaths
    outcome <- liftIO $ tryIOError $ do
      createDirectoryIfMissing True (takeDirectory path)
      -- 仅重置本 demo 的两份产物，在三个分支启动前完成。
      writeFile path ""
      writeFile journal ""
    either (raise . PrepareProbeError . displayException) pure outcome

instance FileResourceEffect App where
  openedFile = do
    FilePaths paths@(SharedPaths path journal) <- require @FilePaths
    outcome <- liftIO $ tryIOError $
      bracketOnError (openFile path AppendMode) hClose $ \file -> do
        hSetEncoding file utf8
        -- 记录真实资源获取；日志独立于 Context，重新产值不会清零它。
        appendFile journal "file-open\n"
        pure (OpenedFile (SharedFile paths file))
    either (raise . FileResourceError . displayException) pure outcome

instance SharedFileScopeEffect App where
  openSharedFile = do
    OpenedFile (SharedFile (SharedPaths _ journal) _) <- request @OpenedFile
    outcome <- liftIO (tryIOError (appendFile journal "open-body\n"))
    either (raise . SharedFileScopeError . displayException) pure outcome

  closeSharedFile = do
    OpenedFile (SharedFile (SharedPaths _ journal) file) <- require @OpenedFile
    outcome <- liftIO $ tryIOError $ do
      appendFile journal "close-body\n"
      hClose file
      appendFile journal "file-close\n"
    either (raise . SharedFileScopeError . displayException) pure outcome

-- 每条链先 request 参数；scope 内 require 稳定参数，重叠使用时可共享实例。
-- 不在业务中加打开标志或互斥锁，也不为尚未开始的 Node 预留资源。
instance WriteFirstEffect App where
  writeFirst = do
    _ <- request @FilePaths
    openSharedFile
    OpenedFile (SharedFile _ file) <- require @OpenedFile
    outcome <- liftIO $ tryIOError $ do
      hPutStr file "first\n"
      hFlush file
    either (raise . WriteFirstError . displayException) pure outcome

instance WriteSecondEffect App where
  writeSecond = do
    _ <- request @FilePaths
    openSharedFile
    OpenedFile (SharedFile _ file) <- require @OpenedFile
    outcome <- liftIO $ tryIOError $ do
      hPutStr file "second\n"
      hFlush file
    either (raise . WriteSecondError . displayException) pure outcome

instance WriteThirdEffect App where
  writeThird = do
    _ <- request @FilePaths
    openSharedFile
    OpenedFile (SharedFile _ file) <- require @OpenedFile
    outcome <- liftIO $ tryIOError $ do
      hPutStr file "third\n"
      hFlush file
    either (raise . WriteThirdError . displayException) pure outcome

instance VerifyReuseEffect App where
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
