{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE EmptyDataDecls #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE UndecidableInstances #-}
{-# LANGUAGE UndecidableSuperClasses #-}

-- 自动生成；通过 SDK 的 effect-codegen 更新，手写注册与 handler 位于上级目录。
module ScopeReuseDemo.Generated.Effects where

import Framework.Effect.Contract (Effect(..), Registered)
import qualified Framework.Effect.Contract as FrameworkRoot
import qualified Framework.SDK as SDK
import ScopeReuseDemo.Types

-- SDK 提供运行载体与空存储；Context 经声明的 request/require 取得。
type Root = SDK.Root ContextValues Errors
type App = SDK.App ContextValues Errors

-- 方法定义身份；仅生成区使用，图中不以字符串匹配方法。
data MethodGen = GetFilePathsGen | ReadFilePathsGen | PrepareProbeGen | AcquireFileGen | ReadOpenedFileGen | OpenSharedFileGen | CloseSharedFileGen | WriteFirstGen | WriteSecondGen | WriteThirdGen | VerifyReuseGen
  deriving (Eq, Ord, Show, Read, SDK.Generic)
instance SDK.NFData MethodGen

data FileLocations

class (Effect Root m) => FileLocationsEffect m where
  getFilePaths :: m (Produce FileLocations)
  readFilePaths :: m (Produce FileLocations)
  readFilePaths = (FrameworkRoot.withErrorPath [] . FrameworkRoot.handler @Root) $
    SDK.readContext "FileLocations" ContextBindingError (Just (SDK.ScopeInput "FileLocations")) boundFileLocations
  {-# MINIMAL getFilePaths #-}

instance (Monad m, Effect Root m, FileLocationsEffect m) => Effect FileLocations m where
  type Registration FileLocations = Registered FileLocationsEffect Root
  type Typing FileLocations = 'SDK.ContextKind
  type Require FileLocations = SDK.Void
  type Produce FileLocations = FilePaths
  type Error FileLocations = FileLocationsError
  raise (FileLocationsError description) = SDK.failEffect "FileLocations" FileLocationsFailure description
  handler = FrameworkRoot.handler @Root

data PrepareProbe

class (Effect Root m, Effect FileLocations m, Produce FileLocations ~ (FilePaths)) => PrepareProbeEffect m where
  prepareProbe :: m ()
  {-# MINIMAL prepareProbe #-}

instance (Monad m, Effect Root m, PrepareProbeEffect m) => Effect PrepareProbe m where
  type Registration PrepareProbe = Registered PrepareProbeEffect Root
  type Typing PrepareProbe = 'SDK.ExcuKind
  type Require PrepareProbe = FilePaths
  type Error PrepareProbe = PrepareProbeError
  raise (PrepareProbeError description) = SDK.failEffect "PrepareProbe" PrepareProbeFailure description
  handler = FrameworkRoot.handler @Root

data FileResource

class (Effect Root m, Effect FileLocations m, Produce FileLocations ~ (FilePaths)) => FileResourceEffect m where
  acquireFile :: m (Produce FileResource)
  readOpenedFile :: m (Produce FileResource)
  readOpenedFile = (FrameworkRoot.withErrorPath [] . FrameworkRoot.handler @Root) $
    SDK.readContext "FileResource" ContextBindingError Nothing boundFileResource
  {-# MINIMAL acquireFile #-}

instance (Monad m, Effect Root m, FileResourceEffect m) => Effect FileResource m where
  type Registration FileResource = Registered FileResourceEffect Root
  type Typing FileResource = 'SDK.ContextKind
  type Require FileResource = FilePaths
  type Produce FileResource = OpenedFile
  type Error FileResource = FileResourceError
  raise (FileResourceError description) = SDK.failEffect "FileResource" FileResourceFailure description
  handler = FrameworkRoot.handler @Root

data SharedFileScope

class (Effect Root m, Effect FileResource m, Produce FileResource ~ (OpenedFile)) => SharedFileScopeEffect m where
  openSharedFile :: m ()
  closeSharedFile :: m ()
  {-# MINIMAL openSharedFile, closeSharedFile #-}

instance (Monad m, Effect Root m, SharedFileScopeEffect m) => Effect SharedFileScope m where
  type Registration SharedFileScope = Registered SharedFileScopeEffect Root
  type Typing SharedFileScope = 'SDK.ScopedKind
  type Require SharedFileScope = (OpenedFile, OpenedFile)
  type Error SharedFileScope = SharedFileScopeError
  raise (SharedFileScopeError description) = SDK.failEffect "SharedFileScope" SharedFileScopeFailure description
  handler = FrameworkRoot.handler @Root

data WriteFirst

class (Effect SharedFileScope m, Effect FileLocations m, Effect FileResource m, Produce FileLocations ~ (FilePaths), Produce FileResource ~ (OpenedFile)) => WriteFirstEffect m where
  writeFirst :: m ()
  {-# MINIMAL writeFirst #-}

instance (Monad m, Effect SharedFileScope m, WriteFirstEffect m) => Effect WriteFirst m where
  type Registration WriteFirst = Registered WriteFirstEffect SharedFileScope
  type Typing WriteFirst = 'SDK.ExcuKind
  type Require WriteFirst = (FilePaths, OpenedFile)
  type Error WriteFirst = WriteFirstError
  raise (WriteFirstError description) = SDK.failEffect "WriteFirst" WriteFirstFailure description
  handler = FrameworkRoot.handler @Root

data WriteSecond

class (Effect SharedFileScope m, Effect FileLocations m, Effect FileResource m, Produce FileLocations ~ (FilePaths), Produce FileResource ~ (OpenedFile)) => WriteSecondEffect m where
  writeSecond :: m ()
  {-# MINIMAL writeSecond #-}

instance (Monad m, Effect SharedFileScope m, WriteSecondEffect m) => Effect WriteSecond m where
  type Registration WriteSecond = Registered WriteSecondEffect SharedFileScope
  type Typing WriteSecond = 'SDK.ExcuKind
  type Require WriteSecond = (FilePaths, OpenedFile)
  type Error WriteSecond = WriteSecondError
  raise (WriteSecondError description) = SDK.failEffect "WriteSecond" WriteSecondFailure description
  handler = FrameworkRoot.handler @Root

data WriteThird

class (Effect SharedFileScope m, Effect FileLocations m, Effect FileResource m, Produce FileLocations ~ (FilePaths), Produce FileResource ~ (OpenedFile)) => WriteThirdEffect m where
  writeThird :: m ()
  {-# MINIMAL writeThird #-}

instance (Monad m, Effect SharedFileScope m, WriteThirdEffect m) => Effect WriteThird m where
  type Registration WriteThird = Registered WriteThirdEffect SharedFileScope
  type Typing WriteThird = 'SDK.ExcuKind
  type Require WriteThird = (FilePaths, OpenedFile)
  type Error WriteThird = WriteThirdError
  raise (WriteThirdError description) = SDK.failEffect "WriteThird" WriteThirdFailure description
  handler = FrameworkRoot.handler @Root

data VerifyReuse

class (Effect Root m, Effect FileLocations m, Produce FileLocations ~ (FilePaths)) => VerifyReuseEffect m where
  verifyReuse :: m ()
  {-# MINIMAL verifyReuse #-}

instance (Monad m, Effect Root m, VerifyReuseEffect m) => Effect VerifyReuse m where
  type Registration VerifyReuse = Registered VerifyReuseEffect Root
  type Typing VerifyReuse = 'SDK.ExcuKind
  type Require VerifyReuse = FilePaths
  type Error VerifyReuse = VerifyReuseError
  raise (VerifyReuseError description) = SDK.failEffect "VerifyReuse" VerifyReuseFailure description
  handler = FrameworkRoot.handler @Root

-- SDK 生成的本地错误只接收消息；类型唯一确定 raise 来源。
newtype FileLocationsError = FileLocationsError String
  deriving (Eq, Show, Read)

-- SDK 生成的本地错误只接收消息；类型唯一确定 raise 来源。
newtype PrepareProbeError = PrepareProbeError String
  deriving (Eq, Show, Read)

-- SDK 生成的本地错误只接收消息；类型唯一确定 raise 来源。
newtype FileResourceError = FileResourceError String
  deriving (Eq, Show, Read)

-- SDK 生成的本地错误只接收消息；类型唯一确定 raise 来源。
newtype SharedFileScopeError = SharedFileScopeError String
  deriving (Eq, Show, Read)

-- SDK 生成的本地错误只接收消息；类型唯一确定 raise 来源。
newtype WriteFirstError = WriteFirstError String
  deriving (Eq, Show, Read)

-- SDK 生成的本地错误只接收消息；类型唯一确定 raise 来源。
newtype WriteSecondError = WriteSecondError String
  deriving (Eq, Show, Read)

-- SDK 生成的本地错误只接收消息；类型唯一确定 raise 来源。
newtype WriteThirdError = WriteThirdError String
  deriving (Eq, Show, Read)

-- SDK 生成的本地错误只接收消息；类型唯一确定 raise 来源。
newtype VerifyReuseError = VerifyReuseError String
  deriving (Eq, Show, Read)

-- 统一失败协议的分类标签；消息与来源由 SDK.Failure 保存。
data Errors = FileLocationsFailure | PrepareProbeFailure | FileResourceFailure | SharedFileScopeFailure | WriteFirstFailure | WriteSecondFailure | WriteThirdFailure | VerifyReuseFailure | ContextBindingError SDK.ContextFault | ScopeBindingError SDK.ScopeFault
  deriving (Eq, Show)

-- SDK 内部存储：Nothing 仅表示本次运行尚未建立绑定，不是业务缺值。
data ContextValues = ContextValues
  { boundFileLocations :: Maybe (Produce FileLocations)
  , boundFileResource :: Maybe (Produce FileResource)
  }

emptyContexts :: ContextValues
emptyContexts = ContextValues Nothing Nothing

