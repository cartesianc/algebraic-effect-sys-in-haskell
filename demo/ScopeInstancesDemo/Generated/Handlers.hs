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
-- scope 的开启与关闭由 gen 按注册装配到使用闭包上，handler 中不调用 open／close。
{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE UndecidableInstances #-}

{-# OPTIONS_GHC -Werror=missing-methods #-}

module ScopeInstancesDemo.Generated.Handlers (handlerSourceFingerprint, runPrepareFiles, getFileName, readFileName, getOpenedFile, readOpenedFile, openFileSession, closeFileSession, runUseFirst, runSelectSecond, runUseSecond, runSelectFirst, runReopenFirst, runCheckJournal, newScopeHandlers, scopeCleanups, errorHandlers, contextInjections) where

import qualified Framework.Generated as FrameworkRuntime
import qualified ScopeInstancesDemo.Generated.Effects as FrameworkGenerated
import qualified Control.Monad.IO.Class as FrameworkIO
import qualified Data.Proxy as FrameworkProxy
import qualified GHC.TypeLits as FrameworkTypes
import ScopeInstancesDemo.Types
import Framework.SDK (Raises(..), Reads(..))
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
    pure []

-- 选择由普通 Excu 节点改写；下一条使用闭包的 requests 会重新读取它。
instance SelectSecondLayer m => SelectSecondHandler m where
  selectSecond = do
    let outputDirectory = "demo" </> "ScopeInstancesDemo" </> "output"
    outcome <- liftIO (tryIOError (writeFile (outputDirectory </> "selected.txt") (outputDirectory </> "two.txt")))
    either (raise . SelectSecondError . displayException) pure outcome
    pure []

instance SelectFirstLayer m => SelectFirstHandler m where
  selectFirst = do
    let outputDirectory = "demo" </> "ScopeInstancesDemo" </> "output"
    outcome <- liftIO (tryIOError (writeFile (outputDirectory </> "selected.txt") (outputDirectory </> "one.txt")))
    either (raise . SelectFirstError . displayException) pure outcome
    pure []

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
    pure []

instance CloseSelectedFileLayer m => CloseSelectedFileHandler m where
  closeSelectedFile = do
    FileHandle path file <- require @FileHandle
    let journal = "demo" </> "ScopeInstancesDemo" </> "output" </> "events.txt"
    outcome <- liftIO $ tryIOError $ do
      hClose file
      appendFile journal ("close " ++ path ++ "\n")
    either (raise . CloseSelectedFileError . displayException) pure outcome
    pure []

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
    pure []

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
    pure []

-- 记录本编译副本实际使用的手写源码；启动前检查，避免执行过期方法体。
handlerSourceFingerprint :: Maybe String
handlerSourceFingerprint = Just "78520366b00ac43b711576260bd83b06"

-- 以下由 gen 生成。每个 effect 一个类型标签：handler 在标签下执行，
-- 读取、raw 与错误按标签在编译期解析到这个 effect 的来源，不改写 handler 方法体。
newtype At (effect :: FrameworkTypes.Symbol) value = At { runAt :: FrameworkGenerated.App value }
  deriving (Functor, Applicative, Monad, FrameworkIO.MonadIO)

instance FrameworkTypes.KnownSymbol effect => FrameworkRuntime.Raises FrameworkGenerated.PrepareFilesError (At effect) where
  raise (FrameworkGenerated.PrepareFilesError description) = At (FrameworkRuntime.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) FrameworkGenerated.PrepareFilesFailure description)

instance FrameworkTypes.KnownSymbol effect => FrameworkRuntime.Raises FrameworkGenerated.SelectedFileError (At effect) where
  raise (FrameworkGenerated.SelectedFileError description) = At (FrameworkRuntime.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) FrameworkGenerated.SelectedFileFailure description)

instance FrameworkTypes.KnownSymbol effect => FrameworkRuntime.Raises FrameworkGenerated.AcquireFileError (At effect) where
  raise (FrameworkGenerated.AcquireFileError description) = At (FrameworkRuntime.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) FrameworkGenerated.AcquireFileFailure description)

instance FrameworkTypes.KnownSymbol effect => FrameworkRuntime.Raises FrameworkGenerated.OpenSelectedFileError (At effect) where
  raise (FrameworkGenerated.OpenSelectedFileError description) = At (FrameworkRuntime.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) FrameworkGenerated.OpenSelectedFileFailure description)

