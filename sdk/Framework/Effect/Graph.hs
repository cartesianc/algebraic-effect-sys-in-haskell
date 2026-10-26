{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveFunctor #-}
{-# LANGUAGE DeriveGeneric #-}

-- 静态方法引用与 scope 开启顺序的纯视图，不保存执行闭包或活资源。
module Framework.Effect.Graph
  ( MethodRole(..), MethodShape(..), MethodDefinition(..)
  , GraphError(..), EffectGraph(..), buildEffectGraph
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
  deriving (Eq, Show, Read, Generic, NFData)

data MethodDefinition method = MethodDefinition
  { methodIdentity :: method
  -- 同一 effect 的方法共用其首个注册入口身份，不增加用户 key。
  , methodEffect :: method
  , methodRole :: MethodRole
  , methodBody :: MethodShape method
  } deriving (Eq, Show, Read, Generic, NFData)

data GraphError method
  = DuplicateMethod method
  | UnknownMethod method
  | RecursiveMethod method
  | UnknownScope method
  | CyclicScopeRelations [method]
  deriving (Eq, Show, Read, Generic, NFData)

data EffectGraph method = EffectGraph
  { graphMethods :: [MethodDefinition method]
  , graphRoots :: [method]
  , graphReferences :: [(method, method)]
  , graphScopes :: [method]
  , graphScopePaths :: [[method]]
  , graphRootPaths :: [(method, [[method]])]
  , graphScopeOrder :: [(method, method)]
  } deriving (Eq, Show, Read, Generic, NFData)

-- scope 的静态身份就是对应 open 方法的身份；共享节点只保存引用。
data ScopeNode method = ScopeNode
  { scopeIdentity :: method
  , scopeParents :: [method]
  , scopeChildren :: [method]
  } deriving (Eq, Show, Read, Generic, NFData)

data ScopeTree method = ScopeTree
  { scopeRoots :: [method]
  , scopeNodes :: [ScopeNode method]
  , scopeLayers :: [[method]]
  , scopePaths :: [[method]]
  , scopeCandidates :: [(method, method)]
  , scopeOpposed :: [(method, method)]
  , scopeUndetermined :: [(method, method)]
  } deriving (Eq, Show, Read, Generic, NFData)

data ExpandedF method next
  = EmptyLayer
  | MethodLayer (MethodDefinition method) next
  | SequenceLayer [next]
  | ChoiceLayer [next]
  | RecoverLayer next next
  deriving Functor

-- 只展开表中显式引用。require 没有隐含的 producer 边，也不启动生产。
-- Choice 保留各分支路径，Sequence 组合路径；有限分支的路径数可能呈指数增长。
-- 同一 scope 在一条路径中只保留首次 open 入口；这不是资源获取完成顺序。
buildEffectGraph
  :: Ord method
  => [(method, method, method)]
  -> [MethodDefinition method]
  -> MethodShape method
  -> Either (GraphError method) (EffectGraph method)
buildEffectGraph routes definitions shape = do
  uniqueDefinitions [] definitions
  expanded <- expand [] Nothing shape
  pure (zygo scopeAlgebra graphAlgebra expanded)
  where
    uniqueDefinitions _ [] = Right ()
    uniqueDefinitions seen (definition : rest)
      | selected `elem` seen = Left (DuplicateMethod selected)
      | otherwise = uniqueDefinitions (selected : seen) rest
      where selected = methodIdentity definition

    expand _ _ Empty = Right (Fix EmptyLayer)
    expand active consumer (Call lexical) =
      let (selected, routedRead) = route consumer lexical
      in case lookup selected [(methodIdentity entry, entry) | entry <- definitions] of
        Nothing -> Left (UnknownMethod selected)
        Just entry ->
          let current = if routedRead || methodRole entry == ContextRequire then consumer else Just selected
              activation = (selected, current)
          -- 生产方法的 require 路由直接读绑定，不调用显式 require 的覆盖方法体。
          -- 仍保留原定义供查看；只有显式调用 require 才展开该定义。
          in if routedRead
            then pure (Fix (MethodLayer entry (Fix EmptyLayer)))
            else if activation `elem` active
              then Left (RecursiveMethod selected)
              else do
                body <- expand (activation : active) current (methodBody entry)
                pure (Fix (MethodLayer entry body))
    expand active consumer (Sequence children) = Fix . SequenceLayer <$> mapM (expand active consumer) children
    expand active consumer (Choice children) = Fix . ChoiceLayer <$> mapM (expand active consumer) children
    expand active consumer (Recover body recovery) = do
      before <- expand active consumer body
      after <- expand active consumer recovery
      pure (Fix (RecoverLayer before after))

    route Nothing selected = (selected, False)
    route (Just consumer) selected = case lookup (consumer, selected)
        [((caller, producer), replacement) | (caller, producer, replacement) <- routes] of
      Nothing -> (selected, False)
      Just replacement -> (replacement, True)

scopeAlgebra :: Eq method => Algebra (ExpandedF method) [[method]]
scopeAlgebra EmptyLayer = [[]]
scopeAlgebra (MethodLayer definition body)
  | methodRole definition == ScopeOpen = paths (map (methodIdentity definition :) body)
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

-- 注册前提补入同一份树。路径、候选与反向证据仍保持原观察结果；
-- 不把路径候选的并集当依赖，也不为了通过初始化而删除冲突关系。
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
    relationships = nub
      ([(parent, selected) | (selected, parents') <- declared, parent <- parents']
        ++ [(parent, scopeIdentity node) | node <- scopeNodes tree, parent <- scopeParents node])
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
