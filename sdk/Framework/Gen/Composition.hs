{-# LANGUAGE DeriveFunctor #-}
{-# LANGUAGE DuplicateRecordFields #-}

-- 组合状态机 v1（2026-11-17）。声明是输入，装配、能力和原型是计算结果。
-- 本模块拥有全部编译期组合转换；没有独立 Lower/Bind/Build 分别决定语义。
-- Source/Shape 只提供 Haskell 结构，Emit 只投影下面的结果 ADT，runtime 不导入本模块。
--
-- 阅读顺序：状态与 advanceComposition → 接口事实 → 声明/挂载 → 方法绑定 → 图/来源。
-- AwaitingBodies 是 beforegen 的接口检查点；AwaitingGraph 是结构缓存检查点。
-- 工作表/递归栈是同一计算中的局部证据，不能当作另一套装配结论或运行状态。
-- 统一入口不降低路径分析的最坏复杂度；保留先投影再组合、缺值路径与分支相关性。
module Framework.Gen.Composition
  ( beginComposition, prepareComposition, completeComposition, compositionKey
  , PendingComposition, CompositionResult(..)
  , Unit(..), Binding(..), Signature(..), AssetDeclaration(..), BranchContract(..)
  , ValueType(..), Capability(..), EntryOperation(..), ReadRoute(..), ReadView(..)
  , ReaderPlan(..), SelectorPlan(..), SessionEntry(..)
  , Assembly(..), EntryMount(..), OutputConnection(..), EntryStep(..), RawSource(..)
  , stepMethod, rawMethod, bindingCalls, unitTerminals
  , specifications, effectPrototypes, protoOf, contextSpecs, allMethods
  , reference, parenthesized
  ) where

import Control.Monad (foldM, unless, when)
import Control.Monad.State.Strict (StateT, evalStateT, execStateT, gets, lift, modify')
import Data.Char (isAlphaNum, isLower, isSpace, isUpper)
import Data.Graph (SCC(..), stronglyConnComp)
import Data.List (inits, intercalate, intersect, isPrefixOf, nub, nubBy, sort, sortOn, (\\))
import Data.Maybe (listToMaybe, maybeToList)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Framework.Gen.Names
import Framework.Language.AST (WorkflowF(..))
import Framework.Language.Registration hiding (effectKind)
import qualified Framework.Language.Registration as Registration
import Framework.Prototype.Graph
import Framework.Prototype.Query
import Framework.Prototype.Types
import Framework.Prototype.Validate (valid, unique, validatePrototype)
import qualified Framework.Prototype as Prototype
import Framework.Recursion (Fix(..), cata, Algebra)

-- 阶段携带已完成的事实，后续转换只增加依赖这些事实的结论。
-- 每次迁移在 Either 中完成后才交出下一状态；错误不会留下半份可输出的结果。
-- 多次遍历服务于不同关系（调用图/控制路径/来源），不是多套独立调度器。
data CompositionState
  = Declared String [EffectSpec] (Fix WorkflowF) SumTypes
  | Related String [EffectSpec] [EffectProto String] (Fix WorkflowF) SumTypes
  | Numbered String PrototypePlan SumTypes
  | AwaitingBodies Unit
  | ResolvingBodies Unit (Maybe [(String, MethodShape String)])
  | AwaitingGraph PendingComposition
  | BuildingStructure PendingComposition
  | ProvingSources PendingComposition (Prototype String) [MethodDefinition String] [String]
  | Checking Unit Bool (Prototype String)
  | Complete CompositionResult

data PendingComposition = PendingComposition Unit Bool [(String, MethodShape String)]

data CompositionResult = CompositionResult
  { compositionUnit :: Unit
  , compositionPrototype :: Prototype String
  }

-- 唯一状态转换入口。缓存只替换 BuildingStructure/ProvingSources；验证和驱动检查不会跳过。
advanceComposition :: CompositionState -> Either String CompositionState
advanceComposition state = case state of
  Declared namespace specifications tree sumTypes -> do
    effects <- diagnostic (buildEffectProtos specifications sumTypes)
    pure (Related namespace specifications effects tree sumTypes)
  Related namespace specifications effects tree sumTypes -> do
    workflow <- diagnostic (numberWorkflow effects tree)
    pure (Numbered namespace (PrototypePlan specifications effects workflow) sumTypes)
  Numbered namespace plan sumTypes -> do
    assembly <- diagnostic (assembleProgram plan)
    AwaitingBodies <$> bindProgram namespace plan assembly sumTypes
  ResolvingBodies unit supplied -> do
    let checked = case supplied of Just _ -> True; Nothing -> False
    methods <- composeMethods checked (unitBindings unit) (unitReads unit) (maybe [] id supplied)
    pure (AwaitingGraph (PendingComposition unit checked methods))
  BuildingStructure pending@(PendingComposition unit _ methods) -> do
    (prototype, written, readers) <- diagnostic (buildStructure (unitPlan unit) (unitAssembly unit) methods)
    pure (ProvingSources pending prototype written readers)
  ProvingSources (PendingComposition unit checked _) prototype written readers -> do
    analyzed <- diagnostic (resolveSources (assemblyOutputs (unitAssembly unit)) written readers prototype)
    pure (Checking unit checked analyzed)
  Checking unit checked prototype -> do
    diagnostic (validatePrototype prototype)
    when checked (diagnostic (checkDriven (unitAssembly unit) prototype))
    pure (Complete (CompositionResult unit prototype))
  -- 检查点等待前端补入形状/缓存，不隐式重复计算，也不靠空列表猜测首次生成。
  AwaitingBodies _ -> pure state
  AwaitingGraph _ -> pure state
  Complete _ -> pure state
  where diagnostic = either (Left . show) Right

settleComposition :: CompositionState -> Either String CompositionState
settleComposition state = case state of
  AwaitingBodies _ -> pure state
  AwaitingGraph _ -> pure state
  Complete _ -> pure state
  _ -> advanceComposition state >>= settleComposition

-- 声明加载进程返回同一机器的接口检查点。Unit 只含纯 ADT，可 Show/Read；没有 GHC AST 或类字典。
beginComposition :: String -> [EffectSpec] -> Fix WorkflowF -> SumTypes -> Either String Unit
beginComposition namespace specifications tree sumTypes = do
  state <- settleComposition (Declared namespace specifications tree sumTypes)
  case state of
    AwaitingBodies unit -> pure unit
    _ -> Left "Composition did not reach the interface checkpoint"

prepareComposition :: Unit -> Maybe [(String, MethodShape String)] -> Either String PendingComposition
prepareComposition unit shapes = do
  state <- settleComposition (ResolvingBodies unit shapes)
  case state of
    AwaitingGraph pending -> pure pending
    _ -> Left "Composition did not reach the graph checkpoint"

compositionKey :: PendingComposition -> String
compositionKey (PendingComposition unit _ methods) = show (unitPlan unit, unitAssembly unit, methods)

completeComposition :: PendingComposition -> Maybe (Prototype String) -> Either String CompositionResult
completeComposition pending@(PendingComposition unit checked _) cached = do
  state <- settleComposition (case cached of
    Just prototype -> Checking unit checked prototype
    Nothing -> BuildingStructure pending)
  case state of
    Complete result -> pure result
    _ -> Left "Composition did not complete"

-- 接口结果先有结构，再由 Emit 加 Haskell 模块限定。不能通过已渲染的 typeclass 文本重新选择装配。
data ValueType = NativeType String | RefinedType String
  deriving (Eq, Ord, Show, Read)

data Capability = ReadsType ValueType | HasRaw | EndsSource | EndsSubscription | PureMonad | IOMonad
  deriving (Eq, Show, Read)

-- 每个入口的解释已经确定；Emit 仅把该操作翻译成现有 runtime 包装，不再查看 typing。
data EntryOperation
  = AtomicOperation | OpenResource | CloseResource | SourceStep | PureOperation | PublishAsset String | ErrorOperation
  deriving (Eq, Show, Read)

-- 读取结果始终是声明的表示类型。持续来源使用固定交付；是否反复执行由挂载/会话计划决定。
-- 业务可以把记录或统计声明为普通 ADT，编译器不为这类内容另外包装或选驱动。
data ReadView = ValueView | ContinuousView | BranchView BranchContract
  deriving (Eq, Show, Read)

data ReadRoute = ReadRoute
  { routeEffect :: String, routeType :: ValueType, routeContract :: String
  , routeProvider :: String, routeReader :: String, routeView :: ReadView
  } deriving (Eq, Show, Read)

data ReaderPlan = ReaderPlan
  { readerEffect :: String, readerMethod :: String, readerContract :: String, readerContinuous :: Bool
  } deriving (Eq, Show, Read)

data SelectorPlan = SelectorPlan
  { selectorContract :: String, selectorEntry :: String
  , selectorConstructors :: [String]
  } deriving (Eq, Show, Read)

data SessionEntry
  = ReceiveEntry String (EntryMount String) (EntryMount String)
  | DeriveEntry String (EntryMount String)
  deriving (Eq, Show, Read)

typeSpelling :: ValueType -> String
typeSpelling (NativeType selected) = selected
typeSpelling (RefinedType selected) = selected

readValueType :: Unit -> ResolvedDemand -> ValueType
readValueType unit resolved = NativeType (representationOf unit (demandContract resolved))

routeOf :: Unit -> EffectSpec -> ResolvedDemand -> ReadRoute
routeOf unit specification resolved = ReadRoute (name specification) (readValueType unit resolved)
  contractType producer (readerOf unit producer) view
  where
    contractType = demandContract resolved
    producer = demandProvider resolved
    view = case [branch | branch <- unitBranches unit, branchName branch == contractType] of
      branch : _ -> BranchView branch
      _ | continuousContract unit contractType -> ContinuousView
        | otherwise -> ValueView

entryResult :: EffectSpec -> ValueType
entryResult specification = case typing specification of
  Context { asset = declared } -> RefinedType (contractOf declared)
  _ -> NativeType (resultOf specification)

entryOperation :: EffectSpec -> String -> EntryOperation
entryOperation specification method = case typing specification of
  Excu _ -> AtomicOperation
  Scoped _ _ | Just method == entryMethod specification -> OpenResource
             | otherwise -> CloseResource
  Stream _ -> SourceStep
  Pure _ -> PureOperation
  Context { asset = declared } -> PublishAsset (contractOf declared)
  Error {} -> ErrorOperation

sessionEntries :: Unit -> Assembly String -> [SessionEntry]
sessionEntries unit assembly = nubBy sameEntry
  [ entry
  | specification <- contextSpecs unit
  , session <- assemblySessions assembly
  , Just (sessionAsset session) == effectProduces (protoOf unit (name specification))
  , let entries = [mount | position <- sessionMounts session
              , mount <- assemblyMounts assembly, mountNode mount == position]
  , entry <- case (sessionPlan session, entries) of
      (Receive _, [source, parser]) -> [ReceiveEntry (name specification) source parser]
      (Derive _, [parser]) -> [DeriveEntry (name specification) parser]
      _ -> [] ]
  where
    -- 一个会话入口可用于多个挂载；只有生成的闭包定义共享，NodeId 仍保存在 Assembly/Prototype。
    -- 按完整 mount 去重会把同一来源的 finite/lifelong 入口重复输出。
    key entry = (mountTarget entry, mountMethod entry)
    sameEntry (ReceiveEntry owner a b) (ReceiveEntry owner' a' b') =
      owner == owner' && key a == key a' && key b == key b'
    sameEntry (DeriveEntry owner a) (DeriveEntry owner' a') = owner == owner' && key a == key a'
    sameEntry _ _ = False

-- ========================================================================
-- 资产来源与访问
-- ========================================================================

-- input 是 Stream 的 Context 是它的 parser：会话每取得一份原始输入就调用一次 getT。
belowStream :: [EffectSpec] -> EffectSpec -> Bool
belowStream specifications specification = case typing specification of
  Context {} -> not (null [() | source <- specifications, name source == input specification, Stream {} <- [typing source]])
  _ -> False

-- 持续资产：stream = True，按组合计划持续发布，可以被 streams 订阅。
-- 挂在 Stream 下的由会话单步驱动；Input 链上有 streams 的由上游交付驱动，已挂载的操作沿用本次输出。
continuousContext :: EffectSpec -> Bool
continuousContext specification = case typing specification of
  Context { stream = streaming } -> streaming
  _ -> False

-- 先校验整个注册集合，包括当前没有消费者的资产；不按访问模式挑选生产方。
validateAssetSources :: [EffectSpec] -> Either String ()
validateAssetSources specifications =
  unless (length names == length (nub names)) (Left "Duplicate Context contract")
  where
    names = [contractOf declared | specification <- specifications
             , Just declared <- [contextAsset (typing specification)]]

-- requires 与 streams 读取资产；requests 只驱动，不读取。
readsAccess :: Access -> Bool
readsAccess RequestAccess = False
readsAccess RequireAccess = True
readsAccess StreamAccess = True

findEffect :: [EffectSpec] -> String -> Either String EffectSpec
findEffect specifications selected = case filter ((== selected) . name) specifications of
  [specification] -> Right specification
  [] -> Left ("Unknown effect: " ++ selected)
  _ -> Left ("Duplicate effect: " ++ selected)

produced :: EffectSpec -> Maybe String
produced specification = contractOf <$> contextAsset (typing specification)

-- 资产名在注册集合中唯一，因此每个契约恰好对应一个生产方。
-- requires 需要生产方缓存（require = True），streams 需要持续资产。
-- branches：和类型资产的分支契约 → 基础契约；分支契约由基础契约的生产方提供（投影）。
resolveDemands :: [(String, String)] -> [EffectSpec] -> EffectSpec -> Either String [ResolvedDemand]
resolveDemands branches specifications consumer = do
  validateAssetSources specifications
  let keys = [(access demand, contract demand) | demand <- demands consumer]
  unless (length keys == length (nub keys)) $
    Left ("Duplicate demand in " ++ name consumer ++ "; each asset/access pair may be declared once")
  mapM resolveOne (demands consumer)
  where
    resolveOne demand = do
      let producedContract = maybe (contract demand) id (lookup (contract demand) branches)
      provider <- case [specification | specification <- specifications
            , name specification /= name consumer, produced specification == Just producedContract] of
        [specification] -> pure specification
        [] -> Left ("No Context produces contract " ++ contract demand ++ " for " ++ name consumer
          ++ "; a contract is the asset name declared by its producer Context")
        _ -> Left ("Several Context effects produce contract " ++ producedContract)
      case (access demand, typing provider) of
        (RequestAccess, _) | continuousContext provider -> Left ("Contract " ++ contract demand
          ++ " is a continuous asset produced by its session, so " ++ name consumer ++ " cannot request it")
        (RequireAccess, Context { require = False }) -> Left ("Contract " ++ contract demand
          ++ " is not cached (require = False), so " ++ name consumer ++ " cannot require it")
        (StreamAccess, _) | not (continuousContext provider) -> Left ("Contract " ++ contract demand
          ++ " is not a continuous asset (its Context declares stream = False), so "
          ++ name consumer ++ " cannot subscribe to it")
        (StreamAccess, _) | producedContract /= contract demand -> Left ("Branch contract " ++ contract demand
          ++ " cannot be subscribed; subscribe to " ++ producedContract ++ " in " ++ name consumer)
        _ -> pure ()
      pure (ResolvedDemand (access demand) (contract demand) (name provider))

-- 收集声明前提所需的 Context，按依赖顺序去重；不根据业务值合并调用。
contextNames :: [(String, String)] -> [EffectSpec] -> [String] -> Either String [String]
contextNames branches specifications selected = nub . concat <$> mapM (visit []) selected
  where
    visit _ "Root" = Right []
    visit seen selectedName
      | selectedName `elem` seen = Left ("Cyclic input/demand: " ++ selectedName)
      | otherwise = do
          specification <- findEffect specifications selectedName
          resolved <- resolveDemands branches specifications specification
          let providers = nub (map demandProvider resolved)
          upstream <- concat <$> mapM (visit (selectedName : seen)) (nub (input specification : providers))
          pure (upstream ++ providers)

-- ========================================================================
-- 声明关系与 workflow 编号
-- ========================================================================

fromRegistration :: Either String value -> Either (PrototypeError String) value
fromRegistration = either (Left . InvalidPrototype) Right

-- 注册关系的标准解析：同时完成注册级检查。之后的绑定与输出只读取这些事实，不再自行推导。
buildEffectProtos :: [EffectSpec] -> SumTypes -> Either (PrototypeError String) [EffectProto String]
buildEffectProtos specifications sumTypes = do
  valid (unique (map name specifications)) "Duplicate effect name"
  valid (all ((/= "Root") . name) specifications) "Root is reserved"
  fromRegistration (validateAssetSources specifications)
  mapM_ (\specification -> mapM_ (\demand -> valid (validContractName (contract demand))
      ("Demanded contract must be a contract name such as StartURL: " ++ contract demand
        ++ " in " ++ name specification)) (demands specification)) specifications
  resolved <- mapM (fromRegistration . resolveDemands branchTable specifications) specifications
  dependencies <- mapM (fromRegistration . contextNames branchTable specifications . pure . name) specifications
  let table = zip (map name specifications) resolved
      resolvedOf selected = maybe [] id (lookup selected table)
      providers mode specification = nub
        [demandProvider demand | demand <- resolvedOf (name specification), demandAccess demand == mode]
      requested = providers RequestAccess
      required = providers RequireAccess
      requestSource = listToMaybe . requested
      operations specification = nub (input specification : requested specification)
      scopes seen selected
        | selected `elem` seen = []
        | otherwise = concat
            [concatMap (scopes (selected : seen)) (operations specification)
              ++ [selected | Scoped {} <- [typing specification]]
            | specification <- specifications, name specification == selected]
      upstream specification = nub (concatMap (scopes []) (operations specification))
      nearest seen selected
        | selected `elem` seen = []
        | otherwise = concat
            [case typing specification of
              Scoped {} -> [selected]
              _ -> concatMap (nearest (selected : seen)) (operations specification)
            | specification <- specifications, name specification == selected]
      errorScopes specification = nub
        (concatMap (nearest [name specification]) (operations specification))
      requiredSources seen selected
        | selected `elem` seen = []
        | otherwise = nub $ concat
            [let sources = required specification
             in sources ++ concatMap (requiredSources (selected : seen)) (operations specification ++ sources)
            | specification <- specifications, name specification == selected]
      parents specification = filter (/= name specification) $ nub
        (upstream specification ++ [name owner
          | source <- requiredSources [] (name specification)
          , source `notElem` requested specification
          , owner <- specifications, Scoped (Just _) _ <- [typing owner]
          , requestSource owner == Just source])
      valueInputs seen selected
        | selected `elem` seen = []
        | otherwise = concat
            [requested producer ++ required producer
              ++ concatMap (valueInputs (selected : seen)) (requested producer)
            | producer <- specifications, name producer == selected]
      -- Context 挂接的句柄：沿一串 Pure 向上，直到 Excu 或 Scoped；中间的 Pure 只变换句柄交出的 list。
      anchorOf seen selected
        | selected `elem` seen = Nothing
        | otherwise = listToMaybe
            [ found | anchor <- specifications, name anchor == selected
            , found <- case typing anchor of
                Pure _ -> maybeToList (anchorOf (selected : seen) (input anchor))
                kind | Registration.effectKind kind `elem` [ExcuKind, ScopedKind], Just _ <- entryMethod anchor -> [name anchor]
                _ -> [] ]
      inputAncestors "Root" = []
      inputAncestors selected = selected : concat
        [inputAncestors (input specification) | specification <- specifications, name specification == selected]
      make specification contextDependencies = EffectProto
        { effectName = name specification
        , effectKind = Registration.effectKind (typing specification)
        , effectInput = input specification
        , effectMethods = registeredMethods specifications specification
        , effectDemands = resolvedOf (name specification)
        , effectProduces = contractOf <$> contextAsset (typing specification)
        , effectBranches = branchesOf specification
        , effectAnchor = case typing specification of
            Context {} -> anchorOf [] (input specification)
            _ -> Nothing
        , effectScopes = upstream specification
        , effectErrorScope = case typing specification of
            Error {} -> listToMaybe (errorScopes specification)
            _ -> Nothing
        , effectInputChain = inputAncestors (input specification)
        , effectScopeParents = parents specification
        , effectOpeningInputs = case typing specification of
            Scoped {} -> nub (concatMap (valueInputs []) (maybeToList (requestSource specification)))
            _ -> []
        , effectNearestScopes = nub (nearest [] (name specification))
        , effectResource = case typing specification of Scoped {} -> requestSource specification; _ -> Nothing
        , effectContextDependencies = contextDependencies
        , effectContinuous = continuousContext specification
        }
      prototypes = zipWith make specifications dependencies
      findSpec selected = case filter ((== selected) . name) specifications of
        [specification] -> Right specification
        _ -> Left (UnknownPrototypeTarget selected)
      checkScope selected = do
        specification <- findSpec selected
        case typing specification of
          Scoped (Just _) _ -> pure ()
          _ -> Left (InvalidPrototype ("Input scope needs Scoped.open: " ++ selected))
      boundHandlers = nub (concatMap (map snd . handlerBindings) specifications)
      checkHandled (RaisedBy selected) = valid (selected `elem` boundHandlers)
        ("RaisedBy must name a registered handler: " ++ selected)
      checkHandled (ScopeFaultIn selected) = do
        target <- findSpec selected
        valid (Registration.effectKind (typing target) == ScopedKind) ("ScopeFaultIn must name a Scoped effect: " ++ selected)
      checkHandled (ContextFaultIn selected) = do
        target <- findSpec selected
        valid (Registration.effectKind (typing target) == ContextKind) ("ContextFaultIn must name a Context effect: " ++ selected)
      check specification = do
        unless (input specification == "Root") $ do
          predecessor <- findSpec (input specification)
          valid (Registration.effectKind (typing predecessor) /= ContextKind)
            ("Input cannot reference Context " ++ name predecessor ++ " in " ++ name specification ++ "; use demands")
          valid (Registration.effectKind (typing predecessor) /= ErrorKind)
            ("Input cannot reference Error " ++ name predecessor ++ " in " ++ name specification ++ "; Error runs only for scope failures")
        mapM_ checkScope (upstream specification)
        case typing specification of
          Scoped {} -> do
            valid (length (requested specification) <= 1) ("Scoped requests at most one resource Context: " ++ name specification)
          Context { asset = declared, parser = parsing, require = requiring, stream = streaming } -> do
            -- stream 与 Input 链必须一致：链被持续驱动时，每次驱动产出一个新值，结果就是一份持续资产。
            -- 驱动有两种：直接 input 是 Stream（自己驱动），或 Input 链上有 streams demand（由那份持续资产的交付驱动）。
            -- 被驱动的链不能产出普通资产，普通链也不能声明成持续资产；持续资产也缓存最新值。
            valid (parsing /= Nothing) ("Context needs a parser handler: " ++ name specification)
            let below = belowStream specifications specification
                driving = nub [contract demand | ancestor <- specifications
                  , name ancestor `elem` inputAncestors (input specification)
                  , demand <- demands ancestor, access demand == StreamAccess]
            valid (not below || null driving) ("Context " ++ name specification
              ++ " hangs below a Stream, which drives itself; its Input chain cannot also subscribe to "
              ++ intercalate ", " driving)
            valid (length driving <= 1) ("Context " ++ name specification ++ " is driven by several continuous assets "
              ++ intercalate ", " driving ++ "; one production chain is driven by one asset")
            valid (streaming == (below || not (null driving)))
              (if streaming then "Context " ++ name specification ++ " declares stream = True but nothing drives it continuously;"
                 ++ " hang it below a Stream, or below an effect that subscribes with streams"
               else if below then "Context " ++ name specification ++ " hangs below a Stream and needs stream = True"
               else "Context " ++ name specification ++ " is driven by continuous asset " ++ intercalate ", " driving
                 ++ " (streams on its Input chain) and produces one value per delivery; declare stream = True")
            valid (not streaming || requiring) ("Context " ++ name specification ++ " declares stream = True and needs require = True")
            valid (validContractName (contractOf declared))
              ("Asset name must be a type name such as StartURL: " ++ contractOf declared ++ " in " ++ name specification)
            case representation declared of
              TypeRef _ -> pure ()
              _ -> Left (InvalidPrototype ("Context.request must wrap a business value, not Output: " ++ name specification))
            valid (null [() | anchorName <- maybeToList (anchorOf [] (input specification))
              , anchor <- specifications, name anchor == anchorName
              , Scoped {} <- [typing anchor], requestSource anchor == Just (name specification)])
              ("Context " ++ name specification ++ " cannot hang below the scope that requests it as its resource")
          -- Pure 只在生产链中：值来自上层的 raw，交给下面的 Pure 或 Context，不声明 demands。
          Pure method -> do
            valid (method /= Nothing) ("Pure needs a handler: " ++ name specification)
            valid (null (demands specification))
              ("Pure " ++ name specification ++ " takes its value from raw and declares no demands")
            upper <- if input specification == "Root"
              then Left (InvalidPrototype ("Pure " ++ name specification
                ++ " needs an Excu, Scoped or Pure input to read raw from"))
              else findSpec (input specification)
            valid (Registration.effectKind (typing upper) `elem` [ExcuKind, ScopedKind, PureKind])
              ("Pure " ++ name specification ++ " reads raw from an Excu, Scoped or Pure, not from "
                ++ name upper ++ "; a Stream has only its parser Context below it")
            let below = [Registration.effectKind (typing consumer) | consumer <- specifications, input consumer == name specification]
            valid (not (null below) && all (`elem` [ContextKind, PureKind]) below)
              ("Pure " ++ name specification ++ " is used only in a production chain: only a Context or another Pure may take it as input, and at least one must")
          Stream method -> do
            valid (method /= Nothing) ("Stream needs a handler: " ++ name specification)
            -- 只有解析器 Context 能以 Stream 为 input，否则其他方法可以绕过会话直接取原始输入。
            let below = [typing consumer | consumer <- specifications, input consumer == name specification]
                isContext selected = case selected of Context {} -> True; _ -> False
            valid (all isContext below)
              ("Only the parser Context may take Stream " ++ name specification ++ " as its input")
            valid (length below == 1)
              ("Stream " ++ name specification ++ " needs exactly one Context hanging below it as its parser")
          Error { handles = matched } -> do
            valid (not (null matched)) ("Error must declare the failures it handles: " ++ name specification)
            mapM_ checkHandled matched
            -- Error 只指向 scope；普通 effect 的失败通过提前 mock 解决，不作全局处置。
            case errorScopes specification of
              [_] -> pure ()
              [] -> Left (InvalidPrototype ("Error " ++ name specification ++ " has no scope on its Input chain; Error only handles scope failures"))
              _ -> Left (InvalidPrototype ("Error capability reaches several nearest scopes: " ++ name specification))
          _ -> pure ()
        valid (null [demand | demand <- demands specification, access demand == RequestAccess,
          contract demand `elem` map fst branchTable]) ("Branch contracts can only be required: " ++ name specification)
        valid (null [() | demand <- demands specification, access demand == StreamAccess]
          || Registration.effectKind (typing specification) `elem` [ExcuKind, ScopedKind])
          ("Only Excu and Scoped effects may subscribe with streams: " ++ name specification)
      handled specification = case typing specification of Error { handles = matched } -> matched; _ -> []
  mapM_ check specifications
  let generatedMethods = concatMap (map snd . effectMethods) prototypes
  valid (unique generatedMethods) "Generated effect method names must be unique; rename an effect or asset"
  case [selected | selected <- nub (concatMap (map snd . handlerBindings) specifications), selected `elem` generatedMethods] of
    [] -> pure ()
    selected : _ -> Left (InvalidPrototype ("Handler " ++ selected
      ++ " has the name of a generated effect method; rename the handler"))
  valid (null [(name left, name right)
    | (index, left) <- zip [0 :: Int ..] specifications, right <- drop (index + 1) specifications
    , not (null (handled left `intersect` handled right)), errorScopes left == errorScopes right])
    "Error policies handle the same failure for the same scope"
  pure prototypes
  where
    validContractName selected = case selected of
      first : rest -> isUpper first && all (\character -> isAlphaNum character || character `elem` "_'") rest
      [] -> False
    branchesOf specification = case typing specification of
      Context { asset = declared } | TypeRef typeName <- representation declared
        , Just constructors <- lookup typeName sumTypes, length constructors > 1 ->
          [(contractOf declared ++ constructor, constructor) | (constructor, _) <- constructors]
      _ -> []
    branchTable = [(branch, contractOf declared)
      | specification <- specifications, Just declared <- [contextAsset (typing specification)]
      , (branch, _) <- branchesOf specification]

-- effect 方法由 gen 生成并命名：run／open／close／detect／resolve／next 加 effect 名，get／read／stream 加资产名。
registeredMethods :: [EffectSpec] -> EffectSpec -> [(MethodRole, String)]
registeredMethods specifications specification = case typing specification of
  Pure method -> named HandlerMethod "run" method
  Excu method -> named HandlerMethod "run" method
  Scoped opening closing -> named ScopeOpen "open" opening ++ named ScopeClose "close" closing
  Error detecting resolving _ -> named ErrorDetect "detect" detecting ++ named ErrorResolve "resolve" resolving
  -- 持续资产的 getT 由会话步骤或 AST 输出挂接调用，不是可请求的生产入口。
  selected@Context {} ->
    [ (if continuousContext specification then ContextStream else ContextRequest, method)
    | method <- maybeToList (contextProducer selected) ]
    ++ [(ContextRequire, method) | method <- maybeToList (contextReader selected)]
  Stream method -> named StreamHandler "next" method
  where
    named role prefix method = [(role, effectMethodName prefix (name specification)) | Just _ <- [method]]

-- 算法说明 v1（2026-11-15）：末端来自 node 的显式选择，不从全图寻找出度为零的节点。
-- cata 给每次挂载分配 AST 路径；同一 effect 重复挂载仍保留不同 NodeId，不能按名字合并。
-- alternative 根据候选 Input 链的分支契约定位同一资产与构造器，检查完整覆盖后登记选择入口。
-- 此处不提取候选的最长公共前缀，也不改写它们的 Input；选择绑定的交接由运行协议完成。
-- 编号遍历本身随 AST 大小增长，但每处的注册查询、候选检查与 planSessions 分析另计。
numberWorkflow :: [EffectProto String] -> Fix WorkflowF -> Either (PrototypeError String) WorkflowTree
numberWorkflow effects tree = cata number tree [] False
  where
    -- inside：是否位于 lifelong 内。持续订阅只能挂在 lifelong 内；lifelong 不嵌套。
    number (Node selected) path inside = do
      effect <- findEffectProto effects selected
      valid (effectKind effect `notElem` [PureKind, ContextKind, ErrorKind, StreamKind])
        ("AST terminal must be an Excu or Scoped handle: " ++ selected
          ++ " (Pure, Context, Stream and Error run only inside their chains)")
      _ <- ordinaryEntry effect
      let subscribed = streamedAssets effects selected
      unless (inside || null subscribed) $ Left (InvalidLifelong path ("Node " ++ selected
        ++ " subscribes to " ++ intercalate ", " subscribed ++ " with streams; mount it inside lifelong"))
      pure (NodeAt path selected)
    number (Chained children) path inside = do
      nonEmpty path inside children
      ChainedAt path <$> descend path inside children
    number (Parallel children) path inside = do
      nonEmpty path inside children
      ParallelAt path <$> descend path inside children
    number (Lifelong children) path inside = do
      when inside $ Left (InvalidLifelong path "lifelong cannot be nested")
      nonEmpty path True children
      parts <- descend path True children
      -- 直接子项各为一个单元；直接子项是 parallel 时拆这一层，不穿透更深的结构。
      let units = concat [case part of
            ParallelAt _ inner -> map workflowNode inner
            _ -> [workflowNode part] | part <- parts]
      subscriptions <- mapM subscription [(node', selected) | part <- parts, NodeAt node' selected <- allWorkflow part]
      -- 先沿用本边界已经挂载的操作输出，再为其余订阅建立独立生产；副产物也登记为会话资产。
      sessions <- planSessions effects path parts subscriptions
      pure (LifelongAt path (LifelongProto units subscriptions sessions) parts)
    number (Alternative children) path inside = do
      nonEmpty path inside children
      parts <- descend path inside children
      cases <- mapM (candidateCase effects path) parts
      contractType <- case nub (map fst cases) of
        [selected] -> Right selected
        _ -> invalid path "Candidates must depend on the same branch contract"
      let constructors = map snd cases
          declared = concat [map snd (effectBranches effect) | effect <- effects, effectProduces effect == Just contractType]
      unless (unique constructors && sort constructors == sort declared) $
        invalid path "Candidates must cover every constructor exactly once"
      pure (AlternativeAt path (AlternativeProto contractType (path ++ [-1])
        (zip (map workflowNode parts) constructors)) parts)
    descend path inside children = sequence [child (path ++ [index]) inside | (index, child) <- zip [0 ..] children]
    invalid path reason = Left (InvalidAlternative path reason)
    -- lifelong 内每条成功路径都要领取新交付；挂载的 target 都订阅持续资产，所以只需拒绝空分支。
    nonEmpty path inside children = when (inside && null children) $
      Left (InvalidLifelong path "an empty branch inside lifelong never takes a delivery")
    -- 一个挂载的 target 恰好由一份持续资产驱动；链内不再读取其他持续资产的快照，
    -- 否则执行结果取决于读取时刻（多个来源的触发组合另行设计）。
    subscription (node', selected) = case streamedAssets effects selected of
      [contractType] -> do
        let others = [other | other <- continuousReads effects selected, other /= contractType]
        unless (null others) $ Left (InvalidLifelong node' ("Node " ++ selected ++ " is driven by " ++ contractType
          ++ " and also reads continuous assets " ++ intercalate ", " others ++ "; read only its driving asset"))
        pure (node', contractType)
      [] -> Left (InvalidLifelong node' ("Node " ++ selected
        ++ " inside lifelong must subscribe to exactly one continuous asset with streams"))
      several -> Left (InvalidLifelong node' ("Node " ++ selected ++ " subscribes to several continuous assets "
        ++ intercalate ", " several ++ "; one lifelong target is driven by one asset"))
-- 一条 original chain 由末端及其 Input 祖先组成；只看这些 effect 自己声明的 streams，
-- 不汇总 Context 生产链内部的依赖。
originEffects :: [EffectProto method] -> String -> [EffectProto method]
originEffects effects selected =
  [effect | effect <- effects, effectName effect `elem` (selected : concat
    [effectInputChain terminal | terminal <- effects, effectName terminal == selected])]

streamedAssets :: [EffectProto method] -> String -> [String]
streamedAssets effects selected = nub
  [demandContract demand | effect <- originEffects effects selected, demand <- effectDemands effect
  , demandAccess demand == StreamAccess]

-- 分支契约按其基础契约计入：读取持续和类型资产的分支即读取该资产。
continuousReads :: [EffectProto method] -> String -> [String]
continuousReads effects selected = nub
  [base | effect <- originEffects effects selected, demand <- effectDemands effect
  , let base = baseContract (demandContract demand)
  , producer <- effects, effectContinuous producer, effectProduces producer == Just base]
  where
    baseContract contractType = case [produced | producer <- effects, Just produced <- [effectProduces producer]
                                     , (branch, _) <- effectBranches producer, branch == contractType] of
      produced : _ -> produced
      [] -> contractType

-- ========================================================================
-- 持续生产连接及启动证明
-- ========================================================================

-- 本边界的装配先定位已由 AST 执行的原子句柄，再决定哪些资产需要独立生产。
-- 同名 effect 的不同挂载仍是不同执行；多个供值位置只允许同一单元内互斥的候选。
-- 连续副产物即使只有后继 requires，也有交付状态，不能因没有订阅而丢掉发布。
planSessions :: [EffectProto method] -> NodeId -> [WorkflowTree] -> [(NodeId, String)]
                   -> Either (PrototypeError method) [SessionProto]
planSessions effects boundary children subscriptions = do
  sessions <- mapM plan (zip [0 ..] assets)
  checkStartup sessions
  checkCoverage sessions
  pure sessions
  where
    units = concat [case child of
      ParallelAt _ inner -> map workflowNode inner
      _ -> [workflowNode child] | child <- children]
    workflow = LifelongAt boundary (LifelongProto units subscriptions []) children
    mounted = [(node', effect) | NodeAt node' selected <- concatMap allWorkflow children
      , effect <- effects, effectName effect == selected]
    -- 匹配 original chain 的 target/Input，不扫描它请求的独立 Context 链。
    positions producer = [node' | Just anchor <- [effectAnchor producer], (node', target) <- mounted
      , anchor `elem` (effectName target : effectInputChain target)]
    outputs = [contractType | producer <- effects, effectContinuous producer
      , Just contractType <- [effectProduces producer], not (null (positions producer))]
    assets = sessionAssets effects (nub (map snd subscriptions ++ outputs))
    unitOf node' = [unit | unit <- units, unit `isPrefixOf` node']
    plan (index, contractType) = do
      producer <- case [effect | effect <- effects, effectProduces effect == Just contractType] of
        [effect] -> pure effect
        _ -> Left (UnknownPrototypeTarget contractType)
      let nodes = positions producer
      -- p 个位置要做 p*(p-1)/2 次同单元/互斥检查；exclusive 自身还遍历 workflow。
      -- 并行或顺序中都可能发生的两次输出不能靠“谁先生产”合并成同一个来源。
      unless (and [unitOf left == unitOf right && exclusive workflow left right
          | (offset, left) <- zip [0 :: Int ..] nodes, right <- drop (offset + 1) nodes]) $
        Left (InvalidLifelong boundary ("Continuous asset " ++ contractType
          ++ " has several AST output positions " ++ show nodes
          ++ "; use one position, mutually exclusive positions in one unit, or refine the asset"))
      let selected = if null nodes then bootPlan effects producer else ReuseOutput nodes
      pure (SessionProto contractType selected
        [boundary ++ [-1, index, step] | step <- [0 .. sessionSteps selected - 1]])
    -- 订阅边之外，还要计入 workflow 的启动前置。否则 chained [读 A, 产 A]
    -- 虽然注册关系无环，第一条增量仍只能由正在等待它的后继产生。
    -- 保守地纳入所有候选前驱：不依赖运行时恰好选中某个分支才具有进展。
    -- SCC 只检测这份启动依赖图；发现环就拒绝，不删边来强行安排运行。
    -- 纯 SCC 阶段与图规模相关，构边前的 precedes/selectors 查询和后面的覆盖遍历另计。
    checkStartup sessions = case [cycle' | CyclicSCC cycle' <- stronglyConnComp graph] of
      [] -> pure ()
      cycle' : _ -> Left (InvalidLifelong boundary ("Continuous startup cycle: "
        ++ intercalate " -> " (map describe cycle')
        ++ "; a producer cannot wait for a target that needs its own publication"))
      where
        graph = [(key, key, dependencies) | (key, dependencies) <- edges]
        edges = [(Left node', nub (Right asset : previous node' ++ selectors node'))
          | (node', asset) <- subscriptions]
          ++ [(Right (sessionAsset session), case sessionPlan session of
              Receive _ -> []
              Derive upstream -> [Right upstream]
              ReuseOutput nodes -> map Left nodes) | session <- sessions]
        previous node' = [Left before | (before, _) <- mounted, precedes workflow before node']
        selectors node' = [Right (alternativeContract choice)
          | AlternativeAt _ choice branches <- allWorkflow workflow
          , any (\branch -> workflowNode branch `isPrefixOf` node') branches
          , alternativeContract choice `elem` map sessionAsset sessions]
        describe (Left node') = "target " ++ show node'
        describe (Right asset) = "asset " ++ asset
    -- 同一单元只有完成本轮后才能进入下一轮。每条能到达订阅的路径都必须
    -- 已经生产，或同时启动了一条必经的生产路径，不能等本单元的下一轮来补值。
    -- 其他单元独立推进，允许等待其未来发布；这里不证明原子 IO 的进展。
    checkCoverage sessions = mapM_ check
      [(node', asset, output, nodes, unit) | (node', asset) <- subscriptions
      , (output, nodes@(source : _)) <- outputOf [] asset
      , unit <- unitOf node', unit `elem` unitOf source]
      where
        outputOf seen asset
          | asset `elem` seen = []
          | otherwise = concat [case sessionPlan session of
              ReuseOutput nodes -> [(sessionAsset session, nodes)]
              Derive upstream -> outputOf (asset : seen) upstream
              Receive _ -> []
            | session <- sessions, sessionAsset session == asset]
        check (node', asset, output, nodes, unit) = do
          -- open 复用已有实例时不执行原子方法，也没有新输出。经过该位置不能
          -- 证明本轮有交付；独立单元可以等待以后真正开启产生的输出或正常结束。
          unless (null [() | producer <- effects, effectProduces producer == Just output
              , Just anchorName <- [effectAnchor producer], anchor <- effects
              , effectName anchor == anchorName, effectKind anchor == ScopedKind]) $
            Left (InvalidLifelong node' ("Subscription to " ++ asset
              ++ " waits for a Scoped output within the same unit; reusing an open scope produces no new output"))
          case lookupWorkflow workflow unit of
            Just tree -> unless (covered nodes node' False tree) $
              Left (InvalidLifelong node' ("Subscription to " ++ asset
                ++ " has a workflow path without an output from " ++ show nodes
                ++ " in the same unit; that unit cannot reach its next execution while waiting"))
            Nothing -> Left (InvalidLifelong unit "Missing unit for an output subscription")
        covered sources target available tree = case tree of
          NodeAt node' _ -> node' /= target || available
          ChainedAt _ parts -> sequenceCovered parts available
          ParallelAt _ parts -> and
            [covered sources target (available || any (produces sources) others) child
            | child <- parts, let others = filter ((/= workflowNode child) . workflowNode) parts]
          _ -> all (covered sources target available) (workflowChildren tree)
          where
            sequenceCovered [] _ = True
            sequenceCovered (child : rest) ready = covered sources target ready child
              && sequenceCovered rest (ready || produces sources child)
        produces sources tree = case tree of
          NodeAt node' _ -> node' `elem` sources
          AlternativeAt _ _ parts -> not (null parts) && all (produces sources) parts
          _ -> any (produces sources) (workflowChildren tree)

-- ========================================================================
-- 入口与输出连接事实
-- ========================================================================

-- 调用顺序仍是 requests → Input → handler。角色用于保留装配依据；
-- 相同方法出现在两个步骤时仍执行两次，不能按名字或结构去重。
data EntryStep method = RequestStep method | InputStep method
  deriving (Eq, Show, Read)

stepMethod :: EntryStep method -> method
stepMethod (RequestStep method) = method
stepMethod (InputStep method) = method

-- raw 的直接输入在本模块的绑定转换中解析。Stream 单步产 String，需要包装成单元素 list；
-- 其余输入交出 list。是否已有本次输出由现有 replay 协议决定，不缓存另一调用的结果。
data RawSource method = RawList method | RawStream method
  deriving (Eq, Show, Read)

rawMethod :: RawSource method -> method
rawMethod (RawList method) = method
rawMethod (RawStream method) = method

-- 一个静态挂载；NodeId 保留每次 AST 出现的位置，同方法不合并挂载。
-- terminal 是结构展示的末端/契约，target 是运行入口的诊断标签：
-- 会话中 terminal 是资产名，target 分别是 Stream 与 parser 的 effect 名。
data EntryMount method = EntryMount
  { mountNode :: NodeId
  , mountRole :: ChainRole
  , mountTerminal :: String
  , mountTarget :: String
  , mountMethod :: method
  } deriving (Eq, Show, Read)

-- 同次输出的连接：anchor → parser。role 区分普通吞错注入与持续失败传播；
-- 每次注入只能回放当前 anchor，不能借此跳过其他前驱。
data OutputConnection method = OutputConnection
  { outputAnchor :: method
  , outputParser :: method
  , outputProducer :: String
  , outputRole :: MethodRole
  } deriving (Eq, Show, Read)

data Assembly method = Assembly
  { assemblyMounts :: [EntryMount method]
  , assemblyOutputs :: [OutputConnection method]
  , assemblySessions :: [SessionProto]
  , assemblyFiniteSessions :: [SessionProto]
  } deriving (Eq, Show, Read)

assembleProgram :: PrototypePlan -> Either (PrototypeError String) (Assembly String)
assembleProgram plan = do
  mounted <- concat <$> mapM mountedNode (allWorkflow workflow)
  selectors <- mapM mountedSelector [selected | selected@AlternativeAt {} <- allWorkflow workflow]
  sessions <- concat <$> mapM mountedSession
    describedSessions
  pure (Assembly (mounted ++ selectors ++ sessions) outputs describedSessions finite)
  where
    effects = plannedEffects plan
    workflow = plannedWorkflow plan
    finite = finiteSessions effects
    describedSessions = concatMap (lifelongSessions . snd) (workflowLifelongs workflow) ++ finite
    mountedNode (NodeAt identifier selected) = do
      effect <- findEffectProto effects selected
      method <- ordinaryEntry effect
      pure [EntryMount identifier NodeChain selected selected method]
    mountedNode _ = pure []
    mountedSelector (AlternativeAt _ selected _) = case
      [method | effect <- effects, effectProduces effect == Just (alternativeContract selected)
        , Just method <- [selectorMethod effect]] of
      [method] -> pure (EntryMount (alternativeSelector selected) SelectorChain
        (alternativeContract selected) (alternativeContract selected) method)
      _ -> Left (UnknownPrototypeTarget (alternativeContract selected))
    mountedSelector _ = Left (InvalidPrototype "Expected alternative selector")
    mountedSession described = do
      producer <- case [effect | effect <- effects, effectProduces effect == Just (sessionAsset described)] of
        [effect] -> pure effect
        _ -> Left (UnknownPrototypeTarget (sessionAsset described))
      let entry effect role = case lookup role (effectMethods effect) of
            Just method -> pure (effectName effect, method)
            Nothing -> Left (InvalidPrototype ("Session for " ++ sessionAsset described
              ++ " has no " ++ show role ++ " method"))
      steps <- case sessionPlan described of
        Receive source -> do
          streamEffect <- findEffectProto effects source
          handle <- entry streamEffect StreamHandler
          parser <- entry producer ContextStream
          pure [handle, parser]
        Derive _ -> (: []) <$> entry producer ContextStream
        -- 沿用 AST 输出，不另建生产步骤；位置证据已经在 planSessions 的 BootPlan 中检查。
        ReuseOutput _ -> pure []
      valid (length steps == length (sessionMounts described)) ("Session steps differ for " ++ sessionAsset described)
      pure [EntryMount mount SessionChain (sessionAsset described) target method
        | (mount, (target, method)) <- zip (sessionMounts described) steps]
    -- 保留原注入顺序：同一 anchor 内先普通 Context，再持续 Context，各自按注册顺序。
    outputs =
      [ OutputConnection anchorMethod parser (effectName producer) role
      | anchor <- effects, (anchorRole, anchorMethod) <- effectMethods anchor
      , anchorRole `elem` [HandlerMethod, ScopeOpen]
      , role <- [ContextRequest, ContextStream], producer <- effects
      , effectAnchor producer == Just (effectName anchor)
      , Just parser <- [lookup role (effectMethods producer)] ]

-- ========================================================================
-- 接口能力、读取路由与方法组成
-- ========================================================================

-- 一次绑定：handler 在某个 effect 方法中执行。
-- before 保存有角色的有序步骤（先驱动，后 Input），raw 保存直接 Input 及其输出形状；
-- routes 把规范化的表示类型映射到 (契约, 读取方法)。结构分析据此把 handler 方法体换成 effect 方法的结构。
data Binding = Binding
  { bindingEffect :: String
  , bindingMethod :: String
  , bindingHandler :: String
  , bindingBefore :: [EntryStep String]
  , bindingRaw :: Maybe (RawSource String)
  , bindingRoutes :: [(String, (String, String))]
  , bindingResult :: ValueType
  , bindingOperation :: EntryOperation
  , bindingCapabilities :: [Capability]
  } deriving (Eq, Show, Read)

-- handler 的签名由绑定类别与 effect 的 demands 推出；同一 handler 的所有绑定必须一致。
-- layer 不含 Raises：它总是本 handler 的错误，由输出时补入。
data Signature = Signature
  { signatureHandler :: String
  , signatureResult :: ValueType
  , signatureLayer :: [Capability]
  , signatureEffects :: [String]
  } deriving (Eq, Show, Read)

-- 每个 Context 的契约类型由声明的资产名生成。
data AssetDeclaration = AssetDeclaration
  { assetContract :: String
  , assetRepresentation :: TypeRef
  , assetOwner :: String
  } deriving (Eq, Show, Read)

-- 表示类型是和类型（至少两个构造器）时，每个构造器另有分支契约：契约名加构造器名。
-- 分支契约是基础契约的投影，读到构造器的字段（无字段为 ()）。
data BranchContract = BranchContract
  { branchName :: String
  , branchBase :: String
  , branchConstructor :: String
  , branchField :: Maybe String
  , branchOwner :: String
  } deriving (Eq, Show, Read)

-- 一份程序的绑定结果：降级计划加上 gen 推出的资产、分支契约、handler 签名、绑定与末端入口。
data Unit = Unit
  { unitNamespace :: String
  , unitPlan :: PrototypePlan
  , unitAssets :: [AssetDeclaration]
  , unitBranches :: [BranchContract]
  , unitHandlers :: [String]
  , unitSignatures :: [Signature]
  , unitBindings :: [Binding]
  -- 已解析的挂载与输出连接；构图、来源分析与输出共用。
  , unitAssembly :: Assembly String
  -- effect → handler 方法体必须读取的契约（requires／streams 中没有被 workflow 控制流使用的部分）。
  , unitReads :: [(String, [String])]
  , unitRoutes :: [ReadRoute]
  , unitReaders :: [ReaderPlan]
  , unitSelectors :: [SelectorPlan]
  , unitSessionEntries :: [SessionEntry]
  , unitScopeOrder :: [String]
  } deriving (Eq, Show, Read)

-- 绑定阶段的入口：推出全部事实，再按原顺序检查生成名字、末端、表示类型与签名。
bindProgram :: String -> PrototypePlan -> Assembly String -> SumTypes -> Either String Unit
bindProgram namespace prepared assembly sumTypes = do
  checkGenerated unit
  when (null (unitTerminals unit)) (Left "Select at least one terminal effect for generation")
  mapM_ (checkRepresentations unit) (specifications unit)
  signatures <- mapM (signatureOf unit) (unitHandlers unit)
  pure unit { unitSignatures = signatures }
  where
    unit = Unit
      { unitNamespace = namespace
      , unitPlan = prepared
      , unitAssets = assets
      , unitBranches = branches
      , unitHandlers = nub [handler' | specification <- specifications unit, (_, handler') <- handlerBindings specification]
      , unitSignatures = []
      , unitBindings =
          [ Binding (name specification) method handler' (beforeOf unit specification method)
              (if readsRaw specification method then rawSource unit specification else Nothing)
              [ (normalizeType (typeSpelling (routeType route)), (routeContract route, routeReader route))
              | route <- unitRoutes unit, routeEffect route == name specification ]
              (entryResult specification) (entryOperation specification method) (layerOf unit specification method)
          | specification <- specifications unit, (method, handler') <- handlerBindings specification ]
      , unitAssembly = assembly
      , unitRoutes = [routeOf unit specification resolved
          | specification <- specifications unit, not (null (handlerBindings specification))
          , resolved <- readDemands unit (name specification)]
      , unitReaders = [ReaderPlan (name specification) method (contractOf declared)
            (Prototype.effectContinuous (protoOf unit (name specification)))
          | specification <- contextSpecs unit
          , Just method <- [contextReader (typing specification)]
          , Just declared <- [contextAsset (typing specification)]]
      , unitSelectors = [SelectorPlan contractType method
            [branchConstructor branch | branch <- branches, branchBase branch == contractType]
          | (contractType, method) <- nub [(mountTerminal mount, mountMethod mount)
              | mount <- assemblyMounts assembly, mountRole mount == SelectorChain]]
      , unitSessionEntries = sessionEntries unit assembly
      , unitScopeOrder = nub (concat [Prototype.effectScopes effect
          ++ [Prototype.effectName effect | Prototype.effectKind effect == ScopedKind]
          | effect <- effectPrototypes unit])
      , unitReads =
          [ (name specification, nub
              [ demandContract resolved | resolved <- resolvedOf unit (name specification), readsAccess (demandAccess resolved)
              , (name specification, demandContract resolved) `notElem` controlled ])
          | specification <- specifications unit ]
      }
    controlled = controlReads (Prototype.plannedEffects prepared) (Prototype.plannedWorkflow prepared)
    assets =
      [ AssetDeclaration (contractOf declared) (representation declared) (name specification)
      | specification <- contextSpecs unit
      , Just declared <- [contextAsset (typing specification)] ]
    branches =
      [ BranchContract (base ++ constructor) base constructor field owner
      | AssetDeclaration base (TypeRef typeName) owner <- assets
      , (branch, constructor) <- Prototype.effectBranches (protoOf unit owner)
      , Just constructors <- [lookup typeName sumTypes]
      , Just field <- [lookup constructor constructors]
      , branch == base ++ constructor ]

specifications :: Unit -> [EffectSpec]
specifications = Prototype.plannedRegistrations . unitPlan

effectPrototypes :: Unit -> [Prototype.EffectProto String]
effectPrototypes = Prototype.plannedEffects . unitPlan

protoOf :: Unit -> String -> Prototype.EffectProto String
protoOf unit selectedName = case [effect | effect <- effectPrototypes unit, Prototype.effectName effect == selectedName] of
  effect : _ -> effect
  [] -> error ("Validated prototype has no effect: " ++ selectedName)

specOf :: Unit -> String -> EffectSpec
specOf unit selectedName = case [specification | specification <- specifications unit, name specification == selectedName] of
  specification : _ -> specification
  [] -> error ("Validated registration has no effect: " ++ selectedName)

resolvedOf :: Unit -> String -> [ResolvedDemand]
resolvedOf unit = Prototype.effectDemands . protoOf unit

contextSpecs :: Unit -> [EffectSpec]
contextSpecs = filter ((== ContextKind) . Registration.effectKind . typing) . specifications

allMethods :: Unit -> [String]
allMethods unit = [method | effect <- effectPrototypes unit, (_, method) <- Prototype.effectMethods effect]

continuousContract :: Unit -> String -> Bool
continuousContract unit contractType = or
  [ Prototype.effectContinuous (protoOf unit (assetOwner declared))
  | declared <- unitAssets unit, assetContract declared == contractType ]

-- 契约读到的表示类型：基础契约是声明的表示类型，分支契约是构造器的字段（无字段为 ()）。
representationOf :: Unit -> String -> String
representationOf unit contractType = case [branch | branch <- unitBranches unit, branchName branch == contractType] of
  branch : _ -> maybe "()" id (branchField branch)
  [] -> case [reference (assetRepresentation declared) | declared <- unitAssets unit, assetContract declared == contractType] of
    found : _ -> found
    [] -> error ("Validated demand has no asset: " ++ contractType)

-- 读取方式影响驱动关系，不改变资产表示；本轮交付和有限读取都捕获声明的同一个 T。
readType :: Unit -> ResolvedDemand -> String
readType unit resolved = representationOf unit (demandContract resolved)

readDemands :: Unit -> String -> [ResolvedDemand]
readDemands unit selectedName = nubBy (\left right -> demandContract left == demandContract right)
  [resolved | resolved <- resolvedOf unit selectedName, readsAccess (demandAccess resolved)]

readerOf :: Unit -> String -> String
readerOf unit provider = case contextReader (typing (specOf unit provider)) of
  Just method -> method
  Nothing -> error ("Validated demand has no reader: " ++ provider)

-- 驱动：requests 声明的资产在入口先调用 getT，沿 Input 驱动它的整条 Context 链。
drives :: Unit -> EffectSpec -> [String]
drives unit specification =
  [ getter | resolved <- resolvedOf unit (name specification), demandAccess resolved == RequestAccess
  , Just getter <- [contextProducer (typing (specOf unit (demandProvider resolved)))] ]

-- 挂接的 parser 与 Pure 用 raw 读取直接 Input 的输出，不把 Input 当前驱执行：
-- Input 是 Excu、Scoped、Pure 时读它交出的 list，是 Stream 时读会话本次取得的一份输入。
rawSource :: Unit -> EffectSpec -> Maybe (RawSource String)
rawSource unit specification
  | rawKind (typing specification), input specification /= "Root" = case typing (specOf unit (input specification)) of
      Excu _ -> RawList <$> entryMethod (specOf unit (input specification))
      Scoped {} -> RawList <$> entryMethod (specOf unit (input specification))
      Pure _ -> RawList <$> entryMethod (specOf unit (input specification))
      Stream _ -> RawStream <$> entryMethod (specOf unit (input specification))
      _ -> Nothing
  | otherwise = Nothing
  where
    rawKind Context {} = True
    rawKind (Pure _) = True
    rawKind _ = False

-- 读取 raw 的方法：Context 的 parser（生产入口）与 Pure 的入口。
readsRaw :: EffectSpec -> String -> Bool
readsRaw specification method = case typing specification of
  selected@Context {} -> Just method == contextProducer selected
  Pure _ -> Just method == entryMethod specification
  _ -> False

-- 其他 Input 是前驱：在 handler 之前执行一次，输出不交给 handler。
predecessor :: Unit -> EffectSpec -> [String]
predecessor unit specification
  | input specification == "Root" = []
  | Just _ <- rawSource unit specification = []
  | otherwise = maybeToList (entryMethod (specOf unit (input specification)))

-- 算法说明 v2（2026-11-16）：绑定时计算一次，composeMethods 与 Emit 都读取 bindingBefore。
-- 先 requests 驱动，再 Input 前驱，最后 handler；close 与 Error 方法只执行 handler。
-- 即使驱动链与 Input 链包含相同方法，也不能在这里 nub：两个声明的调用仍是两次执行。
-- raw 的同次输出回放与 scope 的活实例共享在各自协议中判定，不由方法名相同推出。
-- handler 绑定复用只复用实现，不合并不同 effect 的路由或不同挂载的调用。
beforeOf :: Unit -> EffectSpec -> String -> [EntryStep String]
beforeOf unit specification method
  | Just method == entryMethod specification =
      map RequestStep (drives unit specification) ++ map InputStep (predecessor unit specification)
  | otherwise = []

bindingCalls :: Binding -> [String]
bindingCalls = map stepMethod . bindingBefore

-- Target 的实现可共用，挂载身份仍全部保存在 assemblyMounts；这里只投影生成的入口目录。
unitTerminals :: Unit -> [(String, String)]
unitTerminals unit = nub [(mountTerminal mount, mountMethod mount)
  | mount <- assemblyMounts (unitAssembly unit), mountRole mount == Prototype.NodeChain]

-- 绑定类别决定方法类型：原子句柄与 Pure 都交出 [String]。
resultOf :: EffectSpec -> String
resultOf specification = case typing specification of
  Pure _ -> "[String]"
  Excu _ -> "[String]"
  Scoped {} -> "[String]"
  Error {} -> "()"
  Stream _ -> "String"
  Context { asset = declared } -> reference (representation declared)

layerOf :: Unit -> EffectSpec -> String -> [Capability]
layerOf unit specification method = map ReadsType
  (sortOn typeSpelling (nub [routeType route | route <- unitRoutes unit, routeEffect route == name specification]))
  ++ [HasRaw | readsRaw specification method, Just _ <- [rawSource unit specification]]
  ++ [EndsSource | Registration.effectKind (typing specification) == StreamKind]
  ++ [EndsSubscription | consumesStream unit specification]
  ++ [if Registration.effectKind (typing specification) == PureKind then PureMonad else IOMonad]

-- 算法说明 v2（2026-11-17）：endStream 给哪些 effect。
-- 只给自己以 streams 订阅持续资产的 Excu：它是被持续资产驱动的消费方，endStream 结束的是它自己的订阅。
-- 同一条链上的其他 effect（Input 前驱）和 lifelong 里不订阅的普通节点是原子操作，lifelong 只是插入它们的控制流，
-- handler 的签名不随所处的控制流改变，因而可以在持续链与有限链之间复用。
-- streams 只出现在被驱动的位置（lifelong 节点的订阅、持续 Context 被驱动的 Input 链），
-- 运行时按当前调用的位置确定订阅，不需要业务说明结束哪一份资产。
-- 只给 Excu：Scoped.open 被打断会使实例失效，Pure 是值变换，Stream 用 streamEnd。
-- 代价：每个 effect 查一次自己的 demand。
consumesStream :: Unit -> EffectSpec -> Bool
consumesStream unit specification = Registration.effectKind (typing specification) == ExcuKind
  && or [Prototype.demandAccess demand == StreamAccess | demand <- Prototype.effectDemands (protoOf unit (name specification))]

signatureOf :: Unit -> String -> Either String Signature
signatureOf unit handler' = do
  let bound = [(bindingEffect binding, (NativeType (resultOf (specOf unit (bindingEffect binding))), bindingCapabilities binding))
        | binding <- unitBindings unit, bindingHandler binding == handler']
  case nub (map snd bound) of
    [(result, layer)] -> pure (Signature handler' result layer (nub (map fst bound)))
    _ -> Left ("Handler " ++ handler' ++ " is bound with different signatures: "
      ++ intercalate "; " [effect ++ " needs m (" ++ typeSpelling result ++ ") with " ++ intercalate ", " (map show layer) | (effect, (result, layer)) <- bound]
      ++ "; reuse a handler only where the binding kind and representation reads agree")

-- 一个 effect 内每种表示类型至多出现一次；同类型的两个值需要角色类型（待定）。
checkRepresentations :: Unit -> EffectSpec -> Either String ()
checkRepresentations unit specification = do
  let keys = [(normalizeType (readType unit resolved), demandContract resolved) | resolved <- readDemands unit (name specification)]
  case [representation' | (representation', _) <- keys, length (filter ((== representation') . fst) keys) > 1] of
    representation' : _ -> Left ("Effect " ++ name specification ++ " reads several assets of representation "
      ++ representation' ++ " (" ++ intercalate ", " [contractType | (key, contractType) <- keys, key == representation']
      ++ "); one effect reads each representation type at most once")
    [] -> pure ()

-- 资产名与 handler 派生名都进入生成区的同一命名空间，不能重名或与固定名冲突。
checkGenerated :: Unit -> Either String ()
checkGenerated unit = do
  let declared = map assetContract (unitAssets unit) ++ map branchName (unitBranches unit)
      derived = concat [[handlerClass handler', handlerLayer handler', handlerError handler', handlerFailure handler'] | handler' <- unitHandlers unit]
      reserved = reservedTypes ++ derived
  case [contractType | contractType <- nub declared, length (filter (== contractType) declared) > 1] of
    contractType : _ -> Left ("Contract " ++ contractType ++ " comes from more than one asset or branch; rename one of them")
    [] -> pure ()
  case [contractType | contractType <- nub declared, contractType `elem` reserved] of
    contractType : _ -> Left ("Asset or branch contract " ++ contractType
      ++ " collides with a generated name; rename the asset or constructor")
    [] -> pure ()
  case [handler' | handler' <- unitHandlers unit, not (validMethodName handler') || handler' `elem` reservedValues] of
    handler' : _ -> Left ("Handler name must be a lowercase identifier not used by generated code: " ++ handler')
    [] -> pure ()
  mapM_ (\(AssetDeclaration contractType representation' owner) -> do
      unless (validTypeName contractType) $
        Left ("Asset name must be a type name such as StartURL: " ++ contractType ++ " in " ++ owner)
      case representation' of
        TypeRef _ -> pure ()
        _ -> Left ("Context asset must wrap a business value, not Output: " ++ owner))
    (unitAssets unit)
  where
    validTypeName selectedName = case selectedName of
      first : rest -> isUpper first && all (\character -> isAlphaNum character || character `elem` "_'") rest
      [] -> False
    validMethodName selectedName = case selectedName of
      first : rest -> isLower first && all (\character -> isAlphaNum character || character `elem` "_'") rest
      [] -> False

reference :: TypeRef -> String
reference (TypeRef typeName) = typeName
reference (OutputRef cause value) = "SDK.Output (" ++ reference cause ++ ") (" ++ reference value ++ ")"

-- 含空格且尚未整体括起的类型加括号。
parenthesized :: String -> String
parenthesized selected
  | any (== ' ') selected && not (enclosed selected) = "(" ++ selected ++ ")"
  | otherwise = selected
  where enclosed text = take 1 text `elem` ["(", "["] && last text `elem` ")]" && balanced text
        balanced text = all (> 0) (init (scanl1 (+) (map depth text)))
        depth character
          | character `elem` "([" = 1 :: Int
          | character `elem` ")]" = -1
          | otherwise = 0

-- 表示类型的比较形式：去掉模块限定与括号，String、FilePath 展开为 [Char]（与 Typeable 的写法一致）。
normalizeType :: String -> String
normalizeType = unwords . concatMap expand . filter (`notElem` ["(", ")"]) . tokens
  where
    expand token = case unqualified token of
      "String" -> ["[", "Char", "]"]
      "FilePath" -> ["[", "Char", "]"]
      other -> [other]
    unqualified token = case break (== '.') token of
      (first : _, '.' : rest) | isUpper first, not (null rest) -> unqualified rest
      _ -> token
    tokens [] = []
    tokens (character : rest)
      | isSpace character = tokens rest
      | character `elem` "()[]," = [character] : tokens rest
      | otherwise = let (word, remaining) = break (\next -> isSpace next || next `elem` "()[],") (character : rest)
                    in word : tokens remaining

-- workflow 控制流已经使用的读取：lifelong 订阅的 streams，以及 alternative 候选选择所依据的分支契约。
-- 输入链上的声明参与选择／交付，因此这些 demand 不要求 handler 方法体再读一次。
controlReads :: [Prototype.EffectProto method] -> Prototype.WorkflowTree -> [(String, String)]
controlReads effects tree = nub (walk tree ++ driven)
  where
    -- 持续资产生产链上的 streams 由上游交付驱动这条链，同样已被控制流使用。
    driven = [ (Prototype.effectName effect, demandContract demand) | producer <- effects, Prototype.effectContinuous producer
      , effect <- effects, Prototype.effectName effect `elem` Prototype.effectInputChain producer
      , demand <- Prototype.effectDemands effect, demandAccess demand == StreamAccess ]
    inherited selectedName = selectedName : concat
      [Prototype.effectInputChain effect | effect <- effects, Prototype.effectName effect == selectedName]
    demandsOf selectedName = [(Prototype.effectName effect, demand) | effect <- effects
      , Prototype.effectName effect `elem` inherited selectedName, demand <- Prototype.effectDemands effect]
    walk node' = here node' ++ concatMap walk (Prototype.workflowChildren node')
    here (Prototype.LifelongAt _ description _) =
      [ (consumer, demandContract demand) | (path, contractType) <- Prototype.lifelongSubscriptions description
      , Just (Prototype.NodeAt _ selectedName) <- [Prototype.lookupWorkflow tree path]
      , (consumer, demand) <- demandsOf selectedName
      , demandAccess demand == StreamAccess, demandContract demand == contractType ]
    here (Prototype.AlternativeAt _ description _) =
      [ (consumer, demandContract demand) | (path, constructor) <- Prototype.alternativeCases description
      , Just subtree <- [Prototype.lookupWorkflow tree path]
      , selectedName <- Prototype.workflowTerminals subtree
      , (consumer, demand) <- demandsOf selectedName, readsAccess (demandAccess demand)
      , producer <- effects, Prototype.effectProduces producer == Just (Prototype.alternativeContract description)
      , (branch, selectedConstructor) <- Prototype.effectBranches producer
      , branch == demandContract demand, selectedConstructor == constructor ]
    here _ = []

-- 结构分析给出每个 handler 方法体的结构：@T 是按表示类型的读取，%raw 是 raw。
-- 每个绑定按自己的路由把它们换成 effect 方法调用，前面接上驱动与 Input 前驱，得到 effect 方法的结构。
-- 同时检查 handler 读取的表示类型都有声明，raw 只用于挂接的 parser，声明的读取都被方法体或控制流使用。
composeMethods :: Bool -> [Binding] -> [(String, [String])] -> [(String, MethodShape String)]
               -> Either String [(String, MethodShape String)]
composeMethods checkReads bindings required handlerShapes = do
  composed <- mapM compose bindings
  when checkReads $ mapM_ (checkUsed composed) required
  pure [(bindingMethod binding, shape) | (binding, shape, _) <- composed]
  where
    compose binding = do
      let body = maybe Empty id (lookup (bindingHandler binding) handlerShapes)
      (mapped, contracts) <- resolve binding body
      pure (binding, sequenceShape (map Call (bindingCalls binding) ++ [mapped]), contracts)
    resolve binding shape = case shape of
      Empty -> pure (Empty, [])
      Call ('@' : typeText) -> case lookup (normalizeType typeText) (bindingRoutes binding) of
        Just (contractType, reader) -> pure (Call reader, [contractType])
        Nothing -> Left ("Handler " ++ bindingHandler binding ++ " reads " ++ typeText ++ " in " ++ bindingEffect binding
          ++ ", whose demands give " ++ describe (bindingRoutes binding)
          ++ "; declare requires/streams for an asset of that representation")
      Call "%raw" -> case bindingRaw binding of
        Just source -> pure (Call (rawMethod source), [])
        Nothing -> Left ("Handler " ++ bindingHandler binding ++ " uses raw in " ++ bindingEffect binding
          ++ "; only a Context parser or a Pure hanging below an Excu, Scoped, Pure or Stream reads raw")
      Call other -> pure (Call other, [])
      Sequence children -> combine Sequence children
      Choice children -> combine Choice children
      Recover body recovery -> do
        (left, first) <- resolve binding body
        (right, second) <- resolve binding recovery
        pure (Recover left right, first ++ second)
      where
        combine constructor children = do
          resolved <- mapM (resolve binding) children
          pure (constructor (map fst resolved), concatMap snd resolved)
    describe [] = "no readable asset"
    describe routes = intercalate ", " [representation' ++ " (" ++ contractType ++ ")" | (representation', (contractType, _)) <- routes]
    checkUsed composed (effect, contracts) = do
      let used = nub (concat [read' | (binding, _, read') <- composed, bindingEffect binding == effect])
          missing = filter (`notElem` used) contracts
      unless (null missing) $ Left ("Effect " ++ effect ++ " declares asset(s) its handlers never read: "
        ++ intercalate ", " missing ++ "; read them with require in the handler or remove the demands")
    sequenceShape shapes = case concatMap flatten shapes of
      [] -> Empty
      [shape] -> shape
      remaining -> Sequence remaining
    flatten Empty = []
    flatten (Sequence children) = children
    flatten shape = [shape]

-- ========================================================================
-- 方法图与原型组装
-- ========================================================================

-- 算法说明 v2（2026-11-16）：依赖顺序是“已解析 Assembly + 已组成方法”→ EffectGraph
-- → 路径 ScopeTree + 注册前提 → 链事实上的来源/开启计划 → 自洽与驱动检查。
-- Assembly 同时供 Emit 与来源证明使用，挂载及 anchor/parser 连接不在这里重新推导。
-- 挂载表保留每个 NodeId；entries 的 nub 只避免从相同静态方法重复建根，运行仍逐挂载启动。
-- logical 另含挂接生产的可达边，供驱动/读取查询；不能把它当作执行顺序或 scope 路径。
buildStructure :: PrototypePlan -> Assembly String -> [(String, MethodShape String)]
                       -> Either (PrototypeError String) (Prototype String, [MethodDefinition String], [String])
buildStructure plan assembly shapes = do
  valid (unique (map fst shapes)) "Duplicate handler method in the structure generation plan"
  valid (all (`elem` map methodIdentity defaults) (map fst shapes)) "Unregistered handler method in the structure generation plan"
  let definitions = mergedDefinitions effects connections defaults shapes
      bodyOf = writtenBody defaults shapes
  -- 注入只回放挂接句柄：Context 只能直接或经一串 Pure 读到句柄，不能经其他方法再到达它。
  valid (null [(anchor, produced) | connection <- connections
      , let anchor = outputAnchor connection
            produced = outputParser connection
      , anchor `elem` reachableMethods definitions (calledMethods (replayedBody effects bodyOf anchor (bodyOf produced)))])
    "An injected Context reaches its anchor through another method; read the anchor with raw, directly or through Pure"
  let mounts = assemblyMounts assembly
      sessions = [mount | mount <- mounts, mountNode mount `elem` concatMap sessionMounts lifelongSessionsOf]
      entries = nub (map mountMethod mounts)
      logical = withProducerReferences connections definitions
  graph <- either (Left . InvalidEffectGraph) Right (buildEffectGraph definitions (Choice (map Call entries)))
  names <- mapM scopeName orderedScopes
  declared <- mapM (scopeDeclaration names) orderedScopes
  scopes <- either (Left . InvalidEffectGraph) Right (completeScopeTree declared (buildScopeTree graph))
  let makeChain mount = ChainProto (mountNode mount) (mountRole mount) (mountTerminal mount) (mountMethod mount)
        (reachableMethods logical [mountMethod mount]) [] []
        (maybe [] id (lookup (mountMethod mount) (graphRootPaths graph)))
      chainDefinitions = [ChainDefinition kind (effectName effect) method (reachableMethods logical [method])
        | effect <- effects, (role, method) <- effectMethods effect
        , Just kind <- [case role of
            HandlerMethod -> Just OriginChain
            ScopeOpen -> Just OriginChain
            ContextRequest -> Just ContextChain
            ContextRequire -> Just ContextChain
            ContextStream -> Just ContextChain
            StreamHandler -> Just ContextChain
            _ -> Nothing]]
      written = [definition { methodBody = maybe (methodBody definition) id
          (lookup (methodIdentity definition) shapes) } | definition <- defaults]
      defaultReaders = [methodIdentity definition | definition <- defaults
        , methodRole definition == ContextRequire, methodIdentity definition `notElem` map fst shapes]
      result = Prototype (plannedRegistrations plan) effects definitions workflow finite
        (map makeChain mounts) chainDefinitions graph scopes names [] []
  -- Stream 的方法只经会话执行：Stream 单步执行它取得下一份原始输入；挂在该 Stream 下的解析器调用它时，
  -- 由会话本次取得的输入回答，与挂在原子句柄下的 Context 调用句柄相同。其他方法直接调用会绕过会话另取一份。
  let streamMethods = [(effectName effect, method) | effect <- effects, (StreamHandler, method) <- effectMethods effect]
      parsing = [(parser, method) | effect <- effects, (ContextStream, parser) <- effectMethods effect
        , (source, method) <- streamMethods, source == effectInput effect]
  mapM_ (\definition -> case [called | called <- calledMethods (methodBody definition), called `elem` map snd streamMethods
        , (methodIdentity definition, called) `notElem` parsing] of
      [] -> pure ()
      called : _ -> Left (InvalidPrototype ("Method " ++ methodIdentity definition ++ " calls Stream method "
        ++ called ++ " directly; only its session and the parser Context hanging below that Stream may call it")))
    [definition | definition <- definitions, methodRole definition /= StreamHandler]
  -- 启动环：会话的生产链不能依赖其他持续资产，否则首次生产就要先等待另一份增量。
  -- 驱动它的那份上游资产除外：每一步在领取一条上游交付之后才执行，读到的就是这条交付。
  let continuousMethods = [(contractType, method) | effect <- effects, effectContinuous effect
        , Just contractType <- [effectProduces effect], (role, method) <- effectMethods effect
        , role == ContextRequire]
      drivenBy terminal = concat [drivingAssets effects producer
        | producer <- effects, effectProduces producer == Just terminal]
  mapM_ (\chain -> do
      let others = nub [contractType | (contractType, method) <- continuousMethods
            , method `elem` chainReaches chain, contractType /= chainTerminal chain
            , contractType `notElem` drivenBy (chainTerminal chain)]
      unless (null others) $ Left (InvalidLifelong (chainNode chain) ("Production of continuous asset "
        ++ chainTerminal chain ++ " depends on continuous assets " ++ intercalate ", " others
        ++ "; its first delivery would wait for another stream")))
    [makeChain mount | mount <- sessions]
  -- 沿用 AST 输出的 parser 没有独立会话挂载，但仍须遵守相同的读取边界。
  -- 只分析交接后的 parser（raw 对 anchor 的调用已抹去），避免把合法下游消费算进来。
  mapM_ (\(session, nodes) -> do
      producer <- case [effect | effect <- effects, effectProduces effect == Just (sessionAsset session)] of
        [effect] -> pure effect
        _ -> Left (UnknownPrototypeTarget (sessionAsset session))
      parser <- maybe (Left (InvalidPrototype "Reused output has no parser")) Right
        (lookup ContextStream (effectMethods producer))
      anchor <- maybe (Left (InvalidPrototype "Reused output has no atomic anchor")) (findEffectProto effects)
        (effectAnchor producer) >>= ordinaryEntry
      let reached = reachableMethods logical
            (calledMethods (replayedBody effects bodyOf anchor (bodyOf parser)))
          others = nub [contractType | (contractType, method) <- continuousMethods
            , method `elem` reached, contractType `notElem` drivingAssets effects producer]
          position = case nodes of first : _ -> first; [] -> []
      unless (null others) $ Left (InvalidLifelong position ("Parser for reused output " ++ sessionAsset session
        ++ " reads other continuous assets " ++ intercalate ", " others
        ++ "; it may read only the asset driving the original operation")))
    [(session, nodes) | session <- lifelongSessionsOf, ReuseOutput nodes <- [sessionPlan session]]
  pure (result, written, defaultReaders)
  where
    connections = assemblyOutputs assembly
    effects = plannedEffects plan
    workflow = plannedWorkflow plan
    lifelongSessionsOf = concatMap (lifelongSessions . snd) (workflowLifelongs workflow)
    finite = assemblyFiniteSessions assembly
    -- 读取入口不调用生产方法：require 缺值时等待发布，图中没有读取到生产的边。
    defaults = [MethodDefinition method owner role Empty
      | effect <- effects, (_, owner) : _ <- [effectMethods effect], (role, method) <- effectMethods effect]
    orderedScopes = filter hasOpening $ nub
      (concat [effectScopes effect ++ [effectName effect | effectKind effect == ScopedKind] | effect <- effects])
    hasOpening selected = any (\effect -> effectName effect == selected
      && ScopeOpen `elem` map fst (effectMethods effect)) effects
    scopeName selected = do
      effect <- findEffectProto effects selected
      case lookup ScopeOpen (effectMethods effect) of
        Just opening -> pure (opening, selected)
        Nothing -> Left (InvalidPrototype ("Scope has no open method: " ++ selected))
    scopeDeclaration names selected = do
      effect <- findEffectProto effects selected
      method <- maybe (Left (UnknownPrototypeTarget selected)) Right (lookup selected [(name', identity) | (identity, name') <- names])
      parents <- mapM (\parent -> maybe (Left (UnknownPrototypeTarget parent)) Right
        (lookup parent [(name', identity) | (identity, name') <- names])) (effectScopeParents effect)
      pure (method, parents)

mergedDefinitions :: [EffectProto String] -> [OutputConnection String] -> [MethodDefinition String] -> [(String, MethodShape String)]
                  -> [MethodDefinition String]
mergedDefinitions effects connections defaults shapes =
  [definition { methodBody = injected (methodIdentity definition) (bodyOf (methodIdentity definition)) } | definition <- defaults]
  where
    bodyOf = writtenBody defaults shapes
    injected selected body = case
      [replayedBody effects bodyOf selected (bodyOf (outputParser connection))
      | connection <- connections, outputAnchor connection == selected] of
      [] -> body
      contexts -> Sequence [body, Choice [Empty, Sequence contexts]]

writtenBody :: [MethodDefinition String] -> [(String, MethodShape String)] -> String -> MethodShape String
writtenBody defaults shapes selected = case lookup selected shapes of
  Just shape -> shape
  Nothing -> maybe Empty methodBody (listToMaybe [definition | definition <- defaults, methodIdentity definition == selected])

-- 同次输出复用（算法说明 v2）：沿 Assembly 的连接改写注入副本，原生产方法仍可独立驱动。
-- 连接与生成的注入表同源；这里消除的是分析副本中的回放调用，不修改手写方法体。
-- 挂接 Context 的 raw 到达 anchor 时由已有输出回答，所以该调用在副本中是 Empty；
-- 中间 Pure 的结构就地展开，以便保留其读取/控制结构，同时消去对 anchor 的重复执行边。
-- 这只消除“句柄输出交给自己的 parser，parser 又索取同次输出”的结构回边；
-- 不是寻找任意公共前缀，也不任意断开业务依赖。其他回到 anchor 的路径由前面的检查拒绝。
replayedBody :: [EffectProto String] -> (String -> MethodShape String) -> String -> MethodShape String -> MethodShape String
replayedBody effects bodyOf anchor = replay []
  where
    pureMethods = [method | effect <- effects, effectKind effect == PureKind, (_, method) <- effectMethods effect]
    replay seen shape = case shape of
      Call method
        | method == anchor -> Empty
        | method `elem` pureMethods, method `notElem` seen -> replay (method : seen) (bodyOf method)
      Sequence children -> Sequence (map (replay seen) children)
      Choice children -> Choice (map (replay seen) children)
      Recover body recovery -> Recover (replay seen body) (replay seen recovery)
      other -> other

withProducerReferences :: Eq method => [OutputConnection method] -> [MethodDefinition method] -> [MethodDefinition method]
withProducerReferences connections definitions =
  [definition { methodBody = Sequence (methodBody definition : [Call (outputParser connection)
      | connection <- connections, outputAnchor connection == methodIdentity definition]) }
  | definition <- definitions]

-- 首次尚无 Handlers 时仅生成契约；有源码快照后必须另外执行这个驱动检查。
checkDriven :: Assembly String -> Prototype String -> Either (PrototypeError String) ()
checkDriven assembly prototype = valid (null undriven)
  ("Context never driven from the AST: " ++ intercalate ", " undriven
    ++ "; no terminal reaches its production or the handle it hangs below")
  where
    reached = reachableMethods (withProducerReferences (assemblyOutputs assembly) (protoMethods prototype))
      (map chainEntry (protoChains prototype))
    undriven = [methodIdentity definition | definition <- protoMethods prototype
      , methodRole definition == ContextRequest, methodIdentity definition `notElem` reached]

-- ========================================================================
-- 共享方法摘要与 ScopeTree
-- ========================================================================

data AnalysisF method next
  = EmptyLayer
  | MethodLayer (MethodDefinition method) next
  | SequenceLayer [next]
  | ChoiceLayer [next]
  | RecoverLayer next next
  deriving Functor

-- v2：保留 zygo 的两份 algebra，但在方法引用上共享归约结果，不先建立按调用次数复制的 Fix 树。
-- 缓存只含纯结构摘要；Sequence 的每个 Call 仍按原顺序参与组合，业务执行没有去重。
-- require 的读取方法不连到生产方法。scope 记在 open 方法体之后，同一路径只留首次完成。
type Summary method = ([[method]], EffectGraph method)
type GraphAnalysis method = StateT (Map.Map method (Summary method)) (Either (GraphError method))

buildEffectGraph
  :: Ord method
  => [MethodDefinition method]
  -> MethodShape method
  -> Either (GraphError method) (EffectGraph method)
buildEffectGraph definitions shape = do
  table <- foldM insertDefinition Map.empty definitions
  snd <$> evalStateT (analyzeShape table Set.empty shape) Map.empty
  where
    insertDefinition table definition
      | Map.member selected table = Left (DuplicateMethod selected)
      | otherwise = Right (Map.insert selected definition table)
      where selected = methodIdentity definition

-- active 是当前栈，memo 只含已经完成的定义：共享前段可复用摘要，递归回边仍必须拒绝。
-- N 个定义、E 个可达方法体结构位置，索引与引用检查约 O((N+E) log(N+1))；
-- 这不包含摘要的合并、nub 和 scope 路径组合。独立条件仍可能形成指数路径族。
-- 资产来源分析依赖入口、捕获和前态，不得套用这里“只按方法身份”的缓存。
analyzeShape
  :: Ord method
  => Map.Map method (MethodDefinition method)
  -> Set.Set method
  -> MethodShape method
  -> GraphAnalysis method (Summary method)
analyzeShape definitions active shape = case shape of
  Empty -> pure (summarize EmptyLayer)
  Call selected
    | Set.member selected active -> lift (Left (RecursiveMethod selected))
    | otherwise -> do
        cached <- gets (Map.lookup selected)
        case cached of
          Just summary -> pure summary
          Nothing -> case Map.lookup selected definitions of
            Nothing -> lift (Left (UnknownMethod selected))
            Just definition -> do
              body <- analyzeShape definitions (Set.insert selected active) (methodBody definition)
              let summary = summarize (MethodLayer definition body)
              modify' (Map.insert selected summary)
              pure summary
  Sequence children -> summarize . SequenceLayer <$> mapM next children
  Choice children -> summarize . ChoiceLayer <$> mapM next children
  Recover body recovery -> do
    before <- next body
    after <- next recovery
    pure (summarize (RecoverLayer before after))
  where
    next = analyzeShape definitions active

-- 辅助结果和主结果共用本层的 scope 路径；主 algebra 不再重复调用辅助 algebra。
summarize :: Eq method => AnalysisF method (Summary method) -> Summary method
summarize layer = (scopePathsHere, graphAlgebra scopePathsHere layer)
  where scopePathsHere = scopeAlgebra (fmap fst layer)

scopeAlgebra :: Eq method => Algebra (AnalysisF method) [[method]]
scopeAlgebra EmptyLayer = [[]]
scopeAlgebra (MethodLayer definition body)
  | methodRole definition == ScopeOpen = paths (map (++ [methodIdentity definition]) body)
  | otherwise = body
scopeAlgebra (SequenceLayer children) = paths (foldr combine [[]] children)
  where combine before after = [left ++ right | left <- before, right <- after]
scopeAlgebra (ChoiceLayer []) = [[]]
scopeAlgebra (ChoiceLayer children) = paths (concat children)
-- 正文可在任意位置失败；包括首个 scope 之前，不假定已完成整个正文。
scopeAlgebra (RecoverLayer body recovery) = paths
  (body ++ [prefix ++ after | before <- body, prefix <- inits before, after <- recovery])

-- zygo 的辅助结果是子结构的 scope 路径，主结果汇总方法图和顺序证据。
-- 图信息不依赖业务值，构图期间不会调用 handler。
-- nubBy/nub 只规范化方法目录、引用边和路径证据；MethodDefinition 内的 Sequence/Call 未去重。
-- scope 路径按定义只留首次完成，是构树投影；不能据其长度判断 open 次数或实际使用计数。
graphAlgebra
  :: Eq method
  => [[method]]
  -> AnalysisF method ([[method]], EffectGraph method)
  -> EffectGraph method
graphAlgebra scopePathsHere layer = EffectGraph
  { graphMethods = nubBy sameMethod (localMethods ++ concatMap graphMethods children)
  , graphRoots = nub roots
  , graphReferences = nub (localReferences ++ concatMap graphReferences children)
  , graphScopes = nub (concat scopePathsHere)
  , graphScopePaths = scopePathsHere
  , graphRootPaths = case layer of
      MethodLayer definition _ -> [(methodIdentity definition, scopePathsHere)]
      _ -> concatMap graphRootPaths children
  , graphScopeOrder = pathOrder scopePathsHere
  }
  where
    (localMethods, roots, localReferences, children) = case layer of
      EmptyLayer -> ([], [], [], [])
      MethodLayer definition (_, body) ->
        let selected = methodIdentity definition
        in ([definition], [selected], [(selected, child) | child <- graphRoots body], [body])
      SequenceLayer parts -> branch parts
      ChoiceLayer parts -> branch parts
      RecoverLayer body recovery -> branch [body, recovery]
    branch parts = ([], concatMap (graphRoots . snd) parts, [], map snd parts)
    sameMethod left right = methodIdentity left == methodIdentity right

paths :: Eq method => [[method]] -> [[method]]
paths = nub . map nub

pathOrder :: Eq method => [[method]] -> [(method, method)]
pathOrder = nub . concatMap orderedPairs
  where
    orderedPairs [] = []
    orderedPairs (before : rest) = [(before, after) | after <- rest] ++ orderedPairs rest

-- A precedes B 当且仅当每条包含 B 的路径都包含更早的 A。
-- 这给出共同必经前序的 DAG，不证明资源依赖，也不证明未确定的节点彼此独立。
-- 相反方向证据来自单条路径内的顺序，不能由跨路径的传递闭包代替。
-- 无环依据（v1）：A≺B 且 B≺C 时，每条含 C 的路径必依次含 A、B，故 A≺C；
-- 路径已按定义去重，A 不可能先于自身。关系传递且反自反，才能做传递约简与分层。
-- 只对出现过的 B 求交，避免空路径族上的全称判断；不是对候选边并集删 SCC。
-- 复杂度包含路径扫描、每条路径的成对顺序和传递约简；当前约简枚举关系边×中介节点，
-- 并用列表做成员查询，nub 也有二次比较开销，不能等同于一次线性图遍历。
buildScopeTree :: Ord method => EffectGraph method -> ScopeTree method
buildScopeTree graph = ScopeTree
  { scopeRoots = [selected | selected <- nodes, null (parents selected)]
  , scopeNodes = [ScopeNode selected (parents selected) (children selected) | selected <- nodes]
  , scopeLayers = layers nodes
  , scopePaths = observedPaths
  , scopeCandidates = candidates
  , scopeOpposed = opposed
  , scopeUndetermined =
      [(left, right) | left <- nodes, right <- nodes, left < right,
                       (left, right) `notElem` precedes, (right, left) `notElem` precedes,
                       (left, right) `notElem` opposed]
  }
  where
    observedPaths = paths (graphScopePaths graph)
    nodes = sort (nub (concat observedPaths))
    candidates = sort (pathOrder observedPaths)
    opposed = [edge | edge@(before, after) <- candidates, (after, before) `elem` candidates]
    predecessors selected = case [takeWhile (/= selected) path | path <- observedPaths, selected `elem` path] of
      [] -> []
      first : rest -> foldl intersect first rest
    -- 完整前序只用于构树；对外以父子边表达，不再保留第二份关系结构。
    precedes = sort [(before, after) | after <- nodes, before <- predecessors after]
    reduced =
      [(before, after) | (before, after) <- precedes,
        not (any (\middle -> (before, middle) `elem` precedes && (middle, after) `elem` precedes) nodes)]
    parents selected = [before | (before, after) <- reduced, after == selected]
    children selected = [after | (before, after) <- reduced, before == selected]
    layers [] = []
    layers remaining = ready : layers (remaining \\ ready)
      where ready = [selected | selected <- remaining, all (`notElem` remaining) (parents selected)]

-- 注册前提补入同一份树。注册前提是依赖：上游 scope 必须比下游活得久，关闭下游时仍可能读取上游资源。
-- 观察到的开启顺序是证据：逐条补入，与注册前提及已补入的边构成相反方向的不作为父边。
-- 路径、候选与反向证据仍保持原观察结果，被推翻的顺序仍在 scopeCandidates 中；不把路径候选的并集当依赖。
-- 声明顺序保留给独立 scope；运行清理使用最终父边的逆拓扑顺序。
-- 环处理（v1）：声明前提不能删除，若自身有环，layers 报 CyclicScopeRelations。
-- 观察边只在 child 不能到达 parent 时加入；放弃的是不相容的观察证据，不是声明的业务依赖。
-- ancestors/observedAncestors 当前递归展开后才 nub，未按节点记忆化；共享祖先很多的 DAG
-- 也可能重复遍历，性能估算须连同路径数量计算，不能仅引用拓扑排序的复杂度。
completeScopeTree
  :: Ord method
  => [(method, [method])]
  -> ScopeTree method
  -> Either (GraphError method) (ScopeTree method)
completeScopeTree declared tree = do
  mapM_ checkParent [parent | (_, parents') <- declared, parent <- parents']
  completedLayers <- layers nodes
  let ancestors selected = nub
        (parents selected ++ concatMap ancestors (parents selected))
      precedes = [(before, after) | after <- nodes, before <- ancestors after]
      reduced =
        [(before, after) | (before, after) <- precedes,
          not (any (\middle -> (before, middle) `elem` precedes
            && (middle, after) `elem` precedes) nodes)]
      completedParents selected = [before | (before, after) <- reduced, after == selected]
      completedChildren selected = [after | (before, after) <- reduced, before == selected]
  pure tree
    { scopeRoots = [selected | selected <- nodes, null (completedParents selected)]
    , scopeNodes = [ScopeNode selected (completedParents selected) (completedChildren selected)
        | selected <- nodes]
    , scopeLayers = completedLayers
    }
  where
    nodes = nub (map fst declared ++ map scopeIdentity (scopeNodes tree))
    -- 观察关系取完整前序（父边的传递闭包），被推翻的边不会经由其他观察边间接保留。
    observedParents selected = concat [scopeParents node | node <- scopeNodes tree, scopeIdentity node == selected]
    observedAncestors selected = nub
      (observedParents selected ++ concatMap observedAncestors (observedParents selected))
    observed = sort [(before, scopeIdentity node) | node <- scopeNodes tree
                    , before <- observedAncestors (scopeIdentity node)]
    relationships = foldl admit
      (nub [(parent, selected) | (selected, parents') <- declared, parent <- parents']) observed
    admit accepted edge@(parent, child)
      | edge `elem` accepted || reaches accepted child parent = accepted
      | otherwise = accepted ++ [edge]
    reaches edges from target = search [from] []
      where
        search [] _ = False
        search (current : rest) seen
          | current == target = True
          | current `elem` seen = search rest seen
          | otherwise = search ([next | (previous, next) <- edges, previous == current] ++ rest) (current : seen)
    parents selected = [parent | (parent, child) <- relationships, child == selected]
    checkParent parent
      | parent `elem` nodes = Right ()
      | otherwise = Left (UnknownScope parent)
    layers [] = Right []
    layers remaining =
      let ready = [selected | selected <- remaining, all (`notElem` remaining) (parents selected)]
      in if null ready
        then Left (CyclicScopeRelations remaining)
        else (ready :) <$> layers (remaining \\ ready)

-- ========================================================================
-- 路径状态与来源证明
-- ========================================================================

-- 来源算法 v3（2026-11-17）：会话读取记录开启参数，保留 FromSession 及实际交付身份。
-- 状态机收进该运算时不改变证明规则：先按消费单元/后续读取投影，再组合候选状态。
-- k 个仍相关的独立可选发布可以形成 2^k 个状态；nub 只合并相等状态，最坏二次比较。
-- 不以全局发布并集替代路径，不将方法摘要的缓存当作带捕获和前态的来源缓存。

-- 生成期只跟踪“已经发布／捕获了哪个 origin”，不求值业务值。
-- Nothing 表示持续交付；资源保留本链的开启位置，但不进入普通资产发布表。
data AssetState = AssetState
  -- 可跨链路由的发布位置与资产契约；有 owner 的资源不进入这份普通来源表。
  { assetPublications :: [(NodeId, String)]
  -- 本条分析路径已捕获的契约及其位置；Nothing 表示不按普通发布路由的捕获。
  , assetCaptures :: [(String, Maybe NodeId)]
  -- 只在本条链内传播：其他节点成功开启的资源不能成为隐式读取来源。
  , assetOpened :: [String]
  -- 当前 open 协议实际取得的参数；已有捕获本身不等于开启已经观察过它。
  , assetInputs :: [(String, [(String, Maybe NodeId)])]
  } deriving (Eq, Show)

-- Bool 为本出口是否成功；失败出口保留此前事实，供 Recover 或吞错注入继续分析。
data AssetExit = AssetExit Bool AssetState deriving (Eq, Show)

-- 跨候选状态累计最终查询事实；裁剪中间状态时不能丢掉这些已观察的读取/生产。
data AssetFacts = AssetFacts
  { assetDrives :: [(NodeId, String)]
  , assetReads :: [(ReadPoint, [NodeId])]
  , assetScopeOpenings :: [ScopeOpening]
  }

-- 当前分析调用的环境；不表示 runtime 调用对象。重放句柄与活动方法分别防止
-- 注入时重复执行原子句柄，以及未被声明允许的递归展开。assetRelevant 是本次出口仍需保留的契约。
data AssetCall = AssetCall
  { assetRoot :: NodeId
  , assetCaller :: Maybe String
  , assetOpenings :: [String]
  , assetReplays :: [String]
  , assetActiveMethods :: [String]
  , assetClosing :: Bool
  , assetRelevant :: [String]
  }

type AssetAnalysis = StateT AssetFacts (Either (PrototypeError String))

-- 可选生产保留为状态分支：A 未发布的路径上 B 的 require 只能等待，故 A/B 不会被
-- 简单的 may-set 误报为共存来源。parallel 从相同输入独立分析，随后合并发布。
-- require 不生产：没有可见发布的路径停在这次读取，不从读取返回。状态按有限事实去重，不展开任何业务 IO。
-- 只保留本链或后续 workflow 可能读取的契约；在方法出口就裁剪，避免无关注入
-- 的成功／失败组合先指数展开。仍保留活跃契约之间的相关性，不退化为 may-set。
resolveSources :: [OutputConnection String] -> [MethodDefinition String] -> [String] -> Prototype String
               -> Either (PrototypeError String) (Prototype String)
resolveSources connections definitions defaultReaders prototype = do
  facts <- flip execStateT (AssetFacts [] [] []) $ do
    _ <- workflow (protoWorkflow prototype) [] [] []
    -- interpreter 托管的会话各自从空环境启动，不是任何读取点的可见前驱。
    mapM_ (\mount -> root mount [] [] []) (concatMap sessionMounts (protoSessions prototype))
  let reads = [(point, if readContract point `elem` receiving then FromSession
                       else if null sources then FromOwnChain else FromChains (sort (nub sources)))
        | (point, sources) <- assetReads facts]
      annotate chain = chain
        { chainDrives = sort (nub [contractType | (node', contractType) <- assetDrives facts, node' == chainNode chain])
        , chainReads = sort (nub [readContract point | (point, _) <- reads, readNode point == chainNode chain])
        }
  mapM_ companionRead reads
  mapM_ successorRead reads
  pure prototype { protoChains = map annotate (protoChains prototype), protoSources = reads
    , protoScopeOpenings = assetScopeOpenings facts }
  where
    effects = protoEffects prototype
    lifelongs = workflowLifelongs (protoWorkflow prototype)
    -- lifelong 之后读取持续资产：读已经结束的那个 lifelong 会话的最新一条，不另行启动来源。
    -- 先后排列的多个 lifelong 有同一会话时读最近结束的那个；互不先后（例如并行）时“最近”取决于调度，拒绝。
    successorRead (point, FromSession) =
      let ended = [boundary | (boundary, described) <- lifelongs
            , precedes (protoWorkflow prototype) boundary (readNode point)
            , readContract point `elem` map sessionAsset (lifelongSessions described)]
          unordered = [(left, right) | left <- ended, right <- ended, left < right
            , not (precedes (protoWorkflow prototype) left right || precedes (protoWorkflow prototype) right left)]
      in case unordered of
        (left, right) : _ -> Left (InvalidLifelong (readNode point) ("Asset " ++ readContract point
          ++ " is streamed by the lifelongs at " ++ show left ++ " and " ++ show right
          ++ ", which are not ordered; which one ended last depends on scheduling. Order them, or refine the contract"))
        [] -> pure ()
    successorRead _ = pure ()
    -- 有限读取 v1（2026-11-17）：派生来源与直接来源共用托管会话计划。
    -- 读取边只给本次调用一个固定值；反复执行仍只来自 lifelong 订阅或生产链的 Derive。
    -- 因而这里不再以“没有相应 lifelong”拒绝派生资产，也不把 require 纳入订阅表。
    -- 后继读取 lifelong 内部发布的资产：资产按来源保留最新一次发布（require 读最新值）。
    -- 同一单元内互斥位置（不同 alternative 候选）在不同轮发布同一契约时，按轮次先后取最新，不是并发写入；
    -- 来自不同单元、同一轮可能都发布、或与 lifelong 之外的来源并存时，仍按来源唯一规则拒绝。
    unitsAll = concat [lifelongUnits described | (_, described) <- lifelongs]
    retainedChoice reader sources = case nub [unit | source' <- sources, unit <- unitsAll, unit `isPrefixOf` source'] of
      [unit] -> all (unit `isPrefixOf`) sources
        && not (any (`isPrefixOf` reader) [boundary | (boundary, _) <- lifelongs, boundary `isPrefixOf` unit])
        && and [exclusive (protoWorkflow prototype) left right | left <- sources, right <- sources, left /= right]
      _ -> False
    -- 会话生产步骤的其他普通发布随交付读取（伴随发布），每一步都会替换。读取位置必须在调用前
    -- 已经领取该会话的交付：由该资产驱动的 Node，或以它为转折资产的选择读取；否则读到哪一步取决于调度。
    companionRead (point, FromChains nodes) = do
      let producers = nub [sessionAsset session | (_, described) <- lifelongs
            , session <- lifelongSessions described, any (`elem` sessionMounts session) nodes]
          taken = [contractType | (_, described) <- lifelongs
              , (node', contractType) <- lifelongSubscriptions described, node' == readNode point]
            ++ [alternativeContract choice | AlternativeAt _ choice _ <- allWorkflow (protoWorkflow prototype)
              , alternativeSelector choice == readNode point]
          stray = filter (`notElem` taken) producers
      unless (null stray) $ Left (InvalidLifelong (readNode point) ("Asset " ++ readContract point
        ++ " is published by the production step of " ++ intercalate ", " stray
        ++ " and is replaced at every delivery; read it only in targets driven by " ++ intercalate ", " stray
        ++ ", or produce it before the lifelong"))
    companionRead _ = pure ()
    resources = [source | effect <- effects, Just source <- [effectResource effect]]
    resourceContracts = [contractType | effect <- effects, effectName effect `elem` resources
      , Just contractType <- [effectProduces effect]]
    resourceOwners = [(contractType, effectName scope) | scope <- effects
      , producer <- effects, effectResource scope == Just (effectName producer)
      , Just contractType <- [effectProduces producer]]
    receiving = [contractType | effect <- effects, effectContinuous effect
      , Just contractType <- [effectProduces effect]]
    -- 复用已完成的可达性分析：链能到达读取入口的契约。生产入口只生产，不再按调用方路由成读取；
    -- 不依赖尚未算出的 chainReads。
    possibleReads = [(chainNode chain, nub
      [contractType | effect <- effects, Just contractType <- [effectProduces effect]
        , Just reader <- [lookup ContextRequire (effectMethods effect)], reader `elem` chainReaches chain])
      | chain <- protoChains prototype]
    readsAt node' = maybe [] id (lookup node' possibleReads)
    readsIn tree = nub (localReads ++ concatMap readsIn (workflowChildren tree))
      where
        localReads = case tree of
          NodeAt node' _ -> readsAt node'
          AlternativeAt _ selected _ -> readsAt (alternativeSelector selected)
          LifelongAt _ described _ -> concatMap readsAt (concatMap sessionMounts (lifelongSessions described))
          _ -> []
    retainPublications relevant = filter ((`elem` relevant) . snd)
    retainState relevant state = state
      { assetPublications = retainPublications relevant (assetPublications state)
      , assetCaptures = filter ((`elem` relevant) . fst) (assetCaptures state)
      -- 开启事实只服务本链资源读取；无关的可选 open 不能使已等价的状态继续分叉。
      , assetOpened = sort [scope | scope <- assetOpened state
          , scope `elem` [owner | (contractType, owner) <- resourceOwners, contractType `elem` relevant]]
      }
    retainExit relevant (AssetExit succeeded state) = AssetExit succeeded (retainState relevant state)
    -- Workflow 失败后没有恢复分支；读取／生产事实已单独记录，失败产物不再传给后继。
    -- 方法层的失败仍保留相关状态，供 Recover 和吞错注入继续分析。
    retainOutcome relevant (succeeded, publications) =
      (succeeded, if succeeded then retainPublications relevant publications else [])
    effectFor :: String -> AssetAnalysis (EffectProto String)
    effectFor method = case [effect | effect <- effects, method `elem` map snd (effectMethods effect)] of
      [effect] -> pure effect
      _ -> lift (Left (InvalidPrototype ("Asset analysis has no effect for method " ++ method)))
    definitionFor :: String -> AssetAnalysis (MethodDefinition String)
    definitionFor method = case [definition | definition <- definitions, methodIdentity definition == method] of
      [definition] -> pure definition
      _ -> lift (Left (InvalidPrototype ("Asset analysis has no body for method " ++ method)))
    capture :: String -> Maybe NodeId -> AssetState -> AssetState
    capture contractType origin state = state
      { assetCaptures = sort ((contractType, origin) : filter ((/= contractType) . fst) (assetCaptures state)) }
    recordRead :: NodeId -> String -> [NodeId] -> AssetAnalysis ()
    recordRead node' contractType sources = modify' $ \facts ->
      let point = ReadPoint node' contractType
          previous = maybe [] id (lookup point (assetReads facts))
          updated = (point, nub (previous ++ sources))
      in facts { assetReads = updated : filter ((/= point) . fst) (assetReads facts) }
    recordDrive :: NodeId -> String -> AssetAnalysis ()
    recordDrive node' contractType = modify' $ \facts -> facts
      { assetDrives = nub ((node', contractType) : assetDrives facts) }
    -- 只从本路径已捕获的参数记录出处，保留 alternative 的交接；不能用 chainDrives
    -- 把条件生产的位置一律判成多例。跨路径只合并候选及已观察到的类别。
    openingInputs :: EffectProto String -> AssetState -> Maybe [(String, Maybe NodeId)]
    openingInputs effect state = sequence
      [ do observed <- lookup (effectName effect) (assetInputs state)
           origin <- lookup source observed
           pure (source, origin)
      | source <- effectOpeningInputs effect ]
    recordOpening :: AssetCall -> EffectProto String -> AssetState -> AssetAnalysis ()
    recordOpening call effect state = case openingInputs effect state of
      Nothing -> pure ()
      Just inputs -> modify' $ \facts ->
        let node' = assetRoot call
            same opening = openingNode opening == node' && openingScope opening == effectName effect
            previous = filter same (assetScopeOpenings facts)
            sources = [(source, if continuous source then FromSession else FromChains
                (sort (nub ([node | Just node <- [origin]] ++ concat
                  [old | opening <- previous, (selected, FromChains old) <- openingSources opening, selected == source]))))
              | (source, origin) <- inputs]
            continuous source = any (\producer -> effectName producer == source && effectContinuous producer) effects
            possible | null inputs = [RegistrationSingleton]
                     | any (\(source, origin) -> origin == Just node' && source `notElem` resources
                         && not (continuous source)) inputs = [ExecutionMultiple]
                     -- 会话可交接本轮输出，也可交付独立生产的值；运行时按实际 Binding 判定，
                     -- 不能因为没有普通 NodeId 捕获就漏掉整个开启位置。
                     | any (continuous . fst) inputs = [ProductionSingleton, ExecutionMultiple]
                     -- owner 的本链 open 也可能复用前驱实例；资源自身不进入普通来源表。
                     | any ((== Just node') . snd) inputs = [ProductionSingleton, ExecutionMultiple]
                     | otherwise = [ProductionSingleton]
            kinds = sort (nub (possible ++ concatMap openingKinds previous))
            opening = ScopeOpeningPlan node' (effectName effect) sources kinds
        in facts { assetScopeOpenings = opening : filter (not . same) (assetScopeOpenings facts) }
    observeOpeningInput :: AssetCall -> EffectProto String -> AssetState -> AssetAnalysis AssetState
    observeOpeningInput call producer state = case assetOpenings call of
      selected : _ -> case [scope | scope <- effects, effectName scope == selected
          , effectName producer `elem` effectOpeningInputs scope] of
        [scope] -> do
          let observed = maybe [] id (lookup selected (assetInputs state))
              origin = effectProduces producer >>= (\contractType -> lookup contractType (assetCaptures state))
              updated = case origin of
                Nothing -> observed
                Just source -> (effectName producer, source) : filter ((/= effectName producer) . fst) observed
              after = state { assetInputs = (selected, updated) : filter ((/= selected) . fst) (assetInputs state) }
          recordOpening call scope after
          pure after
        _ -> pure state
      [] -> pure state
    checkResourceRead :: AssetCall -> EffectProto String -> AssetState -> AssetAnalysis ()
    checkResourceRead call effect state =
      let owners = [effectName scope | scope <- effects, effectResource scope == Just (effectName effect)]
          available = assetOpenings call ++ assetOpened state
      in unless (null owners || assetClosing call || any (`elem` available) owners) $
        lift (Left (InvalidPrototype ("Resource " ++ effectName effect ++ " read at " ++ show (assetRoot call)
          ++ " requires its Scoped to be opened in the same chain: " ++ intercalate ", " owners)))
    -- 在已经捕获的路径上不查询外部来源；所有缺值路径使用同一静态候选表。
    readAsset :: AssetCall -> EffectProto String -> AssetState -> AssetAnalysis [AssetExit]
    readAsset call effect state = do
      checkResourceRead call effect state
      exits <- case effectProduces effect of
        Nothing -> lift (Left (InvalidPrototype "Context reader has no contract"))
        Just contractType -> readContractAsset contractType
      successes (\after -> do
        observed <- observeOpeningInput call effect after
        pure [AssetExit True observed]) exits
      where
      readContractAsset contractType = case lookup contractType (assetCaptures state) of
        Just _ -> pure [AssetExit True state, AssetExit False state]
        -- 持续资产只由会话生产：没有本次交付时由会话交付，不查询普通来源。
        Nothing | contractType `elem` receiving -> do
          recordRead (assetRoot call) contractType []
          pure [AssetExit True (capture contractType Nothing state), AssetExit False state]
        Nothing -> do
          let sources = nub [node' | (node', produced) <- assetPublications state, produced == contractType
                , visibleFrom (protoWorkflow prototype) node' (assetRoot call)]
              external = filter (/= assetRoot call) sources
          recordRead (assetRoot call) contractType external
          case sources of
            [] | effectName effect `elem` resources -> pure [AssetExit False state]
            [] | assetClosing call -> pure [AssetExit False state]
            -- 没有可见发布：运行时这次读取等待之后的发布，本条路径不从读取返回；
            -- 失败出口由 method 统一补上。
            [] -> pure []
            [source] -> pure [AssetExit True (capture contractType (Just source) state), AssetExit False state]
            -- lifelong 之后：同一单元的互斥位置各自保留最新发布，运行时取轮次最新的那个；每个候选是一条路径。
            _ | retainedChoice (assetRoot call) sources ->
                pure (AssetExit False state : [AssetExit True (capture contractType (Just source) state) | source <- sources])
            _ -> lift (Left (InvalidPrototype ("Asset " ++ contractType ++ " read at " ++ show (assetRoot call)
              ++ " has several visible sources " ++ show sources ++ "; refine the contract or the workflow")))
    publish :: AssetCall -> EffectProto String -> AssetState -> AssetAnalysis AssetState
    publish call effect state = case effectProduces effect of
      Nothing -> lift (Left (InvalidPrototype "Context production has no contract"))
      Just contractType -> do
        let owned = case assetOpenings call of
              current : _ -> any (\scope -> effectName scope == current
                && effectResource scope == Just (effectName effect)) effects
              [] -> False
            captured = capture contractType (Just (assetRoot call)) state
        if owned then pure captured else do
          recordDrive (assetRoot call) contractType
          pure captured { assetPublications = sort (nub ((assetRoot call, contractType) : assetPublications state)) }
    successes :: (AssetState -> AssetAnalysis [AssetExit]) -> [AssetExit] -> AssetAnalysis [AssetExit]
    successes action exits = nub . concat <$> mapM (\exit@(AssetExit succeeded state) ->
      if succeeded then action state else pure [exit]) exits
    -- 每个不透明原子方法都可能失败；失败保留此前已捕获和已发布的事实。
    -- 这些失败前缀只会在 Recover 或吞错注入继续，正常 Sequence 仍失败停止。
    withFailures :: AssetState -> [AssetExit] -> [AssetExit]
    withFailures state exits = AssetExit False state : exits
      ++ [AssetExit False after | AssetExit True after <- exits]
    shape :: AssetCall -> MethodShape String -> AssetState -> AssetAnalysis [AssetExit]
    shape _ Empty state = pure [AssetExit True state, AssetExit False state]
    shape call (Call selected) state = method call selected state
    shape call (Sequence parts) state = sequential (shape call) parts [AssetExit True state]
    shape call (Choice parts) state = case parts of
      [] -> pure [AssetExit True state]
      _ -> nub . concat <$> mapM (\part -> shape call part state) parts
    shape call (Recover body recovery) state = do
      before <- shape call body state
      nub . concat <$> mapM (\exit@(AssetExit succeeded after) ->
        if succeeded then pure [exit] else shape call recovery after) before
    sequential :: (part -> AssetState -> AssetAnalysis [AssetExit]) -> [part] -> [AssetExit] -> AssetAnalysis [AssetExit]
    sequential _ [] exits = pure (nub exits)
    sequential action (part : rest) exits = do
      next <- successes (action part) exits
      sequential action rest next
    method :: AssetCall -> String -> AssetState -> AssetAnalysis [AssetExit]
    method call selected state
      | selected `elem` assetReplays call = pure [AssetExit True (retainState (assetRelevant call) state)]
      | selected `elem` assetActiveMethods call =
          lift (Left (InvalidEffectGraph (RecursiveMethod selected)))
      | otherwise = do
          effect <- effectFor selected
          definition <- definitionFor selected
          -- 读取入口与 Pure 不改变调用者：经一串 Pure 拉取句柄的 Context 仍是它自己，句柄不再注入它。
          let entered = call { assetCaller = if methodRole definition == ContextRequire || effectKind effect == PureKind
                  then assetCaller call else Just (effectName effect)
                , assetActiveMethods = selected : assetActiveMethods call }
              role = methodRole definition
          exits <- case role of
            ContextRequire | selected `elem` defaultReaders ->
              readAsset entered effect state
            -- 生产入口每次调用都生产并发布：requests 驱动、选择读取、注入与会话步骤。
            ContextRequest -> do
              body <- shape entered (methodBody definition) state
              successes (\after -> do
                published <- publish call effect after
                observed <- observeOpeningInput call effect published
                pure [AssetExit True observed]) body
            -- 持续入口由会话步骤或被许可 AST 输出的挂接调用；成功即发布一次交付。
            ContextStream -> do
              body <- shape entered (methodBody definition) state
              successes (\after -> do
                published <- publish call effect after
                pure [AssetExit True published]) body
            ScopeOpen | assetClosing call -> pure [AssetExit False state]
            ScopeOpen -> do
              let inside = entered { assetOpenings = effectName effect : assetOpenings entered }
                  initial = state { assetInputs = (effectName effect, []) : filter ((/= effectName effect) . fst) (assetInputs state) }
                  opened (AssetExit succeeded after) = AssetExit succeeded
                    (if succeeded then after { assetOpened = nub (effectName effect : assetOpened after) } else after)
                  finished (AssetExit succeeded after) = AssetExit succeeded
                    (after { assetInputs = filter ((/= effectName effect) . fst) (assetInputs after) })
              recordOpening inside effect initial
              body <- shape inside (methodBody definition) initial
              fresh <- inject call selected (map opened body)
              let restoreResource after = foldr (\contractType -> capture contractType (Just (assetRoot call))) after
                    [contractType | producer <- effects, effectResource effect == Just (effectName producer)
                      , Just contractType <- [effectProduces producer]]
                  -- 无输入 scope 在进入方法体前选择复用；有输入时可在取得参数后
                  -- 跳过余下方法体，保守保留失败前缀中的已完成输入操作。
                  reused = nub [after | after <- initial : [after | AssetExit _ after <- body]
                    , Just _ <- [openingInputs effect after]]
              pure (map (finished . opened) (fresh ++ [AssetExit True (restoreResource after) | after <- reused]))
            ScopeClose -> do
              body <- shape (entered { assetClosing = True }) (methodBody definition) state
              -- 重复 close 可在取得资源绑定时跳过余下方法体并成功返回；不触发注入。
              pure (body ++ [AssetExit True after | after <- nub (state : [part | AssetExit _ part <- body])])
            ErrorDetect -> shape (entered { assetClosing = True }) (methodBody definition) state
            ErrorResolve -> shape (entered { assetClosing = True }) (methodBody definition) state
            _ -> shape entered (methodBody definition) state >>= inject call selected
          pure (nub (map (retainExit (assetRelevant call)) (withFailures state exits)))
    inject :: AssetCall -> String -> [AssetExit] -> AssetAnalysis [AssetExit]
    inject call anchor exits = do
      let anchored = [(outputProducer connection, outputParser connection, outputRole connection)
            | connection <- connections, outputAnchor connection == anchor
            , outputRole connection == ContextRequest || outputRole connection == ContextStream
                && reusedHere call (outputProducer connection)]
          producing = [entry | entry@(_, _, role) <- anchored
            , maybe True (`notElem` [owner | (owner, _, selected) <- anchored, selected == role]) (assetCaller call)]
      successes (\state -> do
        let injectOne (_, produced, role) before = do
              results <- method (call { assetCaller = Nothing
                , assetReplays = anchor : assetReplays call }) produced before
              -- 普通注入保留原吞错协议；持续解析失败沿既有会话失败协议传播。
              pure (if role == ContextStream then results
                else nub [AssetExit True after | AssetExit _ after <- results])
        sequential injectOne producing [AssetExit True state]) exits
    reusedHere call producer = or
      [ effectProduces effect == Just (sessionAsset session) && assetRoot call `elem` nodes
      | effect <- effects, effectName effect == producer
      , (_, described) <- lifelongs, session <- lifelongSessions described
      , ReuseOutput nodes <- [sessionPlan session] ]
    root :: NodeId -> [String] -> [(String, Maybe NodeId)] -> [(NodeId, String)] -> AssetAnalysis [AssetExit]
    root node' future handoff publications = do
      chain <- lift (lookupChain prototype node')
      let relevant = nub (readsAt node' ++ future)
      method (AssetCall node' Nothing [] [] [] False relevant) (chainEntry chain)
        (retainState relevant (AssetState publications handoff [] []))
    workflow :: WorkflowTree -> [String] -> [(NodeId, String)] -> [(String, Maybe NodeId)]
             -> AssetAnalysis [(Bool, [(NodeId, String)])]
    workflow tree future publications handoff = case tree of
      NodeAt node' _ -> do
        exits <- root node' future handoff publications
        pure (nub [retainOutcome future (succeeded, assetPublications state) | AssetExit succeeded state <- exits])
      ChainedAt _ children -> workflowSequence children future [(True, publications)] handoff
      ParallelAt _ children -> do
        -- 兄弟各读同一份前置状态；只把外层后继仍需要的产物交给组合，避免无关笛卡尔积。
        parts <- mapM (\child -> workflow child future publications handoff) children
        pure (foldl (combine future) [(True, retainPublications future publications)] parts)
      AlternativeAt _ choice children -> do
        selected <- root (alternativeSelector choice) (nub (concatMap readsIn children ++ future)) handoff publications
        nub . concat <$> mapM (\(AssetExit succeeded state) -> if not succeeded
          then pure [(False, [])]
          else nub . concat <$> mapM (\child -> workflow child future (assetPublications state)
              [(contractType, origin) | (contractType, Just origin') <- assetCaptures state
                , contractType `notElem` resourceContracts, let origin = Just origin']) children) selected
      LifelongAt boundary described _ -> do
        -- 复用原型中的实际消费单元，只拆 lifelong 直接子项的那一层 parallel。
        units <- lift $ mapM (\node' -> case lookupWorkflow tree node' of
          Just unit -> Right unit
          Nothing -> Left (InvalidPrototype ("Missing lifelong unit at " ++ show node')))
          (lifelongUnits described)
        let sessions = lifelongSessions described
            mounts = concatMap sessionMounts sessions
            delivered = [(sessionAsset session, Just (last (sessionMounts session)))
              | session <- sessions, not (null (sessionMounts session))]
            combineStates before after = nub [sort (nub (left ++ right))
              | left <- before, right <- after]
        -- 每个单元只保留自己可能读取的发布；root 仍保留生产链自身的读取依赖，
        -- read/drive 事实独立累计。不能先按所有单元的读取并集展开，再于出口投影。
        prepared <- mapM (\unit -> do
          let relevant = readsIn unit
          produced <- mapM (\session -> do
            steps <- mapM (\mount -> do
              exits <- root mount relevant handoff publications
              pure (nub [retainPublications relevant (assetPublications state)
                | AssetExit True state <- exits])) (sessionMounts session)
            -- 各成功出口分别保留；Receive 的两个步骤先各自投影，再组合并去重。
            pure $ case foldl combineStates [[]] steps of
              [] -> [[]]
              states -> states) sessions
          pure (unit, retainPublications relevant publications, produced)) units
        let -- 显式 request 的交付没有伴随发布，且会被本边界的其他单元消费；
            -- 因此 request 固定点仍跨全部单元求解，生产步骤始终使用边界环境。
            analyzeUnits requested = do
              mapM_ (\(unit, initial, produced) -> do
                let options = [nub (if sessionAsset session `elem` requested then [] : states else states)
                      | (session, states) <- zip sessions produced]
                mapM_ (\state -> workflow unit [] state (handoff ++ delivered))
                  (foldl combineStates [initial] options)) prepared
              drives <- gets assetDrives
              let now = nub [contractType | (node', contractType) <- drives, boundary `isPrefixOf` node'
                    , node' `notElem` mounts, contractType `elem` map sessionAsset sessions]
              unless (all (`elem` requested) now) (analyzeUnits (nub (requested ++ now)))
        analyzeUnits []
        -- 全部单元正常结束后 lifelong 成功返回，后继继续执行；仍有消费单元未结束时后继不会开始。
        -- 进入 lifelong 之前的发布照常交给后继；单元内可能发布的位置也交给后继：每个来源保留它最新一次发布，
        -- 零轮或从未发布时运行时缺值，按已有的耗尽协议报出。会话挂载的发布只作为交付的伴随发布，不外传。
        drives <- gets assetDrives
        let inside = [(node', contractType) | (node', contractType) <- drives, boundary `isPrefixOf` node'
              , node' `notElem` mounts, contractType `elem` future]
        pure [(True, sort (nub (retainPublications future publications ++ inside))), (False, [])]
    workflowSequence :: [WorkflowTree] -> [String] -> [(Bool, [(NodeId, String)])] -> [(String, Maybe NodeId)]
                     -> AssetAnalysis [(Bool, [(NodeId, String)])]
    workflowSequence children future states handoff = go positioned states
      where
        positioned = zip children (drop 1 (scanr (\child later -> nub (readsIn child ++ later)) future children))
        go [] outcomes = pure (nub (map (retainOutcome future) outcomes))
        go ((child, later) : rest) outcomes = do
          next <- nub . concat <$> mapM (\outcome@(succeeded, publications) -> if succeeded
            then workflow child later publications handoff else pure [outcome]) outcomes
          go rest next
    combine :: [String] -> [(Bool, [(NodeId, String)])] -> [(Bool, [(NodeId, String)])] -> [(Bool, [(NodeId, String)])]
    combine future before after = nub [retainOutcome future (leftOK && rightOK, sort (nub (left ++ right)))
      | (leftOK, left) <- before, (rightOK, right) <- after]
