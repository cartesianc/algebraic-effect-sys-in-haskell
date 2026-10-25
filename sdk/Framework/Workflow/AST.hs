{-# LANGUAGE DeriveFunctor #-}

-- Workflow 的可序列化结构与引用收集；不启动节点。
module Framework.Workflow.AST
  ( WorkflowF(..), AST, node, chained, parallel, targets
  ) where

import Framework.Recursion (Fix(..), cata)

-- AST 只保存调用描述；递归位置独立为 next，由不同 algebra 解释。
data WorkflowF next
  = Node String
  | Chained [next]
  | Parallel [next]
  deriving (Functor, Show, Read)

type AST = Fix WorkflowF

node :: String -> AST
node = Fix . Node

chained :: [AST] -> AST
chained = Fix . Chained

parallel :: [AST] -> AST
parallel = Fix . Parallel

targets :: AST -> [String]
targets = cata references
  where
    references (Node selected) = [selected]
    references (Chained children) = concat children
    references (Parallel children) = concat children
