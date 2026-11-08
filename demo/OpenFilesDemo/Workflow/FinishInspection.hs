module OpenFilesDemo.Workflow.FinishInspection (finishInspection) where

import Framework.SDK (AST, chained, node)

-- 先持有一次文件并记下快照，链退出时 SDK 关闭它们；随后的 node 检查快照中的文件已经关闭。
finishInspection :: AST
finishInspection = chained
  [ node "ReleaseFiles"
  , node "FinishInspection"
  ]
