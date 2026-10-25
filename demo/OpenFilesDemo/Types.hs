module OpenFilesDemo.Types (FileNames(..), OpenedFiles(..)) where

import System.IO (Handle)

newtype FileNames = FileNames [FilePath]
  deriving (Eq, Show)

-- 一份 scope 持有一组十个文件，不是同一 scope 的十次重复开启。
newtype OpenedFiles = OpenedFiles [(FilePath, Handle)]
  deriving Show
