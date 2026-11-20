module LinesDemo.Hanging (hangingTree) where

import Framework.SDK (HangingTree, hanging, middleware, node)
import LinesDemo.AST (monitorLines)

-- 只观察读行与统计单元及其生产会话；挂载不启动这些分支。
hangingTree :: HangingTree
hangingTree = hanging [middleware [node "TraceLine"] [monitorLines]]
