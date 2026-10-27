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
module ScopeInstancesDemo.Generated.Effects where

import Framework.Effect.Contract (Effect(..), Registered)
import qualified Framework.Effect.Contract as FrameworkRoot
import qualified Framework.SDK as SDK
import ScopeInstancesDemo.Types

-- SDK 提供运行载体与空存储；Context 经声明的 request/require 取得。
type Root = SDK.Root ContextValues Errors
type App = SDK.App ContextValues Errors

-- 每个 Context 的契约类型：名字来自 handler 名，包装其表示类型；只能由该生产方构造。
newtype FileName = FileName ([Char])
deriving instance Eq ([Char]) => Eq FileName
deriving instance Show ([Char]) => Show FileName

newtype OpenedFile = OpenedFile (FileHandle)
deriving instance Eq (FileHandle) => Eq OpenedFile
deriving instance Show (FileHandle) => Show OpenedFile

-- 方法定义身份；仅生成区使用，图中不以字符串匹配方法。
data MethodGen = PrepareFilesGen | FileNameGen | ReadFileNameGen | OpenedFileGen | ReadOpenedFileGen | OpenFileSessionGen | CloseFileSessionGen | CheckIndependentGen | CheckReopenGen
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
  fileName :: m (Produce FileLocation)
  readFileName :: m (Produce FileLocation)
  readFileName = (FrameworkRoot.withErrorPath [] . FrameworkRoot.handler @Root) $
    SDK.readContext "FileLocation" ContextBindingError [("FileResource", SDK.RequireValue), ("CheckIndependent", SDK.RequestValue), ("CheckReopen", SDK.RequestValue)] (Just (SDK.ScopeInput "FileLocation")) boundFileLocation fileName
  {-# MINIMAL fileName #-}

instance (Monad m, Effect Root m, FileLocationEffect m) => Effect FileLocation m where
  type Registration FileLocation = Registered FileLocationEffect Root
  type Typing FileLocation = 'SDK.ContextKind
  type Require FileLocation = SDK.Void
  type Produce FileLocation = FileName
  type Error FileLocation = FileLocationError
  raise (FileLocationError description) = SDK.failEffect "FileLocation" FileLocationFailure description
  handler = FrameworkRoot.handler @Root

data FileResource

class (Effect Root m, Provides FileName m) => FileResourceEffect m where
  openedFile :: m (Produce FileResource)
  readOpenedFile :: m (Produce FileResource)
  readOpenedFile = (FrameworkRoot.withErrorPath [] . FrameworkRoot.handler @Root) $
    SDK.readContext "FileResource" ContextBindingError [("FileSession", SDK.RequestValue), ("CheckIndependent", SDK.RequireValue), ("CheckReopen", SDK.RequireValue)] Nothing boundFileResource openedFile
  {-# MINIMAL openedFile #-}

instance (Monad m, Effect Root m, FileResourceEffect m) => Effect FileResource m where
  type Registration FileResource = Registered FileResourceEffect Root
  type Typing FileResource = 'SDK.ContextKind
  type Require FileResource = FileName
  type Produce FileResource = OpenedFile
  type Error FileResource = FileResourceError
  raise (FileResourceError description) = SDK.failEffect "FileResource" FileResourceFailure description
  handler = FrameworkRoot.handler @Root

data FileSession

class (Effect Root m, Provides OpenedFile m) => FileSessionEffect m where
  openFileSession :: m ()
  closeFileSession :: m ()
  {-# MINIMAL openFileSession, closeFileSession #-}

instance (Monad m, Effect Root m, FileSessionEffect m) => Effect FileSession m where
  type Registration FileSession = Registered FileSessionEffect Root
  type Typing FileSession = 'SDK.ScopedKind
  type Require FileSession = OpenedFile
  type Error FileSession = FileSessionError
  raise (FileSessionError description) = SDK.failEffect "FileSession" FileSessionFailure description
  handler = FrameworkRoot.handler @Root

data CheckIndependent

class (Effect FileSession m, Provides FileName m, Provides OpenedFile m) => CheckIndependentEffect m where
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

class (Effect FileSession m, Provides FileName m, Provides OpenedFile m) => CheckReopenEffect m where
  checkReopen :: m ()
  {-# MINIMAL checkReopen #-}

instance (Monad m, Effect FileSession m, CheckReopenEffect m) => Effect CheckReopen m where
  type Registration CheckReopen = Registered CheckReopenEffect FileSession
  type Typing CheckReopen = 'SDK.ExcuKind
  type Require CheckReopen = (FileName, OpenedFile)
  type Error CheckReopen = CheckReopenError
  raise (CheckReopenError description) = SDK.failEffect "CheckReopen" CheckReopenFailure description
  handler = FrameworkRoot.handler @Root

-- 依值入口：request 重新生产，require 读取已有绑定；来源由注册解析，不由消费方指名。
class Provides contract m where
  request :: m contract
  require :: m contract

instance (FileLocationEffect App) => Provides FileName App where
  request = SDK.provideContext "FileName" ContextBindingError [("CheckIndependent", fileName), ("CheckReopen", fileName)]
  require = SDK.provideContext "FileName" ContextBindingError [("FileResource", readFileName)]

instance (FileResourceEffect App) => Provides OpenedFile App where
  request = SDK.provideContext "OpenedFile" ContextBindingError [("FileSession", openedFile)]
  require = SDK.provideContext "OpenedFile" ContextBindingError [("FileSession", readOpenedFile), ("CheckIndependent", readOpenedFile), ("CheckReopen", readOpenedFile)]

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

