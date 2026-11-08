{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveFunctor #-}
{-# LANGUAGE DeriveGeneric #-}

-- 静态方法引用与 scope 开启顺序的纯数据，是 Prototype 的一部分；不保存执行闭包或活资源。
-- 构图算法在 Framework.Gen.Build.Graph。
module Framework.Prototype.Graph
  ( MethodRole(..), MethodShape(..), MethodDefinition(..)
  , GraphError(..), EffectGraph(..), ScopeNode(..), ScopeTree(..)
  ) where

import Control.DeepSeq (NFData)
import GHC.Generics (Generic)

-- 方法身份由生成的枚举提供；显示名称不参与身份判断。
data MethodRole
  = HandlerMethod
  | ContextRequest
  | ContextRequire
  | ScopeOpen
  | ScopeClose
  | ErrorDetect
  | ErrorResolve
  -- StreamHandler 取得单步原始输入；ContextStream 标记挂在 Stream 下的 getT 解析器。
  -- 解析器仍调用 Stream 方法；运行包装用本次原始输入回答，不再获取一次。
  | StreamHandler
  | ContextStream
  deriving (Eq, Ord, Show, Read, Generic, NFData)

data MethodShape method
  = Empty
  | Call method
  | Sequence [MethodShape method]
  | Choice [MethodShape method]
  | Recover (MethodShape method) (MethodShape method)
  deriving (Eq, Show, Read, Functor, Generic, NFData)

data MethodDefinition method = MethodDefinition
  { methodIdentity :: method
  -- 同一 effect 的方法共用其首个注册入口身份，不增加用户 key。
  , methodEffect :: method
  , methodRole :: MethodRole
  , methodBody :: MethodShape method
  } deriving (Eq, Show, Read, Functor, Generic, NFData)

data GraphError method
  = DuplicateMethod method
  | UnknownMethod method
  | RecursiveMethod method
  | UnknownScope method
  | CyclicScopeRelations [method]
  deriving (Eq, Show, Read, Functor, Generic, NFData)

data EffectGraph method = EffectGraph
  { graphMethods :: [MethodDefinition method]
  , graphRoots :: [method]
  , graphReferences :: [(method, method)]
  , graphScopes :: [method]
  , graphScopePaths :: [[method]]
  , graphRootPaths :: [(method, [[method]])]
  , graphScopeOrder :: [(method, method)]
  } deriving (Eq, Show, Read, Functor, Generic, NFData)

-- scope 的静态身份就是对应 open 方法的身份；共享节点只保存引用。
data ScopeNode method = ScopeNode
  { scopeIdentity :: method
  , scopeParents :: [method]
  , scopeChildren :: [method]
  } deriving (Eq, Show, Read, Functor, Generic, NFData)

data ScopeTree method = ScopeTree
  { scopeRoots :: [method]
  , scopeNodes :: [ScopeNode method]
  , scopeLayers :: [[method]]
  , scopePaths :: [[method]]
  , scopeCandidates :: [(method, method)]
  , scopeOpposed :: [(method, method)]
  , scopeUndetermined :: [(method, method)]
  } deriving (Eq, Show, Read, Functor, Generic, NFData)
