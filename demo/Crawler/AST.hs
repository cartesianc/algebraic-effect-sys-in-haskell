module Crawler.AST (ast) where

import Framework.SDK (AST)
import Crawler.Workflow.PrintPages (printPages)

-- 顶层只组合 branch；进入模块查看其 node。
-- 每个打印 requests 自己页面的摘要：gen 把抓取链（会话、抓取、去空白、解析）展开为它的前驱，
-- 所以打印前先抓取并解析本页，不另挂抓取节点。每条使用闭包结束时自动释放空闲 scope。
ast :: AST
ast = printPages
