module OpenFilesDemo.AST (ast) where

import Framework.SDK (AST, chained)
import OpenFilesDemo.Workflow.HoldAndInspectFiles (holdAndInspectFiles)
import OpenFilesDemo.Workflow.FinishInspection (finishInspection)

-- 先观察跨 Node 的资源存续，再显式关闭作对照。
ast :: AST
ast = chained
  [ holdAndInspectFiles
  , finishInspection
  ]
