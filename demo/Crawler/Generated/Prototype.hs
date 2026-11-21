{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE TypeApplications #-}

-- 自动生成；gen 编译出的静态结构，由 Program 交给 interpreter，运行前校验。
module Crawler.Generated.Prototype (generatedPrototype) where

import qualified Framework.Generated as SDK
import qualified Crawler.Types as AssetTypes
import Crawler.Generated.Effects (MethodGen(..))

-- 生成时完成注册、方法、origin/ctx 链、资产来源、Workflow 和 scope 的统一分析。
-- NodeId 只在这份 AST 快照中有效；运行时校验后装配闭包。
generatedPrototype :: SDK.Prototype MethodGen
generatedPrototype =
  SDK.Prototype
    { SDK.protoRegistrations =
        [ SDK.EffectSpec
            { SDK.name = "StartPage"
            , SDK.typing =
                SDK.Context
                  (SDK.AssetDecl "StartURL" (SDK.typeRef @AssetTypes.PageURL))
                  (Just "startURL")
                  True
                  False
            , SDK.input = "Root"
            , SDK.demands = []
            }
        , SDK.EffectSpec
            { SDK.name = "LinkedPage"
            , SDK.typing =
                SDK.Context
                  (SDK.AssetDecl "LinkedURL" (SDK.typeRef @AssetTypes.PageURL))
                  (Just "linkedURL")
                  True
                  False
            , SDK.input = "Root"
            , SDK.demands = []
            }
        , SDK.EffectSpec
            { SDK.name = "FetchPage"
            , SDK.typing = SDK.Excu (Just "fetchPage")
            , SDK.input = "CrawlSession"
            , SDK.demands =
                [ SDK.Demand SDK.RequestAccess "StartURL"
                , SDK.Demand SDK.RequireAccess "StartURL"
                , SDK.Demand SDK.RequireAccess "CrawlSessionInfo"
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
                  (SDK.AssetDecl "StartPageSummary" (SDK.typeRef @AssetTypes.PageSummary))
                  (Just "extractSummary")
                  True
                  False
            , SDK.input = "KeepPageBody"
            , SDK.demands = [SDK.Demand SDK.RequireAccess "StartURL"]
            }
        , SDK.EffectSpec
            { SDK.name = "PrintPage"
            , SDK.typing = SDK.Excu (Just "printSummary")
            , SDK.input = "Root"
            , SDK.demands = [SDK.Demand SDK.RequireAccess "StartPageSummary"]
            }
        , SDK.EffectSpec
            { SDK.name = "FetchLinkedPage"
            , SDK.typing = SDK.Excu (Just "fetchPage")
            , SDK.input = "CrawlSession"
            , SDK.demands =
                [ SDK.Demand SDK.RequestAccess "LinkedURL"
                , SDK.Demand SDK.RequireAccess "LinkedURL"
                , SDK.Demand SDK.RequireAccess "CrawlSessionInfo"
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
                  (SDK.AssetDecl "LinkedPageSummary" (SDK.typeRef @AssetTypes.PageSummary))
                  (Just "extractSummary")
                  True
                  False
            , SDK.input = "KeepLinkedPageBody"
            , SDK.demands = [SDK.Demand SDK.RequireAccess "LinkedURL"]
            }
        , SDK.EffectSpec
            { SDK.name = "PrintLinkedPage"
            , SDK.typing = SDK.Excu (Just "printSummary")
            , SDK.input = "Root"
            , SDK.demands = [SDK.Demand SDK.RequireAccess "LinkedPageSummary"]
            }
        , SDK.EffectSpec
            { SDK.name = "SessionContext"
            , SDK.typing =
                SDK.Context
                  (SDK.AssetDecl "CrawlSessionInfo" (SDK.typeRef @AssetTypes.SessionInfo))
                  (Just "sessionInfo")
                  True
                  False
            , SDK.input = "Root"
            , SDK.demands = []
            }
        , SDK.EffectSpec
            { SDK.name = "CrawlSession"
            , SDK.typing = SDK.Scoped (Just "openSession") (Just "closeSession")
            , SDK.input = "Root"
            , SDK.demands =
                [SDK.Demand SDK.RequestAccess "CrawlSessionInfo", SDK.Demand SDK.RequireAccess "CrawlSessionInfo"]
            }
        ]
    , SDK.protoEffects =
        [ (SDK.effectProto "StartPage" SDK.ContextKind "Root")
            { SDK.effectMethods =
                [(SDK.ContextRequest, GetStartURLGen), (SDK.ContextRequire, ReadStartURLGen)]
            , SDK.effectProduces = Just "StartURL"
            }
        , (SDK.effectProto "LinkedPage" SDK.ContextKind "Root")
            { SDK.effectMethods =
                [(SDK.ContextRequest, GetLinkedURLGen), (SDK.ContextRequire, ReadLinkedURLGen)]
            , SDK.effectProduces = Just "LinkedURL"
            }
        , (SDK.effectProto "FetchPage" SDK.ExcuKind "CrawlSession")
            { SDK.effectMethods = [(SDK.HandlerMethod, RunFetchPageGen)]
            , SDK.effectDemands =
                [ SDK.ResolvedDemand SDK.RequestAccess "StartURL" "StartPage"
                , SDK.ResolvedDemand SDK.RequireAccess "StartURL" "StartPage"
                , SDK.ResolvedDemand SDK.RequireAccess "CrawlSessionInfo" "SessionContext"
                ]
            , SDK.effectScopes = ["CrawlSession"]
            , SDK.effectInputChain = ["CrawlSession"]
            , SDK.effectScopeParents = ["CrawlSession"]
            , SDK.effectNearestScopes = ["CrawlSession"]
            , SDK.effectContextDependencies = ["SessionContext","StartPage"]
            }
        , (SDK.effectProto "KeepPageBody" SDK.PureKind "FetchPage")
            { SDK.effectMethods = [(SDK.HandlerMethod, RunKeepPageBodyGen)]
            , SDK.effectScopes = ["CrawlSession"]
            , SDK.effectInputChain = ["FetchPage","CrawlSession"]
            , SDK.effectScopeParents = ["CrawlSession"]
            , SDK.effectNearestScopes = ["CrawlSession"]
            , SDK.effectContextDependencies = ["SessionContext","StartPage"]
            }
        , (SDK.effectProto "ExtractPage" SDK.ContextKind "KeepPageBody")
            { SDK.effectMethods =
                [(SDK.ContextRequest, GetStartPageSummaryGen), (SDK.ContextRequire, ReadStartPageSummaryGen)]
            , SDK.effectDemands = [SDK.ResolvedDemand SDK.RequireAccess "StartURL" "StartPage"]
            , SDK.effectProduces = Just "StartPageSummary"
            , SDK.effectAnchor = Just "FetchPage"
            , SDK.effectScopes = ["CrawlSession"]
            , SDK.effectInputChain = ["KeepPageBody","FetchPage","CrawlSession"]
            , SDK.effectScopeParents = ["CrawlSession"]
            , SDK.effectNearestScopes = ["CrawlSession"]
            , SDK.effectContextDependencies = ["SessionContext","StartPage"]
            }
        , (SDK.effectProto "PrintPage" SDK.ExcuKind "Root")
            { SDK.effectMethods = [(SDK.HandlerMethod, RunPrintPageGen)]
            , SDK.effectDemands = [SDK.ResolvedDemand SDK.RequireAccess "StartPageSummary" "ExtractPage"]
            , SDK.effectScopeParents = ["CrawlSession"]
            , SDK.effectContextDependencies = ["SessionContext","StartPage","ExtractPage"]
            }
        , (SDK.effectProto "FetchLinkedPage" SDK.ExcuKind "CrawlSession")
            { SDK.effectMethods = [(SDK.HandlerMethod, RunFetchLinkedPageGen)]
            , SDK.effectDemands =
                [ SDK.ResolvedDemand SDK.RequestAccess "LinkedURL" "LinkedPage"
                , SDK.ResolvedDemand SDK.RequireAccess "LinkedURL" "LinkedPage"
                , SDK.ResolvedDemand SDK.RequireAccess "CrawlSessionInfo" "SessionContext"
                ]
            , SDK.effectScopes = ["CrawlSession"]
            , SDK.effectInputChain = ["CrawlSession"]
            , SDK.effectScopeParents = ["CrawlSession"]
            , SDK.effectNearestScopes = ["CrawlSession"]
            , SDK.effectContextDependencies = ["SessionContext","LinkedPage"]
            }
        , (SDK.effectProto "KeepLinkedPageBody" SDK.PureKind "FetchLinkedPage")
            { SDK.effectMethods = [(SDK.HandlerMethod, RunKeepLinkedPageBodyGen)]
            , SDK.effectScopes = ["CrawlSession"]
            , SDK.effectInputChain = ["FetchLinkedPage","CrawlSession"]
            , SDK.effectScopeParents = ["CrawlSession"]
            , SDK.effectNearestScopes = ["CrawlSession"]
            , SDK.effectContextDependencies = ["SessionContext","LinkedPage"]
            }
        , (SDK.effectProto "ExtractLinkedPage" SDK.ContextKind "KeepLinkedPageBody")
            { SDK.effectMethods =
                [(SDK.ContextRequest, GetLinkedPageSummaryGen), (SDK.ContextRequire, ReadLinkedPageSummaryGen)]
            , SDK.effectDemands = [SDK.ResolvedDemand SDK.RequireAccess "LinkedURL" "LinkedPage"]
            , SDK.effectProduces = Just "LinkedPageSummary"
            , SDK.effectAnchor = Just "FetchLinkedPage"
            , SDK.effectScopes = ["CrawlSession"]
            , SDK.effectInputChain = ["KeepLinkedPageBody","FetchLinkedPage","CrawlSession"]
            , SDK.effectScopeParents = ["CrawlSession"]
            , SDK.effectNearestScopes = ["CrawlSession"]
            , SDK.effectContextDependencies = ["SessionContext","LinkedPage"]
            }
        , (SDK.effectProto "PrintLinkedPage" SDK.ExcuKind "Root")
            { SDK.effectMethods = [(SDK.HandlerMethod, RunPrintLinkedPageGen)]
            , SDK.effectDemands =
                [SDK.ResolvedDemand SDK.RequireAccess "LinkedPageSummary" "ExtractLinkedPage"]
            , SDK.effectScopeParents = ["CrawlSession"]
            , SDK.effectContextDependencies = ["SessionContext","LinkedPage","ExtractLinkedPage"]
            }
        , (SDK.effectProto "SessionContext" SDK.ContextKind "Root")
            { SDK.effectMethods =
                [(SDK.ContextRequest, GetCrawlSessionInfoGen), (SDK.ContextRequire, ReadCrawlSessionInfoGen)]
            , SDK.effectProduces = Just "CrawlSessionInfo"
            }
        , (SDK.effectProto "CrawlSession" SDK.ScopedKind "Root")
            { SDK.effectMethods =
                [(SDK.ScopeOpen, OpenCrawlSessionGen), (SDK.ScopeClose, CloseCrawlSessionGen)]
            , SDK.effectDemands =
                [ SDK.ResolvedDemand SDK.RequestAccess "CrawlSessionInfo" "SessionContext"
                , SDK.ResolvedDemand SDK.RequireAccess "CrawlSessionInfo" "SessionContext"
                ]
            , SDK.effectNearestScopes = ["CrawlSession"]
            , SDK.effectResource = Just "SessionContext"
            , SDK.effectContextDependencies = ["SessionContext"]
            }
        ]
    , SDK.protoMethods =
        [ SDK.MethodDefinition GetStartURLGen GetStartURLGen SDK.ContextRequest SDK.Empty
        , SDK.MethodDefinition ReadStartURLGen GetStartURLGen SDK.ContextRequire SDK.Empty
        , SDK.MethodDefinition GetLinkedURLGen GetLinkedURLGen SDK.ContextRequest SDK.Empty
        , SDK.MethodDefinition ReadLinkedURLGen GetLinkedURLGen SDK.ContextRequire SDK.Empty
        , SDK.MethodDefinition
            RunFetchPageGen
            RunFetchPageGen
            SDK.HandlerMethod
            (
              SDK.Sequence
                [ SDK.Sequence
                    [ SDK.Call GetStartURLGen
                    , SDK.Call OpenCrawlSessionGen
                    , SDK.Call ReadStartURLGen
                    , SDK.Call ReadCrawlSessionInfoGen
                    ]
                , SDK.Choice [SDK.Empty, SDK.Sequence [SDK.Sequence [SDK.Empty, SDK.Call ReadStartURLGen]]]
                ]
            )
        , SDK.MethodDefinition
            RunKeepPageBodyGen
            RunKeepPageBodyGen
            SDK.HandlerMethod
            (SDK.Call RunFetchPageGen)
        , SDK.MethodDefinition
            GetStartPageSummaryGen
            GetStartPageSummaryGen
            SDK.ContextRequest
            (SDK.Sequence [SDK.Call RunKeepPageBodyGen, SDK.Call ReadStartURLGen])
        , SDK.MethodDefinition ReadStartPageSummaryGen GetStartPageSummaryGen SDK.ContextRequire SDK.Empty
        , SDK.MethodDefinition
            RunPrintPageGen
            RunPrintPageGen
            SDK.HandlerMethod
            (SDK.Call ReadStartPageSummaryGen)
        , SDK.MethodDefinition
            RunFetchLinkedPageGen
            RunFetchLinkedPageGen
            SDK.HandlerMethod
            (
              SDK.Sequence
                [ SDK.Sequence
                    [ SDK.Call GetLinkedURLGen
                    , SDK.Call OpenCrawlSessionGen
                    , SDK.Call ReadLinkedURLGen
                    , SDK.Call ReadCrawlSessionInfoGen
                    ]
                , SDK.Choice [SDK.Empty, SDK.Sequence [SDK.Sequence [SDK.Empty, SDK.Call ReadLinkedURLGen]]]
                ]
            )
        , SDK.MethodDefinition
            RunKeepLinkedPageBodyGen
            RunKeepLinkedPageBodyGen
            SDK.HandlerMethod
            (SDK.Call RunFetchLinkedPageGen)
        , SDK.MethodDefinition
            GetLinkedPageSummaryGen
            GetLinkedPageSummaryGen
            SDK.ContextRequest
            (SDK.Sequence [SDK.Call RunKeepLinkedPageBodyGen, SDK.Call ReadLinkedURLGen])
        , SDK.MethodDefinition ReadLinkedPageSummaryGen GetLinkedPageSummaryGen SDK.ContextRequire SDK.Empty
        , SDK.MethodDefinition
            RunPrintLinkedPageGen
            RunPrintLinkedPageGen
            SDK.HandlerMethod
            (SDK.Call ReadLinkedPageSummaryGen)
        , SDK.MethodDefinition GetCrawlSessionInfoGen GetCrawlSessionInfoGen SDK.ContextRequest SDK.Empty
        , SDK.MethodDefinition ReadCrawlSessionInfoGen GetCrawlSessionInfoGen SDK.ContextRequire SDK.Empty
        , SDK.MethodDefinition
            OpenCrawlSessionGen
            OpenCrawlSessionGen
            SDK.ScopeOpen
            (SDK.Sequence [SDK.Call GetCrawlSessionInfoGen, SDK.Call ReadCrawlSessionInfoGen])
        , SDK.MethodDefinition
            CloseCrawlSessionGen
            OpenCrawlSessionGen
            SDK.ScopeClose
            (SDK.Call ReadCrawlSessionInfoGen)
        ]
    , SDK.protoWorkflow =
        SDK.ChainedAt
          []
          [ SDK.ParallelAt
              [0]
              [ SDK.NodeAt [0,0] "FetchPage"
              , SDK.NodeAt [0,1] "FetchLinkedPage"
              ]
          , SDK.NodeAt [1] "PrintPage"
          , SDK.NodeAt [2] "PrintLinkedPage"
          ]
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
            { SDK.chainNode = [1]
            , SDK.chainRole = SDK.NodeChain
            , SDK.chainTerminal = "PrintPage"
            , SDK.chainEntry = RunPrintPageGen
            , SDK.chainReaches = [RunPrintPageGen, ReadStartPageSummaryGen]
            , SDK.chainDrives = []
            , SDK.chainReads = ["StartPageSummary"]
            , SDK.chainScopePaths = [[]]
            }
        , SDK.ChainProto
            { SDK.chainNode = [2]
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
                  RunFetchPageGen
                  RunFetchPageGen
                  SDK.HandlerMethod
                  (
                    SDK.Sequence
                      [ SDK.Sequence
                          [ SDK.Call GetStartURLGen
                          , SDK.Call OpenCrawlSessionGen
                          , SDK.Call ReadStartURLGen
                          , SDK.Call ReadCrawlSessionInfoGen
                          ]
                      , SDK.Choice [SDK.Empty, SDK.Sequence [SDK.Sequence [SDK.Empty, SDK.Call ReadStartURLGen]]]
                      ]
                  )
              , SDK.MethodDefinition GetStartURLGen GetStartURLGen SDK.ContextRequest SDK.Empty
              , SDK.MethodDefinition
                  OpenCrawlSessionGen
                  OpenCrawlSessionGen
                  SDK.ScopeOpen
                  (SDK.Sequence [SDK.Call GetCrawlSessionInfoGen, SDK.Call ReadCrawlSessionInfoGen])
              , SDK.MethodDefinition GetCrawlSessionInfoGen GetCrawlSessionInfoGen SDK.ContextRequest SDK.Empty
              , SDK.MethodDefinition ReadCrawlSessionInfoGen GetCrawlSessionInfoGen SDK.ContextRequire SDK.Empty
              , SDK.MethodDefinition ReadStartURLGen GetStartURLGen SDK.ContextRequire SDK.Empty
              , SDK.MethodDefinition
                  RunFetchLinkedPageGen
                  RunFetchLinkedPageGen
                  SDK.HandlerMethod
                  (
                    SDK.Sequence
                      [ SDK.Sequence
                          [ SDK.Call GetLinkedURLGen
                          , SDK.Call OpenCrawlSessionGen
                          , SDK.Call ReadLinkedURLGen
                          , SDK.Call ReadCrawlSessionInfoGen
                          ]
                      , SDK.Choice [SDK.Empty, SDK.Sequence [SDK.Sequence [SDK.Empty, SDK.Call ReadLinkedURLGen]]]
                      ]
                  )
              , SDK.MethodDefinition GetLinkedURLGen GetLinkedURLGen SDK.ContextRequest SDK.Empty
              , SDK.MethodDefinition ReadLinkedURLGen GetLinkedURLGen SDK.ContextRequire SDK.Empty
              , SDK.MethodDefinition
                  RunPrintPageGen
                  RunPrintPageGen
                  SDK.HandlerMethod
                  (SDK.Call ReadStartPageSummaryGen)
              , SDK.MethodDefinition ReadStartPageSummaryGen GetStartPageSummaryGen SDK.ContextRequire SDK.Empty
              , SDK.MethodDefinition
                  RunPrintLinkedPageGen
                  RunPrintLinkedPageGen
                  SDK.HandlerMethod
                  (SDK.Call ReadLinkedPageSummaryGen)
              , SDK.MethodDefinition ReadLinkedPageSummaryGen GetLinkedPageSummaryGen SDK.ContextRequire SDK.Empty
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
        [ (SDK.ReadPoint [2] "LinkedPageSummary", SDK.FromChains [[0,1]])
        , (SDK.ReadPoint [1] "StartPageSummary", SDK.FromChains [[0,0]])
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
    , SDK.protoDriving =
        SDK.DrivingPlan
          { SDK.drivingNodes =
              [ SDK.NodeDrive [] [[0,0],[0,1],[1],[2]] [] Nothing [] [] []
              , SDK.NodeDrive [0] [[0,0],[0,1]] [] Nothing [] [] []
              , SDK.NodeDrive [0,0] [[0,0]] [] Nothing [] [] []
              , SDK.NodeDrive [0,1] [[0,1]] [] Nothing [] [] []
              , SDK.NodeDrive [1] [[1]] [] Nothing [] [] []
              , SDK.NodeDrive [2] [[2]] [] Nothing [] [] []
              ]
          , SDK.drivingUnits = []
          , SDK.drivingSessions = []
          , SDK.drivingRootNodes = [[0,0],[0,1],[1],[2]]
          , SDK.drivingOutputSites = []
          , SDK.drivingRequests =
              [ ("StartPage", GetStartURLGen)
              , ("LinkedPage", GetLinkedURLGen)
              , ("ExtractPage", GetStartPageSummaryGen)
              , ("ExtractLinkedPage", GetLinkedPageSummaryGen)
              , ("SessionContext", GetCrawlSessionInfoGen)
              ]
          , SDK.drivingMiddleware = []
          , SDK.drivingHooks = []
          }
    }
