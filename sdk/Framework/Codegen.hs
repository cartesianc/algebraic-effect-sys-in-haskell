{-# LANGUAGE DuplicateRecordFields #-}

-- 将注册和选定末端 lower 为普通 Haskell 源码；不执行业务。
module Framework.Codegen (lowerProgram) where

import Framework.Effect.Contract (EffectKind(..))
import Framework.Effect.Registration
import qualified Framework.Prototype as Prototype
import Framework.Workflow.AST (WorkflowF)
import Framework.Recursion (Fix)
import qualified Framework.Effect.Graph as Graph
import Data.Char (isAlphaNum, isUpper, toUpper)
import Data.List (intercalate, nub)
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

-- 完整 AST 先交给 Prototype 编号和解析；渲染只读取其中的声明事实。
lowerProgram :: String -> [EffectSpec] -> Fix WorkflowF -> SumTypes
             -> Either String (String, String, [(String, String, String, String)], String, Prototype.PrototypePlan, [String], DemandRoutes, [(String, String, Bool)])
lowerProgram namespace specifications tree sumTypes = do
  plan <- either (Left . show) Right (Prototype.preparePrototype specifications sumTypes tree)
  renderProgram namespace plan sumTypes

-- 接口和运行包装只读取统一原型准备阶段的事实；方法体随后由生成器补入。
renderProgram :: String -> Prototype.PrototypePlan -> SumTypes
              -> Either String (String, String, [(String, String, String, String)], String, Prototype.PrototypePlan, [String], DemandRoutes, [(String, String, Bool)])
renderProgram namespace prepared sumTypes = do
  checkGenerated
  if null selected
    then Left "Select at least one terminal effect for generation"
    else pure ()
  selectedMethods <- mapM findHandler selected
  declarations <- mapM declaration specifications
  pure
    ( unlines (contractHeader ++ runtimeAliases ++ generatedContracts ++ methodIdentities ++ concat declarations
        ++ providerDeclarations ++ errorDeclaration ++ contextDeclarations)
    , unlines (programHeader ++ astInterpreter selectedMethods)
    , concatMap instanceWrappers specifications
    , scopeHandlers ++ scopeCleanups ++ errorHandlers ++ injectionTable
    , prepared
    , nub [reference representation' | (_, representation', _) <- generatedDeclarations]
    , (demandRoutes, contextMethods)
    , contractOwners
    )
  where
    specifications = Prototype.plannedRegistrations prepared
    effectPrototypes = Prototype.plannedEffects prepared
    workflow = Prototype.plannedWorkflow prepared
    protoOf selectedName = case [effect | effect <- effectPrototypes, Prototype.effectName effect == selectedName] of
      effect : _ -> effect
      [] -> error ("Validated prototype has no effect: " ++ selectedName)
    resolvedTable = [(Prototype.effectName effect, Prototype.effectDemands effect) | effect <- effectPrototypes]
    resolvedOf selectedName = fromMaybe [] (lookup selectedName resolvedTable)
    requestProviders specification =
      nub [demandProvider resolved | resolved <- resolvedOf (name specification), demandAccess resolved == RequestAccess]
    requireProviders specification =
      nub [demandProvider resolved | resolved <- resolvedOf (name specification), demandAccess resolved == RequireAccess]
    -- Scoped 至多 request 一个资源 Context；它就是该 scope 的资源来源。
    requestSource = Prototype.effectResource . protoOf . name
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
      , (branch, constructor) <- Prototype.effectBranches (protoOf owner)
      , Just constructors <- [lookup typeName sumTypes]
      , Just field <- [lookup constructor constructors]
      , branch == base ++ constructor ]
    -- 构造器归属：契约类型只能由其生产方的 instance 方法构造；契约均由生成器产出。
    -- 分支契约由生成的投影构造，归属其基础契约的生产方，消费方只能模式匹配。
    contractOwners =
      [ (contractType, owner ++ "Effect", True)
      | (contractType, _, owner) <- generatedDeclarations, validTypeName contractType ]
      ++ [ (branch, owner ++ "Effect", True) | (branch, (_, _, _, owner)) <- branchContracts ]

    -- alternative 的转折与覆盖已由 Prototype 统一解析；这里只渲染选择读取闭包。
    selectorContracts = nub (Prototype.workflowSelectors workflow)
    readerOfContract contractType =
      [ reader | (declared, _, owner) <- generatedDeclarations, declared == contractType
      , Just reader <- [readerMethod owner] ]
    contextMethods =
      [ (name specification ++ "Effect", method)
      | specification <- contextSpecs
      , method <- maybeToList (entryMethod (typing specification))
          ++ maybeToList (contextReader (typing specification)) ]

    -- 原子句柄：Excu.handler 与 Scoped.open／close，统一输出 RawOutput（SDK 内部）。
    -- input 指向原子 effect 的 Context 挂在它下面，解析其入口方法（handler／open）的输出；
    -- close 没有挂接点，输出总被丢弃。
    contextInjections =
      [ (entry, anchored)
      | specification <- specifications
      , Just entry <- [entryMethod (typing specification)]
      , let anchored =
              [ (Prototype.effectName context, producing)
              | context <- effectPrototypes
              , Prototype.effectAnchor context == Just (name specification)
              , (Graph.ContextRequest, producing) <- Prototype.effectMethods context ]
      , not (null anchored) ]
    terminalAction terminal method
      | any (\specification -> name specification == terminal && effectKind (typing specification) == ContextKind) specifications = method
      | otherwise = "(() <$ " ++ method ++ ")"

    selected = nub (Prototype.workflowTerminals workflow)
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

    -- 祖先能力与注册方法均来自同一份原型准备结果。
    registeredMethods specification =
      [(specification, method) | (_, method) <- Prototype.effectMethods (protoOf (name specification))]
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
        , "  request = SDK.provideContext " ++ show producerName ++ " " ++ show contractType ++ " ContextBindingError " ++ routeList RequestAccess
        ] ++ (case lookup contractType branchContracts of
          -- 分支契约：读取基础契约，资产当前是该构造器时取出字段。
          Just (base, constructor, field, _) ->
            [ "  require = SDK.projectContext " ++ show producerName ++ " " ++ show contractType ++ " ContextBindingError " ++ routeList RequireAccess
            , "    (\\(" ++ base ++ " value) -> case value of"
            , "      " ++ constructor ++ (if field == Nothing then " -> Just (" ++ contractType ++ " ())"
                                              else " field -> Just (" ++ contractType ++ " field)")
            , "      _ -> Nothing)" ]
          Nothing ->
            [ "  require = SDK.provideContext " ++ show producerName ++ " " ++ show contractType ++ " ContextBindingError " ++ routeList RequireAccess ])
        ++ [ "" ]
      | demanded <- nub [demandContract resolved | (_, resolvedDemands) <- resolvedTable, resolved <- resolvedDemands]
      , let contractType = demanded
            routes selectedAccess =
              [ (consumer, method)
              | (consumer, resolvedDemands) <- resolvedTable, resolved <- resolvedDemands
              , demandContract resolved == demanded, demandAccess resolved == selectedAccess
              , Just method <- [sourceMethod resolved] ]
            producerName = concat (take 1 providers)
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

    upstreamScopes = Prototype.effectScopes . protoOf . name
    errorPath = Prototype.effectNearestScopes . protoOf . name
    orderedScopes = nub (concat
      [ Prototype.effectScopes effect
          ++ [Prototype.effectName effect | Prototype.effectKind effect == ScopedKind]
      | effect <- effectPrototypes ])
    openingInputs = Prototype.effectOpeningInputs . protoOf . name
    comparedInputs = nub (concatMap openingInputs
      [specification | specification <- specifications, effectKind (typing specification) == ScopedKind])
    observation prefix selectedName
      | selectedName `elem` comparedInputs = "(Just (" ++ prefix ++ "ScopeInput " ++ show selectedName ++ "))"
      | otherwise = "Nothing"

    -- preparePrototype 已验证挂载；渲染只读取原型指定的原始入口。
    findHandler selectedName = case
      [method | (role, method) <- Prototype.effectMethods (protoOf selectedName)
              , role `elem` [Graph.HandlerMethod, Graph.ScopeOpen]] of
      [method] -> Right method
      _ -> Left ("Prototype has no origin entry: " ++ selectedName)

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

    errorScopes = maybeToList . Prototype.effectErrorScope . protoOf . name
    -- 业务产物只归 Context；Output 仍只在运行边界统一包装。
    valueContract specification = case typing specification of
      Context (Just producing) -> Right (TypeRef (contractOf producing))
      Context Nothing ->
        Left ("Context needs request = requester \"handler\" @Representation: " ++ name specification)
      _ -> Right (TypeRef "()")

    declaration specification = do
      valueType <- valueContract specification
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
               ++ [upstreamEffect ++ "Effect m" | upstreamEffect <- Prototype.effectInputChain (protoOf effectName)]
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

    astInterpreter methods =
          [ ""
          , "-- 仅汇总所选末端的成功产物，不保存共享绑定或增加完成包装。"
          , "data Results = " ++ intercalate " | "
              [terminal ++ "Result (Produce " ++ terminal ++ ")" | terminal <- selected]
          , "  deriving Show"
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
              | contractType <- selectorContracts, reader <- readerOfContract contractType ]
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
              ++ " Handlers.handlerSourceFingerprint generatedPrototype compiledEntries"
          ]
      where
        wrapTarget label action = "SDK.targetApp " ++ show label ++ " emptyContexts scopes"
          ++ " (FrameworkRoot.withErrorHandlers Handlers.errorHandlers"
          ++ " (FrameworkRoot.withAnchoredContexts Handlers.contextInjections"
          ++ " (SDK.withScopeCleanups Handlers.scopeCleanups (" ++ action ++ "))))"
        renderList _ [] = "[]"
        renderList indent items = "[ " ++ intercalate ("\n" ++ indent ++ ", ") items ++ "\n" ++ indent ++ "]"

