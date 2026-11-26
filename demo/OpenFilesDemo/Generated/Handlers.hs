{-# OPTIONS_GHC -fexpose-all-unfoldings -fspecialise-aggressively #-}
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

module OpenFilesDemo.Generated.Handlers (handlerSourceFingerprint, getFileNames, readFileNames, getOpenedFiles, readOpenedFiles, openFileSession, closeFileSession, runHoldFiles, runInspectFiles, runReleaseFiles, runFinishInspection, newScopeHandlers, errorHandlers) where

import qualified Framework.Generated as SDK
import qualified OpenFilesDemo.Generated.Effects as Effects
import qualified Control.Monad.IO.Class as FrameworkIO
import qualified Data.Proxy as FrameworkProxy
import qualified GHC.TypeLits as FrameworkTypes
import Framework.SDK (Raises(..), Reads(..), rawoutput)
import OpenFilesDemo.Generated.Effects
import OpenFilesDemo.Types
import Control.Exception (bracketOnError, displayException)
import Control.Monad (filterM, forM_, unless)
import Control.Monad.IO.Class (liftIO)
import Data.List (nub)
import System.Directory (createDirectoryIfMissing, doesFileExist, removeFile)
import System.FilePath ((</>), takeDirectory)
import System.IO.Error (tryIOError)
import System.Mem (performGC)

instance ListFilesLayer m => ListFilesHandler m where
  listFiles = pure
    [ "demo" </> "OpenFilesDemo" </> "output" </> ("file-" ++ show index ++ ".txt")
    | index <- [1..10 :: Int]
    ]

instance AcquireFilesLayer m => AcquireFilesHandler m where
  acquireFiles = do
    paths <- require @[String]
    -- 整批取得：确保每个文件存在并在旁边记下开启标记 <path>.open；资产只记路径。
    -- 取得整批之后才由 scope 的 close 接管；中途失败则逆序撤销本批新建的标记。
    let acquire path rest = do
          createDirectoryIfMissing True (takeDirectory path)
          appendFile path ""
          let marker = path ++ ".open"
          existing <- doesFileExist marker
          if existing then rest else
            bracketOnError (writeFile marker "") (const (removeFile marker)) (const rest)
    outcome <- liftIO $ tryIOError $ foldr acquire (pure ()) paths
    either (raise . AcquireFilesError . displayException) pure outcome
    pure (FileHandles paths)

-- requests 在开启前驱动 FileResources 取得整批文件。
instance OpenFilesLayer m => OpenFilesHandler m where
  openFiles = do
    FileHandles paths <- require @FileHandles
    liftIO (putStrLn ("[open] acquired " ++ show (length paths) ++ " files"))
    rawoutput []

instance CloseFilesLayer m => CloseFilesHandler m where
  closeFiles = do
    FileHandles paths <- require @FileHandles
    outcome <- liftIO (tryIOError (mapM_ (removeFile . (++ ".open")) paths))
    either (raise . CloseFilesError . displayException) pure outcome
    liftIO (putStrLn ("[close] released " ++ show (length paths) ++ " files"))
    rawoutput []

-- HoldFiles 与 ReleaseFiles 共用：Input 已开启文件，本链只持有它们，链退出后 SDK 自动关闭。
instance HoldFilesLayer m => HoldFilesHandler m where
  holdFiles = rawoutput []

instance InspectFilesLayer m => InspectFilesHandler m where
  inspectFiles = do
    -- 前一 Node 的使用已经结束；本条链经 Input 重新开启，并持有自己的资源绑定。
    FileHandles paths <- require @FileHandles
    unless (length paths == 10 && length (nub paths) == 10) $
      raise (InspectFilesError "Expected ten distinct files")
    let openCount = length <$> filterM (doesFileExist . (++ ".open")) paths
    outcome <- liftIO $ tryIOError $ do
      beforeGC <- openCount
      putStrLn ("[check] current chain: " ++ show beforeGC ++ "/10 open")
      performGC
      afterGC <- openCount
      putStrLn ("[check] after GC, scope still retained: " ++ show afterGC ++ "/10 open")
      pure (beforeGC == 10 && afterGC == 10)
    remainedOpen <- either (raise . InspectFilesError . displayException) pure outcome
    unless remainedOpen (raise (InspectFilesError "A file closed without calling closeFiles"))
    -- 写入时由本 handler 按路径打开文件，写完即关闭。
    written <- liftIO $ tryIOError $ forM_ paths $ \path ->
      appendFile path "Still writable during this chain after GC; closeFiles has not run.\n"
    either (raise . InspectFilesError . displayException) pure written
    liftIO (putStrLn "[check] write and flush: 10/10 succeeded before close")
    -- 链退出后自动关闭；后续 Node 不继承这份活资源。
    rawoutput []

-- 前一个 node 的链已经退出，SDK 已关闭它持有的文件；这里重新列出文件名，只检查各文件的开启标记，
-- 不 require 已关闭的资源。
instance FinishInspectionLayer m => FinishInspectionHandler m where
  finishInspection = do
    paths <- require @[String]
    outcome <- liftIO (tryIOError (length <$> filterM (doesFileExist . (++ ".open")) paths))
    stillOpen <- either (raise . FinishInspectionError . displayException) pure outcome
    unless (length paths == 10 && stillOpen == 0) $
      raise (FinishInspectionError "Not all files closed after the scope closed")
    liftIO (putStrLn "[check] after the scope closed: 10/10 closed")
    rawoutput []

-- 记录本编译副本实际使用的手写源码；启动前检查，避免执行过期方法体。
handlerSourceFingerprint :: Maybe String
handlerSourceFingerprint = Just "846b99532877f92c6311f81b31352316"

-- 以下由 gen 生成。每个 effect 一个类型标签：handler 在标签下执行，
-- 读取、rawinput 与错误按标签在编译期解析到这个 effect 的来源，不改写 handler 方法体。
newtype Wrap (effect :: FrameworkTypes.Symbol) (method :: FrameworkTypes.Symbol) value = Wrap { runWrap :: Effects.App value }
  deriving (Functor, Applicative, Monad, FrameworkIO.MonadIO)

-- 类型标签上的名字：effect 名与方法名只写在标签上，需要字符串时从这里取。
nameOf :: forall name. FrameworkTypes.KnownSymbol name => String
nameOf = FrameworkTypes.symbolVal (FrameworkProxy.Proxy @name)

-- 在标签下执行 handler，交给 Root 的 superhandler；方法名取自标签。close 的调用点用 callClose。
call :: forall effect method value. (FrameworkTypes.KnownSymbol method)
  => Wrap effect method value -> Effects.App value
call handler = runWrap (SDK.super (nameOf @method) handler)

callClose :: forall effect method value. (FrameworkTypes.KnownSymbol method)
  => Wrap effect method value -> Effects.App value
callClose handler = runWrap (SDK.superClose (nameOf @method) handler)

instance SDK.Root (Wrap effect method) value

instance (SDK.HandlerError problem Effects.Errors, FrameworkTypes.KnownSymbol effect)
    => SDK.Raises problem (Wrap effect method) where
  raise problem = Wrap (SDK.failEffect (nameOf @effect) failure description)
    where (failure, description) = SDK.raised problem

instance SDK.Reads [[Char]] (Wrap "FileResources" method) where
  require = Wrap (SDK.coerce <$> readFileNames)

instance SDK.Reads FileHandles (Wrap "FileSession" method) where
  require = Wrap (SDK.coerce <$> readOpenedFiles)

instance SDK.Reads FileHandles (Wrap "InspectFiles" method) where
  require = Wrap (SDK.coerce <$> readOpenedFiles)

instance SDK.Reads [[Char]] (Wrap "FinishInspection" method) where
  require = Wrap (SDK.coerce <$> readFileNames)

instance SDK.RawOutputs (Wrap effect method)

getFileNames :: Effects.App Effects.FileNames
getFileNames =
  SDK.handleFailure
  . SDK.callContext (SDK.Slot 0 "FileLocations")
      (\value bindings -> bindings { Effects.boundFileLocations = Just value })
      Effects.boundFileLocations $
    Effects.FileNames <$> call @"FileLocations" @"listFiles" Effects.listFiles

readFileNames :: Effects.App Effects.FileNames
readFileNames =
  SDK.handleFailure $
    SDK.readContext (SDK.Slot 0 "FileLocations") Effects.ContextBindingError Effects.boundFileLocations

getOpenedFiles :: Effects.App Effects.OpenedFiles
getOpenedFiles =
  SDK.handleFailure
  . SDK.callContext (SDK.Slot 1 "FileResources")
      (\value bindings -> bindings { Effects.boundFileResources = Just value })
      Effects.boundFileResources $
    Effects.OpenedFiles <$> call @"FileResources" @"acquireFiles" Effects.acquireFiles

readOpenedFiles :: Effects.App Effects.OpenedFiles
readOpenedFiles =
  SDK.handleFailure $
    SDK.readContext (SDK.Slot 1 "FileResources") Effects.ContextBindingError Effects.boundFileResources

openFileSession :: Effects.App [String]
openFileSession =
  SDK.runOnce (SDK.Slot 2 "FileSession")
  . SDK.withErrorPath ["FileSession"]
  . SDK.handleFailure
  . SDK.atomicScope (SDK.Slot 2 "FileSession") []
  . SDK.openScope (SDK.Slot 2 "FileSession") Effects.ScopeBindingError (Just (() <$ closeFileSession))
  . SDK.enterHandler (SDK.Slot 2 "FileSession") $
    getOpenedFiles >> call @"FileSession" @"openFiles" Effects.openFiles

closeFileSession :: Effects.App [String]
closeFileSession =
  SDK.withErrorPath ["FileSession"]
  . SDK.handleFailure
  . SDK.atomicScope (SDK.Slot 2 "FileSession") []
  . SDK.closeScope (SDK.Slot 2 "FileSession") Effects.ScopeBindingError
  . SDK.enterHandler (SDK.Slot 2 "FileSession") $
    callClose @"FileSession" @"closeFiles" Effects.closeFiles

runHoldFiles :: Effects.App [String]
runHoldFiles =
  SDK.runOnce (SDK.Slot 3 "HoldFiles")
  . SDK.withErrorPath ["FileSession"]
  . SDK.handleFailure
  . SDK.withScopeDependencies [(SDK.Slot 2 "FileSession")]
  . SDK.enterHandler (SDK.Slot 3 "HoldFiles") $
    getFileNames >> openFileSession >> call @"HoldFiles" @"holdFiles" Effects.holdFiles

runInspectFiles :: Effects.App [String]
runInspectFiles =
  SDK.withErrorPath ["FileSession"]
  . SDK.handleFailure
  . SDK.withScopeDependencies [(SDK.Slot 2 "FileSession")]
  . SDK.enterHandler (SDK.Slot 4 "InspectFiles") $
    runHoldFiles >> call @"InspectFiles" @"inspectFiles" Effects.inspectFiles

runReleaseFiles :: Effects.App [String]
runReleaseFiles =
  SDK.withErrorPath ["FileSession"]
  . SDK.handleFailure
  . SDK.withScopeDependencies [(SDK.Slot 2 "FileSession")]
  . SDK.enterHandler (SDK.Slot 5 "ReleaseFiles") $
    runHoldFiles >> call @"ReleaseFiles" @"holdFiles" Effects.holdFiles

runFinishInspection :: Effects.App [String]
runFinishInspection =
  SDK.handleFailure
  . SDK.enterHandler (SDK.Slot 6 "FinishInspection") $
    getFileNames >> call @"FinishInspection" @"finishInspection" Effects.finishInspection

-- SDK 内部：scope 按上游到下游登记，退出时逆序收尾；创建不执行业务方法。
newScopeHandlers :: IO [SDK.ScopeHandler Effects.ContextValues Effects.Errors]
newScopeHandlers = sequence
  [ SDK.newScopeHandler (SDK.Slot 2 "FileSession") [(SDK.Slot 0 "FileLocations")] (Just (SDK.Slot 1 "FileResources"))
  ]

-- Error 回调登记：按 handles 匹配故障的 handler 与协议分类；关联 scope 由 Input 链推导。
errorHandlers :: [(Maybe String, SDK.ErrorHandler Effects.Errors Effects.App)]
errorHandlers = []
