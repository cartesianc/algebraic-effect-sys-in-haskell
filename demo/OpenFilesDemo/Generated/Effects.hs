{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MonoLocalBinds #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE UndecidableInstances #-}

-- 自动生成；通过 SDK 的 effect-codegen 更新，手写注册与 handler 位于上级目录。
module OpenFilesDemo.Generated.Effects where

import qualified Framework.Generated as SDK
import Control.Monad.IO.Class (MonadIO)
import OpenFilesDemo.Types

-- SDK 提供运行载体；资产存储与错误分类由本文件给出。
type App = SDK.App ContextValues Errors

-- 每个 Context 的资产类型：名字来自 Asset 声明，包装其表示类型。
newtype FileNames = FileNames ([[Char]])
deriving instance Eq ([[Char]]) => Eq FileNames
deriving instance Show ([[Char]]) => Show FileNames

newtype OpenedFiles = OpenedFiles ([FileHandle])
deriving instance Eq ([FileHandle]) => Eq OpenedFiles
deriving instance Show ([FileHandle]) => Show OpenedFiles

newtype InspectedFiles = InspectedFiles ([FileHandle])
deriving instance Eq ([FileHandle]) => Eq InspectedFiles
deriving instance Show ([FileHandle]) => Show InspectedFiles

-- effect 方法的定义身份；仅生成区使用，图中不以字符串匹配方法。
data MethodGen = GetFileNamesGen | ReadFileNamesGen | GetOpenedFilesGen | ReadOpenedFilesGen | OpenFileSessionGen | CloseFileSessionGen | RunHoldFilesGen | RunInspectFilesGen | RunReleaseFilesGen | GetInspectedFilesGen | ReadInspectedFilesGen | RunFinishInspectionGen
  deriving (Eq, Ord, Show, Read, SDK.Generic)
instance SDK.NFData MethodGen

-- handler listFiles：绑定到 FileLocations。
type ListFilesLayer m = (SDK.Raises ListFilesError m, MonadIO m)
class ListFilesHandler m where
  listFiles :: m [[Char]]

-- 失败属于 handler：发生位置由 SDK 记录，Error 按 RaisedBy "listFiles" 匹配。
newtype ListFilesError = ListFilesError String
  deriving (Eq, Show, Read)

-- handler acquireFiles：绑定到 FileResources。
type AcquireFilesLayer m = (SDK.Reads ([[Char]]) m, SDK.Raises AcquireFilesError m, MonadIO m)
class AcquireFilesHandler m where
  acquireFiles :: m [FileHandle]

-- 失败属于 handler：发生位置由 SDK 记录，Error 按 RaisedBy "acquireFiles" 匹配。
newtype AcquireFilesError = AcquireFilesError String
  deriving (Eq, Show, Read)

-- handler openFiles：绑定到 FileSession。
type OpenFilesLayer m = (SDK.Reads ([FileHandle]) m, SDK.Raises OpenFilesError m, MonadIO m)
class OpenFilesHandler m where
  openFiles :: m [String]

-- 失败属于 handler：发生位置由 SDK 记录，Error 按 RaisedBy "openFiles" 匹配。
newtype OpenFilesError = OpenFilesError String
  deriving (Eq, Show, Read)

-- handler closeFiles：绑定到 FileSession。
type CloseFilesLayer m = (SDK.Reads ([FileHandle]) m, SDK.Raises CloseFilesError m, MonadIO m)
class CloseFilesHandler m where
  closeFiles :: m [String]

-- 失败属于 handler：发生位置由 SDK 记录，Error 按 RaisedBy "closeFiles" 匹配。
newtype CloseFilesError = CloseFilesError String
  deriving (Eq, Show, Read)

-- handler holdFiles：绑定到 HoldFiles、ReleaseFiles。
type HoldFilesLayer m = (SDK.Raises HoldFilesError m, MonadIO m)
class HoldFilesHandler m where
  holdFiles :: m [String]

-- 失败属于 handler：发生位置由 SDK 记录，Error 按 RaisedBy "holdFiles" 匹配。
newtype HoldFilesError = HoldFilesError String
  deriving (Eq, Show, Read)

-- handler inspectFiles：绑定到 InspectFiles。
type InspectFilesLayer m = (SDK.Reads ([FileHandle]) m, SDK.Raises InspectFilesError m, MonadIO m)
class InspectFilesHandler m where
  inspectFiles :: m [String]

-- 失败属于 handler：发生位置由 SDK 记录，Error 按 RaisedBy "inspectFiles" 匹配。
newtype InspectFilesError = InspectFilesError String
  deriving (Eq, Show, Read)

-- handler snapshotFiles：绑定到 InspectionSnapshot。
type SnapshotFilesLayer m = (SDK.Reads ([FileHandle]) m, SDK.Raw m, SDK.Raises SnapshotFilesError m, MonadIO m)
class SnapshotFilesHandler m where
  snapshotFiles :: m [FileHandle]

-- 失败属于 handler：发生位置由 SDK 记录，Error 按 RaisedBy "snapshotFiles" 匹配。
newtype SnapshotFilesError = SnapshotFilesError String
  deriving (Eq, Show, Read)

-- handler finishInspection：绑定到 FinishInspection。
type FinishInspectionLayer m = (SDK.Reads ([FileHandle]) m, SDK.Raises FinishInspectionError m, MonadIO m)
class FinishInspectionHandler m where
  finishInspection :: m [String]

-- 失败属于 handler：发生位置由 SDK 记录，Error 按 RaisedBy "finishInspection" 匹配。
newtype FinishInspectionError = FinishInspectionError String
  deriving (Eq, Show, Read)

-- 统一失败协议的分类标签：每个 handler 一个；消息与发生位置由 SDK.Failure 保存。
data Errors = ListFilesFailure | AcquireFilesFailure | OpenFilesFailure | CloseFilesFailure | HoldFilesFailure | InspectFilesFailure | SnapshotFilesFailure | FinishInspectionFailure | ContextBindingError SDK.ContextFault | ScopeBindingError SDK.ScopeFault
  deriving (Eq, Show)

-- SDK 内部存储：Nothing 仅表示本次运行尚未建立绑定，不是业务缺值。
data ContextValues = ContextValues
  { boundFileLocations :: Maybe FileNames
  , boundFileResources :: Maybe OpenedFiles
  , boundInspectionSnapshot :: Maybe InspectedFiles
  }

emptyContexts :: ContextValues
emptyContexts = ContextValues Nothing Nothing Nothing

