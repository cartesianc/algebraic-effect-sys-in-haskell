{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveFunctor #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DuplicateRecordFields #-}

-- Prototype 的唯一数据模型。这里只保存可发射、可校验的静态事实，不引入执行句柄或资源。
-- 构建与验证入口留在 Framework.Prototype；内部算法依赖本模块以避免门面反向依赖。
module Framework.Prototype.Types
  ( NodeId, SumTypes, Prototype(..), PrototypePlan(..), EffectProto(..)
  , WorkflowTree(..), AlternativeProto(..), LifelongProto(..), SessionProto(..), BootPlan(..)
  , ChainRole(..), ChainProto(..), ChainKind(..), ChainDefinition(..)
  , ReadPoint(..), Source(..), PrototypeError(..)
  ) where

import Control.DeepSeq (NFData)
import Framework.Effect.Contract (EffectKind)
import Framework.Effect.Graph (MethodRole, MethodDefinition, EffectGraph, ScopeTree, GraphError)
import Framework.Effect.Registration (EffectSpec, ResolvedDemand)
import GHC.Generics (Generic)

-- 当前 AST 快照内的挂载路径，不是运行调用序号；Context 链定义自身没有 AST 位置。
type NodeId = [Int]
type SumTypes = [(String, [(String, Maybe String)])]

data Prototype method = Prototype
  { protoRegistrations :: [EffectSpec]
  , protoEffects :: [EffectProto method]
  , protoMethods :: [MethodDefinition method]
  , protoWorkflow :: WorkflowTree
  -- lifelong 外的有限 require 读取 Receive 资产时由 interpreter 托管的会话；按注册确定，惰性启动。
  , protoSessions :: [SessionProto]
  , protoChains :: [ChainProto method]
  , protoChainDefinitions :: [ChainDefinition method]
  , protoGraph :: EffectGraph method
  , protoScopes :: ScopeTree method
  , protoScopeNames :: [(method, String)]
  , protoSources :: [(ReadPoint, Source)]
  } deriving (Eq, Show, Read, Functor, Generic, NFData)

-- 声明接口先于 Handlers 存在；准备阶段只运行一次，方法解析后补全同一份计划。
data PrototypePlan = PrototypePlan
  { plannedRegistrations :: [EffectSpec]
  , plannedEffects :: [EffectProto String]
  , plannedWorkflow :: WorkflowTree
  } deriving (Eq, Show, Read, Generic, NFData)

data EffectProto method = EffectProto
  { effectName :: String
  , effectKind :: EffectKind
  , effectInput :: String
  , effectMethods :: [(MethodRole, method)]
  , effectDemands :: [ResolvedDemand]
  , effectProduces :: Maybe String
  , effectBranches :: [(String, String)]
  , effectAnchor :: Maybe String
  , effectScopes :: [String]
  , effectErrorScope :: Maybe String
  , effectInputChain :: [String]
  , effectScopeParents :: [String]
  , effectOpeningInputs :: [String]
  , effectNearestScopes :: [String]
  , effectResource :: Maybe String
  , effectContextDependencies :: [String]
  -- 持续资产：stream = True，只能挂在 Stream 下；streams 读取 History，requires 读取最新一条。
  , effectContinuous :: Bool
  } deriving (Eq, Show, Read, Functor, Generic, NFData)

data WorkflowTree
  = NodeAt NodeId String
  | ChainedAt NodeId [WorkflowTree]
  | ParallelAt NodeId [WorkflowTree]
  | AlternativeAt NodeId AlternativeProto [WorkflowTree]
  | LifelongAt NodeId LifelongProto [WorkflowTree]
  deriving (Eq, Show, Read, Generic, NFData)

data AlternativeProto = AlternativeProto
  { alternativeContract :: String
  , alternativeSelector :: NodeId
  , alternativeCases :: [(NodeId, String)]
  } deriving (Eq, Show, Read, Generic, NFData)

-- lifelong 的静态装配：消费单元、每个挂载 target 的驱动资产，以及按资产共享的生产会话。
-- 会话以 lifelong 边界为出身，挂载路径为 lifelong 路径加 [-1, 会话序号, 步骤序号]，先于全部单元。
data LifelongProto = LifelongProto
  { lifelongUnits :: [NodeId]
  , lifelongSubscriptions :: [(NodeId, String)]
  , lifelongSessions :: [SessionProto]
  } deriving (Eq, Show, Read, Generic, NFData)

data SessionProto = SessionProto
  { sessionAsset :: String
  , sessionPlan :: BootPlan
  , sessionMounts :: [NodeId]
  } deriving (Eq, Show, Read, Generic, NFData)

-- 持续资产只由上游 Stream 驱动：两步挂载依次为 Stream 单步与 parser。
data BootPlan = Receive String
  deriving (Eq, Show, Read, Generic, NFData)

data ChainRole = NodeChain | SelectorChain | SessionChain
  deriving (Eq, Show, Read, Generic, NFData)

data ChainProto method = ChainProto
  { chainNode :: NodeId
  , chainRole :: ChainRole
  , chainTerminal :: String
  , chainEntry :: method
  , chainReaches :: [method]
  , chainDrives :: [String]
  , chainReads :: [String]
  , chainScopePaths :: [[method]]
  } deriving (Eq, Show, Read, Functor, Generic, NFData)

-- 定义身份属于方法；NodeId 只属于 AST 挂载。同一 origin 定义可挂载多次，
-- Context 生产／读取链由 demand 进入，始终没有虚构的 AST 路径。
data ChainKind = OriginChain | ContextChain
  deriving (Eq, Show, Read, Generic, NFData)

data ChainDefinition method = ChainDefinition
  { definitionKind :: ChainKind
  , definitionEffect :: String
  , definitionEntry :: method
  , definitionReaches :: [method]
  } deriving (Eq, Show, Read, Functor, Generic, NFData)

data ReadPoint = ReadPoint { readNode :: NodeId, readContract :: String }
  deriving (Eq, Show, Read, Generic, NFData)

-- FromChains 保存保证先完成的静态候选；运行时仍须核对本次实际发布的唯一来源。
-- FromOwnChain 没有外部候选，沿用本次捕获与缺值协议，不意味着每次都生产。
-- FromSession：Receive 资产在没有本次交付时，由 interpreter 托管的会话交付当前历史。
data Source = FromChains [NodeId] | FromOwnChain | FromSession
  deriving (Eq, Show, Read, Generic, NFData)

data PrototypeError method
  = InvalidPrototype String
  | InvalidEffectGraph (GraphError method)
  | UnknownPrototypeTarget String
  | InvalidAlternative NodeId String
  | InvalidLifelong NodeId String
  | PrototypeWorkflowMismatch
  deriving (Eq, Show, Read, Functor, Generic, NFData)
