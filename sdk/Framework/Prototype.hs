{-# LANGUAGE DuplicateRecordFields #-}

-- 统一静态原型的构建与校验门面；不包含闭包或运行中的资源。
-- Types 保存同一份纯模型，Query 提供结构查询，Sources 分析资产发布与读取来源。
-- 生成、执行装配和展示仍经本模块访问原型，不各自维护一份静态事实。
module Framework.Prototype
  ( NodeId, SumTypes, Prototype(..), PrototypePlan(..), EffectProto(..)
  , WorkflowTree(..), AlternativeProto(..), LifelongProto(..), SessionProto(..), BootPlan(..)
  , ChainRole(..), ChainProto(..)
  , ChainKind(..), ChainDefinition(..), ReadPoint(..), Source(..), PrototypeError(..)
  , buildEffectProtos, preparePrototype, buildPreparedPrototype, buildPrototype
  , validatePrototype, validateWorkflow, matchWorkflowLayer, checkDriven
  , driveSet, readPoints, resolveSources
  , expandChain, reachableMethods, calledMethods
  , lookupChain, lookupWorkflow, workflowNode, workflowChildren
  , workflowTerminals, workflowSelectors, workflowLifelongs, precedes, exclusive, visibleFrom
  , bootPlan, sessionSteps, finiteSessions
  ) where

import Control.Monad (unless, when)
import Data.Char (isAlphaNum, isUpper)
import Data.List (intercalate, intersect, nub, sort, (\\))
import Data.Maybe (listToMaybe, maybeToList)
import Framework.Effect.Contract (EffectKind(..))
import Framework.Effect.Demand (resolveDemands, contextNames, validateAssetSources)
import Framework.Effect.Graph
import Framework.Effect.Registration hiding (effectKind)
import qualified Framework.Effect.Registration as Registration
import Framework.Prototype.Types
import Framework.Prototype.Query
import Framework.Prototype.Sources (resolveSources)
import Framework.Recursion (Fix(..), cata)
import Framework.Workflow.AST (AST, WorkflowF(..), foldAST)

valid :: Bool -> String -> Either (PrototypeError method) ()
valid condition reason = unless condition (Left (InvalidPrototype reason))

unique :: Eq value => [value] -> Bool
unique values = length values == length (nub values)

sameSet :: Ord value => [value] -> [value] -> Bool
sameSet left right = sort (nub left) == sort (nub right)

fromRegistration :: Either String value -> Either (PrototypeError String) value
fromRegistration = either (Left . InvalidPrototype) Right

-- 注册关系的标准解析。Codegen 读取这些事实生成契约与包装，不再自行推导。
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
            Context {} -> listToMaybe
              [name anchor | anchor <- specifications, name anchor == input specification
                , Registration.effectKind (typing anchor) `elem` [ExcuKind, ScopedKind]
                , Just _ <- [entryMethod anchor]]
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
          Scoped (Just _) (Just _) -> pure ()
          _ -> Left (InvalidPrototype ("Input scope needs Scoped.open and Scoped.close: " ++ selected))
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
          Scoped opening closing -> do
            valid (length (requested specification) <= 1) ("Scoped requests at most one resource Context: " ++ name specification)
            valid (opening == Nothing || closing /= Nothing) ("Scoped.open needs Scoped.close for automatic cleanup: " ++ name specification)
          Context { asset = declared, parser = parsing, require = requiring, stream = streaming } -> do
            -- 持续交付只由上游 Stream 驱动：stream 当且仅当 input 是 Stream，持续资产也缓存最新值。
            valid (parsing /= Nothing) ("Context needs a parser handler: " ++ name specification)
            valid (streaming == belowStream specifications specification)
              (if streaming then "Context " ++ name specification ++ " declares stream = True but its input is not a Stream"
               else "Context " ++ name specification ++ " hangs below a Stream and needs stream = True")
            valid (not streaming || requiring) ("Context " ++ name specification ++ " declares stream = True and needs require = True")
            valid (validContractName (contractOf declared))
              ("Asset name must be a type name such as StartURL: " ++ contractOf declared ++ " in " ++ name specification)
            case representation declared of
              TypeRef _ -> pure ()
              _ -> Left (InvalidPrototype ("Context.request must wrap a business value, not Output: " ++ name specification))
            valid (null [() | anchor <- specifications, name anchor == input specification,
              Scoped {} <- [typing anchor], requestSource anchor == Just (name specification)])
              ("Context " ++ name specification ++ " cannot hang below the scope that requests it as its resource")
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
          || Registration.effectKind (typing specification) `elem` [PureKind, ExcuKind, ScopedKind])
          ("Only original-chain effects may subscribe with streams: " ++ name specification)
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
  -- 挂在 Stream 下时 getT 是 parser：只由会话在取得一份原始输入后调用，不是可请求的生产入口。
  selected@Context {} ->
    [ (if belowStream specifications specification then ContextStream else ContextRequest, method)
    | method <- maybeToList (contextProducer selected) ]
    ++ [(ContextRequire, method) | method <- maybeToList (contextReader selected)]
  Stream method -> named StreamHandler "next" method
  where
    named role prefix method = [(role, effectMethodName prefix (name specification)) | Just _ <- [method]]

