{-# LANGUAGE ScopedTypeVariables #-}

-- 已交付的 Binding 在受控使用期间的保留根；不解释业务 ADT，也不修改 ownership。
-- 保留根 v1（2026-11-18）：与 scope 关闭预约共用协调锁，先登记接收者再推进游标。
-- 队列与后继的待用由 Graph 查询；这里仅登记执行中的交付、固定捕获和显式交接。
-- scope 的冻结快照不登记为根，避免实例通过自己的 cleanup 永久保留自己。
module Framework.Runtime.Retention
  ( Retentions, Retention, newRetentions, withRetention, keepBindings, keepBindingsLocked, detachedRetention
  , withRetentionLock, retainedBindings, clearRetentions
  ) where

import Control.Concurrent.MVar (MVar, withMVar)
import Control.Exception (SomeAsyncException, SomeException, fromException, mask, throwIO, try, uninterruptibleMask_)
import Data.IORef (IORef, newIORef, readIORef, writeIORef)
import Data.List (nubBy)
import Data.Unique (Unique, newUnique)
import Framework.Runtime.Binding (Binding(..))
import Framework.Runtime.Scope (ScopeBinding)

data Retentions environment cause = Retentions
  (MVar ()) (IORef [(Unique, [ScopeBinding environment cause])])
data Retention environment cause = Retention (Retentions environment cause) Unique

newRetentions :: MVar () -> IO (Retentions environment cause)
newRetentions coordinator = Retentions coordinator <$> newIORef []

withRetentionLock :: Retention environment cause -> IO value -> IO value
withRetentionLock (Retention (Retentions coordinator _) _) action =
  uninterruptibleMask_ (withMVar coordinator (const action))

-- 仅供同一协调锁内的查询调用，不另取锁，不求值资产内容。
retainedBindings :: Retentions environment cause -> IO [ScopeBinding environment cause]
retainedBindings (Retentions _ entries) = concatMap snd <$> readIORef entries

-- 没有资源时不进入协调锁：普通值本来就不登记。
keepBindings :: Retention environment cause -> [ScopeBinding environment cause] -> IO ()
keepBindings retention values
  | any bindingResource values = withRetentionLock retention (keepBindingsLocked retention values)
  | otherwise = pure ()

-- 不登记的执行（Untracked）用的保留根：它从未登记，交给它的资源会按“越过执行边界”报错，
-- 说明 gen 的回收无关判定与实际交付不符，而不是悄悄不保留。普通值照常是空操作。
detachedRetention :: Retentions environment cause -> IO (Retention environment cause)
detachedRetention registry = Retention registry <$> newUnique

-- 普通资产不会获得 scope ownership，不进入保留表；尚未认领的资源保留共享单元。
-- 调用者已经持有协调锁；用于“选中最新 Binding + 捕获”的同一临界区。
keepBindingsLocked :: Retention environment cause -> [ScopeBinding environment cause] -> IO ()
keepBindingsLocked retention values = case filter bindingResource values of
  [] -> pure ()
  resources -> register retention resources
  where
    register (Retention (Retentions _ entries) identifier) resources = do
      current <- readIORef entries
      case lookup identifier current of
        Nothing -> ioError (userError "SDK: retaining a binding after its execution boundary ended")
        Just previous -> do
          let kept = nubBy (\left right -> bindingOwnership left == bindingOwnership right) (resources ++ previous)
              updated = (identifier, kept) : filter ((/= identifier) . fst) current
          length kept `seq` length updated `seq` writeIORef entries updated

-- 撤销先于 scope 回收，业务 IO 和 close 都不在保留锁内执行。
-- 原操作的取消优先；收尾收到的取消也传播，不把已撤销当成仍在运行。
withRetention :: Retentions environment cause -> ([ScopeBinding environment cause] -> IO ())
              -> (Retention environment cause -> IO value) -> IO value
withRetention registry@(Retentions _ entries) collect action = mask $ \restore -> do
  identifier <- newUnique
  let retention = Retention registry identifier
  withRetentionLock retention $ do
    current <- readIORef entries
    writeIORef entries ((identifier, []) : current)
  outcome <- try (restore (action retention))
  released <- withRetentionLock retention $ do
    current <- readIORef entries
    let values = maybe [] id (lookup identifier current)
        remaining = filter ((/= identifier) . fst) current
    length remaining `seq` writeIORef entries remaining
    pure values
  retired <- try (restore (collect released))
  case (outcome, retired) of
    (Left (exception :: SomeException), _)
      | Just (_ :: SomeAsyncException) <- fromException exception -> throwIO exception
    (_, Left (exception :: SomeException))
      | Just (_ :: SomeAsyncException) <- fromException exception -> throwIO exception
    (Left exception, _) -> throwIO exception
    (_, Left exception) -> throwIO exception
    (Right value, Right ()) -> pure value

-- 全部受控工作已退出后清空。队列中的未交付义务在运行退出时一并放弃。
clearRetentions :: Retentions environment cause -> IO ()
clearRetentions (Retentions coordinator entries) = uninterruptibleMask_ $
  withMVar coordinator (const (writeIORef entries []))
