{-# LANGUAGE DuplicateRecordFields #-}

-- 降级：把注册与 workflow 解析为 PrototypePlan，并完成注册级与 workflow 结构检查。
-- 这是 gen 唯一在声明加载进程（ghci）中执行的阶段：effects 与 ast 只有在那里能求值，
-- 结果经 Show/Read 交回生成器；之后的绑定、构图与输出都只读取这份计划。
module Framework.Gen.Lower
  ( lowerProgram, preparePrototype, buildEffectProtos
  ) where

import Control.Monad (unless, when)
import Data.Char (isAlphaNum, isUpper)
import Data.List (intercalate, intersect, nub, sort)
import Data.Maybe (listToMaybe, maybeToList)
import Framework.Gen.Demand (resolveDemands, contextNames, validateAssetSources, belowStream, continuousContext)
import Framework.Gen.Names (contextProducer, contextReader, effectMethodName, entryMethod, handlerBindings)
import Framework.Language.AST (WorkflowF(..))
import Framework.Language.Registration hiding (effectKind)
import qualified Framework.Language.Registration as Registration
import Framework.Prototype.Graph
import Framework.Prototype.Query
import Framework.Prototype.Types
import Framework.Prototype.Validate (valid, unique)
import Framework.Recursion (Fix(..), cata)

-- 声明加载进程的入口：生成器打印它的结果，再读回 PrototypePlan。
lowerProgram :: [EffectSpec] -> Fix WorkflowF -> SumTypes -> Either String PrototypePlan
lowerProgram specifications tree sumTypes =
  either (Left . show) Right (preparePrototype specifications sumTypes tree)

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
