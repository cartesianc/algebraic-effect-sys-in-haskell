{-# LANGUAGE DeriveFunctor #-}

-- Workflow 的可序列化结构与引用收集；不启动节点。
module Framework.Workflow.AST
  ( WorkflowF(..), AST, EffectNode, node, chained, parallel, alternative, targets, alternativeGroups, foldAST
  ) where

import Framework.Recursion (Fix(..), Algebra, cata)

-- AST 只保存调用描述；递归位置独立为 next，由不同 algebra 解释。
-- Alternative 只列出候选，不写条件：候选经注册依赖同一和类型资产的不同分支契约，
-- 运行时先 require 该资产，再按它的构造器启动对应候选。
data WorkflowF next
  = Node String
  | Chained [next]
  | Parallel [next]
  | Alternative [next]
  deriving (Functor, Show, Read)

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

chained :: BranchChild child => [child] -> AST
chained children = AST (Fix (Chained (map childTree children)))

parallel :: BranchChild child => [child] -> AST
parallel children = AST (Fix (Parallel (map childTree children)))

alternative :: BranchChild child => [child] -> AST
alternative children = AST (Fix (Alternative (map childTree children)))

-- 解释器只折叠已经构造好的 branch，不能据此把裸 node 提升为 AST。
foldAST :: Algebra WorkflowF value -> AST -> value
foldAST algebra (AST tree) = cata algebra tree

targets :: AST -> [String]
targets = foldAST references
  where
    references (Node selected) = [selected]
    references (Chained children) = concat children
    references (Parallel children) = concat children
    references (Alternative children) = concat children

-- 每个 alternative 的候选及各自的末端，供 gencode 推出候选对应的分支。
alternativeGroups :: AST -> [[[String]]]
alternativeGroups = snd . foldAST groups
  where
    groups (Node selected) = ([selected], [])
    groups (Chained children) = (concatMap fst children, concatMap snd children)
    groups (Parallel children) = (concatMap fst children, concatMap snd children)
    groups (Alternative children) = (concatMap fst children, map fst children : concatMap snd children)
