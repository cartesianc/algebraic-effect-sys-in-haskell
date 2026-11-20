{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MonoLocalBinds #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE UndecidableInstances #-}

-- 自动生成；通过 SDK 的 effect-codegen 更新，手写注册与 handler 位于上级目录。
module LinesDemo.Generated.Effects where

import qualified Framework.Generated as SDK
import Control.Monad.IO.Class (MonadIO)
import LinesDemo.Types

-- SDK 提供运行载体；资产存储与错误分类由本文件给出。
type App = SDK.App ContextValues Errors

-- 每个 Context 的资产类型：名字来自 Asset 声明，包装其表示类型。
newtype OpenedInput = OpenedInput InputFile
deriving instance Eq InputFile => Eq OpenedInput
deriving instance Show InputFile => Show OpenedInput

newtype TextLine = TextLine Line
deriving instance Eq Line => Eq TextLine
deriving instance Show Line => Show TextLine

newtype RunningTotal = RunningTotal Total
deriving instance Eq Total => Eq RunningTotal
deriving instance Show Total => Show RunningTotal

-- effect 方法的定义身份；仅生成区使用，图中不以字符串匹配方法。
data MethodGen = RunAnnounceGen | GetOpenedInputGen | ReadOpenedInputGen | OpenInputSessionGen | CloseInputSessionGen | NextLineFeedGen | HookTraceLineGen | GetTextLineGen | StreamTextLineGen | RunPrintLineGen | RunTextCounterGen | GetRunningTotalGen | StreamRunningTotalGen | RunShowTotalGen | RunReportGen
  deriving (Eq, Ord, Show, Read, SDK.Generic)
instance SDK.NFData MethodGen

-- handler announce：绑定到 Announce。
type AnnounceLayer m = (SDK.RawOutputs m, SDK.Raises AnnounceError m, MonadIO m)
class AnnounceHandler m where
  announce :: m [String]

-- 失败属于 handler：发生位置由 SDK 记录，Error 按 RaisedBy "announce" 匹配。
newtype AnnounceError = AnnounceError String
  deriving (Eq, Show, Read)
instance SDK.HandlerError AnnounceError Errors where raised (AnnounceError description) = (AnnounceFailure, description)

-- handler acquireInput：绑定到 InputResource。
type AcquireInputLayer m = (SDK.Raises AcquireInputError m, MonadIO m)
class AcquireInputHandler m where
  acquireInput :: m InputFile

-- 失败属于 handler：发生位置由 SDK 记录，Error 按 RaisedBy "acquireInput" 匹配。
newtype AcquireInputError = AcquireInputError String
  deriving (Eq, Show, Read)
instance SDK.HandlerError AcquireInputError Errors where raised (AcquireInputError description) = (AcquireInputFailure, description)

-- handler openInput：绑定到 InputSession。
type OpenInputLayer m = (SDK.Reads InputFile m, SDK.RawOutputs m, SDK.Raises OpenInputError m, MonadIO m)
class OpenInputHandler m where
  openInput :: m [String]

-- 失败属于 handler：发生位置由 SDK 记录，Error 按 RaisedBy "openInput" 匹配。
newtype OpenInputError = OpenInputError String
  deriving (Eq, Show, Read)
instance SDK.HandlerError OpenInputError Errors where raised (OpenInputError description) = (OpenInputFailure, description)

-- handler closeInput：绑定到 InputSession。
type CloseInputLayer m = (SDK.Reads InputFile m, SDK.RawOutputs m, SDK.Raises CloseInputError m, MonadIO m)
class CloseInputHandler m where
  closeInput :: m [String]

-- 失败属于 handler：发生位置由 SDK 记录，Error 按 RaisedBy "closeInput" 匹配。
newtype CloseInputError = CloseInputError String
  deriving (Eq, Show, Read)
instance SDK.HandlerError CloseInputError Errors where raised (CloseInputError description) = (CloseInputFailure, description)

-- handler nextLine：绑定到 LineFeed。
type NextLineLayer m = (SDK.Reads InputFile m, SDK.Emits m, SDK.StreamEnds m, SDK.Raises NextLineError m, MonadIO m)
class NextLineHandler m where
  nextLine :: m ()

-- 失败属于 handler：发生位置由 SDK 记录，Error 按 RaisedBy "nextLine" 匹配。
newtype NextLineError = NextLineError String
  deriving (Eq, Show, Read)
instance SDK.HandlerError NextLineError Errors where raised (NextLineError description) = (NextLineFailure, description)

-- handler traceLine：绑定到 TraceLine。
type TraceLineLayer m = (SDK.Hooks m, SDK.RawOutputs m, SDK.Raises TraceLineError m, MonadIO m)
class TraceLineHandler m where
  traceLine :: m [String]

-- 失败属于 handler：发生位置由 SDK 记录，Error 按 RaisedBy "traceLine" 匹配。
newtype TraceLineError = TraceLineError String
  deriving (Eq, Show, Read)
instance SDK.HandlerError TraceLineError Errors where raised (TraceLineError description) = (TraceLineFailure, description)

-- handler parseLine：绑定到 LineParser。
type ParseLineLayer m = (SDK.Raw m, SDK.Raises ParseLineError m, MonadIO m)
class ParseLineHandler m where
  parseLine :: m Line

-- 失败属于 handler：发生位置由 SDK 记录，Error 按 RaisedBy "parseLine" 匹配。
newtype ParseLineError = ParseLineError String
  deriving (Eq, Show, Read)
instance SDK.HandlerError ParseLineError Errors where raised (ParseLineError description) = (ParseLineFailure, description)

-- handler printLine：绑定到 PrintLine。
type PrintLineLayer m = (SDK.Reads Line m, SDK.RawOutputs m, SDK.EndsStream m, SDK.Raises PrintLineError m, MonadIO m)
class PrintLineHandler m where
  printLine :: m [String]

-- 失败属于 handler：发生位置由 SDK 记录，Error 按 RaisedBy "printLine" 匹配。
newtype PrintLineError = PrintLineError String
  deriving (Eq, Show, Read)
instance SDK.HandlerError PrintLineError Errors where raised (PrintLineError description) = (PrintLineFailure, description)

-- handler countText：绑定到 TextCounter。
type CountTextLayer m = (SDK.Reads InputFile m, SDK.Reads Line m, SDK.RawOutputs m, SDK.EndsStream m, SDK.Raises CountTextError m, MonadIO m)
class CountTextHandler m where
  countText :: m [String]

-- 失败属于 handler：发生位置由 SDK 记录，Error 按 RaisedBy "countText" 匹配。
newtype CountTextError = CountTextError String
  deriving (Eq, Show, Read)
instance SDK.HandlerError CountTextError Errors where raised (CountTextError description) = (CountTextFailure, description)

-- handler parseTotal：绑定到 CountParser。
type ParseTotalLayer m = (SDK.Raw m, SDK.Raises ParseTotalError m, MonadIO m)
class ParseTotalHandler m where
  parseTotal :: m Total

-- 失败属于 handler：发生位置由 SDK 记录，Error 按 RaisedBy "parseTotal" 匹配。
newtype ParseTotalError = ParseTotalError String
  deriving (Eq, Show, Read)
instance SDK.HandlerError ParseTotalError Errors where raised (ParseTotalError description) = (ParseTotalFailure, description)

-- handler showTotal：绑定到 ShowTotal。
type ShowTotalLayer m = (SDK.Reads Total m, SDK.RawOutputs m, SDK.EndsStream m, SDK.Raises ShowTotalError m, MonadIO m)
class ShowTotalHandler m where
  showTotal :: m [String]

-- 失败属于 handler：发生位置由 SDK 记录，Error 按 RaisedBy "showTotal" 匹配。
newtype ShowTotalError = ShowTotalError String
  deriving (Eq, Show, Read)
instance SDK.HandlerError ShowTotalError Errors where raised (ShowTotalError description) = (ShowTotalFailure, description)

-- handler report：绑定到 Report。
type ReportLayer m = (SDK.Reads Total m, SDK.RawOutputs m, SDK.Raises ReportError m, MonadIO m)
class ReportHandler m where
  report :: m [String]

-- 失败属于 handler：发生位置由 SDK 记录，Error 按 RaisedBy "report" 匹配。
newtype ReportError = ReportError String
  deriving (Eq, Show, Read)
instance SDK.HandlerError ReportError Errors where raised (ReportError description) = (ReportFailure, description)

-- 统一失败协议的分类标签：每个 handler 一个；消息与发生位置由 SDK.Failure 保存。
data Errors = AnnounceFailure | AcquireInputFailure | OpenInputFailure | CloseInputFailure | NextLineFailure | TraceLineFailure | ParseLineFailure | PrintLineFailure | CountTextFailure | ParseTotalFailure | ShowTotalFailure | ReportFailure | ContextBindingError SDK.ContextFault | ScopeBindingError SDK.ScopeFault
  deriving (Eq, Show)

-- SDK 内部存储：Nothing 仅表示本次运行尚未建立绑定，不是业务缺值。
data ContextValues = ContextValues
  { boundInputResource :: Maybe OpenedInput
  , boundLineParser :: Maybe TextLine
  , boundCountParser :: Maybe RunningTotal
  }

emptyContexts :: ContextValues
emptyContexts = ContextValues Nothing Nothing Nothing

