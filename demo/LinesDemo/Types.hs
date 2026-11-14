-- 业务表示类型；资产名与契约在 Effects.hs 的 Asset 声明中给出。
module LinesDemo.Types (InputFile(..), Line(..)) where

import System.IO (Handle)

-- 打开的输入文件：路径与真实 Handle，是 InputSession 持有的资源。
data InputFile = InputFile FilePath Handle
  deriving Show

-- 输入中的一行文本。
newtype Line = Line String
  deriving (Eq, Show)
