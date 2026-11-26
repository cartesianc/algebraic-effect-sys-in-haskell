-- 业务表示类型；资产名与契约在 Effects.hs 的 Asset 中声明。字段是基础字段或本模块的类型。
module StreamDemo.Types where

-- 一份已经解析好的温度读数（摄氏度）。parser 解析一次，消费方直接读数值。
-- 编号与最近读数由消费方以 stream @Temperature 读取 x:xs 得到。
newtype Temperature = Temperature Double
  deriving (Eq, Show)

-- 一次心跳：单调时钟的秒数（十进制文本）。消费方只数心跳次数，不做数值计算，所以保留文本。
newtype Tick = Tick String
  deriving (Eq, Show)
