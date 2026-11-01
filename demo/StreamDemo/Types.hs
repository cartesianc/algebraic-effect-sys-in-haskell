-- 业务表示类型；资产名与契约在 Effects.hs 的 namedAsset 中声明。
module StreamDemo.Types where

-- 一次读数，单位摄氏度。
newtype Temperature = Temperature Double
  deriving (Eq, Show)
