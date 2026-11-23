{-# LANGUAGE DuplicateRecordFields #-}

-- 自动生成；组合好的执行闭包，原型在 Generated/Prototype.hs，执行由 SDK 的 interpreter 完成。
module FacadeProbe.Generated.Program (Results(..), compiledProgram, interpreter, generatedPrototype) where

import Framework.Generated (EffectSpec(..), EffectTyping(..), Asset(..), Handles(..), Demand(..), Access(..), TypeRef(..))
import qualified Framework.Generated as SDK
import FacadeProbe.Generated.Effects
import FacadeProbe.Generated.Prototype (generatedPrototype)
import qualified FacadeProbe.Generated.Handlers as Handlers


-- 仅汇总所选末端的成功结果，不保存共享绑定或增加完成包装。
data Results = WriteReportResult () | WriteReplyResult () | ShowReportResult () | ShowReplyResult () | OnBlankResult () | OnFilledResult () | ShowAResult () | ShowBResult () | ReplyScopeResult ()
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
          [ SDK.Concurrent [0] 
          [ ([(SDK.Slot 0 "ReportLocation"), (SDK.Slot 4 "ReportFile"), (SDK.Slot 2 "ReportDraft")], SDK.Step [0,0] (target "WriteReport" (WriteReportResult () <$ Handlers.runWriteReport)))
          , ([(SDK.Slot 1 "ReplyLocation"), (SDK.Slot 5 "ReplyFile"), (SDK.Slot 3 "ReplyDraft")], SDK.Step [0,1] (target "WriteReply" (WriteReplyResult () <$ Handlers.runWriteReply)))
          ]
          , SDK.Step [1] (target "ShowReport" (ShowReportResult () <$ Handlers.runShowReport))
          , SDK.Step [2] (target "ShowReply" (ShowReplyResult () <$ Handlers.runShowReply))
          , SDK.Choose [3] [3,-1] (target "InspectReport" (SDK.chooseCase "runInspectReport" ContextBindingError (Handlers.runInspectReport) [((SDK.Slot 18 "ReportBlank"), () <$ Handlers.getReportEmpty), ((SDK.Slot 19 "ReportFilled"), () <$ Handlers.getReportText)])) 
          [ ("ReportBlank", [3,0], SDK.Step [3,0] (target "OnBlank" (OnBlankResult () <$ Handlers.runOnBlank)))
          , ("ReportFilled", [3,1], SDK.Step [3,1] (target "OnFilled" (OnFilledResult () <$ Handlers.runOnFilled)))
          ]
          , SDK.Concurrent [4] 
          [ ([(SDK.Slot 24 "ParserA")], SDK.Drive [4,0] (Just (SDK.StreamSource (SDK.Slot 24 "ParserA") ([4,0,-1,0,0], target "FeedA" (Handlers.nextFeedA)) ([4,0,-1,0,1], target "ParserA" (() <$ Handlers.getLevelA)) Nothing)))
          , ([(SDK.Slot 25 "ParserB")], SDK.Drive [4,1] (Just (SDK.StreamSource (SDK.Slot 25 "ParserB") ([4,1,-1,0,0], target "FeedB" (Handlers.nextFeedB)) ([4,1,-1,0,1], target "ParserB" (() <$ Handlers.getLevelB)) Nothing)))
          ]
          , SDK.Step [5] (target "ReplyScope" (ReplyScopeResult () <$ Handlers.openReplyScope))
          ]
    , SDK.compiledReactions = 
        [ SDK.Reaction (SDK.Slot 24 "ParserA") (Just [4,0]) (SDK.RunUnit [4,0,0] (SDK.Step [4,0,0] (target "ShowA" (ShowAResult () <$ Handlers.runShowA))))
        , SDK.Reaction (SDK.Slot 25 "ParserB") (Just [4,1]) (SDK.RunUnit [4,1,0] (SDK.Step [4,1,0] (target "ShowB" (ShowBResult () <$ Handlers.runShowB))))
        ]
    , SDK.compiledStatic = 
        [ ((SDK.Slot 24 "ParserA"), [-2,0], SDK.StreamSource (SDK.Slot 24 "ParserA") ([-2,0,0], target "FeedA" (Handlers.nextFeedA)) ([-2,0,1], target "ParserA" (() <$ Handlers.getLevelA)) Nothing)
        , ((SDK.Slot 25 "ParserB"), [-2,1], SDK.StreamSource (SDK.Slot 25 "ParserB") ([-2,1,0], target "FeedB" (Handlers.nextFeedB)) ([-2,1,1], target "ParserB" (() <$ Handlers.getLevelB)) Nothing)
        ]
    }

-- SDK 装配入口，不需要用户提供节点执行器或重复选择 handler。
interpreter :: SDK.AST -> [EffectSpec] -> IO ()
interpreter = SDK.interpreter "FacadeProbe" [("demo/FacadeProbe/Handlers.hs", Handlers.handlerSourceFingerprint), ("demo/FacadeProbe/Hanging.hs",Nothing)] generatedPrototype compiledProgram
