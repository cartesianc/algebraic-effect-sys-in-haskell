{-# LANGUAGE DuplicateRecordFields #-}

-- Effect SDK 的统一入口；内部存储协议和 target 执行细节不在此导出。
-- Root.handler 只供生成区使用，避免与注册的 handler record 字段混名。
module Framework.Effect
  ( Effect(Registration, Typing, Require, Produce, Error, raise), EffectTyping(..), EffectKind(..), Root, Registered, Pure, App
  , Target, Identity, targetPure, targetApp, bootPure
  , Output(..), Failure(..), failEffect
  , Producer(..), TypeRef(..), typeRef, EffectSpec(..), ContextInput(..), ValueSource(..), Void
  , ContextFault(..), ContextAccess(..), readContext, requestContext, callContext, enterHandler
  , ScopeInput(..), ScopeFault(..), openScope, closeScope, withScopeDependencies
  , ScopeHandler, newScopeHandler
  ) where

import Framework.Effect.Contract
  ( Effect(Registration, Typing, Require, Produce, Error, raise), EffectKind(..), Root, Registered, Void
  , Output(..), Failure(..), failEffect, ContextStore(enterHandler)
  , ScopeInput(..), ScopeFault(..), ScopeStore(openScope, closeScope, withScopeDependencies)
  )
import Framework.Effect.Context (ContextFault(..), ContextAccess(..), readContext, requestContext, callContext)
import Framework.Effect.Registration
  ( EffectTyping(..), Producer(..), TypeRef(..), typeRef, EffectSpec(..), ContextInput(..), ValueSource(..) )
import Framework.Effect.Runtime (Pure, App, Target, Identity, targetPure, targetApp, bootPure)
import Framework.Effect.Scope (ScopeHandler, newScopeHandler)
