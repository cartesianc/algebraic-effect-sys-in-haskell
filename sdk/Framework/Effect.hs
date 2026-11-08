{-# LANGUAGE DuplicateRecordFields #-}

-- 手写业务的公共契约：注册声明、handler 能力（require、raw、raise）、故障读取与历史观察；
-- Context 存储入口、Target 装配和 scope 生命周期包装由 Framework.Generated 提供。
module Framework.Effect
  ( Reads(..), Raw(..), Raises(..)
  , EffectTyping(..), EffectKind(..), EffectSpec(..), Asset(..), Handles(..)
  , Demand(..), Access(..), requests, requires, streams
  , Output(..), Failure(..), ErrorReport(..), caughtFailure
  , ContextFault(..), ScopeFault(..)
  , History, historyEntries, latest, historySize
  ) where

import Framework.Effect.Contract
  ( Reads(..), Raw(..), Raises(..), EffectKind(..)
  , Output(..), Failure(..), ErrorReport(..), ErrorStore(caughtFailure)
  , ContextFault(..), ScopeFault(..)
  )
import Framework.Effect.Registration
  ( EffectTyping(..), EffectSpec(..), Asset(..), Handles(..), Demand(..), Access(..)
  , requests, requires, streams )
import Framework.Effect.History (History, historyEntries, latest, historySize)
