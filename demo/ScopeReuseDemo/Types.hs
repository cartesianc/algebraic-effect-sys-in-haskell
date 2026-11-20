module ScopeReuseDemo.Types (SharedPaths(..), SharedFile(..)) where

-- 资产都由 String 构造。共享输出文件与日志文件的路径；契约 FilePaths 由生成器包装它，并作为开启参数按值比较。
data SharedPaths = SharedPaths String String
  deriving (Eq, Show)

-- 生命周期与使用登记由 SDK 管理；资源只记路径，写入者在自己的执行中按路径追加。契约 OpenedFile 包装它。
newtype SharedFile = SharedFile SharedPaths
  deriving (Eq, Show)
