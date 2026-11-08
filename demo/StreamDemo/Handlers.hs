-- handler 是不带参数的类方法；SDK 按注册装配上游、会话与读取来源，运行编译 Generated 副本。
{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE UndecidableInstances #-}

{-# OPTIONS_GHC -Werror=missing-methods #-}

module StreamDemo.Handlers () where

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
    pure Nothing

instance DisconnectSensorLayer m => DisconnectSensorHandler m where
  disconnectSensor = do
    liftIO (putStrLn "[sensor] disconnected")
    pure Nothing

-- 一次只取一份原始读数；节奏由 handler 自己的等待决定，SDK 不加间隔。
instance NextReadingLayer m => NextReadingHandler m where
  nextReading = do
    liftIO (threadDelay 700000)
    seconds <- liftIO getMonotonicTime
    pure (printf "%.1f" (21 + 3 * sin (seconds / 3) :: Double))

-- parser 挂在 Stream 下：raw 是会话本次取得的原始读数（不会再读一次），返回一份资产的表示值；
-- 发布、历史和交付由 SDK 完成。
instance ParseTemperatureLayer m => ParseTemperatureHandler m where
  parseTemperature = do
    reading <- maybe "" id <$> raw
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
    tick <- maybe "" id <$> raw
    case reads tick of
      [(value, "")] -> pure value
      _ -> raise (ParseBeatError ("unreadable clock output: " ++ tick))

instance AnnounceLayer m => AnnounceHandler m where
  announce = do
    liftIO (putStrLn "Monitoring the sensor; press Ctrl-C to stop.")
    pure Nothing

-- 同一单元的一次执行里，ShowTemperature 与 CheckTrend 读到同一份交付视图。
instance ShowTemperatureLayer m => ShowTemperatureHandler m where
  showTemperature = do
    samples <- require @(History Temperature)
    case latest samples of
      Just (Temperature value) ->
        liftIO (printf "reading #%d: %.1f C\n" (length (historyEntries samples)) value)
      Nothing -> pure ()
    pure Nothing

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
    pure Nothing

instance ReportHeartbeatLayer m => ReportHeartbeatHandler m where
  reportHeartbeat = do
    beats <- require @(History Int)
    liftIO (putStrLn ("[heartbeat] #" ++ show (length (historyEntries beats))))
    pure Nothing
