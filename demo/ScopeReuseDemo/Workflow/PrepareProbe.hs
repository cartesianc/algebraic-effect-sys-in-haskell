module ScopeReuseDemo.Workflow.PrepareProbe (prepareProbe) where

import Framework.SDK (AST, chain, node)

prepareProbe :: AST
prepareProbe = chain
  [ node "PrepareProbe"
  ]
