-- 自动生成的编译副本；请修改上级 Handlers.hs 后重新生成。
{-# LANGUAGE AllowAmbiguousTypes #-}
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
newtype Wrap (effect :: FrameworkTypes.Symbol) (method :: FrameworkTypes.Symbol) value = Wrap { runWrap :: Effects.App value }
  deriving (Functor, Applicative, Monad, FrameworkIO.MonadIO)

-- 类型标签上的名字：effect 名与方法名只写在标签上，需要字符串时从这里取。
nameOf :: forall name. FrameworkTypes.KnownSymbol name => String
nameOf = FrameworkTypes.symbolVal (FrameworkProxy.Proxy @name)

-- 在标签下执行 handler，交给 Root 的 superhandler；方法名取自标签。close 的调用点用 callClose。
call :: forall effect method value. (FrameworkTypes.KnownSymbol method)
  => Wrap effect method value -> Effects.App value
call handler = runWrap (SDK.super (nameOf @method) handler)

callClose :: forall effect method value. (FrameworkTypes.KnownSymbol method)
  => Wrap effect method value -> Effects.App value
callClose handler = runWrap (SDK.superClose (nameOf @method) handler)

instance SDK.Root (Wrap effect method) value

instance (SDK.HandlerError problem Effects.Errors, FrameworkTypes.KnownSymbol effect)
    => SDK.Raises problem (Wrap effect method) where
  raise problem = Wrap (SDK.failEffect (nameOf @effect) failure description)
    where (failure, description) = SDK.raised problem

instance SDK.Reads SensorMemory (Wrap "SensorLink" method) where
  require = Wrap (SDK.coerce <$> readSensorState)

instance SDK.Reads SensorMemory (Wrap "TemperatureParser" method) where
  require = Wrap (SDK.coerce <$> readSensorState)

instance SDK.Reads SensorMemory (Wrap "Heartbeat" method) where
  require = Wrap (SDK.coerce <$> readSensorState)

instance SDK.Reads Temperature (Wrap "ShowTemperature" method) where
  require = Wrap (SDK.coerce <$> streamTemperatureSample)

instance SDK.Reads Temperature (Wrap "CheckTrend" method) where
  require = Wrap (SDK.coerce <$> streamTemperatureSample)

instance SDK.Reads Int (Wrap "ReportHeartbeat" method) where
  require = Wrap (SDK.coerce <$> streamBeat)

instance SDK.Raw (Wrap "TemperatureParser" "parseTemperature") where
  rawinput = Wrap SDK.emittedInput

instance SDK.Raw (Wrap "Heartbeat" "parseBeat") where
  rawinput = Wrap SDK.emittedInput

instance SDK.RawOutputs (Wrap effect method)

instance SDK.Emits (Wrap effect method) where
  rawemit text = Wrap (SDK.emitToParser text)

instance SDK.StreamEnds (Wrap effect method) where
  streamEnd = Wrap SDK.endSource

instance SDK.EndsStream (Wrap effect method) where
  endStream = Wrap SDK.endSubscription

getSensorState :: Effects.App Effects.SensorState
getSensorState =
  SDK.handleFailure
  . SDK.callContext "SensorResource"
      (\value bindings -> bindings { Effects.boundSensorResource = Just value }) $
    Effects.SensorState <$> call @"SensorResource" @"prepareSensor" Effects.prepareSensor

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
    getSensorState >> call @"SensorLink" @"connectSensor" Effects.connectSensor

closeSensorLink :: Effects.App [String]
closeSensorLink =
  SDK.withErrorPath ["SensorLink"]
  . SDK.handleFailure
  . SDK.atomicScope "closeSensorLink" [] []
  . SDK.closeScope "SensorLink" Effects.ScopeBindingError
  . SDK.enterHandler "SensorLink" $
    callClose @"SensorLink" @"disconnectSensor" Effects.disconnectSensor

nextTemperatureFeed :: Effects.App ()
nextTemperatureFeed =
  SDK.withErrorPath ["SensorLink"]
  . SDK.handleFailure
  . SDK.withScopeDependencies ["SensorLink"]
  . SDK.enterHandler "TemperatureFeed" $
    openSensorLink >> call @"TemperatureFeed" @"nextReading" Effects.nextReading

getTemperatureSample :: Effects.App Effects.TemperatureSample
getTemperatureSample =
  SDK.withErrorPath ["SensorLink"]
  . SDK.handleFailure
  . SDK.withScopeDependencies ["SensorLink"]
  . SDK.callContext "TemperatureParser"
      (\value bindings -> bindings { Effects.boundTemperatureParser = Just value }) $
    Effects.TemperatureSample <$> call @"TemperatureParser" @"parseTemperature" Effects.parseTemperature

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
    openSensorLink >> call @"HeartbeatClock" @"nextBeat" Effects.nextBeat

getBeat :: Effects.App Effects.Beat
getBeat =
  SDK.withErrorPath ["SensorLink"]
  . SDK.handleFailure
  . SDK.withScopeDependencies ["SensorLink"]
  . SDK.callContext "Heartbeat"
      (\value bindings -> bindings { Effects.boundHeartbeat = Just value }) $
    Effects.Beat <$> call @"Heartbeat" @"parseBeat" Effects.parseBeat

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
    call @"Announce" @"announce" Effects.announce

runShowTemperature :: Effects.App [String]
runShowTemperature =
  SDK.handleFailure
  . SDK.atomicHandle "runShowTemperature" [] []
  . SDK.enterHandler "ShowTemperature" $
    call @"ShowTemperature" @"showTemperature" Effects.showTemperature

runCheckTrend :: Effects.App [String]
runCheckTrend =
  SDK.handleFailure
  . SDK.atomicHandle "runCheckTrend" [] []
  . SDK.enterHandler "CheckTrend" $
    call @"CheckTrend" @"checkTrend" Effects.checkTrend

runReportHeartbeat :: Effects.App [String]
runReportHeartbeat =
  SDK.handleFailure
  . SDK.atomicHandle "runReportHeartbeat" [] []
  . SDK.enterHandler "ReportHeartbeat" $
    call @"ReportHeartbeat" @"reportHeartbeat" Effects.reportHeartbeat

-- SDK 内部：scope 按上游到下游登记，退出时逆序收尾；创建不执行业务方法。
newScopeHandlers :: IO [SDK.ScopeHandler Effects.ContextValues Effects.Errors]
newScopeHandlers = sequence
  [ SDK.newScopeHandler "SensorLink" [] (Just "SensorResource")
  ]

-- Error 回调登记：按 handles 匹配故障的 handler 与协议分类；关联 scope 由 Input 链推导。
errorHandlers :: [(Maybe String, SDK.ErrorHandler Effects.Errors Effects.App)]
errorHandlers = []
