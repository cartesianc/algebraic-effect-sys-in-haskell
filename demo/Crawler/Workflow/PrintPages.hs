module Crawler.Workflow.PrintPages (printPages) where

import Framework.SDK (AST, chained, node)

-- 打印 instance 再次 request 解析链，不复用此前解析模块的产物。
printPages :: AST
printPages = chained
  [ node "PrintPage"
  , node "PrintLinkedPage"
  ]
