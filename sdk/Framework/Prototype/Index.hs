-- 运行时的原型索引：interpreter 启动时把 gen 写下的 Prototype 一次性编成按身份寻址的表。
-- Prototype 本身保持可序列化的列表形式，以名字记录 effect；这里按 gen 的编号规则
-- （effect 在 protoEffects 中的位置）把名字换成 Slot，此后运行中只按编号与 NodeId 查表，
-- 不再线性扫描原型，也不按名字匹配资产。查询结果与 Framework.Prototype.Query 的同名函数一致。
module Framework.Prototype.Index
  ( PrototypeIndex, indexPrototype, indexedPrototype
  , IndexedOpening(..), LocalSlot(..)
  , slotOf, chainAt, nodeDriveOf, unitDriveOf, sessionRouteOf, sessionUpstreamOf, sessionDescriptionAt
  , sourcePlanAt, sourcesAt, hooksLabel, openingsAt, historyOf, requestEntryOf
  , subscriptionsAt, unitReadersAt, unitLocalSourcesAt, parameterScopesOf, isResourceSlot, outputSiteAt
  ) where

import qualified Data.IntSet as IntSet
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Data.Maybe (fromMaybe)
import Framework.Prototype.Query (describedSession, variantLabel)
import Framework.Prototype.Slot (Slot(..))
import Framework.Prototype.Types

-- 开启计划的编号视图：参数来源按 Context 编号匹配。
data IndexedOpening = IndexedOpening
  { indexedOpeningNode :: NodeId
  , indexedOpeningScope :: String
  , indexedOpeningSources :: [(Slot, Source)]
  , indexedOpeningKinds :: [ScopeKind]
  }

-- LocalSource 的编号视图。
data LocalSlot = PublishedSlotAt [NodeId] | DerivedFromSlot Slot

data PrototypeIndex method = PrototypeIndex
  { indexedPrototype :: Prototype method
  -- 名字 → 编号只在建索引与装配时使用；运行中的读取、发布与等待不经过它。
  , indexSlots :: Map.Map String Slot
  , indexChains :: Map.Map NodeId (ChainProto method)
  , indexNodes :: Map.Map NodeId NodeDrive
  , indexUnits :: Map.Map NodeId UnitDrive
  , indexRoutes :: Map.Map (Maybe NodeId, Slot) SessionDrive
  , indexUpstreams :: Map.Map (Maybe NodeId, Slot) (Maybe Slot)
  , indexDescriptions :: Map.Map (Maybe NodeId, Slot) SessionProto
  -- (读取节点, Context 编号) → 静态来源。原型按契约名记录读取点；这里先换算成生产它的 Context 编号。
  , indexSources :: Map.Map (NodeId, Slot) Source
  , indexSourcesByNode :: Map.Map NodeId [(Slot, Source)]
  , indexHooks :: Map.Map NodeId [String]
  , indexOpenings :: Map.Map NodeId [IndexedOpening]
  , indexHistories :: IntSet.IntSet
  , indexRequests :: Map.Map Slot method
  , indexSubscriptions :: Map.Map NodeId [Slot]
  , indexUnitReaders :: Map.Map NodeId [(Slot, [ReaderSite])]
  , indexUnitLocals :: Map.Map NodeId [(Slot, LocalSlot)]
  , indexParameterScopes :: Map.Map Slot [String]
  , indexResources :: IntSet.IntSet
  , indexOutputSites :: Set.Set (NodeId, Slot)
  }

