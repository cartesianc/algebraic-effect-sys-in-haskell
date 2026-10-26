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
module ScopeInstancesDemo.Generated.Effects where

import Framework.Effect.Contract (Effect(..), Registered)
import qualified Framework.Effect.Contract as FrameworkRoot
import qualified Framework.SDK as SDK
import ScopeInstancesDemo.Types

-- SDK 提供运行载体与空存储；Context 经声明的 request/require 取得。
type Root = SDK.Root ContextValues Errors
type App = SDK.App ContextValues Errors

-- 方法定义身份；仅生成区使用，图中不以字符串匹配方法。
data MethodGen = PrepareFilesGen | GetFileNameGen | ReadFileNameGen | AcquireFileGen | ReadOpenedFileGen | OpenFileSessionGen | CloseFileSessionGen | CheckIndependentGen | CheckReopenGen
  deriving (Eq, Ord, Show, Read, SDK.Generic)
instance SDK.NFData MethodGen

data PrepareFiles

class (Effect Root m) => PrepareFilesEffect m where
  prepareFiles :: m ()
  {-# MINIMAL prepareFiles #-}

instance (Monad m, Effect Root m, PrepareFilesEffect m) => Effect PrepareFiles m where
  type Registration PrepareFiles = Registered PrepareFilesEffect Root
  type Typing PrepareFiles = 'SDK.ExcuKind
  type Require PrepareFiles = SDK.Void
  type Error PrepareFiles = PrepareFilesError
  raise (PrepareFilesError description) = SDK.failEffect "PrepareFiles" PrepareFilesFailure description
  handler = FrameworkRoot.handler @Root

data FileLocation

class (Effect Root m) => FileLocationEffect m where
  getFileName :: m (Produce FileLocation)
  readFileName :: m (Produce FileLocation)
  readFileName = (FrameworkRoot.withErrorPath [] . FrameworkRoot.handler @Root) $
    SDK.readContext "FileLocation" ContextBindingError (Just (SDK.ScopeInput "FileLocation")) boundFileLocation
  {-# MINIMAL getFileName #-}

instance (Monad m, Effect Root m, FileLocationEffect m) => Effect FileLocation m where
  type Registration FileLocation = Registered FileLocationEffect Root
  type Typing FileLocation = 'SDK.ContextKind
  type Require FileLocation = SDK.Void
  type Produce FileLocation = FileName
  type Error FileLocation = FileLocationError
  raise (FileLocationError description) = SDK.failEffect "FileLocation" FileLocationFailure description
  handler = FrameworkRoot.handler @Root

data FileResource

class (Effect Root m, Effect FileLocation m, Produce FileLocation ~ (FileName)) => FileResourceEffect m where
  acquireFile :: m (Produce FileResource)
  readOpenedFile :: m (Produce FileResource)
  readOpenedFile = (FrameworkRoot.withErrorPath [] . FrameworkRoot.handler @Root) $
    SDK.readContext "FileResource" ContextBindingError Nothing boundFileResource
  {-# MINIMAL acquireFile #-}

instance (Monad m, Effect Root m, FileResourceEffect m) => Effect FileResource m where
  type Registration FileResource = Registered FileResourceEffect Root
  type Typing FileResource = 'SDK.ContextKind
  type Require FileResource = FileName
  type Produce FileResource = OpenedFile
  type Error FileResource = FileResourceError
  raise (FileResourceError description) = SDK.failEffect "FileResource" FileResourceFailure description
  handler = FrameworkRoot.handler @Root

data FileSession

class (Effect Root m, Effect FileResource m, Produce FileResource ~ (OpenedFile)) => FileSessionEffect m where
  openFileSession :: m ()
  closeFileSession :: m ()
  {-# MINIMAL openFileSession, closeFileSession #-}

instance (Monad m, Effect Root m, FileSessionEffect m) => Effect FileSession m where
  type Registration FileSession = Registered FileSessionEffect Root
  type Typing FileSession = 'SDK.ScopedKind
  type Require FileSession = (OpenedFile, OpenedFile)
  type Error FileSession = FileSessionError
  raise (FileSessionError description) = SDK.failEffect "FileSession" FileSessionFailure description
  handler = FrameworkRoot.handler @Root

data CheckIndependent

class (Effect FileSession m, Effect FileLocation m, Effect FileResource m, Produce FileLocation ~ (FileName), Produce FileResource ~ (OpenedFile)) => CheckIndependentEffect m where
  checkIndependent :: m ()
  {-# MINIMAL checkIndependent #-}

instance (Monad m, Effect FileSession m, CheckIndependentEffect m) => Effect CheckIndependent m where
  type Registration CheckIndependent = Registered CheckIndependentEffect FileSession
  type Typing CheckIndependent = 'SDK.ExcuKind
  type Require CheckIndependent = (FileName, OpenedFile)
  type Error CheckIndependent = CheckIndependentError
  raise (CheckIndependentError description) = SDK.failEffect "CheckIndependent" CheckIndependentFailure description
  handler = FrameworkRoot.handler @Root

data CheckReopen

class (Effect FileSession m, Effect FileLocation m, Effect FileResource m, Produce FileLocation ~ (FileName), Produce FileResource ~ (OpenedFile)) => CheckReopenEffect m where
  checkReopen :: m ()
  {-# MINIMAL checkReopen #-}

instance (Monad m, Effect FileSession m, CheckReopenEffect m) => Effect CheckReopen m where
  type Registration CheckReopen = Registered CheckReopenEffect FileSession
  type Typing CheckReopen = 'SDK.ExcuKind
  type Require CheckReopen = (FileName, OpenedFile)
  type Error CheckReopen = CheckReopenError
  raise (CheckReopenError description) = SDK.failEffect "CheckReopen" CheckReopenFailure description
  handler = FrameworkRoot.handler @Root

-- SDK 生成的本地错误只接收消息；类型唯一确定 raise 来源。
newtype PrepareFilesError = PrepareFilesError String
  deriving (Eq, Show, Read)

-- SDK 生成的本地错误只接收消息；类型唯一确定 raise 来源。
newtype FileLocationError = FileLocationError String
  deriving (Eq, Show, Read)

-- SDK 生成的本地错误只接收消息；类型唯一确定 raise 来源。
newtype FileResourceError = FileResourceError String
  deriving (Eq, Show, Read)

-- SDK 生成的本地错误只接收消息；类型唯一确定 raise 来源。
newtype FileSessionError = FileSessionError String
  deriving (Eq, Show, Read)

-- SDK 生成的本地错误只接收消息；类型唯一确定 raise 来源。
newtype CheckIndependentError = CheckIndependentError String
  deriving (Eq, Show, Read)

-- SDK 生成的本地错误只接收消息；类型唯一确定 raise 来源。
newtype CheckReopenError = CheckReopenError String
  deriving (Eq, Show, Read)

-- 统一失败协议的分类标签；消息与来源由 SDK.Failure 保存。
data Errors = PrepareFilesFailure | FileLocationFailure | FileResourceFailure | FileSessionFailure | CheckIndependentFailure | CheckReopenFailure | ContextBindingError SDK.ContextFault | ScopeBindingError SDK.ScopeFault
  deriving (Eq, Show)

-- SDK 内部存储：Nothing 仅表示本次运行尚未建立绑定，不是业务缺值。
data ContextValues = ContextValues
  { boundFileLocation :: Maybe (Produce FileLocation)
  , boundFileResource :: Maybe (Produce FileResource)
  }

emptyContexts :: ContextValues
emptyContexts = ContextValues Nothing Nothing

