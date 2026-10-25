{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE TypeFamilies #-}

-- 自动生成；只登记末端句柄，Node algebra 才 lower，业务组合仍在 handler 内。
module Crawler.Generated.Program where

import Framework.SDK (Effect(..), EffectSpec(..), EffectTyping(..), Producer(..), ContextInput(..), ValueSource(..), TypeRef(..), Output)
import qualified Framework.SDK as SDK
import qualified Framework.Effect.Contract as FrameworkRoot
import Crawler.Generated.Effects
import qualified Crawler.Generated.Handlers as Handlers
import Crawler.Types

-- 编译时注册快照；运行前核对声明，改变连接后须重新生成。
registeredEffects :: [EffectSpec]
registeredEffects =
  [ EffectSpec {name = "CrawlerContext", typing = Context {request = Just (Producer {handler = "loadCrawlURLs", produces = TypeRef "CrawlURLs"}), require = Just "readCrawlURLs"}, input = "CrawlSession", context = Nothing}
  , EffectSpec {name = "FetchPage", typing = Context {request = Just (Producer {handler = "fetchPage", produces = TypeRef "FetchedPage"}), require = Just "readFetchedPage"}, input = "CrawlSession", context = Just (ContextInput {request = Just (From "CrawlerContext" (TypeRef "CrawlURLs")), require = Just (From "SessionContext" (TypeRef "CrawlSessionInfo"))})}
  , EffectSpec {name = "ExtractPage", typing = Context {request = Just (Producer {handler = "extractPage", produces = TypeRef "PageSummary"}), require = Just "readPageSummary"}, input = "CrawlSession", context = Just (ContextInput {request = Just (From "FetchPage" (TypeRef "FetchedPage")), require = Nothing})}
  , EffectSpec {name = "PrintPage", typing = Excu {handler = Just "printPage"}, input = "CrawlSession", context = Just (ContextInput {request = Just (From "ExtractPage" (TypeRef "PageSummary")), require = Nothing})}
  , EffectSpec {name = "FetchLinkedPage", typing = Context {request = Just (Producer {handler = "fetchLinkedPage", produces = TypeRef "FetchedPage"}), require = Just "readFetchedLinkedPage"}, input = "CrawlSession", context = Just (ContextInput {request = Just (From "CrawlerContext" (TypeRef "CrawlURLs")), require = Just (From "SessionContext" (TypeRef "CrawlSessionInfo"))})}
  , EffectSpec {name = "ExtractLinkedPage", typing = Context {request = Just (Producer {handler = "extractLinkedPage", produces = TypeRef "PageSummary"}), require = Just "readLinkedPageSummary"}, input = "CrawlSession", context = Just (ContextInput {request = Just (From "FetchLinkedPage" (TypeRef "FetchedPage")), require = Nothing})}
  , EffectSpec {name = "PrintLinkedPage", typing = Excu {handler = Just "printLinkedPage"}, input = "CrawlSession", context = Just (ContextInput {request = Just (From "ExtractLinkedPage" (TypeRef "PageSummary")), require = Nothing})}
  , EffectSpec {name = "SessionContext", typing = Context {request = Just (Producer {handler = "createCrawlSession", produces = TypeRef "CrawlSessionInfo"}), require = Just "readCrawlSession"}, input = "Root", context = Nothing}
  , EffectSpec {name = "CrawlSession", typing = Scoped {open = Just "openCrawlSession", close = Just "closeCrawlSession"}, input = "Root", context = Just (ContextInput {request = Just (From "SessionContext" (TypeRef "CrawlSessionInfo")), require = Just (From "SessionContext" (TypeRef "CrawlSessionInfo"))})}
  , EffectSpec {name = "FinishCrawl", typing = Excu {handler = Just "finishCrawl"}, input = "CrawlSession", context = Nothing}
  ]


-- 仅汇总所选末端的成功产物，不保存共享绑定或增加完成包装。
data Results = ExtractPageResult (Produce ExtractPage) | ExtractLinkedPageResult (Produce ExtractLinkedPage) | PrintPageResult (Produce PrintPage) | PrintLinkedPageResult (Produce PrintLinkedPage) | FinishCrawlResult (Produce FinishCrawl)
  deriving Show

-- 末端共享生成的 scope 句柄；只创建空状态，Node algebra 才 lower，业务调用仍在 instance 内。
compiledEntries :: IO [SDK.Target IO ContextValues Errors Results]
compiledEntries = do
  scopes <- Handlers.newScopeHandlers
  pure
    [ SDK.targetApp "ExtractPage" emptyContexts scopes (FrameworkRoot.withErrorHandlers Handlers.errorHandlers (ExtractPageResult <$> extractPage))
    , SDK.targetApp "ExtractLinkedPage" emptyContexts scopes (FrameworkRoot.withErrorHandlers Handlers.errorHandlers (ExtractLinkedPageResult <$> extractLinkedPage))
    , SDK.targetApp "PrintPage" emptyContexts scopes (FrameworkRoot.withErrorHandlers Handlers.errorHandlers (PrintPageResult <$> printPage))
    , SDK.targetApp "PrintLinkedPage" emptyContexts scopes (FrameworkRoot.withErrorHandlers Handlers.errorHandlers (PrintLinkedPageResult <$> printLinkedPage))
    , SDK.targetApp "FinishCrawl" emptyContexts scopes (FrameworkRoot.withErrorHandlers Handlers.errorHandlers (FinishCrawlResult <$> finishCrawl))
    ]

-- SDK 装配入口，不需要用户提供节点执行器或重复选择 handler。
interpreter :: SDK.AST -> [EffectSpec] -> IO ()
interpreter = SDK.interpreter "Crawler" registeredEffects Handlers.handlerSourceFingerprint compiledEntries
