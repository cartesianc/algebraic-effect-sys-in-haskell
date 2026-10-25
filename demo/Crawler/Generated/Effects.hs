{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE EmptyDataDecls #-}
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

data CrawlerContext

class (Effect CrawlSession m) => CrawlerContextEffect m where
  loadCrawlURLs :: m (Produce CrawlerContext)
  readCrawlURLs :: m (Produce CrawlerContext)
  readCrawlURLs = FrameworkRoot.handler @Root $
    SDK.readContext "CrawlerContext" ContextBindingError Nothing boundCrawlerContext
  {-# MINIMAL loadCrawlURLs #-}

instance (Monad m, Effect CrawlSession m, CrawlerContextEffect m) => Effect CrawlerContext m where
  type Registration CrawlerContext = Registered CrawlerContextEffect CrawlSession
  type Typing CrawlerContext = 'SDK.ContextKind
  type Require CrawlerContext = SDK.Void
  type Produce CrawlerContext = CrawlURLs
  type Error CrawlerContext = CrawlerContextError
  raise (CrawlerContextError description) = SDK.failEffect "CrawlerContext" CrawlerContextFailure description
  handler = FrameworkRoot.handler @Root

data FetchPage

class (Effect CrawlSession m, Effect CrawlerContext m, Effect SessionContext m, Produce CrawlerContext ~ (CrawlURLs), Produce SessionContext ~ (CrawlSessionInfo)) => FetchPageEffect m where
  fetchPage :: m (Produce FetchPage)
  readFetchedPage :: m (Produce FetchPage)
  readFetchedPage = FrameworkRoot.handler @Root $
    SDK.readContext "FetchPage" ContextBindingError Nothing boundFetchPage
  {-# MINIMAL fetchPage #-}

instance (Monad m, Effect CrawlSession m, FetchPageEffect m) => Effect FetchPage m where
  type Registration FetchPage = Registered FetchPageEffect CrawlSession
  type Typing FetchPage = 'SDK.ContextKind
  type Require FetchPage = (CrawlURLs, CrawlSessionInfo)
  type Produce FetchPage = FetchedPage
  type Error FetchPage = FetchPageError
  raise (FetchPageError description) = SDK.failEffect "FetchPage" FetchPageFailure description
  handler = FrameworkRoot.handler @Root

data ExtractPage

class (Effect CrawlSession m, Effect FetchPage m, Produce FetchPage ~ (FetchedPage)) => ExtractPageEffect m where
  extractPage :: m (Produce ExtractPage)
  readPageSummary :: m (Produce ExtractPage)
  readPageSummary = FrameworkRoot.handler @Root $
    SDK.readContext "ExtractPage" ContextBindingError Nothing boundExtractPage
  {-# MINIMAL extractPage #-}

instance (Monad m, Effect CrawlSession m, ExtractPageEffect m) => Effect ExtractPage m where
  type Registration ExtractPage = Registered ExtractPageEffect CrawlSession
  type Typing ExtractPage = 'SDK.ContextKind
  type Require ExtractPage = FetchedPage
  type Produce ExtractPage = PageSummary
  type Error ExtractPage = ExtractPageError
  raise (ExtractPageError description) = SDK.failEffect "ExtractPage" ExtractPageFailure description
  handler = FrameworkRoot.handler @Root

data PrintPage

class (Effect CrawlSession m, Effect ExtractPage m, Produce ExtractPage ~ (PageSummary)) => PrintPageEffect m where
  printPage :: m ()
  {-# MINIMAL printPage #-}

instance (Monad m, Effect CrawlSession m, PrintPageEffect m) => Effect PrintPage m where
  type Registration PrintPage = Registered PrintPageEffect CrawlSession
  type Typing PrintPage = 'SDK.ExcuKind
  type Require PrintPage = PageSummary
  type Error PrintPage = PrintPageError
  raise (PrintPageError description) = SDK.failEffect "PrintPage" PrintPageFailure description
  handler = FrameworkRoot.handler @Root

data FetchLinkedPage

class (Effect CrawlSession m, Effect CrawlerContext m, Effect SessionContext m, Produce CrawlerContext ~ (CrawlURLs), Produce SessionContext ~ (CrawlSessionInfo)) => FetchLinkedPageEffect m where
  fetchLinkedPage :: m (Produce FetchLinkedPage)
  readFetchedLinkedPage :: m (Produce FetchLinkedPage)
  readFetchedLinkedPage = FrameworkRoot.handler @Root $
    SDK.readContext "FetchLinkedPage" ContextBindingError Nothing boundFetchLinkedPage
  {-# MINIMAL fetchLinkedPage #-}

instance (Monad m, Effect CrawlSession m, FetchLinkedPageEffect m) => Effect FetchLinkedPage m where
  type Registration FetchLinkedPage = Registered FetchLinkedPageEffect CrawlSession
  type Typing FetchLinkedPage = 'SDK.ContextKind
  type Require FetchLinkedPage = (CrawlURLs, CrawlSessionInfo)
  type Produce FetchLinkedPage = FetchedPage
  type Error FetchLinkedPage = FetchLinkedPageError
  raise (FetchLinkedPageError description) = SDK.failEffect "FetchLinkedPage" FetchLinkedPageFailure description
  handler = FrameworkRoot.handler @Root

data ExtractLinkedPage

class (Effect CrawlSession m, Effect FetchLinkedPage m, Produce FetchLinkedPage ~ (FetchedPage)) => ExtractLinkedPageEffect m where
  extractLinkedPage :: m (Produce ExtractLinkedPage)
  readLinkedPageSummary :: m (Produce ExtractLinkedPage)
  readLinkedPageSummary = FrameworkRoot.handler @Root $
    SDK.readContext "ExtractLinkedPage" ContextBindingError Nothing boundExtractLinkedPage
  {-# MINIMAL extractLinkedPage #-}

instance (Monad m, Effect CrawlSession m, ExtractLinkedPageEffect m) => Effect ExtractLinkedPage m where
  type Registration ExtractLinkedPage = Registered ExtractLinkedPageEffect CrawlSession
  type Typing ExtractLinkedPage = 'SDK.ContextKind
  type Require ExtractLinkedPage = FetchedPage
  type Produce ExtractLinkedPage = PageSummary
  type Error ExtractLinkedPage = ExtractLinkedPageError
  raise (ExtractLinkedPageError description) = SDK.failEffect "ExtractLinkedPage" ExtractLinkedPageFailure description
  handler = FrameworkRoot.handler @Root

data PrintLinkedPage

class (Effect CrawlSession m, Effect ExtractLinkedPage m, Produce ExtractLinkedPage ~ (PageSummary)) => PrintLinkedPageEffect m where
  printLinkedPage :: m ()
  {-# MINIMAL printLinkedPage #-}

instance (Monad m, Effect CrawlSession m, PrintLinkedPageEffect m) => Effect PrintLinkedPage m where
  type Registration PrintLinkedPage = Registered PrintLinkedPageEffect CrawlSession
  type Typing PrintLinkedPage = 'SDK.ExcuKind
  type Require PrintLinkedPage = PageSummary
  type Error PrintLinkedPage = PrintLinkedPageError
  raise (PrintLinkedPageError description) = SDK.failEffect "PrintLinkedPage" PrintLinkedPageFailure description
  handler = FrameworkRoot.handler @Root

data SessionContext

class (Effect Root m) => SessionContextEffect m where
  createCrawlSession :: m (Produce SessionContext)
  readCrawlSession :: m (Produce SessionContext)
  readCrawlSession = FrameworkRoot.handler @Root $
    SDK.readContext "SessionContext" ContextBindingError Nothing boundSessionContext
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

class (Effect Root m, Effect SessionContext m, Produce SessionContext ~ (CrawlSessionInfo)) => CrawlSessionEffect m where
  openCrawlSession :: m ()
  closeCrawlSession :: m ()
  {-# MINIMAL openCrawlSession, closeCrawlSession #-}

instance (Monad m, Effect Root m, CrawlSessionEffect m) => Effect CrawlSession m where
  type Registration CrawlSession = Registered CrawlSessionEffect Root
  type Typing CrawlSession = 'SDK.ScopedKind
  type Require CrawlSession = (CrawlSessionInfo, CrawlSessionInfo)
  type Error CrawlSession = CrawlSessionError
  raise (CrawlSessionError description) = SDK.failEffect "CrawlSession" CrawlSessionFailure description
  handler = FrameworkRoot.handler @Root

data FinishCrawl

class (Effect CrawlSession m) => FinishCrawlEffect m where
  finishCrawl :: m ()
  {-# MINIMAL finishCrawl #-}

instance (Monad m, Effect CrawlSession m, FinishCrawlEffect m) => Effect FinishCrawl m where
  type Registration FinishCrawl = Registered FinishCrawlEffect CrawlSession
  type Typing FinishCrawl = 'SDK.ExcuKind
  type Require FinishCrawl = SDK.Void
  type Error FinishCrawl = FinishCrawlError
  raise (FinishCrawlError description) = SDK.failEffect "FinishCrawl" FinishCrawlFailure description
  handler = FrameworkRoot.handler @Root

-- SDK 生成的本地错误只接收消息；类型唯一确定 raise 来源。
newtype CrawlerContextError = CrawlerContextError String
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

-- SDK 生成的本地错误只接收消息；类型唯一确定 raise 来源。
newtype FinishCrawlError = FinishCrawlError String
  deriving (Eq, Show, Read)

-- 统一失败协议的分类标签；消息与来源由 SDK.Failure 保存。
data Errors = CrawlerContextFailure | FetchPageFailure | ExtractPageFailure | PrintPageFailure | FetchLinkedPageFailure | ExtractLinkedPageFailure | PrintLinkedPageFailure | SessionContextFailure | CrawlSessionFailure | FinishCrawlFailure | ContextBindingError SDK.ContextFault | ScopeBindingError SDK.ScopeFault
  deriving (Eq, Show)

-- SDK 内部存储：Nothing 仅表示本次运行尚未建立绑定，不是业务缺值。
data ContextValues = ContextValues
  { boundCrawlerContext :: Maybe (Produce CrawlerContext)
  , boundFetchPage :: Maybe (Produce FetchPage)
  , boundExtractPage :: Maybe (Produce ExtractPage)
  , boundFetchLinkedPage :: Maybe (Produce FetchLinkedPage)
  , boundExtractLinkedPage :: Maybe (Produce ExtractLinkedPage)
  , boundSessionContext :: Maybe (Produce SessionContext)
  }

emptyContexts :: ContextValues
emptyContexts = ContextValues Nothing Nothing Nothing Nothing Nothing Nothing

