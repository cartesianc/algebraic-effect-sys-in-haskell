-- 自动生成的编译副本；请修改上级 Handlers.hs 后重新生成。
{-# LANGUAGE TypeApplications #-}
-- 原生 Haskell 取值；SDK 生成方法入口包装，运行编译 Generated 副本。
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE UndecidableInstances #-}

{-# OPTIONS_GHC -Werror=missing-methods #-}

module OpenFilesDemo.Generated.Handlers (newScopeHandlers) where

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
  ( Handle, IOMode(ReadWriteMode), SeekMode(SeekFromEnd)
  , hClose, hFlush, hIsClosed, hPutStrLn, hSeek, hSetEncoding, openFile, utf8 )
import System.IO.Error (tryIOError)
import System.Mem (performGC)

instance FileLocationsEffect App where
  getFileNames =
    (FrameworkRoot.handler @FrameworkGenerated.Root . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.callContext "FileLocations" FrameworkGenerated.ContextBindingError
      [("FileResources", FrameworkRuntime.RequestValue)]
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
    (FrameworkRoot.handler @FrameworkGenerated.Root . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.callContext "FileResources" FrameworkGenerated.ContextBindingError
      [("FileSession", FrameworkRuntime.RequestValue), ("InspectFiles", FrameworkRuntime.RequireValue), ("FinishInspection", FrameworkRuntime.RequireValue)]
      Nothing
      FrameworkGenerated.boundFileResources
      (\value bindings -> bindings { FrameworkGenerated.boundFileResources = Just value })) $
      let
        acquireFiles = do
          FileNames paths <- getFileNames
          outcome <- liftIO (tryIOError (OpenedFiles <$> acquireAll paths))
          either (raise . FileResourcesError . displayException) pure outcome
      in acquireFiles

instance FileSessionEffect App where
  openFiles =
    (FrameworkRoot.handler @FrameworkGenerated.Root . FrameworkRuntime.openScope "FileSession" FrameworkGenerated.ScopeBindingError . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.enterHandler "FileSession") $
      let
        openFiles = do
          OpenedFiles files <- acquireFiles
          liftIO (putStrLn ("[open] acquired " ++ show (length files) ++ " files"))
      in openFiles

  closeFiles =
    (FrameworkRoot.handler @FrameworkGenerated.Root . FrameworkRuntime.closeScope "FileSession" FrameworkGenerated.ScopeBindingError . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.enterHandler "FileSession") $
      let
        closeFiles = do
          OpenedFiles files <- readOpenedFiles
          outcome <- liftIO (tryIOError (mapM_ (hClose . snd) files))
          either (raise . FileSessionError . displayException) pure outcome
          liftIO (putStrLn ("[close] released " ++ show (length files) ++ " files"))
      in closeFiles

instance HoldFilesEffect App where
  holdFiles =
    (FrameworkRoot.handler @FrameworkGenerated.Root . FrameworkRuntime.withScopeDependencies ["FileSession"] . FrameworkRuntime.enterHandler "HoldFiles") $
      let
        holdFiles = openFiles
      in holdFiles

instance InspectFilesEffect App where
  inspectFiles =
    (FrameworkRoot.handler @FrameworkGenerated.Root . FrameworkRuntime.withScopeDependencies ["FileSession"] . FrameworkRuntime.enterHandler "InspectFiles") $
      let
        inspectFiles = do
          -- 前一 Node 已返回；再次引用上游 open，SDK 应复用同一份 scope。
          holdFiles
          OpenedFiles files <- readOpenedFiles
          unless (length files == 10 && length (nub (map fst files)) == 10) $
            raise (InspectFilesError "Expected ten distinct files")
          outcome <- liftIO $ tryIOError $ do
            beforeGC <- mapM (hIsClosed . snd) files
            putStrLn ("[check] after previous Node returned: " ++ show (length (filter not beforeGC)) ++ "/10 open")
            performGC
            afterGC <- mapM (hIsClosed . snd) files
            putStrLn ("[check] after GC, scope still retained: " ++ show (length (filter not afterGC)) ++ "/10 open")
            pure (all not beforeGC && all not afterGC)
          remainedOpen <- either (raise . InspectFilesError . displayException) pure outcome
          unless remainedOpen (raise (InspectFilesError "A file closed without calling closeFiles"))
          written <- liftIO $ tryIOError $ forM_ files $ \(_, file) -> do
            hSeek file SeekFromEnd 0
            hPutStrLn file "Still writable after Node return and GC; closeFiles has not run."
            hFlush file
          either (raise . InspectFilesError . displayException) pure written
          liftIO (putStrLn "[check] write and flush: 10/10 succeeded before close")
      in inspectFiles

instance FinishInspectionEffect App where
  finishInspection =
    (FrameworkRoot.handler @FrameworkGenerated.Root . FrameworkRuntime.withScopeDependencies ["FileSession"] . FrameworkRuntime.enterHandler "FinishInspection") $
      let
        finishInspection = do
          -- 在关闭前取得 Handle，随后只检查本地快照，不向已关闭 scope 再次 require。
          OpenedFiles files <- readOpenedFiles
          closeFiles
          outcome <- liftIO (tryIOError (mapM (hIsClosed . snd) files))
          closed <- either (raise . FinishInspectionError . displayException) pure outcome
          unless (length closed == 10 && and closed) $
            raise (FinishInspectionError "Not all files closed after closeFiles")
          liftIO (putStrLn "[check] after explicit close: 10/10 closed")
      in finishInspection

-- 每个文件成功打开后继续获取其余文件；中途获取失败则释放已获取的文件。
-- 全部成功后交给 Context 保存，不在此处自动关闭。
acquireAll :: [FilePath] -> IO [(FilePath, Handle)]
acquireAll [] = pure []
acquireAll (path : paths) = do
  createDirectoryIfMissing True (takeDirectory path)
  bracketOnError (openFile path ReadWriteMode) hClose $ \file -> do
    hSetEncoding file utf8
    rest <- acquireAll paths
    pure ((path, file) : rest)


-- SDK 内部：每份 Scoped 句柄拥有自己的状态和 MVar；创建不执行业务方法。
newScopeHandlers :: IO [FrameworkRuntime.ScopeHandler FrameworkGenerated.ContextValues FrameworkGenerated.Errors]
newScopeHandlers = sequence
  [ FrameworkRuntime.newScopeHandler "FileSession" ["FileLocations"] (Just "FileResources")
  ]
