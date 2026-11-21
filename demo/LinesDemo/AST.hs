module LinesDemo.AST (ast, monitorLines, snapshotAst) where

import Framework.SDK (AST, chain, lifelong, node)

-- 一个单元逐行打印并统计，同次输出经 parser 发布；另一个单元按统计增量显示。
-- 打印与显示可以交错。发布单元结束后统计来源封口，显示单元排空，Report 才执行。
ast :: AST
ast = chain
  [ chain [node "Announce"]
  , monitorLines
  , chain [node "Report"]
  ]

monitorLines :: AST
monitorLines = lifelong
  [ chain [node "PrintLine", node "TextCounter"]
  , chain [node "ShowTotal"]
  ]

-- 一次性读取同一派生资产：选用 ast = snapshotAst 时将 Hanging.hs 的目标同步改成 snapshotAst，再重新生成。
-- CountParser 沿独立生产链订阅 TextLine；Report 只读取本次统计，不因随后增量重复执行。
-- 这仍由 main = interpreter ast effects 启动，不提供绕过 workflow 的入口。
snapshotAst :: AST
snapshotAst = chain [node "Announce", node "Report"]
