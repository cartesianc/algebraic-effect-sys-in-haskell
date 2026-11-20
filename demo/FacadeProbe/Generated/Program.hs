{-# LANGUAGE DuplicateRecordFields #-}

-- 自动生成；只登记末端入口，原型在 Generated/Prototype.hs，执行由 SDK 的 interpreter 完成。
module FacadeProbe.Generated.Program (Results(..), compiledEntries, interpreter, generatedPrototype) where

import Framework.Generated (EffectSpec(..), EffectTyping(..), Asset(..), Handles(..), Demand(..), Access(..), TypeRef(..))
import qualified Framework.Generated as SDK
import FacadeProbe.Generated.Effects
import FacadeProbe.Generated.Prototype (generatedPrototype)
import qualified FacadeProbe.Generated.Handlers as Handlers


-- 仅汇总所选末端的成功结果，不保存共享绑定或增加完成包装。
data Results = WriteReportResult () | WriteReplyResult () | ReadReportResult () | ReadReplyResult () | ShowReportResult () | ShowReplyResult () | OnBlankResult () | OnFilledResult () | ShowAResult () | ShowBResult ()
  deriving Show

-- 末端共享生成的 scope 句柄；只创建空状态，Node algebra 才 lower。
-- 第二个列表是各 alternative 的选择末端：执行共同的 Excu，返回第一个判定成功的 Context 名。
-- 第三个列表是各持续资产的生产步骤：会话按需启动，Receive 在每次 rawemit 时调用 parser，Derive 每领取一条上游交付调用一次。
compiledEntries :: IO ([SDK.Target ContextValues Errors Results], [SDK.Target ContextValues Errors String]
                     , [(String, SDK.SessionSteps ContextValues Errors)])
compiledEntries = do
  scopes <- Handlers.newScopeHandlers
  let target :: Show value => String -> App value -> SDK.Target ContextValues Errors value
      target label action = SDK.targetApp label emptyContexts scopes
        (SDK.withErrorHandlers Handlers.errorHandlers action)
  pure
    ( [ target "WriteReport" (WriteReportResult () <$ Handlers.runWriteReport)
      , target "WriteReply" (WriteReplyResult () <$ Handlers.runWriteReply)
      , target "ReadReport" (ReadReportResult () <$ Handlers.runReadReport)
      , target "ReadReply" (ReadReplyResult () <$ Handlers.runReadReply)
      , target "ShowReport" (ShowReportResult () <$ Handlers.runShowReport)
      , target "ShowReply" (ShowReplyResult () <$ Handlers.runShowReply)
      , target "OnBlank" (OnBlankResult () <$ Handlers.runOnBlank)
      , target "OnFilled" (OnFilledResult () <$ Handlers.runOnFilled)
      , target "ShowA" (ShowAResult () <$ Handlers.runShowA)
      , target "ShowB" (ShowBResult () <$ Handlers.runShowB)
      ]
    , [ target "InspectReport" (SDK.chooseCase "runInspectReport" ContextBindingError (Handlers.runInspectReport) [("ReportBlank", () <$ Handlers.getReportEmpty), ("ReportFilled", () <$ Handlers.getReportText)])
      ]
    , [ ("ParserA", SDK.receiveSteps (target "FeedA" (Handlers.nextFeedA)) (target "ParserA" (() <$ Handlers.getLevelA)))
      , ("ParserB", SDK.receiveSteps (target "FeedB" (Handlers.nextFeedB)) (target "ParserB" (() <$ Handlers.getLevelB)))
      ]
    )

-- SDK 装配入口，不需要用户提供节点执行器或重复选择 handler。
interpreter :: SDK.AST -> [EffectSpec] -> IO ()
interpreter = SDK.interpreter "FacadeProbe" [("demo/FacadeProbe/Handlers.hs", Handlers.handlerSourceFingerprint), ("demo/FacadeProbe/Hanging.hs",Nothing)] generatedPrototype compiledEntries
