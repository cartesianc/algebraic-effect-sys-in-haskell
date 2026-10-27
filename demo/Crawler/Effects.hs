{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE TypeApplications #-}

module Crawler.Effects (effects) where

import Framework.SDK (EffectSpec(..), EffectTyping(..), Producer(..), requests, requires, typeRef)
import Crawler.Types

-- 1. Registered code：只有类型引用、分类和连接，没有 HTTP 或 HTML 实现。
-- typing 声明生产方方法名；demands 声明需要的契约与取值模式，来源省略时唯一解析。
-- 来源按类型唯一解析：起始页与链接页两条链的 URL、抓取结果和摘要
-- 各用 Types.hs 中不同的 newtype，因此无需指名生产方。
-- instance 显式调用 open；无开启输入的 scope 在实际重叠的使用闭包之间共享。
-- 普通 effect 成功值固定为 ()；业务产值统一由 Context 提供，失败仍用 raise。
effects :: [EffectSpec]
effects =
  [ EffectSpec
      { name = "StartPage"
      , typing = Context
          { request = Just Producer
              { handler = "loadStartURL"
              , produces = typeRef @StartURL
              }
          , require = Just "readStartURL"
          }
      , input = "CrawlSession"
      , demands = []
      }
  , EffectSpec
      { name = "LinkedPage"
      , typing = Context
          { request = Just Producer
              { handler = "loadLinkedURL"
              , produces = typeRef @LinkedURL
              }
          , require = Just "readLinkedURL"
          }
      , input = "CrawlSession"
      , demands = []
      }
  , EffectSpec
      { name = "FetchPage"
      , typing = Context
          { request = Just Producer
              { handler = "fetchPage"
              , produces = typeRef @StartFetchedPage
              }
          , require = Just "readFetchedPage"
          }
      , input = "CrawlSession"
      , demands = [requests @StartURL, requires @CrawlSessionInfo]
      }
  , EffectSpec
      { name = "ExtractPage"
      , typing = Context
          { request = Just Producer
              { handler = "extractPage"
              , produces = typeRef @StartPageSummary
              }
          , require = Just "readPageSummary"
          }
      , input = "CrawlSession"
      , demands = [requests @StartFetchedPage]
      }
  , EffectSpec
      { name = "PrintPage"
      , typing = Excu { handler = Just "printPage" }
      , input = "CrawlSession"
      , demands = [requests @StartPageSummary]
      }
  , EffectSpec
      { name = "FetchLinkedPage"
      , typing = Context
          { request = Just Producer
              { handler = "fetchLinkedPage"
              , produces = typeRef @LinkedFetchedPage
              }
          , require = Just "readFetchedLinkedPage"
          }
      , input = "CrawlSession"
      , demands = [requests @LinkedURL, requires @CrawlSessionInfo]
      }
  , EffectSpec
      { name = "ExtractLinkedPage"
      , typing = Context
          { request = Just Producer
              { handler = "extractLinkedPage"
              , produces = typeRef @LinkedPageSummary
              }
          , require = Just "readLinkedPageSummary"
          }
      , input = "CrawlSession"
      , demands = [requests @LinkedFetchedPage]
      }
  , EffectSpec
      { name = "PrintLinkedPage"
      , typing = Excu { handler = Just "printLinkedPage" }
      , input = "CrawlSession"
      , demands = [requests @LinkedPageSummary]
      }
  -- 信息由上游 Context 提供；Scope 只描述开启／关闭和持存状态。
  , EffectSpec
      { name = "SessionContext"
      , typing = Context
          { request = Just Producer
              { handler = "createCrawlSession"
              , produces = typeRef @CrawlSessionInfo
              }
          , require = Just "readCrawlSession"
          }
      , input = "Root"
      , demands = []
      }
  , EffectSpec
      { name = "CrawlSession"
      , typing = Scoped
          { open = Just "openCrawlSession"
          , close = Just "closeCrawlSession"
          }
      , input = "Root"
      , demands = [requests @CrawlSessionInfo, requires @CrawlSessionInfo]
      }
  ]
