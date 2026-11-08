{-# LANGUAGE DuplicateRecordFields #-}

-- gen 派生的全部名字：effect 方法、资产入口、handler 的类／Layer／错误，以及生成区的固定名字。
-- 用户只写 effect 名、资产名和 handler 名；这里的名字只出现在 Generated 中，用户不写也不调用。
module Framework.Gen.Names
  ( effectMethodName, entryMethod, handlerBindings, contextProducer, contextReader
  , capitalized, handlerClass, handlerLayer, handlerError, handlerFailure
  , reservedTypes, reservedValues
  ) where

import Data.Char (toUpper)
import Framework.Language.Registration

-- effect 方法名：run／open／close／detect／resolve／next 加 effect 名。
effectMethodName :: String -> String -> String
effectMethodName prefix effectName = prefix ++ effectName

-- 普通入口按角色确定，关闭方法不参与入口选择。
entryMethod :: EffectSpec -> Maybe String
entryMethod specification = case typing specification of
  Pure method -> effectMethodName "run" (name specification) <$ method
  Excu method -> effectMethodName "run" (name specification) <$ method
  Scoped opening _ -> effectMethodName "open" (name specification) <$ opening
  -- Error 的两个方法由故障协议激活，不猜测一个普通 Node 入口。
  Error {} -> Nothing
  selected@Context {} -> contextProducer selected
  -- Stream 的方法只经会话执行，不作为 AST 末端；末端检查另行拒绝。
  Stream method -> effectMethodName "next" (name specification) <$ method

-- 注册把 handler 绑定到 effect 方法：(effect 方法名, handler 名)。
handlerBindings :: EffectSpec -> [(String, String)]
handlerBindings specification = case typing specification of
  Pure method -> bound "run" method
  Excu method -> bound "run" method
  Scoped opening closing -> bound "open" opening ++ bound "close" closing
  Error { detect = detecting, resolve = resolving } -> bound "detect" detecting ++ bound "resolve" resolving
  selected@Context { parser = parsing } -> [(method, selected') | Just method <- [contextProducer selected], Just selected' <- [parsing]]
  Stream method -> bound "next" method
  where
    bound prefix method = [(effectMethodName prefix (name specification), selected) | Just selected <- [method]]

-- 生产入口：get 加资产名，例如 getStartURL；它沿 Input 驱动 parser，结果发布为资产。
-- 消费方写 requests 驱动它，handler 不直接调用。
contextProducer :: EffectTyping -> Maybe String
contextProducer (Context declared (Just _) _ _) = Just ("get" ++ contractOf declared)
contextProducer _ = Nothing

-- 读取入口：read 加资产名读取最新值；持续资产为 stream 加资产名，读取历史。
-- 消费方写 requires／streams，handler 按表示类型 require，不直接调用它。
contextReader :: EffectTyping -> Maybe String
contextReader (Context declared _ True streaming) =
  Just ((if streaming then "stream" else "read") ++ contractOf declared)
contextReader _ = Nothing

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
reservedTypes = ["App", "At", "ContextValues", "Errors", "MethodGen", "Results", "ContextBindingError", "ScopeBindingError"]

reservedValues :: [String]
reservedValues = ["runAt", "emptyContexts", "handlerSourceFingerprint", "newScopeHandlers", "scopeCleanups"
  , "errorHandlers", "contextInjections", "interpreter", "compiledEntries", "generatedPrototype"]
