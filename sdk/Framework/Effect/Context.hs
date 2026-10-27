{-# LANGUAGE FlexibleContexts #-}

-- Context 的读取与成功发布；存储由运行载体提供。
module Framework.Effect.Context
  ( ContextFault(..), ContextAccess(..), readContext, requireContext, requestContext, callContext, provideContext
  ) where

import Framework.Effect.Contract (ContextStore(..), ContextFault(..), ScopeInput, ScopeInputAccess(..), Failure, failEffect)
import Control.Monad.Except (MonadError)
import Data.Maybe (fromMaybe)

data ContextAccess = RequestValue | RequireValue deriving (Eq, Show)

-- require 是一个表达式：值只来自 request，求得后存入 state；require 读取 state。
-- state 中尚无值时转去求值同一个 request（传入的生产入口），结果写回 state，相当于 thunk。
readContext
  :: (ContextStore environment m, MonadError (Failure cause) m)
  => String -> (ContextFault -> cause) -> [(String, ContextAccess)] -> Maybe (value -> ScopeInput)
  -> (environment -> Maybe value) -> m value -> m value
readContext contextName wrap accesses compareValue select produce =
  requireContext contextName wrap accesses (readBoundContext contextName wrap compareValue select (Just produce))

-- 默认和用户覆盖的读取入口都检查来源声明；不改变 caller，state 中已有值时不重新执行生产者。
requireContext
  :: (ContextStore environment m, MonadError (Failure cause) m)
  => String -> (ContextFault -> cause) -> [(String, ContextAccess)] -> m value -> m value
requireContext selected wrap accesses action = do
  _ <- contextAccess selected wrap accesses
  action

contextAccess
  :: (ContextStore environment m, MonadError (Failure cause) m)
  => String -> (ContextFault -> cause) -> [(String, ContextAccess)] -> m (Maybe ContextAccess)
contextAccess selected wrap accesses = do
  caller <- currentHandler
  case caller of
    Nothing -> pure Nothing
    Just consumer -> case lookup consumer accesses of
      Just access -> pure (Just access)
      Nothing -> failEffect selected (wrap (UndeclaredContextAccess consumer))
        ("No context request/require from " ++ consumer ++ " to " ++ selected)

-- 只由已经校验过的入口读取 state；已有值时即使声明了 request 也不刷新。
-- 尚无值时按需求值一次 request（载体负责单次求值，并在诊断、收尾或 scope 资源时拒绝）；
-- 求值失败不写入 state，原失败继续传播，下次 require 会再次求值。
readBoundContext
  :: (ContextStore environment m, MonadError (Failure cause) m)
  => String -> (ContextFault -> cause) -> Maybe (value -> ScopeInput)
  -> (environment -> Maybe value) -> Maybe (m value) -> m value
readBoundContext contextName wrap compareValue select produce = do
  bound <- lookupBound
  case bound of
    Just value -> observed value
    Nothing -> case produce of
      Nothing -> notInitialized
      Just production -> do
        -- 等待并发求值后再查一次 state，避免同一资产重复求值。
        forced <- forceContext contextName (lookupBound >>= maybe production observed)
        maybe notInitialized pure forced
  where
    lookupBound = do
      resolved <- readContextBinding contextName select
      either (\problem -> failEffect contextName (wrap problem) (show problem)) pure resolved
    observed value = do
      observeInput RequiredInput compareValue value
      pure value
    notInitialized = failEffect contextName (wrap ContextNotInitialized) (show ContextNotInitialized)

-- 只观察 instance 实际取得的值，不触发任何生产动作。
observeInput :: ContextStore environment m => ScopeInputAccess -> Maybe (value -> ScopeInput) -> value -> m ()
observeInput _ Nothing _ = pure ()
observeInput access (Just observe) value = recordContextInput access (observe value)

-- 同一个成功值先交给绑定回调再返回；生产失败不会触发回调或再次执行生产。
requestContext
  :: ContextStore environment m
  => String -> (value -> environment -> environment) -> m value -> m value
requestContext selected synchronize produce = protectContextBinding selected $ do
  value <- produce
  publishContextBinding selected (synchronize value)
  pure value

-- 生成的 instance 包装调用此入口；业务 instance 仍直接引用上游类方法。
-- 根调用执行生产；链内根据当前消费者的注册选择刷新或只读。
callContext
  :: (ContextStore environment m, MonadError (Failure cause) m)
  => String -> (ContextFault -> cause) -> [(String, ContextAccess)]
  -> Maybe (value -> ScopeInput)
  -> (environment -> Maybe value) -> (value -> environment -> environment)
  -> m value -> m value
callContext selected wrap accesses compareValue select synchronize produce = do
  access <- contextAccess selected wrap accesses
  case access of
    Just RequireValue -> readBoundContext selected wrap compareValue select (Just refresh)
    _ -> refresh
  where
    refresh = do
      -- 按需求值的 require 生产时仍按 require 被 scope 开启参数观察（同参共享）。
      mode <- productionAccess
      value <- requestContext selected synchronize (enterContext selected produce)
      observeInput mode compareValue value
      pure value

-- 消费方的 request @T / require @T 按当前调用者分派到注册解析出的来源入口。
-- 路由表由生成器从 demands 解析得到；来源入口仍走原有的生产或读取包装。
provideContext
  :: (ContextStore environment m, MonadError (Failure cause) m)
  => String -> (ContextFault -> cause) -> [(String, m value)] -> m value
provideContext contract wrap routes = do
  caller <- currentHandler
  case caller >>= (`lookup` routes) of
    Just action -> action
    Nothing -> failEffect contract (wrap (UndeclaredContextAccess consumer))
      ("No declared demand for " ++ contract ++ " from " ++ consumer)
      where consumer = fromMaybe "the root call" caller
