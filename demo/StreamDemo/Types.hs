-- 业务表示类型；资产名与契约在 Effects.hs 的 Asset 中声明。
module StreamDemo.Types where

-- 一份已经解析好的温度读数。编号与最近读数由消费方以 stream @Temperature 读取 x:xs 得到。
newtype Temperature = Temperature Double
  deriving (Eq, Show)
