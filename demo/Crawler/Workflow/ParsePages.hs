module Crawler.Workflow.ParsePages (parsePages) where

import Framework.SDK (AST, parallel, node)

-- 每个 node 选择抓取链的末端；挂在抓取句柄下的 Context 解析其输出并发布摘要。
-- AST 只挂原始句柄，不挂 Context；等待两条链全部完成。
parsePages :: AST
parsePages = parallel
  [ node "FetchPage"
  , node "FetchLinkedPage"
  ]
