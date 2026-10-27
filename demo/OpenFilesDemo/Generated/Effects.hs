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
module OpenFilesDemo.Generated.Effects where

import Framework.Effect.Contract (Effect(..), Registered)
import qualified Framework.Effect.Contract as FrameworkRoot
import qualified Framework.SDK as SDK
import Control.Monad.IO.Class (MonadIO)
import OpenFilesDemo.Types

-- SDK 提供运行载体与空存储；Context 经声明的 request/require 取得。
type Root = SDK.Root ContextValues Errors
type App = SDK.App ContextValues Errors

-- 每个 Context 的契约类型：名字来自 handler 名，包装其表示类型；只能由该生产方构造。
newtype FileNames = FileNames ([[Char]])
deriving instance Eq ([[Char]]) => Eq FileNames
deriving instance Show ([[Char]]) => Show FileNames

newtype OpenedFiles = OpenedFiles ([FileHandle])
deriving instance Eq ([FileHandle]) => Eq OpenedFiles
deriving instance Show ([FileHandle]) => Show OpenedFiles

-- 方法定义身份；仅生成区使用，图中不以字符串匹配方法。
data MethodGen = FileNamesGen | ReadFileNamesGen | OpenedFilesGen | ReadOpenedFilesGen | OpenFilesGen | CloseFilesGen | HoldFilesGen | InspectFilesGen | FinishInspectionGen
  deriving (Eq, Ord, Show, Read, SDK.Generic)
instance SDK.NFData MethodGen

data FileLocations

type FileLocationsInputs m = (FrameworkRoot.Capability FileLocations m, Effect Root m, MonadIO m)
instance FrameworkRoot.Capability FileLocations App

