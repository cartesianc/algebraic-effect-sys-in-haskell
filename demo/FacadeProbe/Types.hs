-- 资产都由 String 构造；文件句柄只在读写它的 handler 执行中持有。
module FacadeProbe.Types where

newtype TextFile = TextFile String deriving (Eq, Show)

newtype Body = Body String deriving (Eq, Show)

newtype LineCount = LineCount String deriving (Eq, Show)

newtype Level = Level String deriving (Eq, Show)

newtype EmptyReport = EmptyReport String deriving (Eq, Show)