instance FrameworkTypes.KnownSymbol effect => FrameworkRuntime.Raises FrameworkGenerated.CloseSelectedFileError (At effect) where
  raise (FrameworkGenerated.CloseSelectedFileError description) = At (FrameworkRuntime.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) FrameworkGenerated.CloseSelectedFileFailure description)

instance FrameworkTypes.KnownSymbol effect => FrameworkRuntime.Raises FrameworkGenerated.CheckSelectionError (At effect) where
  raise (FrameworkGenerated.CheckSelectionError description) = At (FrameworkRuntime.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) FrameworkGenerated.CheckSelectionFailure description)

instance FrameworkTypes.KnownSymbol effect => FrameworkRuntime.Raises FrameworkGenerated.SelectSecondError (At effect) where
  raise (FrameworkGenerated.SelectSecondError description) = At (FrameworkRuntime.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) FrameworkGenerated.SelectSecondFailure description)

instance FrameworkTypes.KnownSymbol effect => FrameworkRuntime.Raises FrameworkGenerated.SelectFirstError (At effect) where
  raise (FrameworkGenerated.SelectFirstError description) = At (FrameworkRuntime.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) FrameworkGenerated.SelectFirstFailure description)

instance FrameworkTypes.KnownSymbol effect => FrameworkRuntime.Raises FrameworkGenerated.CheckJournalError (At effect) where
  raise (FrameworkGenerated.CheckJournalError description) = At (FrameworkRuntime.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) FrameworkGenerated.CheckJournalFailure description)

instance FrameworkRuntime.Reads ([Char]) (At "FileResource") where
  require = At ((\(FrameworkGenerated.FileName value) -> value) <$> readFileName)

instance FrameworkRuntime.Reads (FileHandle) (At "FileSession") where
  require = At ((\(FrameworkGenerated.OpenedFile value) -> value) <$> readOpenedFile)

instance FrameworkRuntime.Reads ([Char]) (At "UseFirst") where
  require = At ((\(FrameworkGenerated.FileName value) -> value) <$> readFileName)

instance FrameworkRuntime.Reads (FileHandle) (At "UseFirst") where
  require = At ((\(FrameworkGenerated.OpenedFile value) -> value) <$> readOpenedFile)

instance FrameworkRuntime.Reads ([Char]) (At "UseSecond") where
  require = At ((\(FrameworkGenerated.FileName value) -> value) <$> readFileName)

instance FrameworkRuntime.Reads (FileHandle) (At "UseSecond") where
  require = At ((\(FrameworkGenerated.OpenedFile value) -> value) <$> readOpenedFile)

instance FrameworkRuntime.Reads ([Char]) (At "ReopenFirst") where
  require = At ((\(FrameworkGenerated.FileName value) -> value) <$> readFileName)

instance FrameworkRuntime.Reads (FileHandle) (At "ReopenFirst") where
  require = At ((\(FrameworkGenerated.OpenedFile value) -> value) <$> readOpenedFile)

runPrepareFiles :: FrameworkGenerated.App [String]
runPrepareFiles = (FrameworkRuntime.withErrorPath [] . FrameworkRuntime.handleFailure . FrameworkRuntime.atomicHandle "runPrepareFiles" . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.enterHandler "PrepareFiles") $
  runAt @"PrepareFiles" FrameworkGenerated.prepareFiles

getFileName :: FrameworkGenerated.App FrameworkGenerated.FileName
getFileName = (FrameworkRuntime.withErrorPath [] . FrameworkRuntime.handleFailure . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.callContext "FileLocation"
    (\value bindings -> bindings { FrameworkGenerated.boundFileLocation = Just value })) $
  (FrameworkGenerated.FileName <$> runAt @"FileLocation" FrameworkGenerated.selectedFile)

readFileName :: FrameworkGenerated.App FrameworkGenerated.FileName
readFileName = (FrameworkRuntime.withErrorPath [] . FrameworkRuntime.handleFailure) $
  FrameworkRuntime.readContext "FileLocation" FrameworkGenerated.ContextBindingError FrameworkGenerated.boundFileLocation

getOpenedFile :: FrameworkGenerated.App FrameworkGenerated.OpenedFile
getOpenedFile = (FrameworkRuntime.withErrorPath [] . FrameworkRuntime.handleFailure . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.callContext "FileResource"
    (\value bindings -> bindings { FrameworkGenerated.boundFileResource = Just value })) $
  (FrameworkGenerated.OpenedFile <$> runAt @"FileResource" FrameworkGenerated.acquireFile)

