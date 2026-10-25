-- 原生 Haskell 取值；SDK 生成方法入口包装，运行编译 Generated 副本。
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE UndecidableInstances #-}

{-# OPTIONS_GHC -Werror=missing-methods #-}

module FileDemo.Handlers () where

import Framework.SDK (Effect(..))
import FileDemo.Generated.Effects
import FileDemo.Types
import Control.Exception (bracketOnError, displayException)
import Control.Monad (unless)
import Control.Monad.Except (catchError, throwError)
import Control.Monad.IO.Class (liftIO)
import System.FilePath ((</>))
import System.IO
  ( Handle, IOMode(ReadWriteMode), SeekMode(AbsoluteSeek, SeekFromEnd)
  , hClose, hFlush, hGetChar, hIsClosed, hIsEOF, hPrint, hPutStr, hSeek, hSetEncoding
  , openFile, stderr, utf8 )
import System.IO.Error (tryIOError)

instance FileLocationEffect App where
  -- 示例专用文件：首次运行创建，后续追加；在项目根目录运行。
  getFileName = pure (FileName ("demo" </> "FileDemo" </> "output.txt"))

instance ValidateFileNameEffect App where
  validateFileName = do
    FileName path <- getFileName
    unless (not (null path) && '\0' `notElem` path) $
      raise (ValidateFileNameError "File name must be nonempty and contain no NUL character")

instance FileResourceEffect App where
  acquireFile = do
    validateFileName
    FileName path <- readFileName
    outcome <- liftIO $ tryIOError $
      bracketOnError (openFile path ReadWriteMode) hClose $ \file -> do
        hSetEncoding file utf8
        putStrLn ("[open] " ++ path)
        pure (OpenedFile path file)
    either (raise . FileResourceError . displayException) pure outcome

instance FileSessionEffect App where
  -- 开启期间 Context 保存真实 Handle，后续 require 复用它。
  openFileSession = do
    _ <- acquireFile
    pure ()

  closeFileSession = do
    OpenedFile path file <- readOpenedFile
    outcome <- liftIO (tryIOError (hClose file))
    either (raise . FileSessionError . displayException) pure outcome
    liftIO (putStrLn ("[close] " ++ path))

instance ReadFileEffect App where
  readFileText = do
    -- 末端也会引用 open；SDK 跳过同份已开启 scope 的方法体。
    openFileSession
    OpenedFile _ file <- readOpenedFile
    outcome <- liftIO $ tryIOError $ do
      hSeek file AbsoluteSeek 0
      FileText <$> readFully file
    either (raise . ReadFileError . displayException) pure outcome

instance FileRecoveryEffect App where
  detectFileSession = do
    OpenedFile _ file <- readOpenedFile
    outcome <- liftIO (tryIOError (hIsClosed file))
    closed <- either (raise . FileRecoveryError . displayException) pure outcome
    -- 返回 () 表示已定位：文件已关闭；仍打开则不能把原故障归到此条件。
    unless closed $
      raise (FileRecoveryError "File handle is still open; failure not located in FileSession")

  -- 沿 superclass 引用配对的关闭方法；不重放读写，也不自动重开。
  resolveFileSession = closeFileSession

instance WriteFileEffect App where
  writeFileText = do
    FileText contents <- readFileText
    OpenedFile path file <- readOpenedFile
    -- 明确消费刚读出的文本；只追加，不截断已有内容。
    let line = "file-demo: read " ++ show (length contents) ++ " characters before this append.\n"
    outcome <- liftIO $ tryIOError $ do
      putStrLn ("[read] " ++ if null contents then "(empty file)" else contents)
      hSeek file SeekFromEnd 0
      hPutStr file line
      hFlush file
      putStrLn ("[write] " ++ path ++ ": " ++ line)
    either (raise . WriteFileError . displayException) pure outcome

instance FileWorkflowEffect App where
  runFileWorkflow = do
    openFileSession
    -- 当前没有 SDK 自动收尾：本例显式清理已转成 Failure 的读写错误。
    -- 清理也失败时输出次生故障，并保持原始错误向上传播。
    writeFileText `catchError` \failure -> do
      closeFileSession `catchError` \closingFailure -> liftIO (hPrint stderr closingFailure)
      throwError failure
    closeFileSession

-- 原子 IO 辅助函数：读完仍保持 Handle 打开，供后续写入；不使用惰性 hGetContents。
readFully :: Handle -> IO String
readFully file = go []
  where
    go characters = do
      finished <- hIsEOF file
      if finished
        then pure (reverse characters)
        else hGetChar file >>= \character -> go (character : characters)
