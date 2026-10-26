module ScopeReuseDemo.Types (FilePaths(..), OpenedFile(..)) where

import System.IO (Handle)

data FilePaths = FilePaths FilePath FilePath
  deriving (Eq, Show)

-- 生命周期与使用登记由 SDK 管理；demo 只保存路径和真实资源。
data OpenedFile = OpenedFile FilePaths Handle
