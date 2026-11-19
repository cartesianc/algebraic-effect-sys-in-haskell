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

-- Generated/Handlers 导出的名字：全部 effect 方法与登记表。
handlerExports :: Unit -> [String]
handlerExports unit = allMethods unit ++ ["newScopeHandlers", "scopeCleanups", "errorHandlers", "contextInjections", "streamContextInjections"]

hasMiddleware :: Unit -> Bool
hasMiddleware unit = any ((== MiddlewareOperation) . bindingOperation) (unitBindings unit)

-- 首次生成尚无 Handlers.hs 时只给出指纹，编写 Handlers.hs 后重新生成；原文件始终保留，只有副本进入运行导入链。
renderHandlers :: Unit -> Maybe HandlerSource -> Either String String
renderHandlers unit loaded = do
  let generatedName = unitNamespace unit ++ ".Generated.Handlers"
      sourceFingerprint = fmap (show . fingerprintString . handlerText) loaded
      extraExports = "handlerSourceFingerprint" : handlerExports unit
      extensions = copyExtensions ++ (if hasMiddleware unit then middlewareExtensions else [])
  generated <- case loaded of
    Nothing -> pure ("module " ++ generatedName ++ " (handlerSourceFingerprint) where\n")
    Just source -> copyModule (unitNamespace unit) generatedName extraExports (handlerText source) (handlerModule source)
  pure ("-- 自动生成的编译副本；请修改上级 Handlers.hs 后重新生成。\n"
        ++ concat ["{-# LANGUAGE " ++ extension ++ " #-}\n" | extension <- extensions]
        ++ generated
        ++ "\n-- 记录本编译副本实际使用的手写源码；启动前检查，避免执行过期方法体。\n"
        ++ "handlerSourceFingerprint :: Maybe String\n"
        ++ "handlerSourceFingerprint = " ++ show sourceFingerprint ++ "\n"
        ++ (if isJust loaded then support unit else ""))

