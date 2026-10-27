module ScopeReuseDemo.Types (SharedPaths(..), SharedFile(..)) where

import System.IO (Handle)

-- 共享输出文件与日志文件的路径；契约 FilePaths 由生成器包装它，并作为开启参数按值比较。
data SharedPaths = SharedPaths FilePath FilePath
  deriving (Eq, Show)

-- 生命周期与使用登记由 SDK 管理；demo 只保存路径和真实资源。契约 OpenedFile 包装它。
data SharedFile = SharedFile SharedPaths Handle
