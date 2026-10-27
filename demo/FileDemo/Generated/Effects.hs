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
module FileDemo.Generated.Effects where

import Framework.Effect.Contract (Effect(..), Registered)
import qualified Framework.Effect.Contract as FrameworkRoot
import qualified Framework.SDK as SDK
import FileDemo.Types

-- SDK 提供运行载体与空存储；Context 经声明的 request/require 取得。
type Root = SDK.Root ContextValues Errors
type App = SDK.App ContextValues Errors

-- 方法定义身份；仅生成区使用，图中不以字符串匹配方法。
data MethodGen = GetFileNameGen | ReadFileNameGen | ValidateFileNameGen | AcquireFileGen | ReadOpenedFileGen | OpenFileSessionGen | CloseFileSessionGen | DetectFileSessionGen | ResolveFileSessionGen | ReadFileTextGen | ReadLastFileTextGen | WriteFileTextGen | RunFileWorkflowGen
  deriving (Eq, Ord, Show, Read, SDK.Generic)
instance SDK.NFData MethodGen

data FileLocation

class (Effect Root m) => FileLocationEffect m where
  getFileName :: m (Produce FileLocation)
  readFileName :: m (Produce FileLocation)
  readFileName = (FrameworkRoot.withErrorPath [] . FrameworkRoot.handler @Root) $
    SDK.readContext "FileLocation" ContextBindingError [("ValidateFileName", SDK.RequireValue), ("FileResource", SDK.RequireValue), ("FileWorkflow", SDK.RequestValue)] (Just (SDK.ScopeInput "FileLocation")) boundFileLocation
  {-# MINIMAL getFileName #-}

instance (Monad m, Effect Root m, FileLocationEffect m) => Effect FileLocation m where
  type Registration FileLocation = Registered FileLocationEffect Root
  type Typing FileLocation = 'SDK.ContextKind
  type Require FileLocation = SDK.Void
  type Produce FileLocation = FileName
  type Error FileLocation = FileLocationError
  raise (FileLocationError description) = SDK.failEffect "FileLocation" FileLocationFailure description
  handler = FrameworkRoot.handler @Root

data ValidateFileName

class (Effect Root m, Provides FileName m) => ValidateFileNameEffect m where
  validateFileName :: m ()
  {-# MINIMAL validateFileName #-}

instance (Monad m, Effect Root m, ValidateFileNameEffect m) => Effect ValidateFileName m where
  type Registration ValidateFileName = Registered ValidateFileNameEffect Root
  type Typing ValidateFileName = 'SDK.PureKind
  type Require ValidateFileName = FileName
  type Error ValidateFileName = ValidateFileNameError
  raise (ValidateFileNameError description) = SDK.failEffect "ValidateFileName" ValidateFileNameFailure description
  handler = FrameworkRoot.handler @Root

data FileResource

class (Effect ValidateFileName m, Provides FileName m) => FileResourceEffect m where
  acquireFile :: m (Produce FileResource)
  readOpenedFile :: m (Produce FileResource)
  readOpenedFile = (FrameworkRoot.withErrorPath [] . FrameworkRoot.handler @Root) $
    SDK.readContext "FileResource" ContextBindingError [("FileSession", SDK.RequestValue), ("FileRecovery", SDK.RequireValue), ("ReadFile", SDK.RequireValue), ("WriteFile", SDK.RequireValue)] Nothing boundFileResource
  {-# MINIMAL acquireFile #-}

instance (Monad m, Effect ValidateFileName m, FileResourceEffect m) => Effect FileResource m where
  type Registration FileResource = Registered FileResourceEffect ValidateFileName
  type Typing FileResource = 'SDK.ContextKind
  type Require FileResource = FileName
  type Produce FileResource = OpenedFile
  type Error FileResource = FileResourceError
  raise (FileResourceError description) = SDK.failEffect "FileResource" FileResourceFailure description
  handler = FrameworkRoot.handler @Root

data FileSession

class (Effect ValidateFileName m, Provides OpenedFile m) => FileSessionEffect m where
  openFileSession :: m ()
  closeFileSession :: m ()
  {-# MINIMAL openFileSession, closeFileSession #-}

instance (Monad m, Effect ValidateFileName m, FileSessionEffect m) => Effect FileSession m where
  type Registration FileSession = Registered FileSessionEffect ValidateFileName
  type Typing FileSession = 'SDK.ScopedKind
  type Require FileSession = OpenedFile
  type Error FileSession = FileSessionError
  raise (FileSessionError description) = SDK.failEffect "FileSession" FileSessionFailure description
  handler = FrameworkRoot.handler @Root

data FileRecovery

class (Effect FileSession m, Provides OpenedFile m) => FileRecoveryEffect m where
  detectFileSession :: m ()
  resolveFileSession :: m ()
  {-# MINIMAL detectFileSession, resolveFileSession #-}

instance (Monad m, Effect FileSession m, FileRecoveryEffect m) => Effect FileRecovery m where
  type Registration FileRecovery = Registered FileRecoveryEffect FileSession
  type Typing FileRecovery = 'SDK.ErrorKind
  type Require FileRecovery = OpenedFile
  type Error FileRecovery = FileRecoveryError
  raise (FileRecoveryError description) = SDK.failEffect "FileRecovery" FileRecoveryFailure description
  handler = FrameworkRoot.handler @Root

data ReadFile

class (Effect FileSession m, Provides OpenedFile m) => ReadFileEffect m where
  readFileText :: m (Produce ReadFile)
  readLastFileText :: m (Produce ReadFile)
  readLastFileText = (FrameworkRoot.withErrorPath ["FileSession"] . FrameworkRoot.handler @Root) $
    SDK.readContext "ReadFile" ContextBindingError [("WriteFile", SDK.RequestValue)] Nothing boundReadFile
  {-# MINIMAL readFileText #-}

instance (Monad m, Effect FileSession m, ReadFileEffect m) => Effect ReadFile m where
  type Registration ReadFile = Registered ReadFileEffect FileSession
  type Typing ReadFile = 'SDK.ContextKind
  type Require ReadFile = OpenedFile
  type Produce ReadFile = FileText
  type Error ReadFile = ReadFileError
  raise (ReadFileError description) = SDK.failEffect "ReadFile" ReadFileFailure description
  handler = FrameworkRoot.handler @Root

data WriteFile

class (Effect FileSession m, Provides FileText m, Provides OpenedFile m) => WriteFileEffect m where
  writeFileText :: m ()
  {-# MINIMAL writeFileText #-}

instance (Monad m, Effect FileSession m, WriteFileEffect m) => Effect WriteFile m where
  type Registration WriteFile = Registered WriteFileEffect FileSession
  type Typing WriteFile = 'SDK.ExcuKind
  type Require WriteFile = (FileText, OpenedFile)
  type Error WriteFile = WriteFileError
  raise (WriteFileError description) = SDK.failEffect "WriteFile" WriteFileFailure description
  handler = FrameworkRoot.handler @Root

data FileWorkflow

class (Effect WriteFile m, Provides FileName m) => FileWorkflowEffect m where
  runFileWorkflow :: m ()
  {-# MINIMAL runFileWorkflow #-}

instance (Monad m, Effect WriteFile m, FileWorkflowEffect m) => Effect FileWorkflow m where
  type Registration FileWorkflow = Registered FileWorkflowEffect WriteFile
  type Typing FileWorkflow = 'SDK.ExcuKind
  type Require FileWorkflow = FileName
  type Error FileWorkflow = FileWorkflowError
  raise (FileWorkflowError description) = SDK.failEffect "FileWorkflow" FileWorkflowFailure description
  handler = FrameworkRoot.handler @Root

-- 依值入口：request 重新生产，require 读取已有绑定；来源由注册解析，不由消费方指名。
class Provides contract m where
  request :: m contract
  require :: m contract

instance (FileLocationEffect App) => Provides FileName App where
  request = SDK.provideContext "FileName" ContextBindingError [("FileWorkflow", getFileName)]
  require = SDK.provideContext "FileName" ContextBindingError [("ValidateFileName", readFileName), ("FileResource", readFileName)]

instance (FileResourceEffect App) => Provides OpenedFile App where
  request = SDK.provideContext "OpenedFile" ContextBindingError [("FileSession", acquireFile)]
  require = SDK.provideContext "OpenedFile" ContextBindingError [("FileSession", readOpenedFile), ("FileRecovery", readOpenedFile), ("ReadFile", readOpenedFile), ("WriteFile", readOpenedFile)]

instance (ReadFileEffect App) => Provides FileText App where
  request = SDK.provideContext "FileText" ContextBindingError [("WriteFile", readFileText)]
  require = SDK.provideContext "FileText" ContextBindingError []

-- SDK 生成的本地错误只接收消息；类型唯一确定 raise 来源。
newtype FileLocationError = FileLocationError String
  deriving (Eq, Show, Read)

-- SDK 生成的本地错误只接收消息；类型唯一确定 raise 来源。
newtype ValidateFileNameError = ValidateFileNameError String
  deriving (Eq, Show, Read)

-- SDK 生成的本地错误只接收消息；类型唯一确定 raise 来源。
newtype FileResourceError = FileResourceError String
  deriving (Eq, Show, Read)

-- SDK 生成的本地错误只接收消息；类型唯一确定 raise 来源。
newtype FileSessionError = FileSessionError String
  deriving (Eq, Show, Read)

-- SDK 生成的本地错误只接收消息；类型唯一确定 raise 来源。
newtype FileRecoveryError = FileRecoveryError String
  deriving (Eq, Show, Read)

-- SDK 生成的本地错误只接收消息；类型唯一确定 raise 来源。
newtype ReadFileError = ReadFileError String
  deriving (Eq, Show, Read)

-- SDK 生成的本地错误只接收消息；类型唯一确定 raise 来源。
newtype WriteFileError = WriteFileError String
  deriving (Eq, Show, Read)

-- SDK 生成的本地错误只接收消息；类型唯一确定 raise 来源。
newtype FileWorkflowError = FileWorkflowError String
  deriving (Eq, Show, Read)

-- 统一失败协议的分类标签；消息与来源由 SDK.Failure 保存。
data Errors = FileLocationFailure | ValidateFileNameFailure | FileResourceFailure | FileSessionFailure | FileRecoveryFailure | ReadFileFailure | WriteFileFailure | FileWorkflowFailure | ContextBindingError SDK.ContextFault | ScopeBindingError SDK.ScopeFault
  deriving (Eq, Show)

-- SDK 内部存储：Nothing 仅表示本次运行尚未建立绑定，不是业务缺值。
data ContextValues = ContextValues
  { boundFileLocation :: Maybe (Produce FileLocation)
  , boundFileResource :: Maybe (Produce FileResource)
  , boundReadFile :: Maybe (Produce ReadFile)
  }

emptyContexts :: ContextValues
emptyContexts = ContextValues Nothing Nothing Nothing

