{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MonoLocalBinds #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE UndecidableInstances #-}

-- 自动生成；通过 SDK 的 effect-codegen 更新，手写注册与 handler 位于上级目录。
module Crawler.Generated.Effects where

import qualified Framework.Generated as SDK
import Control.Monad.IO.Class (MonadIO)
import Crawler.Types

-- SDK 提供运行载体；资产存储与错误分类由本文件给出。
type App = SDK.App ContextValues Errors

-- 每个 Context 的资产类型：名字来自 Asset 声明，包装其表示类型。
newtype StartURL = StartURL (PageURL)
deriving instance Eq (PageURL) => Eq StartURL
deriving instance Show (PageURL) => Show StartURL

newtype LinkedURL = LinkedURL (PageURL)
deriving instance Eq (PageURL) => Eq LinkedURL
deriving instance Show (PageURL) => Show LinkedURL

newtype StartPageSummary = StartPageSummary (PageSummary)
deriving instance Eq (PageSummary) => Eq StartPageSummary
deriving instance Show (PageSummary) => Show StartPageSummary

newtype LinkedPageSummary = LinkedPageSummary (PageSummary)
deriving instance Eq (PageSummary) => Eq LinkedPageSummary
deriving instance Show (PageSummary) => Show LinkedPageSummary

newtype CrawlSessionInfo = CrawlSessionInfo (SessionInfo)
deriving instance Eq (SessionInfo) => Eq CrawlSessionInfo
deriving instance Show (SessionInfo) => Show CrawlSessionInfo

-- effect 方法的定义身份；仅生成区使用，图中不以字符串匹配方法。
data MethodGen = GetStartURLGen | ReadStartURLGen | GetLinkedURLGen | ReadLinkedURLGen | RunFetchPageGen | GetStartPageSummaryGen | ReadStartPageSummaryGen | RunPrintPageGen | RunFetchLinkedPageGen | GetLinkedPageSummaryGen | ReadLinkedPageSummaryGen | RunPrintLinkedPageGen | GetCrawlSessionInfoGen | ReadCrawlSessionInfoGen | OpenCrawlSessionGen | CloseCrawlSessionGen
  deriving (Eq, Ord, Show, Read, SDK.Generic)
instance SDK.NFData MethodGen

-- handler startURL：绑定到 StartPage。
type StartURLLayer m = (SDK.Raises StartURLError m, MonadIO m)
class StartURLHandler m where
  startURL :: m PageURL

-- 失败属于 handler：发生位置由 SDK 记录，Error 按 RaisedBy "startURL" 匹配。
newtype StartURLError = StartURLError String
  deriving (Eq, Show, Read)

-- handler linkedURL：绑定到 LinkedPage。
type LinkedURLLayer m = (SDK.Raises LinkedURLError m, MonadIO m)
class LinkedURLHandler m where
  linkedURL :: m PageURL

-- 失败属于 handler：发生位置由 SDK 记录，Error 按 RaisedBy "linkedURL" 匹配。
newtype LinkedURLError = LinkedURLError String
  deriving (Eq, Show, Read)

-- handler fetchPage：绑定到 FetchPage、FetchLinkedPage。
type FetchPageLayer m = (SDK.Reads (PageURL) m, SDK.Reads (SessionInfo) m, SDK.Raises FetchPageError m, MonadIO m)
class FetchPageHandler m where
  fetchPage :: m (Maybe String)

-- 失败属于 handler：发生位置由 SDK 记录，Error 按 RaisedBy "fetchPage" 匹配。
newtype FetchPageError = FetchPageError String
  deriving (Eq, Show, Read)

-- handler extractSummary：绑定到 ExtractPage、ExtractLinkedPage。
type ExtractSummaryLayer m = (SDK.Reads (PageURL) m, SDK.Raw m, SDK.Raises ExtractSummaryError m, MonadIO m)
class ExtractSummaryHandler m where
  extractSummary :: m PageSummary

-- 失败属于 handler：发生位置由 SDK 记录，Error 按 RaisedBy "extractSummary" 匹配。
newtype ExtractSummaryError = ExtractSummaryError String
  deriving (Eq, Show, Read)

-- handler printSummary：绑定到 PrintPage、PrintLinkedPage。
type PrintSummaryLayer m = (SDK.Reads (PageSummary) m, SDK.Raises PrintSummaryError m, MonadIO m)
class PrintSummaryHandler m where
  printSummary :: m (Maybe String)

-- 失败属于 handler：发生位置由 SDK 记录，Error 按 RaisedBy "printSummary" 匹配。
newtype PrintSummaryError = PrintSummaryError String
  deriving (Eq, Show, Read)

-- handler sessionInfo：绑定到 SessionContext。
type SessionInfoLayer m = (SDK.Raises SessionInfoError m, MonadIO m)
class SessionInfoHandler m where
  sessionInfo :: m SessionInfo

-- 失败属于 handler：发生位置由 SDK 记录，Error 按 RaisedBy "sessionInfo" 匹配。
newtype SessionInfoError = SessionInfoError String
  deriving (Eq, Show, Read)

-- handler openSession：绑定到 CrawlSession。
type OpenSessionLayer m = (SDK.Reads (SessionInfo) m, SDK.Raises OpenSessionError m, MonadIO m)
class OpenSessionHandler m where
  openSession :: m (Maybe String)

-- 失败属于 handler：发生位置由 SDK 记录，Error 按 RaisedBy "openSession" 匹配。
newtype OpenSessionError = OpenSessionError String
  deriving (Eq, Show, Read)

-- handler closeSession：绑定到 CrawlSession。
type CloseSessionLayer m = (SDK.Reads (SessionInfo) m, SDK.Raises CloseSessionError m, MonadIO m)
class CloseSessionHandler m where
  closeSession :: m (Maybe String)

-- 失败属于 handler：发生位置由 SDK 记录，Error 按 RaisedBy "closeSession" 匹配。
newtype CloseSessionError = CloseSessionError String
  deriving (Eq, Show, Read)

-- 统一失败协议的分类标签：每个 handler 一个；消息与发生位置由 SDK.Failure 保存。
data Errors = StartURLFailure | LinkedURLFailure | FetchPageFailure | ExtractSummaryFailure | PrintSummaryFailure | SessionInfoFailure | OpenSessionFailure | CloseSessionFailure | ContextBindingError SDK.ContextFault | ScopeBindingError SDK.ScopeFault
  deriving (Eq, Show)

-- SDK 内部存储：Nothing 仅表示本次运行尚未建立绑定，不是业务缺值。
data ContextValues = ContextValues
  { boundStartPage :: Maybe StartURL
  , boundLinkedPage :: Maybe LinkedURL
  , boundExtractPage :: Maybe StartPageSummary
  , boundExtractLinkedPage :: Maybe LinkedPageSummary
  , boundSessionContext :: Maybe CrawlSessionInfo
  }

emptyContexts :: ContextValues
emptyContexts = ContextValues Nothing Nothing Nothing Nothing Nothing

