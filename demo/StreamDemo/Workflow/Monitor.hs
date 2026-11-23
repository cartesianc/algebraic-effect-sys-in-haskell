module StreamDemo.Workflow.Monitor (monitor) where

import Framework.SDK (AST, chain, lifelong, node, parallel)

-- 读数与心跳是两个独立来源，各写一个 lifelong，并发须用 parallel 显式写出。
-- 读数每发布一条执行一次 ShowTemperature → CheckTrend（两者读同一次交付），心跳每发布一次执行一次 ReportHeartbeat。
-- 两个来源都不结束，monitor 没有正常结束。
monitor :: AST
monitor = parallel
  [ lifelong [chain [node "ShowTemperature", node "CheckTrend"]]
  , lifelong [chain [node "ReportHeartbeat"]]
  ]
