-- 生成：cabal run effect-codegen -- workflow StreamDemo
-- 运行：cabal run stream-demo（持续运行；观察输出后按 Ctrl-C 结束，SDK 取消会话并收尾）
module StreamDemo.Main (main) where

import StreamDemo.AST (ast)
import StreamDemo.Effects (effects)
import StreamDemo.Generated.Program (interpreter)

main :: IO ()
main = interpreter ast effects
