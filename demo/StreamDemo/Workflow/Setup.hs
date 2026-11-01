module StreamDemo.Workflow.Setup (setup) where

import Framework.SDK (AST, chained, node)

-- 有限的准备步骤：执行一次，完成后进入持续监控。
setup :: AST
setup = chained [node "Announce"]
