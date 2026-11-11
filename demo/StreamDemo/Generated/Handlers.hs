-- 自动生成的编译副本；请修改上级 Handlers.hs 后重新生成。
{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE UndecidableInstances #-}
-- handler 是不带参数的类方法；SDK 按注册装配上游、会话与读取来源，运行编译 Generated 副本。
{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE UndecidableInstances #-}

{-# OPTIONS_GHC -Werror=missing-methods #-}

module StreamDemo.Generated.Handlers (handlerSourceFingerprint, openSensorLink, closeSensorLink, nextTemperatureFeed, getTemperatureSample, streamTemperatureSample, nextHeartbeatClock, getBeat, streamBeat, runAnnounce, runShowTemperature, runCheckTrend, runReportHeartbeat, newScopeHandlers, scopeCleanups, errorHandlers, contextInjections) where

import qualified Framework.Generated as FrameworkRuntime
import qualified StreamDemo.Generated.Effects as FrameworkGenerated
import qualified Control.Monad.IO.Class as FrameworkIO
import qualified Data.Proxy as FrameworkProxy
import qualified GHC.TypeLits as FrameworkTypes
import StreamDemo.Types
import Framework.SDK (History, Raises(..), Raw(..), Reads(..), historyEntries, latest)
import StreamDemo.Generated.Effects
import StreamDemo.Types
import Control.Concurrent (threadDelay)
import Control.Monad.IO.Class (liftIO)
import GHC.Clock (getMonotonicTime)
import Text.Printf (printf)

-- 连接在第一次读数时由 Input 打开；生产会话的各步骤共用它，运行退出时由 SDK 关闭。
instance ConnectSensorLayer m => ConnectSensorHandler m where
  connectSensor = do
    liftIO (putStrLn "[sensor] connected")
    pure []

instance DisconnectSensorLayer m => DisconnectSensorHandler m where
  disconnectSensor = do
    liftIO (putStrLn "[sensor] disconnected")
    pure []

-- 一次只取一份原始读数；节奏由 handler 自己的等待决定，SDK 不加间隔。
instance NextReadingLayer m => NextReadingHandler m where
  nextReading = do
    liftIO (threadDelay 700000)
    seconds <- liftIO getMonotonicTime
    pure (printf "%.1f" (21 + 3 * sin (seconds / 3) :: Double))

-- parser 挂在 Stream 下：raw 是会话本次取得的一份原始读数（单元素 list，不会再读一次），返回一份资产的表示值；
-- 发布、历史和交付由 SDK 完成。
instance ParseTemperatureLayer m => ParseTemperatureHandler m where
  parseTemperature = do
    reading <- concat <$> raw
    case reads reading of
      [(value, "")] -> pure (Temperature value)
      _ -> raise (ParseTemperatureError ("unreadable sensor output: " ++ reading))

-- 心跳也是 Stream：每两秒交出一次单调时钟的秒数，由挂在它下面的 parser 解析。
instance NextBeatLayer m => NextBeatHandler m where
  nextBeat = do
    liftIO (threadDelay 2000000)
    seconds <- liftIO getMonotonicTime
    pure (show (round seconds :: Int))

instance ParseBeatLayer m => ParseBeatHandler m where
  parseBeat = do
    tick <- concat <$> raw
    case reads tick of
      [(value, "")] -> pure value
      _ -> raise (ParseBeatError ("unreadable clock output: " ++ tick))

instance AnnounceLayer m => AnnounceHandler m where
  announce = do
    liftIO (putStrLn "Monitoring the sensor; press Ctrl-C to stop.")
    pure []

-- 同一单元的一次执行里，ShowTemperature 与 CheckTrend 读到同一份交付视图。
instance ShowTemperatureLayer m => ShowTemperatureHandler m where
  showTemperature = do
    samples <- require @(History Temperature)
    case latest samples of
      Just (Temperature value) ->
        liftIO (printf "reading #%d: %.1f C\n" (length (historyEntries samples)) value)
      Nothing -> pure ()
    pure []

instance CheckTrendLayer m => CheckTrendHandler m where
  checkTrend = do
    samples <- require @(History Temperature)
    let values = [value | Temperature value <- historyEntries samples]
        recent = drop (length values - 5) values
        average = sum recent / fromIntegral (length recent)
    case reverse recent of
      current : previous : _ ->
        liftIO (printf "  trend %s, average of the last %d: %.2f C\n"
          (if current >= previous then "rising" else "falling" :: String) (length recent) average)
      _ -> liftIO (putStrLn "  trend: waiting for a second reading")
    pure []

instance ReportHeartbeatLayer m => ReportHeartbeatHandler m where
  reportHeartbeat = do
    beats <- require @(History Int)
    liftIO (putStrLn ("[heartbeat] #" ++ show (length (historyEntries beats))))
    pure []

-- 记录本编译副本实际使用的手写源码；启动前检查，避免执行过期方法体。
handlerSourceFingerprint :: Maybe String
handlerSourceFingerprint = Just "6740435b373ec4b64f11e0bf346af887"

-- 以下由 gen 生成。每个 effect 一个类型标签：handler 在标签下执行，
-- 读取、raw 与错误按标签在编译期解析到这个 effect 的来源，不改写 handler 方法体。
newtype At (effect :: FrameworkTypes.Symbol) value = At { runAt :: FrameworkGenerated.App value }
  deriving (Functor, Applicative, Monad, FrameworkIO.MonadIO)

instance FrameworkTypes.KnownSymbol effect => FrameworkRuntime.Raises FrameworkGenerated.ConnectSensorError (At effect) where
  raise (FrameworkGenerated.ConnectSensorError description) = At (FrameworkRuntime.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) FrameworkGenerated.ConnectSensorFailure description)

instance FrameworkTypes.KnownSymbol effect => FrameworkRuntime.Raises FrameworkGenerated.DisconnectSensorError (At effect) where
  raise (FrameworkGenerated.DisconnectSensorError description) = At (FrameworkRuntime.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) FrameworkGenerated.DisconnectSensorFailure description)

instance FrameworkTypes.KnownSymbol effect => FrameworkRuntime.Raises FrameworkGenerated.NextReadingError (At effect) where
  raise (FrameworkGenerated.NextReadingError description) = At (FrameworkRuntime.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) FrameworkGenerated.NextReadingFailure description)

