-- 运行时的原型索引：interpreter 启动时把 gen 写下的 Prototype 一次性编成按身份寻址的表。
-- Prototype 本身保持可序列化的列表形式，以名字记录 effect、以路径记录位置；这里把名字换成
-- effect 编号（Slot：effect 在 protoEffects 中的位置），把路径换成坐标（Coord：位置树的先序序号），
-- 此后运行中只按编号与坐标查表，不再线性扫描原型、按名字匹配资产或比较路径前缀。
-- 查询结果与 Framework.Prototype.Query 的同名函数一致。
module Framework.Prototype.Index
  ( PrototypeIndex, indexPrototype, indexedPrototype
  , DriveAt(..), UnitAt(..), SourceAt(..), ReaderAt(..), LocalSlot(..), IndexedOpening(..), SessionAt(..)
  , slotOf, coordAt, rootCoord
  , chainAt, driveAt, unitAt, rootNodesOf, sessionRouteOf, sessionUpstreamOf, sessionAt
  , sourcePlanAt, sourcesAt, hooksLabel, openingsAt, historyOf, sampledOf, listensAt, requestEntryOf
  , parameterScopesOf, scopeClosureOf, isResourceSlot, outputSiteAt
  ) where

import qualified Data.IntSet as IntSet
import Data.List (nub, sortOn)
import Data.Ord (Down(..))
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Data.Maybe (fromMaybe)
import Framework.Prototype.Coordinate (Coord, coordinates)
import Framework.Prototype.Query (allWorkflow, describedSession, variantLabel, workflowNode)
import Framework.Prototype.Slot (Slot(..))
import Framework.Prototype.Structure (scopeRelations)
import Framework.Prototype.Types

-- NodeDrive 的坐标视图。
data DriveAt = DriveAt
  { nodeMembers :: [Coord]
  , nodeSubscriptions :: [Slot]
  , nodeBoundary :: Maybe Coord
  , nodeCaptures :: [Coord]
  , nodePriorBoundaries :: [Coord]
  , nodeBlockedPublishers :: [Coord]
  }

-- UnitDrive 的坐标视图。
data UnitAt = UnitAt
  { unitFrameNodes :: [Coord]
  , unitReaders :: [(Slot, [ReaderAt])]
  , unitLocals :: [(Slot, LocalSlot)]
  }

-- Source 的坐标视图：ChainsAt 是 gen 给出的供值位置集合，即这份资产的 effect → 坐标一对多关系。
data SourceAt = ChainsAt [Coord] | OwnChainAt | SessionSourced

data ReaderAt = ReadsAt Coord | ChoosesAmong [Coord]

-- LocalSource 的视图。
data LocalSlot = PublishedSlotAt [Coord] | DerivedFromSlot Slot

-- 开启计划的视图：参数来源按 Context 编号匹配。
data IndexedOpening = IndexedOpening
  { indexedOpeningNode :: Coord
  , indexedOpeningScope :: Slot
  , indexedOpeningSources :: [(Slot, SourceAt)]
  , indexedOpeningKinds :: [ScopeKind]
  }

-- SessionProto 的视图：会话资产与生产计划仍读原型，挂载换成坐标。
data SessionAt = SessionAt
  { sessionAtProto :: SessionProto
  , sessionAtMounts :: [Coord]
  -- ReuseOutput 的原始链挂载；其他计划为 Nothing。
  , sessionAtReuses :: Maybe [Coord]
  }

data PrototypeIndex method = PrototypeIndex
  { indexedPrototype :: Prototype method
  -- 名字 → 编号、路径 → 坐标只在建索引与装配时使用；运行中的读取、发布、等待与回收不经过它们。
  , indexSlots :: Map.Map String Slot
  , indexCoords :: Map.Map NodeId Coord
  , indexChains :: Map.Map Coord (ChainProto method)
  , indexNodes :: Map.Map Coord DriveAt
  , indexUnits :: Map.Map Coord UnitAt
  , indexRootNodes :: [Coord]
  , indexRoutes :: Map.Map (Maybe Coord, Slot) SessionDrive
  , indexUpstreams :: Map.Map (Maybe Coord, Slot) (Maybe Slot)
  , indexSessions :: Map.Map (Maybe Coord, Slot) SessionAt
  -- (读取坐标, Context 编号) → 静态来源。原型按契约名记录读取点；这里先换算成生产它的 Context 编号。
  , indexSources :: Map.Map (Coord, Slot) SourceAt
  , indexSourcesByNode :: Map.Map Coord [(Slot, SourceAt)]
  , indexHooks :: Map.Map Coord [String]
  , indexOpenings :: Map.Map Coord [IndexedOpening]
  , indexHistories :: IntSet.IntSet
  , indexSampled :: IntSet.IntSet
  , indexRequests :: Map.Map Slot method
  , indexParameterScopes :: Map.Map Slot [Slot]
  -- Scoped 编号 → 它与 ScopeTree 上全部祖先；回收按它展开，运行中不再沿关系表求闭包。
  , indexScopeClosures :: Map.Map Slot [Slot]
  , indexResources :: IntSet.IntSet
  , indexOutputSites :: Set.Set (Coord, Slot)
  }

