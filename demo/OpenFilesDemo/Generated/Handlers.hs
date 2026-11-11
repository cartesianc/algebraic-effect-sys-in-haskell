-- 自动生成的编译副本；请修改上级 Handlers.hs 后重新生成。
{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE UndecidableInstances #-}
-- handler 是不带参数的类方法：按表示类型 require 资产，用 raise 报告自己的失败。
-- 开启、关闭与上游由 gen 按注册装配，运行编译 Generated 副本。
{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE UndecidableInstances #-}

{-# OPTIONS_GHC -Werror=missing-methods #-}

module OpenFilesDemo.Generated.Handlers (handlerSourceFingerprint, getFileNames, readFileNames, getOpenedFiles, readOpenedFiles, openFileSession, closeFileSession, runHoldFiles, runInspectFiles, runReleaseFiles, getInspectedFiles, readInspectedFiles, runFinishInspection, newScopeHandlers, scopeCleanups, errorHandlers, contextInjections) where

import qualified Framework.Generated as FrameworkRuntime
import qualified OpenFilesDemo.Generated.Effects as FrameworkGenerated
import qualified Control.Monad.IO.Class as FrameworkIO
import qualified Data.Proxy as FrameworkProxy
import qualified GHC.TypeLits as FrameworkTypes
import OpenFilesDemo.Types
import Framework.SDK (Raises(..), Reads(..))
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

instance ListFilesLayer m => ListFilesHandler m where
  listFiles = pure
    [ "demo" </> "OpenFilesDemo" </> "output" </> ("file-" ++ show index ++ ".txt")
    | index <- [1..10 :: Int]
    ]

instance AcquireFilesLayer m => AcquireFilesHandler m where
  acquireFiles = do
    paths <- require @[FilePath]
    -- 整批获取是本 Context 的原子操作；中途失败释放此前已打开的文件。
    outcome <- liftIO $ tryIOError $
      foldr (\path acquireRest -> do
        createDirectoryIfMissing True (takeDirectory path)
        bracketOnError (openFile path ReadWriteMode) hClose $ \file -> do
          hSetEncoding file utf8
          rest <- acquireRest
          pure (FileHandle path file : rest)) (pure []) paths
    either (raise . AcquireFilesError . displayException) pure outcome

-- requests 在开启前驱动 FileResources 打开整批文件。
instance OpenFilesLayer m => OpenFilesHandler m where
  openFiles = do
    files <- require @[FileHandle]
    liftIO (putStrLn ("[open] acquired " ++ show (length files) ++ " files"))
    pure []

instance CloseFilesLayer m => CloseFilesHandler m where
  closeFiles = do
    held <- require @[FileHandle]
    let files = [(path, file) | FileHandle path file <- held]
    outcome <- liftIO (tryIOError (mapM_ (hClose . snd) files))
    either (raise . CloseFilesError . displayException) pure outcome
    liftIO (putStrLn ("[close] released " ++ show (length files) ++ " files"))
    pure []

-- 挂在 ReleaseFiles 下，记下本链持有的文件；值只经资产流动，关闭后的检查读取这份快照，不再 require 已关闭的资源。
instance SnapshotFilesLayer m => SnapshotFilesHandler m where
  snapshotFiles = require @[FileHandle]

-- HoldFiles 与 ReleaseFiles 共用：Input 已开启文件，本链只持有它们，链退出后 SDK 自动关闭。
instance HoldFilesLayer m => HoldFilesHandler m where
  holdFiles = pure []

instance InspectFilesLayer m => InspectFilesHandler m where
  inspectFiles = do
    -- 前一 Node 的使用已经结束；本条链经 Input 重新开启，并持有自己的资源绑定。
    held <- require @[FileHandle]
    let files = [(path, file) | FileHandle path file <- held]
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
    -- 链退出后自动关闭；后续 Node 不继承这份活资源。
    pure []

-- 前一个 node 的链已经退出，SDK 已关闭它持有的文件；这里只检查快照中的 Handle。
instance FinishInspectionLayer m => FinishInspectionHandler m where
  finishInspection = do
    held <- require @[FileHandle]
    let files = [(path, file) | FileHandle path file <- held]
    outcome <- liftIO (tryIOError (mapM (hIsClosed . snd) files))
    closed <- either (raise . FinishInspectionError . displayException) pure outcome
    unless (length closed == 10 && and closed) $
      raise (FinishInspectionError "Not all files closed after the scope closed")
    liftIO (putStrLn "[check] after the scope closed: 10/10 closed")
    pure []

-- 记录本编译副本实际使用的手写源码；启动前检查，避免执行过期方法体。
handlerSourceFingerprint :: Maybe String
handlerSourceFingerprint = Just "63242e28103b32fa7873ea8d4096e691"

-- 以下由 gen 生成。每个 effect 一个类型标签：handler 在标签下执行，
-- 读取、raw 与错误按标签在编译期解析到这个 effect 的来源，不改写 handler 方法体。
newtype At (effect :: FrameworkTypes.Symbol) value = At { runAt :: FrameworkGenerated.App value }
  deriving (Functor, Applicative, Monad, FrameworkIO.MonadIO)

instance FrameworkTypes.KnownSymbol effect => FrameworkRuntime.Raises FrameworkGenerated.ListFilesError (At effect) where
  raise (FrameworkGenerated.ListFilesError description) = At (FrameworkRuntime.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) FrameworkGenerated.ListFilesFailure description)

instance FrameworkTypes.KnownSymbol effect => FrameworkRuntime.Raises FrameworkGenerated.AcquireFilesError (At effect) where
  raise (FrameworkGenerated.AcquireFilesError description) = At (FrameworkRuntime.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) FrameworkGenerated.AcquireFilesFailure description)

instance FrameworkTypes.KnownSymbol effect => FrameworkRuntime.Raises FrameworkGenerated.OpenFilesError (At effect) where
  raise (FrameworkGenerated.OpenFilesError description) = At (FrameworkRuntime.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) FrameworkGenerated.OpenFilesFailure description)

