-- 自动生成的编译副本；请修改上级 Handlers.hs 后重新生成。
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}
-- 原生 Haskell 取值；SDK 生成方法入口包装，运行编译 Generated 副本。
{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE UndecidableInstances #-}

{-# OPTIONS_GHC -Werror=missing-methods #-}

module FileDemo.Generated.Handlers (handlerSourceFingerprint, newScopeHandlers, scopeCleanups, errorHandlers, contextInjections) where

import qualified Framework.SDK as FrameworkRuntime
import qualified Framework.Effect.Contract as FrameworkRoot
import qualified FileDemo.Generated.Effects as FrameworkGenerated
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
  fileName =
    (FrameworkRoot.withErrorPath [] . FrameworkRoot.handler @FrameworkGenerated.Root . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.callContext "FileLocation" FrameworkGenerated.ContextBindingError
      [("ValidateFileName", FrameworkRuntime.RequireValue), ("FileResource", FrameworkRuntime.RequireValue)]
      (Just (FrameworkRuntime.ScopeInput "FileLocation"))
      FrameworkGenerated.boundFileLocation
      (\value bindings -> bindings { FrameworkGenerated.boundFileLocation = Just value })) $
      let
        fileName :: (m) (FrameworkGenerated.FileName)
        fileName = pure (FileName ("demo" </> "FileDemo" </> "output.txt"))
      in fileName

instance ValidateFileNameInputs m => ValidateFileNameEffect m where
  validateFileName =
    (FrameworkRoot.withErrorPath [] . FrameworkRoot.handler @FrameworkGenerated.Root . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.enterHandler "ValidateFileName") $
      let
        validateFileName :: (m) (())
        validateFileName = do
          FileName path <- require @FileName
          unless (not (null path) && '\0' `notElem` path) $
            raise (ValidateFileNameError "File name must be nonempty and contain no NUL character")
      in validateFileName

instance FileResourceInputs m => FileResourceEffect m where
  openedFile =
    (FrameworkRoot.withErrorPath [] . FrameworkRoot.handler @FrameworkGenerated.Root . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.callContext "FileResource" FrameworkGenerated.ContextBindingError
      [("FileSession", FrameworkRuntime.RequestValue), ("FileRecovery", FrameworkRuntime.RequireValue), ("ReadFile", FrameworkRuntime.RequireValue), ("WriteFirstLine", FrameworkRuntime.RequireValue), ("AppendLine", FrameworkRuntime.RequireValue)]
      Nothing
      FrameworkGenerated.boundFileResource
      (\value bindings -> bindings { FrameworkGenerated.boundFileResource = Just value })) $
      let
        openedFile :: (m) (FrameworkGenerated.OpenedFile)
        openedFile = do
          validateFileName
          FileName path <- require @FileName
          outcome <- liftIO $ tryIOError $
            bracketOnError (openFile path ReadWriteMode) hClose $ \file -> do
              hSetEncoding file utf8
              putStrLn ("[open] " ++ path)
              pure (OpenedFile (FileHandle path file))
          either (raise . FileResourceError . displayException) pure outcome
      in openedFile

instance FileSessionInputs m => FileSessionEffect m where
  -- 开启期间 Context 保存真实 Handle，后续 require 复用它。
  openFileSession =
    (FrameworkRoot.withErrorPath ["FileSession"] . FrameworkRoot.handler @FrameworkGenerated.Root . FrameworkRuntime.atomicScope "openFileSession" . FrameworkRuntime.openScope "FileSession" FrameworkGenerated.ScopeBindingError . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.enterHandler "FileSession") $
      let
        openFileSession :: (m) (Maybe String)
        openFileSession = do
          _ <- request @OpenedFile
          pure Nothing
      in openFileSession

  closeFileSession =
    (FrameworkRoot.withErrorPath ["FileSession"] . FrameworkRoot.handler @FrameworkGenerated.Root . FrameworkRuntime.atomicScope "closeFileSession" . FrameworkRuntime.closeScope "FileSession" FrameworkGenerated.ScopeBindingError . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.enterHandler "FileSession") $
      let
        closeFileSession :: (m) (Maybe String)
        closeFileSession = do
          OpenedFile (FileHandle path file) <- require @OpenedFile
          outcome <- liftIO (tryIOError (hClose file))
          either (raise . FileSessionError . displayException) pure outcome
          liftIO (putStrLn ("[close] " ++ path))
          pure Nothing
      in closeFileSession

-- 读取是原子句柄：只执行 IO，把读到的文本交出；FileText 由挂在它下面的 ExtractFileText 产出。
instance ReadFileInputs m => ReadFileEffect m where
  readFileContent =
    (FrameworkRoot.withErrorPath ["FileSession"] . FrameworkRoot.handler @FrameworkGenerated.Root . FrameworkRuntime.atomicHandle "readFileContent" . FrameworkRuntime.withScopeDependencies ["FileSession"] . FrameworkRuntime.enterHandler "ReadFile") $
      let
        readFileContent :: (m) (Maybe String)
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
      in readFileContent

-- 挂在读取句柄下，把读到的文本解析成文件状态（和类型）。alternative 启动时按 require 求值它：
-- state 中尚无值，便驱动读取句柄读一次文件。
instance ExtractFileTextInputs m => ExtractFileTextEffect m where
  fileText =
    (FrameworkRoot.withErrorPath ["FileSession"] . FrameworkRoot.handler @FrameworkGenerated.Root . FrameworkRuntime.withScopeDependencies ["FileSession"] . FrameworkRuntime.callContext "ExtractFileText" FrameworkGenerated.ContextBindingError
      [("WriteFirstLine", FrameworkRuntime.RequireValue), ("AppendLine", FrameworkRuntime.RequireValue)]
      Nothing
      FrameworkGenerated.boundExtractFileText
      (\value bindings -> bindings { FrameworkGenerated.boundExtractFileText = Just value })) $
      let
        fileText :: (m) (FrameworkGenerated.FileText)
        fileText = do
          contents <- readFileContent
          text <- maybe (raise (ExtractFileTextError "File read returned no text")) pure contents
          pure (FileText (if null text then Blank else Written text))
      in fileText

instance FileRecoveryInputs m => FileRecoveryEffect m where
  detectFileSession =
    (FrameworkRoot.withErrorPath ["FileSession"] . FrameworkRoot.handler @FrameworkGenerated.Root . FrameworkRuntime.withScopeDependencies ["FileSession"] . FrameworkRuntime.enterHandler "FileRecovery") $
      let
        detectFileSession :: (m) (())
        detectFileSession = do
          OpenedFile (FileHandle _ file) <- require @OpenedFile
          outcome <- liftIO (tryIOError (hIsClosed file))
          closed <- either (raise . FileRecoveryError . displayException) pure outcome
          -- handles 已按故障类型粗定位；detect 只做值级细化：文件已关闭才归此处。
          unless closed $
            raise (FileRecoveryError "File handle is still open; failure not located in FileSession")
      in detectFileSession

  -- 沿 superclass 引用配对的关闭方法；不重放读写，也不自动重开。
  resolveFileSession =
    (FrameworkRoot.withErrorPath ["FileSession"] . FrameworkRoot.handler @FrameworkGenerated.Root . FrameworkRuntime.withScopeDependencies ["FileSession"] . FrameworkRuntime.enterHandler "FileRecovery") $
      let
        resolveFileSession :: (m) (())
        resolveFileSession = do
          closeFileSession
          pure ()
      in resolveFileSession

-- 两个候选都是完整的写入链：各自开启文件，按分支契约取得文件状态后写入。
-- 选择在 AST 的 alternative 中自动完成，候选本身不判断条件；链退出后自动关闭文件。
instance WriteFirstLineInputs m => WriteFirstLineEffect m where
  writeFirstLine =
    (FrameworkRoot.withErrorPath ["FileSession"] . FrameworkRoot.handler @FrameworkGenerated.Root . FrameworkRuntime.atomicHandle "writeFirstLine" . FrameworkRuntime.withScopeDependencies ["FileSession"] . FrameworkRuntime.enterHandler "WriteFirstLine") $
      let
        writeFirstLine :: (m) (Maybe String)
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
      in writeFirstLine

instance AppendLineInputs m => AppendLineEffect m where
  appendLine =
    (FrameworkRoot.withErrorPath ["FileSession"] . FrameworkRoot.handler @FrameworkGenerated.Root . FrameworkRuntime.atomicHandle "appendLine" . FrameworkRuntime.withScopeDependencies ["FileSession"] . FrameworkRuntime.enterHandler "AppendLine") $
      let
        appendLine :: (m) (Maybe String)
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
      in appendLine

-- 记录本编译副本实际使用的手写源码；启动前检查，避免执行过期方法体。
handlerSourceFingerprint :: Maybe String
handlerSourceFingerprint = Just "1a81ce82019af319b6c911c4899e647c"


-- SDK 内部：scope 按上游到下游登记，退出时逆序收尾；创建不执行业务方法。
newScopeHandlers :: IO [FrameworkRuntime.ScopeHandler FrameworkGenerated.ContextValues FrameworkGenerated.Errors]
newScopeHandlers = sequence
  [ FrameworkRuntime.newScopeHandler "FileSession" ["FileLocation"] (Just "FileResource")
  ]

-- SDK 自动收尾入口；安装时不关闭资源。
scopeCleanups :: [(String, FrameworkGenerated.App ())]
scopeCleanups =
  [ ("FileSession", () <$ closeFileSession)
  ]

-- Error 回调登记：按 handles 匹配故障来源与分类；关联 scope 由 Input 链推导。
errorHandlers :: [(Maybe String, FrameworkRoot.ErrorHandler FrameworkGenerated.Errors FrameworkGenerated.App)]
errorHandlers =
  [ (Just "FileSession", FrameworkRoot.ErrorHandler "FileRecovery"
      (\failure -> case (FrameworkRoot.origin failure, FrameworkRoot.detail failure) of
        (_, FrameworkGenerated.ReadFileFailure) -> True
        (_, FrameworkGenerated.WriteFirstLineFailure) -> True
        (_, FrameworkGenerated.AppendLineFailure) -> True
        _ -> False)
      (Just detectFileSession) (Just resolveFileSession))
  ]

-- 挂在原子句柄下的 Context：句柄的输出交给它解析并发布为资产；没有挂接时输出被丢弃。
contextInjections :: [(String, [(String, FrameworkGenerated.App ())])]
contextInjections =
  [ ("readFileContent", [("ExtractFileText", () <$ fileText)])
  ]
