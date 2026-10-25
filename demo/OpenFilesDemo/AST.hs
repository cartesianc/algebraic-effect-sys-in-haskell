module OpenFilesDemo.AST (ast) where

import Framework.SDK (AST, chained, node)

-- 前两个 Node 都不 close：第二个检查第一个返回后是否仍持有十个文件。
-- 最后显式关闭作对照；这是测试收尾，不是 interpreter 自动收尾。
ast :: AST
ast = chained
  [ node "HoldFiles"
  , node "InspectFiles"
  , node "FinishInspection"
  ]