instance FrameworkTypes.KnownSymbol effect => FrameworkRuntime.Raises FrameworkGenerated.CloseFilesError (At effect) where
  raise (FrameworkGenerated.CloseFilesError description) = At (FrameworkRuntime.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) FrameworkGenerated.CloseFilesFailure description)

instance FrameworkTypes.KnownSymbol effect => FrameworkRuntime.Raises FrameworkGenerated.HoldFilesError (At effect) where
  raise (FrameworkGenerated.HoldFilesError description) = At (FrameworkRuntime.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) FrameworkGenerated.HoldFilesFailure description)

instance FrameworkTypes.KnownSymbol effect => FrameworkRuntime.Raises FrameworkGenerated.InspectFilesError (At effect) where
  raise (FrameworkGenerated.InspectFilesError description) = At (FrameworkRuntime.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) FrameworkGenerated.InspectFilesFailure description)

instance FrameworkTypes.KnownSymbol effect => FrameworkRuntime.Raises FrameworkGenerated.SnapshotFilesError (At effect) where
  raise (FrameworkGenerated.SnapshotFilesError description) = At (FrameworkRuntime.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) FrameworkGenerated.SnapshotFilesFailure description)

instance FrameworkTypes.KnownSymbol effect => FrameworkRuntime.Raises FrameworkGenerated.FinishInspectionError (At effect) where
  raise (FrameworkGenerated.FinishInspectionError description) = At (FrameworkRuntime.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) FrameworkGenerated.FinishInspectionFailure description)

instance FrameworkRuntime.Reads ([[Char]]) (At "FileResources") where
  require = At ((\(FrameworkGenerated.FileNames value) -> value) <$> readFileNames)

instance FrameworkRuntime.Reads ([FileHandle]) (At "FileSession") where
  require = At ((\(FrameworkGenerated.OpenedFiles value) -> value) <$> readOpenedFiles)

instance FrameworkRuntime.Reads ([FileHandle]) (At "InspectFiles") where
  require = At ((\(FrameworkGenerated.OpenedFiles value) -> value) <$> readOpenedFiles)

instance FrameworkRuntime.Reads ([FileHandle]) (At "InspectionSnapshot") where
  require = At ((\(FrameworkGenerated.OpenedFiles value) -> value) <$> readOpenedFiles)

instance FrameworkRuntime.Reads ([FileHandle]) (At "FinishInspection") where
  require = At ((\(FrameworkGenerated.InspectedFiles value) -> value) <$> readInspectedFiles)

instance FrameworkRuntime.Raw (At "InspectionSnapshot") where
  raw = At (runReleaseFiles)

getFileNames :: FrameworkGenerated.App FrameworkGenerated.FileNames
getFileNames = (FrameworkRuntime.withErrorPath [] . FrameworkRuntime.handleFailure . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.callContext "FileLocations"
    (Just (FrameworkRuntime.ScopeInput "FileLocations"))
    (\value bindings -> bindings { FrameworkGenerated.boundFileLocations = Just value })) $
  (FrameworkGenerated.FileNames <$> runAt @"FileLocations" FrameworkGenerated.listFiles)

readFileNames :: FrameworkGenerated.App FrameworkGenerated.FileNames
readFileNames = (FrameworkRuntime.withErrorPath [] . FrameworkRuntime.handleFailure) $
  FrameworkRuntime.readContext "FileLocations" FrameworkGenerated.ContextBindingError (Just (FrameworkRuntime.ScopeInput "FileLocations")) FrameworkGenerated.boundFileLocations

getOpenedFiles :: FrameworkGenerated.App FrameworkGenerated.OpenedFiles
getOpenedFiles = (FrameworkRuntime.withErrorPath [] . FrameworkRuntime.handleFailure . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.callContext "FileResources"
    Nothing
    (\value bindings -> bindings { FrameworkGenerated.boundFileResources = Just value })) $
  (FrameworkGenerated.OpenedFiles <$> runAt @"FileResources" FrameworkGenerated.acquireFiles)

readOpenedFiles :: FrameworkGenerated.App FrameworkGenerated.OpenedFiles
readOpenedFiles = (FrameworkRuntime.withErrorPath [] . FrameworkRuntime.handleFailure) $
  FrameworkRuntime.readContext "FileResources" FrameworkGenerated.ContextBindingError Nothing FrameworkGenerated.boundFileResources

