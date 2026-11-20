-- 自动生成的编译副本；请修改上级 Handlers.hs 后重新生成。
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE ScopedTypeVariables #-}
-- handler 是不带参数的类方法；SDK 按注册装配上游、会话与读取来源，运行编译 Generated 副本。
{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE UndecidableInstances #-}

{-# OPTIONS_GHC -Werror=missing-methods #-}

module StreamDemo.Generated.Handlers (handlerSourceFingerprint, getSensorState, readSensorState, openSensorLink, closeSensorLink, nextTemperatureFeed, getTemperatureSample, streamTemperatureSample, nextHeartbeatClock, getBeat, streamBeat, runAnnounce, runShowTemperature, runCheckTrend, runReportHeartbeat, newScopeHandlers, errorHandlers) where

import qualified Framework.Generated as SDK
import qualified StreamDemo.Generated.Effects as Effects
import qualified Control.Monad.IO.Class as FrameworkIO
import qualified Data.Proxy as FrameworkProxy
import qualified GHC.TypeLits as FrameworkTypes
import Framework.SDK (Emits(rawemit), Raises(..), Raw(..), Reads(..), rawoutput)
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
    rawemit (printf "%.1f" (21 + 3 * sin (seconds / 3) :: Double))

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
    rawemit (show (round seconds :: Int))

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
handlerSourceFingerprint = Just "e9cc1f0242b01e10df6d0e847f699bb9"

-- 以下由 gen 生成。每个 effect 一个类型标签：handler 在标签下执行，
-- 读取、rawinput 与错误按标签在编译期解析到这个 effect 的来源，不改写 handler 方法体。
newtype Wrap (effect :: FrameworkTypes.Symbol) value = Wrap { runWrap :: Effects.App value }
  deriving (Functor, Applicative, Monad, FrameworkIO.MonadIO)

instance SDK.Root (Wrap effect) value

instance FrameworkTypes.KnownSymbol effect => SDK.Raises Effects.PrepareSensorError (Wrap effect) where
  raise (Effects.PrepareSensorError description) = Wrap (SDK.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) Effects.PrepareSensorFailure description)

instance FrameworkTypes.KnownSymbol effect => SDK.Raises Effects.ConnectSensorError (Wrap effect) where
  raise (Effects.ConnectSensorError description) = Wrap (SDK.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) Effects.ConnectSensorFailure description)

instance FrameworkTypes.KnownSymbol effect => SDK.Raises Effects.DisconnectSensorError (Wrap effect) where
  raise (Effects.DisconnectSensorError description) = Wrap (SDK.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) Effects.DisconnectSensorFailure description)

instance FrameworkTypes.KnownSymbol effect => SDK.Raises Effects.NextReadingError (Wrap effect) where
  raise (Effects.NextReadingError description) = Wrap (SDK.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) Effects.NextReadingFailure description)

instance FrameworkTypes.KnownSymbol effect => SDK.Raises Effects.ParseTemperatureError (Wrap effect) where
  raise (Effects.ParseTemperatureError description) = Wrap (SDK.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) Effects.ParseTemperatureFailure description)

instance FrameworkTypes.KnownSymbol effect => SDK.Raises Effects.NextBeatError (Wrap effect) where
  raise (Effects.NextBeatError description) = Wrap (SDK.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) Effects.NextBeatFailure description)

instance FrameworkTypes.KnownSymbol effect => SDK.Raises Effects.ParseBeatError (Wrap effect) where
  raise (Effects.ParseBeatError description) = Wrap (SDK.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) Effects.ParseBeatFailure description)

instance FrameworkTypes.KnownSymbol effect => SDK.Raises Effects.AnnounceError (Wrap effect) where
  raise (Effects.AnnounceError description) = Wrap (SDK.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) Effects.AnnounceFailure description)

instance FrameworkTypes.KnownSymbol effect => SDK.Raises Effects.ShowTemperatureError (Wrap effect) where
  raise (Effects.ShowTemperatureError description) = Wrap (SDK.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) Effects.ShowTemperatureFailure description)

