{-# LANGUAGE DuplicateRecordFields #-}

-- 绑定：降级之后，按注册确定每个 handler 绑定的全部事实——入口前的驱动与 Input 前驱、raw 的来源、
-- 按表示类型的读取路由、handler 的方法类型与 Layer——并做绑定级检查。
-- 读取来源、前驱与驱动都在这里定下来，运行时不再按调用者查找；Emit 只渲染这些事实。
-- handler 方法体的结构随后由 composeMethods 按每个绑定换成 effect 方法的结构，交给构图。
module Framework.Gen.Bind
  ( Unit(..), Binding(..), Signature(..), AssetDeclaration(..), BranchContract(..), bindProgram
  , specifications, effectPrototypes, specOf, protoOf, resolvedOf, contextSpecs, allMethods
  , readDemands, readType, readerOf, continuousContract, beforeOf, rawExpression, readsRaw, resultOf, reference, parenthesized
  , composeMethods, normalizeType
  ) where

import Control.Monad (unless, when)
import Data.Char (isAlphaNum, isLower, isSpace, isUpper)
import Data.List (intercalate, nub, sort)
import Data.Maybe (maybeToList)
import Framework.Gen.Demand (readsAccess)
import Framework.Gen.Names
import Framework.Language.Registration
import Framework.Prototype.Graph (MethodRole(..), MethodShape(..))
import Framework.Prototype.Types (PrototypePlan, ResolvedDemand(..), SumTypes)
import qualified Framework.Prototype as Prototype

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

-- handler 的签名由绑定类别与 effect 的 demands 推出；同一 handler 的所有绑定必须一致。
-- layer 不含 Raises：它总是本 handler 的错误，由输出时补入。
data Signature = Signature
  { signatureHandler :: String
  , signatureResult :: String
  , signatureLayer :: [String]
  , signatureEffects :: [String]
  } deriving (Eq, Show)

-- 每个 Context 的契约类型由声明的资产名生成。
data AssetDeclaration = AssetDeclaration
  { assetContract :: String
  , assetRepresentation :: TypeRef
  , assetOwner :: String
  } deriving (Eq, Show)

-- 表示类型是和类型（至少两个构造器）时，每个构造器另有分支契约：契约名加构造器名。
-- 分支契约是基础契约的投影，读到构造器的字段（无字段为 ()）。
data BranchContract = BranchContract
  { branchName :: String
  , branchBase :: String
  , branchConstructor :: String
  , branchField :: Maybe String
  , branchOwner :: String
  } deriving (Eq, Show)

-- 一份程序的绑定结果：降级计划加上 gen 推出的资产、分支契约、handler 签名、绑定与末端入口。
data Unit = Unit
  { unitNamespace :: String
  , unitPlan :: PrototypePlan
  , unitAssets :: [AssetDeclaration]
  , unitBranches :: [BranchContract]
  , unitHandlers :: [String]
  , unitSignatures :: [Signature]
  , unitBindings :: [Binding]
  -- (末端 effect, 原始入口方法)；顺序即 AST 中首次出现的顺序。
  , unitTerminals :: [(String, String)]
  -- effect → handler 方法体必须读取的契约（requires／streams 中没有被 workflow 控制流使用的部分）。
  , unitReads :: [(String, [String])]
  }

-- 绑定阶段的入口：推出全部事实，再按原顺序检查生成名字、末端、表示类型与签名。
bindProgram :: String -> PrototypePlan -> SumTypes -> Either String Unit
bindProgram namespace prepared sumTypes = do
  checkGenerated unit
  when (null terminals) (Left "Select at least one terminal effect for generation")
  entries <- mapM (findEntry unit) terminals
  mapM_ (checkRepresentations unit) (specifications unit)
  signatures <- mapM (signatureOf unit) (unitHandlers unit)
  pure unit { unitTerminals = zip terminals entries, unitSignatures = signatures }
  where
    unit = Unit
      { unitNamespace = namespace
      , unitPlan = prepared
      , unitAssets = assets
      , unitBranches = branches
      , unitHandlers = nub [handler' | specification <- specifications unit, (_, handler') <- handlerBindings specification]
      , unitSignatures = []
      , unitBindings =
          [ Binding (name specification) method handler' (beforeOf unit specification method)
              (if readsRaw specification method then rawSource unit specification else Nothing)
              [ (normalizeType (readType unit "History" resolved), (demandContract resolved, readerOf unit (demandProvider resolved)))
              | resolved <- readDemands unit (name specification) ]
          | specification <- specifications unit, (method, handler') <- handlerBindings specification ]
      , unitTerminals = []
      , unitReads =
          [ (name specification, nub
              [ demandContract resolved | resolved <- resolvedOf unit (name specification), readsAccess (demandAccess resolved)
              , (name specification, demandContract resolved) `notElem` controlled ])
          | specification <- specifications unit ]
      }
    terminals = nub (Prototype.workflowTerminals (Prototype.plannedWorkflow prepared))
    controlled = controlReads (Prototype.plannedEffects prepared) (Prototype.plannedWorkflow prepared)
    assets =
      [ AssetDeclaration (contractOf declared) (representation declared) (name specification)
      | specification <- contextSpecs unit
      , Just declared <- [contextAsset (typing specification)] ]
    branches =
      [ BranchContract (base ++ constructor) base constructor field owner
      | AssetDeclaration base (TypeRef typeName) owner <- assets
      , (branch, constructor) <- Prototype.effectBranches (protoOf unit owner)
      , Just constructors <- [lookup typeName sumTypes]
      , Just field <- [lookup constructor constructors]
      , branch == base ++ constructor ]

specifications :: Unit -> [EffectSpec]
specifications = Prototype.plannedRegistrations . unitPlan

effectPrototypes :: Unit -> [Prototype.EffectProto String]
effectPrototypes = Prototype.plannedEffects . unitPlan

protoOf :: Unit -> String -> Prototype.EffectProto String
protoOf unit selectedName = case [effect | effect <- effectPrototypes unit, Prototype.effectName effect == selectedName] of
  effect : _ -> effect
  [] -> error ("Validated prototype has no effect: " ++ selectedName)

specOf :: Unit -> String -> EffectSpec
specOf unit selectedName = case [specification | specification <- specifications unit, name specification == selectedName] of
  specification : _ -> specification
  [] -> error ("Validated registration has no effect: " ++ selectedName)

resolvedOf :: Unit -> String -> [ResolvedDemand]
resolvedOf unit = Prototype.effectDemands . protoOf unit

contextSpecs :: Unit -> [EffectSpec]
contextSpecs = filter ((== ContextKind) . effectKind . typing) . specifications

allMethods :: Unit -> [String]
allMethods unit = [method | effect <- effectPrototypes unit, (_, method) <- Prototype.effectMethods effect]

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

-- requires 读最新值，streams 读历史。
readType :: Unit -> String -> ResolvedDemand -> String
readType unit historyType resolved = case demandAccess resolved of
  StreamAccess -> historyType ++ " (" ++ representationOf unit (demandContract resolved) ++ ")"
  _ -> representationOf unit (demandContract resolved)

readDemands :: Unit -> String -> [ResolvedDemand]
readDemands unit selectedName = [resolved | resolved <- resolvedOf unit selectedName, readsAccess (demandAccess resolved)]

readerOf :: Unit -> String -> String
readerOf unit provider = case contextReader (typing (specOf unit provider)) of
  Just method -> method
  Nothing -> error ("Validated demand has no reader: " ++ provider)

-- 驱动：requests 声明的资产在入口先调用 getT，沿 Input 驱动它的整条 Context 链。
drives :: Unit -> EffectSpec -> [String]
drives unit specification =
  [ getter | resolved <- resolvedOf unit (name specification), demandAccess resolved == RequestAccess
  , Just getter <- [contextProducer (typing (specOf unit (demandProvider resolved)))] ]

-- 挂接的 parser 与 Pure 用 raw 读取直接 Input 的输出，不把 Input 当前驱执行：
-- Input 是 Excu、Scoped、Pure 时读它交出的 list，是 Stream 时读会话本次取得的一份输入。
rawSource :: Unit -> EffectSpec -> Maybe String
rawSource unit specification
  | rawKind (typing specification), input specification /= "Root" = case typing (specOf unit (input specification)) of
      Excu _ -> entryMethod (specOf unit (input specification))
      Scoped {} -> entryMethod (specOf unit (input specification))
      Pure _ -> entryMethod (specOf unit (input specification))
      Stream _ -> entryMethod (specOf unit (input specification))
      _ -> Nothing
  | otherwise = Nothing
  where
    rawKind Context {} = True
    rawKind (Pure _) = True
    rawKind _ = False

-- 读取 raw 的方法：Context 的 parser（生产入口）与 Pure 的入口。
readsRaw :: EffectSpec -> String -> Bool
readsRaw specification method = case typing specification of
  selected@Context {} -> Just method == contextProducer selected
  Pure _ -> Just method == entryMethod specification
  _ -> False

-- Stream 一次交出一份 String；raw 统一是 list，所以读作单元素 list。
rawExpression :: Unit -> EffectSpec -> Maybe String
rawExpression unit specification = case rawSource unit specification of
  Just method | Stream {} <- typing (specOf unit (input specification)) -> Just ("(: []) <$> " ++ method)
  other -> other

-- 其他 Input 是前驱：在 handler 之前执行一次，输出不交给 handler。
predecessor :: Unit -> EffectSpec -> [String]
predecessor unit specification
  | input specification == "Root" = []
  | Just _ <- rawSource unit specification = []
  | otherwise = maybeToList (entryMethod (specOf unit (input specification)))

-- handler 之前调用的 effect 方法：入口方法先驱动再执行 Input；close 与 Error 方法只执行 handler。
beforeOf :: Unit -> EffectSpec -> String -> [String]
beforeOf unit specification method
  | Just method == entryMethod specification = drives unit specification ++ predecessor unit specification
  | otherwise = []

-- 绑定类别决定方法类型：原子句柄与 Pure 都交出 [String]。
resultOf :: EffectSpec -> String
resultOf specification = case typing specification of
  Pure _ -> "[String]"
  Excu _ -> "[String]"
  Scoped {} -> "[String]"
  Error {} -> "()"
  Stream _ -> "String"
  Context { asset = declared } -> reference (representation declared)

layerOf :: Unit -> EffectSpec -> String -> [String]
layerOf unit specification method = sort (nub ["SDK.Reads (" ++ readType unit "SDK.History" resolved ++ ") m"
    | resolved <- readDemands unit (name specification)])
  ++ ["SDK.Raw m" | readsRaw specification method, Just _ <- [rawSource unit specification]]
  -- end 只属于 Stream handler：来源自己在取下一份输入时报告结束。
  ++ ["SDK.Ends m" | effectKind (typing specification) == StreamKind]
  ++ [if effectKind (typing specification) == PureKind then "Monad m" else "MonadIO m"]

signatureOf :: Unit -> String -> Either String Signature
signatureOf unit handler' = do
  let bound = [(name specification, (resultOf specification, layerOf unit specification method))
        | specification <- specifications unit, (method, selectedHandler) <- handlerBindings specification, selectedHandler == handler']
  case nub (map snd bound) of
    [(result, layer)] -> pure (Signature handler' result layer (nub (map fst bound)))
    _ -> Left ("Handler " ++ handler' ++ " is bound with different signatures: "
      ++ intercalate "; " [effect ++ " needs m (" ++ result ++ ") with " ++ intercalate ", " layer | (effect, (result, layer)) <- bound]
      ++ "; reuse a handler only where the binding kind and representation reads agree")

-- 一个 effect 内每种表示类型至多出现一次；同类型的两个值需要角色类型（待定）。
checkRepresentations :: Unit -> EffectSpec -> Either String ()
checkRepresentations unit specification = do
  let keys = [(normalizeType (readType unit "History" resolved), demandContract resolved) | resolved <- readDemands unit (name specification)]
  case [representation' | (representation', _) <- keys, length (filter ((== representation') . fst) keys) > 1] of
    representation' : _ -> Left ("Effect " ++ name specification ++ " reads several assets of representation "
      ++ representation' ++ " (" ++ intercalate ", " [contractType | (key, contractType) <- keys, key == representation']
      ++ "); one effect reads each representation type at most once")
    [] -> pure ()

-- 降级已验证挂载；这里只取原型指定的原始入口。
findEntry :: Unit -> String -> Either String String
findEntry unit selectedName = case
  [method | (role, method) <- Prototype.effectMethods (protoOf unit selectedName)
          , role `elem` [HandlerMethod, ScopeOpen]] of
  [method] -> Right method
  _ -> Left ("Prototype has no origin entry: " ++ selectedName)

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

reference :: TypeRef -> String
reference (TypeRef typeName) = typeName
reference (OutputRef cause value) = "SDK.Output (" ++ reference cause ++ ") (" ++ reference value ++ ")"

-- 含空格且尚未整体括起的类型加括号。
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
          ++ "; only a Context parser or a Pure hanging below an Excu, Scoped, Pure or Stream reads raw")
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
