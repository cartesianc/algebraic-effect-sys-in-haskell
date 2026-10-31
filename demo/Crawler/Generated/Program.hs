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


-- 仅汇总所选末端的成功产物，不保存共享绑定或增加完成包装。
data Results = FetchPageResult (Produce FetchPage) | FetchLinkedPageResult (Produce FetchLinkedPage) | PrintPageResult (Produce PrintPage) | PrintLinkedPageResult (Produce PrintLinkedPage)
  deriving Show

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
interpreter = SDK.interpreter "Crawler" Handlers.handlerSourceFingerprint generatedPrototype compiledEntries
-- 生成时完成注册、方法、origin/ctx 链、资产来源、Workflow 和 scope 的统一分析。
-- NodeId 只在这份 AST 快照中有效；运行时校验后装配闭包。
generatedPrototype :: SDK.Prototype MethodGen
generatedPrototype =
  SDK.Prototype
    { SDK.protoRegistrations =
        [ SDK.EffectSpec
            { SDK.name = "StartPage"
            , SDK.typing = SDK.Context (Just (SDK.Requester ("startURL") (SDK.TypeRef ("PageURL"))))
            , SDK.input = "Root"
            , SDK.demands = []
            }
        , SDK.EffectSpec
            { SDK.name = "LinkedPage"
            , SDK.typing = SDK.Context (Just (SDK.Requester ("linkedURL") (SDK.TypeRef ("PageURL"))))
            , SDK.input = "Root"
            , SDK.demands = []
            }
        , SDK.EffectSpec
            { SDK.name = "FetchPage"
            , SDK.typing = SDK.Excu (Just "fetchStartPage")
            , SDK.input = "CrawlSession"
            , SDK.demands =
                [SDK.Demand (SDK.RequestAccess) ("StartURL"), SDK.Demand (SDK.RequireAccess) ("CrawlSessionInfo")]
            }
        , SDK.EffectSpec
            { SDK.name = "ExtractPage"
            , SDK.typing =
                SDK.Context (Just (SDK.Requester ("startPageSummary") (SDK.TypeRef ("PageSummary"))))
            , SDK.input = "FetchPage"
            , SDK.demands = [SDK.Demand (SDK.RequireAccess) ("StartURL")]
            }
        , SDK.EffectSpec
            { SDK.name = "PrintPage"
            , SDK.typing = SDK.Excu (Just "printPage")
            , SDK.input = "Root"
            , SDK.demands = [SDK.Demand (SDK.RequireAccess) ("StartPageSummary")]
            }
        , SDK.EffectSpec
            { SDK.name = "FetchLinkedPage"
            , SDK.typing = SDK.Excu (Just "fetchLinkedPage")
            , SDK.input = "CrawlSession"
            , SDK.demands =
                [SDK.Demand (SDK.RequestAccess) ("LinkedURL"), SDK.Demand (SDK.RequireAccess) ("CrawlSessionInfo")]
            }
        , SDK.EffectSpec
            { SDK.name = "ExtractLinkedPage"
            , SDK.typing =
                SDK.Context (Just (SDK.Requester ("linkedPageSummary") (SDK.TypeRef ("PageSummary"))))
            , SDK.input = "FetchLinkedPage"
            , SDK.demands = [SDK.Demand (SDK.RequireAccess) ("LinkedURL")]
            }
        , SDK.EffectSpec
            { SDK.name = "PrintLinkedPage"
            , SDK.typing = SDK.Excu (Just "printLinkedPage")
            , SDK.input = "Root"
            , SDK.demands = [SDK.Demand (SDK.RequireAccess) ("LinkedPageSummary")]
            }
        , SDK.EffectSpec
            { SDK.name = "SessionContext"
            , SDK.typing =
                SDK.Context (Just (SDK.Requester ("crawlSessionInfo") (SDK.TypeRef ("SessionInfo"))))
            , SDK.input = "Root"
            , SDK.demands = []
            }
        , SDK.EffectSpec
            { SDK.name = "CrawlSession"
            , SDK.typing = SDK.Scoped (Just "openCrawlSession") (Just "closeCrawlSession")
            , SDK.input = "Root"
            , SDK.demands =
                [ SDK.Demand (SDK.RequestAccess) ("CrawlSessionInfo")
                , SDK.Demand (SDK.RequireAccess) ("CrawlSessionInfo")
                ]
            }
        ]
    , SDK.protoEffects =
        [ SDK.EffectProto
            { SDK.effectName = "StartPage"
            , SDK.effectKind = SDK.ContextKind
            , SDK.effectInput = "Root"
            , SDK.effectMethods = [(SDK.ContextRequest, StartURLGen), (SDK.ContextRequire, ReadStartURLGen)]
            , SDK.effectDemands = []
            , SDK.effectProduces = Just "StartURL"
            , SDK.effectBranches = []
            , SDK.effectAnchor = Nothing
            , SDK.effectScopes = []
            , SDK.effectErrorScope = Nothing
            , SDK.effectInputChain = []
            , SDK.effectScopeParents = []
            , SDK.effectOpeningInputs = []
            , SDK.effectNearestScopes = []
            , SDK.effectResource = Nothing
            , SDK.effectContextDependencies = []
            }
        , SDK.EffectProto
            { SDK.effectName = "LinkedPage"
            , SDK.effectKind = SDK.ContextKind
            , SDK.effectInput = "Root"
            , SDK.effectMethods = [(SDK.ContextRequest, LinkedURLGen), (SDK.ContextRequire, ReadLinkedURLGen)]
            , SDK.effectDemands = []
            , SDK.effectProduces = Just "LinkedURL"
            , SDK.effectBranches = []
            , SDK.effectAnchor = Nothing
            , SDK.effectScopes = []
            , SDK.effectErrorScope = Nothing
            , SDK.effectInputChain = []
            , SDK.effectScopeParents = []
            , SDK.effectOpeningInputs = []
            , SDK.effectNearestScopes = []
            , SDK.effectResource = Nothing
            , SDK.effectContextDependencies = []
            }
        , SDK.EffectProto
            { SDK.effectName = "FetchPage"
            , SDK.effectKind = SDK.ExcuKind
            , SDK.effectInput = "CrawlSession"
            , SDK.effectMethods = [(SDK.HandlerMethod, FetchStartPageGen)]
            , SDK.effectDemands =
                [ SDK.ResolvedDemand (SDK.RequestAccess) ("StartURL") ("StartPage")
                , SDK.ResolvedDemand (SDK.RequireAccess) ("CrawlSessionInfo") ("SessionContext")
                ]
            , SDK.effectProduces = Nothing
            , SDK.effectBranches = []
            , SDK.effectAnchor = Nothing
            , SDK.effectScopes = ["CrawlSession"]
            , SDK.effectErrorScope = Nothing
            , SDK.effectInputChain = ["CrawlSession"]
            , SDK.effectScopeParents = ["CrawlSession"]
            , SDK.effectOpeningInputs = []
            , SDK.effectNearestScopes = ["CrawlSession"]
            , SDK.effectResource = Nothing
            , SDK.effectContextDependencies = ["SessionContext","StartPage"]
            }
        , SDK.EffectProto
            { SDK.effectName = "ExtractPage"
            , SDK.effectKind = SDK.ContextKind
            , SDK.effectInput = "FetchPage"
            , SDK.effectMethods =
                [(SDK.ContextRequest, StartPageSummaryGen), (SDK.ContextRequire, ReadStartPageSummaryGen)]
            , SDK.effectDemands = [SDK.ResolvedDemand (SDK.RequireAccess) ("StartURL") ("StartPage")]
            , SDK.effectProduces = Just "StartPageSummary"
            , SDK.effectBranches = []
            , SDK.effectAnchor = Just "FetchPage"
            , SDK.effectScopes = ["CrawlSession"]
            , SDK.effectErrorScope = Nothing
            , SDK.effectInputChain = ["FetchPage","CrawlSession"]
            , SDK.effectScopeParents = ["CrawlSession"]
            , SDK.effectOpeningInputs = []
            , SDK.effectNearestScopes = ["CrawlSession"]
            , SDK.effectResource = Nothing
            , SDK.effectContextDependencies = ["SessionContext","StartPage"]
            }
        , SDK.EffectProto
            { SDK.effectName = "PrintPage"
            , SDK.effectKind = SDK.ExcuKind
            , SDK.effectInput = "Root"
            , SDK.effectMethods = [(SDK.HandlerMethod, PrintPageGen)]
            , SDK.effectDemands =
                [SDK.ResolvedDemand (SDK.RequireAccess) ("StartPageSummary") ("ExtractPage")]
            , SDK.effectProduces = Nothing
            , SDK.effectBranches = []
            , SDK.effectAnchor = Nothing
            , SDK.effectScopes = []
            , SDK.effectErrorScope = Nothing
            , SDK.effectInputChain = []
            , SDK.effectScopeParents = ["CrawlSession"]
            , SDK.effectOpeningInputs = []
            , SDK.effectNearestScopes = []
            , SDK.effectResource = Nothing
            , SDK.effectContextDependencies = ["SessionContext","StartPage","ExtractPage"]
            }
        , SDK.EffectProto
            { SDK.effectName = "FetchLinkedPage"
            , SDK.effectKind = SDK.ExcuKind
            , SDK.effectInput = "CrawlSession"
            , SDK.effectMethods = [(SDK.HandlerMethod, FetchLinkedPageGen)]
            , SDK.effectDemands =
                [ SDK.ResolvedDemand (SDK.RequestAccess) ("LinkedURL") ("LinkedPage")
                , SDK.ResolvedDemand (SDK.RequireAccess) ("CrawlSessionInfo") ("SessionContext")
                ]
            , SDK.effectProduces = Nothing
            , SDK.effectBranches = []
            , SDK.effectAnchor = Nothing
            , SDK.effectScopes = ["CrawlSession"]
            , SDK.effectErrorScope = Nothing
            , SDK.effectInputChain = ["CrawlSession"]
            , SDK.effectScopeParents = ["CrawlSession"]
            , SDK.effectOpeningInputs = []
            , SDK.effectNearestScopes = ["CrawlSession"]
            , SDK.effectResource = Nothing
            , SDK.effectContextDependencies = ["SessionContext","LinkedPage"]
            }
        , SDK.EffectProto
            { SDK.effectName = "ExtractLinkedPage"
            , SDK.effectKind = SDK.ContextKind
            , SDK.effectInput = "FetchLinkedPage"
            , SDK.effectMethods =
                [(SDK.ContextRequest, LinkedPageSummaryGen), (SDK.ContextRequire, ReadLinkedPageSummaryGen)]
            , SDK.effectDemands = [SDK.ResolvedDemand (SDK.RequireAccess) ("LinkedURL") ("LinkedPage")]
            , SDK.effectProduces = Just "LinkedPageSummary"
            , SDK.effectBranches = []
            , SDK.effectAnchor = Just "FetchLinkedPage"
            , SDK.effectScopes = ["CrawlSession"]
            , SDK.effectErrorScope = Nothing
            , SDK.effectInputChain = ["FetchLinkedPage","CrawlSession"]
            , SDK.effectScopeParents = ["CrawlSession"]
            , SDK.effectOpeningInputs = []
            , SDK.effectNearestScopes = ["CrawlSession"]
            , SDK.effectResource = Nothing
            , SDK.effectContextDependencies = ["SessionContext","LinkedPage"]
            }
        , SDK.EffectProto
            { SDK.effectName = "PrintLinkedPage"
            , SDK.effectKind = SDK.ExcuKind
            , SDK.effectInput = "Root"
            , SDK.effectMethods = [(SDK.HandlerMethod, PrintLinkedPageGen)]
            , SDK.effectDemands =
                [SDK.ResolvedDemand (SDK.RequireAccess) ("LinkedPageSummary") ("ExtractLinkedPage")]
            , SDK.effectProduces = Nothing
            , SDK.effectBranches = []
            , SDK.effectAnchor = Nothing
            , SDK.effectScopes = []
            , SDK.effectErrorScope = Nothing
            , SDK.effectInputChain = []
            , SDK.effectScopeParents = ["CrawlSession"]
            , SDK.effectOpeningInputs = []
            , SDK.effectNearestScopes = []
            , SDK.effectResource = Nothing
            , SDK.effectContextDependencies = ["SessionContext","LinkedPage","ExtractLinkedPage"]
            }
        , SDK.EffectProto
            { SDK.effectName = "SessionContext"
            , SDK.effectKind = SDK.ContextKind
            , SDK.effectInput = "Root"
            , SDK.effectMethods =
                [(SDK.ContextRequest, CrawlSessionInfoGen), (SDK.ContextRequire, ReadCrawlSessionInfoGen)]
            , SDK.effectDemands = []
            , SDK.effectProduces = Just "CrawlSessionInfo"
            , SDK.effectBranches = []
            , SDK.effectAnchor = Nothing
            , SDK.effectScopes = []
            , SDK.effectErrorScope = Nothing
            , SDK.effectInputChain = []
            , SDK.effectScopeParents = []
            , SDK.effectOpeningInputs = []
            , SDK.effectNearestScopes = []
            , SDK.effectResource = Nothing
            , SDK.effectContextDependencies = []
            }
        , SDK.EffectProto
            { SDK.effectName = "CrawlSession"
            , SDK.effectKind = SDK.ScopedKind
            , SDK.effectInput = "Root"
            , SDK.effectMethods =
                [(SDK.ScopeOpen, OpenCrawlSessionGen), (SDK.ScopeClose, CloseCrawlSessionGen)]
            , SDK.effectDemands =
                [ SDK.ResolvedDemand (SDK.RequestAccess) ("CrawlSessionInfo") ("SessionContext")
                , SDK.ResolvedDemand (SDK.RequireAccess) ("CrawlSessionInfo") ("SessionContext")
                ]
            , SDK.effectProduces = Nothing
            , SDK.effectBranches = []
            , SDK.effectAnchor = Nothing
            , SDK.effectScopes = []
            , SDK.effectErrorScope = Nothing
            , SDK.effectInputChain = []
            , SDK.effectScopeParents = []
            , SDK.effectOpeningInputs = []
            , SDK.effectNearestScopes = ["CrawlSession"]
            , SDK.effectResource = Just "SessionContext"
            , SDK.effectContextDependencies = ["SessionContext"]
            }
        ]
    , SDK.protoMethods =
        [ SDK.MethodDefinition (StartURLGen) (StartURLGen) (SDK.ContextRequest) (SDK.Empty)
        , SDK.MethodDefinition
            (ReadStartURLGen)
            (StartURLGen)
            (SDK.ContextRequire)
            (SDK.Choice ([SDK.Empty, SDK.Call (StartURLGen)]))
        , SDK.MethodDefinition (LinkedURLGen) (LinkedURLGen) (SDK.ContextRequest) (SDK.Empty)
        , SDK.MethodDefinition
            (ReadLinkedURLGen)
            (LinkedURLGen)
            (SDK.ContextRequire)
            (SDK.Choice ([SDK.Empty, SDK.Call (LinkedURLGen)]))
        , SDK.MethodDefinition
            (FetchStartPageGen)
            (FetchStartPageGen)
            (SDK.HandlerMethod)
            (
              SDK.Sequence
                (
                  [ SDK.Sequence
                      ([SDK.Call (OpenCrawlSessionGen), SDK.Call (StartURLGen), SDK.Call (ReadCrawlSessionInfoGen)])
                  , SDK.Choice ([SDK.Empty, SDK.Sequence ([SDK.Sequence ([SDK.Empty, SDK.Call (ReadStartURLGen)])])])
                  ]
                )
            )
        , SDK.MethodDefinition
            (StartPageSummaryGen)
            (StartPageSummaryGen)
            (SDK.ContextRequest)
            (SDK.Sequence ([SDK.Call (FetchStartPageGen), SDK.Call (ReadStartURLGen)]))
        , SDK.MethodDefinition
            (ReadStartPageSummaryGen)
            (StartPageSummaryGen)
            (SDK.ContextRequire)
            (SDK.Choice ([SDK.Empty, SDK.Call (StartPageSummaryGen)]))
        , SDK.MethodDefinition
            (PrintPageGen)
            (PrintPageGen)
            (SDK.HandlerMethod)
            (SDK.Call (ReadStartPageSummaryGen))
        , SDK.MethodDefinition
            (FetchLinkedPageGen)
            (FetchLinkedPageGen)
            (SDK.HandlerMethod)
            (
              SDK.Sequence
                (
                  [ SDK.Sequence
                      ([SDK.Call (OpenCrawlSessionGen), SDK.Call (LinkedURLGen), SDK.Call (ReadCrawlSessionInfoGen)])
                  , SDK.Choice ([SDK.Empty, SDK.Sequence ([SDK.Sequence ([SDK.Empty, SDK.Call (ReadLinkedURLGen)])])])
                  ]
                )
            )
        , SDK.MethodDefinition
            (LinkedPageSummaryGen)
            (LinkedPageSummaryGen)
            (SDK.ContextRequest)
            (SDK.Sequence ([SDK.Call (FetchLinkedPageGen), SDK.Call (ReadLinkedURLGen)]))
        , SDK.MethodDefinition
            (ReadLinkedPageSummaryGen)
            (LinkedPageSummaryGen)
            (SDK.ContextRequire)
            (SDK.Choice ([SDK.Empty, SDK.Call (LinkedPageSummaryGen)]))
        , SDK.MethodDefinition
            (PrintLinkedPageGen)
            (PrintLinkedPageGen)
            (SDK.HandlerMethod)
            (SDK.Call (ReadLinkedPageSummaryGen))
        , SDK.MethodDefinition (CrawlSessionInfoGen) (CrawlSessionInfoGen) (SDK.ContextRequest) (SDK.Empty)
        , SDK.MethodDefinition
            (ReadCrawlSessionInfoGen)
            (CrawlSessionInfoGen)
            (SDK.ContextRequire)
            (SDK.Empty)
        , SDK.MethodDefinition
            (OpenCrawlSessionGen)
            (OpenCrawlSessionGen)
            (SDK.ScopeOpen)
            (SDK.Call (CrawlSessionInfoGen))
        , SDK.MethodDefinition
            (CloseCrawlSessionGen)
            (OpenCrawlSessionGen)
            (SDK.ScopeClose)
            (SDK.Call (ReadCrawlSessionInfoGen))
        ]
    , SDK.protoWorkflow =
        SDK.ChainedAt
          ([])
          (
            [ SDK.ParallelAt
                ([0])
                (
                  [ SDK.NodeAt ([0,0]) ("FetchPage")
                  , SDK.NodeAt ([0,1]) ("FetchLinkedPage")
                  ]
                )
            , SDK.ChainedAt
                ([1])
                (
                  [ SDK.NodeAt ([1,0]) ("PrintPage")
                  , SDK.NodeAt ([1,1]) ("PrintLinkedPage")
                  ]
                )
            ]
          )
    , SDK.protoChains =
        [ SDK.ChainProto
            { SDK.chainNode = [0,0]
            , SDK.chainRole = SDK.NodeChain
            , SDK.chainTerminal = "FetchPage"
            , SDK.chainEntry = FetchStartPageGen
            , SDK.chainReaches =
                [ FetchStartPageGen
                , OpenCrawlSessionGen
                , CrawlSessionInfoGen
                , StartURLGen
                , ReadCrawlSessionInfoGen
                , ReadStartURLGen
                , StartPageSummaryGen
                ]
            , SDK.chainDrives = ["StartPageSummary","StartURL"]
            , SDK.chainReads = []
            , SDK.chainScopePaths = [[OpenCrawlSessionGen]]
            }
        , SDK.ChainProto
            { SDK.chainNode = [0,1]
            , SDK.chainRole = SDK.NodeChain
            , SDK.chainTerminal = "FetchLinkedPage"
            , SDK.chainEntry = FetchLinkedPageGen
            , SDK.chainReaches =
                [ FetchLinkedPageGen
                , OpenCrawlSessionGen
                , CrawlSessionInfoGen
                , LinkedURLGen
                , ReadCrawlSessionInfoGen
                , ReadLinkedURLGen
                , LinkedPageSummaryGen
                ]
            , SDK.chainDrives = ["LinkedPageSummary","LinkedURL"]
            , SDK.chainReads = []
            , SDK.chainScopePaths = [[OpenCrawlSessionGen]]
            }
        , SDK.ChainProto
            { SDK.chainNode = [1,0]
            , SDK.chainRole = SDK.NodeChain
            , SDK.chainTerminal = "PrintPage"
            , SDK.chainEntry = PrintPageGen
            , SDK.chainReaches =
                [ PrintPageGen
                , ReadStartPageSummaryGen
                , StartPageSummaryGen
                , FetchStartPageGen
                , OpenCrawlSessionGen
                , CrawlSessionInfoGen
                , StartURLGen
                , ReadCrawlSessionInfoGen
                , ReadStartURLGen
                ]
            , SDK.chainDrives = ["StartPageSummary","StartURL"]
            , SDK.chainReads = ["StartPageSummary"]
            , SDK.chainScopePaths = [[], [OpenCrawlSessionGen]]
            }
        , SDK.ChainProto
            { SDK.chainNode = [1,1]
            , SDK.chainRole = SDK.NodeChain
            , SDK.chainTerminal = "PrintLinkedPage"
            , SDK.chainEntry = PrintLinkedPageGen
            , SDK.chainReaches =
                [ PrintLinkedPageGen
                , ReadLinkedPageSummaryGen
                , LinkedPageSummaryGen
                , FetchLinkedPageGen
                , OpenCrawlSessionGen
                , CrawlSessionInfoGen
                , LinkedURLGen
                , ReadCrawlSessionInfoGen
                , ReadLinkedURLGen
                ]
            , SDK.chainDrives = ["LinkedPageSummary","LinkedURL"]
            , SDK.chainReads = ["LinkedPageSummary"]
            , SDK.chainScopePaths = [[], [OpenCrawlSessionGen]]
            }
        ]
    , SDK.protoChainDefinitions =
        [ SDK.ChainDefinition
            { SDK.definitionKind = SDK.ContextChain
            , SDK.definitionEffect = "StartPage"
            , SDK.definitionEntry = StartURLGen
            , SDK.definitionReaches = [StartURLGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.ContextChain
            , SDK.definitionEffect = "StartPage"
            , SDK.definitionEntry = ReadStartURLGen
            , SDK.definitionReaches = [ReadStartURLGen, StartURLGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.ContextChain
            , SDK.definitionEffect = "LinkedPage"
            , SDK.definitionEntry = LinkedURLGen
            , SDK.definitionReaches = [LinkedURLGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.ContextChain
            , SDK.definitionEffect = "LinkedPage"
            , SDK.definitionEntry = ReadLinkedURLGen
            , SDK.definitionReaches = [ReadLinkedURLGen, LinkedURLGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.OriginChain
            , SDK.definitionEffect = "FetchPage"
            , SDK.definitionEntry = FetchStartPageGen
            , SDK.definitionReaches =
                [ FetchStartPageGen
                , OpenCrawlSessionGen
                , CrawlSessionInfoGen
                , StartURLGen
                , ReadCrawlSessionInfoGen
                , ReadStartURLGen
                , StartPageSummaryGen
                ]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.ContextChain
            , SDK.definitionEffect = "ExtractPage"
            , SDK.definitionEntry = StartPageSummaryGen
            , SDK.definitionReaches =
                [ StartPageSummaryGen
                , FetchStartPageGen
                , OpenCrawlSessionGen
                , CrawlSessionInfoGen
                , StartURLGen
                , ReadCrawlSessionInfoGen
                , ReadStartURLGen
                ]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.ContextChain
            , SDK.definitionEffect = "ExtractPage"
            , SDK.definitionEntry = ReadStartPageSummaryGen
            , SDK.definitionReaches =
                [ ReadStartPageSummaryGen
                , StartPageSummaryGen
                , FetchStartPageGen
                , OpenCrawlSessionGen
                , CrawlSessionInfoGen
                , StartURLGen
                , ReadCrawlSessionInfoGen
                , ReadStartURLGen
                ]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.OriginChain
            , SDK.definitionEffect = "PrintPage"
            , SDK.definitionEntry = PrintPageGen
            , SDK.definitionReaches =
                [ PrintPageGen
                , ReadStartPageSummaryGen
                , StartPageSummaryGen
                , FetchStartPageGen
                , OpenCrawlSessionGen
                , CrawlSessionInfoGen
                , StartURLGen
                , ReadCrawlSessionInfoGen
                , ReadStartURLGen
                ]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.OriginChain
            , SDK.definitionEffect = "FetchLinkedPage"
            , SDK.definitionEntry = FetchLinkedPageGen
            , SDK.definitionReaches =
                [ FetchLinkedPageGen
                , OpenCrawlSessionGen
                , CrawlSessionInfoGen
                , LinkedURLGen
                , ReadCrawlSessionInfoGen
                , ReadLinkedURLGen
                , LinkedPageSummaryGen
                ]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.ContextChain
            , SDK.definitionEffect = "ExtractLinkedPage"
            , SDK.definitionEntry = LinkedPageSummaryGen
            , SDK.definitionReaches =
                [ LinkedPageSummaryGen
                , FetchLinkedPageGen
                , OpenCrawlSessionGen
                , CrawlSessionInfoGen
                , LinkedURLGen
                , ReadCrawlSessionInfoGen
                , ReadLinkedURLGen
                ]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.ContextChain
            , SDK.definitionEffect = "ExtractLinkedPage"
            , SDK.definitionEntry = ReadLinkedPageSummaryGen
            , SDK.definitionReaches =
                [ ReadLinkedPageSummaryGen
                , LinkedPageSummaryGen
                , FetchLinkedPageGen
                , OpenCrawlSessionGen
                , CrawlSessionInfoGen
                , LinkedURLGen
                , ReadCrawlSessionInfoGen
                , ReadLinkedURLGen
                ]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.OriginChain
            , SDK.definitionEffect = "PrintLinkedPage"
            , SDK.definitionEntry = PrintLinkedPageGen
            , SDK.definitionReaches =
                [ PrintLinkedPageGen
                , ReadLinkedPageSummaryGen
                , LinkedPageSummaryGen
                , FetchLinkedPageGen
                , OpenCrawlSessionGen
                , CrawlSessionInfoGen
                , LinkedURLGen
                , ReadCrawlSessionInfoGen
                , ReadLinkedURLGen
                ]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.ContextChain
            , SDK.definitionEffect = "SessionContext"
            , SDK.definitionEntry = CrawlSessionInfoGen
            , SDK.definitionReaches = [CrawlSessionInfoGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.ContextChain
            , SDK.definitionEffect = "SessionContext"
            , SDK.definitionEntry = ReadCrawlSessionInfoGen
            , SDK.definitionReaches = [ReadCrawlSessionInfoGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.OriginChain
            , SDK.definitionEffect = "CrawlSession"
            , SDK.definitionEntry = OpenCrawlSessionGen
            , SDK.definitionReaches = [OpenCrawlSessionGen, CrawlSessionInfoGen]
            }
        ]
    , SDK.protoGraph =
        SDK.EffectGraph
          { SDK.graphMethods =
              [ SDK.MethodDefinition
                  (FetchStartPageGen)
                  (FetchStartPageGen)
                  (SDK.HandlerMethod)
                  (
                    SDK.Sequence
                      (
                        [ SDK.Sequence
                            ([SDK.Call (OpenCrawlSessionGen), SDK.Call (StartURLGen), SDK.Call (ReadCrawlSessionInfoGen)])
                        , SDK.Choice ([SDK.Empty, SDK.Sequence ([SDK.Sequence ([SDK.Empty, SDK.Call (ReadStartURLGen)])])])
                        ]
                      )
                  )
              , SDK.MethodDefinition
                  (OpenCrawlSessionGen)
                  (OpenCrawlSessionGen)
                  (SDK.ScopeOpen)
                  (SDK.Call (CrawlSessionInfoGen))
              , SDK.MethodDefinition (CrawlSessionInfoGen) (CrawlSessionInfoGen) (SDK.ContextRequest) (SDK.Empty)
              , SDK.MethodDefinition (StartURLGen) (StartURLGen) (SDK.ContextRequest) (SDK.Empty)
              , SDK.MethodDefinition
                  (ReadCrawlSessionInfoGen)
                  (CrawlSessionInfoGen)
                  (SDK.ContextRequire)
                  (SDK.Empty)
              , SDK.MethodDefinition
                  (ReadStartURLGen)
                  (StartURLGen)
                  (SDK.ContextRequire)
                  (SDK.Choice ([SDK.Empty, SDK.Call (StartURLGen)]))
              , SDK.MethodDefinition
                  (FetchLinkedPageGen)
                  (FetchLinkedPageGen)
                  (SDK.HandlerMethod)
                  (
                    SDK.Sequence
                      (
                        [ SDK.Sequence
                            ([SDK.Call (OpenCrawlSessionGen), SDK.Call (LinkedURLGen), SDK.Call (ReadCrawlSessionInfoGen)])
                        , SDK.Choice ([SDK.Empty, SDK.Sequence ([SDK.Sequence ([SDK.Empty, SDK.Call (ReadLinkedURLGen)])])])
                        ]
                      )
                  )
              , SDK.MethodDefinition (LinkedURLGen) (LinkedURLGen) (SDK.ContextRequest) (SDK.Empty)
              , SDK.MethodDefinition
                  (ReadLinkedURLGen)
                  (LinkedURLGen)
                  (SDK.ContextRequire)
                  (SDK.Choice ([SDK.Empty, SDK.Call (LinkedURLGen)]))
              , SDK.MethodDefinition
                  (PrintPageGen)
                  (PrintPageGen)
                  (SDK.HandlerMethod)
                  (SDK.Call (ReadStartPageSummaryGen))
              , SDK.MethodDefinition
                  (ReadStartPageSummaryGen)
                  (StartPageSummaryGen)
                  (SDK.ContextRequire)
                  (SDK.Choice ([SDK.Empty, SDK.Call (StartPageSummaryGen)]))
              , SDK.MethodDefinition
                  (StartPageSummaryGen)
                  (StartPageSummaryGen)
                  (SDK.ContextRequest)
                  (SDK.Sequence ([SDK.Call (FetchStartPageGen), SDK.Call (ReadStartURLGen)]))
              , SDK.MethodDefinition
                  (PrintLinkedPageGen)
                  (PrintLinkedPageGen)
                  (SDK.HandlerMethod)
                  (SDK.Call (ReadLinkedPageSummaryGen))
              , SDK.MethodDefinition
                  (ReadLinkedPageSummaryGen)
                  (LinkedPageSummaryGen)
                  (SDK.ContextRequire)
                  (SDK.Choice ([SDK.Empty, SDK.Call (LinkedPageSummaryGen)]))
              , SDK.MethodDefinition
                  (LinkedPageSummaryGen)
                  (LinkedPageSummaryGen)
                  (SDK.ContextRequest)
                  (SDK.Sequence ([SDK.Call (FetchLinkedPageGen), SDK.Call (ReadLinkedURLGen)]))
              ]
          , SDK.graphRoots = [FetchStartPageGen, FetchLinkedPageGen, PrintPageGen, PrintLinkedPageGen]
          , SDK.graphReferences =
              [ (FetchStartPageGen, OpenCrawlSessionGen)
              , (FetchStartPageGen, StartURLGen)
              , (FetchStartPageGen, ReadCrawlSessionInfoGen)
              , (FetchStartPageGen, ReadStartURLGen)
              , (OpenCrawlSessionGen, CrawlSessionInfoGen)
              , (ReadStartURLGen, StartURLGen)
              , (FetchLinkedPageGen, OpenCrawlSessionGen)
              , (FetchLinkedPageGen, LinkedURLGen)
              , (FetchLinkedPageGen, ReadCrawlSessionInfoGen)
              , (FetchLinkedPageGen, ReadLinkedURLGen)
              , (ReadLinkedURLGen, LinkedURLGen)
              , (PrintPageGen, ReadStartPageSummaryGen)
              , (ReadStartPageSummaryGen, StartPageSummaryGen)
              , (StartPageSummaryGen, FetchStartPageGen)
              , (StartPageSummaryGen, ReadStartURLGen)
              , (PrintLinkedPageGen, ReadLinkedPageSummaryGen)
              , (ReadLinkedPageSummaryGen, LinkedPageSummaryGen)
              , (LinkedPageSummaryGen, FetchLinkedPageGen)
              , (LinkedPageSummaryGen, ReadLinkedURLGen)
              ]
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
    , SDK.protoScopes =
        SDK.ScopeTree
          { SDK.scopeRoots = [OpenCrawlSessionGen]
          , SDK.scopeNodes =
              [ SDK.ScopeNode
                  { SDK.scopeIdentity = OpenCrawlSessionGen
                  , SDK.scopeParents = []
                  , SDK.scopeChildren = []
                  }
              ]
          , SDK.scopeLayers = [[OpenCrawlSessionGen]]
          , SDK.scopePaths = [[OpenCrawlSessionGen], []]
          , SDK.scopeCandidates = []
          , SDK.scopeOpposed = []
          , SDK.scopeUndetermined = []
          }
    , SDK.protoScopeNames = [(OpenCrawlSessionGen, "CrawlSession")]
    , SDK.protoSources =
        [ (SDK.ReadPoint ([1,1]) ("LinkedPageSummary"), SDK.FromChains ([[0,1]]))
        , (SDK.ReadPoint ([1,0]) ("StartPageSummary"), SDK.FromChains ([[0,0]]))
        ]
    }