preparePrototype :: [EffectSpec] -> SumTypes -> Fix WorkflowF -> Either (PrototypeError String) PrototypePlan
preparePrototype specifications sumTypes tree = do
  effects <- buildEffectProtos specifications sumTypes
  workflow <- numberWorkflow effects tree
  pure (PrototypePlan specifications effects workflow)

numberWorkflow :: [EffectProto String] -> Fix WorkflowF -> Either (PrototypeError String) WorkflowTree
numberWorkflow effects tree = cata number tree [] False
  where
    -- inside：是否位于 lifelong 内。持续订阅只能挂在 lifelong 内；lifelong 不嵌套。
    number (Node selected) path inside = do
      effect <- findEffectProto effects selected
      valid (effectKind effect `notElem` [ContextKind, ErrorKind, StreamKind])
        ("AST terminal must be an original callable handle: " ++ selected)
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
      sessions <- mapM (session path) (zip [0 ..] (nub (map snd subscriptions)))
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
    -- 持续资产只由上游 Stream 驱动。
    session path (index, contractType) = do
      producer <- case [effect | effect <- effects, effectProduces effect == Just contractType] of
        [effect] -> pure effect
        _ -> Left (UnknownPrototypeTarget contractType)
      let plan = bootPlan effects producer
      pure (SessionProto contractType plan [path ++ [-1, index, step] | step <- [0 .. sessionSteps plan - 1]])

-- 每个 Receive 资产一份 interpreter 托管的会话，挂载为 [-2, 序号, 步骤]；不属于 AST，
-- 不作为任何读取点的可见前驱，只在 lifelong 外的有限 require 缺少交付时惰性启动。
finiteSessions :: [EffectProto method] -> [SessionProto]
finiteSessions effects =
  [ SessionProto contractType plan [[-2, index, step] | step <- [0 .. sessionSteps plan - 1]]
  | (index, (contractType, plan)) <- zip [0 ..] receiving ]
  where
    receiving = [(contractType, plan) | effect <- effects, effectContinuous effect
      , Just contractType <- [effectProduces effect], let plan = bootPlan effects effect]

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

-- 候选对应只读 effect 原型中的 requires 与 Input 祖先；生成和加载校验共用。
candidateCase :: [EffectProto method] -> NodeId -> WorkflowTree
              -> Either (PrototypeError method) (String, String)
candidateCase effects path subtree = do
  cases <- mapM terminalCase (workflowTerminals subtree)
  case nub cases of
    [selected] -> pure selected
    _ -> invalid "Every candidate terminal must select the same constructor"
  where
    terminalCase selected = do
      effect <- findEffectProto effects selected
      let inherited = selected : effectInputChain effect
          cases = nub [(base, constructor)
            | consumer <- effects, effectName consumer `elem` inherited
            , demand <- effectDemands consumer, demandAccess demand == RequireAccess
            , producer <- effects, Just base <- [effectProduces producer]
            , (branch, constructor) <- effectBranches producer, branch == demandContract demand]
      case cases of
        [selectedCase] -> pure selectedCase
        _ -> invalid ("Candidate must require exactly one branch contract: " ++ selected)
    invalid reason = Left (InvalidAlternative path reason)

