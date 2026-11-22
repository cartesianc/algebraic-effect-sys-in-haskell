-- gen 分配的 effect 编号：运行时按它寻找 effect、存取资产，名字只用于诊断与展示。
-- 编号等于该 effect 在 protoEffects 中的位置；生成代码与 Prototype 出自同一次 gen，编号一致。
-- 一个编号恰对应一个 effect；同一 effect 在剧本中的多个执行位置由坐标区分，不进入编号。
module Framework.Prototype.Slot
  ( Slot(..), scopeResourceSlot
  ) where

import Data.Ord (comparing)

data Slot = Slot
  { slotNumber :: !Int
  , slotName :: String
  }

-- 相等与排序只比较编号；名字不参与匹配。
instance Eq Slot where
  left == right = slotNumber left == slotNumber right

instance Ord Slot where
  compare = comparing slotNumber

-- 展示为名字，诊断文本与改用编号之前一致。
instance Show Slot where
  showsPrec precedence = showsPrec precedence . slotName

-- 没有业务 Context 的 scope 以内部 unit 绑定登记资源；它沿用 Scoped effect 自己的编号，
-- Scoped effect 不生产资产，这个编号不会与资产冲突。
scopeResourceSlot :: Slot -> Slot
scopeResourceSlot scope = Slot (slotNumber scope) ("$scope:" ++ slotName scope)
