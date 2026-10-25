{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE EmptyCase #-}
{-# LANGUAGE EmptyDataDeriving #-}
{-# LANGUAGE EmptyDataDecls #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE ExistentialQuantification #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE FunctionalDependencies #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE TypeFamilyDependencies #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE UndecidableInstances #-}
{-# LANGUAGE UndecidableSuperClasses #-}

-- Effect 契约与根能力；不包含执行载体或 workflow。
module Framework.Effect.Contract
  ( Effect(..), EffectKind(..), Root, Registered, Void
  , Failure(..), Output(..), failEffect
  , ContextStore(..), ContextFault(..), ScopeStore(..), ScopeFault(..), ScopeInput(..)
  ) where

import Control.Monad.Except (MonadError, throwError)
import Data.Kind (Constraint, Type)
import Data.Void (Void)
import Data.Typeable (Typeable, cast)

-- 关联 Typing 只保留类别；方法名由注册描述。
data EffectKind = PureKind | ExcuKind | ScopedKind | ContextKind deriving (Eq, Show)

data Root environment cause
newtype Registered (handler :: (Type -> Type) -> Constraint) parent = Registered parent

type family Inherited registration (m :: Type -> Type) :: Constraint where
  Inherited (Root environment cause) m =
    (ContextStore environment m, ScopeStore cause m, MonadError (Failure cause) m)
  Inherited (Registered handler parent) m = (Effect parent m, handler m)

class (Monad m, Inherited (Registration effect) m) => Effect effect m where
  type Registration effect :: Type
  type Typing effect :: EffectKind
  type Require effect :: Type
  -- 业务产物只归 Context；普通操作和 Scoped 方法均无产物。
  type Produce effect :: Type
  type Produce effect = ()
  -- SDK 生成的错误类型唯一确定所属 effect，使 raise 自动推导来源。
  type Error effect = (cause :: Type) | cause -> effect
  raise :: Error effect -> m value
  -- SDK 生成的统一调用入口；具体 effect 转交 Root，不改变业务调用者或提前执行上游。
  handler :: m value -> m value

-- 根 superclass 没有业务失败入口；空类型只供 SDK 根约束使用。
data NoError (effect :: Type) deriving Show

-- SDK 内部存储协议：Pure 保存纯状态，App 经 Reader 访问共享存储。
-- 用户的 Context 仍只实现生产方法；读取与发布回调由生成器连接。
class Monad m => ContextStore environment m | m -> environment where
  readContextBinding :: String -> (environment -> Maybe value)
                     -> m (Either ContextFault (Maybe value))
  publishContextBinding :: String -> (environment -> environment) -> m ()
  currentHandler :: m (Maybe String)
  enterHandler :: String -> m value -> m value
  enterContext :: String -> m value -> m value
  enterContext = enterHandler
  recordContextInput :: ScopeInput -> m ()
  recordContextInput _ = pure ()

data ContextFault = ContextNotInitialized | UndeclaredContextAccess String
  | AmbiguousContextBinding String
  deriving (Eq, Show)

-- 开启参数保留真实 ADT 值；类型相同且 Eq 相等才是同一输入。
-- 这是 SDK 观察记录，不是用户注册的 key 字段。
data ScopeInput = forall value. (Eq value, Typeable value) => ScopeInput String value

instance Eq ScopeInput where
  ScopeInput leftName left == ScopeInput rightName right =
    leftName == rightName && maybe False (left ==) (cast right)

-- SDK 内部生命周期能力；业务 instance 仍只实现 open／close。
data ScopeFault = ScopeNotOpen | ScopeIsClosed | ScopeReentry | ScopeInterrupted String
  | ScopeContextMissing String | ScopeContextMismatch String | ScopeInputsMissing [String] | ScopeInputAfterOpen String
  deriving (Eq, Show)

class Monad m => ScopeStore cause m | m -> cause where
  withScopeDependencies :: [String] -> m value -> m value
  openScope :: String -> (ScopeFault -> cause) -> m () -> m ()
  closeScope :: String -> (ScopeFault -> cause) -> m () -> m ()
  invalidateScope :: String -> Failure cause -> m ()

-- 链首提供 Monad、上下文存储与业务失败短路能力，没有全局业务 handle。
-- 环境类型由 facade 中的生成代码指定，不反向依赖业务模块。
instance (Monad m, ContextStore environment m, ScopeStore cause m, MonadError (Failure cause) m)
      => Effect (Root environment cause) m where
  type Registration (Root environment cause) = Root environment cause
  type Typing (Root environment cause) = 'PureKind
  type Require (Root environment cause) = Void
  type Error (Root environment cause) = NoError (Root environment cause)
  raise cause = case cause of {}
  -- middleware 尚未装配：保持原动作、产物和错误传播。
  handler = id

-- SDK 统一失败协议：来源、生成的错误分类和消息；传播时不改写或再次包装。
data Failure cause = Failure
  { origin :: String
  , detail :: cause
  , message :: String
  } deriving (Eq, Show)

-- 完成结果只在运行边界封装一次，不包含 Pending。
data Output cause value = Succ value | Failed (Failure cause)
  deriving (Eq, Show)

-- 生成的 Effect instance 统一实现 raise，绑定注册名并接入本次错误总和类型。
failEffect :: MonadError (Failure cause) m => String -> cause -> String -> m value
failEffect effectName cause description = throwError (Failure effectName cause description)