-- 生成区的装配：effect 标签、handler 能力的实例与 effect 方法。
-- 注入 v5（2026-11-19）：生成入口把原子 action 交给 Root.super；hooks 由挂载决定。
-- 有捕获的 super 管理进入与成功返回，raw、raise 在 action 内调用 captureAt @hooks，
-- 它的实例按类型级列表逐个展开到各 Middleware；GHC 在编译期按挂载登记的列表选定实例，入口只有一份，运行时不分发。
support :: Unit -> String
support unit = unlines (supportHeader ++ captureClasses ++ rootInstances ++ concatMap raisesInstance ordinaryHandlers ++ routeInstances ++ rawInstances
    ++ endInstances ++ concatMap entryDefinitions (map Prototype.effectName (effectPrototypes unit)))
    ++ scopeHandlers ++ scopeCleanups ++ errorHandlers
    ++ injectionTable ContextRequest "contextInjections"
    ++ injectionTable ContextStream "streamContextInjections"
  where
    hooked = hasMiddleware unit
    -- 标签与调用的写法：有 Middleware 时带 hooks。
    tag effect = if hooked then "(At hooks " ++ effect ++ ")" else "(At " ++ effect ++ ")"
    runner effect = if hooked then "runAt @hooks @" ++ show effect else "runAt @" ++ show effect
    call method = if hooked then method ++ " @hooks" else method
    context = if hooked then "Captures hooks => " else ""
    signature resultType = if hooked
      then "forall hooks. Captures hooks => FrameworkGenerated.App " ++ resultType
      else "FrameworkGenerated.App " ++ resultType
    tableSignature = if hooked then "forall hooks. Captures hooks => " else ""
    middlewareBindings = [binding | binding <- unitBindings unit, bindingOperation binding == MiddlewareOperation]
    middlewareHandlers = map bindingHandler middlewareBindings
    ordinaryHandlers = filter (`notElem` middlewareHandlers) (unitHandlers unit)
    capture kind event = "captureAt @hooks FrameworkRuntime." ++ show kind ++ " (" ++ event ++ ") >> "
    atomicCall handler' = "(FrameworkRuntime.super " ++ show handler' ++ " FrameworkGenerated." ++ handler' ++ ")"
    supportHeader =
      [ ""
      , "-- 以下由 gen 生成。每个 effect 一个类型标签：handler 在标签下执行，"
      , "-- 读取、raw 与错误按标签在编译期解析到这个 effect 的来源，不改写 handler 方法体。"
      , if hooked
          then "newtype At (hooks :: [FrameworkTypes.Symbol]) (effect :: FrameworkTypes.Symbol) value = At { runAt :: FrameworkGenerated.App value }"
          else "newtype At (effect :: FrameworkTypes.Symbol) value = At { runAt :: FrameworkGenerated.App value }"
      , "  deriving (Functor, Applicative, Monad, FrameworkIO.MonadIO)"
      , ""
      ]
    -- Root 级入口约束：Captures hooks 把一次调用点交给列表中的每个 Middleware；每个 Middleware 按 intercept 取舍类别。
    -- Middleware handler 在自己的 Hook 标签下执行，那里的调用点不改写，它自己不再被捕获。
    captureClasses
      | not hooked = []
      | otherwise =
          [ "-- Root 级入口约束：hooks 是覆盖本次挂载的 Middleware，按注册顺序；空列表不做任何事。"
          , "class Captures (hooks :: [FrameworkTypes.Symbol]) where"
          , "  captureAt :: FrameworkRuntime.EffectKind -> FrameworkRuntime.HookEvent -> FrameworkGenerated.App ()"
          , ""
          , "instance Captures '[] where"
          , "  captureAt _ _ = pure ()"
          , ""
          , "instance (Captured hook, Captures hooks) => Captures (hook ': hooks) where"
          , "  captureAt kind event = capturedAt @hook kind event >> captureAt @hooks kind event"
          , ""
          , "class Captured (hook :: FrameworkTypes.Symbol) where"
          , "  capturedAt :: FrameworkRuntime.EffectKind -> FrameworkRuntime.HookEvent -> FrameworkGenerated.App ()"
          , ""
          , "-- Middleware 的标签：handler 在这里执行，用 hooked* 读本次调用点捕获的 (handler 名, 值)。"
          , "newtype Hook (effect :: FrameworkTypes.Symbol) value = Hook { runHook :: FrameworkRuntime.HookApp FrameworkGenerated.ContextValues FrameworkGenerated.Errors value }"
          , "  deriving (Functor, Applicative, Monad, FrameworkIO.MonadIO)"
          , "" ] ++ concat
          [ [ "instance Captured " ++ show effect ++ " where"
            , "  capturedAt kind event"
            , "    | kind `elem` [" ++ intercalate ", " ["FrameworkRuntime." ++ show kind | kind <- kinds] ++ "] = () <$ " ++ bindingMethod binding ++ " event"
            , "    | otherwise = pure ()"
            , ""
            , "instance FrameworkRuntime.Hooks (Hook " ++ show effect ++ ") where"
            , "  hookedEnter = Hook FrameworkRuntime.hookEnter"
            , "  hookedOutput = Hook FrameworkRuntime.hookOutput"
            , "  hookedRaw = Hook FrameworkRuntime.hookRaw"
            , "  hookedError = Hook FrameworkRuntime.hookError"
            , ""
            , "instance FrameworkRuntime.Raises FrameworkGenerated." ++ handlerError handler' ++ " (Hook " ++ show effect ++ ") where"
            , "  raise (FrameworkGenerated." ++ handlerError handler' ++ " description) = Hook (FrameworkRuntime.liftHookApp"
            , "    (FrameworkRuntime.failEffect " ++ show effect ++ " FrameworkGenerated." ++ handlerFailure handler' ++ " description))"
            , ""
            , bindingMethod binding ++ " :: FrameworkRuntime.HookEvent -> FrameworkGenerated.App [String]"
            , bindingMethod binding ++ " event = FrameworkRuntime.runHookApp event (runHook @" ++ show effect ++ " " ++ atomicCall handler' ++ ")"
            , "" ]
          | binding <- middlewareBindings
          , let effect = bindingEffect binding
                handler' = bindingHandler binding
                kinds = [kind | (owner, selected) <- unitMiddleware unit, owner == effect, kind <- selected] ]
    -- 标签决定原子调用的装配。Middleware 自身使用直接实例，避免递归捕获。
    rootInstances
      | not hooked = ["instance FrameworkRuntime.Root (At effect) value", ""]
      | otherwise = ["instance FrameworkRuntime.Root (Hook effect) value", ""] ++ concat
          [ case captureKind of
              Nothing -> ["instance FrameworkRuntime.Root " ++ tag (show effect) ++ " value", ""]
              Just kind ->
                [ "instance Captures hooks => FrameworkRuntime.Root " ++ tag (show effect) ++ " [String] where"
                , "  super name (At action) = At (FrameworkRuntime.superWith (captureAt @hooks FrameworkRuntime."
                    ++ show kind ++ ") name action)"
                , "" ]
          | (effect, captureKind) <- nub [(bindingEffect b, bindingCaptureKind b) | b <- unitBindings unit,
                                            bindingOperation b /= MiddlewareOperation] ]
    -- 有 Middleware 时，被拦截类别的 effect 按标签逐个给出 raise：先把 (handler 名, 描述) 交给 captureAt，再以原失败退出。
    raisesInstance handler'
      | hooked = concat
          [ [ "instance " ++ context ++ "FrameworkRuntime.Raises FrameworkGenerated." ++ handlerError handler' ++ " " ++ tag (show effect) ++ " where"
            , "  raise (FrameworkGenerated." ++ handlerError handler' ++ " description) = At ("
                ++ maybe "" (\kind -> capture kind ("FrameworkRuntime.ErrorEvent " ++ show handler' ++ " description")) captureKind
                ++ "FrameworkRuntime.failEffect " ++ show effect ++ " FrameworkGenerated." ++ handlerFailure handler' ++ " description)"
            , "" ]
          | (effect, captureKind) <- nub [(bindingEffect b, bindingCaptureKind b) | b <- unitBindings unit, bindingHandler b == handler'] ]
      | otherwise =
          [ "instance FrameworkTypes.KnownSymbol effect => FrameworkRuntime.Raises FrameworkGenerated." ++ handlerError handler' ++ " (At effect) where"
          , "  raise (FrameworkGenerated." ++ handlerError handler' ++ " description) = At (FrameworkRuntime.failEffect"
          , "    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) FrameworkGenerated."
              ++ handlerFailure handler' ++ " description)"
          , ""
          ]
    -- demands 按表示类型路由到资产的读取入口；持续与有限调用都读声明的 T，分支契约投影构造器字段。
    routeInstances = concat
      [ [ "instance FrameworkRuntime.Reads (" ++ renderValueType "FrameworkRuntime." "FrameworkGenerated." (routeType route) ++ ") "
            ++ tag (show (routeEffect route)) ++ " where"
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
    -- raw 的捕获点：读取方 handler 与读到的值；类别取被读取的那次调用的类别。
    rawInstances = concat
      [ [ "instance " ++ context ++ "FrameworkRuntime.Raw " ++ tag (show (bindingEffect binding)) ++ " where"
        , "  raw = At (" ++ capturedRaw binding (rawExpression (callSource source)) ++ ")"
        , "" ]
      | binding <- unitBindings unit, Just source <- [bindingRaw binding] ]
    callSource (RawList method) = RawList (call method)
    callSource (RawStream method) = RawStream (call method)
    capturedRaw binding reading = case bindingRawKind binding of
      Just kind ->
        reading ++ " >>= \\value -> " ++ capture kind ("FrameworkRuntime.RawEvent " ++ show (bindingHandler binding) ++ " value") ++ "pure value"
      _ -> reading
    -- 能力已经由组合计算确定；这里只为对应标签输出实例，不重新解释 effect 类别或 demands。
    endInstances = concat
      [ [ "instance FrameworkRuntime.StreamEnds " ++ tag (show selectedName) ++ " where"
        , "  streamEnd = At FrameworkRuntime.endSource"
        , "" ]
      | selectedName <- map Prototype.effectName (effectPrototypes unit), hasCapability selectedName EndsSource ]
      ++ concat
      [ [ "instance FrameworkRuntime.EndsStream " ++ tag (show selectedName) ++ " where"
        , "  endStream = At FrameworkRuntime.endSubscription"
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
          let action = runner selectedName ++ " " ++ atomicCall handler'
          in case bindingOperation binding of
               PublishAsset contract -> "(FrameworkGenerated." ++ contract ++ " <$> " ++ action ++ ")"
               _ -> action
        scoped = "FrameworkRuntime.withScopeDependencies " ++ show (Prototype.effectScopes (protoOf unit selectedName))
        entered = scoped ++ " . FrameworkRuntime.enterHandler " ++ show selectedName
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
      [ method ++ " :: " ++ (if polymorphic then signature else ("FrameworkGenerated.App " ++)) (parenthesized resultType)
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
    -- 收尾表随 hooks 多态：开启它的挂载按哪组 Middleware 安装，收尾就调用同一组的 close。
    scopeCleanups = unlines
      [ ""
      , "-- SDK 自动收尾入口；安装时不关闭资源。"
      , "scopeCleanups :: " ++ tableSignature ++ "[(String, FrameworkGenerated.App ())]"
      , "scopeCleanups ="
      , "  [" ++ (if null callbacks then "" else " " ++ intercalate "\n  , " callbacks)
      , "  ]"
      ]
      where
        callbacks =
          [ "(" ++ show (scopeEffect plan) ++ ", () <$ " ++ call closing ++ ")"
          | plan <- unitScopes unit, Just closing <- [scopeCleanup plan] ]
    -- 原子句柄的输出交给挂在它下面的 parser：键是句柄的 effect 方法名。
    injectionTable role tableName = unlines
      [ ""
      , "-- 挂在原子句柄下的 Context：句柄的输出交给它的 parser 解析并发布为资产；没有挂接时输出被丢弃。"
      , tableName ++ " :: " ++ tableSignature ++ "[(String, [(String, FrameworkGenerated.App ())])]"
      , tableName ++ " ="
      , "  [" ++ (if null entries then "" else " " ++ intercalate "\n  , " entries)
      , "  ]"
      ]
      where
        connections = [connection | connection <- assemblyOutputs (unitAssembly unit), outputRole connection == role]
        entries =
          [ "(" ++ show anchor ++ ", [" ++ intercalate ", "
              ["(" ++ show (outputProducer connection) ++ ", () <$ " ++ call (outputParser connection) ++ ")"
              | connection <- connections, outputAnchor connection == anchor] ++ "])"
          | anchor <- nub (map outputAnchor connections) ]
    -- Error 只指向 scope：按 handles 匹配故障，detect／resolve 是生成的 effect 方法；Error 不被拦截，按空列表执行。
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
        methodReference = maybe "Nothing" (\method -> "Just " ++ (if hooked then "(" ++ method ++ " @'[])" else method))
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
