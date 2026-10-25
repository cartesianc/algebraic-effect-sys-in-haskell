module Crawler.Workflow.ParsePages (parsePages) where

import Framework.SDK (AST, parallel, node)

-- 每个 node 选择完整解析链的末端；等待两条链全部完成。
parsePages :: AST
parsePages = parallel
  [ node "ExtractPage"
  , node "ExtractLinkedPage"
  ]
