module FileDemo.Types (FileName(..), OpenedFile(..), FileText(..)) where

import System.IO (Handle)

newtype FileName = FileName FilePath
  deriving (Eq, Show)

-- 活资源也是 Context 的业务值；Scoped 本身不返回 Handle。
data OpenedFile = OpenedFile FilePath Handle
  deriving Show

newtype FileText = FileText String
  deriving Show
