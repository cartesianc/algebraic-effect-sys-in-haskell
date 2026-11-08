{-# LANGUAGE AllowAmbiguousTypes #-}
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
module FacadeProbe.Generated.Effects where

import Framework.Effect.Contract (Effect(..), Registered)
import qualified Framework.Effect.Contract as FrameworkRoot
import qualified Framework.SDK as SDK
import Control.Monad.IO.Class (MonadIO)
import FacadeProbe.Types

-- SDK 提供运行载体与空存储；Context 经声明的 request/require 取得。
type Root = SDK.Root ContextValues Errors
type App = SDK.App ContextValues Errors

-- 每个 Context 的契约类型：名字来自 handler 名，包装其表示类型；只能由该生产方构造。
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

-- ReportState 的分支契约：资产当前是 Blank 时可经 require 取得。
newtype ReportStateBlank = ReportStateBlank (())
deriving instance Eq (()) => Eq ReportStateBlank
deriving instance Show (()) => Show ReportStateBlank

-- ReportState 的分支契约：资产当前是 Filled 时可经 require 取得。
newtype ReportStateFilled = ReportStateFilled (Body)
deriving instance Eq (Body) => Eq ReportStateFilled
deriving instance Show (Body) => Show ReportStateFilled

-- 方法定义身份；仅生成区使用，图中不以字符串匹配方法。
data MethodGen = GetReportPathGen | ReadReportPathGen | GetReplyPathGen | ReadReplyPathGen | GetReportBodyGen | ReadReportBodyGen | GetReplyBodyGen | ReadReplyBodyGen | GetOpenedReportGen | ReadOpenedReportGen | GetOpenedReplyGen | ReadOpenedReplyGen | OpenReportGen | CloseReportGen | OpenReplyGen | CloseReplyGen | WriteReportGen | WriteReplyGen | MarkReplyGen | ReadReportGen | ReadReplyGen | GetReportStatsGen | ReadReportStatsGen | GetReplyStatsGen | ReadReplyStatsGen | ShowReportGen | ShowReplyGen | GetReportStateGen | ReadReportStateGen | OnBlankGen | OnFilledGen | NextAGen | NextBGen | GetLevelAGen | ReadLevelAGen | GetLevelBGen | ReadLevelBGen | ShowAGen | ShowBGen
  deriving (Eq, Ord, Show, Read, SDK.Generic)
instance SDK.NFData MethodGen

data ReportLocation

type ReportLocationInputs m = (FrameworkRoot.Capability ReportLocation m, Effect Root m, MonadIO m)
instance FrameworkRoot.Capability ReportLocation App

class (Effect Root m) => ReportLocationEffect m where
  getReportPath :: m (Produce ReportLocation)
  readReportPath :: m (Produce ReportLocation)
  readReportPath = (FrameworkRoot.withErrorPath [] . FrameworkRoot.handler @Root) $
    SDK.readContext "ReportLocation" ContextBindingError [("ReportFile", SDK.RequireValue), ("ReadReport", SDK.RequireValue), ("ReportInspect", SDK.RequireValue)] (Just (SDK.ScopeInput "ReportLocation")) boundReportLocation getReportPath
  {-# MINIMAL getReportPath #-}

instance (Monad m, Effect Root m, ReportLocationEffect m) => Effect ReportLocation m where
  type Registration ReportLocation = Registered ReportLocationEffect Root
  type Typing ReportLocation = 'SDK.ContextKind
  type Require ReportLocation = SDK.Void
  type Produce ReportLocation = ReportPath
  type Error ReportLocation = ReportLocationError
  raise (ReportLocationError description) = SDK.failEffect "ReportLocation" ReportLocationFailure description
  handler = FrameworkRoot.handler @Root

data ReplyLocation

type ReplyLocationInputs m = (FrameworkRoot.Capability ReplyLocation m, Effect Root m, MonadIO m)
instance FrameworkRoot.Capability ReplyLocation App

class (Effect Root m) => ReplyLocationEffect m where
  getReplyPath :: m (Produce ReplyLocation)
  readReplyPath :: m (Produce ReplyLocation)
  readReplyPath = (FrameworkRoot.withErrorPath [] . FrameworkRoot.handler @Root) $
    SDK.readContext "ReplyLocation" ContextBindingError [("ReplyFile", SDK.RequireValue), ("ReadReply", SDK.RequireValue)] (Just (SDK.ScopeInput "ReplyLocation")) boundReplyLocation getReplyPath
  {-# MINIMAL getReplyPath #-}

instance (Monad m, Effect Root m, ReplyLocationEffect m) => Effect ReplyLocation m where
  type Registration ReplyLocation = Registered ReplyLocationEffect Root
  type Typing ReplyLocation = 'SDK.ContextKind
  type Require ReplyLocation = SDK.Void
  type Produce ReplyLocation = ReplyPath
  type Error ReplyLocation = ReplyLocationError
  raise (ReplyLocationError description) = SDK.failEffect "ReplyLocation" ReplyLocationFailure description
  handler = FrameworkRoot.handler @Root

data ReportDraft

type ReportDraftInputs m = (FrameworkRoot.Capability ReportDraft m, Effect Root m, MonadIO m)
instance FrameworkRoot.Capability ReportDraft App

class (Effect Root m) => ReportDraftEffect m where
  getReportBody :: m (Produce ReportDraft)
  readReportBody :: m (Produce ReportDraft)
  readReportBody = (FrameworkRoot.withErrorPath [] . FrameworkRoot.handler @Root) $
    SDK.readContext "ReportDraft" ContextBindingError [("WriteReport", SDK.RequireValue)] Nothing boundReportDraft getReportBody
  {-# MINIMAL getReportBody #-}

instance (Monad m, Effect Root m, ReportDraftEffect m) => Effect ReportDraft m where
  type Registration ReportDraft = Registered ReportDraftEffect Root
  type Typing ReportDraft = 'SDK.ContextKind
  type Require ReportDraft = SDK.Void
  type Produce ReportDraft = ReportBody
  type Error ReportDraft = ReportDraftError
  raise (ReportDraftError description) = SDK.failEffect "ReportDraft" ReportDraftFailure description
  handler = FrameworkRoot.handler @Root

data ReplyDraft

type ReplyDraftInputs m = (FrameworkRoot.Capability ReplyDraft m, Effect Root m, MonadIO m)
instance FrameworkRoot.Capability ReplyDraft App

class (Effect Root m) => ReplyDraftEffect m where
  getReplyBody :: m (Produce ReplyDraft)
  readReplyBody :: m (Produce ReplyDraft)
  readReplyBody = (FrameworkRoot.withErrorPath [] . FrameworkRoot.handler @Root) $
    SDK.readContext "ReplyDraft" ContextBindingError [("WriteReply", SDK.RequireValue)] Nothing boundReplyDraft getReplyBody
  {-# MINIMAL getReplyBody #-}

instance (Monad m, Effect Root m, ReplyDraftEffect m) => Effect ReplyDraft m where
  type Registration ReplyDraft = Registered ReplyDraftEffect Root
  type Typing ReplyDraft = 'SDK.ContextKind
  type Require ReplyDraft = SDK.Void
  type Produce ReplyDraft = ReplyBody
  type Error ReplyDraft = ReplyDraftError
  raise (ReplyDraftError description) = SDK.failEffect "ReplyDraft" ReplyDraftFailure description
  handler = FrameworkRoot.handler @Root

data ReportFile

type ReportFileInputs m = (FrameworkRoot.Capability ReportFile m, Effect Root m, Provides ReportPath m, MonadIO m)
instance FrameworkRoot.Capability ReportFile App

class (Effect Root m, Provides ReportPath m) => ReportFileEffect m where
  getOpenedReport :: m (Produce ReportFile)
  readOpenedReport :: m (Produce ReportFile)
  readOpenedReport = (FrameworkRoot.withErrorPath [] . FrameworkRoot.handler @Root) $
    SDK.readContext "ReportFile" ContextBindingError [("ReportScope", SDK.RequestValue), ("WriteReport", SDK.RequireValue)] Nothing boundReportFile getOpenedReport
  {-# MINIMAL getOpenedReport #-}

instance (Monad m, Effect Root m, ReportFileEffect m) => Effect ReportFile m where
  type Registration ReportFile = Registered ReportFileEffect Root
  type Typing ReportFile = 'SDK.ContextKind
  type Require ReportFile = ReportPath
  type Produce ReportFile = OpenedReport
  type Error ReportFile = ReportFileError
  raise (ReportFileError description) = SDK.failEffect "ReportFile" ReportFileFailure description
  handler = FrameworkRoot.handler @Root

data ReplyFile

type ReplyFileInputs m = (FrameworkRoot.Capability ReplyFile m, Effect Root m, Provides ReplyPath m, MonadIO m)
instance FrameworkRoot.Capability ReplyFile App

class (Effect Root m, Provides ReplyPath m) => ReplyFileEffect m where
  getOpenedReply :: m (Produce ReplyFile)
  readOpenedReply :: m (Produce ReplyFile)
  readOpenedReply = (FrameworkRoot.withErrorPath [] . FrameworkRoot.handler @Root) $
    SDK.readContext "ReplyFile" ContextBindingError [("ReplyScope", SDK.RequestValue), ("WriteReply", SDK.RequireValue)] Nothing boundReplyFile getOpenedReply
  {-# MINIMAL getOpenedReply #-}

instance (Monad m, Effect Root m, ReplyFileEffect m) => Effect ReplyFile m where
  type Registration ReplyFile = Registered ReplyFileEffect Root
  type Typing ReplyFile = 'SDK.ContextKind
  type Require ReplyFile = ReplyPath
  type Produce ReplyFile = OpenedReply
  type Error ReplyFile = ReplyFileError
  raise (ReplyFileError description) = SDK.failEffect "ReplyFile" ReplyFileFailure description
  handler = FrameworkRoot.handler @Root

data ReportScope

type ReportScopeInputs m = (FrameworkRoot.Capability ReportScope m, Effect Root m, Provides OpenedReport m, MonadIO m)
instance FrameworkRoot.Capability ReportScope App

class (Effect Root m, Provides OpenedReport m) => ReportScopeEffect m where
  openReport :: m (Maybe String)
  closeReport :: m (Maybe String)
  {-# MINIMAL openReport, closeReport #-}

instance (Monad m, Effect Root m, ReportScopeEffect m) => Effect ReportScope m where
  type Registration ReportScope = Registered ReportScopeEffect Root
  type Typing ReportScope = 'SDK.ScopedKind
  type Require ReportScope = OpenedReport
  type Error ReportScope = ReportScopeError
  raise (ReportScopeError description) = SDK.failEffect "ReportScope" ReportScopeFailure description
  handler = FrameworkRoot.handler @Root

data ReplyScope

type ReplyScopeInputs m = (FrameworkRoot.Capability ReplyScope m, Effect Root m, Provides OpenedReply m, MonadIO m)
instance FrameworkRoot.Capability ReplyScope App

class (Effect Root m, Provides OpenedReply m) => ReplyScopeEffect m where
  openReply :: m (Maybe String)
  closeReply :: m (Maybe String)
  {-# MINIMAL openReply, closeReply #-}

instance (Monad m, Effect Root m, ReplyScopeEffect m) => Effect ReplyScope m where
  type Registration ReplyScope = Registered ReplyScopeEffect Root
  type Typing ReplyScope = 'SDK.ScopedKind
  type Require ReplyScope = OpenedReply
  type Error ReplyScope = ReplyScopeError
  raise (ReplyScopeError description) = SDK.failEffect "ReplyScope" ReplyScopeFailure description
  handler = FrameworkRoot.handler @Root

data WriteReport

type WriteReportInputs m = (FrameworkRoot.Capability WriteReport m, Effect ReportScope m, Provides OpenedReport m, Provides ReportBody m, ReportScopeEffect m, MonadIO m)
instance FrameworkRoot.Capability WriteReport App

class (Effect ReportScope m, Provides OpenedReport m, Provides ReportBody m) => WriteReportEffect m where
  writeReport :: m (Maybe String)
  {-# MINIMAL writeReport #-}

instance (Monad m, Effect ReportScope m, WriteReportEffect m) => Effect WriteReport m where
  type Registration WriteReport = Registered WriteReportEffect ReportScope
  type Typing WriteReport = 'SDK.ExcuKind
  type Require WriteReport = (OpenedReport, ReportBody)
  type Error WriteReport = WriteReportError
  raise (WriteReportError description) = SDK.failEffect "WriteReport" WriteReportFailure description
  handler = FrameworkRoot.handler @Root

data WriteReply

type WriteReplyInputs m = (FrameworkRoot.Capability WriteReply m, Effect ReplyScope m, Provides OpenedReply m, Provides ReplyBody m, ReplyScopeEffect m, MonadIO m)
instance FrameworkRoot.Capability WriteReply App

class (Effect ReplyScope m, Provides OpenedReply m, Provides ReplyBody m) => WriteReplyEffect m where
  writeReply :: m (Maybe String)
  {-# MINIMAL writeReply #-}

instance (Monad m, Effect ReplyScope m, WriteReplyEffect m) => Effect WriteReply m where
  type Registration WriteReply = Registered WriteReplyEffect ReplyScope
  type Typing WriteReply = 'SDK.ExcuKind
  type Require WriteReply = (OpenedReply, ReplyBody)
  type Error WriteReply = WriteReplyError
  raise (WriteReplyError description) = SDK.failEffect "WriteReply" WriteReplyFailure description
  handler = FrameworkRoot.handler @Root

data MarkReply

type MarkReplyInputs m = (FrameworkRoot.Capability MarkReply m, Effect Root m, MonadIO m)
instance FrameworkRoot.Capability MarkReply App

class (Effect Root m) => MarkReplyEffect m where
  markReply :: m (Maybe String)
  {-# MINIMAL markReply #-}

instance (Monad m, Effect Root m, MarkReplyEffect m) => Effect MarkReply m where
  type Registration MarkReply = Registered MarkReplyEffect Root
  type Typing MarkReply = 'SDK.ExcuKind
  type Require MarkReply = SDK.Void
  type Error MarkReply = MarkReplyError
  raise (MarkReplyError description) = SDK.failEffect "MarkReply" MarkReplyFailure description
  handler = FrameworkRoot.handler @Root

data ReadReport

type ReadReportInputs m = (FrameworkRoot.Capability ReadReport m, Effect Root m, Provides ReportPath m, MonadIO m)
instance FrameworkRoot.Capability ReadReport App

class (Effect Root m, Provides ReportPath m) => ReadReportEffect m where
  readReport :: m (Maybe String)
  {-# MINIMAL readReport #-}

instance (Monad m, Effect Root m, ReadReportEffect m) => Effect ReadReport m where
  type Registration ReadReport = Registered ReadReportEffect Root
  type Typing ReadReport = 'SDK.ExcuKind
  type Require ReadReport = ReportPath
  type Error ReadReport = ReadReportError
  raise (ReadReportError description) = SDK.failEffect "ReadReport" ReadReportFailure description
  handler = FrameworkRoot.handler @Root

data ReadReply

type ReadReplyInputs m = (FrameworkRoot.Capability ReadReply m, Effect MarkReply m, Provides ReplyPath m, MarkReplyEffect m, MonadIO m)
instance FrameworkRoot.Capability ReadReply App

class (Effect MarkReply m, Provides ReplyPath m) => ReadReplyEffect m where
  readReply :: m (Maybe String)
  {-# MINIMAL readReply #-}

instance (Monad m, Effect MarkReply m, ReadReplyEffect m) => Effect ReadReply m where
  type Registration ReadReply = Registered ReadReplyEffect MarkReply
  type Typing ReadReply = 'SDK.ExcuKind
  type Require ReadReply = ReplyPath
  type Error ReadReply = ReadReplyError
  raise (ReadReplyError description) = SDK.failEffect "ReadReply" ReadReplyFailure description
  handler = FrameworkRoot.handler @Root

data ReportCounter

type ReportCounterInputs m = (FrameworkRoot.Capability ReportCounter m, Effect ReadReport m, ReadReportEffect m, MonadIO m)
instance FrameworkRoot.Capability ReportCounter App

class (Effect ReadReport m) => ReportCounterEffect m where
  getReportStats :: m (Produce ReportCounter)
  readReportStats :: m (Produce ReportCounter)
  readReportStats = (FrameworkRoot.withErrorPath [] . FrameworkRoot.handler @Root) $
    SDK.readContext "ReportCounter" ContextBindingError [("ShowReport", SDK.RequireValue)] Nothing boundReportCounter getReportStats
  {-# MINIMAL getReportStats #-}

instance (Monad m, Effect ReadReport m, ReportCounterEffect m) => Effect ReportCounter m where
  type Registration ReportCounter = Registered ReportCounterEffect ReadReport
  type Typing ReportCounter = 'SDK.ContextKind
  type Require ReportCounter = SDK.Void
  type Produce ReportCounter = ReportStats
  type Error ReportCounter = ReportCounterError
  raise (ReportCounterError description) = SDK.failEffect "ReportCounter" ReportCounterFailure description
  handler = FrameworkRoot.handler @Root

data ReplyCounter

type ReplyCounterInputs m = (FrameworkRoot.Capability ReplyCounter m, Effect ReadReply m, ReadReplyEffect m, MarkReplyEffect m, MonadIO m)
instance FrameworkRoot.Capability ReplyCounter App

class (Effect ReadReply m) => ReplyCounterEffect m where
  getReplyStats :: m (Produce ReplyCounter)
  readReplyStats :: m (Produce ReplyCounter)
  readReplyStats = (FrameworkRoot.withErrorPath [] . FrameworkRoot.handler @Root) $
    SDK.readContext "ReplyCounter" ContextBindingError [("ShowReply", SDK.RequireValue)] Nothing boundReplyCounter getReplyStats
  {-# MINIMAL getReplyStats #-}

instance (Monad m, Effect ReadReply m, ReplyCounterEffect m) => Effect ReplyCounter m where
  type Registration ReplyCounter = Registered ReplyCounterEffect ReadReply
  type Typing ReplyCounter = 'SDK.ContextKind
  type Require ReplyCounter = SDK.Void
  type Produce ReplyCounter = ReplyStats
  type Error ReplyCounter = ReplyCounterError
  raise (ReplyCounterError description) = SDK.failEffect "ReplyCounter" ReplyCounterFailure description
  handler = FrameworkRoot.handler @Root

data ShowReport

type ShowReportInputs m = (FrameworkRoot.Capability ShowReport m, Effect Root m, Provides ReportStats m, MonadIO m)
instance FrameworkRoot.Capability ShowReport App

class (Effect Root m, Provides ReportStats m) => ShowReportEffect m where
  showReport :: m (Maybe String)
  {-# MINIMAL showReport #-}

instance (Monad m, Effect Root m, ShowReportEffect m) => Effect ShowReport m where
  type Registration ShowReport = Registered ShowReportEffect Root
  type Typing ShowReport = 'SDK.ExcuKind
  type Require ShowReport = ReportStats
  type Error ShowReport = ShowReportError
  raise (ShowReportError description) = SDK.failEffect "ShowReport" ShowReportFailure description
  handler = FrameworkRoot.handler @Root

data ShowReply

type ShowReplyInputs m = (FrameworkRoot.Capability ShowReply m, Effect Root m, Provides ReplyStats m, MonadIO m)
instance FrameworkRoot.Capability ShowReply App

class (Effect Root m, Provides ReplyStats m) => ShowReplyEffect m where
  showReply :: m (Maybe String)
  {-# MINIMAL showReply #-}

instance (Monad m, Effect Root m, ShowReplyEffect m) => Effect ShowReply m where
  type Registration ShowReply = Registered ShowReplyEffect Root
  type Typing ShowReply = 'SDK.ExcuKind
  type Require ShowReply = ReplyStats
  type Error ShowReply = ShowReplyError
  raise (ShowReplyError description) = SDK.failEffect "ShowReply" ShowReplyFailure description
  handler = FrameworkRoot.handler @Root

data ReportInspect

type ReportInspectInputs m = (FrameworkRoot.Capability ReportInspect m, Effect Root m, Provides ReportPath m, MonadIO m)
instance FrameworkRoot.Capability ReportInspect App

class (Effect Root m, Provides ReportPath m) => ReportInspectEffect m where
  getReportState :: m (Produce ReportInspect)
  readReportState :: m (Produce ReportInspect)
  readReportState = (FrameworkRoot.withErrorPath [] . FrameworkRoot.handler @Root) $
    SDK.readContext "ReportInspect" ContextBindingError [("OnBlank", SDK.RequireValue), ("OnFilled", SDK.RequireValue)] Nothing boundReportInspect getReportState
  {-# MINIMAL getReportState #-}

instance (Monad m, Effect Root m, ReportInspectEffect m) => Effect ReportInspect m where
  type Registration ReportInspect = Registered ReportInspectEffect Root
  type Typing ReportInspect = 'SDK.ContextKind
  type Require ReportInspect = ReportPath
  type Produce ReportInspect = ReportState
  type Error ReportInspect = ReportInspectError
  raise (ReportInspectError description) = SDK.failEffect "ReportInspect" ReportInspectFailure description
  handler = FrameworkRoot.handler @Root

data OnBlank

type OnBlankInputs m = (FrameworkRoot.Capability OnBlank m, Effect Root m, Provides ReportStateBlank m, MonadIO m)
instance FrameworkRoot.Capability OnBlank App

class (Effect Root m, Provides ReportStateBlank m) => OnBlankEffect m where
  onBlank :: m (Maybe String)
  {-# MINIMAL onBlank #-}

instance (Monad m, Effect Root m, OnBlankEffect m) => Effect OnBlank m where
  type Registration OnBlank = Registered OnBlankEffect Root
  type Typing OnBlank = 'SDK.ExcuKind
  type Require OnBlank = ReportStateBlank
  type Error OnBlank = OnBlankError
  raise (OnBlankError description) = SDK.failEffect "OnBlank" OnBlankFailure description
  handler = FrameworkRoot.handler @Root

data OnFilled

type OnFilledInputs m = (FrameworkRoot.Capability OnFilled m, Effect Root m, Provides ReportStateFilled m, MonadIO m)
instance FrameworkRoot.Capability OnFilled App

class (Effect Root m, Provides ReportStateFilled m) => OnFilledEffect m where
  onFilled :: m (Maybe String)
  {-# MINIMAL onFilled #-}

instance (Monad m, Effect Root m, OnFilledEffect m) => Effect OnFilled m where
  type Registration OnFilled = Registered OnFilledEffect Root
  type Typing OnFilled = 'SDK.ExcuKind
  type Require OnFilled = ReportStateFilled
  type Error OnFilled = OnFilledError
  raise (OnFilledError description) = SDK.failEffect "OnFilled" OnFilledFailure description
  handler = FrameworkRoot.handler @Root

data FeedA

type FeedAInputs m = (FrameworkRoot.Capability FeedA m, Effect Root m, MonadIO m)
instance FrameworkRoot.Capability FeedA App

class (Effect Root m) => FeedAEffect m where
  nextA :: m String
  {-# MINIMAL nextA #-}

instance (Monad m, Effect Root m, FeedAEffect m) => Effect FeedA m where
  type Registration FeedA = Registered FeedAEffect Root
  type Typing FeedA = 'SDK.StreamKind
  type Require FeedA = SDK.Void
  type Error FeedA = FeedAError
  raise (FeedAError description) = SDK.failEffect "FeedA" FeedAFailure description
  handler = FrameworkRoot.handler @Root

data FeedB

type FeedBInputs m = (FrameworkRoot.Capability FeedB m, Effect Root m, MonadIO m)
instance FrameworkRoot.Capability FeedB App

class (Effect Root m) => FeedBEffect m where
  nextB :: m String
  {-# MINIMAL nextB #-}

instance (Monad m, Effect Root m, FeedBEffect m) => Effect FeedB m where
  type Registration FeedB = Registered FeedBEffect Root
  type Typing FeedB = 'SDK.StreamKind
  type Require FeedB = SDK.Void
  type Error FeedB = FeedBError
  raise (FeedBError description) = SDK.failEffect "FeedB" FeedBFailure description
  handler = FrameworkRoot.handler @Root

data ParserA

type ParserAInputs m = (FrameworkRoot.Capability ParserA m, Effect FeedA m, FeedAEffect m, MonadIO m)
instance FrameworkRoot.Capability ParserA App

class (Effect FeedA m) => ParserAEffect m where
  getLevelA :: m (Produce ParserA)
  readLevelA :: m (SDK.History (Produce ParserA))
  readLevelA = (FrameworkRoot.withErrorPath [] . FrameworkRoot.handler @Root) $
    SDK.readHistory "ParserA" ContextBindingError [("ShowA", SDK.RequireValue)] boundParserA Nothing
  {-# MINIMAL getLevelA #-}

instance (Monad m, Effect FeedA m, ParserAEffect m) => Effect ParserA m where
  type Registration ParserA = Registered ParserAEffect FeedA
  type Typing ParserA = 'SDK.ContextKind
  type Require ParserA = SDK.Void
  type Produce ParserA = LevelA
  type Error ParserA = ParserAError
  raise (ParserAError description) = SDK.failEffect "ParserA" ParserAFailure description
  handler = FrameworkRoot.handler @Root

data ParserB

type ParserBInputs m = (FrameworkRoot.Capability ParserB m, Effect FeedB m, FeedBEffect m, MonadIO m)
instance FrameworkRoot.Capability ParserB App

class (Effect FeedB m) => ParserBEffect m where
  getLevelB :: m (Produce ParserB)
  readLevelB :: m (SDK.History (Produce ParserB))
  readLevelB = (FrameworkRoot.withErrorPath [] . FrameworkRoot.handler @Root) $
    SDK.readHistory "ParserB" ContextBindingError [("ShowB", SDK.RequireValue)] boundParserB Nothing
  {-# MINIMAL getLevelB #-}

instance (Monad m, Effect FeedB m, ParserBEffect m) => Effect ParserB m where
  type Registration ParserB = Registered ParserBEffect FeedB
  type Typing ParserB = 'SDK.ContextKind
  type Require ParserB = SDK.Void
  type Produce ParserB = LevelB
  type Error ParserB = ParserBError
  raise (ParserBError description) = SDK.failEffect "ParserB" ParserBFailure description
  handler = FrameworkRoot.handler @Root

data ShowA

type ShowAInputs m = (FrameworkRoot.Capability ShowA m, Effect Root m, Provides LevelA m, MonadIO m)
instance FrameworkRoot.Capability ShowA App

class (Effect Root m, Provides LevelA m) => ShowAEffect m where
  showA :: m (Maybe String)
  {-# MINIMAL showA #-}

instance (Monad m, Effect Root m, ShowAEffect m) => Effect ShowA m where
  type Registration ShowA = Registered ShowAEffect Root
  type Typing ShowA = 'SDK.ExcuKind
  type Require ShowA = LevelA
  type Error ShowA = ShowAError
  raise (ShowAError description) = SDK.failEffect "ShowA" ShowAFailure description
  handler = FrameworkRoot.handler @Root

data ShowB

type ShowBInputs m = (FrameworkRoot.Capability ShowB m, Effect Root m, Provides LevelB m, MonadIO m)
instance FrameworkRoot.Capability ShowB App

class (Effect Root m, Provides LevelB m) => ShowBEffect m where
  showB :: m (Maybe String)
  {-# MINIMAL showB #-}

instance (Monad m, Effect Root m, ShowBEffect m) => Effect ShowB m where
  type Registration ShowB = Registered ShowBEffect Root
  type Typing ShowB = 'SDK.ExcuKind
  type Require ShowB = LevelB
  type Error ShowB = ShowBError
  raise (ShowBError description) = SDK.failEffect "ShowB" ShowBFailure description
  handler = FrameworkRoot.handler @Root

-- 依值入口：request 重新生产，require 读取已有绑定；来源由注册解析，不由消费方指名。
-- Reading 是 require 的结果：持续资产为 History，其余为契约本身；只由资产自己的声明决定。
class Provides contract m where
  type Reading contract
  request :: m contract
  require :: m (Reading contract)

instance (ReportLocationEffect App) => Provides ReportPath App where
  type Reading ReportPath = ReportPath
  request = SDK.provideContext "ReportLocation" "ReportPath" ContextBindingError []
  require = SDK.provideContext "ReportLocation" "ReportPath" ContextBindingError [("ReportFile", readReportPath), ("ReadReport", readReportPath), ("ReportInspect", readReportPath)]

instance (ReplyLocationEffect App) => Provides ReplyPath App where
  type Reading ReplyPath = ReplyPath
  request = SDK.provideContext "ReplyLocation" "ReplyPath" ContextBindingError []
  require = SDK.provideContext "ReplyLocation" "ReplyPath" ContextBindingError [("ReplyFile", readReplyPath), ("ReadReply", readReplyPath)]

instance (ReportFileEffect App) => Provides OpenedReport App where
  type Reading OpenedReport = OpenedReport
  request = SDK.provideContext "ReportFile" "OpenedReport" ContextBindingError [("ReportScope", getOpenedReport)]
  require = SDK.provideContext "ReportFile" "OpenedReport" ContextBindingError [("ReportScope", readOpenedReport), ("WriteReport", readOpenedReport)]

instance (ReplyFileEffect App) => Provides OpenedReply App where
  type Reading OpenedReply = OpenedReply
  request = SDK.provideContext "ReplyFile" "OpenedReply" ContextBindingError [("ReplyScope", getOpenedReply)]
  require = SDK.provideContext "ReplyFile" "OpenedReply" ContextBindingError [("ReplyScope", readOpenedReply), ("WriteReply", readOpenedReply)]

instance (ReportDraftEffect App) => Provides ReportBody App where
  type Reading ReportBody = ReportBody
  request = SDK.provideContext "ReportDraft" "ReportBody" ContextBindingError []
  require = SDK.provideContext "ReportDraft" "ReportBody" ContextBindingError [("WriteReport", readReportBody)]

instance (ReplyDraftEffect App) => Provides ReplyBody App where
  type Reading ReplyBody = ReplyBody
  request = SDK.provideContext "ReplyDraft" "ReplyBody" ContextBindingError []
  require = SDK.provideContext "ReplyDraft" "ReplyBody" ContextBindingError [("WriteReply", readReplyBody)]

instance (ReportCounterEffect App) => Provides ReportStats App where
  type Reading ReportStats = ReportStats
  request = SDK.provideContext "ReportCounter" "ReportStats" ContextBindingError []
  require = SDK.provideContext "ReportCounter" "ReportStats" ContextBindingError [("ShowReport", readReportStats)]

instance (ReplyCounterEffect App) => Provides ReplyStats App where
  type Reading ReplyStats = ReplyStats
  request = SDK.provideContext "ReplyCounter" "ReplyStats" ContextBindingError []
  require = SDK.provideContext "ReplyCounter" "ReplyStats" ContextBindingError [("ShowReply", readReplyStats)]

instance (ReportInspectEffect App) => Provides ReportStateBlank App where
  type Reading ReportStateBlank = ReportStateBlank
  request = SDK.provideContext "ReportInspect" "ReportStateBlank" ContextBindingError []
  require = SDK.projectContext "ReportInspect" "ReportStateBlank" ContextBindingError [("OnBlank", readReportState)]
    (\(ReportState value) -> case value of
      Blank -> Just (ReportStateBlank ())
      _ -> Nothing)

instance (ReportInspectEffect App) => Provides ReportStateFilled App where
  type Reading ReportStateFilled = ReportStateFilled
  request = SDK.provideContext "ReportInspect" "ReportStateFilled" ContextBindingError []
  require = SDK.projectContext "ReportInspect" "ReportStateFilled" ContextBindingError [("OnFilled", readReportState)]
    (\(ReportState value) -> case value of
      Filled field -> Just (ReportStateFilled field)
      _ -> Nothing)

instance (ParserAEffect App) => Provides LevelA App where
  type Reading LevelA = SDK.History LevelA
  request = SDK.provideContext "ParserA" "LevelA" ContextBindingError []
  require = SDK.provideContext "ParserA" "LevelA" ContextBindingError [("ShowA", readLevelA)]

instance (ParserBEffect App) => Provides LevelB App where
  type Reading LevelB = SDK.History LevelB
  request = SDK.provideContext "ParserB" "LevelB" ContextBindingError []
  require = SDK.provideContext "ParserB" "LevelB" ContextBindingError [("ShowB", readLevelB)]

-- SDK 生成的本地错误只接收消息；类型唯一确定 raise 来源。
newtype ReportLocationError = ReportLocationError String
  deriving (Eq, Show, Read)

-- SDK 生成的本地错误只接收消息；类型唯一确定 raise 来源。
newtype ReplyLocationError = ReplyLocationError String
  deriving (Eq, Show, Read)

-- SDK 生成的本地错误只接收消息；类型唯一确定 raise 来源。
newtype ReportDraftError = ReportDraftError String
  deriving (Eq, Show, Read)

-- SDK 生成的本地错误只接收消息；类型唯一确定 raise 来源。
newtype ReplyDraftError = ReplyDraftError String
  deriving (Eq, Show, Read)

-- SDK 生成的本地错误只接收消息；类型唯一确定 raise 来源。
newtype ReportFileError = ReportFileError String
  deriving (Eq, Show, Read)

-- SDK 生成的本地错误只接收消息；类型唯一确定 raise 来源。
newtype ReplyFileError = ReplyFileError String
  deriving (Eq, Show, Read)

-- SDK 生成的本地错误只接收消息；类型唯一确定 raise 来源。
newtype ReportScopeError = ReportScopeError String
  deriving (Eq, Show, Read)

-- SDK 生成的本地错误只接收消息；类型唯一确定 raise 来源。
newtype ReplyScopeError = ReplyScopeError String
  deriving (Eq, Show, Read)

-- SDK 生成的本地错误只接收消息；类型唯一确定 raise 来源。
newtype WriteReportError = WriteReportError String
  deriving (Eq, Show, Read)

-- SDK 生成的本地错误只接收消息；类型唯一确定 raise 来源。
newtype WriteReplyError = WriteReplyError String
  deriving (Eq, Show, Read)

-- SDK 生成的本地错误只接收消息；类型唯一确定 raise 来源。
newtype MarkReplyError = MarkReplyError String
  deriving (Eq, Show, Read)

-- SDK 生成的本地错误只接收消息；类型唯一确定 raise 来源。
newtype ReadReportError = ReadReportError String
  deriving (Eq, Show, Read)

-- SDK 生成的本地错误只接收消息；类型唯一确定 raise 来源。
newtype ReadReplyError = ReadReplyError String
  deriving (Eq, Show, Read)

-- SDK 生成的本地错误只接收消息；类型唯一确定 raise 来源。
newtype ReportCounterError = ReportCounterError String
  deriving (Eq, Show, Read)

-- SDK 生成的本地错误只接收消息；类型唯一确定 raise 来源。
newtype ReplyCounterError = ReplyCounterError String
  deriving (Eq, Show, Read)

-- SDK 生成的本地错误只接收消息；类型唯一确定 raise 来源。
newtype ShowReportError = ShowReportError String
  deriving (Eq, Show, Read)

-- SDK 生成的本地错误只接收消息；类型唯一确定 raise 来源。
newtype ShowReplyError = ShowReplyError String
  deriving (Eq, Show, Read)

-- SDK 生成的本地错误只接收消息；类型唯一确定 raise 来源。
newtype ReportInspectError = ReportInspectError String
  deriving (Eq, Show, Read)

-- SDK 生成的本地错误只接收消息；类型唯一确定 raise 来源。
newtype OnBlankError = OnBlankError String
  deriving (Eq, Show, Read)

-- SDK 生成的本地错误只接收消息；类型唯一确定 raise 来源。
newtype OnFilledError = OnFilledError String
  deriving (Eq, Show, Read)

-- SDK 生成的本地错误只接收消息；类型唯一确定 raise 来源。
newtype FeedAError = FeedAError String
  deriving (Eq, Show, Read)

-- SDK 生成的本地错误只接收消息；类型唯一确定 raise 来源。
newtype FeedBError = FeedBError String
  deriving (Eq, Show, Read)

-- SDK 生成的本地错误只接收消息；类型唯一确定 raise 来源。
newtype ParserAError = ParserAError String
  deriving (Eq, Show, Read)

-- SDK 生成的本地错误只接收消息；类型唯一确定 raise 来源。
newtype ParserBError = ParserBError String
  deriving (Eq, Show, Read)

-- SDK 生成的本地错误只接收消息；类型唯一确定 raise 来源。
newtype ShowAError = ShowAError String
  deriving (Eq, Show, Read)

-- SDK 生成的本地错误只接收消息；类型唯一确定 raise 来源。
newtype ShowBError = ShowBError String
  deriving (Eq, Show, Read)

-- 统一失败协议的分类标签；消息与来源由 SDK.Failure 保存。
data Errors = ReportLocationFailure | ReplyLocationFailure | ReportDraftFailure | ReplyDraftFailure | ReportFileFailure | ReplyFileFailure | ReportScopeFailure | ReplyScopeFailure | WriteReportFailure | WriteReplyFailure | MarkReplyFailure | ReadReportFailure | ReadReplyFailure | ReportCounterFailure | ReplyCounterFailure | ShowReportFailure | ShowReplyFailure | ReportInspectFailure | OnBlankFailure | OnFilledFailure | FeedAFailure | FeedBFailure | ParserAFailure | ParserBFailure | ShowAFailure | ShowBFailure | ContextBindingError SDK.ContextFault | ScopeBindingError SDK.ScopeFault
  deriving (Eq, Show)

-- SDK 内部存储：Nothing 仅表示本次运行尚未建立绑定，不是业务缺值。
data ContextValues = ContextValues
  { boundReportLocation :: Maybe (Produce ReportLocation)
  , boundReplyLocation :: Maybe (Produce ReplyLocation)
  , boundReportDraft :: Maybe (Produce ReportDraft)
  , boundReplyDraft :: Maybe (Produce ReplyDraft)
  , boundReportFile :: Maybe (Produce ReportFile)
  , boundReplyFile :: Maybe (Produce ReplyFile)
  , boundReportCounter :: Maybe (Produce ReportCounter)
  , boundReplyCounter :: Maybe (Produce ReplyCounter)
  , boundReportInspect :: Maybe (Produce ReportInspect)
  , boundParserA :: Maybe (Produce ParserA)
  , boundParserB :: Maybe (Produce ParserB)
  }

emptyContexts :: ContextValues
emptyContexts = ContextValues Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing

