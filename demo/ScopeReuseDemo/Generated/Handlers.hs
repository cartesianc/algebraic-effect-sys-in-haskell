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
-- 开启参数的刷新与 scope 开启由 gen 按注册装配，运行编译 Generated 副本。
{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE UndecidableInstances #-}

{-# OPTIONS_GHC -Werror=missing-methods #-}

module ScopeReuseDemo.Generated.Handlers (handlerSourceFingerprint, getFilePaths, readFilePaths, runPrepareProbe, getOpenedFile, readOpenedFile, openSharedFileScope, closeSharedFileScope, runWriteFirst, runWriteSecond, runWriteThird, runVerifyReuse, newScopeHandlers, scopeCleanups, errorHandlers, contextInjections) where

import qualified Framework.Generated as FrameworkRuntime
import qualified ScopeReuseDemo.Generated.Effects as FrameworkGenerated
import qualified Control.Monad.IO.Class as FrameworkIO
import qualified Data.Proxy as FrameworkProxy
import qualified GHC.TypeLits as FrameworkTypes
import ScopeReuseDemo.Types
import Framework.SDK (Raises(..), Reads(..))
import ScopeReuseDemo.Generated.Effects
import ScopeReuseDemo.Types
import Control.Exception (bracketOnError, displayException)
import Control.Monad (unless)
import Control.Monad.IO.Class (liftIO)
import Data.List (sort)
import System.Directory (createDirectoryIfMissing)
import System.FilePath ((</>), takeDirectory)
import System.IO
  ( IOMode(AppendMode)
  , hClose, hFlush, hPutStr
  , hSetEncoding, openFile, readFile', utf8 )
import System.IO.Error (tryIOError)

instance SharedPathsLayer m => SharedPathsHandler m where
  sharedPaths = pure (SharedPaths
    ("demo" </> "ScopeReuseDemo" </> "output" </> "shared.txt")
    ("demo" </> "ScopeReuseDemo" </> "output" </> "events.txt"))

instance PrepareProbeLayer m => PrepareProbeHandler m where
  prepareProbe = do
    SharedPaths path journal <- require @SharedPaths
    outcome <- liftIO $ tryIOError $ do
      createDirectoryIfMissing True (takeDirectory path)
      -- 仅重置本 demo 的两份产物，在三个分支启动前完成。
      writeFile path ""
      writeFile journal ""
    either (raise . PrepareProbeError . displayException) pure outcome
    pure []

instance AcquireFileLayer m => AcquireFileHandler m where
  acquireFile = do
    paths@(SharedPaths path journal) <- require @SharedPaths
    outcome <- liftIO $ tryIOError $
      bracketOnError (openFile path AppendMode) hClose $ \file -> do
        hSetEncoding file utf8
        -- 记录真实资源获取；日志独立于 Context，重新产值不会清零它。
        appendFile journal "file-open\n"
        pure (SharedFile paths file)
    either (raise . AcquireFileError . displayException) pure outcome

-- requests 在开启前驱动 FileResource 打开文件。
instance OpenSharedFileLayer m => OpenSharedFileHandler m where
  openSharedFile = do
    SharedFile (SharedPaths _ journal) _ <- require @SharedFile
    outcome <- liftIO (tryIOError (appendFile journal "open-body\n"))
    either (raise . OpenSharedFileError . displayException) pure outcome
    pure []

instance CloseSharedFileLayer m => CloseSharedFileHandler m where
  closeSharedFile = do
    SharedFile (SharedPaths _ journal) file <- require @SharedFile
    outcome <- liftIO $ tryIOError $ do
      appendFile journal "close-body\n"
      hClose file
      appendFile journal "file-close\n"
    either (raise . CloseSharedFileError . displayException) pure outcome
    pure []

-- 每条链先由 requests 刷新参数，再经 Input 开启；scope 内 require 稳定参数，重叠使用时可共享实例。
-- 不在业务中加打开标志或互斥锁，也不为尚未开始的 Node 预留资源。
instance WriteFirstLayer m => WriteFirstHandler m where
  writeFirst = do
    SharedFile _ file <- require @SharedFile
    outcome <- liftIO $ tryIOError $ do
      hPutStr file "first\n"
      hFlush file
    either (raise . WriteFirstError . displayException) pure outcome
    pure []

instance WriteSecondLayer m => WriteSecondHandler m where
  writeSecond = do
    SharedFile _ file <- require @SharedFile
    outcome <- liftIO $ tryIOError $ do
      hPutStr file "second\n"
      hFlush file
    either (raise . WriteSecondError . displayException) pure outcome
    pure []

instance WriteThirdLayer m => WriteThirdHandler m where
  writeThird = do
    SharedFile _ file <- require @SharedFile
    outcome <- liftIO $ tryIOError $ do
      hPutStr file "third\n"
      hFlush file
    either (raise . WriteThirdError . displayException) pure outcome
    pure []

instance VerifyReuseLayer m => VerifyReuseHandler m where
  verifyReuse = do
    SharedPaths path journal <- require @SharedPaths
    -- parallel 已等待各链退出及自动清理；此处只读日志和文件，不 require 旧资源。
    outcome <- liftIO $ tryIOError $ do
      events <- readFile' journal
      content <- readFile' path
      pure (lines events, lines content)
    (events, content) <- either (raise . VerifyReuseError . displayException) pure outcome
    let openBodies = length (filter (== "open-body") events)
        fileOpens = length (filter (== "file-open") events)
        closeBodies = length (filter (== "close-body") events)
        fileCloses = length (filter (== "file-close") events)
        labels = ["first", "second", "third"]
    unless (fileOpens > 0 && openBodies == fileOpens
            && closeBodies == fileOpens && fileCloses == fileOpens) $
      raise (VerifyReuseError ("Acquisition and cleanup counts differ: " ++ show events))
    unless (sort content == labels) $
      raise (VerifyReuseError ("Unexpected file contents: " ++ show content))
    liftIO $ do
      putStrLn ("[check] actual resource opens/closes: " ++ show fileOpens ++ "/" ++ show fileCloses)
      putStrLn "[check] all writer chains released their resources; each line written exactly once"
    pure []

-- 记录本编译副本实际使用的手写源码；启动前检查，避免执行过期方法体。
handlerSourceFingerprint :: Maybe String
handlerSourceFingerprint = Just "f67952eb8185e826660c71f475062247"

-- 以下由 gen 生成。每个 effect 一个类型标签：handler 在标签下执行，
-- 读取、raw 与错误按标签在编译期解析到这个 effect 的来源，不改写 handler 方法体。
newtype At (effect :: FrameworkTypes.Symbol) value = At { runAt :: FrameworkGenerated.App value }
  deriving (Functor, Applicative, Monad, FrameworkIO.MonadIO)

instance FrameworkTypes.KnownSymbol effect => FrameworkRuntime.Raises FrameworkGenerated.SharedPathsError (At effect) where
  raise (FrameworkGenerated.SharedPathsError description) = At (FrameworkRuntime.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) FrameworkGenerated.SharedPathsFailure description)

instance FrameworkTypes.KnownSymbol effect => FrameworkRuntime.Raises FrameworkGenerated.PrepareProbeError (At effect) where
  raise (FrameworkGenerated.PrepareProbeError description) = At (FrameworkRuntime.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) FrameworkGenerated.PrepareProbeFailure description)

instance FrameworkTypes.KnownSymbol effect => FrameworkRuntime.Raises FrameworkGenerated.AcquireFileError (At effect) where
  raise (FrameworkGenerated.AcquireFileError description) = At (FrameworkRuntime.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) FrameworkGenerated.AcquireFileFailure description)

