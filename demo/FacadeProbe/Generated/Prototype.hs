{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE TypeApplications #-}

-- 自动生成；gen 编译出的静态结构，由 Program 交给 interpreter，运行前校验。
module FacadeProbe.Generated.Prototype (generatedPrototype) where

import qualified Framework.Generated as SDK
import qualified FacadeProbe.Types as AssetTypes
import FacadeProbe.Generated.Effects (MethodGen(..))

-- 生成时完成注册、方法、origin/ctx 链、资产来源、Workflow 和 scope 的统一分析。
-- NodeId 只在这份 AST 快照中有效；运行时校验后装配闭包。
generatedPrototype :: SDK.Prototype MethodGen
generatedPrototype =
  SDK.Prototype
    { SDK.protoRegistrations =
        [ SDK.EffectSpec
            { SDK.name = "ReportLocation"
            , SDK.typing =
                SDK.Context (SDK.AssetDecl "ReportPath" (SDK.typeRef @[Char])) (Just "reportLocation") True False
            , SDK.input = "Root"
            , SDK.demands = []
            }
        , SDK.EffectSpec
            { SDK.name = "ReplyLocation"
            , SDK.typing =
                SDK.Context (SDK.AssetDecl "ReplyPath" (SDK.typeRef @[Char])) (Just "replyLocation") True False
            , SDK.input = "Root"
            , SDK.demands = []
            }
        , SDK.EffectSpec
            { SDK.name = "ReportDraft"
            , SDK.typing =
                SDK.Context
                  (SDK.AssetDecl "ReportBody" (SDK.typeRef @AssetTypes.Body))
                  (Just "reportDraft")
                  True
                  False
            , SDK.input = "Root"
            , SDK.demands = []
            }
        , SDK.EffectSpec
            { SDK.name = "ReplyDraft"
            , SDK.typing =
                SDK.Context
                  (SDK.AssetDecl "ReplyBody" (SDK.typeRef @AssetTypes.Body))
                  (Just "replyDraft")
                  True
                  False
            , SDK.input = "Root"
            , SDK.demands = []
            }
        , SDK.EffectSpec
            { SDK.name = "ReportFile"
            , SDK.typing =
                SDK.Context
                  (SDK.AssetDecl "OpenedReport" (SDK.typeRef @AssetTypes.TextFile))
                  (Just "acquireFile")
                  True
                  False
            , SDK.input = "Root"
            , SDK.demands =
                [SDK.Demand SDK.RequestAccess "ReportPath", SDK.Demand SDK.RequireAccess "ReportPath"]
            }
        , SDK.EffectSpec
            { SDK.name = "ReplyFile"
            , SDK.typing =
                SDK.Context
                  (SDK.AssetDecl "OpenedReply" (SDK.typeRef @AssetTypes.TextFile))
                  (Just "acquireFile")
                  True
                  False
            , SDK.input = "Root"
            , SDK.demands =
                [SDK.Demand SDK.RequestAccess "ReplyPath", SDK.Demand SDK.RequireAccess "ReplyPath"]
            }
        , SDK.EffectSpec
            { SDK.name = "ReportScope"
            , SDK.typing = SDK.Scoped (Just "openTextFile") (Just "closeTextFile")
            , SDK.input = "Root"
            , SDK.demands =
                [SDK.Demand SDK.RequestAccess "OpenedReport", SDK.Demand SDK.RequireAccess "OpenedReport"]
            }
        , SDK.EffectSpec
            { SDK.name = "ReplyScope"
            , SDK.typing = SDK.Scoped (Just "openTextFile") (Just "closeTextFile")
            , SDK.input = "Root"
            , SDK.demands =
                [SDK.Demand SDK.RequestAccess "OpenedReply", SDK.Demand SDK.RequireAccess "OpenedReply"]
            }
        , SDK.EffectSpec
            { SDK.name = "WriteReport"
            , SDK.typing = SDK.Excu (Just "writeText")
            , SDK.input = "ReportScope"
            , SDK.demands =
                [ SDK.Demand SDK.RequestAccess "ReportBody"
                , SDK.Demand SDK.RequireAccess "OpenedReport"
                , SDK.Demand SDK.RequireAccess "ReportBody"
                ]
            }
        , SDK.EffectSpec
            { SDK.name = "WriteReply"
            , SDK.typing = SDK.Excu (Just "writeText")
            , SDK.input = "ReplyScope"
            , SDK.demands =
                [ SDK.Demand SDK.RequestAccess "ReplyBody"
                , SDK.Demand SDK.RequireAccess "OpenedReply"
                , SDK.Demand SDK.RequireAccess "ReplyBody"
                ]
            }
        , SDK.EffectSpec
            { SDK.name = "MarkReply"
            , SDK.typing = SDK.Excu (Just "markRead")
            , SDK.input = "Root"
            , SDK.demands = []
            }
        , SDK.EffectSpec
            { SDK.name = "ReadReport"
            , SDK.typing = SDK.Excu (Just "readText")
            , SDK.input = "Root"
            , SDK.demands = [SDK.Demand SDK.RequireAccess "ReportPath"]
            }
        , SDK.EffectSpec
            { SDK.name = "ReadReply"
            , SDK.typing = SDK.Excu (Just "readText")
            , SDK.input = "MarkReply"
            , SDK.demands = [SDK.Demand SDK.RequireAccess "ReplyPath"]
            }
        , SDK.EffectSpec
            { SDK.name = "ReportCounter"
            , SDK.typing =
                SDK.Context
                  (SDK.AssetDecl "ReportStats" (SDK.typeRef @AssetTypes.LineCount))
                  (Just "countLines")
                  True
                  False
            , SDK.input = "ReadReport"
            , SDK.demands = []
            }
        , SDK.EffectSpec
            { SDK.name = "ReplyCounter"
            , SDK.typing =
                SDK.Context
                  (SDK.AssetDecl "ReplyStats" (SDK.typeRef @AssetTypes.LineCount))
                  (Just "countLines")
                  True
                  False
            , SDK.input = "ReadReply"
            , SDK.demands = []
            }
        , SDK.EffectSpec
            { SDK.name = "ShowReport"
            , SDK.typing = SDK.Excu (Just "showCount")
            , SDK.input = "Root"
            , SDK.demands = [SDK.Demand SDK.RequireAccess "ReportStats"]
            }
        , SDK.EffectSpec
            { SDK.name = "ShowReply"
            , SDK.typing = SDK.Excu (Just "showCount")
            , SDK.input = "Root"
            , SDK.demands = [SDK.Demand SDK.RequireAccess "ReplyStats"]
            }
        , SDK.EffectSpec
            { SDK.name = "InspectReport"
            , SDK.typing = SDK.Excu (Just "inspectFile")
            , SDK.input = "Root"
            , SDK.demands = [SDK.Demand SDK.RequireAccess "ReportPath"]
            }
        , SDK.EffectSpec
            { SDK.name = "ReportBlank"
            , SDK.typing =
                SDK.Context
                  (SDK.AssetDecl "ReportEmpty" (SDK.typeRef @AssetTypes.EmptyReport))
                  (Just "parseBlankReport")
                  True
                  False
            , SDK.input = "InspectReport"
            , SDK.demands = []
            }
        , SDK.EffectSpec
            { SDK.name = "ReportFilled"
            , SDK.typing =
                SDK.Context
                  (SDK.AssetDecl "ReportText" (SDK.typeRef @AssetTypes.Body))
                  (Just "parseFilledReport")
                  True
                  False
            , SDK.input = "InspectReport"
            , SDK.demands = []
            }
        , SDK.EffectSpec
            { SDK.name = "OnBlank"
            , SDK.typing = SDK.Excu (Just "describeBlank")
            , SDK.input = "Root"
            , SDK.demands = [SDK.Demand SDK.RequireAccess "ReportEmpty"]
            }
        , SDK.EffectSpec
            { SDK.name = "OnFilled"
            , SDK.typing = SDK.Excu (Just "describeFilled")
            , SDK.input = "Root"
            , SDK.demands = [SDK.Demand SDK.RequireAccess "ReportText"]
            }
        , SDK.EffectSpec
            { SDK.name = "FeedA"
            , SDK.typing = SDK.Stream (Just "nextA")
            , SDK.input = "Root"
            , SDK.demands = []
            }
        , SDK.EffectSpec
            { SDK.name = "FeedB"
            , SDK.typing = SDK.Stream (Just "nextB")
            , SDK.input = "Root"
            , SDK.demands = []
            }
        , SDK.EffectSpec
            { SDK.name = "ParserA"
            , SDK.typing =
                SDK.Context (SDK.AssetDecl "LevelA" (SDK.typeRef @AssetTypes.Level)) (Just "parseLevel") True True
            , SDK.input = "FeedA"
            , SDK.demands = []
            }
        , SDK.EffectSpec
            { SDK.name = "ParserB"
            , SDK.typing =
                SDK.Context (SDK.AssetDecl "LevelB" (SDK.typeRef @AssetTypes.Level)) (Just "parseLevel") True True
            , SDK.input = "FeedB"
            , SDK.demands = []
            }
        , SDK.EffectSpec
            { SDK.name = "ShowA"
            , SDK.typing = SDK.Excu (Just "showLevel")
            , SDK.input = "Root"
            , SDK.demands = [SDK.Demand SDK.StreamAccess "LevelA"]
            }
        , SDK.EffectSpec
            { SDK.name = "ShowB"
            , SDK.typing = SDK.Excu (Just "showLevel")
            , SDK.input = "Root"
            , SDK.demands = [SDK.Demand SDK.StreamAccess "LevelB"]
            }
        ]
    , SDK.protoEffects =
        [ (SDK.effectProto "ReportLocation" SDK.ContextKind "Root")
            { SDK.effectMethods =
                [(SDK.ContextRequest, GetReportPathGen), (SDK.ContextRequire, ReadReportPathGen)]
            , SDK.effectProduces = Just "ReportPath"
            }
        , (SDK.effectProto "ReplyLocation" SDK.ContextKind "Root")
            { SDK.effectMethods =
                [(SDK.ContextRequest, GetReplyPathGen), (SDK.ContextRequire, ReadReplyPathGen)]
            , SDK.effectProduces = Just "ReplyPath"
            }
        , (SDK.effectProto "ReportDraft" SDK.ContextKind "Root")
            { SDK.effectMethods =
                [(SDK.ContextRequest, GetReportBodyGen), (SDK.ContextRequire, ReadReportBodyGen)]
            , SDK.effectProduces = Just "ReportBody"
            }
        , (SDK.effectProto "ReplyDraft" SDK.ContextKind "Root")
            { SDK.effectMethods =
                [(SDK.ContextRequest, GetReplyBodyGen), (SDK.ContextRequire, ReadReplyBodyGen)]
            , SDK.effectProduces = Just "ReplyBody"
            }
        , (SDK.effectProto "ReportFile" SDK.ContextKind "Root")
            { SDK.effectMethods =
                [(SDK.ContextRequest, GetOpenedReportGen), (SDK.ContextRequire, ReadOpenedReportGen)]
            , SDK.effectDemands =
                [ SDK.ResolvedDemand SDK.RequestAccess "ReportPath" "ReportLocation"
                , SDK.ResolvedDemand SDK.RequireAccess "ReportPath" "ReportLocation"
                ]
            , SDK.effectProduces = Just "OpenedReport"
            , SDK.effectContextDependencies = ["ReportLocation"]
            }
        , (SDK.effectProto "ReplyFile" SDK.ContextKind "Root")
            { SDK.effectMethods =
                [(SDK.ContextRequest, GetOpenedReplyGen), (SDK.ContextRequire, ReadOpenedReplyGen)]
            , SDK.effectDemands =
                [ SDK.ResolvedDemand SDK.RequestAccess "ReplyPath" "ReplyLocation"
                , SDK.ResolvedDemand SDK.RequireAccess "ReplyPath" "ReplyLocation"
                ]
            , SDK.effectProduces = Just "OpenedReply"
            , SDK.effectContextDependencies = ["ReplyLocation"]
            }
        , (SDK.effectProto "ReportScope" SDK.ScopedKind "Root")
            { SDK.effectMethods = [(SDK.ScopeOpen, OpenReportScopeGen), (SDK.ScopeClose, CloseReportScopeGen)]
            , SDK.effectDemands =
                [ SDK.ResolvedDemand SDK.RequestAccess "OpenedReport" "ReportFile"
                , SDK.ResolvedDemand SDK.RequireAccess "OpenedReport" "ReportFile"
                ]
            , SDK.effectOpeningInputs = ["ReportLocation"]
            , SDK.effectNearestScopes = ["ReportScope"]
            , SDK.effectResource = Just "ReportFile"
            , SDK.effectContextDependencies = ["ReportLocation","ReportFile"]
            }
        , (SDK.effectProto "ReplyScope" SDK.ScopedKind "Root")
            { SDK.effectMethods = [(SDK.ScopeOpen, OpenReplyScopeGen), (SDK.ScopeClose, CloseReplyScopeGen)]
            , SDK.effectDemands =
                [ SDK.ResolvedDemand SDK.RequestAccess "OpenedReply" "ReplyFile"
                , SDK.ResolvedDemand SDK.RequireAccess "OpenedReply" "ReplyFile"
                ]
            , SDK.effectOpeningInputs = ["ReplyLocation"]
            , SDK.effectNearestScopes = ["ReplyScope"]
            , SDK.effectResource = Just "ReplyFile"
            , SDK.effectContextDependencies = ["ReplyLocation","ReplyFile"]
            }
        , (SDK.effectProto "WriteReport" SDK.ExcuKind "ReportScope")
            { SDK.effectMethods = [(SDK.HandlerMethod, RunWriteReportGen)]
            , SDK.effectDemands =
                [ SDK.ResolvedDemand SDK.RequestAccess "ReportBody" "ReportDraft"
                , SDK.ResolvedDemand SDK.RequireAccess "OpenedReport" "ReportFile"
                , SDK.ResolvedDemand SDK.RequireAccess "ReportBody" "ReportDraft"
                ]
            , SDK.effectScopes = ["ReportScope"]
            , SDK.effectInputChain = ["ReportScope"]
            , SDK.effectScopeParents = ["ReportScope"]
            , SDK.effectNearestScopes = ["ReportScope"]
            , SDK.effectContextDependencies = ["ReportLocation","ReportFile","ReportDraft"]
            }
        , (SDK.effectProto "WriteReply" SDK.ExcuKind "ReplyScope")
            { SDK.effectMethods = [(SDK.HandlerMethod, RunWriteReplyGen)]
            , SDK.effectDemands =
                [ SDK.ResolvedDemand SDK.RequestAccess "ReplyBody" "ReplyDraft"
                , SDK.ResolvedDemand SDK.RequireAccess "OpenedReply" "ReplyFile"
                , SDK.ResolvedDemand SDK.RequireAccess "ReplyBody" "ReplyDraft"
                ]
            , SDK.effectScopes = ["ReplyScope"]
            , SDK.effectInputChain = ["ReplyScope"]
            , SDK.effectScopeParents = ["ReplyScope"]
            , SDK.effectNearestScopes = ["ReplyScope"]
            , SDK.effectContextDependencies = ["ReplyLocation","ReplyFile","ReplyDraft"]
            }
        , (SDK.effectProto "MarkReply" SDK.ExcuKind "Root")
            { SDK.effectMethods = [(SDK.HandlerMethod, RunMarkReplyGen)]
            }
        , (SDK.effectProto "ReadReport" SDK.ExcuKind "Root")
            { SDK.effectMethods = [(SDK.HandlerMethod, RunReadReportGen)]
            , SDK.effectDemands = [SDK.ResolvedDemand SDK.RequireAccess "ReportPath" "ReportLocation"]
            , SDK.effectContextDependencies = ["ReportLocation"]
            }
        , (SDK.effectProto "ReadReply" SDK.ExcuKind "MarkReply")
            { SDK.effectMethods = [(SDK.HandlerMethod, RunReadReplyGen)]
            , SDK.effectDemands = [SDK.ResolvedDemand SDK.RequireAccess "ReplyPath" "ReplyLocation"]
            , SDK.effectInputChain = ["MarkReply"]
            , SDK.effectContextDependencies = ["ReplyLocation"]
            }
        , (SDK.effectProto "ReportCounter" SDK.ContextKind "ReadReport")
            { SDK.effectMethods =
                [(SDK.ContextRequest, GetReportStatsGen), (SDK.ContextRequire, ReadReportStatsGen)]
            , SDK.effectProduces = Just "ReportStats"
            , SDK.effectAnchor = Just "ReadReport"
            , SDK.effectInputChain = ["ReadReport"]
            , SDK.effectContextDependencies = ["ReportLocation"]
            }
        , (SDK.effectProto "ReplyCounter" SDK.ContextKind "ReadReply")
            { SDK.effectMethods =
                [(SDK.ContextRequest, GetReplyStatsGen), (SDK.ContextRequire, ReadReplyStatsGen)]
            , SDK.effectProduces = Just "ReplyStats"
            , SDK.effectAnchor = Just "ReadReply"
            , SDK.effectInputChain = ["ReadReply","MarkReply"]
            , SDK.effectContextDependencies = ["ReplyLocation"]
            }
        , (SDK.effectProto "ShowReport" SDK.ExcuKind "Root")
            { SDK.effectMethods = [(SDK.HandlerMethod, RunShowReportGen)]
            , SDK.effectDemands = [SDK.ResolvedDemand SDK.RequireAccess "ReportStats" "ReportCounter"]
            , SDK.effectContextDependencies = ["ReportLocation","ReportCounter"]
            }
        , (SDK.effectProto "ShowReply" SDK.ExcuKind "Root")
            { SDK.effectMethods = [(SDK.HandlerMethod, RunShowReplyGen)]
            , SDK.effectDemands = [SDK.ResolvedDemand SDK.RequireAccess "ReplyStats" "ReplyCounter"]
            , SDK.effectContextDependencies = ["ReplyLocation","ReplyCounter"]
            }
        , (SDK.effectProto "InspectReport" SDK.ExcuKind "Root")
            { SDK.effectMethods = [(SDK.HandlerMethod, RunInspectReportGen)]
            , SDK.effectDemands = [SDK.ResolvedDemand SDK.RequireAccess "ReportPath" "ReportLocation"]
            , SDK.effectContextDependencies = ["ReportLocation"]
            }
        , (SDK.effectProto "ReportBlank" SDK.ContextKind "InspectReport")
            { SDK.effectMethods =
                [(SDK.ContextRequest, GetReportEmptyGen), (SDK.ContextRequire, ReadReportEmptyGen)]
            , SDK.effectProduces = Just "ReportEmpty"
            , SDK.effectAnchor = Just "InspectReport"
            , SDK.effectInputChain = ["InspectReport"]
            , SDK.effectContextDependencies = ["ReportLocation"]
            }
        , (SDK.effectProto "ReportFilled" SDK.ContextKind "InspectReport")
            { SDK.effectMethods =
                [(SDK.ContextRequest, GetReportTextGen), (SDK.ContextRequire, ReadReportTextGen)]
            , SDK.effectProduces = Just "ReportText"
            , SDK.effectAnchor = Just "InspectReport"
            , SDK.effectInputChain = ["InspectReport"]
            , SDK.effectContextDependencies = ["ReportLocation"]
            }
        , (SDK.effectProto "OnBlank" SDK.ExcuKind "Root")
            { SDK.effectMethods = [(SDK.HandlerMethod, RunOnBlankGen)]
            , SDK.effectDemands = [SDK.ResolvedDemand SDK.RequireAccess "ReportEmpty" "ReportBlank"]
            , SDK.effectContextDependencies = ["ReportLocation","ReportBlank"]
            }
        , (SDK.effectProto "OnFilled" SDK.ExcuKind "Root")
            { SDK.effectMethods = [(SDK.HandlerMethod, RunOnFilledGen)]
            , SDK.effectDemands = [SDK.ResolvedDemand SDK.RequireAccess "ReportText" "ReportFilled"]
            , SDK.effectContextDependencies = ["ReportLocation","ReportFilled"]
            }
        , (SDK.effectProto "FeedA" SDK.StreamKind "Root")
            { SDK.effectMethods = [(SDK.StreamHandler, NextFeedAGen)]
            }
        , (SDK.effectProto "FeedB" SDK.StreamKind "Root")
            { SDK.effectMethods = [(SDK.StreamHandler, NextFeedBGen)]
            }
        , (SDK.effectProto "ParserA" SDK.ContextKind "FeedA")
            { SDK.effectMethods = [(SDK.ContextStream, GetLevelAGen), (SDK.ContextRequire, StreamLevelAGen)]
            , SDK.effectProduces = Just "LevelA"
            , SDK.effectInputChain = ["FeedA"]
            , SDK.effectContinuous = True
            , SDK.effectHistory = True
            }
        , (SDK.effectProto "ParserB" SDK.ContextKind "FeedB")
            { SDK.effectMethods = [(SDK.ContextStream, GetLevelBGen), (SDK.ContextRequire, StreamLevelBGen)]
            , SDK.effectProduces = Just "LevelB"
            , SDK.effectInputChain = ["FeedB"]
            , SDK.effectContinuous = True
            , SDK.effectHistory = True
            }
        , (SDK.effectProto "ShowA" SDK.ExcuKind "Root")
            { SDK.effectMethods = [(SDK.HandlerMethod, RunShowAGen)]
            , SDK.effectDemands = [SDK.ResolvedDemand SDK.StreamAccess "LevelA" "ParserA"]
            , SDK.effectContextDependencies = ["ParserA"]
            }
        , (SDK.effectProto "ShowB" SDK.ExcuKind "Root")
            { SDK.effectMethods = [(SDK.HandlerMethod, RunShowBGen)]
            , SDK.effectDemands = [SDK.ResolvedDemand SDK.StreamAccess "LevelB" "ParserB"]
            , SDK.effectContextDependencies = ["ParserB"]
            }
        ]
    , SDK.protoMethods =
        [ SDK.MethodDefinition GetReportPathGen GetReportPathGen SDK.ContextRequest SDK.Empty
        , SDK.MethodDefinition ReadReportPathGen GetReportPathGen SDK.ContextRequire SDK.Empty
        , SDK.MethodDefinition GetReplyPathGen GetReplyPathGen SDK.ContextRequest SDK.Empty
        , SDK.MethodDefinition ReadReplyPathGen GetReplyPathGen SDK.ContextRequire SDK.Empty
        , SDK.MethodDefinition GetReportBodyGen GetReportBodyGen SDK.ContextRequest SDK.Empty
        , SDK.MethodDefinition ReadReportBodyGen GetReportBodyGen SDK.ContextRequire SDK.Empty
        , SDK.MethodDefinition GetReplyBodyGen GetReplyBodyGen SDK.ContextRequest SDK.Empty
        , SDK.MethodDefinition ReadReplyBodyGen GetReplyBodyGen SDK.ContextRequire SDK.Empty
        , SDK.MethodDefinition
            GetOpenedReportGen
            GetOpenedReportGen
            SDK.ContextRequest
            (SDK.Sequence [SDK.Call GetReportPathGen, SDK.Call ReadReportPathGen])
        , SDK.MethodDefinition ReadOpenedReportGen GetOpenedReportGen SDK.ContextRequire SDK.Empty
        , SDK.MethodDefinition
            GetOpenedReplyGen
            GetOpenedReplyGen
            SDK.ContextRequest
            (SDK.Sequence [SDK.Call GetReplyPathGen, SDK.Call ReadReplyPathGen])
        , SDK.MethodDefinition ReadOpenedReplyGen GetOpenedReplyGen SDK.ContextRequire SDK.Empty
        , SDK.MethodDefinition
            OpenReportScopeGen
            OpenReportScopeGen
            SDK.ScopeOpen
            (SDK.Sequence [SDK.Call GetOpenedReportGen, SDK.Call ReadOpenedReportGen])
        , SDK.MethodDefinition
            CloseReportScopeGen
            OpenReportScopeGen
            SDK.ScopeClose
            (SDK.Call ReadOpenedReportGen)
        , SDK.MethodDefinition
            OpenReplyScopeGen
            OpenReplyScopeGen
            SDK.ScopeOpen
            (SDK.Sequence [SDK.Call GetOpenedReplyGen, SDK.Call ReadOpenedReplyGen])
        , SDK.MethodDefinition
            CloseReplyScopeGen
            OpenReplyScopeGen
            SDK.ScopeClose
            (SDK.Call ReadOpenedReplyGen)
        , SDK.MethodDefinition
            RunWriteReportGen
            RunWriteReportGen
            SDK.HandlerMethod
            (
              SDK.Sequence
                [ SDK.Call GetReportBodyGen
                , SDK.Call OpenReportScopeGen
                , SDK.Call ReadOpenedReportGen
                , SDK.Call ReadReportBodyGen
                ]
            )
        , SDK.MethodDefinition
            RunWriteReplyGen
            RunWriteReplyGen
            SDK.HandlerMethod
            (
              SDK.Sequence
                [ SDK.Call GetReplyBodyGen
                , SDK.Call OpenReplyScopeGen
                , SDK.Call ReadOpenedReplyGen
                , SDK.Call ReadReplyBodyGen
                ]
            )
        , SDK.MethodDefinition RunMarkReplyGen RunMarkReplyGen SDK.HandlerMethod SDK.Empty
        , SDK.MethodDefinition
            RunReadReportGen
            RunReadReportGen
            SDK.HandlerMethod
            (SDK.Sequence [SDK.Call ReadReportPathGen, SDK.Choice [SDK.Empty, SDK.Sequence [SDK.Empty]]])
        , SDK.MethodDefinition
            RunReadReplyGen
            RunReadReplyGen
            SDK.HandlerMethod
            (
              SDK.Sequence
                [ SDK.Sequence [SDK.Call RunMarkReplyGen, SDK.Call ReadReplyPathGen]
                , SDK.Choice [SDK.Empty, SDK.Sequence [SDK.Empty]]
                ]
            )
        , SDK.MethodDefinition
            GetReportStatsGen
            GetReportStatsGen
            SDK.ContextRequest
            (SDK.Call RunReadReportGen)
        , SDK.MethodDefinition ReadReportStatsGen GetReportStatsGen SDK.ContextRequire SDK.Empty
        , SDK.MethodDefinition GetReplyStatsGen GetReplyStatsGen SDK.ContextRequest (SDK.Call RunReadReplyGen)
        , SDK.MethodDefinition ReadReplyStatsGen GetReplyStatsGen SDK.ContextRequire SDK.Empty
        , SDK.MethodDefinition
            RunShowReportGen
            RunShowReportGen
            SDK.HandlerMethod
            (SDK.Call ReadReportStatsGen)
        , SDK.MethodDefinition RunShowReplyGen RunShowReplyGen SDK.HandlerMethod (SDK.Call ReadReplyStatsGen)
        , SDK.MethodDefinition
            RunInspectReportGen
            RunInspectReportGen
            SDK.HandlerMethod
            (
              SDK.Sequence
                [SDK.Call ReadReportPathGen, SDK.Choice [SDK.Empty, SDK.Sequence [SDK.Empty, SDK.Empty]]]
            )
        , SDK.MethodDefinition
            GetReportEmptyGen
            GetReportEmptyGen
            SDK.ContextRequest
            (SDK.Call RunInspectReportGen)
        , SDK.MethodDefinition ReadReportEmptyGen GetReportEmptyGen SDK.ContextRequire SDK.Empty
        , SDK.MethodDefinition
            GetReportTextGen
            GetReportTextGen
            SDK.ContextRequest
            (SDK.Call RunInspectReportGen)
        , SDK.MethodDefinition ReadReportTextGen GetReportTextGen SDK.ContextRequire SDK.Empty
        , SDK.MethodDefinition RunOnBlankGen RunOnBlankGen SDK.HandlerMethod SDK.Empty
        , SDK.MethodDefinition RunOnFilledGen RunOnFilledGen SDK.HandlerMethod (SDK.Call ReadReportTextGen)
        , SDK.MethodDefinition NextFeedAGen NextFeedAGen SDK.StreamHandler SDK.Empty
        , SDK.MethodDefinition NextFeedBGen NextFeedBGen SDK.StreamHandler SDK.Empty
        , SDK.MethodDefinition GetLevelAGen GetLevelAGen SDK.ContextStream (SDK.Call NextFeedAGen)
        , SDK.MethodDefinition StreamLevelAGen GetLevelAGen SDK.ContextRequire SDK.Empty
        , SDK.MethodDefinition GetLevelBGen GetLevelBGen SDK.ContextStream (SDK.Call NextFeedBGen)
        , SDK.MethodDefinition StreamLevelBGen GetLevelBGen SDK.ContextRequire SDK.Empty
        , SDK.MethodDefinition
            RunShowAGen
            RunShowAGen
            SDK.HandlerMethod
            (SDK.Sequence [SDK.Call StreamLevelAGen, SDK.Call StreamLevelAGen])
        , SDK.MethodDefinition
            RunShowBGen
            RunShowBGen
            SDK.HandlerMethod
            (SDK.Sequence [SDK.Call StreamLevelBGen, SDK.Call StreamLevelBGen])
        ]
    , SDK.protoWorkflow =
        SDK.ChainedAt
          []
          [ SDK.ParallelAt
              [0]
              [ SDK.NodeAt [0,0] "WriteReport"
              , SDK.NodeAt [0,1] "WriteReply"
              ]
          , SDK.ParallelAt
              [1]
              [ SDK.NodeAt [1,0] "ReadReport"
              , SDK.NodeAt [1,1] "ReadReply"
              ]
          , SDK.NodeAt [2] "ShowReport"
          , SDK.NodeAt [3] "ShowReply"
          , SDK.AlternativeAt
              [4]
              (
                SDK.AlternativeProto
                  { SDK.alternativeSource = "InspectReport"
                  , SDK.alternativeSelector = [4,-1]
                  , SDK.alternativeCases = [([4,0],"ReportBlank"),([4,1],"ReportFilled")]
                  }
              )
              [ SDK.NodeAt [4,0] "OnBlank"
              , SDK.NodeAt [4,1] "OnFilled"
              ]
          , SDK.LifelongAt
              [5]
              (
                SDK.LifelongProto
                  { SDK.lifelongUnits = [[5,0],[5,1]]
                  , SDK.lifelongSubscriptions = [([5,0],"LevelA"),([5,1],"LevelB")]
                  , SDK.lifelongSessions =
                      [ SDK.SessionProto
                          { SDK.sessionAsset = "LevelA"
                          , SDK.sessionPlan = SDK.Receive "FeedA"
                          , SDK.sessionMounts = [[5,-1,0,0],[5,-1,0,1]]
                          }
                      , SDK.SessionProto
                          { SDK.sessionAsset = "LevelB"
                          , SDK.sessionPlan = SDK.Receive "FeedB"
                          , SDK.sessionMounts = [[5,-1,1,0],[5,-1,1,1]]
                          }
                      ]
                  }
              )
              [ SDK.NodeAt [5,0] "ShowA"
              , SDK.NodeAt [5,1] "ShowB"
              ]
          ]
    , SDK.protoSessions =
        [ SDK.SessionProto
            { SDK.sessionAsset = "LevelA"
            , SDK.sessionPlan = SDK.Receive "FeedA"
            , SDK.sessionMounts = [[-2,0,0],[-2,0,1]]
            }
        , SDK.SessionProto
            { SDK.sessionAsset = "LevelB"
            , SDK.sessionPlan = SDK.Receive "FeedB"
            , SDK.sessionMounts = [[-2,1,0],[-2,1,1]]
            }
        ]
    , SDK.protoChains =
        [ SDK.ChainProto
            { SDK.chainNode = [0,0]
            , SDK.chainRole = SDK.NodeChain
            , SDK.chainTerminal = "WriteReport"
            , SDK.chainEntry = RunWriteReportGen
            , SDK.chainReaches =
                [ RunWriteReportGen
                , GetReportBodyGen
                , OpenReportScopeGen
                , GetOpenedReportGen
                , GetReportPathGen
                , ReadReportPathGen
                , ReadOpenedReportGen
                , ReadReportBodyGen
                ]
            , SDK.chainDrives = ["ReportBody","ReportPath"]
            , SDK.chainReads = []
            , SDK.chainScopePaths = [[OpenReportScopeGen]]
            }
        , SDK.ChainProto
            { SDK.chainNode = [0,1]
            , SDK.chainRole = SDK.NodeChain
            , SDK.chainTerminal = "WriteReply"
            , SDK.chainEntry = RunWriteReplyGen
            , SDK.chainReaches =
                [ RunWriteReplyGen
                , GetReplyBodyGen
                , OpenReplyScopeGen
                , GetOpenedReplyGen
                , GetReplyPathGen
                , ReadReplyPathGen
                , ReadOpenedReplyGen
                , ReadReplyBodyGen
                ]
            , SDK.chainDrives = ["ReplyBody","ReplyPath"]
            , SDK.chainReads = []
            , SDK.chainScopePaths = [[OpenReplyScopeGen]]
            }
        , SDK.ChainProto
            { SDK.chainNode = [1,0]
            , SDK.chainRole = SDK.NodeChain
            , SDK.chainTerminal = "ReadReport"
            , SDK.chainEntry = RunReadReportGen
            , SDK.chainReaches = [RunReadReportGen, ReadReportPathGen, GetReportStatsGen]
            , SDK.chainDrives = ["ReportStats"]
            , SDK.chainReads = ["ReportPath"]
            , SDK.chainScopePaths = [[]]
            }
        , SDK.ChainProto
            { SDK.chainNode = [1,1]
            , SDK.chainRole = SDK.NodeChain
            , SDK.chainTerminal = "ReadReply"
            , SDK.chainEntry = RunReadReplyGen
            , SDK.chainReaches = [RunReadReplyGen, RunMarkReplyGen, ReadReplyPathGen, GetReplyStatsGen]
            , SDK.chainDrives = ["ReplyStats"]
            , SDK.chainReads = ["ReplyPath"]
            , SDK.chainScopePaths = [[]]
            }
        , SDK.ChainProto
            { SDK.chainNode = [2]
            , SDK.chainRole = SDK.NodeChain
            , SDK.chainTerminal = "ShowReport"
            , SDK.chainEntry = RunShowReportGen
            , SDK.chainReaches = [RunShowReportGen, ReadReportStatsGen]
            , SDK.chainDrives = []
            , SDK.chainReads = ["ReportStats"]
            , SDK.chainScopePaths = [[]]
            }
        , SDK.ChainProto
            { SDK.chainNode = [3]
            , SDK.chainRole = SDK.NodeChain
            , SDK.chainTerminal = "ShowReply"
            , SDK.chainEntry = RunShowReplyGen
            , SDK.chainReaches = [RunShowReplyGen, ReadReplyStatsGen]
            , SDK.chainDrives = []
            , SDK.chainReads = ["ReplyStats"]
            , SDK.chainScopePaths = [[]]
            }
        , SDK.ChainProto
            { SDK.chainNode = [4,0]
            , SDK.chainRole = SDK.NodeChain
            , SDK.chainTerminal = "OnBlank"
            , SDK.chainEntry = RunOnBlankGen
            , SDK.chainReaches = [RunOnBlankGen]
            , SDK.chainDrives = []
            , SDK.chainReads = []
            , SDK.chainScopePaths = [[]]
            }
        , SDK.ChainProto
            { SDK.chainNode = [4,1]
            , SDK.chainRole = SDK.NodeChain
            , SDK.chainTerminal = "OnFilled"
            , SDK.chainEntry = RunOnFilledGen
            , SDK.chainReaches = [RunOnFilledGen, ReadReportTextGen]
            , SDK.chainDrives = []
            , SDK.chainReads = []
            , SDK.chainScopePaths = [[]]
            }
        , SDK.ChainProto
            { SDK.chainNode = [5,0]
            , SDK.chainRole = SDK.NodeChain
            , SDK.chainTerminal = "ShowA"
            , SDK.chainEntry = RunShowAGen
            , SDK.chainReaches = [RunShowAGen, StreamLevelAGen]
            , SDK.chainDrives = []
            , SDK.chainReads = []
            , SDK.chainScopePaths = [[]]
            }
        , SDK.ChainProto
            { SDK.chainNode = [5,1]
            , SDK.chainRole = SDK.NodeChain
            , SDK.chainTerminal = "ShowB"
            , SDK.chainEntry = RunShowBGen
            , SDK.chainReaches = [RunShowBGen, StreamLevelBGen]
            , SDK.chainDrives = []
            , SDK.chainReads = []
            , SDK.chainScopePaths = [[]]
            }
        , SDK.ChainProto
            { SDK.chainNode = [4,-1]
            , SDK.chainRole = SDK.SelectorChain
            , SDK.chainTerminal = "InspectReport"
            , SDK.chainEntry = RunInspectReportGen
            , SDK.chainReaches = [RunInspectReportGen, ReadReportPathGen, GetReportEmptyGen, GetReportTextGen]
            , SDK.chainDrives = ["ReportEmpty","ReportText"]
            , SDK.chainReads = ["ReportEmpty","ReportPath","ReportText"]
            , SDK.chainScopePaths = [[]]
            }
        , SDK.ChainProto
            { SDK.chainNode = [5,-1,0,0]
            , SDK.chainRole = SDK.SessionChain
            , SDK.chainTerminal = "LevelA"
            , SDK.chainEntry = NextFeedAGen
            , SDK.chainReaches = [NextFeedAGen]
            , SDK.chainDrives = []
            , SDK.chainReads = []
            , SDK.chainScopePaths = [[]]
            }
        , SDK.ChainProto
            { SDK.chainNode = [5,-1,0,1]
            , SDK.chainRole = SDK.SessionChain
            , SDK.chainTerminal = "LevelA"
            , SDK.chainEntry = GetLevelAGen
            , SDK.chainReaches = [GetLevelAGen, NextFeedAGen]
            , SDK.chainDrives = ["LevelA"]
            , SDK.chainReads = []
            , SDK.chainScopePaths = [[]]
            }
        , SDK.ChainProto
            { SDK.chainNode = [5,-1,1,0]
            , SDK.chainRole = SDK.SessionChain
            , SDK.chainTerminal = "LevelB"
            , SDK.chainEntry = NextFeedBGen
            , SDK.chainReaches = [NextFeedBGen]
            , SDK.chainDrives = []
            , SDK.chainReads = []
            , SDK.chainScopePaths = [[]]
            }
        , SDK.ChainProto
            { SDK.chainNode = [5,-1,1,1]
            , SDK.chainRole = SDK.SessionChain
            , SDK.chainTerminal = "LevelB"
            , SDK.chainEntry = GetLevelBGen
            , SDK.chainReaches = [GetLevelBGen, NextFeedBGen]
            , SDK.chainDrives = ["LevelB"]
            , SDK.chainReads = []
            , SDK.chainScopePaths = [[]]
            }
        , SDK.ChainProto
            { SDK.chainNode = [-2,0,0]
            , SDK.chainRole = SDK.SessionChain
            , SDK.chainTerminal = "LevelA"
            , SDK.chainEntry = NextFeedAGen
            , SDK.chainReaches = [NextFeedAGen]
            , SDK.chainDrives = []
            , SDK.chainReads = []
            , SDK.chainScopePaths = [[]]
            }
        , SDK.ChainProto
            { SDK.chainNode = [-2,0,1]
            , SDK.chainRole = SDK.SessionChain
            , SDK.chainTerminal = "LevelA"
            , SDK.chainEntry = GetLevelAGen
            , SDK.chainReaches = [GetLevelAGen, NextFeedAGen]
            , SDK.chainDrives = ["LevelA"]
            , SDK.chainReads = []
            , SDK.chainScopePaths = [[]]
            }
        , SDK.ChainProto
            { SDK.chainNode = [-2,1,0]
            , SDK.chainRole = SDK.SessionChain
            , SDK.chainTerminal = "LevelB"
            , SDK.chainEntry = NextFeedBGen
            , SDK.chainReaches = [NextFeedBGen]
            , SDK.chainDrives = []
            , SDK.chainReads = []
            , SDK.chainScopePaths = [[]]
            }
        , SDK.ChainProto
            { SDK.chainNode = [-2,1,1]
            , SDK.chainRole = SDK.SessionChain
            , SDK.chainTerminal = "LevelB"
            , SDK.chainEntry = GetLevelBGen
            , SDK.chainReaches = [GetLevelBGen, NextFeedBGen]
            , SDK.chainDrives = ["LevelB"]
            , SDK.chainReads = []
            , SDK.chainScopePaths = [[]]
            }
        ]
    , SDK.protoChainDefinitions =
        [ SDK.ChainDefinition
            { SDK.definitionKind = SDK.ContextChain
            , SDK.definitionEffect = "ReportLocation"
            , SDK.definitionEntry = GetReportPathGen
            , SDK.definitionReaches = [GetReportPathGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.ContextChain
            , SDK.definitionEffect = "ReportLocation"
            , SDK.definitionEntry = ReadReportPathGen
            , SDK.definitionReaches = [ReadReportPathGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.ContextChain
            , SDK.definitionEffect = "ReplyLocation"
            , SDK.definitionEntry = GetReplyPathGen
            , SDK.definitionReaches = [GetReplyPathGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.ContextChain
            , SDK.definitionEffect = "ReplyLocation"
            , SDK.definitionEntry = ReadReplyPathGen
            , SDK.definitionReaches = [ReadReplyPathGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.ContextChain
            , SDK.definitionEffect = "ReportDraft"
            , SDK.definitionEntry = GetReportBodyGen
            , SDK.definitionReaches = [GetReportBodyGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.ContextChain
            , SDK.definitionEffect = "ReportDraft"
            , SDK.definitionEntry = ReadReportBodyGen
            , SDK.definitionReaches = [ReadReportBodyGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.ContextChain
            , SDK.definitionEffect = "ReplyDraft"
            , SDK.definitionEntry = GetReplyBodyGen
            , SDK.definitionReaches = [GetReplyBodyGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.ContextChain
            , SDK.definitionEffect = "ReplyDraft"
            , SDK.definitionEntry = ReadReplyBodyGen
            , SDK.definitionReaches = [ReadReplyBodyGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.ContextChain
            , SDK.definitionEffect = "ReportFile"
            , SDK.definitionEntry = GetOpenedReportGen
            , SDK.definitionReaches = [GetOpenedReportGen, GetReportPathGen, ReadReportPathGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.ContextChain
            , SDK.definitionEffect = "ReportFile"
            , SDK.definitionEntry = ReadOpenedReportGen
            , SDK.definitionReaches = [ReadOpenedReportGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.ContextChain
            , SDK.definitionEffect = "ReplyFile"
            , SDK.definitionEntry = GetOpenedReplyGen
            , SDK.definitionReaches = [GetOpenedReplyGen, GetReplyPathGen, ReadReplyPathGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.ContextChain
            , SDK.definitionEffect = "ReplyFile"
            , SDK.definitionEntry = ReadOpenedReplyGen
            , SDK.definitionReaches = [ReadOpenedReplyGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.OriginChain
            , SDK.definitionEffect = "ReportScope"
            , SDK.definitionEntry = OpenReportScopeGen
            , SDK.definitionReaches =
                [OpenReportScopeGen, GetOpenedReportGen, GetReportPathGen, ReadReportPathGen, ReadOpenedReportGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.OriginChain
            , SDK.definitionEffect = "ReplyScope"
            , SDK.definitionEntry = OpenReplyScopeGen
            , SDK.definitionReaches =
                [OpenReplyScopeGen, GetOpenedReplyGen, GetReplyPathGen, ReadReplyPathGen, ReadOpenedReplyGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.OriginChain
            , SDK.definitionEffect = "WriteReport"
            , SDK.definitionEntry = RunWriteReportGen
            , SDK.definitionReaches =
                [ RunWriteReportGen
                , GetReportBodyGen
                , OpenReportScopeGen
                , GetOpenedReportGen
                , GetReportPathGen
                , ReadReportPathGen
                , ReadOpenedReportGen
                , ReadReportBodyGen
                ]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.OriginChain
            , SDK.definitionEffect = "WriteReply"
            , SDK.definitionEntry = RunWriteReplyGen
            , SDK.definitionReaches =
                [ RunWriteReplyGen
                , GetReplyBodyGen
                , OpenReplyScopeGen
                , GetOpenedReplyGen
                , GetReplyPathGen
                , ReadReplyPathGen
                , ReadOpenedReplyGen
                , ReadReplyBodyGen
                ]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.OriginChain
            , SDK.definitionEffect = "MarkReply"
            , SDK.definitionEntry = RunMarkReplyGen
            , SDK.definitionReaches = [RunMarkReplyGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.OriginChain
            , SDK.definitionEffect = "ReadReport"
            , SDK.definitionEntry = RunReadReportGen
            , SDK.definitionReaches = [RunReadReportGen, ReadReportPathGen, GetReportStatsGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.OriginChain
            , SDK.definitionEffect = "ReadReply"
            , SDK.definitionEntry = RunReadReplyGen
            , SDK.definitionReaches = [RunReadReplyGen, RunMarkReplyGen, ReadReplyPathGen, GetReplyStatsGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.ContextChain
            , SDK.definitionEffect = "ReportCounter"
            , SDK.definitionEntry = GetReportStatsGen
            , SDK.definitionReaches = [GetReportStatsGen, RunReadReportGen, ReadReportPathGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.ContextChain
            , SDK.definitionEffect = "ReportCounter"
            , SDK.definitionEntry = ReadReportStatsGen
            , SDK.definitionReaches = [ReadReportStatsGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.ContextChain
            , SDK.definitionEffect = "ReplyCounter"
            , SDK.definitionEntry = GetReplyStatsGen
            , SDK.definitionReaches = [GetReplyStatsGen, RunReadReplyGen, RunMarkReplyGen, ReadReplyPathGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.ContextChain
            , SDK.definitionEffect = "ReplyCounter"
            , SDK.definitionEntry = ReadReplyStatsGen
            , SDK.definitionReaches = [ReadReplyStatsGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.OriginChain
            , SDK.definitionEffect = "ShowReport"
            , SDK.definitionEntry = RunShowReportGen
            , SDK.definitionReaches = [RunShowReportGen, ReadReportStatsGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.OriginChain
            , SDK.definitionEffect = "ShowReply"
            , SDK.definitionEntry = RunShowReplyGen
            , SDK.definitionReaches = [RunShowReplyGen, ReadReplyStatsGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.OriginChain
            , SDK.definitionEffect = "InspectReport"
            , SDK.definitionEntry = RunInspectReportGen
            , SDK.definitionReaches =
                [RunInspectReportGen, ReadReportPathGen, GetReportEmptyGen, GetReportTextGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.ContextChain
            , SDK.definitionEffect = "ReportBlank"
            , SDK.definitionEntry = GetReportEmptyGen
            , SDK.definitionReaches =
                [GetReportEmptyGen, RunInspectReportGen, ReadReportPathGen, GetReportTextGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.ContextChain
            , SDK.definitionEffect = "ReportBlank"
            , SDK.definitionEntry = ReadReportEmptyGen
            , SDK.definitionReaches = [ReadReportEmptyGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.ContextChain
            , SDK.definitionEffect = "ReportFilled"
            , SDK.definitionEntry = GetReportTextGen
            , SDK.definitionReaches =
                [GetReportTextGen, RunInspectReportGen, ReadReportPathGen, GetReportEmptyGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.ContextChain
            , SDK.definitionEffect = "ReportFilled"
            , SDK.definitionEntry = ReadReportTextGen
            , SDK.definitionReaches = [ReadReportTextGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.OriginChain
            , SDK.definitionEffect = "OnBlank"
            , SDK.definitionEntry = RunOnBlankGen
            , SDK.definitionReaches = [RunOnBlankGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.OriginChain
            , SDK.definitionEffect = "OnFilled"
            , SDK.definitionEntry = RunOnFilledGen
            , SDK.definitionReaches = [RunOnFilledGen, ReadReportTextGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.ContextChain
            , SDK.definitionEffect = "FeedA"
            , SDK.definitionEntry = NextFeedAGen
            , SDK.definitionReaches = [NextFeedAGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.ContextChain
            , SDK.definitionEffect = "FeedB"
            , SDK.definitionEntry = NextFeedBGen
            , SDK.definitionReaches = [NextFeedBGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.ContextChain
            , SDK.definitionEffect = "ParserA"
            , SDK.definitionEntry = GetLevelAGen
            , SDK.definitionReaches = [GetLevelAGen, NextFeedAGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.ContextChain
            , SDK.definitionEffect = "ParserA"
            , SDK.definitionEntry = StreamLevelAGen
            , SDK.definitionReaches = [StreamLevelAGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.ContextChain
            , SDK.definitionEffect = "ParserB"
            , SDK.definitionEntry = GetLevelBGen
            , SDK.definitionReaches = [GetLevelBGen, NextFeedBGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.ContextChain
            , SDK.definitionEffect = "ParserB"
            , SDK.definitionEntry = StreamLevelBGen
            , SDK.definitionReaches = [StreamLevelBGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.OriginChain
            , SDK.definitionEffect = "ShowA"
            , SDK.definitionEntry = RunShowAGen
            , SDK.definitionReaches = [RunShowAGen, StreamLevelAGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.OriginChain
            , SDK.definitionEffect = "ShowB"
            , SDK.definitionEntry = RunShowBGen
            , SDK.definitionReaches = [RunShowBGen, StreamLevelBGen]
            }
        ]
    , SDK.protoGraph =
        SDK.EffectGraph
          { SDK.graphMethods =
              [ SDK.MethodDefinition
                  RunWriteReportGen
                  RunWriteReportGen
                  SDK.HandlerMethod
                  (
                    SDK.Sequence
                      [ SDK.Call GetReportBodyGen
                      , SDK.Call OpenReportScopeGen
                      , SDK.Call ReadOpenedReportGen
                      , SDK.Call ReadReportBodyGen
                      ]
                  )
              , SDK.MethodDefinition GetReportBodyGen GetReportBodyGen SDK.ContextRequest SDK.Empty
              , SDK.MethodDefinition
                  OpenReportScopeGen
                  OpenReportScopeGen
                  SDK.ScopeOpen
                  (SDK.Sequence [SDK.Call GetOpenedReportGen, SDK.Call ReadOpenedReportGen])
              , SDK.MethodDefinition
                  GetOpenedReportGen
                  GetOpenedReportGen
                  SDK.ContextRequest
                  (SDK.Sequence [SDK.Call GetReportPathGen, SDK.Call ReadReportPathGen])
              , SDK.MethodDefinition GetReportPathGen GetReportPathGen SDK.ContextRequest SDK.Empty
              , SDK.MethodDefinition ReadReportPathGen GetReportPathGen SDK.ContextRequire SDK.Empty
              , SDK.MethodDefinition ReadOpenedReportGen GetOpenedReportGen SDK.ContextRequire SDK.Empty
              , SDK.MethodDefinition ReadReportBodyGen GetReportBodyGen SDK.ContextRequire SDK.Empty
              , SDK.MethodDefinition
                  RunWriteReplyGen
                  RunWriteReplyGen
                  SDK.HandlerMethod
                  (
                    SDK.Sequence
                      [ SDK.Call GetReplyBodyGen
                      , SDK.Call OpenReplyScopeGen
                      , SDK.Call ReadOpenedReplyGen
                      , SDK.Call ReadReplyBodyGen
                      ]
                  )
              , SDK.MethodDefinition GetReplyBodyGen GetReplyBodyGen SDK.ContextRequest SDK.Empty
              , SDK.MethodDefinition
                  OpenReplyScopeGen
                  OpenReplyScopeGen
                  SDK.ScopeOpen
                  (SDK.Sequence [SDK.Call GetOpenedReplyGen, SDK.Call ReadOpenedReplyGen])
              , SDK.MethodDefinition
                  GetOpenedReplyGen
                  GetOpenedReplyGen
                  SDK.ContextRequest
                  (SDK.Sequence [SDK.Call GetReplyPathGen, SDK.Call ReadReplyPathGen])
              , SDK.MethodDefinition GetReplyPathGen GetReplyPathGen SDK.ContextRequest SDK.Empty
              , SDK.MethodDefinition ReadReplyPathGen GetReplyPathGen SDK.ContextRequire SDK.Empty
              , SDK.MethodDefinition ReadOpenedReplyGen GetOpenedReplyGen SDK.ContextRequire SDK.Empty
              , SDK.MethodDefinition ReadReplyBodyGen GetReplyBodyGen SDK.ContextRequire SDK.Empty
              , SDK.MethodDefinition
                  RunReadReportGen
                  RunReadReportGen
                  SDK.HandlerMethod
                  (SDK.Sequence [SDK.Call ReadReportPathGen, SDK.Choice [SDK.Empty, SDK.Sequence [SDK.Empty]]])
              , SDK.MethodDefinition
                  RunReadReplyGen
                  RunReadReplyGen
                  SDK.HandlerMethod
                  (
                    SDK.Sequence
                      [ SDK.Sequence [SDK.Call RunMarkReplyGen, SDK.Call ReadReplyPathGen]
                      , SDK.Choice [SDK.Empty, SDK.Sequence [SDK.Empty]]
                      ]
                  )
              , SDK.MethodDefinition RunMarkReplyGen RunMarkReplyGen SDK.HandlerMethod SDK.Empty
              , SDK.MethodDefinition
                  RunShowReportGen
                  RunShowReportGen
                  SDK.HandlerMethod
                  (SDK.Call ReadReportStatsGen)
              , SDK.MethodDefinition ReadReportStatsGen GetReportStatsGen SDK.ContextRequire SDK.Empty
              , SDK.MethodDefinition RunShowReplyGen RunShowReplyGen SDK.HandlerMethod (SDK.Call ReadReplyStatsGen)
              , SDK.MethodDefinition ReadReplyStatsGen GetReplyStatsGen SDK.ContextRequire SDK.Empty
              , SDK.MethodDefinition RunOnBlankGen RunOnBlankGen SDK.HandlerMethod SDK.Empty
              , SDK.MethodDefinition RunOnFilledGen RunOnFilledGen SDK.HandlerMethod (SDK.Call ReadReportTextGen)
              , SDK.MethodDefinition ReadReportTextGen GetReportTextGen SDK.ContextRequire SDK.Empty
              , SDK.MethodDefinition
                  RunShowAGen
                  RunShowAGen
                  SDK.HandlerMethod
                  (SDK.Sequence [SDK.Call StreamLevelAGen, SDK.Call StreamLevelAGen])
              , SDK.MethodDefinition StreamLevelAGen GetLevelAGen SDK.ContextRequire SDK.Empty
              , SDK.MethodDefinition
                  RunShowBGen
                  RunShowBGen
                  SDK.HandlerMethod
                  (SDK.Sequence [SDK.Call StreamLevelBGen, SDK.Call StreamLevelBGen])
              , SDK.MethodDefinition StreamLevelBGen GetLevelBGen SDK.ContextRequire SDK.Empty
              , SDK.MethodDefinition
                  RunInspectReportGen
                  RunInspectReportGen
                  SDK.HandlerMethod
                  (
                    SDK.Sequence
                      [SDK.Call ReadReportPathGen, SDK.Choice [SDK.Empty, SDK.Sequence [SDK.Empty, SDK.Empty]]]
                  )
              , SDK.MethodDefinition NextFeedAGen NextFeedAGen SDK.StreamHandler SDK.Empty
              , SDK.MethodDefinition GetLevelAGen GetLevelAGen SDK.ContextStream (SDK.Call NextFeedAGen)
              , SDK.MethodDefinition NextFeedBGen NextFeedBGen SDK.StreamHandler SDK.Empty
              , SDK.MethodDefinition GetLevelBGen GetLevelBGen SDK.ContextStream (SDK.Call NextFeedBGen)
              ]
          , SDK.graphRoots =
              [ RunWriteReportGen
              , RunWriteReplyGen
              , RunReadReportGen
              , RunReadReplyGen
              , RunShowReportGen
              , RunShowReplyGen
              , RunOnBlankGen
              , RunOnFilledGen
              , RunShowAGen
              , RunShowBGen
              , RunInspectReportGen
              , NextFeedAGen
              , GetLevelAGen
              , NextFeedBGen
              , GetLevelBGen
              ]
          , SDK.graphReferences =
              [ (RunWriteReportGen, GetReportBodyGen)
              , (RunWriteReportGen, OpenReportScopeGen)
              , (RunWriteReportGen, ReadOpenedReportGen)
              , (RunWriteReportGen, ReadReportBodyGen)
              , (OpenReportScopeGen, GetOpenedReportGen)
              , (OpenReportScopeGen, ReadOpenedReportGen)
              , (GetOpenedReportGen, GetReportPathGen)
              , (GetOpenedReportGen, ReadReportPathGen)
              , (RunWriteReplyGen, GetReplyBodyGen)
              , (RunWriteReplyGen, OpenReplyScopeGen)
              , (RunWriteReplyGen, ReadOpenedReplyGen)
              , (RunWriteReplyGen, ReadReplyBodyGen)
              , (OpenReplyScopeGen, GetOpenedReplyGen)
              , (OpenReplyScopeGen, ReadOpenedReplyGen)
              , (GetOpenedReplyGen, GetReplyPathGen)
              , (GetOpenedReplyGen, ReadReplyPathGen)
              , (RunReadReportGen, ReadReportPathGen)
              , (RunReadReplyGen, RunMarkReplyGen)
              , (RunReadReplyGen, ReadReplyPathGen)
              , (RunShowReportGen, ReadReportStatsGen)
              , (RunShowReplyGen, ReadReplyStatsGen)
              , (RunOnFilledGen, ReadReportTextGen)
              , (RunShowAGen, StreamLevelAGen)
              , (RunShowBGen, StreamLevelBGen)
              , (RunInspectReportGen, ReadReportPathGen)
              , (GetLevelAGen, NextFeedAGen)
              , (GetLevelBGen, NextFeedBGen)
              ]
          , SDK.graphScopes = [OpenReportScopeGen, OpenReplyScopeGen]
          , SDK.graphScopePaths = [[OpenReportScopeGen], [OpenReplyScopeGen], []]
          , SDK.graphRootPaths =
              [ (RunWriteReportGen, [[OpenReportScopeGen]])
              , (RunWriteReplyGen, [[OpenReplyScopeGen]])
              , (RunReadReportGen, [[]])
              , (RunReadReplyGen, [[]])
              , (RunShowReportGen, [[]])
              , (RunShowReplyGen, [[]])
              , (RunOnBlankGen, [[]])
              , (RunOnFilledGen, [[]])
              , (RunShowAGen, [[]])
              , (RunShowBGen, [[]])
              , (RunInspectReportGen, [[]])
              , (NextFeedAGen, [[]])
              , (GetLevelAGen, [[]])
              , (NextFeedBGen, [[]])
              , (GetLevelBGen, [[]])
              ]
          , SDK.graphScopeOrder = []
          }
    , SDK.protoScopes =
        SDK.ScopeTree
          { SDK.scopeRoots = [OpenReportScopeGen, OpenReplyScopeGen]
          , SDK.scopeNodes =
              [ SDK.ScopeNode
                  { SDK.scopeIdentity = OpenReportScopeGen
                  , SDK.scopeParents = []
                  , SDK.scopeChildren = []
                  }
              , SDK.ScopeNode
                  { SDK.scopeIdentity = OpenReplyScopeGen
                  , SDK.scopeParents = []
                  , SDK.scopeChildren = []
                  }
              ]
          , SDK.scopeLayers = [[OpenReportScopeGen, OpenReplyScopeGen]]
          , SDK.scopePaths = [[OpenReportScopeGen], [OpenReplyScopeGen], []]
          , SDK.scopeCandidates = []
          , SDK.scopeOpposed = []
          , SDK.scopeUndetermined = [(OpenReplyScopeGen, OpenReportScopeGen)]
          }
    , SDK.protoScopeNames = [(OpenReportScopeGen, "ReportScope"), (OpenReplyScopeGen, "ReplyScope")]
    , SDK.protoSources =
        [ (SDK.ReadPoint [4,-1] "ReportPath", SDK.FromChains [[0,0]])
        , (SDK.ReadPoint [3] "ReplyStats", SDK.FromChains [[1,1]])
        , (SDK.ReadPoint [2] "ReportStats", SDK.FromChains [[1,0]])
        , (SDK.ReadPoint [1,1] "ReplyPath", SDK.FromChains [[0,1]])
        , (SDK.ReadPoint [1,0] "ReportPath", SDK.FromChains [[0,0]])
        , (SDK.ReadPoint [4,-1] "ReportEmpty", SDK.FromOwnChain)
        , (SDK.ReadPoint [4,-1] "ReportText", SDK.FromOwnChain)
        ]
    , SDK.protoScopeOpenings =
        [ SDK.ScopeOpeningPlan
            { SDK.openingNode = [0,1]
            , SDK.openingScope = "ReplyScope"
            , SDK.openingSources = [("ReplyLocation", SDK.FromChains [[0,1]])]
            , SDK.openingKinds = [SDK.ExecutionMultiple]
            }
        , SDK.ScopeOpeningPlan
            { SDK.openingNode = [0,0]
            , SDK.openingScope = "ReportScope"
            , SDK.openingSources = [("ReportLocation", SDK.FromChains [[0,0]])]
            , SDK.openingKinds = [SDK.ExecutionMultiple]
            }
        ]
    , SDK.protoDriving =
        SDK.DrivingPlan
          { SDK.drivingNodes =
              [ SDK.NodeDrive [] [[0,0],[0,1],[1,0],[1,1],[2],[3],[4,0],[4,1],[5,0],[5,1]] [] Nothing [] [] []
              , SDK.NodeDrive [0] [[0,0],[0,1]] [] Nothing [] [] []
              , SDK.NodeDrive [0,0] [[0,0]] [] Nothing [] [] []
              , SDK.NodeDrive [0,1] [[0,1]] [] Nothing [] [] []
              , SDK.NodeDrive [1] [[1,0],[1,1]] [] Nothing [] [] []
              , SDK.NodeDrive [1,0] [[1,0]] [] Nothing [] [] []
              , SDK.NodeDrive [1,1] [[1,1]] [] Nothing [] [] []
              , SDK.NodeDrive [2] [[2]] [] Nothing [] [] []
              , SDK.NodeDrive [3] [[3]] [] Nothing [] [] []
              , SDK.NodeDrive [4] [[4,0],[4,1]] [] Nothing [] [] []
              , SDK.NodeDrive [4,0] [[4,0]] [] Nothing [[4,-1]] [] []
              , SDK.NodeDrive [4,1] [[4,1]] [] Nothing [[4,-1]] [] []
              , SDK.NodeDrive [5] [[5,0],[5,1]] [] (Just [5]) [] [] []
              , SDK.NodeDrive [5,0] [[5,0]] ["ParserA"] (Just [5]) [] [] []
              , SDK.NodeDrive [5,1] [[5,1]] ["ParserB"] (Just [5]) [] [] []
              , SDK.NodeDrive [4,-1] [] [] Nothing [] [] []
              , SDK.NodeDrive [5,-1,0,0] [] [] (Just [5]) [] [] []
              , SDK.NodeDrive [5,-1,0,1] [] [] (Just [5]) [] [] []
              , SDK.NodeDrive [5,-1,1,0] [] [] (Just [5]) [] [] []
              , SDK.NodeDrive [5,-1,1,1] [] [] (Just [5]) [] [] []
              , SDK.NodeDrive [-2,0,0] [] [] Nothing [] [] []
              , SDK.NodeDrive [-2,0,1] [] [] Nothing [] [] []
              , SDK.NodeDrive [-2,1,0] [] [] Nothing [] [] []
              , SDK.NodeDrive [-2,1,1] [] [] Nothing [] [] []
              ]
          , SDK.drivingUnits =
              [ SDK.UnitDrive [5,0] [[5,0]] [("ParserA", [SDK.ReadAt [5,0]]), ("ParserB", [])] []
              , SDK.UnitDrive [5,1] [[5,1]] [("ParserA", []), ("ParserB", [SDK.ReadAt [5,1]])] []
              ]
          , SDK.drivingSessions =
              [ SDK.SessionDrive Nothing "ParserA" "LevelA" Nothing
              , SDK.SessionDrive Nothing "ParserB" "LevelB" Nothing
              , SDK.SessionDrive (Just [5]) "ParserA" "LevelA" Nothing
              , SDK.SessionDrive (Just [5]) "ParserB" "LevelB" Nothing
              ]
          , SDK.drivingRootNodes = [[0,0],[0,1],[1,0],[1,1],[2],[3],[4,0],[4,1],[5,0],[5,1],[4,-1]]
          , SDK.drivingOutputSites = []
          , SDK.drivingRequests =
              [ ("ReportLocation", GetReportPathGen)
              , ("ReplyLocation", GetReplyPathGen)
              , ("ReportDraft", GetReportBodyGen)
              , ("ReplyDraft", GetReplyBodyGen)
              , ("ReportFile", GetOpenedReportGen)
              , ("ReplyFile", GetOpenedReplyGen)
              , ("ReportCounter", GetReportStatsGen)
              , ("ReplyCounter", GetReplyStatsGen)
              , ("ReportBlank", GetReportEmptyGen)
              , ("ReportFilled", GetReportTextGen)
              , ("ParserA", GetLevelAGen)
              , ("ParserB", GetLevelBGen)
              ]
          , SDK.drivingMiddleware = []
          , SDK.drivingHooks = []
          }
    }
