{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE TypeApplications #-}

module RequestBenchmark.Effects (effects) where

import Framework.SDK (EffectSpec(..), EffectTyping(..), Producer(..), requests, requires, typeRef)
import RequestBenchmark.Types

-- 1. Registered code（手写）：Input 注入句柄；demands 只声明需要的契约与取值模式。
-- 来源由生成器在注册集合中按类型唯一解析；不同含义使用不同类型。
-- 三个数值生产操作都是 Context；Pure 执行载体表示本例不需要 IO，不等于 Pure typing。
-- 方法名绑定在 typing 内；只有 typing.Context.request 声明业务产物。
effects :: [EffectSpec]
effects =
  [ EffectSpec
      { name = "DemoContext"
      , typing = Context
          { request = Just Producer
              { handler = "loadDemoInputs"
              , produces = typeRef @DemoInputs
              }
          , require = Just "readDemoInputs"
          }
      , input = "Root"
      , demands = []
      }
  , EffectSpec
      { name = "MakeNumber"
      , typing = Context
          { request = Just Producer
              { handler = "makeNumber"
              , produces = typeRef @NumberValue
              }
          , require = Just "readNumber"
          }
      , input = "Root"
      , demands = [requests @DemoInputs]
      }
  , EffectSpec
      { name = "AddOne"
      , typing = Context
          { request = Just Producer
              { handler = "addOne"
              , produces = typeRef @AddedValue
              }
          , require = Just "readAddedNumber"
          }
      , input = "Root"
      , demands = [requests @NumberValue]
      }
  , EffectSpec
      { name = "RenderNumber"
      , typing = Context
          { request = Just Producer
              { handler = "renderNumber"
              , produces = typeRef @RenderedValue
              }
          , require = Just "readRenderedNumber"
          }
      , input = "Root"
      , demands = [requests @AddedValue, requires @DemoInputs]
      }
  ]
