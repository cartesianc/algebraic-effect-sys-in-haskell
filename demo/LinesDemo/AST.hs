module LinesDemo.AST (ast, snapshotAst) where

import Framework.SDK (AST, chained, lifelong, middleware, node, parallel)

-- 一个单元逐行打印并统计，同次输出经 parser 发布；另一个单元按统计增量显示。
-- 打印与显示可以交错。发布单元结束后统计来源封口，显示单元排空，Report 才执行。
ast :: AST
ast = middleware [node "TraceLine"] $ chained
  [ chained [node "Announce"]
  , lifelong
      [ parallel
          [ chained [node "PrintLine", node "TextCounter"]
          , chained [node "ShowTotal"]
          ]
      ]
  , chained [node "Report"]
  ]

-- 一次性读取同一派生资产：选用 ast = snapshotAst 后重新生成。
-- CountParser 沿独立生产链订阅 TextLine；Report 只读取本次统计，不因随后增量重复执行。
-- 这仍由 main = interpreter ast effects 启动，不提供绕过 workflow 的入口。
snapshotAst :: AST
snapshotAst = chained [node "Announce", node "Report"]
