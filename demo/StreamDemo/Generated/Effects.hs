{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MonoLocalBinds #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE UndecidableInstances #-}

-- 自动生成；通过 SDK 的 effect-codegen 更新，手写注册与 handler 位于上级目录。
module StreamDemo.Generated.Effects where

import qualified Framework.Generated as SDK
import Control.Monad.IO.Class (MonadIO)
import StreamDemo.Types

-- SDK 提供运行载体；资产存储与错误分类由本文件给出。
type App = SDK.App ContextValues Errors

-- 每个 Context 的资产类型：名字来自 Asset 声明，包装其表示类型。
newtype TemperatureSample = TemperatureSample (Temperature)
deriving instance Eq (Temperature) => Eq TemperatureSample
deriving instance Show (Temperature) => Show TemperatureSample

newtype Beat = Beat (Int)
deriving instance Eq (Int) => Eq Beat
deriving instance Show (Int) => Show Beat

-- effect 方法的定义身份；仅生成区使用，图中不以字符串匹配方法。
data MethodGen = OpenSensorLinkGen | CloseSensorLinkGen | NextTemperatureFeedGen | GetTemperatureSampleGen | StreamTemperatureSampleGen | NextHeartbeatClockGen | GetBeatGen | StreamBeatGen | RunAnnounceGen | RunShowTemperatureGen | RunCheckTrendGen | RunReportHeartbeatGen
  deriving (Eq, Ord, Show, Read, SDK.Generic)
instance SDK.NFData MethodGen

-- handler connectSensor：绑定到 SensorLink。
type ConnectSensorLayer m = (SDK.Raises ConnectSensorError m, MonadIO m)
class ConnectSensorHandler m where
  connectSensor :: m [String]

-- 失败属于 handler：发生位置由 SDK 记录，Error 按 RaisedBy "connectSensor" 匹配。
newtype ConnectSensorError = ConnectSensorError String
  deriving (Eq, Show, Read)

-- handler disconnectSensor：绑定到 SensorLink。
type DisconnectSensorLayer m = (SDK.Raises DisconnectSensorError m, MonadIO m)
class DisconnectSensorHandler m where
  disconnectSensor :: m [String]

-- 失败属于 handler：发生位置由 SDK 记录，Error 按 RaisedBy "disconnectSensor" 匹配。
newtype DisconnectSensorError = DisconnectSensorError String
  deriving (Eq, Show, Read)

-- handler nextReading：绑定到 TemperatureFeed。
type NextReadingLayer m = (SDK.Raises NextReadingError m, MonadIO m)
class NextReadingHandler m where
  nextReading :: m String

-- 失败属于 handler：发生位置由 SDK 记录，Error 按 RaisedBy "nextReading" 匹配。
newtype NextReadingError = NextReadingError String
  deriving (Eq, Show, Read)

-- handler parseTemperature：绑定到 TemperatureParser。
type ParseTemperatureLayer m = (SDK.Raw m, SDK.Raises ParseTemperatureError m, MonadIO m)
class ParseTemperatureHandler m where
  parseTemperature :: m Temperature

-- 失败属于 handler：发生位置由 SDK 记录，Error 按 RaisedBy "parseTemperature" 匹配。
newtype ParseTemperatureError = ParseTemperatureError String
  deriving (Eq, Show, Read)

-- handler nextBeat：绑定到 HeartbeatClock。
type NextBeatLayer m = (SDK.Raises NextBeatError m, MonadIO m)
class NextBeatHandler m where
  nextBeat :: m String

-- 失败属于 handler：发生位置由 SDK 记录，Error 按 RaisedBy "nextBeat" 匹配。
newtype NextBeatError = NextBeatError String
  deriving (Eq, Show, Read)

-- handler parseBeat：绑定到 Heartbeat。
type ParseBeatLayer m = (SDK.Raw m, SDK.Raises ParseBeatError m, MonadIO m)
class ParseBeatHandler m where
  parseBeat :: m Int

-- 失败属于 handler：发生位置由 SDK 记录，Error 按 RaisedBy "parseBeat" 匹配。
newtype ParseBeatError = ParseBeatError String
  deriving (Eq, Show, Read)

-- handler announce：绑定到 Announce。
type AnnounceLayer m = (SDK.Raises AnnounceError m, MonadIO m)
class AnnounceHandler m where
  announce :: m [String]

-- 失败属于 handler：发生位置由 SDK 记录，Error 按 RaisedBy "announce" 匹配。
newtype AnnounceError = AnnounceError String
  deriving (Eq, Show, Read)

-- handler showTemperature：绑定到 ShowTemperature。
type ShowTemperatureLayer m = (SDK.Reads (SDK.History (Temperature)) m, SDK.Raises ShowTemperatureError m, MonadIO m)
class ShowTemperatureHandler m where
  showTemperature :: m [String]

-- 失败属于 handler：发生位置由 SDK 记录，Error 按 RaisedBy "showTemperature" 匹配。
newtype ShowTemperatureError = ShowTemperatureError String
  deriving (Eq, Show, Read)

-- handler checkTrend：绑定到 CheckTrend。
type CheckTrendLayer m = (SDK.Reads (SDK.History (Temperature)) m, SDK.Raises CheckTrendError m, MonadIO m)
class CheckTrendHandler m where
  checkTrend :: m [String]

-- 失败属于 handler：发生位置由 SDK 记录，Error 按 RaisedBy "checkTrend" 匹配。
newtype CheckTrendError = CheckTrendError String
  deriving (Eq, Show, Read)

-- handler reportHeartbeat：绑定到 ReportHeartbeat。
type ReportHeartbeatLayer m = (SDK.Reads (SDK.History (Int)) m, SDK.Raises ReportHeartbeatError m, MonadIO m)
class ReportHeartbeatHandler m where
  reportHeartbeat :: m [String]

-- 失败属于 handler：发生位置由 SDK 记录，Error 按 RaisedBy "reportHeartbeat" 匹配。
newtype ReportHeartbeatError = ReportHeartbeatError String
  deriving (Eq, Show, Read)

-- 统一失败协议的分类标签：每个 handler 一个；消息与发生位置由 SDK.Failure 保存。
data Errors = ConnectSensorFailure | DisconnectSensorFailure | NextReadingFailure | ParseTemperatureFailure | NextBeatFailure | ParseBeatFailure | AnnounceFailure | ShowTemperatureFailure | CheckTrendFailure | ReportHeartbeatFailure | ContextBindingError SDK.ContextFault | ScopeBindingError SDK.ScopeFault
  deriving (Eq, Show)

-- SDK 内部存储：Nothing 仅表示本次运行尚未建立绑定，不是业务缺值。
data ContextValues = ContextValues
  { boundTemperatureParser :: Maybe TemperatureSample
  , boundHeartbeat :: Maybe Beat
  }

emptyContexts :: ContextValues
emptyContexts = ContextValues Nothing Nothing