findEffectProto :: [EffectProto method] -> String -> Either (PrototypeError method) (EffectProto method)
findEffectProto effects selected = case filter ((== selected) . effectName) effects of
  [effect] -> Right effect
  _ -> Left (UnknownPrototypeTarget selected)

ordinaryEntry :: EffectProto method -> Either (PrototypeError method) method
ordinaryEntry effect = case [method | (role, method) <- effectMethods effect, role `elem` [HandlerMethod, ScopeOpen]] of
  method : _ -> pure method
  [] -> Left (InvalidPrototype ("Effect has no callable entry (no handler or open handler): " ++ effectName effect))

buildPrototype :: [EffectSpec] -> SumTypes -> [(String, MethodShape String)] -> Fix WorkflowF
               -> Either (PrototypeError String) (Prototype String)
buildPrototype specifications sumTypes shapes tree = do
  prepared <- preparePrototype specifications sumTypes tree
  buildPreparedPrototype prepared shapes

buildPreparedPrototype :: PrototypePlan -> [(String, MethodShape String)]
                       -> Either (PrototypeError String) (Prototype String)
buildPreparedPrototype plan shapes = do
  valid (unique (map fst shapes)) "Duplicate handler method in the structure generation plan"
  valid (all (`elem` map methodIdentity defaults) (map fst shapes)) "Unregistered handler method in the structure generation plan"
  let definitions = mergedDefinitions effects defaults shapes
  valid (null [(anchor, produced) | (anchor, produced) <- anchors effects
      , definition <- definitions, methodIdentity definition == produced
      , anchor `elem` reachableMethods definitions (filter (/= anchor) (calledMethods (methodBody definition)))])
    "An injected Context reaches its anchor through another method; call the anchor directly"
  mounted <- mapM mountedNode (allWorkflow workflow) >>= pure . concat
  selectors <- mapM mountedSelector [selected | selected@AlternativeAt {} <- allWorkflow workflow]
  sessions <- concat <$> mapM mountedSession lifelongSessionsOf
  finiteMounts <- concat <$> mapM mountedSession finite
  let mounts = mounted ++ selectors ++ sessions ++ finiteMounts
      entries = nub [method | (_, _, _, method) <- mounts]
      logical = withProducerReferences effects definitions
  graph <- either (Left . InvalidEffectGraph) Right (buildEffectGraph definitions (Choice (map Call entries)))
  names <- mapM scopeName orderedScopes
  declared <- mapM (scopeDeclaration names) orderedScopes
  scopes <- either (Left . InvalidEffectGraph) Right (completeScopeTree declared (buildScopeTree graph))
  let makeChain (identifier, role, terminal, method) = ChainProto identifier role terminal method
        (reachableMethods logical [method]) [] [] (maybe [] id (lookup method (graphRootPaths graph)))
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
        (map makeChain mounts) chainDefinitions graph scopes names []
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
  let continuousMethods = [(contractType, method) | effect <- effects, effectContinuous effect
        , Just contractType <- [effectProduces effect], (role, method) <- effectMethods effect
        , role `elem` [ContextRequest, ContextRequire, ContextStream]]
  mapM_ (\chain -> do
      let others = nub [contractType | (contractType, method) <- continuousMethods
            , method `elem` chainReaches chain, contractType /= chainTerminal chain]
      unless (null others) $ Left (InvalidLifelong (chainNode chain) ("Production of continuous asset "
        ++ chainTerminal chain ++ " depends on continuous assets " ++ intercalate ", " others
        ++ "; its first delivery would wait for another stream")))
    [makeChain mount | mount <- sessions]
  analyzed <- resolveSources written defaultReaders result
  validatePrototype analyzed
  pure analyzed
  where
    effects = plannedEffects plan
    workflow = plannedWorkflow plan
    lifelongSessionsOf = concatMap (lifelongSessions . snd) (workflowLifelongs workflow)
    finite = finiteSessions effects
    resources = [resource | effect <- effects, Just resource <- [effectResource effect]]
    defaults = [MethodDefinition method owner role (defaultBody effect role)
      | effect <- effects, (_, owner) : _ <- [effectMethods effect], (role, method) <- effectMethods effect]
    defaultBody effect ContextRequire
      | effectName effect `notElem` resources
      , Just producing <- lookup ContextRequest (effectMethods effect) = Choice [Empty, Call producing]
    defaultBody _ _ = Empty
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
    mountedNode (NodeAt identifier selected) = do
      effect <- findEffectProto effects selected
      method <- ordinaryEntry effect
      pure [(identifier, NodeChain, selected, method)]
    mountedNode _ = pure []
    mountedSelector (AlternativeAt _ selected _) = case
      [method | effect <- effects, effectProduces effect == Just (alternativeContract selected)
        , (ContextRequire, method) <- effectMethods effect] of
      [method] -> pure (alternativeSelector selected, SelectorChain, alternativeContract selected, method)
      _ -> Left (UnknownPrototypeTarget (alternativeContract selected))
    mountedSelector _ = Left (InvalidPrototype "Expected alternative selector")
    -- 会话挂载依次为 Stream 单步与 parser；终端名记资产名。
    mountedSession described = do
      producer <- case [effect | effect <- effects, effectProduces effect == Just (sessionAsset described)] of
        [effect] -> pure effect
        _ -> Left (UnknownPrototypeTarget (sessionAsset described))
      let roleOf effect role = maybe (Left (InvalidPrototype ("Session for " ++ sessionAsset described
            ++ " has no " ++ show role ++ " method"))) Right (lookup role (effectMethods effect))
      methods <- case sessionPlan described of
        Receive source -> do
          streamEffect <- findEffectProto effects source
          handle <- roleOf streamEffect StreamHandler
          parser <- roleOf producer ContextStream
          pure [handle, parser]
      valid (length methods == length (sessionMounts described)) ("Session steps differ for " ++ sessionAsset described)
      pure [(mount, SessionChain, sessionAsset described, method) | (mount, method) <- zip (sessionMounts described) methods]

