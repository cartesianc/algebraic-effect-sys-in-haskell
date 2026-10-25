{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE TypeApplications #-}

module Crawler.Effects (effects) where

import Framework.SDK (EffectSpec(..), EffectTyping(..), Producer(..), ContextInput(..), ValueSource(..), typeRef)
import Crawler.Types

-- 1. Registered code：只有类型引用、分类和连接，没有 HTTP 或 HTML 实现。
-- typing 声明生产方方法名；context 内的 request / require 声明消费来源与接收 ADT。
-- scope 沿 Input 和 request 生产链推导；instance 显式调用 open，SDK 保证同份 scope 只开启一次。
-- 普通 effect 成功值固定为 ()；业务产值统一由 Context 提供，失败仍用 raise。


effects :: [EffectSpec]
effects =
  [ EffectSpec
      { name = "CrawlerContext"
      , typing = Context
          { request = Just Producer
              { handler = "loadCrawlURLs"
              , produces = typeRef @CrawlURLs
              }
          , require = Just "readCrawlURLs"
          }
      , input = "CrawlSession"
      , context = Nothing
      }



  , EffectSpec
      { name = "FetchPage"
      , typing = Context
          { request = Just Producer
              { handler = "fetchPage"
              , produces = typeRef @FetchedPage
              }
          , require = Just "readFetchedPage"
          }
      , input = "CrawlSession"
      , context = Just ContextInput
          { request = Just (From "CrawlerContext" (typeRef @CrawlURLs))
          , require = Just (From "SessionContext" (typeRef @CrawlSessionInfo))
          }
      }

  , EffectSpec
      { name = "ExtractPage"
      , typing = Context
          { request = Just Producer
              { handler = "extractPage"
              , produces = typeRef @PageSummary
              }
          , require = Just "readPageSummary"
          }
      , input = "CrawlSession"
      , context = Just ContextInput
          { request = Just (From "FetchPage" (typeRef @FetchedPage))
          , require = Nothing
          }
      }
  , EffectSpec
      { name = "PrintPage"
      , typing = Excu { handler = Just "printPage" }
      , input = "CrawlSession"
      , context = Just ContextInput
          { request = Just (From "ExtractPage" (typeRef @PageSummary))
          , require = Nothing
          }
      }
  , EffectSpec
      { name = "FetchLinkedPage"
      , typing = Context
          { request = Just Producer
              { handler = "fetchLinkedPage"
              , produces = typeRef @FetchedPage
              }
          , require = Just "readFetchedLinkedPage"
          }
      , input = "CrawlSession"
      , context = Just ContextInput
          { request = Just (From "CrawlerContext" (typeRef @CrawlURLs))
          , require = Just (From "SessionContext" (typeRef @CrawlSessionInfo))
          }
      }
  , EffectSpec
      { name = "ExtractLinkedPage"
      , typing = Context
          { request = Just Producer
              { handler = "extractLinkedPage"
              , produces = typeRef @PageSummary
              }
          , require = Just "readLinkedPageSummary"
          }
      , input = "CrawlSession"
      , context = Just ContextInput
          { request = Just (From "FetchLinkedPage" (typeRef @FetchedPage))
          , require = Nothing
          }
      }
  , EffectSpec
      { name = "PrintLinkedPage"
      , typing = Excu { handler = Just "printLinkedPage" }
      , input = "CrawlSession"
      , context = Just ContextInput
          { request = Just (From "ExtractLinkedPage" (typeRef @PageSummary))
          , require = Nothing
          }
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
      , context = Nothing
      }
  , EffectSpec
      { name = "CrawlSession"
      , typing = Scoped
          { open = Just "openCrawlSession"
          , close = Just "closeCrawlSession"
          }
      , input = "Root"
      , context = Just ContextInput
          { request = Just (From "SessionContext" (typeRef @CrawlSessionInfo))
          , require = Just (From "SessionContext" (typeRef @CrawlSessionInfo))
          }
      }
  , EffectSpec
      { name = "FinishCrawl"
      , typing = Excu { handler = Just "finishCrawl" }
      , input = "CrawlSession"
      , context = Nothing
      }
  ]
