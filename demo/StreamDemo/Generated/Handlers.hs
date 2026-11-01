-- 自动生成的编译副本；请修改上级 Handlers.hs 后重新生成。
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}
-- 原生 Haskell 取值；SDK 生成方法入口包装，运行编译 Generated 副本。
{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE UndecidableInstances #-}

{-# OPTIONS_GHC -Werror=missing-methods #-}

module StreamDemo.Generated.Handlers (handlerSourceFingerprint, newScopeHandlers, scopeCleanups, errorHandlers, contextInjections) where

import qualified Framework.SDK as FrameworkRuntime
import qualified Framework.Effect.Contract as FrameworkRoot
import qualified StreamDemo.Generated.Effects as FrameworkGenerated
import Framework.SDK (Effect(..), historyEntries, latest)
import StreamDemo.Generated.Effects
import StreamDemo.Types
import Control.Concurrent (threadDelay)
import Control.Monad.IO.Class (liftIO)
import GHC.Clock (getMonotonicTime)
import Text.Printf (printf)

-- 连接在第一次读数时打开；生产会话的各步骤共用它，运行退出时由 SDK 关闭。
instance SensorLinkInputs m => SensorLinkEffect m where
  connectSensor =
    (FrameworkRoot.withErrorPath ["SensorLink"] . FrameworkRoot.handler @FrameworkGenerated.Root . FrameworkRuntime.atomicScope "connectSensor" . FrameworkRuntime.openScope "SensorLink" FrameworkGenerated.ScopeBindingError . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.enterHandler "SensorLink") $
      let
        connectSensor :: (m) (Maybe String)
        connectSensor = do
          liftIO (putStrLn "[sensor] connected")
          pure Nothing
      in connectSensor
  disconnectSensor =
    (FrameworkRoot.withErrorPath ["SensorLink"] . FrameworkRoot.handler @FrameworkGenerated.Root . FrameworkRuntime.atomicScope "disconnectSensor" . FrameworkRuntime.closeScope "SensorLink" FrameworkGenerated.ScopeBindingError . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.enterHandler "SensorLink") $
      let
        disconnectSensor :: (m) (Maybe String)
        disconnectSensor = do
          liftIO (putStrLn "[sensor] disconnected")
          pure Nothing
      in disconnectSensor

-- 一次只取一份原始读数；节奏由方法体自己的等待决定，SDK 不加间隔。
instance TemperatureFeedInputs m => TemperatureFeedEffect m where
  nextReading =
    (FrameworkRoot.withErrorPath ["SensorLink"] . FrameworkRoot.handler @FrameworkGenerated.Root . FrameworkRuntime.withScopeDependencies ["SensorLink"] . FrameworkRuntime.enterHandler "TemperatureFeed") $
      let
        nextReading :: (m) (String)
        nextReading = do
          _ <- connectSensor
          liftIO (threadDelay 700000)
          seconds <- liftIO getMonotonicTime
          pure (printf "%.1f" (21 + 3 * sin (seconds / 3) :: Double))
      in nextReading

-- 解析器读取本次原始输入，返回一个资产；发布、历史和交付由 SDK 完成。
instance TemperatureParserInputs m => TemperatureParserEffect m where
  streamTemperatureSample =
    (FrameworkRoot.withErrorPath ["SensorLink"] . FrameworkRoot.handler @FrameworkGenerated.Root . FrameworkRuntime.withScopeDependencies ["SensorLink"] . FrameworkRuntime.callContext "TemperatureParser" FrameworkGenerated.ContextBindingError
      [("ShowTemperature", FrameworkRuntime.RequireValue), ("CheckTrend", FrameworkRuntime.RequireValue)]
      Nothing
      FrameworkGenerated.boundTemperatureParser
      (\value bindings -> bindings { FrameworkGenerated.boundTemperatureParser = Just value })) $
      let
        streamTemperatureSample :: (m) (FrameworkGenerated.TemperatureSample)
        streamTemperatureSample = do
          raw <- inputTemperatureSample
          case reads raw of
            [(value, "")] -> pure (TemperatureSample (Temperature value))
            _ -> raise (TemperatureParserError ("unreadable sensor output: " ++ raw))
      in streamTemperatureSample

-- 请求序列：会话反复执行 request，每次成功即一条新交付。
instance HeartbeatInputs m => HeartbeatEffect m where
  getBeat =
    (FrameworkRoot.withErrorPath [] . FrameworkRoot.handler @FrameworkGenerated.Root . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.callContext "Heartbeat" FrameworkGenerated.ContextBindingError
      [("ReportHeartbeat", FrameworkRuntime.RequireValue)]
      Nothing
      FrameworkGenerated.boundHeartbeat
      (\value bindings -> bindings { FrameworkGenerated.boundHeartbeat = Just value })) $
      let
        getBeat :: (m) (FrameworkGenerated.Beat)
        getBeat = do
          liftIO (threadDelay 2000000)
          seconds <- liftIO getMonotonicTime
          pure (Beat (round seconds))
      in getBeat

instance AnnounceInputs m => AnnounceEffect m where
  announce =
    (FrameworkRoot.withErrorPath [] . FrameworkRoot.handler @FrameworkGenerated.Root . FrameworkRuntime.atomicHandle "announce" . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.enterHandler "Announce") $
      let
        announce :: (m) (Maybe String)
        announce = do
          liftIO (putStrLn "Monitoring the sensor; press Ctrl-C to stop.")
          pure Nothing
      in announce

-- 同一单元的一次执行里，ShowTemperature 与 CheckTrend 读到同一份交付视图。
instance ShowTemperatureInputs m => ShowTemperatureEffect m where
  showTemperature =
    (FrameworkRoot.withErrorPath [] . FrameworkRoot.handler @FrameworkGenerated.Root . FrameworkRuntime.atomicHandle "showTemperature" . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.enterHandler "ShowTemperature") $
      let
        showTemperature :: (m) (Maybe String)
        showTemperature = do
          samples <- require @TemperatureSample
          case latest samples of
            Just (TemperatureSample (Temperature value)) ->
              liftIO (printf "reading #%d: %.1f C\n" (length (historyEntries samples)) value)
            Nothing -> pure ()
          pure Nothing
      in showTemperature

instance CheckTrendInputs m => CheckTrendEffect m where
  checkTrend =
    (FrameworkRoot.withErrorPath [] . FrameworkRoot.handler @FrameworkGenerated.Root . FrameworkRuntime.atomicHandle "checkTrend" . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.enterHandler "CheckTrend") $
      let
        checkTrend :: (m) (Maybe String)
        checkTrend = do
          samples <- require @TemperatureSample
          let values = [value | TemperatureSample (Temperature value) <- historyEntries samples]
              recent = drop (length values - 5) values
              average = sum recent / fromIntegral (length recent)
          case reverse recent of
            current : previous : _ ->
              liftIO (printf "  trend %s, average of the last %d: %.2f C\n"
                (if current >= previous then "rising" else "falling" :: String) (length recent) average)
            _ -> liftIO (putStrLn "  trend: waiting for a second reading")
          pure Nothing
      in checkTrend

instance ReportHeartbeatInputs m => ReportHeartbeatEffect m where
  reportHeartbeat =
    (FrameworkRoot.withErrorPath [] . FrameworkRoot.handler @FrameworkGenerated.Root . FrameworkRuntime.atomicHandle "reportHeartbeat" . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.enterHandler "ReportHeartbeat") $
      let
        reportHeartbeat :: (m) (Maybe String)
        reportHeartbeat = do
          beats <- require @Beat
          liftIO (putStrLn ("[heartbeat] #" ++ show (length (historyEntries beats))))
          pure Nothing
      in reportHeartbeat

-- 记录本编译副本实际使用的手写源码；启动前检查，避免执行过期方法体。
handlerSourceFingerprint :: Maybe String
handlerSourceFingerprint = Just "92e53b8a50806263ef4dfb0ddc2292d1"


-- SDK 内部：scope 按上游到下游登记，退出时逆序收尾；创建不执行业务方法。
newScopeHandlers :: IO [FrameworkRuntime.ScopeHandler FrameworkGenerated.ContextValues FrameworkGenerated.Errors]
newScopeHandlers = sequence
  [ FrameworkRuntime.newScopeHandler "SensorLink" [] (Nothing)
  ]

-- SDK 自动收尾入口；安装时不关闭资源。
scopeCleanups :: [(String, FrameworkGenerated.App ())]
scopeCleanups =
  [ ("SensorLink", () <$ disconnectSensor)
  ]

-- Error 回调登记：按 handles 匹配故障来源与分类；关联 scope 由 Input 链推导。
errorHandlers :: [(Maybe String, FrameworkRoot.ErrorHandler FrameworkGenerated.Errors FrameworkGenerated.App)]
errorHandlers =
  [
  ]

-- 挂在原子句柄下的 Context：句柄的输出交给它解析并发布为资产；没有挂接时输出被丢弃。
contextInjections :: [(String, [(String, FrameworkGenerated.App ())])]
contextInjections =
  [
  ]
