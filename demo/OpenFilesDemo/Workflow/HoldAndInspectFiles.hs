module OpenFilesDemo.Workflow.HoldAndInspectFiles (holdAndInspectFiles) where

import Framework.SDK (AST, chained, node)

-- 两个 node 各自持有一次使用闭包；后一个经 Input 重新开启，并检查本链的文件存续。
holdAndInspectFiles :: AST
holdAndInspectFiles = chained
  [ node "HoldFiles"
  , node "InspectFiles"
  ]
