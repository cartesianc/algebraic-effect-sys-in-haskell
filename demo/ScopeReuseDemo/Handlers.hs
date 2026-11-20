-- handler 是不带参数的类方法：按表示类型 require 资产，用 raise 报告自己的失败。
-- 开启参数的刷新与 scope 开启由 gen 按注册装配，运行编译 Generated 副本。
{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE UndecidableInstances #-}

{-# OPTIONS_GHC -Werror=missing-methods #-}

module ScopeReuseDemo.Handlers () where

import Framework.SDK (Raises(..), Reads(..), rawoutput)
import ScopeReuseDemo.Generated.Effects
import ScopeReuseDemo.Types
import Control.Concurrent (threadDelay)
import Control.Exception (displayException)
import Control.Monad (unless)
import Control.Monad.IO.Class (liftIO)
import Data.List (sort)
import System.Directory (createDirectoryIfMissing)
import System.FilePath ((</>), takeDirectory)
import System.IO (readFile')
import System.IO.Error (isAlreadyInUseError, tryIOError)

instance SharedPathsLayer m => SharedPathsHandler m where
  sharedPaths = pure (SharedPaths
    ("demo" </> "ScopeReuseDemo" </> "output" </> "shared.txt")
    ("demo" </> "ScopeReuseDemo" </> "output" </> "events.txt"))

instance PrepareProbeLayer m => PrepareProbeHandler m where
  prepareProbe = do
    SharedPaths path journal <- require @SharedPaths
    outcome <- liftIO $ tryIOError $ do
      createDirectoryIfMissing True (takeDirectory path)
      -- 仅重置本 demo 的两份产物，在三个分支启动前完成。
      writeFile path ""
      writeFile journal ""
    either (raise . PrepareProbeError . displayException) pure outcome
    rawoutput []

instance AcquireFileLayer m => AcquireFileHandler m where
  acquireFile = do
    paths@(SharedPaths path journal) <- require @SharedPaths
    outcome <- liftIO $ tryIOError $ do
      appendFile path ""
      -- 记录资源获取；日志独立于 Context，重新产值不会清零它。
      appendFile journal "file-open\n"
    either (raise . AcquireFileError . displayException) pure outcome
    pure (SharedFile paths)

-- requests 在开启前驱动 FileResource 取得文件。
instance OpenSharedFileLayer m => OpenSharedFileHandler m where
  openSharedFile = do
    SharedFile (SharedPaths _ journal) <- require @SharedFile
    outcome <- liftIO (tryIOError (appendFile journal "open-body\n"))
    either (raise . OpenSharedFileError . displayException) pure outcome
    rawoutput []

instance CloseSharedFileLayer m => CloseSharedFileHandler m where
  closeSharedFile = do
    SharedFile (SharedPaths _ journal) <- require @SharedFile
    outcome <- liftIO $ tryIOError $ do
      appendFile journal "close-body\n"
      appendFile journal "file-close\n"
    either (raise . CloseSharedFileError . displayException) pure outcome
    rawoutput []

-- 每条链先由 requests 刷新参数，再经 Input 开启；scope 内 require 稳定参数，重叠使用时可共享实例。
-- 不在业务中加打开标志或互斥锁，也不为尚未开始的 Node 预留资源。
-- 资源只记路径，写入者在自己的执行中按路径追加；重叠的写入者同时追加时，GHC 的单进程文件锁
-- 会让后到者暂时失败（resource busy），稍后重试。
instance WriteFirstLayer m => WriteFirstHandler m where
  writeFirst = do
    SharedFile (SharedPaths path _) <- require @SharedFile
    let append remaining = tryIOError (appendFile path "first\n") >>= either
          (\failure -> if isAlreadyInUseError failure && remaining > (0 :: Int)
             then threadDelay 10000 >> append (remaining - 1) else ioError failure) pure
    outcome <- liftIO (tryIOError (append 50))
    either (raise . WriteFirstError . displayException) pure outcome
    rawoutput []

instance WriteSecondLayer m => WriteSecondHandler m where
  writeSecond = do
    SharedFile (SharedPaths path _) <- require @SharedFile
    let append remaining = tryIOError (appendFile path "second\n") >>= either
          (\failure -> if isAlreadyInUseError failure && remaining > (0 :: Int)
             then threadDelay 10000 >> append (remaining - 1) else ioError failure) pure
    outcome <- liftIO (tryIOError (append 50))
    either (raise . WriteSecondError . displayException) pure outcome
    rawoutput []

instance WriteThirdLayer m => WriteThirdHandler m where
  writeThird = do
    SharedFile (SharedPaths path _) <- require @SharedFile
    let append remaining = tryIOError (appendFile path "third\n") >>= either
          (\failure -> if isAlreadyInUseError failure && remaining > (0 :: Int)
             then threadDelay 10000 >> append (remaining - 1) else ioError failure) pure
    outcome <- liftIO (tryIOError (append 50))
    either (raise . WriteThirdError . displayException) pure outcome
    rawoutput []

instance VerifyReuseLayer m => VerifyReuseHandler m where
  verifyReuse = do
    SharedPaths path journal <- require @SharedPaths
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
    rawoutput []