instance FrameworkTypes.KnownSymbol effect => FrameworkRuntime.Raises FrameworkGenerated.OpenSharedFileError (At effect) where
  raise (FrameworkGenerated.OpenSharedFileError description) = At (FrameworkRuntime.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) FrameworkGenerated.OpenSharedFileFailure description)

instance FrameworkTypes.KnownSymbol effect => FrameworkRuntime.Raises FrameworkGenerated.CloseSharedFileError (At effect) where
  raise (FrameworkGenerated.CloseSharedFileError description) = At (FrameworkRuntime.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) FrameworkGenerated.CloseSharedFileFailure description)

instance FrameworkTypes.KnownSymbol effect => FrameworkRuntime.Raises FrameworkGenerated.WriteFirstError (At effect) where
  raise (FrameworkGenerated.WriteFirstError description) = At (FrameworkRuntime.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) FrameworkGenerated.WriteFirstFailure description)

instance FrameworkTypes.KnownSymbol effect => FrameworkRuntime.Raises FrameworkGenerated.WriteSecondError (At effect) where
  raise (FrameworkGenerated.WriteSecondError description) = At (FrameworkRuntime.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) FrameworkGenerated.WriteSecondFailure description)

instance FrameworkTypes.KnownSymbol effect => FrameworkRuntime.Raises FrameworkGenerated.WriteThirdError (At effect) where
  raise (FrameworkGenerated.WriteThirdError description) = At (FrameworkRuntime.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) FrameworkGenerated.WriteThirdFailure description)

