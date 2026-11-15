{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE TypeApplications #-}

module LinesDemo.Effects (effects) where

import Framework.SDK (EffectSpec(..), EffectTyping(..), Asset(..), requests, requires, streams)
import LinesDemo.Types

-- 一个会结束的 Stream：逐行读取文本文件，读到末尾时 handler 调用 end。
-- 输入文件是 InputSession 的资源：没有开启参数，只开启一次，在生产会话的各步骤间保持。
-- LineFeed 每次取得一行原始文本；挂在它下面的 LineParser 把它解析成持续资产 TextLine。
-- PrintLine 以 TextLine 的新交付驱动；Report 排在 lifelong 之后，来源结束、交付处理完才执行。
-- Tally 也由 TextLine 驱动，但它下面挂着 Context：每来一行重新统计一次，产出另一份持续资产 RunningTotal。
-- Tally 不挂载到 AST，它是 RunningTotal 的生产链，由订阅它的 ShowTotal 启动；Report 读它结束时的最新一条。
effects :: [EffectSpec]
effects =
  [ EffectSpec
      { name = "Announce"
      , typing = Excu { handler = Just "announce" }
      , input = "Root"
      , demands = []
      }
  , EffectSpec
      { name = "InputResource"
      , typing = Context { asset = Asset @InputFile "OpenedInput", parser = Just "acquireInput", require = True, stream = False }
      , input = "Root"
      , demands = []
      }
  , EffectSpec
      { name = "InputSession"
      , typing = Scoped { open = Just "openInput", close = Just "closeInput" }
      , input = "Root"
      , demands = [requests "OpenedInput", requires "OpenedInput"]
      }
  , EffectSpec
      { name = "LineFeed"
      , typing = Stream { handler = Just "nextLine" }
      , input = "InputSession"
      , demands = [requires "OpenedInput"]
      }
  , EffectSpec
      { name = "LineParser"
      , typing = Context { asset = Asset @Line "TextLine", parser = Just "parseLine", require = True, stream = True }
      , input = "LineFeed"
      , demands = []
      }
  , EffectSpec
      { name = "PrintLine"
      , typing = Excu { handler = Just "printLine" }
      , input = "Root"
      , demands = [streams "TextLine"]
      }
  , EffectSpec
      { name = "Tally"
      , typing = Excu { handler = Just "tally" }
      , input = "Root"
      , demands = [streams "TextLine"]
      }
  , EffectSpec
      { name = "TallyParser"
      , typing = Context { asset = Asset @Total "RunningTotal", parser = Just "parseTotal", require = True, stream = True }
      , input = "Tally"
      , demands = []
      }
  , EffectSpec
      { name = "ShowTotal"
      , typing = Excu { handler = Just "showTotal" }
      , input = "Root"
      , demands = [streams "RunningTotal"]
      }
  , EffectSpec
      { name = "Report"
      , typing = Excu { handler = Just "report" }
      , input = "Root"
      , demands = [requires "RunningTotal"]
      }
  ]