-- 重复身份是生成产物失配：保留第一个以便查询返回确定结果，Validate 在加载时已拒绝这类原型。
indexPrototype :: Prototype method -> PrototypeIndex method
indexPrototype prototype = PrototypeIndex
  { indexedPrototype = prototype
  , indexSlots = slots
  , indexChains = keyed chainNode (protoChains prototype)
  , indexNodes = keyed driveNode (drivingNodes driving)
  , indexUnits = keyed driveUnit (drivingUnits driving)
  , indexRoutes = routes
  , indexUpstreams = Map.map (fmap named . driveSessionUpstream) routes
  , indexDescriptions = Map.fromListWith (\_ first -> first)
      [ (key, described) | route <- drivingSessions driving
      , let key = (driveSessionBoundary route, named (driveSessionSource route))
      , Just described <- [describedSession prototype route] ]
  , indexSources = Map.fromList
      [ ((readNode point, context), plan) | (point, plan) <- protoSources prototype
      , Just context <- [Map.lookup (readContract point) contexts] ]
  , indexSourcesByNode = Map.fromListWith (flip (++))
      [ (readNode point, [(context, plan)]) | (point, plan) <- protoSources prototype
      , Just context <- [Map.lookup (readContract point) contexts] ]
  , indexHooks = Map.fromList (drivingHooks driving)
  , indexOpenings = Map.fromListWith (flip (++))
      [(openingNode opening, [indexedOpening opening]) | opening <- protoScopeOpenings prototype]
  , indexHistories = IntSet.fromList
      [slotNumber (named (effectName effect)) | effect <- protoEffects prototype, effectHistory effect]
  , indexRequests = Map.fromListWith (\_ first -> first)
      [(named source, method) | (source, method) <- drivingRequests driving]
  , indexSubscriptions = Map.fromList
      [(driveNode node, map named (driveSubscriptions node)) | node <- drivingNodes driving]
  , indexUnitReaders = Map.fromList
      [(driveUnit unit, [(named source, sites) | (source, sites) <- driveReaders unit]) | unit <- drivingUnits driving]
  , indexUnitLocals = Map.fromList
      [(driveUnit unit, [(named source, local plan) | (source, plan) <- driveLocalSources unit]) | unit <- drivingUnits driving]
  , indexParameterScopes = Map.fromListWith (flip (++))
      [ (named source, [openingScope opening]) | opening <- protoScopeOpenings prototype
      , (source, _) <- openingSources opening ]
  , indexResources = IntSet.fromList
      [slotNumber (named resource) | effect <- protoEffects prototype, Just resource <- [effectResource effect]]
  , indexOutputSites = Set.fromList [(node, named source) | (node, source) <- drivingOutputSites driving]
  }
  where
    driving = protoDriving prototype
    keyed key items = Map.fromListWith (\_ first -> first) [(key item, item) | item <- items]
    -- gen 的编号规则：effect 在 protoEffects 中的位置。生成代码中的 Slot 字面量出自同一规则。
    slots = Map.fromListWith (\_ first -> first)
      [(effectName effect, Slot number (effectName effect)) | (number, effect) <- zip [0 ..] (protoEffects prototype)]
    -- 原型里的名字都来自已校验的注册；不认识的名字是生成产物失配。
    named name = fromMaybe (error ("Prototype names an unknown effect " ++ show name ++ "; regenerate")) (Map.lookup name slots)
    routes = Map.fromListWith (\_ first -> first)
      [((driveSessionBoundary route, named (driveSessionSource route)), route) | route <- drivingSessions driving]
    -- 每份资产恰有一个 Context 来源（注册校验保证）。
    contexts = Map.fromList [(contract, named (effectName effect)) | effect <- protoEffects prototype
      , Just contract <- [effectProduces effect]]
    indexedOpening opening = IndexedOpening (openingNode opening) (openingScope opening)
      [(named source, plan) | (source, plan) <- openingSources opening] (openingKinds opening)
    local (PublishedAt nodes) = PublishedSlotAt nodes
    local (DerivedFrom upstream) = DerivedFromSlot (named upstream)

-- 装配时把原型里的名字换成编号；运行中不调用。
slotOf :: PrototypeIndex method -> String -> Slot
slotOf index name = fromMaybe (error ("Unknown effect " ++ show name ++ "; regenerate")) (Map.lookup name (indexSlots index))

chainAt :: PrototypeIndex method -> NodeId -> Either (PrototypeError method) (ChainProto method)
chainAt index node = maybe (Left (InvalidPrototype ("Missing or duplicate chain at " ++ show node))) Right
  (Map.lookup node (indexChains index))

