{-# LANGUAGE DuplicateRecordFields #-}
-- 编译检查点的纯计划。这里不执行组合解释；运行时所需结构属于 Prototype。
module Framework.Gen.Plan
  ( EffectDeclaration(..), ErrorPlan(..), ScopePlan(..), Unit(..), Binding(..), Signature(..), AssetDeclaration(..)
  , ValueType(..), Capability(..), EntryOperation(..), ReadRoute(..), ReadView(..)
  , ReaderPlan(..), SelectorPlan(..), SessionEntry(..), SuperSelection(..)
  , Assembly(..), EntryMount(..), OutputConnection(..), EntryStep(..), RawSource(..)
  , rawMethod, bindingCalls, bindingSessionRequests, unitTerminals, mountHooks, unitVariants
  , effectPrototypes, protoOf, effectSlot, slotLiteral, allMethods, streamedRoutes, historyEntry, historyEntries
  , reference, parenthesized, normalizeType, readsAccess ) where

import Data.Char (isSpace, isUpper)
import Data.List (nub)
import Framework.Language.Registration hiding (effectKind)
import Framework.Prototype.Graph (MethodRole)
import Framework.Prototype.Types
import qualified Framework.Prototype as Prototype

-- Composition 已解释注册；Injector 只接收这些绑定事实，不再检查原始 typing。
data EffectDeclaration = EffectDeclaration
  { declarationName :: String
  , declarationEntry :: Maybe String
  , declarationAsset :: Maybe Asset
  , declarationBindings :: [(String, String, EntryOperation)]
  , declarationResult :: ValueType
  , declarationErrors :: Maybe [Handles]
  -- Middleware 拦截的类别；其他注册为空。
  , declarationIntercept :: [EffectKind]
  } deriving (Eq, Show, Read)

data ErrorPlan = ErrorPlan
  { errorEffect :: String, errorScope :: Maybe String, errorMatches :: [Handles]
  , errorDetect :: Maybe String, errorResolve :: Maybe String
  } deriving (Eq, Show, Read)

data ScopePlan = ScopePlan
  { scopeEffect :: String, scopeInputs :: [String], scopeResource :: Maybe String
  , scopeCleanup :: Maybe String
  } deriving (Eq, Show, Read)

-- 接口结果先有结构，再由 Emit 加 Haskell 模块限定。不能通过已渲染的 typeclass 文本重新选择装配。
data ValueType = NativeType String | RefinedType String
  deriving (Eq, Ord, Show, Read)

data Capability = ReadsType ValueType | StreamsType ValueType | HasRaw | WritesRaw | EmitsItem | EndsSource | MasksExceptions | EndsSubscription | ObservesHooks | PureMonad | IOMonad
  deriving (Eq, Show, Read)

-- 每个入口的解释已经确定；Emit 仅把该操作翻译成现有 runtime 包装，不再查看 typing。
data EntryOperation
  = AtomicOperation | OpenResource | CloseResource | SourceStep | PureOperation | PublishAsset String | ErrorOperation
  | MiddlewareOperation
  deriving (Eq, Show, Read)

-- 读取结果始终是声明的表示类型。持续来源使用固定交付；是否反复执行由挂载/会话计划决定。
-- 业务可以把记录或统计声明为普通 ADT，编译器不为这类内容另外包装或选驱动。
data ReadView = ValueView | ContinuousView
  deriving (Eq, Show, Read)

data ReadRoute = ReadRoute
  { routeEffect :: String, routeType :: ValueType, routeContract :: String
  , routeProvider :: String, routeReader :: String, routeView :: ReadView
  } deriving (Eq, Show, Read)

data ReaderPlan = ReaderPlan
  { readerEffect :: String, readerMethod :: String, readerContract :: String, readerContinuous :: Bool
  } deriving (Eq, Show, Read)

-- alternative 的选择入口：共同 Excu 的入口方法，以及按候选声明顺序排列的（判定 Context，其生产方法）。
data SelectorPlan = SelectorPlan
  { selectorSource :: String, selectorEntry :: String
  , selectorCases :: [(String, String)]
  } deriving (Eq, Show, Read)

data SessionEntry
  = ReceiveEntry String (EntryMount String) (EntryMount String)
  | DeriveEntry String (EntryMount String)
  deriving (Eq, Show, Read)

-- 入口在 handler 之前依次执行的步骤，顺序由 Injector 的消费链排序确定（算法说明 v3）。
-- InputStep：声明的 Input 前驱。AnchorStep：requests 的资产生产链上的 Excu／Scoped（锚点），
-- 作为前驱注入，附带它为本入口生产的 Context（这些 Context 的 parser 读它的同一次输出）。
-- RequestStep：普通资产的 Context 入口，即从锚点分出的生产分支。
-- SessionRequestStep：requests 一份持续资产，记生产它的 Context；入口启动或加入它的会话并取当前一条，
-- 不是方法调用，不进入方法图。
-- 同一次调用中同一 effect 只执行一次：再次到达时运行时返回它本次的输出（Excu、Scoped、Pure）或发布（Context）。
data EntryStep method = RequestStep method | InputStep method | AnchorStep method [String] | SessionRequestStep String
  deriving (Eq, Show, Read)

-- rawinput 的直接输入在本模块的绑定转换中解析。RawStream 记录结构上的来源方法；运行时读取本次 rawemit 的单元素 list；
-- 其余输入交出 list。同一次调用中上游已执行时读它本次的输出（runOnce），不缓存另一调用的结果。
data RawSource method = RawList method | RawStream method
  deriving (Eq, Show, Read)

rawMethod :: RawSource method -> method
rawMethod (RawList method) = method
rawMethod (RawStream method) = method

-- 一个静态挂载；NodeId 保留每次 AST 出现的位置，同方法不合并挂载。
-- terminal 是结构展示的末端/契约，target 是运行入口的诊断标签：
-- 会话中 terminal 是资产名，target 分别是 Stream 与 parser 的 effect 名。
data EntryMount method = EntryMount
  { mountNode :: NodeId
  , mountRole :: ChainRole
  , mountTerminal :: String
  , mountTarget :: String
  , mountMethod :: method
  } deriving (Eq, Show, Read)

-- 同次输出的连接：anchor → parser。role 为 ContextRequest 是普通生产分支（输出联立：锚点每次执行都解析
-- 并写入最新值），ContextStream 是持续分支（只在原型指定的发布位置交给会话）。解析失败都沿原链传播。
-- 每次注入只能回放当前 anchor，不能借此跳过其他前驱。
data OutputConnection method = OutputConnection
  { outputAnchor :: method
  , outputParser :: method
  , outputProducer :: String
  , outputRole :: MethodRole
  } deriving (Eq, Show, Read)

data Assembly method = Assembly
  { assemblyMounts :: [EntryMount method]
  , assemblyOutputs :: [OutputConnection method]
  , assemblySessions :: [SessionProto]
  , assemblyFiniteSessions :: [SessionProto]
  } deriving (Eq, Show, Read)

-- 一次绑定：handler 在某个 effect 方法中执行。
-- before 保存有角色的有序步骤（先驱动，后 Input），bindingRaw 保存直接 Input 及其输出形状；
-- routes 把规范化的表示类型映射到 (契约, 读取方法)。结构分析据此把 handler 方法体换成 effect 方法的结构。
data Binding = Binding
  { bindingEffect :: String
  , bindingMethod :: String
  , bindingHandler :: String
  , bindingBefore :: [EntryStep String]
  , bindingRaw :: Maybe (RawSource String)
  , bindingRoutes :: [(String, (String, String))]
  , bindingResult :: ValueType
  , bindingOperation :: EntryOperation
  , bindingCapabilities :: [Capability]
  -- Injector 选定的 super 捕获类别；Nothing 使用 Root 的直接调用。
  , bindingCaptureKind :: Maybe EffectKind
  -- rawinput 读到的那次原子调用的类别；rawinput 的捕获按它匹配。
  , bindingRawKind :: Maybe EffectKind
  } deriving (Eq, Show, Read)

-- handler 的签名由绑定类别与 effect 的 demands 推出；同一 handler 的所有绑定必须一致。
-- layer 不含 Raises：它总是本 handler 的错误，由输出时补入。
data Signature = Signature
  { signatureHandler :: String
  , signatureResult :: ValueType
  , signatureLayer :: [Capability]
  , signatureEffects :: [String]
  } deriving (Eq, Show, Read)

-- 每个 Context 的契约类型由声明的资产名生成。
data AssetDeclaration = AssetDeclaration
  { assetContract :: String
  , assetRepresentation :: TypeRef
  , assetOwner :: String
  } deriving (Eq, Show, Read)

-- 一份程序的绑定结果：降级计划加上 gen 推出的资产、handler 签名、绑定与末端入口。
data Unit = Unit
  { unitNamespace :: String
  , unitPlan :: PrototypePlan
  , unitAssets :: [AssetDeclaration]
  , unitHandlers :: [String]
  , unitSignatures :: [Signature]
  , unitBindings :: [Binding]
  -- 已解析的挂载与输出连接；构图、来源分析与输出共用。
  , unitAssembly :: Assembly String
  -- effect → handler 方法体必须读取的契约（requires／streams 中没有被 workflow 控制流使用的部分）。
  , unitReads :: [(String, [String])]
  , unitRoutes :: [ReadRoute]
  , unitReaders :: [ReaderPlan]
  , unitSelectors :: [SelectorPlan]
  , unitSessionEntries :: [SessionEntry]
  , unitScopes :: [ScopePlan]
  , unitErrors :: [ErrorPlan]
  , unitScopeOrder :: [String]
  -- Middleware → 它拦截的类别（注册顺序）。
  , unitMiddleware :: [(String, [EffectKind])]
  -- superhandler 的静态选择，由 Injector.Super 在会话入口确定后计算。
  , unitSupers :: [SuperSelection]
  } deriving (Eq, Show, Read)

-- 某个 Middleware 列表在某个捕获类别上要调用的 Middleware（注册顺序）；空表示 Root 直接执行 action。
data SuperSelection = SuperSelection
  { selectionHooks :: [String]
  , selectionKind :: EffectKind
  , selectionMiddleware :: [String]
  } deriving (Eq, Show, Read)

-- 绑定阶段的入口：推出全部事实，再按原顺序检查生成名字、末端、表示类型与签名。
effectPrototypes :: Unit -> [Prototype.EffectProto String]
effectPrototypes = Prototype.plannedEffects . unitPlan

protoOf :: Unit -> String -> Prototype.EffectProto String
protoOf unit selectedName = case [effect | effect <- effectPrototypes unit, Prototype.effectName effect == selectedName] of
  effect : _ -> effect
  [] -> error ("Validated prototype has no effect: " ++ selectedName)

-- gen 的 effect 编号：effect 在 plannedEffects（即 Prototype 的 protoEffects）中的位置。
-- 运行时的原型索引按同一规则编号，生成代码里的 Slot 字面量因此与 Prototype 一致。
effectSlot :: Unit -> String -> Int
effectSlot unit selectedName = case [number | (number, effect) <- zip [0 ..] (effectPrototypes unit)
    , Prototype.effectName effect == selectedName] of
  number : _ -> number
  [] -> error ("Validated prototype has no effect: " ++ selectedName)

-- 生成代码中的编号字面量；名字只用于诊断与展示。prefix 是 SDK 模块的限定名。
slotLiteral :: String -> Unit -> String -> String
slotLiteral prefix unit selectedName = "(" ++ prefix ++ "Slot " ++ show (effectSlot unit selectedName) ++ " " ++ show selectedName ++ ")"

allMethods :: Unit -> [String]
allMethods unit = [method | effect <- effectPrototypes unit, (_, method) <- Prototype.effectMethods effect]

-- x:xs 读取的路由：持续资产，且所在 effect 的 Layer 带对应的 Streams 能力。
streamedRoutes :: Unit -> [ReadRoute]
streamedRoutes unit =
  [ route | route <- unitRoutes unit, routeView route == ContinuousView
  , any (\binding -> bindingEffect binding == routeEffect route && StreamsType (routeType route) `elem` bindingCapabilities binding)
      (unitBindings unit) ]

-- 每个被 streams 读取的持续契约一个历史读取入口；名字前缀不与任何 effect 方法前缀相同。
historyEntry :: String -> String
historyEntry contractType = "history" ++ contractType

historyEntries :: Unit -> [String]
historyEntries unit = nub [historyEntry (routeContract route) | route <- streamedRoutes unit]

bindingCalls :: Binding -> [String]
bindingCalls binding = [method | step <- bindingBefore binding, method <- callOf step]
  where
    callOf (RequestStep method) = [method]
    callOf (InputStep method) = [method]
    callOf (AnchorStep method _) = [method]
    callOf (SessionRequestStep _) = []

-- 入口先取得的持续资产（生产它的 Context 名），在 Input 前驱与 handler 之前。
bindingSessionRequests :: Binding -> [String]
bindingSessionRequests binding = [producer | SessionRequestStep producer <- bindingBefore binding]

-- 一个挂载被哪些 Middleware 覆盖（注册顺序）；与 Prototype 的 drivingHooks 用同一计算。
mountHooks :: Unit -> NodeId -> [String]
mountHooks unit = Prototype.hooksAt (map fst (unitMiddleware unit)) (plannedMiddleware (unitPlan unit))

-- 挂载登记用到的 Middleware 列表：各挂载实际出现的非空列表。
unitVariants :: Unit -> [[String]]
unitVariants unit = nub [hooks | mount <- assemblyMounts (unitAssembly unit)
  , let hooks = mountHooks unit (mountNode mount), not (null hooks)]

-- Target 的实现可共用，挂载身份仍全部保存在 assemblyMounts；这里只投影生成的入口目录。
unitTerminals :: Unit -> [(String, String)]
unitTerminals unit = nub [(mountTerminal mount, mountMethod mount)
  | mount <- assemblyMounts (unitAssembly unit), mountRole mount == Prototype.NodeChain]

reference :: TypeRef -> String
reference (TypeRef typeName _) = typeName
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
-- 绑定路由与方法形状代换共用同一类型比较；不选择资产。
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

-- requires 与 streams 读取资产；requests 只驱动，不读取。
readsAccess :: Access -> Bool
readsAccess RequestAccess = False
readsAccess RequireAccess = True
readsAccess StreamAccess = True

