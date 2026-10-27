{-# LANGUAGE DeriveGeneric #-}

module Crawler.Types where

import GHC.Generics (Generic)

-- 业务契约（手写）：使用原生 data 与 record，handler 直接匹配这些构造器。
data PageURL = PageURL
  { pageAddress :: String
  } deriving (Show, Read, Generic)

-- 上游 SessionContext 提供的信息；Scope 自身不产值，不持有实际网络连接。
-- 起始页与链接页是两条链的不同业务含义；同一表示用 newtype 区分，类型即装配键。
newtype StartURL = StartURL PageURL deriving (Show, Read, Generic)
newtype LinkedURL = LinkedURL PageURL deriving (Show, Read, Generic)

data CrawlSessionInfo = CrawlSessionInfo
  { sessionName :: String
  , sessionUserAgent :: String
  } deriving (Show, Read, Generic)

data FetchedPage = FetchedHTML
  { fetchedURL :: String
  , fetchedBody :: String
  } deriving (Show, Read, Generic)

data PageSummary = PageSummary
  { summaryURL :: String
  , summaryTitle :: String
  , summaryContent :: String
  , summaryLinks :: [String]
  } deriving (Show, Read, Generic)

newtype StartFetchedPage = StartFetchedPage FetchedPage deriving (Show, Read, Generic)
newtype LinkedFetchedPage = LinkedFetchedPage FetchedPage deriving (Show, Read, Generic)
newtype StartPageSummary = StartPageSummary PageSummary deriving (Show, Read, Generic)
newtype LinkedPageSummary = LinkedPageSummary PageSummary deriving (Show, Read, Generic)
