{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeApplications #-}

-- 自动生成；组合好的执行闭包，原型在 Generated/Prototype.hs，执行由 SDK 的 interpreter 完成。
module LinesDemo.Generated.Program (Results(..), compiledProgram, interpreter, generatedPrototype) where

import Framework.Generated (EffectSpec(..), EffectTyping(..), Asset(..), Handles(..), Demand(..), Access(..), TypeRef(..))
import qualified Framework.Generated as SDK
import LinesDemo.Generated.Effects
import LinesDemo.Generated.Prototype (generatedPrototype)
import qualified LinesDemo.Generated.Handlers as Handlers


-- 仅汇总所选末端的成功结果，不保存共享绑定或增加完成包装。
data Results = AnnounceResult () | PrintLineResult () | TextCounterResult () | ShowTotalResult () | ReportResult ()
  deriving Show

-- 末端共享生成的 scope 句柄；只创建空状态。
-- compiledWorkflow：AST 的执行闭包（Serial 顺序、Concurrent 并行、Choose 选择、Drive 是 lifelong 的位置）。
-- compiledReactions：资产每次发布后同步执行的回调（lifelong 的单元与派生步骤）；Nothing 作用范围是 event。
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
          [ SDK.Step [0] (target "Announce" (AnnounceResult () <$ Handlers.runAnnounce @'[]))
          , SDK.Drive [1] (Just (SDK.StreamSource (SDK.Slot 5 "LineParser") ([1,-1,0,0], target "LineFeed" (Handlers.nextLineFeed @'["TraceLine"])) ([1,-1,0,1], target "LineParser" (() <$ Handlers.getTextLine @'["TraceLine"])) Nothing))
          , SDK.Step [2] (target "Report" (ReportResult () <$ Handlers.runReport @'[]))
          ]
    , SDK.compiledReactions = 
        [ SDK.Reaction (SDK.Slot 5 "LineParser") (Just [1]) (SDK.RunUnit [1,0] (SDK.Serial [1,0] 
              [ SDK.Step [1,0,0] (target "PrintLine@TraceLine" (PrintLineResult () <$ Handlers.runPrintLine @'["TraceLine"]))
              , SDK.Step [1,0,1] (target "TextCounter@TraceLine" (TextCounterResult () <$ Handlers.runTextCounter @'["TraceLine"]))
              ]))
        , SDK.Reaction (SDK.Slot 8 "CountParser") (Just [1]) (SDK.RunUnit [1,1] (SDK.Step [1,1] (target "ShowTotal@TraceLine" (ShowTotalResult () <$ Handlers.runShowTotal @'["TraceLine"]))))
        , SDK.Reaction (SDK.Slot 5 "LineParser") (Just [-2,0]) (SDK.RunDerive [-2,1,0] (target "CountParser" (() <$ Handlers.getRunningTotal @'[])))
        ]
    , SDK.compiledStatic = 
        [ ((SDK.Slot 5 "LineParser"), [-2,0], SDK.StreamSource (SDK.Slot 5 "LineParser") ([-2,0,0], target "LineFeed" (Handlers.nextLineFeed @'[])) ([-2,0,1], target "LineParser" (() <$ Handlers.getTextLine @'[])) Nothing)
        , ((SDK.Slot 8 "CountParser"), [-2,0], SDK.StreamSource (SDK.Slot 5 "LineParser") ([-2,0,0], target "LineFeed" (Handlers.nextLineFeed @'[])) ([-2,0,1], target "LineParser" (() <$ Handlers.getTextLine @'[])) Nothing)
        ]
    }

-- SDK 装配入口，不需要用户提供节点执行器或重复选择 handler。
interpreter :: SDK.AST -> [EffectSpec] -> IO ()
interpreter = SDK.interpreter "LinesDemo" [("demo/LinesDemo/Handlers.hs", Handlers.handlerSourceFingerprint), ("demo/LinesDemo/AST.hs",Just "53c23cfba246800347ec4ef6dad0f7f2"), ("demo/LinesDemo/Hanging.hs",Just "2d3a4e4f9d49fba66e4c6b11f7e10a76")] generatedPrototype compiledProgram
