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

module StreamDemo.Generated.Handlers (handlerSourceFingerprint, getSensorState, readSensorState, openSensorLink, closeSensorLink, nextTemperatureFeed, getTemperatureSample, streamTemperatureSample, nextHeartbeatClock, getBeat, streamBeat, runAnnounce, runShowTemperature, runCheckTrend, runReportHeartbeat, newScopeHandlers, errorHandlers) where

import qualified Framework.Generated as FrameworkRuntime
import qualified StreamDemo.Generated.Effects as FrameworkGenerated
import qualified Control.Monad.IO.Class as FrameworkIO
import qualified Data.Proxy as FrameworkProxy
import qualified GHC.TypeLits as FrameworkTypes
import StreamDemo.Types
import Framework.SDK (Raises(..), Raw(..), Reads(..), rawoutput)
import StreamDemo.Generated.Effects
import StreamDemo.Types
import Control.Concurrent (threadDelay)
import Control.Monad.IO.Class (liftIO)
import Data.IORef (atomicModifyIORef', newIORef)
import GHC.Clock (getMonotonicTime)
import Text.Printf (printf)

-- 两个来源共用同一传感器会话；内存里的累计是业务资源，不是 SDK 的特殊资产。
instance PrepareSensorLayer m => PrepareSensorHandler m where
  prepareSensor = liftIO (SensorMemory <$> newIORef (0, []) <*> newIORef 0)

-- 连接在第一次读数时由 Input 打开；生产会话的各步骤共用它，运行退出时由 SDK 关闭。
instance ConnectSensorLayer m => ConnectSensorHandler m where
  connectSensor = do
    SensorMemory _ _ <- require @SensorMemory
    liftIO (putStrLn "[sensor] connected")
    rawoutput []

instance DisconnectSensorLayer m => DisconnectSensorHandler m where
  disconnectSensor = do
    SensorMemory _ _ <- require @SensorMemory
    liftIO (putStrLn "[sensor] disconnected")
    rawoutput []

-- 一次只取一份原始读数；节奏由 handler 自己的等待决定，SDK 不加间隔。
instance NextReadingLayer m => NextReadingHandler m where
  nextReading = do
    liftIO (threadDelay 700000)
    seconds <- liftIO getMonotonicTime
    pure (printf "%.1f" (21 + 3 * sin (seconds / 3) :: Double))

-- parser 挂在 Stream 下：rawinput 是会话本次取得的一份原始读数（单元素 list，不会再读一次），返回一份资产的表示值；
-- 发布与交付由 SDK 完成；最近五次读数由这个业务 parser 维护。
instance ParseTemperatureLayer m => ParseTemperatureHandler m where
  parseTemperature = do
    reading <- concat <$> rawinput
    SensorMemory samples _ <- require @SensorMemory
    case reads reading of
      [(value, "")] -> liftIO $ atomicModifyIORef' samples $ \(count, previous) ->
        let recent = take 5 (value : previous)
            number = count + 1
        in number `seq` ((number, recent), Temperature number value recent)
      _ -> raise (ParseTemperatureError ("unreadable sensor output: " ++ reading))

-- 心跳也是 Stream：每两秒交出一次单调时钟的秒数，由挂在它下面的 parser 解析。
instance NextBeatLayer m => NextBeatHandler m where
  nextBeat = do
    liftIO (threadDelay 2000000)
    seconds <- liftIO getMonotonicTime
    pure (show (round seconds :: Int))

instance ParseBeatLayer m => ParseBeatHandler m where
  parseBeat = do
    tick <- concat <$> rawinput
    SensorMemory _ beats <- require @SensorMemory
    case reads tick :: [(Int, String)] of
      [(_, "")] -> liftIO $ atomicModifyIORef' beats $ \previous ->
        let number = previous + 1 in (number, number)
      _ -> raise (ParseBeatError ("unreadable clock output: " ++ tick))

instance AnnounceLayer m => AnnounceHandler m where
  announce = do
    liftIO (putStrLn "Monitoring the sensor; press Ctrl-C to stop.")
    rawoutput []

-- 同一单元的一次执行里，ShowTemperature 与 CheckTrend 读到同一份交付视图。
instance ShowTemperatureLayer m => ShowTemperatureHandler m where
  showTemperature = do
    Temperature number value _ <- require @Temperature
    liftIO (printf "reading #%d: %.1f C\n" number value)
    rawoutput []

instance CheckTrendLayer m => CheckTrendHandler m where
  checkTrend = do
    Temperature _ _ recent <- require @Temperature
    let average = sum recent / fromIntegral (length recent)
    case recent of
      current : previous : _ ->
        liftIO (printf "  trend %s, average of the last %d: %.2f C\n"
          (if current >= previous then "rising" else "falling" :: String) (length recent) average)
      _ -> liftIO (putStrLn "  trend: waiting for a second reading")
    rawoutput []

instance ReportHeartbeatLayer m => ReportHeartbeatHandler m where
  reportHeartbeat = do
    number <- require @Int
    liftIO (putStrLn ("[heartbeat] #" ++ show number))
    rawoutput []

-- 记录本编译副本实际使用的手写源码；启动前检查，避免执行过期方法体。
handlerSourceFingerprint :: Maybe String
handlerSourceFingerprint = Just "45a0c043b1b086b1b8a311aff1d715f4"

-- 以下由 gen 生成。每个 effect 一个类型标签：handler 在标签下执行，
-- 读取、rawinput 与错误按标签在编译期解析到这个 effect 的来源，不改写 handler 方法体。
newtype Wrap (effect :: FrameworkTypes.Symbol) value = Wrap { runWrap :: FrameworkGenerated.App value }
  deriving (Functor, Applicative, Monad, FrameworkIO.MonadIO)

instance FrameworkRuntime.Root (Wrap effect) value

instance FrameworkTypes.KnownSymbol effect => FrameworkRuntime.Raises FrameworkGenerated.PrepareSensorError (Wrap effect) where
  raise (FrameworkGenerated.PrepareSensorError description) = Wrap (FrameworkRuntime.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) FrameworkGenerated.PrepareSensorFailure description)

