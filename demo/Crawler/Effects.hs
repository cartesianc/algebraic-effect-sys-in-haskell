{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE TypeApplications #-}

module Crawler.Effects (effects) where

import Framework.SDK (EffectSpec(..), EffectTyping(..), requester, requests, requires)
import Crawler.Types

-- 1. Registered code：只有类型引用、分类和连接，没有 HTTP 或 HTML 实现。
-- requester "handler名" @表示类型：handler 名首字母大写即契约名，生成器产出 newtype 契约 = 契约 表示类型。
-- 消费方以契约名声明 requests／requires，来源由契约名唯一确定；handler 中写 request @契约名。
-- instance 显式调用 open；无开启输入的 scope 在实际重叠的使用闭包之间共享。
-- 普通 effect 成功值固定为 ()；业务产值统一由 Context 提供，失败仍用 raise。
effects :: [EffectSpec]
effects =
  [ EffectSpec
      { name = "StartPage"
      , typing = Context { request = requester "startURL" @PageURL }
      , input = "CrawlSession"
      , demands = []
      }
  , EffectSpec
      { name = "LinkedPage"
      , typing = Context { request = requester "linkedURL" @PageURL }
      , input = "CrawlSession"
      , demands = []
      }
  , EffectSpec
      { name = "FetchPage"
      , typing = Context { request = requester "startFetchedPage" @FetchedPage }
      , input = "CrawlSession"
      , demands = [requests "StartURL", requires "CrawlSessionInfo"]
      }
  , EffectSpec
      { name = "ExtractPage"
      , typing = Context { request = requester "startPageSummary" @PageSummary }
      , input = "CrawlSession"
      , demands = [requests "StartFetchedPage"]
      }
  , EffectSpec
      { name = "PrintPage"
      , typing = Excu { handler = Just "printPage" }
      , input = "CrawlSession"
      , demands = [requests "StartPageSummary"]
      }
  , EffectSpec
      { name = "FetchLinkedPage"
      , typing = Context { request = requester "linkedFetchedPage" @FetchedPage }
      , input = "CrawlSession"
      , demands = [requests "LinkedURL", requires "CrawlSessionInfo"]
      }
  , EffectSpec
      { name = "ExtractLinkedPage"
      , typing = Context { request = requester "linkedPageSummary" @PageSummary }
      , input = "CrawlSession"
      , demands = [requests "LinkedFetchedPage"]
      }
  , EffectSpec
      { name = "PrintLinkedPage"
      , typing = Excu { handler = Just "printLinkedPage" }
      , input = "CrawlSession"
      , demands = [requests "LinkedPageSummary"]
      }
  -- 信息由上游 Context 提供；Scope 只描述开启／关闭和持存状态。
  , EffectSpec
      { name = "SessionContext"
      , typing = Context { request = requester "crawlSessionInfo" @SessionInfo }
      , input = "Root"
      , demands = []
      }
  , EffectSpec
      { name = "CrawlSession"
      , typing = Scoped { open = Just "openCrawlSession", close = Just "closeCrawlSession" }
      , input = "Root"
      , demands = [requests "CrawlSessionInfo", requires "CrawlSessionInfo"]
      }
  ]
