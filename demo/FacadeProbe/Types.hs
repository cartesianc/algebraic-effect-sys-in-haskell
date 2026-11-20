module FacadeProbe.Types where

import System.IO (Handle)

data TextFile = TextFile FilePath Handle deriving Show

newtype Body = Body String deriving Show

newtype LineCount = LineCount Int deriving Show

newtype Level = Level Int deriving Show

data FileState = Blank | Filled Body deriving Show
