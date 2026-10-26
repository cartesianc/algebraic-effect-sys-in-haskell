{-# LANGUAGE FlexibleContexts #-}

-- Context 的读取与成功发布；存储由运行载体提供。
module Framework.Effect.Context
  ( ContextFault(..), ContextAccess(..), readContext, requireContext, requestContext, callContext
  ) where

import Framework.Effect.Contract (ContextStore(..), ContextFault(..), ScopeInput, ScopeInputAccess(..), Failure, failEffect)
import Control.Monad.Except (MonadError)

data ContextAccess = RequestValue | RequireValue deriving (Eq, Show)

readContext
  :: (ContextStore environment m, MonadError (Failure cause) m)
  => String -> (ContextFault -> cause) -> [(String, ContextAccess)] -> Maybe (value -> ScopeInput)
  -> (environment -> Maybe value) -> m value
readContext contextName wrap accesses compareValue select =
  requireContext contextName wrap accesses (readBoundContext contextName wrap compareValue select)

-- 默认和用户覆盖的读取入口都检查来源声明；不改变 caller，也不重新执行生产者。
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

-- 只由已经校验过的入口读取绑定；显式读取即使声明了 request 也不会刷新。
readBoundContext
  :: (ContextStore environment m, MonadError (Failure cause) m)
  => String -> (ContextFault -> cause) -> Maybe (value -> ScopeInput)
  -> (environment -> Maybe value) -> m value
readBoundContext contextName wrap compareValue select = do
  resolved <- readContextBinding contextName select
  bound <- either (\problem -> failEffect contextName (wrap problem) (show problem)) pure resolved
  value <- maybe (failEffect contextName (wrap ContextNotInitialized) (show ContextNotInitialized)) pure bound
  observeInput RequiredInput compareValue value
  pure value

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
    Just RequireValue -> readBoundContext selected wrap compareValue select
    _ -> refresh
  where
    refresh = do
      value <- requestContext selected synchronize (enterContext selected produce)
      observeInput RequestedInput compareValue value
      pure value
