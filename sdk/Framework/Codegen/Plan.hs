-- 原型的源码出口；所有结构事实由 Framework.Prototype 构建，本模块只渲染数据。
module Framework.Codegen.Plan (renderPrototype) where

import Data.Char (toUpper)
import Data.List (intercalate)
import qualified Framework.Effect.Graph as G
import qualified Framework.Effect.Registration as R
import qualified Framework.Prototype as P

renderPrototype :: P.Prototype String -> String
renderPrototype prototype = unlines
  [ "-- 生成时完成注册、方法、origin/ctx 链、Workflow 和 scope 的统一分析。"
  , "-- NodeId 只在这份 AST 快照中有效；运行时校验后装配闭包。"
  , "generatedPrototype :: SDK.Prototype MethodGen"
  , "generatedPrototype ="
  ] ++ indent 2 (record "Prototype"
  [ ("protoRegistrations", list renderSpec (P.protoRegistrations prototype))
  , ("protoEffects", list renderEffect (P.protoEffects prototype))
  , ("protoMethods", list renderMethod (P.protoMethods prototype))
  , ("protoWorkflow", renderWorkflow (P.protoWorkflow prototype))
  , ("protoChains", list renderChain (P.protoChains prototype))
  , ("protoChainDefinitions", list renderChainDefinition (P.protoChainDefinitions prototype))
  , ("protoGraph", renderGraph (P.protoGraph prototype))
  , ("protoScopes", renderScopes (P.protoScopes prototype))
  , ("protoScopeNames", list (pair genName show) (P.protoScopeNames prototype))
  , ("protoSources", list (pair renderReadPoint renderSource) (P.protoSources prototype))
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

maybeValue :: (value -> String) -> Maybe value -> String
maybeValue _ Nothing = "Nothing"
maybeValue render (Just value) = "Just (" ++ render value ++ ")"

constructor :: String -> [String] -> String
constructor name values
  | fits compact = compact
  | otherwise = blockConstructor name values
  where compact = unwords (("SDK." ++ name) : map (\value -> "(" ++ value ++ ")") values)

blockConstructor :: String -> [String] -> String
blockConstructor name values = intercalate "\n"
  (("SDK." ++ name) : map (indent 2 . argument) values)
  where
    argument value
      | '\n' `notElem` value = "(" ++ value ++ ")"
      | otherwise = "(\n" ++ indent 2 value ++ "\n)"

record :: String -> [(String, String)] -> String
record name [] = "SDK." ++ name ++ " {}"
record name (first : rest) = intercalate "\n"
  (("SDK." ++ name) : field "  { " first : map (field "  , ") rest ++ ["  }"])
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
renderTyping (R.Pure method) = constructor "Pure" [show method]
renderTyping (R.Excu method) = constructor "Excu" [show method]
renderTyping (R.Scoped opening closing) = constructor "Scoped" [show opening, show closing]
renderTyping (R.Error detecting resolving handled) =
  constructor "Error" [show detecting, show resolving, list renderHandles handled]
renderTyping (R.Context producing) = constructor "Context" [maybeValue renderRequester producing]

renderRequester :: R.Requester -> String
renderRequester (R.Requester method representation) = constructor "Requester" [show method, renderType representation]

renderType :: R.TypeRef -> String
renderType (R.TypeRef selected) = constructor "TypeRef" [show selected]
renderType (R.OutputRef cause value) = constructor "OutputRef" [renderType cause, renderType value]

renderHandles :: R.Handles -> String
renderHandles (R.RaisedBy selected) = constructor "RaisedBy" [show selected]
renderHandles (R.ScopeFaultIn selected) = constructor "ScopeFaultIn" [show selected]
renderHandles (R.ContextFaultIn selected) = constructor "ContextFaultIn" [show selected]

renderDemand :: R.Demand -> String
renderDemand (R.Demand access contract) = constructor "Demand" [tag access, show contract]

renderResolved :: R.ResolvedDemand -> String
renderResolved (R.ResolvedDemand access contract provider) =
  constructor "ResolvedDemand" [tag access, show contract, show provider]

renderEffect :: P.EffectProto String -> String
renderEffect effect = record "EffectProto"
  [ ("effectName", show (P.effectName effect))
  , ("effectKind", tag (P.effectKind effect))
  , ("effectInput", show (P.effectInput effect))
  , ("effectMethods", list (pair tag genName) (P.effectMethods effect))
  , ("effectDemands", list renderResolved (P.effectDemands effect))
  , ("effectProduces", show (P.effectProduces effect))
  , ("effectBranches", show (P.effectBranches effect))
  , ("effectAnchor", show (P.effectAnchor effect))
  , ("effectScopes", show (P.effectScopes effect))
  , ("effectErrorScope", show (P.effectErrorScope effect))
  , ("effectInputChain", show (P.effectInputChain effect))
  , ("effectScopeParents", show (P.effectScopeParents effect))
  , ("effectOpeningInputs", show (P.effectOpeningInputs effect))
  , ("effectNearestScopes", show (P.effectNearestScopes effect))
  , ("effectResource", show (P.effectResource effect))
  , ("effectContextDependencies", show (P.effectContextDependencies effect))
  ]

renderMethod :: G.MethodDefinition String -> String
renderMethod definition = constructor "MethodDefinition"
  [ genName (G.methodIdentity definition)
  , genName (G.methodEffect definition)
  , tag (G.methodRole definition)
  , renderShape (G.methodBody definition)
  ]

renderShape :: G.MethodShape String -> String
renderShape G.Empty = "SDK.Empty"
renderShape (G.Call method) = constructor "Call" [genName method]
renderShape (G.Sequence children) = constructor "Sequence" [list renderShape children]
renderShape (G.Choice children) = constructor "Choice" [list renderShape children]
renderShape (G.Recover body recovery) = constructor "Recover" [renderShape body, renderShape recovery]

renderWorkflow :: P.WorkflowTree -> String
renderWorkflow (P.NodeAt node selected) = constructor "NodeAt" [show node, show selected]
renderWorkflow (P.ChainedAt node children) = blockConstructor "ChainedAt" [show node, blockList renderWorkflow children]
renderWorkflow (P.ParallelAt node children) = blockConstructor "ParallelAt" [show node, blockList renderWorkflow children]
renderWorkflow (P.AlternativeAt node alternative children) =
  blockConstructor "AlternativeAt" [show node, renderAlternative alternative, blockList renderWorkflow children]

renderAlternative :: P.AlternativeProto -> String
renderAlternative alternative = record "AlternativeProto"
  [ ("alternativeContract", show (P.alternativeContract alternative))
  , ("alternativeSelector", show (P.alternativeSelector alternative))
  , ("alternativeCases", show (P.alternativeCases alternative))
  ]

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
renderReadPoint point = constructor "ReadPoint" [show (P.readNode point), show (P.readContract point)]

renderSource :: P.Source -> String
renderSource (P.FromChain node) = constructor "FromChain" [show node]
renderSource P.FromOwnChain = "SDK.FromOwnChain"
