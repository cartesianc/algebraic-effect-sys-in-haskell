module OpenFilesDemo.Workflow.HoldAndInspectFiles (holdAndInspectFiles) where

import Framework.SDK (AST, chained, node)

-- 两个 node 都不 close；后一个检查前一个返回后是否仍持有十个文件。
holdAndInspectFiles :: AST
holdAndInspectFiles = chained
  [ node "HoldFiles"
  , node "InspectFiles"
  ]
