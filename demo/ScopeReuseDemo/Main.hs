-- 生成：cabal run effect-codegen -- workflow ScopeReuseDemo
-- 运行：cabal run scope-reuse-demo
module ScopeReuseDemo.Main (main) where

import ScopeReuseDemo.AST (ast)
import ScopeReuseDemo.Effects (effects)
import ScopeReuseDemo.Generated.Program (interpreter)

main :: IO ()
main = interpreter ast effects
