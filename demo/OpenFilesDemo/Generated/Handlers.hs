-- 自动生成的编译副本；请修改上级 Handlers.hs 后重新生成。
{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE ScopedTypeVariables #-}
-- handler 是不带参数的类方法：按表示类型 require 资产，用 raise 报告自己的失败。
-- 开启、关闭与上游由 gen 按注册装配，运行编译 Generated 副本。
{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE UndecidableInstances #-}

{-# OPTIONS_GHC -Werror=missing-methods #-}

module OpenFilesDemo.Generated.Handlers (handlerSourceFingerprint, getFileNames, readFileNames, getOpenedFiles, readOpenedFiles, openFileSession, closeFileSession, runHoldFiles, runInspectFiles, runReleaseFiles, getInspectedFiles, readInspectedFiles, runFinishInspection, newScopeHandlers, errorHandlers) where

import qualified Framework.Generated as SDK
import qualified OpenFilesDemo.Generated.Effects as Effects
import qualified Control.Monad.IO.Class as FrameworkIO
import qualified Data.Proxy as FrameworkProxy
import qualified GHC.TypeLits as FrameworkTypes
import Framework.SDK (Raises(..), Reads(..), rawoutput)
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
    rawoutput []

instance CloseFilesLayer m => CloseFilesHandler m where
  closeFiles = do
    held <- require @[FileHandle]
    let files = [(path, file) | FileHandle path file <- held]
    outcome <- liftIO (tryIOError (mapM_ (hClose . snd) files))
    either (raise . CloseFilesError . displayException) pure outcome
    liftIO (putStrLn ("[close] released " ++ show (length files) ++ " files"))
    rawoutput []

-- 挂在 ReleaseFiles 下，记下本链持有的文件；值只经资产流动，关闭后的检查读取这份快照，不再 require 已关闭的资源。
instance SnapshotFilesLayer m => SnapshotFilesHandler m where
  snapshotFiles = require @[FileHandle]

-- HoldFiles 与 ReleaseFiles 共用：Input 已开启文件，本链只持有它们，链退出后 SDK 自动关闭。
instance HoldFilesLayer m => HoldFilesHandler m where
  holdFiles = rawoutput []

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
    rawoutput []

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
    rawoutput []

-- 记录本编译副本实际使用的手写源码；启动前检查，避免执行过期方法体。
handlerSourceFingerprint :: Maybe String
handlerSourceFingerprint = Just "51dd65515b772801e2460a0459aae292"

-- 以下由 gen 生成。每个 effect 一个类型标签：handler 在标签下执行，
-- 读取、rawinput 与错误按标签在编译期解析到这个 effect 的来源，不改写 handler 方法体。
newtype Wrap (effect :: FrameworkTypes.Symbol) (method :: FrameworkTypes.Symbol) value = Wrap { runWrap :: Effects.App value }
  deriving (Functor, Applicative, Monad, FrameworkIO.MonadIO)

-- 类型标签上的名字：effect 名与方法名只写在标签上，需要字符串时从这里取。
nameOf :: forall name. FrameworkTypes.KnownSymbol name => String
nameOf = FrameworkTypes.symbolVal (FrameworkProxy.Proxy @name)

-- 在标签下执行 handler，交给 Root 的 superhandler；方法名取自标签。close 的调用点用 callClose。
call :: forall effect method value. (FrameworkTypes.KnownSymbol method, SDK.Root (Wrap effect method) value)
  => Wrap effect method value -> Effects.App value
call handler = runWrap (SDK.super (nameOf @method) handler)

callClose :: forall effect method value. (FrameworkTypes.KnownSymbol method, SDK.Root (Wrap effect method) value)
  => Wrap effect method value -> Effects.App value
callClose handler = runWrap (SDK.superClose (nameOf @method) handler)

instance SDK.Root (Wrap effect method) value

instance (SDK.HandlerError problem Effects.Errors, FrameworkTypes.KnownSymbol effect)
    => SDK.Raises problem (Wrap effect method) where
  raise problem = Wrap (SDK.failEffect (nameOf @effect) failure description)
    where (failure, description) = SDK.raised problem

instance SDK.Reads [[Char]] (Wrap "FileResources" method) where
  require = Wrap (SDK.coerce <$> readFileNames)

instance SDK.Reads [FileHandle] (Wrap "FileSession" method) where
  require = Wrap (SDK.coerce <$> readOpenedFiles)

instance SDK.Reads [FileHandle] (Wrap "InspectFiles" method) where
  require = Wrap (SDK.coerce <$> readOpenedFiles)

instance SDK.Reads [FileHandle] (Wrap "InspectionSnapshot" method) where
  require = Wrap (SDK.coerce <$> readOpenedFiles)

instance SDK.Reads [FileHandle] (Wrap "FinishInspection" method) where
  require = Wrap (SDK.coerce <$> readInspectedFiles)

instance SDK.Raw (Wrap "InspectionSnapshot" "snapshotFiles") where
  rawinput = Wrap runReleaseFiles

instance SDK.RawOutputs (Wrap effect method)

getFileNames :: Effects.App Effects.FileNames
getFileNames =
  SDK.handleFailure
  . SDK.callContext "FileLocations"
      (\value bindings -> bindings { Effects.boundFileLocations = Just value }) $
    Effects.FileNames <$> call @"FileLocations" @"listFiles" Effects.listFiles

readFileNames :: Effects.App Effects.FileNames
readFileNames =
  SDK.handleFailure $
    SDK.readContext "FileLocations" Effects.ContextBindingError Effects.boundFileLocations

getOpenedFiles :: Effects.App Effects.OpenedFiles
getOpenedFiles =
  SDK.handleFailure
  . SDK.callContext "FileResources"
      (\value bindings -> bindings { Effects.boundFileResources = Just value }) $
    Effects.OpenedFiles <$> call @"FileResources" @"acquireFiles" Effects.acquireFiles

readOpenedFiles :: Effects.App Effects.OpenedFiles
readOpenedFiles =
  SDK.handleFailure $
    SDK.readContext "FileResources" Effects.ContextBindingError Effects.boundFileResources

openFileSession :: Effects.App [String]
openFileSession =
  SDK.withErrorPath ["FileSession"]
  . SDK.handleFailure
  . SDK.atomicScope "openFileSession" [] []
  . SDK.openScope "FileSession" Effects.ScopeBindingError (Just (() <$ closeFileSession))
  . SDK.enterHandler "FileSession" $
    getOpenedFiles >> call @"FileSession" @"openFiles" Effects.openFiles

closeFileSession :: Effects.App [String]
closeFileSession =
  SDK.withErrorPath ["FileSession"]
  . SDK.handleFailure
  . SDK.atomicScope "closeFileSession" [] []
  . SDK.closeScope "FileSession" Effects.ScopeBindingError
  . SDK.enterHandler "FileSession" $
    callClose @"FileSession" @"closeFiles" Effects.closeFiles

runHoldFiles :: Effects.App [String]
runHoldFiles =
  SDK.withErrorPath ["FileSession"]
  . SDK.handleFailure
  . SDK.atomicHandle "runHoldFiles" [] []
  . SDK.withScopeDependencies ["FileSession"]
  . SDK.enterHandler "HoldFiles" $
    getFileNames >> openFileSession >> call @"HoldFiles" @"holdFiles" Effects.holdFiles

runInspectFiles :: Effects.App [String]
runInspectFiles =
  SDK.withErrorPath ["FileSession"]
  . SDK.handleFailure
  . SDK.atomicHandle "runInspectFiles" [] []
  . SDK.withScopeDependencies ["FileSession"]
  . SDK.enterHandler "InspectFiles" $
    runHoldFiles >> call @"InspectFiles" @"inspectFiles" Effects.inspectFiles

runReleaseFiles :: Effects.App [String]
runReleaseFiles =
  SDK.withErrorPath ["FileSession"]
  . SDK.handleFailure
  . SDK.atomicHandle "runReleaseFiles" [("InspectionSnapshot", () <$ getInspectedFiles)] []
  . SDK.withScopeDependencies ["FileSession"]
  . SDK.enterHandler "ReleaseFiles" $
    runHoldFiles >> call @"ReleaseFiles" @"holdFiles" Effects.holdFiles

getInspectedFiles :: Effects.App Effects.InspectedFiles
getInspectedFiles =
  SDK.withErrorPath ["FileSession"]
  . SDK.handleFailure
  . SDK.withScopeDependencies ["FileSession"]
  . SDK.callContext "InspectionSnapshot"
      (\value bindings -> bindings { Effects.boundInspectionSnapshot = Just value }) $
    Effects.InspectedFiles <$> call @"InspectionSnapshot" @"snapshotFiles" Effects.snapshotFiles

readInspectedFiles :: Effects.App Effects.InspectedFiles
readInspectedFiles =
  SDK.withErrorPath ["FileSession"]
  . SDK.handleFailure $
    SDK.readContext "InspectionSnapshot" Effects.ContextBindingError Effects.boundInspectionSnapshot

runFinishInspection :: Effects.App [String]
runFinishInspection =
  SDK.handleFailure
  . SDK.atomicHandle "runFinishInspection" [] []
  . SDK.enterHandler "FinishInspection" $
    call @"FinishInspection" @"finishInspection" Effects.finishInspection

-- SDK 内部：scope 按上游到下游登记，退出时逆序收尾；创建不执行业务方法。
newScopeHandlers :: IO [SDK.ScopeHandler Effects.ContextValues Effects.Errors]
newScopeHandlers = sequence
  [ SDK.newScopeHandler "FileSession" ["FileLocations"] (Just "FileResources")
  ]

-- Error 回调登记：按 handles 匹配故障的 handler 与协议分类；关联 scope 由 Input 链推导。
errorHandlers :: [(Maybe String, SDK.ErrorHandler Effects.Errors Effects.App)]
errorHandlers = []