instance FrameworkTypes.KnownSymbol effect => FrameworkRuntime.Raises FrameworkGenerated.ParseTemperatureError (At effect) where
  raise (FrameworkGenerated.ParseTemperatureError description) = At (FrameworkRuntime.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) FrameworkGenerated.ParseTemperatureFailure description)

instance FrameworkTypes.KnownSymbol effect => FrameworkRuntime.Raises FrameworkGenerated.NextBeatError (At effect) where
  raise (FrameworkGenerated.NextBeatError description) = At (FrameworkRuntime.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) FrameworkGenerated.NextBeatFailure description)

instance FrameworkTypes.KnownSymbol effect => FrameworkRuntime.Raises FrameworkGenerated.ParseBeatError (At effect) where
  raise (FrameworkGenerated.ParseBeatError description) = At (FrameworkRuntime.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) FrameworkGenerated.ParseBeatFailure description)

instance FrameworkTypes.KnownSymbol effect => FrameworkRuntime.Raises FrameworkGenerated.AnnounceError (At effect) where
  raise (FrameworkGenerated.AnnounceError description) = At (FrameworkRuntime.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) FrameworkGenerated.AnnounceFailure description)

instance FrameworkTypes.KnownSymbol effect => FrameworkRuntime.Raises FrameworkGenerated.ShowTemperatureError (At effect) where
  raise (FrameworkGenerated.ShowTemperatureError description) = At (FrameworkRuntime.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) FrameworkGenerated.ShowTemperatureFailure description)

