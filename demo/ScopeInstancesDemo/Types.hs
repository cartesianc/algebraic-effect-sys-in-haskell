module ScopeInstancesDemo.Types (FileHandle(..)) where

-- 资源的表示：文件路径。资产都由 String 构造；开启参数是资产 FileName（String），按值比较，也不另配 key。
-- 开启状态以文件旁的 <path>.open 标记表示：取得时创建，closeSelectedFile 删除；
-- 文件句柄只在读写它的 handler 执行中持有，不进入资产。
newtype FileHandle = FileHandle String
  deriving (Eq, Show)
