-- 输出：把 Prototype（编译产物）渲染为 Generated/Program.hs 中的 Haskell 值；只渲染数据，不再推导结构。
module Framework.Gen.Emit.Prototype (renderPrototype, renderPrototypeModule) where

import Data.Char (toUpper)
import Data.List (intercalate)
import qualified Framework.Prototype.Graph as G
import qualified Framework.Language.Registration as R
import qualified Framework.Prototype as P

-- Generated/Prototype.hs 只放 gen 编译出的结构数据；Program 引用它交给 interpreter。
-- 结构正文可来自构图缓存，模块头随命名空间另加。
renderPrototypeModule :: String -> String -> String
renderPrototypeModule namespace structure = unlines
  [ "{-# LANGUAGE DuplicateRecordFields #-}"
  , ""
  , "-- 自动生成；gen 编译出的静态结构，由 Program 交给 interpreter，运行前校验。"
  , "module " ++ namespace ++ ".Generated.Prototype (generatedPrototype) where"
  , ""
  , "import qualified Framework.Generated as SDK"
  , "import " ++ namespace ++ ".Generated.Effects (MethodGen(..))"
  , ""
  ] ++ structure

renderPrototype :: P.Prototype String -> String
renderPrototype prototype = unlines
  [ "-- 生成时完成注册、方法、origin/ctx 链、资产来源、Workflow 和 scope 的统一分析。"
  , "-- NodeId 只在这份 AST 快照中有效；运行时校验后装配闭包。"
  , "generatedPrototype :: SDK.Prototype MethodGen"
  , "generatedPrototype ="
  ] ++ indent 2 (record "Prototype"
  [ ("protoRegistrations", list renderSpec (P.protoRegistrations prototype))
  , ("protoEffects", list renderEffect (P.protoEffects prototype))
  , ("protoMethods", list renderMethod (P.protoMethods prototype))
  , ("protoWorkflow", renderWorkflow (P.protoWorkflow prototype))
  , ("protoSessions", list renderSession (P.protoSessions prototype))
  , ("protoChains", list renderChain (P.protoChains prototype))
  , ("protoChainDefinitions", list renderChainDefinition (P.protoChainDefinitions prototype))
  , ("protoGraph", renderGraph (P.protoGraph prototype))
  , ("protoScopes", renderScopes (P.protoScopes prototype))
  , ("protoScopeNames", list (pair genName show) (P.protoScopeNames prototype))
  , ("protoSources", list (pair renderReadPoint renderSource) (P.protoSources prototype))
  , ("protoScopeOpenings", list renderScopeOpening (P.protoScopeOpenings prototype))
  , ("protoDriving", renderDriving (P.protoDriving prototype))
  ]) ++ "\n"

genName :: String -> String
genName [] = error "Empty method identity in the prototype"
genName (first : rest) = toUpper first : rest ++ "Gen"

list :: (value -> String) -> [value] -> String
list render values
  | fits compact = compact
  | otherwise = blockList render values
  where compact = "[" ++ intercalate ", " (map render values) ++ "]"

blockList :: (value -> String) -> [value] -> String
blockList _ [] = "[]"
blockList render (first : rest) = intercalate "\n"
  (prefixed "[ " (render first) : map (prefixed ", " . render) rest ++ ["]"])

-- Prefix only the first line, keeping the remainder aligned with the value.
prefixed :: String -> String -> String
prefixed prefix value = case lines value of
  [] -> prefix
  first : rest -> intercalate "\n" ((prefix ++ first) : map (replicate (length prefix) ' ' ++) rest)

indent :: Int -> String -> String
indent width = intercalate "\n" . map (replicate width ' ' ++) . lines

fits :: String -> Bool
fits value = '\n' `notElem` value && length value <= 100

pair :: (left -> String) -> (right -> String) -> (left, right) -> String
pair renderLeft renderRight (left, right) =
  "(" ++ renderLeft left ++ ", " ++ renderRight right ++ ")"

-- 构造器参数按 Haskell 应用优先级渲染：叶子值一律经 showArg（Just、负数由 Show 加括号），
-- 标签与列表可直接作参数，嵌套的生成表达式显式分组。记录字段的值不需要括号，仍用 show。
showArg :: Show a => a -> String
showArg value = showsPrec 11 value ""

group :: String -> String
group value
  | '\n' `elem` value = "(\n" ++ indent 2 value ++ "\n)"
  | otherwise = "(" ++ value ++ ")"

