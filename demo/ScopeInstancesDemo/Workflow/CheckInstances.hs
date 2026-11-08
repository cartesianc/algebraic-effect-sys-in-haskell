module ScopeInstancesDemo.Workflow.CheckInstances (checkInstances) where

import Framework.SDK (AST, chained, node)

-- 三条使用闭包引用同一 Scoped 注册；前一条退出后实例关闭，后一条按当前参数开启新实例。
checkInstances :: AST
checkInstances = chained
  [ node "UseFirst"
  , node "SelectSecond"
  , node "UseSecond"
  , node "SelectFirst"
  , node "ReopenFirst"
  , node "CheckJournal"
  ]
