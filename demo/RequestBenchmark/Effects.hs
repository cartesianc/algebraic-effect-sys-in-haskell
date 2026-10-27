{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE TypeApplications #-}

module RequestBenchmark.Effects (effects) where

import Framework.SDK (EffectSpec(..), EffectTyping(..), requester, requests, requires)
import RequestBenchmark.Types

-- 1. Registered code（手写）：Input 注入句柄；demands 以契约名声明需要的值与取值模式。
-- requester "handler名" @表示类型：handler 名首字母大写即契约名，生成器产出该 newtype。
-- 三个数值生产操作都是 Context；Pure 执行载体表示本例不需要 IO，不等于 Pure typing。
effects :: [EffectSpec]
effects =
  [ EffectSpec
      { name = "DemoContext"
      , typing = Context { request = requester "demoInputs" @InputSettings }
      , input = "Root"
      , demands = []
      }
  , EffectSpec
      { name = "MakeNumber"
      , typing = Context { request = requester "numberValue" @Int }
      , input = "Root"
      , demands = [requests "DemoInputs"]
      }
  , EffectSpec
      { name = "AddOne"
      , typing = Context { request = requester "addedValue" @Int }
      , input = "Root"
      , demands = [requests "NumberValue"]
      }
  , EffectSpec
      { name = "RenderNumber"
      , typing = Context { request = requester "renderedValue" @String }
      , input = "Root"
      , demands = [requests "AddedValue", requires "DemoInputs"]
      }
  ]
