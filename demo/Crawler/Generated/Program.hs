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
  ]

-- 生成身份连接到已有运行 scope 名；依赖只保存在下方显式 ScopeTree 中。
scopeNames :: [(MethodGen, String)]
scopeNames = [(OpenCrawlSessionGen, "CrawlSession")]

-- 只校验生成常量；当前 workflow 在执行装配的一次 fold 中检查入口。
programStructure :: Either (SDK.StructureError MethodGen) (SDK.ProgramStructure MethodGen)
programStructure = SDK.initializeGeneratedStructure
  [("ExtractPage", ExtractPageGen), ("ExtractLinkedPage", ExtractLinkedPageGen), ("PrintPage", PrintPageGen), ("PrintLinkedPage", PrintLinkedPageGen)]
  scopeNames generatedEffectGraph generatedScopeTree


-- 仅汇总所选末端的成功产物，不保存共享绑定或增加完成包装。
data Results = ExtractPageResult (Produce ExtractPage) | ExtractLinkedPageResult (Produce ExtractLinkedPage) | PrintPageResult (Produce PrintPage) | PrintLinkedPageResult (Produce PrintLinkedPage)
  deriving Show

-- 末端共享生成的 scope 句柄；只创建空状态，Node algebra 才 lower，业务调用仍在 instance 内。
compiledEntries :: IO [SDK.Target IO ContextValues Errors Results]
compiledEntries = do
  scopes <- Handlers.newScopeHandlers
  pure
    [ SDK.targetApp "ExtractPage" emptyContexts scopes (FrameworkRoot.withErrorHandlers Handlers.errorHandlers (SDK.withScopeCleanups Handlers.scopeCleanups (ExtractPageResult <$> extractPage)))
    , SDK.targetApp "ExtractLinkedPage" emptyContexts scopes (FrameworkRoot.withErrorHandlers Handlers.errorHandlers (SDK.withScopeCleanups Handlers.scopeCleanups (ExtractLinkedPageResult <$> extractLinkedPage)))
    , SDK.targetApp "PrintPage" emptyContexts scopes (FrameworkRoot.withErrorHandlers Handlers.errorHandlers (SDK.withScopeCleanups Handlers.scopeCleanups (PrintPageResult <$> printPage)))
    , SDK.targetApp "PrintLinkedPage" emptyContexts scopes (FrameworkRoot.withErrorHandlers Handlers.errorHandlers (SDK.withScopeCleanups Handlers.scopeCleanups (PrintLinkedPageResult <$> printLinkedPage)))
    ]

-- SDK 装配入口，不需要用户提供节点执行器或重复选择 handler。
interpreter :: SDK.AST -> [EffectSpec] -> IO ()
interpreter = SDK.interpreter "Crawler" registeredEffects Handlers.handlerSourceFingerprint programStructure compiledEntries
-- 生成时已完成方法展开与路径分析；运行时只读取显式 ADT 值。
generatedEffectGraph :: SDK.EffectGraph MethodGen
generatedEffectGraph = SDK.EffectGraph
  { SDK.graphMethods =
      [ SDK.MethodDefinition ExtractPageGen ExtractPageGen SDK.ContextRequest (SDK.Call FetchPageGen)
      , SDK.MethodDefinition FetchPageGen FetchPageGen SDK.ContextRequest (SDK.Sequence [SDK.Call OpenCrawlSessionGen, SDK.Call LoadCrawlURLsGen, SDK.Call ReadCrawlSessionGen])
      , SDK.MethodDefinition OpenCrawlSessionGen OpenCrawlSessionGen SDK.ScopeOpen (SDK.Call CreateCrawlSessionGen)
      , SDK.MethodDefinition CreateCrawlSessionGen CreateCrawlSessionGen SDK.ContextRequest (SDK.Empty)
      , SDK.MethodDefinition LoadCrawlURLsGen LoadCrawlURLsGen SDK.ContextRequest (SDK.Empty)
      , SDK.MethodDefinition ReadCrawlSessionGen CreateCrawlSessionGen SDK.ContextRequire (SDK.Empty)
      , SDK.MethodDefinition ExtractLinkedPageGen ExtractLinkedPageGen SDK.ContextRequest (SDK.Call FetchLinkedPageGen)
      , SDK.MethodDefinition FetchLinkedPageGen FetchLinkedPageGen SDK.ContextRequest (SDK.Sequence [SDK.Call OpenCrawlSessionGen, SDK.Call LoadCrawlURLsGen, SDK.Call ReadCrawlSessionGen])
      , SDK.MethodDefinition PrintPageGen PrintPageGen SDK.HandlerMethod (SDK.Call ExtractPageGen)
      , SDK.MethodDefinition PrintLinkedPageGen PrintLinkedPageGen SDK.HandlerMethod (SDK.Call ExtractLinkedPageGen)
      ]
  , SDK.graphRoots = [ExtractPageGen, ExtractLinkedPageGen, PrintPageGen, PrintLinkedPageGen]
  , SDK.graphReferences = [(ExtractPageGen, FetchPageGen), (FetchPageGen, OpenCrawlSessionGen), (FetchPageGen, LoadCrawlURLsGen), (FetchPageGen, ReadCrawlSessionGen), (OpenCrawlSessionGen, CreateCrawlSessionGen), (ExtractLinkedPageGen, FetchLinkedPageGen), (FetchLinkedPageGen, OpenCrawlSessionGen), (FetchLinkedPageGen, LoadCrawlURLsGen), (FetchLinkedPageGen, ReadCrawlSessionGen), (PrintPageGen, ExtractPageGen), (PrintLinkedPageGen, ExtractLinkedPageGen)]
  , SDK.graphScopes = [OpenCrawlSessionGen]
  , SDK.graphScopePaths = [[OpenCrawlSessionGen]]
  , SDK.graphRootPaths =
      [ (ExtractPageGen, [[OpenCrawlSessionGen]])
      , (ExtractLinkedPageGen, [[OpenCrawlSessionGen]])
      , (PrintPageGen, [[OpenCrawlSessionGen]])
      , (PrintLinkedPageGen, [[OpenCrawlSessionGen]])
      ]
  , SDK.graphScopeOrder = []
  }

-- 唯一的 ScopeTree：共同前序与注册前提已合并、检查环并约简。
generatedScopeTree :: SDK.ScopeTree MethodGen
generatedScopeTree = SDK.ScopeTree
  { SDK.scopeRoots = [OpenCrawlSessionGen]
  , SDK.scopeNodes =
      [ SDK.ScopeNode { SDK.scopeIdentity = OpenCrawlSessionGen, SDK.scopeParents = [], SDK.scopeChildren = [] }
      ]
  , SDK.scopeLayers = [[OpenCrawlSessionGen]]
  , SDK.scopePaths = [[OpenCrawlSessionGen]]
  , SDK.scopeCandidates = []
  , SDK.scopeOpposed = []
  , SDK.scopeUndetermined = []
  }
