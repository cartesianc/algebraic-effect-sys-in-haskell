-- 生成：cabal run effect-codegen -- workflow OpenFilesDemo
-- 运行：cabal run open-files-demo
module OpenFilesDemo.Main (main) where

import OpenFilesDemo.AST (ast)
import OpenFilesDemo.Effects (effects)
import OpenFilesDemo.Generated.Program (interpreter)

main :: IO ()
main = interpreter ast effects