-- 重复身份是生成产物失配：保留第一个以便查询返回确定结果，Validate 在加载时已拒绝这类原型。
indexPrototype :: Eq method => Prototype method -> PrototypeIndex method
indexPrototype prototype = PrototypeIndex
  { indexedPrototype = prototype
  , indexSlots = slots
  , indexCoords = coords
  , indexChains = keyed (at . chainNode) (protoChains prototype)
  , indexNodes = Map.fromListWith (\_ first -> first) [(at (driveNode node), nodeView node) | node <- drivingNodes driving]
  , indexUnits = Map.fromListWith (\_ first -> first) [(at (driveUnit unit), unitView unit) | unit <- drivingUnits driving]
  , indexRootNodes = map at (drivingRootNodes driving)
  , indexRoutes = routes
  , indexUpstreams = Map.map (fmap named . driveSessionUpstream) routes
  , indexSessions = Map.fromListWith (\_ first -> first)
      [ (key, sessionView described) | route <- drivingSessions driving
      , let key = (at <$> driveSessionBoundary route, named (driveSessionSource route))
      , Just described <- [describedSession prototype route] ]
  , indexSources = Map.fromList
      [ ((at (readNode point), context), source plan) | (point, plan) <- protoSources prototype
      , Just context <- [Map.lookup (readContract point) contexts] ]
  , indexSourcesByNode = Map.fromListWith (flip (++))
      [ (at (readNode point), [(context, source plan)]) | (point, plan) <- protoSources prototype
      , Just context <- [Map.lookup (readContract point) contexts] ]
  , indexHooks = Map.fromList [(at position, hooks) | (position, hooks) <- drivingHooks driving]
  , indexOpenings = Map.fromListWith (flip (++))
      [(at (openingNode opening), [indexedOpening opening]) | opening <- protoScopeOpenings prototype]
  , indexHistories = IntSet.fromList
      [slotNumber (named (effectName effect)) | effect <- protoEffects prototype, effectHistory effect]
  , indexSampled = IntSet.fromList
      [slotNumber (named (effectName effect)) | effect <- protoEffects prototype, effectSampled effect]
  , indexRequests = Map.fromListWith (\_ first -> first)
      [(named name, method) | (name, method) <- drivingRequests driving]
  , indexParameterScopes = Map.fromListWith (flip (++))
      [ (named name, [named (openingScope opening)]) | opening <- protoScopeOpenings prototype
      , (name, _) <- openingSources opening ]
  , indexScopeClosures = Map.fromList
      [ (named scope, nub (named scope : map named parents)) | (scope, parents) <- scopeRelations prototype ]
  , indexResources = IntSet.fromList
      [slotNumber (named resource) | effect <- protoEffects prototype, Just resource <- [effectResource effect]]
  , indexOutputSites = Set.fromList [(at node, named name) | (node, name) <- drivingOutputSites driving]
  }
  where
    driving = protoDriving prototype
    keyed key items = Map.fromListWith (\_ first -> first) [(key item, item) | item <- items]
    -- gen 的编号规则：effect 在 protoEffects 中的位置。生成代码中的 Slot 字面量出自同一规则。
    slots = Map.fromListWith (\_ first -> first)
      [(effectName effect, Slot number (effectName effect)) | (number, effect) <- zip [0 ..] (protoEffects prototype)]
    -- 原型里的名字都来自已校验的注册；不认识的名字是生成产物失配。
    named name = fromMaybe (error ("Prototype names an unknown effect " ++ show name ++ "; regenerate")) (Map.lookup name slots)
    -- 原型写下的全部位置；坐标覆盖它们及其前缀。
    coords = coordinates (positions prototype)
    at node = fromMaybe (error ("Prototype names an unknown position " ++ show node ++ "; regenerate")) (Map.lookup node coords)
    routes = Map.fromListWith (\_ first -> first)
      [((at <$> driveSessionBoundary route, named (driveSessionSource route)), route) | route <- drivingSessions driving]
    -- 每份资产恰有一个 Context 来源（注册校验保证）。
    contexts = Map.fromList [(contract, named (effectName effect)) | effect <- protoEffects prototype
      , Just contract <- [effectProduces effect]]
    source (FromChains nodes) = ChainsAt (map at nodes)
    source FromOwnChain = OwnChainAt
    source FromSession = SessionSourced
    indexedOpening opening = IndexedOpening (at (openingNode opening)) (named (openingScope opening))
      [(named name, source plan) | (name, plan) <- openingSources opening] (openingKinds opening)
    -- 此前的 lifelong 边界按先序坐标从后往前：彼此先后的边界中，最近结束的排在前面。
    nodeView node = DriveAt (map at (driveMembers node)) (map named (driveSubscriptions node))
      (at <$> driveBoundary node) (map at (driveCaptures node)) (sortOn Down (map at (drivePriorBoundaries node)))
      (map at (driveBlockedPublishers node))
    unitView unit = UnitAt (map at (driveFrameNodes unit))
      [(named name, map reader sites) | (name, sites) <- driveReaders unit]
      [(named name, local plan) | (name, plan) <- driveLocalSources unit]
    reader (ReadAt node) = ReadsAt (at node)
    reader (ChooseAmong nodes) = ChoosesAmong (map at nodes)
    local (PublishedAt nodes) = PublishedSlotAt (map at nodes)
    local (DerivedFrom upstream) = DerivedFromSlot (named upstream)
    sessionView described = SessionAt described (map at (sessionMounts described)) $ case sessionPlan described of
      ReuseOutput nodes -> Just (map at nodes)
      _ -> Nothing

