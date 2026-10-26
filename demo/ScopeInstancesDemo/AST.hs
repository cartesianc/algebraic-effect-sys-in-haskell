module ScopeInstancesDemo.AST (ast) where

import Framework.SDK (AST, chained, node)

-- 两条独立使用闭包引用同一 Scoped 注册；前一链结束后，后一链显式 open 新一轮。
ast :: AST
ast = chained [node "PrepareFiles", node "CheckIndependent", node "CheckReopen"]