instance FrameworkTypes.KnownSymbol effect => SDK.Raises Effects.CheckTrendError (Wrap effect) where
  raise (Effects.CheckTrendError description) = Wrap (SDK.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) Effects.CheckTrendFailure description)

instance FrameworkTypes.KnownSymbol effect => SDK.Raises Effects.ReportHeartbeatError (Wrap effect) where
  raise (Effects.ReportHeartbeatError description) = Wrap (SDK.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) Effects.ReportHeartbeatFailure description)

instance SDK.Reads SensorMemory (Wrap "SensorLink") where
  require = Wrap (SDK.coerce <$> readSensorState)

instance SDK.Reads SensorMemory (Wrap "TemperatureParser") where
  require = Wrap (SDK.coerce <$> readSensorState)

instance SDK.Reads SensorMemory (Wrap "Heartbeat") where
  require = Wrap (SDK.coerce <$> readSensorState)

instance SDK.Reads Temperature (Wrap "ShowTemperature") where
  require = Wrap (SDK.coerce <$> streamTemperatureSample)

instance SDK.Reads Temperature (Wrap "CheckTrend") where
  require = Wrap (SDK.coerce <$> streamTemperatureSample)

instance SDK.Reads Int (Wrap "ReportHeartbeat") where
  require = Wrap (SDK.coerce <$> streamBeat)

instance SDK.Raw (Wrap "TemperatureParser") where
  rawinput = Wrap SDK.emittedInput

instance SDK.Raw (Wrap "Heartbeat") where
  rawinput = Wrap SDK.emittedInput

instance SDK.RawOutputs (Wrap effect)

instance SDK.Emits (Wrap "TemperatureFeed") where
  rawemit text = Wrap (SDK.emitToParser text)

instance SDK.Emits (Wrap "HeartbeatClock") where
  rawemit text = Wrap (SDK.emitToParser text)

instance SDK.StreamEnds (Wrap "TemperatureFeed") where
  streamEnd = Wrap SDK.endSource

instance SDK.StreamEnds (Wrap "HeartbeatClock") where
  streamEnd = Wrap SDK.endSource

instance SDK.EndsStream (Wrap "ShowTemperature") where
  endStream = Wrap SDK.endSubscription

instance SDK.EndsStream (Wrap "CheckTrend") where
  endStream = Wrap SDK.endSubscription

instance SDK.EndsStream (Wrap "ReportHeartbeat") where
  endStream = Wrap SDK.endSubscription

getSensorState :: Effects.App Effects.SensorState
getSensorState =
  SDK.handleFailure
  . SDK.callContext "SensorResource"
      (\value bindings -> bindings { Effects.boundSensorResource = Just value }) $
    Effects.SensorState <$> runWrap @"SensorResource" (SDK.super "prepareSensor" Effects.prepareSensor)

readSensorState :: Effects.App Effects.SensorState
readSensorState =
  SDK.handleFailure $
    SDK.readContext "SensorResource" Effects.ContextBindingError Effects.boundSensorResource

openSensorLink :: Effects.App [String]
openSensorLink =
  SDK.withErrorPath ["SensorLink"]
  . SDK.handleFailure
  . SDK.atomicScope "openSensorLink" [] []
  . SDK.openScope "SensorLink" Effects.ScopeBindingError (Just (() <$ closeSensorLink))
  . SDK.enterHandler "SensorLink" $
    getSensorState >> runWrap @"SensorLink" (SDK.super "connectSensor" Effects.connectSensor)

closeSensorLink :: Effects.App [String]
closeSensorLink =
  SDK.withErrorPath ["SensorLink"]
  . SDK.handleFailure
  . SDK.atomicScope "closeSensorLink" [] []
  . SDK.closeScope "SensorLink" Effects.ScopeBindingError
  . SDK.enterHandler "SensorLink" $
    runWrap @"SensorLink" (SDK.superClose "disconnectSensor" Effects.disconnectSensor)

