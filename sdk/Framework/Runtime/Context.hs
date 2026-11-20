{-# LANGUAGE FlexibleContexts #-}

-- Context 的读取与成功发布；存储由运行载体提供。
module Framework.Runtime.Context
  ( ContextFault(..), readContext, callContext
  , chooseCase, atomicHandle, atomicScope, readStreamContext, readStreamHistory
  ) where

import Framework.Runtime.Protocol
  (ContextStore(..), ContextFault(..), RawOutput(..), failEffect)
import Framework.Language.Handler (Failure(..), Flow(..))
import Control.Monad (forM_, when)
import Control.Monad.Except (MonadError, catchError, throwError)

-- require 是一次读取：值只来自 requests 驱动的生产或 Stream 会话，读取本身不生产。
-- 已有值时直接返回；尚无值时等发布或节点进度变化，再读取同一份运行级最新值。
-- 只在已证明合法生产机会耗尽时结束等待；无法证明的路径继续等待。
-- 载体在诊断、收尾或 scope 资源时不等待，缺值按 ContextNotInitialized 报出。
readContext
  :: (ContextStore environment m, MonadError (Failure cause) m)
  => String -> (ContextFault -> cause) -> (environment -> Maybe value) -> m value
readContext contextName wrap select = awaitBound
  where
    awaitBound = do
      -- 先取等待动作再读：读取之后、开始等待之前的发布也会唤醒这次等待。
      waiting <- awaitContext contextName
      bound <- lookupBound
      case bound of
        Just value -> observed value
        Nothing -> case waiting of
          Nothing -> notInitialized
          Just wait -> do
            changed <- wait
            if changed then awaitBound else do
              -- 初次读空之后，生产者仍可能先发布再退出；耗尽证据确定后最后重读，
              -- 不能把这份已经发布的值误报为 ContextNotInitialized。
              final <- lookupBound
              maybe notInitialized observed final
    lookupBound = do
      resolved <- readContextBinding contextName select
      either (\problem -> failEffect contextName (wrap problem) (show problem)) pure resolved
    observed value = do
      recordContextInput contextName
      pure value
    notInitialized = failEffect contextName (wrap ContextNotInitialized) (show ContextNotInitialized)

-- 同一个成功值先交给绑定回调再返回；生产失败不会触发回调或再次执行生产。
requestContext
  :: ContextStore environment m
  => String -> (value -> environment -> environment) -> m value -> m value
requestContext selected synchronize produce = enterRequest selected $
  protectContextBinding selected $ do
    value <- produce
    publishContextBinding selected (synchronize value)
    pure value

-- getT 的生成入口：每次调用都生产并发布。只有 requests 驱动、alternative 的选择读取、
-- 挂接注入和会话步骤调用它；require 读取走 readContext，不经这里。
callContext
  :: ContextStore environment m
  => String -> (value -> environment -> environment)
  -> m value -> m value
callContext selected synchronize produce = do
  value <- requestContext selected synchronize (enterContext selected produce)
  recordContextInput selected
  pure value

-- alternative 的选择读取（option）：执行一次共同的 Excu，按候选的声明顺序把同一份输出交给各自的
-- 判定 Context，返回第一个解析成功的 Context 名；它的发布被本次调用捕获，交给选中的候选。
-- 执行 Excu 时以首个判定 Context 为调用者，挂接注入因此不重复执行这些 parser；
-- 判定失败只算放弃，全部放弃时报第一个失败，消息列出每个候选各自的原因。
chooseCase
  :: (ContextStore environment m, MonadError (Failure cause) m)
  => String -> m [String] -> [(String, m ())] -> m String
chooseCase method upstream cases = do
  output <- maybe id enterHandler (fst <$> safeHead cases) upstream
  attempt output [] cases
  where
    safeHead (first : _) = Just first
    safeHead [] = Nothing
    attempt _ failures [] = case failures of
      (_, first) : _ -> throwError first { message = "no alternative case matched: "
        ++ concatMap (\(name, problem) -> "[" ++ name ++ "] " ++ message problem ++ " ") failures }
      [] -> error "SDK: an alternative without candidates; regenerate the program"
    attempt output failures ((name, produce) : rest) = do
      outcome <- (Right <$> attemptOutput method (RawOutput True output) produce) `catchError` (pure . Left)
      case outcome of
        Right () -> pure name
        Left problem -> attempt output (failures ++ [(name, problem)]) rest

-- streamT 的生成入口：从本次固定交付或有限读取的捕获值取得业务表示类型。
-- 是否继续被增量驱动由组合计划决定；这里执行一次读取，不包装或解释业务数据。
readStreamContext
  :: (ContextStore environment m, MonadError (Failure cause) m)
  => String -> (ContextFault -> cause) -> (environment -> Maybe value) -> m value
readStreamContext contextName wrap select = do
  captured <- readContextValue contextName select
  value <- case captured of
    Just value -> pure value
    Nothing -> do
      delivered <- awaitContextValue contextName select
      maybe (failEffect contextName (wrap ContextNotInitialized)
        (contextName ++ ": no delivery here (no stream session can deliver, or the stream ended without publishing)")) pure delivered
  recordContextInput contextName
  pure value

-- stream @T 的生成入口：与 readStreamContext 领取同一次交付，返回 x :> xs。
-- x 是本次值，xs 是同一会话更早的发布（最新在前），都已发布；读取不等待后续发布，也不驱动来源。
readStreamHistory
  :: (ContextStore environment m, MonadError (Failure cause) m)
  => String -> (ContextFault -> cause) -> (environment -> Maybe value) -> m (Flow value)
readStreamHistory contextName wrap select = do
  captured <- readContextHistory contextName select
  values <- case captured of
    Just values -> pure values
    Nothing -> do
      delivered <- awaitContextHistory contextName select
      maybe (failEffect contextName (wrap ContextNotInitialized)
        (contextName ++ ": no delivery here (no stream session can deliver, or the stream ended without publishing)")) pure delivered
  recordContextInput contextName
  pure (foldr (:>) Done values)

-- Excu 的生成入口：每次调用都执行。
atomicHandle
  :: (ContextStore environment m, MonadError (Failure cause) m)
  => String -> [(String, m ())] -> [(String, m ())] -> m [String] -> m [String]
atomicHandle method anchored continuous = atomicScope method anchored continuous . fmap Just

-- 原子句柄（Excu、Scoped.open／close）的统一出口。handler 交出的 list 与是否成功
-- 组成 RawOutput，只交给挂在该句柄下（可经一串 Pure）的 Context parser 解析并作为资产发布；没有挂接时直接丢弃。
-- 以它为 Input 的入口不读取这份输出；普通挂接的失败留在注入内，持续挂接的失败按持续执行协议传播。
-- 外层 Nothing 表示 handler 没有执行（复用的 scope 实例、重复 close），此时没有新的输出。
-- 挂在句柄下的 parser 由 gen 写在入口上：anchored 是普通挂接，continuous 是持续挂接，各为 (Context 名, 生产入口)。
atomicScope
  :: (ContextStore environment m, MonadError (Failure cause) m)
  => String -> [(String, m ())] -> [(String, m ())] -> m (Maybe [String]) -> m [String]
atomicScope method anchored continuous body = do
  replayed <- replayedOutput method
  case replayed of
    -- 注入中的 parser（或它上方的 Pure）经 rawinput 调用挂接的句柄：回答本次输出，不重复执行。
    Just raw -> pure (info raw)
    Nothing -> do
      consumer <- currentHandler
      outcome <- (Right <$> body) `catchError` (pure . Left)
      case outcome of
        Right Nothing -> pure []
        Right (Just output) -> deliver consumer (RawOutput True output) >> pure output
        Left problem -> deliver consumer (RawOutput False [message problem]) >> throwError problem
  where
    -- 失败的输出不交给 Context，原失败照常沿原链传播。
    -- 挂接的 Context 自己拉取该句柄时（requests 驱动或选择读取），由它自己的入口发布，不再注入；
    -- 中间的 Pure 入口不改变调用者，所以经一串 Pure 拉取时仍认得出是这个 Context。
    deliver consumer raw = when (succeeded raw) $ do
      when (maybe True (`notElem` map fst anchored) consumer) $
        forM_ anchored $ \(_, produce) -> injectOutput method raw produce
      active <- activeStreamContexts continuous
      when (maybe True (`notElem` map fst active) consumer) $
        forM_ active $ \(_, produce) -> injectStreamOutput method raw produce
