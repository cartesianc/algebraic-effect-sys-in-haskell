{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MonoLocalBinds #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE UndecidableInstances #-}

-- 自动生成；通过 SDK 的 effect-codegen 更新，手写注册与 handler 位于上级目录。
module FacadeProbe.Generated.Effects where

import qualified Framework.Generated as SDK
import Control.Monad.IO.Class (MonadIO)
import FacadeProbe.Types

-- SDK 提供运行载体；资产存储与错误分类由本文件给出。
type App = SDK.App ContextValues Errors

-- 每个 Context 的资产类型：名字来自 Asset 声明，包装其表示类型。
newtype ReportPath = ReportPath ([Char])
deriving instance Eq ([Char]) => Eq ReportPath
deriving instance Show ([Char]) => Show ReportPath

newtype ReplyPath = ReplyPath ([Char])
deriving instance Eq ([Char]) => Eq ReplyPath
deriving instance Show ([Char]) => Show ReplyPath

newtype ReportBody = ReportBody (Body)
deriving instance Eq (Body) => Eq ReportBody
deriving instance Show (Body) => Show ReportBody

newtype ReplyBody = ReplyBody (Body)
deriving instance Eq (Body) => Eq ReplyBody
deriving instance Show (Body) => Show ReplyBody

newtype OpenedReport = OpenedReport (TextFile)
deriving instance Eq (TextFile) => Eq OpenedReport
deriving instance Show (TextFile) => Show OpenedReport

newtype OpenedReply = OpenedReply (TextFile)
deriving instance Eq (TextFile) => Eq OpenedReply
deriving instance Show (TextFile) => Show OpenedReply

newtype ReportStats = ReportStats (LineCount)
deriving instance Eq (LineCount) => Eq ReportStats
deriving instance Show (LineCount) => Show ReportStats

newtype ReplyStats = ReplyStats (LineCount)
deriving instance Eq (LineCount) => Eq ReplyStats
deriving instance Show (LineCount) => Show ReplyStats

newtype ReportState = ReportState (FileState)
deriving instance Eq (FileState) => Eq ReportState
deriving instance Show (FileState) => Show ReportState

newtype LevelA = LevelA (Level)
deriving instance Eq (Level) => Eq LevelA
deriving instance Show (Level) => Show LevelA

newtype LevelB = LevelB (Level)
deriving instance Eq (Level) => Eq LevelB
deriving instance Show (Level) => Show LevelB

-- effect 方法的定义身份；仅生成区使用，图中不以字符串匹配方法。
data MethodGen = GetReportPathGen | ReadReportPathGen | GetReplyPathGen | ReadReplyPathGen | GetReportBodyGen | ReadReportBodyGen | GetReplyBodyGen | ReadReplyBodyGen | GetOpenedReportGen | ReadOpenedReportGen | GetOpenedReplyGen | ReadOpenedReplyGen | OpenReportScopeGen | CloseReportScopeGen | OpenReplyScopeGen | CloseReplyScopeGen | RunWriteReportGen | RunWriteReplyGen | RunMarkReplyGen | RunReadReportGen | RunReadReplyGen | GetReportStatsGen | ReadReportStatsGen | GetReplyStatsGen | ReadReplyStatsGen | RunShowReportGen | RunShowReplyGen | GetReportStateGen | ReadReportStateGen | RunOnBlankGen | RunOnFilledGen | NextFeedAGen | NextFeedBGen | GetLevelAGen | StreamLevelAGen | GetLevelBGen | StreamLevelBGen | RunShowAGen | RunShowBGen
  deriving (Eq, Ord, Show, Read, SDK.Generic)
instance SDK.NFData MethodGen

-- handler reportLocation：绑定到 ReportLocation。
type ReportLocationLayer m = (SDK.Raises ReportLocationError m, MonadIO m)
class ReportLocationHandler m where
  reportLocation :: m [Char]

-- 失败属于 handler：发生位置由 SDK 记录，Error 按 RaisedBy "reportLocation" 匹配。
newtype ReportLocationError = ReportLocationError String
  deriving (Eq, Show, Read)

-- handler replyLocation：绑定到 ReplyLocation。
type ReplyLocationLayer m = (SDK.Raises ReplyLocationError m, MonadIO m)
class ReplyLocationHandler m where
  replyLocation :: m [Char]

-- 失败属于 handler：发生位置由 SDK 记录，Error 按 RaisedBy "replyLocation" 匹配。
newtype ReplyLocationError = ReplyLocationError String
  deriving (Eq, Show, Read)

-- handler reportDraft：绑定到 ReportDraft。
type ReportDraftLayer m = (SDK.Raises ReportDraftError m, MonadIO m)
class ReportDraftHandler m where
  reportDraft :: m Body

-- 失败属于 handler：发生位置由 SDK 记录，Error 按 RaisedBy "reportDraft" 匹配。
newtype ReportDraftError = ReportDraftError String
  deriving (Eq, Show, Read)

-- handler replyDraft：绑定到 ReplyDraft。
type ReplyDraftLayer m = (SDK.Raises ReplyDraftError m, MonadIO m)
class ReplyDraftHandler m where
  replyDraft :: m Body

-- 失败属于 handler：发生位置由 SDK 记录，Error 按 RaisedBy "replyDraft" 匹配。
newtype ReplyDraftError = ReplyDraftError String
  deriving (Eq, Show, Read)

-- handler acquireFile：绑定到 ReportFile、ReplyFile。
type AcquireFileLayer m = (SDK.Reads ([Char]) m, SDK.Raises AcquireFileError m, MonadIO m)
class AcquireFileHandler m where
  acquireFile :: m TextFile

-- 失败属于 handler：发生位置由 SDK 记录，Error 按 RaisedBy "acquireFile" 匹配。
newtype AcquireFileError = AcquireFileError String
  deriving (Eq, Show, Read)

-- handler openTextFile：绑定到 ReportScope、ReplyScope。
type OpenTextFileLayer m = (SDK.Reads (TextFile) m, SDK.Raises OpenTextFileError m, MonadIO m)
class OpenTextFileHandler m where
  openTextFile :: m (Maybe String)

-- 失败属于 handler：发生位置由 SDK 记录，Error 按 RaisedBy "openTextFile" 匹配。
newtype OpenTextFileError = OpenTextFileError String
  deriving (Eq, Show, Read)

-- handler closeTextFile：绑定到 ReportScope、ReplyScope。
type CloseTextFileLayer m = (SDK.Reads (TextFile) m, SDK.Raises CloseTextFileError m, MonadIO m)
class CloseTextFileHandler m where
  closeTextFile :: m (Maybe String)

-- 失败属于 handler：发生位置由 SDK 记录，Error 按 RaisedBy "closeTextFile" 匹配。
newtype CloseTextFileError = CloseTextFileError String
  deriving (Eq, Show, Read)

-- handler writeText：绑定到 WriteReport、WriteReply。
type WriteTextLayer m = (SDK.Reads (Body) m, SDK.Reads (TextFile) m, SDK.Raises WriteTextError m, MonadIO m)
class WriteTextHandler m where
  writeText :: m (Maybe String)

-- 失败属于 handler：发生位置由 SDK 记录，Error 按 RaisedBy "writeText" 匹配。
newtype WriteTextError = WriteTextError String
  deriving (Eq, Show, Read)

-- handler markRead：绑定到 MarkReply。
type MarkReadLayer m = (SDK.Raises MarkReadError m, MonadIO m)
class MarkReadHandler m where
  markRead :: m (Maybe String)

-- 失败属于 handler：发生位置由 SDK 记录，Error 按 RaisedBy "markRead" 匹配。
newtype MarkReadError = MarkReadError String
  deriving (Eq, Show, Read)

-- handler readText：绑定到 ReadReport、ReadReply。
type ReadTextLayer m = (SDK.Reads ([Char]) m, SDK.Raises ReadTextError m, MonadIO m)
class ReadTextHandler m where
  readText :: m (Maybe String)

-- 失败属于 handler：发生位置由 SDK 记录，Error 按 RaisedBy "readText" 匹配。
newtype ReadTextError = ReadTextError String
  deriving (Eq, Show, Read)

-- handler countLines：绑定到 ReportCounter、ReplyCounter。
type CountLinesLayer m = (SDK.Raw m, SDK.Raises CountLinesError m, MonadIO m)
class CountLinesHandler m where
  countLines :: m LineCount

-- 失败属于 handler：发生位置由 SDK 记录，Error 按 RaisedBy "countLines" 匹配。
newtype CountLinesError = CountLinesError String
  deriving (Eq, Show, Read)

-- handler showCount：绑定到 ShowReport、ShowReply。
type ShowCountLayer m = (SDK.Reads (LineCount) m, SDK.Raises ShowCountError m, MonadIO m)
class ShowCountHandler m where
  showCount :: m (Maybe String)

-- 失败属于 handler：发生位置由 SDK 记录，Error 按 RaisedBy "showCount" 匹配。
newtype ShowCountError = ShowCountError String
  deriving (Eq, Show, Read)

-- handler inspectFile：绑定到 ReportInspect。
type InspectFileLayer m = (SDK.Reads ([Char]) m, SDK.Raises InspectFileError m, MonadIO m)
class InspectFileHandler m where
  inspectFile :: m FileState

-- 失败属于 handler：发生位置由 SDK 记录，Error 按 RaisedBy "inspectFile" 匹配。
newtype InspectFileError = InspectFileError String
  deriving (Eq, Show, Read)

-- handler describeBlank：绑定到 OnBlank。
type DescribeBlankLayer m = (SDK.Reads (()) m, SDK.Raises DescribeBlankError m, MonadIO m)
class DescribeBlankHandler m where
  describeBlank :: m (Maybe String)

-- 失败属于 handler：发生位置由 SDK 记录，Error 按 RaisedBy "describeBlank" 匹配。
newtype DescribeBlankError = DescribeBlankError String
  deriving (Eq, Show, Read)

-- handler describeFilled：绑定到 OnFilled。
type DescribeFilledLayer m = (SDK.Reads (Body) m, SDK.Raises DescribeFilledError m, MonadIO m)
class DescribeFilledHandler m where
  describeFilled :: m (Maybe String)

-- 失败属于 handler：发生位置由 SDK 记录，Error 按 RaisedBy "describeFilled" 匹配。
newtype DescribeFilledError = DescribeFilledError String
  deriving (Eq, Show, Read)

-- handler nextA：绑定到 FeedA。
type NextALayer m = (SDK.Raises NextAError m, MonadIO m)
class NextAHandler m where
  nextA :: m String

-- 失败属于 handler：发生位置由 SDK 记录，Error 按 RaisedBy "nextA" 匹配。
newtype NextAError = NextAError String
  deriving (Eq, Show, Read)

-- handler nextB：绑定到 FeedB。
type NextBLayer m = (SDK.Raises NextBError m, MonadIO m)
class NextBHandler m where
  nextB :: m String

-- 失败属于 handler：发生位置由 SDK 记录，Error 按 RaisedBy "nextB" 匹配。
newtype NextBError = NextBError String
  deriving (Eq, Show, Read)

-- handler parseLevel：绑定到 ParserA、ParserB。
type ParseLevelLayer m = (SDK.Raw m, SDK.Raises ParseLevelError m, MonadIO m)
class ParseLevelHandler m where
  parseLevel :: m Level

-- 失败属于 handler：发生位置由 SDK 记录，Error 按 RaisedBy "parseLevel" 匹配。
newtype ParseLevelError = ParseLevelError String
  deriving (Eq, Show, Read)

-- handler showLevel：绑定到 ShowA、ShowB。
type ShowLevelLayer m = (SDK.Reads (SDK.History (Level)) m, SDK.Raises ShowLevelError m, MonadIO m)
class ShowLevelHandler m where
  showLevel :: m (Maybe String)

-- 失败属于 handler：发生位置由 SDK 记录，Error 按 RaisedBy "showLevel" 匹配。
newtype ShowLevelError = ShowLevelError String
  deriving (Eq, Show, Read)

-- 统一失败协议的分类标签：每个 handler 一个；消息与发生位置由 SDK.Failure 保存。
data Errors = ReportLocationFailure | ReplyLocationFailure | ReportDraftFailure | ReplyDraftFailure | AcquireFileFailure | OpenTextFileFailure | CloseTextFileFailure | WriteTextFailure | MarkReadFailure | ReadTextFailure | CountLinesFailure | ShowCountFailure | InspectFileFailure | DescribeBlankFailure | DescribeFilledFailure | NextAFailure | NextBFailure | ParseLevelFailure | ShowLevelFailure | ContextBindingError SDK.ContextFault | ScopeBindingError SDK.ScopeFault
  deriving (Eq, Show)

-- SDK 内部存储：Nothing 仅表示本次运行尚未建立绑定，不是业务缺值。
data ContextValues = ContextValues
  { boundReportLocation :: Maybe ReportPath
  , boundReplyLocation :: Maybe ReplyPath
  , boundReportDraft :: Maybe ReportBody
  , boundReplyDraft :: Maybe ReplyBody
  , boundReportFile :: Maybe OpenedReport
  , boundReplyFile :: Maybe OpenedReply
  , boundReportCounter :: Maybe ReportStats
  , boundReplyCounter :: Maybe ReplyStats
  , boundReportInspect :: Maybe ReportState
  , boundParserA :: Maybe LevelA
  , boundParserB :: Maybe LevelB
  }

emptyContexts :: ContextValues
emptyContexts = ContextValues Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing

