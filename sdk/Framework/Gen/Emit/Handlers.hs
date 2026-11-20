{-# LANGUAGE DuplicateRecordFields #-}

-- 输出 Generated/Handlers.hs：手写 Handlers.hs 的编译副本（方法体原样保留），后接 gen 生成的装配——
-- 每个 effect 一个类型标签 Wrap，按标签的 Reads／Raw／Raises 实例，“驱动 → Input → 方法体”的 effect 方法，
-- 以及 scope 与 Error 的登记表。挂接的 Context 与自动收尾的 close 直接写在入口包装上。只渲染绑定阶段定下的事实。
module Framework.Gen.Emit.Handlers (renderHandlers) where

import Data.List (intercalate, nub, sortOn)
import Framework.Gen.Plan
import Framework.Gen.Emit.Types (renderValueType)
import Framework.Gen.Names (HandlerNames, entryName, helperName, handlerError, handlerFailure)
import Framework.Gen.Frontend.Source (HandlerSource(..), sourceOffset)
import Framework.Language.Registration
import Framework.Prototype.Graph (MethodRole(..))
import qualified Framework.Prototype as Prototype
import GHC (GhcPs)
import GHC.Fingerprint (fingerprintString)
import GHC.Hs
import GHC.Parser.Annotation (getLocA)
import GHC.Types.SrcLoc

hasMiddleware :: Unit -> Bool
hasMiddleware unit = any ((== MiddlewareOperation) . bindingOperation) (unitBindings unit)

-- 首次生成尚无 Handlers.hs 时只给出指纹，编写 Handlers.hs 后重新生成；原文件始终保留，只有副本进入运行导入链。
renderHandlers :: HandlerNames -> Unit -> Maybe HandlerSource -> Either String String
renderHandlers names unit loaded = do
  let generatedName = unitNamespace unit ++ ".Generated.Handlers"
      sourceFingerprint = fmap (show . fingerprintString . handlerText) loaded
      fingerprint = helperName names "handlerSourceFingerprint"
      extraExports = fingerprint : map (entryName names) (allMethods unit) ++ map (helperName names) ["newScopeHandlers", "errorHandlers"]
      extensions = copyExtensions ++ (if hasMiddleware unit then middlewareExtensions else [])
  generated <- case loaded of
    Nothing -> pure ("module " ++ generatedName ++ " (" ++ fingerprint ++ ") where\n")
    Just source -> copyModule (unitNamespace unit) generatedName extraExports (handlerText source) (handlerModule source)
  pure ("-- 自动生成的编译副本；请修改上级 Handlers.hs 后重新生成。\n"
        ++ concat ["{-# LANGUAGE " ++ extension ++ " #-}\n" | extension <- extensions]
        ++ generated
        ++ "\n-- 记录本编译副本实际使用的手写源码；启动前检查，避免执行过期方法体。\n"
        ++ fingerprint ++ " :: Maybe String\n"
        ++ fingerprint ++ " = " ++ show sourceFingerprint ++ "\n"
        ++ maybe "" (const (support names unit)) loaded)

-- 生成区的装配：effect 标签、handler 能力的实例与 effect 方法。
-- 注入 v6（2026-11-19）：生成入口把原子 action 交给 Root.super；hooks 由挂载决定，类别由绑定决定。
-- Injector.Super 已为每个 (列表, 类别) 选定 Middleware，这里把选择写成 Captures 实例：
-- 有捕获的 super 管理进入与成功返回，rawinput、raise 在 action 内调用 captureAt @hooks @kind。
-- GHC 在编译期按挂载登记的列表选定实例，入口只有一份，运行时不分发、不筛选。
support :: HandlerNames -> Unit -> String
support names unit = unlines (supportHeader ++ captureClasses ++ rootInstances ++ concatMap raisesInstance ordinaryHandlers ++ routeInstances ++ rawInstances
    ++ outputInstances ++ endInstances ++ concatMap entryDefinitions (map Prototype.effectName (effectPrototypes unit)))
    ++ scopeHandlers ++ errorHandlers
  where
    hooked = hasMiddleware unit
    entry = entryName names
    helper = helperName names
    wrap = helper "Wrap"
    runWrap = helper "runWrap"
    hookTag = helper "Hook"
    runHook = helper "runHook"
    captures = helper "Captures"
    captured = helper "Captured"
    captureAt = helper "captureAt"
    superWrap = helper "superWrap"
    closeWrap = helper "closeWrap"
    -- 标签与调用的写法：有 Middleware 时带 hooks。
    tag effect = methodTag effect "method"
    methodTag effect method = "(" ++ wrap ++ (if hooked then " hooks " else " ") ++ effect
      ++ (if hooked then " " ++ method else "") ++ ")"
    runner effect handler' = runWrap ++ (if hooked then " @hooks @" else " @") ++ show effect
      ++ (if hooked then " @" ++ show handler' else "")
    call method = entry method ++ if hooked then " @hooks" else ""
    context = if hooked then captured ++ " hooks => " else ""
    signature resultType = if hooked
      then "forall hooks. " ++ context ++ "FrameworkGenerated.App " ++ resultType
      else "FrameworkGenerated.App " ++ resultType
    middlewareBindings = [binding | binding <- unitBindings unit, bindingOperation binding == MiddlewareOperation]
    middlewareHandlers = map bindingHandler middlewareBindings
    ordinaryHandlers = filter (`notElem` middlewareHandlers) (unitHandlers unit)
    capture kind event = captureAt ++ " @hooks @" ++ promoted kind ++ " (" ++ event ++ ") >> "
    promoted kind = "'FrameworkRuntime." ++ show kind
    hookList hooks = "'[" ++ intercalate ", " (map show hooks) ++ "]"
    -- close 的调用点用 superClose：是否 close 由绑定的操作在生成期确定。
    atomicCall operation handler' = "(FrameworkRuntime." ++ (if operation == CloseResource then "superClose" else "super")
      ++ " " ++ show handler' ++ " FrameworkGenerated." ++ handler' ++ ")"
    supportHeader =
      [ ""
      , "-- 以下由 gen 生成。每个 effect 一个类型标签：handler 在标签下执行，"
      , "-- 读取、rawinput 与错误按标签在编译期解析到这个 effect 的来源，不改写 handler 方法体。"
      , "newtype " ++ wrap ++ (if hooked then " (hooks :: [FrameworkTypes.Symbol])" else "")
          ++ " (effect :: FrameworkTypes.Symbol)" ++ (if hooked then " (method :: FrameworkTypes.Symbol)" else "") ++ " value = " ++ wrap ++ " { " ++ runWrap ++ " :: FrameworkGenerated.App value }"
      , "  deriving (Functor, Applicative, Monad, FrameworkIO.MonadIO)"
      , ""
      ]
    -- Captures hooks kind：Injector.Super 的选择逐条写成实例，选中的 Middleware 按注册顺序同步调用。
    -- Middleware handler 在自己的 Hook 标签下执行，那里的调用点不改写，它自己不再被捕获。
    captureClasses
      | not hooked = []
      | otherwise =
          [ "-- superhandler 的静态选择：hooks 是覆盖本次挂载的 Middleware（注册顺序），kind 是捕获类别。"
          , "-- 默认方法即空选择：不捕获，super 直接执行 action。"
          , "class " ++ captures ++ " (hooks :: [FrameworkTypes.Symbol]) (kind :: FrameworkRuntime.EffectKind) where"
          , "  " ++ captureAt ++ " :: FrameworkRuntime.Operation -> FrameworkGenerated.App ()"
          , "  " ++ captureAt ++ " _ = pure ()"
          , "  " ++ superWrap ++ ", " ++ closeWrap ++ " :: String -> FrameworkGenerated.App [String] -> FrameworkGenerated.App [String]"
          , "  " ++ superWrap ++ " _ = id"
          , "  " ++ closeWrap ++ " _ = id"
          , ""
          , "-- 入口对 hooks 多态：每个被拦截的类别都有该列表的选择。"
          , "type " ++ captured ++ " hooks = (" ++ intercalate ", " [captures ++ " hooks " ++ promoted kind | kind <- selectedKinds] ++ ")"
          , "" ] ++ concatMap selectionInstance (unitSupers unit) ++
          [ ""
          , "-- Middleware 的标签：handler 在这里执行，用 hook 读取触发本次调用的 Operation。"
          , "newtype " ++ hookTag ++ " (effect :: FrameworkTypes.Symbol) value = " ++ hookTag ++ " { " ++ runHook ++ " :: FrameworkRuntime.HookApp FrameworkGenerated.ContextValues FrameworkGenerated.Errors value }"
          , "  deriving (Functor, Applicative, Monad, FrameworkIO.MonadIO)"
          , "" ] ++ concat
          [ [ "instance FrameworkRuntime.Hooks (" ++ hookTag ++ " " ++ show effect ++ ") where"
            , "  hook = " ++ hookTag ++ " FrameworkRuntime.currentOperation"
            , ""
            , "instance FrameworkRuntime.RawOutputs (" ++ hookTag ++ " " ++ show effect ++ ")"
            , ""
            , "instance FrameworkRuntime.Raises FrameworkGenerated." ++ handlerError handler' ++ " (" ++ hookTag ++ " " ++ show effect ++ ") where"
            , "  raise (FrameworkGenerated." ++ handlerError handler' ++ " description) = " ++ hookTag ++ " (FrameworkRuntime.liftHookApp"
            , "    (FrameworkRuntime.failEffect " ++ show effect ++ " FrameworkGenerated." ++ handlerFailure handler' ++ " description))"
            , ""
            , entry (bindingMethod binding) ++ " :: FrameworkRuntime.Operation -> FrameworkGenerated.App [String]"
            , entry (bindingMethod binding) ++ " event = FrameworkRuntime.runHookApp event (" ++ runHook ++ " @" ++ show effect ++ " "
                ++ atomicCall MiddlewareOperation handler' ++ ")"
            , "" ]
          | binding <- middlewareBindings
          , let effect = bindingEffect binding
                handler' = bindingHandler binding ]
    selectedKinds = nub (map selectionKind (unitSupers unit))
    middlewareMethod selected = case [bindingMethod binding | binding <- middlewareBindings, bindingEffect binding == selected] of
      method : _ -> entry method
      [] -> error ("Middleware has no hook method: " ++ selected)
    -- 一条选择一个实例；空选择沿用默认方法。只有 Scoped 有 close 的调用点。
    selectionInstance (SuperSelection hooks kind []) =
      ["instance " ++ captures ++ " " ++ hookList hooks ++ " " ++ promoted kind, ""]
    selectionInstance (SuperSelection hooks kind selected) =
      [ "instance " ++ captures ++ " " ++ hookList hooks ++ " " ++ promoted kind ++ " where"
      , "  " ++ captureAt ++ " event = " ++ concatMap (\hook -> middlewareMethod hook ++ " event >> ") selected ++ "pure ()" ]
      ++ [ "  " ++ superWrap ++ " = FrameworkRuntime.superWith (" ++ captureAt ++ " @" ++ hookList hooks ++ " @" ++ promoted kind ++ ")"
         | kind /= StreamKind ]
      ++ [ "  " ++ closeWrap ++ " = FrameworkRuntime.superClosing (" ++ captureAt ++ " @" ++ hookList hooks ++ " @" ++ promoted kind ++ ")"
         | kind == ScopedKind ]
      ++ [""]
    -- 标签决定原子调用的装配。Middleware 自身使用直接实例，避免递归捕获。
    rootInstances
      | not hooked = ["instance FrameworkRuntime.Root " ++ tag "effect" ++ " value", ""]
      | otherwise = ["instance FrameworkRuntime.Root (" ++ hookTag ++ " effect) value", ""] ++ concat
          [ case captureKind of
              Nothing -> ["instance FrameworkRuntime.Root " ++ tag (show effect) ++ " value", ""]
              Just StreamKind ->
                [ "instance " ++ captures ++ " hooks " ++ promoted StreamKind ++ " => FrameworkRuntime.Root " ++ tag (show effect) ++ " () where"
                , "  super name (" ++ wrap ++ " action) = " ++ wrap ++ " ("
                    ++ capture StreamKind "FrameworkRuntime.Enter name" ++ "action)"
                , "" ]
              Just kind ->
                [ "instance " ++ captures ++ " hooks " ++ promoted kind ++ " => FrameworkRuntime.Root " ++ tag (show effect) ++ " [String] where"
                , rootMethod "super" superWrap kind ]
                ++ [ rootMethod "superClose" closeWrap kind | kind == ScopedKind ]
                ++ [ "" ]
          | (effect, captureKind) <- nub [(bindingEffect b, bindingCaptureKind b) | b <- unitBindings unit,
                                            bindingOperation b /= MiddlewareOperation] ]
    rootMethod method dispatch kind = "  " ++ method ++ " name (" ++ wrap ++ " action) = " ++ wrap
      ++ " (" ++ dispatch ++ " @hooks @" ++ promoted kind ++ " name action)"
    -- 有 Middleware 时，被拦截类别的 effect 按标签逐个给出 raise：先把 (handler 名, 描述) 交给 captureAt，再以原失败退出。
    raisesInstance handler'
      | hooked = concat
          [ [ "instance " ++ context ++ "FrameworkRuntime.Raises FrameworkGenerated." ++ handlerError handler' ++ " " ++ tag (show effect) ++ " where"
            , "  raise (FrameworkGenerated." ++ handlerError handler' ++ " description) = " ++ wrap ++ " ("
                ++ maybe "" (\kind -> capture kind ("FrameworkRuntime.Raise " ++ show handler' ++ " description")) captureKind
                ++ "FrameworkRuntime.failEffect " ++ show effect ++ " FrameworkGenerated." ++ handlerFailure handler' ++ " description)"
            , "" ]
          | (effect, captureKind) <- nub [(bindingEffect b, bindingCaptureKind b) | b <- unitBindings unit, bindingHandler b == handler'] ]
      | otherwise =
          [ "instance FrameworkTypes.KnownSymbol effect => FrameworkRuntime.Raises FrameworkGenerated." ++ handlerError handler' ++ " " ++ tag "effect" ++ " where"
          , "  raise (FrameworkGenerated." ++ handlerError handler' ++ " description) = " ++ wrap ++ " (FrameworkRuntime.failEffect"
          , "    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) FrameworkGenerated."
              ++ handlerFailure handler' ++ " description)"
          , ""
          ]
    -- demands 按表示类型路由到资产的读取入口；持续与有限调用都读声明的 T，分支契约投影构造器字段。
    routeInstances = concat
      [ [ "instance FrameworkRuntime.Reads (" ++ renderValueType "FrameworkRuntime." "FrameworkGenerated." (routeType route) ++ ") "
            ++ tag (show (routeEffect route)) ++ " where"
        , "  require = " ++ wrap ++ " (" ++ routeExpression route ++ ")"
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
        reader = entry (routeReader route)
        unwrap selectedContract = "(\\(FrameworkGenerated." ++ selectedContract ++ " value) -> value)"
    -- rawinput 的捕获点：读取方 handler 与读到的值；类别取被读取的那次调用的类别。
    rawInstances = concat
      [ [ "instance " ++ context ++ "FrameworkRuntime.Raw " ++ tag (show (bindingEffect binding)) ++ " where"
        , "  rawinput = " ++ wrap ++ " (" ++ capturedRaw binding (rawExpression (callSource source)) ++ ")"
        , "" ]
      | binding <- unitBindings unit, Just source <- [bindingRaw binding] ]
    callSource (RawList method) = RawList (call method)
    callSource (RawStream method) = RawStream method
    capturedRaw binding reading = case bindingRawKind binding of
      Just kind ->
        reading ++ " >>= \\value -> " ++ capture kind ("FrameworkRuntime.RawInput " ++ show (bindingHandler binding) ++ " value") ++ "pure value"
      _ -> reading
    -- 能力已经由组合计算确定；这里只为对应标签输出实例，不重新解释 effect 类别或 demands。
    -- Scoped 的 open 和 close 共用 effect 标签，method 标签区分两处输出的业务名称。
    -- Middleware 自身的 Hook 标签用 RawOutputs 的默认实现，输出不会再进入 hook。
    outputInstances
      | not hooked = ["instance FrameworkRuntime.RawOutputs " ++ tag "effect", ""]
      | otherwise = concat (nub
          [ [ "instance " ++ context ++ "FrameworkRuntime.RawOutputs " ++ methodTag (show (bindingEffect binding)) (show handler') ++ " where"
            , "  rawoutput value = " ++ wrap ++ " ("
                ++ maybe "" (\kind -> capture kind ("FrameworkRuntime.RawOutput " ++ show handler' ++ " value"))
                     (bindingCaptureKind binding)
                ++ "pure value)"
            , "" ]
          | binding <- unitBindings unit, WritesRaw `elem` bindingCapabilities binding
          , bindingOperation binding /= MiddlewareOperation, let handler' = bindingHandler binding ])
    endInstances = concat
      [ [ "instance " ++ context ++ "FrameworkRuntime.Emits " ++ tag (show (bindingEffect binding)) ++ " where"
        , "  rawemit text = " ++ wrap ++ " ("
            ++ maybe "" (\kind -> capture kind ("FrameworkRuntime.RawEmit " ++ show (bindingHandler binding) ++ " text"))
                 (bindingCaptureKind binding)
            ++ "FrameworkRuntime.emitToParser text)"
        , "" ]
      | binding <- unitBindings unit, EmitsItem `elem` bindingCapabilities binding ]
      ++ concat
      [ [ "instance FrameworkRuntime.StreamEnds " ++ tag (show selectedName) ++ " where"
        , "  streamEnd = " ++ wrap ++ " FrameworkRuntime.endSource"
        , "" ]
      | selectedName <- map Prototype.effectName (effectPrototypes unit), hasCapability selectedName EndsSource ]
      ++ concat
      [ [ "instance FrameworkRuntime.EndsStream " ++ tag (show selectedName) ++ " where"
        , "  endStream = " ++ wrap ++ " FrameworkRuntime.endSubscription"
        , "" ]
      | selectedName <- map Prototype.effectName (effectPrototypes unit), hasCapability selectedName EndsSubscription ]
    hasCapability selectedName capability = or
      [ capability `elem` bindingCapabilities binding
      | binding <- unitBindings unit, bindingEffect binding == selectedName ]

    -- effect 方法：外层包装由类别决定；方法体先驱动、再执行 Input 前驱，最后在本 effect 的标签下执行 handler。
    entryDefinitions selectedName =
      [ line
      | binding <- unitBindings unit, bindingEffect binding == selectedName, bindingOperation binding /= MiddlewareOperation
      , let method = bindingMethod binding
            handler' = bindingHandler binding
      , line <- definition True method (renderValueType "FrameworkRuntime." "FrameworkGenerated." (bindingResult binding)) (wrapper binding)
          (intercalate " >> " (map call (bindingCalls binding) ++ [handlerCall binding handler'])) ]
      ++ concat [ readerDefinition reader | reader <- unitReaders unit, readerEffect reader == selectedName ]
      where
        handlerCall binding handler' =
          let action = runner selectedName handler' ++ " " ++ atomicCall (bindingOperation binding) handler'
          in case bindingOperation binding of
               PublishAsset contract -> "(FrameworkGenerated." ++ contract ++ " <$> " ++ action ++ ")"
               _ -> action
        scoped = "FrameworkRuntime.withScopeDependencies " ++ show (Prototype.effectScopes (protoOf unit selectedName))
        entered = scoped ++ " . FrameworkRuntime.enterHandler " ++ show selectedName
        wrapper binding = rootWrapper selectedName ++ " . " ++ case bindingOperation binding of
          -- 先进入本 scope，再检查其上游；失效后的 close 仍可读取自己的 Context 以收尾。
          OpenResource -> scopeWrapper binding "openScope " (" " ++ cleanupOf selectedName)
          CloseResource -> scopeWrapper binding "closeScope " ""
          AtomicOperation -> "FrameworkRuntime.atomicHandle " ++ show (bindingMethod binding) ++ anchoredOf binding ++ " . " ++ entered
          SourceStep -> entered
          PureOperation -> scoped
          PublishAsset _ -> scoped ++ " . FrameworkRuntime.callContext " ++ show selectedName
            ++ "\n    (\\value bindings -> bindings { FrameworkGenerated.bound" ++ selectedName ++ " = Just value })"
          ErrorOperation -> entered
          MiddlewareOperation -> entered
        scopeWrapper binding operation cleanup = "FrameworkRuntime.atomicScope " ++ show (bindingMethod binding) ++ anchoredOf binding
          ++ " . FrameworkRuntime." ++ operation ++ show selectedName ++ " FrameworkGenerated.ScopeBindingError" ++ cleanup ++ " . " ++ entered
    -- 挂在原子句柄下的 parser：句柄成功交出时，普通挂接注入后吞错，持续挂接按本次执行位置筛选后传播失败。
    anchoredOf binding = " " ++ connectionsOf ContextRequest ++ " " ++ connectionsOf ContextStream
      where
        connectionsOf role = "[" ++ intercalate ", "
          [ "(" ++ show (outputProducer connection) ++ ", () <$ " ++ call (outputParser connection) ++ ")"
          | connection <- assemblyOutputs (unitAssembly unit)
          , outputRole connection == role, outputAnchor connection == bindingMethod binding ] ++ "]"
    -- 自动收尾：open 带上本 scope 的 close，在同一 Middleware 列表下执行。
    cleanupOf selectedName = case [closing | plan <- unitScopes unit, scopeEffect plan == selectedName, Just closing <- [scopeCleanup plan]] of
      closing : _ -> "(Just (() <$ " ++ call closing ++ "))"
      [] -> "Nothing"
    rootWrapper selectedName = "FrameworkRuntime.withErrorPath " ++ show (Prototype.effectNearestScopes (protoOf unit selectedName))
      ++ " . FrameworkRuntime.handleFailure"
    -- readT 与 streamT 的模式由组合计算选定，渲染器只输出相应的读取入口；读取不执行 handler，不随 hooks 变化。
    readerDefinition reader
      | readerContinuous reader = definition False method
          ("FrameworkGenerated." ++ contractType) (rootWrapper selectedName)
          ("FrameworkRuntime.readStreamContext " ++ show selectedName ++ " FrameworkGenerated.ContextBindingError"
            ++ " FrameworkGenerated.bound" ++ selectedName)
      | otherwise = definition False method ("FrameworkGenerated." ++ contractType) (rootWrapper selectedName)
          ("FrameworkRuntime.readContext " ++ show selectedName ++ " FrameworkGenerated.ContextBindingError "
             ++ "FrameworkGenerated.bound" ++ selectedName)
      where
        selectedName = readerEffect reader
        method = readerMethod reader
        contractType = readerContract reader
    definition polymorphic method resultType wrapper body =
      [ entry method ++ " :: " ++ (if polymorphic then signature else ("FrameworkGenerated.App " ++)) (parenthesized resultType)
      , entry method ++ " = (" ++ wrapper ++ ") $"
      , "  " ++ body
      , "" ]


    -- 控制对象由生成的 handler 模块创建；不同链引用同份对象，不预执行 open。
    scopeHandlers = unlines
      [ "-- SDK 内部：scope 按上游到下游登记，退出时逆序收尾；创建不执行业务方法。"
      , helper "newScopeHandlers" ++ " :: IO [FrameworkRuntime.ScopeHandler FrameworkGenerated.ContextValues FrameworkGenerated.Errors]"
      , helper "newScopeHandlers" ++ " = sequence"
      , "  [" ++ (if null registered then "" else " " ++ intercalate "\n  , " registered)
      , "  ]"
      ]
      where
        registered =
          [ "FrameworkRuntime.newScopeHandler " ++ show (scopeEffect plan) ++ " " ++ show (scopeInputs plan)
              ++ " (" ++ show (scopeResource plan) ++ ")"
          | plan <- unitScopes unit ]
    -- Error 只指向 scope：按 handles 匹配故障，detect／resolve 是生成的 effect 方法；Error 不被拦截，按空列表执行。
    errorHandlers = unlines
      [ ""
      , "-- Error 回调登记：按 handles 匹配故障的 handler 与协议分类；关联 scope 由 Input 链推导。"
      , helper "errorHandlers" ++ " :: [(Maybe String, FrameworkRuntime.ErrorHandler FrameworkGenerated.Errors FrameworkGenerated.App)]"
      , helper "errorHandlers" ++ " ="
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
        methodReference = maybe "Nothing" (\method -> "Just " ++ (if hooked then "(" ++ entry method ++ " @'[])" else entry method))
        matchCase (RaisedBy selectedHandler) = "(_, FrameworkGenerated." ++ handlerFailure selectedHandler ++ ") -> True"
        matchCase (ScopeFaultIn selectedEffect) = "(" ++ show selectedEffect ++ ", FrameworkGenerated.ScopeBindingError _) -> True"
        matchCase (ContextFaultIn selectedEffect) = "(" ++ show selectedEffect ++ ", FrameworkGenerated.ContextBindingError _) -> True"


-- 只渲染绑定中已解析的 rawinput 形状，不重新查询 Input 注册。
rawExpression :: RawSource String -> String
rawExpression (RawList method) = method
rawExpression (RawStream _) = "FrameworkRuntime.emittedInput"

-- 追加代码需要的扩展；手写文件自己的扩展照常生效。
copyExtensions :: [String]
copyExtensions =
  [ "ConstraintKinds", "DataKinds", "FlexibleContexts", "FlexibleInstances", "GeneralizedNewtypeDeriving"
  , "KindSignatures", "MultiParamTypeClasses", "ScopedTypeVariables", "TypeApplications", "UndecidableInstances" ]

-- 入口对 hooks 多态（类型只出现在约束里）、类型级列表的实例展开。
middlewareExtensions :: [String]
middlewareExtensions = ["AllowAmbiguousTypes", "TypeOperators"]

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
