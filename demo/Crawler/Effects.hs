{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE TypeApplications #-}

module Crawler.Effects (effects) where

import Framework.SDK (EffectSpec(..), EffectTyping(..), Asset(..), requests, requires)
import Crawler.Types

-- 1. Registered code：只有类型引用、分类和连接，没有 HTTP 或 HTML 实现；每个字段写 handler 名。
-- Asset @表示类型 "资产名" 把表示类型细化为以资产名命名的资产（refinement asset），demands 以资产名引用。
-- handler 按表示类型 require；同一个 handler 注册到不同 effect，由各自的 demands 决定读哪份资产。
-- requests 在入口驱动资产的生产链，requires 只读取；input 是前驱，gen 在 handler 之前执行它。
-- 抓取是原子句柄（Excu），只执行 IO，交出 [String]；Pure 在生产链中去掉空白正文；
-- 解析 Context 以 input 挂在 Pure 下，用 raw 读取它变换后的 list。
-- 无开启输入的 scope 在实际重叠的使用闭包之间共享。业务产值统一由 Context 提供，失败仍用 raise。
effects :: [EffectSpec]
effects =
  [ EffectSpec
      { name = "StartPage"
      , typing = Context { asset = Asset @PageURL "StartURL", parser = Just "startURL", require = True, stream = False }
      , input = "Root"
      , demands = []
      }
  , EffectSpec
      { name = "LinkedPage"
      , typing = Context { asset = Asset @PageURL "LinkedURL", parser = Just "linkedURL", require = True, stream = False }
      , input = "Root"
      , demands = []
      }
  -- 两个抓取共用 fetchPage：前驱相同，读到的 URL 各自来自 StartURL、LinkedURL。
  , EffectSpec
      { name = "FetchPage"
      , typing = Excu { handler = Just "fetchPage" }
      , input = "CrawlSession"
      , demands = [requests "StartURL", requires "StartURL", requires "CrawlSessionInfo"]
      }
  -- 两个 Pure 共用 dropBlankBodies：只变换上层交出的 list，不声明 demands。
  , EffectSpec
      { name = "KeepPageBody"
      , typing = Pure { handler = Just "dropBlankBodies" }
      , input = "FetchPage"
      , demands = []
      }
  , EffectSpec
      { name = "ExtractPage"
      , typing = Context { asset = Asset @PageSummary "StartPageSummary", parser = Just "extractSummary", require = True, stream = False }
      , input = "KeepPageBody"
      , demands = [requires "StartURL"]
      }
  , EffectSpec
      { name = "PrintPage"
      , typing = Excu { handler = Just "printSummary" }
      , input = "Root"
      , demands = [requires "StartPageSummary"]
      }
  , EffectSpec
      { name = "FetchLinkedPage"
      , typing = Excu { handler = Just "fetchPage" }
      , input = "CrawlSession"
      , demands = [requests "LinkedURL", requires "LinkedURL", requires "CrawlSessionInfo"]
      }
  , EffectSpec
      { name = "KeepLinkedPageBody"
      , typing = Pure { handler = Just "dropBlankBodies" }
      , input = "FetchLinkedPage"
      , demands = []
      }
  , EffectSpec
      { name = "ExtractLinkedPage"
      , typing = Context { asset = Asset @PageSummary "LinkedPageSummary", parser = Just "extractSummary", require = True, stream = False }
      , input = "KeepLinkedPageBody"
      , demands = [requires "LinkedURL"]
      }
  , EffectSpec
      { name = "PrintLinkedPage"
      , typing = Excu { handler = Just "printSummary" }
      , input = "Root"
      , demands = [requires "LinkedPageSummary"]
      }
  -- 会话信息由 Context 生产；scope 开启前由 requests 驱动，抓取链读取 scope 内保存的值。
  , EffectSpec
      { name = "SessionContext"
      , typing = Context { asset = Asset @SessionInfo "CrawlSessionInfo", parser = Just "sessionInfo", require = True, stream = False }
      , input = "Root"
      , demands = []
      }
  , EffectSpec
      { name = "CrawlSession"
      , typing = Scoped { open = Just "openSession", close = Just "closeSession" }
      , input = "Root"
      , demands = [requests "CrawlSessionInfo", requires "CrawlSessionInfo"]
      }
  ]
