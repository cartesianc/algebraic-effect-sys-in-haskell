module Crawler.AST (ast) where

import Framework.SDK (AST, chained)
import Crawler.Workflow.ParsePages (parsePages)
import Crawler.Workflow.PrintPages (printPages)

-- 顶层只组合 branch；进入各模块查看其 node，Context 仍由 effect 注册连接。
-- 并行抓取（挂接的 Context 同时解析出页面摘要）全部成功后顺序打印；打印读取摘要，不再抓取。
-- 每条使用闭包结束时自动释放空闲 scope，不另设收尾 branch。
ast :: AST
ast = chained
  [ parsePages
  , printPages
  ]


