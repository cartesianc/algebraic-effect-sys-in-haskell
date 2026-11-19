{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveFunctor #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DuplicateRecordFields #-}

-- Prototype 的唯一数据模型，也就是 gen 的编译产物（中间表示）。这里只保存可发射、可校验的静态事实，
-- 不引入执行句柄或资源。构建算法在 Framework.Gen.Composition，执行与展示只读取它。
module Framework.Prototype.Types
  ( NodeId, SumTypes, Prototype(..), PrototypePlan(..), EffectProto(..)
  , WorkflowTree(..), AlternativeProto(..), LifelongProto(..), SessionProto(..), BootPlan(..)
  , ChainRole(..), ChainProto(..), ChainKind(..), ChainDefinition(..)
  , ReadPoint(..), Source(..), PrototypeError(..), ResolvedDemand(..)
  , ScopeOpening(..), ScopeKind(..)
  , DrivingPlan(..), NodeDrive(..), UnitDrive(..), SessionDrive(..), ReaderSite(..), LocalSource(..)
  ) where

import Control.DeepSeq (NFData)
import Framework.Prototype.Graph (MethodRole, MethodDefinition, EffectGraph, ScopeTree, GraphError)
import Framework.Language.Registration (Access, EffectKind, EffectSpec)
import GHC.Generics (Generic)

-- 当前 AST 快照内的挂载路径，不是运行调用序号；Context 链定义自身没有 AST 位置。
type NodeId = [Int]
-- Types.hs 中的和类型：类型名 → [(构造器名, 唯一字段的类型原文)]；由 gen 解析 Types.hs 得到。
type SumTypes = [(String, [(String, Maybe String)])]

-- 降级后的 demand：访问方式、契约（资产名或分支契约）与唯一的生产方 effect。
data ResolvedDemand = ResolvedDemand
  { demandAccess :: Access
  , demandContract :: String
  , demandProvider :: String
  } deriving (Eq, Show, Read, Generic, NFData)

data Prototype method = Prototype
  { protoRegistrations :: [EffectSpec]
  , protoEffects :: [EffectProto method]
  , protoMethods :: [MethodDefinition method]
  , protoWorkflow :: WorkflowTree
  -- 有限 require 读取持续资产时由 interpreter 托管的 Receive/Derive 会话；gen 按注册确定，惰性启动。
  , protoSessions :: [SessionProto]
  , protoChains :: [ChainProto method]
  , protoChainDefinitions :: [ChainDefinition method]
  , protoGraph :: EffectGraph method
  , protoScopes :: ScopeTree method
  , protoScopeNames :: [(method, String)]
  , protoSources :: [(ReadPoint, Source)]
  , protoScopeOpenings :: [ScopeOpening]
  , protoDriving :: DrivingPlan method
  } deriving (Eq, Show, Read, Functor, Generic, NFData)

-- 声明接口先于 Handlers 存在；准备阶段只运行一次，方法解析后补全同一份计划。
data PrototypePlan = PrototypePlan
  { plannedRegistrations :: [EffectSpec]
  , plannedEffects :: [EffectProto String]
  , plannedWorkflow :: WorkflowTree
  -- AST 的 middleware 标注：(标注位置, hook 名)，位置按去掉标注后的路径编号。
  , plannedMiddleware :: [(NodeId, [String])]
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
  -- 持续资产：stream = True，Input 链由 Stream 或增量驱动；读取方是否重复由组合计划决定。
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
-- 会话以 lifelong 边界为出身；独立生产挂载为边界路径加 [-1, 会话序号, 步骤序号]，沿用 AST 输出的不再造挂载。
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

-- 持续资产的生产方式，由注册与本 lifelong 的实际挂载共同决定。
-- Receive：直接 input 是 Stream，记它的注册名；两步挂载依次为 Stream 单步与 parser。
-- Derive：Input 链上有 streams demand，记驱动它的持续资产；上游每交付一条，一步挂载（parser 及其 Input 链）执行一次。
-- ReuseOutput：原子句柄已由这些 AST 入口执行；parser 沿用本次输出，只登记交付会话，不另建执行挂载。
data BootPlan = Receive String | Derive String | ReuseOutput [NodeId]
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

-- FromChains 保存结构推演找到的生产机会，供缺值耗尽与开启参数证明使用；不是可见性过滤器。
-- FromOwnChain 没有已知候选，仍可使用调用捕获；普通值由运行级最新发布回答。
-- FromSession：持续资产按本轮交付、合法先前边界或 interpreter 托管会话读取。
data Source = FromChains [NodeId] | FromOwnChain | FromSession
  deriving (Eq, Show, Read, Generic, NFData)

-- 每个挂载链开启各 Scoped 时，参数 Context 的生产节点或会话来源。
-- FromSession 固定为所选交付，不把它伪装成没有候选的普通发布。FromOwnChain 不用于开启计划。
-- 候选包含本链与已经捕获的来源；不是运行时任选来源的许可，也不保存分支相关性。
-- 与 SessionProto.mounts 联合供持续待用使用；无需另一份会话资源图。
-- runtime 匹配固定捕获或共享最新值的生产身份；必定新生产的未开始开启不保留旧实例。
-- 类别不独立决定 close，实际使用、待用、子 scope 与 Binding ownership 仍共同决定。
data ScopeOpening = ScopeOpeningPlan
  { openingNode :: NodeId
  , openingScope :: String
  , openingSources :: [(String, Source)]
  , openingKinds :: [ScopeKind]
  } deriving (Eq, Show, Read, Generic, NFData)

-- 类别是该位置各合法路径的可能结果，实际开启仍由参数绑定的生产身份决定。
data ScopeKind = RegistrationSingleton | ProductionSingleton | ExecutionMultiple
  deriving (Eq, Ord, Show, Read, Generic, NFData)

data PrototypeError method
  = InvalidPrototype String
  | InvalidEffectGraph (GraphError method)
  | UnknownPrototypeTarget String
  | InvalidAlternative NodeId String
  | InvalidLifelong NodeId String
  | PrototypeWorkflowMismatch
  deriving (Eq, Show, Read, Functor, Generic, NFData)

-- Booter 的静态驱动标记 v1（2026-11-18）。只保存关系，不包含游标、结束状态或资源实例。
-- NodeId/资产名是既有结构的引用；会话的 BootPlan 仍只保存在 SessionProto。
data DrivingPlan method = DrivingPlan
  { drivingNodes :: [NodeDrive]
  , drivingUnits :: [UnitDrive]
  , drivingSessions :: [SessionDrive]
  , drivingRootNodes :: [NodeId]
  , drivingOutputSites :: [(NodeId, String)]
  , drivingRequests :: [(String, method)]
  -- 源 AST 的 middleware 标注，启动时与当前 AST 核对。
  , drivingMiddleware :: [(NodeId, [String])]
  -- 每个启动位置实际生效的 Middleware（只列非空）：所有覆盖该位置的标注之并，去重。
  , drivingHooks :: [(NodeId, [String])]
  } deriving (Eq, Show, Read, Functor, Generic, NFData)

data NodeDrive = NodeDrive
  { driveNode :: NodeId
  , driveMembers :: [NodeId]
  , driveSubscriptions :: [String]
  , driveBoundary :: Maybe NodeId
  , driveCaptures :: [NodeId]
  , drivePriorBoundaries :: [NodeId]
  -- 已知供值候选中不能在当前顺序等待期间推进的位置；不是资产可见性过滤器。
  , driveBlockedPublishers :: [NodeId]
  } deriving (Eq, Show, Read, Generic, NFData)

data UnitDrive = UnitDrive
  { driveUnit :: NodeId
  , driveFrameNodes :: [NodeId]
  , driveReaders :: [(String, [ReaderSite])]
  , driveLocalSources :: [(String, LocalSource)]
  } deriving (Eq, Show, Read, Generic, NFData)

-- 普通位置仍活着，或选择器至少还有一个活候选，才保留该单元的订阅。
data ReaderSite = ReadAt NodeId | ChooseAmong [NodeId]
  deriving (Eq, Show, Read, Generic, NFData)

-- 等待本轮全部发布位置退休，或等待派生上游本轮稳定；运行时再检查实际进度。
data LocalSource = PublishedAt [NodeId] | DerivedFrom String
  deriving (Eq, Show, Read, Generic, NFData)

-- (边界, Context 来源) 到既有会话的路由；asset 引用 SessionProto，不复制其生产计划。
data SessionDrive = SessionDrive
  { driveSessionBoundary :: Maybe NodeId
  , driveSessionSource :: String
  , driveSessionAsset :: String
  , driveSessionUpstream :: Maybe String
  } deriving (Eq, Show, Read, Generic, NFData)
