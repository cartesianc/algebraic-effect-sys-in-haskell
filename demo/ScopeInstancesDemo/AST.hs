module ScopeInstancesDemo.AST (ast) where

import Framework.SDK (AST, chained)
import ScopeInstancesDemo.Workflow.PrepareFiles (prepareFiles)
import ScopeInstancesDemo.Workflow.CheckInstances (checkInstances)

-- 一个 interpreter，两个下游 Input 链跨 Node 引用同一 Scoped 注册。
ast :: AST
ast = chained
  [ prepareFiles
  , checkInstances
  ]
