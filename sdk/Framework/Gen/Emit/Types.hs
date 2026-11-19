-- 只把组合计算已经决定的类型与能力打印成 Haskell；这里不查询注册或选择执行方式。
module Framework.Gen.Emit.Types (renderValueType, renderCapability) where

import Framework.Gen.Plan (ValueType(..), Capability(..))

-- 前缀包含末尾的点：源契约中的细化类型可用空前缀，运行副本使用 FrameworkGenerated.。
renderValueType :: String -> String -> ValueType -> String
renderValueType _ generated selected = case selected of
  NativeType source -> source
  RefinedType contract -> generated ++ contract

renderCapability :: Capability -> String
renderCapability capability = case capability of
  ReadsType value -> "SDK.Reads (" ++ renderValueType "SDK." "" value ++ ") m"
  HasRaw -> "SDK.Raw m"
  EndsSource -> "SDK.StreamEnds m"
  EndsSubscription -> "SDK.EndsStream m"
  ObservesHooks -> "SDK.Hooks m"
  PureMonad -> "Monad m"
  IOMonad -> "MonadIO m"
