{-# LANGUAGE FlexibleContexts #-}

-- Context 的读取与成功发布；存储由运行载体提供。
module Framework.Runtime.Context
  ( ContextFault(..), readContext, callContext, runOnce
  , chooseCase, atomicHandle, atomicScope, readStreamContext, readStreamHistory, requestStreamContext
  ) where

import Framework.Runtime.Protocol
  (ContextStore(..), ContextFault(..), RawOutput(..), failEffect)
import Framework.Language.Handler (Failure(..), Flow(..))
import Control.Monad (forM_, when)
import Control.Monad.Except (MonadError, catchError, throwError)
import Framework.Prototype.Slot (Slot(..))

-- require 是一次读取：值只来自 requests 驱动的生产或 Stream 会话，读取本身不生产。
-- 已有值时直接返回；尚无值时等发布或节点进度变化，再读取同一份运行级最新值。
-- 只在已证明合法生产机会耗尽时结束等待；无法证明的路径继续等待。
-- 载体在诊断、收尾或 scope 资源时不等待，缺值按 ContextNotInitialized 报出。
readContext
  :: (ContextStore environment m, MonadError (Failure cause) m)
  => Slot -> (ContextFault -> cause) -> (environment -> Maybe value) -> m value
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
      either (\problem -> failEffect (slotName contextName) (wrap problem) (show problem)) pure resolved
    observed value = do
      recordContextInput contextName
      pure value
    notInitialized = failEffect (slotName contextName) (wrap ContextNotInitialized) (show ContextNotInitialized)

-- 同一个成功值先交给绑定回调再返回；生产失败不会触发回调或再次执行生产。
requestContext
  :: ContextStore environment m
  => Slot -> (value -> environment -> environment) -> m value -> m value
requestContext selected synchronize produce = enterRequest selected $
  protectContextBinding selected $ do
    value <- produce
    publishContextBinding selected (synchronize value)
    pure value

-- getT 的生成入口：生产并发布。只有 requests 驱动、alternative 的选择读取、
-- 挂接注入和会话步骤调用它；require 读取走 readContext，不经这里。
-- 同一次调用中已经发布过时不再生产，返回本次捕获的那份发布（发布即捕获，捕获优先于其他调用的发布）。
callContext
  :: (ContextStore environment m, MonadError (Failure cause) m)
  => Slot -> (value -> environment -> environment) -> (environment -> Maybe value)
  -> m value -> m value
callContext selected synchronize select produce = do
  produced <- recallOutput selected
  captured <- case produced of
    Just _ -> either (const Nothing) id <$> readContextBinding selected select
    Nothing -> pure Nothing
  value <- case captured of
    Just value -> pure value
    Nothing -> do
      value <- requestContext selected synchronize (enterContext selected produce)
      rememberOutput selected []
      pure value
  recordContextInput selected
  pure value

-- Excu、Scoped.open 与 Pure 入口的最外层：同一次调用中再次到达同一 effect 时返回它本次的 list，
-- 不再执行（包括它的前驱）。rawinput 因此读到锚点的同一次输出，n 条生产分支共用一次执行。
-- 失败不记录：失败照常沿原链传播。
runOnce :: ContextStore environment m => Slot -> m [String] -> m [String]
runOnce selected body = do
  recalled <- recallOutput selected
  case recalled of
    Just output -> pure output
    Nothing -> do
      output <- body
      rememberOutput selected output
      pure output

-- alternative 的选择读取（option）：race 等待某一支有值，再走那一支。
-- 先执行一次共同的 Excu，按候选的声明顺序把同一份输出交给各自的判定 Context；第一个解析成功的
-- 候选胜出，它的发布被本次调用捕获，交给选中的候选。执行 Excu 时以首个判定 Context 为调用者，
-- 挂接注入因此不重复执行这些 parser。判定 parser 的 raise 只表示这一支没有值，不是失败。
-- 都没有值时按 require 的等待协议等待任一判定 Context 发布（gen 已为选择读取登记静态来源），
-- 醒来后按声明顺序重读；已证明生产机会耗尽仍没有值时，按普通缺值报 ContextNotInitialized。
chooseCase
  :: (ContextStore environment m, MonadError (Failure cause) m)
  => String -> (ContextFault -> cause) -> m [String] -> [(Slot, m ())] -> m String
chooseCase method wrap upstream cases = do
  output <- maybe id enterHandler (fst <$> safeHead cases) upstream
  attempt output cases
  where
    safeHead (first : _) = Just first
    safeHead [] = Nothing
    attempt _ [] = awaitCase
    attempt output ((name, produce) : rest) = do
      outcome <- (True <$ attemptOutput method (RawOutput True output) produce) `catchError` (\_ -> pure False)
      if outcome then pure (slotName name) else attempt output rest
    -- 先取等待动作再读：读取之后、开始等待之前的发布也会唤醒这次等待。
    awaitCase = do
      waits <- mapM (awaitContext . fst) cases
      bound <- firstBound cases
      case bound of
        Just name -> pure (slotName name)
        Nothing -> do
          changed <- anyChanged [wait | Just wait <- waits]
          if changed then awaitCase else firstBound cases >>= maybe notInitialized (pure . slotName)
    -- 共享信号由任一发布或节点进度唤醒；只要有一个来源仍可能发布，就等到变化后重读全部候选。
    anyChanged [] = pure False
    anyChanged (wait : rest) = wait >>= \changed -> if changed then pure True else anyChanged rest
    firstBound [] = pure Nothing
    firstBound ((name, _) : rest) = do
      resolved <- readContextBinding name (const (Just ()))
      case resolved of
        Left problem -> failEffect (slotName name) (wrap problem) (show problem)
        Right (Just ()) -> Just name <$ recordContextInput name
        Right Nothing -> firstBound rest
    notInitialized = case cases of
      (name, _) : _ -> failEffect (slotName name) (wrap ContextNotInitialized) (show ContextNotInitialized)
      [] -> error "SDK: an alternative without candidates; regenerate the program"

-- streamT 的生成入口：从本次固定交付或有限读取的捕获值取得业务表示类型。
-- 是否继续被增量驱动由组合计划决定；这里执行一次读取，不包装或解释业务数据。
readStreamContext
  :: (ContextStore environment m, MonadError (Failure cause) m)
  => Slot -> (ContextFault -> cause) -> (environment -> Maybe value) -> m value
readStreamContext contextName wrap select = do
  captured <- readContextValue contextName select
  value <- case captured of
    Just value -> pure value
    Nothing -> do
      delivered <- awaitContextValue contextName select
      maybe (failEffect (slotName contextName) (wrap ContextNotInitialized)
        (slotName contextName ++ ": no delivery here (no started stream session can deliver; requests it to start one,"
          ++ " or the stream ended without publishing)")) pure delivered
  recordContextInput contextName
  pure value

-- 持续资产 requests 的生成入口：在方法体之前执行。本次调用已有固定交付（lifelong 交付或此前的取得）时不再取得；
-- 否则启动或加入该资产的会话，取当前一条固定给本次调用，之后的 requires 读它。
requestStreamContext
  :: (ContextStore environment m, MonadError (Failure cause) m)
  => Slot -> (ContextFault -> cause) -> (environment -> Maybe value) -> m ()
requestStreamContext contextName wrap select = do
  captured <- readContextValue contextName select
  case captured of
    Just _ -> pure ()
    Nothing -> do
      delivered <- requestContextValue contextName select
      maybe (failEffect (slotName contextName) (wrap ContextNotInitialized)
        (slotName contextName ++ ": no delivery (the session cannot start here, or the stream ended without publishing)"))
        (const (pure ())) delivered
  recordContextInput contextName

-- stream @T 的生成入口：与 readStreamContext 领取同一次交付，返回 x :> xs。
-- x 是本次值，xs 是同一会话更早的发布（最新在前），都已发布；读取不等待后续发布，也不驱动来源。
readStreamHistory
  :: (ContextStore environment m, MonadError (Failure cause) m)
  => Slot -> (ContextFault -> cause) -> (environment -> Maybe value) -> m (Flow value)
readStreamHistory contextName wrap select = do
  captured <- readContextHistory contextName select
  values <- case captured of
    Just values -> pure values
    Nothing -> do
      delivered <- awaitContextHistory contextName select
      maybe (failEffect (slotName contextName) (wrap ContextNotInitialized)
        (slotName contextName ++ ": no delivery here (no started stream session can deliver; requests it to start one,"
          ++ " or the stream ended without publishing)")) pure delivered
  recordContextInput contextName
  pure (foldr (:>) Done values)

-- Excu 的生成入口：每次调用都执行。
atomicHandle
  :: (ContextStore environment m, MonadError (Failure cause) m)
  => String -> [(Slot, m ())] -> [(Slot, m ())] -> m [String] -> m [String]
atomicHandle method anchored continuous = atomicScope method anchored continuous . fmap Just

-- 原子句柄（Excu、Scoped.open／close）的统一出口。handler 交出的 list 与是否成功组成 RawOutput。
-- 输出联立：挂在句柄下（可经一串 Pure）的普通 Context 每次都解析这份输出并发布到最新值；
-- 挂在句柄下的持续 Context 在本次执行位置是原型指定的发布位置时取得这份输出。没有挂接时直接丢弃。
-- 两种注入的解析失败都沿原链传播。以它为 Input 的入口不读取这份输出。
-- 外层 Nothing 表示 handler 没有执行（复用的 scope 实例、重复 close），此时没有新的输出。
-- anchored 与 continuous 由 gen 写在入口上，各为 (Context 编号, 生产入口)。
atomicScope
  :: (ContextStore environment m, MonadError (Failure cause) m)
  => String -> [(Slot, m ())] -> [(Slot, m ())] -> m (Maybe [String]) -> m [String]
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
    -- Context 自己拉取该句柄时由它自己的入口发布，不再注入它；同一句柄下的其他普通分支照常解析。
    -- 中间的 Pure 入口不改变调用者，所以经一串 Pure 拉取时仍认得出是这个 Context。
    deliver consumer raw = when (succeeded raw) $ do
      forM_ [entry | entry@(owner, _) <- anchored, consumer /= Just owner] $ \(_, produce) ->
        injectOutput method raw produce
      active <- activeStreamContexts continuous
      when (maybe True (`notElem` map fst active) consumer) $
        forM_ active $ \(_, produce) -> injectStreamOutput method raw produce
