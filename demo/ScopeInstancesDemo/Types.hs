module ScopeInstancesDemo.Types (FileName(..), OpenedFile(..)) where

import System.IO (Handle)

-- 比较开启参数的实际值；不比较活 Handle，也不另配 key。
newtype FileName = FileName FilePath deriving (Eq, Show)
data OpenedFile = OpenedFile FilePath Handle deriving Show
