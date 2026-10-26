module FileDemo.AST (ast) where

import Framework.SDK (AST)
import FileDemo.Workflow.OperateFile (operateFile)

-- 顶层引用完整文件操作模块；进入模块查看末端 node。
ast :: AST
ast = operateFile
