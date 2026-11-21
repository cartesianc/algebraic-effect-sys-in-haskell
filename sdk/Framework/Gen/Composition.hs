{-# LANGUAGE DeriveFunctor #-}
{-# LANGUAGE DuplicateRecordFields #-}

-- 组合流水线 v3（2026-11-18）。声明是输入；Plan 记录装配、能力与原型计算的中间事实。
-- advanceComposition 统一阶段转换与结果；内部仍由各解释阶段计算，不是通用规则求解器。
-- 本模块负责声明、方法图与来源证明；Injector 合成入口，Booter 合成挂载及静态驱动标记。
-- Frontend.Source/Shape 只提供 Haskell 结构，Emit 只投影计划，runtime 不导入本模块。
--
-- 规则定位：buildEffectProtos（资产来源/访问/类别）→ Booter.numberWorkflow（挂载/驱动）
-- → Injector.bindProgram（类型/能力/路由/入口）→ composeMethods/buildStructure（方法/图）
-- → resolveSources（供值/捕获/开启）→ Booter.completeDriving（静态运行关联）。
-- 跨阶段以明确参数及结果连接，不重新解释前一阶段事实。
-- AwaitingBodies 是 beforegen 的接口检查点；AwaitingGraph 是结构缓存检查点。
-- 工作表/递归栈是同一计算中的局部证据，不能当作另一套装配结论或运行状态。
-- 统一入口不降低路径分析的最坏复杂度；保留先投影再组合、缺值路径与分支相关性。
module Framework.Gen.Composition
  ( beginComposition, prepareComposition, completeComposition, compositionKey
  , PendingComposition, CompositionResult(..)
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
import Framework.Gen.Plan
import Framework.Gen.Injector
import Framework.Gen.Injector.Super (superSelections)
import Framework.Gen.Booter
import Framework.Language.AST (WorkflowF(..), HangingTree, hangingRows)
import Framework.Gen.Workflow (hangingMarks, prepareWorkflow)
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
  = Declared String [EffectSpec] (Fix WorkflowF) [(NodeId, [String])]
  | Related String [EffectSpec] [EffectProto String] (Fix WorkflowF) [(NodeId, [String])]
  | Numbered String PrototypePlan
  | AwaitingBodies Unit
  | ResolvingBodies Unit (Maybe [(String, MethodShape String)])
  | AwaitingGraph PendingComposition
  | BuildingStructure PendingComposition
  | ProvingSources PendingComposition (Prototype String) [MethodDefinition String] [String]
  | Checking Unit Bool (Prototype String)
  | Complete CompositionResult

-- 末项：被 stream @T 读取 x:xs 的持续契约；随方法一起进入缓存键，建图后标在其生产 Context 上。
data PendingComposition = PendingComposition Unit Bool [(String, MethodShape String)] [String]

data CompositionResult = CompositionResult
  { compositionUnit :: Unit
  , compositionPrototype :: Prototype String
  }

-- 唯一状态转换入口。缓存只替换 BuildingStructure/ProvingSources；验证和驱动检查不会跳过。
advanceComposition :: CompositionState -> Either String CompositionState
advanceComposition state = case state of
  Declared namespace specifications tree marks -> do
    effects <- diagnostic (buildEffectProtos specifications)
    pure (Related namespace specifications effects tree marks)
  -- 业务树独立编号；Hanging 只贡献挂载范围，类型筛选仍由 Injector.Super 完成。
  Related namespace specifications effects tree marks -> do
    workflow <- diagnostic (numberWorkflow effects tree)
    diagnostic (checkMiddleware effects marks)
    pure (Numbered namespace (PrototypePlan specifications effects workflow marks))
  Numbered namespace plan -> do
    diagnostic (checkRequested (plannedEffects plan) (plannedWorkflow plan))
    assembly <- diagnostic (assembleProgram plan)
    unit <- bindProgram namespace plan (declareEffects (plannedRegistrations plan)) assembly
      (controlReads (plannedEffects plan) (plannedWorkflow plan))
    let (selectors, sessions) = entryPlans (mountHooks unit) (plannedEffects plan) (plannedWorkflow plan) assembly
        entered = unit { unitSelectors = selectors, unitSessionEntries = sessions }
    pure (AwaitingBodies entered { unitSupers = superSelections entered })
  ResolvingBodies unit supplied -> do
    let checked = case supplied of Just _ -> True; Nothing -> False
    methods <- composeMethods checked (effectPrototypes unit) (unitBindings unit) (unitReads unit) (maybe [] id supplied)
    let histories = streamHistories (unitBindings unit) (maybe [] id supplied)
    pure (AwaitingGraph (PendingComposition unit checked methods histories))
  BuildingStructure pending@(PendingComposition unit _ methods histories) -> do
    (prototype, written, readers) <- diagnostic (buildStructure (unitPlan unit) (unitAssembly unit) methods)
    pure (ProvingSources pending (markHistories histories prototype) written readers)
  ProvingSources (PendingComposition unit checked _ _) prototype written readers -> do
    analyzed <- diagnostic (resolveSources checked (assemblyOutputs (unitAssembly unit)) written readers prototype)
    pure (Checking unit checked (completeDriving analyzed))
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
-- tree 与 targets 是源码上的原样结构和挂载路径；Gen.Workflow 先给出规范形式与迁移后的挂载。
beginComposition :: String -> [EffectSpec] -> Fix WorkflowF -> HangingTree -> [[(String, [NodeId])]] -> Either String Unit
beginComposition namespace specifications tree mounts targets = do
  marks <- hangingMarks (hangingRows mounts) targets
  (normalized, moved) <- either (Left . show) Right (prepareWorkflow tree marks)
  state <- settleComposition (Declared namespace specifications normalized moved)
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
compositionKey (PendingComposition unit checked methods histories) = show (unitPlan unit, unitAssembly unit, checked, methods, histories)

completeComposition :: PendingComposition -> Maybe (Prototype String) -> Either String CompositionResult
completeComposition pending@(PendingComposition unit checked _ _) cached = do
  state <- settleComposition (case cached of
    Just prototype -> Checking unit checked prototype
    Nothing -> BuildingStructure pending)
  case state of
    Complete result -> pure result
    _ -> Left "Composition did not complete"

-- ========================================================================
-- 声明关系与方法角色
-- ========================================================================

-- 注册关系的标准解析：同时完成注册级检查。之后的绑定与输出只读取这些事实，不再自行推导。
buildEffectProtos :: [EffectSpec] -> Either (PrototypeError String) [EffectProto String]
buildEffectProtos specifications = do
  valid (unique (map name specifications)) "Duplicate effect name"
  valid (all ((/= "Root") . name) specifications) "Root is reserved"
  valid (all ((/= "None") . name) specifications) "None is reserved"
  fromRegistration (validateAssetSources specifications)
  mapM_ (\specification -> mapM_ (\demand -> valid (validContractName (contract demand))
      ("Demanded contract must be a contract name such as StartURL: " ++ contract demand
        ++ " in " ++ name specification)) (demands specification)) specifications
  resolved <- mapM (fromRegistration . resolveDemands specifications) specifications
  dependencies <- mapM (fromRegistration . contextNames specifications . pure . name) specifications
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
      inputAncestors "None" = []
      inputAncestors selected = selected : concat
        [inputAncestors (input specification) | specification <- specifications, name specification == selected]
      make specification contextDependencies = EffectProto
        { effectName = name specification
        , effectKind = Registration.effectKind (typing specification)
        , effectInput = input specification
        , effectMethods = registeredMethods specifications specification
        , effectDemands = resolvedOf (name specification)
        , effectProduces = contractOf <$> contextAsset (typing specification)
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
        -- 由方法体形状在建图后标记（markHistories）；声明阶段一律不保留历史。
        , effectHistory = False
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
        -- "None" 只属于 Middleware：它没有 Input 前驱，由 AST 标注挂载；Middleware 不能作为任何 effect 的 Input。
        valid ((input specification == "None") == (Registration.effectKind (typing specification) == MiddlewareKind))
          ("Input \"None\" is reserved for Middleware, and a Middleware has input \"None\": " ++ name specification)
        unless (input specification `elem` ["Root", "None"]) $ do
          predecessor <- findSpec (input specification)
          valid (Registration.effectKind (typing predecessor) /= MiddlewareKind)
            ("Input cannot reference Middleware " ++ name predecessor ++ " in " ++ name specification ++ "; mount it with middleware in the AST")
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
              TypeRef _ _ -> pure ()
              _ -> Left (InvalidPrototype ("Context.request must wrap a business value, not Output: " ++ name specification))
            valid (null [() | anchorName <- maybeToList (anchorOf [] (input specification))
              , anchor <- specifications, name anchor == anchorName
              , Scoped {} <- [typing anchor], requestSource anchor == Just (name specification)])
              ("Context " ++ name specification ++ " cannot hang below the scope that requests it as its resource")
          -- Pure 只在生产链中：用 rawinput 读取直接上游的输出，再交给下游 Pure 或 Context。
          Pure method -> do
            valid (method /= Nothing) ("Pure needs a handler: " ++ name specification)
            valid (null (demands specification))
              ("Pure " ++ name specification ++ " reads its input with rawinput and declares no demands")
            upper <- if input specification == "Root"
              then Left (InvalidPrototype ("Pure " ++ name specification
                ++ " needs an Excu, Scoped or Pure input for rawinput"))
              else findSpec (input specification)
            valid (Registration.effectKind (typing upper) `elem` [ExcuKind, ScopedKind, PureKind])
              ("Pure " ++ name specification ++ " uses rawinput to read from an Excu, Scoped or Pure, not from "
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
          -- Middleware 没有 demands：只在 Root 级调用点捕获值，不读取或驱动资产。
          Middleware method intercepted -> do
            valid (method /= Nothing) ("Middleware needs a handler: " ++ name specification)
            valid (null (demands specification)) ("Middleware " ++ name specification ++ " declares no demands")
            valid (not (null intercepted) && unique intercepted && all (`elem` allEffects) intercepted)
              ("Middleware " ++ name specification ++ " intercepts a non-empty list of distinct kinds among Excu, Scoped, Pure and Stream")
          Error { handles = matched } -> do
            valid (not (null matched)) ("Error must declare the failures it handles: " ++ name specification)
            mapM_ checkHandled matched
            -- Error 只指向 scope；普通 effect 的失败通过提前 mock 解决，不作全局处置。
            case errorScopes specification of
              [_] -> pure ()
              [] -> Left (InvalidPrototype ("Error " ++ name specification ++ " has no scope on its Input chain; Error only handles scope failures"))
              _ -> Left (InvalidPrototype ("Error capability reaches several nearest scopes: " ++ name specification))
          _ -> pure ()
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

    -- 声明解释的私有运算；其他阶段只取得 EffectProto，不能直接重做解析。
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

    findEffect :: [EffectSpec] -> String -> Either String EffectSpec
    findEffect specifications selected = case filter ((== selected) . name) specifications of
      [specification] -> Right specification
      [] -> Left ("Unknown effect: " ++ selected)
      _ -> Left ("Duplicate effect: " ++ selected)

    produced :: EffectSpec -> Maybe String
    produced specification = contractOf <$> contextAsset (typing specification)

    -- 资产名在注册集合中唯一，因此每个契约恰好对应一个生产方。
    -- requires 需要生产方缓存（require = True），streams 需要持续资产。
    resolveDemands :: [EffectSpec] -> EffectSpec -> Either String [ResolvedDemand]
    resolveDemands specifications consumer = do
      validateAssetSources specifications
      let keys = [(access demand, contract demand) | demand <- demands consumer]
      unless (length keys == length (nub keys)) $
        Left ("Duplicate demand in " ++ name consumer ++ "; each asset/access pair may be declared once")
      mapM resolveOne (demands consumer)
      where
        resolveOne demand = do
          provider <- case [specification | specification <- specifications
                , name specification /= name consumer, produced specification == Just (contract demand)] of
            [specification] -> pure specification
            [] -> Left ("No Context produces contract " ++ contract demand ++ " for " ++ name consumer
              ++ "; a contract is the asset name declared by its producer Context")
            _ -> Left ("Several Context effects produce contract " ++ contract demand)
          case (access demand, typing provider) of
            (RequestAccess, _) | continuousContext provider -> Left ("Contract " ++ contract demand
              ++ " is a continuous asset produced by its session, so " ++ name consumer ++ " cannot request it")
            (RequireAccess, Context { require = False }) -> Left ("Contract " ++ contract demand
              ++ " is not cached (require = False), so " ++ name consumer ++ " cannot require it")
            (StreamAccess, _) | not (continuousContext provider) -> Left ("Contract " ++ contract demand
              ++ " is not a continuous asset (its Context declares stream = False), so "
              ++ name consumer ++ " cannot subscribe to it")
            _ -> pure ()
          pure (ResolvedDemand (access demand) (contract demand) (name provider))

    -- 收集声明前提所需的 Context，按依赖顺序去重；不根据业务值合并调用。
    contextNames :: [EffectSpec] -> [String] -> Either String [String]
    contextNames specifications selected = nub . concat <$> mapM (visit []) selected
      where
        visit _ "Root" = Right []
        visit _ "None" = Right []
        visit seen selectedName
          | selectedName `elem` seen = Left ("Cyclic input/demand: " ++ selectedName)
          | otherwise = do
              specification <- findEffect specifications selectedName
              resolved <- resolveDemands specifications specification
              let providers = nub (map demandProvider resolved)
              upstream <- concat <$> mapM (visit (selectedName : seen)) (nub (input specification : providers))
              pure (upstream ++ providers)

    fromRegistration :: Either String value -> Either (PrototypeError String) value
    fromRegistration = either (Left . InvalidPrototype) Right

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
      Middleware method _ -> named MiddlewareHook "hook" method
      where
        named role prefix method = [(role, effectMethodName prefix (name specification)) | Just _ <- [method]]

-- 算法说明 v1（2026-11-15）：末端来自 node 的显式选择，不从全图寻找出度为零的节点。
-- cata 给每次挂载分配 AST 路径；同一 effect 重复挂载仍保留不同 NodeId，不能按名字合并。
-- alternative 按候选 requires 的、由同一原子句柄的输出解析出的资产定位判定 Context，登记选择入口。
-- 此处不提取候选的最长公共前缀，也不改写它们的 Input；选择绑定的交接由运行协议完成。
-- 编号遍历本身随 AST 大小增长，但每处的注册查询、候选检查与 planSessions 分析另计。
-- ========================================================================
-- 接口能力、读取路由与方法组成
-- ========================================================================

-- 结构分析给出每个 handler 方法体的结构：@T 是按表示类型的读取，%raw 是 rawinput。
-- 每个绑定按自己的路由把它们换成 effect 方法调用，前面接上驱动与 Input 前驱，得到 effect 方法的结构。
-- 同时检查 handler 读取的表示类型都有声明，rawinput 只用于挂接的 parser，声明的读取都被方法体或控制流使用。
composeMethods :: Bool -> [EffectProto String] -> [Binding] -> [(String, [String])] -> [(String, MethodShape String)]
               -> Either String [(String, MethodShape String)]
composeMethods checkReads effects bindings required handlerShapes = do
  composed <- mapM compose bindings
  when checkReads $ do
    mapM_ checkCloseResourceRead composed
    mapM_ (checkUsed composed) required
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
      -- stream @T：同一路由的 x:xs 读取，方法图上仍是对读取方法的调用；只允许 streams 读取的持续资产。
      Call ('~' : typeText) -> case lookup (normalizeType typeText) (bindingRoutes binding) of
        Just (contractType, reader)
          | streamed binding contractType -> pure (Call reader, [contractType])
          | otherwise -> Left ("Handler " ++ bindingHandler binding ++ " reads " ++ typeText ++ " with stream in "
              ++ bindingEffect binding ++ ", but " ++ contractType ++ " is not a continuous asset read with streams"
              ++ "; use require for a single value, or declare streams " ++ show contractType)
        Nothing -> Left ("Handler " ++ bindingHandler binding ++ " streams " ++ typeText ++ " in " ++ bindingEffect binding
          ++ ", whose demands give " ++ describe (bindingRoutes binding)
          ++ "; declare streams for a continuous asset of that representation")
      Call "%raw" -> case bindingRaw binding of
        Just source -> pure (Call (rawMethod source), [])
        Nothing -> Left ("Handler " ++ bindingHandler binding ++ " uses rawinput in " ++ bindingEffect binding
          ++ "; rawinput requires an attached Context parser or a Pure with a valid input")
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
    streamed binding contractType = or
      [ demandAccess demand == StreamAccess && demandContract demand == contractType
      | effect <- effects, effectName effect == bindingEffect binding, demand <- effectDemands effect ]
    describe [] = "no readable asset"
    describe routes = intercalate ", " [representation' ++ " (" ++ contractType ++ ")" | (representation', (contractType, _)) <- routes]
    -- close 读取检查 v1（2026-11-17）：有资源的 close 自身须读取资源以定位实例。
    -- open 的 requests 已生产并认领资源，方法体可以为空；不能套用 close 的读取前提。
    -- 只看本方法按当前绑定路由出的读取；另一方法或 gen 装配的 requests 不代替它。
    -- 不枚举分支：这里只证明整个方法完全没有该读取，不能证明每条路径或 IO 前已读取。
    -- checked 为 False 的首次契约生成跳过；正常生成在图缓存查询前每次检查。
    checkCloseResourceRead (binding, _, used)
      | bindingOperation binding == CloseResource = mapM_ check
          [(effectName producer, contractType, [contractType])
            | scope <- effects, effectName scope == bindingEffect binding
            , producer <- effects, effectResource scope == Just (effectName producer)
            , Just contractType <- [effectProduces producer]]
      | otherwise = pure ()
      where
        check (source, contractType, readable) = unless (any (`elem` used) readable) $
          Left ("Scoped " ++ bindingEffect binding ++ " close handler " ++ bindingHandler binding
            ++ " does not read its resource " ++ contractType ++ " (Context " ++ source ++ ")"
            ++ "; declare requires " ++ show contractType ++ " and read its representation with require in this method"
            ++ "; reading it in another lifecycle method does not satisfy this contract")
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

-- 算法说明 v1（2026-11-21）：x:xs 读取的契约。每个绑定按自己的路由把方法体中的 ~T 换成契约；
-- 读取是否合法已由 composeMethods 检查，这里只收集，供运行时决定哪些会话从开头保留交付。
streamHistories :: [Binding] -> [(String, MethodShape String)] -> [String]
streamHistories bindings handlerShapes = nub
  [ contractType
  | binding <- bindings
  , Just body <- [lookup (bindingHandler binding) handlerShapes]
  , typeText <- streamed body
  , Just (contractType, _) <- [lookup (normalizeType typeText) (bindingRoutes binding)] ]
  where
    streamed shape = case shape of
      Call ('~' : typeText) -> [typeText]
      Sequence children -> concatMap streamed children
      Choice children -> concatMap streamed children
      Recover body recovery -> streamed body ++ streamed recovery
      _ -> []

-- 被 x:xs 读取的契约，标在生产它的持续 Context 上；其余 effect 保持 effectProto 的默认值。
markHistories :: [String] -> Prototype String -> Prototype String
markHistories histories prototype = prototype { protoEffects = map mark (protoEffects prototype) }
  where mark effect = effect { effectHistory = effectContinuous effect && maybe False (`elem` histories) (effectProduces effect) }

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
    "An injected Context reaches its anchor through another method; read the anchor with rawinput, directly or through Pure"
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
        (map makeChain mounts) chainDefinitions graph scopes names [] [] (DrivingPlan [] [] [] [] [] [] (plannedMiddleware plan) [])
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
  -- 只分析交接后的 parser（rawinput 对 anchor 的调用已抹去），避免把合法下游消费算进来。
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

    -- 方法图装配专用的分析副本变换，不允许其他阶段直接改写方法。
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
    -- 挂接 Context 的 rawinput 到达 anchor 时由已有输出回答，所以该调用在副本中是 Empty；
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

-- 构图与最终驱动校验共用的纯引用投影；不决定实际生产时机。
withProducerReferences :: Eq method => [OutputConnection method] -> [MethodDefinition method] -> [MethodDefinition method]
withProducerReferences connections definitions =
  [definition { methodBody = Sequence (methodBody definition : [Call (outputParser connection)
      | connection <- connections, outputAnchor connection == methodIdentity definition]) }
  | definition <- definitions]

-- 普通资产只由 requests 生产：requests 是前驱，在请求方入口执行该资产的整条生产链，
-- 回调更新资产的当前值；requires 只被动读取这个值。因此被 requires 的普通资产必须有某个
-- effect requests 它。alternative 的判定资产由选择读取（chooseCase）产生，不在此列；
-- 持续资产由会话驱动，另按持续协议检查。
checkRequested :: [EffectProto String] -> WorkflowTree -> Either (PrototypeError String) ()
checkRequested effects workflow = valid (null missing)
  ("Asset never requested: " ++ intercalate "; " missing
    ++ ". Ordinary assets are produced only by requests; add requests \"<asset>\" to the reader or to an effect"
    ++ " on its Input chain")
  where
    requested = [demandContract demand | effect <- effects, demand <- effectDemands effect
      , demandAccess demand == RequestAccess]
    continuous = [contract | effect <- effects, effectContinuous effect, Just contract <- [effectProduces effect]]
    deciding = [contract | AlternativeAt _ choice _ <- allWorkflow workflow, (_, caseName) <- alternativeCases choice
      , effect <- effects, effectName effect == caseName, Just contract <- [effectProduces effect]]
    missing = nub [contract ++ " (required by " ++ effectName effect ++ ")"
      | effect <- effects, demand <- effectDemands effect, demandAccess demand == RequireAccess
      , let contract = demandContract demand
      , contract `notElem` requested, contract `notElem` continuous, contract `notElem` deciding]

-- 首次尚无 Handlers 时仅生成契约；有源码快照后必须另外执行这个驱动检查。
checkDriven :: Assembly String -> Prototype String -> Either (PrototypeError String) ()
checkDriven assembly prototype = valid (null undriven)
  ("Context never driven from the AST: " ++ intercalate ", " undriven
    ++ "; no terminal reaches its production or the handle it hangs below")
  where
    reached = reachableMethods (withProducerReferences (assemblyOutputs assembly) (protoMethods prototype))
      (map chainEntry (protoChains prototype) ++ deciding)
    -- alternative 的选择读取（chooseCase）自己运行各判定 parser，不经句柄注入。
    deciding = [parser | AlternativeAt _ choice _ <- allWorkflow (protoWorkflow prototype)
      , (_, caseName) <- alternativeCases choice, effect <- protoEffects prototype, effectName effect == caseName
      , Just parser <- [lookup ContextRequest (effectMethods effect)]]
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

    -- 方法归约的 memo 与 algebra 是 buildEffectGraph 的内部计算。
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

-- 方法图与 ScopeTree 共用的路径规范化，仅消除结构证据的重复。
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

-- 来源算法 v5（2026-11-18）：普通发布按运行共享，有限结构从空供值集求单调固定点。
-- 一轮只加入已能启动的路径所产生的事实；并行发布可以解开其他读取，读取本身不生产。
-- 备用会话只参与结构校验，不作为凭空启动的供值证据；实际有限需求才激活其分析。
-- 证据按 ReadPoint 合并，不增加路径状态；仍先按消费单元/后续读取投影，再组合候选状态。
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
  -- Bool 表示至少有一条到达该读取的路径具有捕获或可启动的供值；False 也记录读取确实可达。
  , assetReadSupply :: [(ReadPoint, Bool)]
  -- 上一次结构推演已经找到的生产机会，不表示运行时已发布或必然成功。
  , assetAvailable :: [(NodeId, String)]
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

-- 保留本次调用的路径捕获与资源开启证明；普通读取另从共享供值固定点取得候选。
-- 这是最低限度的进展检查：擦除 IO、保留可能分支，不证明所有路径或任意 IO 都会结束。
resolveSources :: Bool -> [OutputConnection String] -> [MethodDefinition String] -> [String] -> Prototype String
               -> Either (PrototypeError String) (Prototype String)
resolveSources checked connections definitions defaultReaders prototype = do
  facts <- settle []
  let reads = [(point, if readContract point `elem` receiving then FromSession
                       else let candidates = sort (nub (sources ++ [node | (node, contractType) <- assetAvailable facts
                                                , contractType == readContract point]))
                            in if null candidates then FromOwnChain else FromChains candidates)
        | (point, sources) <- assetReads facts]
        ++ selectorReads (assetAvailable facts)
      annotate chain = chain
        { chainDrives = sort (nub [contractType | (node', contractType) <- assetDrives facts ++ assetAvailable facts, node' == chainNode chain])
        , chainReads = sort (nub [readContract point | (point, _) <- reads, readNode point == chainNode chain])
        }
  when checked (mapM_ checkReadSupply (assetReadSupply facts))
  mapM_ successorRead reads
  pure prototype { protoChains = map annotate (protoChains prototype), protoSources = reads
    , protoScopeOpenings = assetScopeOpenings facts }
  where
    effects = protoEffects prototype
    lifelongs = workflowLifelongs (protoWorkflow prototype)
    -- 判定全失败后只等待其他挂载实际可能发布的契约。chainReaches 包含普通入口的挂接，
    -- 它本身不能证明这些 parser 在选择读取时也会执行。
    selectorReads available =
      [ (ReadPoint selector contractType, if null candidates then FromOwnChain else FromChains candidates)
      | AlternativeAt _ choice _ <- allWorkflow (protoWorkflow prototype)
      , let selector = alternativeSelector choice
      , (_, caseName) <- alternativeCases choice
      , effect <- effects, effectName effect == caseName
      , Just contractType <- [effectProduces effect]
      , let candidates = [origin | (origin, produced) <- available, produced == contractType, origin /= selector] ]
    -- 上界是有限的（挂载，资产）对；不模拟业务次数或累积无限轮次。
    settle available = do
      found <- analyze available False
      let expanded = sort (nub (available ++ assetDrives found))
      if expanded == available then analyze available True else settle expanded
    analyze available includeDormant = flip execStateT (AssetFacts [] [] [] [] available) $ do
      _ <- workflow (protoWorkflow prototype) [] [] []
      activateSessions []
      when includeDormant $ mapM_ (\mount -> root mount [] [] [])
        (concatMap sessionMounts (protoSessions prototype))
    -- 有限 requires 持续资产会启动其托管来源；只有分析已到达这份需求才计入供值。
    activateSessions started = do
      reads <- gets assetReads
      let demanded = sessionAssets effects [readContract point | (point, _) <- reads
            , readContract point `elem` receiving
            , not (any (\(boundary, _) -> boundary `isPrefixOf` readNode point) lifelongs)]
          newly = [session | session <- protoSessions prototype
            , sessionAsset session `elem` demanded, sessionAsset session `notElem` started]
      unless (null newly) $ do
        mapM_ (\mount -> root mount [] [] []) (concatMap sessionMounts newly)
        activateSessions (map sessionAsset newly ++ started)
    checkReadSupply (_, True) = pure ()
    checkReadSupply (point, False) = do
      chain <- lookupChain prototype (readNode point)
      Left (InvalidPrototype ("Asset " ++ readContract point ++ " read in chain targeting "
        ++ chainTerminal chain ++ " at " ++ show (readNode point)
        ++ " has no reachable publication or capture; declared production is absent or waits on this read"
        ++ "; start a production path before the wait or in an independent branch"))
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
    resources = [source | effect <- effects, Just source <- [effectResource effect]]
    resourceContracts = [contractType | effect <- effects, effectName effect `elem` resources
      , Just contractType <- [effectProduces effect]]
    resourceOwners = [(contractType, effectName scope) | scope <- effects
      , producer <- effects, effectResource scope == Just (effectName producer)
      , Just contractType <- [effectProduces producer]]
    receiving = [contractType | effect <- effects, effectContinuous effect
      , Just contractType <- [effectProduces effect]]
    -- 虚拟 SessionChain 包含未必启动的备用托管挂载，空环境分析不能证明实际边界交接缺值。
    -- 本轮最低覆盖只检查 workflow 的真实读取根；会话自身的来源证明保持原协议。
    sessionRoots = [chainNode chain | chain <- protoChains prototype, chainRole chain == SessionChain]
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
    -- 此事实独立于来源表：已有捕获的成功路径也必须记入，否则另一条缺值路径会被误判为必缺值。
    -- 同 NodeId/资产的读取合并为一个点；这是一项保守的最低覆盖，不声称逐语句证明所有等待。
    recordReadSupply :: AssetCall -> EffectProto String -> String -> AssetState -> [NodeId] -> AssetAnalysis ()
    recordReadSupply call effect contractType state sources =
      unless (contractType `elem` receiving || effectName effect `elem` resources || assetClosing call
        || assetRoot call `elem` sessionRoots) $
        modify' $ \facts ->
          let point = ReadPoint (assetRoot call) contractType
              supplied = lookup contractType (assetCaptures state) /= Nothing || not (null sources)
              previous = maybe False id (lookup point (assetReadSupply facts))
          in facts { assetReadSupply = (point, previous || supplied)
                : filter ((/= point) . fst) (assetReadSupply facts) }
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
    -- 资源组合事实 v2（2026-11-18）：同一计算覆盖 AST、选择读取和 SessionChain。
    -- openingSources 是允许匹配的参数出处，kinds 是路径上的身份候选，不是 close 策略。
    -- SessionProto.mounts 与本表共同支持运行时的持续待用帧；实际 Binding/ActivationId
    -- 决定某个具体实例是否仍可复用。不能在 Emit/runtime 按 request、Stream 或业务 IO
    -- 重新推导一份寿命分类，也不能把新参数生产解释成旧实例失去全部使用者。
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
                         && not (continuous source) && any (\producer -> effectName producer == source
                           && maybe False (\contractType -> (node', contractType) `elem` assetPublications state)
                                (effectProduces producer)) effects) inputs = [ExecutionMultiple]
                     -- 会话可交接本轮输出，也可交付独立生产的值；运行时按实际 Binding 判定，
                     -- 不能因为没有普通 NodeId 捕获就漏掉整个开启位置。
                     | any (continuous . fst) inputs = [ProductionSingleton, ExecutionMultiple]
                     -- owner 的本链 open 也可能复用前驱实例；资源自身不进入普通来源表。
                     | any (\(source, origin) -> source `elem` resources && origin == Just node') inputs = [ProductionSingleton, ExecutionMultiple]
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
    -- 已捕获的路径不重新取值；缺值路径从局部发布和共享供值中推导可能捕获。
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
      readContractAsset contractType = do
        available <- gets assetAvailable
        let shared = [pair | pair@(_, produced) <- available, produced == contractType
              , effectName effect `notElem` resources, not (assetClosing call)]
            sources = nub [node' | (node', produced) <- assetPublications state ++ shared, produced == contractType]
            external = sources
        recordReadSupply call effect contractType state sources
        case lookup contractType (assetCaptures state) of
          Just _ -> pure [AssetExit True state, AssetExit False state]
          -- 持续资产只由会话生产：没有本次交付时由会话交付，不查询普通来源。
          Nothing | contractType `elem` receiving -> do
            recordRead (assetRoot call) contractType []
            pure [AssetExit True (capture contractType Nothing state), AssetExit False state]
          Nothing -> do
            recordRead (assetRoot call) contractType external
            case sources of
              [] | effectName effect `elem` resources -> pure [AssetExit False state]
              [] | assetClosing call -> pure [AssetExit False state]
              -- 缺值状态不提供成功出口；所有路径分析结束后再检查是否完全没有合法供值。
              -- 失败出口由 method 统一补上，Recover 不会抹去这次读取的结构证据。
              [] -> pure []
              [source] -> pure [AssetExit True (capture contractType (Just source) state), AssetExit False state]
              -- 多处驱动仍是同一 refined asset。运行读取最新发布，结构逐候选保留参数身份，
              -- 不把参数 ADT 相等当作同一次生产，也不把任一候选解释成必定发生。
              _ -> pure (AssetExit False state :
                [AssetExit True (capture contractType (Just source) state) | source <- sources])
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
            ContextRequest -> shape entered (methodBody definition) state >>= publishRequest call effect
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
    publishRequest :: AssetCall -> EffectProto String -> [AssetExit] -> AssetAnalysis [AssetExit]
    publishRequest call effect = successes $ \after -> do
      published <- publish call effect after
      observed <- observeOpeningInput call effect published
      pure [AssetExit True observed]
    inject :: AssetCall -> String -> [AssetExit] -> AssetAnalysis [AssetExit]
    inject call anchor exits = do
      -- 只有持续 Context 挂在句柄输出上，且只在原型指定的发布位置沿用本次输出；解析失败沿会话失败协议传播。
      let anchored = [(outputProducer connection, outputParser connection)
            | connection <- connections, outputAnchor connection == anchor
            , reusedHere call (outputProducer connection)]
          producing = [entry | entry <- anchored
            , maybe True (`notElem` map fst anchored) (assetCaller call)]
      successes (\state -> do
        let injectOne (_, produced) before = method (call { assetCaller = Nothing
              , assetReplays = anchor : assetReplays call }) produced before
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
      ChainAt _ children -> workflowSequence children future [(True, publications)] handoff
      ParallelAt _ children -> do
        -- 每个兄弟保留自己的捕获路径；跨兄弟供值由外层固定点传入，出口只组合后续所需事实。
        parts <- mapM (\child -> workflow child future publications handoff) children
        pure (foldl (combine future) [(True, retainPublications future publications)] parts)
      AlternativeAt _ choice children -> do
        let selector = alternativeSelector choice
        chain <- lift (lookupChain prototype selector)
        cases <- mapM (\(child, (_, name')) -> case
            [(effect, contractType, parser) | effect <- effects, effectName effect == name'
              , Just contractType <- [effectProduces effect], Just parser <- [lookup ContextRequest (effectMethods effect)]] of
          [(effect, contractType, parser)] -> do
            definition <- definitionFor parser
            pure (child, effect, contractType, definition)
          _ -> lift (Left (InvalidPrototype ("Missing alternative decision parser for " ++ name'))))
          (zip children (alternativeCases choice))
        let relevant = nub (readsAt selector ++ concatMap readsIn children ++ future ++
                [contractType | (_, _, contractType, _) <- cases])
            anchor = chainEntry chain
            call = AssetCall selector (snd <$> listToMaybe (alternativeCases choice)) [] [] [] False relevant
            runChild child state = workflow child future (assetPublications state)
              [(contractType, Just origin) | (contractType, Just origin) <- assetCaptures state
                , contractType `notElem` resourceContracts]
            -- chooseCase 只运行一次共同句柄。第一个成功的判定 parser 交接捕获；
            -- 失败前缀中的其他发布仍有效，但失败的 parser 不发布自己的结果。
            attempt [] states = nub . concat <$> mapM (firstBound cases) states
            attempt ((child, effect, _, definition) : rest) states = do
              let parserCall = call { assetCaller = Just (effectName effect), assetReplays = [anchor]
                    , assetActiveMethods = [methodIdentity definition] }
                  tryParser state = do
                    body <- shape parserCall (methodBody definition) state
                    -- 即使 rawinput 重放成功，业务模式匹配仍可能拒绝这份输出。
                    publishRequest parserCall effect (withFailures state body)
              exits <- nub . concat <$> mapM tryParser states
              selected <- mapM (runChild child) [state | AssetExit True state <- exits]
              later <- attempt rest [state | AssetExit False state <- exits]
              pure (nub (concat selected ++ later))
            -- 本次尝试全失败时，既有捕获优先；其他挂载可能在等待期间发布。
            firstBound [] _ = pure [(False, [])]
            firstBound ((child, _, contractType, _) : rest) state = do
              available <- gets assetAvailable
              let captured = lookup contractType (assetCaptures state)
                  published = [Just origin | (origin, produced) <- assetPublications state, produced == contractType]
                  shared = [Just origin | (origin, produced) <- available, produced == contractType
                    , origin /= selector || any (\(boundary, _) -> boundary `isPrefixOf` selector) lifelongs]
                  origins = maybe (nub (published ++ shared)) (:[]) captured
              selected <- mapM (\origin -> runChild child (capture contractType origin state)) origins
              later <- if captured == Nothing && null published then firstBound rest state else pure []
              pure (nub (concat selected ++ later))
        upstream <- method call anchor (retainState relevant (AssetState publications handoff [] []))
        selected <- attempt cases [state | AssetExit True state <- upstream]
        pure (nub ([(False, []) | any (\(AssetExit ok _) -> not ok) upstream] ++ selected))
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
        -- lifelong 的正常出口使后继可启动；共享供值固定点保留期间可能发布的位置。
        -- 零轮或条件未发布仍可能缺值，由运行时的保守耗尽协议处理。
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

-- 普通入口按角色确定，关闭方法不参与入口选择。
entryMethod :: EffectSpec -> Maybe String
entryMethod specification = case typing specification of
  Pure method -> effectMethodName "run" (name specification) <$ method
  Excu method -> effectMethodName "run" (name specification) <$ method
  Scoped opening _ -> effectMethodName "open" (name specification) <$ opening
  -- Error 的两个方法由故障协议激活，不猜测一个普通 Node 入口。
  Error {} -> Nothing
  selected@Context {} -> contextProducer selected
  -- Stream 的方法只经会话执行，不作为 AST 末端；末端检查另行拒绝。
  Stream method -> effectMethodName "next" (name specification) <$ method
  -- Middleware 只在 Root 级调用点上执行，不是普通入口。
  Middleware {} -> Nothing

-- 注册把 handler 绑定到 effect 方法：(effect 方法名, handler 名)。
handlerBindings :: EffectSpec -> [(String, String)]
handlerBindings specification = case typing specification of
  Pure method -> bound "run" method
  Excu method -> bound "run" method
  Scoped opening closing -> bound "open" opening ++ bound "close" closing
  Error { detect = detecting, resolve = resolving } -> bound "detect" detecting ++ bound "resolve" resolving
  selected@Context { parser = parsing } -> [(method, selected') | Just method <- [contextProducer selected], Just selected' <- [parsing]]
  Stream method -> bound "next" method
  Middleware method _ -> bound "hook" method
  where
    bound prefix method = [(effectMethodName prefix (name specification), selected) | Just selected <- [method]]

-- 生产入口：get 加资产名，例如 getStartURL；它沿 Input 驱动 parser，结果发布为资产。
-- 消费方写 requests 驱动它，handler 不直接调用。
contextProducer :: EffectTyping -> Maybe String
contextProducer (Context declared (Just _) _ _) = Just ("get" ++ contractOf declared)
contextProducer _ = Nothing

-- 读取入口：read 加资产名读取最新值；持续资产为 stream 加资产名，读取本次固定交付。
-- 消费方写 requires／streams，handler 按表示类型 require，不直接调用它。
contextReader :: EffectTyping -> Maybe String
contextReader (Context declared _ True streaming) =
  Just ((if streaming then "stream" else "read") ++ contractOf declared)
contextReader _ = Nothing


-- 注册只在此解释一次。Injector 消费方法、结果与操作角色，Names 只拼写已选角色的名字。
declareEffects :: [EffectSpec] -> [EffectDeclaration]
declareEffects = map declare
  where
    declare specification = EffectDeclaration (name specification) (entryMethod specification) (contextAsset (typing specification))
      [(method, handler, operation specification method) | (method, handler) <- handlerBindings specification]
      (NativeType (result specification))
      (case typing specification of Error { handles = matched } -> Just matched; _ -> Nothing)
      (case typing specification of Middleware { intercept = intercepted } -> intercepted; _ -> [])
    result specification = case typing specification of
      Pure _ -> "[String]"
      Excu _ -> "[String]"
      Scoped {} -> "[String]"
      Error {} -> "()"
      Middleware {} -> "[String]"
      Stream _ -> "()"
      Context { asset = declared } -> reference (representation declared)
    operation specification method = case typing specification of
      Excu _ -> AtomicOperation
      Scoped _ _ | Just method == entryMethod specification -> OpenResource
                 | otherwise -> CloseResource
      Stream _ -> SourceStep
      Pure _ -> PureOperation
      Context { asset = declared } -> PublishAsset (contractOf declared)
      Error {} -> ErrorOperation
      Middleware {} -> MiddlewareOperation
