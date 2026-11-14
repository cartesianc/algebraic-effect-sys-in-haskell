{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MonoLocalBinds #-}
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
newtype OpenedInput = OpenedInput (InputFile)
deriving instance Eq (InputFile) => Eq OpenedInput
deriving instance Show (InputFile) => Show OpenedInput

newtype TextLine = TextLine (Line)
deriving instance Eq (Line) => Eq TextLine
deriving instance Show (Line) => Show TextLine

-- effect 方法的定义身份；仅生成区使用，图中不以字符串匹配方法。
data MethodGen = RunAnnounceGen | GetOpenedInputGen | ReadOpenedInputGen | OpenInputSessionGen | CloseInputSessionGen | NextLineFeedGen | GetTextLineGen | StreamTextLineGen | RunPrintLineGen | RunReportGen
  deriving (Eq, Ord, Show, Read, SDK.Generic)
instance SDK.NFData MethodGen

-- handler announce：绑定到 Announce。
type AnnounceLayer m = (SDK.Raises AnnounceError m, MonadIO m)
class AnnounceHandler m where
  announce :: m [String]

-- 失败属于 handler：发生位置由 SDK 记录，Error 按 RaisedBy "announce" 匹配。
newtype AnnounceError = AnnounceError String
  deriving (Eq, Show, Read)

-- handler acquireInput：绑定到 InputResource。
type AcquireInputLayer m = (SDK.Raises AcquireInputError m, MonadIO m)
class AcquireInputHandler m where
  acquireInput :: m InputFile

-- 失败属于 handler：发生位置由 SDK 记录，Error 按 RaisedBy "acquireInput" 匹配。
newtype AcquireInputError = AcquireInputError String
  deriving (Eq, Show, Read)

-- handler openInput：绑定到 InputSession。
type OpenInputLayer m = (SDK.Reads (InputFile) m, SDK.Raises OpenInputError m, MonadIO m)
class OpenInputHandler m where
  openInput :: m [String]

-- 失败属于 handler：发生位置由 SDK 记录，Error 按 RaisedBy "openInput" 匹配。
newtype OpenInputError = OpenInputError String
  deriving (Eq, Show, Read)

-- handler closeInput：绑定到 InputSession。
type CloseInputLayer m = (SDK.Reads (InputFile) m, SDK.Raises CloseInputError m, MonadIO m)
class CloseInputHandler m where
  closeInput :: m [String]

-- 失败属于 handler：发生位置由 SDK 记录，Error 按 RaisedBy "closeInput" 匹配。
newtype CloseInputError = CloseInputError String
  deriving (Eq, Show, Read)

-- handler nextLine：绑定到 LineFeed。
type NextLineLayer m = (SDK.Reads (InputFile) m, SDK.Ends m, SDK.Raises NextLineError m, MonadIO m)
class NextLineHandler m where
  nextLine :: m String

-- 失败属于 handler：发生位置由 SDK 记录，Error 按 RaisedBy "nextLine" 匹配。
newtype NextLineError = NextLineError String
  deriving (Eq, Show, Read)

-- handler parseLine：绑定到 LineParser。
type ParseLineLayer m = (SDK.Raw m, SDK.Raises ParseLineError m, MonadIO m)
class ParseLineHandler m where
  parseLine :: m Line

-- 失败属于 handler：发生位置由 SDK 记录，Error 按 RaisedBy "parseLine" 匹配。
newtype ParseLineError = ParseLineError String
  deriving (Eq, Show, Read)

-- handler printLine：绑定到 PrintLine。
type PrintLineLayer m = (SDK.Reads (SDK.History (Line)) m, SDK.Raises PrintLineError m, MonadIO m)
class PrintLineHandler m where
  printLine :: m [String]

-- 失败属于 handler：发生位置由 SDK 记录，Error 按 RaisedBy "printLine" 匹配。
newtype PrintLineError = PrintLineError String
  deriving (Eq, Show, Read)

-- handler report：绑定到 Report。
type ReportLayer m = (SDK.Raises ReportError m, MonadIO m)
class ReportHandler m where
  report :: m [String]

-- 失败属于 handler：发生位置由 SDK 记录，Error 按 RaisedBy "report" 匹配。
newtype ReportError = ReportError String
  deriving (Eq, Show, Read)

-- 统一失败协议的分类标签：每个 handler 一个；消息与发生位置由 SDK.Failure 保存。
data Errors = AnnounceFailure | AcquireInputFailure | OpenInputFailure | CloseInputFailure | NextLineFailure | ParseLineFailure | PrintLineFailure | ReportFailure | ContextBindingError SDK.ContextFault | ScopeBindingError SDK.ScopeFault
  deriving (Eq, Show)

-- SDK 内部存储：Nothing 仅表示本次运行尚未建立绑定，不是业务缺值。
data ContextValues = ContextValues
  { boundInputResource :: Maybe OpenedInput
  , boundLineParser :: Maybe TextLine
  }

emptyContexts :: ContextValues
emptyContexts = ContextValues Nothing Nothing

