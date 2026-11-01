{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE TypeApplications #-}

module Crawler.Effects (effects) where

import Framework.SDK (EffectSpec(..), EffectTyping(..), namedAsset, requests, requires)
import Crawler.Types

-- 1. Registered code：只有类型引用、分类和连接，没有 HTTP 或 HTML 实现。
-- namedAsset "资产名" @表示类型：资产名即契约名，生成器产出 newtype 契约 = 契约 表示类型；request 角色生成 get 加资产名的生产方法，require 角色生成 read 加资产名的读取方法；demands 以契约名引用。
-- 消费方以契约名声明 requests／requires，来源由契约名唯一确定；handler 中写 request @契约名。
-- instance 显式调用 open；无开启输入的 scope 在实际重叠的使用闭包之间共享。
-- 抓取是原子句柄（Excu），只执行 IO；解析 Context 以 input 挂在抓取句柄下，解析它的输出。
-- 业务产值统一由 Context 提供，失败仍用 raise。
effects :: [EffectSpec]
effects =
  [ EffectSpec
      { name = "StartPage"
      , typing = Context { asset = namedAsset "StartURL" @PageURL, request = Just (), require = Just (), stream = Nothing }
      , input = "Root"
      , demands = []
      }
  , EffectSpec
      { name = "LinkedPage"
      , typing = Context { asset = namedAsset "LinkedURL" @PageURL, request = Just (), require = Just (), stream = Nothing }
      , input = "Root"
      , demands = []
      }
  , EffectSpec
      { name = "FetchPage"
      , typing = Excu { handler = Just "fetchStartPage" }
      , input = "CrawlSession"
      , demands = [requests "StartURL", requires "CrawlSessionInfo"]
      }
  , EffectSpec
      { name = "ExtractPage"
      , typing = Context { asset = namedAsset "StartPageSummary" @PageSummary, request = Just (), require = Just (), stream = Nothing }
      , input = "FetchPage"
      , demands = [requires "StartURL"]
      }
  , EffectSpec
      { name = "PrintPage"
      , typing = Excu { handler = Just "printPage" }
      , input = "Root"
      , demands = [requires "StartPageSummary"]
      }
  , EffectSpec
      { name = "FetchLinkedPage"
      , typing = Excu { handler = Just "fetchLinkedPage" }
      , input = "CrawlSession"
      , demands = [requests "LinkedURL", requires "CrawlSessionInfo"]
      }
  , EffectSpec
      { name = "ExtractLinkedPage"
      , typing = Context { asset = namedAsset "LinkedPageSummary" @PageSummary, request = Just (), require = Just (), stream = Nothing }
      , input = "FetchLinkedPage"
      , demands = [requires "LinkedURL"]
      }
  , EffectSpec
      { name = "PrintLinkedPage"
      , typing = Excu { handler = Just "printLinkedPage" }
      , input = "Root"
      , demands = [requires "LinkedPageSummary"]
      }
  -- 信息由上游 Context 提供；Scope 只描述开启／关闭和持存状态。
  , EffectSpec
      { name = "SessionContext"
      , typing = Context { asset = namedAsset "CrawlSessionInfo" @SessionInfo, request = Just (), require = Just (), stream = Nothing }
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
