{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE EmptyDataDecls #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE StandaloneDeriving #-}
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

-- 每个 Context 的契约类型：名字来自 handler 名，包装其表示类型；只能由该生产方构造。
newtype FilePaths = FilePaths (SharedPaths)
deriving instance Eq (SharedPaths) => Eq FilePaths
deriving instance Show (SharedPaths) => Show FilePaths

newtype OpenedFile = OpenedFile (SharedFile)
deriving instance Eq (SharedFile) => Eq OpenedFile
deriving instance Show (SharedFile) => Show OpenedFile

-- 方法定义身份；仅生成区使用，图中不以字符串匹配方法。
data MethodGen = FilePathsGen | ReadFilePathsGen | PrepareProbeGen | OpenedFileGen | ReadOpenedFileGen | OpenSharedFileGen | CloseSharedFileGen | WriteFirstGen | WriteSecondGen | WriteThirdGen | VerifyReuseGen
  deriving (Eq, Ord, Show, Read, SDK.Generic)
instance SDK.NFData MethodGen

data FileLocations

class (Effect Root m) => FileLocationsEffect m where
  filePaths :: m (Produce FileLocations)
  readFilePaths :: m (Produce FileLocations)
  readFilePaths = (FrameworkRoot.withErrorPath [] . FrameworkRoot.handler @Root) $
    SDK.readContext "FileLocations" ContextBindingError [("PrepareProbe", SDK.RequestValue), ("FileResource", SDK.RequireValue), ("WriteFirst", SDK.RequestValue), ("WriteSecond", SDK.RequestValue), ("WriteThird", SDK.RequestValue), ("VerifyReuse", SDK.RequestValue)] (Just (SDK.ScopeInput "FileLocations")) boundFileLocations filePaths
  {-# MINIMAL filePaths #-}

instance (Monad m, Effect Root m, FileLocationsEffect m) => Effect FileLocations m where
  type Registration FileLocations = Registered FileLocationsEffect Root
  type Typing FileLocations = 'SDK.ContextKind
  type Require FileLocations = SDK.Void
  type Produce FileLocations = FilePaths
  type Error FileLocations = FileLocationsError
  raise (FileLocationsError description) = SDK.failEffect "FileLocations" FileLocationsFailure description
  handler = FrameworkRoot.handler @Root

data PrepareProbe

class (Effect Root m, Provides FilePaths m) => PrepareProbeEffect m where
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

class (Effect Root m, Provides FilePaths m) => FileResourceEffect m where
  openedFile :: m (Produce FileResource)
  readOpenedFile :: m (Produce FileResource)
  readOpenedFile = (FrameworkRoot.withErrorPath [] . FrameworkRoot.handler @Root) $
    SDK.readContext "FileResource" ContextBindingError [("SharedFileScope", SDK.RequestValue), ("WriteFirst", SDK.RequireValue), ("WriteSecond", SDK.RequireValue), ("WriteThird", SDK.RequireValue)] Nothing boundFileResource openedFile
  {-# MINIMAL openedFile #-}

instance (Monad m, Effect Root m, FileResourceEffect m) => Effect FileResource m where
  type Registration FileResource = Registered FileResourceEffect Root
  type Typing FileResource = 'SDK.ContextKind
  type Require FileResource = FilePaths
  type Produce FileResource = OpenedFile
  type Error FileResource = FileResourceError
  raise (FileResourceError description) = SDK.failEffect "FileResource" FileResourceFailure description
  handler = FrameworkRoot.handler @Root

data SharedFileScope

class (Effect Root m, Provides OpenedFile m) => SharedFileScopeEffect m where
  openSharedFile :: m ()
  closeSharedFile :: m ()
  {-# MINIMAL openSharedFile, closeSharedFile #-}

instance (Monad m, Effect Root m, SharedFileScopeEffect m) => Effect SharedFileScope m where
  type Registration SharedFileScope = Registered SharedFileScopeEffect Root
  type Typing SharedFileScope = 'SDK.ScopedKind
  type Require SharedFileScope = OpenedFile
  type Error SharedFileScope = SharedFileScopeError
  raise (SharedFileScopeError description) = SDK.failEffect "SharedFileScope" SharedFileScopeFailure description
  handler = FrameworkRoot.handler @Root

data WriteFirst

class (Effect SharedFileScope m, Provides FilePaths m, Provides OpenedFile m) => WriteFirstEffect m where
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

class (Effect SharedFileScope m, Provides FilePaths m, Provides OpenedFile m) => WriteSecondEffect m where
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

class (Effect SharedFileScope m, Provides FilePaths m, Provides OpenedFile m) => WriteThirdEffect m where
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

class (Effect Root m, Provides FilePaths m) => VerifyReuseEffect m where
  verifyReuse :: m ()
  {-# MINIMAL verifyReuse #-}

instance (Monad m, Effect Root m, VerifyReuseEffect m) => Effect VerifyReuse m where
  type Registration VerifyReuse = Registered VerifyReuseEffect Root
  type Typing VerifyReuse = 'SDK.ExcuKind
  type Require VerifyReuse = FilePaths
  type Error VerifyReuse = VerifyReuseError
  raise (VerifyReuseError description) = SDK.failEffect "VerifyReuse" VerifyReuseFailure description
  handler = FrameworkRoot.handler @Root

-- 依值入口：request 重新生产，require 读取已有绑定；来源由注册解析，不由消费方指名。
class Provides contract m where
  request :: m contract
  require :: m contract

instance (FileLocationsEffect App) => Provides FilePaths App where
  request = SDK.provideContext "FilePaths" ContextBindingError [("PrepareProbe", filePaths), ("WriteFirst", filePaths), ("WriteSecond", filePaths), ("WriteThird", filePaths), ("VerifyReuse", filePaths)]
  require = SDK.provideContext "FilePaths" ContextBindingError [("FileResource", readFilePaths)]

instance (FileResourceEffect App) => Provides OpenedFile App where
  request = SDK.provideContext "OpenedFile" ContextBindingError [("SharedFileScope", openedFile)]
  require = SDK.provideContext "OpenedFile" ContextBindingError [("SharedFileScope", readOpenedFile), ("WriteFirst", readOpenedFile), ("WriteSecond", readOpenedFile), ("WriteThird", readOpenedFile)]

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

