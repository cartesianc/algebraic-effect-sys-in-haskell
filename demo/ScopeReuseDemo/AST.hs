module ScopeReuseDemo.AST (ast) where

import Framework.SDK (AST, chained)
import ScopeReuseDemo.Workflow.PrepareProbe (prepareProbe)
import ScopeReuseDemo.Workflow.WriteInParallel (writeInParallel)
import ScopeReuseDemo.Workflow.VerifyReuse (verifyReuse)

-- 三条独立 Input 链使用相等的 require 参数；实际重叠时共享同一活实例。
-- 每链完成后撤销使用；汇合后检查已有日志，不预留资源给后续 Node。
ast :: AST
ast = chained
  [ prepareProbe
  , writeInParallel
  , verifyReuse
  ]
