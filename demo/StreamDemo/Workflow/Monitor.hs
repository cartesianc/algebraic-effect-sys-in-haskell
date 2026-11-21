module StreamDemo.Workflow.Monitor (monitor) where

import Framework.SDK (AST, chain, lifelong, node)

-- lifelong 的直接子项各是一个独立推进的单元：
-- 读数单元每收到一条新读数执行一次 ShowTemperature → CheckTrend（两者共享这次交付），
-- 心跳单元每收到一次心跳执行一次。两个单元互不等待；lifelong 没有正常结束。
monitor :: AST
monitor = lifelong
  [ chain [node "ShowTemperature", node "CheckTrend"]
  , chain [node "ReportHeartbeat"]
  ]
