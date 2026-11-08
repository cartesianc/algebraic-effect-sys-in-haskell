{-# LANGUAGE DuplicateRecordFields #-}

-- 输出 Generated/Handlers.hs：手写 Handlers.hs 的编译副本（方法体原样保留），后接 gen 生成的装配——
-- 每个 effect 一个类型标签 At，按标签的 Reads／Raw／Raises 实例，“驱动 → Input → 方法体”的 effect 方法，
-- 以及 scope、Error 与挂接 Context 的登记表。只渲染绑定阶段定下的事实。
module Framework.Gen.Emit.Handlers (renderHandlers, handlerExports) where

import Data.List (intercalate, nub, sortOn)
import Data.Maybe (isJust)
import Framework.Gen.Bind
import Framework.Gen.Demand (readsAccess)
import Framework.Gen.Names (contextProducer, contextReader, entryMethod, handlerBindings, handlerError, handlerFailure)
import Framework.Gen.Source (HandlerSource(..), sourceOffset)
import Framework.Language.Registration
import Framework.Prototype.Graph (MethodRole(..))
import Framework.Prototype.Types (ResolvedDemand(..))
import qualified Framework.Prototype as Prototype
import GHC (GhcPs)
import GHC.Fingerprint (fingerprintString)
import GHC.Hs
import GHC.Parser.Annotation (getLocA)
import GHC.Types.SrcLoc

-- Generated/Handlers 导出的名字：全部 effect 方法与登记表。
handlerExports :: Unit -> [String]
handlerExports unit = allMethods unit ++ ["newScopeHandlers", "scopeCleanups", "errorHandlers", "contextInjections"]

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
    ++ concatMap entryDefinitions (specifications unit))
    ++ scopeHandlers ++ scopeCleanups ++ errorHandlers ++ injectionTable
  where
    supportHeader =
      [ ""
      , "-- 以下由 gen 生成。每个 effect 一个类型标签：handler 在标签下执行，"
      , "-- 读取、raw 与错误按标签在编译期解析到这个 effect 的来源，不改写 handler 方法体。"
      , "newtype At (effect :: FrameworkTypes.Symbol) value = At { runAt :: FrameworkGenerated.App value }"
      , "  deriving (Functor, Applicative, Monad, FrameworkIO.MonadIO)"
      , ""
      ]
    raisesInstance handler' =
      [ "instance FrameworkTypes.KnownSymbol effect => FrameworkRuntime.Raises FrameworkGenerated." ++ handlerError handler' ++ " (At effect) where"
      , "  raise (FrameworkGenerated." ++ handlerError handler' ++ " description) = At (FrameworkRuntime.failEffect"
      , "    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) FrameworkGenerated."
          ++ handlerFailure handler' ++ " description)"
      , ""
      ]
    -- demands 按表示类型路由到资产的读取入口；分支契约投影出构造器字段，streams 读历史。
    routeInstances = concat
      [ [ "instance FrameworkRuntime.Reads (" ++ readType unit "FrameworkRuntime.History" resolved ++ ") (At "
            ++ show (name specification) ++ ") where"
        , "  require = At (" ++ routeExpression resolved ++ ")"
        , "" ]
      | specification <- specifications unit, not (null (handlerBindings specification))
      , resolved <- readDemands unit (name specification) ]
    routeExpression resolved = case (demandAccess resolved, [branch | branch <- unitBranches unit, branchName branch == contractType]) of
      (StreamAccess, _) -> "fmap " ++ unwrap contractType ++ " <$> " ++ reader
      (_, BranchContract _ base constructor field _ : _) -> "FrameworkRuntime.projectContext " ++ show producer ++ " "
        ++ show contractType ++ " FrameworkGenerated.ContextBindingError (\\(FrameworkGenerated." ++ base
        ++ " value) -> case value of { " ++ constructor ++ maybe " -> Just ()" (const " field -> Just field") field
        ++ "; _ -> Nothing }) (" ++ current base ++ ")"
      _ -> unwrap contractType ++ " <$> " ++ current contractType
      where
        contractType = demandContract resolved
        producer = demandProvider resolved
        reader = readerOf unit producer
        unwrap selectedContract = "(\\(FrameworkGenerated." ++ selectedContract ++ " value) -> value)"
        current base
          | continuousContract unit base = "FrameworkRuntime.latestContext " ++ show producer
              ++ " FrameworkGenerated.ContextBindingError " ++ reader
          | otherwise = reader
    rawInstances = concat
      [ [ "instance FrameworkRuntime.Raw (At " ++ show (name specification) ++ ") where"
        , "  raw = At (" ++ expression ++ ")"
        , "" ]
      | specification <- contextSpecs unit, Just expression <- [rawExpression unit specification] ]

    -- effect 方法：外层包装由类别决定；方法体先驱动、再执行 Input 前驱，最后在本 effect 的标签下执行 handler。
    entryDefinitions specification =
      [ line
      | (method, handler') <- handlerBindings specification
      , line <- definition method (resultType method) (wrapper method)
          (intercalate " >> " (beforeOf unit specification method ++ [handlerCall method handler'])) ]
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
        scoped = "FrameworkRuntime.withScopeDependencies " ++ show (Prototype.effectScopes (protoOf unit selectedName))
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
    rootWrapper specification = "FrameworkRuntime.withErrorPath " ++ show (Prototype.effectNearestScopes (protoOf unit (name specification)))
      ++ " . FrameworkRuntime.handleFailure"
    -- readT 读最新值：尚无值时按需求值一次 getT；streamT 读历史视图，由会话交付。
    readerDefinition specification method
      | Prototype.effectContinuous (protoOf unit selectedName) = definition method
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
      | consumer <- specifications unit
      , Just access <- [accessFor consumer] ] ++ "]"
      where
        providersOf consumer mode = [demandProvider resolved | resolved <- resolvedOf unit (name consumer), mode (demandAccess resolved)]
        accessFor consumer
          | selectedName `elem` providersOf consumer (== RequestAccess) = Just "RequestValue"
          | selectedName `elem` providersOf consumer readsAccess = Just "RequireValue"
          | otherwise = Nothing
    orderedScopes = nub (concat
      [ Prototype.effectScopes effect ++ [Prototype.effectName effect | Prototype.effectKind effect == ScopedKind]
      | effect <- effectPrototypes unit ])
    openingInputs = Prototype.effectOpeningInputs . protoOf unit . name
    comparedInputs = nub (concatMap openingInputs
      [specification | specification <- specifications unit, effectKind (typing specification) == ScopedKind])
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
              ++ " (" ++ show (Prototype.effectResource (protoOf unit (name specification))) ++ ")"
          | selectedScope <- orderedScopes, specification <- specifications unit, name specification == selectedScope ]
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
          , effect <- effectPrototypes unit, Prototype.effectName effect == selectedScope
          , (ScopeClose, closing) <- Prototype.effectMethods effect ]
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
          | specification <- specifications unit
          , Just entry <- [entryMethod specification]
          , let anchored =
                  [ (context, producing)
                  | context <- effectPrototypes unit
                  , Prototype.effectAnchor context == Just (name specification)
                  , (ContextRequest, producing) <- Prototype.effectMethods context ]
          , not (null anchored) ]
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
          [ "(" ++ show (Prototype.effectErrorScope effect) ++ ", FrameworkRuntime.ErrorHandler " ++ show (name specification)
              ++ "\n      (\\failure -> case (FrameworkRuntime.origin failure, FrameworkRuntime.detail failure) of"
              ++ concatMap (("\n        " ++) . matchCase) (nub matched)
              ++ "\n        _ -> False)"
              ++ "\n      (" ++ methodReference ErrorDetect ++ ") (" ++ methodReference ErrorResolve ++ "))"
          | specification <- specifications unit
          , Error { handles = matched } <- [typing specification]
          , let effect = protoOf unit (name specification)
                methodReference role = maybe "Nothing" ("Just " ++) (lookup role (Prototype.effectMethods effect)) ]
        matchCase (RaisedBy selectedHandler) = "(_, FrameworkGenerated." ++ handlerFailure selectedHandler ++ ") -> True"
        matchCase (ScopeFaultIn selectedEffect) = "(" ++ show selectedEffect ++ ", FrameworkGenerated.ScopeBindingError _) -> True"
        matchCase (ContextFaultIn selectedEffect) = "(" ++ show selectedEffect ++ ", FrameworkGenerated.ContextBindingError _) -> True"


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
