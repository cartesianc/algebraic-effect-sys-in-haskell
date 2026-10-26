module ScopeInstancesDemo.Workflow.PrepareFiles (prepareFiles) where

import Framework.SDK (AST, chained, node)

prepareFiles :: AST
prepareFiles = chained
  [ node "PrepareFiles"
  ]