readOpenedFile :: FrameworkGenerated.App FrameworkGenerated.OpenedFile
readOpenedFile = (FrameworkRuntime.withErrorPath [] . FrameworkRuntime.handleFailure) $
  FrameworkRuntime.readContext "FileResource" FrameworkGenerated.ContextBindingError FrameworkGenerated.boundFileResource

openFileSession :: FrameworkGenerated.App [String]
openFileSession = (FrameworkRuntime.withErrorPath ["FileSession"] . FrameworkRuntime.handleFailure . FrameworkRuntime.atomicScope "openFileSession" . FrameworkRuntime.openScope "FileSession" FrameworkGenerated.ScopeBindingError . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.enterHandler "FileSession") $
  getOpenedFile >> runAt @"FileSession" FrameworkGenerated.openSelectedFile

closeFileSession :: FrameworkGenerated.App [String]
closeFileSession = (FrameworkRuntime.withErrorPath ["FileSession"] . FrameworkRuntime.handleFailure . FrameworkRuntime.atomicScope "closeFileSession" . FrameworkRuntime.closeScope "FileSession" FrameworkGenerated.ScopeBindingError . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.enterHandler "FileSession") $
  runAt @"FileSession" FrameworkGenerated.closeSelectedFile

runUseFirst :: FrameworkGenerated.App [String]
runUseFirst = (FrameworkRuntime.withErrorPath ["FileSession"] . FrameworkRuntime.handleFailure . FrameworkRuntime.atomicHandle "runUseFirst" . FrameworkRuntime.withScopeDependencies ["FileSession"] . FrameworkRuntime.enterHandler "UseFirst") $
  getFileName >> openFileSession >> runAt @"UseFirst" FrameworkGenerated.checkSelection

runSelectSecond :: FrameworkGenerated.App [String]
runSelectSecond = (FrameworkRuntime.withErrorPath [] . FrameworkRuntime.handleFailure . FrameworkRuntime.atomicHandle "runSelectSecond" . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.enterHandler "SelectSecond") $
  runAt @"SelectSecond" FrameworkGenerated.selectSecond

runUseSecond :: FrameworkGenerated.App [String]
runUseSecond = (FrameworkRuntime.withErrorPath ["FileSession"] . FrameworkRuntime.handleFailure . FrameworkRuntime.atomicHandle "runUseSecond" . FrameworkRuntime.withScopeDependencies ["FileSession"] . FrameworkRuntime.enterHandler "UseSecond") $
  getFileName >> openFileSession >> runAt @"UseSecond" FrameworkGenerated.checkSelection

runSelectFirst :: FrameworkGenerated.App [String]
runSelectFirst = (FrameworkRuntime.withErrorPath [] . FrameworkRuntime.handleFailure . FrameworkRuntime.atomicHandle "runSelectFirst" . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.enterHandler "SelectFirst") $
  runAt @"SelectFirst" FrameworkGenerated.selectFirst

runReopenFirst :: FrameworkGenerated.App [String]
runReopenFirst = (FrameworkRuntime.withErrorPath ["FileSession"] . FrameworkRuntime.handleFailure . FrameworkRuntime.atomicHandle "runReopenFirst" . FrameworkRuntime.withScopeDependencies ["FileSession"] . FrameworkRuntime.enterHandler "ReopenFirst") $
  getFileName >> openFileSession >> runAt @"ReopenFirst" FrameworkGenerated.checkSelection

runCheckJournal :: FrameworkGenerated.App [String]
runCheckJournal = (FrameworkRuntime.withErrorPath [] . FrameworkRuntime.handleFailure . FrameworkRuntime.atomicHandle "runCheckJournal" . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.enterHandler "CheckJournal") $
  runAt @"CheckJournal" FrameworkGenerated.checkJournal

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

-- Error 回调登记：按 handles 匹配故障的 handler 与协议分类；关联 scope 由 Input 链推导。
errorHandlers :: [(Maybe String, FrameworkRuntime.ErrorHandler FrameworkGenerated.Errors FrameworkGenerated.App)]
errorHandlers =
  [
  ]

-- 挂在原子句柄下的 Context：句柄的输出交给它的 parser 解析并发布为资产；没有挂接时输出被丢弃。
contextInjections :: [(String, [(String, FrameworkGenerated.App ())])]
contextInjections =
  [
  ]
