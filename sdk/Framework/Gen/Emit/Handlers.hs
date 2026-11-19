{-# LANGUAGE DuplicateRecordFields #-}

-- 输出 Generated/Handlers.hs：手写 Handlers.hs 的编译副本（方法体原样保留），后接 gen 生成的装配——
-- 每个 effect 一个类型标签 At，按标签的 Reads／Raw／Raises 实例，“驱动 → Input → 方法体”的 effect 方法，
-- 以及 scope、Error 与挂接 Context 的登记表。只渲染绑定阶段定下的事实。
module Framework.Gen.Emit.Handlers (renderHandlers, handlerExports) where

import Data.List (intercalate, nub, sortOn)
import Data.Maybe (isJust)
import Framework.Gen.Plan
import Framework.Gen.Emit.Types (renderValueType)
import Framework.Gen.Names (handlerError, handlerFailure)
import Framework.Gen.Frontend.Source (HandlerSource(..), sourceOffset)
import Framework.Language.Registration
import Framework.Prototype.Graph (MethodRole(..))
import qualified Framework.Prototype as Prototype
import GHC (GhcPs)
import GHC.Fingerprint (fingerprintString)
import GHC.Hs
import GHC.Parser.Annotation (getLocA)
import GHC.Types.SrcLoc

-- Generated/Handlers 导出的名字：全部 effect 方法与登记表；Middleware 目录只在注册了 Middleware 时生成。
handlerExports :: Unit -> [String]
handlerExports unit = allMethods unit ++ ["newScopeHandlers", "scopeCleanups", "errorHandlers", "contextInjections", "streamContextInjections"]
  ++ ["middlewareHooks" | hasMiddleware unit]

hasMiddleware :: Unit -> Bool
hasMiddleware unit = any ((== MiddlewareOperation) . bindingOperation) (unitBindings unit)

-- 首次生成尚无 Handlers.hs 时只给出指纹，编写 Handlers.hs 后重新生成；原文件始终保留，只有副本进入运行导入链。
renderHandlers :: Unit -> Maybe HandlerSource -> Either String String
renderHandlers unit loaded = do
  let generatedName = unitNamespace unit ++ ".Generated.Handlers"
      sourceFingerprint = fmap (show . fingerprintString . handlerText) loaded
      extraExports = "handlerSourceFingerprint" : handlerExports unit
  generated <- case loaded of
    Nothing -> pure ("module " ++ generatedName ++ " (handlerSourceFingerprint) where\n")
    Just source -> copyModule (unitNamespace unit) generatedName extraExports (handlerText source) (handlerModule source)
  pure ("-- 自动生成的编译副本；请修改上级 Handlers.hs 后重新生成。\n"
        ++ concat ["{-# LANGUAGE " ++ extension ++ " #-}\n" | extension <- copyExtensions]
        ++ generated
        ++ "\n-- 记录本编译副本实际使用的手写源码；启动前检查，避免执行过期方法体。\n"
        ++ "handlerSourceFingerprint :: Maybe String\n"
        ++ "handlerSourceFingerprint = " ++ show sourceFingerprint ++ "\n"
        ++ (if isJust loaded then support unit else ""))

-- 生成区的装配：effect 标签、handler 能力的实例与 effect 方法。
support :: Unit -> String
support unit = unlines (supportHeader ++ concatMap raisesInstance (unitHandlers unit) ++ routeInstances ++ rawInstances
    ++ endInstances ++ hookInstances ++ concatMap entryDefinitions (map Prototype.effectName (effectPrototypes unit)))
    ++ scopeHandlers ++ scopeCleanups ++ errorHandlers ++ middlewareHooks
    ++ injectionTable ContextRequest "contextInjections"
    ++ injectionTable ContextStream "streamContextInjections"
  where
    supportHeader =
      [ ""
      , "-- 以下由 gen 生成。每个 effect 一个类型标签：handler 在标签下执行，"
      , "-- 读取、raw 与错误按标签在编译期解析到这个 effect 的来源，不改写 handler 方法体。"
      , "newtype At (effect :: FrameworkTypes.Symbol) value = At { runAt :: FrameworkGenerated.App value }"
      , "  deriving (Functor, Applicative, Monad, FrameworkIO.MonadIO)"
      , ""
      ]
    -- 有绑定被捕获的 handler 按标签逐个给出 raise：被捕获的标签先带 handler 名交给 Middleware，再以原失败退出。
    raisesInstance handler'
      | any (isJust . bindingObserved) bound = concat
          [ [ "instance FrameworkRuntime.Raises FrameworkGenerated." ++ handlerError handler' ++ " (At " ++ show effect ++ ") where"
            , "  raise (FrameworkGenerated." ++ handlerError handler' ++ " description) = At (" ++ observed
                ++ "FrameworkRuntime.failEffect " ++ show effect ++ " FrameworkGenerated." ++ handlerFailure handler' ++ " description)"
            , "" ]
          | (effect, kind) <- nub [(bindingEffect binding, bindingObserved binding) | binding <- bound]
          , let observed = maybe "" (\selected -> "FrameworkRuntime.observeRaise FrameworkRuntime." ++ show selected
                  ++ " " ++ show handler' ++ " description $ ") kind ]
      where bound = [binding | binding <- unitBindings unit, bindingHandler binding == handler']
    raisesInstance handler' =
      [ "instance FrameworkTypes.KnownSymbol effect => FrameworkRuntime.Raises FrameworkGenerated." ++ handlerError handler' ++ " (At effect) where"
      , "  raise (FrameworkGenerated." ++ handlerError handler' ++ " description) = At (FrameworkRuntime.failEffect"
      , "    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) FrameworkGenerated."
          ++ handlerFailure handler' ++ " description)"
      , ""
      ]
    -- demands 按表示类型路由到资产的读取入口；持续与有限调用都读声明的 T，分支契约投影构造器字段。
    routeInstances = concat
      [ [ "instance FrameworkRuntime.Reads (" ++ renderValueType "FrameworkRuntime." "FrameworkGenerated." (routeType route) ++ ") (At "
            ++ show (routeEffect route) ++ ") where"
        , "  require = At (" ++ routeExpression route ++ ")"
        , "" ]
      | route <- unitRoutes unit ]
    routeExpression route = case routeView route of
      BranchView (BranchContract _ base constructor field _) ->
        "FrameworkRuntime.projectContext " ++ show producer ++ " "
        ++ show contractType ++ " FrameworkGenerated.ContextBindingError (\\(FrameworkGenerated." ++ base
        ++ " value) -> case value of { " ++ constructor ++ maybe " -> Just ()" (const " field -> Just field") field
        ++ "; _ -> Nothing }) (" ++ reader ++ ")"
      ContinuousView -> unwrap contractType ++ " <$> " ++ reader
      ValueView -> unwrap contractType ++ " <$> " ++ reader
      where
        contractType = routeContract route
        producer = routeProvider route
        reader = routeReader route
        unwrap selectedContract = "(\\(FrameworkGenerated." ++ selectedContract ++ " value) -> value)"
    rawInstances = concat
      [ [ "instance FrameworkRuntime.Raw (At " ++ show (bindingEffect binding) ++ ") where"
        , "  raw = At (" ++ observedRaw binding (rawExpression source) ++ ")"
        , "" ]
      | binding <- unitBindings unit, Just source <- [bindingRaw binding] ]
    observedRaw binding reading = case bindingRawObserved binding of
      Just kind -> "FrameworkRuntime.observeRaw FrameworkRuntime." ++ show kind ++ " " ++ show (bindingHandler binding) ++ " (" ++ reading ++ ")"
      Nothing -> reading
    -- 能力已经由组合计算确定；这里只为对应标签输出实例，不重新解释 effect 类别或 demands。
    endInstances = concat
      [ [ "instance FrameworkRuntime.StreamEnds (At " ++ show (selectedName) ++ ") where"
        , "  streamEnd = At FrameworkRuntime.endSource"
        , "" ]
      | selectedName <- map Prototype.effectName (effectPrototypes unit), hasCapability selectedName EndsSource ]
      ++ concat
      [ [ "instance FrameworkRuntime.EndsStream (At " ++ show (selectedName) ++ ") where"
        , "  endStream = At FrameworkRuntime.endSubscription"
        , "" ]
      | selectedName <- map Prototype.effectName (effectPrototypes unit), hasCapability selectedName EndsSubscription ]
    -- 只为 Middleware 的标签给出 Hooks：普通 effect 的 handler 没有这项能力。
    hookInstances = concat
      [ [ "instance FrameworkRuntime.Hooks (At " ++ show (bindingEffect binding) ++ ") where"
        , "  hookedOutput = At FrameworkRuntime.observedOutput"
        , "  hookedRaw = At FrameworkRuntime.observedRaw"
        , "  hookedError = At FrameworkRuntime.observedError"
        , "" ]
      | binding <- unitBindings unit, bindingOperation binding == MiddlewareOperation ]
    hasCapability selectedName capability = or
      [ capability `elem` bindingCapabilities binding
      | binding <- unitBindings unit, bindingEffect binding == selectedName ]

    -- effect 方法：外层包装由类别决定；方法体先驱动、再执行 Input 前驱，最后在本 effect 的标签下执行 handler。
    entryDefinitions selectedName =
      [ line
      | binding <- unitBindings unit, bindingEffect binding == selectedName
      , let method = bindingMethod binding
            handler' = bindingHandler binding
      , line <- definition method (renderValueType "FrameworkRuntime." "FrameworkGenerated." (bindingResult binding)) (wrapper binding)
          (intercalate " >> " (bindingCalls binding ++ [handlerCall binding handler'])) ]
      ++ concat [ readerDefinition reader | reader <- unitReaders unit, readerEffect reader == selectedName ]
      where
        handlerCall binding handler' = case bindingOperation binding of
          PublishAsset contract ->
            "(FrameworkGenerated." ++ contract ++ " <$> runAt @" ++ show selectedName ++ " FrameworkGenerated." ++ handler' ++ ")"
          _ -> observedOutput binding ("runAt @" ++ show selectedName ++ " FrameworkGenerated." ++ handler')
        -- 交出值的捕获点：原子 handler（Excu、Scoped 的 open／close、Pure）这一次调用交出的值。
        observedOutput binding call = case bindingObserved binding of
          Just kind | bindingOperation binding `elem` [AtomicOperation, OpenResource, CloseResource, PureOperation] ->
            "FrameworkRuntime.observeOutput FrameworkRuntime." ++ show kind ++ " " ++ show (bindingHandler binding) ++ " (" ++ call ++ ")"
          _ -> call
        scoped = "FrameworkRuntime.withScopeDependencies " ++ show (Prototype.effectScopes (protoOf unit selectedName))
        entered = scoped ++ " . FrameworkRuntime.enterHandler " ++ show selectedName
        -- Middleware 入口不加包装：它在调用点内同步执行，失败从该调用点沿原入口的包装传播。
        wrapper binding | bindingOperation binding == MiddlewareOperation = "id"
        wrapper binding = rootWrapper selectedName ++ " . " ++ case bindingOperation binding of
          -- 先进入本 scope，再检查其上游；失效后的 close 仍可读取自己的 Context 以收尾。
          OpenResource -> scopeWrapper binding "openScope "
          CloseResource -> scopeWrapper binding "closeScope "
          AtomicOperation -> "FrameworkRuntime.atomicHandle " ++ show (bindingMethod binding) ++ " . " ++ entered
          SourceStep -> "FrameworkRuntime.streamHandle . " ++ entered
          PureOperation -> scoped
          PublishAsset _ -> scoped ++ " . FrameworkRuntime.callContext " ++ show selectedName
            ++ "\n    (\\value bindings -> bindings { FrameworkGenerated.bound" ++ selectedName ++ " = Just value })"
          ErrorOperation -> entered
          MiddlewareOperation -> entered
        scopeWrapper binding operation = "FrameworkRuntime.atomicScope " ++ show (bindingMethod binding) ++ " . FrameworkRuntime."
          ++ operation ++ show selectedName ++ " FrameworkGenerated.ScopeBindingError . " ++ entered
    rootWrapper selectedName = "FrameworkRuntime.withErrorPath " ++ show (Prototype.effectNearestScopes (protoOf unit selectedName))
      ++ " . FrameworkRuntime.handleFailure"
    -- readT 与 streamT 的模式由组合计算选定，渲染器只输出相应的读取入口。
    readerDefinition reader
      | readerContinuous reader = definition method
          ("FrameworkGenerated." ++ contractType) (rootWrapper selectedName)
          ("FrameworkRuntime.readStreamContext " ++ show selectedName ++ " FrameworkGenerated.ContextBindingError"
            ++ " FrameworkGenerated.bound" ++ selectedName)
      | otherwise = definition method ("FrameworkGenerated." ++ contractType) (rootWrapper selectedName)
          ("FrameworkRuntime.readContext " ++ show selectedName ++ " FrameworkGenerated.ContextBindingError "
             ++ "FrameworkGenerated.bound" ++ selectedName)
      where
        selectedName = readerEffect reader
        method = readerMethod reader
        contractType = readerContract reader
    definition method resultType wrapper body =
      [ method ++ " :: FrameworkGenerated.App " ++ parenthesized resultType
      , method ++ " = (" ++ wrapper ++ ") $"
      , "  " ++ body
      , "" ]


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
          [ "FrameworkRuntime.newScopeHandler " ++ show (scopeEffect plan) ++ " " ++ show (scopeInputs plan)
              ++ " (" ++ show (scopeResource plan) ++ ")"
          | plan <- unitScopes unit ]
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
          [ "(" ++ show (scopeEffect plan) ++ ", () <$ " ++ closing ++ ")"
          | plan <- unitScopes unit, Just closing <- [scopeCleanup plan] ]
    -- 原子句柄的输出交给挂在它下面的 parser：键是句柄的 effect 方法名。
    injectionTable role tableName = unlines
      [ ""
      , "-- 挂在原子句柄下的 Context：句柄的输出交给它的 parser 解析并发布为资产；没有挂接时输出被丢弃。"
      , tableName ++ " :: [(String, [(String, FrameworkGenerated.App ())])]"
      , tableName ++ " ="
      , "  [" ++ (if null entries then "" else " " ++ intercalate "\n  , " entries)
      , "  ]"
      ]
      where
        connections = [connection | connection <- assemblyOutputs (unitAssembly unit), outputRole connection == role]
        entries =
          [ "(" ++ show anchor ++ ", [" ++ intercalate ", "
              ["(" ++ show (outputProducer connection) ++ ", () <$ " ++ outputParser connection ++ ")"
              | connection <- connections, outputAnchor connection == anchor] ++ "])"
          | anchor <- nub (map outputAnchor connections) ]
    -- Middleware 目录（注册顺序）：名字 → (拦截类别, 入口)。生效位置由 Prototype 的静态集合决定。
    middlewareHooks
      | hasMiddleware unit = unlines
          [ ""
          , "-- Middleware 目录：按名字登记拦截类别与入口；每个启动位置的生效集合来自 Prototype。"
          , "middlewareHooks :: [(String, ([FrameworkRuntime.EffectKind], FrameworkGenerated.App ()))]"
          , "middlewareHooks ="
          , "  [ " ++ intercalate "\n  , "
              [ "(" ++ show (bindingEffect binding) ++ ", ([" ++ intercalate ", " ["FrameworkRuntime." ++ show kind | kind <- kinds]
                  ++ "], () <$ " ++ bindingMethod binding ++ "))"
              | binding <- unitBindings unit, bindingOperation binding == MiddlewareOperation
              , let kinds = interceptedKinds (bindingEffect binding) ]
          , "  ]"
          ]
      | otherwise = ""
    interceptedKinds selectedName = [kind | (owner, kinds) <- unitMiddleware unit, owner == selectedName, kind <- kinds]
    -- Error 只指向 scope：按 handles 匹配故障，detect／resolve 是生成的 effect 方法。
    errorHandlers = unlines
      [ ""
      , "-- Error 回调登记：按 handles 匹配故障的 handler 与协议分类；关联 scope 由 Input 链推导。"
      , "errorHandlers :: [(Maybe String, FrameworkRuntime.ErrorHandler FrameworkGenerated.Errors FrameworkGenerated.App)]"
      , "errorHandlers ="
      , "  [" ++ (if null callbacks then "" else " " ++ intercalate "\n  , " callbacks)
      , "  ]"
      ]
      where
        callbacks =
          [ "(" ++ show (errorScope plan) ++ ", FrameworkRuntime.ErrorHandler " ++ show (errorEffect plan)
              ++ "\n      (\\failure -> case (FrameworkRuntime.origin failure, FrameworkRuntime.detail failure) of"
              ++ concatMap (("\n        " ++) . matchCase) (errorMatches plan)
              ++ "\n        _ -> False)"
              ++ "\n      (" ++ methodReference (errorDetect plan) ++ ") (" ++ methodReference (errorResolve plan) ++ "))"
          | plan <- unitErrors unit ]
        methodReference = maybe "Nothing" ("Just " ++)
        matchCase (RaisedBy selectedHandler) = "(_, FrameworkGenerated." ++ handlerFailure selectedHandler ++ ") -> True"
        matchCase (ScopeFaultIn selectedEffect) = "(" ++ show selectedEffect ++ ", FrameworkGenerated.ScopeBindingError _) -> True"
        matchCase (ContextFaultIn selectedEffect) = "(" ++ show selectedEffect ++ ", FrameworkGenerated.ContextBindingError _) -> True"


-- 只渲染绑定中已解析的 raw 形状，不重新查询 Input 注册。
rawExpression :: RawSource String -> String
rawExpression (RawList method) = method
rawExpression (RawStream method) = "(: []) <$> " ++ method

-- 追加代码需要的扩展；手写文件自己的扩展照常生效。
copyExtensions :: [String]
copyExtensions =
  [ "ConstraintKinds", "DataKinds", "FlexibleContexts", "FlexibleInstances", "GeneralizedNewtypeDeriving"
  , "KindSignatures", "MultiParamTypeClasses", "ScopedTypeVariables", "TypeApplications", "UndecidableInstances" ]

-- 只改模块名、导出表并补充导入；方法体与 instance 原样保留。
copyModule :: String -> String -> [String] -> String -> HsModule GhcPs -> Either String String
copyModule namespace generatedName extraExports source parsed = do
  moduleName <- maybe (Left "Handlers.hs must declare its module") Right (hsmodName parsed)
  rename <- replace (getLocA moduleName) generatedName
  exports <- case hsmodExports parsed of
    Just names -> do
      (start, _) <- range (getLocA names)
      pure [(start + 1, start + 1, intercalate ", " extraExports ++ if null (unLoc names) then "" else ", ")]
    Nothing -> pure []
  firstImport <- case hsmodImports parsed of
    first : _ -> Right first
    [] -> Left "Handlers.hs must import the generated handler contracts"
  (importStart, _) <- range (getLocA firstImport)
  let imports = (importStart, importStart,
        "import qualified Framework.Generated as FrameworkRuntime\n"
        ++ "import qualified " ++ namespace ++ ".Generated.Effects as FrameworkGenerated\n"
        ++ "import qualified Control.Monad.IO.Class as FrameworkIO\n"
        ++ "import qualified Data.Proxy as FrameworkProxy\n"
        ++ "import qualified GHC.TypeLits as FrameworkTypes\n"
        ++ "import " ++ namespace ++ ".Types\n")
  pure (foldr apply source (sortOn (\(start, _, _) -> start) (rename : imports : exports)))
  where
    apply (start, end, replacement) remaining =
      take start remaining ++ replacement ++ drop end remaining
    range (RealSrcSpan span _) = Right
      (sourceOffset source (srcSpanStartLine span) (srcSpanStartCol span),
       sourceOffset source (srcSpanEndLine span) (srcSpanEndCol span))
    range _ = Left "Handler source has no concrete location"
    replace location replacement = do
      (start, end) <- range location
      pure (start, end, replacement)
