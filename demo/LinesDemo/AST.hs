module LinesDemo.AST (ast) where

import Framework.SDK (AST, chained, lifelong, node, parallel)

-- 一个单元逐行打印并统计，同次输出经 parser 发布；另一个单元按统计增量显示。
-- 打印与显示可以交错。发布单元结束后统计来源封口，显示单元排空，Report 才执行。
ast :: AST
ast = chained
  [ chained [node "Announce"]
  , lifelong
      [ parallel
          [ chained [node "PrintLine", node "TextCounter"]
          , chained [node "ShowTotal"]
          ]
      ]
  , chained [node "Report"]
  ]
