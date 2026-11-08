{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MonoLocalBinds #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE UndecidableInstances #-}

-- 自动生成；通过 SDK 的 effect-codegen 更新，手写注册与 handler 位于上级目录。
module ScopeInstancesDemo.Generated.Effects where

import qualified Framework.Generated as SDK
import Control.Monad.IO.Class (MonadIO)
import ScopeInstancesDemo.Types

-- SDK 提供运行载体；资产存储与错误分类由本文件给出。
type App = SDK.App ContextValues Errors

-- 每个 Context 的资产类型：名字来自 Asset 声明，包装其表示类型。
newtype FileName = FileName ([Char])
deriving instance Eq ([Char]) => Eq FileName
deriving instance Show ([Char]) => Show FileName

newtype OpenedFile = OpenedFile (FileHandle)
deriving instance Eq (FileHandle) => Eq OpenedFile
deriving instance Show (FileHandle) => Show OpenedFile

-- effect 方法的定义身份；仅生成区使用，图中不以字符串匹配方法。
data MethodGen = RunPrepareFilesGen | GetFileNameGen | ReadFileNameGen | GetOpenedFileGen | ReadOpenedFileGen | OpenFileSessionGen | CloseFileSessionGen | RunUseFirstGen | RunSelectSecondGen | RunUseSecondGen | RunSelectFirstGen | RunReopenFirstGen | RunCheckJournalGen
  deriving (Eq, Ord, Show, Read, SDK.Generic)
instance SDK.NFData MethodGen

-- handler prepareFiles：绑定到 PrepareFiles。
type PrepareFilesLayer m = (SDK.Raises PrepareFilesError m, MonadIO m)
class PrepareFilesHandler m where
  prepareFiles :: m (Maybe String)

-- 失败属于 handler：发生位置由 SDK 记录，Error 按 RaisedBy "prepareFiles" 匹配。
newtype PrepareFilesError = PrepareFilesError String
  deriving (Eq, Show, Read)

-- handler selectedFile：绑定到 FileLocation。
type SelectedFileLayer m = (SDK.Raises SelectedFileError m, MonadIO m)
class SelectedFileHandler m where
  selectedFile :: m [Char]

-- 失败属于 handler：发生位置由 SDK 记录，Error 按 RaisedBy "selectedFile" 匹配。
newtype SelectedFileError = SelectedFileError String
  deriving (Eq, Show, Read)

-- handler acquireFile：绑定到 FileResource。
type AcquireFileLayer m = (SDK.Reads ([Char]) m, SDK.Raises AcquireFileError m, MonadIO m)
class AcquireFileHandler m where
  acquireFile :: m FileHandle

-- 失败属于 handler：发生位置由 SDK 记录，Error 按 RaisedBy "acquireFile" 匹配。
newtype AcquireFileError = AcquireFileError String
  deriving (Eq, Show, Read)

-- handler openSelectedFile：绑定到 FileSession。
type OpenSelectedFileLayer m = (SDK.Reads (FileHandle) m, SDK.Raises OpenSelectedFileError m, MonadIO m)
class OpenSelectedFileHandler m where
  openSelectedFile :: m (Maybe String)

-- 失败属于 handler：发生位置由 SDK 记录，Error 按 RaisedBy "openSelectedFile" 匹配。
newtype OpenSelectedFileError = OpenSelectedFileError String
  deriving (Eq, Show, Read)

-- handler closeSelectedFile：绑定到 FileSession。
type CloseSelectedFileLayer m = (SDK.Reads (FileHandle) m, SDK.Raises CloseSelectedFileError m, MonadIO m)
class CloseSelectedFileHandler m where
  closeSelectedFile :: m (Maybe String)

-- 失败属于 handler：发生位置由 SDK 记录，Error 按 RaisedBy "closeSelectedFile" 匹配。
newtype CloseSelectedFileError = CloseSelectedFileError String
  deriving (Eq, Show, Read)

-- handler checkSelection：绑定到 UseFirst、UseSecond、ReopenFirst。
type CheckSelectionLayer m = (SDK.Reads (FileHandle) m, SDK.Reads ([Char]) m, SDK.Raises CheckSelectionError m, MonadIO m)
class CheckSelectionHandler m where
  checkSelection :: m (Maybe String)

-- 失败属于 handler：发生位置由 SDK 记录，Error 按 RaisedBy "checkSelection" 匹配。
newtype CheckSelectionError = CheckSelectionError String
  deriving (Eq, Show, Read)

-- handler selectSecond：绑定到 SelectSecond。
type SelectSecondLayer m = (SDK.Raises SelectSecondError m, MonadIO m)
class SelectSecondHandler m where
  selectSecond :: m (Maybe String)

-- 失败属于 handler：发生位置由 SDK 记录，Error 按 RaisedBy "selectSecond" 匹配。
newtype SelectSecondError = SelectSecondError String
  deriving (Eq, Show, Read)

-- handler selectFirst：绑定到 SelectFirst。
type SelectFirstLayer m = (SDK.Raises SelectFirstError m, MonadIO m)
class SelectFirstHandler m where
  selectFirst :: m (Maybe String)

-- 失败属于 handler：发生位置由 SDK 记录，Error 按 RaisedBy "selectFirst" 匹配。
newtype SelectFirstError = SelectFirstError String
  deriving (Eq, Show, Read)

-- handler checkJournal：绑定到 CheckJournal。
type CheckJournalLayer m = (SDK.Raises CheckJournalError m, MonadIO m)
class CheckJournalHandler m where
  checkJournal :: m (Maybe String)

-- 失败属于 handler：发生位置由 SDK 记录，Error 按 RaisedBy "checkJournal" 匹配。
newtype CheckJournalError = CheckJournalError String
  deriving (Eq, Show, Read)

-- 统一失败协议的分类标签：每个 handler 一个；消息与发生位置由 SDK.Failure 保存。
data Errors = PrepareFilesFailure | SelectedFileFailure | AcquireFileFailure | OpenSelectedFileFailure | CloseSelectedFileFailure | CheckSelectionFailure | SelectSecondFailure | SelectFirstFailure | CheckJournalFailure | ContextBindingError SDK.ContextFault | ScopeBindingError SDK.ScopeFault
  deriving (Eq, Show)

-- SDK 内部存储：Nothing 仅表示本次运行尚未建立绑定，不是业务缺值。
data ContextValues = ContextValues
  { boundFileLocation :: Maybe FileName
  , boundFileResource :: Maybe OpenedFile
  }

emptyContexts :: ContextValues
emptyContexts = ContextValues Nothing Nothing