openFileSession :: FrameworkGenerated.App [String]
openFileSession = (FrameworkRuntime.withErrorPath ["FileSession"] . FrameworkRuntime.handleFailure . FrameworkRuntime.atomicScope "openFileSession" . FrameworkRuntime.openScope "FileSession" FrameworkGenerated.ScopeBindingError . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.enterHandler "FileSession") $
  getOpenedFiles >> runAt @"FileSession" FrameworkGenerated.openFiles

closeFileSession :: FrameworkGenerated.App [String]
closeFileSession = (FrameworkRuntime.withErrorPath ["FileSession"] . FrameworkRuntime.handleFailure . FrameworkRuntime.atomicScope "closeFileSession" . FrameworkRuntime.closeScope "FileSession" FrameworkGenerated.ScopeBindingError . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.enterHandler "FileSession") $
  runAt @"FileSession" FrameworkGenerated.closeFiles

runHoldFiles :: FrameworkGenerated.App [String]
runHoldFiles = (FrameworkRuntime.withErrorPath ["FileSession"] . FrameworkRuntime.handleFailure . FrameworkRuntime.atomicHandle "runHoldFiles" . FrameworkRuntime.withScopeDependencies ["FileSession"] . FrameworkRuntime.enterHandler "HoldFiles") $
  getFileNames >> openFileSession >> runAt @"HoldFiles" FrameworkGenerated.holdFiles

runInspectFiles :: FrameworkGenerated.App [String]
runInspectFiles = (FrameworkRuntime.withErrorPath ["FileSession"] . FrameworkRuntime.handleFailure . FrameworkRuntime.atomicHandle "runInspectFiles" . FrameworkRuntime.withScopeDependencies ["FileSession"] . FrameworkRuntime.enterHandler "InspectFiles") $
  runHoldFiles >> runAt @"InspectFiles" FrameworkGenerated.inspectFiles

runReleaseFiles :: FrameworkGenerated.App [String]
runReleaseFiles = (FrameworkRuntime.withErrorPath ["FileSession"] . FrameworkRuntime.handleFailure . FrameworkRuntime.atomicHandle "runReleaseFiles" . FrameworkRuntime.withScopeDependencies ["FileSession"] . FrameworkRuntime.enterHandler "ReleaseFiles") $
  runHoldFiles >> runAt @"ReleaseFiles" FrameworkGenerated.holdFiles

getInspectedFiles :: FrameworkGenerated.App FrameworkGenerated.InspectedFiles
getInspectedFiles = (FrameworkRuntime.withErrorPath ["FileSession"] . FrameworkRuntime.handleFailure . FrameworkRuntime.withScopeDependencies ["FileSession"] . FrameworkRuntime.callContext "InspectionSnapshot"
    Nothing
    (\value bindings -> bindings { FrameworkGenerated.boundInspectionSnapshot = Just value })) $
  (FrameworkGenerated.InspectedFiles <$> runAt @"InspectionSnapshot" FrameworkGenerated.snapshotFiles)

readInspectedFiles :: FrameworkGenerated.App FrameworkGenerated.InspectedFiles
readInspectedFiles = (FrameworkRuntime.withErrorPath ["FileSession"] . FrameworkRuntime.handleFailure) $
  FrameworkRuntime.readContext "InspectionSnapshot" FrameworkGenerated.ContextBindingError Nothing FrameworkGenerated.boundInspectionSnapshot

runFinishInspection :: FrameworkGenerated.App [String]
runFinishInspection = (FrameworkRuntime.withErrorPath [] . FrameworkRuntime.handleFailure . FrameworkRuntime.atomicHandle "runFinishInspection" . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.enterHandler "FinishInspection") $
  runAt @"FinishInspection" FrameworkGenerated.finishInspection

-- SDK 内部：scope 按上游到下游登记，退出时逆序收尾；创建不执行业务方法。
newScopeHandlers :: IO [FrameworkRuntime.ScopeHandler FrameworkGenerated.ContextValues FrameworkGenerated.Errors]
newScopeHandlers = sequence
  [ FrameworkRuntime.newScopeHandler "FileSession" ["FileLocations"] (Just "FileResources")
  ]

-- SDK 自动收尾入口；安装时不关闭资源。
scopeCleanups :: [(String, FrameworkGenerated.App ())]
scopeCleanups =
  [ ("FileSession", () <$ closeFileSession)
  ]

-- Error 回调登记：按 handles 匹配故障的 handler 与协议分类；关联 scope 由 Input 链推导。
errorHandlers :: [(Maybe String, FrameworkRuntime.ErrorHandler FrameworkGenerated.Errors FrameworkGenerated.App)]
errorHandlers =
  [
  ]

-- 挂在原子句柄下的 Context：句柄的输出交给它的 parser 解析并发布为资产；没有挂接时输出被丢弃。
contextInjections :: [(String, [(String, FrameworkGenerated.App ())])]
contextInjections =
  [ ("runReleaseFiles", [("InspectionSnapshot", () <$ getInspectedFiles)])
  ]
