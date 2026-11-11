{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MonoLocalBinds #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE UndecidableInstances #-}

-- 自动生成；通过 SDK 的 effect-codegen 更新，手写注册与 handler 位于上级目录。
module ScopeReuseDemo.Generated.Effects where

import qualified Framework.Generated as SDK
import Control.Monad.IO.Class (MonadIO)
import ScopeReuseDemo.Types

-- SDK 提供运行载体；资产存储与错误分类由本文件给出。
type App = SDK.App ContextValues Errors

-- 每个 Context 的资产类型：名字来自 Asset 声明，包装其表示类型。
newtype FilePaths = FilePaths (SharedPaths)
deriving instance Eq (SharedPaths) => Eq FilePaths
deriving instance Show (SharedPaths) => Show FilePaths

newtype OpenedFile = OpenedFile (SharedFile)
deriving instance Eq (SharedFile) => Eq OpenedFile
deriving instance Show (SharedFile) => Show OpenedFile

-- effect 方法的定义身份；仅生成区使用，图中不以字符串匹配方法。
data MethodGen = GetFilePathsGen | ReadFilePathsGen | RunPrepareProbeGen | GetOpenedFileGen | ReadOpenedFileGen | OpenSharedFileScopeGen | CloseSharedFileScopeGen | RunWriteFirstGen | RunWriteSecondGen | RunWriteThirdGen | RunVerifyReuseGen
  deriving (Eq, Ord, Show, Read, SDK.Generic)
instance SDK.NFData MethodGen

-- handler sharedPaths：绑定到 FileLocations。
type SharedPathsLayer m = (SDK.Raises SharedPathsError m, MonadIO m)
class SharedPathsHandler m where
  sharedPaths :: m SharedPaths

-- 失败属于 handler：发生位置由 SDK 记录，Error 按 RaisedBy "sharedPaths" 匹配。
newtype SharedPathsError = SharedPathsError String
  deriving (Eq, Show, Read)

-- handler prepareProbe：绑定到 PrepareProbe。
type PrepareProbeLayer m = (SDK.Reads (SharedPaths) m, SDK.Raises PrepareProbeError m, MonadIO m)
class PrepareProbeHandler m where
  prepareProbe :: m [String]

-- 失败属于 handler：发生位置由 SDK 记录，Error 按 RaisedBy "prepareProbe" 匹配。
newtype PrepareProbeError = PrepareProbeError String
  deriving (Eq, Show, Read)

-- handler acquireFile：绑定到 FileResource。
type AcquireFileLayer m = (SDK.Reads (SharedPaths) m, SDK.Raises AcquireFileError m, MonadIO m)
class AcquireFileHandler m where
  acquireFile :: m SharedFile

-- 失败属于 handler：发生位置由 SDK 记录，Error 按 RaisedBy "acquireFile" 匹配。
newtype AcquireFileError = AcquireFileError String
  deriving (Eq, Show, Read)

-- handler openSharedFile：绑定到 SharedFileScope。
type OpenSharedFileLayer m = (SDK.Reads (SharedFile) m, SDK.Raises OpenSharedFileError m, MonadIO m)
class OpenSharedFileHandler m where
  openSharedFile :: m [String]

-- 失败属于 handler：发生位置由 SDK 记录，Error 按 RaisedBy "openSharedFile" 匹配。
newtype OpenSharedFileError = OpenSharedFileError String
  deriving (Eq, Show, Read)

-- handler closeSharedFile：绑定到 SharedFileScope。
type CloseSharedFileLayer m = (SDK.Reads (SharedFile) m, SDK.Raises CloseSharedFileError m, MonadIO m)
class CloseSharedFileHandler m where
  closeSharedFile :: m [String]

-- 失败属于 handler：发生位置由 SDK 记录，Error 按 RaisedBy "closeSharedFile" 匹配。
newtype CloseSharedFileError = CloseSharedFileError String
  deriving (Eq, Show, Read)

-- handler writeFirst：绑定到 WriteFirst。
type WriteFirstLayer m = (SDK.Reads (SharedFile) m, SDK.Raises WriteFirstError m, MonadIO m)
class WriteFirstHandler m where
  writeFirst :: m [String]

-- 失败属于 handler：发生位置由 SDK 记录，Error 按 RaisedBy "writeFirst" 匹配。
newtype WriteFirstError = WriteFirstError String
  deriving (Eq, Show, Read)

-- handler writeSecond：绑定到 WriteSecond。
type WriteSecondLayer m = (SDK.Reads (SharedFile) m, SDK.Raises WriteSecondError m, MonadIO m)
class WriteSecondHandler m where
  writeSecond :: m [String]

-- 失败属于 handler：发生位置由 SDK 记录，Error 按 RaisedBy "writeSecond" 匹配。
newtype WriteSecondError = WriteSecondError String
  deriving (Eq, Show, Read)

-- handler writeThird：绑定到 WriteThird。
type WriteThirdLayer m = (SDK.Reads (SharedFile) m, SDK.Raises WriteThirdError m, MonadIO m)
class WriteThirdHandler m where
  writeThird :: m [String]

-- 失败属于 handler：发生位置由 SDK 记录，Error 按 RaisedBy "writeThird" 匹配。
newtype WriteThirdError = WriteThirdError String
  deriving (Eq, Show, Read)

-- handler verifyReuse：绑定到 VerifyReuse。
type VerifyReuseLayer m = (SDK.Reads (SharedPaths) m, SDK.Raises VerifyReuseError m, MonadIO m)
class VerifyReuseHandler m where
  verifyReuse :: m [String]

-- 失败属于 handler：发生位置由 SDK 记录，Error 按 RaisedBy "verifyReuse" 匹配。
newtype VerifyReuseError = VerifyReuseError String
  deriving (Eq, Show, Read)

-- 统一失败协议的分类标签：每个 handler 一个；消息与发生位置由 SDK.Failure 保存。
data Errors = SharedPathsFailure | PrepareProbeFailure | AcquireFileFailure | OpenSharedFileFailure | CloseSharedFileFailure | WriteFirstFailure | WriteSecondFailure | WriteThirdFailure | VerifyReuseFailure | ContextBindingError SDK.ContextFault | ScopeBindingError SDK.ScopeFault
  deriving (Eq, Show)

-- SDK 内部存储：Nothing 仅表示本次运行尚未建立绑定，不是业务缺值。
data ContextValues = ContextValues
  { boundFileLocations :: Maybe FilePaths
  , boundFileResource :: Maybe OpenedFile
  }

emptyContexts :: ContextValues
emptyContexts = ContextValues Nothing Nothing

