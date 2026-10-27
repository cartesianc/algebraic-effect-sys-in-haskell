-- 原生 Haskell 取值；SDK 生成方法入口包装，运行编译 Generated 副本。
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE UndecidableInstances #-}

{-# OPTIONS_GHC -Werror=missing-methods #-}

module FileDemo.Handlers () where

import Framework.SDK (Effect(..))
import FileDemo.Generated.Effects
import FileDemo.Types
import Control.Exception (bracketOnError, displayException)
import Control.Monad (unless)
import Control.Monad.IO.Class (liftIO)
import Data.Function (fix)
import System.FilePath ((</>))
import System.IO
  ( IOMode(ReadWriteMode), SeekMode(AbsoluteSeek, SeekFromEnd)
  , hClose, hFlush, hGetChar, hIsClosed, hIsEOF, hPutStr, hSeek, hSetEncoding
  , openFile, utf8 )
import System.IO.Error (tryIOError)

instance FileLocationEffect App where
  -- 示例专用文件：首次运行创建，后续追加；在项目根目录运行。
  fileName = pure (FileName ("demo" </> "FileDemo" </> "output.txt"))

instance ValidateFileNameEffect App where
  validateFileName = do
    FileName path <- require @FileName
    unless (not (null path) && '\0' `notElem` path) $
      raise (ValidateFileNameError "File name must be nonempty and contain no NUL character")

instance FileResourceEffect App where
  openedFile = do
    validateFileName
    FileName path <- require @FileName
    outcome <- liftIO $ tryIOError $
      bracketOnError (openFile path ReadWriteMode) hClose $ \file -> do
        hSetEncoding file utf8
        putStrLn ("[open] " ++ path)
        pure (OpenedFile (FileHandle path file))
    either (raise . FileResourceError . displayException) pure outcome

instance FileSessionEffect App where
  -- 开启期间 Context 保存真实 Handle，后续 require 复用它。
  openFileSession = do
    _ <- request @OpenedFile
    pure ()

  closeFileSession = do
    OpenedFile (FileHandle path file) <- require @OpenedFile
    outcome <- liftIO (tryIOError (hClose file))
    either (raise . FileSessionError . displayException) pure outcome
    liftIO (putStrLn ("[close] " ++ path))

instance ReadFileEffect App where
  fileText = do
    -- 末端也会引用 open；SDK 跳过同份已开启 scope 的方法体。
    openFileSession
    OpenedFile (FileHandle _ file) <- require @OpenedFile
    outcome <- liftIO $ tryIOError $ do
      hSeek file AbsoluteSeek 0
      -- 读完仍保留当前 Handle，供同一链随后写入；不使用会关闭它的 hGetContents。
      FileText <$> fix (\next characters -> do
        finished <- hIsEOF file
        if finished
          then pure (reverse characters)
          else hGetChar file >>= \character -> next (character : characters)) []
    either (raise . ReadFileError . displayException) pure outcome

instance FileRecoveryEffect App where
  detectFileSession = do
    OpenedFile (FileHandle _ file) <- require @OpenedFile
    outcome <- liftIO (tryIOError (hIsClosed file))
    closed <- either (raise . FileRecoveryError . displayException) pure outcome
    -- handles 已按故障类型粗定位；detect 只做值级细化：文件已关闭才归此处。
    unless closed $
      raise (FileRecoveryError "File handle is still open; failure not located in FileSession")

  -- 沿 superclass 引用配对的关闭方法；不重放读写，也不自动重开。
  resolveFileSession = closeFileSession

instance WriteFileEffect App where
  writeFileText = do
    FileText contents <- request @FileText
    OpenedFile (FileHandle path file) <- require @OpenedFile
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
    -- 本条链先取得稳定参数；校验和 scope 开启都 require 这份绑定。
    _ <- request @FileName
    openFileSession
    writeFileText
    -- 完整链退出后由 SDK 释放本次使用并自动关闭空闲实例。
