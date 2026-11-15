{-# LANGUAGE DeriveFunctor #-}

-- 构图：按共享方法定义归约 EffectGraph，再由开启顺序与注册前提得到独立的 ScopeTree。
-- 只读方法结构，不调用 handler；结果是 Prototype 的 protoGraph 与 protoScopes。
-- 算法说明 v2（2026-11-16）：EffectGraph 共享方法定义，ScopeTree 共享 scope 定义；
-- 两者都不表示运行次数或活实例数，也不授权跳过普通 Excu。实际复用由输出/实例协议决定。
module Framework.Gen.Build.Graph
  ( buildEffectGraph, buildScopeTree, completeScopeTree
  ) where

import Control.Monad (foldM)
import Control.Monad.State.Strict (StateT, evalStateT, gets, lift, modify')
import Data.List (inits, intersect, nub, nubBy, sort, (\\))
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Framework.Prototype.Graph
import Framework.Recursion (Algebra)

data AnalysisF method next
  = EmptyLayer
  | MethodLayer (MethodDefinition method) next
  | SequenceLayer [next]
  | ChoiceLayer [next]
  | RecoverLayer next next
  deriving Functor

-- v2：保留 zygo 的两份 algebra，但在方法引用上共享归约结果，不先建立按调用次数复制的 Fix 树。
-- 缓存只含纯结构摘要；Sequence 的每个 Call 仍按原顺序参与组合，业务执行没有去重。
-- require 的读取方法不连到生产方法。scope 记在 open 方法体之后，同一路径只留首次完成。
type Summary method = ([[method]], EffectGraph method)
type GraphAnalysis method = StateT (Map.Map method (Summary method)) (Either (GraphError method))

buildEffectGraph
  :: Ord method
  => [MethodDefinition method]
  -> MethodShape method
  -> Either (GraphError method) (EffectGraph method)
buildEffectGraph definitions shape = do
  table <- foldM insertDefinition Map.empty definitions
  snd <$> evalStateT (analyzeShape table Set.empty shape) Map.empty
  where
    insertDefinition table definition
      | Map.member selected table = Left (DuplicateMethod selected)
      | otherwise = Right (Map.insert selected definition table)
      where selected = methodIdentity definition

-- active 是当前栈，memo 只含已经完成的定义：共享前段可复用摘要，递归回边仍必须拒绝。
-- N 个定义、E 个可达方法体结构位置，索引与引用检查约 O((N+E) log(N+1))；
-- 这不包含摘要的合并、nub 和 scope 路径组合。独立条件仍可能形成指数路径族。
-- 资产来源分析依赖入口、捕获和前态，不得套用这里“只按方法身份”的缓存。
analyzeShape
  :: Ord method
  => Map.Map method (MethodDefinition method)
  -> Set.Set method
  -> MethodShape method
  -> GraphAnalysis method (Summary method)
analyzeShape definitions active shape = case shape of
  Empty -> pure (summarize EmptyLayer)
  Call selected
    | Set.member selected active -> lift (Left (RecursiveMethod selected))
    | otherwise -> do
        cached <- gets (Map.lookup selected)
        case cached of
          Just summary -> pure summary
          Nothing -> case Map.lookup selected definitions of
            Nothing -> lift (Left (UnknownMethod selected))
            Just definition -> do
              body <- analyzeShape definitions (Set.insert selected active) (methodBody definition)
              let summary = summarize (MethodLayer definition body)
              modify' (Map.insert selected summary)
              pure summary
  Sequence children -> summarize . SequenceLayer <$> mapM next children
  Choice children -> summarize . ChoiceLayer <$> mapM next children
  Recover body recovery -> do
    before <- next body
    after <- next recovery
    pure (summarize (RecoverLayer before after))
  where
    next = analyzeShape definitions active

-- 辅助结果和主结果共用本层的 scope 路径；主 algebra 不再重复调用辅助 algebra。
summarize :: Eq method => AnalysisF method (Summary method) -> Summary method
summarize layer = (scopePathsHere, graphAlgebra scopePathsHere layer)
  where scopePathsHere = scopeAlgebra (fmap fst layer)

scopeAlgebra :: Eq method => Algebra (AnalysisF method) [[method]]
scopeAlgebra EmptyLayer = [[]]
scopeAlgebra (MethodLayer definition body)
  | methodRole definition == ScopeOpen = paths (map (++ [methodIdentity definition]) body)
  | otherwise = body
scopeAlgebra (SequenceLayer children) = paths (foldr combine [[]] children)
  where combine before after = [left ++ right | left <- before, right <- after]
scopeAlgebra (ChoiceLayer []) = [[]]
scopeAlgebra (ChoiceLayer children) = paths (concat children)
-- 正文可在任意位置失败；包括首个 scope 之前，不假定已完成整个正文。
scopeAlgebra (RecoverLayer body recovery) = paths
  (body ++ [prefix ++ after | before <- body, prefix <- inits before, after <- recovery])

-- zygo 的辅助结果是子结构的 scope 路径，主结果汇总方法图和顺序证据。
-- 图信息不依赖业务值，构图期间不会调用 handler。
-- nubBy/nub 只规范化方法目录、引用边和路径证据；MethodDefinition 内的 Sequence/Call 未去重。
-- scope 路径按定义只留首次完成，是构树投影；不能据其长度判断 open 次数或实际使用计数。
graphAlgebra
  :: Eq method
  => [[method]]
  -> AnalysisF method ([[method]], EffectGraph method)
  -> EffectGraph method
graphAlgebra scopePathsHere layer = EffectGraph
  { graphMethods = nubBy sameMethod (localMethods ++ concatMap graphMethods children)
  , graphRoots = nub roots
  , graphReferences = nub (localReferences ++ concatMap graphReferences children)
  , graphScopes = nub (concat scopePathsHere)
  , graphScopePaths = scopePathsHere
  , graphRootPaths = case layer of
      MethodLayer definition _ -> [(methodIdentity definition, scopePathsHere)]
      _ -> concatMap graphRootPaths children
  , graphScopeOrder = pathOrder scopePathsHere
  }
  where
    (localMethods, roots, localReferences, children) = case layer of
      EmptyLayer -> ([], [], [], [])
      MethodLayer definition (_, body) ->
        let selected = methodIdentity definition
        in ([definition], [selected], [(selected, child) | child <- graphRoots body], [body])
      SequenceLayer parts -> branch parts
      ChoiceLayer parts -> branch parts
      RecoverLayer body recovery -> branch [body, recovery]
    branch parts = ([], concatMap (graphRoots . snd) parts, [], map snd parts)
    sameMethod left right = methodIdentity left == methodIdentity right

paths :: Eq method => [[method]] -> [[method]]
paths = nub . map nub

pathOrder :: Eq method => [[method]] -> [(method, method)]
pathOrder = nub . concatMap orderedPairs
  where
    orderedPairs [] = []
    orderedPairs (before : rest) = [(before, after) | after <- rest] ++ orderedPairs rest

-- A precedes B 当且仅当每条包含 B 的路径都包含更早的 A。
-- 这给出共同必经前序的 DAG，不证明资源依赖，也不证明未确定的节点彼此独立。
-- 相反方向证据来自单条路径内的顺序，不能由跨路径的传递闭包代替。
-- 无环依据（v1）：A≺B 且 B≺C 时，每条含 C 的路径必依次含 A、B，故 A≺C；
-- 路径已按定义去重，A 不可能先于自身。关系传递且反自反，才能做传递约简与分层。
-- 只对出现过的 B 求交，避免空路径族上的全称判断；不是对候选边并集删 SCC。
-- 复杂度包含路径扫描、每条路径的成对顺序和传递约简；当前约简枚举关系边×中介节点，
-- 并用列表做成员查询，nub 也有二次比较开销，不能等同于一次线性图遍历。
buildScopeTree :: Ord method => EffectGraph method -> ScopeTree method
buildScopeTree graph = ScopeTree
  { scopeRoots = [selected | selected <- nodes, null (parents selected)]
  , scopeNodes = [ScopeNode selected (parents selected) (children selected) | selected <- nodes]
  , scopeLayers = layers nodes
  , scopePaths = observedPaths
  , scopeCandidates = candidates
  , scopeOpposed = opposed
  , scopeUndetermined =
      [(left, right) | left <- nodes, right <- nodes, left < right,
                       (left, right) `notElem` precedes, (right, left) `notElem` precedes,
                       (left, right) `notElem` opposed]
  }
  where
    observedPaths = paths (graphScopePaths graph)
    nodes = sort (nub (concat observedPaths))
    candidates = sort (pathOrder observedPaths)
    opposed = [edge | edge@(before, after) <- candidates, (after, before) `elem` candidates]
    predecessors selected = case [takeWhile (/= selected) path | path <- observedPaths, selected `elem` path] of
      [] -> []
      first : rest -> foldl intersect first rest
    -- 完整前序只用于构树；对外以父子边表达，不再保留第二份关系结构。
    precedes = sort [(before, after) | after <- nodes, before <- predecessors after]
    reduced =
      [(before, after) | (before, after) <- precedes,
        not (any (\middle -> (before, middle) `elem` precedes && (middle, after) `elem` precedes) nodes)]
    parents selected = [before | (before, after) <- reduced, after == selected]
    children selected = [after | (before, after) <- reduced, before == selected]
    layers [] = []
    layers remaining = ready : layers (remaining \\ ready)
      where ready = [selected | selected <- remaining, all (`notElem` remaining) (parents selected)]

-- 注册前提补入同一份树。注册前提是依赖：上游 scope 必须比下游活得久，关闭下游时仍可能读取上游资源。
-- 观察到的开启顺序是证据：逐条补入，与注册前提及已补入的边构成相反方向的不作为父边。
-- 路径、候选与反向证据仍保持原观察结果，被推翻的顺序仍在 scopeCandidates 中；不把路径候选的并集当依赖。
-- 声明顺序保留给独立 scope；运行清理使用最终父边的逆拓扑顺序。
-- 环处理（v1）：声明前提不能删除，若自身有环，layers 报 CyclicScopeRelations。
-- 观察边只在 child 不能到达 parent 时加入；放弃的是不相容的观察证据，不是声明的业务依赖。
-- ancestors/observedAncestors 当前递归展开后才 nub，未按节点记忆化；共享祖先很多的 DAG
-- 也可能重复遍历，性能估算须连同路径数量计算，不能仅引用拓扑排序的复杂度。
completeScopeTree
  :: Ord method
  => [(method, [method])]
  -> ScopeTree method
  -> Either (GraphError method) (ScopeTree method)
completeScopeTree declared tree = do
  mapM_ checkParent [parent | (_, parents') <- declared, parent <- parents']
  completedLayers <- layers nodes
  let ancestors selected = nub
        (parents selected ++ concatMap ancestors (parents selected))
      precedes = [(before, after) | after <- nodes, before <- ancestors after]
      reduced =
        [(before, after) | (before, after) <- precedes,
          not (any (\middle -> (before, middle) `elem` precedes
            && (middle, after) `elem` precedes) nodes)]
      completedParents selected = [before | (before, after) <- reduced, after == selected]
      completedChildren selected = [after | (before, after) <- reduced, before == selected]
  pure tree
    { scopeRoots = [selected | selected <- nodes, null (completedParents selected)]
    , scopeNodes = [ScopeNode selected (completedParents selected) (completedChildren selected)
        | selected <- nodes]
    , scopeLayers = completedLayers
    }
  where
    nodes = nub (map fst declared ++ map scopeIdentity (scopeNodes tree))
    -- 观察关系取完整前序（父边的传递闭包），被推翻的边不会经由其他观察边间接保留。
    observedParents selected = concat [scopeParents node | node <- scopeNodes tree, scopeIdentity node == selected]
    observedAncestors selected = nub
      (observedParents selected ++ concatMap observedAncestors (observedParents selected))
    observed = sort [(before, scopeIdentity node) | node <- scopeNodes tree
                    , before <- observedAncestors (scopeIdentity node)]
    relationships = foldl admit
      (nub [(parent, selected) | (selected, parents') <- declared, parent <- parents']) observed
    admit accepted edge@(parent, child)
      | edge `elem` accepted || reaches accepted child parent = accepted
      | otherwise = accepted ++ [edge]
    reaches edges from target = search [from] []
      where
        search [] _ = False
        search (current : rest) seen
          | current == target = True
          | current `elem` seen = search rest seen
          | otherwise = search ([next | (previous, next) <- edges, previous == current] ++ rest) (current : seen)
    parents selected = [parent | (parent, child) <- relationships, child == selected]
    checkParent parent
      | parent `elem` nodes = Right ()
      | otherwise = Left (UnknownScope parent)
    layers [] = Right []
    layers remaining =
      let ready = [selected | selected <- remaining, all (`notElem` remaining) (parents selected)]
      in if null ready
        then Left (CyclicScopeRelations remaining)
        else (ready :) <$> layers (remaining \\ ready)
