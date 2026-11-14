-- 生成：cabal run effect-codegen -- workflow LinesDemo
-- 运行：cabal run lines-demo（读完输入文件后自行结束）
module LinesDemo.Main (main) where

import LinesDemo.AST (ast)
import LinesDemo.Effects (effects)
import LinesDemo.Generated.Program (interpreter)

main :: IO ()
main = interpreter ast effects
