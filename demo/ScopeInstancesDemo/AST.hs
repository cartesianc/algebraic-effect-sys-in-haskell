module ScopeInstancesDemo.AST (ast) where

import Framework.SDK (AST, chained, node)

-- 一个 interpreter，两个下游 Input 链跨 Node 引用同一 Scoped 注册。
ast :: AST
ast = chained [node "PrepareFiles", node "CheckIndependent", node "CheckReopen"]