constructor :: String -> [String] -> String
constructor name arguments
  | fits compact = compact
  | otherwise = blockConstructor name arguments
  where compact = unwords (("SDK." ++ name) : arguments)

blockConstructor :: String -> [String] -> String
blockConstructor name arguments = intercalate "\n" (("SDK." ++ name) : map (indent 2) arguments)

record :: String -> [(String, String)] -> String
record name [] = "SDK." ++ name ++ " {}"
record name fields = fieldBlock ("SDK." ++ name) fields

-- 以已有值为底的记录更新：只写给出的字段。
update :: String -> [(String, String)] -> String
update base [] = base
update base fields = fieldBlock ("(" ++ base ++ ")") fields

fieldBlock :: String -> [(String, String)] -> String
fieldBlock _ [] = error "fieldBlock needs at least one field"
fieldBlock header (first : rest) = intercalate "\n"
  (header : field "  { " first : map (field "  , ") rest ++ ["  }"])
  where
    field prefix (selected, value)
      | fits complete = complete
      | otherwise = prefix ++ "SDK." ++ selected ++ " =\n" ++ indent 6 value
      where complete = prefix ++ "SDK." ++ selected ++ " = " ++ value

tag :: Show value => value -> String
tag value = "SDK." ++ show value

renderSpec :: R.EffectSpec -> String
renderSpec specification = record "EffectSpec"
  [ ("name", show (R.name specification))
  , ("typing", renderTyping (R.typing specification))
  , ("input", show (R.input specification))
  , ("demands", list renderDemand (R.demands specification))
  ]

renderTyping :: R.EffectTyping -> String
renderTyping (R.Pure method) = constructor "Pure" [showArg method]
renderTyping (R.Excu method) = constructor "Excu" [showArg method]
renderTyping (R.Scoped opening closing) = constructor "Scoped" [showArg opening, showArg closing]
renderTyping (R.Error detecting resolving handled) =
  constructor "Error" [showArg detecting, showArg resolving, list renderHandles handled]
renderTyping (R.Context declared parsing requiring streaming) =
  constructor "Context" [group (renderAsset declared), showArg parsing, showArg requiring, showArg streaming]
renderTyping (R.Stream method) = constructor "Stream" [showArg method]
renderTyping (R.Middleware method intercepted) = constructor "Middleware" [showArg method, list tag intercepted]

renderAsset :: R.Asset -> String
renderAsset (R.AssetDecl selected representation) = constructor "AssetDecl" [showArg selected, group (renderType representation)]

renderType :: R.TypeRef -> String
renderType (R.TypeRef selected) = constructor "TypeRef" [showArg selected]
renderType (R.OutputRef cause value) = constructor "OutputRef" [group (renderType cause), group (renderType value)]

renderHandles :: R.Handles -> String
renderHandles (R.RaisedBy selected) = constructor "RaisedBy" [showArg selected]
renderHandles (R.ScopeFaultIn selected) = constructor "ScopeFaultIn" [showArg selected]
renderHandles (R.ContextFaultIn selected) = constructor "ContextFaultIn" [showArg selected]

renderDemand :: R.Demand -> String
renderDemand (R.Demand access contract) = constructor "Demand" [tag access, showArg contract]

renderResolved :: P.ResolvedDemand -> String
renderResolved (P.ResolvedDemand access contract provider) =
  constructor "ResolvedDemand" [tag access, showArg contract, showArg provider]

renderEffect :: P.EffectProto String -> String
renderEffect effect = update
  ("SDK.effectProto " ++ unwords [show (P.effectName effect), tag (P.effectKind effect), show (P.effectInput effect)])
  (concat
    [ changed P.effectMethods "effectMethods" (list (pair tag genName))
    , changed P.effectDemands "effectDemands" (list renderResolved)
    , changed P.effectProduces "effectProduces" show
    , changed P.effectBranches "effectBranches" show
    , changed P.effectAnchor "effectAnchor" show
    , changed P.effectScopes "effectScopes" show
    , changed P.effectErrorScope "effectErrorScope" show
    , changed P.effectInputChain "effectInputChain" show
    , changed P.effectScopeParents "effectScopeParents" show
    , changed P.effectOpeningInputs "effectOpeningInputs" show
    , changed P.effectNearestScopes "effectNearestScopes" show
    , changed P.effectResource "effectResource" show
    , changed P.effectContextDependencies "effectContextDependencies" show
    , changed P.effectContinuous "effectContinuous" show
    , changed P.effectHistory "effectHistory" show
    ])
  where
    -- 与 SDK 的 effectProto 默认值相同的字段不写。
    base = P.effectProto (P.effectName effect) (P.effectKind effect) (P.effectInput effect)
    changed :: Eq value => (P.EffectProto String -> value) -> String -> (value -> String) -> [(String, String)]
    changed selector name render = [(name, render (selector effect)) | selector effect /= selector base]

