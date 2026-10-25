module Crawler.AST (ast) where

import Framework.SDK (AST, chained)
import Crawler.Workflow.ParsePages (parsePages)
import Crawler.Workflow.PrintPages (printPages)
import Crawler.Workflow.FinishCrawl (finishCrawl)

-- 顶层只组合 branch；进入各模块查看其 node，Context 仍由 effect 注册连接。
-- 并行解析全部成功后顺序打印，随后关闭共享 scope。
ast :: AST
ast = chained
  [ parsePages
  , printPages
  , finishCrawl
  ]


