module OpenFilesDemo.Types (FileHandles(..)) where

-- 一组文件的路径。资产都由 String 构造：Context 契约 OpenedFiles 由生成器包装它；
-- 一份 scope 持有一组十个文件，不是同一 scope 的十次重复开启。
-- 开启状态以每个文件旁的 <path>.open 标记表示：取得时创建，closeFiles 删除；
-- 文件句柄只在读写它的 handler 执行中持有，不进入资产。
newtype FileHandles = FileHandles [String]
  deriving (Eq, Show)
