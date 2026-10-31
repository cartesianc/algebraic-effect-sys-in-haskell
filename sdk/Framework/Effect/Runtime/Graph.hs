{-# LANGUAGE ExistentialQuantification #-}

-- 只读 Prototype 的运行实例：活动 chain 引用、绑定、scope 控制对象与既有求值锁。
-- 运行不解释图边；业务仍由已经装配的闭包执行。
module Framework.Effect.Runtime.Graph
  ( RuntimeGraph(..), PrototypeReference(..), ChainReference(..), Activation(..)
  , newRuntimeGraph, configureRuntimeScopes, newOrigin
  , beginActivation, endActivation, sourceLock, finishOrigin
  , publishAsset, readVisibleAsset
  ) where

import Control.Concurrent.MVar (MVar, modifyMVar, modifyMVar_, newMVar)
import Control.Exception (evaluate, uninterruptibleMask_)
import Data.IORef (IORef, atomicModifyIORef', newIORef, readIORef)
import Data.Maybe (fromMaybe)
import Framework.Effect.Contract (ContextFault(..))
import Framework.Effect.Graph (MethodRole(..))
import Framework.Effect.Runtime.Identity
import Framework.Effect.Scope
  ( Scopes, ScopeBinding, ScopeBindings, ScopeUser(..), configureScopeRelations )
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
  -- 发布时无归属的资产按 Origin 分组；后续认领保留同一引用，读取再检查共享 owner。
  -- 同一来源内只替换该入口自己的最新绑定，旧引用不会指向后来的 request 产物。
  , runtimeAssets :: IORef [((Origin, String), ScopeBinding environment cause)]
  , runtimeForcing :: MVar [((Origin, String), MVar ())]
  -- 有限 AST 每个挂载只启动一次；完成后只保留身份，供后继读取，不保留其 activation。
  , runtimeOrigins :: IORef [(NodeId, Origin)]
  , runtimeActivations :: MVar [(ActivationId, Activation environment cause)]
  , runtimeOriginSequence :: IORef Integer
  , runtimeActivationSequence :: IORef Integer
  }

newRuntimeGraph
  :: (Eq method, Show method)
  => Prototype method -> Scopes environment cause -> IO (RuntimeGraph environment cause)
newRuntimeGraph prototype scopes = RuntimeGraph (PrototypeReference prototype) scopes
  <$> newIORef [] <*> newMVar [] <*> newIORef [] <*> newMVar [] <*> newIORef 0 <*> newIORef 0

-- ScopeTree 的独立构建与校验仍在 Prototype；这里只把同一树的关系装入现有控制对象。
configureRuntimeScopes :: RuntimeGraph environment cause -> IO ()
configureRuntimeScopes graph = case runtimePrototype graph of
  PrototypeReference prototype -> configureScopeRelations (scopeRelations prototype) (runtimeScopes graph)

nextSequence :: IORef Integer -> IO Integer
nextSequence counter = atomicModifyIORef' counter (\previous -> (previous + 1, previous))

newOrigin :: RuntimeGraph environment cause -> NodeId -> IO Origin
newOrigin graph node = do
  origin <- Origin node <$> nextSequence (runtimeOriginSequence graph)
  atomicModifyIORef' (runtimeOrigins graph) $ \origins ->
    let updated = (node, origin) : filter ((/= node) . fst) origins
    in length updated `seq` (updated, ())
  pure origin

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

-- 只对本入口的缺值求值串行化；显式 request 不经此锁，不合并其他入口的生产。
sourceLock :: RuntimeGraph environment cause -> Origin -> String -> IO (MVar ())
sourceLock graph origin source = modifyMVar (runtimeForcing graph) $ \locks -> case lookup key locks of
  Just lock -> pure (locks, lock)
  Nothing -> do
    lock <- newMVar ()
    pure ((key, lock) : locks, lock)
  where key = (origin, source)

-- 入口、诊断及收尾均已退出；保留产物和轻量 Origin 索引，撤销不再使用的求值锁。
finishOrigin :: RuntimeGraph environment cause -> Origin -> IO ()
finishOrigin graph origin = uninterruptibleMask_ $
  modifyMVar_ (runtimeForcing graph) $ \locks -> do
    let remaining = filter ((/= origin) . fst . fst) locks
    _ <- evaluate (length remaining)
    pure remaining

publishAsset :: RuntimeGraph environment cause -> Origin -> String
             -> ScopeBinding environment cause -> IO ()
publishAsset graph origin source value = atomicModifyIORef' (runtimeAssets graph) $ \assets ->
  let key = (origin, source)
      updated = (key, value) : filter ((/= key) . fst) assets
  in length updated `seq` (updated, ())

-- 先按生成表定位来源入口，再读取本次实际发布；不按完成时序或全局最新值挑选。
-- 缺少发布只返回空值，由当前调用继续执行普通 request thunk。
readVisibleAsset :: RuntimeGraph environment cause -> Origin -> String
                 -> IO (Either ContextFault (Maybe (ScopeBinding environment cause)))
readVisibleAsset graph origin source = do
  origins <- readIORef (runtimeOrigins graph)
  assets <- readIORef (runtimeAssets graph)
  let selected = case sourcePlan (runtimePrototype graph) (originNode origin) source of
        FromOwnChain -> [origin]
        FromChains nodes -> [produced | node <- nodes, Just produced <- [lookup node origins]]
      candidates = [value | produced <- selected, Just value <- [lookup (produced, source) assets]]
  pure $ case candidates of
    [] -> Right Nothing
    [value] -> Right (Just value)
    _ -> Left (AmbiguousContextBinding source)

sourcePlan :: PrototypeReference -> NodeId -> String -> Source
sourcePlan (PrototypeReference prototype) node source = case
  [contract | effect <- protoEffects prototype, effectName effect == source
    , Just contract <- [effectProduces effect]] of
  [contract] -> fromMaybe FromOwnChain (lookup (ReadPoint node contract) (protoSources prototype))
  _ -> FromOwnChain
