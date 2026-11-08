{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE TypeApplications #-}

-- Current syntax: only used so the existing generator can build the prototype.
module FacadeProbe.Effects (effects) where

import Framework.SDK (EffectSpec(..), EffectTyping(..), Asset(..), requests, requires, streams)
import FacadeProbe.Types

effects :: [EffectSpec]
effects =
  [ context "ReportLocation" (Asset @FilePath "ReportPath") "Root" []
  , context "ReplyLocation" (Asset @FilePath "ReplyPath") "Root" []
  , context "ReportDraft" (Asset @Body "ReportBody") "Root" []
  , context "ReplyDraft" (Asset @Body "ReplyBody") "Root" []
  , context "ReportFile" (Asset @TextFile "OpenedReport") "Root" [requires "ReportPath"]
  , context "ReplyFile" (Asset @TextFile "OpenedReply") "Root" [requires "ReplyPath"]
  , scoped "ReportScope" "openReport" "closeReport" "OpenedReport"
  , scoped "ReplyScope" "openReply" "closeReply" "OpenedReply"
  , excu "WriteReport" "writeReport" "ReportScope" [requires "OpenedReport", requires "ReportBody"]
  , excu "WriteReply" "writeReply" "ReplyScope" [requires "OpenedReply", requires "ReplyBody"]
  , excu "MarkReply" "markReply" "Root" []
  , excu "ReadReport" "readReport" "Root" [requires "ReportPath"]
  , excu "ReadReply" "readReply" "MarkReply" [requires "ReplyPath"]
  , context "ReportCounter" (Asset @LineCount "ReportStats") "ReadReport" []
  , context "ReplyCounter" (Asset @LineCount "ReplyStats") "ReadReply" []
  , excu "ShowReport" "showReport" "Root" [requires "ReportStats"]
  , excu "ShowReply" "showReply" "Root" [requires "ReplyStats"]
  , context "ReportInspect" (Asset @FileState "ReportState") "Root" [requires "ReportPath"]
  , excu "OnBlank" "onBlank" "Root" [requires "ReportStateBlank"]
  , excu "OnFilled" "onFilled" "Root" [requires "ReportStateFilled"]
  , stream "FeedA" "nextA"
  , stream "FeedB" "nextB"
  , context "ParserA" (Asset @Level "LevelA") "FeedA" []
  , context "ParserB" (Asset @Level "LevelB") "FeedB" []
  , excu "ShowA" "showA" "Root" [streams "LevelA"]
  , excu "ShowB" "showB" "Root" [streams "LevelB"]
  ]
  where
    context selected declared upstream needed = EffectSpec
      { name = selected
      , typing = Context { asset = declared, request = Just (), require = Just (), stream = Nothing }
      , input = upstream
      , demands = needed
      }
    excu selected method upstream needed = EffectSpec
      { name = selected
      , typing = Excu { handler = Just method }
      , input = upstream
      , demands = needed
      }
    scoped selected opening closing resource = EffectSpec
      { name = selected
      , typing = Scoped { open = Just opening, close = Just closing }
      , input = "Root"
      , demands = [requests resource, requires resource]
      }
    stream selected method = EffectSpec
      { name = selected
      , typing = Stream { handler = Just method }
      , input = "Root"
      , demands = []
      }
