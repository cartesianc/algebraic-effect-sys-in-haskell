-- 原生 Haskell 取值；SDK 生成方法入口包装，运行编译 Generated 副本。
{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE UndecidableInstances #-}

{-# OPTIONS_GHC -Werror=missing-methods #-}

module StreamDemo.Handlers () where

import Framework.SDK (Effect(..), historyEntries, latest)
import StreamDemo.Generated.Effects
import StreamDemo.Types
import Control.Concurrent (threadDelay)
import Control.Monad.IO.Class (liftIO)
import GHC.Clock (getMonotonicTime)
import Text.Printf (printf)

-- 连接在第一次读数时打开；生产会话的各步骤共用它，运行退出时由 SDK 关闭。
instance SensorLinkInputs m => SensorLinkEffect m where
  connectSensor = do
    liftIO (putStrLn "[sensor] connected")
    pure Nothing
  disconnectSensor = do
    liftIO (putStrLn "[sensor] disconnected")
    pure Nothing

-- 一次只取一份原始读数；节奏由方法体自己的等待决定，SDK 不加间隔。
instance TemperatureFeedInputs m => TemperatureFeedEffect m where
  nextReading = do
    _ <- connectSensor
    liftIO (threadDelay 700000)
    seconds <- liftIO getMonotonicTime
    pure (printf "%.1f" (21 + 3 * sin (seconds / 3) :: Double))

-- 解析器挂在 Stream 下：调用 nextReading 得到会话本次取得的原始读数（不会再读一次），返回一个资产；
-- 发布、历史和交付由 SDK 完成。
instance TemperatureParserInputs m => TemperatureParserEffect m where
  getTemperatureSample = do
    raw <- nextReading
    case reads raw of
      [(value, "")] -> pure (TemperatureSample (Temperature value))
      _ -> raise (TemperatureParserError ("unreadable sensor output: " ++ raw))

-- 请求序列：会话反复执行 request，每次成功即一条新交付。
instance HeartbeatInputs m => HeartbeatEffect m where
  getBeat = do
    liftIO (threadDelay 2000000)
    seconds <- liftIO getMonotonicTime
    pure (Beat (round seconds))

instance AnnounceInputs m => AnnounceEffect m where
  announce = do
    liftIO (putStrLn "Monitoring the sensor; press Ctrl-C to stop.")
    pure Nothing

-- 同一单元的一次执行里，ShowTemperature 与 CheckTrend 读到同一份交付视图。
instance ShowTemperatureInputs m => ShowTemperatureEffect m where
  showTemperature = do
    samples <- require @TemperatureSample
    case latest samples of
      Just (TemperatureSample (Temperature value)) ->
        liftIO (printf "reading #%d: %.1f C\n" (length (historyEntries samples)) value)
      Nothing -> pure ()
    pure Nothing

instance CheckTrendInputs m => CheckTrendEffect m where
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

instance ReportHeartbeatInputs m => ReportHeartbeatEffect m where
  reportHeartbeat = do
    beats <- require @Beat
    liftIO (putStrLn ("[heartbeat] #" ++ show (length (historyEntries beats))))
    pure Nothing