renderMethod :: G.MethodDefinition String -> String
renderMethod definition = constructor "MethodDefinition"
  [ genName (G.methodIdentity definition)
  , genName (G.methodEffect definition)
  , tag (G.methodRole definition)
  , shapeArgument (G.methodBody definition)
  ]

renderShape :: G.MethodShape String -> String
renderShape G.Empty = "SDK.Empty"
renderShape (G.Call method) = constructor "Call" [genName method]
renderShape (G.Sequence children) = constructor "Sequence" [list renderShape children]
renderShape (G.Choice children) = constructor "Choice" [list renderShape children]
renderShape (G.Recover body recovery) = constructor "Recover" [shapeArgument body, shapeArgument recovery]

shapeArgument :: G.MethodShape String -> String
shapeArgument G.Empty = "SDK.Empty"
shapeArgument shape = group (renderShape shape)

renderWorkflow :: P.WorkflowTree -> String
renderWorkflow (P.NodeAt node selected) = constructor "NodeAt" [showArg node, showArg selected]
renderWorkflow (P.ChainedAt node children) = blockConstructor "ChainedAt" [showArg node, blockList renderWorkflow children]
renderWorkflow (P.ParallelAt node children) = blockConstructor "ParallelAt" [showArg node, blockList renderWorkflow children]
renderWorkflow (P.AlternativeAt node alternative children) =
  blockConstructor "AlternativeAt" [showArg node, group (renderAlternative alternative), blockList renderWorkflow children]
renderWorkflow (P.LifelongAt node lifelong children) =
  blockConstructor "LifelongAt" [showArg node, group (renderLifelong lifelong), blockList renderWorkflow children]

renderAlternative :: P.AlternativeProto -> String
renderAlternative alternative = record "AlternativeProto"
  [ ("alternativeContract", show (P.alternativeContract alternative))
  , ("alternativeSelector", show (P.alternativeSelector alternative))
  , ("alternativeCases", show (P.alternativeCases alternative))
  ]

renderLifelong :: P.LifelongProto -> String
renderLifelong lifelong = record "LifelongProto"
  [ ("lifelongUnits", show (P.lifelongUnits lifelong))
  , ("lifelongSubscriptions", show (P.lifelongSubscriptions lifelong))
  , ("lifelongSessions", list renderSession (P.lifelongSessions lifelong))
  ]

renderSession :: P.SessionProto -> String
renderSession session = record "SessionProto"
  [ ("sessionAsset", show (P.sessionAsset session))
  , ("sessionPlan", renderBootPlan (P.sessionPlan session))
  , ("sessionMounts", show (P.sessionMounts session))
  ]

renderBootPlan :: P.BootPlan -> String
renderBootPlan (P.Receive source) = constructor "Receive" [showArg source]
renderBootPlan (P.Derive upstream) = constructor "Derive" [showArg upstream]
renderBootPlan (P.ReuseOutput nodes) = constructor "ReuseOutput" [showArg nodes]

renderChain :: P.ChainProto String -> String
renderChain chain = record "ChainProto"
  [ ("chainNode", show (P.chainNode chain))
  , ("chainRole", tag (P.chainRole chain))
  , ("chainTerminal", show (P.chainTerminal chain))
  , ("chainEntry", genName (P.chainEntry chain))
  , ("chainReaches", list genName (P.chainReaches chain))
  , ("chainDrives", show (P.chainDrives chain))
  , ("chainReads", show (P.chainReads chain))
  , ("chainScopePaths", list (list genName) (P.chainScopePaths chain))
  ]

renderChainDefinition :: P.ChainDefinition String -> String
renderChainDefinition definition = record "ChainDefinition"
  [ ("definitionKind", tag (P.definitionKind definition))
  , ("definitionEffect", show (P.definitionEffect definition))
  , ("definitionEntry", genName (P.definitionEntry definition))
  , ("definitionReaches", list genName (P.definitionReaches definition))
  ]

