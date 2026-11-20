-- 业务表示类型；资产名与契约在 Effects.hs 的 Asset 中声明。资产都由 String 构造。
module StreamDemo.Types where

-- 一份已经解析好的温度读数（摄氏度的十进制文本）。编号与最近读数由消费方以 stream @Temperature 读取 x:xs 得到。
newtype Temperature = Temperature String
  deriving (Eq, Show)

-- 一次心跳：单调时钟的秒数（十进制文本）。
newtype Tick = Tick String
  deriving (Eq, Show)
