{-# LANGUAGE DuplicateRecordFields #-}

-- 将注册和选定末端 lower 为普通 Haskell 源码；不执行业务。
module Framework.Codegen (lowerProgram) where

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
-- 程序只经 AST 启动：入口是 AST 中各 node 选中的末端 effect。

-- 结构分析使用的取值路由：消费方类 → ((request|require, 契约名), 来源方法)；
-- 以及 Context 的生产／读取方法，供拒绝跨 effect 直接调用。
type DemandRoutes = ([(String, [((String, String), String)])], [(String, String)])

-- Types.hs 中的和类型：类型名 → [(构造器名, 唯一字段的类型原文)]；由 SDK 解析 Types.hs 得到。
type SumTypes = [(String, [(String, Maybe String)])]

-- terminals：AST 选中的全部末端；groups：每个 alternative 的候选及各自的末端。
lowerProgram :: String -> [EffectSpec] -> [String] -> [[[String]]] -> SumTypes
             -> Either String (String, String, [(String, String, String, String)], String, GraphPlan String, [String], DemandRoutes, [(String, String, Bool)])
lowerProgram namespace specifications terminals groups sumTypes = do
  if any ((== "Root") . name) specifications
    then Left "Root is reserved for the superclass"
    else pure ()
  mapM_ checkInput specifications
  mapM_ checkAnchor specifications
  _ <- resolvedEither
  mapM_ checkDemandNames specifications
  checkGenerated
  mapM_ checkError specifications
  checkErrorOverlap
  mapM_ (contextNames branchTable specifications . pure . name) specifications
  if null selected
    then Left "Select at least one terminal effect for generation"
    else pure ()
  selectedMethods <- mapM findHandler selected
  mapM_ checkTerminal selected
  alternativeCases <- concat <$> mapM checkAlternative groups
  let allMethods = concatMap registeredMethods specifications
  if length allMethods /= length (nub (map snd allMethods))
    then Left "Registered method names must be unique within a generated module"
    else pure ()
  declarations <- mapM declaration specifications
  pure
    ( unlines (contractHeader ++ runtimeAliases ++ generatedContracts ++ methodIdentities ++ concat declarations
        ++ providerDeclarations ++ errorDeclaration ++ contextDeclarations)
    , unlines (programHeader ++ registrationSnapshot ++ structureDeclarations ++ astInterpreter selectedMethods alternativeCases)
    , concatMap instanceWrappers specifications
    , scopeHandlers ++ scopeCleanups ++ errorHandlers ++ injectionTable
    , graphPlan
    , nub [reference representation' | (_, representation', _) <- generatedDeclarations]
    , (demandRoutes, contextMethods)
    , contractOwners
    )
  where
    resolvedEither = mapM (\specification -> (,) (name specification) <$> resolveDemands branchTable specifications specification) specifications
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
              , Context (Just Requester { handler = method }) <- [typing specification]]
    readerMethod providerName = listToMaybe
      [method | specification <- specifications, name specification == providerName
              , Just method <- [contextReader (typing specification)]]
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
      , Context (Just producing) <- [typing specification] ]
    -- 表示类型是和类型（至少两个构造器）时，每个构造器另有分支契约：契约名加构造器名。
    -- 分支契约是基础契约的投影，由基础契约的生产方提供，只能 require：
    -- (分支契约, (基础契约, 构造器, 字段类型, 生产方))。
    branchContracts =
      [ (base ++ constructor, (base, constructor, field, owner))
      | (base, TypeRef typeName, owner) <- generatedDeclarations
      , Just constructors <- [lookup typeName sumTypes], length constructors > 1
      , (constructor, field) <- constructors ]
    branchTable = [(branch, base) | (branch, (base, _, _, _)) <- branchContracts]
    -- 构造器归属：契约类型只能由其生产方的 instance 方法构造；契约均由生成器产出。
    -- 分支契约由生成的投影构造，归属其基础契约的生产方，消费方只能模式匹配。
    contractOwners =
      [ (contractType, owner ++ "Effect", True)
      | (contractType, _, owner) <- generatedDeclarations, validTypeName contractType ]
      ++ [ (branch, owner ++ "Effect", True) | (branch, (_, _, _, owner)) <- branchContracts ]

    -- alternative 的每个候选经注册依赖同一和类型资产的一个分支契约，以此对应一个构造器：
    -- 候选末端自身及其 Input 链上游声明的 requires 分支契约。候选须覆盖该和类型的全部构造器。
    -- 结果为静态表：候选末端 → (转折契约, 构造器)；运行时只据此在已装配的闭包间选择。
    terminalCases terminal = nub
      [ (base, constructor)
      | effectName <- terminal : inputChain [] (inputOf terminal)
      , specification <- specifications, name specification == effectName
      , demand <- demands specification
      , Just (base, constructor, _, _) <- [lookup (contract demand) branchContracts] ]
    inputOf terminal = case [input specification | specification <- specifications, name specification == terminal] of
      upstream : _ -> upstream
      [] -> "Root"
    checkAlternative candidates = do
      cases <- mapM candidateCase candidates
      selectorContract <- case nub (map fst cases) of
        [contractType] -> Right contractType
        found -> Left ("Alternative candidates must branch on one sum-type contract, found: " ++ show found)
      let constructors = map snd cases
          declared = [constructor | (_, (base, constructor, _, _)) <- branchContracts, base == selectorContract]
      if length constructors /= length (nub constructors)
        then Left ("Alternative candidates repeat a case of " ++ selectorContract ++ ": " ++ show constructors)
        else pure ()
      case filter (`notElem` constructors) declared of
        [] -> pure ()
        missing -> Left ("Alternative over " ++ selectorContract ++ " has no candidate for " ++ intercalate ", " missing)
      pure [ (terminal, (selectorContract, constructor))
           | (candidate, (_, constructor)) <- zip candidates cases, terminal <- candidate ]
    candidateCase candidate = case nub (map terminalCases candidate) of
      [[found]] -> Right found
      [[]] -> Left ("Alternative candidate " ++ intercalate ", " candidate
        ++ " requires no branch contract; require one such as <Contract><Constructor>")
      [_] -> Left ("Alternative candidate " ++ intercalate ", " candidate ++ " requires several branch contracts")
      _ -> Left ("Terminals in alternative candidate " ++ intercalate ", " candidate ++ " require different branch contracts")
    contextMethods =
      [ (name specification ++ "Effect", method)
      | specification <- contextSpecs
      , method <- maybeToList (entryMethod (typing specification))
          ++ maybeToList (contextReader (typing specification)) ]

    -- 原子句柄：Excu.handler 与 Scoped.open／close，统一输出 RawOutput（SDK 内部）。
    -- input 指向原子 effect 的 Context 挂在它下面，解析其入口方法（handler／open）的输出；
    -- close 没有挂接点，输出总被丢弃。
    atomicMethods specification = case typing specification of
      Excu method -> maybeToList method
      Scoped opening closing -> maybeToList opening ++ maybeToList closing
      _ -> []
    anchoredUnder specification =
      [context | context <- contextSpecs, input context == name specification, not (null (atomicMethods specification))]
    contextInjections =
      [ (entry, anchored)
      | specification <- specifications
      , Just entry <- [entryMethod (typing specification)], entry `elem` atomicMethods specification
      , let anchored = [ (name context, producing) | context <- anchoredUnder specification
                       , Just producing <- [entryMethod (typing context)] ]
      , not (null anchored) ]
    terminalAction terminal method
      | any (\specification -> name specification == terminal && effectKind (typing specification) == ContextKind) specifications = method
      | otherwise = "(() <$ " ++ method ++ ")"

    selected = nub terminals
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
      , "import Control.Monad.IO.Class (MonadIO)"
      , "import " ++ namespace ++ ".Types"
      , ""
      ]

    -- App 载体提供 IO；各类别是否收紧 IO 待 Pure 类别的语义确定后再定。
    carrierCapabilities = ["MonadIO m"]

    -- Input 链上的全部上游 effect（不含 Root），由近到远。
    inputChain seen selectedName
      | selectedName == "Root" || selectedName `elem` seen = []
      | otherwise = selectedName : concat
          [inputChain (selectedName : seen) (input specification) | specification <- specifications, name specification == selectedName]

    -- 身份是生成的封闭 ADT；手写调用仍引用原生类方法。
    registeredMethods specification =
      [(specification, method) | method <- maybeToList (entryMethod (typing specification))
        ++ (case typing specification of Scoped _ closing -> maybeToList closing; _ -> [])
        ++ errorMethods specification
        ++ maybeToList (contextReader (typing specification))]
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
      Context producing -> if fmap (\Requester { handler = selectedMethod } -> selectedMethod) producing == Just method
        then Graph.ContextRequest else Graph.ContextRequire
      Error { detect = detecting } -> if Just method == detecting then Graph.ErrorDetect else Graph.ErrorResolve
      _ -> Graph.HandlerMethod
    -- require 的默认读取在 state 无值时会求值同一个 request，因此结构上可能进入生产链；
    -- scope 资源只经 open 取得，不按需求值，其读取保持为空。
    resourceContexts = nub [provider | specification <- specifications
      , Scoped _ _ <- [typing specification], Just provider <- [requestSource specification]]
    planBody specification method
      | Just method == contextReader (typing specification)
      , name specification `notElem` resourceContexts
      , Just producing <- entryMethod (typing specification) = Graph.Choice [Graph.Empty, Graph.Call producing]
      | otherwise = Graph.Empty
    graphPlan = GraphPlan
      { planDefinitions =
          [ Graph.MethodDefinition method firstMethod (methodRole specification method) (planBody specification method)
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
      , planAnchors = [(entry, producing) | (entry, anchored) <- contextInjections, (_, producing) <- anchored]
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
      , "import Framework.SDK (Effect(..), EffectSpec(..), EffectTyping(..), Requester(..), Handles(..), Demand(..), Access(..), TypeRef(..))"
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
        ] ++ (case lookup contractType branchContracts of
          -- 分支契约：读取基础契约，资产当前是该构造器时取出字段。
          Just (base, constructor, field, _) ->
            [ "  require = SDK.projectContext " ++ show contractType ++ " ContextBindingError " ++ routeList RequireAccess
            , "    (\\(" ++ base ++ " value) -> case value of"
            , "      " ++ constructor ++ (if field == Nothing then " -> Just (" ++ contractType ++ " ())"
                                              else " field -> Just (" ++ contractType ++ " field)")
            , "      _ -> Nothing)" ]
          Nothing ->
            [ "  require = SDK.provideContext " ++ show contractType ++ " ContextBindingError " ++ routeList RequireAccess ])
        ++ [ "" ]
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

    carrierType = "App"

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
        ++ concat
          [ [ "-- " ++ base ++ " 的分支契约：资产当前是 " ++ constructor ++ " 时可经 require 取得。"
            , "newtype " ++ branch ++ " = " ++ branch ++ " (" ++ payload ++ ")"
            , "deriving instance Eq (" ++ payload ++ ") => Eq " ++ branch
            , "deriving instance Show (" ++ payload ++ ") => Show " ++ branch
            , "" ]
          | (branch, (base, constructor, field, _)) <- branchContracts
          , let payload = maybe "()" id field ]

    runtimeAliases =
      [ "-- SDK 提供运行载体与空存储；Context 经声明的 request/require 取得。"
      , "type Root = SDK.Root ContextValues Errors"
      , "type App = SDK.App ContextValues Errors"
      , ""
      ]

    -- 注册时连接生产/读取入口；业务方法使用原生 Haskell 取值，不改写表达式。
    -- 第四项是方法结果类型，供生成副本给保留原文的局部绑定写出完整签名。
    instanceWrappers specification =
      [ (name specification ++ "Effect", method, wrapper method, resultType)
      | method <- maybeToList (entryMethod (typing specification)) ++ closing
          ++ errorMethods specification ++ maybeToList reading ]
      where
        selectedName = name specification
        resultType = case typing specification of
          Context (Just producing) -> "FrameworkGenerated." ++ contractOf producing
          Excu _ -> "Maybe String"
          Scoped _ _ -> "Maybe String"
          _ -> "()"
        closing = case typing specification of
          Scoped _ method -> maybeToList method
          _ -> []
        reading = contextReader (typing specification)
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
              -- 原子句柄的输出只交给挂在它下面的 Context，组合它的方法照常继续。
              Scoped _ closingMethod ->
                "FrameworkRuntime.atomicScope " ++ show method ++ " . FrameworkRuntime."
                  ++ (if Just method == closingMethod then "closeScope " else "openScope ")
                  ++ show selectedName ++ " FrameworkGenerated.ScopeBindingError . "
                  ++ scopedDependencies ++ " . FrameworkRuntime.enterHandler " ++ show selectedName
              Excu _ -> "FrameworkRuntime.atomicHandle " ++ show method ++ " . "
                  ++ scopedDependencies ++ " . " ++ operation
              _ -> scopedDependencies ++ " . " ++ operation) ++ ")"
        operation = case typing specification of
          Context (Just _) ->
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
    -- withErrorPath 只接收关联种子；祖先和 top-down 顺序由同一 ScopeTree 决定。
    errorPath specification = nub (nearestScopeNames [] (name specification))
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

    -- AST 末端和 request 均只引用 effect，从 typing 取得普通入口。
    -- Nothing 可保留为声明，但不能被选择为可执行入口。
    findHandler effectName = do
      specification <- findEffect effectName
      case typing specification of
        Error {} -> Left ("Error methods are activated by the Root failure protocol, not a Node target: " ++ effectName)
        _ -> case entryMethod (typing specification) of
          Just method -> Right method
          Nothing -> Left ("Effect has no callable entry (handler/open/Context.request = Nothing): " ++ effectName)

    -- 启动只从 origin 链开始：末端须是原始句柄；Context 由挂接句柄注入或 request／require 驱动。
    checkTerminal terminal = do
      specification <- findEffect terminal
      case typing specification of
        Context _ -> Left ("A terminal must be an original handle, not Context " ++ terminal
          ++ "; a Context is produced below the handle it hangs on or through request/require")
        _ -> Right ()

    -- 挂在 Scoped 下的 Context 解析 open 的输出，不能同时是该 scope 经 request 取得的资源 Context。
    checkAnchor specification = case typing specification of
      Context _ | Right anchor <- findEffect (input specification)
                , Scoped _ _ <- typing anchor
                , requestSource anchor == Just (name specification) ->
          Left ("Context " ++ name specification ++ " is the resource of " ++ name anchor
            ++ " and cannot also hang below it; give it another input")
      _ -> Right ()

    -- 此限制只针对手写 Input。生成的 superclass 仍包含声明的 Context 能力。
    checkInput specification
      | input specification == "Root" = Right ()
      | otherwise = do
          predecessor <- findEffect (input specification)
          case typing predecessor of
            Context _ -> Left ("Input cannot reference Context " ++ name predecessor
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
      -- 分支契约是基础资产的投影，不单独生产，只能 require。
      case [contract demand | demand <- demands specification, access demand == RequestAccess
           , Just _ <- [lookup (contract demand) branchContracts]] of
        branch : _ -> Left ("Branch contract " ++ branch ++ " can only be required, not requested, in " ++ name specification)
        [] -> pure ()

    -- 契约名由 handler 名推导：须是合法类型名，不与生成区固定名或 effect 派生名冲突；
    -- handler 名因此同时决定资产名，应按业务含义起名（例如 startURL，而不是 loadStartURL）。
    -- 与 Types.hs 中的类型重名会在 GHC 名称解析时报歧义。表示类型须是普通业务或库类型。
    checkGenerated = do
      let declared = [contractType | (contractType, _, _) <- generatedDeclarations] ++ map fst branchContracts
          reserved = ["Root", "App", "Pure", "Provides", "ContextValues", "Errors", "MethodGen", "Results"]
            ++ concat [[name s, name s ++ "Effect", name s ++ "Inputs", name s ++ "Error", name s ++ "Failure"] | s <- specifications]
      case [contractType | contractType <- nub declared, length (filter (== contractType) declared) > 1] of
        contractType : _ -> Left ("Contract " ++ contractType ++ " comes from more than one handler or branch; rename one of them")
        [] -> pure ()
      case [branch | (branch, _) <- branchContracts, branch `elem` reserved] of
        branch : _ -> Left ("Branch contract " ++ branch ++ " collides with a generated or effect name; rename the handler or constructor")
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
          Context _ -> pure ()
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
      Context (Just producing) -> Right (TypeRef (contractOf producing))
      Context Nothing ->
        Left ("Context needs request = requester \"handler\" @Representation: " ++ name specification)
      _ -> Right (TypeRef "()")

    declaration specification = do
      valueType <- valueContract specification
      _ <- contextNames branchTable specifications [name specification]
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
          -- 原子句柄（Excu、Scoped.open／close）返回可选的信息；业务值只归 Context。
          -- 这份输出只交给挂在它下面的 Context，资源信息仍来自显式声明的上游 Context。
          ordinaryMethods =
            [ (method, case effectKind (typing specification) of
                PureKind -> "m ()"
                ExcuKind -> "m (Maybe String)"
                ScopedKind -> "m (Maybe String)"
                ErrorKind -> "m ()"
                _ -> "m (Produce " ++ effectName ++ ")")
            | method <- maybeToList (entryMethod (typing specification)) ]
          closingMethods = case typing specification of
            Scoped _ closing -> [(method, "m (Maybe String)") | method <- maybeToList closing]
            _ -> []
          methods = ordinaryMethods ++ closingMethods
            ++ [(method, "m ()") | method <- errorMethods specification]
          methodLines = ["  " ++ method ++ " :: " ++ signature | (method, signature) <- methods]
          readingLines = case contextReader (typing specification) of
            Just method ->
              [ "  " ++ method ++ " :: m (Produce " ++ effectName ++ ")"
              , "  " ++ method ++ " = (FrameworkRoot.withErrorPath " ++ show (errorPath specification)
                ++ " . FrameworkRoot.handler @Root) $"
              , "    SDK.readContext " ++ show effectName
                ++ " ContextBindingError " ++ contextAccessTable "SDK." effectName
                ++ " " ++ observation "SDK." effectName ++ " bound" ++ effectName
                ++ " " ++ fromMaybe "" (entryMethod (typing specification))
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
            Context (Just _) -> ["  type Produce " ++ effectName ++ " = " ++ reference valueType]
            _ -> []
      pure ([ "data " ++ effectName
         , ""
         -- instance 对 m 泛型时只能使用这里给出的能力：自身能力标记、Input 链、demands 与载体能力。
         -- 标记只在本程序载体上成立，方法体不能凭泛型 instance 构造 Input 链以外的句柄。
         -- Input 链上游的类直接列出：经 Effect 的类型族 superclass 展开不足以让 GHC 取到上游句柄。
         , "type " ++ effectName ++ "Inputs m = (" ++ intercalate ", "
             (("FrameworkRoot.Capability " ++ effectName ++ " m") : superclasses
               ++ [upstreamEffect ++ "Effect m" | upstreamEffect <- inputChain [] upstream]
               ++ carrierCapabilities) ++ ")"
         , "instance FrameworkRoot.Capability " ++ effectName ++ " " ++ carrierType
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
    scopeHandlers = unlines
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
    scopeCleanups = unlines
          [ ""
          , "-- SDK 自动收尾入口；安装时不关闭资源。"
          , "scopeCleanups :: [(String, FrameworkGenerated.App ())]"
          , "scopeCleanups ="
          , "  [" ++ if null callbacks then "" else " " ++ intercalate "\n  , " callbacks
          , "  ]"
          ]
      where
        callbacks =
          [ "(" ++ show selectedScope ++ ", () <$ " ++ closing ++ ")"
          | selectedScope <- orderedScopes
          , specification <- specifications, name specification == selectedScope
          , Scoped _ (Just closing) <- [typing specification] ]

    -- 只保存生产入口引用；安装时不注入，原子句柄实际返回后才交给挂接的 Context。
    injectionTable = unlines
      [ ""
      , "-- 挂在原子句柄下的 Context：句柄的输出交给它解析并发布为资产；没有挂接时输出被丢弃。"
      , "contextInjections :: [(String, [(String, FrameworkGenerated." ++ carrierType ++ " ())])]"
      , "contextInjections ="
      , "  [" ++ if null entries then "" else " " ++ intercalate "\n  , " entries
      , "  ]"
      ]
      where
        entries =
          [ "(" ++ show entry ++ ", [" ++ intercalate ", "
              ["(" ++ show contextName ++ ", () <$ " ++ producing ++ ")" | (contextName, producing) <- anchored] ++ "])"
          | (entry, anchored) <- contextInjections ]

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
        carrier = carrierType
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

    astInterpreter methods alternativeCases =
          [ ""
          , "-- 仅汇总所选末端的成功产物，不保存共享绑定或增加完成包装。"
          , "data Results = " ++ intercalate " | "
              [terminal ++ "Result (Produce " ++ terminal ++ ")" | terminal <- selected]
          , "  deriving Show"
          , ""
          , "-- alternative 的候选：末端 → (转折契约, 构造器)。由 gencode 从注册推出；"
          , "-- 运行时只据此在已装配的闭包之间选择，不保存或重组 effect chain。"
          , "alternativeCases :: [(String, (String, String))]"
          , "alternativeCases = " ++ show alternativeCases
          , ""
          , "-- 末端共享生成的 scope 句柄；只创建空状态，Node algebra 才 lower，业务调用仍在 instance 内。"
          , "-- 第二个列表是各转折契约的读取末端：按 require 取得资产，返回它当前的构造器名。"
          , "compiledEntries :: IO ([SDK.Target ContextValues Errors Results], [SDK.Target ContextValues Errors String])"
          , "compiledEntries = do"
          , "  scopes <- Handlers.newScopeHandlers"
          , "  pure"
          , "    ( " ++ renderList "      "
              [ wrapTarget terminal (terminal ++ "Result <$> " ++ terminalAction terminal method)
              | (terminal, method) <- zip selected methods ]
          , "    , " ++ renderList "      "
              [ wrapTarget contractType ("caseOf" ++ contractType ++ " <$> " ++ reader)
              | contractType <- selectorContracts, reader <- readerOf contractType ]
          , "    )"
          , ""
          ] ++ concat
          [ [ "caseOf" ++ contractType ++ " :: " ++ contractType ++ " -> String"
            , "caseOf" ++ contractType ++ " (" ++ contractType ++ " value) = case value of" ]
            ++ [ "  " ++ constructor ++ " {} -> " ++ show constructor
               | (_, (base, constructor, _, _)) <- branchContracts, base == contractType ]
            ++ [ "" ]
          | contractType <- selectorContracts ] ++
          [ "-- SDK 装配入口，不需要用户提供节点执行器或重复选择 handler。"
          , "interpreter :: SDK.AST -> [EffectSpec] -> IO ()"
          , "interpreter = SDK.interpreter " ++ show namespace
              ++ " registeredEffects Handlers.handlerSourceFingerprint programStructure alternativeCases compiledEntries"
          ]
      where
        selectorContracts = nub [contractType | (_, (contractType, _)) <- alternativeCases]
        readerOf contractType =
          [ reader | (declared, _, owner) <- generatedDeclarations, declared == contractType
          , Just reader <- [readerMethod owner] ]
        wrapTarget label action = "SDK.targetApp " ++ show label ++ " emptyContexts scopes"
          ++ " (FrameworkRoot.withErrorHandlers Handlers.errorHandlers"
          ++ " (FrameworkRoot.withAnchoredContexts Handlers.contextInjections"
          ++ " (SDK.withScopeCleanups Handlers.scopeCleanups (" ++ action ++ "))))"
        renderList _ [] = "[]"
        renderList indent items = "[ " ++ intercalate ("\n" ++ indent ++ ", ") items ++ "\n" ++ indent ++ "]"

    registrationSnapshot =
      [ "-- 编译时注册快照；运行前核对声明，改变连接后须重新生成。"
      , "registeredEffects :: [EffectSpec]"
      , "registeredEffects ="
      , "  [ " ++ intercalate "\n  , " (map show specifications)
      , "  ]"
      , ""
      ]

