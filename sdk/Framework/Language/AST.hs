{-# LANGUAGE DeriveFunctor #-}

-- Workflow 的可序列化结构与引用收集；不启动节点。
module Framework.Language.AST
  ( WorkflowF(..), AST, EffectNode, node, chained, parallel, alternative, lifelong, middleware
  , foldAST, toWorkflowF, stripMiddleware, stripAST
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
  -- Lifelong 订阅持续资产。每个单元按交付重复执行，所有单元结束后本分支成功返回。
  -- 直接子项各为一个单元，直接子项是 parallel 时拆这一层；其余子树作为有限单元整体重复。
  | Lifelong [next]
  -- 透明标注：为子树中 Root 级调用点挂载 Middleware，不改变子树的执行结构与 NodeId。
  | Hooked [String] next
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

chained :: BranchChild child => [child] -> AST
chained children = AST (Fix (Chained (map childTree children)))

parallel :: BranchChild child => [child] -> AST
parallel children = AST (Fix (Parallel (map childTree children)))

alternative :: BranchChild child => [child] -> AST
alternative children = AST (Fix (Alternative (map childTree children)))

lifelong :: BranchChild child => [child] -> AST
lifelong children = AST (Fix (Lifelong (map childTree children)))

-- 第一个参数引用 Middleware 注册，第二个参数是已写明驱动方式的一棵子树。
middleware :: [EffectNode] -> AST -> AST
middleware hooks (AST tree) = AST (Fix (Hooked [selected | EffectNode selected <- hooks] tree))

-- 去掉 middleware 标注：子树占据标注所在的位置，路径编号与没有标注时相同。
-- 同时返回 (标注位置, hook 名) ，按先序排列；嵌套在同一位置的标注各占一项。
stripMiddleware :: Fix WorkflowF -> (Fix WorkflowF, [([Int], [String])])
stripMiddleware = strip []
  where
    strip path (Fix layer) = case layer of
      Hooked hooks child -> let (inner, marks) = strip path child in (inner, (path, hooks) : marks)
      Node selected -> (Fix (Node selected), [])
      Chained children -> rebuild Chained children
      Parallel children -> rebuild Parallel children
      Alternative children -> rebuild Alternative children
      Lifelong children -> rebuild Lifelong children
      where
        rebuild make children =
          let results = [strip (path ++ [index]) child | (index, child) <- zip [0 ..] children]
          in (Fix (make (map fst results)), concatMap snd results)

stripAST :: AST -> (AST, [([Int], [String])])
stripAST (AST tree) = let (inner, marks) = stripMiddleware tree in (AST inner, marks)

-- 解释器只折叠已经构造好的 branch，不能据此把裸 node 提升为 AST。
foldAST :: Algebra WorkflowF value -> AST -> value
foldAST algebra (AST tree) = cata algebra tree

-- SDK 的原型构建器读取有限 AST；业务仍只通过 node/branch 构造。
toWorkflowF :: AST -> Fix WorkflowF
toWorkflowF (AST tree) = tree
