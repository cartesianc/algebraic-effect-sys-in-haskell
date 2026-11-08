{-# LANGUAGE DuplicateRecordFields #-}

-- 手写业务的公共入口（源语言）：注册声明、handler 能力（require、raw、raise）、故障读取、历史观察与 workflow 组合。
-- 业务 main 使用本程序 Generated.Program 的 interpreter；生成包装和执行装配使用 Framework.Generated，
-- 不在这里暴露存储、scope 控制对象或裸运行入口。
module Framework.SDK
  ( Reads(..), Raw(..), Raises(..)
  , EffectTyping(..), EffectKind(..), EffectSpec(..), Asset(..), Handles(..)
  , Demand(..), Access(..), requests, requires, streams
  , Output(..), Failure(..), ErrorReport(..), caughtFailure
  , ContextFault(..), ScopeFault(..)
  , History, historyEntries, latest, historySize
  , AST, EffectNode, node, chained, parallel, alternative, lifelong
  ) where

import Framework.Language.AST (AST, EffectNode, node, chained, parallel, alternative, lifelong)
import Framework.Language.Handler (Reads(..), Raw(..), Raises(..), Output(..), Failure(..), ErrorReport(..))
import Framework.Language.History (History, historyEntries, latest, historySize)
import Framework.Language.Registration
  ( EffectTyping(..), EffectKind(..), EffectSpec(..), Asset(..), Handles(..), Demand(..), Access(..)
  , requests, requires, streams )
import Framework.Runtime.Protocol (ErrorStore(caughtFailure), ContextFault(..), ScopeFault(..))