renderGraph :: G.EffectGraph String -> String
renderGraph graph = record "EffectGraph"
  [ ("graphMethods", list renderMethod (G.graphMethods graph))
  , ("graphRoots", list genName (G.graphRoots graph))
  , ("graphReferences", list (pair genName genName) (G.graphReferences graph))
  , ("graphScopes", list genName (G.graphScopes graph))
  , ("graphScopePaths", list (list genName) (G.graphScopePaths graph))
  , ("graphRootPaths", list (pair genName (list (list genName))) (G.graphRootPaths graph))
  , ("graphScopeOrder", list (pair genName genName) (G.graphScopeOrder graph))
  ]

renderScopes :: G.ScopeTree String -> String
renderScopes tree = record "ScopeTree"
  [ ("scopeRoots", list genName (G.scopeRoots tree))
  , ("scopeNodes", list renderScopeNode (G.scopeNodes tree))
  , ("scopeLayers", list (list genName) (G.scopeLayers tree))
  , ("scopePaths", list (list genName) (G.scopePaths tree))
  , ("scopeCandidates", list (pair genName genName) (G.scopeCandidates tree))
  , ("scopeOpposed", list (pair genName genName) (G.scopeOpposed tree))
  , ("scopeUndetermined", list (pair genName genName) (G.scopeUndetermined tree))
  ]

renderScopeNode :: G.ScopeNode String -> String
renderScopeNode node = record "ScopeNode"
  [ ("scopeIdentity", genName (G.scopeIdentity node))
  , ("scopeParents", list genName (G.scopeParents node))
  , ("scopeChildren", list genName (G.scopeChildren node))
  ]

renderReadPoint :: P.ReadPoint -> String
renderReadPoint point = constructor "ReadPoint" [showArg (P.readNode point), showArg (P.readContract point)]

renderSource :: P.Source -> String
renderSource (P.FromChains nodes) = constructor "FromChains" [list show nodes]
renderSource P.FromOwnChain = "SDK.FromOwnChain"
renderSource P.FromSession = "SDK.FromSession"

renderScopeOpening :: P.ScopeOpening -> String
renderScopeOpening opening = record "ScopeOpeningPlan"
  [ ("openingNode", show (P.openingNode opening))
  , ("openingScope", show (P.openingScope opening))
  , ("openingSources", list (pair show renderSource) (P.openingSources opening))
  , ("openingKinds", list tag (P.openingKinds opening))
  ]

-- 驱动标记仍是显式 ADT；不在加载时用 read 解析文本或重建关系。
renderDriving :: P.DrivingPlan String -> String
renderDriving plan = record "DrivingPlan"
  [ ("drivingNodes", list node (P.drivingNodes plan))
  , ("drivingUnits", list unit (P.drivingUnits plan))
  , ("drivingSessions", list session (P.drivingSessions plan))
  , ("drivingRootNodes", show (P.drivingRootNodes plan))
  , ("drivingOutputSites", show (P.drivingOutputSites plan))
  , ("drivingRequests", list (pair show genName) (P.drivingRequests plan))
  , ("drivingMiddleware", show (P.drivingMiddleware plan))
  , ("drivingHooks", show (P.drivingHooks plan)) ]
  where
    node p = constructor "NodeDrive" [showArg (P.driveNode p), showArg (P.driveMembers p), showArg (P.driveSubscriptions p)
      , showArg (P.driveBoundary p), showArg (P.driveCaptures p), showArg (P.drivePriorBoundaries p), showArg (P.driveBlockedPublishers p)]
    unit p = constructor "UnitDrive" [showArg (P.driveUnit p), showArg (P.driveFrameNodes p)
      , list (pair show (list reader)) (P.driveReaders p), list (pair show local) (P.driveLocalSources p)]
    reader (P.ReadAt node') = constructor "ReadAt" [showArg node']
    reader (P.ChooseAmong nodes) = constructor "ChooseAmong" [showArg nodes]
    local (P.PublishedAt nodes) = constructor "PublishedAt" [showArg nodes]
    local (P.DerivedFrom source) = constructor "DerivedFrom" [showArg source]
    session p = constructor "SessionDrive" [showArg (P.driveSessionBoundary p), showArg (P.driveSessionSource p)
      , showArg (P.driveSessionAsset p), showArg (P.driveSessionUpstream p)]
