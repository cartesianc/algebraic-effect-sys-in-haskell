{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE TypeFamilies #-}

-- 自动生成；只登记末端句柄，Node algebra 才 lower，业务组合仍在 handler 内。
module Crawler.Generated.Program where

import Framework.SDK (Effect(..), EffectSpec(..), EffectTyping(..), Requester(..), Handles(..), Demand(..), Access(..), TypeRef(..))
import qualified Framework.SDK as SDK
import qualified Framework.Effect.Contract as FrameworkRoot
import Crawler.Generated.Effects hiding (request, require)
import qualified Crawler.Generated.Handlers as Handlers
import Crawler.Types

-- 编译时注册快照；运行前核对声明，改变连接后须重新生成。
registeredEffects :: [EffectSpec]
registeredEffects =
  [ EffectSpec {name = "StartPage", typing = Context {request = Just (Requester {handler = "startURL", representation = TypeRef "PageURL"})}, input = "Root", demands = []}
  , EffectSpec {name = "LinkedPage", typing = Context {request = Just (Requester {handler = "linkedURL", representation = TypeRef "PageURL"})}, input = "Root", demands = []}
  , EffectSpec {name = "FetchPage", typing = Excu {handler = Just "fetchStartPage"}, input = "CrawlSession", demands = [Demand {access = RequestAccess, contract = "StartURL"},Demand {access = RequireAccess, contract = "CrawlSessionInfo"}]}
  , EffectSpec {name = "ExtractPage", typing = Context {request = Just (Requester {handler = "startPageSummary", representation = TypeRef "PageSummary"})}, input = "FetchPage", demands = [Demand {access = RequireAccess, contract = "StartURL"}]}
  , EffectSpec {name = "PrintPage", typing = Excu {handler = Just "printPage"}, input = "Root", demands = [Demand {access = RequireAccess, contract = "StartPageSummary"}]}
  , EffectSpec {name = "FetchLinkedPage", typing = Excu {handler = Just "fetchLinkedPage"}, input = "CrawlSession", demands = [Demand {access = RequestAccess, contract = "LinkedURL"},Demand {access = RequireAccess, contract = "CrawlSessionInfo"}]}
  , EffectSpec {name = "ExtractLinkedPage", typing = Context {request = Just (Requester {handler = "linkedPageSummary", representation = TypeRef "PageSummary"})}, input = "FetchLinkedPage", demands = [Demand {access = RequireAccess, contract = "LinkedURL"}]}
  , EffectSpec {name = "PrintLinkedPage", typing = Excu {handler = Just "printLinkedPage"}, input = "Root", demands = [Demand {access = RequireAccess, contract = "LinkedPageSummary"}]}
  , EffectSpec {name = "SessionContext", typing = Context {request = Just (Requester {handler = "crawlSessionInfo", representation = TypeRef "SessionInfo"})}, input = "Root", demands = []}
  , EffectSpec {name = "CrawlSession", typing = Scoped {open = Just "openCrawlSession", close = Just "closeCrawlSession"}, input = "Root", demands = [Demand {access = RequestAccess, contract = "CrawlSessionInfo"},Demand {access = RequireAccess, contract = "CrawlSessionInfo"}]}
  ]

-- 生成身份连接到已有运行 scope 名；依赖只保存在下方显式 ScopeTree 中。
scopeNames :: [(MethodGen, String)]
scopeNames = [(OpenCrawlSessionGen, "CrawlSession")]

-- 只校验生成常量；当前 workflow 在执行装配的一次 fold 中检查入口。
programStructure :: Either (SDK.StructureError MethodGen) (SDK.ProgramStructure MethodGen)
programStructure = SDK.initializeGeneratedStructure
  [("FetchPage", FetchStartPageGen), ("FetchLinkedPage", FetchLinkedPageGen), ("PrintPage", PrintPageGen), ("PrintLinkedPage", PrintLinkedPageGen)]
  scopeNames generatedEffectGraph generatedScopeTree


-- 仅汇总所选末端的成功产物，不保存共享绑定或增加完成包装。
data Results = FetchPageResult (Produce FetchPage) | FetchLinkedPageResult (Produce FetchLinkedPage) | PrintPageResult (Produce PrintPage) | PrintLinkedPageResult (Produce PrintLinkedPage)
  deriving Show

-- alternative 的候选：末端 → (转折契约, 构造器)。由 gencode 从注册推出；
-- 运行时只据此在已装配的闭包之间选择，不保存或重组 effect chain。
alternativeCases :: [(String, (String, String))]
alternativeCases = []

-- 末端共享生成的 scope 句柄；只创建空状态，Node algebra 才 lower，业务调用仍在 instance 内。
-- 第二个列表是各转折契约的读取末端：按 require 取得资产，返回它当前的构造器名。
compiledEntries :: IO ([SDK.Target ContextValues Errors Results], [SDK.Target ContextValues Errors String])
compiledEntries = do
  scopes <- Handlers.newScopeHandlers
  pure
    ( [ SDK.targetApp "FetchPage" emptyContexts scopes (FrameworkRoot.withErrorHandlers Handlers.errorHandlers (FrameworkRoot.withAnchoredContexts Handlers.contextInjections (SDK.withScopeCleanups Handlers.scopeCleanups (FetchPageResult <$> (() <$ fetchStartPage)))))
      , SDK.targetApp "FetchLinkedPage" emptyContexts scopes (FrameworkRoot.withErrorHandlers Handlers.errorHandlers (FrameworkRoot.withAnchoredContexts Handlers.contextInjections (SDK.withScopeCleanups Handlers.scopeCleanups (FetchLinkedPageResult <$> (() <$ fetchLinkedPage)))))
      , SDK.targetApp "PrintPage" emptyContexts scopes (FrameworkRoot.withErrorHandlers Handlers.errorHandlers (FrameworkRoot.withAnchoredContexts Handlers.contextInjections (SDK.withScopeCleanups Handlers.scopeCleanups (PrintPageResult <$> (() <$ printPage)))))
      , SDK.targetApp "PrintLinkedPage" emptyContexts scopes (FrameworkRoot.withErrorHandlers Handlers.errorHandlers (FrameworkRoot.withAnchoredContexts Handlers.contextInjections (SDK.withScopeCleanups Handlers.scopeCleanups (PrintLinkedPageResult <$> (() <$ printLinkedPage)))))
      ]
    , []
    )

-- SDK 装配入口，不需要用户提供节点执行器或重复选择 handler。
interpreter :: SDK.AST -> [EffectSpec] -> IO ()
interpreter = SDK.interpreter "Crawler" registeredEffects Handlers.handlerSourceFingerprint programStructure alternativeCases compiledEntries
-- 生成时已完成方法展开与路径分析；运行时只读取显式 ADT 值。
generatedEffectGraph :: SDK.EffectGraph MethodGen
generatedEffectGraph = SDK.EffectGraph
  { SDK.graphMethods =
      [ SDK.MethodDefinition FetchStartPageGen FetchStartPageGen SDK.HandlerMethod (SDK.Sequence [SDK.Sequence [SDK.Call OpenCrawlSessionGen, SDK.Call StartURLGen, SDK.Call ReadCrawlSessionInfoGen], SDK.Choice [SDK.Empty, SDK.Sequence [SDK.Sequence [SDK.Empty, SDK.Call ReadStartURLGen]]]])
      , SDK.MethodDefinition OpenCrawlSessionGen OpenCrawlSessionGen SDK.ScopeOpen (SDK.Call CrawlSessionInfoGen)
      , SDK.MethodDefinition CrawlSessionInfoGen CrawlSessionInfoGen SDK.ContextRequest (SDK.Empty)
      , SDK.MethodDefinition StartURLGen StartURLGen SDK.ContextRequest (SDK.Empty)
      , SDK.MethodDefinition ReadCrawlSessionInfoGen CrawlSessionInfoGen SDK.ContextRequire (SDK.Empty)
      , SDK.MethodDefinition ReadStartURLGen StartURLGen SDK.ContextRequire (SDK.Choice [SDK.Empty, SDK.Call StartURLGen])
      , SDK.MethodDefinition FetchLinkedPageGen FetchLinkedPageGen SDK.HandlerMethod (SDK.Sequence [SDK.Sequence [SDK.Call OpenCrawlSessionGen, SDK.Call LinkedURLGen, SDK.Call ReadCrawlSessionInfoGen], SDK.Choice [SDK.Empty, SDK.Sequence [SDK.Sequence [SDK.Empty, SDK.Call ReadLinkedURLGen]]]])
      , SDK.MethodDefinition LinkedURLGen LinkedURLGen SDK.ContextRequest (SDK.Empty)
      , SDK.MethodDefinition ReadLinkedURLGen LinkedURLGen SDK.ContextRequire (SDK.Choice [SDK.Empty, SDK.Call LinkedURLGen])
      , SDK.MethodDefinition PrintPageGen PrintPageGen SDK.HandlerMethod (SDK.Call ReadStartPageSummaryGen)
      , SDK.MethodDefinition ReadStartPageSummaryGen StartPageSummaryGen SDK.ContextRequire (SDK.Choice [SDK.Empty, SDK.Call StartPageSummaryGen])
      , SDK.MethodDefinition StartPageSummaryGen StartPageSummaryGen SDK.ContextRequest (SDK.Sequence [SDK.Call FetchStartPageGen, SDK.Call ReadStartURLGen])
      , SDK.MethodDefinition PrintLinkedPageGen PrintLinkedPageGen SDK.HandlerMethod (SDK.Call ReadLinkedPageSummaryGen)
      , SDK.MethodDefinition ReadLinkedPageSummaryGen LinkedPageSummaryGen SDK.ContextRequire (SDK.Choice [SDK.Empty, SDK.Call LinkedPageSummaryGen])
      , SDK.MethodDefinition LinkedPageSummaryGen LinkedPageSummaryGen SDK.ContextRequest (SDK.Sequence [SDK.Call FetchLinkedPageGen, SDK.Call ReadLinkedURLGen])
      ]
  , SDK.graphRoots = [FetchStartPageGen, FetchLinkedPageGen, PrintPageGen, PrintLinkedPageGen]
  , SDK.graphReferences = [(FetchStartPageGen, OpenCrawlSessionGen), (FetchStartPageGen, StartURLGen), (FetchStartPageGen, ReadCrawlSessionInfoGen), (FetchStartPageGen, ReadStartURLGen), (OpenCrawlSessionGen, CrawlSessionInfoGen), (ReadStartURLGen, StartURLGen), (FetchLinkedPageGen, OpenCrawlSessionGen), (FetchLinkedPageGen, LinkedURLGen), (FetchLinkedPageGen, ReadCrawlSessionInfoGen), (FetchLinkedPageGen, ReadLinkedURLGen), (ReadLinkedURLGen, LinkedURLGen), (PrintPageGen, ReadStartPageSummaryGen), (ReadStartPageSummaryGen, StartPageSummaryGen), (StartPageSummaryGen, FetchStartPageGen), (StartPageSummaryGen, ReadStartURLGen), (PrintLinkedPageGen, ReadLinkedPageSummaryGen), (ReadLinkedPageSummaryGen, LinkedPageSummaryGen), (LinkedPageSummaryGen, FetchLinkedPageGen), (LinkedPageSummaryGen, ReadLinkedURLGen)]
  , SDK.graphScopes = [OpenCrawlSessionGen]
  , SDK.graphScopePaths = [[OpenCrawlSessionGen], []]
  , SDK.graphRootPaths =
      [ (FetchStartPageGen, [[OpenCrawlSessionGen]])
      , (FetchLinkedPageGen, [[OpenCrawlSessionGen]])
      , (PrintPageGen, [[], [OpenCrawlSessionGen]])
      , (PrintLinkedPageGen, [[], [OpenCrawlSessionGen]])
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
  , SDK.scopePaths = [[OpenCrawlSessionGen], []]
  , SDK.scopeCandidates = []
  , SDK.scopeOpposed = []
  , SDK.scopeUndetermined = []
  }