instance FrameworkTypes.KnownSymbol effect => FrameworkRuntime.Raises FrameworkGenerated.CheckTrendError (At effect) where
  raise (FrameworkGenerated.CheckTrendError description) = At (FrameworkRuntime.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) FrameworkGenerated.CheckTrendFailure description)

instance FrameworkTypes.KnownSymbol effect => FrameworkRuntime.Raises FrameworkGenerated.ReportHeartbeatError (At effect) where
  raise (FrameworkGenerated.ReportHeartbeatError description) = At (FrameworkRuntime.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) FrameworkGenerated.ReportHeartbeatFailure description)

instance FrameworkRuntime.Reads (FrameworkRuntime.History (Temperature)) (At "ShowTemperature") where
  require = At (fmap (\(FrameworkGenerated.TemperatureSample value) -> value) <$> streamTemperatureSample)

instance FrameworkRuntime.Reads (FrameworkRuntime.History (Temperature)) (At "CheckTrend") where
  require = At (fmap (\(FrameworkGenerated.TemperatureSample value) -> value) <$> streamTemperatureSample)

instance FrameworkRuntime.Reads (FrameworkRuntime.History (Int)) (At "ReportHeartbeat") where
  require = At (fmap (\(FrameworkGenerated.Beat value) -> value) <$> streamBeat)

instance FrameworkRuntime.Raw (At "TemperatureParser") where
  raw = At ((: []) <$> nextTemperatureFeed)

instance FrameworkRuntime.Raw (At "Heartbeat") where
  raw = At ((: []) <$> nextHeartbeatClock)

openSensorLink :: FrameworkGenerated.App [String]
openSensorLink = (FrameworkRuntime.withErrorPath ["SensorLink"] . FrameworkRuntime.handleFailure . FrameworkRuntime.atomicScope "openSensorLink" . FrameworkRuntime.openScope "SensorLink" FrameworkGenerated.ScopeBindingError . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.enterHandler "SensorLink") $
  runAt @"SensorLink" FrameworkGenerated.connectSensor

closeSensorLink :: FrameworkGenerated.App [String]
closeSensorLink = (FrameworkRuntime.withErrorPath ["SensorLink"] . FrameworkRuntime.handleFailure . FrameworkRuntime.atomicScope "closeSensorLink" . FrameworkRuntime.closeScope "SensorLink" FrameworkGenerated.ScopeBindingError . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.enterHandler "SensorLink") $
  runAt @"SensorLink" FrameworkGenerated.disconnectSensor

nextTemperatureFeed :: FrameworkGenerated.App String
nextTemperatureFeed = (FrameworkRuntime.withErrorPath ["SensorLink"] . FrameworkRuntime.handleFailure . FrameworkRuntime.streamHandle . FrameworkRuntime.withScopeDependencies ["SensorLink"] . FrameworkRuntime.enterHandler "TemperatureFeed") $
  openSensorLink >> runAt @"TemperatureFeed" FrameworkGenerated.nextReading

getTemperatureSample :: FrameworkGenerated.App FrameworkGenerated.TemperatureSample
getTemperatureSample = (FrameworkRuntime.withErrorPath ["SensorLink"] . FrameworkRuntime.handleFailure . FrameworkRuntime.withScopeDependencies ["SensorLink"] . FrameworkRuntime.callContext "TemperatureParser"
    Nothing
    (\value bindings -> bindings { FrameworkGenerated.boundTemperatureParser = Just value })) $
  (FrameworkGenerated.TemperatureSample <$> runAt @"TemperatureParser" FrameworkGenerated.parseTemperature)

streamTemperatureSample :: FrameworkGenerated.App (FrameworkRuntime.History FrameworkGenerated.TemperatureSample)
streamTemperatureSample = (FrameworkRuntime.withErrorPath ["SensorLink"] . FrameworkRuntime.handleFailure) $
  FrameworkRuntime.readHistory "TemperatureParser" FrameworkGenerated.ContextBindingError FrameworkGenerated.boundTemperatureParser

