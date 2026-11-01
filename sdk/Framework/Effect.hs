{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE ExplicitNamespaces #-}

-- Effect SDK 的统一入口；内部存储协议和 target 执行细节不在此导出。
-- Root.handler 只供生成区使用，避免与注册的 handler record 字段混名。
module Framework.Effect
  ( Effect(Registration, Typing, Require, Produce, raise), type Error, EffectTyping(..), EffectKind(..), Root, Registered, App
  , Target, targetApp, SessionSteps, receiveSteps, requestSteps
  , Output(..), Failure(..), ErrorReport(..), caughtFailure, failEffect
  , AssetDecl(..), namedAsset, Handles(..), TypeRef(..), typeRef, EffectSpec(..), Demand(..), Access(..)
  , requests, requires, streams, Void
  , ContextFault(..), ContextAccess(..), readContext, requireContext, requestContext, callContext, provideContext, projectContext, enterHandler
  , atomicHandle, atomicScope, readHistory, streamInput
  , History, historyEntries, latest, historySize
  , ScopeInput(..), ScopeFault(..), openScope, closeScope, withScopeDependencies
  , ScopeHandler, newScopeHandler, withScopeCleanups
  ) where

import Framework.Effect.Contract
  ( Effect(Registration, Typing, Require, Produce, Error, raise), EffectKind(..), Root, Registered, Void
  , Output(..), Failure(..), ErrorReport(..), ErrorStore(caughtFailure), failEffect, ContextStore(enterHandler)
  , ScopeInput(..), ScopeFault(..), ScopeStore(openScope, closeScope, withScopeDependencies)
  )
import Framework.Effect.Context
  ( ContextFault(..), ContextAccess(..), readContext, requireContext, requestContext, callContext, provideContext, projectContext
  , atomicHandle, atomicScope, readHistory, streamInput )
import Framework.Effect.Registration
  ( EffectTyping(..), AssetDecl(..), namedAsset, Handles(..), TypeRef(..), typeRef, EffectSpec(..), Demand(..), Access(..)
  , requests, requires, streams )
import Framework.Effect.History (History, historyEntries, latest, historySize)
import Framework.Effect.Runtime (App, Target, targetApp, SessionSteps, receiveSteps, requestSteps)
import Framework.Effect.Runtime.App (withScopeCleanups)
import Framework.Effect.Scope (ScopeHandler, newScopeHandler)
