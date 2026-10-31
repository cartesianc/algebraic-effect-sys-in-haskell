{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveFunctor #-}
{-# LANGUAGE DeriveGeneric #-}

-- 静态方法引用与 scope 开启顺序的纯视图，不保存执行闭包或活资源。
module Framework.Effect.Graph
  ( MethodRole(..), MethodShape(..), MethodDefinition(..)
  , GraphError(..), EffectGraph(..), buildEffectGraph
  , ExpandedF(..), expandChain
  , ScopeNode(..), ScopeTree(..), buildScopeTree, completeScopeTree
  ) where

import Control.DeepSeq (NFData)
import Data.List (inits, intersect, nub, nubBy, sort, (\\))
import Framework.Recursion (Algebra, Fix(..), zygo)
import GHC.Generics (Generic)

-- 方法身份由生成的枚举提供；显示名称不参与身份判断。
data MethodRole
  = HandlerMethod
  | ContextRequest
  | ContextRequire
  | ScopeOpen
  | ScopeClose
  | ErrorDetect
  | ErrorResolve
  deriving (Eq, Ord, Show, Read, Generic, NFData)

data MethodShape method
  = Empty
  | Call method
  | Sequence [MethodShape method]
  | Choice [MethodShape method]
  | Recover (MethodShape method) (MethodShape method)
  deriving (Eq, Show, Read, Functor, Generic, NFData)

data MethodDefinition method = MethodDefinition
  { methodIdentity :: method
  -- 同一 effect 的方法共用其首个注册入口身份，不增加用户 key。
  , methodEffect :: method
  , methodRole :: MethodRole
  , methodBody :: MethodShape method
  } deriving (Eq, Show, Read, Functor, Generic, NFData)

data GraphError method
  = DuplicateMethod method
  | UnknownMethod method
  | RecursiveMethod method
  | UnknownScope method
  | CyclicScopeRelations [method]
  deriving (Eq, Show, Read, Functor, Generic, NFData)

data EffectGraph method = EffectGraph
  { graphMethods :: [MethodDefinition method]
  , graphRoots :: [method]
  , graphReferences :: [(method, method)]
  , graphScopes :: [method]
  , graphScopePaths :: [[method]]
  , graphRootPaths :: [(method, [[method]])]
  , graphScopeOrder :: [(method, method)]
  } deriving (Eq, Show, Read, Functor, Generic, NFData)

-- scope 的静态身份就是对应 open 方法的身份；共享节点只保存引用。
data ScopeNode method = ScopeNode
  { scopeIdentity :: method
  , scopeParents :: [method]
  , scopeChildren :: [method]
  } deriving (Eq, Show, Read, Functor, Generic, NFData)

data ScopeTree method = ScopeTree
  { scopeRoots :: [method]
  , scopeNodes :: [ScopeNode method]
  , scopeLayers :: [[method]]
  , scopePaths :: [[method]]
  , scopeCandidates :: [(method, method)]
  , scopeOpposed :: [(method, method)]
  , scopeUndetermined :: [(method, method)]
  } deriving (Eq, Show, Read, Functor, Generic, NFData)

data ExpandedF method next
  = EmptyLayer
  | MethodLayer (MethodDefinition method) next
  | SequenceLayer [next]
  | ChoiceLayer [next]
  | RecoverLayer next next
  deriving Functor

-- 只展开表中已解析到来源的方法引用；require 的按需求值路径由生成计划表达，不启动生产。
-- Choice 保留各分支路径，Sequence 组合路径；有限分支的路径数可能呈指数增长。
-- scope 记在其 open 方法体之后，即开启完成的位置：open 内部开启的 scope 排在它前面，
-- 嵌套 open 的方向与注册前提一致。同一 scope 在一条路径中只保留首次完成。
buildEffectGraph
  :: Ord method
  => [MethodDefinition method]
  -> MethodShape method
  -> Either (GraphError method) (EffectGraph method)
buildEffectGraph definitions shape = do
  expanded <- expandChain definitions shape
  pure (zygo scopeAlgebra graphAlgebra expanded)

-- 所有静态链分析共用这一展开器；调用次数与分支结构原样保留。
expandChain
  :: Eq method
  => [MethodDefinition method]
  -> MethodShape method
  -> Either (GraphError method) (Fix (ExpandedF method))
expandChain definitions shape = do
  uniqueDefinitions [] definitions
  expand [] shape
  where
    uniqueDefinitions _ [] = Right ()
    uniqueDefinitions seen (definition : rest)
      | selected `elem` seen = Left (DuplicateMethod selected)
      | otherwise = uniqueDefinitions (selected : seen) rest
      where selected = methodIdentity definition

    expand _ Empty = Right (Fix EmptyLayer)
    expand active (Call selected) =
      case lookup selected [(methodIdentity entry, entry) | entry <- definitions] of
        Nothing -> Left (UnknownMethod selected)
        Just entry
          | selected `elem` active -> Left (RecursiveMethod selected)
          | otherwise -> do
              body <- expand (selected : active) (methodBody entry)
              pure (Fix (MethodLayer entry body))
    expand active (Sequence children) = Fix . SequenceLayer <$> mapM (expand active) children
    expand active (Choice children) = Fix . ChoiceLayer <$> mapM (expand active) children
    expand active (Recover body recovery) = do
      before <- expand active body
      after <- expand active recovery
      pure (Fix (RecoverLayer before after))

scopeAlgebra :: Eq method => Algebra (ExpandedF method) [[method]]
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
graphAlgebra
  :: Eq method
  => ExpandedF method ([[method]], EffectGraph method)
  -> EffectGraph method
graphAlgebra layer = EffectGraph
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
    scopePathsHere = scopeAlgebra (fmap fst layer)
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

-- 注册前提补入同一份树。注册前提是依赖：上游 scope 必须比下游活得久，下游的 close 也可能调用上游。
-- 观察到的开启顺序是证据：逐条补入，与注册前提及已补入的边构成相反方向的不作为父边。
-- 路径、候选与反向证据仍保持原观察结果，被推翻的顺序仍在 scopeCandidates 中；不把路径候选的并集当依赖。
-- 声明顺序保留给独立 scope；运行清理使用最终父边的逆拓扑顺序。
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
