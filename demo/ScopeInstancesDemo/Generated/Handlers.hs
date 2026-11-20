-- 自动生成的编译副本；请修改上级 Handlers.hs 后重新生成。
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
import Control.Exception (bracketOnError, displayException)
import Control.Monad (unless)
import Control.Monad.IO.Class (liftIO)
import System.Directory (createDirectoryIfMissing)
import System.FilePath ((</>), takeFileName)
import System.IO (IOMode(AppendMode), hClose, hFlush, hIsClosed, hPutStrLn, openFile, readFile')
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
    path <- require @FilePath
    let journal = "demo" </> "ScopeInstancesDemo" </> "output" </> "events.txt"
    outcome <- liftIO $ tryIOError $
      bracketOnError (openFile path AppendMode) hClose $ \file -> do
        appendFile journal ("acquire " ++ path ++ "\n")
        pure (FileHandle path file)
    either (raise . AcquireFileError . displayException) pure outcome

-- requests 在开启前驱动 FileResource 打开文件；open／close 只读取 scope 内的资源。
instance OpenSelectedFileLayer m => OpenSelectedFileHandler m where
  openSelectedFile = do
    FileHandle path _ <- require @FileHandle
    let journal = "demo" </> "ScopeInstancesDemo" </> "output" </> "events.txt"
    outcome <- liftIO (tryIOError (appendFile journal ("open " ++ path ++ "\n")))
    either (raise . OpenSelectedFileError . displayException) pure outcome
    rawoutput []

instance CloseSelectedFileLayer m => CloseSelectedFileHandler m where
  closeSelectedFile = do
    FileHandle path file <- require @FileHandle
    let journal = "demo" </> "ScopeInstancesDemo" </> "output" </> "events.txt"
    outcome <- liftIO $ tryIOError $ do
      hClose file
      appendFile journal ("close " ++ path ++ "\n")
    either (raise . CloseSelectedFileError . displayException) pure outcome
    rawoutput []

-- UseFirst、UseSecond、ReopenFirst 共用：scope 内 require 稳定参数与本条闭包选中的实例。
instance CheckSelectionLayer m => CheckSelectionHandler m where
  checkSelection = do
    selected <- require @FilePath
    FileHandle path file <- require @FileHandle
    closed <- liftIO (hIsClosed file)
    unless (path == selected && not closed) $
      raise (CheckSelectionError ("The instance does not match the current argument " ++ selected))
    outcome <- liftIO $ tryIOError $ do
      hPutStrLn file "used"
      hFlush file
    either (raise . CheckSelectionError . displayException) pure outcome
    liftIO (putStrLn ("[use] " ++ takeFileName path ++ ": the current argument selected this instance; its Handle is live"))
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
    liftIO $ do
      putStrLn "[check] each use closure opened the instance its current argument selected and closed it on exit"
      putStrLn "[check] actual acquisitions/closures: file 1 = 2/2; file 2 = 1/1"
      putStrLn "[check] three argument requests, three open calls; require reuses the stable parameter within each chain"
    rawoutput []

-- 记录本编译副本实际使用的手写源码；启动前检查，避免执行过期方法体。
handlerSourceFingerprint :: Maybe String
handlerSourceFingerprint = Just "41486932e45cadd7d9a7a352aa7f8739"

-- 以下由 gen 生成。每个 effect 一个类型标签：handler 在标签下执行，
-- 读取、rawinput 与错误按标签在编译期解析到这个 effect 的来源，不改写 handler 方法体。
newtype Wrap (effect :: FrameworkTypes.Symbol) value = Wrap { runWrap :: Effects.App value }
  deriving (Functor, Applicative, Monad, FrameworkIO.MonadIO)

instance SDK.Root (Wrap effect) value

instance FrameworkTypes.KnownSymbol effect => SDK.Raises Effects.PrepareFilesError (Wrap effect) where
  raise (Effects.PrepareFilesError description) = Wrap (SDK.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) Effects.PrepareFilesFailure description)

