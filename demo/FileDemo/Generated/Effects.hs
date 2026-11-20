{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MonoLocalBinds #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE UndecidableInstances #-}

-- 自动生成；通过 SDK 的 effect-codegen 更新，手写注册与 handler 位于上级目录。
module FileDemo.Generated.Effects where

import qualified Framework.Generated as SDK
import Control.Monad.IO.Class (MonadIO)
import FileDemo.Types

-- SDK 提供运行载体；资产存储与错误分类由本文件给出。
type App = SDK.App ContextValues Errors

-- 每个 Context 的资产类型：名字来自 Asset 声明，包装其表示类型。
newtype FileName = FileName [Char]
deriving instance Eq [Char] => Eq FileName
deriving instance Show [Char] => Show FileName

newtype OpenedFile = OpenedFile FileHandle
deriving instance Eq FileHandle => Eq OpenedFile
deriving instance Show FileHandle => Show OpenedFile

newtype FileBlank = FileBlank EmptyText
deriving instance Eq EmptyText => Eq FileBlank
deriving instance Show EmptyText => Show FileBlank

newtype FileWritten = FileWritten WrittenText
deriving instance Eq WrittenText => Eq FileWritten
deriving instance Show WrittenText => Show FileWritten

-- effect 方法的定义身份；仅生成区使用，图中不以字符串匹配方法。
data MethodGen = RunLocateFileGen | RunValidateFileNameGen | GetFileNameGen | ReadFileNameGen | GetOpenedFileGen | ReadOpenedFileGen | OpenFileSessionGen | CloseFileSessionGen | DetectFileRecoveryGen | ResolveFileRecoveryGen | RunReadFileGen | GetFileBlankGen | ReadFileBlankGen | GetFileWrittenGen | ReadFileWrittenGen | RunWriteFirstLineGen | RunAppendLineGen
  deriving (Eq, Ord, Show, Read, SDK.Generic)
instance SDK.NFData MethodGen

-- handler locateFile：绑定到 LocateFile。
type LocateFileLayer m = (SDK.RawOutputs m, SDK.Raises LocateFileError m, MonadIO m)
class LocateFileHandler m where
  locateFile :: m [String]

-- 失败属于 handler：发生位置由 SDK 记录，Error 按 RaisedBy "locateFile" 匹配。
newtype LocateFileError = LocateFileError String
  deriving (Eq, Show, Read)
instance SDK.HandlerError LocateFileError Errors where raised (LocateFileError description) = (LocateFileFailure, description)

-- handler validateFileName：绑定到 ValidateFileName。
type ValidateFileNameLayer m = (SDK.Raw m, SDK.RawOutputs m, SDK.Raises ValidateFileNameError m, Monad m)
class ValidateFileNameHandler m where
  validateFileName :: m [String]

-- 失败属于 handler：发生位置由 SDK 记录，Error 按 RaisedBy "validateFileName" 匹配。
newtype ValidateFileNameError = ValidateFileNameError String
  deriving (Eq, Show, Read)
instance SDK.HandlerError ValidateFileNameError Errors where raised (ValidateFileNameError description) = (ValidateFileNameFailure, description)

-- handler parseFileName：绑定到 FileLocation。
type ParseFileNameLayer m = (SDK.Raw m, SDK.Raises ParseFileNameError m, MonadIO m)
class ParseFileNameHandler m where
  parseFileName :: m [Char]

-- 失败属于 handler：发生位置由 SDK 记录，Error 按 RaisedBy "parseFileName" 匹配。
newtype ParseFileNameError = ParseFileNameError String
  deriving (Eq, Show, Read)
instance SDK.HandlerError ParseFileNameError Errors where raised (ParseFileNameError description) = (ParseFileNameFailure, description)

-- handler acquireFile：绑定到 FileResource。
type AcquireFileLayer m = (SDK.Reads [Char] m, SDK.Raises AcquireFileError m, MonadIO m)
class AcquireFileHandler m where
  acquireFile :: m FileHandle

-- 失败属于 handler：发生位置由 SDK 记录，Error 按 RaisedBy "acquireFile" 匹配。
newtype AcquireFileError = AcquireFileError String
  deriving (Eq, Show, Read)
instance SDK.HandlerError AcquireFileError Errors where raised (AcquireFileError description) = (AcquireFileFailure, description)

-- handler openSession：绑定到 FileSession。
type OpenSessionLayer m = (SDK.Reads FileHandle m, SDK.RawOutputs m, SDK.Raises OpenSessionError m, MonadIO m)
class OpenSessionHandler m where
  openSession :: m [String]

-- 失败属于 handler：发生位置由 SDK 记录，Error 按 RaisedBy "openSession" 匹配。
newtype OpenSessionError = OpenSessionError String
  deriving (Eq, Show, Read)
instance SDK.HandlerError OpenSessionError Errors where raised (OpenSessionError description) = (OpenSessionFailure, description)

-- handler closeSession：绑定到 FileSession。
type CloseSessionLayer m = (SDK.Reads FileHandle m, SDK.RawOutputs m, SDK.Raises CloseSessionError m, MonadIO m)
class CloseSessionHandler m where
  closeSession :: m [String]

-- 失败属于 handler：发生位置由 SDK 记录，Error 按 RaisedBy "closeSession" 匹配。
newtype CloseSessionError = CloseSessionError String
  deriving (Eq, Show, Read)
instance SDK.HandlerError CloseSessionError Errors where raised (CloseSessionError description) = (CloseSessionFailure, description)

-- handler detectFileSession：绑定到 FileRecovery。
type DetectFileSessionLayer m = (SDK.Reads FileHandle m, SDK.Raises DetectFileSessionError m, MonadIO m)
class DetectFileSessionHandler m where
  detectFileSession :: m ()

-- 失败属于 handler：发生位置由 SDK 记录，Error 按 RaisedBy "detectFileSession" 匹配。
newtype DetectFileSessionError = DetectFileSessionError String
  deriving (Eq, Show, Read)
instance SDK.HandlerError DetectFileSessionError Errors where raised (DetectFileSessionError description) = (DetectFileSessionFailure, description)

-- handler resolveFileSession：绑定到 FileRecovery。
type ResolveFileSessionLayer m = (SDK.Reads FileHandle m, SDK.Raises ResolveFileSessionError m, MonadIO m)
class ResolveFileSessionHandler m where
  resolveFileSession :: m ()

-- 失败属于 handler：发生位置由 SDK 记录，Error 按 RaisedBy "resolveFileSession" 匹配。
newtype ResolveFileSessionError = ResolveFileSessionError String
  deriving (Eq, Show, Read)
instance SDK.HandlerError ResolveFileSessionError Errors where raised (ResolveFileSessionError description) = (ResolveFileSessionFailure, description)

-- handler readFileContent：绑定到 ReadFile。
type ReadFileContentLayer m = (SDK.Reads FileHandle m, SDK.RawOutputs m, SDK.Raises ReadFileContentError m, MonadIO m)
class ReadFileContentHandler m where
  readFileContent :: m [String]

-- 失败属于 handler：发生位置由 SDK 记录，Error 按 RaisedBy "readFileContent" 匹配。
newtype ReadFileContentError = ReadFileContentError String
  deriving (Eq, Show, Read)
instance SDK.HandlerError ReadFileContentError Errors where raised (ReadFileContentError description) = (ReadFileContentFailure, description)

-- handler parseBlankText：绑定到 BlankText。
type ParseBlankTextLayer m = (SDK.Raw m, SDK.Raises ParseBlankTextError m, MonadIO m)
class ParseBlankTextHandler m where
  parseBlankText :: m EmptyText

-- 失败属于 handler：发生位置由 SDK 记录，Error 按 RaisedBy "parseBlankText" 匹配。
newtype ParseBlankTextError = ParseBlankTextError String
  deriving (Eq, Show, Read)
instance SDK.HandlerError ParseBlankTextError Errors where raised (ParseBlankTextError description) = (ParseBlankTextFailure, description)

-- handler parseWrittenText：绑定到 FilledText。
type ParseWrittenTextLayer m = (SDK.Raw m, SDK.Raises ParseWrittenTextError m, MonadIO m)
class ParseWrittenTextHandler m where
  parseWrittenText :: m WrittenText

-- 失败属于 handler：发生位置由 SDK 记录，Error 按 RaisedBy "parseWrittenText" 匹配。
newtype ParseWrittenTextError = ParseWrittenTextError String
  deriving (Eq, Show, Read)
instance SDK.HandlerError ParseWrittenTextError Errors where raised (ParseWrittenTextError description) = (ParseWrittenTextFailure, description)

-- handler writeFirstLine：绑定到 WriteFirstLine。
type WriteFirstLineLayer m = (SDK.Reads EmptyText m, SDK.Reads FileHandle m, SDK.RawOutputs m, SDK.Raises WriteFirstLineError m, MonadIO m)
class WriteFirstLineHandler m where
  writeFirstLine :: m [String]

-- 失败属于 handler：发生位置由 SDK 记录，Error 按 RaisedBy "writeFirstLine" 匹配。
newtype WriteFirstLineError = WriteFirstLineError String
  deriving (Eq, Show, Read)
instance SDK.HandlerError WriteFirstLineError Errors where raised (WriteFirstLineError description) = (WriteFirstLineFailure, description)

-- handler appendLine：绑定到 AppendLine。
type AppendLineLayer m = (SDK.Reads FileHandle m, SDK.Reads WrittenText m, SDK.RawOutputs m, SDK.Raises AppendLineError m, MonadIO m)
class AppendLineHandler m where
  appendLine :: m [String]

-- 失败属于 handler：发生位置由 SDK 记录，Error 按 RaisedBy "appendLine" 匹配。
newtype AppendLineError = AppendLineError String
  deriving (Eq, Show, Read)
instance SDK.HandlerError AppendLineError Errors where raised (AppendLineError description) = (AppendLineFailure, description)

-- 统一失败协议的分类标签：每个 handler 一个；消息与发生位置由 SDK.Failure 保存。
data Errors = LocateFileFailure | ValidateFileNameFailure | ParseFileNameFailure | AcquireFileFailure | OpenSessionFailure | CloseSessionFailure | DetectFileSessionFailure | ResolveFileSessionFailure | ReadFileContentFailure | ParseBlankTextFailure | ParseWrittenTextFailure | WriteFirstLineFailure | AppendLineFailure | ContextBindingError SDK.ContextFault | ScopeBindingError SDK.ScopeFault
  deriving (Eq, Show)

-- SDK 内部存储：Nothing 仅表示本次运行尚未建立绑定，不是业务缺值。
data ContextValues = ContextValues
  { boundFileLocation :: Maybe FileName
  , boundFileResource :: Maybe OpenedFile
  , boundBlankText :: Maybe FileBlank
  , boundFilledText :: Maybe FileWritten
  }

emptyContexts :: ContextValues
emptyContexts = ContextValues Nothing Nothing Nothing Nothing

