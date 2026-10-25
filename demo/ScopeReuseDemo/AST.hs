module ScopeReuseDemo.AST (ast) where

import Framework.SDK (AST, chained)
import ScopeReuseDemo.Workflow.PrepareProbe (prepareProbe)
import ScopeReuseDemo.Workflow.WriteInParallel (writeInParallel)
import ScopeReuseDemo.Workflow.VerifyReuse (verifyReuse)

-- 三条独立 Input 链都引用 SharedFileScope；中间不 close。
-- 检查与关闭等待三个写入分支全部完成，不要求写入顺序固定。
ast :: AST
ast = chained
  [ prepareProbe
  , writeInParallel
  , verifyReuse
  ]
