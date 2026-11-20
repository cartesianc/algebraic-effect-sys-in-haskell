-- handler 是不带参数的类方法：按表示类型 require 资产，用 raise 报告自己的失败。
-- scope 的开启与关闭由 gen 按注册装配到使用闭包上，handler 中不调用 open／close。
{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE UndecidableInstances #-}

{-# OPTIONS_GHC -Werror=missing-methods #-}

module ScopeInstancesDemo.Handlers () where

import Framework.SDK (Raises(..), Reads(..), rawoutput)
import ScopeInstancesDemo.Generated.Effects
import ScopeInstancesDemo.Types
import Control.Exception (displayException)
import Control.Monad (unless)
import Control.Monad.IO.Class (liftIO)
import System.Directory (createDirectoryIfMissing, doesFileExist, removeFile)
import System.FilePath ((</>), takeFileName)
import System.IO (readFile')
import System.IO.Error (tryIOError)

instance PrepareFilesLayer m => PrepareFilesHandler m where
  prepareFiles = do
    let outputDirectory = "demo" </> "ScopeInstancesDemo" </> "output"
    outcome <- liftIO $ tryIOError $ do
      createDirectoryIfMissing True outputDirectory
      -- 仅重置本 demo 的产物；初始选择第一份文件。
      mapM_ ((`writeFile` "") . (outputDirectory </>)) ["one.txt", "two.txt", "events.txt"]
      writeFile (outputDirectory </> "selected.txt") (outputDirectory </> "one.txt")
    either (raise . PrepareFilesError . displayException) pure outcome
    rawoutput []

-- 选择由普通 Excu 节点改写；下一条使用闭包的 requests 会重新读取它。
instance SelectSecondLayer m => SelectSecondHandler m where
  selectSecond = do
    let outputDirectory = "demo" </> "ScopeInstancesDemo" </> "output"
    outcome <- liftIO (tryIOError (writeFile (outputDirectory </> "selected.txt") (outputDirectory </> "two.txt")))
    either (raise . SelectSecondError . displayException) pure outcome
    rawoutput []

instance SelectFirstLayer m => SelectFirstHandler m where
  selectFirst = do
    let outputDirectory = "demo" </> "ScopeInstancesDemo" </> "output"
    outcome <- liftIO (tryIOError (writeFile (outputDirectory </> "selected.txt") (outputDirectory </> "one.txt")))
    either (raise . SelectFirstError . displayException) pure outcome
    rawoutput []

-- 参数确实由 parser 中的 IO 动态取得。观察日志不承担任何 scope 状态管理。
instance SelectedFileLayer m => SelectedFileHandler m where
  selectedFile = do
    let outputDirectory = "demo" </> "ScopeInstancesDemo" </> "output"
        journal = outputDirectory </> "events.txt"
    outcome <- liftIO $ tryIOError $ do
      path <- readFile' (outputDirectory </> "selected.txt")
      appendFile journal ("argument " ++ path ++ "\n")
      pure path
    either (raise . SelectedFileError . displayException) pure outcome

instance AcquireFileLayer m => AcquireFileHandler m where
  acquireFile = do
    path <- require @String
    let journal = "demo" </> "ScopeInstancesDemo" </> "output" </> "events.txt"
    -- 取得时确保文件存在，并在旁边记下开启标记 <path>.open；资产只记路径。
    outcome <- liftIO $ tryIOError $ do
      appendFile path ""
      writeFile (path ++ ".open") ""
      appendFile journal ("acquire " ++ path ++ "\n")
    either (raise . AcquireFileError . displayException) pure outcome
    pure (FileHandle path)

-- requests 在开启前驱动 FileResource 取得文件；open／close 只读取 scope 内的资源。
instance OpenSelectedFileLayer m => OpenSelectedFileHandler m where
  openSelectedFile = do
    FileHandle path <- require @FileHandle
    let journal = "demo" </> "ScopeInstancesDemo" </> "output" </> "events.txt"
    outcome <- liftIO (tryIOError (appendFile journal ("open " ++ path ++ "\n")))
    either (raise . OpenSelectedFileError . displayException) pure outcome
    rawoutput []

instance CloseSelectedFileLayer m => CloseSelectedFileHandler m where
  closeSelectedFile = do
    FileHandle path <- require @FileHandle
    let journal = "demo" </> "ScopeInstancesDemo" </> "output" </> "events.txt"
    outcome <- liftIO $ tryIOError $ do
      removeFile (path ++ ".open")
      appendFile journal ("close " ++ path ++ "\n")
    either (raise . CloseSelectedFileError . displayException) pure outcome
    rawoutput []

-- UseFirst、UseSecond、ReopenFirst 共用：scope 内 require 稳定参数与本条闭包选中的实例。
instance CheckSelectionLayer m => CheckSelectionHandler m where
  checkSelection = do
    selected <- require @String
    FileHandle path <- require @FileHandle
    live <- liftIO (doesFileExist (path ++ ".open"))
    unless (path == selected && live) $
      raise (CheckSelectionError ("The instance does not match the current argument " ++ selected))
    -- 写入时由本 handler 按路径打开文件，写完即关闭。
    outcome <- liftIO (tryIOError (appendFile path "used\n"))
    either (raise . CheckSelectionError . displayException) pure outcome
    liftIO (putStrLn ("[use] " ++ takeFileName path ++ ": the current argument selected this instance; it is open"))
    rawoutput []

-- 各使用闭包已退出并自动关闭实例；此处只读日志和文件，不 require 旧资源。
instance CheckJournalLayer m => CheckJournalHandler m where
  checkJournal = do
    let outputDirectory = "demo" </> "ScopeInstancesDemo" </> "output"
        firstFile = outputDirectory </> "one.txt"
        secondFile = outputDirectory </> "two.txt"
    outcome <- liftIO $ tryIOError $ do
      events <- readFile' (outputDirectory </> "events.txt")
      first <- readFile' firstFile
      second <- readFile' secondFile
      pure (lines events, lines first, lines second)
    (events, first, second) <- either (raise . CheckJournalError . displayException) pure outcome
    let expected =
          [ operation ++ path
          | path <- [firstFile, secondFile, firstFile]
          , operation <- ["argument ", "acquire ", "open ", "close "]
          ]
    unless (events == expected) $
      raise (CheckJournalError ("Unexpected lifecycle or extra Context evaluation: " ++ show events))
    unless (first == ["used", "used"] && second == ["used"]) $
      raise (CheckJournalError ("Unexpected file contents: " ++ show (first, second)))
    markers <- liftIO (mapM (doesFileExist . (++ ".open")) [firstFile, secondFile])
    unless (not (or markers)) $
      raise (CheckJournalError "An instance is still open after its use closure exited")
    liftIO $ do
      putStrLn "[check] each use closure opened the instance its current argument selected and closed it on exit"
      putStrLn "[check] actual acquisitions/closures: file 1 = 2/2; file 2 = 1/1"
      putStrLn "[check] three argument requests, three open calls; require reuses the stable parameter within each chain"
    rawoutput []
