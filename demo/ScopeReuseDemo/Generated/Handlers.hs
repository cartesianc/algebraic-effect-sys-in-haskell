-- 自动生成的编译副本；请修改上级 Handlers.hs 后重新生成。
{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE ScopedTypeVariables #-}
-- handler 是不带参数的类方法：按表示类型 require 资产，用 raise 报告自己的失败。
-- 开启参数的刷新与 scope 开启由 gen 按注册装配，运行编译 Generated 副本。
{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE UndecidableInstances #-}

{-# OPTIONS_GHC -Werror=missing-methods #-}

module ScopeReuseDemo.Generated.Handlers (handlerSourceFingerprint, getFilePaths, readFilePaths, runPrepareProbe, getOpenedFile, readOpenedFile, openSharedFileScope, closeSharedFileScope, runWriteFirst, runWriteSecond, runWriteThird, runVerifyReuse, newScopeHandlers, errorHandlers) where

import qualified Framework.Generated as SDK
import qualified ScopeReuseDemo.Generated.Effects as Effects
import qualified Control.Monad.IO.Class as FrameworkIO
import qualified Data.Proxy as FrameworkProxy
import qualified GHC.TypeLits as FrameworkTypes
import Framework.SDK (Raises(..), Reads(..), rawoutput)
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
    rawoutput []

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
    rawoutput []

instance CloseSharedFileLayer m => CloseSharedFileHandler m where
  closeSharedFile = do
    SharedFile (SharedPaths _ journal) file <- require @SharedFile
    outcome <- liftIO $ tryIOError $ do
      appendFile journal "close-body\n"
      hClose file
      appendFile journal "file-close\n"
    either (raise . CloseSharedFileError . displayException) pure outcome
    rawoutput []

-- 每条链先由 requests 刷新参数，再经 Input 开启；scope 内 require 稳定参数，重叠使用时可共享实例。
-- 不在业务中加打开标志或互斥锁，也不为尚未开始的 Node 预留资源。
instance WriteFirstLayer m => WriteFirstHandler m where
  writeFirst = do
    SharedFile _ file <- require @SharedFile
    outcome <- liftIO $ tryIOError $ do
      hPutStr file "first\n"
      hFlush file
    either (raise . WriteFirstError . displayException) pure outcome
    rawoutput []

instance WriteSecondLayer m => WriteSecondHandler m where
  writeSecond = do
    SharedFile _ file <- require @SharedFile
    outcome <- liftIO $ tryIOError $ do
      hPutStr file "second\n"
      hFlush file
    either (raise . WriteSecondError . displayException) pure outcome
    rawoutput []

instance WriteThirdLayer m => WriteThirdHandler m where
  writeThird = do
    SharedFile _ file <- require @SharedFile
    outcome <- liftIO $ tryIOError $ do
      hPutStr file "third\n"
      hFlush file
    either (raise . WriteThirdError . displayException) pure outcome
    rawoutput []

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
    rawoutput []

-- 记录本编译副本实际使用的手写源码；启动前检查，避免执行过期方法体。
handlerSourceFingerprint :: Maybe String
handlerSourceFingerprint = Just "46df5382e1875f64d669496bd64d138b"

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

instance SDK.Reads SharedPaths (Wrap "PrepareProbe" method) where
  require = Wrap (SDK.coerce <$> readFilePaths)

instance SDK.Reads SharedPaths (Wrap "FileResource" method) where
  require = Wrap (SDK.coerce <$> readFilePaths)

instance SDK.Reads SharedFile (Wrap "SharedFileScope" method) where
  require = Wrap (SDK.coerce <$> readOpenedFile)

instance SDK.Reads SharedFile (Wrap "WriteFirst" method) where
  require = Wrap (SDK.coerce <$> readOpenedFile)

instance SDK.Reads SharedFile (Wrap "WriteSecond" method) where
  require = Wrap (SDK.coerce <$> readOpenedFile)

instance SDK.Reads SharedFile (Wrap "WriteThird" method) where
  require = Wrap (SDK.coerce <$> readOpenedFile)

instance SDK.Reads SharedPaths (Wrap "VerifyReuse" method) where
  require = Wrap (SDK.coerce <$> readFilePaths)

instance SDK.RawOutputs (Wrap effect method)

getFilePaths :: Effects.App Effects.FilePaths
getFilePaths =
  SDK.handleFailure
  . SDK.callContext "FileLocations"
      (\value bindings -> bindings { Effects.boundFileLocations = Just value }) $
    Effects.FilePaths <$> call @"FileLocations" @"sharedPaths" Effects.sharedPaths

readFilePaths :: Effects.App Effects.FilePaths
readFilePaths =
  SDK.handleFailure $
    SDK.readContext "FileLocations" Effects.ContextBindingError Effects.boundFileLocations

runPrepareProbe :: Effects.App [String]
runPrepareProbe =
  SDK.handleFailure
  . SDK.atomicHandle "runPrepareProbe" [] []
  . SDK.enterHandler "PrepareProbe" $
    getFilePaths >> call @"PrepareProbe" @"prepareProbe" Effects.prepareProbe

getOpenedFile :: Effects.App Effects.OpenedFile
getOpenedFile =
  SDK.handleFailure
  . SDK.callContext "FileResource"
      (\value bindings -> bindings { Effects.boundFileResource = Just value }) $
    Effects.OpenedFile <$> call @"FileResource" @"acquireFile" Effects.acquireFile

readOpenedFile :: Effects.App Effects.OpenedFile
readOpenedFile =
  SDK.handleFailure $
    SDK.readContext "FileResource" Effects.ContextBindingError Effects.boundFileResource

openSharedFileScope :: Effects.App [String]
openSharedFileScope =
  SDK.withErrorPath ["SharedFileScope"]
  . SDK.handleFailure
  . SDK.atomicScope "openSharedFileScope" [] []
  . SDK.openScope "SharedFileScope" Effects.ScopeBindingError (Just (() <$ closeSharedFileScope))
  . SDK.enterHandler "SharedFileScope" $
    getOpenedFile >> call @"SharedFileScope" @"openSharedFile" Effects.openSharedFile

closeSharedFileScope :: Effects.App [String]
closeSharedFileScope =
  SDK.withErrorPath ["SharedFileScope"]
  . SDK.handleFailure
  . SDK.atomicScope "closeSharedFileScope" [] []
  . SDK.closeScope "SharedFileScope" Effects.ScopeBindingError
  . SDK.enterHandler "SharedFileScope" $
    callClose @"SharedFileScope" @"closeSharedFile" Effects.closeSharedFile

runWriteFirst :: Effects.App [String]
runWriteFirst =
  SDK.withErrorPath ["SharedFileScope"]
  . SDK.handleFailure
  . SDK.atomicHandle "runWriteFirst" [] []
  . SDK.withScopeDependencies ["SharedFileScope"]
  . SDK.enterHandler "WriteFirst" $
    openSharedFileScope >> call @"WriteFirst" @"writeFirst" Effects.writeFirst

runWriteSecond :: Effects.App [String]
runWriteSecond =
  SDK.withErrorPath ["SharedFileScope"]
  . SDK.handleFailure
  . SDK.atomicHandle "runWriteSecond" [] []
  . SDK.withScopeDependencies ["SharedFileScope"]
  . SDK.enterHandler "WriteSecond" $
    openSharedFileScope >> call @"WriteSecond" @"writeSecond" Effects.writeSecond

runWriteThird :: Effects.App [String]
runWriteThird =
  SDK.withErrorPath ["SharedFileScope"]
  . SDK.handleFailure
  . SDK.atomicHandle "runWriteThird" [] []
  . SDK.withScopeDependencies ["SharedFileScope"]
  . SDK.enterHandler "WriteThird" $
    openSharedFileScope >> call @"WriteThird" @"writeThird" Effects.writeThird

runVerifyReuse :: Effects.App [String]
runVerifyReuse =
  SDK.handleFailure
  . SDK.atomicHandle "runVerifyReuse" [] []
  . SDK.enterHandler "VerifyReuse" $
    getFilePaths >> call @"VerifyReuse" @"verifyReuse" Effects.verifyReuse

-- SDK 内部：scope 按上游到下游登记，退出时逆序收尾；创建不执行业务方法。
newScopeHandlers :: IO [SDK.ScopeHandler Effects.ContextValues Effects.Errors]
newScopeHandlers = sequence
  [ SDK.newScopeHandler "SharedFileScope" ["FileLocations"] (Just "FileResource")
  ]

-- Error 回调登记：按 handles 匹配故障的 handler 与协议分类；关联 scope 由 Input 链推导。
errorHandlers :: [(Maybe String, SDK.ErrorHandler Effects.Errors Effects.App)]
errorHandlers = []
