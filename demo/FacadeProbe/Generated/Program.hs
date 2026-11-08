{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE TypeFamilies #-}

-- 自动生成；只登记末端句柄，Node algebra 才 lower，业务组合仍在 handler 内。
module FacadeProbe.Generated.Program where

import Framework.SDK (Effect(..), EffectSpec(..), EffectTyping(..), Asset(..), Handles(..), Demand(..), Access(..), TypeRef(..))
import qualified Framework.SDK as SDK
import qualified Framework.Effect.Contract as FrameworkRoot
import FacadeProbe.Generated.Effects hiding (request, require)
import qualified FacadeProbe.Generated.Handlers as Handlers
import FacadeProbe.Types


-- 仅汇总所选末端的成功产物，不保存共享绑定或增加完成包装。
data Results = WriteReportResult (Produce WriteReport) | WriteReplyResult (Produce WriteReply) | ReadReportResult (Produce ReadReport) | ReadReplyResult (Produce ReadReply) | ShowReportResult (Produce ShowReport) | ShowReplyResult (Produce ShowReply) | OnBlankResult (Produce OnBlank) | OnFilledResult (Produce OnFilled) | ShowAResult (Produce ShowA) | ShowBResult (Produce ShowB)
  deriving Show

-- 末端共享生成的 scope 句柄；只创建空状态，Node algebra 才 lower，业务调用仍在 instance 内。
-- 第二个列表是各转折契约的读取末端：按 require 取得资产，返回它当前的构造器名。
-- 第三个列表是各持续资产的生产步骤：会话按需启动，解析器或 request 自己发布一次资产。
compiledEntries :: IO ([SDK.Target ContextValues Errors Results], [SDK.Target ContextValues Errors String]
                     , [(String, SDK.SessionSteps ContextValues Errors)])
compiledEntries = do
  scopes <- Handlers.newScopeHandlers
  pure
    ( [ SDK.targetApp "WriteReport" emptyContexts scopes (FrameworkRoot.withErrorHandlers Handlers.errorHandlers (FrameworkRoot.withAnchoredContexts Handlers.contextInjections (SDK.withScopeCleanups Handlers.scopeCleanups (WriteReportResult <$> (() <$ writeReport)))))
      , SDK.targetApp "WriteReply" emptyContexts scopes (FrameworkRoot.withErrorHandlers Handlers.errorHandlers (FrameworkRoot.withAnchoredContexts Handlers.contextInjections (SDK.withScopeCleanups Handlers.scopeCleanups (WriteReplyResult <$> (() <$ writeReply)))))
      , SDK.targetApp "ReadReport" emptyContexts scopes (FrameworkRoot.withErrorHandlers Handlers.errorHandlers (FrameworkRoot.withAnchoredContexts Handlers.contextInjections (SDK.withScopeCleanups Handlers.scopeCleanups (ReadReportResult <$> (() <$ readReport)))))
      , SDK.targetApp "ReadReply" emptyContexts scopes (FrameworkRoot.withErrorHandlers Handlers.errorHandlers (FrameworkRoot.withAnchoredContexts Handlers.contextInjections (SDK.withScopeCleanups Handlers.scopeCleanups (ReadReplyResult <$> (() <$ readReply)))))
      , SDK.targetApp "ShowReport" emptyContexts scopes (FrameworkRoot.withErrorHandlers Handlers.errorHandlers (FrameworkRoot.withAnchoredContexts Handlers.contextInjections (SDK.withScopeCleanups Handlers.scopeCleanups (ShowReportResult <$> (() <$ showReport)))))
      , SDK.targetApp "ShowReply" emptyContexts scopes (FrameworkRoot.withErrorHandlers Handlers.errorHandlers (FrameworkRoot.withAnchoredContexts Handlers.contextInjections (SDK.withScopeCleanups Handlers.scopeCleanups (ShowReplyResult <$> (() <$ showReply)))))
      , SDK.targetApp "OnBlank" emptyContexts scopes (FrameworkRoot.withErrorHandlers Handlers.errorHandlers (FrameworkRoot.withAnchoredContexts Handlers.contextInjections (SDK.withScopeCleanups Handlers.scopeCleanups (OnBlankResult <$> (() <$ onBlank)))))
      , SDK.targetApp "OnFilled" emptyContexts scopes (FrameworkRoot.withErrorHandlers Handlers.errorHandlers (FrameworkRoot.withAnchoredContexts Handlers.contextInjections (SDK.withScopeCleanups Handlers.scopeCleanups (OnFilledResult <$> (() <$ onFilled)))))
      , SDK.targetApp "ShowA" emptyContexts scopes (FrameworkRoot.withErrorHandlers Handlers.errorHandlers (FrameworkRoot.withAnchoredContexts Handlers.contextInjections (SDK.withScopeCleanups Handlers.scopeCleanups (ShowAResult <$> (() <$ showA)))))
      , SDK.targetApp "ShowB" emptyContexts scopes (FrameworkRoot.withErrorHandlers Handlers.errorHandlers (FrameworkRoot.withAnchoredContexts Handlers.contextInjections (SDK.withScopeCleanups Handlers.scopeCleanups (ShowBResult <$> (() <$ showB)))))
      ]
    , [ SDK.targetApp "ReportState" emptyContexts scopes (FrameworkRoot.withErrorHandlers Handlers.errorHandlers (FrameworkRoot.withAnchoredContexts Handlers.contextInjections (SDK.withScopeCleanups Handlers.scopeCleanups (caseOfReportState <$> readReportState))))
      ]
    , [ ("ParserA", SDK.receiveSteps (SDK.targetApp "FeedA" emptyContexts scopes (FrameworkRoot.withErrorHandlers Handlers.errorHandlers (FrameworkRoot.withAnchoredContexts Handlers.contextInjections (SDK.withScopeCleanups Handlers.scopeCleanups (nextA))))) (SDK.targetApp "ParserA" emptyContexts scopes (FrameworkRoot.withErrorHandlers Handlers.errorHandlers (FrameworkRoot.withAnchoredContexts Handlers.contextInjections (SDK.withScopeCleanups Handlers.scopeCleanups (() <$ getLevelA))))))
      , ("ParserB", SDK.receiveSteps (SDK.targetApp "FeedB" emptyContexts scopes (FrameworkRoot.withErrorHandlers Handlers.errorHandlers (FrameworkRoot.withAnchoredContexts Handlers.contextInjections (SDK.withScopeCleanups Handlers.scopeCleanups (nextB))))) (SDK.targetApp "ParserB" emptyContexts scopes (FrameworkRoot.withErrorHandlers Handlers.errorHandlers (FrameworkRoot.withAnchoredContexts Handlers.contextInjections (SDK.withScopeCleanups Handlers.scopeCleanups (() <$ getLevelB))))))
      ]
    )

caseOfReportState :: ReportState -> String
caseOfReportState (ReportState value) = case value of
  Blank {} -> "Blank"
  Filled {} -> "Filled"

-- SDK 装配入口，不需要用户提供节点执行器或重复选择 handler。
interpreter :: SDK.AST -> [EffectSpec] -> IO ()
interpreter = SDK.interpreter "FacadeProbe" Handlers.handlerSourceFingerprint generatedPrototype compiledEntries
-- 生成时完成注册、方法、origin/ctx 链、资产来源、Workflow 和 scope 的统一分析。
-- NodeId 只在这份 AST 快照中有效；运行时校验后装配闭包。
generatedPrototype :: SDK.Prototype MethodGen
generatedPrototype =
  SDK.Prototype
    { SDK.protoRegistrations =
        [ SDK.EffectSpec
            { SDK.name = "ReportLocation"
            , SDK.typing =
                SDK.Context (SDK.AssetDecl ("ReportPath") (SDK.TypeRef ("[Char]"))) (Just ()) (Just ()) (Nothing)
            , SDK.input = "Root"
            , SDK.demands = []
            }
        , SDK.EffectSpec
            { SDK.name = "ReplyLocation"
            , SDK.typing =
                SDK.Context (SDK.AssetDecl ("ReplyPath") (SDK.TypeRef ("[Char]"))) (Just ()) (Just ()) (Nothing)
            , SDK.input = "Root"
            , SDK.demands = []
            }
        , SDK.EffectSpec
            { SDK.name = "ReportDraft"
            , SDK.typing =
                SDK.Context (SDK.AssetDecl ("ReportBody") (SDK.TypeRef ("Body"))) (Just ()) (Just ()) (Nothing)
            , SDK.input = "Root"
            , SDK.demands = []
            }
        , SDK.EffectSpec
            { SDK.name = "ReplyDraft"
            , SDK.typing =
                SDK.Context (SDK.AssetDecl ("ReplyBody") (SDK.TypeRef ("Body"))) (Just ()) (Just ()) (Nothing)
            , SDK.input = "Root"
            , SDK.demands = []
            }
        , SDK.EffectSpec
            { SDK.name = "ReportFile"
            , SDK.typing =
                SDK.Context
                  (SDK.AssetDecl ("OpenedReport") (SDK.TypeRef ("TextFile")))
                  (Just ())
                  (Just ())
                  (Nothing)
            , SDK.input = "Root"
            , SDK.demands = [SDK.Demand (SDK.RequireAccess) ("ReportPath")]
            }
        , SDK.EffectSpec
            { SDK.name = "ReplyFile"
            , SDK.typing =
                SDK.Context (SDK.AssetDecl ("OpenedReply") (SDK.TypeRef ("TextFile"))) (Just ()) (Just ()) (Nothing)
            , SDK.input = "Root"
            , SDK.demands = [SDK.Demand (SDK.RequireAccess) ("ReplyPath")]
            }
        , SDK.EffectSpec
            { SDK.name = "ReportScope"
            , SDK.typing = SDK.Scoped (Just "openReport") (Just "closeReport")
            , SDK.input = "Root"
            , SDK.demands =
                [SDK.Demand (SDK.RequestAccess) ("OpenedReport"), SDK.Demand (SDK.RequireAccess) ("OpenedReport")]
            }
        , SDK.EffectSpec
            { SDK.name = "ReplyScope"
            , SDK.typing = SDK.Scoped (Just "openReply") (Just "closeReply")
            , SDK.input = "Root"
            , SDK.demands =
                [SDK.Demand (SDK.RequestAccess) ("OpenedReply"), SDK.Demand (SDK.RequireAccess) ("OpenedReply")]
            }
        , SDK.EffectSpec
            { SDK.name = "WriteReport"
            , SDK.typing = SDK.Excu (Just "writeReport")
            , SDK.input = "ReportScope"
            , SDK.demands =
                [SDK.Demand (SDK.RequireAccess) ("OpenedReport"), SDK.Demand (SDK.RequireAccess) ("ReportBody")]
            }
        , SDK.EffectSpec
            { SDK.name = "WriteReply"
            , SDK.typing = SDK.Excu (Just "writeReply")
            , SDK.input = "ReplyScope"
            , SDK.demands =
                [SDK.Demand (SDK.RequireAccess) ("OpenedReply"), SDK.Demand (SDK.RequireAccess) ("ReplyBody")]
            }
        , SDK.EffectSpec
            { SDK.name = "MarkReply"
            , SDK.typing = SDK.Excu (Just "markReply")
            , SDK.input = "Root"
            , SDK.demands = []
            }
        , SDK.EffectSpec
            { SDK.name = "ReadReport"
            , SDK.typing = SDK.Excu (Just "readReport")
            , SDK.input = "Root"
            , SDK.demands = [SDK.Demand (SDK.RequireAccess) ("ReportPath")]
            }
        , SDK.EffectSpec
            { SDK.name = "ReadReply"
            , SDK.typing = SDK.Excu (Just "readReply")
            , SDK.input = "MarkReply"
            , SDK.demands = [SDK.Demand (SDK.RequireAccess) ("ReplyPath")]
            }
        , SDK.EffectSpec
            { SDK.name = "ReportCounter"
            , SDK.typing =
                SDK.Context
                  (SDK.AssetDecl ("ReportStats") (SDK.TypeRef ("LineCount")))
                  (Just ())
                  (Just ())
                  (Nothing)
            , SDK.input = "ReadReport"
            , SDK.demands = []
            }
        , SDK.EffectSpec
            { SDK.name = "ReplyCounter"
            , SDK.typing =
                SDK.Context (SDK.AssetDecl ("ReplyStats") (SDK.TypeRef ("LineCount"))) (Just ()) (Just ()) (Nothing)
            , SDK.input = "ReadReply"
            , SDK.demands = []
            }
        , SDK.EffectSpec
            { SDK.name = "ShowReport"
            , SDK.typing = SDK.Excu (Just "showReport")
            , SDK.input = "Root"
            , SDK.demands = [SDK.Demand (SDK.RequireAccess) ("ReportStats")]
            }
        , SDK.EffectSpec
            { SDK.name = "ShowReply"
            , SDK.typing = SDK.Excu (Just "showReply")
            , SDK.input = "Root"
            , SDK.demands = [SDK.Demand (SDK.RequireAccess) ("ReplyStats")]
            }
        , SDK.EffectSpec
            { SDK.name = "ReportInspect"
            , SDK.typing =
                SDK.Context
                  (SDK.AssetDecl ("ReportState") (SDK.TypeRef ("FileState")))
                  (Just ())
                  (Just ())
                  (Nothing)
            , SDK.input = "Root"
            , SDK.demands = [SDK.Demand (SDK.RequireAccess) ("ReportPath")]
            }
        , SDK.EffectSpec
            { SDK.name = "OnBlank"
            , SDK.typing = SDK.Excu (Just "onBlank")
            , SDK.input = "Root"
            , SDK.demands = [SDK.Demand (SDK.RequireAccess) ("ReportStateBlank")]
            }
        , SDK.EffectSpec
            { SDK.name = "OnFilled"
            , SDK.typing = SDK.Excu (Just "onFilled")
            , SDK.input = "Root"
            , SDK.demands = [SDK.Demand (SDK.RequireAccess) ("ReportStateFilled")]
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
                SDK.Context (SDK.AssetDecl ("LevelA") (SDK.TypeRef ("Level"))) (Just ()) (Just ()) (Nothing)
            , SDK.input = "FeedA"
            , SDK.demands = []
            }
        , SDK.EffectSpec
            { SDK.name = "ParserB"
            , SDK.typing =
                SDK.Context (SDK.AssetDecl ("LevelB") (SDK.TypeRef ("Level"))) (Just ()) (Just ()) (Nothing)
            , SDK.input = "FeedB"
            , SDK.demands = []
            }
        , SDK.EffectSpec
            { SDK.name = "ShowA"
            , SDK.typing = SDK.Excu (Just "showA")
            , SDK.input = "Root"
            , SDK.demands = [SDK.Demand (SDK.StreamAccess) ("LevelA")]
            }
        , SDK.EffectSpec
            { SDK.name = "ShowB"
            , SDK.typing = SDK.Excu (Just "showB")
            , SDK.input = "Root"
            , SDK.demands = [SDK.Demand (SDK.StreamAccess) ("LevelB")]
            }
        ]
    , SDK.protoEffects =
        [ SDK.EffectProto
            { SDK.effectName = "ReportLocation"
            , SDK.effectKind = SDK.ContextKind
            , SDK.effectInput = "Root"
            , SDK.effectMethods =
                [(SDK.ContextRequest, GetReportPathGen), (SDK.ContextRequire, ReadReportPathGen)]
            , SDK.effectDemands = []
            , SDK.effectProduces = Just "ReportPath"
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
            { SDK.effectName = "ReplyLocation"
            , SDK.effectKind = SDK.ContextKind
            , SDK.effectInput = "Root"
            , SDK.effectMethods =
                [(SDK.ContextRequest, GetReplyPathGen), (SDK.ContextRequire, ReadReplyPathGen)]
            , SDK.effectDemands = []
            , SDK.effectProduces = Just "ReplyPath"
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
            { SDK.effectName = "ReportDraft"
            , SDK.effectKind = SDK.ContextKind
            , SDK.effectInput = "Root"
            , SDK.effectMethods =
                [(SDK.ContextRequest, GetReportBodyGen), (SDK.ContextRequire, ReadReportBodyGen)]
            , SDK.effectDemands = []
            , SDK.effectProduces = Just "ReportBody"
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
            { SDK.effectName = "ReplyDraft"
            , SDK.effectKind = SDK.ContextKind
            , SDK.effectInput = "Root"
            , SDK.effectMethods =
                [(SDK.ContextRequest, GetReplyBodyGen), (SDK.ContextRequire, ReadReplyBodyGen)]
            , SDK.effectDemands = []
            , SDK.effectProduces = Just "ReplyBody"
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
            { SDK.effectName = "ReportFile"
            , SDK.effectKind = SDK.ContextKind
            , SDK.effectInput = "Root"
            , SDK.effectMethods =
                [(SDK.ContextRequest, GetOpenedReportGen), (SDK.ContextRequire, ReadOpenedReportGen)]
            , SDK.effectDemands = [SDK.ResolvedDemand (SDK.RequireAccess) ("ReportPath") ("ReportLocation")]
            , SDK.effectProduces = Just "OpenedReport"
            , SDK.effectBranches = []
            , SDK.effectAnchor = Nothing
            , SDK.effectScopes = []
            , SDK.effectErrorScope = Nothing
            , SDK.effectInputChain = []
            , SDK.effectScopeParents = []
            , SDK.effectOpeningInputs = []
            , SDK.effectNearestScopes = []
            , SDK.effectResource = Nothing
            , SDK.effectContextDependencies = ["ReportLocation"]
            , SDK.effectContinuous = False
            }
        , SDK.EffectProto
            { SDK.effectName = "ReplyFile"
            , SDK.effectKind = SDK.ContextKind
            , SDK.effectInput = "Root"
            , SDK.effectMethods =
                [(SDK.ContextRequest, GetOpenedReplyGen), (SDK.ContextRequire, ReadOpenedReplyGen)]
            , SDK.effectDemands = [SDK.ResolvedDemand (SDK.RequireAccess) ("ReplyPath") ("ReplyLocation")]
            , SDK.effectProduces = Just "OpenedReply"
            , SDK.effectBranches = []
            , SDK.effectAnchor = Nothing
            , SDK.effectScopes = []
            , SDK.effectErrorScope = Nothing
            , SDK.effectInputChain = []
            , SDK.effectScopeParents = []
            , SDK.effectOpeningInputs = []
            , SDK.effectNearestScopes = []
            , SDK.effectResource = Nothing
            , SDK.effectContextDependencies = ["ReplyLocation"]
            , SDK.effectContinuous = False
            }
        , SDK.EffectProto
            { SDK.effectName = "ReportScope"
            , SDK.effectKind = SDK.ScopedKind
            , SDK.effectInput = "Root"
            , SDK.effectMethods = [(SDK.ScopeOpen, OpenReportGen), (SDK.ScopeClose, CloseReportGen)]
            , SDK.effectDemands =
                [ SDK.ResolvedDemand (SDK.RequestAccess) ("OpenedReport") ("ReportFile")
                , SDK.ResolvedDemand (SDK.RequireAccess) ("OpenedReport") ("ReportFile")
                ]
            , SDK.effectProduces = Nothing
            , SDK.effectBranches = []
            , SDK.effectAnchor = Nothing
            , SDK.effectScopes = []
            , SDK.effectErrorScope = Nothing
            , SDK.effectInputChain = []
            , SDK.effectScopeParents = []
            , SDK.effectOpeningInputs = ["ReportLocation"]
            , SDK.effectNearestScopes = ["ReportScope"]
            , SDK.effectResource = Just "ReportFile"
            , SDK.effectContextDependencies = ["ReportLocation","ReportFile"]
            , SDK.effectContinuous = False
            }
        , SDK.EffectProto
            { SDK.effectName = "ReplyScope"
            , SDK.effectKind = SDK.ScopedKind
            , SDK.effectInput = "Root"
            , SDK.effectMethods = [(SDK.ScopeOpen, OpenReplyGen), (SDK.ScopeClose, CloseReplyGen)]
            , SDK.effectDemands =
                [ SDK.ResolvedDemand (SDK.RequestAccess) ("OpenedReply") ("ReplyFile")
                , SDK.ResolvedDemand (SDK.RequireAccess) ("OpenedReply") ("ReplyFile")
                ]
            , SDK.effectProduces = Nothing
            , SDK.effectBranches = []
            , SDK.effectAnchor = Nothing
            , SDK.effectScopes = []
            , SDK.effectErrorScope = Nothing
            , SDK.effectInputChain = []
            , SDK.effectScopeParents = []
            , SDK.effectOpeningInputs = ["ReplyLocation"]
            , SDK.effectNearestScopes = ["ReplyScope"]
            , SDK.effectResource = Just "ReplyFile"
            , SDK.effectContextDependencies = ["ReplyLocation","ReplyFile"]
            , SDK.effectContinuous = False
            }
        , SDK.EffectProto
            { SDK.effectName = "WriteReport"
            , SDK.effectKind = SDK.ExcuKind
            , SDK.effectInput = "ReportScope"
            , SDK.effectMethods = [(SDK.HandlerMethod, WriteReportGen)]
            , SDK.effectDemands =
                [ SDK.ResolvedDemand (SDK.RequireAccess) ("OpenedReport") ("ReportFile")
                , SDK.ResolvedDemand (SDK.RequireAccess) ("ReportBody") ("ReportDraft")
                ]
            , SDK.effectProduces = Nothing
            , SDK.effectBranches = []
            , SDK.effectAnchor = Nothing
            , SDK.effectScopes = ["ReportScope"]
            , SDK.effectErrorScope = Nothing
            , SDK.effectInputChain = ["ReportScope"]
            , SDK.effectScopeParents = ["ReportScope"]
            , SDK.effectOpeningInputs = []
            , SDK.effectNearestScopes = ["ReportScope"]
            , SDK.effectResource = Nothing
            , SDK.effectContextDependencies = ["ReportLocation","ReportFile","ReportDraft"]
            , SDK.effectContinuous = False
            }
        , SDK.EffectProto
            { SDK.effectName = "WriteReply"
            , SDK.effectKind = SDK.ExcuKind
            , SDK.effectInput = "ReplyScope"
            , SDK.effectMethods = [(SDK.HandlerMethod, WriteReplyGen)]
            , SDK.effectDemands =
                [ SDK.ResolvedDemand (SDK.RequireAccess) ("OpenedReply") ("ReplyFile")
                , SDK.ResolvedDemand (SDK.RequireAccess) ("ReplyBody") ("ReplyDraft")
                ]
            , SDK.effectProduces = Nothing
            , SDK.effectBranches = []
            , SDK.effectAnchor = Nothing
            , SDK.effectScopes = ["ReplyScope"]
            , SDK.effectErrorScope = Nothing
            , SDK.effectInputChain = ["ReplyScope"]
            , SDK.effectScopeParents = ["ReplyScope"]
            , SDK.effectOpeningInputs = []
            , SDK.effectNearestScopes = ["ReplyScope"]
            , SDK.effectResource = Nothing
            , SDK.effectContextDependencies = ["ReplyLocation","ReplyFile","ReplyDraft"]
            , SDK.effectContinuous = False
            }
        , SDK.EffectProto
            { SDK.effectName = "MarkReply"
            , SDK.effectKind = SDK.ExcuKind
            , SDK.effectInput = "Root"
            , SDK.effectMethods = [(SDK.HandlerMethod, MarkReplyGen)]
            , SDK.effectDemands = []
            , SDK.effectProduces = Nothing
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
            { SDK.effectName = "ReadReport"
            , SDK.effectKind = SDK.ExcuKind
            , SDK.effectInput = "Root"
            , SDK.effectMethods = [(SDK.HandlerMethod, ReadReportGen)]
            , SDK.effectDemands = [SDK.ResolvedDemand (SDK.RequireAccess) ("ReportPath") ("ReportLocation")]
            , SDK.effectProduces = Nothing
            , SDK.effectBranches = []
            , SDK.effectAnchor = Nothing
            , SDK.effectScopes = []
            , SDK.effectErrorScope = Nothing
            , SDK.effectInputChain = []
            , SDK.effectScopeParents = []
            , SDK.effectOpeningInputs = []
            , SDK.effectNearestScopes = []
            , SDK.effectResource = Nothing
            , SDK.effectContextDependencies = ["ReportLocation"]
            , SDK.effectContinuous = False
            }
        , SDK.EffectProto
            { SDK.effectName = "ReadReply"
            , SDK.effectKind = SDK.ExcuKind
            , SDK.effectInput = "MarkReply"
            , SDK.effectMethods = [(SDK.HandlerMethod, ReadReplyGen)]
            , SDK.effectDemands = [SDK.ResolvedDemand (SDK.RequireAccess) ("ReplyPath") ("ReplyLocation")]
            , SDK.effectProduces = Nothing
            , SDK.effectBranches = []
            , SDK.effectAnchor = Nothing
            , SDK.effectScopes = []
            , SDK.effectErrorScope = Nothing
            , SDK.effectInputChain = ["MarkReply"]
            , SDK.effectScopeParents = []
            , SDK.effectOpeningInputs = []
            , SDK.effectNearestScopes = []
            , SDK.effectResource = Nothing
            , SDK.effectContextDependencies = ["ReplyLocation"]
            , SDK.effectContinuous = False
            }
        , SDK.EffectProto
            { SDK.effectName = "ReportCounter"
            , SDK.effectKind = SDK.ContextKind
            , SDK.effectInput = "ReadReport"
            , SDK.effectMethods =
                [(SDK.ContextRequest, GetReportStatsGen), (SDK.ContextRequire, ReadReportStatsGen)]
            , SDK.effectDemands = []
            , SDK.effectProduces = Just "ReportStats"
            , SDK.effectBranches = []
            , SDK.effectAnchor = Just "ReadReport"
            , SDK.effectScopes = []
            , SDK.effectErrorScope = Nothing
            , SDK.effectInputChain = ["ReadReport"]
            , SDK.effectScopeParents = []
            , SDK.effectOpeningInputs = []
            , SDK.effectNearestScopes = []
            , SDK.effectResource = Nothing
            , SDK.effectContextDependencies = ["ReportLocation"]
            , SDK.effectContinuous = False
            }
        , SDK.EffectProto
            { SDK.effectName = "ReplyCounter"
            , SDK.effectKind = SDK.ContextKind
            , SDK.effectInput = "ReadReply"
            , SDK.effectMethods =
                [(SDK.ContextRequest, GetReplyStatsGen), (SDK.ContextRequire, ReadReplyStatsGen)]
            , SDK.effectDemands = []
            , SDK.effectProduces = Just "ReplyStats"
            , SDK.effectBranches = []
            , SDK.effectAnchor = Just "ReadReply"
            , SDK.effectScopes = []
            , SDK.effectErrorScope = Nothing
            , SDK.effectInputChain = ["ReadReply","MarkReply"]
            , SDK.effectScopeParents = []
            , SDK.effectOpeningInputs = []
            , SDK.effectNearestScopes = []
            , SDK.effectResource = Nothing
            , SDK.effectContextDependencies = ["ReplyLocation"]
            , SDK.effectContinuous = False
            }
        , SDK.EffectProto
            { SDK.effectName = "ShowReport"
            , SDK.effectKind = SDK.ExcuKind
            , SDK.effectInput = "Root"
            , SDK.effectMethods = [(SDK.HandlerMethod, ShowReportGen)]
            , SDK.effectDemands = [SDK.ResolvedDemand (SDK.RequireAccess) ("ReportStats") ("ReportCounter")]
            , SDK.effectProduces = Nothing
            , SDK.effectBranches = []
            , SDK.effectAnchor = Nothing
            , SDK.effectScopes = []
            , SDK.effectErrorScope = Nothing
            , SDK.effectInputChain = []
            , SDK.effectScopeParents = []
            , SDK.effectOpeningInputs = []
            , SDK.effectNearestScopes = []
            , SDK.effectResource = Nothing
            , SDK.effectContextDependencies = ["ReportLocation","ReportCounter"]
            , SDK.effectContinuous = False
            }
        , SDK.EffectProto
            { SDK.effectName = "ShowReply"
            , SDK.effectKind = SDK.ExcuKind
            , SDK.effectInput = "Root"
            , SDK.effectMethods = [(SDK.HandlerMethod, ShowReplyGen)]
            , SDK.effectDemands = [SDK.ResolvedDemand (SDK.RequireAccess) ("ReplyStats") ("ReplyCounter")]
            , SDK.effectProduces = Nothing
            , SDK.effectBranches = []
            , SDK.effectAnchor = Nothing
            , SDK.effectScopes = []
            , SDK.effectErrorScope = Nothing
            , SDK.effectInputChain = []
            , SDK.effectScopeParents = []
            , SDK.effectOpeningInputs = []
            , SDK.effectNearestScopes = []
            , SDK.effectResource = Nothing
            , SDK.effectContextDependencies = ["ReplyLocation","ReplyCounter"]
            , SDK.effectContinuous = False
            }
        , SDK.EffectProto
            { SDK.effectName = "ReportInspect"
            , SDK.effectKind = SDK.ContextKind
            , SDK.effectInput = "Root"
            , SDK.effectMethods =
                [(SDK.ContextRequest, GetReportStateGen), (SDK.ContextRequire, ReadReportStateGen)]
            , SDK.effectDemands = [SDK.ResolvedDemand (SDK.RequireAccess) ("ReportPath") ("ReportLocation")]
            , SDK.effectProduces = Just "ReportState"
            , SDK.effectBranches = [("ReportStateBlank","Blank"),("ReportStateFilled","Filled")]
            , SDK.effectAnchor = Nothing
            , SDK.effectScopes = []
            , SDK.effectErrorScope = Nothing
            , SDK.effectInputChain = []
            , SDK.effectScopeParents = []
            , SDK.effectOpeningInputs = []
            , SDK.effectNearestScopes = []
            , SDK.effectResource = Nothing
            , SDK.effectContextDependencies = ["ReportLocation"]
            , SDK.effectContinuous = False
            }
        , SDK.EffectProto
            { SDK.effectName = "OnBlank"
            , SDK.effectKind = SDK.ExcuKind
            , SDK.effectInput = "Root"
            , SDK.effectMethods = [(SDK.HandlerMethod, OnBlankGen)]
            , SDK.effectDemands =
                [SDK.ResolvedDemand (SDK.RequireAccess) ("ReportStateBlank") ("ReportInspect")]
            , SDK.effectProduces = Nothing
            , SDK.effectBranches = []
            , SDK.effectAnchor = Nothing
            , SDK.effectScopes = []
            , SDK.effectErrorScope = Nothing
            , SDK.effectInputChain = []
            , SDK.effectScopeParents = []
            , SDK.effectOpeningInputs = []
            , SDK.effectNearestScopes = []
            , SDK.effectResource = Nothing
            , SDK.effectContextDependencies = ["ReportLocation","ReportInspect"]
            , SDK.effectContinuous = False
            }
        , SDK.EffectProto
            { SDK.effectName = "OnFilled"
            , SDK.effectKind = SDK.ExcuKind
            , SDK.effectInput = "Root"
            , SDK.effectMethods = [(SDK.HandlerMethod, OnFilledGen)]
            , SDK.effectDemands =
                [SDK.ResolvedDemand (SDK.RequireAccess) ("ReportStateFilled") ("ReportInspect")]
            , SDK.effectProduces = Nothing
            , SDK.effectBranches = []
            , SDK.effectAnchor = Nothing
            , SDK.effectScopes = []
            , SDK.effectErrorScope = Nothing
            , SDK.effectInputChain = []
            , SDK.effectScopeParents = []
            , SDK.effectOpeningInputs = []
            , SDK.effectNearestScopes = []
            , SDK.effectResource = Nothing
            , SDK.effectContextDependencies = ["ReportLocation","ReportInspect"]
            , SDK.effectContinuous = False
            }
        , SDK.EffectProto
            { SDK.effectName = "FeedA"
            , SDK.effectKind = SDK.StreamKind
            , SDK.effectInput = "Root"
            , SDK.effectMethods = [(SDK.StreamHandler, NextAGen)]
            , SDK.effectDemands = []
            , SDK.effectProduces = Nothing
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
            { SDK.effectName = "FeedB"
            , SDK.effectKind = SDK.StreamKind
            , SDK.effectInput = "Root"
            , SDK.effectMethods = [(SDK.StreamHandler, NextBGen)]
            , SDK.effectDemands = []
            , SDK.effectProduces = Nothing
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
            { SDK.effectName = "ParserA"
            , SDK.effectKind = SDK.ContextKind
            , SDK.effectInput = "FeedA"
            , SDK.effectMethods = [(SDK.ContextStream, GetLevelAGen), (SDK.ContextRequire, ReadLevelAGen)]
            , SDK.effectDemands = []
            , SDK.effectProduces = Just "LevelA"
            , SDK.effectBranches = []
            , SDK.effectAnchor = Nothing
            , SDK.effectScopes = []
            , SDK.effectErrorScope = Nothing
            , SDK.effectInputChain = ["FeedA"]
            , SDK.effectScopeParents = []
            , SDK.effectOpeningInputs = []
            , SDK.effectNearestScopes = []
            , SDK.effectResource = Nothing
            , SDK.effectContextDependencies = []
            , SDK.effectContinuous = True
            }
        , SDK.EffectProto
            { SDK.effectName = "ParserB"
            , SDK.effectKind = SDK.ContextKind
            , SDK.effectInput = "FeedB"
            , SDK.effectMethods = [(SDK.ContextStream, GetLevelBGen), (SDK.ContextRequire, ReadLevelBGen)]
            , SDK.effectDemands = []
            , SDK.effectProduces = Just "LevelB"
            , SDK.effectBranches = []
            , SDK.effectAnchor = Nothing
            , SDK.effectScopes = []
            , SDK.effectErrorScope = Nothing
            , SDK.effectInputChain = ["FeedB"]
            , SDK.effectScopeParents = []
            , SDK.effectOpeningInputs = []
            , SDK.effectNearestScopes = []
            , SDK.effectResource = Nothing
            , SDK.effectContextDependencies = []
            , SDK.effectContinuous = True
            }
        , SDK.EffectProto
            { SDK.effectName = "ShowA"
            , SDK.effectKind = SDK.ExcuKind
            , SDK.effectInput = "Root"
            , SDK.effectMethods = [(SDK.HandlerMethod, ShowAGen)]
            , SDK.effectDemands = [SDK.ResolvedDemand (SDK.StreamAccess) ("LevelA") ("ParserA")]
            , SDK.effectProduces = Nothing
            , SDK.effectBranches = []
            , SDK.effectAnchor = Nothing
            , SDK.effectScopes = []
            , SDK.effectErrorScope = Nothing
            , SDK.effectInputChain = []
            , SDK.effectScopeParents = []
            , SDK.effectOpeningInputs = []
            , SDK.effectNearestScopes = []
            , SDK.effectResource = Nothing
            , SDK.effectContextDependencies = ["ParserA"]
            , SDK.effectContinuous = False
            }
        , SDK.EffectProto
            { SDK.effectName = "ShowB"
            , SDK.effectKind = SDK.ExcuKind
            , SDK.effectInput = "Root"
            , SDK.effectMethods = [(SDK.HandlerMethod, ShowBGen)]
            , SDK.effectDemands = [SDK.ResolvedDemand (SDK.StreamAccess) ("LevelB") ("ParserB")]
            , SDK.effectProduces = Nothing
            , SDK.effectBranches = []
            , SDK.effectAnchor = Nothing
            , SDK.effectScopes = []
            , SDK.effectErrorScope = Nothing
            , SDK.effectInputChain = []
            , SDK.effectScopeParents = []
            , SDK.effectOpeningInputs = []
            , SDK.effectNearestScopes = []
            , SDK.effectResource = Nothing
            , SDK.effectContextDependencies = ["ParserB"]
            , SDK.effectContinuous = False
            }
        ]
    , SDK.protoMethods =
        [ SDK.MethodDefinition (GetReportPathGen) (GetReportPathGen) (SDK.ContextRequest) (SDK.Empty)
        , SDK.MethodDefinition
            (ReadReportPathGen)
            (GetReportPathGen)
            (SDK.ContextRequire)
            (SDK.Choice ([SDK.Empty, SDK.Call (GetReportPathGen)]))
        , SDK.MethodDefinition (GetReplyPathGen) (GetReplyPathGen) (SDK.ContextRequest) (SDK.Empty)
        , SDK.MethodDefinition
            (ReadReplyPathGen)
            (GetReplyPathGen)
            (SDK.ContextRequire)
            (SDK.Choice ([SDK.Empty, SDK.Call (GetReplyPathGen)]))
        , SDK.MethodDefinition (GetReportBodyGen) (GetReportBodyGen) (SDK.ContextRequest) (SDK.Empty)
        , SDK.MethodDefinition
            (ReadReportBodyGen)
            (GetReportBodyGen)
            (SDK.ContextRequire)
            (SDK.Choice ([SDK.Empty, SDK.Call (GetReportBodyGen)]))
        , SDK.MethodDefinition (GetReplyBodyGen) (GetReplyBodyGen) (SDK.ContextRequest) (SDK.Empty)
        , SDK.MethodDefinition
            (ReadReplyBodyGen)
            (GetReplyBodyGen)
            (SDK.ContextRequire)
            (SDK.Choice ([SDK.Empty, SDK.Call (GetReplyBodyGen)]))
        , SDK.MethodDefinition
            (GetOpenedReportGen)
            (GetOpenedReportGen)
            (SDK.ContextRequest)
            (SDK.Call (ReadReportPathGen))
        , SDK.MethodDefinition (ReadOpenedReportGen) (GetOpenedReportGen) (SDK.ContextRequire) (SDK.Empty)
        , SDK.MethodDefinition
            (GetOpenedReplyGen)
            (GetOpenedReplyGen)
            (SDK.ContextRequest)
            (SDK.Call (ReadReplyPathGen))
        , SDK.MethodDefinition (ReadOpenedReplyGen) (GetOpenedReplyGen) (SDK.ContextRequire) (SDK.Empty)
        , SDK.MethodDefinition (OpenReportGen) (OpenReportGen) (SDK.ScopeOpen) (SDK.Call (GetOpenedReportGen))
        , SDK.MethodDefinition
            (CloseReportGen)
            (OpenReportGen)
            (SDK.ScopeClose)
            (SDK.Call (ReadOpenedReportGen))
        , SDK.MethodDefinition (OpenReplyGen) (OpenReplyGen) (SDK.ScopeOpen) (SDK.Call (GetOpenedReplyGen))
        , SDK.MethodDefinition (CloseReplyGen) (OpenReplyGen) (SDK.ScopeClose) (SDK.Call (ReadOpenedReplyGen))
        , SDK.MethodDefinition
            (WriteReportGen)
            (WriteReportGen)
            (SDK.HandlerMethod)
            (
              SDK.Sequence
                ([SDK.Call (OpenReportGen), SDK.Call (ReadOpenedReportGen), SDK.Call (ReadReportBodyGen)])
            )
        , SDK.MethodDefinition
            (WriteReplyGen)
            (WriteReplyGen)
            (SDK.HandlerMethod)
            (SDK.Sequence ([SDK.Call (OpenReplyGen), SDK.Call (ReadOpenedReplyGen), SDK.Call (ReadReplyBodyGen)]))
        , SDK.MethodDefinition (MarkReplyGen) (MarkReplyGen) (SDK.HandlerMethod) (SDK.Empty)
        , SDK.MethodDefinition
            (ReadReportGen)
            (ReadReportGen)
            (SDK.HandlerMethod)
            (SDK.Sequence ([SDK.Call (ReadReportPathGen), SDK.Choice ([SDK.Empty, SDK.Sequence ([SDK.Empty])])]))
        , SDK.MethodDefinition
            (ReadReplyGen)
            (ReadReplyGen)
            (SDK.HandlerMethod)
            (
              SDK.Sequence
                (
                  [ SDK.Sequence ([SDK.Call (MarkReplyGen), SDK.Call (ReadReplyPathGen)])
                  , SDK.Choice ([SDK.Empty, SDK.Sequence ([SDK.Empty])])
                  ]
                )
            )
        , SDK.MethodDefinition
            (GetReportStatsGen)
            (GetReportStatsGen)
            (SDK.ContextRequest)
            (SDK.Call (ReadReportGen))
        , SDK.MethodDefinition
            (ReadReportStatsGen)
            (GetReportStatsGen)
            (SDK.ContextRequire)
            (SDK.Choice ([SDK.Empty, SDK.Call (GetReportStatsGen)]))
        , SDK.MethodDefinition
            (GetReplyStatsGen)
            (GetReplyStatsGen)
            (SDK.ContextRequest)
            (SDK.Call (ReadReplyGen))
        , SDK.MethodDefinition
            (ReadReplyStatsGen)
            (GetReplyStatsGen)
            (SDK.ContextRequire)
            (SDK.Choice ([SDK.Empty, SDK.Call (GetReplyStatsGen)]))
        , SDK.MethodDefinition
            (ShowReportGen)
            (ShowReportGen)
            (SDK.HandlerMethod)
            (SDK.Call (ReadReportStatsGen))
        , SDK.MethodDefinition
            (ShowReplyGen)
            (ShowReplyGen)
            (SDK.HandlerMethod)
            (SDK.Call (ReadReplyStatsGen))
        , SDK.MethodDefinition
            (GetReportStateGen)
            (GetReportStateGen)
            (SDK.ContextRequest)
            (SDK.Call (ReadReportPathGen))
        , SDK.MethodDefinition
            (ReadReportStateGen)
            (GetReportStateGen)
            (SDK.ContextRequire)
            (SDK.Choice ([SDK.Empty, SDK.Call (GetReportStateGen)]))
        , SDK.MethodDefinition (OnBlankGen) (OnBlankGen) (SDK.HandlerMethod) (SDK.Call (ReadReportStateGen))
        , SDK.MethodDefinition (OnFilledGen) (OnFilledGen) (SDK.HandlerMethod) (SDK.Call (ReadReportStateGen))
        , SDK.MethodDefinition (NextAGen) (NextAGen) (SDK.StreamHandler) (SDK.Empty)
        , SDK.MethodDefinition (NextBGen) (NextBGen) (SDK.StreamHandler) (SDK.Empty)
        , SDK.MethodDefinition (GetLevelAGen) (GetLevelAGen) (SDK.ContextStream) (SDK.Call (NextAGen))
        , SDK.MethodDefinition (ReadLevelAGen) (GetLevelAGen) (SDK.ContextRequire) (SDK.Empty)
        , SDK.MethodDefinition (GetLevelBGen) (GetLevelBGen) (SDK.ContextStream) (SDK.Call (NextBGen))
        , SDK.MethodDefinition (ReadLevelBGen) (GetLevelBGen) (SDK.ContextRequire) (SDK.Empty)
        , SDK.MethodDefinition (ShowAGen) (ShowAGen) (SDK.HandlerMethod) (SDK.Call (ReadLevelAGen))
        , SDK.MethodDefinition (ShowBGen) (ShowBGen) (SDK.HandlerMethod) (SDK.Call (ReadLevelBGen))
        ]
    , SDK.protoWorkflow =
        SDK.ChainedAt
          ([])
          (
            [ SDK.ParallelAt
                ([0])
                (
                  [ SDK.NodeAt ([0,0]) ("WriteReport")
                  , SDK.NodeAt ([0,1]) ("WriteReply")
                  ]
                )
            , SDK.ParallelAt
                ([1])
                (
                  [ SDK.NodeAt ([1,0]) ("ReadReport")
                  , SDK.NodeAt ([1,1]) ("ReadReply")
                  ]
                )
            , SDK.ChainedAt
                ([2])
                (
                  [ SDK.NodeAt ([2,0]) ("ShowReport")
                  , SDK.NodeAt ([2,1]) ("ShowReply")
                  ]
                )
            , SDK.AlternativeAt
                ([3])
                (
                  SDK.AlternativeProto
                    { SDK.alternativeContract = "ReportState"
                    , SDK.alternativeSelector = [3,-1]
                    , SDK.alternativeCases = [([3,0],"Blank"),([3,1],"Filled")]
                    }
                )
                (
                  [ SDK.NodeAt ([3,0]) ("OnBlank")
                  , SDK.NodeAt ([3,1]) ("OnFilled")
                  ]
                )
            , SDK.LifelongAt
                ([4])
                (
                  SDK.LifelongProto
                    { SDK.lifelongUnits = [[4,0],[4,1]]
                    , SDK.lifelongSubscriptions = [([4,0],"LevelA"),([4,1],"LevelB")]
                    , SDK.lifelongSessions =
                        [ SDK.SessionProto
                            { SDK.sessionAsset = "LevelA"
                            , SDK.sessionPlan = SDK.Receive ("FeedA")
                            , SDK.sessionMounts = [[4,-1,0,0],[4,-1,0,1]]
                            }
                        , SDK.SessionProto
                            { SDK.sessionAsset = "LevelB"
                            , SDK.sessionPlan = SDK.Receive ("FeedB")
                            , SDK.sessionMounts = [[4,-1,1,0],[4,-1,1,1]]
                            }
                        ]
                    }
                )
                (
                  [ SDK.NodeAt ([4,0]) ("ShowA")
                  , SDK.NodeAt ([4,1]) ("ShowB")
                  ]
                )
            ]
          )
    , SDK.protoSessions =
        [ SDK.SessionProto
            { SDK.sessionAsset = "LevelA"
            , SDK.sessionPlan = SDK.Receive ("FeedA")
            , SDK.sessionMounts = [[-2,0,0],[-2,0,1]]
            }
        , SDK.SessionProto
            { SDK.sessionAsset = "LevelB"
            , SDK.sessionPlan = SDK.Receive ("FeedB")
            , SDK.sessionMounts = [[-2,1,0],[-2,1,1]]
            }
        ]
    , SDK.protoChains =
        [ SDK.ChainProto
            { SDK.chainNode = [0,0]
            , SDK.chainRole = SDK.NodeChain
            , SDK.chainTerminal = "WriteReport"
            , SDK.chainEntry = WriteReportGen
            , SDK.chainReaches =
                [ WriteReportGen
                , OpenReportGen
                , GetOpenedReportGen
                , ReadReportPathGen
                , GetReportPathGen
                , ReadOpenedReportGen
                , ReadReportBodyGen
                , GetReportBodyGen
                ]
            , SDK.chainDrives = ["ReportBody","ReportPath"]
            , SDK.chainReads = ["ReportBody","ReportPath"]
            , SDK.chainScopePaths = [[OpenReportGen]]
            }
        , SDK.ChainProto
            { SDK.chainNode = [0,1]
            , SDK.chainRole = SDK.NodeChain
            , SDK.chainTerminal = "WriteReply"
            , SDK.chainEntry = WriteReplyGen
            , SDK.chainReaches =
                [ WriteReplyGen
                , OpenReplyGen
                , GetOpenedReplyGen
                , ReadReplyPathGen
                , GetReplyPathGen
                , ReadOpenedReplyGen
                , ReadReplyBodyGen
                , GetReplyBodyGen
                ]
            , SDK.chainDrives = ["ReplyBody","ReplyPath"]
            , SDK.chainReads = ["ReplyBody","ReplyPath"]
            , SDK.chainScopePaths = [[OpenReplyGen]]
            }
        , SDK.ChainProto
            { SDK.chainNode = [1,0]
            , SDK.chainRole = SDK.NodeChain
            , SDK.chainTerminal = "ReadReport"
            , SDK.chainEntry = ReadReportGen
            , SDK.chainReaches = [ReadReportGen, ReadReportPathGen, GetReportPathGen, GetReportStatsGen]
            , SDK.chainDrives = ["ReportPath","ReportStats"]
            , SDK.chainReads = ["ReportPath"]
            , SDK.chainScopePaths = [[]]
            }
        , SDK.ChainProto
            { SDK.chainNode = [1,1]
            , SDK.chainRole = SDK.NodeChain
            , SDK.chainTerminal = "ReadReply"
            , SDK.chainEntry = ReadReplyGen
            , SDK.chainReaches =
                [ReadReplyGen, MarkReplyGen, ReadReplyPathGen, GetReplyPathGen, GetReplyStatsGen]
            , SDK.chainDrives = ["ReplyPath","ReplyStats"]
            , SDK.chainReads = ["ReplyPath"]
            , SDK.chainScopePaths = [[]]
            }
        , SDK.ChainProto
            { SDK.chainNode = [2,0]
            , SDK.chainRole = SDK.NodeChain
            , SDK.chainTerminal = "ShowReport"
            , SDK.chainEntry = ShowReportGen
            , SDK.chainReaches =
                [ ShowReportGen
                , ReadReportStatsGen
                , GetReportStatsGen
                , ReadReportGen
                , ReadReportPathGen
                , GetReportPathGen
                ]
            , SDK.chainDrives = ["ReportStats"]
            , SDK.chainReads = ["ReportPath","ReportStats"]
            , SDK.chainScopePaths = [[]]
            }
        , SDK.ChainProto
            { SDK.chainNode = [2,1]
            , SDK.chainRole = SDK.NodeChain
            , SDK.chainTerminal = "ShowReply"
            , SDK.chainEntry = ShowReplyGen
            , SDK.chainReaches =
                [ ShowReplyGen
                , ReadReplyStatsGen
                , GetReplyStatsGen
                , ReadReplyGen
                , MarkReplyGen
                , ReadReplyPathGen
                , GetReplyPathGen
                ]
            , SDK.chainDrives = ["ReplyStats"]
            , SDK.chainReads = ["ReplyPath","ReplyStats"]
            , SDK.chainScopePaths = [[]]
            }
        , SDK.ChainProto
            { SDK.chainNode = [3,0]
            , SDK.chainRole = SDK.NodeChain
            , SDK.chainTerminal = "OnBlank"
            , SDK.chainEntry = OnBlankGen
            , SDK.chainReaches =
                [OnBlankGen, ReadReportStateGen, GetReportStateGen, ReadReportPathGen, GetReportPathGen]
            , SDK.chainDrives = []
            , SDK.chainReads = []
            , SDK.chainScopePaths = [[]]
            }
        , SDK.ChainProto
            { SDK.chainNode = [3,1]
            , SDK.chainRole = SDK.NodeChain
            , SDK.chainTerminal = "OnFilled"
            , SDK.chainEntry = OnFilledGen
            , SDK.chainReaches =
                [OnFilledGen, ReadReportStateGen, GetReportStateGen, ReadReportPathGen, GetReportPathGen]
            , SDK.chainDrives = []
            , SDK.chainReads = []
            , SDK.chainScopePaths = [[]]
            }
        , SDK.ChainProto
            { SDK.chainNode = [4,0]
            , SDK.chainRole = SDK.NodeChain
            , SDK.chainTerminal = "ShowA"
            , SDK.chainEntry = ShowAGen
            , SDK.chainReaches = [ShowAGen, ReadLevelAGen]
            , SDK.chainDrives = []
            , SDK.chainReads = []
            , SDK.chainScopePaths = [[]]
            }
        , SDK.ChainProto
            { SDK.chainNode = [4,1]
            , SDK.chainRole = SDK.NodeChain
            , SDK.chainTerminal = "ShowB"
            , SDK.chainEntry = ShowBGen
            , SDK.chainReaches = [ShowBGen, ReadLevelBGen]
            , SDK.chainDrives = []
            , SDK.chainReads = []
            , SDK.chainScopePaths = [[]]
            }
        , SDK.ChainProto
            { SDK.chainNode = [3,-1]
            , SDK.chainRole = SDK.SelectorChain
            , SDK.chainTerminal = "ReportState"
            , SDK.chainEntry = ReadReportStateGen
            , SDK.chainReaches = [ReadReportStateGen, GetReportStateGen, ReadReportPathGen, GetReportPathGen]
            , SDK.chainDrives = ["ReportState"]
            , SDK.chainReads = ["ReportPath","ReportState"]
            , SDK.chainScopePaths = [[]]
            }
        , SDK.ChainProto
            { SDK.chainNode = [4,-1,0,0]
            , SDK.chainRole = SDK.SessionChain
            , SDK.chainTerminal = "LevelA"
            , SDK.chainEntry = NextAGen
            , SDK.chainReaches = [NextAGen]
            , SDK.chainDrives = []
            , SDK.chainReads = []
            , SDK.chainScopePaths = [[]]
            }
        , SDK.ChainProto
            { SDK.chainNode = [4,-1,0,1]
            , SDK.chainRole = SDK.SessionChain
            , SDK.chainTerminal = "LevelA"
            , SDK.chainEntry = GetLevelAGen
            , SDK.chainReaches = [GetLevelAGen, NextAGen]
            , SDK.chainDrives = ["LevelA"]
            , SDK.chainReads = []
            , SDK.chainScopePaths = [[]]
            }
        , SDK.ChainProto
            { SDK.chainNode = [4,-1,1,0]
            , SDK.chainRole = SDK.SessionChain
            , SDK.chainTerminal = "LevelB"
            , SDK.chainEntry = NextBGen
            , SDK.chainReaches = [NextBGen]
            , SDK.chainDrives = []
            , SDK.chainReads = []
            , SDK.chainScopePaths = [[]]
            }
        , SDK.ChainProto
            { SDK.chainNode = [4,-1,1,1]
            , SDK.chainRole = SDK.SessionChain
            , SDK.chainTerminal = "LevelB"
            , SDK.chainEntry = GetLevelBGen
            , SDK.chainReaches = [GetLevelBGen, NextBGen]
            , SDK.chainDrives = ["LevelB"]
            , SDK.chainReads = []
            , SDK.chainScopePaths = [[]]
            }
        , SDK.ChainProto
            { SDK.chainNode = [-2,0,0]
            , SDK.chainRole = SDK.SessionChain
            , SDK.chainTerminal = "LevelA"
            , SDK.chainEntry = NextAGen
            , SDK.chainReaches = [NextAGen]
            , SDK.chainDrives = []
            , SDK.chainReads = []
            , SDK.chainScopePaths = [[]]
            }
        , SDK.ChainProto
            { SDK.chainNode = [-2,0,1]
            , SDK.chainRole = SDK.SessionChain
            , SDK.chainTerminal = "LevelA"
            , SDK.chainEntry = GetLevelAGen
            , SDK.chainReaches = [GetLevelAGen, NextAGen]
            , SDK.chainDrives = ["LevelA"]
            , SDK.chainReads = []
            , SDK.chainScopePaths = [[]]
            }
        , SDK.ChainProto
            { SDK.chainNode = [-2,1,0]
            , SDK.chainRole = SDK.SessionChain
            , SDK.chainTerminal = "LevelB"
            , SDK.chainEntry = NextBGen
            , SDK.chainReaches = [NextBGen]
            , SDK.chainDrives = []
            , SDK.chainReads = []
            , SDK.chainScopePaths = [[]]
            }
        , SDK.ChainProto
            { SDK.chainNode = [-2,1,1]
            , SDK.chainRole = SDK.SessionChain
            , SDK.chainTerminal = "LevelB"
            , SDK.chainEntry = GetLevelBGen
            , SDK.chainReaches = [GetLevelBGen, NextBGen]
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
            , SDK.definitionReaches = [ReadReportPathGen, GetReportPathGen]
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
            , SDK.definitionReaches = [ReadReplyPathGen, GetReplyPathGen]
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
            , SDK.definitionReaches = [ReadReportBodyGen, GetReportBodyGen]
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
            , SDK.definitionReaches = [ReadReplyBodyGen, GetReplyBodyGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.ContextChain
            , SDK.definitionEffect = "ReportFile"
            , SDK.definitionEntry = GetOpenedReportGen
            , SDK.definitionReaches = [GetOpenedReportGen, ReadReportPathGen, GetReportPathGen]
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
            , SDK.definitionReaches = [GetOpenedReplyGen, ReadReplyPathGen, GetReplyPathGen]
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
            , SDK.definitionEntry = OpenReportGen
            , SDK.definitionReaches = [OpenReportGen, GetOpenedReportGen, ReadReportPathGen, GetReportPathGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.OriginChain
            , SDK.definitionEffect = "ReplyScope"
            , SDK.definitionEntry = OpenReplyGen
            , SDK.definitionReaches = [OpenReplyGen, GetOpenedReplyGen, ReadReplyPathGen, GetReplyPathGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.OriginChain
            , SDK.definitionEffect = "WriteReport"
            , SDK.definitionEntry = WriteReportGen
            , SDK.definitionReaches =
                [ WriteReportGen
                , OpenReportGen
                , GetOpenedReportGen
                , ReadReportPathGen
                , GetReportPathGen
                , ReadOpenedReportGen
                , ReadReportBodyGen
                , GetReportBodyGen
                ]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.OriginChain
            , SDK.definitionEffect = "WriteReply"
            , SDK.definitionEntry = WriteReplyGen
            , SDK.definitionReaches =
                [ WriteReplyGen
                , OpenReplyGen
                , GetOpenedReplyGen
                , ReadReplyPathGen
                , GetReplyPathGen
                , ReadOpenedReplyGen
                , ReadReplyBodyGen
                , GetReplyBodyGen
                ]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.OriginChain
            , SDK.definitionEffect = "MarkReply"
            , SDK.definitionEntry = MarkReplyGen
            , SDK.definitionReaches = [MarkReplyGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.OriginChain
            , SDK.definitionEffect = "ReadReport"
            , SDK.definitionEntry = ReadReportGen
            , SDK.definitionReaches = [ReadReportGen, ReadReportPathGen, GetReportPathGen, GetReportStatsGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.OriginChain
            , SDK.definitionEffect = "ReadReply"
            , SDK.definitionEntry = ReadReplyGen
            , SDK.definitionReaches =
                [ReadReplyGen, MarkReplyGen, ReadReplyPathGen, GetReplyPathGen, GetReplyStatsGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.ContextChain
            , SDK.definitionEffect = "ReportCounter"
            , SDK.definitionEntry = GetReportStatsGen
            , SDK.definitionReaches = [GetReportStatsGen, ReadReportGen, ReadReportPathGen, GetReportPathGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.ContextChain
            , SDK.definitionEffect = "ReportCounter"
            , SDK.definitionEntry = ReadReportStatsGen
            , SDK.definitionReaches =
                [ReadReportStatsGen, GetReportStatsGen, ReadReportGen, ReadReportPathGen, GetReportPathGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.ContextChain
            , SDK.definitionEffect = "ReplyCounter"
            , SDK.definitionEntry = GetReplyStatsGen
            , SDK.definitionReaches =
                [GetReplyStatsGen, ReadReplyGen, MarkReplyGen, ReadReplyPathGen, GetReplyPathGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.ContextChain
            , SDK.definitionEffect = "ReplyCounter"
            , SDK.definitionEntry = ReadReplyStatsGen
            , SDK.definitionReaches =
                [ReadReplyStatsGen, GetReplyStatsGen, ReadReplyGen, MarkReplyGen, ReadReplyPathGen, GetReplyPathGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.OriginChain
            , SDK.definitionEffect = "ShowReport"
            , SDK.definitionEntry = ShowReportGen
            , SDK.definitionReaches =
                [ ShowReportGen
                , ReadReportStatsGen
                , GetReportStatsGen
                , ReadReportGen
                , ReadReportPathGen
                , GetReportPathGen
                ]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.OriginChain
            , SDK.definitionEffect = "ShowReply"
            , SDK.definitionEntry = ShowReplyGen
            , SDK.definitionReaches =
                [ ShowReplyGen
                , ReadReplyStatsGen
                , GetReplyStatsGen
                , ReadReplyGen
                , MarkReplyGen
                , ReadReplyPathGen
                , GetReplyPathGen
                ]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.ContextChain
            , SDK.definitionEffect = "ReportInspect"
            , SDK.definitionEntry = GetReportStateGen
            , SDK.definitionReaches = [GetReportStateGen, ReadReportPathGen, GetReportPathGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.ContextChain
            , SDK.definitionEffect = "ReportInspect"
            , SDK.definitionEntry = ReadReportStateGen
            , SDK.definitionReaches =
                [ReadReportStateGen, GetReportStateGen, ReadReportPathGen, GetReportPathGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.OriginChain
            , SDK.definitionEffect = "OnBlank"
            , SDK.definitionEntry = OnBlankGen
            , SDK.definitionReaches =
                [OnBlankGen, ReadReportStateGen, GetReportStateGen, ReadReportPathGen, GetReportPathGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.OriginChain
            , SDK.definitionEffect = "OnFilled"
            , SDK.definitionEntry = OnFilledGen
            , SDK.definitionReaches =
                [OnFilledGen, ReadReportStateGen, GetReportStateGen, ReadReportPathGen, GetReportPathGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.ContextChain
            , SDK.definitionEffect = "FeedA"
            , SDK.definitionEntry = NextAGen
            , SDK.definitionReaches = [NextAGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.ContextChain
            , SDK.definitionEffect = "FeedB"
            , SDK.definitionEntry = NextBGen
            , SDK.definitionReaches = [NextBGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.ContextChain
            , SDK.definitionEffect = "ParserA"
            , SDK.definitionEntry = GetLevelAGen
            , SDK.definitionReaches = [GetLevelAGen, NextAGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.ContextChain
            , SDK.definitionEffect = "ParserA"
            , SDK.definitionEntry = ReadLevelAGen
            , SDK.definitionReaches = [ReadLevelAGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.ContextChain
            , SDK.definitionEffect = "ParserB"
            , SDK.definitionEntry = GetLevelBGen
            , SDK.definitionReaches = [GetLevelBGen, NextBGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.ContextChain
            , SDK.definitionEffect = "ParserB"
            , SDK.definitionEntry = ReadLevelBGen
            , SDK.definitionReaches = [ReadLevelBGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.OriginChain
            , SDK.definitionEffect = "ShowA"
            , SDK.definitionEntry = ShowAGen
            , SDK.definitionReaches = [ShowAGen, ReadLevelAGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.OriginChain
            , SDK.definitionEffect = "ShowB"
            , SDK.definitionEntry = ShowBGen
            , SDK.definitionReaches = [ShowBGen, ReadLevelBGen]
            }
        ]
    , SDK.protoGraph =
        SDK.EffectGraph
          { SDK.graphMethods =
              [ SDK.MethodDefinition
                  (WriteReportGen)
                  (WriteReportGen)
                  (SDK.HandlerMethod)
                  (
                    SDK.Sequence
                      ([SDK.Call (OpenReportGen), SDK.Call (ReadOpenedReportGen), SDK.Call (ReadReportBodyGen)])
                  )
              , SDK.MethodDefinition (OpenReportGen) (OpenReportGen) (SDK.ScopeOpen) (SDK.Call (GetOpenedReportGen))
              , SDK.MethodDefinition
                  (GetOpenedReportGen)
                  (GetOpenedReportGen)
                  (SDK.ContextRequest)
                  (SDK.Call (ReadReportPathGen))
              , SDK.MethodDefinition
                  (ReadReportPathGen)
                  (GetReportPathGen)
                  (SDK.ContextRequire)
                  (SDK.Choice ([SDK.Empty, SDK.Call (GetReportPathGen)]))
              , SDK.MethodDefinition (GetReportPathGen) (GetReportPathGen) (SDK.ContextRequest) (SDK.Empty)
              , SDK.MethodDefinition (ReadOpenedReportGen) (GetOpenedReportGen) (SDK.ContextRequire) (SDK.Empty)
              , SDK.MethodDefinition
                  (ReadReportBodyGen)
                  (GetReportBodyGen)
                  (SDK.ContextRequire)
                  (SDK.Choice ([SDK.Empty, SDK.Call (GetReportBodyGen)]))
              , SDK.MethodDefinition (GetReportBodyGen) (GetReportBodyGen) (SDK.ContextRequest) (SDK.Empty)
              , SDK.MethodDefinition
                  (WriteReplyGen)
                  (WriteReplyGen)
                  (SDK.HandlerMethod)
                  (SDK.Sequence ([SDK.Call (OpenReplyGen), SDK.Call (ReadOpenedReplyGen), SDK.Call (ReadReplyBodyGen)]))
              , SDK.MethodDefinition (OpenReplyGen) (OpenReplyGen) (SDK.ScopeOpen) (SDK.Call (GetOpenedReplyGen))
              , SDK.MethodDefinition
                  (GetOpenedReplyGen)
                  (GetOpenedReplyGen)
                  (SDK.ContextRequest)
                  (SDK.Call (ReadReplyPathGen))
              , SDK.MethodDefinition
                  (ReadReplyPathGen)
                  (GetReplyPathGen)
                  (SDK.ContextRequire)
                  (SDK.Choice ([SDK.Empty, SDK.Call (GetReplyPathGen)]))
              , SDK.MethodDefinition (GetReplyPathGen) (GetReplyPathGen) (SDK.ContextRequest) (SDK.Empty)
              , SDK.MethodDefinition (ReadOpenedReplyGen) (GetOpenedReplyGen) (SDK.ContextRequire) (SDK.Empty)
              , SDK.MethodDefinition
                  (ReadReplyBodyGen)
                  (GetReplyBodyGen)
                  (SDK.ContextRequire)
                  (SDK.Choice ([SDK.Empty, SDK.Call (GetReplyBodyGen)]))
              , SDK.MethodDefinition (GetReplyBodyGen) (GetReplyBodyGen) (SDK.ContextRequest) (SDK.Empty)
              , SDK.MethodDefinition
                  (ReadReportGen)
                  (ReadReportGen)
                  (SDK.HandlerMethod)
                  (SDK.Sequence ([SDK.Call (ReadReportPathGen), SDK.Choice ([SDK.Empty, SDK.Sequence ([SDK.Empty])])]))
              , SDK.MethodDefinition
                  (ReadReplyGen)
                  (ReadReplyGen)
                  (SDK.HandlerMethod)
                  (
                    SDK.Sequence
                      (
                        [ SDK.Sequence ([SDK.Call (MarkReplyGen), SDK.Call (ReadReplyPathGen)])
                        , SDK.Choice ([SDK.Empty, SDK.Sequence ([SDK.Empty])])
                        ]
                      )
                  )
              , SDK.MethodDefinition (MarkReplyGen) (MarkReplyGen) (SDK.HandlerMethod) (SDK.Empty)
              , SDK.MethodDefinition
                  (ShowReportGen)
                  (ShowReportGen)
                  (SDK.HandlerMethod)
                  (SDK.Call (ReadReportStatsGen))
              , SDK.MethodDefinition
                  (ReadReportStatsGen)
                  (GetReportStatsGen)
                  (SDK.ContextRequire)
                  (SDK.Choice ([SDK.Empty, SDK.Call (GetReportStatsGen)]))
              , SDK.MethodDefinition
                  (GetReportStatsGen)
                  (GetReportStatsGen)
                  (SDK.ContextRequest)
                  (SDK.Call (ReadReportGen))
              , SDK.MethodDefinition
                  (ShowReplyGen)
                  (ShowReplyGen)
                  (SDK.HandlerMethod)
                  (SDK.Call (ReadReplyStatsGen))
              , SDK.MethodDefinition
                  (ReadReplyStatsGen)
                  (GetReplyStatsGen)
                  (SDK.ContextRequire)
                  (SDK.Choice ([SDK.Empty, SDK.Call (GetReplyStatsGen)]))
              , SDK.MethodDefinition
                  (GetReplyStatsGen)
                  (GetReplyStatsGen)
                  (SDK.ContextRequest)
                  (SDK.Call (ReadReplyGen))
              , SDK.MethodDefinition (OnBlankGen) (OnBlankGen) (SDK.HandlerMethod) (SDK.Call (ReadReportStateGen))
              , SDK.MethodDefinition
                  (ReadReportStateGen)
                  (GetReportStateGen)
                  (SDK.ContextRequire)
                  (SDK.Choice ([SDK.Empty, SDK.Call (GetReportStateGen)]))
              , SDK.MethodDefinition
                  (GetReportStateGen)
                  (GetReportStateGen)
                  (SDK.ContextRequest)
                  (SDK.Call (ReadReportPathGen))
              , SDK.MethodDefinition (OnFilledGen) (OnFilledGen) (SDK.HandlerMethod) (SDK.Call (ReadReportStateGen))
              , SDK.MethodDefinition (ShowAGen) (ShowAGen) (SDK.HandlerMethod) (SDK.Call (ReadLevelAGen))
              , SDK.MethodDefinition (ReadLevelAGen) (GetLevelAGen) (SDK.ContextRequire) (SDK.Empty)
              , SDK.MethodDefinition (ShowBGen) (ShowBGen) (SDK.HandlerMethod) (SDK.Call (ReadLevelBGen))
              , SDK.MethodDefinition (ReadLevelBGen) (GetLevelBGen) (SDK.ContextRequire) (SDK.Empty)
              , SDK.MethodDefinition (NextAGen) (NextAGen) (SDK.StreamHandler) (SDK.Empty)
              , SDK.MethodDefinition (GetLevelAGen) (GetLevelAGen) (SDK.ContextStream) (SDK.Call (NextAGen))
              , SDK.MethodDefinition (NextBGen) (NextBGen) (SDK.StreamHandler) (SDK.Empty)
              , SDK.MethodDefinition (GetLevelBGen) (GetLevelBGen) (SDK.ContextStream) (SDK.Call (NextBGen))
              ]
          , SDK.graphRoots =
              [ WriteReportGen
              , WriteReplyGen
              , ReadReportGen
              , ReadReplyGen
              , ShowReportGen
              , ShowReplyGen
              , OnBlankGen
              , OnFilledGen
              , ShowAGen
              , ShowBGen
              , ReadReportStateGen
              , NextAGen
              , GetLevelAGen
              , NextBGen
              , GetLevelBGen
              ]
          , SDK.graphReferences =
              [ (WriteReportGen, OpenReportGen)
              , (WriteReportGen, ReadOpenedReportGen)
              , (WriteReportGen, ReadReportBodyGen)
              , (OpenReportGen, GetOpenedReportGen)
              , (GetOpenedReportGen, ReadReportPathGen)
              , (ReadReportPathGen, GetReportPathGen)
              , (ReadReportBodyGen, GetReportBodyGen)
              , (WriteReplyGen, OpenReplyGen)
              , (WriteReplyGen, ReadOpenedReplyGen)
              , (WriteReplyGen, ReadReplyBodyGen)
              , (OpenReplyGen, GetOpenedReplyGen)
              , (GetOpenedReplyGen, ReadReplyPathGen)
              , (ReadReplyPathGen, GetReplyPathGen)
              , (ReadReplyBodyGen, GetReplyBodyGen)
              , (ReadReportGen, ReadReportPathGen)
              , (ReadReplyGen, MarkReplyGen)
              , (ReadReplyGen, ReadReplyPathGen)
              , (ShowReportGen, ReadReportStatsGen)
              , (ReadReportStatsGen, GetReportStatsGen)
              , (GetReportStatsGen, ReadReportGen)
              , (ShowReplyGen, ReadReplyStatsGen)
              , (ReadReplyStatsGen, GetReplyStatsGen)
              , (GetReplyStatsGen, ReadReplyGen)
              , (OnBlankGen, ReadReportStateGen)
              , (ReadReportStateGen, GetReportStateGen)
              , (GetReportStateGen, ReadReportPathGen)
              , (OnFilledGen, ReadReportStateGen)
              , (ShowAGen, ReadLevelAGen)
              , (ShowBGen, ReadLevelBGen)
              , (GetLevelAGen, NextAGen)
              , (GetLevelBGen, NextBGen)
              ]
          , SDK.graphScopes = [OpenReportGen, OpenReplyGen]
          , SDK.graphScopePaths = [[OpenReportGen], [OpenReplyGen], []]
          , SDK.graphRootPaths =
              [ (WriteReportGen, [[OpenReportGen]])
              , (WriteReplyGen, [[OpenReplyGen]])
              , (ReadReportGen, [[]])
              , (ReadReplyGen, [[]])
              , (ShowReportGen, [[]])
              , (ShowReplyGen, [[]])
              , (OnBlankGen, [[]])
              , (OnFilledGen, [[]])
              , (ShowAGen, [[]])
              , (ShowBGen, [[]])
              , (ReadReportStateGen, [[]])
              , (NextAGen, [[]])
              , (GetLevelAGen, [[]])
              , (NextBGen, [[]])
              , (GetLevelBGen, [[]])
              ]
          , SDK.graphScopeOrder = []
          }
    , SDK.protoScopes =
        SDK.ScopeTree
          { SDK.scopeRoots = [OpenReportGen, OpenReplyGen]
          , SDK.scopeNodes =
              [ SDK.ScopeNode
                  { SDK.scopeIdentity = OpenReportGen
                  , SDK.scopeParents = []
                  , SDK.scopeChildren = []
                  }
              , SDK.ScopeNode
                  { SDK.scopeIdentity = OpenReplyGen
                  , SDK.scopeParents = []
                  , SDK.scopeChildren = []
                  }
              ]
          , SDK.scopeLayers = [[OpenReportGen, OpenReplyGen]]
          , SDK.scopePaths = [[OpenReportGen], [OpenReplyGen], []]
          , SDK.scopeCandidates = []
          , SDK.scopeOpposed = []
          , SDK.scopeUndetermined = [(OpenReplyGen, OpenReportGen)]
          }
    , SDK.protoScopeNames = [(OpenReportGen, "ReportScope"), (OpenReplyGen, "ReplyScope")]
    , SDK.protoSources =
        [ (SDK.ReadPoint ([3,-1]) ("ReportPath"), SDK.FromChains ([[0,0], [1,0]]))
        , (SDK.ReadPoint ([3,-1]) ("ReportState"), SDK.FromOwnChain)
        , (SDK.ReadPoint ([2,1]) ("ReplyStats"), SDK.FromChains ([[1,1]]))
        , (SDK.ReadPoint ([2,0]) ("ReportStats"), SDK.FromChains ([[1,0]]))
        , (SDK.ReadPoint ([2,1]) ("ReplyPath"), SDK.FromChains ([[0,1], [1,1]]))
        , (SDK.ReadPoint ([2,0]) ("ReportPath"), SDK.FromChains ([[0,0], [1,0]]))
        , (SDK.ReadPoint ([1,1]) ("ReplyPath"), SDK.FromChains ([[0,1]]))
        , (SDK.ReadPoint ([1,0]) ("ReportPath"), SDK.FromChains ([[0,0]]))
        , (SDK.ReadPoint ([0,1]) ("ReplyBody"), SDK.FromOwnChain)
        , (SDK.ReadPoint ([0,1]) ("ReplyPath"), SDK.FromOwnChain)
        , (SDK.ReadPoint ([0,0]) ("ReportBody"), SDK.FromOwnChain)
        , (SDK.ReadPoint ([0,0]) ("ReportPath"), SDK.FromOwnChain)
        ]
    }
