{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE TypeFamilies #-}

-- 自动生成；只登记末端句柄，Node algebra 才 lower，业务组合仍在 handler 内。
module RequestBenchmark.Generated.Program where

import Framework.SDK (Effect(..), EffectSpec(..), EffectTyping(..), Producer(..), ContextInput(..), ValueSource(..), TypeRef(..), Output)
import qualified Framework.SDK as SDK
import qualified Framework.Effect.Contract as FrameworkRoot
import RequestBenchmark.Generated.Effects
import qualified RequestBenchmark.Generated.Handlers as Handlers
import RequestBenchmark.Types

-- 纯计算样例也只登记末端句柄，不在外部组合上游。
compiledTarget :: SDK.Target SDK.Identity ContextValues Errors (Produce RenderNumber)
compiledTarget = SDK.targetPure "RenderNumber" emptyContexts
  (FrameworkRoot.withErrorHandlers Handlers.errorHandlers renderNumber)

benchmark :: Output Errors (Produce RenderNumber)
benchmark = SDK.bootPure compiledTarget

-- 生成入口由 SDK 提供；业务无需另写 Codegen 模块。
runDemo :: Show value => [EffectSpec] -> String -> value -> IO ()
runDemo = SDK.runDemo "RequestBenchmark"
