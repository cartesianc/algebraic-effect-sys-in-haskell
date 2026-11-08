{-# LANGUAGE DuplicateRecordFields #-}

-- 将注册和选定末端 lower 为普通 Haskell 源码；不执行业务。
-- gen 是 EDSL 的编译：handler 的读取来源、Input 前驱与驱动在这里解析为生成代码，
-- 运行时不再按调用者查找来源。
module Framework.Codegen
  ( GeneratedCode(..), Binding(..), lowerProgram, composeMethods, normalizeType
  ) where

import Framework.Effect.Contract (EffectKind(..))
import Framework.Effect.Registration
import Framework.Effect.Demand (readsAccess)
import Framework.Effect.Graph (MethodShape(..))
import qualified Framework.Prototype as Prototype
import Framework.Workflow.AST (WorkflowF)
import Framework.Recursion (Fix)
import qualified Framework.Effect.Graph as Graph
import Control.Monad (unless, when)
import Data.Char (isAlphaNum, isLower, isSpace, isUpper, toUpper)
import Data.List (intercalate, nub, sort)
import Data.Maybe (maybeToList)

-- Types.hs 中的和类型：类型名 → [(构造器名, 唯一字段的类型原文)]；由 SDK 解析 Types.hs 得到。
type SumTypes = [(String, [(String, Maybe String)])]

-- 一次绑定：handler 在某个 effect 方法中执行。
-- before 是入口在 handler 之前调用的 effect 方法（先驱动，后 Input）；raw 是回答 raw 的直接 Input 方法；
-- routes 把规范化的表示类型映射到 (契约, 读取方法)。结构分析据此把 handler 方法体换成 effect 方法的结构。
data Binding = Binding
  { bindingEffect :: String
  , bindingMethod :: String
  , bindingHandler :: String
  , bindingBefore :: [String]
  , bindingRaw :: Maybe String
  , bindingRoutes :: [(String, (String, String))]
  } deriving (Eq, Show, Read)

-- 生成进程交接的是具名的源码产物与纯计划；字段不包含闭包或运行状态。
-- 通过 Show/Read 交接 ghci 的声明加载结果。
data GeneratedCode = GeneratedCode
  { codeEffects :: String
  , codeProgram :: String
  -- 追加到 Generated/Handlers 的装配代码，以及它导出的名字。
  , codeSupport :: String
  , codeExports :: [String]
  -- (handler 类, handler 方法)：结构分析只分析这些 instance。
  , codeHandlers :: [(String, String)]
  , codeBindings :: [Binding]
  -- effect → handler 方法体必须读取的契约（requires／streams 中没有被 workflow 控制流使用的部分）。
  , codeReads :: [(String, [String])]
  , codePrototypePlan :: Prototype.PrototypePlan
  , codeAssetRoots :: [String]
  , codeAssetContracts :: [String]
  } deriving (Eq, Show, Read)

-- 完整 AST 先交给 Prototype 编号和解析；渲染只读取其中的声明事实。
lowerProgram :: String -> [EffectSpec] -> Fix WorkflowF -> SumTypes
             -> Either String GeneratedCode
lowerProgram namespace specifications tree sumTypes = do
  plan <- either (Left . show) Right (Prototype.preparePrototype specifications sumTypes tree)
  renderProgram namespace plan sumTypes

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

-- 接口和运行包装只读取统一原型准备阶段的事实；handler 方法体随后由结构分析补入。
renderProgram :: String -> Prototype.PrototypePlan -> SumTypes -> Either String GeneratedCode
renderProgram namespace prepared sumTypes = do
  checkGenerated
  when (null selected) (Left "Select at least one terminal effect for generation")
  selectedMethods <- mapM findEntry selected
  mapM_ checkRepresentations specifications
  signatures <- mapM signatureOf handlers
  pure GeneratedCode
    { codeEffects = unlines (contractHeader ++ runtimeAliases ++ generatedContracts ++ methodIdentities
        ++ concatMap handlerContract signatures ++ errorDeclaration ++ contextDeclarations)
    , codeProgram = unlines (programHeader ++ astInterpreter selectedMethods)
    , codeSupport = unlines (supportHeader ++ concatMap raisesInstance handlers ++ routeInstances ++ rawInstances
        ++ concatMap entryDefinitions specifications)
        ++ scopeHandlers ++ scopeCleanups ++ errorHandlers ++ injectionTable
    , codeExports = allMethods ++ ["newScopeHandlers", "scopeCleanups", "errorHandlers", "contextInjections"]
    , codeHandlers = [(capitalized handler' ++ "Handler", handler') | handler' <- handlers]
    , codeBindings = bindings
    , codeReads =
        [ (name specification, nub
            [ demandContract resolved | resolved <- resolvedOf (name specification), readsAccess (demandAccess resolved)
            , (name specification, demandContract resolved) `notElem` controlled ])
        | specification <- specifications ]
    , codePrototypePlan = prepared
    , codeAssetRoots = nub [reference representation' | (_, representation', _) <- generatedDeclarations]
    , codeAssetContracts = [contractType | (contractType, _, _) <- generatedDeclarations]
    }
  where
    specifications = Prototype.plannedRegistrations prepared
    effectPrototypes = Prototype.plannedEffects prepared
    workflow = Prototype.plannedWorkflow prepared
    protoOf selectedName = case [effect | effect <- effectPrototypes, Prototype.effectName effect == selectedName] of
      effect : _ -> effect
      [] -> error ("Validated prototype has no effect: " ++ selectedName)
    specOf selectedName = case [specification | specification <- specifications, name specification == selectedName] of
      specification : _ -> specification
      [] -> error ("Validated registration has no effect: " ++ selectedName)
    resolvedOf = Prototype.effectDemands . protoOf
    allMethods = [method | effect <- effectPrototypes, (_, method) <- Prototype.effectMethods effect]
    contextSpecs = filter ((== ContextKind) . effectKind . typing) specifications
    selected = nub (Prototype.workflowTerminals workflow)
    controlled = controlReads effectPrototypes workflow

    -- 每个 Context 的契约类型由声明的资产名生成：(契约名, 表示类型, 生产方)。
    generatedDeclarations =
      [ (contractOf declared, representation declared, name specification)
      | specification <- contextSpecs
      , Just declared <- [contextAsset (typing specification)] ]
    -- 表示类型是和类型（至少两个构造器）时，每个构造器另有分支契约：契约名加构造器名。
    -- 分支契约是基础契约的投影，读到构造器的字段：(分支契约, (基础契约, 构造器, 字段类型, 生产方))。
    branchContracts =
      [ (base ++ constructor, (base, constructor, field, owner))
      | (base, TypeRef typeName, owner) <- generatedDeclarations
      , (branch, constructor) <- Prototype.effectBranches (protoOf owner)
      , Just constructors <- [lookup typeName sumTypes]
      , Just field <- [lookup constructor constructors]
      , branch == base ++ constructor ]
    continuousContract contractType = or
      [ Prototype.effectContinuous (protoOf owner) | (declared, _, owner) <- generatedDeclarations, declared == contractType ]
    -- 契约读到的表示类型：基础契约是声明的表示类型，分支契约是构造器的字段（无字段为 ()）。
    representationOf contractType = case lookup contractType branchContracts of
      Just (_, _, field, _) -> maybe "()" id field
      Nothing -> case [reference representation' | (declared, representation', _) <- generatedDeclarations, declared == contractType] of
        found : _ -> found
        [] -> error ("Validated demand has no asset: " ++ contractType)
    -- requires 读最新值，streams 读历史。
    readType historyType resolved = case demandAccess resolved of
      StreamAccess -> historyType ++ " (" ++ representationOf (demandContract resolved) ++ ")"
      _ -> representationOf (demandContract resolved)
    readDemands selectedName = [resolved | resolved <- resolvedOf selectedName, readsAccess (demandAccess resolved)]
    readerOf provider = case contextReader (typing (specOf provider)) of
      Just method -> method
      Nothing -> error ("Validated demand has no reader: " ++ provider)

    -- 驱动：requests 声明的资产在入口先调用 getT，沿 Input 驱动它的整条 Context 链。
    drives specification =
      [ getter | resolved <- resolvedOf (name specification), demandAccess resolved == RequestAccess
      , Just getter <- [contextProducer (typing (specOf (demandProvider resolved)))] ]
    -- 挂在原子句柄或 Stream 下的 parser 用 raw 读取直接 Input 的输出，不把 Input 当前驱执行。
    rawSource specification = case typing specification of
      Context {} | input specification /= "Root" -> case typing (specOf (input specification)) of
        Excu _ -> entryMethod (specOf (input specification))
        Scoped {} -> entryMethod (specOf (input specification))
        Stream _ -> entryMethod (specOf (input specification))
        _ -> Nothing
      _ -> Nothing
    rawExpression specification = case rawSource specification of
      Just method | Stream {} <- typing (specOf (input specification)) -> Just ("Just <$> " ++ method)
      other -> other
    -- 其他 Input 是前驱：在 handler 之前执行一次，输出不交给 handler。
    predecessor specification
      | input specification == "Root" = []
      | Just _ <- rawSource specification = []
      | otherwise = maybeToList (entryMethod (specOf (input specification)))
    -- handler 之前调用的 effect 方法：入口方法先驱动再执行 Input；close 与 Error 方法只执行 handler。
    beforeOf specification method
      | Just method == entryMethod specification = drives specification ++ predecessor specification
      | otherwise = []

    bindingsOf specification = handlerBindings specification
    handlers = nub [handler' | specification <- specifications, (_, handler') <- bindingsOf specification]
    bindings =
      [ Binding (name specification) method handler' (beforeOf specification method)
          (if Just method == contextProducer (typing specification) then rawSource specification else Nothing)
          [ (normalizeType (readType "History" resolved), (demandContract resolved, readerOf (demandProvider resolved)))
          | resolved <- readDemands (name specification) ]
      | specification <- specifications, (method, handler') <- bindingsOf specification ]

    -- 一个 effect 内每种表示类型至多出现一次；同类型的两个值需要角色类型（待定）。
    checkRepresentations specification = do
      let keys = [(normalizeType (readType "History" resolved), demandContract resolved) | resolved <- readDemands (name specification)]
      case [representation' | (representation', _) <- keys, length (filter ((== representation') . fst) keys) > 1] of
        representation' : _ -> Left ("Effect " ++ name specification ++ " reads several assets of representation "
          ++ representation' ++ " (" ++ intercalate ", " [contractType | (key, contractType) <- keys, key == representation']
          ++ "); one effect reads each representation type at most once")
        [] -> pure ()

    -- handler 的签名由绑定类别与 effect 的 demands 推出；同一 handler 的所有绑定必须一致。
    resultOf specification = case typing specification of
      Pure _ -> "()"
      Excu _ -> "Maybe String"
      Scoped {} -> "Maybe String"
      Error {} -> "()"
      Stream _ -> "String"
      Context { asset = declared } -> reference (representation declared)
    layerOf specification method = sort (nub ["SDK.Reads (" ++ readType "SDK.History" resolved ++ ") m"
        | resolved <- readDemands (name specification)])
      ++ ["SDK.Raw m" | Just method == contextProducer (typing specification), Just _ <- [rawSource specification]]
      ++ [if effectKind (typing specification) == PureKind then "Monad m" else "MonadIO m"]
    signatureOf handler' = do
      let bound = [(name specification, (resultOf specification, layerOf specification method))
            | specification <- specifications, (method, selectedHandler) <- bindingsOf specification, selectedHandler == handler']
      case nub (map snd bound) of
        [(result, layer)] -> pure (handler', result, layer, nub (map fst bound))
        _ -> Left ("Handler " ++ handler' ++ " is bound with different signatures: "
          ++ intercalate "; " [effect ++ " needs m (" ++ result ++ ") with " ++ intercalate ", " layer | (effect, (result, layer)) <- bound]
          ++ "; reuse a handler only where the binding kind and representation reads agree")

    contractHeader =
      [ "{-# LANGUAGE ConstraintKinds #-}"
      , "{-# LANGUAGE DeriveGeneric #-}"
      , "{-# LANGUAGE FlexibleContexts #-}"
      , "{-# LANGUAGE FlexibleInstances #-}"
      , "{-# LANGUAGE MonoLocalBinds #-}"
      , "{-# LANGUAGE StandaloneDeriving #-}"
      , "{-# LANGUAGE UndecidableInstances #-}"
      , ""
      , "-- 自动生成；通过 SDK 的 effect-codegen 更新，手写注册与 handler 位于上级目录。"
      , "module " ++ namespace ++ ".Generated.Effects where"
      , ""
      , "import qualified Framework.Generated as SDK"
      , "import Control.Monad.IO.Class (MonadIO)"
      , "import " ++ namespace ++ ".Types"
      , ""
      ]
    runtimeAliases =
      [ "-- SDK 提供运行载体；资产存储与错误分类由本文件给出。"
      , "type App = SDK.App ContextValues Errors"
      , ""
      ]
    -- 资产的名义类型只在生成区使用：handler 按表示类型读取，不构造或匹配它们。
    generatedContracts = case generatedDeclarations of
      [] -> []
      _ -> "-- 每个 Context 的资产类型：名字来自 Asset 声明，包装其表示类型。"
        : concat
          [ [ "newtype " ++ generated ++ " = " ++ generated ++ " (" ++ reference representation' ++ ")"
            , "deriving instance Eq (" ++ reference representation' ++ ") => Eq " ++ generated
            , "deriving instance Show (" ++ reference representation' ++ ") => Show " ++ generated
            , "" ]
          | (generated, representation', _) <- generatedDeclarations ]
    genName [] = "MissingMethodGen"
    genName (first : rest) = toUpper first : rest ++ "Gen"
    methodIdentities =
      [ "-- effect 方法的定义身份；仅生成区使用，图中不以字符串匹配方法。"
      , "data MethodGen = " ++ intercalate " | " (map genName allMethods)
      , "  deriving (Eq, Ord, Show, Read, SDK.Generic)"
      , "instance SDK.NFData MethodGen"
      , ""
      ]
    -- 每个 handler 一个类：Layer 是它能用的全部能力，来自绑定的 effect 的 demands 与类别。
    handlerContract (handler', result, layer, bound) =
      [ "-- handler " ++ handler' ++ "：绑定到 " ++ intercalate "、" bound ++ "。"
      , "type " ++ capitalized handler' ++ "Layer m = (" ++ intercalate ", "
          (init layer ++ ["SDK.Raises " ++ capitalized handler' ++ "Error m", last layer]) ++ ")"
      , "class " ++ capitalized handler' ++ "Handler m where"
      , "  " ++ handler' ++ " :: m " ++ parenthesized result
      , ""
      , "-- 失败属于 handler：发生位置由 SDK 记录，Error 按 RaisedBy " ++ show handler' ++ " 匹配。"
      , "newtype " ++ capitalized handler' ++ "Error = " ++ capitalized handler' ++ "Error String"
      , "  deriving (Eq, Show, Read)"
      , ""
      ]
    errorDeclaration =
      [ "-- 统一失败协议的分类标签：每个 handler 一个；消息与发生位置由 SDK.Failure 保存。"
      , "data Errors = " ++ intercalate " | "
          ([capitalized handler' ++ "Failure" | handler' <- handlers]
           ++ ["ContextBindingError SDK.ContextFault", "ScopeBindingError SDK.ScopeFault"])
      , "  deriving (Eq, Show)"
      , ""
      ]
    contextDeclarations =
      [ "-- SDK 内部存储：Nothing 仅表示本次运行尚未建立绑定，不是业务缺值。"
      , "data ContextValues = ContextValues"
      ] ++ (case ["bound" ++ name s ++ " :: Maybe " ++ contractOf declared
                  | s <- contextSpecs, Just declared <- [contextAsset (typing s)]] of
        [] -> [""]
        fields -> ["  { " ++ intercalate "\n  , " fields, "  }", ""])
      ++ [ "emptyContexts :: ContextValues"
         , "emptyContexts = ContextValues" ++ concat [" Nothing" | _ <- contextSpecs]
         , ""
         ]

    -- 生成区的装配：effect 标签、handler 能力的实例与 effect 方法。------------------------------
    supportHeader =
      [ ""
      , "-- 以下由 gen 生成。每个 effect 一个类型标签：handler 在标签下执行，"
      , "-- 读取、raw 与错误按标签在编译期解析到这个 effect 的来源，不改写 handler 方法体。"
      , "newtype At (effect :: FrameworkTypes.Symbol) value = At { runAt :: FrameworkGenerated.App value }"
      , "  deriving (Functor, Applicative, Monad, FrameworkIO.MonadIO)"
      , ""
      ]
    raisesInstance handler' =
      [ "instance FrameworkTypes.KnownSymbol effect => FrameworkRuntime.Raises FrameworkGenerated." ++ capitalized handler' ++ "Error (At effect) where"
      , "  raise (FrameworkGenerated." ++ capitalized handler' ++ "Error description) = At (FrameworkRuntime.failEffect"
      , "    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) FrameworkGenerated."
          ++ capitalized handler' ++ "Failure description)"
      , ""
      ]
    -- demands 按表示类型路由到资产的读取入口；分支契约投影出构造器字段，streams 读历史。
    routeInstances = concat
      [ [ "instance FrameworkRuntime.Reads (" ++ readType "FrameworkRuntime.History" resolved ++ ") (At "
            ++ show (name specification) ++ ") where"
        , "  require = At (" ++ routeExpression resolved ++ ")"
        , "" ]
      | specification <- specifications, not (null (bindingsOf specification))
      , resolved <- readDemands (name specification) ]
    routeExpression resolved = case (demandAccess resolved, lookup contractType branchContracts) of
      (StreamAccess, _) -> "fmap " ++ unwrap contractType ++ " <$> " ++ reader
      (_, Just (base, constructor, field, _)) -> "FrameworkRuntime.projectContext " ++ show producer ++ " "
        ++ show contractType ++ " FrameworkGenerated.ContextBindingError (\\(FrameworkGenerated." ++ base
        ++ " value) -> case value of { " ++ constructor ++ maybe " -> Just ()" (const " field -> Just field") field
        ++ "; _ -> Nothing }) (" ++ current base ++ ")"
      _ -> unwrap contractType ++ " <$> " ++ current contractType
      where
        contractType = demandContract resolved
        producer = demandProvider resolved
        reader = readerOf producer
        unwrap selectedContract = "(\\(FrameworkGenerated." ++ selectedContract ++ " value) -> value)"
        current base
          | continuousContract base = "FrameworkRuntime.latestContext " ++ show producer
              ++ " FrameworkGenerated.ContextBindingError " ++ reader
          | otherwise = reader
    rawInstances = concat
      [ [ "instance FrameworkRuntime.Raw (At " ++ show (name specification) ++ ") where"
        , "  raw = At (" ++ expression ++ ")"
        , "" ]
      | specification <- contextSpecs, Just expression <- [rawExpression specification] ]

    -- effect 方法：外层包装由类别决定；方法体先驱动、再执行 Input 前驱，最后在本 effect 的标签下执行 handler。
    entryDefinitions specification =
      [ line
      | (method, handler') <- bindingsOf specification
      , line <- definition method (resultType method) (wrapper method)
          (intercalate " >> " (beforeOf specification method ++ [handlerCall method handler'])) ]
      ++ concat [ readerDefinition specification method | Just method <- [contextReader (typing specification)] ]
      where
        selectedName = name specification
        resultType method = case typing specification of
          Context { asset = declared } | Just method == contextProducer (typing specification) -> "FrameworkGenerated." ++ contractOf declared
          _ -> resultOf specification
        handlerCall method handler' = case typing specification of
          Context { asset = declared } | Just method == contextProducer (typing specification) ->
            "(FrameworkGenerated." ++ contractOf declared ++ " <$> runAt @" ++ show selectedName ++ " FrameworkGenerated." ++ handler' ++ ")"
          _ -> "runAt @" ++ show selectedName ++ " FrameworkGenerated." ++ handler'
        scoped = "FrameworkRuntime.withScopeDependencies " ++ show (Prototype.effectScopes (protoOf selectedName))
        entered = scoped ++ " . FrameworkRuntime.enterHandler " ++ show selectedName
        wrapper method = rootWrapper specification ++ " . " ++ case typing specification of
          -- 先进入本 scope，再检查其上游；失效后的 close 仍可读取自己的 Context 以收尾。
          Scoped _ _ -> "FrameworkRuntime.atomicScope " ++ show method ++ " . FrameworkRuntime."
            ++ (if Just method == entryMethod specification then "openScope " else "closeScope ")
            ++ show selectedName ++ " FrameworkGenerated.ScopeBindingError . " ++ entered
          -- 原子句柄的输出只交给挂在它下面的 parser，以它为 Input 的方法照常继续。
          Excu _ -> "FrameworkRuntime.atomicHandle " ++ show method ++ " . " ++ entered
          -- parser 的 raw 在会话中由本次原始输入回答，不再执行 handler。
          Stream _ -> "FrameworkRuntime.streamHandle . " ++ entered
          Context {} -> scoped ++ " . FrameworkRuntime.callContext " ++ show selectedName
            ++ " FrameworkGenerated.ContextBindingError\n    " ++ contextAccessTable selectedName
            ++ "\n    " ++ observation selectedName
            ++ "\n    FrameworkGenerated.bound" ++ selectedName
            ++ "\n    (\\value bindings -> bindings { FrameworkGenerated.bound" ++ selectedName ++ " = Just value })"
          _ -> entered
    rootWrapper specification = "FrameworkRoot.withErrorPath " ++ show (Prototype.effectNearestScopes (protoOf (name specification)))
      ++ " . FrameworkRoot.handleFailure"
    -- readT 读最新值：尚无值时按需求值一次 getT；streamT 读历史视图，由会话交付。
    readerDefinition specification method
      | Prototype.effectContinuous (protoOf selectedName) = definition method
          ("FrameworkRuntime.History FrameworkGenerated." ++ contractType) (rootWrapper specification)
          ("FrameworkRuntime.readHistory " ++ show selectedName ++ " FrameworkGenerated.ContextBindingError "
            ++ contextAccessTable selectedName ++ " FrameworkGenerated.bound" ++ selectedName ++ " Nothing")
      | otherwise = definition method ("FrameworkGenerated." ++ contractType) (rootWrapper specification)
          ("FrameworkRuntime.readContext " ++ show selectedName ++ " FrameworkGenerated.ContextBindingError "
            ++ contextAccessTable selectedName ++ " " ++ observation selectedName ++ " FrameworkGenerated.bound" ++ selectedName
            ++ " " ++ missing)
      where
        selectedName = name specification
        contractType = maybe "" contractOf (contextAsset (typing specification))
        missing = case contextProducer (typing specification) of
          Just producing -> producing
          Nothing -> "(FrameworkRuntime.failEffect " ++ show selectedName
            ++ " (FrameworkGenerated.ContextBindingError FrameworkRuntime.ContextNotInitialized) "
            ++ show (selectedName ++ " has no parser") ++ ")"
    definition method resultType wrapper body =
      [ method ++ " :: FrameworkGenerated.App " ++ parenthesized resultType
      , method ++ " = (" ++ wrapper ++ ") $"
      , "  " ++ body
      , "" ]

    -- 生产与读取共用声明表：requests 刷新，requires／streams 只读。键是 effect 名（运行时的当前 handler 位置）。
    contextAccessTable selectedName = "[" ++ intercalate ", "
      [ "(" ++ show (name consumer) ++ ", FrameworkRuntime." ++ access ++ ")"
      | consumer <- specifications
      , Just access <- [accessFor consumer] ] ++ "]"
      where
        providersOf consumer mode = [demandProvider resolved | resolved <- resolvedOf (name consumer), mode (demandAccess resolved)]
        accessFor consumer
          | selectedName `elem` providersOf consumer (== RequestAccess) = Just "RequestValue"
          | selectedName `elem` providersOf consumer readsAccess = Just "RequireValue"
          | otherwise = Nothing
    orderedScopes = nub (concat
      [ Prototype.effectScopes effect ++ [Prototype.effectName effect | Prototype.effectKind effect == ScopedKind]
      | effect <- effectPrototypes ])
    openingInputs = Prototype.effectOpeningInputs . protoOf . name
    comparedInputs = nub (concatMap openingInputs
      [specification | specification <- specifications, effectKind (typing specification) == ScopedKind])
    observation selectedName
      | selectedName `elem` comparedInputs = "(Just (FrameworkRuntime.ScopeInput " ++ show selectedName ++ "))"
      | otherwise = "Nothing"

    -- 控制对象由生成的 handler 模块创建；不同链引用同份对象，不预执行 open。
    scopeHandlers = unlines
      [ "-- SDK 内部：scope 按上游到下游登记，退出时逆序收尾；创建不执行业务方法。"
      , "newScopeHandlers :: IO [FrameworkRuntime.ScopeHandler FrameworkGenerated.ContextValues FrameworkGenerated.Errors]"
      , "newScopeHandlers = sequence"
      , "  [" ++ (if null registered then "" else " " ++ intercalate "\n  , " registered)
      , "  ]"
      ]
      where
        registered =
          [ "FrameworkRuntime.newScopeHandler " ++ show (name specification) ++ " " ++ show (openingInputs specification)
              ++ " (" ++ show (Prototype.effectResource (protoOf (name specification))) ++ ")"
          | selectedScope <- orderedScopes, specification <- specifications, name specification == selectedScope ]
    scopeCleanups = unlines
      [ ""
      , "-- SDK 自动收尾入口；安装时不关闭资源。"
      , "scopeCleanups :: [(String, FrameworkGenerated.App ())]"
      , "scopeCleanups ="
      , "  [" ++ (if null callbacks then "" else " " ++ intercalate "\n  , " callbacks)
      , "  ]"
      ]
      where
        callbacks =
          [ "(" ++ show selectedScope ++ ", () <$ " ++ closing ++ ")"
          | selectedScope <- orderedScopes
          , effect <- effectPrototypes, Prototype.effectName effect == selectedScope
          , (Graph.ScopeClose, closing) <- Prototype.effectMethods effect ]
    -- 原子句柄的输出交给挂在它下面的 parser：键是句柄的 effect 方法名。
    injectionTable = unlines
      [ ""
      , "-- 挂在原子句柄下的 Context：句柄的输出交给它的 parser 解析并发布为资产；没有挂接时输出被丢弃。"
      , "contextInjections :: [(String, [(String, FrameworkGenerated.App ())])]"
      , "contextInjections ="
      , "  [" ++ (if null entries then "" else " " ++ intercalate "\n  , " entries)
      , "  ]"
      ]
      where
        entries =
          [ "(" ++ show entry ++ ", [" ++ intercalate ", "
              ["(" ++ show (Prototype.effectName context) ++ ", () <$ " ++ producing ++ ")" | (context, producing) <- anchored] ++ "])"
          | specification <- specifications
          , Just entry <- [entryMethod specification]
          , let anchored =
                  [ (context, producing)
                  | context <- effectPrototypes
                  , Prototype.effectAnchor context == Just (name specification)
                  , (Graph.ContextRequest, producing) <- Prototype.effectMethods context ]
          , not (null anchored) ]
    -- Error 只指向 scope：按 handles 匹配故障，detect／resolve 是生成的 effect 方法。
    errorHandlers = unlines
      [ ""
      , "-- Error 回调登记：按 handles 匹配故障的 handler 与协议分类；关联 scope 由 Input 链推导。"
      , "errorHandlers :: [(Maybe String, FrameworkRoot.ErrorHandler FrameworkGenerated.Errors FrameworkGenerated.App)]"
      , "errorHandlers ="
      , "  [" ++ (if null callbacks then "" else " " ++ intercalate "\n  , " callbacks)
      , "  ]"
      ]
      where
        callbacks =
          [ "(" ++ show (Prototype.effectErrorScope effect) ++ ", FrameworkRoot.ErrorHandler " ++ show (name specification)
              ++ "\n      (\\failure -> case (FrameworkRoot.origin failure, FrameworkRoot.detail failure) of"
              ++ concatMap (("\n        " ++) . matchCase) (nub matched)
              ++ "\n        _ -> False)"
              ++ "\n      (" ++ methodReference Graph.ErrorDetect ++ ") (" ++ methodReference Graph.ErrorResolve ++ "))"
          | specification <- specifications
          , Error { handles = matched } <- [typing specification]
          , let effect = protoOf (name specification)
                methodReference role = maybe "Nothing" ("Just " ++) (lookup role (Prototype.effectMethods effect)) ]
        matchCase (RaisedBy selectedHandler) = "(_, FrameworkGenerated." ++ capitalized selectedHandler ++ "Failure) -> True"
        matchCase (ScopeFaultIn selectedEffect) = "(" ++ show selectedEffect ++ ", FrameworkGenerated.ScopeBindingError _) -> True"
        matchCase (ContextFaultIn selectedEffect) = "(" ++ show selectedEffect ++ ", FrameworkGenerated.ContextBindingError _) -> True"

    -- preparePrototype 已验证挂载；渲染只读取原型指定的原始入口。
    findEntry selectedName = case
      [method | (role, method) <- Prototype.effectMethods (protoOf selectedName)
              , role `elem` [Graph.HandlerMethod, Graph.ScopeOpen]] of
      [method] -> Right method
      _ -> Left ("Prototype has no origin entry: " ++ selectedName)

    -- 资产名与 handler 派生名都进入生成区的同一命名空间，不能重名或与固定名冲突。
    checkGenerated = do
      let declared = [contractType | (contractType, _, _) <- generatedDeclarations] ++ map fst branchContracts
          derived = concat [[capitalized handler' ++ suffix | suffix <- ["Handler", "Layer", "Error", "Failure"]] | handler' <- handlers]
          reserved = ["App", "At", "ContextValues", "Errors", "MethodGen", "Results", "ContextBindingError", "ScopeBindingError"] ++ derived
          fixedValues = ["runAt", "emptyContexts", "handlerSourceFingerprint", "newScopeHandlers", "scopeCleanups"
            , "errorHandlers", "contextInjections", "interpreter", "compiledEntries", "generatedPrototype"]
      case [contractType | contractType <- nub declared, length (filter (== contractType) declared) > 1] of
        contractType : _ -> Left ("Contract " ++ contractType ++ " comes from more than one asset or branch; rename one of them")
        [] -> pure ()
      case [contractType | contractType <- nub declared, contractType `elem` reserved] of
        contractType : _ -> Left ("Asset or branch contract " ++ contractType
          ++ " collides with a generated name; rename the asset or constructor")
        [] -> pure ()
      case [handler' | handler' <- handlers, not (validMethodName handler') || handler' `elem` fixedValues] of
        handler' : _ -> Left ("Handler name must be a lowercase identifier not used by generated code: " ++ handler')
        [] -> pure ()
      mapM_ (\(contractType, representation', owner) -> do
          unless (validTypeName contractType) $
            Left ("Asset name must be a type name such as StartURL: " ++ contractType ++ " in " ++ owner)
          case representation' of
            TypeRef _ -> pure ()
            _ -> Left ("Context asset must wrap a business value, not Output: " ++ owner))
        generatedDeclarations
    validTypeName selectedName = case selectedName of
      first : rest -> isUpper first && all (\character -> isAlphaNum character || character `elem` "_'") rest
      [] -> False
    validMethodName selectedName = case selectedName of
      first : rest -> isLower first && all (\character -> isAlphaNum character || character `elem` "_'") rest
      [] -> False

    reference (TypeRef typeName) = typeName
    reference (OutputRef cause value) = "SDK.Output (" ++ reference cause ++ ") (" ++ reference value ++ ")"

    programHeader =
      [ "{-# LANGUAGE DuplicateRecordFields #-}"
      , ""
      , "-- 自动生成；只登记末端入口与原型，执行由 SDK 的 interpreter 完成。"
      , "module " ++ namespace ++ ".Generated.Program where"
      , ""
      , "import Framework.Generated (EffectSpec(..), EffectTyping(..), Asset(..), Handles(..), Demand(..), Access(..), TypeRef(..))"
      , "import qualified Framework.Generated as SDK"
      , "import qualified Framework.Effect.Contract as FrameworkRoot"
      , "import " ++ namespace ++ ".Generated.Effects"
      , "import qualified " ++ namespace ++ ".Generated.Handlers as Handlers"
      , "import " ++ namespace ++ ".Types"
      , ""
      ]
    selectorContracts = nub (Prototype.workflowSelectors workflow)
    readerOfContract contractType =
      [ reader | (declared, _, owner) <- generatedDeclarations, declared == contractType
      , Just reader <- [contextReader (typing (specOf owner))] ]
    astInterpreter methods =
      [ ""
      , "-- 仅汇总所选末端的成功结果，不保存共享绑定或增加完成包装。"
      , "data Results = " ++ intercalate " | " [terminal ++ "Result ()" | terminal <- selected]
      , "  deriving Show"
      , ""
      , "-- 末端共享生成的 scope 句柄；只创建空状态，Node algebra 才 lower。"
      , "-- 第二个列表是各转折契约的读取末端：读取资产，返回它当前的构造器名。"
      , "-- 第三个列表是各持续资产的生产步骤：会话按需启动，Stream 单步取得原始输入，parser 发布一次资产。"
      , "compiledEntries :: IO ([SDK.Target ContextValues Errors Results], [SDK.Target ContextValues Errors String]"
      , "                     , [(String, SDK.SessionSteps ContextValues Errors)])"
      , "compiledEntries = do"
      , "  scopes <- Handlers.newScopeHandlers"
      , "  pure"
      , "    ( " ++ renderList "      "
          [ wrapTarget terminal (terminal ++ "Result <$> (() <$ Handlers." ++ method ++ ")")
          | (terminal, method) <- zip selected methods ]
      , "    , " ++ renderList "      "
          [ wrapTarget contractType ("caseOf" ++ contractType ++ " <$> Handlers." ++ reader)
          | contractType <- selectorContracts, reader <- readerOfContract contractType ]
      , "    , " ++ renderList "      " sessionSteps
      , "    )"
      , ""
      ] ++ concat
      [ if continuousContract contractType
          -- 持续资产读到交付视图：按本次交付的最新条目分派（交付视图至少有一条）。
          then [ "caseOf" ++ contractType ++ " :: SDK.History " ++ contractType ++ " -> String"
               , "caseOf" ++ contractType ++ " history = case SDK.latest history of"
               , "  Just (" ++ contractType ++ " value) -> case value of" ]
               ++ [ "    " ++ constructor ++ " {} -> " ++ show constructor
                  | (_, (base, constructor, _, _)) <- branchContracts, base == contractType ]
               ++ [ "  Nothing -> \"\"", "" ]
          else [ "caseOf" ++ contractType ++ " :: " ++ contractType ++ " -> String"
               , "caseOf" ++ contractType ++ " (" ++ contractType ++ " value) = case value of" ]
               ++ [ "  " ++ constructor ++ " {} -> " ++ show constructor
                  | (_, (base, constructor, _, _)) <- branchContracts, base == contractType ]
               ++ [ "" ]
      | contractType <- selectorContracts ] ++
      [ "-- SDK 装配入口，不需要用户提供节点执行器或重复选择 handler。"
      , "interpreter :: SDK.AST -> [EffectSpec] -> IO ()"
      , "interpreter = SDK.interpreter " ++ show namespace
          ++ " " ++ show ("demo/" ++ map (\character -> if character == '.' then '/' else character) namespace ++ "/Handlers.hs")
          ++ " Handlers.handlerSourceFingerprint generatedPrototype compiledEntries"
      ]
      where
        -- 按 Context 注册名登记（与运行时绑定来源同名）：Stream 单步取得原始输入，parser 解析它并发布。
        sessionSteps =
          [ "(" ++ show (name specification) ++ ", SDK.receiveSteps ("
              ++ wrapTarget (input specification) ("Handlers." ++ handle) ++ ") ("
              ++ wrapTarget (name specification) ("() <$ Handlers." ++ parsing) ++ "))"
          | specification <- contextSpecs, Prototype.effectContinuous (protoOf (name specification))
          , Just parsing <- [contextProducer (typing specification)]
          , Just handle <- [entryMethod (specOf (input specification))] ]
        wrapTarget label action = "SDK.targetApp " ++ show label ++ " emptyContexts scopes"
          ++ " (FrameworkRoot.withErrorHandlers Handlers.errorHandlers"
          ++ " (FrameworkRoot.withAnchoredContexts Handlers.contextInjections"
          ++ " (SDK.withScopeCleanups Handlers.scopeCleanups (" ++ action ++ "))))"
        renderList _ [] = "[]"
        renderList indent items = "[ " ++ intercalate ("\n" ++ indent ++ ", ") items ++ "\n" ++ indent ++ "]"

capitalized :: String -> String
capitalized [] = []
capitalized (first : rest) = toUpper first : rest

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

-- workflow 控制流已经使用的读取：lifelong 订阅的 streams，以及 alternative 候选选择所依据的分支契约。
-- 输入链上的声明参与选择／交付，因此这些 demand 不要求 handler 方法体再读一次。
controlReads :: [Prototype.EffectProto method] -> Prototype.WorkflowTree -> [(String, String)]
controlReads effects tree = nub (walk tree)
  where
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
      pure (binding, sequenceShape (map Call (bindingBefore binding) ++ [mapped]), contracts)
    resolve binding shape = case shape of
      Empty -> pure (Empty, [])
      Call ('@' : typeText) -> case lookup (normalizeType typeText) (bindingRoutes binding) of
        Just (contractType, reader) -> pure (Call reader, [contractType])
        Nothing -> Left ("Handler " ++ bindingHandler binding ++ " reads " ++ typeText ++ " in " ++ bindingEffect binding
          ++ ", whose demands give " ++ describe (bindingRoutes binding)
          ++ "; declare requires/streams for an asset of that representation")
      Call "%raw" -> case bindingRaw binding of
        Just method -> pure (Call method, [])
        Nothing -> Left ("Handler " ++ bindingHandler binding ++ " uses raw in " ++ bindingEffect binding
          ++ "; only a Context parser hanging below an Excu, Scoped or Stream reads raw")
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
