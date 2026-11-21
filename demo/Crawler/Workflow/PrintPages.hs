module Crawler.Workflow.PrintPages (printPages) where

import Framework.SDK (AST, chain, node)

-- 两次打印依次执行；每次先经 requests 抓取并解析本页，再打印摘要。
printPages :: AST
printPages = chain
  [ node "PrintPage"
  , node "PrintLinkedPage"
  ]
