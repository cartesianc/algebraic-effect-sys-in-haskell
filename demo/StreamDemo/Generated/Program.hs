{-# LANGUAGE DuplicateRecordFields #-}

-- 自动生成；组合好的执行闭包，原型在 Generated/Prototype.hs，执行由 SDK 的 interpreter 完成。
module StreamDemo.Generated.Program (Results(..), compiledProgram, interpreter, generatedPrototype) where

import Framework.Generated (EffectSpec(..), EffectTyping(..), Asset(..), Handles(..), Demand(..), Access(..), TypeRef(..))
import qualified Framework.Generated as SDK
import StreamDemo.Generated.Effects
import StreamDemo.Generated.Prototype (generatedPrototype)
import qualified StreamDemo.Generated.Handlers as Handlers


-- 仅汇总所选末端的成功结果，不保存共享绑定或增加完成包装。
data Results = AnnounceResult () | ShowTemperatureResult () | CheckTrendResult () | ReportHeartbeatResult ()
  deriving Show

-- 末端共享生成的 scope 句柄；只创建空状态。
-- compiledWorkflow：AST 的执行闭包（Serial 顺序、Concurrent 并行、Choose 选择、Drive 是 lifelong 的位置）。
-- compiledReactions：资产每次发布后同步执行的回调（lifelong 的单元与派生步骤）；Nothing 作用范围是 event。
-- Untracked 的单元与 scope 回收无关，执行时不建执行帧、不登记保留根与执行身份。
-- compiledStatic：lifelong 之外 requests 持续资产时，同步运行到结束的根来源。
compiledProgram :: IO (SDK.Compiled ContextValues Errors Results)
compiledProgram = do
  scopes <- Handlers.newScopeHandlers
  let target :: Show value => String -> App value -> SDK.Target ContextValues Errors value
      target label action = SDK.targetApp label emptyContexts scopes
        (SDK.withErrorHandlers Handlers.errorHandlers action)
  pure SDK.Compiled
    { SDK.compiledWorkflow =
        SDK.Serial [] 
          [ SDK.Step [0] (target "Announce" (AnnounceResult () <$ Handlers.runAnnounce))
          , SDK.Concurrent [1] 
          [ ([(SDK.Slot 2 "TemperatureParser")], SDK.Drive [1,0] (Just (SDK.StreamSource (SDK.Slot 2 "TemperatureParser") ([1,0,-1,0,0], target "TemperatureFeed" (Handlers.nextTemperatureFeed)) ([1,0,-1,0,1], target "TemperatureParser" (() <$ Handlers.getTemperatureSample)) Nothing)))
          , ([(SDK.Slot 4 "Heartbeat")], SDK.Drive [1,1] (Just (SDK.StreamSource (SDK.Slot 4 "Heartbeat") ([1,1,-1,0,0], target "HeartbeatClock" (Handlers.nextHeartbeatClock)) ([1,1,-1,0,1], target "Heartbeat" (() <$ Handlers.getBeat)) Nothing)))
          ]
          ]
    , SDK.compiledReactions = 
        [ SDK.Reaction (SDK.Slot 2 "TemperatureParser") (Just [1,0]) (SDK.RunUnit [1,0,0] SDK.Tracked (SDK.Serial [1,0,0] 
              [ SDK.Step [1,0,0,0] (target "ShowTemperature" (ShowTemperatureResult () <$ Handlers.runShowTemperature))
              , SDK.Step [1,0,0,1] (target "CheckTrend" (CheckTrendResult () <$ Handlers.runCheckTrend))
              ]))
        , SDK.Reaction (SDK.Slot 4 "Heartbeat") (Just [1,1]) (SDK.RunUnit [1,1,0] SDK.Tracked (SDK.Step [1,1,0] (target "ReportHeartbeat" (ReportHeartbeatResult () <$ Handlers.runReportHeartbeat))))
        ]
    , SDK.compiledStatic = 
        [ ((SDK.Slot 2 "TemperatureParser"), [-2,0], SDK.StreamSource (SDK.Slot 2 "TemperatureParser") ([-2,0,0], target "TemperatureFeed" (Handlers.nextTemperatureFeed)) ([-2,0,1], target "TemperatureParser" (() <$ Handlers.getTemperatureSample)) Nothing)
        , ((SDK.Slot 4 "Heartbeat"), [-2,1], SDK.StreamSource (SDK.Slot 4 "Heartbeat") ([-2,1,0], target "HeartbeatClock" (Handlers.nextHeartbeatClock)) ([-2,1,1], target "Heartbeat" (() <$ Handlers.getBeat)) Nothing)
        ]
    }

-- SDK 装配入口，不需要用户提供节点执行器或重复选择 handler。
interpreter :: SDK.AST -> [EffectSpec] -> IO ()
interpreter = SDK.interpreter "StreamDemo" [("demo/StreamDemo/Handlers.hs", Handlers.handlerSourceFingerprint), ("demo/StreamDemo/Hanging.hs",Nothing)] generatedPrototype compiledProgram
