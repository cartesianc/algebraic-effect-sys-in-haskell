-- 生成：cabal run effect-codegen -- workflow FileDemo
-- 运行：cabal run file-demo
module FileDemo.Main (main) where

import FileDemo.AST (ast)
import FileDemo.Effects (effects)
import FileDemo.Generated.Program (interpreter)

main :: IO ()
main = interpreter ast effects