instance FrameworkTypes.KnownSymbol effect => FrameworkRuntime.Raises FrameworkGenerated.ConnectSensorError (Wrap effect) where
  raise (FrameworkGenerated.ConnectSensorError description) = Wrap (FrameworkRuntime.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) FrameworkGenerated.ConnectSensorFailure description)

instance FrameworkTypes.KnownSymbol effect => FrameworkRuntime.Raises FrameworkGenerated.DisconnectSensorError (Wrap effect) where
  raise (FrameworkGenerated.DisconnectSensorError description) = Wrap (FrameworkRuntime.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) FrameworkGenerated.DisconnectSensorFailure description)

instance FrameworkTypes.KnownSymbol effect => FrameworkRuntime.Raises FrameworkGenerated.NextReadingError (Wrap effect) where
  raise (FrameworkGenerated.NextReadingError description) = Wrap (FrameworkRuntime.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) FrameworkGenerated.NextReadingFailure description)

instance FrameworkTypes.KnownSymbol effect => FrameworkRuntime.Raises FrameworkGenerated.ParseTemperatureError (Wrap effect) where
  raise (FrameworkGenerated.ParseTemperatureError description) = Wrap (FrameworkRuntime.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) FrameworkGenerated.ParseTemperatureFailure description)

instance FrameworkTypes.KnownSymbol effect => FrameworkRuntime.Raises FrameworkGenerated.NextBeatError (Wrap effect) where
  raise (FrameworkGenerated.NextBeatError description) = Wrap (FrameworkRuntime.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) FrameworkGenerated.NextBeatFailure description)

instance FrameworkTypes.KnownSymbol effect => FrameworkRuntime.Raises FrameworkGenerated.ParseBeatError (Wrap effect) where
  raise (FrameworkGenerated.ParseBeatError description) = Wrap (FrameworkRuntime.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) FrameworkGenerated.ParseBeatFailure description)

instance FrameworkTypes.KnownSymbol effect => FrameworkRuntime.Raises FrameworkGenerated.AnnounceError (Wrap effect) where
  raise (FrameworkGenerated.AnnounceError description) = Wrap (FrameworkRuntime.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) FrameworkGenerated.AnnounceFailure description)

instance FrameworkTypes.KnownSymbol effect => FrameworkRuntime.Raises FrameworkGenerated.ShowTemperatureError (Wrap effect) where
  raise (FrameworkGenerated.ShowTemperatureError description) = Wrap (FrameworkRuntime.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) FrameworkGenerated.ShowTemperatureFailure description)

instance FrameworkTypes.KnownSymbol effect => FrameworkRuntime.Raises FrameworkGenerated.CheckTrendError (Wrap effect) where
  raise (FrameworkGenerated.CheckTrendError description) = Wrap (FrameworkRuntime.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) FrameworkGenerated.CheckTrendFailure description)

instance FrameworkTypes.KnownSymbol effect => FrameworkRuntime.Raises FrameworkGenerated.ReportHeartbeatError (Wrap effect) where
  raise (FrameworkGenerated.ReportHeartbeatError description) = Wrap (FrameworkRuntime.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) FrameworkGenerated.ReportHeartbeatFailure description)

instance FrameworkRuntime.Reads (SensorMemory) (Wrap "SensorLink") where
  require = Wrap ((\(FrameworkGenerated.SensorState value) -> value) <$> readSensorState)

