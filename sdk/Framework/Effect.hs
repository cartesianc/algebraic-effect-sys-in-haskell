{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE ExplicitNamespaces #-}

-- Effect SDK 的统一入口；内部存储协议和 target 执行细节不在此导出。
-- Root.handler 只供生成区使用，避免与注册的 handler record 字段混名。
module Framework.Effect
  ( Effect(Registration, Typing, Require, Produce, raise), type Error, EffectTyping(..), EffectKind(..), Root, Registered, Pure, App
  , Target, Identity, targetPure, targetApp, bootPure
  , Output(..), Failure(..), ErrorReport(..), caughtFailure, failEffect
  , Producer(..), TypeRef(..), typeRef, EffectSpec(..), ContextInput(..), ValueSource(..), Void
  , ContextFault(..), ContextAccess(..), readContext, requireContext, requestContext, callContext, enterHandler
  , ScopeInput(..), ScopeFault(..), openScope, closeScope, withScopeDependencies
  , ScopeHandler, newScopeHandler, withScopeCleanups
  ) where

import Framework.Effect.Contract
  ( Effect(Registration, Typing, Require, Produce, Error, raise), EffectKind(..), Root, Registered, Void
  , Output(..), Failure(..), ErrorReport(..), ErrorStore(caughtFailure), failEffect, ContextStore(enterHandler)
  , ScopeInput(..), ScopeFault(..), ScopeStore(openScope, closeScope, withScopeDependencies)
  )
import Framework.Effect.Context (ContextFault(..), ContextAccess(..), readContext, requireContext, requestContext, callContext)
import Framework.Effect.Registration
  ( EffectTyping(..), Producer(..), TypeRef(..), typeRef, EffectSpec(..), ContextInput(..), ValueSource(..) )
import Framework.Effect.Runtime (Pure, App, Target, Identity, targetPure, targetApp, bootPure)
import Framework.Effect.Runtime.App (withScopeCleanups)
import Framework.Effect.Scope (ScopeHandler, newScopeHandler)
