module FileDemo.Types (FileHandle(..), EmptyText(..), WrittenText(..)) where

import System.IO (Handle)

-- 活资源的表示：路径与真实 Handle。Context 契约 OpenedFile 由生成器按声明的资产名包装它；
-- 文件名等单值契约直接包装 FilePath，不再手写一层 newtype。
data FileHandle = FileHandle FilePath Handle
  deriving Show

-- 读到的文件内容按两种结果解析：为空、或非空时的全文。两个 Context 挂在同一次读取下，
-- 只有一个解析成功；alternative 按候选各自 requires 的那一个选择。
newtype EmptyText = EmptyText String
  deriving (Eq, Show)

newtype WrittenText = WrittenText String
  deriving (Eq, Show)
