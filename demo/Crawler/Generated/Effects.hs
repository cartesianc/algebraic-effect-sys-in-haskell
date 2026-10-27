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
module Crawler.Generated.Effects where

import Framework.Effect.Contract (Effect(..), Registered)
import qualified Framework.Effect.Contract as FrameworkRoot
import qualified Framework.SDK as SDK
import Control.Monad.IO.Class (MonadIO)
import Crawler.Types

-- SDK 提供运行载体与空存储；Context 经声明的 request/require 取得。
type Root = SDK.Root ContextValues Errors
type App = SDK.App ContextValues Errors

-- 每个 Context 的契约类型：名字来自 handler 名，包装其表示类型；只能由该生产方构造。
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

-- 方法定义身份；仅生成区使用，图中不以字符串匹配方法。
data MethodGen = StartURLGen | ReadStartURLGen | LinkedURLGen | ReadLinkedURLGen | FetchStartPageGen | StartPageSummaryGen | ReadStartPageSummaryGen | PrintPageGen | FetchLinkedPageGen | LinkedPageSummaryGen | ReadLinkedPageSummaryGen | PrintLinkedPageGen | CrawlSessionInfoGen | ReadCrawlSessionInfoGen | OpenCrawlSessionGen | CloseCrawlSessionGen
  deriving (Eq, Ord, Show, Read, SDK.Generic)
instance SDK.NFData MethodGen

data StartPage

type StartPageInputs m = (FrameworkRoot.Capability StartPage m, Effect Root m, MonadIO m)
instance FrameworkRoot.Capability StartPage App

