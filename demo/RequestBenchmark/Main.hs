-- 运行：runghc -idemo -isdk demo/RequestBenchmark/Main.hs
-- 首次生成接口：cabal run effect-codegen -- target RequestBenchmark
module RequestBenchmark.Main (main) where

import RequestBenchmark.Effects (effects)
import RequestBenchmark.Generated.Program (benchmark, runDemo)
import RequestBenchmark.Target (target)

main :: IO ()
main = runDemo effects target benchmark
