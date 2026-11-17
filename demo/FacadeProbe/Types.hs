module FacadeProbe.Types where

import Data.IORef (IORef)
import System.IO (Handle)

data TextFile = TextFile FilePath Handle deriving Show

newtype Body = Body String deriving Show

newtype LineCount = LineCount Int deriving Show

-- 每份来源保存自己的业务计数；两个 effect 仍复用同一获取和消费 handler。
newtype FeedCounter = FeedCounter (IORef Int)

instance Show FeedCounter where
  show _ = "FeedCounter"

data Level = Level Int Int deriving Show

data FileState = Blank | Filled Body deriving Show
