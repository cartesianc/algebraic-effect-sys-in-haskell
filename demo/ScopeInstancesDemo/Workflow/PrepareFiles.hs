module ScopeInstancesDemo.Workflow.PrepareFiles (prepareFiles) where

import Framework.SDK (AST, chain, node)

prepareFiles :: AST
prepareFiles = chain
  [ node "PrepareFiles"
  ]
