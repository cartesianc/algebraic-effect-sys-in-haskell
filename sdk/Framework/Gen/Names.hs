{-# LANGUAGE DuplicateRecordFields #-}

-- gen 派生的全部名字：effect 方法、资产入口、handler 的类／Layer／错误，以及生成区的固定名字。
-- 用户只写 effect 名、资产名和 handler 名；这里的名字只出现在 Generated 中，用户不写也不调用。
module Framework.Gen.Names
  ( effectMethodName
  , capitalized, handlerClass, handlerLayer, handlerError, handlerFailure
  , reservedTypes, reservedValues
  , HandlerNames, nameHandlers, entryName, helperName
  ) where

import Data.Char (toUpper)
import Data.List (mapAccumL)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set

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
reservedTypes = ["App", "ContextValues", "Errors", "MethodGen", "Results", "ContextBindingError", "ScopeBindingError"]

reservedValues :: [String]
reservedValues = ["emptyContexts", "interpreter", "compiledEntries", "generatedPrototype"]

-- 两个输出模块共用同一份拼写。先分配 effect 入口，再分配辅助名，因而逻辑入口
-- closeWrap 与内部包装方法 closeWrap 可以同时存在。Prototype 仍使用原来的逻辑入口名。
data HandlerNames = HandlerNames
  { entryName :: String -> String
  , helperName :: String -> String
  }

nameHandlers :: Set.Set String -> [String] -> HandlerNames
nameHandlers visible methods = HandlerNames (entries Map.!) (helpers Map.!)
  where
    (withEntries, entries) = allocate visible methods
    (_, helpers) = allocate withEntries
      ["Wrap", "runWrap", "Hook", "runHook", "Captures", "Captured", "captureAt", "superWrap", "closeWrap"
      , "newScopeHandlers", "errorHandlers", "handlerSourceFingerprint"]
    allocate occupied preferred =
      let (used, pairs) = mapAccumL choose occupied preferred in (used, Map.fromList pairs)
    choose used preferred =
      let spelling = available used preferred in (Set.insert spelling used, (preferred, spelling))
    available used spelling
      | Set.member spelling used = available used (spelling ++ "'")
      | otherwise = spelling
