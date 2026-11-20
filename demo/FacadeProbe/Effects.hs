{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE TypeApplications #-}

-- 原子 handler 复用：effect 是业务配置，同一个 handler 注册到不同的 effect，
-- 读哪份资产由各自的 demands 决定，前驱由各自的 input 决定。
module FacadeProbe.Effects (effects) where

import Framework.SDK (EffectSpec(..), EffectTyping(..), Asset(..), requests, requires, streams)
import FacadeProbe.Types

effects :: [EffectSpec]
effects =
  [ context "ReportLocation" (Asset @String "ReportPath") "reportLocation" "Root" []
  , context "ReplyLocation" (Asset @String "ReplyPath") "replyLocation" "Root" []
  , context "ReportDraft" (Asset @Body "ReportBody") "reportDraft" "Root" []
  , context "ReplyDraft" (Asset @Body "ReplyBody") "replyDraft" "Root" []
    -- 两份资产，同一个获取 handler；两个 Scoped 注册共用开关 handler，彼此独立。
    -- 取得文件前先驱动路径；后面的读取只读这次发布的路径。
  , context "ReportFile" (Asset @TextFile "OpenedReport") "acquireFile" "Root" [requests "ReportPath", requires "ReportPath"]
  , context "ReplyFile" (Asset @TextFile "OpenedReply") "acquireFile" "Root" [requests "ReplyPath", requires "ReplyPath"]
  , scoped "ReportScope" "OpenedReport"
  , scoped "ReplyScope" "OpenedReply"
    -- 同一个 writeText：Input 和 demands 都不同
  , excu "WriteReport" "writeText" "ReportScope" [requests "ReportBody", requires "OpenedReport", requires "ReportBody"]
  , excu "WriteReply" "writeText" "ReplyScope" [requests "ReplyBody", requires "OpenedReply", requires "ReplyBody"]
    -- 同一个 readText：前驱不同
  , excu "MarkReply" "markRead" "Root" []
  , excu "ReadReport" "readText" "Root" [requires "ReportPath"]
  , excu "ReadReply" "readText" "MarkReply" [requires "ReplyPath"]
    -- 同一个解析器，挂在不同的句柄下，用 rawinput 读取句柄本次的输出
  , context "ReportCounter" (Asset @LineCount "ReportStats") "countLines" "ReadReport" []
  , context "ReplyCounter" (Asset @LineCount "ReplyStats") "countLines" "ReadReply" []
  , excu "ShowReport" "showCount" "Root" [requires "ReportStats"]
  , excu "ShowReply" "showCount" "Root" [requires "ReplyStats"]
    -- 同一次读取的输出挂两个 Context，只有一个解析成功；alternative 按候选 requires 的那一个选择
  , excu "InspectReport" "inspectFile" "Root" [requires "ReportPath"]
  , context "ReportBlank" (Asset @EmptyReport "ReportEmpty") "parseBlankReport" "InspectReport" []
  , context "ReportFilled" (Asset @Body "ReportText") "parseFilledReport" "InspectReport" []
  , excu "OnBlank" "describeBlank" "Root" [requires "ReportEmpty"]
  , excu "OnFilled" "describeFilled" "Root" [requires "ReportText"]
    -- 同一个 Stream 解析器和消费者；Stream 方法体各不相同。交付编号由消费者以 stream @Level 读取 x:xs 得到
  , stream "FeedA" "nextA"
  , stream "FeedB" "nextB"
  , continuous "ParserA" (Asset @Level "LevelA") "parseLevel" "FeedA"
  , continuous "ParserB" (Asset @Level "LevelB") "parseLevel" "FeedB"
  , excu "ShowA" "showLevel" "Root" [streams "LevelA"]
  , excu "ShowB" "showLevel" "Root" [streams "LevelB"]
  ]
  where
    context selected declared parsing upstream needed = EffectSpec
      { name = selected
      , typing = Context { asset = declared, parser = Just parsing, require = True, stream = False }
      , input = upstream
      , demands = needed
      }
    continuous selected declared parsing upstream = EffectSpec
      { name = selected
      , typing = Context { asset = declared, parser = Just parsing, require = True, stream = True }
      , input = upstream
      , demands = []
      }
    excu selected method upstream needed = EffectSpec
      { name = selected
      , typing = Excu { handler = Just method }
      , input = upstream
      , demands = needed
      }
    scoped selected resource = EffectSpec
      { name = selected
      , typing = Scoped { open = Just "openTextFile", close = Just "closeTextFile" }
      , input = "Root"
      , demands = [requests resource, requires resource]
      }
    stream selected method = EffectSpec
      { name = selected
      , typing = Stream { handler = Just method }
      , input = "Root"
      , demands = []
      }
