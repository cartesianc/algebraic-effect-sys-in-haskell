module ScopeReuseDemo.Workflow.WriteInParallel (writeInParallel) where

import Framework.SDK (AST, parallel, node)

writeInParallel :: AST
writeInParallel = parallel
  [ node "WriteFirst"
  , node "WriteSecond"
  , node "WriteThird"
  ]
