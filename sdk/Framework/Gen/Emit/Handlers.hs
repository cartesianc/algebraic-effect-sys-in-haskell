{-# LANGUAGE DuplicateRecordFields #-}

-- 输出 Generated/Handlers.hs：手写 Handlers.hs 的编译副本（方法体原样保留），后接 gen 生成的装配——
-- 每个 effect 一个类型标签 Wrap，按标签的 Reads／Raw／Raises 实例，“驱动 → Input → 方法体”的 effect 方法，
-- 以及 scope 与 Error 的登记表。挂接的 Context 与自动收尾的 close 直接写在入口包装上。只渲染绑定阶段定下的事实。
module Framework.Gen.Emit.Handlers (renderHandlers) where

import Data.Char (isAlphaNum, isSpace)
import Data.List (intercalate, isPrefixOf, nub, sortOn, stripPrefix)
import Data.Maybe (fromMaybe)
import Framework.Gen.Plan
import Framework.Gen.Emit.Types (renderValueType, specialisation)
import Framework.Gen.Names (HandlerNames, entryName, helperName, handlerFailure)
import Framework.Gen.Frontend.Source (HandlerSource(..), sourceOffset)
import Framework.Language.Registration
import Framework.Prototype.Graph (MethodRole(..))
import qualified Framework.Prototype as Prototype
import GHC (GhcPs, moduleNameString)
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
      extraExports = fingerprint : map (entryName names) (allMethods unit ++ historyEntries unit) ++ map (helperName names) ["newScopeHandlers", "errorHandlers"]
      extensions = copyExtensions ++ (if hasMiddleware unit then middlewareExtensions else [])
      supplied = maybe [] (leadingExtensions extensions . handlerText) loaded
      qualifiers = maybe longQualifiers (chooseQualifiers . handlerModule) loaded
  generated <- case loaded of
    Nothing -> pure ("module " ++ generatedName ++ " (" ++ fingerprint ++ ") where\n")
    Just source -> copyModule qualifiers (unitNamespace unit) generatedName extraExports (handlerText source) (handlerModule source)
  pure (specialisation ++ "\n-- 自动生成的编译副本；请修改上级 Handlers.hs 后重新生成。\n"
        ++ concat ["{-# LANGUAGE " ++ extension ++ " #-}\n" | extension <- extensions, extension `notElem` supplied]
        ++ generated
        ++ "\n-- 记录本编译副本实际使用的手写源码；启动前检查，避免执行过期方法体。\n"
        ++ fingerprint ++ " :: Maybe String\n"
        ++ fingerprint ++ " = " ++ show sourceFingerprint ++ "\n"
        ++ maybe "" (const (requalify qualifiers (support names unit))) loaded)

-- 生成区的装配：effect 标签、handler 能力的实例与 effect 方法。
-- 注入 v6（2026-11-19）：生成入口把原子 action 交给 Root.super；hooks 由挂载决定，类别由绑定决定。
-- Injector.Super 已为每个 (列表, 类别) 选定 Middleware，这里把选择写成 Captures 实例：
-- super 通知进入，然后执行 action；显式操作在各自的调用点通知 Middleware。
-- GHC 在编译期按挂载登记的列表选定实例，入口只有一份，运行时不分发、不筛选。
support :: HandlerNames -> Unit -> String
support names unit = unlines (supportHeader ++ captureClasses ++ rootInstances ++ raisesInstances ++ routeInstances ++ streamInstances ++ rawInstances
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
    kindOf = helper "KindOf"
    selected = helper "selected"
    selection = helper "selection"
    notify = helper "notify"
    notifyAt = helper "notifyAt"
    callHandler = helper "call"
    callClose = helper "callClose"
    -- 标签的写法：effect 与方法名都在标签上，有 Middleware 时另带 hooks。
    tag effect = methodTag effect "method"
    methodTag effect method = "(" ++ wrap ++ (if hooked then " hooks " else " ") ++ effect ++ " " ++ method ++ ")"
    hooksArgument = if hooked then " @hooks" else ""
    call method = entry method ++ hooksArgument
    slot = slotLiteral "FrameworkRuntime." unit
    context = if hooked then captured ++ " hooks => " else ""
    signature resultType = if hooked
      then "forall hooks. " ++ context ++ "FrameworkGenerated.App " ++ resultType
      else "FrameworkGenerated.App " ++ resultType
    middlewareBindings = [binding | binding <- unitBindings unit, bindingOperation binding == MiddlewareOperation]
    promoted kind = "'FrameworkRuntime." ++ show kind
    hookList hooks = "'[" ++ intercalate ", " (map show hooks) ++ "]"
    nameOf = helper "nameOf"
    symbolOf variable = "(" ++ nameOf ++ " @" ++ variable ++ ")"
    -- 签名中的标签类型不加括号。
    tagType = wrap ++ (if hooked then " hooks" else "") ++ " effect method"
    -- 显式操作交给 Middleware 的捕获点：本标签的类别（notify）或被读取调用的类别（notifyAt）。
    notifies = if hooked then "(" ++ kindOf ++ " effect kind, " ++ captures ++ " hooks kind, FrameworkTypes.KnownSymbol method) => " else ""
    supportHeader =
      [ ""
      , "-- 以下由 gen 生成。每个 effect 一个类型标签：handler 在标签下执行，"
      , "-- 读取、rawinput 与错误按标签在编译期解析到这个 effect 的来源，不改写 handler 方法体。"
      , "newtype " ++ wrap ++ (if hooked then " (hooks :: [FrameworkTypes.Symbol])" else "")
          ++ " (effect :: FrameworkTypes.Symbol) (method :: FrameworkTypes.Symbol) value = " ++ wrap ++ " { " ++ runWrap ++ " :: FrameworkGenerated.App value }"
      , "  deriving (Functor, Applicative, Monad, FrameworkIO.MonadIO"
          ++ (if any (elem MasksExceptions . signatureLayer) (unitSignatures unit)
              then ", FrameworkRuntime.MonadThrow, FrameworkRuntime.MonadCatch, FrameworkRuntime.MonadMask" else "") ++ ")"
      , ""
      , "-- 类型标签上的名字：effect 名与方法名只写在标签上，需要字符串时从这里取。"
      , nameOf ++ " :: forall name. FrameworkTypes.KnownSymbol name => String"
      , nameOf ++ " = FrameworkTypes.symbolVal (FrameworkProxy.Proxy @name)"
      , ""
      , "-- 在标签下执行 handler，交给 Root 的 superhandler；方法名取自标签。close 的调用点用 " ++ callClose ++ "。"
      ] ++ concat
      [ [ name ++ " :: forall " ++ (if hooked then "hooks effect method kind" else "effect method") ++ " value. (FrameworkTypes.KnownSymbol method"
            ++ (if hooked then ", " ++ kindOf ++ " effect kind, " ++ captures ++ " hooks kind" else "") ++ ")"
        , "  => " ++ tagType ++ " value -> FrameworkGenerated.App value"
        , name ++ " handler = " ++ runWrap ++ " (FrameworkRuntime." ++ method ++ " " ++ symbolOf "method" ++ " handler)"
        , "" ]
      | (name, method) <- [(callHandler, "super"), (callClose, "superClose")] ]
    -- 有 Middleware 时：每个 effect 的类别是一条事实；Injector.Super 的选择逐条写成 Captures 实例，
    -- 没有被拦截的类别对任何列表都是空选择。选中的 Middleware 按注册顺序同步调用。
    -- Middleware handler 在自己的 Hook 标签下执行，那里的调用点不改写，它自己不再被捕获。
    captureClasses
      | not hooked = []
      | otherwise =
          [ "-- 每个 effect 的类别：Root 与显式操作按它取 " ++ captures ++ " 的选择。"
          , "class " ++ kindOf ++ " (effect :: FrameworkTypes.Symbol) (kind :: FrameworkRuntime.EffectKind) | effect -> kind"
          ] ++ [ "instance " ++ kindOf ++ " " ++ show effect ++ " " ++ promoted kind | (effect, kind) <- effectKinds ] ++
          [ ""
          , "-- superhandler 的静态选择：hooks 是覆盖本次挂载的 Middleware（注册顺序），kind 是捕获类别。"
          , "-- 默认即空选择：不捕获，super 直接执行 action。"
          , "class " ++ captures ++ " (hooks :: [FrameworkTypes.Symbol]) (kind :: FrameworkRuntime.EffectKind) where"
          , "  " ++ selected ++ " :: Maybe (FrameworkRuntime.Operation -> FrameworkGenerated.App ())"
          , "  " ++ selected ++ " = Nothing"
          , ""
          , "-- 入口对 hooks 多态：每个被拦截的类别都有该列表的选择。"
          , "type " ++ captured ++ " hooks = (" ++ intercalate ", " [captures ++ " hooks " ++ promoted kind | kind <- selectedKinds] ++ ")"
          , "" ] ++ concatMap selectionInstance (unitSupers unit)
          ++ [ "instance " ++ captures ++ " hooks " ++ promoted kind | kind <- nub (map snd effectKinds), kind `notElem` selectedKinds ] ++
          [ ""
          , selection ++ " :: forall hooks effect kind. (" ++ kindOf ++ " effect kind, " ++ captures ++ " hooks kind)"
          , "  => Maybe (FrameworkRuntime.Operation -> FrameworkGenerated.App ())"
          , selection ++ " = " ++ selected ++ " @hooks @kind"
          , ""
          , "-- 显式操作的捕获点：把本 handler 的操作交给选中的 Middleware，操作名取自标签。"
          , notifyAt ++ " :: forall kind hooks effect method. (" ++ captures ++ " hooks kind, FrameworkTypes.KnownSymbol method)"
          , "  => (String -> FrameworkRuntime.Operation) -> " ++ tagType ++ " ()"
          , notifyAt ++ " event = " ++ wrap ++ " (maybe (pure ()) ($ event " ++ symbolOf "method" ++ ") (" ++ selected ++ " @hooks @kind))"
          , ""
          , notify ++ " :: forall hooks effect method kind. (" ++ kindOf ++ " effect kind, " ++ captures ++ " hooks kind, FrameworkTypes.KnownSymbol method)"
          , "  => (String -> FrameworkRuntime.Operation) -> " ++ tagType ++ " ()"
          , notify ++ " = " ++ notifyAt ++ " @kind"
          , ""
          , "-- Middleware 的标签：handler 在这里执行，用 hook 读取触发本次调用的 Operation。"
          , "newtype " ++ hookTag ++ " (effect :: FrameworkTypes.Symbol) value = " ++ hookTag ++ " { " ++ runHook ++ " :: FrameworkRuntime.HookApp FrameworkGenerated.ContextValues FrameworkGenerated.Errors value }"
          , "  deriving (Functor, Applicative, Monad, FrameworkIO.MonadIO)"
          , ""
          , "instance FrameworkRuntime.Hooks (" ++ hookTag ++ " effect) where"
          , "  hook = " ++ hookTag ++ " FrameworkRuntime.currentOperation"
          , ""
          , "instance FrameworkRuntime.RawOutputs (" ++ hookTag ++ " effect)"
          , ""
          , "instance (FrameworkRuntime.HandlerError problem FrameworkGenerated.Errors, FrameworkTypes.KnownSymbol effect)"
          , "    => FrameworkRuntime.Raises problem (" ++ hookTag ++ " effect) where"
          , "  raise problem = " ++ hookTag ++ " (FrameworkRuntime.liftHookApp (FrameworkRuntime.failEffect " ++ symbolOf "effect" ++ " failure description))"
          , "    where (failure, description) = FrameworkRuntime.raised problem"
          , "" ] ++ concat
          [ [ entry (bindingMethod binding) ++ " :: FrameworkRuntime.Operation -> FrameworkGenerated.App [String]"
            , entry (bindingMethod binding) ++ " event = FrameworkRuntime.runHookApp event (" ++ runHook ++ " @" ++ show effect
                ++ " (FrameworkRuntime.super " ++ show handler' ++ " FrameworkGenerated." ++ handler' ++ "))"
            , "" ]
          | binding <- middlewareBindings
          , let effect = bindingEffect binding
                handler' = bindingHandler binding ]
    selectedKinds = nub (map selectionKind (unitSupers unit))
    -- 每个带 Wrap 标签的 effect 的类别；被拦截时与 Injector 选定的捕获类别一致。
    effectKinds = nub
      [ (bindingEffect binding, maybe (Prototype.effectKind (protoOf unit (bindingEffect binding))) id (bindingCaptureKind binding))
      | binding <- unitBindings unit, bindingOperation binding /= MiddlewareOperation ]
    middlewareMethod selectedName = case [bindingMethod binding | binding <- middlewareBindings, bindingEffect binding == selectedName] of
      method : _ -> entry method
      [] -> error ("Middleware has no hook method: " ++ selectedName)
    -- 一条选择一个实例；空选择沿用默认。
    selectionInstance (SuperSelection hooks kind []) =
      ["instance " ++ captures ++ " " ++ hookList hooks ++ " " ++ promoted kind]
    selectionInstance (SuperSelection hooks kind chosen) =
      [ "instance " ++ captures ++ " " ++ hookList hooks ++ " " ++ promoted kind ++ " where"
      , "  " ++ selected ++ " = Just (\\event -> " ++ concatMap (\hook -> middlewareMethod hook ++ " event >> ") chosen ++ "pure ())" ]
    -- Root 的 superhandler：有 Middleware 时按标签类别的选择通知进入；Middleware 自身使用直接实例，避免递归捕获。
    rootInstances
      | not hooked = ["instance FrameworkRuntime.Root " ++ tag "effect" ++ " value", ""]
      | otherwise =
          [ "instance FrameworkRuntime.Root (" ++ hookTag ++ " effect) value"
          , ""
          , "instance (" ++ kindOf ++ " effect kind, " ++ captures ++ " hooks kind) => FrameworkRuntime.Root " ++ tag "effect" ++ " value where"
          , "  super name (" ++ wrap ++ " action) = " ++ wrap ++ " (maybe (const id) FrameworkRuntime.superWith (" ++ selection ++ " @hooks @effect) name action)"
          , "  superClose name (" ++ wrap ++ " action) = " ++ wrap ++ " (maybe (const id) FrameworkRuntime.superClosing (" ++ selection ++ " @hooks @effect) name action)"
          , "" ]
    -- raise 按生成的 HandlerError 事实取失败分类，以标签上的 effect 名报告；有 Middleware 时先通知。
    raisesInstances =
      [ "instance (FrameworkRuntime.HandlerError problem FrameworkGenerated.Errors, FrameworkTypes.KnownSymbol effect"
          ++ (if hooked then "\n         , " ++ kindOf ++ " effect kind, " ++ captures ++ " hooks kind, FrameworkTypes.KnownSymbol method" else "") ++ ")"
      , "    => FrameworkRuntime.Raises problem " ++ tag "effect" ++ " where"
      , "  raise problem = " ++ (if hooked then notify ++ " (`FrameworkRuntime.Raise` description) >> " else "")
          ++ wrap ++ " (FrameworkRuntime.failEffect " ++ symbolOf "effect" ++ " failure description)"
      , "    where (failure, description) = FrameworkRuntime.raised problem"
      , "" ]
    -- demands 按表示类型路由到资产的读取入口；持续与有限调用都读声明的 T。
    routeInstances = concat
      [ [ "instance FrameworkRuntime.Reads " ++ parenthesized (renderValueType "FrameworkRuntime." "FrameworkGenerated." (routeType route)) ++ " "
            ++ tag (show (routeEffect route)) ++ " where"
        , "  require = " ++ wrap ++ " " ++ parenthesized (routeExpression route)
        , "" ]
      | route <- unitRoutes unit ]
    routeExpression route = "FrameworkRuntime.coerce <$> " ++ entry (routeReader route)
    -- streams 读取的持续资产另有 x:xs 入口；Flow 的参数是 representational 角色，契约细化直接 coerce 掉。
    streamInstances = concat
      [ [ "instance FrameworkRuntime.Streams " ++ parenthesized (renderValueType "FrameworkRuntime." "FrameworkGenerated." (routeType route)) ++ " "
            ++ tag (show (routeEffect route)) ++ " where"
        , "  stream = " ++ wrap ++ " (FrameworkRuntime.coerce <$> " ++ entry (historyEntry (routeContract route)) ++ ")"
        , "" ]
      | route <- streamedRoutes unit ]
    -- rawinput 的捕获点：读取方 handler 与读到的值；类别取被读取的那次调用的类别。
    rawInstances = concat
      [ [ "instance " ++ context ++ "FrameworkRuntime.Raw " ++ methodTag (show (bindingEffect binding)) (show (bindingHandler binding)) ++ " where"
        , "  rawinput = " ++ capturedRaw binding (wrap ++ " " ++ parenthesized (rawExpression (callSource source)))
        , "" ]
      | binding <- unitBindings unit, Just source <- [bindingRaw binding] ]
    callSource (RawList method) = RawList (call method)
    callSource (RawStream method) = RawStream method
    capturedRaw binding reading = case bindingRawKind binding of
      Just kind -> reading ++ " >>= \\value -> value <$ " ++ notifyAt ++ " @" ++ promoted kind ++ " (`FrameworkRuntime.RawInput` value)"
      _ -> reading
    -- 能力已经由组合计算确定，handler 只能用 Layer 中的能力；这里给所有标签同一份实现，不重新解释 effect 类别或 demands。
    -- Middleware 自身的 Hook 标签用 RawOutputs 的默认实现，输出不会再进入 hook。
    outputInstances
      | not hooked = ["instance FrameworkRuntime.RawOutputs " ++ tag "effect", ""]
      | otherwise =
          [ "instance " ++ notifies ++ "FrameworkRuntime.RawOutputs " ++ tag "effect" ++ " where"
          , "  rawoutput value = value <$ " ++ notify ++ " (`FrameworkRuntime.RawOutput` value)"
          , "" ]
    endInstances =
      [ line | anyCapability EmitsItem, line <-
        [ "instance " ++ notifies ++ "FrameworkRuntime.Emits " ++ tag "effect" ++ " where"
        , "  rawemit text = " ++ (if hooked then notify ++ " (`FrameworkRuntime.RawEmit` text) >> " else "")
            ++ wrap ++ " (FrameworkRuntime.emitToParser text)"
        , "" ] ]
      ++ [ line | anyCapability EndsSource, line <-
        [ "instance FrameworkRuntime.StreamEnds " ++ tag "effect" ++ " where"
        , "  streamEnd = " ++ wrap ++ " FrameworkRuntime.endSource"
        , "" ] ]
      ++ [ line | anyCapability EndsSubscription, line <-
        [ "instance FrameworkRuntime.EndsStream " ++ tag "effect" ++ " where"
        , "  endStream = " ++ wrap ++ " FrameworkRuntime.endSubscription"
        , "" ] ]
    anyCapability capability = any ((capability `elem`) . bindingCapabilities) (unitBindings unit)

    -- effect 方法：外层包装由类别决定；方法体先驱动、再执行 Input 前驱，最后在本 effect 的标签下执行 handler。
    entryDefinitions selectedName =
      [ line
      | binding <- unitBindings unit, bindingEffect binding == selectedName, bindingOperation binding /= MiddlewareOperation
      , let method = bindingMethod binding
            handler' = bindingHandler binding
      , line <- definition True method (renderValueType "FrameworkRuntime." "FrameworkGenerated." (bindingResult binding)) (wrapper binding)
          (intercalate " >> " (map entryStep (bindingBefore binding) ++ [handlerCall binding handler'])) ]
      ++ concat [ readerDefinition reader | reader <- unitReaders unit, readerEffect reader == selectedName ]
      ++ concat [ historyDefinition reader | reader <- unitReaders unit, readerEffect reader == selectedName
                , readerContinuous reader, historyEntry (readerContract reader) `elem` historyEntries unit ]
      where
        -- 步骤按 Injector 排定的顺序执行。锚点带上它为本入口生产的 Context：
        -- 在 Scoped 的 open 中，锚点的 IO 属于这些开启输入的生产，不提前固定开启输入。
        -- 订阅回调把交付的资产记为本次已发布：入口里对它的 requests 跳过生产链，直接读这条交付。
        entryStep (SessionRequestStep producer) = sessionRequest producer
        entryStep (RequestStep method) = call method
        entryStep (InputStep method) = call method
        entryStep (AnchorStep method []) = call method
        entryStep (AnchorStep method produced) = "FrameworkRuntime.unlessPerformed [" ++ slots ++ "] (FrameworkRuntime.producingFor ["
          ++ slots ++ "] (" ++ call method ++ "))"
          where slots = intercalate ", " (map slot produced)
        -- 持续资产的 requests：回调已交付时读交付；lifelong 之外同步运行来源到结束，固定整段历史。
        sessionRequest producer = "FrameworkRuntime.requestStreamContext " ++ slot producer
          ++ " FrameworkGenerated.ContextBindingError FrameworkGenerated.bound" ++ producer
        -- close 的调用点用 callClose：是否 close 由绑定的操作在生成期确定。
        handlerCall binding handler' =
          let caller = if bindingOperation binding == CloseResource then callClose else callHandler
              action = caller ++ hooksArgument ++ " @" ++ show selectedName ++ " @" ++ show handler' ++ " FrameworkGenerated." ++ handler'
          in case bindingOperation binding of
               PublishAsset contract -> "FrameworkGenerated." ++ contract ++ " <$> " ++ action
               _ -> action
        scoped = ["FrameworkRuntime.withScopeDependencies [" ++ intercalate ", " (map slot scopes) ++ "]" | not (null scopes)]
          where scopes = Prototype.effectScopes (protoOf unit selectedName)
        entered = scoped ++ ["FrameworkRuntime.enterHandler " ++ slot selectedName]
        -- 同一次调用中再次到达时返回本次输出，不重复执行：Excu、Scoped.open 与 Pure 的 list，见 runOnce；
        -- Context 的发布由 callContext 按本次捕获返回。
        once binding = ["FrameworkRuntime.runOnce " ++ slot selectedName | bindingResult binding == NativeType "[String]"]
        wrapper binding = case bindingOperation binding of
          OpenResource -> once binding ++ rootWrapper selectedName ++ scopeWrapper binding "openScope " (" " ++ cleanupOf selectedName)
          -- 没有输出联立分支时，句柄的输出只由 runOnce 记录：atomicHandle 在交出前的那次记录没有读者。
          AtomicOperation
            | null (anchoredBranches binding) && not (null (once binding)) -> once binding ++ rootWrapper selectedName ++ entered
            | otherwise -> once binding ++ rootWrapper selectedName
                ++ (("FrameworkRuntime.atomicHandle " ++ slot selectedName ++ anchoredOf binding) : entered)
          PureOperation -> once binding ++ rootWrapper selectedName ++ scoped
          operation -> rootWrapper selectedName ++ case operation of
            -- 先进入本 scope，再检查其上游；失效后的 close 仍可读取自己的 Context 以收尾。
            CloseResource -> scopeWrapper binding "closeScope " ""
            SourceStep -> entered
            PublishAsset _ -> scoped ++ ["FrameworkRuntime.callContext " ++ slot selectedName
              ++ "\n      (\\value bindings -> bindings { FrameworkGenerated.bound" ++ selectedName ++ " = Just value })"
              ++ "\n      FrameworkGenerated.bound" ++ selectedName]
            ErrorOperation -> entered
            MiddlewareOperation -> entered
            _ -> entered
        scopeWrapper binding operation cleanup =
          [ "FrameworkRuntime.atomicScope " ++ slot selectedName ++ anchoredOf binding
          , "FrameworkRuntime." ++ operation ++ slot selectedName ++ " FrameworkGenerated.ScopeBindingError" ++ cleanup ] ++ entered
    -- 输出联立的执行闭包：句柄成功交出后依次执行挂在它下面的生产分支（先普通、再持续），失败沿原链传播。
    anchoredOf binding = " [" ++ intercalate ", "
      [ "(" ++ slot (outputProducer connection) ++ ", () <$ " ++ call (outputParser connection) ++ ")"
      | connection <- anchoredBranches binding ] ++ "]"
    anchoredBranches binding =
      [ connection | role <- [ContextRequest, ContextStream], connection <- assemblyOutputs (unitAssembly unit)
      , outputRole connection == role, outputAnchor connection == bindingMethod binding ]
    -- 自动收尾：open 带上本 scope 的 close，在同一 Middleware 列表下执行。
    cleanupOf selectedName = case [closing | plan <- unitScopes unit, scopeEffect plan == selectedName, Just closing <- [scopeCleanup plan]] of
      closing : _ -> "(Just (() <$ " ++ call closing ++ "))"
      [] -> "Nothing"
    rootWrapper selectedName =
      ["FrameworkRuntime.withErrorPath " ++ show path | not (null path)] ++ ["FrameworkRuntime.handleFailure"]
      where path = Prototype.effectNearestScopes (protoOf unit selectedName)
    -- readT 与 streamT 的模式由组合计算选定，渲染器只输出相应的读取入口；读取不执行 handler，不随 hooks 变化。
    readerDefinition reader
      | readerContinuous reader = definition False method
          ("FrameworkGenerated." ++ contractType) (rootWrapper selectedName)
          ("FrameworkRuntime.readStreamContext " ++ slot selectedName ++ " FrameworkGenerated.ContextBindingError"
            ++ " FrameworkGenerated.bound" ++ selectedName)
      | otherwise = definition False method ("FrameworkGenerated." ++ contractType) (rootWrapper selectedName)
          ("FrameworkRuntime.readContext " ++ slot selectedName ++ " FrameworkGenerated.ContextBindingError "
             ++ "FrameworkGenerated.bound" ++ selectedName)
      where
        selectedName = readerEffect reader
        method = readerMethod reader
        contractType = readerContract reader
    -- x:xs：本次固定交付及其之前的同会话交付；与 streamT 取同一个视图，不另起读取。
    historyDefinition reader = definition False (historyEntry (readerContract reader))
      ("FrameworkRuntime.Flow FrameworkGenerated." ++ readerContract reader) (rootWrapper (readerEffect reader))
      ("FrameworkRuntime.readStreamHistory " ++ slot (readerEffect reader) ++ " FrameworkGenerated.ContextBindingError"
        ++ " FrameworkGenerated.bound" ++ readerEffect reader)
    definition polymorphic method resultType wrapper body =
      [ entry method ++ " :: " ++ (if polymorphic then signature else ("FrameworkGenerated.App " ++)) (parenthesized resultType)
      , entry method ++ " ="
      , "  " ++ intercalate "\n  . " wrapper ++ " $"
      , "    " ++ body
      , "" ]


    -- 控制对象由生成的 handler 模块创建；不同链引用同份对象，不预执行 open。
    scopeHandlers = unlines
      [ "-- SDK 内部：scope 按上游到下游登记，退出时逆序收尾；创建不执行业务方法。"
      , helper "newScopeHandlers" ++ " :: IO [FrameworkRuntime.ScopeHandler FrameworkGenerated.ContextValues FrameworkGenerated.Errors]"
      , helper "newScopeHandlers" ++ " = sequence" ++ (if null registered then " []" else "\n  [ " ++ intercalate "\n  , " registered ++ "\n  ]")
      ]
      where
        registered =
          [ "FrameworkRuntime.newScopeHandler " ++ slot (scopeEffect plan)
              ++ " [" ++ intercalate ", " (map slot (scopeInputs plan)) ++ "] "
              ++ maybe "Nothing" (\resource -> "(Just " ++ slot resource ++ ")") (scopeResource plan)
          | plan <- unitScopes unit ]
    -- Error 只指向 scope：按 handles 匹配故障，detect／resolve 是生成的 effect 方法；Error 不被拦截，按空列表执行。
    errorHandlers = unlines
      [ ""
      , "-- Error 回调登记：按 handles 匹配故障的 handler 与协议分类；关联 scope 由 Input 链推导。"
      , helper "errorHandlers" ++ " :: [(Maybe String, FrameworkRuntime.ErrorHandler FrameworkGenerated.Errors FrameworkGenerated.App)]"
      , helper "errorHandlers" ++ " =" ++ (if null callbacks then " []" else "\n  [ " ++ intercalate "\n  , " callbacks ++ "\n  ]")
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
  [ "AllowAmbiguousTypes", "ConstraintKinds", "DataKinds", "FlexibleContexts", "FlexibleInstances", "GeneralizedNewtypeDeriving"
  , "KindSignatures", "MultiParamTypeClasses", "ScopedTypeVariables", "TypeApplications", "UndecidableInstances" ]

-- 入口对 hooks 多态（类型只出现在约束里）、类型级列表的实例展开。
middlewareExtensions :: [String]
middlewareExtensions = ["FunctionalDependencies", "TypeOperators"]

-- 只认文件头连续出现的正向、已知扩展；遇到 CPP、OPTIONS 或其他 pragma 就停止。
-- 原文件中的 pragma 和顺序照抄，生成区只补这里尚未启用的扩展。
leadingExtensions :: [String] -> String -> [String]
leadingExtensions allowed = scan . lines
  where
    scan [] = []
    scan (line : rest)
      | null trimmed || "--" `isPrefixOf` trimmed = scan rest
      | ["{-#", "LANGUAGE", ext, "#-}"] <- words trimmed, ext `elem` allowed = ext : scan rest
      | otherwise = []
      where trimmed = dropWhile isSpace line

-- 生成区以固定的长限定名书写，输出时换成短名：Framework.Generated 写作 SDK（与 Effects.hs、Program.hs 一致），
-- 生成的契约模块写作 Effects。手写文件已用某个短名作限定（as 别名或模块名）时，该模块保留长名。
data Qualifiers = Qualifiers { runtimeQualifier :: String, effectsQualifier :: String }

longQualifiers :: Qualifiers
longQualifiers = Qualifiers "FrameworkRuntime" "FrameworkGenerated"

chooseQualifiers :: HsModule GhcPs -> Qualifiers
chooseQualifiers parsed =
  Qualifiers (pick "SDK" (runtimeQualifier longQualifiers)) (pick "Effects" (effectsQualifier longQualifiers))
  where
    taken = [ moduleNameString (unLoc (fromMaybe (ideclName declaration) (ideclAs declaration)))
            | L _ declaration <- hsmodImports parsed ]
    pick short long = if short `elem` taken then long else short

-- 只替换作为限定前缀出现的长名；生成区不含手写代码。
requalify :: Qualifiers -> String -> String
requalify qualifiers = go ' '
  where
    go _ [] = []
    go previous text@(character : rest)
      | boundary previous, Just remaining <- stripPrefix "FrameworkRuntime." text =
          runtimeQualifier qualifiers ++ "." ++ go '.' remaining
      | boundary previous, Just remaining <- stripPrefix "FrameworkGenerated." text =
          effectsQualifier qualifiers ++ "." ++ go '.' remaining
      | otherwise = character : go character rest
    boundary previous = not (isAlphaNum previous || previous `elem` "_.")

-- 只改模块名、导出表并补充导入；方法体与 instance 原样保留。
copyModule :: Qualifiers -> String -> String -> [String] -> String -> HsModule GhcPs -> Either String String
copyModule qualifiers namespace generatedName extraExports source parsed = do
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
  let typesImport = "import " ++ namespace ++ ".Types"
      -- 复用无条件的完整导入；带限定、显式列表或 CPP 的导入保留原有补全。
      alreadyImportsTypes = not (any (("#" `isPrefixOf`) . dropWhile isSpace) (lines source))
        && any (sameImport typesImport) (hsmodImports parsed)
      imports = (importStart, importStart,
        "import qualified Framework.Generated as " ++ runtimeQualifier qualifiers ++ "\n"
        ++ "import qualified " ++ namespace ++ ".Generated.Effects as " ++ effectsQualifier qualifiers ++ "\n"
        ++ "import qualified Control.Monad.IO.Class as FrameworkIO\n"
        ++ "import qualified Data.Proxy as FrameworkProxy\n"
        ++ "import qualified GHC.TypeLits as FrameworkTypes\n"
        ++ (if alreadyImportsTypes then "" else typesImport ++ "\n"))
  pure (foldr apply source (sortOn (\(start, _, _) -> start) (rename : imports : exports)))
  where
    sameImport expected declaration = case range (getLocA declaration) of
      Right (start, end) -> take (end - start) (drop start source) == expected
      Left _ -> False
    apply (start, end, replacement) remaining =
      take start remaining ++ replacement ++ drop end remaining
    range (RealSrcSpan span _) = Right
      (sourceOffset source (srcSpanStartLine span) (srcSpanStartCol span),
       sourceOffset source (srcSpanEndLine span) (srcSpanEndCol span))
    range _ = Left "Handler source has no concrete location"
    replace location replacement = do
      (start, end) <- range location
      pure (start, end, replacement)
