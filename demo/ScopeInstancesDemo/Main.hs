-- 生成：cabal run effect-codegen -- workflow ScopeInstancesDemo
-- 运行：cabal run scope-instances-demo
module ScopeInstancesDemo.Main (main) where

import ScopeInstancesDemo.AST (ast)
import ScopeInstancesDemo.Effects (effects)
import ScopeInstancesDemo.Generated.Program (interpreter)

main :: IO ()
main = interpreter ast effects
