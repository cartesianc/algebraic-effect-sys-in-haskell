{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE ExplicitNamespaces #-}

-- 手写 effect 的公共契约。这里提供注册、raise、故障读取与历史观察；
-- Context 存储入口、Target 装配和 scope 生命周期包装由 Framework.Generated 提供。
-- Root.handler 仍只供生成区使用，避免与注册的 handler record 字段混名。
module Framework.Effect
  ( Effect(Registration, Typing, Require, Produce, raise), type Error
  , EffectTyping(..), EffectKind(..), EffectSpec(..), Asset(..), Handles(..)
  , Demand(..), Access(..), requests, requires, streams
  , Output(..), Failure(..), ErrorReport(..), caughtFailure
  , ContextFault(..), ScopeFault(..)
  , History, historyEntries, latest, historySize
  ) where

import Framework.Effect.Contract
  ( Effect(Registration, Typing, Require, Produce, Error, raise), EffectKind(..)
  , Output(..), Failure(..), ErrorReport(..), ErrorStore(caughtFailure)
  , ContextFault(..), ScopeFault(..)
  )
import Framework.Effect.Registration
  ( EffectTyping(..), EffectSpec(..), Asset(..), Handles(..), Demand(..), Access(..)
  , requests, requires, streams )
import Framework.Effect.History (History, historyEntries, latest, historySize)
