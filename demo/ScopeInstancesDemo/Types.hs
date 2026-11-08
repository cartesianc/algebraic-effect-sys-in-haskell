module ScopeInstancesDemo.Types (FileHandle(..)) where

import System.IO (Handle)

-- 活资源的表示；开启参数是资产 FileName（细化 FilePath），按值比较，不比较活 Handle，也不另配 key。
data FileHandle = FileHandle FilePath Handle deriving Show
