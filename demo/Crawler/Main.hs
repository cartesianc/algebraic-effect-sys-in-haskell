-- 运行：cabal run crawler-demo
-- 首次生成接口：cabal run effect-codegen -- workflow Crawler
module Crawler.Main (main) where

import Crawler.AST (ast)
import Crawler.Effects (effects)
import Crawler.Generated.Program (interpreter)

main :: IO ()
main = interpreter ast effects
