-- 业务表示类型；资产名与契约在 Effects.hs 的 Asset 声明中给出。资产都由 String 构造。
module LinesDemo.Types (InputFile(..), Line(..), Total(..)) where

-- InputSession 的资源：输入文件的路径。文件句柄只在读取它的 handler 执行中持有，不进入资产。
newtype InputFile = InputFile String
  deriving (Eq, Show)

-- 输入中的一行文本。
newtype Line = Line String
  deriving (Eq, Show)

-- 到目前为止读到的行数与字符总数（十进制文本）。
data Total = Total String String
  deriving (Eq, Show)