nextTemperatureFeed :: Effects.App ()
nextTemperatureFeed =
  SDK.withErrorPath ["SensorLink"]
  . SDK.handleFailure
  . SDK.withScopeDependencies ["SensorLink"]
  . SDK.enterHandler "TemperatureFeed" $
    openSensorLink >> runWrap @"TemperatureFeed" (SDK.super "nextReading" Effects.nextReading)

getTemperatureSample :: Effects.App Effects.TemperatureSample
getTemperatureSample =
  SDK.withErrorPath ["SensorLink"]
  . SDK.handleFailure
  . SDK.withScopeDependencies ["SensorLink"]
  . SDK.callContext "TemperatureParser"
      (\value bindings -> bindings { Effects.boundTemperatureParser = Just value }) $
    Effects.TemperatureSample <$> runWrap @"TemperatureParser" (SDK.super "parseTemperature" Effects.parseTemperature)

streamTemperatureSample :: Effects.App Effects.TemperatureSample
streamTemperatureSample =
  SDK.withErrorPath ["SensorLink"]
  . SDK.handleFailure $
    SDK.readStreamContext "TemperatureParser" Effects.ContextBindingError Effects.boundTemperatureParser

nextHeartbeatClock :: Effects.App ()
nextHeartbeatClock =
  SDK.withErrorPath ["SensorLink"]
  . SDK.handleFailure
  . SDK.withScopeDependencies ["SensorLink"]
  . SDK.enterHandler "HeartbeatClock" $
    openSensorLink >> runWrap @"HeartbeatClock" (SDK.super "nextBeat" Effects.nextBeat)

getBeat :: Effects.App Effects.Beat
getBeat =
  SDK.withErrorPath ["SensorLink"]
  . SDK.handleFailure
  . SDK.withScopeDependencies ["SensorLink"]
  . SDK.callContext "Heartbeat"
      (\value bindings -> bindings { Effects.boundHeartbeat = Just value }) $
    Effects.Beat <$> runWrap @"Heartbeat" (SDK.super "parseBeat" Effects.parseBeat)

streamBeat :: Effects.App Effects.Beat
streamBeat =
  SDK.withErrorPath ["SensorLink"]
  . SDK.handleFailure $
    SDK.readStreamContext "Heartbeat" Effects.ContextBindingError Effects.boundHeartbeat

runAnnounce :: Effects.App [String]
runAnnounce =
  SDK.handleFailure
  . SDK.atomicHandle "runAnnounce" [] []
  . SDK.enterHandler "Announce" $
    runWrap @"Announce" (SDK.super "announce" Effects.announce)

runShowTemperature :: Effects.App [String]
runShowTemperature =
  SDK.handleFailure
  . SDK.atomicHandle "runShowTemperature" [] []
  . SDK.enterHandler "ShowTemperature" $
    runWrap @"ShowTemperature" (SDK.super "showTemperature" Effects.showTemperature)

runCheckTrend :: Effects.App [String]
runCheckTrend =
  SDK.handleFailure
  . SDK.atomicHandle "runCheckTrend" [] []
  . SDK.enterHandler "CheckTrend" $
    runWrap @"CheckTrend" (SDK.super "checkTrend" Effects.checkTrend)

runReportHeartbeat :: Effects.App [String]
runReportHeartbeat =
  SDK.handleFailure
  . SDK.atomicHandle "runReportHeartbeat" [] []
  . SDK.enterHandler "ReportHeartbeat" $
    runWrap @"ReportHeartbeat" (SDK.super "reportHeartbeat" Effects.reportHeartbeat)

-- SDK 内部：scope 按上游到下游登记，退出时逆序收尾；创建不执行业务方法。
newScopeHandlers :: IO [SDK.ScopeHandler Effects.ContextValues Effects.Errors]
newScopeHandlers = sequence
  [ SDK.newScopeHandler "SensorLink" [] (Just "SensorResource")
  ]

-- Error 回调登记：按 handles 匹配故障的 handler 与协议分类；关联 scope 由 Input 链推导。
errorHandlers :: [(Maybe String, SDK.ErrorHandler Effects.Errors Effects.App)]
errorHandlers = []
