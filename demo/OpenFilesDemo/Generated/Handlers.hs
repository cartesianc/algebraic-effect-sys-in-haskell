-- 自动生成的编译副本；请修改上级 Handlers.hs 后重新生成。
{-# LANGUAGE TypeApplications #-}
-- 原生 Haskell 取值；SDK 生成方法入口包装，运行编译 Generated 副本。
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE UndecidableInstances #-}

{-# OPTIONS_GHC -Werror=missing-methods #-}

module OpenFilesDemo.Generated.Handlers (handlerSourceFingerprint, newScopeHandlers, scopeCleanups, errorHandlers) where

import qualified Framework.SDK as FrameworkRuntime
import qualified Framework.Effect.Contract as FrameworkRoot
import qualified OpenFilesDemo.Generated.Effects as FrameworkGenerated
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
  getFileNames =
    (FrameworkRoot.withErrorPath [] . FrameworkRoot.handler @FrameworkGenerated.Root . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.callContext "FileLocations" FrameworkGenerated.ContextBindingError
      [("FileResources", FrameworkRuntime.RequireValue), ("HoldFiles", FrameworkRuntime.RequestValue)]
      (Just (FrameworkRuntime.ScopeInput "FileLocations"))
      FrameworkGenerated.boundFileLocations
      (\value bindings -> bindings { FrameworkGenerated.boundFileLocations = Just value })) $
      let
        getFileNames = pure (FileNames
          [ "demo" </> "OpenFilesDemo" </> "output" </> ("file-" ++ show index ++ ".txt")
          | index <- [1..10 :: Int]
          ])
      in getFileNames

instance FileResourcesEffect App where
  acquireFiles =
    (FrameworkRoot.withErrorPath [] . FrameworkRoot.handler @FrameworkGenerated.Root . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.callContext "FileResources" FrameworkGenerated.ContextBindingError
      [("FileSession", FrameworkRuntime.RequestValue), ("InspectFiles", FrameworkRuntime.RequireValue), ("FinishInspection", FrameworkRuntime.RequireValue)]
      Nothing
      FrameworkGenerated.boundFileResources
      (\value bindings -> bindings { FrameworkGenerated.boundFileResources = Just value })) $
      let
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
      in acquireFiles

instance FileSessionEffect App where
  openFiles =
    (FrameworkRoot.withErrorPath ["FileSession"] . FrameworkRoot.handler @FrameworkGenerated.Root . FrameworkRuntime.openScope "FileSession" FrameworkGenerated.ScopeBindingError . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.enterHandler "FileSession") $
      let
        openFiles = do
          OpenedFiles files <- acquireFiles
          liftIO (putStrLn ("[open] acquired " ++ show (length files) ++ " files"))
      in openFiles

  closeFiles =
    (FrameworkRoot.withErrorPath ["FileSession"] . FrameworkRoot.handler @FrameworkGenerated.Root . FrameworkRuntime.closeScope "FileSession" FrameworkGenerated.ScopeBindingError . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.enterHandler "FileSession") $
      let
        closeFiles = do
          OpenedFiles files <- readOpenedFiles
          outcome <- liftIO (tryIOError (mapM_ (hClose . snd) files))
          either (raise . FileSessionError . displayException) pure outcome
          liftIO (putStrLn ("[close] released " ++ show (length files) ++ " files"))
      in closeFiles

instance HoldFilesEffect App where
  holdFiles =
    (FrameworkRoot.withErrorPath ["FileSession"] . FrameworkRoot.handler @FrameworkGenerated.Root . FrameworkRuntime.withScopeDependencies ["FileSession"] . FrameworkRuntime.enterHandler "HoldFiles") $
      let
        holdFiles = do
          _ <- getFileNames
          openFiles
      in holdFiles

instance InspectFilesEffect App where
  inspectFiles =
    (FrameworkRoot.withErrorPath ["FileSession"] . FrameworkRoot.handler @FrameworkGenerated.Root . FrameworkRuntime.withScopeDependencies ["FileSession"] . FrameworkRuntime.enterHandler "InspectFiles") $
      let
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
      in inspectFiles
    -- 链退出后自动关闭；后续 Node 不继承这份活资源。

instance FinishInspectionEffect App where
  finishInspection =
    (FrameworkRoot.withErrorPath ["FileSession"] . FrameworkRoot.handler @FrameworkGenerated.Root . FrameworkRuntime.withScopeDependencies ["FileSession"] . FrameworkRuntime.enterHandler "FinishInspection") $
      let
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
      in finishInspection

-- 记录本编译副本实际使用的手写源码；启动前检查，避免执行过期方法体。
handlerSourceFingerprint :: Maybe String
handlerSourceFingerprint = Just "62dc22bd6b725b9835d3f28d161870f0"


-- SDK 内部：scope 按上游到下游登记，退出时逆序收尾；创建不执行业务方法。
newScopeHandlers :: IO [FrameworkRuntime.ScopeHandler FrameworkGenerated.ContextValues FrameworkGenerated.Errors]
newScopeHandlers = sequence
  [ FrameworkRuntime.newScopeHandler "FileSession" ["FileLocations"] (Just "FileResources")
  ]

-- SDK 自动收尾入口；安装时不关闭资源。
scopeCleanups :: [(String, FrameworkGenerated.App ())]
scopeCleanups =
  [ ("FileSession", closeFiles)
  ]

-- Error 回调登记；记录 scope 对应的 detect/resolve，不在此执行检测。
errorHandlers :: [(String, FrameworkRoot.ErrorHandler FrameworkGenerated.App)]
errorHandlers =
  [
  ]
