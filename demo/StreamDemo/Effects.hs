{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE TypeApplications #-}

module StreamDemo.Effects (effects) where

import Framework.SDK (EffectSpec(..), EffectTyping(..), namedAsset, streams)
import StreamDemo.Types

-- Stream：每次取得一份原始输入（String），本身不是 AST 末端；挂在它下面的 Context 用 stream 角色解析。
-- stream = Just () 声明持续资产：require 返回 History。挂在 Stream 下时由接收会话生产（Receive），
-- 否则由会话反复执行 request（RepeatRequest）。生产方式只看资产自己的注册。
-- 消费方写 streams "资产名"：以该资产的新交付驱动，同时取得 require 读取权限；只能挂在 lifelong 内。
effects :: [EffectSpec]
effects =
  [ EffectSpec
      { name = "SensorLink"
      , typing = Scoped { open = Just "connectSensor", close = Just "disconnectSensor" }
      , input = "Root"
      , demands = []
      }
  , EffectSpec
      { name = "TemperatureFeed"
      , typing = Stream { handler = Just "nextReading" }
      , input = "SensorLink"
      , demands = []
      }
  , EffectSpec
      { name = "TemperatureParser"
      , typing = Context { asset = namedAsset "TemperatureSample" @Temperature, request = Nothing, require = Just (), stream = Just () }
      , input = "TemperatureFeed"
      , demands = []
      }
  , EffectSpec
      { name = "Heartbeat"
      , typing = Context { asset = namedAsset "Beat" @Int, request = Just (), require = Just (), stream = Just () }
      , input = "Root"
      , demands = []
      }
  , EffectSpec
      { name = "Announce"
      , typing = Excu { handler = Just "announce" }
      , input = "Root"
      , demands = []
      }
  , EffectSpec
      { name = "ShowTemperature"
      , typing = Excu { handler = Just "showTemperature" }
      , input = "Root"
      , demands = [streams "TemperatureSample"]
      }
  , EffectSpec
      { name = "CheckTrend"
      , typing = Excu { handler = Just "checkTrend" }
      , input = "Root"
      , demands = [streams "TemperatureSample"]
      }
  , EffectSpec
      { name = "ReportHeartbeat"
      , typing = Excu { handler = Just "reportHeartbeat" }
      , input = "Root"
      , demands = [streams "Beat"]
      }
  ]