-- 原型中出现的每个位置。
positions :: Prototype method -> [NodeId]
positions prototype = concat
  [ concat [workflowPositions tree | tree <- allWorkflow (protoWorkflow prototype)]
  , concatMap sessionPositions (protoSessions prototype)
  , map chainNode (protoChains prototype)
  , concat [readNode point : sourcePositions plan | (point, plan) <- protoSources prototype]
  , concat [openingNode opening : concatMap (sourcePositions . snd) (openingSources opening) | opening <- protoScopeOpenings prototype]
  , concat [ driveNode node : driveMembers node ++ maybe [] pure (driveBoundary node) ++ driveCaptures node
             ++ drivePriorBoundaries node ++ driveBlockedPublishers node | node <- drivingNodes driving ]
  , concat [ driveUnit unit : driveFrameNodes unit ++ concat [readerPositions site | (_, sites) <- driveReaders unit, site <- sites]
             ++ concat [nodes | (_, PublishedAt nodes) <- driveLocalSources unit] | unit <- drivingUnits driving ]
  , [boundary | route <- drivingSessions driving, Just boundary <- [driveSessionBoundary route]]
  , drivingRootNodes driving
  , map fst (drivingOutputSites driving)
  , map fst (drivingMiddleware driving)
  , map fst (drivingHooks driving)
  ]
  where
    driving = protoDriving prototype
    workflowPositions tree = workflowNode tree : case tree of
      AlternativeAt _ choice _ -> alternativeSelector choice : map fst (alternativeCases choice)
      LifelongAt _ described _ -> lifelongUnits described ++ map fst (lifelongSubscriptions described)
        ++ concatMap sessionPositions (lifelongSessions described)
      _ -> []
    sessionPositions session = sessionMounts session ++ case sessionPlan session of
      ReuseOutput nodes -> nodes
      _ -> []
    sourcePositions (FromChains nodes) = nodes
    sourcePositions _ = []
    readerPositions (ReadAt node) = [node]
    readerPositions (ChooseAmong nodes) = nodes

-- 装配时把原型里的名字换成编号；运行中不调用。
slotOf :: PrototypeIndex method -> String -> Slot
slotOf index name = fromMaybe (error ("Unknown effect " ++ show name ++ "; regenerate")) (Map.lookup name (indexSlots index))

-- 装配时把原型里的路径换成坐标；运行中不调用。
coordAt :: PrototypeIndex method -> NodeId -> Coord
coordAt index node = fromMaybe (error ("Unknown position " ++ show node ++ "; regenerate")) (Map.lookup node (indexCoords index))

-- 整棵 AST 的根位置（空路径）。
rootCoord :: PrototypeIndex method -> Coord
rootCoord index = coordAt index []

