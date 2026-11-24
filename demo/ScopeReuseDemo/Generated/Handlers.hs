{-# OPTIONS_GHC -fexpose-all-unfoldings -fspecialise-aggressively #-}
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
import Control.Concurrent (threadDelay)
import Control.Exception (displayException)
import Control.Monad (unless)
import Control.Monad.IO.Class (liftIO)
import Data.List (sort)
import System.Directory (createDirectoryIfMissing)
import System.FilePath ((</>), takeDirectory)
import System.IO (readFile')
import System.IO.Error (isAlreadyInUseError, tryIOError)

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
    outcome <- liftIO $ tryIOError $ do
      appendFile path ""
      -- 记录资源获取；日志独立于 Context，重新产值不会清零它。
      appendFile journal "file-open\n"
    either (raise . AcquireFileError . displayException) pure outcome
    pure (SharedFile paths)

-- requests 在开启前驱动 FileResource 取得文件。
instance OpenSharedFileLayer m => OpenSharedFileHandler m where
  openSharedFile = do
    SharedFile (SharedPaths _ journal) <- require @SharedFile
    outcome <- liftIO (tryIOError (appendFile journal "open-body\n"))
    either (raise . OpenSharedFileError . displayException) pure outcome
    rawoutput []

instance CloseSharedFileLayer m => CloseSharedFileHandler m where
  closeSharedFile = do
    SharedFile (SharedPaths _ journal) <- require @SharedFile
    outcome <- liftIO $ tryIOError $ do
      appendFile journal "close-body\n"
      appendFile journal "file-close\n"
    either (raise . CloseSharedFileError . displayException) pure outcome
    rawoutput []

-- 每条链先由 requests 刷新参数，再经 Input 开启；scope 内 require 稳定参数，重叠使用时可共享实例。
-- 不在业务中加打开标志或互斥锁，也不为尚未开始的 Node 预留资源。
-- 资源只记路径，写入者在自己的执行中按路径追加；重叠的写入者同时追加时，GHC 的单进程文件锁
-- 会让后到者暂时失败（resource busy），稍后重试。
instance WriteFirstLayer m => WriteFirstHandler m where
  writeFirst = do
    SharedFile (SharedPaths path _) <- require @SharedFile
    let append remaining = tryIOError (appendFile path "first\n") >>= either
          (\failure -> if isAlreadyInUseError failure && remaining > (0 :: Int)
             then threadDelay 10000 >> append (remaining - 1) else ioError failure) pure
    outcome <- liftIO (tryIOError (append 50))
    either (raise . WriteFirstError . displayException) pure outcome
    rawoutput []

instance WriteSecondLayer m => WriteSecondHandler m where
  writeSecond = do
    SharedFile (SharedPaths path _) <- require @SharedFile
    let append remaining = tryIOError (appendFile path "second\n") >>= either
          (\failure -> if isAlreadyInUseError failure && remaining > (0 :: Int)
             then threadDelay 10000 >> append (remaining - 1) else ioError failure) pure
    outcome <- liftIO (tryIOError (append 50))
    either (raise . WriteSecondError . displayException) pure outcome
    rawoutput []

instance WriteThirdLayer m => WriteThirdHandler m where
  writeThird = do
    SharedFile (SharedPaths path _) <- require @SharedFile
    let append remaining = tryIOError (appendFile path "third\n") >>= either
          (\failure -> if isAlreadyInUseError failure && remaining > (0 :: Int)
             then threadDelay 10000 >> append (remaining - 1) else ioError failure) pure
    outcome <- liftIO (tryIOError (append 50))
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
handlerSourceFingerprint = Just "3064667593881e7ee18e00db631b7366"

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
  . SDK.callContext (SDK.Slot 0 "FileLocations")
      (\value bindings -> bindings { Effects.boundFileLocations = Just value })
      Effects.boundFileLocations $
    Effects.FilePaths <$> call @"FileLocations" @"sharedPaths" Effects.sharedPaths

readFilePaths :: Effects.App Effects.FilePaths
readFilePaths =
  SDK.handleFailure $
    SDK.readContext (SDK.Slot 0 "FileLocations") Effects.ContextBindingError Effects.boundFileLocations

runPrepareProbe :: Effects.App [String]
runPrepareProbe =
  SDK.runOnce (SDK.Slot 1 "PrepareProbe")
  . SDK.handleFailure
  . SDK.enterHandler (SDK.Slot 1 "PrepareProbe") $
    getFilePaths >> call @"PrepareProbe" @"prepareProbe" Effects.prepareProbe

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

openSharedFileScope :: Effects.App [String]
openSharedFileScope =
  SDK.runOnce (SDK.Slot 3 "SharedFileScope")
  . SDK.withErrorPath ["SharedFileScope"]
  . SDK.handleFailure
  . SDK.atomicScope (SDK.Slot 3 "SharedFileScope") []
  . SDK.openScope (SDK.Slot 3 "SharedFileScope") Effects.ScopeBindingError (Just (() <$ closeSharedFileScope))
  . SDK.enterHandler (SDK.Slot 3 "SharedFileScope") $
    getOpenedFile >> call @"SharedFileScope" @"openSharedFile" Effects.openSharedFile

closeSharedFileScope :: Effects.App [String]
closeSharedFileScope =
  SDK.withErrorPath ["SharedFileScope"]
  . SDK.handleFailure
  . SDK.atomicScope (SDK.Slot 3 "SharedFileScope") []
  . SDK.closeScope (SDK.Slot 3 "SharedFileScope") Effects.ScopeBindingError
  . SDK.enterHandler (SDK.Slot 3 "SharedFileScope") $
    callClose @"SharedFileScope" @"closeSharedFile" Effects.closeSharedFile

runWriteFirst :: Effects.App [String]
runWriteFirst =
  SDK.runOnce (SDK.Slot 4 "WriteFirst")
  . SDK.withErrorPath ["SharedFileScope"]
  . SDK.handleFailure
  . SDK.withScopeDependencies [(SDK.Slot 3 "SharedFileScope")]
  . SDK.enterHandler (SDK.Slot 4 "WriteFirst") $
    openSharedFileScope >> call @"WriteFirst" @"writeFirst" Effects.writeFirst

runWriteSecond :: Effects.App [String]
runWriteSecond =
  SDK.runOnce (SDK.Slot 5 "WriteSecond")
  . SDK.withErrorPath ["SharedFileScope"]
  . SDK.handleFailure
  . SDK.withScopeDependencies [(SDK.Slot 3 "SharedFileScope")]
  . SDK.enterHandler (SDK.Slot 5 "WriteSecond") $
    openSharedFileScope >> call @"WriteSecond" @"writeSecond" Effects.writeSecond

runWriteThird :: Effects.App [String]
runWriteThird =
  SDK.runOnce (SDK.Slot 6 "WriteThird")
  . SDK.withErrorPath ["SharedFileScope"]
  . SDK.handleFailure
  . SDK.withScopeDependencies [(SDK.Slot 3 "SharedFileScope")]
  . SDK.enterHandler (SDK.Slot 6 "WriteThird") $
    openSharedFileScope >> call @"WriteThird" @"writeThird" Effects.writeThird

runVerifyReuse :: Effects.App [String]
runVerifyReuse =
  SDK.runOnce (SDK.Slot 7 "VerifyReuse")
  . SDK.handleFailure
  . SDK.enterHandler (SDK.Slot 7 "VerifyReuse") $
    getFilePaths >> call @"VerifyReuse" @"verifyReuse" Effects.verifyReuse

-- SDK 内部：scope 按上游到下游登记，退出时逆序收尾；创建不执行业务方法。
newScopeHandlers :: IO [SDK.ScopeHandler Effects.ContextValues Effects.Errors]
newScopeHandlers = sequence
  [ SDK.newScopeHandler (SDK.Slot 3 "SharedFileScope") [(SDK.Slot 0 "FileLocations")] (Just (SDK.Slot 2 "FileResource"))
  ]

-- Error 回调登记：按 handles 匹配故障的 handler 与协议分类；关联 scope 由 Input 链推导。
errorHandlers :: [(Maybe String, SDK.ErrorHandler Effects.Errors Effects.App)]
errorHandlers = []