instance FrameworkTypes.KnownSymbol effect => SDK.Raises Effects.SelectedFileError (Wrap effect) where
  raise (Effects.SelectedFileError description) = Wrap (SDK.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) Effects.SelectedFileFailure description)

instance FrameworkTypes.KnownSymbol effect => SDK.Raises Effects.AcquireFileError (Wrap effect) where
  raise (Effects.AcquireFileError description) = Wrap (SDK.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) Effects.AcquireFileFailure description)

instance FrameworkTypes.KnownSymbol effect => SDK.Raises Effects.OpenSelectedFileError (Wrap effect) where
  raise (Effects.OpenSelectedFileError description) = Wrap (SDK.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) Effects.OpenSelectedFileFailure description)

instance FrameworkTypes.KnownSymbol effect => SDK.Raises Effects.CloseSelectedFileError (Wrap effect) where
  raise (Effects.CloseSelectedFileError description) = Wrap (SDK.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) Effects.CloseSelectedFileFailure description)

instance FrameworkTypes.KnownSymbol effect => SDK.Raises Effects.CheckSelectionError (Wrap effect) where
  raise (Effects.CheckSelectionError description) = Wrap (SDK.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) Effects.CheckSelectionFailure description)

instance FrameworkTypes.KnownSymbol effect => SDK.Raises Effects.SelectSecondError (Wrap effect) where
  raise (Effects.SelectSecondError description) = Wrap (SDK.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) Effects.SelectSecondFailure description)

instance FrameworkTypes.KnownSymbol effect => SDK.Raises Effects.SelectFirstError (Wrap effect) where
  raise (Effects.SelectFirstError description) = Wrap (SDK.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) Effects.SelectFirstFailure description)

instance FrameworkTypes.KnownSymbol effect => SDK.Raises Effects.CheckJournalError (Wrap effect) where
  raise (Effects.CheckJournalError description) = Wrap (SDK.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) Effects.CheckJournalFailure description)

instance SDK.Reads [Char] (Wrap "FileResource") where
  require = Wrap (SDK.coerce <$> readFileName)

instance SDK.Reads FileHandle (Wrap "FileSession") where
  require = Wrap (SDK.coerce <$> readOpenedFile)

instance SDK.Reads [Char] (Wrap "UseFirst") where
  require = Wrap (SDK.coerce <$> readFileName)

instance SDK.Reads FileHandle (Wrap "UseFirst") where
  require = Wrap (SDK.coerce <$> readOpenedFile)

instance SDK.Reads [Char] (Wrap "UseSecond") where
  require = Wrap (SDK.coerce <$> readFileName)

instance SDK.Reads FileHandle (Wrap "UseSecond") where
  require = Wrap (SDK.coerce <$> readOpenedFile)

instance SDK.Reads [Char] (Wrap "ReopenFirst") where
  require = Wrap (SDK.coerce <$> readFileName)

instance SDK.Reads FileHandle (Wrap "ReopenFirst") where
  require = Wrap (SDK.coerce <$> readOpenedFile)

instance SDK.RawOutputs (Wrap effect)

runPrepareFiles :: Effects.App [String]
runPrepareFiles =
  SDK.handleFailure
  . SDK.atomicHandle "runPrepareFiles" [] []
  . SDK.enterHandler "PrepareFiles" $
    runWrap @"PrepareFiles" (SDK.super "prepareFiles" Effects.prepareFiles)

getFileName :: Effects.App Effects.FileName
getFileName =
  SDK.handleFailure
  . SDK.callContext "FileLocation"
      (\value bindings -> bindings { Effects.boundFileLocation = Just value }) $
    Effects.FileName <$> runWrap @"FileLocation" (SDK.super "selectedFile" Effects.selectedFile)

readFileName :: Effects.App Effects.FileName
readFileName =
  SDK.handleFailure $
    SDK.readContext "FileLocation" Effects.ContextBindingError Effects.boundFileLocation

getOpenedFile :: Effects.App Effects.OpenedFile
getOpenedFile =
  SDK.handleFailure
  . SDK.callContext "FileResource"
      (\value bindings -> bindings { Effects.boundFileResource = Just value }) $
    Effects.OpenedFile <$> runWrap @"FileResource" (SDK.super "acquireFile" Effects.acquireFile)

