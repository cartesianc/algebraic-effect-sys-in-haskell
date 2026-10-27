{-# LANGUAGE DuplicateRecordFields #-}

-- 将注册和选定末端 lower 为普通 Haskell 源码；不执行业务。
module Framework.Codegen (Entry(..), lowerProgram) where

import Framework.Effect.Contract (EffectKind(..))
import Framework.Effect.Registration
import Framework.Codegen.Plan (GraphPlan(..))
import qualified Framework.Effect.Graph as Graph
import Data.Char (isAlphaNum, isUpper, toUpper)
import Data.List (intercalate, intersect, nub)
import Data.Maybe (fromMaybe, listToMaybe, maybeToList)

-- 3. 生成契约、superclass 和末端句柄登记。
-- 不生成外部 request 流水线；上游方法由用户 instance 直接引用。
-- Input 保存操作能力；Context 经 demands 按契约解析来源，消费方不指名生产者的类。
data Entry = SingleTarget String | Workflow [String]

-- 结构分析使用的取值路由：消费方类 → ((request|require, 契约名), 来源方法)；
-- 以及 Context 的生产／读取方法，供拒绝跨 effect 直接调用。
type DemandRoutes = ([(String, [((String, String), String)])], [(String, String)])

lowerProgram :: String -> [EffectSpec] -> Entry
             -> Either String (String, String, [(String, String, String)], String, GraphPlan String, [String], DemandRoutes, [(String, String, Bool)])
lowerProgram namespace specifications entry = do
  if any ((== "Root") . name) specifications
    then Left "Root is reserved for the superclass"
    else pure ()
  mapM_ checkInput specifications
  _ <- resolvedEither
  mapM_ checkDemandNames specifications
  checkGenerated
  mapM_ checkError specifications
  checkErrorOverlap
  mapM_ (contextNames specifications . pure . name) specifications
  if null selected
    then Left "Select at least one terminal effect for generation"
    else pure ()
  selectedMethods <- mapM findHandler selected
  let allMethods = concatMap registeredMethods specifications
  if length allMethods /= length (nub (map snd allMethods))
    then Left "Registered method names must be unique within a generated module"
    else pure ()
  declarations <- mapM declaration specifications
  singleEntry <- case entry of
    SingleTarget terminal -> do
      method <- findHandler terminal
      pure
        [ "-- 纯计算样例也只登记末端句柄，不在外部组合上游。"
        , "compiledTarget :: SDK.Target SDK.Identity ContextValues Errors (Produce " ++ terminal ++ ")"
        , "compiledTarget = SDK.targetPure " ++ show terminal ++ " emptyContexts"
        , "  (FrameworkRoot.withErrorHandlers Handlers.errorHandlers " ++ method ++ ")"
        , ""
        , "benchmark :: Output Errors (Produce " ++ terminal ++ ")"
        , "benchmark = SDK.bootPure compiledTarget"
        , ""
        , "registeredTarget :: String"
        , "registeredTarget = " ++ show terminal
        , ""
        , "-- 生成入口由 SDK 提供；业务无需另写 Codegen 模块。"
        , "runDemo :: Show value => [EffectSpec] -> String -> value -> IO ()"
        , "runDemo = SDK.runDemo " ++ show namespace ++ " registeredEffects registeredTarget Handlers.handlerSourceFingerprint"
        ]
    Workflow _ -> pure []
  pure
    ( unlines (contractHeader ++ runtimeAliases ++ generatedContracts ++ methodIdentities ++ concat declarations
        ++ providerDeclarations ++ errorDeclaration ++ contextDeclarations)
    , unlines (programHeader ++ registrationSnapshot ++ structureDeclarations ++ singleEntry ++ astInterpreter selectedMethods)
    , concatMap instanceWrappers specifications
    , scopeHandlers ++ scopeCleanups ++ errorHandlers
    , graphPlan
    , nub [reference representation' | (_, representation', _) <- generatedDeclarations]
    , (demandRoutes, contextMethods)
    , contractOwners
    )
  where
    resolvedEither = mapM (\specification -> (,) (name specification) <$> resolveDemands specifications specification) specifications
    resolvedTable = either (const []) id resolvedEither
    resolvedOf selectedName = fromMaybe [] (lookup selectedName resolvedTable)
    requestProviders specification =
      nub [demandProvider resolved | resolved <- resolvedOf (name specification), demandAccess resolved == RequestAccess]
    requireProviders specification =
      nub [demandProvider resolved | resolved <- resolvedOf (name specification), demandAccess resolved == RequireAccess]
    -- Scoped 至多 request 一个资源 Context；它就是该 scope 的资源来源。
    requestSource = listToMaybe . requestProviders
    producerMethod providerName = listToMaybe
      [method | specification <- specifications, name specification == providerName
              , Context (Just Requester { handler = method }) _ <- [typing specification]]
    readerMethod providerName = listToMaybe
      [method | specification <- specifications, name specification == providerName
              , Context _ (Just method) <- [typing specification]]
    sourceMethod resolved = case demandAccess resolved of
      RequestAccess -> producerMethod (demandProvider resolved)
      RequireAccess -> readerMethod (demandProvider resolved)
    accessWord RequestAccess = "request"
    accessWord RequireAccess = "require"
    demandRoutes =
      [ (name specification ++ "Effect",
          [ ((accessWord (demandAccess resolved), demandContract resolved), method)
          | resolved <- resolvedOf (name specification), Just method <- [sourceMethod resolved] ])
      | specification <- specifications ]
    -- 每个 Context 的契约类型由 handler 名生成：(契约名, 表示类型, 生产方)。
    generatedDeclarations =
      [ (contractOf producing, representation producing, name specification)
      | specification <- contextSpecs
      , Context (Just producing) _ <- [typing specification] ]
    -- 构造器归属：契约类型只能由其生产方的 instance 方法构造；契约均由生成器产出。
    contractOwners =
      [ (contractType, owner ++ "Effect", True)
      | (contractType, _, owner) <- generatedDeclarations, validTypeName contractType ]
    contextMethods =
      [ (name specification ++ "Effect", method)
      | specification <- contextSpecs
      , method <- maybeToList (entryMethod (typing specification))
          ++ (case typing specification of Context _ reading -> maybeToList reading; _ -> []) ]

    selected = case entry of
      SingleTarget terminal -> [terminal]
      Workflow terminals -> nub terminals
    isWorkflow = case entry of
      Workflow _ -> True
      SingleTarget _ -> False
    contextSpecs = filter ((== ContextKind) . effectKind . typing) specifications
    contractHeader =
      [ "{-# LANGUAGE ConstraintKinds #-}"
      , "{-# LANGUAGE DataKinds #-}"
      , "{-# LANGUAGE EmptyDataDecls #-}"
      , "{-# LANGUAGE DeriveGeneric #-}"
      , "{-# LANGUAGE FlexibleContexts #-}"
      , "{-# LANGUAGE FlexibleInstances #-}"
      , "{-# LANGUAGE MultiParamTypeClasses #-}"
      , "{-# LANGUAGE StandaloneDeriving #-}"
      , "{-# LANGUAGE TypeApplications #-}"
      , "{-# LANGUAGE TypeFamilies #-}"
      , "{-# LANGUAGE TypeOperators #-}"
      , "{-# LANGUAGE UndecidableInstances #-}"
      , "{-# LANGUAGE UndecidableSuperClasses #-}"
      , ""
      , "-- 自动生成；通过 SDK 的 effect-codegen 更新，手写注册与 handler 位于上级目录。"
      , "module " ++ namespace ++ ".Generated.Effects where"
      , ""
      , "import Framework.Effect.Contract (Effect(..), Registered)"
      , "import qualified Framework.Effect.Contract as FrameworkRoot"
      , "import qualified Framework.SDK as SDK"
      , "import " ++ namespace ++ ".Types"
      , ""
      ]

    -- 身份是生成的封闭 ADT；手写调用仍引用原生类方法。
    registeredMethods specification =
      [(specification, method) | method <- maybeToList (entryMethod (typing specification))
        ++ (case typing specification of Scoped _ closing -> maybeToList closing; _ -> [])
        ++ errorMethods specification
        ++ (case typing specification of Context _ reading -> maybeToList reading; _ -> [])]
    genName [] = "MissingMethodGen"
    genName (first : rest) = toUpper first : rest ++ "Gen"
    methodIdentities =
      [ "-- 方法定义身份；仅生成区使用，图中不以字符串匹配方法。"
      , "data MethodGen = " ++ intercalate " | "
          [genName method | (_, method) <- concatMap registeredMethods specifications]
      , "  deriving (Eq, Ord, Show, Read, SDK.Generic)"
      , "instance SDK.NFData MethodGen"
      , ""
      ]
    methodRole specification method = case typing specification of
      Scoped opening _ -> if Just method == opening then Graph.ScopeOpen else Graph.ScopeClose
      Context producing _ -> if fmap (\Requester { handler = selectedMethod } -> selectedMethod) producing == Just method
        then Graph.ContextRequest else Graph.ContextRequire
      Error { detect = detecting } -> if Just method == detecting then Graph.ErrorDetect else Graph.ErrorResolve
      _ -> Graph.HandlerMethod
    graphPlan = GraphPlan
      { planDefinitions =
          [ Graph.MethodDefinition method firstMethod (methodRole specification method) Graph.Empty
          | (specification, method) <- concatMap registeredMethods specifications
          , (_, firstMethod) : _ <- [registeredMethods specification] ]
      -- require @T 在结构分析时已直接解析为来源的读取方法，不再需要按消费者改写生产调用。
      , planRoutes = []
      , planScopes =
          [ (opening, selectedScope, scopeRegistrationParents specification)
          | selectedScope <- orderedScopes
          , specification <- specifications, name specification == selectedScope
          , Scoped (Just opening) _ <- [typing specification] ]
      , planEntries = [(terminal, method) | terminal <- selected, Right method <- [findHandler terminal]]
      }
    structureDeclarations =
      [ "-- 生成身份连接到已有运行 scope 名；依赖只保存在下方显式 ScopeTree 中。"
      , "scopeNames :: [(MethodGen, String)]"
      , "scopeNames = [" ++ intercalate ", "
          [ "(" ++ genName opening ++ ", " ++ show scopeName ++ ")"
          | (opening, scopeName, _) <- planScopes graphPlan ] ++ "]"
      , ""
      , "-- 只校验生成常量；当前 workflow 在执行装配的一次 fold 中检查入口。"
      , "programStructure :: Either (SDK.StructureError MethodGen) (SDK.ProgramStructure MethodGen)"
      , "programStructure = SDK.initializeGeneratedStructure"
      , "  [" ++ intercalate ", "
          ["(" ++ show terminal ++ ", " ++ genName method ++ ")"
          | (terminal, method) <- planEntries graphPlan] ++ "]"
      , "  scopeNames generatedEffectGraph generatedScopeTree"
      , ""
      ]
    programHeader =
      [ "{-# LANGUAGE DuplicateRecordFields #-}"
      , "{-# LANGUAGE TypeFamilies #-}"
      , ""
      , "-- 自动生成；只登记末端句柄，Node algebra 才 lower，业务组合仍在 handler 内。"
      , "module " ++ namespace ++ ".Generated.Program where"
      , ""
      , "import Framework.SDK (Effect(..), EffectSpec(..), EffectTyping(..), Requester(..), Handles(..), Demand(..), Access(..), TypeRef(..), Output)"
      , "import qualified Framework.SDK as SDK"
      , "import qualified Framework.Effect.Contract as FrameworkRoot"
      , "import " ++ namespace ++ ".Generated.Effects hiding (request, require)"
      , "import qualified " ++ namespace ++ ".Generated.Handlers as Handlers"
      , "import " ++ namespace ++ ".Types"
      , ""
      ]
    -- 消费方以契约取值；生成的 instance 按当前消费者分派到 demands 解析出的来源方法。
    providerDeclarations =
      [ "-- 依值入口：request 重新生产，require 读取已有绑定；来源由注册解析，不由消费方指名。"
      , "class Provides contract m where"
      , "  request :: m contract"
      , "  require :: m contract"
      , ""
      ] ++ concat
      -- instance 固定在本程序的载体上：泛型 handler 的推导约束不会被化简成具体生产方的类。
      -- 生产方类的 instance 位于 Handlers，因此以无变量上下文延迟到使用处求解。
      [ [ "instance (" ++ intercalate ", " [provider ++ "Effect " ++ carrierType | provider <- providers] ++ ") => Provides "
            ++ contractType ++ " " ++ carrierType ++ " where"
        , "  request = SDK.provideContext " ++ show contractType ++ " ContextBindingError " ++ routeList RequestAccess
        , "  require = SDK.provideContext " ++ show contractType ++ " ContextBindingError " ++ routeList RequireAccess
        , "" ]
      | demanded <- nub [demandContract resolved | (_, resolvedDemands) <- resolvedTable, resolved <- resolvedDemands]
      , let contractType = demanded
            routes selectedAccess =
              [ (consumer, method)
              | (consumer, resolvedDemands) <- resolvedTable, resolved <- resolvedDemands
              , demandContract resolved == demanded, demandAccess resolved == selectedAccess
              , Just method <- [sourceMethod resolved] ]
            providers = nub [demandProvider resolved | (_, resolvedDemands) <- resolvedTable, resolved <- resolvedDemands
              , demandContract resolved == demanded]
            routeList selectedAccess = "[" ++ intercalate ", "
              ["(" ++ show consumer ++ ", " ++ method ++ ")" | (consumer, method) <- routes selectedAccess] ++ "]" ]

    carrierType = if isWorkflow then "App" else "Pure"

    -- 生成的契约类型；不派生 Read，值只能由声明它的生产方构造。
    -- Eq／Show 仅在表示类型具备时可用。
    generatedContracts = case generatedDeclarations of
      [] -> []
      _ -> "-- 每个 Context 的契约类型：名字来自 handler 名，包装其表示类型；只能由该生产方构造。"
        : concat
          [ [ "newtype " ++ generated ++ " = " ++ generated ++ " (" ++ reference representation' ++ ")"
            , "deriving instance Eq (" ++ reference representation' ++ ") => Eq " ++ generated
            , "deriving instance Show (" ++ reference representation' ++ ") => Show " ++ generated
            , "" ]
          | (generated, representation', _) <- generatedDeclarations ]

    runtimeAliases =
      [ "-- SDK 提供运行载体与空存储；Context 经声明的 request/require 取得。"
      , "type Root = SDK.Root ContextValues Errors"
      , if isWorkflow then "type App = SDK.App ContextValues Errors"
                      else "type Pure = SDK.Pure ContextValues Errors"
      , ""
      ]

    -- 注册时连接生产/读取入口；业务方法使用原生 Haskell 取值，不改写表达式。
    instanceWrappers specification =
      [ (name specification ++ "Effect", method, wrapper method)
      | method <- maybeToList (entryMethod (typing specification)) ++ closing
          ++ errorMethods specification ++ maybeToList reading ]
      where
        selectedName = name specification
        closing = case typing specification of
          Scoped _ method -> maybeToList method
          _ -> []
        reading = case typing specification of
          Context _ method -> method
          _ -> Nothing
        scopedDependencies = "FrameworkRuntime.withScopeDependencies "
          ++ show (upstreamScopes specification)
        rootWrapper = "FrameworkRoot.withErrorPath " ++ show (errorPath specification)
          ++ " . FrameworkRoot.handler @FrameworkGenerated.Root"
        wrapper method
          -- require 的覆盖实现同样检查来源声明，不刷新来源或改变消费者身份。
          | Just method == reading = "(" ++ rootWrapper
              ++ " . FrameworkRuntime.requireContext " ++ show selectedName
              ++ " FrameworkGenerated.ContextBindingError "
              ++ contextAccessTable "FrameworkRuntime." selectedName ++ ")"
          | otherwise = "(" ++ rootWrapper ++ " . " ++ (case typing specification of
              -- 先进入本 scope，再检查其上游；失效后的 close 仍可读取自己的 Context 以收尾。
              Scoped _ closingMethod ->
                "FrameworkRuntime." ++ (if Just method == closingMethod then "closeScope " else "openScope ")
                  ++ show selectedName ++ " FrameworkGenerated.ScopeBindingError . "
                  ++ scopedDependencies ++ " . FrameworkRuntime.enterHandler " ++ show selectedName
              _ -> scopedDependencies ++ " . " ++ operation) ++ ")"
        operation = case typing specification of
          Context (Just _) _ ->
            "FrameworkRuntime.callContext " ++ show selectedName
              ++ " FrameworkGenerated.ContextBindingError\n"
              ++ "  " ++ contextAccessTable "FrameworkRuntime." selectedName
              ++ "\n  " ++ observation "FrameworkRuntime." selectedName
              ++ "\n  FrameworkGenerated.bound" ++ selectedName
              ++ "\n  (\\value bindings -> bindings { FrameworkGenerated.bound" ++ selectedName ++ " = Just value })"
          _ -> "FrameworkRuntime.enterHandler " ++ show selectedName

    -- 生产与显式读取共用声明表；读取只校验来源，不采用 request 的刷新行为。
    contextAccessTable prefix selectedName = "[" ++ intercalate ", "
      [ "(" ++ show (name consumer) ++ ", " ++ prefix ++ access ++ ")"
      | consumer <- specifications
      , Just access <- [accessFor consumer] ] ++ "]"
      where
        accessFor consumer
          | selectedName `elem` requestProviders consumer = Just "RequestValue"
          | selectedName `elem` requireProviders consumer = Just "RequireValue"
          | otherwise = Nothing

    errorMethods specification = case typing specification of
      Error { detect = detecting, resolve = resolving } -> maybeToList detecting ++ maybeToList resolving
      _ -> []

    -- 同时保留原 Input 和 request 生产链；从 Root 方向向下，先原 Input 再 request。
    -- 共享祖先按身份去重；require 不启动生产链。
    operationInputs specification = nub (input specification : requestProviders specification)
    upstreamScopes specification = nub (concatMap (scopeNames []) (operationInputs specification))
    -- App/IO 的 withErrorPath 只接收关联种子；祖先和 top-down 顺序由同一 ScopeTree 决定。
    -- Pure 尚未安装 ScopeTree，继续保留原来的完整候选名单。
    errorPath specification
      | isWorkflow = nub (nearestScopeNames [] (name specification))
      | otherwise = nub (scopeNames [] (name specification))
    -- scope 与回调装配仍收齐全量前提，不依赖上面的最近种子集合。
    orderedScopes = nub (concatMap (scopeNames [] . name) specifications)
    nearestScopeNames seen selectedName
      | selectedName `elem` seen = []
      | otherwise = concat
          [ case typing specification of
              Scoped _ _ -> [selectedName]
              _ -> concatMap (nearestScopeNames (selectedName : seen)) (operationInputs specification)
          | specification <- specifications, name specification == selectedName ]
    scopeNames seen selectedName
      | selectedName `elem` seen = []
      | otherwise = concat
          [ concatMap (scopeNames (selectedName : seen)) (operationInputs specification)
            ++ (case typing specification of Scoped _ _ -> [selectedName]; _ -> [])
          | specification <- specifications, name specification == selectedName ]

    -- Input/request 保留现有保守前提；require 不启动来源，但可导航到该
    -- Context 的声明资源 owner。关闭自己资源的 require 不引入自依赖，
    -- 也不把同一资源声明的其他 scope 误当自己的关闭 owner。
    scopeRegistrationParents specification = filter (/= name specification) $ nub
      (upstreamScopes specification ++
        [name owner
        | source <- requiredSources [] (name specification)
        , source `notElem` requestProviders specification
        , owner <- specifications
        , Scoped (Just _) _ <- [typing owner]
        , requestSource owner == Just source])
    requiredSources seen selectedName
      | selectedName `elem` seen = []
      | otherwise = nub $ concat
          [ let required = requireProviders specification
            in required ++ concatMap (requiredSources (selectedName : seen))
              (operationInputs specification ++ required)
          | specification <- specifications, name specification == selectedName ]

    -- scope.request 指向资源生产者；它声明消费的 Context 值构成开启输入。
    -- 这里只生成观察协议，不调用生产者，不读取用户方法体。
    openingInputs specification = nub (concatMap (valueInputs []) (maybeToList (requestSource specification)))
    valueInputs seen selectedName
      | selectedName `elem` seen = []
      | otherwise = concat
          [ let requested = requestProviders producer
                required = requireProviders producer
            -- require 只观察缓存值，不要求重现其生产时的输入；request 才继续生产链。
            in requested ++ required ++ concatMap (valueInputs (selectedName : seen)) requested
          | producer <- specifications, name producer == selectedName ]
    comparedInputs = nub (concatMap openingInputs
      [specification | specification <- specifications, effectKind (typing specification) == ScopedKind])
    observation prefix selectedName
      | selectedName `elem` comparedInputs = "(Just (" ++ prefix ++ "ScopeInput " ++ show selectedName ++ "))"
      | otherwise = "Nothing"

    findEffect effectName = case filter ((== effectName) . name) specifications of
      [specification] -> Right specification
      [] -> Left ("Unknown effect: " ++ effectName)
      _ -> Left ("Duplicate effect: " ++ effectName)

    -- target 和 request 均只引用 effect，从 typing 取得普通入口。
    -- Nothing 可保留为声明，但不能被选择为可执行入口。
    findHandler effectName = do
      specification <- findEffect effectName
      case typing specification of
        Error {} -> Left ("Error methods are activated by the Root failure protocol, not a Node target: " ++ effectName)
        _ -> case entryMethod (typing specification) of
          Just method -> Right method
          Nothing -> Left ("Effect has no callable entry (handler/open/Context.request = Nothing): " ++ effectName)

    -- 此限制只针对手写 Input。生成的 superclass 仍包含声明的 Context 能力。
    checkInput specification
      | input specification == "Root" = Right ()
      | otherwise = do
          predecessor <- findEffect (input specification)
          case typing predecessor of
            Context _ _ -> Left ("Input cannot reference Context " ++ name predecessor
              ++ " in " ++ name specification ++ "; declare context.request or context.require instead")
            _ -> Right ()

    -- 消费方以契约名引用；handler 中写作 request @契约名 / require @契约名。
    checkDemandNames specification = do
      mapM_ (\demand -> if validTypeName (contract demand) then Right ()
          else Left ("Demanded contract must be a contract name such as \"StartURL\": "
            ++ contract demand ++ " in " ++ name specification)) (demands specification)
      case typing specification of
        Scoped _ _ | length (requestProviders specification) > 1 ->
          Left ("Scoped requests at most one resource Context: " ++ name specification)
        _ -> pure ()

    -- 契约名由 handler 名推导：须是合法类型名，不与生成区固定名或 effect 派生名冲突；
    -- handler 名因此同时决定资产名，应按业务含义起名（例如 startURL，而不是 loadStartURL）。
    -- 与 Types.hs 中的类型重名会在 GHC 名称解析时报歧义。表示类型须是普通业务或库类型。
    checkGenerated = do
      let declared = [contractType | (contractType, _, _) <- generatedDeclarations]
          reserved = ["Root", "App", "Pure", "Provides", "ContextValues", "Errors", "MethodGen", "Results"]
            ++ concat [[name s, name s ++ "Effect", name s ++ "Error", name s ++ "Failure"] | s <- specifications]
      case [contractType | contractType <- nub declared, length (filter (== contractType) declared) > 1] of
        contractType : _ -> Left ("Contract " ++ contractType ++ " comes from more than one handler; rename one of them")
        [] -> pure ()
      mapM_ (\(contractType, representation', owner) -> do
          if not (validTypeName contractType)
            then Left ("Handler name must start with a letter to name contract " ++ contractType ++ " in " ++ owner) else pure ()
          if contractType `elem` reserved
            then Left ("Contract " ++ contractType ++ " (from the handler of " ++ owner
              ++ ") collides with a generated or effect name; rename the handler") else pure ()
          case representation' of
            TypeRef _ -> pure ()
            _ -> Left ("Context.request must wrap a business value, not Output: " ++ owner))
        generatedDeclarations

    validTypeName selected = case selected of
      first : rest -> isUpper first && all (\character -> isAlphaNum character || character `elem` "_'") rest
      [] -> False

    -- Error 按 handles 匹配故障；关联 scope 沿 Input/request 推导，至多一个。
    checkError specification = case typing specification of
      Error { handles = matched } -> do
        if null matched
          then Left ("Error must declare the failures it handles: " ++ name specification) else pure ()
        mapM_ checkHandled matched
        case errorScopes specification of
          (_ : _ : _) -> Left ("Error capability reaches several nearest scopes; narrow its input: " ++ name specification)
          _ -> pure ()
      _ -> pure ()
      where
        checkHandled (RaisedBy selected) = findEffect selected >> pure ()
        checkHandled (ScopeFaultIn selected) = findEffect selected >>= \target -> case typing target of
          Scoped _ _ -> pure ()
          _ -> Left ("ScopeFaultIn must name a Scoped effect: " ++ selected)
        checkHandled (ContextFaultIn selected) = findEffect selected >>= \target -> case typing target of
          Context _ _ -> pure ()
          _ -> Left ("ContextFaultIn must name a Context effect: " ++ selected)

    errorScopes specification = nub (concatMap (nearestScopeNames [name specification]) (operationInputs specification))

    -- 同一 scope（或同为全局）下，同一故障类型只能有一个处置，避免多个 resolve 互相冲突。
    checkErrorOverlap =
      case [ (name left, name right)
           | (index, left) <- zip [0 :: Int ..] errorSpecs, right <- drop (index + 1) errorSpecs
           , errorScopes left == errorScopes right
           , not (null (handledBy left `intersect` handledBy right)) ] of
        [] -> Right ()
        (left, right) : _ -> Left ("Error policies " ++ left ++ " and " ++ right ++ " handle the same failure for the same scope")
      where
        errorSpecs = [specification | specification <- specifications, effectKind (typing specification) == ErrorKind]

    handledBy specification = case typing specification of
      Error { handles = matched } -> matched
      _ -> []

    -- 被 Input 后端复用的 scope 仍须提供完整开启／关闭协议。
    checkScope effectName = do
      specification <- findEffect effectName
      case typing specification of
        Scoped (Just _) (Just _) -> Right ()
        _ -> Left ("Input scope needs Scoped.open and Scoped.close: " ++ effectName)

    -- 业务产物只归 Context；Output 仍只在运行边界统一包装。
    valueContract specification = case typing specification of
      Context (Just producing) _ -> Right (TypeRef (contractOf producing))
      Context Nothing (Just _) ->
        Left ("Context.require needs a Context.request product contract: " ++ name specification)
      _ -> Right (TypeRef "()")

    declaration specification = do
      valueType <- valueContract specification
      _ <- contextNames specifications [name specification]
      mapM_ checkScope (upstreamScopes specification)
      case typing specification of
        Scoped (Just _) Nothing ->
          Left ("Scoped.open needs Scoped.close for automatic cleanup: " ++ name specification)
        _ -> pure ()
      let effectName = name specification
          typeName = "'SDK." ++ show (effectKind (typing specification))
          upstream = input specification
          -- 依值只经 Provides 契约进入 superclass；来源由解析结果在 Provides instance 中连接。
          superclasses = nub (("Effect " ++ upstream ++ " m") :
            ["Provides " ++ contract demand ++ " m" | demand <- demands specification])
          ordinaryMethods =
            [ (method, case effectKind (typing specification) of
                PureKind -> "m ()"
                ExcuKind -> "m ()"
                ScopedKind -> "m ()"
                ErrorKind -> "m ()"
                _ -> "m (Produce " ++ effectName ++ ")")
            | method <- maybeToList (entryMethod (typing specification)) ]
          -- open／close 不产值；资源信息来自显式声明的上游 Context。
          closingMethods = case typing specification of
            Scoped _ closing -> [(method, "m ()") | method <- maybeToList closing]
            _ -> []
          methods = ordinaryMethods ++ closingMethods
            ++ [(method, "m ()") | method <- errorMethods specification]
          methodLines = ["  " ++ method ++ " :: " ++ signature | (method, signature) <- methods]
          readingLines = case typing specification of
            Context _ (Just method) ->
              [ "  " ++ method ++ " :: m (Produce " ++ effectName ++ ")"
              , "  " ++ method ++ " = (FrameworkRoot.withErrorPath " ++ show (errorPath specification)
                ++ " . FrameworkRoot.handler @Root) $"
              , "    SDK.readContext " ++ show effectName
                ++ " ContextBindingError " ++ contextAccessTable "SDK." effectName
                ++ " " ++ observation "SDK." effectName ++ " bound" ++ effectName
              ]
            _ -> []
          minimalLines = case methods of
            [] -> []
            _ -> ["  {-# MINIMAL " ++ intercalate ", " (map fst methods) ++ " #-}"]
          -- 消费契约按 demands 的声明顺序组成；多个输入排为元组。
          -- 原生 <- 在方法体内取得声明的输入；不向业务方法增加位置参数。
          requireType = case nub (map contract (demands specification)) of
            [] -> "SDK.Void"
            [contract] -> contract
            contracts -> "(" ++ intercalate ", " contracts ++ ")"
          produceLines = case typing specification of
            Context (Just _) _ -> ["  type Produce " ++ effectName ++ " = " ++ reference valueType]
            _ -> []
      pure ([ "data " ++ effectName
         , ""
         , "class (" ++ intercalate ", " superclasses ++ ") => " ++ effectName ++ "Effect m where"
         ]
         ++ methodLines ++ readingLines ++ minimalLines
         ++ [ ""
            , "instance (Monad m, Effect " ++ upstream ++ " m, " ++ effectName
              ++ "Effect m) => Effect " ++ effectName ++ " m where"
            , "  type Registration " ++ effectName ++ " = Registered "
              ++ effectName ++ "Effect " ++ upstream
            , "  type Typing " ++ effectName ++ " = " ++ typeName
            , "  type Require " ++ effectName ++ " = " ++ requireType
            ] ++ produceLines ++
            [ "  type Error " ++ effectName ++ " = " ++ effectName ++ "Error"
            , "  raise (" ++ effectName ++ "Error description) = SDK.failEffect " ++ show effectName
              ++ " " ++ effectName ++ "Failure description"
            , "  handler = FrameworkRoot.handler @Root"
            , ""
            ])

    errorDeclaration = concat
      [ [ "-- SDK 生成的本地错误只接收消息；类型唯一确定 raise 来源。"
        , "newtype " ++ name s ++ "Error = " ++ name s ++ "Error String"
        , "  deriving (Eq, Show, Read)"
        , ""
        ] | s <- specifications ] ++
      [ "-- 统一失败协议的分类标签；消息与来源由 SDK.Failure 保存。"
      , "data Errors = " ++ intercalate " | "
          ([name s ++ "Failure" | s <- specifications]
           ++ ["ContextBindingError SDK.ContextFault", "ScopeBindingError SDK.ScopeFault"])
      , "  deriving (Eq, Show)"
      , ""
      ]

    contextDeclarations =
      [ "-- SDK 内部存储：Nothing 仅表示本次运行尚未建立绑定，不是业务缺值。"
      , "data ContextValues = ContextValues"
      ] ++ (case ["bound" ++ name s ++ " :: Maybe (Produce " ++ name s ++ ")"
                  | s <- contextSpecs] of
        [] -> [""]
        fields -> ["  { " ++ intercalate "\n  , " fields, "  }", ""])
      ++ [ "emptyContexts :: ContextValues"
         , "emptyContexts = ContextValues" ++ concat [" Nothing" | _ <- contextSpecs]
         , ""
         ]

    reference (TypeRef typeName) = typeName
    reference (OutputRef cause value) =
      "SDK.Output (" ++ reference cause ++ ") (" ++ reference value ++ ")"

    -- 控制对象由生成的 handler 模块创建；不同链引用同份对象，不预执行 open。
    scopeHandlers
      | not isWorkflow = ""
      | otherwise = unlines
          [ "-- SDK 内部：scope 按上游到下游登记，退出时逆序收尾；创建不执行业务方法。"
          , "newScopeHandlers :: IO [FrameworkRuntime.ScopeHandler FrameworkGenerated.ContextValues FrameworkGenerated.Errors]"
          , "newScopeHandlers = sequence"
          , "  [ " ++ intercalate "\n  , "
              ["FrameworkRuntime.newScopeHandler " ++ show (name specification) ++ " " ++ show (openingInputs specification)
                ++ " (" ++ show (requestSource specification) ++ ")"
              | selectedScope <- orderedScopes
              , specification <- specifications, name specification == selectedScope]
          , "  ]"
          ]

    -- 只登记已有 close 方法；本轮资源绑定由运行载体在 open 时捕获。
    scopeCleanups
      | not isWorkflow = ""
      | otherwise = unlines
          [ ""
          , "-- SDK 自动收尾入口；安装时不关闭资源。"
          , "scopeCleanups :: [(String, FrameworkGenerated.App ())]"
          , "scopeCleanups ="
          , "  [" ++ if null callbacks then "" else " " ++ intercalate "\n  , " callbacks
          , "  ]"
          ]
      where
        callbacks =
          [ "(" ++ show selectedScope ++ ", " ++ closing ++ ")"
          | selectedScope <- orderedScopes
          , specification <- specifications, name specification == selectedScope
          , Scoped _ (Just closing) <- [typing specification] ]

    -- 只保存匹配函数与类方法引用；安装时不检测、不处置，也不执行上游业务。
    errorHandlers = unlines
      [ ""
      , "-- Error 回调登记：按 handles 匹配故障来源与分类；关联 scope 由 Input 链推导。"
      , "errorHandlers :: [(Maybe String, FrameworkRoot.ErrorHandler FrameworkGenerated.Errors FrameworkGenerated." ++ carrier ++ ")]"
      , "errorHandlers ="
      , "  [" ++ if null callbacks then "" else " " ++ intercalate "\n  , " callbacks
      , "  ]"
      ]
      where
        carrier = if isWorkflow then "App" else "Pure"
        callbacks =
          [ "(" ++ show (listToMaybe (errorScopes specification)) ++ ", FrameworkRoot.ErrorHandler " ++ show (name specification)
              ++ "\n      (\\failure -> case (FrameworkRoot.origin failure, FrameworkRoot.detail failure) of"
              ++ concatMap (("\n        " ++) . matchCase) (nub matched)
              ++ "\n        _ -> False)"
              ++ "\n      (" ++ methodReference detecting ++ ") (" ++ methodReference resolving ++ "))"
          | specification <- specifications
          , Error { detect = detecting, resolve = resolving, handles = matched } <- [typing specification] ]
        matchCase (RaisedBy selected) = "(_, FrameworkGenerated." ++ selected ++ "Failure) -> True"
        matchCase (ScopeFaultIn selected) = "(" ++ show selected ++ ", FrameworkGenerated.ScopeBindingError _) -> True"
        matchCase (ContextFaultIn selected) = "(" ++ show selected ++ ", FrameworkGenerated.ContextBindingError _) -> True"
        methodReference Nothing = "Nothing"
        methodReference (Just method) = "Just " ++ method

    astInterpreter methods
      | not isWorkflow = []
      | otherwise =
          [ ""
          , "-- 仅汇总所选末端的成功产物，不保存共享绑定或增加完成包装。"
          , "data Results = " ++ intercalate " | "
              [terminal ++ "Result (Produce " ++ terminal ++ ")" | terminal <- selected]
          , "  deriving Show"
          , ""
          , "-- 末端共享生成的 scope 句柄；只创建空状态，Node algebra 才 lower，业务调用仍在 instance 内。"
          , "compiledEntries :: IO [SDK.Target IO ContextValues Errors Results]"
          , "compiledEntries = do"
          , "  scopes <- Handlers.newScopeHandlers"
          , "  pure"
          , "    [ " ++ intercalate "\n    , "
              ["SDK.targetApp " ++ show terminal ++ " emptyContexts scopes"
                ++ " (FrameworkRoot.withErrorHandlers Handlers.errorHandlers"
                ++ " (SDK.withScopeCleanups Handlers.scopeCleanups (" ++ terminal ++ "Result <$> " ++ method ++ ")))"
              | (terminal, method) <- zip selected methods]
          , "    ]"
          , ""
          , "-- SDK 装配入口，不需要用户提供节点执行器或重复选择 handler。"
          , "interpreter :: SDK.AST -> [EffectSpec] -> IO ()"
          , "interpreter = SDK.interpreter " ++ show namespace ++ " registeredEffects Handlers.handlerSourceFingerprint programStructure compiledEntries"
          ]

    -- workflow 与纯 target 共用同一注册快照核对规则。
    registrationSnapshot =
      [ "-- 编译时注册快照；运行前核对声明，改变连接后须重新生成。"
      , "registeredEffects :: [EffectSpec]"
      , "registeredEffects ="
      , "  [ " ++ intercalate "\n  , " (map show specifications)
      , "  ]"
      , ""
      ]

