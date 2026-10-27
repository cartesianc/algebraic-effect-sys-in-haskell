module OpenFilesDemo.Types (FileHandle(..)) where

import System.IO (Handle)

-- 一个文件的路径与真实 Handle。Context 契约 OpenedFiles 由生成器包装 [FileHandle]；
-- 一份 scope 持有一组十个文件，不是同一 scope 的十次重复开启。
data FileHandle = FileHandle FilePath Handle
  deriving Show
