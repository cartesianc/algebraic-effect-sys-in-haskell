module Crawler.Workflow.FinishCrawl (finishCrawl) where

import Framework.SDK (AST, chained, node)

finishCrawl :: AST
finishCrawl = chained
  [ node "FinishCrawl"
  ]
