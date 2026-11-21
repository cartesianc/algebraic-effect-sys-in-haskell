-- 自动生成的编译副本；请修改上级 Handlers.hs 后重新生成。
{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE ScopedTypeVariables #-}
-- handler 是不带参数的类方法：按表示类型 require 资产，用 raise 报告自己的失败。
-- scope 的开启与关闭由 gen 按注册装配到使用闭包上，handler 中不调用 open／close。
{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE UndecidableInstances #-}

{-# OPTIONS_GHC -Werror=missing-methods #-}

module ScopeInstancesDemo.Generated.Handlers (handlerSourceFingerprint, runPrepareFiles, getFileName, readFileName, getOpenedFile, readOpenedFile, openFileSession, closeFileSession, runUseFirst, runSelectSecond, runUseSecond, runSelectFirst, runReopenFirst, runCheckJournal, newScopeHandlers, errorHandlers) where

import qualified Framework.Generated as SDK
import qualified ScopeInstancesDemo.Generated.Effects as Effects
import qualified Control.Monad.IO.Class as FrameworkIO
import qualified Data.Proxy as FrameworkProxy
import qualified GHC.TypeLits as FrameworkTypes
import Framework.SDK (Raises(..), Reads(..), rawoutput)
import ScopeInstancesDemo.Generated.Effects
import ScopeInstancesDemo.Types
import Control.Exception (displayException)
import Control.Monad (unless)
import Control.Monad.IO.Class (liftIO)
import System.Directory (createDirectoryIfMissing, doesFileExist, removeFile)
import System.FilePath ((</>), takeFileName)
import System.IO (readFile')
import System.IO.Error (tryIOError)

instance PrepareFilesLayer m => PrepareFilesHandler m where
  prepareFiles = do
    let outputDirectory = "demo" </> "ScopeInstancesDemo" </> "output"
    outcome <- liftIO $ tryIOError $ do
      createDirectoryIfMissing True outputDirectory
      -- 仅重置本 demo 的产物；初始选择第一份文件。
      mapM_ ((`writeFile` "") . (outputDirectory </>)) ["one.txt", "two.txt", "events.txt"]
      writeFile (outputDirectory </> "selected.txt") (outputDirectory </> "one.txt")
    either (raise . PrepareFilesError . displayException) pure outcome
    rawoutput []

-- 选择由普通 Excu 节点改写；下一条使用闭包的 requests 会重新读取它。
instance SelectSecondLayer m => SelectSecondHandler m where
  selectSecond = do
    let outputDirectory = "demo" </> "ScopeInstancesDemo" </> "output"
    outcome <- liftIO (tryIOError (writeFile (outputDirectory </> "selected.txt") (outputDirectory </> "two.txt")))
    either (raise . SelectSecondError . displayException) pure outcome
    rawoutput []

instance SelectFirstLayer m => SelectFirstHandler m where
  selectFirst = do
    let outputDirectory = "demo" </> "ScopeInstancesDemo" </> "output"
    outcome <- liftIO (tryIOError (writeFile (outputDirectory </> "selected.txt") (outputDirectory </> "one.txt")))
    either (raise . SelectFirstError . displayException) pure outcome
    rawoutput []

-- 参数确实由 parser 中的 IO 动态取得。观察日志不承担任何 scope 状态管理。
instance SelectedFileLayer m => SelectedFileHandler m where
  selectedFile = do
    let outputDirectory = "demo" </> "ScopeInstancesDemo" </> "output"
        journal = outputDirectory </> "events.txt"
    outcome <- liftIO $ tryIOError $ do
      path <- readFile' (outputDirectory </> "selected.txt")
      appendFile journal ("argument " ++ path ++ "\n")
      pure path
    either (raise . SelectedFileError . displayException) pure outcome

instance AcquireFileLayer m => AcquireFileHandler m where
  acquireFile = do
    path <- require @String
    let journal = "demo" </> "ScopeInstancesDemo" </> "output" </> "events.txt"
    -- 取得时确保文件存在，并在旁边记下开启标记 <path>.open；资产只记路径。
    outcome <- liftIO $ tryIOError $ do
      appendFile path ""
      writeFile (path ++ ".open") ""
      appendFile journal ("acquire " ++ path ++ "\n")
    either (raise . AcquireFileError . displayException) pure outcome
    pure (FileHandle path)

-- requests 在开启前驱动 FileResource 取得文件；open／close 只读取 scope 内的资源。
instance OpenSelectedFileLayer m => OpenSelectedFileHandler m where
  openSelectedFile = do
    FileHandle path <- require @FileHandle
    let journal = "demo" </> "ScopeInstancesDemo" </> "output" </> "events.txt"
    outcome <- liftIO (tryIOError (appendFile journal ("open " ++ path ++ "\n")))
    either (raise . OpenSelectedFileError . displayException) pure outcome
    rawoutput []

instance CloseSelectedFileLayer m => CloseSelectedFileHandler m where
  closeSelectedFile = do
    FileHandle path <- require @FileHandle
    let journal = "demo" </> "ScopeInstancesDemo" </> "output" </> "events.txt"
    outcome <- liftIO $ tryIOError $ do
      removeFile (path ++ ".open")
      appendFile journal ("close " ++ path ++ "\n")
    either (raise . CloseSelectedFileError . displayException) pure outcome
    rawoutput []

-- UseFirst、UseSecond、ReopenFirst 共用：scope 内 require 稳定参数与本条闭包选中的实例。
instance CheckSelectionLayer m => CheckSelectionHandler m where
  checkSelection = do
    selected <- require @String
    FileHandle path <- require @FileHandle
    live <- liftIO (doesFileExist (path ++ ".open"))
    unless (path == selected && live) $
      raise (CheckSelectionError ("The instance does not match the current argument " ++ selected))
    -- 写入时由本 handler 按路径打开文件，写完即关闭。
    outcome <- liftIO (tryIOError (appendFile path "used\n"))
    either (raise . CheckSelectionError . displayException) pure outcome
    liftIO (putStrLn ("[use] " ++ takeFileName path ++ ": the current argument selected this instance; it is open"))
    rawoutput []

-- 各使用闭包已退出并自动关闭实例；此处只读日志和文件，不 require 旧资源。
instance CheckJournalLayer m => CheckJournalHandler m where
  checkJournal = do
    let outputDirectory = "demo" </> "ScopeInstancesDemo" </> "output"
        firstFile = outputDirectory </> "one.txt"
        secondFile = outputDirectory </> "two.txt"
    outcome <- liftIO $ tryIOError $ do
      events <- readFile' (outputDirectory </> "events.txt")
      first <- readFile' firstFile
      second <- readFile' secondFile
      pure (lines events, lines first, lines second)
    (events, first, second) <- either (raise . CheckJournalError . displayException) pure outcome
    let expected =
          [ operation ++ path
          | path <- [firstFile, secondFile, firstFile]
          , operation <- ["argument ", "acquire ", "open ", "close "]
          ]
    unless (events == expected) $
      raise (CheckJournalError ("Unexpected lifecycle or extra Context evaluation: " ++ show events))
    unless (first == ["used", "used"] && second == ["used"]) $
      raise (CheckJournalError ("Unexpected file contents: " ++ show (first, second)))
    markers <- liftIO (mapM (doesFileExist . (++ ".open")) [firstFile, secondFile])
    unless (not (or markers)) $
      raise (CheckJournalError "An instance is still open after its use closure exited")
    liftIO $ do
      putStrLn "[check] each use closure opened the instance its current argument selected and closed it on exit"
      putStrLn "[check] actual acquisitions/closures: file 1 = 2/2; file 2 = 1/1"
      putStrLn "[check] three argument requests, three open calls; require reuses the stable parameter within each chain"
    rawoutput []

-- 记录本编译副本实际使用的手写源码；启动前检查，避免执行过期方法体。
handlerSourceFingerprint :: Maybe String
handlerSourceFingerprint = Just "629cab5983b93a570ec3e1d417b132ee"

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

instance SDK.Reads [Char] (Wrap "FileResource" method) where
  require = Wrap (SDK.coerce <$> readFileName)

instance SDK.Reads FileHandle (Wrap "FileSession" method) where
  require = Wrap (SDK.coerce <$> readOpenedFile)

instance SDK.Reads [Char] (Wrap "UseFirst" method) where
  require = Wrap (SDK.coerce <$> readFileName)

instance SDK.Reads FileHandle (Wrap "UseFirst" method) where
  require = Wrap (SDK.coerce <$> readOpenedFile)

instance SDK.Reads [Char] (Wrap "UseSecond" method) where
  require = Wrap (SDK.coerce <$> readFileName)

instance SDK.Reads FileHandle (Wrap "UseSecond" method) where
  require = Wrap (SDK.coerce <$> readOpenedFile)

instance SDK.Reads [Char] (Wrap "ReopenFirst" method) where
  require = Wrap (SDK.coerce <$> readFileName)

instance SDK.Reads FileHandle (Wrap "ReopenFirst" method) where
  require = Wrap (SDK.coerce <$> readOpenedFile)

instance SDK.RawOutputs (Wrap effect method)

runPrepareFiles :: Effects.App [String]
runPrepareFiles =
  SDK.runOnce (SDK.Slot 0 "PrepareFiles")
  . SDK.handleFailure
  . SDK.atomicHandle "runPrepareFiles" []
  . SDK.enterHandler (SDK.Slot 0 "PrepareFiles") $
    call @"PrepareFiles" @"prepareFiles" Effects.prepareFiles

getFileName :: Effects.App Effects.FileName
getFileName =
  SDK.handleFailure
  . SDK.callContext (SDK.Slot 1 "FileLocation")
      (\value bindings -> bindings { Effects.boundFileLocation = Just value })
      Effects.boundFileLocation $
    Effects.FileName <$> call @"FileLocation" @"selectedFile" Effects.selectedFile

readFileName :: Effects.App Effects.FileName
readFileName =
  SDK.handleFailure $
    SDK.readContext (SDK.Slot 1 "FileLocation") Effects.ContextBindingError Effects.boundFileLocation

getOpenedFile :: Effects.App Effects.OpenedFile
getOpenedFile =
  SDK.handleFailure
  . SDK.callContext (SDK.Slot 2 "FileResource")
      (\value bindings -> bindings { Effects.boundFileResource = Just value })
      Effects.boundFileResource $
    Effects.OpenedFile <$> call @"FileResource" @"acquireFile" Effects.acquireFile

readOpenedFile :: Effects.App Effects.OpenedFile
readOpenedFile =
  SDK.handleFailure $
    SDK.readContext (SDK.Slot 2 "FileResource") Effects.ContextBindingError Effects.boundFileResource

openFileSession :: Effects.App [String]
openFileSession =
  SDK.runOnce (SDK.Slot 3 "FileSession")
  . SDK.withErrorPath ["FileSession"]
  . SDK.handleFailure
  . SDK.atomicScope "openFileSession" []
  . SDK.openScope (SDK.Slot 3 "FileSession") Effects.ScopeBindingError (Just (() <$ closeFileSession))
  . SDK.enterHandler (SDK.Slot 3 "FileSession") $
    getOpenedFile >> call @"FileSession" @"openSelectedFile" Effects.openSelectedFile

closeFileSession :: Effects.App [String]
closeFileSession =
  SDK.withErrorPath ["FileSession"]
  . SDK.handleFailure
  . SDK.atomicScope "closeFileSession" []
  . SDK.closeScope (SDK.Slot 3 "FileSession") Effects.ScopeBindingError
  . SDK.enterHandler (SDK.Slot 3 "FileSession") $
    callClose @"FileSession" @"closeSelectedFile" Effects.closeSelectedFile

runUseFirst :: Effects.App [String]
runUseFirst =
  SDK.runOnce (SDK.Slot 4 "UseFirst")
  . SDK.withErrorPath ["FileSession"]
  . SDK.handleFailure
  . SDK.atomicHandle "runUseFirst" []
  . SDK.withScopeDependencies [(SDK.Slot 3 "FileSession")]
  . SDK.enterHandler (SDK.Slot 4 "UseFirst") $
    getFileName >> openFileSession >> call @"UseFirst" @"checkSelection" Effects.checkSelection

runSelectSecond :: Effects.App [String]
runSelectSecond =
  SDK.runOnce (SDK.Slot 5 "SelectSecond")
  . SDK.handleFailure
  . SDK.atomicHandle "runSelectSecond" []
  . SDK.enterHandler (SDK.Slot 5 "SelectSecond") $
    call @"SelectSecond" @"selectSecond" Effects.selectSecond

runUseSecond :: Effects.App [String]
runUseSecond =
  SDK.runOnce (SDK.Slot 6 "UseSecond")
  . SDK.withErrorPath ["FileSession"]
  . SDK.handleFailure
  . SDK.atomicHandle "runUseSecond" []
  . SDK.withScopeDependencies [(SDK.Slot 3 "FileSession")]
  . SDK.enterHandler (SDK.Slot 6 "UseSecond") $
    getFileName >> openFileSession >> call @"UseSecond" @"checkSelection" Effects.checkSelection

runSelectFirst :: Effects.App [String]
runSelectFirst =
  SDK.runOnce (SDK.Slot 7 "SelectFirst")
  . SDK.handleFailure
  . SDK.atomicHandle "runSelectFirst" []
  . SDK.enterHandler (SDK.Slot 7 "SelectFirst") $
    call @"SelectFirst" @"selectFirst" Effects.selectFirst

runReopenFirst :: Effects.App [String]
runReopenFirst =
  SDK.runOnce (SDK.Slot 8 "ReopenFirst")
  . SDK.withErrorPath ["FileSession"]
  . SDK.handleFailure
  . SDK.atomicHandle "runReopenFirst" []
  . SDK.withScopeDependencies [(SDK.Slot 3 "FileSession")]
  . SDK.enterHandler (SDK.Slot 8 "ReopenFirst") $
    getFileName >> openFileSession >> call @"ReopenFirst" @"checkSelection" Effects.checkSelection

runCheckJournal :: Effects.App [String]
runCheckJournal =
  SDK.runOnce (SDK.Slot 9 "CheckJournal")
  . SDK.handleFailure
  . SDK.atomicHandle "runCheckJournal" []
  . SDK.enterHandler (SDK.Slot 9 "CheckJournal") $
    call @"CheckJournal" @"checkJournal" Effects.checkJournal

-- SDK 内部：scope 按上游到下游登记，退出时逆序收尾；创建不执行业务方法。
newScopeHandlers :: IO [SDK.ScopeHandler Effects.ContextValues Effects.Errors]
newScopeHandlers = sequence
  [ SDK.newScopeHandler (SDK.Slot 3 "FileSession") [(SDK.Slot 1 "FileLocation")] (Just (SDK.Slot 2 "FileResource"))
  ]

-- Error 回调登记：按 handles 匹配故障的 handler 与协议分类；关联 scope 由 Input 链推导。
errorHandlers :: [(Maybe String, SDK.ErrorHandler Effects.Errors Effects.App)]
errorHandlers = []
