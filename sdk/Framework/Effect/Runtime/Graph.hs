{-# LANGUAGE ExistentialQuantification #-}

-- 只读 Prototype 的运行实例：活动 chain 引用、绑定、scope 控制对象与既有求值锁。
-- 运行不解释图边；业务仍由已经装配的闭包执行。
module Framework.Effect.Runtime.Graph
  ( RuntimeGraph(..), PrototypeReference(..), ChainReference(..), Activation(..)
  , newRuntimeGraph, configureRuntimeScopes, newOrigin
  , beginActivation, endActivation, sourceLock
  ) where

import Control.Concurrent.MVar (MVar, modifyMVar, modifyMVar_, newMVar)
import Control.Exception (evaluate, uninterruptibleMask_)
import Data.IORef (IORef, atomicModifyIORef', newIORef)
import Framework.Effect.Graph (MethodRole(..))
import Framework.Effect.Runtime.Identity
import Framework.Effect.Scope
  ( Scopes, ScopeBindings, ScopeUser(..), configureScopeRelations )
import Framework.Prototype
import Framework.Workflow.Structure (scopeRelations)

-- 保存生成区真正的 MethodGen 身份及同一份 Prototype；不复制成字符串图。
data PrototypeReference = forall method. (Eq method, Show method) =>
  PrototypeReference (Prototype method)

data ChainReference = forall method. Show method =>
  ChainReference (ChainDefinition method)

instance Show ChainReference where
  showsPrec precedence (ChainReference definition) = showsPrec precedence definition

data Activation environment cause = Activation
  { activationId :: ActivationId
  , activationParent :: Maybe ActivationId
  , activationBoot :: Boot
  , activationExecution :: Execution
  , activationDefinition :: ChainReference
  , activationBindings :: IORef (ScopeBindings environment cause)
  , activationUser :: ScopeUser environment cause
  }

data RuntimeGraph environment cause = RuntimeGraph
  { runtimePrototype :: PrototypeReference
  , runtimeScopes :: Scopes environment cause
  -- 本轮只统一存储位置。来源仍按现有注册名读取，求值锁仍按现有来源分配。
  -- Origin 与 activation 登记为后续来源路由提供身份，不提前启用 Stage 2。
  , runtimeAssets :: IORef (ScopeBindings environment cause)
  , runtimeForcing :: MVar [(String, MVar ())]
  , runtimeActivations :: MVar [(ActivationId, Activation environment cause)]
  , runtimeOriginSequence :: IORef Integer
  , runtimeActivationSequence :: IORef Integer
  }

newRuntimeGraph
  :: (Eq method, Show method)
  => Prototype method -> Scopes environment cause -> IO (RuntimeGraph environment cause)
newRuntimeGraph prototype scopes = RuntimeGraph (PrototypeReference prototype) scopes
  <$> newIORef [] <*> newMVar [] <*> newMVar [] <*> newIORef 0 <*> newIORef 0

-- ScopeTree 的独立构建与校验仍在 Prototype；这里只把同一树的关系装入现有控制对象。
configureRuntimeScopes :: RuntimeGraph environment cause -> IO ()
configureRuntimeScopes graph = case runtimePrototype graph of
  PrototypeReference prototype -> configureScopeRelations (scopeRelations prototype) (runtimeScopes graph)

nextSequence :: IORef Integer -> IO Integer
nextSequence counter = atomicModifyIORef' counter (\previous -> (previous + 1, previous))

newOrigin :: RuntimeGraph environment cause -> NodeId -> IO Origin
newOrigin graph node = Origin node <$> nextSequence (runtimeOriginSequence graph)

-- 活动记录与 App 共享同一个绑定 IORef 和入口使用登记；ctx 不另建 scope 使用者。
-- parent 只表达启动关系，不参与 ScopeTree 父边或资产可见性推导。
beginActivation
  :: RuntimeGraph environment cause -> Maybe ActivationId -> Execution -> Boot
  -> IORef (ScopeBindings environment cause) -> ScopeUser environment cause
  -> IO (Activation environment cause)
beginActivation graph parent execution boot bindings user = do
  definition <- either (ioError . userError) pure (resolveDefinition (runtimePrototype graph) boot)
  identifier <- ActivationId <$> nextSequence (runtimeActivationSequence graph)
  let activation = Activation identifier parent boot execution definition bindings user
  -- 只在短临界区更新内存引用；取消期间也不留下半登记的活动节点。
  uninterruptibleMask_ $ modifyMVar_ (runtimeActivations graph) $ \active -> case parent of
    Just predecessor | predecessor `notElem` map fst active ->
      ioError (userError "Runtime activation has no active parent")
    _ -> pure ((identifier, activation) : active)
  pure activation

-- 退出即撤销活动记录；不把完成链积累为无限的调用历史。
endActivation :: RuntimeGraph environment cause -> ActivationId -> IO ()
endActivation graph identifier = uninterruptibleMask_ $
  modifyMVar_ (runtimeActivations graph) $ \active -> do
    let remaining = filter ((/= identifier) . fst) active
    -- 只强制表的脊，避免 filter thunk 持续引用已经结束的 frame；不求值业务绑定。
    _ <- evaluate (length remaining)
    pure remaining

resolveDefinition :: PrototypeReference -> Boot -> Either String ChainReference
resolveDefinition (PrototypeReference prototype) boot = do
  entry <- case boot of
    TargetedBoot node -> either (Left . show) (Right . chainEntry) (lookupChain prototype node)
    RequestBoot source -> case
      [method | effect <- protoEffects prototype, effectName effect == source
        , (ContextRequest, method) <- effectMethods effect] of
      [method] -> Right method
      _ -> Left ("Runtime request has no Context production entry: " ++ source)
  case [definition | definition <- protoChainDefinitions prototype, definitionEntry definition == entry] of
    [definition] -> Right (ChainReference definition)
    _ -> Left "Runtime activation has no unique static chain definition"

-- 保留来源级单次求值锁的现有行为。本轮不按 Origin 分组，不合并显式 request。
sourceLock :: RuntimeGraph environment cause -> String -> IO (MVar ())
sourceLock graph source = modifyMVar (runtimeForcing graph) $ \locks -> case lookup source locks of
  Just lock -> pure (locks, lock)
  Nothing -> do
    lock <- newMVar ()
    pure ((source, lock) : locks, lock)
