module ScopeReuseDemo.AST (ast) where

import Framework.SDK (AST, chained)
import ScopeReuseDemo.Workflow.PrepareProbe (prepareProbe)
import ScopeReuseDemo.Workflow.WriteInParallel (writeInParallel)
import ScopeReuseDemo.Workflow.VerifyReuse (verifyReuse)

-- 三条独立 Input 链读取 PrepareProbe 的同一次参数生产，共享对应的 scope 实例。
-- 实际使用与待用节点共同保留资源；三条写入链结束后关闭，再汇合检查已有日志。
ast :: AST
ast = chained
  [ prepareProbe
  , writeInParallel
  , verifyReuse
  ]
