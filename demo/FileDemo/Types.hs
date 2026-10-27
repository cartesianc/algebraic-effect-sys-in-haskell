module FileDemo.Types (FileHandle(..)) where

import System.IO (Handle)

-- 活资源的表示：路径与真实 Handle。Context 契约 OpenedFile 由生成器按 handler 名包装它；
-- 文件名、文本等单值契约直接包装 FilePath／String，不再手写一层 newtype。
data FileHandle = FileHandle FilePath Handle
  deriving Show
