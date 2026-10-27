{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE EmptyDataDecls #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
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
import Crawler.Types

-- SDK 提供运行载体与空存储；Context 经声明的 request/require 取得。
type Root = SDK.Root ContextValues Errors
type App = SDK.App ContextValues Errors

-- 方法定义身份；仅生成区使用，图中不以字符串匹配方法。
data MethodGen = LoadStartURLGen | ReadStartURLGen | LoadLinkedURLGen | ReadLinkedURLGen | FetchPageGen | ReadFetchedPageGen | ExtractPageGen | ReadPageSummaryGen | PrintPageGen | FetchLinkedPageGen | ReadFetchedLinkedPageGen | ExtractLinkedPageGen | ReadLinkedPageSummaryGen | PrintLinkedPageGen | CreateCrawlSessionGen | ReadCrawlSessionGen | OpenCrawlSessionGen | CloseCrawlSessionGen
  deriving (Eq, Ord, Show, Read, SDK.Generic)
instance SDK.NFData MethodGen

data StartPage

class (Effect CrawlSession m) => StartPageEffect m where
  loadStartURL :: m (Produce StartPage)
  readStartURL :: m (Produce StartPage)
  readStartURL = (FrameworkRoot.withErrorPath ["CrawlSession"] . FrameworkRoot.handler @Root) $
    SDK.readContext "StartPage" ContextBindingError [("FetchPage", SDK.RequestValue)] Nothing boundStartPage
  {-# MINIMAL loadStartURL #-}

instance (Monad m, Effect CrawlSession m, StartPageEffect m) => Effect StartPage m where
  type Registration StartPage = Registered StartPageEffect CrawlSession
  type Typing StartPage = 'SDK.ContextKind
  type Require StartPage = SDK.Void
  type Produce StartPage = StartURL
  type Error StartPage = StartPageError
  raise (StartPageError description) = SDK.failEffect "StartPage" StartPageFailure description
  handler = FrameworkRoot.handler @Root

data LinkedPage

class (Effect CrawlSession m) => LinkedPageEffect m where
  loadLinkedURL :: m (Produce LinkedPage)
  readLinkedURL :: m (Produce LinkedPage)
  readLinkedURL = (FrameworkRoot.withErrorPath ["CrawlSession"] . FrameworkRoot.handler @Root) $
    SDK.readContext "LinkedPage" ContextBindingError [("FetchLinkedPage", SDK.RequestValue)] Nothing boundLinkedPage
  {-# MINIMAL loadLinkedURL #-}

instance (Monad m, Effect CrawlSession m, LinkedPageEffect m) => Effect LinkedPage m where
  type Registration LinkedPage = Registered LinkedPageEffect CrawlSession
  type Typing LinkedPage = 'SDK.ContextKind
  type Require LinkedPage = SDK.Void
  type Produce LinkedPage = LinkedURL
  type Error LinkedPage = LinkedPageError
  raise (LinkedPageError description) = SDK.failEffect "LinkedPage" LinkedPageFailure description
  handler = FrameworkRoot.handler @Root

data FetchPage

class (Effect CrawlSession m, Provides StartURL m, Provides CrawlSessionInfo m) => FetchPageEffect m where
  fetchPage :: m (Produce FetchPage)
  readFetchedPage :: m (Produce FetchPage)
  readFetchedPage = (FrameworkRoot.withErrorPath ["CrawlSession"] . FrameworkRoot.handler @Root) $
    SDK.readContext "FetchPage" ContextBindingError [("ExtractPage", SDK.RequestValue)] Nothing boundFetchPage
  {-# MINIMAL fetchPage #-}

instance (Monad m, Effect CrawlSession m, FetchPageEffect m) => Effect FetchPage m where
  type Registration FetchPage = Registered FetchPageEffect CrawlSession
  type Typing FetchPage = 'SDK.ContextKind
  type Require FetchPage = (StartURL, CrawlSessionInfo)
  type Produce FetchPage = StartFetchedPage
  type Error FetchPage = FetchPageError
  raise (FetchPageError description) = SDK.failEffect "FetchPage" FetchPageFailure description
  handler = FrameworkRoot.handler @Root

data ExtractPage

class (Effect CrawlSession m, Provides StartFetchedPage m) => ExtractPageEffect m where
  extractPage :: m (Produce ExtractPage)
  readPageSummary :: m (Produce ExtractPage)
  readPageSummary = (FrameworkRoot.withErrorPath ["CrawlSession"] . FrameworkRoot.handler @Root) $
    SDK.readContext "ExtractPage" ContextBindingError [("PrintPage", SDK.RequestValue)] Nothing boundExtractPage
  {-# MINIMAL extractPage #-}

instance (Monad m, Effect CrawlSession m, ExtractPageEffect m) => Effect ExtractPage m where
  type Registration ExtractPage = Registered ExtractPageEffect CrawlSession
  type Typing ExtractPage = 'SDK.ContextKind
  type Require ExtractPage = StartFetchedPage
  type Produce ExtractPage = StartPageSummary
  type Error ExtractPage = ExtractPageError
  raise (ExtractPageError description) = SDK.failEffect "ExtractPage" ExtractPageFailure description
  handler = FrameworkRoot.handler @Root

data PrintPage

class (Effect CrawlSession m, Provides StartPageSummary m) => PrintPageEffect m where
  printPage :: m ()
  {-# MINIMAL printPage #-}

instance (Monad m, Effect CrawlSession m, PrintPageEffect m) => Effect PrintPage m where
  type Registration PrintPage = Registered PrintPageEffect CrawlSession
  type Typing PrintPage = 'SDK.ExcuKind
  type Require PrintPage = StartPageSummary
  type Error PrintPage = PrintPageError
  raise (PrintPageError description) = SDK.failEffect "PrintPage" PrintPageFailure description
  handler = FrameworkRoot.handler @Root

data FetchLinkedPage

class (Effect CrawlSession m, Provides LinkedURL m, Provides CrawlSessionInfo m) => FetchLinkedPageEffect m where
  fetchLinkedPage :: m (Produce FetchLinkedPage)
  readFetchedLinkedPage :: m (Produce FetchLinkedPage)
  readFetchedLinkedPage = (FrameworkRoot.withErrorPath ["CrawlSession"] . FrameworkRoot.handler @Root) $
    SDK.readContext "FetchLinkedPage" ContextBindingError [("ExtractLinkedPage", SDK.RequestValue)] Nothing boundFetchLinkedPage
  {-# MINIMAL fetchLinkedPage #-}

instance (Monad m, Effect CrawlSession m, FetchLinkedPageEffect m) => Effect FetchLinkedPage m where
  type Registration FetchLinkedPage = Registered FetchLinkedPageEffect CrawlSession
  type Typing FetchLinkedPage = 'SDK.ContextKind
  type Require FetchLinkedPage = (LinkedURL, CrawlSessionInfo)
  type Produce FetchLinkedPage = LinkedFetchedPage
  type Error FetchLinkedPage = FetchLinkedPageError
  raise (FetchLinkedPageError description) = SDK.failEffect "FetchLinkedPage" FetchLinkedPageFailure description
  handler = FrameworkRoot.handler @Root

data ExtractLinkedPage

class (Effect CrawlSession m, Provides LinkedFetchedPage m) => ExtractLinkedPageEffect m where
  extractLinkedPage :: m (Produce ExtractLinkedPage)
  readLinkedPageSummary :: m (Produce ExtractLinkedPage)
  readLinkedPageSummary = (FrameworkRoot.withErrorPath ["CrawlSession"] . FrameworkRoot.handler @Root) $
    SDK.readContext "ExtractLinkedPage" ContextBindingError [("PrintLinkedPage", SDK.RequestValue)] Nothing boundExtractLinkedPage
  {-# MINIMAL extractLinkedPage #-}

instance (Monad m, Effect CrawlSession m, ExtractLinkedPageEffect m) => Effect ExtractLinkedPage m where
  type Registration ExtractLinkedPage = Registered ExtractLinkedPageEffect CrawlSession
  type Typing ExtractLinkedPage = 'SDK.ContextKind
  type Require ExtractLinkedPage = LinkedFetchedPage
  type Produce ExtractLinkedPage = LinkedPageSummary
  type Error ExtractLinkedPage = ExtractLinkedPageError
  raise (ExtractLinkedPageError description) = SDK.failEffect "ExtractLinkedPage" ExtractLinkedPageFailure description
  handler = FrameworkRoot.handler @Root

data PrintLinkedPage

class (Effect CrawlSession m, Provides LinkedPageSummary m) => PrintLinkedPageEffect m where
  printLinkedPage :: m ()
  {-# MINIMAL printLinkedPage #-}

instance (Monad m, Effect CrawlSession m, PrintLinkedPageEffect m) => Effect PrintLinkedPage m where
  type Registration PrintLinkedPage = Registered PrintLinkedPageEffect CrawlSession
  type Typing PrintLinkedPage = 'SDK.ExcuKind
  type Require PrintLinkedPage = LinkedPageSummary
  type Error PrintLinkedPage = PrintLinkedPageError
  raise (PrintLinkedPageError description) = SDK.failEffect "PrintLinkedPage" PrintLinkedPageFailure description
  handler = FrameworkRoot.handler @Root

data SessionContext

class (Effect Root m) => SessionContextEffect m where
  createCrawlSession :: m (Produce SessionContext)
  readCrawlSession :: m (Produce SessionContext)
  readCrawlSession = (FrameworkRoot.withErrorPath [] . FrameworkRoot.handler @Root) $
    SDK.readContext "SessionContext" ContextBindingError [("FetchPage", SDK.RequireValue), ("FetchLinkedPage", SDK.RequireValue), ("CrawlSession", SDK.RequestValue)] Nothing boundSessionContext
  {-# MINIMAL createCrawlSession #-}

instance (Monad m, Effect Root m, SessionContextEffect m) => Effect SessionContext m where
  type Registration SessionContext = Registered SessionContextEffect Root
  type Typing SessionContext = 'SDK.ContextKind
  type Require SessionContext = SDK.Void
  type Produce SessionContext = CrawlSessionInfo
  type Error SessionContext = SessionContextError
  raise (SessionContextError description) = SDK.failEffect "SessionContext" SessionContextFailure description
  handler = FrameworkRoot.handler @Root

data CrawlSession

class (Effect Root m, Provides CrawlSessionInfo m) => CrawlSessionEffect m where
  openCrawlSession :: m ()
  closeCrawlSession :: m ()
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
  request = SDK.provideContext "StartURL" ContextBindingError [("FetchPage", loadStartURL)]
  require = SDK.provideContext "StartURL" ContextBindingError []

instance (SessionContextEffect App) => Provides CrawlSessionInfo App where
  request = SDK.provideContext "CrawlSessionInfo" ContextBindingError [("CrawlSession", createCrawlSession)]
  require = SDK.provideContext "CrawlSessionInfo" ContextBindingError [("FetchPage", readCrawlSession), ("FetchLinkedPage", readCrawlSession), ("CrawlSession", readCrawlSession)]

instance (FetchPageEffect App) => Provides StartFetchedPage App where
  request = SDK.provideContext "StartFetchedPage" ContextBindingError [("ExtractPage", fetchPage)]
  require = SDK.provideContext "StartFetchedPage" ContextBindingError []

instance (ExtractPageEffect App) => Provides StartPageSummary App where
  request = SDK.provideContext "StartPageSummary" ContextBindingError [("PrintPage", extractPage)]
  require = SDK.provideContext "StartPageSummary" ContextBindingError []

instance (LinkedPageEffect App) => Provides LinkedURL App where
  request = SDK.provideContext "LinkedURL" ContextBindingError [("FetchLinkedPage", loadLinkedURL)]
  require = SDK.provideContext "LinkedURL" ContextBindingError []

instance (FetchLinkedPageEffect App) => Provides LinkedFetchedPage App where
  request = SDK.provideContext "LinkedFetchedPage" ContextBindingError [("ExtractLinkedPage", fetchLinkedPage)]
  require = SDK.provideContext "LinkedFetchedPage" ContextBindingError []

instance (ExtractLinkedPageEffect App) => Provides LinkedPageSummary App where
  request = SDK.provideContext "LinkedPageSummary" ContextBindingError [("PrintLinkedPage", extractLinkedPage)]
  require = SDK.provideContext "LinkedPageSummary" ContextBindingError []

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
  , boundFetchPage :: Maybe (Produce FetchPage)
  , boundExtractPage :: Maybe (Produce ExtractPage)
  , boundFetchLinkedPage :: Maybe (Produce FetchLinkedPage)
  , boundExtractLinkedPage :: Maybe (Produce ExtractLinkedPage)
  , boundSessionContext :: Maybe (Produce SessionContext)
  }

emptyContexts :: ContextValues
emptyContexts = ContextValues Nothing Nothing Nothing Nothing Nothing Nothing Nothing

