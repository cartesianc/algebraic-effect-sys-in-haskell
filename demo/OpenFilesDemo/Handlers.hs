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

import Framework.SDK (Raises(..), Reads(..), rawoutput)
import OpenFilesDemo.Generated.Effects
import OpenFilesDemo.Types
import Control.Exception (bracketOnError, displayException)
import Control.Monad (filterM, forM_, unless)
import Control.Monad.IO.Class (liftIO)
import Data.List (nub)
import System.Directory (createDirectoryIfMissing, doesFileExist, removeFile)
import System.FilePath ((</>), takeDirectory)
import System.IO.Error (tryIOError)
import System.Mem (performGC)

instance ListFilesLayer m => ListFilesHandler m where
  listFiles = pure
    [ "demo" </> "OpenFilesDemo" </> "output" </> ("file-" ++ show index ++ ".txt")
    | index <- [1..10 :: Int]
    ]

instance AcquireFilesLayer m => AcquireFilesHandler m where
  acquireFiles = do
    paths <- require @[String]
    -- 整批取得：确保每个文件存在并在旁边记下开启标记 <path>.open；资产只记路径。
    -- 取得整批之后才由 scope 的 close 接管；中途失败则逆序撤销本批新建的标记。
    let acquire path rest = do
          createDirectoryIfMissing True (takeDirectory path)
          appendFile path ""
          let marker = path ++ ".open"
          existing <- doesFileExist marker
          if existing then rest else
            bracketOnError (writeFile marker "") (const (removeFile marker)) (const rest)
    outcome <- liftIO $ tryIOError $ foldr acquire (pure ()) paths
    either (raise . AcquireFilesError . displayException) pure outcome
    pure (FileHandles paths)

-- requests 在开启前驱动 FileResources 取得整批文件。
instance OpenFilesLayer m => OpenFilesHandler m where
  openFiles = do
    FileHandles paths <- require @FileHandles
    liftIO (putStrLn ("[open] acquired " ++ show (length paths) ++ " files"))
    rawoutput []

instance CloseFilesLayer m => CloseFilesHandler m where
  closeFiles = do
    FileHandles paths <- require @FileHandles
    outcome <- liftIO (tryIOError (mapM_ (removeFile . (++ ".open")) paths))
    either (raise . CloseFilesError . displayException) pure outcome
    liftIO (putStrLn ("[close] released " ++ show (length paths) ++ " files"))
    rawoutput []

-- 挂在 ReleaseFiles 下，记下本链持有的文件；值只经资产流动，关闭后的检查读取这份快照，不再 require 已关闭的资源。
instance SnapshotFilesLayer m => SnapshotFilesHandler m where
  snapshotFiles = require @FileHandles

-- HoldFiles 与 ReleaseFiles 共用：Input 已开启文件，本链只持有它们，链退出后 SDK 自动关闭。
instance HoldFilesLayer m => HoldFilesHandler m where
  holdFiles = rawoutput []

instance InspectFilesLayer m => InspectFilesHandler m where
  inspectFiles = do
    -- 前一 Node 的使用已经结束；本条链经 Input 重新开启，并持有自己的资源绑定。
    FileHandles paths <- require @FileHandles
    unless (length paths == 10 && length (nub paths) == 10) $
      raise (InspectFilesError "Expected ten distinct files")
    let openCount = length <$> filterM (doesFileExist . (++ ".open")) paths
    outcome <- liftIO $ tryIOError $ do
      beforeGC <- openCount
      putStrLn ("[check] current chain: " ++ show beforeGC ++ "/10 open")
      performGC
      afterGC <- openCount
      putStrLn ("[check] after GC, scope still retained: " ++ show afterGC ++ "/10 open")
      pure (beforeGC == 10 && afterGC == 10)
    remainedOpen <- either (raise . InspectFilesError . displayException) pure outcome
    unless remainedOpen (raise (InspectFilesError "A file closed without calling closeFiles"))
    -- 写入时由本 handler 按路径打开文件，写完即关闭。
    written <- liftIO $ tryIOError $ forM_ paths $ \path ->
      appendFile path "Still writable during this chain after GC; closeFiles has not run.\n"
    either (raise . InspectFilesError . displayException) pure written
    liftIO (putStrLn "[check] write and flush: 10/10 succeeded before close")
    -- 链退出后自动关闭；后续 Node 不继承这份活资源。
    rawoutput []

-- 前一个 node 的链已经退出，SDK 已关闭它持有的文件；这里只检查快照中各文件的开启标记。
instance FinishInspectionLayer m => FinishInspectionHandler m where
  finishInspection = do
    FileHandles paths <- require @FileHandles
    outcome <- liftIO (tryIOError (length <$> filterM (doesFileExist . (++ ".open")) paths))
    stillOpen <- either (raise . FinishInspectionError . displayException) pure outcome
    unless (length paths == 10 && stillOpen == 0) $
      raise (FinishInspectionError "Not all files closed after the scope closed")
    liftIO (putStrLn "[check] after the scope closed: 10/10 closed")
    rawoutput []
