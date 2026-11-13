{-# LANGUAGE DuplicateRecordFields #-}

-- 自动生成；只登记末端入口与原型，执行由 SDK 的 interpreter 完成。
module Crawler.Generated.Program where

import Framework.Generated (EffectSpec(..), EffectTyping(..), Asset(..), Handles(..), Demand(..), Access(..), TypeRef(..))
import qualified Framework.Generated as SDK
import Crawler.Generated.Effects
import qualified Crawler.Generated.Handlers as Handlers
import Crawler.Types


-- 仅汇总所选末端的成功结果，不保存共享绑定或增加完成包装。
data Results = FetchPageResult () | FetchLinkedPageResult () | PrintPageResult () | PrintLinkedPageResult ()
  deriving Show

-- 末端共享生成的 scope 句柄；只创建空状态，Node algebra 才 lower。
-- 第二个列表是各转折契约的选择末端：驱动资产（持续资产领取本次交付），返回它当前的构造器名。
-- 第三个列表是各持续资产的生产步骤：会话按需启动，Stream 单步取得原始输入，parser 发布一次资产。
compiledEntries :: IO ([SDK.Target ContextValues Errors Results], [SDK.Target ContextValues Errors String]
                     , [(String, SDK.SessionSteps ContextValues Errors)])
compiledEntries = do
  scopes <- Handlers.newScopeHandlers
  pure
    ( [ SDK.targetApp "FetchPage" emptyContexts scopes (SDK.withErrorHandlers Handlers.errorHandlers (SDK.withAnchoredContexts Handlers.contextInjections (SDK.withScopeCleanups Handlers.scopeCleanups (FetchPageResult <$> (() <$ Handlers.runFetchPage)))))
      , SDK.targetApp "FetchLinkedPage" emptyContexts scopes (SDK.withErrorHandlers Handlers.errorHandlers (SDK.withAnchoredContexts Handlers.contextInjections (SDK.withScopeCleanups Handlers.scopeCleanups (FetchLinkedPageResult <$> (() <$ Handlers.runFetchLinkedPage)))))
      , SDK.targetApp "PrintPage" emptyContexts scopes (SDK.withErrorHandlers Handlers.errorHandlers (SDK.withAnchoredContexts Handlers.contextInjections (SDK.withScopeCleanups Handlers.scopeCleanups (PrintPageResult <$> (() <$ Handlers.runPrintPage)))))
      , SDK.targetApp "PrintLinkedPage" emptyContexts scopes (SDK.withErrorHandlers Handlers.errorHandlers (SDK.withAnchoredContexts Handlers.contextInjections (SDK.withScopeCleanups Handlers.scopeCleanups (PrintLinkedPageResult <$> (() <$ Handlers.runPrintLinkedPage)))))
      ]
    , []
    , []
    )

-- SDK 装配入口，不需要用户提供节点执行器或重复选择 handler。
interpreter :: SDK.AST -> [EffectSpec] -> IO ()
interpreter = SDK.interpreter "Crawler" "demo/Crawler/Handlers.hs" Handlers.handlerSourceFingerprint generatedPrototype compiledEntries
-- 生成时完成注册、方法、origin/ctx 链、资产来源、Workflow 和 scope 的统一分析。
-- NodeId 只在这份 AST 快照中有效；运行时校验后装配闭包。
generatedPrototype :: SDK.Prototype MethodGen
generatedPrototype =
  SDK.Prototype
    { SDK.protoRegistrations =
        [ SDK.EffectSpec
            { SDK.name = "StartPage"
            , SDK.typing =
                SDK.Context (SDK.AssetDecl ("StartURL") (SDK.TypeRef ("PageURL"))) (Just "startURL") (True) (False)
            , SDK.input = "Root"
            , SDK.demands = []
            }
        , SDK.EffectSpec
            { SDK.name = "LinkedPage"
            , SDK.typing =
                SDK.Context
                  (SDK.AssetDecl ("LinkedURL") (SDK.TypeRef ("PageURL")))
                  (Just "linkedURL")
                  (True)
                  (False)
            , SDK.input = "Root"
            , SDK.demands = []
            }
        , SDK.EffectSpec
            { SDK.name = "FetchPage"
            , SDK.typing = SDK.Excu (Just "fetchPage")
            , SDK.input = "CrawlSession"
            , SDK.demands =
                [ SDK.Demand (SDK.RequestAccess) ("StartURL")
                , SDK.Demand (SDK.RequireAccess) ("StartURL")
                , SDK.Demand (SDK.RequireAccess) ("CrawlSessionInfo")
                ]
            }
        , SDK.EffectSpec
            { SDK.name = "KeepPageBody"
            , SDK.typing = SDK.Pure (Just "dropBlankBodies")
            , SDK.input = "FetchPage"
            , SDK.demands = []
            }
        , SDK.EffectSpec
            { SDK.name = "ExtractPage"
            , SDK.typing =
                SDK.Context
                  (SDK.AssetDecl ("StartPageSummary") (SDK.TypeRef ("PageSummary")))
                  (Just "extractSummary")
                  (True)
                  (False)
            , SDK.input = "KeepPageBody"
            , SDK.demands = [SDK.Demand (SDK.RequireAccess) ("StartURL")]
            }
        , SDK.EffectSpec
            { SDK.name = "PrintPage"
            , SDK.typing = SDK.Excu (Just "printSummary")
            , SDK.input = "Root"
            , SDK.demands = [SDK.Demand (SDK.RequireAccess) ("StartPageSummary")]
            }
        , SDK.EffectSpec
            { SDK.name = "FetchLinkedPage"
            , SDK.typing = SDK.Excu (Just "fetchPage")
            , SDK.input = "CrawlSession"
            , SDK.demands =
                [ SDK.Demand (SDK.RequestAccess) ("LinkedURL")
                , SDK.Demand (SDK.RequireAccess) ("LinkedURL")
                , SDK.Demand (SDK.RequireAccess) ("CrawlSessionInfo")
                ]
            }
        , SDK.EffectSpec
            { SDK.name = "KeepLinkedPageBody"
            , SDK.typing = SDK.Pure (Just "dropBlankBodies")
            , SDK.input = "FetchLinkedPage"
            , SDK.demands = []
            }
        , SDK.EffectSpec
            { SDK.name = "ExtractLinkedPage"
            , SDK.typing =
                SDK.Context
                  (SDK.AssetDecl ("LinkedPageSummary") (SDK.TypeRef ("PageSummary")))
                  (Just "extractSummary")
                  (True)
                  (False)
            , SDK.input = "KeepLinkedPageBody"
            , SDK.demands = [SDK.Demand (SDK.RequireAccess) ("LinkedURL")]
            }
        , SDK.EffectSpec
            { SDK.name = "PrintLinkedPage"
            , SDK.typing = SDK.Excu (Just "printSummary")
            , SDK.input = "Root"
            , SDK.demands = [SDK.Demand (SDK.RequireAccess) ("LinkedPageSummary")]
            }
        , SDK.EffectSpec
            { SDK.name = "SessionContext"
            , SDK.typing =
                SDK.Context
                  (SDK.AssetDecl ("CrawlSessionInfo") (SDK.TypeRef ("SessionInfo")))
                  (Just "sessionInfo")
                  (True)
                  (False)
            , SDK.input = "Root"
            , SDK.demands = []
            }
        , SDK.EffectSpec
            { SDK.name = "CrawlSession"
            , SDK.typing = SDK.Scoped (Just "openSession") (Just "closeSession")
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
            , SDK.effectMethods =
                [(SDK.ContextRequest, GetStartURLGen), (SDK.ContextRequire, ReadStartURLGen)]
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
            , SDK.effectContinuous = False
            }
        , SDK.EffectProto
            { SDK.effectName = "LinkedPage"
            , SDK.effectKind = SDK.ContextKind
            , SDK.effectInput = "Root"
            , SDK.effectMethods =
                [(SDK.ContextRequest, GetLinkedURLGen), (SDK.ContextRequire, ReadLinkedURLGen)]
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
            , SDK.effectContinuous = False
            }
        , SDK.EffectProto
            { SDK.effectName = "FetchPage"
            , SDK.effectKind = SDK.ExcuKind
            , SDK.effectInput = "CrawlSession"
            , SDK.effectMethods = [(SDK.HandlerMethod, RunFetchPageGen)]
            , SDK.effectDemands =
                [ SDK.ResolvedDemand (SDK.RequestAccess) ("StartURL") ("StartPage")
                , SDK.ResolvedDemand (SDK.RequireAccess) ("StartURL") ("StartPage")
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
            , SDK.effectContinuous = False
            }
        , SDK.EffectProto
            { SDK.effectName = "KeepPageBody"
            , SDK.effectKind = SDK.PureKind
            , SDK.effectInput = "FetchPage"
            , SDK.effectMethods = [(SDK.HandlerMethod, RunKeepPageBodyGen)]
            , SDK.effectDemands = []
            , SDK.effectProduces = Nothing
            , SDK.effectBranches = []
            , SDK.effectAnchor = Nothing
            , SDK.effectScopes = ["CrawlSession"]
            , SDK.effectErrorScope = Nothing
            , SDK.effectInputChain = ["FetchPage","CrawlSession"]
            , SDK.effectScopeParents = ["CrawlSession"]
            , SDK.effectOpeningInputs = []
            , SDK.effectNearestScopes = ["CrawlSession"]
            , SDK.effectResource = Nothing
            , SDK.effectContextDependencies = ["SessionContext","StartPage"]
            , SDK.effectContinuous = False
            }
        , SDK.EffectProto
            { SDK.effectName = "ExtractPage"
            , SDK.effectKind = SDK.ContextKind
            , SDK.effectInput = "KeepPageBody"
            , SDK.effectMethods =
                [(SDK.ContextRequest, GetStartPageSummaryGen), (SDK.ContextRequire, ReadStartPageSummaryGen)]
            , SDK.effectDemands = [SDK.ResolvedDemand (SDK.RequireAccess) ("StartURL") ("StartPage")]
            , SDK.effectProduces = Just "StartPageSummary"
            , SDK.effectBranches = []
            , SDK.effectAnchor = Just "FetchPage"
            , SDK.effectScopes = ["CrawlSession"]
            , SDK.effectErrorScope = Nothing
            , SDK.effectInputChain = ["KeepPageBody","FetchPage","CrawlSession"]
            , SDK.effectScopeParents = ["CrawlSession"]
            , SDK.effectOpeningInputs = []
            , SDK.effectNearestScopes = ["CrawlSession"]
            , SDK.effectResource = Nothing
            , SDK.effectContextDependencies = ["SessionContext","StartPage"]
            , SDK.effectContinuous = False
            }
        , SDK.EffectProto
            { SDK.effectName = "PrintPage"
            , SDK.effectKind = SDK.ExcuKind
            , SDK.effectInput = "Root"
            , SDK.effectMethods = [(SDK.HandlerMethod, RunPrintPageGen)]
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
            , SDK.effectContinuous = False
            }
        , SDK.EffectProto
            { SDK.effectName = "FetchLinkedPage"
            , SDK.effectKind = SDK.ExcuKind
            , SDK.effectInput = "CrawlSession"
            , SDK.effectMethods = [(SDK.HandlerMethod, RunFetchLinkedPageGen)]
            , SDK.effectDemands =
                [ SDK.ResolvedDemand (SDK.RequestAccess) ("LinkedURL") ("LinkedPage")
                , SDK.ResolvedDemand (SDK.RequireAccess) ("LinkedURL") ("LinkedPage")
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
            , SDK.effectContinuous = False
            }
        , SDK.EffectProto
            { SDK.effectName = "KeepLinkedPageBody"
            , SDK.effectKind = SDK.PureKind
            , SDK.effectInput = "FetchLinkedPage"
            , SDK.effectMethods = [(SDK.HandlerMethod, RunKeepLinkedPageBodyGen)]
            , SDK.effectDemands = []
            , SDK.effectProduces = Nothing
            , SDK.effectBranches = []
            , SDK.effectAnchor = Nothing
            , SDK.effectScopes = ["CrawlSession"]
            , SDK.effectErrorScope = Nothing
            , SDK.effectInputChain = ["FetchLinkedPage","CrawlSession"]
            , SDK.effectScopeParents = ["CrawlSession"]
            , SDK.effectOpeningInputs = []
            , SDK.effectNearestScopes = ["CrawlSession"]
            , SDK.effectResource = Nothing
            , SDK.effectContextDependencies = ["SessionContext","LinkedPage"]
            , SDK.effectContinuous = False
            }
        , SDK.EffectProto
            { SDK.effectName = "ExtractLinkedPage"
            , SDK.effectKind = SDK.ContextKind
            , SDK.effectInput = "KeepLinkedPageBody"
            , SDK.effectMethods =
                [(SDK.ContextRequest, GetLinkedPageSummaryGen), (SDK.ContextRequire, ReadLinkedPageSummaryGen)]
            , SDK.effectDemands = [SDK.ResolvedDemand (SDK.RequireAccess) ("LinkedURL") ("LinkedPage")]
            , SDK.effectProduces = Just "LinkedPageSummary"
            , SDK.effectBranches = []
            , SDK.effectAnchor = Just "FetchLinkedPage"
            , SDK.effectScopes = ["CrawlSession"]
            , SDK.effectErrorScope = Nothing
            , SDK.effectInputChain = ["KeepLinkedPageBody","FetchLinkedPage","CrawlSession"]
            , SDK.effectScopeParents = ["CrawlSession"]
            , SDK.effectOpeningInputs = []
            , SDK.effectNearestScopes = ["CrawlSession"]
            , SDK.effectResource = Nothing
            , SDK.effectContextDependencies = ["SessionContext","LinkedPage"]
            , SDK.effectContinuous = False
            }
        , SDK.EffectProto
            { SDK.effectName = "PrintLinkedPage"
            , SDK.effectKind = SDK.ExcuKind
            , SDK.effectInput = "Root"
            , SDK.effectMethods = [(SDK.HandlerMethod, RunPrintLinkedPageGen)]
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
            , SDK.effectContinuous = False
            }
        , SDK.EffectProto
            { SDK.effectName = "SessionContext"
            , SDK.effectKind = SDK.ContextKind
            , SDK.effectInput = "Root"
            , SDK.effectMethods =
                [(SDK.ContextRequest, GetCrawlSessionInfoGen), (SDK.ContextRequire, ReadCrawlSessionInfoGen)]
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
            , SDK.effectContinuous = False
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
            , SDK.effectContinuous = False
            }
        ]
    , SDK.protoMethods =
        [ SDK.MethodDefinition (GetStartURLGen) (GetStartURLGen) (SDK.ContextRequest) (SDK.Empty)
        , SDK.MethodDefinition (ReadStartURLGen) (GetStartURLGen) (SDK.ContextRequire) (SDK.Empty)
        , SDK.MethodDefinition (GetLinkedURLGen) (GetLinkedURLGen) (SDK.ContextRequest) (SDK.Empty)
        , SDK.MethodDefinition (ReadLinkedURLGen) (GetLinkedURLGen) (SDK.ContextRequire) (SDK.Empty)
        , SDK.MethodDefinition
            (RunFetchPageGen)
            (RunFetchPageGen)
            (SDK.HandlerMethod)
            (
              SDK.Sequence
                (
                  [ SDK.Sequence
                      (
                        [ SDK.Call (GetStartURLGen)
                        , SDK.Call (OpenCrawlSessionGen)
                        , SDK.Call (ReadStartURLGen)
                        , SDK.Call (ReadCrawlSessionInfoGen)
                        ]
                      )
                  , SDK.Choice ([SDK.Empty, SDK.Sequence ([SDK.Sequence ([SDK.Empty, SDK.Call (ReadStartURLGen)])])])
                  ]
                )
            )
        , SDK.MethodDefinition
            (RunKeepPageBodyGen)
            (RunKeepPageBodyGen)
            (SDK.HandlerMethod)
            (SDK.Call (RunFetchPageGen))
        , SDK.MethodDefinition
            (GetStartPageSummaryGen)
            (GetStartPageSummaryGen)
            (SDK.ContextRequest)
            (SDK.Sequence ([SDK.Call (RunKeepPageBodyGen), SDK.Call (ReadStartURLGen)]))
        , SDK.MethodDefinition
            (ReadStartPageSummaryGen)
            (GetStartPageSummaryGen)
            (SDK.ContextRequire)
            (SDK.Empty)
        , SDK.MethodDefinition
            (RunPrintPageGen)
            (RunPrintPageGen)
            (SDK.HandlerMethod)
            (SDK.Call (ReadStartPageSummaryGen))
        , SDK.MethodDefinition
            (RunFetchLinkedPageGen)
            (RunFetchLinkedPageGen)
            (SDK.HandlerMethod)
            (
              SDK.Sequence
                (
                  [ SDK.Sequence
                      (
                        [ SDK.Call (GetLinkedURLGen)
                        , SDK.Call (OpenCrawlSessionGen)
                        , SDK.Call (ReadLinkedURLGen)
                        , SDK.Call (ReadCrawlSessionInfoGen)
                        ]
                      )
                  , SDK.Choice ([SDK.Empty, SDK.Sequence ([SDK.Sequence ([SDK.Empty, SDK.Call (ReadLinkedURLGen)])])])
                  ]
                )
            )
        , SDK.MethodDefinition
            (RunKeepLinkedPageBodyGen)
            (RunKeepLinkedPageBodyGen)
            (SDK.HandlerMethod)
            (SDK.Call (RunFetchLinkedPageGen))
        , SDK.MethodDefinition
            (GetLinkedPageSummaryGen)
            (GetLinkedPageSummaryGen)
            (SDK.ContextRequest)
            (SDK.Sequence ([SDK.Call (RunKeepLinkedPageBodyGen), SDK.Call (ReadLinkedURLGen)]))
        , SDK.MethodDefinition
            (ReadLinkedPageSummaryGen)
            (GetLinkedPageSummaryGen)
            (SDK.ContextRequire)
            (SDK.Empty)
        , SDK.MethodDefinition
            (RunPrintLinkedPageGen)
            (RunPrintLinkedPageGen)
            (SDK.HandlerMethod)
            (SDK.Call (ReadLinkedPageSummaryGen))
        , SDK.MethodDefinition
            (GetCrawlSessionInfoGen)
            (GetCrawlSessionInfoGen)
            (SDK.ContextRequest)
            (SDK.Empty)
        , SDK.MethodDefinition
            (ReadCrawlSessionInfoGen)
            (GetCrawlSessionInfoGen)
            (SDK.ContextRequire)
            (SDK.Empty)
        , SDK.MethodDefinition
            (OpenCrawlSessionGen)
            (OpenCrawlSessionGen)
            (SDK.ScopeOpen)
            (SDK.Sequence ([SDK.Call (GetCrawlSessionInfoGen), SDK.Call (ReadCrawlSessionInfoGen)]))
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
    , SDK.protoSessions = []
    , SDK.protoChains =
        [ SDK.ChainProto
            { SDK.chainNode = [0,0]
            , SDK.chainRole = SDK.NodeChain
            , SDK.chainTerminal = "FetchPage"
            , SDK.chainEntry = RunFetchPageGen
            , SDK.chainReaches =
                [ RunFetchPageGen
                , GetStartURLGen
                , OpenCrawlSessionGen
                , GetCrawlSessionInfoGen
                , ReadCrawlSessionInfoGen
                , ReadStartURLGen
                , GetStartPageSummaryGen
                , RunKeepPageBodyGen
                ]
            , SDK.chainDrives = ["StartPageSummary","StartURL"]
            , SDK.chainReads = []
            , SDK.chainScopePaths = [[OpenCrawlSessionGen]]
            }
        , SDK.ChainProto
            { SDK.chainNode = [0,1]
            , SDK.chainRole = SDK.NodeChain
            , SDK.chainTerminal = "FetchLinkedPage"
            , SDK.chainEntry = RunFetchLinkedPageGen
            , SDK.chainReaches =
                [ RunFetchLinkedPageGen
                , GetLinkedURLGen
                , OpenCrawlSessionGen
                , GetCrawlSessionInfoGen
                , ReadCrawlSessionInfoGen
                , ReadLinkedURLGen
                , GetLinkedPageSummaryGen
                , RunKeepLinkedPageBodyGen
                ]
            , SDK.chainDrives = ["LinkedPageSummary","LinkedURL"]
            , SDK.chainReads = []
            , SDK.chainScopePaths = [[OpenCrawlSessionGen]]
            }
        , SDK.ChainProto
            { SDK.chainNode = [1,0]
            , SDK.chainRole = SDK.NodeChain
            , SDK.chainTerminal = "PrintPage"
            , SDK.chainEntry = RunPrintPageGen
            , SDK.chainReaches = [RunPrintPageGen, ReadStartPageSummaryGen]
            , SDK.chainDrives = []
            , SDK.chainReads = ["StartPageSummary"]
            , SDK.chainScopePaths = [[]]
            }
        , SDK.ChainProto
            { SDK.chainNode = [1,1]
            , SDK.chainRole = SDK.NodeChain
            , SDK.chainTerminal = "PrintLinkedPage"
            , SDK.chainEntry = RunPrintLinkedPageGen
            , SDK.chainReaches = [RunPrintLinkedPageGen, ReadLinkedPageSummaryGen]
            , SDK.chainDrives = []
            , SDK.chainReads = ["LinkedPageSummary"]
            , SDK.chainScopePaths = [[]]
            }
        ]
    , SDK.protoChainDefinitions =
        [ SDK.ChainDefinition
            { SDK.definitionKind = SDK.ContextChain
            , SDK.definitionEffect = "StartPage"
            , SDK.definitionEntry = GetStartURLGen
            , SDK.definitionReaches = [GetStartURLGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.ContextChain
            , SDK.definitionEffect = "StartPage"
            , SDK.definitionEntry = ReadStartURLGen
            , SDK.definitionReaches = [ReadStartURLGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.ContextChain
            , SDK.definitionEffect = "LinkedPage"
            , SDK.definitionEntry = GetLinkedURLGen
            , SDK.definitionReaches = [GetLinkedURLGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.ContextChain
            , SDK.definitionEffect = "LinkedPage"
            , SDK.definitionEntry = ReadLinkedURLGen
            , SDK.definitionReaches = [ReadLinkedURLGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.OriginChain
            , SDK.definitionEffect = "FetchPage"
            , SDK.definitionEntry = RunFetchPageGen
            , SDK.definitionReaches =
                [ RunFetchPageGen
                , GetStartURLGen
                , OpenCrawlSessionGen
                , GetCrawlSessionInfoGen
                , ReadCrawlSessionInfoGen
                , ReadStartURLGen
                , GetStartPageSummaryGen
                , RunKeepPageBodyGen
                ]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.OriginChain
            , SDK.definitionEffect = "KeepPageBody"
            , SDK.definitionEntry = RunKeepPageBodyGen
            , SDK.definitionReaches =
                [ RunKeepPageBodyGen
                , RunFetchPageGen
                , GetStartURLGen
                , OpenCrawlSessionGen
                , GetCrawlSessionInfoGen
                , ReadCrawlSessionInfoGen
                , ReadStartURLGen
                , GetStartPageSummaryGen
                ]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.ContextChain
            , SDK.definitionEffect = "ExtractPage"
            , SDK.definitionEntry = GetStartPageSummaryGen
            , SDK.definitionReaches =
                [ GetStartPageSummaryGen
                , RunKeepPageBodyGen
                , RunFetchPageGen
                , GetStartURLGen
                , OpenCrawlSessionGen
                , GetCrawlSessionInfoGen
                , ReadCrawlSessionInfoGen
                , ReadStartURLGen
                ]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.ContextChain
            , SDK.definitionEffect = "ExtractPage"
            , SDK.definitionEntry = ReadStartPageSummaryGen
            , SDK.definitionReaches = [ReadStartPageSummaryGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.OriginChain
            , SDK.definitionEffect = "PrintPage"
            , SDK.definitionEntry = RunPrintPageGen
            , SDK.definitionReaches = [RunPrintPageGen, ReadStartPageSummaryGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.OriginChain
            , SDK.definitionEffect = "FetchLinkedPage"
            , SDK.definitionEntry = RunFetchLinkedPageGen
            , SDK.definitionReaches =
                [ RunFetchLinkedPageGen
                , GetLinkedURLGen
                , OpenCrawlSessionGen
                , GetCrawlSessionInfoGen
                , ReadCrawlSessionInfoGen
                , ReadLinkedURLGen
                , GetLinkedPageSummaryGen
                , RunKeepLinkedPageBodyGen
                ]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.OriginChain
            , SDK.definitionEffect = "KeepLinkedPageBody"
            , SDK.definitionEntry = RunKeepLinkedPageBodyGen
            , SDK.definitionReaches =
                [ RunKeepLinkedPageBodyGen
                , RunFetchLinkedPageGen
                , GetLinkedURLGen
                , OpenCrawlSessionGen
                , GetCrawlSessionInfoGen
                , ReadCrawlSessionInfoGen
                , ReadLinkedURLGen
                , GetLinkedPageSummaryGen
                ]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.ContextChain
            , SDK.definitionEffect = "ExtractLinkedPage"
            , SDK.definitionEntry = GetLinkedPageSummaryGen
            , SDK.definitionReaches =
                [ GetLinkedPageSummaryGen
                , RunKeepLinkedPageBodyGen
                , RunFetchLinkedPageGen
                , GetLinkedURLGen
                , OpenCrawlSessionGen
                , GetCrawlSessionInfoGen
                , ReadCrawlSessionInfoGen
                , ReadLinkedURLGen
                ]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.ContextChain
            , SDK.definitionEffect = "ExtractLinkedPage"
            , SDK.definitionEntry = ReadLinkedPageSummaryGen
            , SDK.definitionReaches = [ReadLinkedPageSummaryGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.OriginChain
            , SDK.definitionEffect = "PrintLinkedPage"
            , SDK.definitionEntry = RunPrintLinkedPageGen
            , SDK.definitionReaches = [RunPrintLinkedPageGen, ReadLinkedPageSummaryGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.ContextChain
            , SDK.definitionEffect = "SessionContext"
            , SDK.definitionEntry = GetCrawlSessionInfoGen
            , SDK.definitionReaches = [GetCrawlSessionInfoGen]
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
            , SDK.definitionReaches = [OpenCrawlSessionGen, GetCrawlSessionInfoGen, ReadCrawlSessionInfoGen]
            }
        ]
    , SDK.protoGraph =
        SDK.EffectGraph
          { SDK.graphMethods =
              [ SDK.MethodDefinition
                  (RunFetchPageGen)
                  (RunFetchPageGen)
                  (SDK.HandlerMethod)
                  (
                    SDK.Sequence
                      (
                        [ SDK.Sequence
                            (
                              [ SDK.Call (GetStartURLGen)
                              , SDK.Call (OpenCrawlSessionGen)
                              , SDK.Call (ReadStartURLGen)
                              , SDK.Call (ReadCrawlSessionInfoGen)
                              ]
                            )
                        , SDK.Choice ([SDK.Empty, SDK.Sequence ([SDK.Sequence ([SDK.Empty, SDK.Call (ReadStartURLGen)])])])
                        ]
                      )
                  )
              , SDK.MethodDefinition (GetStartURLGen) (GetStartURLGen) (SDK.ContextRequest) (SDK.Empty)
              , SDK.MethodDefinition
                  (OpenCrawlSessionGen)
                  (OpenCrawlSessionGen)
                  (SDK.ScopeOpen)
                  (SDK.Sequence ([SDK.Call (GetCrawlSessionInfoGen), SDK.Call (ReadCrawlSessionInfoGen)]))
              , SDK.MethodDefinition
                  (GetCrawlSessionInfoGen)
                  (GetCrawlSessionInfoGen)
                  (SDK.ContextRequest)
                  (SDK.Empty)
              , SDK.MethodDefinition
                  (ReadCrawlSessionInfoGen)
                  (GetCrawlSessionInfoGen)
                  (SDK.ContextRequire)
                  (SDK.Empty)
              , SDK.MethodDefinition (ReadStartURLGen) (GetStartURLGen) (SDK.ContextRequire) (SDK.Empty)
              , SDK.MethodDefinition
                  (RunFetchLinkedPageGen)
                  (RunFetchLinkedPageGen)
                  (SDK.HandlerMethod)
                  (
                    SDK.Sequence
                      (
                        [ SDK.Sequence
                            (
                              [ SDK.Call (GetLinkedURLGen)
                              , SDK.Call (OpenCrawlSessionGen)
                              , SDK.Call (ReadLinkedURLGen)
                              , SDK.Call (ReadCrawlSessionInfoGen)
                              ]
                            )
                        , SDK.Choice ([SDK.Empty, SDK.Sequence ([SDK.Sequence ([SDK.Empty, SDK.Call (ReadLinkedURLGen)])])])
                        ]
                      )
                  )
              , SDK.MethodDefinition (GetLinkedURLGen) (GetLinkedURLGen) (SDK.ContextRequest) (SDK.Empty)
              , SDK.MethodDefinition (ReadLinkedURLGen) (GetLinkedURLGen) (SDK.ContextRequire) (SDK.Empty)
              , SDK.MethodDefinition
                  (RunPrintPageGen)
                  (RunPrintPageGen)
                  (SDK.HandlerMethod)
                  (SDK.Call (ReadStartPageSummaryGen))
              , SDK.MethodDefinition
                  (ReadStartPageSummaryGen)
                  (GetStartPageSummaryGen)
                  (SDK.ContextRequire)
                  (SDK.Empty)
              , SDK.MethodDefinition
                  (RunPrintLinkedPageGen)
                  (RunPrintLinkedPageGen)
                  (SDK.HandlerMethod)
                  (SDK.Call (ReadLinkedPageSummaryGen))
              , SDK.MethodDefinition
                  (ReadLinkedPageSummaryGen)
                  (GetLinkedPageSummaryGen)
                  (SDK.ContextRequire)
                  (SDK.Empty)
              ]
          , SDK.graphRoots =
              [RunFetchPageGen, RunFetchLinkedPageGen, RunPrintPageGen, RunPrintLinkedPageGen]
          , SDK.graphReferences =
              [ (RunFetchPageGen, GetStartURLGen)
              , (RunFetchPageGen, OpenCrawlSessionGen)
              , (RunFetchPageGen, ReadStartURLGen)
              , (RunFetchPageGen, ReadCrawlSessionInfoGen)
              , (OpenCrawlSessionGen, GetCrawlSessionInfoGen)
              , (OpenCrawlSessionGen, ReadCrawlSessionInfoGen)
              , (RunFetchLinkedPageGen, GetLinkedURLGen)
              , (RunFetchLinkedPageGen, OpenCrawlSessionGen)
              , (RunFetchLinkedPageGen, ReadLinkedURLGen)
              , (RunFetchLinkedPageGen, ReadCrawlSessionInfoGen)
              , (RunPrintPageGen, ReadStartPageSummaryGen)
              , (RunPrintLinkedPageGen, ReadLinkedPageSummaryGen)
              ]
          , SDK.graphScopes = [OpenCrawlSessionGen]
          , SDK.graphScopePaths = [[OpenCrawlSessionGen], []]
          , SDK.graphRootPaths =
              [ (RunFetchPageGen, [[OpenCrawlSessionGen]])
              , (RunFetchLinkedPageGen, [[OpenCrawlSessionGen]])
              , (RunPrintPageGen, [[]])
              , (RunPrintLinkedPageGen, [[]])
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
    , SDK.protoScopeOpenings =
        [ SDK.ScopeOpeningPlan
            { SDK.openingNode = [0,1]
            , SDK.openingScope = "CrawlSession"
            , SDK.openingSources = []
            , SDK.openingKinds = [SDK.RegistrationSingleton]
            }
        , SDK.ScopeOpeningPlan
            { SDK.openingNode = [0,0]
            , SDK.openingScope = "CrawlSession"
            , SDK.openingSources = []
            , SDK.openingKinds = [SDK.RegistrationSingleton]
            }
        ]
    }
