-- 只把组合计算已经决定的类型与能力打印成 Haskell；这里不查询注册或选择执行方式。
module Framework.Gen.Emit.Types (renderValueType, renderCapability, specialisation) where

import Framework.Gen.Plan (ValueType(..), Capability(..), parenthesized)

-- 生成模块与 SDK 的运行模块都带这条编译选项：生成代码只在具体的 App 上调用多态的 handler 与 SDK 函数，
-- GHC 据此为 App 特化，消掉类型类字典调用并内联 monad 栈。手写业务模块不需要。
specialisation :: String
specialisation = "{-# OPTIONS_GHC -fexpose-all-unfoldings -fspecialise-aggressively #-}"

-- 前缀包含末尾的点：源契约中的细化类型可用空前缀，运行副本使用 FrameworkGenerated.。
renderValueType :: String -> String -> ValueType -> String
renderValueType _ generated selected = case selected of
  NativeType source -> source
  RefinedType contract -> generated ++ contract

renderCapability :: Capability -> String
renderCapability capability = case capability of
  ReadsType value -> "SDK.Reads " ++ parenthesized (renderValueType "SDK." "" value) ++ " m"
  StreamsType value -> "SDK.Streams " ++ parenthesized (renderValueType "SDK." "" value) ++ " m"
  HasRaw -> "SDK.Raw m"
  WritesRaw -> "SDK.RawOutputs m"
  EmitsItem -> "SDK.Emits m"
  EndsSource -> "SDK.StreamEnds m"
  MasksExceptions -> "SDK.MonadMask m"
  EndsSubscription -> "SDK.EndsStream m"
  ObservesHooks -> "SDK.Hooks m"
  PureMonad -> "Monad m"
  IOMonad -> "MonadIO m"
