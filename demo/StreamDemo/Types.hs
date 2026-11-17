-- 业务表示类型；资产名与契约在 Effects.hs 的 Asset 中声明。
module StreamDemo.Types where

import Data.IORef (IORef)

-- 传感器会话保存本业务的计数与最近五次读数；SDK 不识别这些累计规则。
data SensorMemory = SensorMemory (IORef (Int, [Double])) (IORef Int)

instance Show SensorMemory where
  show _ = "SensorMemory"

-- 一份已经解析好的读数快照，包含业务需要的编号和最近读数。
data Temperature = Temperature Int Double [Double]
  deriving (Eq, Show)
