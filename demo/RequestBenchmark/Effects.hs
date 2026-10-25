{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE TypeApplications #-}

module RequestBenchmark.Effects (effects) where

import Framework.SDK (EffectSpec(..), EffectTyping(..), Producer(..), ContextInput(..), ValueSource(..), typeRef)
import RequestBenchmark.Types

-- 1. Registered code（手写）：Input 注入句柄；context 声明消费方的取值来源与 ADT。
-- 三个数值生产操作都是 Context；Pure 执行载体表示本例不需要 IO，不等于 Pure typing。
-- 方法名绑定在 typing 内；handler = Nothing 表示不声明本地调用入口。
-- 只有 typing.Context.request 声明业务产物；错误及最终 Output 由 SDK 提供。
-- context = Nothing 表示不声明业务值输入；typing 内的方法名属于生产方。
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
      , context = Nothing
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
      , context = Just ContextInput
          { request = Just (From "DemoContext" (typeRef @DemoInputs))
          , require = Nothing
          }
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
      , context = Just ContextInput
          { request = Just (From "MakeNumber" (typeRef @NumberValue))
          , require = Nothing
          }
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
      , context = Just ContextInput
          { request = Just (From "AddOne" (typeRef @AddedValue))
          , require = Just (From "DemoContext" (typeRef @DemoInputs))
          }
      }
  ]
