{-# LANGUAGE DuplicateRecordFields #-}
-- 一个入口的装配解释；由 Composition 调用，Emit 只读取结果。
module Framework.Gen.Injector (bindProgram) where
import Control.Monad (unless, when)
import Data.Char (isAlphaNum, isLower, isUpper)
import Data.List (intercalate, nub, nubBy, sortOn)
import Data.Maybe (listToMaybe, maybeToList)
import Framework.Gen.Plan
import Framework.Gen.Names
import Framework.Gen.Injector.Super (captureKindOf)
import Framework.Prototype.Graph (MethodRole(..))
import Framework.Language.Registration hiding (effectKind)
import Framework.Prototype.Types
import Framework.Prototype.Query
import qualified Framework.Prototype as Prototype

bindProgram :: String -> PrototypePlan -> [EffectDeclaration] -> Assembly String -> [(String, String)] -> Either String Unit
bindProgram namespace prepared declarations assembly controlled = do
  checkGenerated unit
  mapM_ (\specification -> scriptOf (declarationName specification))
    [specification | specification <- declarations, Just _ <- [methodOf (declarationName specification)]]
  when (null (unitTerminals unit)) (Left "Select at least one terminal effect for generation")
  mapM_ (checkRepresentations unit) (declarations)
  signatures <- mapM (signatureOf unit) (unitHandlers unit)
  pure unit { unitSignatures = signatures }
  where
    unit = Unit
      { unitNamespace = namespace
      , unitPlan = prepared
      , unitAssets = assets
      , unitHandlers = nub [handler' | specification <- declarations, (_, handler') <- [(method, handler) | (method, handler, _) <- declarationBindings specification]]
      , unitSignatures = []
      , unitBindings =
          [ Binding (declarationName specification) method handler' (beforeOf unit specification method)
              (if readsRaw specification method then rawSource unit specification else Nothing)
              [ (normalizeType (typeSpelling (routeType route)), (routeContract route, routeReader route))
              | route <- unitRoutes unit, routeEffect route == declarationName specification ]
              (entryResult specification) (entryOperation specification method) (layerOf unit specification method)
              (captureKindOf declarations (kindOf specification)) (rawKindOf specification method >>= captureKindOf declarations)
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
      , unitMiddleware = [(declarationName declared, declarationIntercept declared)
          | declared <- declarations, not (null (declarationIntercept declared))]
      , unitSupers = []
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
        view
          | continuousContract unit contractType = ContinuousView
          | otherwise = ValueView

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

    -- 契约读到的表示类型就是资产声明的表示类型。
    representationOf :: Unit -> String -> String
    representationOf unit contractType =
      case [reference (assetRepresentation declared) | declared <- unitAssets unit, assetContract declared == contractType] of
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

    -- 普通资产的 requests：生产它的 Context 与入口方法 getT。持续资产不在此列，见 sessionDemands。
    ordinaryDemands :: String -> [(ResolvedDemand, String)]
    ordinaryDemands selected =
      [ (resolved, getter) | resolved <- resolvedOf unit selected, demandAccess resolved == RequestAccess
      , not (continuousContract unit (demandContract resolved))
      , Just getter <- [producerMethodOf (demandProvider resolved)] ]

    -- 持续资产的 requests：入口启动或加入它的会话，取当前一条作为本次调用的固定交付。
    sessionDemands :: String -> [ResolvedDemand]
    sessionDemands selected =
      [ resolved | resolved <- resolvedOf unit selected
      , demandAccess resolved == RequestAccess, continuousContract unit (demandContract resolved) ]

    -- 算法说明 v3（2026-11-22）：消费链与生产分支。
    -- 一份普通资产的锚点：从生产它的 Context 沿 Input 跳过 Pure，遇到的第一个 Excu 或 Scoped。
    -- 锚点作为前驱注入请求方（消费链），Context 与中间的 Pure 是从锚点分出的生产分支，读锚点的同一次输出。
    -- 只有 Context 的生产链（Input 是 Root）没有锚点；持续资产的生产在会话里，也没有锚点。
    anchorOf :: String -> Maybe String
    anchorOf provider = walk (inputNamed provider) [provider]
      where
        walk selected seen
          | selected `elem` ["Root", "None"] || selected `elem` seen = Nothing
          | kindNamed selected == PureKind = walk (inputNamed selected) (selected : seen)
          | kindNamed selected `elem` [ExcuKind, ScopedKind] = Just selected
          | otherwise = Nothing
    kindNamed selected = effectKind (protoOf unit selected)
    inputNamed selected = effectInput (protoOf unit selected)

    -- 一个入口执行时会到达的 effect：声明的 Input、requests 的锚点与生产分支、rawinput 读到的上游，递归闭包。
    -- 约简只去掉闭包里已有的项，所以按未约简的关系求闭包即可；seen 防止有环时不终止，环由 scriptOf 报出。
    reaches :: String -> [String]
    reaches selected = case lookup selected reachTable of
      Just found -> found
      Nothing -> close [] [selected]
    reachTable = [(declarationName specification, close [] [declarationName specification]) | specification <- declarations]
    close seen [] = reverse seen
    close seen (next : rest)
      | next `elem` seen = close seen rest
      | otherwise = close (next : seen) (structural next ++ rest)
    structural selected = case [specification | specification <- declarations, declarationName specification == selected] of
      specification : _ ->
        declaredInputs specification
          ++ [anchor | (resolved, _) <- ordinaryDemands selected, Just anchor <- [anchorOf (demandProvider resolved)]]
          ++ [demandProvider resolved | (resolved, _) <- ordinaryDemands selected]
          ++ [inputOf specification | Just (RawList _) <- [rawSource unit specification]]
      [] -> []
    declaredInputs specification = [inputOf specification | not (null (predecessor unit specification))]

    -- 一个入口在 handler 之前的步骤：
    -- 1. 主线是声明的 Input 与各 requests 的锚点；某一项已在另一项的执行中到达时去掉它
    --    （锚点就是 Input 或在 Input 之上；Input 在锚点之上；锚点在另一锚点之上）。
    --    剩下的项互不在对方上游，没有先后依赖：执行顺序只取声明顺序（Input 先，requests 按书写顺序），
    --    不表示谁是谁的上游；有 scope 关系的项必然一个在另一个之上，不会落到这里。
    -- 2. 生产分支紧跟它的锚点所在的主线项；没有锚点的分支与持续资产的取得放在主线之后、handler 之前。
    -- 3. Scoped 的开启输入（资源与参数）排在最前：open 期间其他 IO 会先固定开启输入。
    -- 4. 数据约束优先于以上顺序：某项执行中读取的资产由本入口的另一分支生产时，生产分支先执行。
    --    约束成环、或某项的执行又到达本 effect 时，生成失败。
    scriptOf :: String -> Either String [EntryStep String]
    scriptOf selected = do
      case [item | item <- structural selected, item /= selected, selected `elem` reaches item] of
        item : _ -> Left ("Effect " ++ selected ++ " reaches itself through " ++ item
          ++ ": an asset it requests is produced from its own chain; remove the requests or the Input that closes the cycle")
        [] -> pure ()
      order selected planned
      where
        specification = specOf unit selected
        demands' = ordinaryDemands selected
        indexed = zip [0 :: Int ..] demands'
        sessions = zip [0 :: Int ..] (sessionDemands selected)
        inputs0 = declaredInputs specification
        anchors0 = nub [anchor | (resolved, _) <- demands', Just anchor <- [anchorOf (demandProvider resolved)]]
        anchors = [ anchor | anchor <- anchors0, anchor `notElem` inputs0
          , not (any (\input -> anchor `elem` reaches input) inputs0)
          , not (any (\other -> other /= anchor && anchor `elem` reaches other) anchors0) ]
        inputs = [input | input <- inputs0, not (any (\anchor -> input `elem` reaches anchor) anchors)]
        mainline = zip [0 :: Int ..] (inputs ++ anchors)
        holder resolved = anchorOf (demandProvider resolved) >>= \anchor ->
          listToMaybe [position | (position, item) <- mainline, item == anchor || anchor `elem` reaches item]
        proto = protoOf unit selected
        opening = effectOpeningInputs proto ++ maybeToList (effectResource proto)
        isOpening resolved = kindNamed selected == ScopedKind && demandProvider resolved `elem` opening
        openingHolders = nub [position | (_, (resolved, _)) <- indexed, isOpening resolved, Just position <- [holder resolved]]
        produced position = [demandProvider resolved | (resolved, _) <- demands', holder resolved == Just position]
        mainStep (position, item)
          | item `elem` inputs = InputStep (entry item)
          | otherwise = AnchorStep (entry item) (produced position)
        planned =
          [ (mainStep main, if fst main `elem` openingHolders then [0, fst main] else [2, fst main, 0], [], reaches (snd main))
          | main <- mainline ]
          ++ [ (RequestStep getter, key, [demandContract resolved], reaches (demandProvider resolved))
             | (index, (resolved, getter)) <- indexed
             , let key | isOpening resolved = [1, index]
                       | Just position <- holder resolved, position `elem` openingHolders = [1, 1000 + index]
                       | Just position <- holder resolved = [2, position, 1, index]
                       | otherwise = [3, index] ]
          ++ [ (SessionRequestStep (demandProvider resolved), if isOpening resolved then [1, 2000 + index] else [3, 1000 + index]
               , [demandContract resolved], [])
             | (index, resolved) <- sessions ]
        entry item = case methodOf item of
          Just method -> method
          Nothing -> error ("Validated chain has no entry: " ++ item)

    -- 按键排序的拓扑排序：数据约束是硬约束，键只在已经可以执行的项之间选择。
    order :: String -> [(EntryStep String, [Int], [String], [String])] -> Either String [EntryStep String]
    order selected = go []
      where
        go done [] = pure (reverse done)
        go done remaining =
          case sortOn key [item | item <- remaining, ready remaining item] of
            item : _ -> go (step item : done) (filter ((/= key item) . key) remaining)
            [] -> Left ("Effect " ++ selected ++ " cannot order its requests: "
              ++ intercalate "; " (map describe remaining)
              ++ "; each of these reads an asset another one produces")
        ready remaining item = not (any (\other -> key other /= key item && blocks other item) remaining)
        blocks producer consumer = any (`elem` readsOf consumer) (producesOf producer)
        readsOf (_, _, _, reached) = nub [demandContract resolved | effect <- reached, effect /= selected
          , resolved <- resolvedOf unit effect, readsAccess (demandAccess resolved)]
        producesOf (_, _, produced', _) = produced'
        step (value, _, _, _) = value
        key (_, value, _, _) = value
        describe (value, _, produced', _) = show value ++ (if null produced' then "" else " produces " ++ intercalate ", " produced')

    -- 挂接的 parser 与 Pure 用 rawinput 读取直接 Input 的输出，不把 Input 当前驱执行：
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

    -- 绑定时计算一次，composeMethods 与 Emit 都读取 bindingBefore；close 与 Error 方法只执行 handler。
    -- 同一次调用中同一 effect 只执行一次（运行时记录本次输出），所以步骤之间共享的上游不会重复执行。
    -- handler 绑定复用只复用实现，不合并不同 effect 的路由或不同挂载的调用。
    -- scriptOf 的错误已在 bindProgram 开头报出，这里只取结果。
    beforeOf :: Unit -> EffectDeclaration -> String -> [EntryStep String]
    beforeOf _ specification method
      | Just method == methodOf (declarationName specification) =
          either (error . ("Validated script failed: " ++)) id (scriptOf (declarationName specification))
      | otherwise = []

    resultOf specification = declarationResult specification

    -- rawinput 读到的是直接 Input 那次原子调用交出的值，捕获按 Input 的类别匹配。
    rawKindOf :: EffectDeclaration -> String -> Maybe EffectKind
    rawKindOf specification method
      | readsRaw specification method, Just _ <- rawSource unit specification =
          Just (effectKind (protoOf unit (inputOf specification)))
      | otherwise = Nothing

    layerOf :: Unit -> EffectDeclaration -> String -> [Capability]
    layerOf unit specification method
      | kindOf specification == MiddlewareKind = [ObservesHooks, WritesRaw, IOMonad]
      | otherwise = map ReadsType
      (sortOn typeSpelling (nub [routeType route | route <- unitRoutes unit, routeEffect route == declarationName specification]))
      -- x:xs 读取：只给以 streams 读取持续资产的路由，由声明决定，首次生成契约时即确定。
      ++ map StreamsType (sortOn typeSpelling (nub
          [ routeType route | route <- unitRoutes unit, routeEffect route == declarationName specification
          , routeView route == ContinuousView, streamsContract unit (declarationName specification) (routeContract route) ]))
      ++ [HasRaw | readsRaw specification method, Just _ <- [rawSource unit specification]]
      ++ [WritesRaw | resultOf specification == NativeType "[String]"]
      ++ (if kindOf specification == StreamKind then [EmitsItem, EndsSource, MasksExceptions] else [])
      ++ [EndsSubscription | consumesStream unit specification]
      ++ [if kindOf specification == PureKind then PureMonad else IOMonad]

    -- 算法说明 v2（2026-11-17）：endStream 给哪些 effect。
    -- 只给自己以 streams 订阅持续资产的 Excu：它是被持续资产驱动的消费方，endStream 结束的是它自己的订阅。
    -- 同一条链上的其他 effect（Input 前驱）和 lifelong 里不订阅的普通节点是原子操作，lifelong 只是插入它们的控制流，
    -- handler 的签名不随所处的控制流改变，因而可以在持续链与有限链之间复用。
    -- streams 只出现在被驱动的位置（lifelong 节点的订阅、持续 Context 被驱动的 Input 链），
    -- 运行时按当前调用的位置确定订阅，不需要业务说明结束哪一份资产。
    -- 只给 Excu：Scoped.open 被打断会使实例失效，Pure 是值变换，Stream 用 streamEnd。
    -- behavior 与 event 以 requests 订阅：同一个 requests 在 lifelong 之外只是一次生产，
    -- 所以这两种订阅方按它在 lifelong 内被订阅驱动的挂载给出 endStream。
    -- 代价：每个 effect 查一次自己的 demand 与 lifelong 订阅表。
    consumesStream :: Unit -> EffectDeclaration -> Bool
    consumesStream unit specification = kindOf specification == ExcuKind
      && (or [Prototype.demandAccess demand == StreamAccess | demand <- Prototype.effectDemands (protoOf unit (declarationName specification))]
        || declarationName specification `elem` subscribers)
      where
        tree = plannedWorkflow (unitPlan unit)
        subscribers = [ terminal | (_, described) <- workflowLifelongs tree, (node, _) <- lifelongSubscriptions described
          , Just (NodeAt _ terminal) <- [lookupWorkflow tree node] ]
    -- 本 effect 以 streams 读取该契约：Layer 才带 Streams。
    streamsContract :: Unit -> String -> String -> Bool
    streamsContract unit selectedName contractType = or
      [ Prototype.demandAccess demand == StreamAccess && Prototype.demandContract demand == contractType
      | demand <- Prototype.effectDemands (protoOf unit selectedName) ]

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
          StreamsType value -> "SDK.Streams (" ++ typeSpelling value ++ ") m"
          HasRaw -> "SDK.Raw m"
          WritesRaw -> "SDK.RawOutputs m"
          EmitsItem -> "SDK.Emits m"
          EndsSource -> "SDK.StreamEnds m"
          MasksExceptions -> "SDK.MonadMask m"
          EndsSubscription -> "SDK.EndsStream m"
          ObservesHooks -> "SDK.Hooks m"
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
      let declared = map assetContract (unitAssets unit)
          derived = concat [[handlerClass handler', handlerLayer handler', handlerError handler', handlerFailure handler'] | handler' <- unitHandlers unit]
          reserved = reservedTypes ++ derived
      case [contractType | contractType <- nub declared, length (filter (== contractType) declared) > 1] of
        contractType : _ -> Left ("Contract " ++ contractType ++ " comes from more than one asset; rename one of them")
        [] -> pure ()
      case [contractType | contractType <- nub declared, contractType `elem` reserved] of
        contractType : _ -> Left ("Asset contract " ++ contractType
          ++ " collides with a generated name; rename the asset")
        [] -> pure ()
      case [handler' | handler' <- unitHandlers unit, not (validMethodName handler') || handler' `elem` reservedValues] of
        handler' : _ -> Left ("Handler name must be a lowercase identifier not used by generated code: " ++ handler')
        [] -> pure ()
      mapM_ (\(AssetDeclaration contractType representation' owner) -> do
          unless (validTypeName contractType) $
            Left ("Asset name must be a type name such as StartURL: " ++ contractType ++ " in " ++ owner)
          case representation' of
            TypeRef _ _ -> pure ()
            _ -> Left ("Context asset must wrap a business value, not Output: " ++ owner))
        (unitAssets unit)
      where
        validTypeName selectedName = case selectedName of
          first : rest -> isUpper first && all (\character -> isAlphaNum character || character `elem` "_'") rest
          [] -> False
        validMethodName selectedName = case selectedName of
          first : rest -> isLower first && all (\character -> isAlphaNum character || character `elem` "_'") rest
          [] -> False

