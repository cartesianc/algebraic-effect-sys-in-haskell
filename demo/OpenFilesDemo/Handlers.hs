-- 原生 Haskell 取值；SDK 生成方法入口包装，运行编译 Generated 副本。
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE UndecidableInstances #-}

{-# OPTIONS_GHC -Werror=missing-methods #-}

module OpenFilesDemo.Handlers () where

import Framework.SDK (Effect(..))
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

instance FileLocationsEffect App where
  getFileNames = pure (FileNames
    [ "demo" </> "OpenFilesDemo" </> "output" </> ("file-" ++ show index ++ ".txt")
    | index <- [1..10 :: Int]
    ])

instance FileResourcesEffect App where
  acquireFiles = do
    FileNames paths <- getFileNames
    -- 整批获取是本 Context 的原子操作；中途失败释放此前已打开的文件。
    outcome <- liftIO $ tryIOError $ fmap OpenedFiles $
      foldr (\path acquireRest -> do
        createDirectoryIfMissing True (takeDirectory path)
        bracketOnError (openFile path ReadWriteMode) hClose $ \file -> do
          hSetEncoding file utf8
          rest <- acquireRest
          pure ((path, file) : rest)) (pure []) paths
    either (raise . FileResourcesError . displayException) pure outcome

instance FileSessionEffect App where
  openFiles = do
    OpenedFiles files <- acquireFiles
    liftIO (putStrLn ("[open] acquired " ++ show (length files) ++ " files"))

  closeFiles = do
    OpenedFiles files <- readOpenedFiles
    outcome <- liftIO (tryIOError (mapM_ (hClose . snd) files))
    either (raise . FileSessionError . displayException) pure outcome
    liftIO (putStrLn ("[close] released " ++ show (length files) ++ " files"))

instance HoldFilesEffect App where
  holdFiles = do
    _ <- getFileNames
    openFiles

instance InspectFilesEffect App where
  inspectFiles = do
    -- 前一 Node 的使用已经结束；本条链显式 open，并持有自己的资源绑定。
    holdFiles
    OpenedFiles files <- readOpenedFiles
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

instance FinishInspectionEffect App where
  finishInspection = do
    holdFiles
    -- 在关闭前取得 Handle，随后只检查本地快照，不向已关闭 scope 再次 require。
    OpenedFiles files <- readOpenedFiles
    closeFiles
    outcome <- liftIO (tryIOError (mapM (hIsClosed . snd) files))
    closed <- either (raise . FinishInspectionError . displayException) pure outcome
    unless (length closed == 10 && and closed) $
      raise (FinishInspectionError "Not all files closed after closeFiles")
    liftIO (putStrLn "[check] after explicit close: 10/10 closed")
