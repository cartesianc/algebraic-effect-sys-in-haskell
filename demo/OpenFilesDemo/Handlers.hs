-- handler 是不带参数的类方法：按表示类型 require 资产，用 raise 报告自己的失败。
-- 开启、关闭与上游由 gen 按注册装配，运行编译 Generated 副本。
{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE UndecidableInstances #-}

{-# OPTIONS_GHC -Werror=missing-methods #-}

module OpenFilesDemo.Handlers () where

import Framework.SDK (Raises(..), Reads(..))
import OpenFilesDemo.Generated.Effects
import OpenFilesDemo.Types
import Control.Exception (bracketOnError, displayException)
import Control.Monad (forM_, unless)
import Control.Monad.IO.Class (liftIO)
import Data.List (nub)
import System.Directory (createDirectoryIfMissing)
import System.FilePath ((</>), takeDirectory)
import System.IO
  ( IOMode(ReadWriteMode), SeekMode(SeekFromEnd)
  , hClose, hFlush, hIsClosed, hPutStrLn, hSeek, hSetEncoding, openFile, utf8 )
import System.IO.Error (tryIOError)
import System.Mem (performGC)

instance ListFilesLayer m => ListFilesHandler m where
  listFiles = pure
    [ "demo" </> "OpenFilesDemo" </> "output" </> ("file-" ++ show index ++ ".txt")
    | index <- [1..10 :: Int]
    ]

instance AcquireFilesLayer m => AcquireFilesHandler m where
  acquireFiles = do
    paths <- require @[FilePath]
    -- 整批获取是本 Context 的原子操作；中途失败释放此前已打开的文件。
    outcome <- liftIO $ tryIOError $
      foldr (\path acquireRest -> do
        createDirectoryIfMissing True (takeDirectory path)
        bracketOnError (openFile path ReadWriteMode) hClose $ \file -> do
          hSetEncoding file utf8
          rest <- acquireRest
          pure (FileHandle path file : rest)) (pure []) paths
    either (raise . AcquireFilesError . displayException) pure outcome

-- requests 在开启前驱动 FileResources 打开整批文件。
instance OpenFilesLayer m => OpenFilesHandler m where
  openFiles = do
    files <- require @[FileHandle]
    liftIO (putStrLn ("[open] acquired " ++ show (length files) ++ " files"))
    pure []

instance CloseFilesLayer m => CloseFilesHandler m where
  closeFiles = do
    held <- require @[FileHandle]
    let files = [(path, file) | FileHandle path file <- held]
    outcome <- liftIO (tryIOError (mapM_ (hClose . snd) files))
    either (raise . CloseFilesError . displayException) pure outcome
    liftIO (putStrLn ("[close] released " ++ show (length files) ++ " files"))
    pure []

-- 挂在 ReleaseFiles 下，记下本链持有的文件；值只经资产流动，关闭后的检查读取这份快照，不再 require 已关闭的资源。
instance SnapshotFilesLayer m => SnapshotFilesHandler m where
  snapshotFiles = require @[FileHandle]

-- HoldFiles 与 ReleaseFiles 共用：Input 已开启文件，本链只持有它们，链退出后 SDK 自动关闭。
instance HoldFilesLayer m => HoldFilesHandler m where
  holdFiles = pure []

instance InspectFilesLayer m => InspectFilesHandler m where
  inspectFiles = do
    -- 前一 Node 的使用已经结束；本条链经 Input 重新开启，并持有自己的资源绑定。
    held <- require @[FileHandle]
    let files = [(path, file) | FileHandle path file <- held]
    unless (length files == 10 && length (nub (map fst files)) == 10) $
      raise (InspectFilesError "Expected ten distinct files")
    outcome <- liftIO $ tryIOError $ do
      beforeGC <- mapM (hIsClosed . snd) files
      putStrLn ("[check] current chain: " ++ show (length (filter not beforeGC)) ++ "/10 open")
      performGC
      afterGC <- mapM (hIsClosed . snd) files
      putStrLn ("[check] after GC, scope still retained: " ++ show (length (filter not afterGC)) ++ "/10 open")
      pure (all not beforeGC && all not afterGC)
    remainedOpen <- either (raise . InspectFilesError . displayException) pure outcome
    unless remainedOpen (raise (InspectFilesError "A file closed without calling closeFiles"))
    written <- liftIO $ tryIOError $ forM_ files $ \(_, file) -> do
      hSeek file SeekFromEnd 0
      hPutStrLn file "Still writable during this chain after GC; closeFiles has not run."
      hFlush file
    either (raise . InspectFilesError . displayException) pure written
    liftIO (putStrLn "[check] write and flush: 10/10 succeeded before close")
    -- 链退出后自动关闭；后续 Node 不继承这份活资源。
    pure []

-- 前一个 node 的链已经退出，SDK 已关闭它持有的文件；这里只检查快照中的 Handle。
instance FinishInspectionLayer m => FinishInspectionHandler m where
  finishInspection = do
    held <- require @[FileHandle]
    let files = [(path, file) | FileHandle path file <- held]
    outcome <- liftIO (tryIOError (mapM (hIsClosed . snd) files))
    closed <- either (raise . FinishInspectionError . displayException) pure outcome
    unless (length closed == 10 && and closed) $
      raise (FinishInspectionError "Not all files closed after the scope closed")
    liftIO (putStrLn "[check] after the scope closed: 10/10 closed")
    pure []