anchors :: [EffectProto method] -> [(method, method)]
anchors effects = [(anchorMethod, produced)
  | effect <- effects, Just anchorName <- [effectAnchor effect]
  , Just produced <- [lookup ContextRequest (effectMethods effect)]
  , anchor <- effects, effectName anchor == anchorName
  , (role, anchorMethod) <- effectMethods anchor, role `elem` [HandlerMethod, ScopeOpen]]

mergedDefinitions :: [EffectProto String] -> [MethodDefinition String] -> [(String, MethodShape String)]
                  -> [MethodDefinition String]
mergedDefinitions effects defaults shapes =
  [definition { methodBody = injected (methodIdentity definition) (written definition) } | definition <- defaults]
  where
    written definition = maybe (methodBody definition) id (lookup (methodIdentity definition) shapes)
    bodyOf selected = maybe Empty written (listToMaybe [definition | definition <- defaults, methodIdentity definition == selected])
    injected selected body = case [replayed selected (bodyOf produced) | (anchor, produced) <- anchors effects, anchor == selected] of
      [] -> body
      contexts -> Sequence [body, Choice [Empty, Sequence contexts]]
    replayed anchor shape = case shape of
      Call method | method == anchor -> Empty
      Sequence children -> Sequence (map (replayed anchor) children)
      Choice children -> Choice (map (replayed anchor) children)
      Recover body recovery -> Recover (replayed anchor body) (replayed anchor recovery)
      other -> other

calledMethods :: MethodShape method -> [method]
calledMethods Empty = []
calledMethods (Call method) = [method]
calledMethods (Sequence children) = concatMap calledMethods children
calledMethods (Choice children) = concatMap calledMethods children
calledMethods (Recover body recovery) = calledMethods body ++ calledMethods recovery

reachableMethods :: Eq method => [MethodDefinition method] -> [method] -> [method]
reachableMethods definitions = visit []
  where
    visit seen [] = seen
    visit seen (method : rest)
      | method `elem` seen = visit seen rest
      | otherwise = visit (seen ++ [method])
          (concat [calledMethods (methodBody definition) | definition <- definitions, methodIdentity definition == method] ++ rest)

withProducerReferences :: Eq method => [EffectProto method] -> [MethodDefinition method] -> [MethodDefinition method]
withProducerReferences effects definitions =
  [definition { methodBody = Sequence (methodBody definition : [Call produced
      | (anchor, produced) <- anchors effects, anchor == methodIdentity definition]) }
  | definition <- definitions]