instance FrameworkRuntime.Reads (SensorMemory) (Wrap "TemperatureParser") where
  require = Wrap ((\(FrameworkGenerated.SensorState value) -> value) <$> readSensorState)

instance FrameworkRuntime.Reads (SensorMemory) (Wrap "Heartbeat") where
  require = Wrap ((\(FrameworkGenerated.SensorState value) -> value) <$> readSensorState)

instance FrameworkRuntime.Reads (Temperature) (Wrap "ShowTemperature") where
  require = Wrap ((\(FrameworkGenerated.TemperatureSample value) -> value) <$> streamTemperatureSample)

instance FrameworkRuntime.Reads (Temperature) (Wrap "CheckTrend") where
  require = Wrap ((\(FrameworkGenerated.TemperatureSample value) -> value) <$> streamTemperatureSample)

instance FrameworkRuntime.Reads (Int) (Wrap "ReportHeartbeat") where
  require = Wrap ((\(FrameworkGenerated.Beat value) -> value) <$> streamBeat)

instance FrameworkRuntime.Raw (Wrap "TemperatureParser") where
  rawinput = Wrap ((: []) <$> nextTemperatureFeed)

instance FrameworkRuntime.Raw (Wrap "Heartbeat") where
  rawinput = Wrap ((: []) <$> nextHeartbeatClock)

instance FrameworkRuntime.StreamEnds (Wrap "TemperatureFeed") where
  streamEnd = Wrap FrameworkRuntime.endSource

instance FrameworkRuntime.StreamEnds (Wrap "HeartbeatClock") where
  streamEnd = Wrap FrameworkRuntime.endSource

instance FrameworkRuntime.EndsStream (Wrap "ShowTemperature") where
  endStream = Wrap FrameworkRuntime.endSubscription

instance FrameworkRuntime.EndsStream (Wrap "CheckTrend") where
  endStream = Wrap FrameworkRuntime.endSubscription

instance FrameworkRuntime.EndsStream (Wrap "ReportHeartbeat") where
  endStream = Wrap FrameworkRuntime.endSubscription

getSensorState :: FrameworkGenerated.App FrameworkGenerated.SensorState
getSensorState = (FrameworkRuntime.withErrorPath [] . FrameworkRuntime.handleFailure . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.callContext "SensorResource"
    (\value bindings -> bindings { FrameworkGenerated.boundSensorResource = Just value })) $
  (FrameworkGenerated.SensorState <$> runWrap @"SensorResource" (FrameworkRuntime.super "prepareSensor" FrameworkGenerated.prepareSensor))

readSensorState :: FrameworkGenerated.App FrameworkGenerated.SensorState
readSensorState = (FrameworkRuntime.withErrorPath [] . FrameworkRuntime.handleFailure) $
  FrameworkRuntime.readContext "SensorResource" FrameworkGenerated.ContextBindingError FrameworkGenerated.boundSensorResource

openSensorLink :: FrameworkGenerated.App [String]
openSensorLink = (FrameworkRuntime.withErrorPath ["SensorLink"] . FrameworkRuntime.handleFailure . FrameworkRuntime.atomicScope "openSensorLink" [] [] . FrameworkRuntime.openScope "SensorLink" FrameworkGenerated.ScopeBindingError (Just (() <$ closeSensorLink)) . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.enterHandler "SensorLink") $
  getSensorState >> runWrap @"SensorLink" (FrameworkRuntime.super "connectSensor" FrameworkGenerated.connectSensor)

closeSensorLink :: FrameworkGenerated.App [String]
closeSensorLink = (FrameworkRuntime.withErrorPath ["SensorLink"] . FrameworkRuntime.handleFailure . FrameworkRuntime.atomicScope "closeSensorLink" [] [] . FrameworkRuntime.closeScope "SensorLink" FrameworkGenerated.ScopeBindingError . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.enterHandler "SensorLink") $
  runWrap @"SensorLink" (FrameworkRuntime.superClose "disconnectSensor" FrameworkGenerated.disconnectSensor)

nextTemperatureFeed :: FrameworkGenerated.App String
nextTemperatureFeed = (FrameworkRuntime.withErrorPath ["SensorLink"] . FrameworkRuntime.handleFailure . FrameworkRuntime.streamHandle . FrameworkRuntime.withScopeDependencies ["SensorLink"] . FrameworkRuntime.enterHandler "TemperatureFeed") $
  openSensorLink >> runWrap @"TemperatureFeed" (FrameworkRuntime.super "nextReading" FrameworkGenerated.nextReading)