nodeDriveOf :: PrototypeIndex method -> NodeId -> NodeDrive
nodeDriveOf index node = fromMaybe
  (error ("Missing or duplicate generated node driver at " ++ show node ++ "; regenerate"))
  (Map.lookup node (indexNodes index))

unitDriveOf :: PrototypeIndex method -> NodeId -> UnitDrive
unitDriveOf index node = fromMaybe
  (error ("Missing or duplicate generated unit driver at " ++ show node ++ "; regenerate"))
  (Map.lookup node (indexUnits index))

sessionRouteOf :: PrototypeIndex method -> Maybe NodeId -> Slot -> Maybe SessionDrive
sessionRouteOf index boundary source = Map.lookup (boundary, source) (indexRoutes index)

-- 会话的上游持续资产；外层 Nothing 表示没有这条会话路由。
sessionUpstreamOf :: PrototypeIndex method -> Maybe NodeId -> Slot -> Maybe (Maybe Slot)
sessionUpstreamOf index boundary source = Map.lookup (boundary, source) (indexUpstreams index)

sessionDescriptionAt :: PrototypeIndex method -> Maybe NodeId -> Slot -> Maybe SessionProto
sessionDescriptionAt index boundary source = Map.lookup (boundary, source) (indexDescriptions index)

-- 读取点的静态来源；没有登记的读取只能使用本次调用的捕获。
sourcePlanAt :: PrototypeIndex method -> NodeId -> Slot -> Source
sourcePlanAt index node context = Map.findWithDefault FromOwnChain (node, context) (indexSources index)

-- 该节点全部读取点：(生产它的 Context 编号, 静态来源)。
sourcesAt :: PrototypeIndex method -> NodeId -> [(Slot, Source)]
sourcesAt index node = Map.findWithDefault [] node (indexSourcesByNode index)

-- 与 Query.entryLabel 相同：没有 Middleware 时就是原名。
hooksLabel :: PrototypeIndex method -> NodeId -> String -> String
hooksLabel index position base = variantLabel base (Map.findWithDefault [] position (indexHooks index))

-- 在该位置开启的 Scoped 及其参数来源，按原型顺序。
openingsAt :: PrototypeIndex method -> NodeId -> [IndexedOpening]
openingsAt index node = Map.findWithDefault [] node (indexOpenings index)

-- 持续资产是否从开头保留全部交付（stream @T 读取 x:xs）。
historyOf :: PrototypeIndex method -> Slot -> Bool
historyOf index source = IntSet.member (slotNumber source) (indexHistories index)

-- RequestBoot 的生产入口。
requestEntryOf :: PrototypeIndex method -> Slot -> Maybe method
requestEntryOf index source = Map.lookup source (indexRequests index)

-- 节点所订阅的持续资产。
subscriptionsAt :: PrototypeIndex method -> NodeId -> [Slot]
subscriptionsAt index node = Map.findWithDefault [] node (indexSubscriptions index)

unitReadersAt :: PrototypeIndex method -> NodeId -> [(Slot, [ReaderSite])]
unitReadersAt index unit = Map.findWithDefault [] unit (indexUnitReaders index)

unitLocalSourcesAt :: PrototypeIndex method -> NodeId -> [(Slot, LocalSlot)]
unitLocalSourcesAt index unit = Map.findWithDefault [] unit (indexUnitLocals index)

-- 开启计划依赖该参数的 Scoped。
parameterScopesOf :: PrototypeIndex method -> Slot -> [String]
parameterScopesOf index source = Map.findWithDefault [] source (indexParameterScopes index)

-- 是否是某个 Scoped 的资源 Context。
isResourceSlot :: PrototypeIndex method -> Slot -> Bool
isResourceSlot index source = IntSet.member (slotNumber source) (indexResources index)

-- 原始链在该挂载沿用本次输出发布这份持续资产。
outputSiteAt :: PrototypeIndex method -> NodeId -> Slot -> Bool
outputSiteAt index node source = Set.member (node, source) (indexOutputSites index)
