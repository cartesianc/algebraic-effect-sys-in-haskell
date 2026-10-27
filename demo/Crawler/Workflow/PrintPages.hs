module Crawler.Workflow.PrintPages (printPages) where

import Framework.SDK (AST, chained, node)

-- 打印 instance require 解析模块产出的摘要，不再抓取。
printPages :: AST
printPages = chained
  [ node "PrintPage"
  , node "PrintLinkedPage"
  ]
