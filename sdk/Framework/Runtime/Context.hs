{-# LANGUAGE FlexibleContexts #-}

-- Context 的读取与成功发布；存储由运行载体提供。
module Framework.Runtime.Context
  ( ContextFault(..), readContext, callContext
  , projectContext, latestContext, atomicHandle, atomicScope, readHistory, streamHandle
  ) where

import Framework.Runtime.Protocol
  (ContextStore(..), ContextFault(..), ScopeInput, ScopeInputAccess(..), RawOutput(..), failEffect)
import Framework.Language.Handler (Failure(..))
import Control.Monad (forM_, when)
import Control.Monad.Except (MonadError, catchError, throwError)
import Framework.Language.History (History, latest)

-- require 是一次读取：值只来自 requests 驱动的生产或 Stream 会话，读取本身不生产。
-- 已有值时直接返回；尚无值时像 await 一样阻塞这条链，等之后的发布再按同一来源表重读，不报错。
-- 载体在诊断、收尾或 scope 资源时不等待，缺值按 ContextNotInitialized 报出。
readContext
  :: (ContextStore environment m, MonadError (Failure cause) m)
  => String -> (ContextFault -> cause) -> Maybe (value -> ScopeInput)
  -> (environment -> Maybe value) -> m value
readContext contextName wrap compareValue select = awaitBound
  where
    awaitBound = do
      -- 先取等待动作再读：读取之后、开始等待之前的发布也会唤醒这次等待。
      waiting <- awaitContext contextName
      bound <- lookupBound
      case bound of
        Just value -> observed value
        Nothing -> maybe notInitialized (>> awaitBound) waiting
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
requestContext selected synchronize produce = enterRequest selected $
  protectContextBinding selected $ do
    value <- produce
    publishContextBinding selected (synchronize value)
    pure value

-- getT 的生成入口：每次调用都生产并发布。只有 requests 驱动、alternative 的选择读取、
-- 挂接注入和会话步骤调用它；require 读取走 readContext，不经这里。
callContext
  :: ContextStore environment m
  => String -> Maybe (value -> ScopeInput) -> (value -> environment -> environment)
  -> m value -> m value
callContext selected compareValue synchronize produce = do
  value <- requestContext selected synchronize (enterContext selected produce)
  observeInput RequestedInput compareValue value
  pure value

-- 和类型资产的分支契约是基础契约的投影：读取基础契约，资产当前是该构造器时取出其字段，
-- 否则报 CaseNotSelected。不新增状态，也不单独生产。故障来源是生产方的注册名，与 ContextFaultIn 的匹配一致。
projectContext
  :: (ContextStore environment m, MonadError (Failure cause) m)
  => String -> String -> (ContextFault -> cause) -> (base -> Maybe branch) -> m base -> m branch
projectContext producer contract wrap project readBase = do
  base <- readBase
  maybe (failEffect producer (wrap (CaseNotSelected contract)) (show (CaseNotSelected contract))) pure (project base)

-- 持续资产的 requires：读取历史视图在本次交付位置的最新条目。
latestContext
  :: (ContextStore environment m, MonadError (Failure cause) m)
  => String -> (ContextFault -> cause) -> m (History value) -> m value
latestContext producer wrap readHistory' = readHistory' >>= maybe
  (failEffect producer (wrap ContextNotInitialized) (producer ++ ": no delivery yet")) pure . latest

-- streamT 的生成入口：先用本次调用已经取得的视图（lifelong 交付或此前的会话读取）。
-- 没有视图时，由 interpreter 托管的会话交付当前历史。
readHistory
  :: (ContextStore environment m, MonadError (Failure cause) m)
  => String -> (ContextFault -> cause) -> (environment -> Maybe value) -> m (History value)
readHistory contextName wrap select = do
  captured <- readContextHistory contextName select
  case captured of
    Just history -> pure history
    Nothing -> do
      delivered <- awaitContextHistory contextName select
      maybe (failEffect contextName (wrap ContextNotInitialized)
        (contextName ++ ": no stream session can deliver here")) pure delivered

-- Stream 的生成入口。会话调用 parser 时安装了本次原始输入：parser 的 raw 由这份输入回答，
-- 不再执行 handler 另取一份，与挂在原子句柄下的 Context 相同。Stream 单步没有安装输入，执行 handler 取得下一份。
streamHandle :: ContextStore environment m => m String -> m String
streamHandle body = streamRawInput >>= maybe body pure

-- Excu 的生成入口：每次调用都执行。
atomicHandle
  :: (ContextStore environment m, MonadError (Failure cause) m)
  => String -> m [String] -> m [String]
atomicHandle method = atomicScope method . fmap Just

-- 原子句柄（Excu、Scoped.open／close）的统一出口。handler 交出的 list 与是否成功
-- 组成 RawOutput，只交给挂在该句柄下（可经一串 Pure）的 Context parser 解析并作为资产发布；没有挂接时直接丢弃。
-- 以它为 Input 的入口照常继续，不读取这份输出，注入的成败也不影响它。
-- 外层 Nothing 表示 handler 没有执行（复用的 scope 实例、重复 close），此时没有新的输出。
atomicScope
  :: (ContextStore environment m, MonadError (Failure cause) m)
  => String -> m (Maybe [String]) -> m [String]
atomicScope method body = do
  replayed <- replayedOutput method
  case replayed of
    -- 注入中的 parser（或它上方的 Pure）经 raw 调用挂接的句柄：回答本次输出，不重复执行。
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
      anchored <- anchoredContexts method
      when (maybe True (`notElem` map fst anchored) consumer) $
        forM_ anchored $ \(_, produce) -> injectOutput method raw produce
