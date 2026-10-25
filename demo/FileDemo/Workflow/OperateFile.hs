module FileDemo.Workflow.OperateFile (operateFile) where

import Framework.SDK (AST, chained, node)

-- 获取路径、开启、读写和关闭仍由 instance 内的引用组合。
operateFile :: AST
operateFile = chained
  [ node "FileWorkflow"
  ]
