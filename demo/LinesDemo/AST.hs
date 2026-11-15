module LinesDemo.AST (ast) where

import Framework.SDK (AST, chained, lifelong, node)

-- 先说明要读的文件，再逐行处理：每一轮先打印这一行，再打印到这一行为止的统计。
-- 来源结束、已发布的行都处理完后 lifelong 返回，Report 才执行。
ast :: AST
ast = chained
  [ chained [node "Announce"]
  , lifelong [chained [node "PrintLine", node "ShowTotal"]]
  , chained [node "Report"]
  ]
