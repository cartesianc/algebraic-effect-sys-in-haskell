module Crawler.AST (ast) where

import Framework.SDK (AST, node, chained, parallel)

-- 2. AST 只选择整条链的末端；Context 通过 effect 注册的 request/require 接入。
-- 先并行抓取并解析两页，全部成功后再依次执行打印链。
-- PrintPage 的 instance 引用解析句柄，重新抓取与解析，不复用第一阶段结果。
-- parallel 等待全部解析完成，随后顺序打印；全部成功完成后关闭共享 scope。
-- target 只在 node 指定；handler 从注册推导，不在 AST 展开链内操作。
ast :: AST
ast = chained
  [ parallel
      [ node "ExtractPage"
      , node "ExtractLinkedPage"
      ]
  , chained
      [ node "PrintPage"
      , node "PrintLinkedPage"
      ]
  , node "FinishCrawl"
  ]


