-- 运行时的原型索引：interpreter 启动时把 gen 写下的 Prototype 一次性编成按身份寻址的表。
-- Prototype 本身保持可序列化的列表形式；运行中按 NodeId、来源名查询时不再线性扫描原型，
-- 也不在每次读取时重新推导资产的静态来源。查询结果与 Framework.Prototype.Query 的同名函数一致。
module Framework.Prototype.Index
  ( PrototypeIndex, indexPrototype, indexedPrototype
  , chainAt, nodeDriveOf, unitDriveOf, sessionRouteOf, sessionDescriptionAt
  , sourcePlanAt, sourcesAt, hooksLabel, contextOf, openingsAt, historyOf
  ) where

import qualified Data.Map.Strict as Map
import Data.Maybe (fromMaybe)
import Framework.Prototype.Query (describedSession, variantLabel)
import Framework.Prototype.Types

data PrototypeIndex method = PrototypeIndex
  { indexedPrototype :: Prototype method
  , indexChains :: Map.Map NodeId (ChainProto method)
  , indexNodes :: Map.Map NodeId NodeDrive
  , indexUnits :: Map.Map NodeId UnitDrive
  , indexRoutes :: Map.Map (Maybe NodeId, String) SessionDrive
  , indexDescriptions :: Map.Map (Maybe NodeId, String) SessionProto
  -- (读取节点, Context 名) → 静态来源。原型按契约名记录读取点；这里先换算成运行时使用的 Context 名。
  , indexSources :: Map.Map (NodeId, String) Source
  , indexSourcesByNode :: Map.Map NodeId [(ReadPoint, Source)]
  , indexHooks :: Map.Map NodeId [String]
  , indexContexts :: Map.Map String String
  , indexOpenings :: Map.Map NodeId [ScopeOpening]
  , indexHistories :: Map.Map String Bool
  }

-- 重复身份是生成产物失配：保留第一个以便查询返回确定结果，Validate 在加载时已拒绝这类原型。
indexPrototype :: Prototype method -> PrototypeIndex method
indexPrototype prototype = PrototypeIndex
  { indexedPrototype = prototype
  , indexChains = keyed chainNode (protoChains prototype)
  , indexNodes = keyed driveNode (drivingNodes driving)
  , indexUnits = keyed driveUnit (drivingUnits driving)
  , indexRoutes = routes
  , indexDescriptions = Map.mapMaybe (describedSession prototype) routes
  , indexSources = Map.fromList
      [ ((readNode point, context), plan) | (point, plan) <- protoSources prototype
      , Just context <- [Map.lookup (readContract point) contexts] ]
  , indexSourcesByNode = Map.fromListWith (flip (++))
      [(readNode point, [(point, plan)]) | (point, plan) <- protoSources prototype]
  , indexHooks = Map.fromList (drivingHooks driving)
  , indexContexts = contexts
  , indexOpenings = Map.fromListWith (flip (++))
      [(openingNode opening, [opening]) | opening <- protoScopeOpenings prototype]
  , indexHistories = Map.fromListWith (||) [(effectName effect, effectHistory effect) | effect <- protoEffects prototype]
  }
  where
    driving = protoDriving prototype
    keyed key items = Map.fromListWith (\_ first -> first) [(key item, item) | item <- items]
    routes = Map.fromListWith (\_ first -> first)
      [((driveSessionBoundary route, driveSessionSource route), route) | route <- drivingSessions driving]
    -- 每份资产恰有一个 Context 来源（注册校验保证）。
    contexts = Map.fromList [(contract, effectName effect) | effect <- protoEffects prototype
      , Just contract <- [effectProduces effect]]

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

sessionRouteOf :: PrototypeIndex method -> Maybe NodeId -> String -> Maybe SessionDrive
sessionRouteOf index boundary source = Map.lookup (boundary, source) (indexRoutes index)

sessionDescriptionAt :: PrototypeIndex method -> Maybe NodeId -> String -> Maybe SessionProto
sessionDescriptionAt index boundary source = Map.lookup (boundary, source) (indexDescriptions index)

-- 读取点的静态来源；没有登记的读取只能使用本次调用的捕获。
sourcePlanAt :: PrototypeIndex method -> NodeId -> String -> Source
sourcePlanAt index node context = Map.findWithDefault FromOwnChain (node, context) (indexSources index)

sourcesAt :: PrototypeIndex method -> NodeId -> [(ReadPoint, Source)]
sourcesAt index node = Map.findWithDefault [] node (indexSourcesByNode index)

-- 与 Query.entryLabel 相同：没有 Middleware 时就是原名。
hooksLabel :: PrototypeIndex method -> NodeId -> String -> String
hooksLabel index position base = variantLabel base (Map.findWithDefault [] position (indexHooks index))

-- 契约名 → 生产它的 Context 名。
contextOf :: PrototypeIndex method -> String -> Maybe String
contextOf index contract = Map.lookup contract (indexContexts index)

-- 在该位置开启的 Scoped 及其参数来源，按原型顺序。
openingsAt :: PrototypeIndex method -> NodeId -> [ScopeOpening]
openingsAt index node = Map.findWithDefault [] node (indexOpenings index)

-- 持续资产是否从开头保留全部交付（stream @T 读取 x:xs）。
historyOf :: PrototypeIndex method -> String -> Bool
historyOf index source = Map.findWithDefault False source (indexHistories index)
