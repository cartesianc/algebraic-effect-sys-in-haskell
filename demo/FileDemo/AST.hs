module FileDemo.AST (ast) where

import Framework.SDK (AST, node)

-- Node 只选择末端；获取路径、开启、读写和关闭由 instance 内的引用组合。
ast :: AST
ast = node "FileWorkflow"
