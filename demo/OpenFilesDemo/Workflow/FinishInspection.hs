module OpenFilesDemo.Workflow.FinishInspection (finishInspection) where

import Framework.SDK (AST, chained, node)

finishInspection :: AST
finishInspection = chained
  [ node "FinishInspection"
  ]