-- 首次尚无 Handlers 时仅生成契约；有源码快照后必须另外执行这个驱动检查。
checkDriven :: Prototype String -> Either (PrototypeError String) ()
checkDriven prototype = valid (null undriven)
  ("Context never driven from the AST: " ++ intercalate ", " undriven
    ++ "; no terminal reaches its production or the handle it hangs below")
  where
    reached = reachableMethods (withProducerReferences (protoEffects prototype) (protoMethods prototype))
      (map chainEntry (protoChains prototype))
    undriven = [methodIdentity definition | definition <- protoMethods prototype
      , methodRole definition == ContextRequest, methodIdentity definition `notElem` reached]

-- 运行装配和纯展示共用层校验，不再为执行检查重复 fold 当前 AST。
matchWorkflowLayer :: WorkflowF child -> WorkflowTree -> Either (PrototypeError method) [WorkflowTree]
matchWorkflowLayer (Node selected) (NodeAt _ expected)
  | selected == expected = pure []
matchWorkflowLayer (Chained children) (ChainedAt _ expected)
  | length children == length expected = pure expected
matchWorkflowLayer (Parallel children) (ParallelAt _ expected)
  | length children == length expected = pure expected
matchWorkflowLayer (Alternative children) (AlternativeAt _ _ expected)
  | length children == length expected = pure expected
matchWorkflowLayer (Lifelong children) (LifelongAt _ _ expected)
  | length children == length expected = pure expected
matchWorkflowLayer _ _ = Left PrototypeWorkflowMismatch

validateWorkflow :: Prototype method -> AST -> Either (PrototypeError method) ()
validateWorkflow prototype ast = foldAST check ast (protoWorkflow prototype)
  where
    check layer expected = do
      children <- matchWorkflowLayer layer expected
      sequence_ (zipWith ($) (childChecks layer) children)
    childChecks (Node _) = []
    childChecks (Chained children) = children
    childChecks (Parallel children) = children
    childChecks (Alternative children) = children
    childChecks (Lifelong children) = children

