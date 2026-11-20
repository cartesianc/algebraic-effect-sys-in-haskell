{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE TypeApplications #-}

module StreamDemo.Effects (effects) where

import Framework.SDK (EffectSpec(..), EffectTyping(..), Asset(..), streams)
import StreamDemo.Types

-- Stream：每次取得一份原始输入（String），本身不是 AST 末端；挂在它下面的 Context 是它的 parser。
-- stream = True 声明持续资产；生产连接与订阅驱动由 gen 根据组合确定。
-- 消费方写 streams "资产名"，handler 用 require @表示类型读取本次交付，
-- 用 stream @表示类型读取 x:xs（本次交付及同一会话中更早的交付）；编号、窗口都由它算出，不另设业务累计。
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
      , typing = Context { asset = Asset @Temperature "TemperatureSample", parser = Just "parseTemperature", require = True, stream = True }
      , input = "TemperatureFeed"
      , demands = []
      }
  , EffectSpec
      { name = "HeartbeatClock"
      , typing = Stream { handler = Just "nextBeat" }
      , input = "SensorLink"
      , demands = []
      }
  , EffectSpec
      { name = "Heartbeat"
      , typing = Context { asset = Asset @Tick "Beat", parser = Just "parseBeat", require = True, stream = True }
      , input = "HeartbeatClock"
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