chainAt :: PrototypeIndex method -> Coord -> Either (PrototypeError method) (ChainProto method)
chainAt index node = maybe (Left (InvalidPrototype ("Missing or duplicate chain at " ++ show node))) Right
  (Map.lookup node (indexChains index))

driveAt :: PrototypeIndex method -> Coord -> DriveAt
driveAt index node = fromMaybe
  (error ("Missing or duplicate generated node driver at " ++ show node ++ "; regenerate"))
  (Map.lookup node (indexNodes index))

unitAt :: PrototypeIndex method -> Coord -> UnitAt
unitAt index node = fromMaybe
  (error ("Missing or duplicate generated unit driver at " ++ show node ++ "; regenerate"))
  (Map.lookup node (indexUnits index))

rootNodesOf :: PrototypeIndex method -> [Coord]
rootNodesOf = indexRootNodes

sessionRouteOf :: PrototypeIndex method -> Maybe Coord -> Slot -> Maybe SessionDrive
sessionRouteOf index boundary context = Map.lookup (boundary, context) (indexRoutes index)

-- 会话的上游持续资产；外层 Nothing 表示没有这条会话路由。
sessionUpstreamOf :: PrototypeIndex method -> Maybe Coord -> Slot -> Maybe (Maybe Slot)
sessionUpstreamOf index boundary context = Map.lookup (boundary, context) (indexUpstreams index)

sessionAt :: PrototypeIndex method -> Maybe Coord -> Slot -> Maybe SessionAt
sessionAt index boundary context = Map.lookup (boundary, context) (indexSessions index)

-- 读取点的静态来源；没有登记的读取只能使用本次调用的捕获。
sourcePlanAt :: PrototypeIndex method -> Coord -> Slot -> SourceAt
sourcePlanAt index node context = Map.findWithDefault OwnChainAt (node, context) (indexSources index)

-- 该位置全部读取点：(生产它的 Context 编号, 静态来源)。
sourcesAt :: PrototypeIndex method -> Coord -> [(Slot, SourceAt)]
sourcesAt index node = Map.findWithDefault [] node (indexSourcesByNode index)

-- 与 Query.entryLabel 相同：没有 Middleware 时就是原名。
hooksLabel :: PrototypeIndex method -> Coord -> String -> String
hooksLabel index position base = variantLabel base (Map.findWithDefault [] position (indexHooks index))

-- 在该位置开启的 Scoped 及其参数来源，按原型顺序。
openingsAt :: PrototypeIndex method -> Coord -> [IndexedOpening]
openingsAt index node = Map.findWithDefault [] node (indexOpenings index)

-- 持续资产是否从开头保留全部交付（stream @T 读取 x:xs）。
historyOf :: PrototypeIndex method -> Slot -> Bool
historyOf index context = IntSet.member (slotNumber context) (indexHistories index)

-- behavior：相等的值只发布一次，读取方只领取最新一条。
sampledOf :: PrototypeIndex method -> Slot -> Bool
sampledOf index context = IntSet.member (slotNumber context) (indexSampled index)

-- event：该边界的会话只接收这份普通资产此后的发布，没有生产任务。
listensAt :: PrototypeIndex method -> Maybe Coord -> Slot -> Bool
listensAt index boundary context = maybe False ((== Listen) . sessionPlan . sessionAtProto) (sessionAt index boundary context)

-- RequestBoot 的生产入口。
requestEntryOf :: PrototypeIndex method -> Slot -> Maybe method
requestEntryOf index context = Map.lookup context (indexRequests index)

-- 开启计划依赖该参数的 Scoped。
parameterScopesOf :: PrototypeIndex method -> Slot -> [Slot]
parameterScopesOf index context = Map.findWithDefault [] context (indexParameterScopes index)

-- 这些 Scoped 及其 ScopeTree 祖先。
scopeClosureOf :: PrototypeIndex method -> [Slot] -> [Slot]
scopeClosureOf index scopes = nub (concat [Map.findWithDefault [scope] scope (indexScopeClosures index) | scope <- scopes])

-- 是否是某个 Scoped 的资源 Context。
isResourceSlot :: PrototypeIndex method -> Slot -> Bool
isResourceSlot index context = IntSet.member (slotNumber context) (indexResources index)

-- 原始链在该挂载沿用本次输出发布这份持续资产。
outputSiteAt :: PrototypeIndex method -> Coord -> Slot -> Bool
outputSiteAt index node context = Set.member (node, context) (indexOutputSites index)
