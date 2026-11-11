-- handler 是不带参数的类方法：按表示类型 require 资产，用 raise 报告自己的失败。
-- 上游、scope 和资产名都不出现在这里；gen 按注册装配，运行编译 Generated 副本。
{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE UndecidableInstances #-}

{-# OPTIONS_GHC -Werror=missing-methods #-}

module FileDemo.Handlers () where

import Framework.SDK (Raises(..), Raw(..), Reads(..))
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

-- 示例专用文件：首次运行创建，后续追加；在项目根目录运行。原子句柄交出路径 list。
instance LocateFileLayer m => LocateFileHandler m where
  locateFile = pure ["demo" </> "FileDemo" </> "output.txt"]

-- Pure：raw 是上层交出的路径 list；逐项检查后原样交给下面的 parser。没有 IO，也不读资产。
instance ValidateFileNameLayer m => ValidateFileNameHandler m where
  validateFileName = do
    paths <- raw
    unless (all (\path -> not (null path) && '\0' `notElem` path) paths) $
      raise (ValidateFileNameError "File name must be nonempty and contain no NUL character")
    pure paths

-- Context 是细化 parser：通过检查的 list 恰好有一个路径时，才是文件名资产。
instance ParseFileNameLayer m => ParseFileNameHandler m where
  parseFileName = do
    paths <- raw
    case paths of
      [path] -> pure path
      _ -> raise (ParseFileNameError "Expected exactly one file name")

-- 文件名由 requests 驱动，生产时已经过 ValidateFileName 的检查。
instance AcquireFileLayer m => AcquireFileHandler m where
  acquireFile = do
    path <- require @FilePath
    outcome <- liftIO $ tryIOError $
      bracketOnError (openFile path ReadWriteMode) hClose $ \file -> do
        hSetEncoding file utf8
        putStrLn ("[open] " ++ path)
        pure (FileHandle path file)
    either (raise . AcquireFileError . displayException) pure outcome

-- requests 在开启前驱动 FileResource 打开文件；开启期间 Context 保存真实 Handle，后续 require 复用它。
instance OpenSessionLayer m => OpenSessionHandler m where
  openSession = pure []

instance CloseSessionLayer m => CloseSessionHandler m where
  closeSession = do
    FileHandle path file <- require @FileHandle
    outcome <- liftIO (tryIOError (hClose file))
    either (raise . CloseSessionError . displayException) pure outcome
    liftIO (putStrLn ("[close] " ++ path))
    pure []

-- 读取是原子句柄：只执行 IO，把读到的文本交出；FileText 由挂在它下面的 ExtractFileText 解析。
-- Input FileSession 已在它之前开启（同份已开启的 scope 不再执行 open）。
instance ReadFileContentLayer m => ReadFileContentHandler m where
  readFileContent = do
    FileHandle _ file <- require @FileHandle
    outcome <- liftIO $ tryIOError $ do
      hSeek file AbsoluteSeek 0
      -- 读完仍保留当前 Handle，供同一链随后写入；不使用会关闭它的 hGetContents。
      fix (\next characters -> do
        finished <- hIsEOF file
        if finished
          then pure (reverse characters)
          else hGetChar file >>= \character -> next (character : characters)) []
    contents <- either (raise . ReadFileContentError . displayException) pure outcome
    pure [contents]

-- parser 挂在读取句柄下：raw 是句柄本次交出的 list（一段文本），解析成文件状态（和类型）。
-- alternative 的选择读取驱动它：raw 执行读取句柄，读一次文件。
instance ParseFileTextLayer m => ParseFileTextHandler m where
  parseFileText = do
    contents <- raw
    text <- case contents of
      [whole] -> pure whole
      _ -> raise (ParseFileTextError "File read returned no text")
    pure (if null text then Blank else Written text)

instance DetectFileSessionLayer m => DetectFileSessionHandler m where
  detectFileSession = do
    FileHandle _ file <- require @FileHandle
    outcome <- liftIO (tryIOError (hIsClosed file))
    closed <- either (raise . DetectFileSessionError . displayException) pure outcome
    -- handles 已按 handler 粗定位；detect 只做值级细化：文件已关闭才归此处。
    unless closed $
      raise (DetectFileSessionError "File handle is still open; failure not located in FileSession")

-- TODO：Error 的处置是另一条驱动链，设计确定前 resolve 不做任何事；不调用 close，也不重放读写。
instance ResolveFileSessionLayer m => ResolveFileSessionHandler m where
  resolveFileSession = pure ()

-- 两个候选都是完整的写入链：Input FileSession 先开启文件，分支契约决定由哪个候选执行。
-- 选择在 AST 的 alternative 中自动完成，候选本身不判断条件；链退出后自动关闭文件。
instance WriteFirstLineLayer m => WriteFirstLineHandler m where
  writeFirstLine = do
    FileHandle path file <- require @FileHandle
    let line = "file-demo: the file was empty; this is the first line.\n"
    outcome <- liftIO $ tryIOError $ do
      putStrLn "[read] (empty file)"
      hSeek file SeekFromEnd 0
      hPutStr file line
      hFlush file
      putStrLn ("[write] " ++ path ++ ": " ++ line)
    either (raise . WriteFirstLineError . displayException) pure outcome
    pure []

instance AppendLineLayer m => AppendLineHandler m where
  appendLine = do
    contents <- require @String
    FileHandle path file <- require @FileHandle
    -- 明确消费读出的文本；只追加，不截断已有内容。
    let line = "file-demo: read " ++ show (length contents) ++ " characters before this append.\n"
    outcome <- liftIO $ tryIOError $ do
      putStrLn ("[read] " ++ contents)
      hSeek file SeekFromEnd 0
      hPutStr file line
      hFlush file
      putStrLn ("[write] " ++ path ++ ": " ++ line)
    either (raise . AppendLineError . displayException) pure outcome
    pure []
