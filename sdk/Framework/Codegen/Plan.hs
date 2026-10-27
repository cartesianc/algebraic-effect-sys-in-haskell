-- 生成阶段的纯结构输入；方法名字仅用于连接源码，输出使用 MethodGen 构造器。
module Framework.Codegen.Plan (GraphPlan(..), renderGraphPlan) where

import Data.Char (toUpper)
import Data.List (intercalate, nub)
import Framework.Effect.Graph
import Framework.Workflow.AST (chained, node)
import Framework.Workflow.Structure (ProgramStructure(..), initializeStructure)

-- 声明先由独立 GHCI 加载，方法结构随后由 GHC parser 提供；两者都不依赖 Generated。
data GraphPlan method = GraphPlan
  { planRoutes :: [(method, method, method)]
  , planDefinitions :: [MethodDefinition method]
  , planScopes :: [(method, String, [String])]
  , planEntries :: [(String, method)]
  } deriving (Eq, Show, Read)

renderGraphPlan :: GraphPlan String -> [(String, MethodShape String)] -> Either String String
renderGraphPlan plan shapes = do
  let supplied = map fst shapes
      registered = map methodIdentity (planDefinitions plan)
  if length supplied /= length (nub supplied)
    then Left "Duplicate handler method in the structure generation plan"
    else pure ()
  case [method | method <- supplied, method `notElem` registered] of
    method : _ -> Left ("Unregistered handler method in the structure generation plan: " ++ method)
    [] -> pure ()
  let definitions =
        -- 手写方法使用解析出的结构；未出现在 Handlers 中的生成方法（如默认 require 读取）保留计划中的结构。
        [definition {methodBody = maybe (methodBody definition) id (lookup (methodIdentity definition) shapes)}
          | definition <- planDefinitions plan]
      -- 这里只枚举各独立入口。初始化算法不会把不同 Node 串成 scope 路径，
      -- 因而不需要载入或冻结业务 workflow 的 chained/parallel 形状。
      entries = chained [node selected | (selected, _) <- planEntries plan]
  initialized <- either (Left . show) Right
    (initializeStructure (planRoutes plan) definitions (planScopes plan) (planEntries plan) entries)
  pure (renderEffectGraph (structureEffects initialized) ++ "\n"
    ++ renderScopeTree (structureScopes initialized))

genName :: String -> String
genName [] = error "Empty method identity in the generation plan"
genName (first : rest) = toUpper first : rest ++ "Gen"

list :: (value -> String) -> [value] -> String
list render values = "[" ++ intercalate ", " (map render values) ++ "]"

pair :: (value -> String) -> (value, value) -> String
pair render (left, right) = "(" ++ render left ++ ", " ++ render right ++ ")"

rows :: (value -> String) -> [value] -> [String]
rows _ [] = ["      []"]
rows render values = ["      [ " ++ intercalate "\n      , " (map render values), "      ]"]

renderShape :: MethodShape String -> String
renderShape Empty = "SDK.Empty"
renderShape (Call method) = "SDK.Call " ++ genName method
renderShape (Sequence children) = "SDK.Sequence " ++ list renderShape children
renderShape (Choice children) = "SDK.Choice " ++ list renderShape children
renderShape (Recover body recovery) = "SDK.Recover (" ++ renderShape body ++ ") (" ++ renderShape recovery ++ ")"

renderDefinition :: MethodDefinition String -> String
renderDefinition definition = "SDK.MethodDefinition "
  ++ genName (methodIdentity definition) ++ " " ++ genName (methodEffect definition)
  ++ " SDK." ++ show (methodRole definition) ++ " (" ++ renderShape (methodBody definition) ++ ")"

renderEffectGraph :: EffectGraph String -> String
renderEffectGraph graph = unlines $
  [ "-- 生成时已完成方法展开与路径分析；运行时只读取显式 ADT 值。"
  , "generatedEffectGraph :: SDK.EffectGraph MethodGen"
  , "generatedEffectGraph = SDK.EffectGraph"
  , "  { SDK.graphMethods ="
  ] ++ rows renderDefinition (graphMethods graph) ++
  [ "  , SDK.graphRoots = " ++ list genName (graphRoots graph)
  , "  , SDK.graphReferences = " ++ list (pair genName) (graphReferences graph)
  , "  , SDK.graphScopes = " ++ list genName (graphScopes graph)
  , "  , SDK.graphScopePaths = " ++ list (list genName) (graphScopePaths graph)
  , "  , SDK.graphRootPaths ="
  ] ++ rows (\(method, paths) -> "(" ++ genName method ++ ", " ++ list (list genName) paths ++ ")")
       (graphRootPaths graph) ++
  [ "  , SDK.graphScopeOrder = " ++ list (pair genName) (graphScopeOrder graph)
  , "  }"
  ]

renderScopeTree :: ScopeTree String -> String
renderScopeTree tree = unlines $
  [ "-- 唯一的 ScopeTree：共同前序与注册前提已合并、检查环并约简。"
  , "generatedScopeTree :: SDK.ScopeTree MethodGen"
  , "generatedScopeTree = SDK.ScopeTree"
  , "  { SDK.scopeRoots = " ++ list genName (scopeRoots tree)
  , "  , SDK.scopeNodes ="
  ] ++ rows renderNode (scopeNodes tree) ++
  [ "  , SDK.scopeLayers = " ++ list (list genName) (scopeLayers tree)
  , "  , SDK.scopePaths = " ++ list (list genName) (scopePaths tree)
  , "  , SDK.scopeCandidates = " ++ list (pair genName) (scopeCandidates tree)
  , "  , SDK.scopeOpposed = " ++ list (pair genName) (scopeOpposed tree)
  , "  , SDK.scopeUndetermined = " ++ list (pair genName) (scopeUndetermined tree)
  , "  }"
  ]
  where
    renderNode selected = "SDK.ScopeNode { SDK.scopeIdentity = " ++ genName (scopeIdentity selected)
      ++ ", SDK.scopeParents = " ++ list genName (scopeParents selected)
      ++ ", SDK.scopeChildren = " ++ list genName (scopeChildren selected) ++ " }"
