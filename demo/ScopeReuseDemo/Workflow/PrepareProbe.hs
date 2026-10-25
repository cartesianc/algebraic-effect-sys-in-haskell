module ScopeReuseDemo.Workflow.PrepareProbe (prepareProbe) where

import Framework.SDK (AST, chained, node)

prepareProbe :: AST
prepareProbe = chained
  [ node "PrepareProbe"
  ]
