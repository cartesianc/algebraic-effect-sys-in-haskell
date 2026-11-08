{-# LANGUAGE DuplicateRecordFields #-}

-- 自动生成；只登记末端入口与原型，执行由 SDK 的 interpreter 完成。
module FacadeProbe.Generated.Program where

import Framework.Generated (EffectSpec(..), EffectTyping(..), Asset(..), Handles(..), Demand(..), Access(..), TypeRef(..))
import qualified Framework.Generated as SDK
import qualified Framework.Effect.Contract as FrameworkRoot
import FacadeProbe.Generated.Effects
import qualified FacadeProbe.Generated.Handlers as Handlers
import FacadeProbe.Types


-- 仅汇总所选末端的成功结果，不保存共享绑定或增加完成包装。
data Results = WriteReportResult () | WriteReplyResult () | ReadReportResult () | ReadReplyResult () | ShowReportResult () | ShowReplyResult () | OnBlankResult () | OnFilledResult () | ShowAResult () | ShowBResult ()
  deriving Show

-- 末端共享生成的 scope 句柄；只创建空状态，Node algebra 才 lower。
-- 第二个列表是各转折契约的读取末端：读取资产，返回它当前的构造器名。
-- 第三个列表是各持续资产的生产步骤：会话按需启动，Stream 单步取得原始输入，parser 发布一次资产。
compiledEntries :: IO ([SDK.Target ContextValues Errors Results], [SDK.Target ContextValues Errors String]
                     , [(String, SDK.SessionSteps ContextValues Errors)])
compiledEntries = do
  scopes <- Handlers.newScopeHandlers
  pure
    ( [ SDK.targetApp "WriteReport" emptyContexts scopes (FrameworkRoot.withErrorHandlers Handlers.errorHandlers (FrameworkRoot.withAnchoredContexts Handlers.contextInjections (SDK.withScopeCleanups Handlers.scopeCleanups (WriteReportResult <$> (() <$ Handlers.runWriteReport)))))
      , SDK.targetApp "WriteReply" emptyContexts scopes (FrameworkRoot.withErrorHandlers Handlers.errorHandlers (FrameworkRoot.withAnchoredContexts Handlers.contextInjections (SDK.withScopeCleanups Handlers.scopeCleanups (WriteReplyResult <$> (() <$ Handlers.runWriteReply)))))
      , SDK.targetApp "ReadReport" emptyContexts scopes (FrameworkRoot.withErrorHandlers Handlers.errorHandlers (FrameworkRoot.withAnchoredContexts Handlers.contextInjections (SDK.withScopeCleanups Handlers.scopeCleanups (ReadReportResult <$> (() <$ Handlers.runReadReport)))))
      , SDK.targetApp "ReadReply" emptyContexts scopes (FrameworkRoot.withErrorHandlers Handlers.errorHandlers (FrameworkRoot.withAnchoredContexts Handlers.contextInjections (SDK.withScopeCleanups Handlers.scopeCleanups (ReadReplyResult <$> (() <$ Handlers.runReadReply)))))
      , SDK.targetApp "ShowReport" emptyContexts scopes (FrameworkRoot.withErrorHandlers Handlers.errorHandlers (FrameworkRoot.withAnchoredContexts Handlers.contextInjections (SDK.withScopeCleanups Handlers.scopeCleanups (ShowReportResult <$> (() <$ Handlers.runShowReport)))))
      , SDK.targetApp "ShowReply" emptyContexts scopes (FrameworkRoot.withErrorHandlers Handlers.errorHandlers (FrameworkRoot.withAnchoredContexts Handlers.contextInjections (SDK.withScopeCleanups Handlers.scopeCleanups (ShowReplyResult <$> (() <$ Handlers.runShowReply)))))
      , SDK.targetApp "OnBlank" emptyContexts scopes (FrameworkRoot.withErrorHandlers Handlers.errorHandlers (FrameworkRoot.withAnchoredContexts Handlers.contextInjections (SDK.withScopeCleanups Handlers.scopeCleanups (OnBlankResult <$> (() <$ Handlers.runOnBlank)))))
      , SDK.targetApp "OnFilled" emptyContexts scopes (FrameworkRoot.withErrorHandlers Handlers.errorHandlers (FrameworkRoot.withAnchoredContexts Handlers.contextInjections (SDK.withScopeCleanups Handlers.scopeCleanups (OnFilledResult <$> (() <$ Handlers.runOnFilled)))))
      , SDK.targetApp "ShowA" emptyContexts scopes (FrameworkRoot.withErrorHandlers Handlers.errorHandlers (FrameworkRoot.withAnchoredContexts Handlers.contextInjections (SDK.withScopeCleanups Handlers.scopeCleanups (ShowAResult <$> (() <$ Handlers.runShowA)))))
      , SDK.targetApp "ShowB" emptyContexts scopes (FrameworkRoot.withErrorHandlers Handlers.errorHandlers (FrameworkRoot.withAnchoredContexts Handlers.contextInjections (SDK.withScopeCleanups Handlers.scopeCleanups (ShowBResult <$> (() <$ Handlers.runShowB)))))
      ]
    , [ SDK.targetApp "ReportState" emptyContexts scopes (FrameworkRoot.withErrorHandlers Handlers.errorHandlers (FrameworkRoot.withAnchoredContexts Handlers.contextInjections (SDK.withScopeCleanups Handlers.scopeCleanups (caseOfReportState <$> Handlers.readReportState))))
      ]
    , [ ("ParserA", SDK.receiveSteps (SDK.targetApp "FeedA" emptyContexts scopes (FrameworkRoot.withErrorHandlers Handlers.errorHandlers (FrameworkRoot.withAnchoredContexts Handlers.contextInjections (SDK.withScopeCleanups Handlers.scopeCleanups (Handlers.nextFeedA))))) (SDK.targetApp "ParserA" emptyContexts scopes (FrameworkRoot.withErrorHandlers Handlers.errorHandlers (FrameworkRoot.withAnchoredContexts Handlers.contextInjections (SDK.withScopeCleanups Handlers.scopeCleanups (() <$ Handlers.getLevelA))))))
      , ("ParserB", SDK.receiveSteps (SDK.targetApp "FeedB" emptyContexts scopes (FrameworkRoot.withErrorHandlers Handlers.errorHandlers (FrameworkRoot.withAnchoredContexts Handlers.contextInjections (SDK.withScopeCleanups Handlers.scopeCleanups (Handlers.nextFeedB))))) (SDK.targetApp "ParserB" emptyContexts scopes (FrameworkRoot.withErrorHandlers Handlers.errorHandlers (FrameworkRoot.withAnchoredContexts Handlers.contextInjections (SDK.withScopeCleanups Handlers.scopeCleanups (() <$ Handlers.getLevelB))))))
      ]
    )

caseOfReportState :: ReportState -> String
caseOfReportState (ReportState value) = case value of
  Blank {} -> "Blank"
  Filled {} -> "Filled"

-- SDK 装配入口，不需要用户提供节点执行器或重复选择 handler。
interpreter :: SDK.AST -> [EffectSpec] -> IO ()
interpreter = SDK.interpreter "FacadeProbe" "demo/FacadeProbe/Handlers.hs" Handlers.handlerSourceFingerprint generatedPrototype compiledEntries
-- 生成时完成注册、方法、origin/ctx 链、资产来源、Workflow 和 scope 的统一分析。
-- NodeId 只在这份 AST 快照中有效；运行时校验后装配闭包。
generatedPrototype :: SDK.Prototype MethodGen
generatedPrototype =
  SDK.Prototype
    { SDK.protoRegistrations =
        [ SDK.EffectSpec
            { SDK.name = "ReportLocation"
            , SDK.typing =
                SDK.Context
                  (SDK.AssetDecl ("ReportPath") (SDK.TypeRef ("[Char]")))
                  (Just "reportLocation")
                  (True)
                  (False)
            , SDK.input = "Root"
            , SDK.demands = []
            }
        , SDK.EffectSpec
            { SDK.name = "ReplyLocation"
            , SDK.typing =
                SDK.Context
                  (SDK.AssetDecl ("ReplyPath") (SDK.TypeRef ("[Char]")))
                  (Just "replyLocation")
                  (True)
                  (False)
            , SDK.input = "Root"
            , SDK.demands = []
            }
        , SDK.EffectSpec
            { SDK.name = "ReportDraft"
            , SDK.typing =
                SDK.Context
                  (SDK.AssetDecl ("ReportBody") (SDK.TypeRef ("Body")))
                  (Just "reportDraft")
                  (True)
                  (False)
            , SDK.input = "Root"
            , SDK.demands = []
            }
        , SDK.EffectSpec
            { SDK.name = "ReplyDraft"
            , SDK.typing =
                SDK.Context (SDK.AssetDecl ("ReplyBody") (SDK.TypeRef ("Body"))) (Just "replyDraft") (True) (False)
            , SDK.input = "Root"
            , SDK.demands = []
            }
        , SDK.EffectSpec
            { SDK.name = "ReportFile"
            , SDK.typing =
                SDK.Context
                  (SDK.AssetDecl ("OpenedReport") (SDK.TypeRef ("TextFile")))
                  (Just "acquireFile")
                  (True)
                  (False)
            , SDK.input = "Root"
            , SDK.demands = [SDK.Demand (SDK.RequireAccess) ("ReportPath")]
            }
        , SDK.EffectSpec
            { SDK.name = "ReplyFile"
            , SDK.typing =
                SDK.Context
                  (SDK.AssetDecl ("OpenedReply") (SDK.TypeRef ("TextFile")))
                  (Just "acquireFile")
                  (True)
                  (False)
            , SDK.input = "Root"
            , SDK.demands = [SDK.Demand (SDK.RequireAccess) ("ReplyPath")]
            }
        , SDK.EffectSpec
            { SDK.name = "ReportScope"
            , SDK.typing = SDK.Scoped (Just "openTextFile") (Just "closeTextFile")
            , SDK.input = "Root"
            , SDK.demands =
                [SDK.Demand (SDK.RequestAccess) ("OpenedReport"), SDK.Demand (SDK.RequireAccess) ("OpenedReport")]
            }
        , SDK.EffectSpec
            { SDK.name = "ReplyScope"
            , SDK.typing = SDK.Scoped (Just "openTextFile") (Just "closeTextFile")
            , SDK.input = "Root"
            , SDK.demands =
                [SDK.Demand (SDK.RequestAccess) ("OpenedReply"), SDK.Demand (SDK.RequireAccess) ("OpenedReply")]
            }
        , SDK.EffectSpec
            { SDK.name = "WriteReport"
            , SDK.typing = SDK.Excu (Just "writeText")
            , SDK.input = "ReportScope"
            , SDK.demands =
                [SDK.Demand (SDK.RequireAccess) ("OpenedReport"), SDK.Demand (SDK.RequireAccess) ("ReportBody")]
            }
        , SDK.EffectSpec
            { SDK.name = "WriteReply"
            , SDK.typing = SDK.Excu (Just "writeText")
            , SDK.input = "ReplyScope"
            , SDK.demands =
                [SDK.Demand (SDK.RequireAccess) ("OpenedReply"), SDK.Demand (SDK.RequireAccess) ("ReplyBody")]
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
            , SDK.demands = [SDK.Demand (SDK.RequireAccess) ("ReportPath")]
            }
        , SDK.EffectSpec
            { SDK.name = "ReadReply"
            , SDK.typing = SDK.Excu (Just "readText")
            , SDK.input = "MarkReply"
            , SDK.demands = [SDK.Demand (SDK.RequireAccess) ("ReplyPath")]
            }
        , SDK.EffectSpec
            { SDK.name = "ReportCounter"
            , SDK.typing =
                SDK.Context
                  (SDK.AssetDecl ("ReportStats") (SDK.TypeRef ("LineCount")))
                  (Just "countLines")
                  (True)
                  (False)
            , SDK.input = "ReadReport"
            , SDK.demands = []
            }
        , SDK.EffectSpec
            { SDK.name = "ReplyCounter"
            , SDK.typing =
                SDK.Context
                  (SDK.AssetDecl ("ReplyStats") (SDK.TypeRef ("LineCount")))
                  (Just "countLines")
                  (True)
                  (False)
            , SDK.input = "ReadReply"
            , SDK.demands = []
            }
        , SDK.EffectSpec
            { SDK.name = "ShowReport"
            , SDK.typing = SDK.Excu (Just "showCount")
            , SDK.input = "Root"
            , SDK.demands = [SDK.Demand (SDK.RequireAccess) ("ReportStats")]
            }
        , SDK.EffectSpec
            { SDK.name = "ShowReply"
            , SDK.typing = SDK.Excu (Just "showCount")
            , SDK.input = "Root"
            , SDK.demands = [SDK.Demand (SDK.RequireAccess) ("ReplyStats")]
            }
        , SDK.EffectSpec
            { SDK.name = "ReportInspect"
            , SDK.typing =
                SDK.Context
                  (SDK.AssetDecl ("ReportState") (SDK.TypeRef ("FileState")))
                  (Just "inspectFile")
                  (True)
                  (False)
            , SDK.input = "Root"
            , SDK.demands = [SDK.Demand (SDK.RequireAccess) ("ReportPath")]
            }
        , SDK.EffectSpec
            { SDK.name = "OnBlank"
            , SDK.typing = SDK.Excu (Just "describeBlank")
            , SDK.input = "Root"
            , SDK.demands = [SDK.Demand (SDK.RequireAccess) ("ReportStateBlank")]
            }
        , SDK.EffectSpec
            { SDK.name = "OnFilled"
            , SDK.typing = SDK.Excu (Just "describeFilled")
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
                SDK.Context (SDK.AssetDecl ("LevelA") (SDK.TypeRef ("Level"))) (Just "parseLevel") (True) (True)
            , SDK.input = "FeedA"
            , SDK.demands = []
            }
        , SDK.EffectSpec
            { SDK.name = "ParserB"
            , SDK.typing =
                SDK.Context (SDK.AssetDecl ("LevelB") (SDK.TypeRef ("Level"))) (Just "parseLevel") (True) (True)
            , SDK.input = "FeedB"
            , SDK.demands = []
            }
        , SDK.EffectSpec
            { SDK.name = "ShowA"
            , SDK.typing = SDK.Excu (Just "showLevel")
            , SDK.input = "Root"
            , SDK.demands = [SDK.Demand (SDK.StreamAccess) ("LevelA")]
            }
        , SDK.EffectSpec
            { SDK.name = "ShowB"
            , SDK.typing = SDK.Excu (Just "showLevel")
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
            , SDK.effectMethods = [(SDK.ScopeOpen, OpenReportScopeGen), (SDK.ScopeClose, CloseReportScopeGen)]
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
            , SDK.effectMethods = [(SDK.ScopeOpen, OpenReplyScopeGen), (SDK.ScopeClose, CloseReplyScopeGen)]
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
            , SDK.effectMethods = [(SDK.HandlerMethod, RunWriteReportGen)]
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
            , SDK.effectMethods = [(SDK.HandlerMethod, RunWriteReplyGen)]
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
            , SDK.effectMethods = [(SDK.HandlerMethod, RunMarkReplyGen)]
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
            , SDK.effectMethods = [(SDK.HandlerMethod, RunReadReportGen)]
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
            , SDK.effectMethods = [(SDK.HandlerMethod, RunReadReplyGen)]
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
            , SDK.effectMethods = [(SDK.HandlerMethod, RunShowReportGen)]
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
            , SDK.effectMethods = [(SDK.HandlerMethod, RunShowReplyGen)]
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
            , SDK.effectMethods = [(SDK.HandlerMethod, RunOnBlankGen)]
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
            , SDK.effectMethods = [(SDK.HandlerMethod, RunOnFilledGen)]
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
            , SDK.effectMethods = [(SDK.StreamHandler, NextFeedAGen)]
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
            , SDK.effectMethods = [(SDK.StreamHandler, NextFeedBGen)]
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
            , SDK.effectMethods = [(SDK.ContextStream, GetLevelAGen), (SDK.ContextRequire, StreamLevelAGen)]
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
            , SDK.effectMethods = [(SDK.ContextStream, GetLevelBGen), (SDK.ContextRequire, StreamLevelBGen)]
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
            , SDK.effectMethods = [(SDK.HandlerMethod, RunShowAGen)]
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
            , SDK.effectMethods = [(SDK.HandlerMethod, RunShowBGen)]
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
        , SDK.MethodDefinition
            (OpenReportScopeGen)
            (OpenReportScopeGen)
            (SDK.ScopeOpen)
            (SDK.Sequence ([SDK.Call (GetOpenedReportGen), SDK.Call (ReadOpenedReportGen)]))
        , SDK.MethodDefinition
            (CloseReportScopeGen)
            (OpenReportScopeGen)
            (SDK.ScopeClose)
            (SDK.Call (ReadOpenedReportGen))
        , SDK.MethodDefinition
            (OpenReplyScopeGen)
            (OpenReplyScopeGen)
            (SDK.ScopeOpen)
            (SDK.Sequence ([SDK.Call (GetOpenedReplyGen), SDK.Call (ReadOpenedReplyGen)]))
        , SDK.MethodDefinition
            (CloseReplyScopeGen)
            (OpenReplyScopeGen)
            (SDK.ScopeClose)
            (SDK.Call (ReadOpenedReplyGen))
        , SDK.MethodDefinition
            (RunWriteReportGen)
            (RunWriteReportGen)
            (SDK.HandlerMethod)
            (
              SDK.Sequence
                ([SDK.Call (OpenReportScopeGen), SDK.Call (ReadOpenedReportGen), SDK.Call (ReadReportBodyGen)])
            )
        , SDK.MethodDefinition
            (RunWriteReplyGen)
            (RunWriteReplyGen)
            (SDK.HandlerMethod)
            (
              SDK.Sequence
                ([SDK.Call (OpenReplyScopeGen), SDK.Call (ReadOpenedReplyGen), SDK.Call (ReadReplyBodyGen)])
            )
        , SDK.MethodDefinition (RunMarkReplyGen) (RunMarkReplyGen) (SDK.HandlerMethod) (SDK.Empty)
        , SDK.MethodDefinition
            (RunReadReportGen)
            (RunReadReportGen)
            (SDK.HandlerMethod)
            (SDK.Sequence ([SDK.Call (ReadReportPathGen), SDK.Choice ([SDK.Empty, SDK.Sequence ([SDK.Empty])])]))
        , SDK.MethodDefinition
            (RunReadReplyGen)
            (RunReadReplyGen)
            (SDK.HandlerMethod)
            (
              SDK.Sequence
                (
                  [ SDK.Sequence ([SDK.Call (RunMarkReplyGen), SDK.Call (ReadReplyPathGen)])
                  , SDK.Choice ([SDK.Empty, SDK.Sequence ([SDK.Empty])])
                  ]
                )
            )
        , SDK.MethodDefinition
            (GetReportStatsGen)
            (GetReportStatsGen)
            (SDK.ContextRequest)
            (SDK.Call (RunReadReportGen))
        , SDK.MethodDefinition
            (ReadReportStatsGen)
            (GetReportStatsGen)
            (SDK.ContextRequire)
            (SDK.Choice ([SDK.Empty, SDK.Call (GetReportStatsGen)]))
        , SDK.MethodDefinition
            (GetReplyStatsGen)
            (GetReplyStatsGen)
            (SDK.ContextRequest)
            (SDK.Call (RunReadReplyGen))
        , SDK.MethodDefinition
            (ReadReplyStatsGen)
            (GetReplyStatsGen)
            (SDK.ContextRequire)
            (SDK.Choice ([SDK.Empty, SDK.Call (GetReplyStatsGen)]))
        , SDK.MethodDefinition
            (RunShowReportGen)
            (RunShowReportGen)
            (SDK.HandlerMethod)
            (SDK.Call (ReadReportStatsGen))
        , SDK.MethodDefinition
            (RunShowReplyGen)
            (RunShowReplyGen)
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
        , SDK.MethodDefinition (RunOnBlankGen) (RunOnBlankGen) (SDK.HandlerMethod) (SDK.Empty)
        , SDK.MethodDefinition
            (RunOnFilledGen)
            (RunOnFilledGen)
            (SDK.HandlerMethod)
            (SDK.Call (ReadReportStateGen))
        , SDK.MethodDefinition (NextFeedAGen) (NextFeedAGen) (SDK.StreamHandler) (SDK.Empty)
        , SDK.MethodDefinition (NextFeedBGen) (NextFeedBGen) (SDK.StreamHandler) (SDK.Empty)
        , SDK.MethodDefinition (GetLevelAGen) (GetLevelAGen) (SDK.ContextStream) (SDK.Call (NextFeedAGen))
        , SDK.MethodDefinition (StreamLevelAGen) (GetLevelAGen) (SDK.ContextRequire) (SDK.Empty)
        , SDK.MethodDefinition (GetLevelBGen) (GetLevelBGen) (SDK.ContextStream) (SDK.Call (NextFeedBGen))
        , SDK.MethodDefinition (StreamLevelBGen) (GetLevelBGen) (SDK.ContextRequire) (SDK.Empty)
        , SDK.MethodDefinition (RunShowAGen) (RunShowAGen) (SDK.HandlerMethod) (SDK.Call (StreamLevelAGen))
        , SDK.MethodDefinition (RunShowBGen) (RunShowBGen) (SDK.HandlerMethod) (SDK.Call (StreamLevelBGen))
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
            , SDK.chainEntry = RunWriteReportGen
            , SDK.chainReaches =
                [ RunWriteReportGen
                , OpenReportScopeGen
                , GetOpenedReportGen
                , ReadReportPathGen
                , GetReportPathGen
                , ReadOpenedReportGen
                , ReadReportBodyGen
                , GetReportBodyGen
                ]
            , SDK.chainDrives = ["ReportBody","ReportPath"]
            , SDK.chainReads = ["ReportBody","ReportPath"]
            , SDK.chainScopePaths = [[OpenReportScopeGen]]
            }
        , SDK.ChainProto
            { SDK.chainNode = [0,1]
            , SDK.chainRole = SDK.NodeChain
            , SDK.chainTerminal = "WriteReply"
            , SDK.chainEntry = RunWriteReplyGen
            , SDK.chainReaches =
                [ RunWriteReplyGen
                , OpenReplyScopeGen
                , GetOpenedReplyGen
                , ReadReplyPathGen
                , GetReplyPathGen
                , ReadOpenedReplyGen
                , ReadReplyBodyGen
                , GetReplyBodyGen
                ]
            , SDK.chainDrives = ["ReplyBody","ReplyPath"]
            , SDK.chainReads = ["ReplyBody","ReplyPath"]
            , SDK.chainScopePaths = [[OpenReplyScopeGen]]
            }
        , SDK.ChainProto
            { SDK.chainNode = [1,0]
            , SDK.chainRole = SDK.NodeChain
            , SDK.chainTerminal = "ReadReport"
            , SDK.chainEntry = RunReadReportGen
            , SDK.chainReaches = [RunReadReportGen, ReadReportPathGen, GetReportPathGen, GetReportStatsGen]
            , SDK.chainDrives = ["ReportPath","ReportStats"]
            , SDK.chainReads = ["ReportPath"]
            , SDK.chainScopePaths = [[]]
            }
        , SDK.ChainProto
            { SDK.chainNode = [1,1]
            , SDK.chainRole = SDK.NodeChain
            , SDK.chainTerminal = "ReadReply"
            , SDK.chainEntry = RunReadReplyGen
            , SDK.chainReaches =
                [RunReadReplyGen, RunMarkReplyGen, ReadReplyPathGen, GetReplyPathGen, GetReplyStatsGen]
            , SDK.chainDrives = ["ReplyPath","ReplyStats"]
            , SDK.chainReads = ["ReplyPath"]
            , SDK.chainScopePaths = [[]]
            }
        , SDK.ChainProto
            { SDK.chainNode = [2,0]
            , SDK.chainRole = SDK.NodeChain
            , SDK.chainTerminal = "ShowReport"
            , SDK.chainEntry = RunShowReportGen
            , SDK.chainReaches =
                [ RunShowReportGen
                , ReadReportStatsGen
                , GetReportStatsGen
                , RunReadReportGen
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
            , SDK.chainEntry = RunShowReplyGen
            , SDK.chainReaches =
                [ RunShowReplyGen
                , ReadReplyStatsGen
                , GetReplyStatsGen
                , RunReadReplyGen
                , RunMarkReplyGen
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
            , SDK.chainEntry = RunOnBlankGen
            , SDK.chainReaches = [RunOnBlankGen]
            , SDK.chainDrives = []
            , SDK.chainReads = []
            , SDK.chainScopePaths = [[]]
            }
        , SDK.ChainProto
            { SDK.chainNode = [3,1]
            , SDK.chainRole = SDK.NodeChain
            , SDK.chainTerminal = "OnFilled"
            , SDK.chainEntry = RunOnFilledGen
            , SDK.chainReaches =
                [RunOnFilledGen, ReadReportStateGen, GetReportStateGen, ReadReportPathGen, GetReportPathGen]
            , SDK.chainDrives = []
            , SDK.chainReads = []
            , SDK.chainScopePaths = [[]]
            }
        , SDK.ChainProto
            { SDK.chainNode = [4,0]
            , SDK.chainRole = SDK.NodeChain
            , SDK.chainTerminal = "ShowA"
            , SDK.chainEntry = RunShowAGen
            , SDK.chainReaches = [RunShowAGen, StreamLevelAGen]
            , SDK.chainDrives = []
            , SDK.chainReads = []
            , SDK.chainScopePaths = [[]]
            }
        , SDK.ChainProto
            { SDK.chainNode = [4,1]
            , SDK.chainRole = SDK.NodeChain
            , SDK.chainTerminal = "ShowB"
            , SDK.chainEntry = RunShowBGen
            , SDK.chainReaches = [RunShowBGen, StreamLevelBGen]
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
            , SDK.chainEntry = NextFeedAGen
            , SDK.chainReaches = [NextFeedAGen]
            , SDK.chainDrives = []
            , SDK.chainReads = []
            , SDK.chainScopePaths = [[]]
            }
        , SDK.ChainProto
            { SDK.chainNode = [4,-1,0,1]
            , SDK.chainRole = SDK.SessionChain
            , SDK.chainTerminal = "LevelA"
            , SDK.chainEntry = GetLevelAGen
            , SDK.chainReaches = [GetLevelAGen, NextFeedAGen]
            , SDK.chainDrives = ["LevelA"]
            , SDK.chainReads = []
            , SDK.chainScopePaths = [[]]
            }
        , SDK.ChainProto
            { SDK.chainNode = [4,-1,1,0]
            , SDK.chainRole = SDK.SessionChain
            , SDK.chainTerminal = "LevelB"
            , SDK.chainEntry = NextFeedBGen
            , SDK.chainReaches = [NextFeedBGen]
            , SDK.chainDrives = []
            , SDK.chainReads = []
            , SDK.chainScopePaths = [[]]
            }
        , SDK.ChainProto
            { SDK.chainNode = [4,-1,1,1]
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
            , SDK.definitionEntry = OpenReportScopeGen
            , SDK.definitionReaches =
                [OpenReportScopeGen, GetOpenedReportGen, ReadReportPathGen, GetReportPathGen, ReadOpenedReportGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.OriginChain
            , SDK.definitionEffect = "ReplyScope"
            , SDK.definitionEntry = OpenReplyScopeGen
            , SDK.definitionReaches =
                [OpenReplyScopeGen, GetOpenedReplyGen, ReadReplyPathGen, GetReplyPathGen, ReadOpenedReplyGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.OriginChain
            , SDK.definitionEffect = "WriteReport"
            , SDK.definitionEntry = RunWriteReportGen
            , SDK.definitionReaches =
                [ RunWriteReportGen
                , OpenReportScopeGen
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
            , SDK.definitionEntry = RunWriteReplyGen
            , SDK.definitionReaches =
                [ RunWriteReplyGen
                , OpenReplyScopeGen
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
            , SDK.definitionEntry = RunMarkReplyGen
            , SDK.definitionReaches = [RunMarkReplyGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.OriginChain
            , SDK.definitionEffect = "ReadReport"
            , SDK.definitionEntry = RunReadReportGen
            , SDK.definitionReaches =
                [RunReadReportGen, ReadReportPathGen, GetReportPathGen, GetReportStatsGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.OriginChain
            , SDK.definitionEffect = "ReadReply"
            , SDK.definitionEntry = RunReadReplyGen
            , SDK.definitionReaches =
                [RunReadReplyGen, RunMarkReplyGen, ReadReplyPathGen, GetReplyPathGen, GetReplyStatsGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.ContextChain
            , SDK.definitionEffect = "ReportCounter"
            , SDK.definitionEntry = GetReportStatsGen
            , SDK.definitionReaches =
                [GetReportStatsGen, RunReadReportGen, ReadReportPathGen, GetReportPathGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.ContextChain
            , SDK.definitionEffect = "ReportCounter"
            , SDK.definitionEntry = ReadReportStatsGen
            , SDK.definitionReaches =
                [ReadReportStatsGen, GetReportStatsGen, RunReadReportGen, ReadReportPathGen, GetReportPathGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.ContextChain
            , SDK.definitionEffect = "ReplyCounter"
            , SDK.definitionEntry = GetReplyStatsGen
            , SDK.definitionReaches =
                [GetReplyStatsGen, RunReadReplyGen, RunMarkReplyGen, ReadReplyPathGen, GetReplyPathGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.ContextChain
            , SDK.definitionEffect = "ReplyCounter"
            , SDK.definitionEntry = ReadReplyStatsGen
            , SDK.definitionReaches =
                [ ReadReplyStatsGen
                , GetReplyStatsGen
                , RunReadReplyGen
                , RunMarkReplyGen
                , ReadReplyPathGen
                , GetReplyPathGen
                ]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.OriginChain
            , SDK.definitionEffect = "ShowReport"
            , SDK.definitionEntry = RunShowReportGen
            , SDK.definitionReaches =
                [ RunShowReportGen
                , ReadReportStatsGen
                , GetReportStatsGen
                , RunReadReportGen
                , ReadReportPathGen
                , GetReportPathGen
                ]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.OriginChain
            , SDK.definitionEffect = "ShowReply"
            , SDK.definitionEntry = RunShowReplyGen
            , SDK.definitionReaches =
                [ RunShowReplyGen
                , ReadReplyStatsGen
                , GetReplyStatsGen
                , RunReadReplyGen
                , RunMarkReplyGen
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
            , SDK.definitionEntry = RunOnBlankGen
            , SDK.definitionReaches = [RunOnBlankGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.OriginChain
            , SDK.definitionEffect = "OnFilled"
            , SDK.definitionEntry = RunOnFilledGen
            , SDK.definitionReaches =
                [RunOnFilledGen, ReadReportStateGen, GetReportStateGen, ReadReportPathGen, GetReportPathGen]
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
                  (RunWriteReportGen)
                  (RunWriteReportGen)
                  (SDK.HandlerMethod)
                  (
                    SDK.Sequence
                      ([SDK.Call (OpenReportScopeGen), SDK.Call (ReadOpenedReportGen), SDK.Call (ReadReportBodyGen)])
                  )
              , SDK.MethodDefinition
                  (OpenReportScopeGen)
                  (OpenReportScopeGen)
                  (SDK.ScopeOpen)
                  (SDK.Sequence ([SDK.Call (GetOpenedReportGen), SDK.Call (ReadOpenedReportGen)]))
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
                  (RunWriteReplyGen)
                  (RunWriteReplyGen)
                  (SDK.HandlerMethod)
                  (
                    SDK.Sequence
                      ([SDK.Call (OpenReplyScopeGen), SDK.Call (ReadOpenedReplyGen), SDK.Call (ReadReplyBodyGen)])
                  )
              , SDK.MethodDefinition
                  (OpenReplyScopeGen)
                  (OpenReplyScopeGen)
                  (SDK.ScopeOpen)
                  (SDK.Sequence ([SDK.Call (GetOpenedReplyGen), SDK.Call (ReadOpenedReplyGen)]))
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
                  (RunReadReportGen)
                  (RunReadReportGen)
                  (SDK.HandlerMethod)
                  (SDK.Sequence ([SDK.Call (ReadReportPathGen), SDK.Choice ([SDK.Empty, SDK.Sequence ([SDK.Empty])])]))
              , SDK.MethodDefinition
                  (RunReadReplyGen)
                  (RunReadReplyGen)
                  (SDK.HandlerMethod)
                  (
                    SDK.Sequence
                      (
                        [ SDK.Sequence ([SDK.Call (RunMarkReplyGen), SDK.Call (ReadReplyPathGen)])
                        , SDK.Choice ([SDK.Empty, SDK.Sequence ([SDK.Empty])])
                        ]
                      )
                  )
              , SDK.MethodDefinition (RunMarkReplyGen) (RunMarkReplyGen) (SDK.HandlerMethod) (SDK.Empty)
              , SDK.MethodDefinition
                  (RunShowReportGen)
                  (RunShowReportGen)
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
                  (SDK.Call (RunReadReportGen))
              , SDK.MethodDefinition
                  (RunShowReplyGen)
                  (RunShowReplyGen)
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
                  (SDK.Call (RunReadReplyGen))
              , SDK.MethodDefinition (RunOnBlankGen) (RunOnBlankGen) (SDK.HandlerMethod) (SDK.Empty)
              , SDK.MethodDefinition
                  (RunOnFilledGen)
                  (RunOnFilledGen)
                  (SDK.HandlerMethod)
                  (SDK.Call (ReadReportStateGen))
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
              , SDK.MethodDefinition (RunShowAGen) (RunShowAGen) (SDK.HandlerMethod) (SDK.Call (StreamLevelAGen))
              , SDK.MethodDefinition (StreamLevelAGen) (GetLevelAGen) (SDK.ContextRequire) (SDK.Empty)
              , SDK.MethodDefinition (RunShowBGen) (RunShowBGen) (SDK.HandlerMethod) (SDK.Call (StreamLevelBGen))
              , SDK.MethodDefinition (StreamLevelBGen) (GetLevelBGen) (SDK.ContextRequire) (SDK.Empty)
              , SDK.MethodDefinition (NextFeedAGen) (NextFeedAGen) (SDK.StreamHandler) (SDK.Empty)
              , SDK.MethodDefinition (GetLevelAGen) (GetLevelAGen) (SDK.ContextStream) (SDK.Call (NextFeedAGen))
              , SDK.MethodDefinition (NextFeedBGen) (NextFeedBGen) (SDK.StreamHandler) (SDK.Empty)
              , SDK.MethodDefinition (GetLevelBGen) (GetLevelBGen) (SDK.ContextStream) (SDK.Call (NextFeedBGen))
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
              , ReadReportStateGen
              , NextFeedAGen
              , GetLevelAGen
              , NextFeedBGen
              , GetLevelBGen
              ]
          , SDK.graphReferences =
              [ (RunWriteReportGen, OpenReportScopeGen)
              , (RunWriteReportGen, ReadOpenedReportGen)
              , (RunWriteReportGen, ReadReportBodyGen)
              , (OpenReportScopeGen, GetOpenedReportGen)
              , (OpenReportScopeGen, ReadOpenedReportGen)
              , (GetOpenedReportGen, ReadReportPathGen)
              , (ReadReportPathGen, GetReportPathGen)
              , (ReadReportBodyGen, GetReportBodyGen)
              , (RunWriteReplyGen, OpenReplyScopeGen)
              , (RunWriteReplyGen, ReadOpenedReplyGen)
              , (RunWriteReplyGen, ReadReplyBodyGen)
              , (OpenReplyScopeGen, GetOpenedReplyGen)
              , (OpenReplyScopeGen, ReadOpenedReplyGen)
              , (GetOpenedReplyGen, ReadReplyPathGen)
              , (ReadReplyPathGen, GetReplyPathGen)
              , (ReadReplyBodyGen, GetReplyBodyGen)
              , (RunReadReportGen, ReadReportPathGen)
              , (RunReadReplyGen, RunMarkReplyGen)
              , (RunReadReplyGen, ReadReplyPathGen)
              , (RunShowReportGen, ReadReportStatsGen)
              , (ReadReportStatsGen, GetReportStatsGen)
              , (GetReportStatsGen, RunReadReportGen)
              , (RunShowReplyGen, ReadReplyStatsGen)
              , (ReadReplyStatsGen, GetReplyStatsGen)
              , (GetReplyStatsGen, RunReadReplyGen)
              , (RunOnFilledGen, ReadReportStateGen)
              , (ReadReportStateGen, GetReportStateGen)
              , (GetReportStateGen, ReadReportPathGen)
              , (RunShowAGen, StreamLevelAGen)
              , (RunShowBGen, StreamLevelBGen)
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
              , (ReadReportStateGen, [[]])
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
