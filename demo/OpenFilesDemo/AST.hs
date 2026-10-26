module OpenFilesDemo.AST (ast) where

import Framework.SDK (AST, chained)
import OpenFilesDemo.Workflow.HoldAndInspectFiles (holdAndInspectFiles)
import OpenFilesDemo.Workflow.FinishInspection (finishInspection)

-- 每个 Node 是独立使用闭包；后续节点显式 open，不预留前一节点的资源。
-- InspectFiles 检查本链及 GC 期间的存续；最后一条链演示显式 close。
ast :: AST
ast = chained
  [ holdAndInspectFiles
  , finishInspection
  ]
