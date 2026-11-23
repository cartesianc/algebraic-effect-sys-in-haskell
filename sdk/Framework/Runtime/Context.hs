{-# LANGUAGE FlexibleContexts #-}

-- Context 的读取与成功发布；存储由运行载体提供。require 是“取值 · 未就绪时等待”：值在本次调用的捕获或运行级
-- 最新值里就继续；还没有、但别的 parallel 分支仍可能发布时，只挂起这一次调用，发布后从读取点继续；
-- 没有这样的分支时立即按缺值报错。哪些资产有来源由 gen 在生成期检查，各分支可能发布什么由 gen 写在闭包上。
module Framework.Runtime.Context
  ( ContextFault(..), readContext, callContext, runOnce, unlessPerformed
  , chooseCase, atomicHandle, atomicScope, readStreamContext, readStreamHistory, requestStreamContext
  ) where

import Framework.Runtime.Protocol
  (ContextStore(..), ContextFault(..), failEffect)
import Framework.Language.Handler (Failure(..), Flow(..))
import Control.Monad (forM_, when)
import Control.Monad.Except (MonadError, catchError)
import Framework.Prototype.Slot (Slot(..))

-- require：本次调用已捕获的值优先，其次是运行级最新值；都没有时按 awaiting 等待或立即报 ContextNotInitialized。
-- 读取本身不生产。
readContext
  :: (ContextStore environment m, MonadError (Failure cause) m)
  => Slot -> (ContextFault -> cause) -> (environment -> Maybe value) -> m value
readContext contextName wrap select = do
  bound <- awaiting [contextName] $ do
    resolved <- readContextBinding contextName select
    either (\problem -> failEffect (slotName contextName) (wrap problem) (show problem)) pure resolved
  case bound of
    Just value -> do
      recordContextInput contextName
      pure value
    Nothing -> failEffect (slotName contextName) (wrap ContextNotInitialized) (show ContextNotInitialized)

-- 缺值时的等待：先取得等待动作（变化信号），再查值；有值就返回，没有值且别的分支仍可能发布时
-- 阻塞到下一次发布或分支退出，再从头查一次；没有这样的分支时返回 Nothing。只挂起这一次调用。
awaiting :: ContextStore environment m => [Slot] -> m (Maybe value) -> m (Maybe value)
awaiting sources look = do
  pending <- awaitContext sources
  found <- look
  case (found, pending) of
    (Just value, _) -> pure (Just value)
    (Nothing, Just block) -> block >> awaiting sources look
    (Nothing, Nothing) -> pure Nothing

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
-- 输出联立和来源步骤调用它；require 读取走 readContext，不经这里。
-- 同一次调用中已经发布过时不再生产，返回本次捕获的那份发布（发布即捕获，捕获优先于其他调用的发布）。
-- 订阅回调把交付的资产预先记为本次已发布，订阅方入口里的 requests 因此直接读这条交付。
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
-- requests 的生产链：它生产的资产在本次执行里都已记为发布时不再执行。订阅回调把交付的资产预先记为发布，
-- 所以回调里对交付资产的 requests 读这条交付，不重新执行生产链。
unlessPerformed :: ContextStore environment m => [Slot] -> m value -> m ()
unlessPerformed produced action = do
  recalled <- mapM recallOutput produced
  if all (maybe False (const True)) recalled then pure () else () <$ action

runOnce :: ContextStore environment m => Slot -> m [String] -> m [String]
runOnce selected body = do
  recalled <- recallOutput selected
  case recalled of
    Just output -> pure output
    Nothing -> do
      output <- body
      rememberOutput selected output
      pure output

-- alternative 的选择读取（option）：执行一次共同的 Excu，按候选的声明顺序把同一份输出交给各自的判定 Context；
-- 第一个解析成功的候选胜出，它的发布被本次调用捕获，交给选中的候选。判定 parser 的 raise 只表示这一支没有值，
-- 不是失败。执行 Excu 时以首个判定 Context 为调用者。全部拒绝时按声明顺序检查已有绑定（此前的发布），
-- 都没有而别的分支仍可能发布其中之一时等待，否则按缺值报 ContextNotInitialized。
chooseCase
  :: (ContextStore environment m, MonadError (Failure cause) m)
  => String -> (ContextFault -> cause) -> m [String] -> [(Slot, m ())] -> m String
chooseCase _ wrap upstream cases = do
  _ <- maybe id enterHandler (fst <$> safeHead cases) upstream
  attempt cases
  where
    safeHead (first : _) = Just first
    safeHead [] = Nothing
    attempt [] = awaiting (map fst cases) (firstBound cases) >>= maybe notInitialized (pure . slotName)
    attempt ((name, produce) : rest) = do
      outcome <- (True <$ attemptOutput produce) `catchError` (\_ -> pure False)
      if outcome then pure (slotName name) else attempt rest
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

-- streamT 的生成入口：本次回调交付的值；没有交付时读运行级最新值（例如 lifelong 之后的后继）。
-- 都没有时与 require 一样：别的分支仍可能发布就等待，否则报缺值。不启动来源。
readStreamContext
  :: (ContextStore environment m, MonadError (Failure cause) m)
  => Slot -> (ContextFault -> cause) -> (environment -> Maybe value) -> m value
readStreamContext contextName wrap select = do
  captured <- awaiting [contextName] (readContextValue contextName select)
  value <- maybe (failEffect (slotName contextName) (wrap ContextNotInitialized)
    (slotName contextName ++ ": nothing delivered or published yet")) pure captured
  recordContextInput contextName
  pure value

-- 持续资产 requests 的生成入口：在方法体之前执行。本次调用已有交付（订阅回调）时不再取得；
-- 否则这是 lifelong 之外的静态读取：同步运行该资产的来源直到结束（同一次运行只运行一次），
-- 把整段历史固定给本次调用，之后的 require 读最后一条，stream 读整段。
requestStreamContext
  :: (ContextStore environment m, MonadError (Failure cause) m)
  => Slot -> (ContextFault -> cause) -> (environment -> Maybe value) -> m ()
requestStreamContext contextName wrap select = do
  delivered <- requestContextValue contextName select
  maybe (failEffect (slotName contextName) (wrap ContextNotInitialized)
    (slotName contextName ++ ": the stream ended without publishing"))
    (const (pure ())) delivered
  recordContextInput contextName

-- stream @T 的生成入口：x 是本次值，xs 是更早的发布（最新在前），都已发布；读取不驱动来源。
readStreamHistory
  :: (ContextStore environment m, MonadError (Failure cause) m)
  => Slot -> (ContextFault -> cause) -> (environment -> Maybe value) -> m (Flow value)
readStreamHistory contextName wrap select = do
  captured <- awaiting [contextName] (readContextHistory contextName select)
  values <- maybe (failEffect (slotName contextName) (wrap ContextNotInitialized)
    (slotName contextName ++ ": nothing delivered or published yet")) pure captured
  recordContextInput contextName
  pure (foldr (:>) Done values)

-- Excu 的生成入口：每次调用都执行。
atomicHandle
  :: (ContextStore environment m, MonadError (Failure cause) m)
  => Slot -> [(Slot, m ())] -> m [String] -> m [String]
atomicHandle anchor branches = atomicScope anchor branches . fmap Just

-- 原子句柄（Excu、Scoped.open）的统一出口，也是输出联立的执行闭包：句柄成功交出 list 后，先记为本次输出，
-- 再依次执行 gen 写在入口上的生产分支（挂在句柄下、可经一串 Pure 的 Context，普通与持续都在内）。
-- 分支的 rawinput 经句柄入口读回这份记录，不重复执行句柄；分支失败沿原链传播。
-- 拉取该句柄的那个 Context 自己发布，不再执行它（经一串 Pure 拉取时调用者仍是它）。
-- 外层 Nothing 表示 handler 没有执行（复用的 scope 实例），没有新的输出，也不执行分支。
-- 失败的句柄不交出输出，原失败照常传播。诊断与收尾期间不执行分支。
atomicScope
  :: (ContextStore environment m, MonadError (Failure cause) m)
  => Slot -> [(Slot, m ())] -> m (Maybe [String]) -> m [String]
atomicScope anchor branches body = do
  consumer <- currentHandler
  outcome <- body
  case outcome of
    Nothing -> pure []
    Just output -> do
      rememberOutput anchor output
      linking <- linkingAllowed
      when linking $
        forM_ [produce | (owner, produce) <- branches, consumer /= Just owner] id
      pure output
