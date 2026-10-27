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
  , Failure(..), Output(..), failEffect, ErrorHandler(..), ErrorReport(..), ErrorStore(..), runErrorHandler
  , ContextStore(..), ContextFault(..), ScopeStore(..), ScopeFault(..), ScopeInput(..), ScopeInputAccess(..)
  ) where

import Control.Monad.Except (MonadError, catchError, throwError)
import Data.Kind (Constraint, Type)
import Data.Void (Void)
import Data.Typeable (Typeable, cast)

-- 关联 Typing 只保留类别；方法名由注册描述。
data EffectKind = PureKind | ExcuKind | ScopedKind | ErrorKind | ContextKind deriving (Eq, Show)

data Root environment cause
newtype Registered (handler :: (Type -> Type) -> Constraint) parent = Registered parent

type family Inherited registration (m :: Type -> Type) :: Constraint where
  Inherited (Root environment cause) m =
    (ContextStore environment m, ScopeStore cause m, ErrorStore cause m, MonadError (Failure cause) m)
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
  -- 资源生产与绑定发布作为一次交接；纯载体无需额外保护。
  protectContextBinding :: String -> m value -> m value
  protectContextBinding _ = id
  currentHandler :: m (Maybe String)
  enterHandler :: String -> m value -> m value
  enterContext :: String -> m value -> m value
  enterContext = enterHandler
  recordContextInput :: ScopeInputAccess -> ScopeInput -> m ()
  recordContextInput _ _ = pure ()
  -- require 在 state 中取不到值时，按需求值一次 request 表达式并写回 state。
  -- 返回 Nothing 表示当前不允许转去生产（诊断、收尾，或该来源是 scope 资源）。
  forceContext :: String -> m value -> m (Maybe value)
  forceContext _ _ = pure Nothing
  -- 本次生产被 scope 开启参数观察时的取值模式；按需求值的 require 仍按 require 处理。
  productionAccess :: m ScopeInputAccess
  productionAccess = pure RequestedInput

data ContextFault = ContextNotInitialized | UndeclaredContextAccess String
  | AmbiguousContextBinding String
  deriving (Eq, Show)

-- 开启参数保留真实 ADT 值；类型相同且 Eq 相等才是同一输入。
-- 这是 SDK 观察记录，不是用户注册的 key 字段。
data ScopeInput = forall value. (Eq value, Typeable value) => ScopeInput String value

data ScopeInputAccess = RequestedInput | RequiredInput deriving (Eq, Show)

instance Eq ScopeInput where
  ScopeInput leftName left == ScopeInput rightName right =
    leftName == rightName && maybe False (left ==) (cast right)

-- SDK 内部生命周期能力；业务 instance 仍只实现 open／close。
data ScopeFault = ScopeNotOpen | ScopeIsClosed | ScopeReentry | ScopeInterrupted String
  | ScopeContextMissing String | ScopeContextMismatch String | ScopeInputsMissing [String] | ScopeInputAfterOpen String
  | ScopeCleanupInterrupted String | ScopeCleanupInProgress | ScopeInUse
  deriving (Eq, Show)

class Monad m => ScopeStore cause m | m -> cause where
  withScopeDependencies :: [String] -> m value -> m value
  openScope :: String -> (ScopeFault -> cause) -> m () -> m ()
  closeScope :: String -> (ScopeFault -> cause) -> m () -> m ()
  invalidateScope :: String -> Failure cause -> m ()

-- 链首提供 Monad、上下文存储与业务失败短路能力，没有全局业务 handle。
-- 环境类型由 facade 中的生成代码指定，不反向依赖业务模块。
instance (Monad m, ContextStore environment m, ScopeStore cause m, ErrorStore cause m, MonadError (Failure cause) m)
      => Effect (Root environment cause) m where
  type Registration (Root environment cause) = Root environment cause
  type Typing (Root environment cause) = 'PureKind
  type Require (Root environment cause) = Void
  type Error (Root environment cause) = NoError (Root environment cause)
  raise cause = case cause of {}
  -- 方法入口统一捕获；业务 instance 不需要手写 catch 或 super 前缀。
  handler = handleFailure

-- 回调由生成区装配；不让 Root 的 superclass 反向依赖业务 Error 类。
-- 匹配函数由注册的 handles 生成，只读取 Failure 的来源与分类，不解释业务消息。
data ErrorHandler cause m = ErrorHandler String (Failure cause -> Bool) (Maybe (m ())) (Maybe (m ()))

-- 回调表的键是推导出的关联 scope；Nothing 表示不定位 scope 实例的全局处置。
class Monad m => ErrorStore cause m | m -> cause where
  withErrorHandlers :: [(Maybe String, ErrorHandler cause m)] -> m value -> m value
  withErrorPath :: [String] -> m value -> m value
  handleFailure :: m value -> m value
  caughtFailure :: m (Maybe (Failure cause))

data ErrorReport cause = ErrorReport
  { reportScope :: Maybe String
  , reportEffect :: String
  , detectResult :: Maybe (Output cause ())
  , resolveResult :: Maybe (Output cause ())
  } deriving (Eq, Show)

-- 类型匹配已完成粗定位；detect 只作可选的值级细化：未注册 detect 时直接 resolve，
-- detect 返回 Succ 才 resolve，Failed 表示不归此处。
-- 每次检测/处置的失败只进入报告，不能覆盖原始故障或递归激活自身。
runErrorHandler :: MonadError (Failure cause) m
                => Maybe String -> ErrorHandler cause m -> m (ErrorReport cause)
runErrorHandler selected (ErrorHandler name _ detecting resolving) = do
  detection <- traverse attempt detecting
  resolution <- case detection of
    Nothing -> traverse attempt resolving
    Just (Succ ()) -> traverse attempt resolving
    _ -> pure Nothing
  pure (ErrorReport selected name detection resolution)
  where
    attempt action = (Succ <$> action) `catchError` (pure . Failed)

-- SDK 统一失败协议：来源、生成的错误分类和消息；传播时不改写或再次包装。
data Failure cause = Failure
  { origin :: String
  , detail :: cause
  , message :: String
  , scopeTrace :: [String]
  -- 生命周期失败保存实际实例身份；Nothing 明确表示本次尚未选出实例。
  , scopeTargets :: [(String, Maybe Int)]
  , errorHandling :: Maybe [ErrorReport cause]
  -- 收尾故障附在原失败之后，不覆盖其来源、分类或诊断结果。
  , cleanupFailures :: [Failure cause]
  } deriving (Eq, Show)

-- 完成结果只在运行边界封装一次，不包含 Pending。
data Output cause value = Succ value | Failed (Failure cause)
  deriving (Eq, Show)

-- 生成的 Effect instance 统一实现 raise，绑定注册名并接入本次错误总和类型。
failEffect :: MonadError (Failure cause) m => String -> cause -> String -> m value
failEffect effectName cause description = throwError (Failure effectName cause description [] [] Nothing [])
