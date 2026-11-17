-- 业务表示类型；资产名与契约在 Effects.hs 的 Asset 声明中给出。
module LinesDemo.Types (InputFile(..), Line(..), Total(..)) where

import Data.IORef (IORef)
import System.IO (Handle)

-- InputSession 持有文件和本次读取的业务计数；累计规则不属于 SDK。
data InputFile = InputFile FilePath Handle (IORef Total)

instance Show InputFile where
  show (InputFile path _ _) = "InputFile " ++ show path

-- 输入中的一行文本。
newtype Line = Line String
  deriving (Eq, Show)

-- 到目前为止读到的行数与字符总数。
data Total = Total Int Int
  deriving (Eq, Show)