getTemperatureSample :: FrameworkGenerated.App FrameworkGenerated.TemperatureSample
getTemperatureSample = (FrameworkRuntime.withErrorPath ["SensorLink"] . FrameworkRuntime.handleFailure . FrameworkRuntime.withScopeDependencies ["SensorLink"] . FrameworkRuntime.callContext "TemperatureParser"
    (\value bindings -> bindings { FrameworkGenerated.boundTemperatureParser = Just value })) $
  (FrameworkGenerated.TemperatureSample <$> runWrap @"TemperatureParser" (FrameworkRuntime.super "parseTemperature" FrameworkGenerated.parseTemperature))

streamTemperatureSample :: FrameworkGenerated.App FrameworkGenerated.TemperatureSample
streamTemperatureSample = (FrameworkRuntime.withErrorPath ["SensorLink"] . FrameworkRuntime.handleFailure) $
  FrameworkRuntime.readStreamContext "TemperatureParser" FrameworkGenerated.ContextBindingError FrameworkGenerated.boundTemperatureParser

nextHeartbeatClock :: FrameworkGenerated.App String
nextHeartbeatClock = (FrameworkRuntime.withErrorPath ["SensorLink"] . FrameworkRuntime.handleFailure . FrameworkRuntime.streamHandle . FrameworkRuntime.withScopeDependencies ["SensorLink"] . FrameworkRuntime.enterHandler "HeartbeatClock") $
  openSensorLink >> runWrap @"HeartbeatClock" (FrameworkRuntime.super "nextBeat" FrameworkGenerated.nextBeat)

getBeat :: FrameworkGenerated.App FrameworkGenerated.Beat
getBeat = (FrameworkRuntime.withErrorPath ["SensorLink"] . FrameworkRuntime.handleFailure . FrameworkRuntime.withScopeDependencies ["SensorLink"] . FrameworkRuntime.callContext "Heartbeat"
    (\value bindings -> bindings { FrameworkGenerated.boundHeartbeat = Just value })) $
  (FrameworkGenerated.Beat <$> runWrap @"Heartbeat" (FrameworkRuntime.super "parseBeat" FrameworkGenerated.parseBeat))

streamBeat :: FrameworkGenerated.App FrameworkGenerated.Beat
streamBeat = (FrameworkRuntime.withErrorPath ["SensorLink"] . FrameworkRuntime.handleFailure) $
  FrameworkRuntime.readStreamContext "Heartbeat" FrameworkGenerated.ContextBindingError FrameworkGenerated.boundHeartbeat

runAnnounce :: FrameworkGenerated.App [String]
runAnnounce = (FrameworkRuntime.withErrorPath [] . FrameworkRuntime.handleFailure . FrameworkRuntime.atomicHandle "runAnnounce" [] [] . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.enterHandler "Announce") $
  runWrap @"Announce" (FrameworkRuntime.super "announce" FrameworkGenerated.announce)

runShowTemperature :: FrameworkGenerated.App [String]
runShowTemperature = (FrameworkRuntime.withErrorPath [] . FrameworkRuntime.handleFailure . FrameworkRuntime.atomicHandle "runShowTemperature" [] [] . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.enterHandler "ShowTemperature") $
  runWrap @"ShowTemperature" (FrameworkRuntime.super "showTemperature" FrameworkGenerated.showTemperature)

runCheckTrend :: FrameworkGenerated.App [String]
runCheckTrend = (FrameworkRuntime.withErrorPath [] . FrameworkRuntime.handleFailure . FrameworkRuntime.atomicHandle "runCheckTrend" [] [] . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.enterHandler "CheckTrend") $
  runWrap @"CheckTrend" (FrameworkRuntime.super "checkTrend" FrameworkGenerated.checkTrend)

runReportHeartbeat :: FrameworkGenerated.App [String]
runReportHeartbeat = (FrameworkRuntime.withErrorPath [] . FrameworkRuntime.handleFailure . FrameworkRuntime.atomicHandle "runReportHeartbeat" [] [] . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.enterHandler "ReportHeartbeat") $
  runWrap @"ReportHeartbeat" (FrameworkRuntime.super "reportHeartbeat" FrameworkGenerated.reportHeartbeat)

-- SDK 内部：scope 按上游到下游登记，退出时逆序收尾；创建不执行业务方法。
newScopeHandlers :: IO [FrameworkRuntime.ScopeHandler FrameworkGenerated.ContextValues FrameworkGenerated.Errors]
newScopeHandlers = sequence
  [ FrameworkRuntime.newScopeHandler "SensorLink" [] (Just "SensorResource")
  ]

-- Error 回调登记：按 handles 匹配故障的 handler 与协议分类；关联 scope 由 Input 链推导。
errorHandlers :: [(Maybe String, FrameworkRuntime.ErrorHandler FrameworkGenerated.Errors FrameworkGenerated.App)]
errorHandlers =
  [
  ]
