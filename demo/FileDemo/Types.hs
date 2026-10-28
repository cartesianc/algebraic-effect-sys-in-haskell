module FileDemo.Types (FileHandle(..), TextState(..)) where

import System.IO (Handle)

-- 活资源的表示：路径与真实 Handle。Context 契约 OpenedFile 由生成器按 handler 名包装它；
-- 文件名等单值契约直接包装 FilePath，不再手写一层 newtype。
data FileHandle = FileHandle FilePath Handle
  deriving Show

-- 文件当前内容的状态：和类型。生成器为每个构造器产出分支契约（FileTextBlank、FileTextWritten），
-- alternative 的候选分别 require 其中一个，运行时按资产当前的构造器选择候选。
data TextState = Blank | Written String
  deriving Show