nextHeartbeatClock :: FrameworkGenerated.App String
nextHeartbeatClock = (FrameworkRuntime.withErrorPath [] . FrameworkRuntime.handleFailure . FrameworkRuntime.streamHandle . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.enterHandler "HeartbeatClock") $
  runAt @"HeartbeatClock" FrameworkGenerated.nextBeat

getBeat :: FrameworkGenerated.App FrameworkGenerated.Beat
getBeat = (FrameworkRuntime.withErrorPath [] . FrameworkRuntime.handleFailure . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.callContext "Heartbeat"
    Nothing
    (\value bindings -> bindings { FrameworkGenerated.boundHeartbeat = Just value })) $
  (FrameworkGenerated.Beat <$> runAt @"Heartbeat" FrameworkGenerated.parseBeat)

streamBeat :: FrameworkGenerated.App (FrameworkRuntime.History FrameworkGenerated.Beat)
streamBeat = (FrameworkRuntime.withErrorPath [] . FrameworkRuntime.handleFailure) $
  FrameworkRuntime.readHistory "Heartbeat" FrameworkGenerated.ContextBindingError FrameworkGenerated.boundHeartbeat

runAnnounce :: FrameworkGenerated.App [String]
runAnnounce = (FrameworkRuntime.withErrorPath [] . FrameworkRuntime.handleFailure . FrameworkRuntime.atomicHandle "runAnnounce" . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.enterHandler "Announce") $
  runAt @"Announce" FrameworkGenerated.announce

runShowTemperature :: FrameworkGenerated.App [String]
runShowTemperature = (FrameworkRuntime.withErrorPath [] . FrameworkRuntime.handleFailure . FrameworkRuntime.atomicHandle "runShowTemperature" . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.enterHandler "ShowTemperature") $
  runAt @"ShowTemperature" FrameworkGenerated.showTemperature

runCheckTrend :: FrameworkGenerated.App [String]
runCheckTrend = (FrameworkRuntime.withErrorPath [] . FrameworkRuntime.handleFailure . FrameworkRuntime.atomicHandle "runCheckTrend" . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.enterHandler "CheckTrend") $
  runAt @"CheckTrend" FrameworkGenerated.checkTrend

runReportHeartbeat :: FrameworkGenerated.App [String]
runReportHeartbeat = (FrameworkRuntime.withErrorPath [] . FrameworkRuntime.handleFailure . FrameworkRuntime.atomicHandle "runReportHeartbeat" . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.enterHandler "ReportHeartbeat") $
  runAt @"ReportHeartbeat" FrameworkGenerated.reportHeartbeat

-- SDK 内部：scope 按上游到下游登记，退出时逆序收尾；创建不执行业务方法。
newScopeHandlers :: IO [FrameworkRuntime.ScopeHandler FrameworkGenerated.ContextValues FrameworkGenerated.Errors]
newScopeHandlers = sequence
  [ FrameworkRuntime.newScopeHandler "SensorLink" [] (Nothing)
  ]

-- SDK 自动收尾入口；安装时不关闭资源。
scopeCleanups :: [(String, FrameworkGenerated.App ())]
scopeCleanups =
  [ ("SensorLink", () <$ closeSensorLink)
  ]

-- Error 回调登记：按 handles 匹配故障的 handler 与协议分类；关联 scope 由 Input 链推导。
errorHandlers :: [(Maybe String, FrameworkRuntime.ErrorHandler FrameworkGenerated.Errors FrameworkGenerated.App)]
errorHandlers =
  [
  ]

-- 挂在原子句柄下的 Context：句柄的输出交给它的 parser 解析并发布为资产；没有挂接时输出被丢弃。
contextInjections :: [(String, [(String, FrameworkGenerated.App ())])]
contextInjections =
  [
  ]
