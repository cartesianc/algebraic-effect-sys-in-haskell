module FileDemo.Workflow.OperateFile (operateFile) where

import Framework.SDK (AST, chained, node)

-- 获取路径、开启和读写由 instance 内引用组合；完整链退出后自动清理。
operateFile :: AST
operateFile = chained
  [ node "FileWorkflow"
  ]