readOpenedFile :: Effects.App Effects.OpenedFile
readOpenedFile =
  SDK.handleFailure $
    SDK.readContext "FileResource" Effects.ContextBindingError Effects.boundFileResource

openFileSession :: Effects.App [String]
openFileSession =
  SDK.withErrorPath ["FileSession"]
  . SDK.handleFailure
  . SDK.atomicScope "openFileSession" [] []
  . SDK.openScope "FileSession" Effects.ScopeBindingError (Just (() <$ closeFileSession))
  . SDK.enterHandler "FileSession" $
    getOpenedFile >> runWrap @"FileSession" (SDK.super "openSelectedFile" Effects.openSelectedFile)

closeFileSession :: Effects.App [String]
closeFileSession =
  SDK.withErrorPath ["FileSession"]
  . SDK.handleFailure
  . SDK.atomicScope "closeFileSession" [] []
  . SDK.closeScope "FileSession" Effects.ScopeBindingError
  . SDK.enterHandler "FileSession" $
    runWrap @"FileSession" (SDK.superClose "closeSelectedFile" Effects.closeSelectedFile)

runUseFirst :: Effects.App [String]
runUseFirst =
  SDK.withErrorPath ["FileSession"]
  . SDK.handleFailure
  . SDK.atomicHandle "runUseFirst" [] []
  . SDK.withScopeDependencies ["FileSession"]
  . SDK.enterHandler "UseFirst" $
    getFileName >> openFileSession >> runWrap @"UseFirst" (SDK.super "checkSelection" Effects.checkSelection)

runSelectSecond :: Effects.App [String]
runSelectSecond =
  SDK.handleFailure
  . SDK.atomicHandle "runSelectSecond" [] []
  . SDK.enterHandler "SelectSecond" $
    runWrap @"SelectSecond" (SDK.super "selectSecond" Effects.selectSecond)

runUseSecond :: Effects.App [String]
runUseSecond =
  SDK.withErrorPath ["FileSession"]
  . SDK.handleFailure
  . SDK.atomicHandle "runUseSecond" [] []
  . SDK.withScopeDependencies ["FileSession"]
  . SDK.enterHandler "UseSecond" $
    getFileName >> openFileSession >> runWrap @"UseSecond" (SDK.super "checkSelection" Effects.checkSelection)

runSelectFirst :: Effects.App [String]
runSelectFirst =
  SDK.handleFailure
  . SDK.atomicHandle "runSelectFirst" [] []
  . SDK.enterHandler "SelectFirst" $
    runWrap @"SelectFirst" (SDK.super "selectFirst" Effects.selectFirst)

runReopenFirst :: Effects.App [String]
runReopenFirst =
  SDK.withErrorPath ["FileSession"]
  . SDK.handleFailure
  . SDK.atomicHandle "runReopenFirst" [] []
  . SDK.withScopeDependencies ["FileSession"]
  . SDK.enterHandler "ReopenFirst" $
    getFileName >> openFileSession >> runWrap @"ReopenFirst" (SDK.super "checkSelection" Effects.checkSelection)

runCheckJournal :: Effects.App [String]
runCheckJournal =
  SDK.handleFailure
  . SDK.atomicHandle "runCheckJournal" [] []
  . SDK.enterHandler "CheckJournal" $
    runWrap @"CheckJournal" (SDK.super "checkJournal" Effects.checkJournal)

-- SDK 内部：scope 按上游到下游登记，退出时逆序收尾；创建不执行业务方法。
newScopeHandlers :: IO [SDK.ScopeHandler Effects.ContextValues Effects.Errors]
newScopeHandlers = sequence
  [ SDK.newScopeHandler "FileSession" ["FileLocation"] (Just "FileResource")
  ]

-- Error 回调登记：按 handles 匹配故障的 handler 与协议分类；关联 scope 由 Input 链推导。
errorHandlers :: [(Maybe String, SDK.ErrorHandler Effects.Errors Effects.App)]
errorHandlers = []
