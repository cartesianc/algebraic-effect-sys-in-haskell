module ScopeReuseDemo.Workflow.VerifyReuse (verifyReuse) where

import Framework.SDK (AST, chain, node)

verifyReuse :: AST
verifyReuse = chain
  [ node "VerifyReuse"
  ]
