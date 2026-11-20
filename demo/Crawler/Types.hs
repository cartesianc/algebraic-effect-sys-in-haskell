module Crawler.Types where

-- 业务数据（手写）：Context 的契约类型由生成器按 handler 名包装这些类型产出。
data PageURL = PageURL
  { pageAddress :: String
  } deriving (Eq, Show)

-- 上游 SessionContext 提供的信息；Scope 自身不产值，不持有实际网络连接。
data SessionInfo = SessionInfo
  { sessionName :: String
  , sessionUserAgent :: String
  } deriving (Eq, Show)

data PageSummary = PageSummary
  { summaryURL :: String
  , summaryTitle :: String
  , summaryContent :: String
  , summaryLinks :: [String]
  } deriving (Eq, Show)
