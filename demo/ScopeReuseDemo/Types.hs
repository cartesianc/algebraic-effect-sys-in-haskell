module ScopeReuseDemo.Types (FilePaths(..), OpenedFile(..)) where

import Data.IORef (IORef)
import System.IO (Handle)

data FilePaths = FilePaths FilePath FilePath
  deriving (Eq, Show)

-- IORef 只记录本例的观察结果，不承担 Scope 状态检查或 open 的互斥。
-- 生命周期保护仍由 SDK 生成；每个写入记录自己实际使用的 Handle。
data OpenedFile = OpenedFile FilePaths Handle (IORef [(String, Handle)])
