{-# LANGUAGE DeriveFunctor #-}

-- Workflow 的可序列化结构与引用收集；不启动节点。
module Framework.Language.AST
  ( WorkflowF(..), AST, EffectNode, node, chain, parallel, alternative, lifelong
  , HangingTree, MiddlewareMount, hanging, middleware, hangingRows, foldAST, toWorkflowF, normalizeWorkflow
  ) where

import Framework.Recursion (Fix(..), Algebra, cata)

-- AST 只保存调用描述；递归位置独立为 next，由不同 algebra 解释。
-- Alternative 只列出候选，不写条件：候选经注册依赖同一和类型资产的不同分支契约，
-- 运行时先驱动该资产（相当于 requests；持续资产领取本次交付），再按它的构造器启动对应候选。
data WorkflowF next
  = Node String
  | Chained [next]
  | Parallel [next]
  | Alternative [next]
  -- Lifelong 订阅持续资产。每个直接子项是一个单元，按交付整体重复执行，所有单元结束后本分支成功返回。
  -- 子项里的 parallel 只是一轮之内的并发汇合，不再划分单元。
  | Lifelong [next]
  deriving (Eq, Functor, Show, Read)

-- 对外区分原子节点与完整 branch，不导出构造器或原始树转换。
newtype EffectNode = EffectNode String
newtype AST = AST (Fix WorkflowF)

-- 仅 SDK 内部提供这两种子项；齐次列表不允许 node 与 branch 混排。
class BranchChild child where
  childTree :: child -> Fix WorkflowF

instance BranchChild EffectNode where
  childTree (EffectNode selected) = Fix (Node selected)

instance BranchChild AST where
  childTree (AST tree) = tree

node :: String -> EffectNode
node = EffectNode

chain :: BranchChild child => [child] -> AST
chain children = AST (Fix (Chained (map childTree children)))

parallel :: BranchChild child => [child] -> AST
parallel children = AST (Fix (Parallel (map childTree children)))

alternative :: BranchChild child => [child] -> AST
alternative children = AST (Fix (Alternative (map childTree children)))

lifelong :: BranchChild child => [child] -> AST
lifelong children = AST (Fix (Lifelong (map childTree children)))

-- Hanging 是独立的编译期声明。AST 引用由 GHC 类检，gen 从其定义名确定业务树中的全部位置。
data MiddlewareMount = MiddlewareMount [EffectNode] [AST]
newtype HangingTree = HangingTree [MiddlewareMount]

middleware :: [EffectNode] -> [AST] -> MiddlewareMount
middleware = MiddlewareMount

hanging :: [MiddlewareMount] -> HangingTree
hanging = HangingTree

-- 名字和顺序沿用声明求值的结果；目标身份另由前端从具名引用取得。
hangingRows :: HangingTree -> [([String], Int)]
hangingRows (HangingTree mounts) =
  [([name | EffectNode name <- hooks], length targets) | MiddlewareMount hooks targets <- mounts]

-- 解释器只折叠已经构造好的 branch，不能据此把裸 node 提升为 AST。
-- 折叠的是规范形式：gen 按同一形式编号，运行与展示逐层核对的也是它。
foldAST :: Algebra WorkflowF value -> AST -> value
foldAST algebra (AST tree) = cata algebra (fst (normalizeWorkflow tree))

-- SDK 的原型构建器读取有限 AST；业务仍只通过 node/branch 构造。
-- 这里是业务写下的原样结构，路径与 Hanging 的源码挂载位置一致；编号前由 gen 规范化。
toWorkflowF :: AST -> Fix WorkflowF
toWorkflowF (AST tree) = tree

-- 规范形式只做语义不变的改写，是 NodeId 的唯一来源：
--   * chain 里的 chain、parallel 里的 parallel 拼入外层（顺序执行与并行汇合都满足结合律）；
--   * chain 与 parallel 中的空 chain／parallel 删除（单位元）；
--   * 只剩一个子项的 chain／parallel 就是这个子项（裸 node 与只含它的 chain 等价）。
-- 这些改写在任何位置都成立，包括 lifelong 的单元内部和 alternative 的候选。
-- lifelong 与 alternative 自身不拼入外层：lifelong 的每个直接子项是一个单元，alternative 的候选按位置保留。
-- 空单元、空候选和空 lifelong 原样保留，由 gen 拒绝。
-- 第二个结果把原树中的路径映射到规范形式中覆盖同一子树的位置：保留下来的节点映射到自身，
-- 被拼入外层或删除的 chain／parallel 映射到它各子项的位置（空的映射为空）。
normalizeWorkflow :: Fix WorkflowF -> (Fix WorkflowF, [Int] -> [[Int]])
normalizeWorkflow tree = (strip shaped, relocate)
  where
    shaped = general [] tree
    placed = positions [] shaped
    original = childPaths [] tree
    relocate path = case lookup path placed of
      Just found -> [found]
      Nothing -> concatMap relocate (maybe [] id (lookup path original))
    general path (Fix layer) = case layer of
      Node selected -> Shaped [path] (Node selected)
      Chained children -> gather path Chained isChained (indexed path children)
      Parallel children -> gather path Parallel isParallel (indexed path children)
      Alternative children -> Shaped [path] (Alternative [general at child | (at, child) <- indexed path children])
      Lifelong children -> Shaped [path] (Lifelong [general at child | (at, child) <- indexed path children])
    gather path constructor same children = case concatMap (splice same) [general at child | (at, child) <- children] of
      [Shaped origins only] -> Shaped (path : origins) only
      remaining -> Shaped [path] (constructor remaining)
    splice same part@(Shaped _ layer)
      | null (members layer) && (isChained layer || isParallel layer) = []
      | same layer = members layer
      | otherwise = [part]
    indexed path children = [(path ++ [index], child) | (index, child) <- zip [0 ..] children]
    positions path (Shaped origins layer) = [(origin, path) | origin <- origins]
      ++ concat [positions (path ++ [index]) child | (index, child) <- zip [0 ..] (members layer)]
    childPaths path (Fix layer) = (path, map fst (indexed path (members layer)))
      : concat [childPaths at child | (at, child) <- indexed path (members layer)]
    strip (Shaped _ layer) = Fix (fmap strip layer)

-- 规范化的中间结果：每个节点记下化简进它的原树路径。
data Shaped = Shaped [[Int]] (WorkflowF Shaped)

members :: WorkflowF child -> [child]
members layer = case layer of
  Node _ -> []
  Chained children -> children
  Parallel children -> children
  Alternative children -> children
  Lifelong children -> children

isChained :: WorkflowF child -> Bool
isChained (Chained _) = True
isChained _ = False

isParallel :: WorkflowF child -> Bool
isParallel (Parallel _) = True
isParallel _ = False