instance FrameworkTypes.KnownSymbol effect => FrameworkRuntime.Raises FrameworkGenerated.VerifyReuseError (At effect) where
  raise (FrameworkGenerated.VerifyReuseError description) = At (FrameworkRuntime.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) FrameworkGenerated.VerifyReuseFailure description)

instance FrameworkRuntime.Reads (SharedPaths) (At "PrepareProbe") where
  require = At ((\(FrameworkGenerated.FilePaths value) -> value) <$> readFilePaths)

instance FrameworkRuntime.Reads (SharedPaths) (At "FileResource") where
  require = At ((\(FrameworkGenerated.FilePaths value) -> value) <$> readFilePaths)

instance FrameworkRuntime.Reads (SharedFile) (At "SharedFileScope") where
  require = At ((\(FrameworkGenerated.OpenedFile value) -> value) <$> readOpenedFile)

instance FrameworkRuntime.Reads (SharedFile) (At "WriteFirst") where
  require = At ((\(FrameworkGenerated.OpenedFile value) -> value) <$> readOpenedFile)

instance FrameworkRuntime.Reads (SharedFile) (At "WriteSecond") where
  require = At ((\(FrameworkGenerated.OpenedFile value) -> value) <$> readOpenedFile)

instance FrameworkRuntime.Reads (SharedFile) (At "WriteThird") where
  require = At ((\(FrameworkGenerated.OpenedFile value) -> value) <$> readOpenedFile)

instance FrameworkRuntime.Reads (SharedPaths) (At "VerifyReuse") where
  require = At ((\(FrameworkGenerated.FilePaths value) -> value) <$> readFilePaths)

getFilePaths :: FrameworkGenerated.App FrameworkGenerated.FilePaths
getFilePaths = (FrameworkRuntime.withErrorPath [] . FrameworkRuntime.handleFailure . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.callContext "FileLocations"
    (Just (FrameworkRuntime.ScopeInput "FileLocations"))
    (\value bindings -> bindings { FrameworkGenerated.boundFileLocations = Just value })) $
  (FrameworkGenerated.FilePaths <$> runAt @"FileLocations" FrameworkGenerated.sharedPaths)

readFilePaths :: FrameworkGenerated.App FrameworkGenerated.FilePaths
readFilePaths = (FrameworkRuntime.withErrorPath [] . FrameworkRuntime.handleFailure) $
  FrameworkRuntime.readContext "FileLocations" FrameworkGenerated.ContextBindingError (Just (FrameworkRuntime.ScopeInput "FileLocations")) FrameworkGenerated.boundFileLocations

runPrepareProbe :: FrameworkGenerated.App [String]
runPrepareProbe = (FrameworkRuntime.withErrorPath [] . FrameworkRuntime.handleFailure . FrameworkRuntime.atomicHandle "runPrepareProbe" . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.enterHandler "PrepareProbe") $
  getFilePaths >> runAt @"PrepareProbe" FrameworkGenerated.prepareProbe

getOpenedFile :: FrameworkGenerated.App FrameworkGenerated.OpenedFile
getOpenedFile = (FrameworkRuntime.withErrorPath [] . FrameworkRuntime.handleFailure . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.callContext "FileResource"
    Nothing
    (\value bindings -> bindings { FrameworkGenerated.boundFileResource = Just value })) $
  (FrameworkGenerated.OpenedFile <$> runAt @"FileResource" FrameworkGenerated.acquireFile)

