{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE EmptyDataDecls #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
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
import OpenFilesDemo.Types

-- SDK 提供运行载体与空存储；Context 经声明的 request/require 取得。
type Root = SDK.Root ContextValues Errors
type App = SDK.App ContextValues Errors

data FileLocations

class (Effect Root m) => FileLocationsEffect m where
  getFileNames :: m (Produce FileLocations)
  readFileNames :: m (Produce FileLocations)
  readFileNames = (FrameworkRoot.withErrorPath [] . FrameworkRoot.handler @Root) $
    SDK.readContext "FileLocations" ContextBindingError [("FileResources", SDK.RequestValue)] (Just (SDK.ScopeInput "FileLocations")) boundFileLocations
  {-# MINIMAL getFileNames #-}

instance (Monad m, Effect Root m, FileLocationsEffect m) => Effect FileLocations m where
  type Registration FileLocations = Registered FileLocationsEffect Root
  type Typing FileLocations = 'SDK.ContextKind
  type Require FileLocations = SDK.Void
  type Produce FileLocations = FileNames
  type Error FileLocations = FileLocationsError
  raise (FileLocationsError description) = SDK.failEffect "FileLocations" FileLocationsFailure description
  handler = FrameworkRoot.handler @Root

data FileResources

class (Effect Root m, Effect FileLocations m, Produce FileLocations ~ (FileNames)) => FileResourcesEffect m where
  acquireFiles :: m (Produce FileResources)
  readOpenedFiles :: m (Produce FileResources)
  readOpenedFiles = (FrameworkRoot.withErrorPath [] . FrameworkRoot.handler @Root) $
    SDK.readContext "FileResources" ContextBindingError [("FileSession", SDK.RequestValue), ("InspectFiles", SDK.RequireValue), ("FinishInspection", SDK.RequireValue)] Nothing boundFileResources
  {-# MINIMAL acquireFiles #-}

instance (Monad m, Effect Root m, FileResourcesEffect m) => Effect FileResources m where
  type Registration FileResources = Registered FileResourcesEffect Root
  type Typing FileResources = 'SDK.ContextKind
  type Require FileResources = FileNames
  type Produce FileResources = OpenedFiles
  type Error FileResources = FileResourcesError
  raise (FileResourcesError description) = SDK.failEffect "FileResources" FileResourcesFailure description
  handler = FrameworkRoot.handler @Root

data FileSession

class (Effect Root m, Effect FileResources m, Produce FileResources ~ (OpenedFiles)) => FileSessionEffect m where
  openFiles :: m ()
  closeFiles :: m ()
  {-# MINIMAL openFiles, closeFiles #-}

instance (Monad m, Effect Root m, FileSessionEffect m) => Effect FileSession m where
  type Registration FileSession = Registered FileSessionEffect Root
  type Typing FileSession = 'SDK.ScopedKind
  type Require FileSession = (OpenedFiles, OpenedFiles)
  type Error FileSession = FileSessionError
  raise (FileSessionError description) = SDK.failEffect "FileSession" FileSessionFailure description
  handler = FrameworkRoot.handler @Root

data HoldFiles

class (Effect FileSession m) => HoldFilesEffect m where
  holdFiles :: m ()
  {-# MINIMAL holdFiles #-}

instance (Monad m, Effect FileSession m, HoldFilesEffect m) => Effect HoldFiles m where
  type Registration HoldFiles = Registered HoldFilesEffect FileSession
  type Typing HoldFiles = 'SDK.ExcuKind
  type Require HoldFiles = SDK.Void
  type Error HoldFiles = HoldFilesError
  raise (HoldFilesError description) = SDK.failEffect "HoldFiles" HoldFilesFailure description
  handler = FrameworkRoot.handler @Root

data InspectFiles

class (Effect HoldFiles m, Effect FileResources m, Produce FileResources ~ (OpenedFiles)) => InspectFilesEffect m where
  inspectFiles :: m ()
  {-# MINIMAL inspectFiles #-}

instance (Monad m, Effect HoldFiles m, InspectFilesEffect m) => Effect InspectFiles m where
  type Registration InspectFiles = Registered InspectFilesEffect HoldFiles
  type Typing InspectFiles = 'SDK.ExcuKind
  type Require InspectFiles = OpenedFiles
  type Error InspectFiles = InspectFilesError
  raise (InspectFilesError description) = SDK.failEffect "InspectFiles" InspectFilesFailure description
  handler = FrameworkRoot.handler @Root

data FinishInspection

class (Effect InspectFiles m, Effect FileResources m, Produce FileResources ~ (OpenedFiles)) => FinishInspectionEffect m where
  finishInspection :: m ()
  {-# MINIMAL finishInspection #-}

instance (Monad m, Effect InspectFiles m, FinishInspectionEffect m) => Effect FinishInspection m where
  type Registration FinishInspection = Registered FinishInspectionEffect InspectFiles
  type Typing FinishInspection = 'SDK.ExcuKind
  type Require FinishInspection = OpenedFiles
  type Error FinishInspection = FinishInspectionError
  raise (FinishInspectionError description) = SDK.failEffect "FinishInspection" FinishInspectionFailure description
  handler = FrameworkRoot.handler @Root

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