-- 只核对显式字段的自洽性，不展开 methodBody、不重构图或修正手调 scope 父边。
validatePrototype :: (Ord method, Show method) => Prototype method -> Either (PrototypeError method) ()
validatePrototype prototype = do
  valid (unique (map name registrations) && unique (map effectName effects)) "Duplicate registered effect"
  valid (map name registrations == map effectName effects) "Effect prototypes differ from registrations"
  valid (and [effectInput effect == input registration
      && effectKind effect == Registration.effectKind (typing registration)
    | (registration, effect) <- zip registrations effects]) "Effect metadata differs from registration snapshot"
  valid (unique allMethodIds) "Duplicate method definition"
  valid (sameSet allMethodIds (concatMap (map snd . effectMethods) effects)) "Effect method coverage differs"
  valid (and [any (\definition -> methodIdentity definition == method
      && methodRole definition == role && methodEffect definition == owner) definitions
    | effect <- effects, (_, owner) : _ <- [effectMethods effect], (role, method) <- effectMethods effect])
    "Method roles or effect identities differ from effect prototypes"
  valid (all (`elem` allMethodIds) [methodEffect definition | definition <- definitions]) "Unknown method effect identity"
  valid (all (`elem` allMethodIds) (concatMap (calledMethods . methodBody) definitions)) "Unknown method body reference"
  valid (unique methodIds) "Duplicate graph method identity"
  valid (all (`elem` definitions) (graphMethods graph)) "Graph definitions differ from prototype definitions"
  valid (unique (graphRoots graph)) "Duplicate graph root"
  valid (all (`elem` methodIds) (graphRoots graph)) "Unknown graph root"
  valid (sameSet (map chainEntry chains) (graphRoots graph)) "Mounted chains differ from graph roots"
  valid (all (knownPair methodIds) (graphReferences graph)) "Unknown method reference"
  valid (unique observedScopes) "Duplicate graph scope identity"
  valid (sameSet observedScopes [methodIdentity method | method <- graphMethods graph, methodRole method == ScopeOpen])
    "Graph scope identities do not match its open methods"
  valid (all (`elem` observedScopes) (concat (graphScopePaths graph))) "Unknown scope in graph path"
  valid (sameSet observedScopes (concat (graphScopePaths graph))) "Graph scope path coverage differs"
  valid (unique (map fst (graphRootPaths graph)) && sameSet (map fst (graphRootPaths graph)) (graphRoots graph)) "Graph entry path coverage differs"
  valid (all (all (all (`elem` observedScopes)) . snd) (graphRootPaths graph)) "Unknown scope in entry path"
  valid (sameSet (concatMap snd (graphRootPaths graph)) (graphScopePaths graph)
    || null (graphRoots graph) && graphScopePaths graph == [[]]) "Graph paths differ from entry paths"
  valid (all (knownPair observedScopes) (graphScopeOrder graph)) "Unknown scope in graph order"
  valid (unique (map fst names) && unique (map snd names)) "Duplicate scope identity or name"
  valid (sameSet names [(method, effectName effect) | effect <- effects, (ScopeOpen, method) <- effectMethods effect])
    "Scope names differ from the registered open methods"
  valid (all (\(identity, _) -> any (\definition -> methodIdentity definition == identity && methodRole definition == ScopeOpen) definitions) names)
    "Scope name does not reference an open method"
  valid (unique nodeIds) "Duplicate scope node"
  valid (sameSet (map fst names) nodeIds) "Scope names do not cover exactly the tree nodes"
  valid (all (`elem` nodeIds) observedScopes) "Missing observed scope identity"
  mapM_ validateScopeNode (scopeNodes tree)
  valid (sameSet parentEdges childEdges) "Scope parent and child references disagree"
  expectedLayers <- layers nodeIds
  valid (unique (scopeRoots tree) && sameSet (scopeRoots tree) [scopeIdentity node' | node' <- scopeNodes tree, null (scopeParents node')])
    "Scope roots disagree with parent references"
  valid (length expectedLayers == length (scopeLayers tree)
    && and (zipWith sameSet expectedLayers (scopeLayers tree)) && unique (concat (scopeLayers tree)))
    "Scope layers disagree with parent references"
  valid (sameSet (scopePaths tree) (graphScopePaths graph)) "Scope tree paths differ from the generated graph"
  valid (sameSet (scopeCandidates tree) (graphScopeOrder graph)) "Scope candidates differ from the generated graph"
  valid (all (knownPair nodeIds) (scopeOpposed tree ++ scopeUndetermined tree)) "Unknown scope in order evidence"
  checkWorkflow [] (protoWorkflow prototype)
  valid (protoSessions prototype == finiteSessions effects) "Interpreter sessions differ from the Receive assets"
  valid (unique (map chainNode chains)) "Duplicate mounted chain NodeId"
  valid (sameSet (map chainNode chains) expectedChainIds) "Mounted chain coverage differs from workflow"
  mapM_ validateChain chains
  valid (unique (map definitionEntry chainDefinitions)) "Duplicate chain definition"
  valid (sameSet (map definitionEntry chainDefinitions)
    [method | effect <- effects, (role, method) <- effectMethods effect
      , role `elem` [HandlerMethod, ScopeOpen, ContextRequest, ContextRequire, ContextStream, StreamHandler]])
    "Chain definitions do not cover the registered entries"
  mapM_ validateDefinition chainDefinitions
  valid (unique (map fst (protoSources prototype))) "Duplicate asset read point"
  mapM_ validateSource (protoSources prototype)
  mapM_ (\chain -> do
    valid (unique (chainDrives chain) && all (`elem` contracts) (chainDrives chain)) "Invalid driven asset contracts"
    valid (unique (chainReads chain) && sameSet (chainReads chain)
      [readContract point | (point, _) <- protoSources prototype, readNode point == chainNode chain])
      "Chain reads differ from the source table") chains
  where
    registrations = protoRegistrations prototype
    effects = protoEffects prototype
    definitions = protoMethods prototype
    allMethodIds = map methodIdentity definitions
    graph = protoGraph prototype
    tree = protoScopes prototype
    names = protoScopeNames prototype
    chains = protoChains prototype
    chainDefinitions = protoChainDefinitions prototype
    contracts = [contractType | effect <- effects, Just contractType <- [effectProduces effect]]
    validateSource (point, source) = do
      _ <- lookupChain prototype (readNode point)
      valid (readContract point `elem` contracts) "Read point has no base Context contract"
      case source of
        FromOwnChain -> pure ()
        FromSession -> valid (readContract point `elem` [sessionAsset session | session <- protoSessions prototype])
          "Session source has no interpreter session"
        FromChains selected -> do
          valid (not (null selected) && unique selected) "Invalid asset source alternatives"
          mapM_ (\node' -> do
            chain <- lookupChain prototype node'
            valid (node' /= readNode point && precedes (protoWorkflow prototype) node' (readNode point))
              "Asset source is not a completed visible chain"
            valid (readContract point `elem` chainDrives chain) "Asset source has no matching production") selected
    methodIds = map methodIdentity (graphMethods graph)
    observedScopes = graphScopes graph
    nodeIds = map scopeIdentity (scopeNodes tree)
    parentEdges = [(parent, scopeIdentity node') | node' <- scopeNodes tree, parent <- scopeParents node']
    childEdges = [(scopeIdentity node', child) | node' <- scopeNodes tree, child <- scopeChildren node']
    knownPair known (left, right) = left `elem` known && right `elem` known
    validateScopeNode node' = do
      let linked = scopeParents node' ++ scopeChildren node'
      valid (all (`elem` nodeIds) linked) "Unknown scope parent or child"
      valid (scopeIdentity node' `notElem` linked) "Scope node refers to itself"
      valid (unique (scopeParents node') && unique (scopeChildren node')) "Duplicate scope parent or child"
    parents selected = [parent | (parent, child) <- parentEdges, child == selected]
    layers [] = Right []
    layers remaining =
      let ready = [selected | selected <- remaining, all (`notElem` remaining) (parents selected)]
      in if null ready then Left (InvalidEffectGraph (CyclicScopeRelations remaining))
         else (ready :) <$> layers (remaining \\ ready)
    expectedChainIds = concat [case selected of
      NodeAt identifier _ -> [identifier]
      AlternativeAt _ choice _ -> [alternativeSelector choice]
      LifelongAt _ described _ -> concatMap sessionMounts (lifelongSessions described)
      _ -> [] | selected <- allWorkflow (protoWorkflow prototype)]
      ++ concatMap sessionMounts (protoSessions prototype)
    checkWorkflow expected selected = do
      valid (workflowNode selected == expected) "Workflow NodeId differs from AST path"
      case selected of
        NodeAt _ terminal -> do
          effect <- findEffectProto effects terminal
          valid (effectKind effect `notElem` [ContextKind, ErrorKind, StreamKind]) "Workflow node is not an origin chain"
        AlternativeAt identifier choice children -> do
          valid (alternativeSelector choice == identifier ++ [-1]) "Alternative selector has an invalid NodeId"
          valid (map fst (alternativeCases choice) == map workflowNode children) "Alternative case paths differ from children"
          let constructors = concat [map snd (effectBranches effect) | effect <- effects,
                effectProduces effect == Just (alternativeContract choice)]
              selectedCases = map snd (alternativeCases choice)
          valid (not (null constructors) && unique selectedCases && sameSet selectedCases constructors)
            "Alternative cases do not cover the contract constructors"
          declaredCases <- mapM (candidateCase effects identifier) children
          valid (declaredCases == [(alternativeContract choice, constructor) | constructor <- selectedCases])
            "Alternative cases differ from candidate requirements"
        LifelongAt identifier described children -> do
          let inner = concatMap allWorkflow children
              mounted = [(node', terminal) | NodeAt node' terminal <- inner]
          valid (null [() | LifelongAt {} <- inner]) "Lifelong is nested"
          valid (sameSet (lifelongUnits described) (concat [case child of
              ParallelAt _ grand -> map workflowNode grand
              _ -> [workflowNode child] | child <- children])) "Lifelong units differ from its children"
          valid (sameSet (map fst (lifelongSubscriptions described)) (map fst mounted)
            && unique (map fst (lifelongSubscriptions described))) "Lifelong subscriptions differ from its targets"
          valid (sameSet (map sessionAsset (lifelongSessions described)) (nub (map snd (lifelongSubscriptions described)))
            && unique (map sessionAsset (lifelongSessions described))) "Lifelong sessions differ from subscribed assets"
          valid (and [ sessionMounts session == [identifier ++ [-1, index, step] | step <- [0 .. steps - 1]]
            | (index, session) <- zip [0 ..] (lifelongSessions described)
            , let steps = sessionSteps (sessionPlan session) ])
            "Lifelong session mounts have invalid NodeIds"
          valid (and [ any (\effect -> effectContinuous effect && effectProduces effect == Just contractType) effects
            | (_, contractType) <- lifelongSubscriptions described ]) "Lifelong subscribes to a non-continuous asset"
        _ -> pure ()
      sequence_ [checkWorkflow (expected ++ [index]) child | (index, child) <- zip [0 ..] (workflowChildren selected)]
    validateChain chain = do
      valid (unique (chainReaches chain) && all (`elem` allMethodIds) (chainReaches chain)
        && chainEntry chain `elem` chainReaches chain) "Invalid reachable method set"
      valid (lookup (chainEntry chain) (graphRootPaths graph) == Just (chainScopePaths chain)) "Chain scope paths differ from graph root"
      valid ([definitionReaches definition | definition <- chainDefinitions,
        definitionEntry definition == chainEntry chain] == [chainReaches chain])
        "Mounted chain differs from its method definition"
      case chainRole chain of
        NodeChain -> case lookupWorkflow (protoWorkflow prototype) (chainNode chain) of
          Just (NodeAt _ terminal) -> do
            valid (terminal == chainTerminal chain) "Chain terminal differs from workflow"
            effect <- findEffectProto effects terminal
            entry <- ordinaryEntry effect
            valid (entry == chainEntry chain) "Chain entry differs from effect entry"
          _ -> Left (InvalidPrototype "Node chain has no workflow node")
        SelectorChain -> case [choice | AlternativeAt _ choice _ <- allWorkflow (protoWorkflow prototype),
            alternativeSelector choice == chainNode chain] of
          [choice] -> valid (alternativeContract choice == chainTerminal chain
            && chainEntry chain `elem` [method | effect <- effects, effectProduces effect == Just (chainTerminal chain)
              , (ContextRequire, method) <- effectMethods effect]) "Selector chain differs from alternative"
          _ -> Left (InvalidPrototype "Selector chain has no alternative")
        SessionChain -> case [ (session, step)
            | session <- concatMap (lifelongSessions . snd) (workflowLifelongs (protoWorkflow prototype))
                ++ protoSessions prototype
            , (step, mount) <- zip [0 :: Int ..] (sessionMounts session), mount == chainNode chain ] of
          [(session, step)] -> do
            producer <- case [effect | effect <- effects, effectProduces effect == Just (sessionAsset session)] of
              [effect] -> pure effect
              _ -> Left (InvalidPrototype "Session asset has no producer")
            let expectedRole = case (sessionPlan session, step) of
                  (Receive _, 0) -> Nothing
                  (Receive _, _) -> Just ContextStream
                streamEntries = case sessionPlan session of
                  Receive source -> [method | effect <- effects, effectName effect == source
                    , (StreamHandler, method) <- effectMethods effect]
                expected = maybe streamEntries (\role -> [method | (role', method) <- effectMethods producer, role' == role]) expectedRole
            valid (sessionAsset session == chainTerminal chain && expected == [chainEntry chain])
              "Session chain differs from its boot plan"
          _ -> Left (InvalidPrototype "Session chain has no session")
    validateDefinition definition = do
      effect <- findEffectProto effects (definitionEffect definition)
      let roles = [role | (role, method) <- effectMethods effect, method == definitionEntry definition]
          expectedRoles = case definitionKind definition of
            OriginChain -> [HandlerMethod, ScopeOpen]
            ContextChain -> [ContextRequest, ContextRequire, ContextStream, StreamHandler]
      valid (not (null roles) && all (`elem` expectedRoles) roles) "Chain kind differs from its method role"
      valid (unique (definitionReaches definition) && all (`elem` allMethodIds) (definitionReaches definition)
        && definitionEntry definition `elem` definitionReaches definition) "Invalid chain definition reachability"
