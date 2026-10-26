module ScopeInstancesDemo.Workflow.CheckInstances (checkInstances) where

import Framework.SDK (AST, chained, node)

checkInstances :: AST
checkInstances = chained
  [ node "CheckIndependent"
  , node "CheckReopen"
  ]