class (Effect Root m) => StartPageEffect m where
  startURL :: m (Produce StartPage)
  readStartURL :: m (Produce StartPage)
  readStartURL = (FrameworkRoot.withErrorPath [] . FrameworkRoot.handler @Root) $
    SDK.readContext "StartPage" ContextBindingError [("FetchPage", SDK.RequestValue), ("ExtractPage", SDK.RequireValue)] Nothing boundStartPage startURL
  {-# MINIMAL startURL #-}

instance (Monad m, Effect Root m, StartPageEffect m) => Effect StartPage m where
  type Registration StartPage = Registered StartPageEffect Root
  type Typing StartPage = 'SDK.ContextKind
  type Require StartPage = SDK.Void
  type Produce StartPage = StartURL
  type Error StartPage = StartPageError
  raise (StartPageError description) = SDK.failEffect "StartPage" StartPageFailure description
  handler = FrameworkRoot.handler @Root

data LinkedPage

type LinkedPageInputs m = (FrameworkRoot.Capability LinkedPage m, Effect Root m, MonadIO m)
instance FrameworkRoot.Capability LinkedPage App

class (Effect Root m) => LinkedPageEffect m where
  linkedURL :: m (Produce LinkedPage)
  readLinkedURL :: m (Produce LinkedPage)
  readLinkedURL = (FrameworkRoot.withErrorPath [] . FrameworkRoot.handler @Root) $
    SDK.readContext "LinkedPage" ContextBindingError [("FetchLinkedPage", SDK.RequestValue), ("ExtractLinkedPage", SDK.RequireValue)] Nothing boundLinkedPage linkedURL
  {-# MINIMAL linkedURL #-}

instance (Monad m, Effect Root m, LinkedPageEffect m) => Effect LinkedPage m where
  type Registration LinkedPage = Registered LinkedPageEffect Root
  type Typing LinkedPage = 'SDK.ContextKind
  type Require LinkedPage = SDK.Void
  type Produce LinkedPage = LinkedURL
  type Error LinkedPage = LinkedPageError
  raise (LinkedPageError description) = SDK.failEffect "LinkedPage" LinkedPageFailure description
  handler = FrameworkRoot.handler @Root

data FetchPage

type FetchPageInputs m = (FrameworkRoot.Capability FetchPage m, Effect CrawlSession m, Provides StartURL m, Provides CrawlSessionInfo m, CrawlSessionEffect m, MonadIO m)
instance FrameworkRoot.Capability FetchPage App

class (Effect CrawlSession m, Provides StartURL m, Provides CrawlSessionInfo m) => FetchPageEffect m where
  fetchStartPage :: m (Maybe String)
  {-# MINIMAL fetchStartPage #-}

instance (Monad m, Effect CrawlSession m, FetchPageEffect m) => Effect FetchPage m where
  type Registration FetchPage = Registered FetchPageEffect CrawlSession
  type Typing FetchPage = 'SDK.ExcuKind
  type Require FetchPage = (StartURL, CrawlSessionInfo)
  type Error FetchPage = FetchPageError
  raise (FetchPageError description) = SDK.failEffect "FetchPage" FetchPageFailure description
  handler = FrameworkRoot.handler @Root

data ExtractPage

type ExtractPageInputs m = (FrameworkRoot.Capability ExtractPage m, Effect FetchPage m, Provides StartURL m, FetchPageEffect m, CrawlSessionEffect m, MonadIO m)
instance FrameworkRoot.Capability ExtractPage App

class (Effect FetchPage m, Provides StartURL m) => ExtractPageEffect m where
  startPageSummary :: m (Produce ExtractPage)
  readStartPageSummary :: m (Produce ExtractPage)
  readStartPageSummary = (FrameworkRoot.withErrorPath ["CrawlSession"] . FrameworkRoot.handler @Root) $
    SDK.readContext "ExtractPage" ContextBindingError [("PrintPage", SDK.RequireValue)] Nothing boundExtractPage startPageSummary
  {-# MINIMAL startPageSummary #-}

instance (Monad m, Effect FetchPage m, ExtractPageEffect m) => Effect ExtractPage m where
  type Registration ExtractPage = Registered ExtractPageEffect FetchPage
  type Typing ExtractPage = 'SDK.ContextKind
  type Require ExtractPage = StartURL
  type Produce ExtractPage = StartPageSummary
  type Error ExtractPage = ExtractPageError
  raise (ExtractPageError description) = SDK.failEffect "ExtractPage" ExtractPageFailure description
  handler = FrameworkRoot.handler @Root

data PrintPage

type PrintPageInputs m = (FrameworkRoot.Capability PrintPage m, Effect Root m, Provides StartPageSummary m, MonadIO m)
instance FrameworkRoot.Capability PrintPage App

class (Effect Root m, Provides StartPageSummary m) => PrintPageEffect m where
  printPage :: m (Maybe String)
  {-# MINIMAL printPage #-}

instance (Monad m, Effect Root m, PrintPageEffect m) => Effect PrintPage m where
  type Registration PrintPage = Registered PrintPageEffect Root
  type Typing PrintPage = 'SDK.ExcuKind
  type Require PrintPage = StartPageSummary
  type Error PrintPage = PrintPageError
  raise (PrintPageError description) = SDK.failEffect "PrintPage" PrintPageFailure description
  handler = FrameworkRoot.handler @Root

data FetchLinkedPage

type FetchLinkedPageInputs m = (FrameworkRoot.Capability FetchLinkedPage m, Effect CrawlSession m, Provides LinkedURL m, Provides CrawlSessionInfo m, CrawlSessionEffect m, MonadIO m)
instance FrameworkRoot.Capability FetchLinkedPage App

class (Effect CrawlSession m, Provides LinkedURL m, Provides CrawlSessionInfo m) => FetchLinkedPageEffect m where
  fetchLinkedPage :: m (Maybe String)
  {-# MINIMAL fetchLinkedPage #-}

instance (Monad m, Effect CrawlSession m, FetchLinkedPageEffect m) => Effect FetchLinkedPage m where
  type Registration FetchLinkedPage = Registered FetchLinkedPageEffect CrawlSession
  type Typing FetchLinkedPage = 'SDK.ExcuKind
  type Require FetchLinkedPage = (LinkedURL, CrawlSessionInfo)
  type Error FetchLinkedPage = FetchLinkedPageError
  raise (FetchLinkedPageError description) = SDK.failEffect "FetchLinkedPage" FetchLinkedPageFailure description
  handler = FrameworkRoot.handler @Root

data ExtractLinkedPage

type ExtractLinkedPageInputs m = (FrameworkRoot.Capability ExtractLinkedPage m, Effect FetchLinkedPage m, Provides LinkedURL m, FetchLinkedPageEffect m, CrawlSessionEffect m, MonadIO m)
instance FrameworkRoot.Capability ExtractLinkedPage App

class (Effect FetchLinkedPage m, Provides LinkedURL m) => ExtractLinkedPageEffect m where
  linkedPageSummary :: m (Produce ExtractLinkedPage)
  readLinkedPageSummary :: m (Produce ExtractLinkedPage)
  readLinkedPageSummary = (FrameworkRoot.withErrorPath ["CrawlSession"] . FrameworkRoot.handler @Root) $
    SDK.readContext "ExtractLinkedPage" ContextBindingError [("PrintLinkedPage", SDK.RequireValue)] Nothing boundExtractLinkedPage linkedPageSummary
  {-# MINIMAL linkedPageSummary #-}

instance (Monad m, Effect FetchLinkedPage m, ExtractLinkedPageEffect m) => Effect ExtractLinkedPage m where
  type Registration ExtractLinkedPage = Registered ExtractLinkedPageEffect FetchLinkedPage
  type Typing ExtractLinkedPage = 'SDK.ContextKind
  type Require ExtractLinkedPage = LinkedURL
  type Produce ExtractLinkedPage = LinkedPageSummary
  type Error ExtractLinkedPage = ExtractLinkedPageError
  raise (ExtractLinkedPageError description) = SDK.failEffect "ExtractLinkedPage" ExtractLinkedPageFailure description
  handler = FrameworkRoot.handler @Root

data PrintLinkedPage

type PrintLinkedPageInputs m = (FrameworkRoot.Capability PrintLinkedPage m, Effect Root m, Provides LinkedPageSummary m, MonadIO m)
instance FrameworkRoot.Capability PrintLinkedPage App

class (Effect Root m, Provides LinkedPageSummary m) => PrintLinkedPageEffect m where
  printLinkedPage :: m (Maybe String)
  {-# MINIMAL printLinkedPage #-}

instance (Monad m, Effect Root m, PrintLinkedPageEffect m) => Effect PrintLinkedPage m where
  type Registration PrintLinkedPage = Registered PrintLinkedPageEffect Root
  type Typing PrintLinkedPage = 'SDK.ExcuKind
  type Require PrintLinkedPage = LinkedPageSummary
  type Error PrintLinkedPage = PrintLinkedPageError
  raise (PrintLinkedPageError description) = SDK.failEffect "PrintLinkedPage" PrintLinkedPageFailure description
  handler = FrameworkRoot.handler @Root

data SessionContext

type SessionContextInputs m = (FrameworkRoot.Capability SessionContext m, Effect Root m, MonadIO m)
instance FrameworkRoot.Capability SessionContext App

class (Effect Root m) => SessionContextEffect m where
  crawlSessionInfo :: m (Produce SessionContext)
  readCrawlSessionInfo :: m (Produce SessionContext)
  readCrawlSessionInfo = (FrameworkRoot.withErrorPath [] . FrameworkRoot.handler @Root) $
    SDK.readContext "SessionContext" ContextBindingError [("FetchPage", SDK.RequireValue), ("FetchLinkedPage", SDK.RequireValue), ("CrawlSession", SDK.RequestValue)] Nothing boundSessionContext crawlSessionInfo
  {-# MINIMAL crawlSessionInfo #-}

instance (Monad m, Effect Root m, SessionContextEffect m) => Effect SessionContext m where
  type Registration SessionContext = Registered SessionContextEffect Root
  type Typing SessionContext = 'SDK.ContextKind
  type Require SessionContext = SDK.Void
  type Produce SessionContext = CrawlSessionInfo
  type Error SessionContext = SessionContextError
  raise (SessionContextError description) = SDK.failEffect "SessionContext" SessionContextFailure description
  handler = FrameworkRoot.handler @Root

data CrawlSession

type CrawlSessionInputs m = (FrameworkRoot.Capability CrawlSession m, Effect Root m, Provides CrawlSessionInfo m, MonadIO m)
instance FrameworkRoot.Capability CrawlSession App

class (Effect Root m, Provides CrawlSessionInfo m) => CrawlSessionEffect m where
  openCrawlSession :: m (Maybe String)
  closeCrawlSession :: m (Maybe String)
  {-# MINIMAL openCrawlSession, closeCrawlSession #-}

instance (Monad m, Effect Root m, CrawlSessionEffect m) => Effect CrawlSession m where
  type Registration CrawlSession = Registered CrawlSessionEffect Root
  type Typing CrawlSession = 'SDK.ScopedKind
  type Require CrawlSession = CrawlSessionInfo
  type Error CrawlSession = CrawlSessionError
  raise (CrawlSessionError description) = SDK.failEffect "CrawlSession" CrawlSessionFailure description
  handler = FrameworkRoot.handler @Root

-- 依值入口：request 重新生产，require 读取已有绑定；来源由注册解析，不由消费方指名。
class Provides contract m where
  request :: m contract
  require :: m contract

instance (StartPageEffect App) => Provides StartURL App where
  request = SDK.provideContext "StartURL" ContextBindingError [("FetchPage", startURL)]
  require = SDK.provideContext "StartURL" ContextBindingError [("ExtractPage", readStartURL)]

instance (SessionContextEffect App) => Provides CrawlSessionInfo App where
  request = SDK.provideContext "CrawlSessionInfo" ContextBindingError [("CrawlSession", crawlSessionInfo)]
  require = SDK.provideContext "CrawlSessionInfo" ContextBindingError [("FetchPage", readCrawlSessionInfo), ("FetchLinkedPage", readCrawlSessionInfo), ("CrawlSession", readCrawlSessionInfo)]

instance (ExtractPageEffect App) => Provides StartPageSummary App where
  request = SDK.provideContext "StartPageSummary" ContextBindingError []
  require = SDK.provideContext "StartPageSummary" ContextBindingError [("PrintPage", readStartPageSummary)]

instance (LinkedPageEffect App) => Provides LinkedURL App where
  request = SDK.provideContext "LinkedURL" ContextBindingError [("FetchLinkedPage", linkedURL)]
  require = SDK.provideContext "LinkedURL" ContextBindingError [("ExtractLinkedPage", readLinkedURL)]

instance (ExtractLinkedPageEffect App) => Provides LinkedPageSummary App where
  request = SDK.provideContext "LinkedPageSummary" ContextBindingError []
  require = SDK.provideContext "LinkedPageSummary" ContextBindingError [("PrintLinkedPage", readLinkedPageSummary)]

-- SDK 生成的本地错误只接收消息；类型唯一确定 raise 来源。
newtype StartPageError = StartPageError String
  deriving (Eq, Show, Read)

-- SDK 生成的本地错误只接收消息；类型唯一确定 raise 来源。
newtype LinkedPageError = LinkedPageError String
  deriving (Eq, Show, Read)

-- SDK 生成的本地错误只接收消息；类型唯一确定 raise 来源。
newtype FetchPageError = FetchPageError String
  deriving (Eq, Show, Read)

-- SDK 生成的本地错误只接收消息；类型唯一确定 raise 来源。
newtype ExtractPageError = ExtractPageError String
  deriving (Eq, Show, Read)

-- SDK 生成的本地错误只接收消息；类型唯一确定 raise 来源。
newtype PrintPageError = PrintPageError String
  deriving (Eq, Show, Read)

-- SDK 生成的本地错误只接收消息；类型唯一确定 raise 来源。
newtype FetchLinkedPageError = FetchLinkedPageError String
  deriving (Eq, Show, Read)

-- SDK 生成的本地错误只接收消息；类型唯一确定 raise 来源。
newtype ExtractLinkedPageError = ExtractLinkedPageError String
  deriving (Eq, Show, Read)

-- SDK 生成的本地错误只接收消息；类型唯一确定 raise 来源。
newtype PrintLinkedPageError = PrintLinkedPageError String
  deriving (Eq, Show, Read)

-- SDK 生成的本地错误只接收消息；类型唯一确定 raise 来源。
newtype SessionContextError = SessionContextError String
  deriving (Eq, Show, Read)

-- SDK 生成的本地错误只接收消息；类型唯一确定 raise 来源。
newtype CrawlSessionError = CrawlSessionError String
  deriving (Eq, Show, Read)

-- 统一失败协议的分类标签；消息与来源由 SDK.Failure 保存。
data Errors = StartPageFailure | LinkedPageFailure | FetchPageFailure | ExtractPageFailure | PrintPageFailure | FetchLinkedPageFailure | ExtractLinkedPageFailure | PrintLinkedPageFailure | SessionContextFailure | CrawlSessionFailure | ContextBindingError SDK.ContextFault | ScopeBindingError SDK.ScopeFault
  deriving (Eq, Show)

-- SDK 内部存储：Nothing 仅表示本次运行尚未建立绑定，不是业务缺值。
data ContextValues = ContextValues
  { boundStartPage :: Maybe (Produce StartPage)
  , boundLinkedPage :: Maybe (Produce LinkedPage)
  , boundExtractPage :: Maybe (Produce ExtractPage)
  , boundExtractLinkedPage :: Maybe (Produce ExtractLinkedPage)
  , boundSessionContext :: Maybe (Produce SessionContext)
  }

emptyContexts :: ContextValues
emptyContexts = ContextValues Nothing Nothing Nothing Nothing Nothing

