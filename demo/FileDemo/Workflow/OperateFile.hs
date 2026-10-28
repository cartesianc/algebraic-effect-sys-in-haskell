module FileDemo.Workflow.OperateFile (operateFile) where

import Framework.SDK (AST, alternative, node)

-- 文件为空时写入首行，已有内容时追加。AST 只列候选、不写条件：
-- 先 require 文件状态（和类型资产），再按它当前的构造器启动对应候选；链退出后自动清理。
operateFile :: AST
operateFile = alternative
  [ node "WriteFirstLine"
  , node "AppendLine"
  ]
