module ScopeReuseDemo.Workflow.VerifyReuse (verifyReuse) where

import Framework.SDK (AST, chained, node)

verifyReuse :: AST
verifyReuse = chained
  [ node "VerifyReuse"
  ]
