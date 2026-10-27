-- 自动生成的编译副本；请修改上级 Handlers.hs 后重新生成。
{-# LANGUAGE TypeApplications #-}
-- 原生 Haskell 取值；SDK 生成方法入口包装，运行编译 Generated 副本。
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE UndecidableInstances #-}

{-# OPTIONS_GHC -Werror=missing-methods #-}

module FileDemo.Generated.Handlers (handlerSourceFingerprint, newScopeHandlers, scopeCleanups, errorHandlers) where

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

instance FileLocationEffect App where
  -- 示例专用文件：首次运行创建，后续追加；在项目根目录运行。
  fileName =
    (FrameworkRoot.withErrorPath [] . FrameworkRoot.handler @FrameworkGenerated.Root . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.callContext "FileLocation" FrameworkGenerated.ContextBindingError
      [("ValidateFileName", FrameworkRuntime.RequireValue), ("FileResource", FrameworkRuntime.RequireValue), ("FileWorkflow", FrameworkRuntime.RequestValue)]
      (Just (FrameworkRuntime.ScopeInput "FileLocation"))
      FrameworkGenerated.boundFileLocation
      (\value bindings -> bindings { FrameworkGenerated.boundFileLocation = Just value })) $
      let
        fileName = pure (FileName ("demo" </> "FileDemo" </> "output.txt"))
      in fileName

instance ValidateFileNameEffect App where
  validateFileName =
    (FrameworkRoot.withErrorPath [] . FrameworkRoot.handler @FrameworkGenerated.Root . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.enterHandler "ValidateFileName") $
      let
        validateFileName = do
          FileName path <- require @FileName
          unless (not (null path) && '\0' `notElem` path) $
            raise (ValidateFileNameError "File name must be nonempty and contain no NUL character")
      in validateFileName

instance FileResourceEffect App where
  openedFile =
    (FrameworkRoot.withErrorPath [] . FrameworkRoot.handler @FrameworkGenerated.Root . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.callContext "FileResource" FrameworkGenerated.ContextBindingError
      [("FileSession", FrameworkRuntime.RequestValue), ("FileRecovery", FrameworkRuntime.RequireValue), ("ReadFile", FrameworkRuntime.RequireValue), ("WriteFile", FrameworkRuntime.RequireValue)]
      Nothing
      FrameworkGenerated.boundFileResource
      (\value bindings -> bindings { FrameworkGenerated.boundFileResource = Just value })) $
      let
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

instance FileSessionEffect App where
  -- 开启期间 Context 保存真实 Handle，后续 require 复用它。
  openFileSession =
    (FrameworkRoot.withErrorPath ["FileSession"] . FrameworkRoot.handler @FrameworkGenerated.Root . FrameworkRuntime.openScope "FileSession" FrameworkGenerated.ScopeBindingError . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.enterHandler "FileSession") $
      let
        openFileSession = do
          _ <- request @OpenedFile
          pure ()
      in openFileSession

  closeFileSession =
    (FrameworkRoot.withErrorPath ["FileSession"] . FrameworkRoot.handler @FrameworkGenerated.Root . FrameworkRuntime.closeScope "FileSession" FrameworkGenerated.ScopeBindingError . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.enterHandler "FileSession") $
      let
        closeFileSession = do
          OpenedFile (FileHandle path file) <- require @OpenedFile
          outcome <- liftIO (tryIOError (hClose file))
          either (raise . FileSessionError . displayException) pure outcome
          liftIO (putStrLn ("[close] " ++ path))
      in closeFileSession

instance ReadFileEffect App where
  fileText =
    (FrameworkRoot.withErrorPath ["FileSession"] . FrameworkRoot.handler @FrameworkGenerated.Root . FrameworkRuntime.withScopeDependencies ["FileSession"] . FrameworkRuntime.callContext "ReadFile" FrameworkGenerated.ContextBindingError
      [("WriteFile", FrameworkRuntime.RequestValue)]
      Nothing
      FrameworkGenerated.boundReadFile
      (\value bindings -> bindings { FrameworkGenerated.boundReadFile = Just value })) $
      let
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
      in fileText

instance FileRecoveryEffect App where
  detectFileSession =
    (FrameworkRoot.withErrorPath ["FileSession"] . FrameworkRoot.handler @FrameworkGenerated.Root . FrameworkRuntime.withScopeDependencies ["FileSession"] . FrameworkRuntime.enterHandler "FileRecovery") $
      let
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
        resolveFileSession = closeFileSession
      in resolveFileSession

instance WriteFileEffect App where
  writeFileText =
    (FrameworkRoot.withErrorPath ["FileSession"] . FrameworkRoot.handler @FrameworkGenerated.Root . FrameworkRuntime.withScopeDependencies ["FileSession"] . FrameworkRuntime.enterHandler "WriteFile") $
      let
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
      in writeFileText

instance FileWorkflowEffect App where
  runFileWorkflow =
    (FrameworkRoot.withErrorPath ["FileSession"] . FrameworkRoot.handler @FrameworkGenerated.Root . FrameworkRuntime.withScopeDependencies ["FileSession"] . FrameworkRuntime.enterHandler "FileWorkflow") $
      let
        runFileWorkflow = do
          -- 本条链先取得稳定参数；校验和 scope 开启都 require 这份绑定。
          _ <- request @FileName
          openFileSession
          writeFileText
      in runFileWorkflow
    -- 完整链退出后由 SDK 释放本次使用并自动关闭空闲实例。

-- 记录本编译副本实际使用的手写源码；启动前检查，避免执行过期方法体。
handlerSourceFingerprint :: Maybe String
handlerSourceFingerprint = Just "da48e355f1ec6c604aa5ede8ac50b9f5"


-- SDK 内部：scope 按上游到下游登记，退出时逆序收尾；创建不执行业务方法。
newScopeHandlers :: IO [FrameworkRuntime.ScopeHandler FrameworkGenerated.ContextValues FrameworkGenerated.Errors]
newScopeHandlers = sequence
  [ FrameworkRuntime.newScopeHandler "FileSession" ["FileLocation"] (Just "FileResource")
  ]

-- SDK 自动收尾入口；安装时不关闭资源。
scopeCleanups :: [(String, FrameworkGenerated.App ())]
scopeCleanups =
  [ ("FileSession", closeFileSession)
  ]

-- Error 回调登记：按 handles 匹配故障来源与分类；关联 scope 由 Input 链推导。
errorHandlers :: [(Maybe String, FrameworkRoot.ErrorHandler FrameworkGenerated.Errors FrameworkGenerated.App)]
errorHandlers =
  [ (Just "FileSession", FrameworkRoot.ErrorHandler "FileRecovery"
      (\failure -> case (FrameworkRoot.origin failure, FrameworkRoot.detail failure) of
        (_, FrameworkGenerated.ReadFileFailure) -> True
        (_, FrameworkGenerated.WriteFileFailure) -> True
        _ -> False)
      (Just detectFileSession) (Just resolveFileSession))
  ]
