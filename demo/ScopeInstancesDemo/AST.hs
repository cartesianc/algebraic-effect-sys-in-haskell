module ScopeInstancesDemo.AST (ast) where

import Framework.SDK (AST, chained)
import ScopeInstancesDemo.Workflow.PrepareFiles (prepareFiles)
import ScopeInstancesDemo.Workflow.CheckInstances (checkInstances)

-- 先准备文件，再让三条使用闭包按当前参数各自开启、退出时自动关闭同一 Scoped 注册的实例。
ast :: AST
ast = chained
  [ prepareFiles
  , checkInstances
  ]