readOpenedFile :: FrameworkGenerated.App FrameworkGenerated.OpenedFile
readOpenedFile = (FrameworkRuntime.withErrorPath [] . FrameworkRuntime.handleFailure) $
  FrameworkRuntime.readContext "FileResource" FrameworkGenerated.ContextBindingError Nothing FrameworkGenerated.boundFileResource

openSharedFileScope :: FrameworkGenerated.App [String]
openSharedFileScope = (FrameworkRuntime.withErrorPath ["SharedFileScope"] . FrameworkRuntime.handleFailure . FrameworkRuntime.atomicScope "openSharedFileScope" . FrameworkRuntime.openScope "SharedFileScope" FrameworkGenerated.ScopeBindingError . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.enterHandler "SharedFileScope") $
  getOpenedFile >> runAt @"SharedFileScope" FrameworkGenerated.openSharedFile

closeSharedFileScope :: FrameworkGenerated.App [String]
closeSharedFileScope = (FrameworkRuntime.withErrorPath ["SharedFileScope"] . FrameworkRuntime.handleFailure . FrameworkRuntime.atomicScope "closeSharedFileScope" . FrameworkRuntime.closeScope "SharedFileScope" FrameworkGenerated.ScopeBindingError . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.enterHandler "SharedFileScope") $
  runAt @"SharedFileScope" FrameworkGenerated.closeSharedFile

runWriteFirst :: FrameworkGenerated.App [String]
runWriteFirst = (FrameworkRuntime.withErrorPath ["SharedFileScope"] . FrameworkRuntime.handleFailure . FrameworkRuntime.atomicHandle "runWriteFirst" . FrameworkRuntime.withScopeDependencies ["SharedFileScope"] . FrameworkRuntime.enterHandler "WriteFirst") $
  getFilePaths >> openSharedFileScope >> runAt @"WriteFirst" FrameworkGenerated.writeFirst

runWriteSecond :: FrameworkGenerated.App [String]
runWriteSecond = (FrameworkRuntime.withErrorPath ["SharedFileScope"] . FrameworkRuntime.handleFailure . FrameworkRuntime.atomicHandle "runWriteSecond" . FrameworkRuntime.withScopeDependencies ["SharedFileScope"] . FrameworkRuntime.enterHandler "WriteSecond") $
  getFilePaths >> openSharedFileScope >> runAt @"WriteSecond" FrameworkGenerated.writeSecond

runWriteThird :: FrameworkGenerated.App [String]
runWriteThird = (FrameworkRuntime.withErrorPath ["SharedFileScope"] . FrameworkRuntime.handleFailure . FrameworkRuntime.atomicHandle "runWriteThird" . FrameworkRuntime.withScopeDependencies ["SharedFileScope"] . FrameworkRuntime.enterHandler "WriteThird") $
  getFilePaths >> openSharedFileScope >> runAt @"WriteThird" FrameworkGenerated.writeThird

runVerifyReuse :: FrameworkGenerated.App [String]
runVerifyReuse = (FrameworkRuntime.withErrorPath [] . FrameworkRuntime.handleFailure . FrameworkRuntime.atomicHandle "runVerifyReuse" . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.enterHandler "VerifyReuse") $
  getFilePaths >> runAt @"VerifyReuse" FrameworkGenerated.verifyReuse

-- SDK 内部：scope 按上游到下游登记，退出时逆序收尾；创建不执行业务方法。
newScopeHandlers :: IO [FrameworkRuntime.ScopeHandler FrameworkGenerated.ContextValues FrameworkGenerated.Errors]
newScopeHandlers = sequence
  [ FrameworkRuntime.newScopeHandler "SharedFileScope" ["FileLocations"] (Just "FileResource")
  ]

-- SDK 自动收尾入口；安装时不关闭资源。
scopeCleanups :: [(String, FrameworkGenerated.App ())]
scopeCleanups =
  [ ("SharedFileScope", () <$ closeSharedFileScope)
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
