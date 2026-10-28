-- 原生 Haskell 取值；SDK 生成方法入口包装，运行编译 Generated 副本。
{-# LANGUAGE ConstraintKinds #-}
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

instance FileLocationInputs m => FileLocationEffect m where
  -- 示例专用文件：首次运行创建，后续追加；在项目根目录运行。
  fileName = pure (FileName ("demo" </> "FileDemo" </> "output.txt"))

instance ValidateFileNameInputs m => ValidateFileNameEffect m where
  validateFileName = do
    FileName path <- require @FileName
    unless (not (null path) && '\0' `notElem` path) $
      raise (ValidateFileNameError "File name must be nonempty and contain no NUL character")

instance FileResourceInputs m => FileResourceEffect m where
  openedFile = do
    validateFileName
    FileName path <- require @FileName
    outcome <- liftIO $ tryIOError $
      bracketOnError (openFile path ReadWriteMode) hClose $ \file -> do
        hSetEncoding file utf8
        putStrLn ("[open] " ++ path)
        pure (OpenedFile (FileHandle path file))
    either (raise . FileResourceError . displayException) pure outcome

instance FileSessionInputs m => FileSessionEffect m where
  -- 开启期间 Context 保存真实 Handle，后续 require 复用它。
  openFileSession = do
    _ <- request @OpenedFile
    pure Nothing

  closeFileSession = do
    OpenedFile (FileHandle path file) <- require @OpenedFile
    outcome <- liftIO (tryIOError (hClose file))
    either (raise . FileSessionError . displayException) pure outcome
    liftIO (putStrLn ("[close] " ++ path))
    pure Nothing

-- 读取是原子句柄：只执行 IO，把读到的文本交出；FileText 由挂在它下面的 ExtractFileText 产出。
instance ReadFileInputs m => ReadFileEffect m where
  readFileContent = do
    -- 末端也会引用 open；SDK 跳过同份已开启 scope 的方法体。
    openFileSession
    OpenedFile (FileHandle _ file) <- require @OpenedFile
    outcome <- liftIO $ tryIOError $ do
      hSeek file AbsoluteSeek 0
      -- 读完仍保留当前 Handle，供同一链随后写入；不使用会关闭它的 hGetContents。
      fix (\next characters -> do
        finished <- hIsEOF file
        if finished
          then pure (reverse characters)
          else hGetChar file >>= \character -> next (character : characters)) []
    contents <- either (raise . ReadFileError . displayException) pure outcome
    pure (Just contents)

-- 挂在读取句柄下，把读到的文本解析成文件状态（和类型）。alternative 启动时按 require 求值它：
-- state 中尚无值，便驱动读取句柄读一次文件。
instance ExtractFileTextInputs m => ExtractFileTextEffect m where
  fileText = do
    contents <- readFileContent
    text <- maybe (raise (ExtractFileTextError "File read returned no text")) pure contents
    pure (FileText (if null text then Blank else Written text))

instance FileRecoveryInputs m => FileRecoveryEffect m where
  detectFileSession = do
    OpenedFile (FileHandle _ file) <- require @OpenedFile
    outcome <- liftIO (tryIOError (hIsClosed file))
    closed <- either (raise . FileRecoveryError . displayException) pure outcome
    -- handles 已按故障类型粗定位；detect 只做值级细化：文件已关闭才归此处。
    unless closed $
      raise (FileRecoveryError "File handle is still open; failure not located in FileSession")

  -- 沿 superclass 引用配对的关闭方法；不重放读写，也不自动重开。
  resolveFileSession = do
    closeFileSession
    pure ()

-- 两个候选都是完整的写入链：各自开启文件，按分支契约取得文件状态后写入。
-- 选择在 AST 的 alternative 中自动完成，候选本身不判断条件；链退出后自动关闭文件。
instance WriteFirstLineInputs m => WriteFirstLineEffect m where
  writeFirstLine = do
    openFileSession
    _ <- require @FileTextBlank
    OpenedFile (FileHandle path file) <- require @OpenedFile
    let line = "file-demo: the file was empty; this is the first line.\n"
    outcome <- liftIO $ tryIOError $ do
      putStrLn "[read] (empty file)"
      hSeek file SeekFromEnd 0
      hPutStr file line
      hFlush file
      putStrLn ("[write] " ++ path ++ ": " ++ line)
    either (raise . WriteFirstLineError . displayException) pure outcome
    pure Nothing

instance AppendLineInputs m => AppendLineEffect m where
  appendLine = do
    openFileSession
    FileTextWritten contents <- require @FileTextWritten
    OpenedFile (FileHandle path file) <- require @OpenedFile
    -- 明确消费读出的文本；只追加，不截断已有内容。
    let line = "file-demo: read " ++ show (length contents) ++ " characters before this append.\n"
    outcome <- liftIO $ tryIOError $ do
      putStrLn ("[read] " ++ contents)
      hSeek file SeekFromEnd 0
      hPutStr file line
      hFlush file
      putStrLn ("[write] " ++ path ++ ": " ++ line)
    either (raise . AppendLineError . displayException) pure outcome
    pure Nothing
