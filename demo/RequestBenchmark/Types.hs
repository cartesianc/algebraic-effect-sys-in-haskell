{-# LANGUAGE DeriveGeneric #-}

module RequestBenchmark.Types where

import GHC.Generics (Generic)

-- 业务契约（手写）：原生 data；注册仅引用类型，不再重述构造器与字段。
data NumberInput = Start Int deriving (Show, Read, Generic)
data RenderOptions = Render String deriving (Show, Read, Generic)
data InputSettings = InputSettings NumberInput RenderOptions deriving (Show, Read, Generic)
