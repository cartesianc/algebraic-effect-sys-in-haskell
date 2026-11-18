{-# LANGUAGE DuplicateRecordFields #-}
-- 一个入口的装配解释；由 Composition 调用，Emit 只读取结果。
module Framework.Gen.Injector (bindProgram) where
import Control.Monad (unless, when)
import Data.Char (isAlphaNum, isLower, isUpper)
import Data.List (intercalate, nub, nubBy, sortOn)
import Data.Maybe (maybeToList)
import Framework.Gen.Plan
import Framework.Gen.Names
import Framework.Prototype.Graph (MethodRole(..))
import Framework.Language.Registration hiding (effectKind)
import Framework.Prototype.Types
import Framework.Prototype.Query
import qualified Framework.Prototype as Prototype

bindProgram :: String -> PrototypePlan -> [EffectDeclaration] -> Assembly String -> SumTypes -> [(String, String)] -> Either String Unit
bindProgram namespace prepared declarations assembly sumTypes controlled = do
  checkGenerated unit
  when (null (unitTerminals unit)) (Left "Select at least one terminal effect for generation")
  mapM_ (checkRepresentations unit) (declarations)
  signatures <- mapM (signatureOf unit) (unitHandlers unit)
  pure unit { unitSignatures = signatures }
  where
    unit = Unit
      { unitNamespace = namespace
      , unitPlan = prepared
      , unitAssets = assets
      , unitBranches = branches
      , unitHandlers = nub [handler' | specification <- declarations, (_, handler') <- [(method, handler) | (method, handler, _) <- declarationBindings specification]]
      , unitSignatures = []
      , unitBindings =
          [ Binding (declarationName specification) method handler' (beforeOf unit specification method)
              (if readsRaw specification method then rawSource unit specification else Nothing)
              [ (normalizeType (typeSpelling (routeType route)), (routeContract route, routeReader route))
              | route <- unitRoutes unit, routeEffect route == declarationName specification ]
              (entryResult specification) (entryOperation specification method) (layerOf unit specification method)
          | specification <- declarations, (method, handler') <- [(method, handler) | (method, handler, _) <- declarationBindings specification] ]
      , unitAssembly = assembly
      , unitRoutes = [routeOf unit specification resolved
          | specification <- declarations, not (null ([(method, handler) | (method, handler, _) <- declarationBindings specification]))
          , resolved <- readDemands unit (declarationName specification)]
      , unitReaders = [ReaderPlan (declarationName specification) method (contractOf declared)
            (Prototype.effectContinuous (protoOf unit (declarationName specification)))
          | specification <- [declared | declared <- declarations, Just _ <- [declarationAsset declared]]
          , Just method <- [readerMethodOf (declarationName specification)]
          , Just declared <- [declarationAsset specification]]
      , unitSelectors = []
      , unitSessionEntries = []
      , unitScopes = [ScopePlan selected (effectOpeningInputs effect) (effectResource effect) (lookup ScopeClose (effectMethods effect))
          | selected <- unitScopeOrder unit, let effect = protoOf unit selected]
      , unitErrors = [ErrorPlan (declarationName declared) (effectErrorScope effect) (nub handled)
            (lookup ErrorDetect (effectMethods effect)) (lookup ErrorResolve (effectMethods effect))
          | declared <- declarations, Just handled <- [declarationErrors declared], let effect = protoOf unit (declarationName declared)]
      , unitScopeOrder = nub (concat [Prototype.effectScopes effect
          ++ [Prototype.effectName effect | Prototype.effectKind effect == ScopedKind]
          | effect <- effectPrototypes unit])
      , unitReads =
          [ (declarationName specification, nub
              [ demandContract resolved | resolved <- resolvedOf unit (declarationName specification), readsAccess (demandAccess resolved)
              , (declarationName specification, demandContract resolved) `notElem` controlled ])
          | specification <- declarations ]
      }
    assets =
      [ AssetDeclaration (contractOf declared) (representation declared) (declarationName specification)
      | specification <- [declared | declared <- declarations, Just _ <- [declarationAsset declared]]
      , Just declared <- [declarationAsset specification] ]
    branches =
      [ BranchContract (base ++ constructor) base constructor field owner
      | AssetDeclaration base (TypeRef typeName) owner <- assets
      , (branch, constructor) <- Prototype.effectBranches (protoOf unit owner)
      , Just constructors <- [lookup typeName sumTypes]
      , Just field <- [lookup constructor constructors]
      , branch == base ++ constructor ]

    -- 绑定解释与校验只在本阶段可见；后续算法和 Emit 读取 Unit 中的确定事实。
    typeSpelling :: ValueType -> String
    typeSpelling (NativeType selected) = selected
    typeSpelling (RefinedType selected) = selected

    readValueType :: Unit -> ResolvedDemand -> ValueType
    readValueType unit resolved = NativeType (representationOf unit (demandContract resolved))

    routeOf :: Unit -> EffectDeclaration -> ResolvedDemand -> ReadRoute
    routeOf unit specification resolved = ReadRoute (declarationName specification) (readValueType unit resolved)
      contractType producer (readerOf unit producer) view
      where
        contractType = demandContract resolved
        producer = demandProvider resolved
        view = case [branch | branch <- unitBranches unit, branchName branch == contractType] of
          branch : _ -> BranchView branch
          _ | continuousContract unit contractType -> ContinuousView
            | otherwise -> ValueView

    entryResult specification = case declarationAsset specification of
      Just declared -> RefinedType (contractOf declared)
      Nothing -> declarationResult specification

    entryOperation specification method = case [operation | (selected, _, operation) <- declarationBindings specification, selected == method] of
      [operation] -> operation
      _ -> error "Validated binding has no unique entry operation"

    specOf :: Unit -> String -> EffectDeclaration
    specOf unit selectedName = case [specification | specification <- declarations, declarationName specification == selectedName] of
      specification : _ -> specification
      [] -> error ("Validated registration has no effect: " ++ selectedName)

    resolvedOf :: Unit -> String -> [ResolvedDemand]
    resolvedOf unit = Prototype.effectDemands . protoOf unit

    continuousContract :: Unit -> String -> Bool
    continuousContract unit contractType = or
      [ Prototype.effectContinuous (protoOf unit (assetOwner declared))
      | declared <- unitAssets unit, assetContract declared == contractType ]

    -- 契约读到的表示类型：基础契约是声明的表示类型，分支契约是构造器的字段（无字段为 ()）。
    representationOf :: Unit -> String -> String
    representationOf unit contractType = case [branch | branch <- unitBranches unit, branchName branch == contractType] of
      branch : _ -> maybe "()" id (branchField branch)
      [] -> case [reference (assetRepresentation declared) | declared <- unitAssets unit, assetContract declared == contractType] of
        found : _ -> found
        [] -> error ("Validated demand has no asset: " ++ contractType)

    -- 读取方式影响驱动关系，不改变资产表示；本轮交付和有限读取都捕获声明的同一个 T。
    readType :: Unit -> ResolvedDemand -> String
    readType unit resolved = representationOf unit (demandContract resolved)

    readDemands :: Unit -> String -> [ResolvedDemand]
    readDemands unit selectedName = nubBy (\left right -> demandContract left == demandContract right)
      [resolved | resolved <- resolvedOf unit selectedName, readsAccess (demandAccess resolved)]

    readerOf :: Unit -> String -> String
    readerOf unit provider = case readerMethodOf provider of
      Just method -> method
      Nothing -> error ("Validated demand has no reader: " ++ provider)

    -- 驱动：requests 声明的资产在入口先调用 getT，沿 Input 驱动它的整条 Context 链。
    drives :: Unit -> EffectDeclaration -> [String]
    drives unit specification =
      [ getter | resolved <- resolvedOf unit (declarationName specification), demandAccess resolved == RequestAccess
      , Just getter <- [producerMethodOf (demandProvider resolved)] ]

    -- 挂接的 parser 与 Pure 用 raw 读取直接 Input 的输出，不把 Input 当前驱执行：
    -- Input 是 Excu、Scoped、Pure 时读它交出的 list，是 Stream 时读会话本次取得的一份输入。
    methodOf selected = declarationEntry (specOf unit selected)
    producerMethodOf selected = lookup ContextRequest (effectMethods (protoOf unit selected))
    readerMethodOf selected = lookup ContextRequire (effectMethods (protoOf unit selected))
    kindOf specification = effectKind (protoOf unit (declarationName specification))
    inputOf specification = effectInput (protoOf unit (declarationName specification))
    rawSource :: Unit -> EffectDeclaration -> Maybe (RawSource String)
    rawSource _ specification
      | kindOf specification `elem` [ContextKind, PureKind], inputOf specification /= "Root" =
          case effectKind (protoOf unit (inputOf specification)) of
            StreamKind -> RawStream <$> methodOf (inputOf specification)
            kind | kind `elem` [ExcuKind, ScopedKind, PureKind] -> RawList <$> methodOf (inputOf specification)
            _ -> Nothing
      | otherwise = Nothing
    readsRaw specification method = kindOf specification `elem` [ContextKind, PureKind]
      && Just method == methodOf (declarationName specification)

    -- 其他 Input 是前驱：在 handler 之前执行一次，输出不交给 handler。
    predecessor :: Unit -> EffectDeclaration -> [String]
    predecessor unit specification
      | inputOf specification == "Root" = []
      | Just _ <- rawSource unit specification = []
      | otherwise = maybeToList (methodOf (inputOf specification))

    -- 算法说明 v2（2026-11-16）：绑定时计算一次，composeMethods 与 Emit 都读取 bindingBefore。
    -- 先 requests 驱动，再 Input 前驱，最后 handler；close 与 Error 方法只执行 handler。
    -- 即使驱动链与 Input 链包含相同方法，也不能在这里 nub：两个声明的调用仍是两次执行。
    -- raw 的同次输出回放与 scope 的活实例共享在各自协议中判定，不由方法名相同推出。
    -- handler 绑定复用只复用实现，不合并不同 effect 的路由或不同挂载的调用。
    beforeOf :: Unit -> EffectDeclaration -> String -> [EntryStep String]
    beforeOf unit specification method
      | Just method == methodOf (declarationName specification) =
          map RequestStep (drives unit specification) ++ map InputStep (predecessor unit specification)
      | otherwise = []

    resultOf specification = declarationResult specification

    layerOf :: Unit -> EffectDeclaration -> String -> [Capability]
    layerOf unit specification method = map ReadsType
      (sortOn typeSpelling (nub [routeType route | route <- unitRoutes unit, routeEffect route == declarationName specification]))
      ++ [HasRaw | readsRaw specification method, Just _ <- [rawSource unit specification]]
      ++ [EndsSource | kindOf specification == StreamKind]
      ++ [EndsSubscription | consumesStream unit specification]
      ++ [if kindOf specification == PureKind then PureMonad else IOMonad]

    -- 算法说明 v2（2026-11-17）：endStream 给哪些 effect。
    -- 只给自己以 streams 订阅持续资产的 Excu：它是被持续资产驱动的消费方，endStream 结束的是它自己的订阅。
    -- 同一条链上的其他 effect（Input 前驱）和 lifelong 里不订阅的普通节点是原子操作，lifelong 只是插入它们的控制流，
    -- handler 的签名不随所处的控制流改变，因而可以在持续链与有限链之间复用。
    -- streams 只出现在被驱动的位置（lifelong 节点的订阅、持续 Context 被驱动的 Input 链），
    -- 运行时按当前调用的位置确定订阅，不需要业务说明结束哪一份资产。
    -- 只给 Excu：Scoped.open 被打断会使实例失效，Pure 是值变换，Stream 用 streamEnd。
    -- 代价：每个 effect 查一次自己的 demand。
    consumesStream :: Unit -> EffectDeclaration -> Bool
    consumesStream unit specification = kindOf specification == ExcuKind
      && or [Prototype.demandAccess demand == StreamAccess | demand <- Prototype.effectDemands (protoOf unit (declarationName specification))]

    signatureOf :: Unit -> String -> Either String Signature
    signatureOf unit handler' = do
      let bound = [(bindingEffect binding, (resultOf (specOf unit (bindingEffect binding)), bindingCapabilities binding))
            | binding <- unitBindings unit, bindingHandler binding == handler']
      case nub (map snd bound) of
        [(result, layer)] -> pure (Signature handler' result layer (nub (map fst bound)))
        _ -> Left ("Handler " ++ handler' ++ " is bound with different signatures: "
          ++ intercalate "; " [effect ++ " needs m (" ++ typeSpelling result ++ ") with " ++ intercalate ", " (map describeCapability layer) | (effect, (result, layer)) <- bound]
          ++ "; reuse a handler only where the binding kind and representation reads agree")

      where
        -- 用户诊断使用可写入 Layer 的约束；派生 Show/Read 继续服务纯检查点，不用于错误展示。
        -- 此处不导入 Emit：诊断描述不参与能力选择或生成代码。
        describeCapability capability = case capability of
          ReadsType value -> "SDK.Reads (" ++ typeSpelling value ++ ") m"
          HasRaw -> "SDK.Raw m"
          EndsSource -> "SDK.StreamEnds m"
          EndsSubscription -> "SDK.EndsStream m"
          PureMonad -> "Monad m"
          IOMonad -> "MonadIO m"

    -- 一个 effect 内每种表示类型至多出现一次；同类型的两个值需要角色类型（待定）。
    checkRepresentations :: Unit -> EffectDeclaration -> Either String ()
    checkRepresentations unit specification = do
      let keys = [(normalizeType (readType unit resolved), demandContract resolved) | resolved <- readDemands unit (declarationName specification)]
      case [representation' | (representation', _) <- keys, length (filter ((== representation') . fst) keys) > 1] of
        representation' : _ -> Left ("Effect " ++ declarationName specification ++ " reads several assets of representation "
          ++ representation' ++ " (" ++ intercalate ", " [contractType | (key, contractType) <- keys, key == representation']
          ++ "); one effect reads each representation type at most once")
        [] -> pure ()

    -- 资产名与 handler 派生名都进入生成区的同一命名空间，不能重名或与固定名冲突。
    checkGenerated :: Unit -> Either String ()
    checkGenerated unit = do
      let declared = map assetContract (unitAssets unit) ++ map branchName (unitBranches unit)
          derived = concat [[handlerClass handler', handlerLayer handler', handlerError handler', handlerFailure handler'] | handler' <- unitHandlers unit]
          reserved = reservedTypes ++ derived
      case [contractType | contractType <- nub declared, length (filter (== contractType) declared) > 1] of
        contractType : _ -> Left ("Contract " ++ contractType ++ " comes from more than one asset or branch; rename one of them")
        [] -> pure ()
      case [contractType | contractType <- nub declared, contractType `elem` reserved] of
        contractType : _ -> Left ("Asset or branch contract " ++ contractType
          ++ " collides with a generated name; rename the asset or constructor")
        [] -> pure ()
      case [handler' | handler' <- unitHandlers unit, not (validMethodName handler') || handler' `elem` reservedValues] of
        handler' : _ -> Left ("Handler name must be a lowercase identifier not used by generated code: " ++ handler')
        [] -> pure ()
      mapM_ (\(AssetDeclaration contractType representation' owner) -> do
          unless (validTypeName contractType) $
            Left ("Asset name must be a type name such as StartURL: " ++ contractType ++ " in " ++ owner)
          case representation' of
            TypeRef _ -> pure ()
            _ -> Left ("Context asset must wrap a business value, not Output: " ++ owner))
        (unitAssets unit)
      where
        validTypeName selectedName = case selectedName of
          first : rest -> isUpper first && all (\character -> isAlphaNum character || character `elem` "_'") rest
          [] -> False
        validMethodName selectedName = case selectedName of
          first : rest -> isLower first && all (\character -> isAlphaNum character || character `elem` "_'") rest
          [] -> False

