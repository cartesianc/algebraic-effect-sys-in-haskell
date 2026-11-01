module StreamDemo.AST (ast) where

import Framework.SDK (AST, chained)
import StreamDemo.Workflow.Monitor (monitor)
import StreamDemo.Workflow.Setup (setup)

-- 先执行一次准备，再进入持续监控。
ast :: AST
ast = chained [setup, monitor]
