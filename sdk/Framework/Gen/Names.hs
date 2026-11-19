{-# LANGUAGE DuplicateRecordFields #-}

-- gen 派生的全部名字：effect 方法、资产入口、handler 的类／Layer／错误，以及生成区的固定名字。
-- 用户只写 effect 名、资产名和 handler 名；这里的名字只出现在 Generated 中，用户不写也不调用。
module Framework.Gen.Names
  ( effectMethodName
  , capitalized, handlerClass, handlerLayer, handlerError, handlerFailure
  , reservedTypes, reservedValues
  ) where

import Data.Char (toUpper)

-- effect 方法名：run／open／close／detect／resolve／next 加 effect 名。
effectMethodName :: String -> String -> String
effectMethodName prefix effectName = prefix ++ effectName

capitalized :: String -> String
capitalized [] = []
capitalized (first : rest) = toUpper first : rest

-- 每个 handler 一个类、一份 Layer、一个错误类型与一个失败分类。
handlerClass, handlerLayer, handlerError, handlerFailure :: String -> String
handlerClass handler' = capitalized handler' ++ "Handler"
handlerLayer handler' = capitalized handler' ++ "Layer"
handlerError handler' = capitalized handler' ++ "Error"
handlerFailure handler' = capitalized handler' ++ "Failure"

-- 生成区的固定类型名与值名；资产名、分支契约和 handler 名都不能与它们冲突。
reservedTypes :: [String]
reservedTypes = ["App", "At", "Hook", "Captures", "Captured", "ContextValues", "Errors", "MethodGen", "Results", "ContextBindingError", "ScopeBindingError"]

reservedValues :: [String]
reservedValues = ["runAt", "runHook", "captureAt", "capturedAt", "emptyContexts", "handlerSourceFingerprint", "newScopeHandlers", "scopeCleanups"
  , "errorHandlers", "contextInjections", "streamContextInjections", "interpreter", "compiledEntries", "generatedPrototype"]
