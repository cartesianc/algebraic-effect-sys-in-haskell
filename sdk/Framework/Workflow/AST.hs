{-# LANGUAGE DeriveFunctor #-}

-- Workflow 的可序列化结构与引用收集；不启动节点。
module Framework.Workflow.AST
  ( WorkflowF(..), AST, EffectNode, node, chained, parallel, targets, foldAST
  ) where

import Framework.Recursion (Fix(..), Algebra, cata)

-- AST 只保存调用描述；递归位置独立为 next，由不同 algebra 解释。
data WorkflowF next
  = Node String
  | Chained [next]
  | Parallel [next]
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

-- 解释器只折叠已经构造好的 branch，不能据此把裸 node 提升为 AST。
foldAST :: Algebra WorkflowF value -> AST -> value
foldAST algebra (AST tree) = cata algebra tree

targets :: AST -> [String]
targets = foldAST references
  where
    references (Node selected) = [selected]
    references (Chained children) = concat children
    references (Parallel children) = concat children