class (Effect Root m) => FileLocationsEffect m where
  fileNames :: m (Produce FileLocations)
  readFileNames :: m (Produce FileLocations)
  readFileNames = (FrameworkRoot.withErrorPath [] . FrameworkRoot.handler @Root) $
    SDK.readContext "FileLocations" ContextBindingError [("FileResources", SDK.RequireValue), ("HoldFiles", SDK.RequestValue)] (Just (SDK.ScopeInput "FileLocations")) boundFileLocations fileNames
  {-# MINIMAL fileNames #-}

instance (Monad m, Effect Root m, FileLocationsEffect m) => Effect FileLocations m where
  type Registration FileLocations = Registered FileLocationsEffect Root
  type Typing FileLocations = 'SDK.ContextKind
  type Require FileLocations = SDK.Void
  type Produce FileLocations = FileNames
  type Error FileLocations = FileLocationsError
  raise (FileLocationsError description) = SDK.failEffect "FileLocations" FileLocationsFailure description
  handler = FrameworkRoot.handler @Root

data FileResources

type FileResourcesInputs m = (FrameworkRoot.Capability FileResources m, Effect Root m, Provides FileNames m, MonadIO m)
instance FrameworkRoot.Capability FileResources App

class (Effect Root m, Provides FileNames m) => FileResourcesEffect m where
  openedFiles :: m (Produce FileResources)
  readOpenedFiles :: m (Produce FileResources)
  readOpenedFiles = (FrameworkRoot.withErrorPath [] . FrameworkRoot.handler @Root) $
    SDK.readContext "FileResources" ContextBindingError [("FileSession", SDK.RequestValue), ("InspectFiles", SDK.RequireValue), ("FinishInspection", SDK.RequireValue)] Nothing boundFileResources openedFiles
  {-# MINIMAL openedFiles #-}

instance (Monad m, Effect Root m, FileResourcesEffect m) => Effect FileResources m where
  type Registration FileResources = Registered FileResourcesEffect Root
  type Typing FileResources = 'SDK.ContextKind
  type Require FileResources = FileNames
  type Produce FileResources = OpenedFiles
  type Error FileResources = FileResourcesError
  raise (FileResourcesError description) = SDK.failEffect "FileResources" FileResourcesFailure description
  handler = FrameworkRoot.handler @Root

data FileSession

type FileSessionInputs m = (FrameworkRoot.Capability FileSession m, Effect Root m, Provides OpenedFiles m, MonadIO m)
instance FrameworkRoot.Capability FileSession App

class (Effect Root m, Provides OpenedFiles m) => FileSessionEffect m where
  openFiles :: m (Maybe String)
  closeFiles :: m (Maybe String)
  {-# MINIMAL openFiles, closeFiles #-}

instance (Monad m, Effect Root m, FileSessionEffect m) => Effect FileSession m where
  type Registration FileSession = Registered FileSessionEffect Root
  type Typing FileSession = 'SDK.ScopedKind
  type Require FileSession = OpenedFiles
  type Error FileSession = FileSessionError
  raise (FileSessionError description) = SDK.failEffect "FileSession" FileSessionFailure description
  handler = FrameworkRoot.handler @Root

data HoldFiles

type HoldFilesInputs m = (FrameworkRoot.Capability HoldFiles m, Effect FileSession m, Provides FileNames m, FileSessionEffect m, MonadIO m)
instance FrameworkRoot.Capability HoldFiles App

class (Effect FileSession m, Provides FileNames m) => HoldFilesEffect m where
  holdFiles :: m (Maybe String)
  {-# MINIMAL holdFiles #-}

instance (Monad m, Effect FileSession m, HoldFilesEffect m) => Effect HoldFiles m where
  type Registration HoldFiles = Registered HoldFilesEffect FileSession
  type Typing HoldFiles = 'SDK.ExcuKind
  type Require HoldFiles = FileNames
  type Error HoldFiles = HoldFilesError
  raise (HoldFilesError description) = SDK.failEffect "HoldFiles" HoldFilesFailure description
  handler = FrameworkRoot.handler @Root

data InspectFiles

type InspectFilesInputs m = (FrameworkRoot.Capability InspectFiles m, Effect HoldFiles m, Provides OpenedFiles m, HoldFilesEffect m, FileSessionEffect m, MonadIO m)
instance FrameworkRoot.Capability InspectFiles App

class (Effect HoldFiles m, Provides OpenedFiles m) => InspectFilesEffect m where
  inspectFiles :: m (Maybe String)
  {-# MINIMAL inspectFiles #-}

instance (Monad m, Effect HoldFiles m, InspectFilesEffect m) => Effect InspectFiles m where
  type Registration InspectFiles = Registered InspectFilesEffect HoldFiles
  type Typing InspectFiles = 'SDK.ExcuKind
  type Require InspectFiles = OpenedFiles
  type Error InspectFiles = InspectFilesError
  raise (InspectFilesError description) = SDK.failEffect "InspectFiles" InspectFilesFailure description
  handler = FrameworkRoot.handler @Root

data FinishInspection

type FinishInspectionInputs m = (FrameworkRoot.Capability FinishInspection m, Effect InspectFiles m, Provides OpenedFiles m, InspectFilesEffect m, HoldFilesEffect m, FileSessionEffect m, MonadIO m)
instance FrameworkRoot.Capability FinishInspection App

class (Effect InspectFiles m, Provides OpenedFiles m) => FinishInspectionEffect m where
  finishInspection :: m (Maybe String)
  {-# MINIMAL finishInspection #-}

instance (Monad m, Effect InspectFiles m, FinishInspectionEffect m) => Effect FinishInspection m where
  type Registration FinishInspection = Registered FinishInspectionEffect InspectFiles
  type Typing FinishInspection = 'SDK.ExcuKind
  type Require FinishInspection = OpenedFiles
  type Error FinishInspection = FinishInspectionError
  raise (FinishInspectionError description) = SDK.failEffect "FinishInspection" FinishInspectionFailure description
  handler = FrameworkRoot.handler @Root

-- 依值入口：request 重新生产，require 读取已有绑定；来源由注册解析，不由消费方指名。
class Provides contract m where
  request :: m contract
  require :: m contract

instance (FileLocationsEffect App) => Provides FileNames App where
  request = SDK.provideContext "FileNames" ContextBindingError [("HoldFiles", fileNames)]
  require = SDK.provideContext "FileNames" ContextBindingError [("FileResources", readFileNames)]

instance (FileResourcesEffect App) => Provides OpenedFiles App where
  request = SDK.provideContext "OpenedFiles" ContextBindingError [("FileSession", openedFiles)]
  require = SDK.provideContext "OpenedFiles" ContextBindingError [("FileSession", readOpenedFiles), ("InspectFiles", readOpenedFiles), ("FinishInspection", readOpenedFiles)]

-- SDK 生成的本地错误只接收消息；类型唯一确定 raise 来源。
newtype FileLocationsError = FileLocationsError String
  deriving (Eq, Show, Read)

-- SDK 生成的本地错误只接收消息；类型唯一确定 raise 来源。
newtype FileResourcesError = FileResourcesError String
  deriving (Eq, Show, Read)

-- SDK 生成的本地错误只接收消息；类型唯一确定 raise 来源。
newtype FileSessionError = FileSessionError String
  deriving (Eq, Show, Read)

-- SDK 生成的本地错误只接收消息；类型唯一确定 raise 来源。
newtype HoldFilesError = HoldFilesError String
  deriving (Eq, Show, Read)

-- SDK 生成的本地错误只接收消息；类型唯一确定 raise 来源。
newtype InspectFilesError = InspectFilesError String
  deriving (Eq, Show, Read)

-- SDK 生成的本地错误只接收消息；类型唯一确定 raise 来源。
newtype FinishInspectionError = FinishInspectionError String
  deriving (Eq, Show, Read)

-- 统一失败协议的分类标签；消息与来源由 SDK.Failure 保存。
data Errors = FileLocationsFailure | FileResourcesFailure | FileSessionFailure | HoldFilesFailure | InspectFilesFailure | FinishInspectionFailure | ContextBindingError SDK.ContextFault | ScopeBindingError SDK.ScopeFault
  deriving (Eq, Show)

-- SDK 内部存储：Nothing 仅表示本次运行尚未建立绑定，不是业务缺值。
data ContextValues = ContextValues
  { boundFileLocations :: Maybe (Produce FileLocations)
  , boundFileResources :: Maybe (Produce FileResources)
  }

emptyContexts :: ContextValues
emptyContexts = ContextValues Nothing Nothing

