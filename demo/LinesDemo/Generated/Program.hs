{-# LANGUAGE DuplicateRecordFields #-}

-- 自动生成；只登记末端入口与原型，执行由 SDK 的 interpreter 完成。
module LinesDemo.Generated.Program where

import Framework.Generated (EffectSpec(..), EffectTyping(..), Asset(..), Handles(..), Demand(..), Access(..), TypeRef(..))
import qualified Framework.Generated as SDK
import LinesDemo.Generated.Effects
import qualified LinesDemo.Generated.Handlers as Handlers
import LinesDemo.Types


-- 仅汇总所选末端的成功结果，不保存共享绑定或增加完成包装。
data Results = AnnounceResult () | PrintLineResult () | TextCounterResult () | ShowTotalResult () | ReportResult ()
  deriving Show

-- 末端共享生成的 scope 句柄；只创建空状态，Node algebra 才 lower。
-- 第二个列表是各转折契约的选择末端：驱动资产（持续资产领取本次交付），返回它当前的构造器名。
-- 第三个列表是各持续资产的生产步骤：会话按需启动，Stream 单步取得原始输入（或领取一条上游交付），parser 发布一次资产。
compiledEntries :: IO ([SDK.Target ContextValues Errors Results], [SDK.Target ContextValues Errors String]
                     , [(String, SDK.SessionSteps ContextValues Errors)])
compiledEntries = do
  scopes <- Handlers.newScopeHandlers
  pure
    ( [ SDK.targetApp "Announce" emptyContexts scopes (SDK.withErrorHandlers Handlers.errorHandlers (SDK.withAnchoredContexts Handlers.contextInjections (SDK.withStreamContexts Handlers.streamContextInjections (SDK.withScopeCleanups Handlers.scopeCleanups (AnnounceResult <$> (() <$ Handlers.runAnnounce))))))
      , SDK.targetApp "PrintLine" emptyContexts scopes (SDK.withErrorHandlers Handlers.errorHandlers (SDK.withAnchoredContexts Handlers.contextInjections (SDK.withStreamContexts Handlers.streamContextInjections (SDK.withScopeCleanups Handlers.scopeCleanups (PrintLineResult <$> (() <$ Handlers.runPrintLine))))))
      , SDK.targetApp "TextCounter" emptyContexts scopes (SDK.withErrorHandlers Handlers.errorHandlers (SDK.withAnchoredContexts Handlers.contextInjections (SDK.withStreamContexts Handlers.streamContextInjections (SDK.withScopeCleanups Handlers.scopeCleanups (TextCounterResult <$> (() <$ Handlers.runTextCounter))))))
      , SDK.targetApp "ShowTotal" emptyContexts scopes (SDK.withErrorHandlers Handlers.errorHandlers (SDK.withAnchoredContexts Handlers.contextInjections (SDK.withStreamContexts Handlers.streamContextInjections (SDK.withScopeCleanups Handlers.scopeCleanups (ShowTotalResult <$> (() <$ Handlers.runShowTotal))))))
      , SDK.targetApp "Report" emptyContexts scopes (SDK.withErrorHandlers Handlers.errorHandlers (SDK.withAnchoredContexts Handlers.contextInjections (SDK.withStreamContexts Handlers.streamContextInjections (SDK.withScopeCleanups Handlers.scopeCleanups (ReportResult <$> (() <$ Handlers.runReport))))))
      ]
    , []
    , [ ("LineParser", SDK.receiveSteps (SDK.targetApp "LineFeed" emptyContexts scopes (SDK.withErrorHandlers Handlers.errorHandlers (SDK.withAnchoredContexts Handlers.contextInjections (SDK.withStreamContexts Handlers.streamContextInjections (SDK.withScopeCleanups Handlers.scopeCleanups (Handlers.nextLineFeed)))))) (SDK.targetApp "LineParser" emptyContexts scopes (SDK.withErrorHandlers Handlers.errorHandlers (SDK.withAnchoredContexts Handlers.contextInjections (SDK.withStreamContexts Handlers.streamContextInjections (SDK.withScopeCleanups Handlers.scopeCleanups (() <$ Handlers.getTextLine)))))))
      , ("CountParser", SDK.deriveSteps (SDK.targetApp "CountParser" emptyContexts scopes (SDK.withErrorHandlers Handlers.errorHandlers (SDK.withAnchoredContexts Handlers.contextInjections (SDK.withStreamContexts Handlers.streamContextInjections (SDK.withScopeCleanups Handlers.scopeCleanups (() <$ Handlers.getRunningTotal)))))))
      ]
    )

-- SDK 装配入口，不需要用户提供节点执行器或重复选择 handler。
interpreter :: SDK.AST -> [EffectSpec] -> IO ()
interpreter = SDK.interpreter "LinesDemo" "demo/LinesDemo/Handlers.hs" Handlers.handlerSourceFingerprint generatedPrototype compiledEntries
-- 生成时完成注册、方法、origin/ctx 链、资产来源、Workflow 和 scope 的统一分析。
-- NodeId 只在这份 AST 快照中有效；运行时校验后装配闭包。
generatedPrototype :: SDK.Prototype MethodGen
generatedPrototype =
  SDK.Prototype
    { SDK.protoRegistrations =
        [ SDK.EffectSpec
            { SDK.name = "Announce"
            , SDK.typing = SDK.Excu (Just "announce")
            , SDK.input = "Root"
            , SDK.demands = []
            }
        , SDK.EffectSpec
            { SDK.name = "InputResource"
            , SDK.typing =
                SDK.Context
                  (SDK.AssetDecl ("OpenedInput") (SDK.TypeRef ("InputFile")))
                  (Just "acquireInput")
                  (True)
                  (False)
            , SDK.input = "Root"
            , SDK.demands = []
            }
        , SDK.EffectSpec
            { SDK.name = "InputSession"
            , SDK.typing = SDK.Scoped (Just "openInput") (Just "closeInput")
            , SDK.input = "Root"
            , SDK.demands =
                [SDK.Demand (SDK.RequestAccess) ("OpenedInput"), SDK.Demand (SDK.RequireAccess) ("OpenedInput")]
            }
        , SDK.EffectSpec
            { SDK.name = "LineFeed"
            , SDK.typing = SDK.Stream (Just "nextLine")
            , SDK.input = "InputSession"
            , SDK.demands = [SDK.Demand (SDK.RequireAccess) ("OpenedInput")]
            }
        , SDK.EffectSpec
            { SDK.name = "LineParser"
            , SDK.typing =
                SDK.Context (SDK.AssetDecl ("TextLine") (SDK.TypeRef ("Line"))) (Just "parseLine") (True) (True)
            , SDK.input = "LineFeed"
            , SDK.demands = []
            }
        , SDK.EffectSpec
            { SDK.name = "PrintLine"
            , SDK.typing = SDK.Excu (Just "printLine")
            , SDK.input = "Root"
            , SDK.demands = [SDK.Demand (SDK.StreamAccess) ("TextLine")]
            }
        , SDK.EffectSpec
            { SDK.name = "TextCounter"
            , SDK.typing = SDK.Excu (Just "countText")
            , SDK.input = "InputSession"
            , SDK.demands =
                [SDK.Demand (SDK.StreamAccess) ("TextLine"), SDK.Demand (SDK.RequireAccess) ("OpenedInput")]
            }
        , SDK.EffectSpec
            { SDK.name = "CountParser"
            , SDK.typing =
                SDK.Context
                  (SDK.AssetDecl ("RunningTotal") (SDK.TypeRef ("Total")))
                  (Just "parseTotal")
                  (True)
                  (True)
            , SDK.input = "TextCounter"
            , SDK.demands = []
            }
        , SDK.EffectSpec
            { SDK.name = "ShowTotal"
            , SDK.typing = SDK.Excu (Just "showTotal")
            , SDK.input = "Root"
            , SDK.demands = [SDK.Demand (SDK.StreamAccess) ("RunningTotal")]
            }
        , SDK.EffectSpec
            { SDK.name = "Report"
            , SDK.typing = SDK.Excu (Just "report")
            , SDK.input = "Root"
            , SDK.demands = [SDK.Demand (SDK.RequireAccess) ("RunningTotal")]
            }
        ]
    , SDK.protoEffects =
        [ SDK.EffectProto
            { SDK.effectName = "Announce"
            , SDK.effectKind = SDK.ExcuKind
            , SDK.effectInput = "Root"
            , SDK.effectMethods = [(SDK.HandlerMethod, RunAnnounceGen)]
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
            { SDK.effectName = "InputResource"
            , SDK.effectKind = SDK.ContextKind
            , SDK.effectInput = "Root"
            , SDK.effectMethods =
                [(SDK.ContextRequest, GetOpenedInputGen), (SDK.ContextRequire, ReadOpenedInputGen)]
            , SDK.effectDemands = []
            , SDK.effectProduces = Just "OpenedInput"
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
            { SDK.effectName = "InputSession"
            , SDK.effectKind = SDK.ScopedKind
            , SDK.effectInput = "Root"
            , SDK.effectMethods =
                [(SDK.ScopeOpen, OpenInputSessionGen), (SDK.ScopeClose, CloseInputSessionGen)]
            , SDK.effectDemands =
                [ SDK.ResolvedDemand (SDK.RequestAccess) ("OpenedInput") ("InputResource")
                , SDK.ResolvedDemand (SDK.RequireAccess) ("OpenedInput") ("InputResource")
                ]
            , SDK.effectProduces = Nothing
            , SDK.effectBranches = []
            , SDK.effectAnchor = Nothing
            , SDK.effectScopes = []
            , SDK.effectErrorScope = Nothing
            , SDK.effectInputChain = []
            , SDK.effectScopeParents = []
            , SDK.effectOpeningInputs = []
            , SDK.effectNearestScopes = ["InputSession"]
            , SDK.effectResource = Just "InputResource"
            , SDK.effectContextDependencies = ["InputResource"]
            , SDK.effectContinuous = False
            }
        , SDK.EffectProto
            { SDK.effectName = "LineFeed"
            , SDK.effectKind = SDK.StreamKind
            , SDK.effectInput = "InputSession"
            , SDK.effectMethods = [(SDK.StreamHandler, NextLineFeedGen)]
            , SDK.effectDemands = [SDK.ResolvedDemand (SDK.RequireAccess) ("OpenedInput") ("InputResource")]
            , SDK.effectProduces = Nothing
            , SDK.effectBranches = []
            , SDK.effectAnchor = Nothing
            , SDK.effectScopes = ["InputSession"]
            , SDK.effectErrorScope = Nothing
            , SDK.effectInputChain = ["InputSession"]
            , SDK.effectScopeParents = ["InputSession"]
            , SDK.effectOpeningInputs = []
            , SDK.effectNearestScopes = ["InputSession"]
            , SDK.effectResource = Nothing
            , SDK.effectContextDependencies = ["InputResource"]
            , SDK.effectContinuous = False
            }
        , SDK.EffectProto
            { SDK.effectName = "LineParser"
            , SDK.effectKind = SDK.ContextKind
            , SDK.effectInput = "LineFeed"
            , SDK.effectMethods =
                [(SDK.ContextStream, GetTextLineGen), (SDK.ContextRequire, StreamTextLineGen)]
            , SDK.effectDemands = []
            , SDK.effectProduces = Just "TextLine"
            , SDK.effectBranches = []
            , SDK.effectAnchor = Nothing
            , SDK.effectScopes = ["InputSession"]
            , SDK.effectErrorScope = Nothing
            , SDK.effectInputChain = ["LineFeed","InputSession"]
            , SDK.effectScopeParents = ["InputSession"]
            , SDK.effectOpeningInputs = []
            , SDK.effectNearestScopes = ["InputSession"]
            , SDK.effectResource = Nothing
            , SDK.effectContextDependencies = ["InputResource"]
            , SDK.effectContinuous = True
            }
        , SDK.EffectProto
            { SDK.effectName = "PrintLine"
            , SDK.effectKind = SDK.ExcuKind
            , SDK.effectInput = "Root"
            , SDK.effectMethods = [(SDK.HandlerMethod, RunPrintLineGen)]
            , SDK.effectDemands = [SDK.ResolvedDemand (SDK.StreamAccess) ("TextLine") ("LineParser")]
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
            , SDK.effectContextDependencies = ["InputResource","LineParser"]
            , SDK.effectContinuous = False
            }
        , SDK.EffectProto
            { SDK.effectName = "TextCounter"
            , SDK.effectKind = SDK.ExcuKind
            , SDK.effectInput = "InputSession"
            , SDK.effectMethods = [(SDK.HandlerMethod, RunTextCounterGen)]
            , SDK.effectDemands =
                [ SDK.ResolvedDemand (SDK.StreamAccess) ("TextLine") ("LineParser")
                , SDK.ResolvedDemand (SDK.RequireAccess) ("OpenedInput") ("InputResource")
                ]
            , SDK.effectProduces = Nothing
            , SDK.effectBranches = []
            , SDK.effectAnchor = Nothing
            , SDK.effectScopes = ["InputSession"]
            , SDK.effectErrorScope = Nothing
            , SDK.effectInputChain = ["InputSession"]
            , SDK.effectScopeParents = ["InputSession"]
            , SDK.effectOpeningInputs = []
            , SDK.effectNearestScopes = ["InputSession"]
            , SDK.effectResource = Nothing
            , SDK.effectContextDependencies = ["InputResource","LineParser"]
            , SDK.effectContinuous = False
            }
        , SDK.EffectProto
            { SDK.effectName = "CountParser"
            , SDK.effectKind = SDK.ContextKind
            , SDK.effectInput = "TextCounter"
            , SDK.effectMethods =
                [(SDK.ContextStream, GetRunningTotalGen), (SDK.ContextRequire, StreamRunningTotalGen)]
            , SDK.effectDemands = []
            , SDK.effectProduces = Just "RunningTotal"
            , SDK.effectBranches = []
            , SDK.effectAnchor = Just "TextCounter"
            , SDK.effectScopes = ["InputSession"]
            , SDK.effectErrorScope = Nothing
            , SDK.effectInputChain = ["TextCounter","InputSession"]
            , SDK.effectScopeParents = ["InputSession"]
            , SDK.effectOpeningInputs = []
            , SDK.effectNearestScopes = ["InputSession"]
            , SDK.effectResource = Nothing
            , SDK.effectContextDependencies = ["InputResource","LineParser"]
            , SDK.effectContinuous = True
            }
        , SDK.EffectProto
            { SDK.effectName = "ShowTotal"
            , SDK.effectKind = SDK.ExcuKind
            , SDK.effectInput = "Root"
            , SDK.effectMethods = [(SDK.HandlerMethod, RunShowTotalGen)]
            , SDK.effectDemands = [SDK.ResolvedDemand (SDK.StreamAccess) ("RunningTotal") ("CountParser")]
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
            , SDK.effectContextDependencies = ["InputResource","LineParser","CountParser"]
            , SDK.effectContinuous = False
            }
        , SDK.EffectProto
            { SDK.effectName = "Report"
            , SDK.effectKind = SDK.ExcuKind
            , SDK.effectInput = "Root"
            , SDK.effectMethods = [(SDK.HandlerMethod, RunReportGen)]
            , SDK.effectDemands = [SDK.ResolvedDemand (SDK.RequireAccess) ("RunningTotal") ("CountParser")]
            , SDK.effectProduces = Nothing
            , SDK.effectBranches = []
            , SDK.effectAnchor = Nothing
            , SDK.effectScopes = []
            , SDK.effectErrorScope = Nothing
            , SDK.effectInputChain = []
            , SDK.effectScopeParents = ["InputSession"]
            , SDK.effectOpeningInputs = []
            , SDK.effectNearestScopes = []
            , SDK.effectResource = Nothing
            , SDK.effectContextDependencies = ["InputResource","LineParser","CountParser"]
            , SDK.effectContinuous = False
            }
        ]
    , SDK.protoMethods =
        [ SDK.MethodDefinition (RunAnnounceGen) (RunAnnounceGen) (SDK.HandlerMethod) (SDK.Empty)
        , SDK.MethodDefinition (GetOpenedInputGen) (GetOpenedInputGen) (SDK.ContextRequest) (SDK.Empty)
        , SDK.MethodDefinition (ReadOpenedInputGen) (GetOpenedInputGen) (SDK.ContextRequire) (SDK.Empty)
        , SDK.MethodDefinition
            (OpenInputSessionGen)
            (OpenInputSessionGen)
            (SDK.ScopeOpen)
            (SDK.Sequence ([SDK.Call (GetOpenedInputGen), SDK.Call (ReadOpenedInputGen)]))
        , SDK.MethodDefinition
            (CloseInputSessionGen)
            (OpenInputSessionGen)
            (SDK.ScopeClose)
            (SDK.Call (ReadOpenedInputGen))
        , SDK.MethodDefinition
            (NextLineFeedGen)
            (NextLineFeedGen)
            (SDK.StreamHandler)
            (SDK.Sequence ([SDK.Call (OpenInputSessionGen), SDK.Call (ReadOpenedInputGen)]))
        , SDK.MethodDefinition
            (GetTextLineGen)
            (GetTextLineGen)
            (SDK.ContextStream)
            (SDK.Call (NextLineFeedGen))
        , SDK.MethodDefinition (StreamTextLineGen) (GetTextLineGen) (SDK.ContextRequire) (SDK.Empty)
        , SDK.MethodDefinition
            (RunPrintLineGen)
            (RunPrintLineGen)
            (SDK.HandlerMethod)
            (SDK.Call (StreamTextLineGen))
        , SDK.MethodDefinition
            (RunTextCounterGen)
            (RunTextCounterGen)
            (SDK.HandlerMethod)
            (
              SDK.Sequence
                (
                  [ SDK.Sequence
                      ([SDK.Call (OpenInputSessionGen), SDK.Call (StreamTextLineGen), SDK.Call (ReadOpenedInputGen)])
                  , SDK.Choice ([SDK.Empty, SDK.Sequence ([SDK.Empty])])
                  ]
                )
            )
        , SDK.MethodDefinition
            (GetRunningTotalGen)
            (GetRunningTotalGen)
            (SDK.ContextStream)
            (SDK.Call (RunTextCounterGen))
        , SDK.MethodDefinition (StreamRunningTotalGen) (GetRunningTotalGen) (SDK.ContextRequire) (SDK.Empty)
        , SDK.MethodDefinition
            (RunShowTotalGen)
            (RunShowTotalGen)
            (SDK.HandlerMethod)
            (SDK.Call (StreamRunningTotalGen))
        , SDK.MethodDefinition
            (RunReportGen)
            (RunReportGen)
            (SDK.HandlerMethod)
            (SDK.Call (StreamRunningTotalGen))
        ]
    , SDK.protoWorkflow =
        SDK.ChainedAt
          ([])
          (
            [ SDK.ChainedAt
                ([0])
                (
                  [ SDK.NodeAt ([0,0]) ("Announce")
                  ]
                )
            , SDK.LifelongAt
                ([1])
                (
                  SDK.LifelongProto
                    { SDK.lifelongUnits = [[1,0,0],[1,0,1]]
                    , SDK.lifelongSubscriptions =
                        [([1,0,0,0],"TextLine"),([1,0,0,1],"TextLine"),([1,0,1,0],"RunningTotal")]
                    , SDK.lifelongSessions =
                        [ SDK.SessionProto
                            { SDK.sessionAsset = "TextLine"
                            , SDK.sessionPlan = SDK.Receive ("LineFeed")
                            , SDK.sessionMounts = [[1,-1,0,0],[1,-1,0,1]]
                            }
                        , SDK.SessionProto
                            { SDK.sessionAsset = "RunningTotal"
                            , SDK.sessionPlan = SDK.ReuseOutput ([[1,0,0,1]])
                            , SDK.sessionMounts = []
                            }
                        ]
                    }
                )
                (
                  [ SDK.ParallelAt
                      ([1,0])
                      (
                        [ SDK.ChainedAt
                            ([1,0,0])
                            (
                              [ SDK.NodeAt ([1,0,0,0]) ("PrintLine")
                              , SDK.NodeAt ([1,0,0,1]) ("TextCounter")
                              ]
                            )
                        , SDK.ChainedAt
                            ([1,0,1])
                            (
                              [ SDK.NodeAt ([1,0,1,0]) ("ShowTotal")
                              ]
                            )
                        ]
                      )
                  ]
                )
            , SDK.ChainedAt
                ([2])
                (
                  [ SDK.NodeAt ([2,0]) ("Report")
                  ]
                )
            ]
          )
    , SDK.protoSessions =
        [ SDK.SessionProto
            { SDK.sessionAsset = "TextLine"
            , SDK.sessionPlan = SDK.Receive ("LineFeed")
            , SDK.sessionMounts = [[-2,0,0],[-2,0,1]]
            }
        , SDK.SessionProto
            { SDK.sessionAsset = "RunningTotal"
            , SDK.sessionPlan = SDK.Derive ("TextLine")
            , SDK.sessionMounts = [[-2,1,0]]
            }
        ]
    , SDK.protoChains =
        [ SDK.ChainProto
            { SDK.chainNode = [0,0]
            , SDK.chainRole = SDK.NodeChain
            , SDK.chainTerminal = "Announce"
            , SDK.chainEntry = RunAnnounceGen
            , SDK.chainReaches = [RunAnnounceGen]
            , SDK.chainDrives = []
            , SDK.chainReads = []
            , SDK.chainScopePaths = [[]]
            }
        , SDK.ChainProto
            { SDK.chainNode = [1,0,0,0]
            , SDK.chainRole = SDK.NodeChain
            , SDK.chainTerminal = "PrintLine"
            , SDK.chainEntry = RunPrintLineGen
            , SDK.chainReaches = [RunPrintLineGen, StreamTextLineGen]
            , SDK.chainDrives = []
            , SDK.chainReads = []
            , SDK.chainScopePaths = [[]]
            }
        , SDK.ChainProto
            { SDK.chainNode = [1,0,0,1]
            , SDK.chainRole = SDK.NodeChain
            , SDK.chainTerminal = "TextCounter"
            , SDK.chainEntry = RunTextCounterGen
            , SDK.chainReaches =
                [ RunTextCounterGen
                , OpenInputSessionGen
                , GetOpenedInputGen
                , ReadOpenedInputGen
                , StreamTextLineGen
                , GetRunningTotalGen
                ]
            , SDK.chainDrives = ["RunningTotal"]
            , SDK.chainReads = []
            , SDK.chainScopePaths = [[OpenInputSessionGen]]
            }
        , SDK.ChainProto
            { SDK.chainNode = [1,0,1,0]
            , SDK.chainRole = SDK.NodeChain
            , SDK.chainTerminal = "ShowTotal"
            , SDK.chainEntry = RunShowTotalGen
            , SDK.chainReaches = [RunShowTotalGen, StreamRunningTotalGen]
            , SDK.chainDrives = []
            , SDK.chainReads = ["RunningTotal"]
            , SDK.chainScopePaths = [[]]
            }
        , SDK.ChainProto
            { SDK.chainNode = [2,0]
            , SDK.chainRole = SDK.NodeChain
            , SDK.chainTerminal = "Report"
            , SDK.chainEntry = RunReportGen
            , SDK.chainReaches = [RunReportGen, StreamRunningTotalGen]
            , SDK.chainDrives = []
            , SDK.chainReads = ["RunningTotal"]
            , SDK.chainScopePaths = [[]]
            }
        , SDK.ChainProto
            { SDK.chainNode = [1,-1,0,0]
            , SDK.chainRole = SDK.SessionChain
            , SDK.chainTerminal = "TextLine"
            , SDK.chainEntry = NextLineFeedGen
            , SDK.chainReaches = [NextLineFeedGen, OpenInputSessionGen, GetOpenedInputGen, ReadOpenedInputGen]
            , SDK.chainDrives = []
            , SDK.chainReads = []
            , SDK.chainScopePaths = [[OpenInputSessionGen]]
            }
        , SDK.ChainProto
            { SDK.chainNode = [1,-1,0,1]
            , SDK.chainRole = SDK.SessionChain
            , SDK.chainTerminal = "TextLine"
            , SDK.chainEntry = GetTextLineGen
            , SDK.chainReaches =
                [GetTextLineGen, NextLineFeedGen, OpenInputSessionGen, GetOpenedInputGen, ReadOpenedInputGen]
            , SDK.chainDrives = ["TextLine"]
            , SDK.chainReads = []
            , SDK.chainScopePaths = [[OpenInputSessionGen]]
            }
        , SDK.ChainProto
            { SDK.chainNode = [-2,0,0]
            , SDK.chainRole = SDK.SessionChain
            , SDK.chainTerminal = "TextLine"
            , SDK.chainEntry = NextLineFeedGen
            , SDK.chainReaches = [NextLineFeedGen, OpenInputSessionGen, GetOpenedInputGen, ReadOpenedInputGen]
            , SDK.chainDrives = []
            , SDK.chainReads = []
            , SDK.chainScopePaths = [[OpenInputSessionGen]]
            }
        , SDK.ChainProto
            { SDK.chainNode = [-2,0,1]
            , SDK.chainRole = SDK.SessionChain
            , SDK.chainTerminal = "TextLine"
            , SDK.chainEntry = GetTextLineGen
            , SDK.chainReaches =
                [GetTextLineGen, NextLineFeedGen, OpenInputSessionGen, GetOpenedInputGen, ReadOpenedInputGen]
            , SDK.chainDrives = ["TextLine"]
            , SDK.chainReads = []
            , SDK.chainScopePaths = [[OpenInputSessionGen]]
            }
        , SDK.ChainProto
            { SDK.chainNode = [-2,1,0]
            , SDK.chainRole = SDK.SessionChain
            , SDK.chainTerminal = "RunningTotal"
            , SDK.chainEntry = GetRunningTotalGen
            , SDK.chainReaches =
                [ GetRunningTotalGen
                , RunTextCounterGen
                , OpenInputSessionGen
                , GetOpenedInputGen
                , ReadOpenedInputGen
                , StreamTextLineGen
                ]
            , SDK.chainDrives = ["RunningTotal"]
            , SDK.chainReads = ["TextLine"]
            , SDK.chainScopePaths = [[OpenInputSessionGen]]
            }
        ]
    , SDK.protoChainDefinitions =
        [ SDK.ChainDefinition
            { SDK.definitionKind = SDK.OriginChain
            , SDK.definitionEffect = "Announce"
            , SDK.definitionEntry = RunAnnounceGen
            , SDK.definitionReaches = [RunAnnounceGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.ContextChain
            , SDK.definitionEffect = "InputResource"
            , SDK.definitionEntry = GetOpenedInputGen
            , SDK.definitionReaches = [GetOpenedInputGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.ContextChain
            , SDK.definitionEffect = "InputResource"
            , SDK.definitionEntry = ReadOpenedInputGen
            , SDK.definitionReaches = [ReadOpenedInputGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.OriginChain
            , SDK.definitionEffect = "InputSession"
            , SDK.definitionEntry = OpenInputSessionGen
            , SDK.definitionReaches = [OpenInputSessionGen, GetOpenedInputGen, ReadOpenedInputGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.ContextChain
            , SDK.definitionEffect = "LineFeed"
            , SDK.definitionEntry = NextLineFeedGen
            , SDK.definitionReaches =
                [NextLineFeedGen, OpenInputSessionGen, GetOpenedInputGen, ReadOpenedInputGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.ContextChain
            , SDK.definitionEffect = "LineParser"
            , SDK.definitionEntry = GetTextLineGen
            , SDK.definitionReaches =
                [GetTextLineGen, NextLineFeedGen, OpenInputSessionGen, GetOpenedInputGen, ReadOpenedInputGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.ContextChain
            , SDK.definitionEffect = "LineParser"
            , SDK.definitionEntry = StreamTextLineGen
            , SDK.definitionReaches = [StreamTextLineGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.OriginChain
            , SDK.definitionEffect = "PrintLine"
            , SDK.definitionEntry = RunPrintLineGen
            , SDK.definitionReaches = [RunPrintLineGen, StreamTextLineGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.OriginChain
            , SDK.definitionEffect = "TextCounter"
            , SDK.definitionEntry = RunTextCounterGen
            , SDK.definitionReaches =
                [ RunTextCounterGen
                , OpenInputSessionGen
                , GetOpenedInputGen
                , ReadOpenedInputGen
                , StreamTextLineGen
                , GetRunningTotalGen
                ]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.ContextChain
            , SDK.definitionEffect = "CountParser"
            , SDK.definitionEntry = GetRunningTotalGen
            , SDK.definitionReaches =
                [ GetRunningTotalGen
                , RunTextCounterGen
                , OpenInputSessionGen
                , GetOpenedInputGen
                , ReadOpenedInputGen
                , StreamTextLineGen
                ]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.ContextChain
            , SDK.definitionEffect = "CountParser"
            , SDK.definitionEntry = StreamRunningTotalGen
            , SDK.definitionReaches = [StreamRunningTotalGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.OriginChain
            , SDK.definitionEffect = "ShowTotal"
            , SDK.definitionEntry = RunShowTotalGen
            , SDK.definitionReaches = [RunShowTotalGen, StreamRunningTotalGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.OriginChain
            , SDK.definitionEffect = "Report"
            , SDK.definitionEntry = RunReportGen
            , SDK.definitionReaches = [RunReportGen, StreamRunningTotalGen]
            }
        ]
    , SDK.protoGraph =
        SDK.EffectGraph
          { SDK.graphMethods =
              [ SDK.MethodDefinition (RunAnnounceGen) (RunAnnounceGen) (SDK.HandlerMethod) (SDK.Empty)
              , SDK.MethodDefinition
                  (RunPrintLineGen)
                  (RunPrintLineGen)
                  (SDK.HandlerMethod)
                  (SDK.Call (StreamTextLineGen))
              , SDK.MethodDefinition (StreamTextLineGen) (GetTextLineGen) (SDK.ContextRequire) (SDK.Empty)
              , SDK.MethodDefinition
                  (RunTextCounterGen)
                  (RunTextCounterGen)
                  (SDK.HandlerMethod)
                  (
                    SDK.Sequence
                      (
                        [ SDK.Sequence
                            ([SDK.Call (OpenInputSessionGen), SDK.Call (StreamTextLineGen), SDK.Call (ReadOpenedInputGen)])
                        , SDK.Choice ([SDK.Empty, SDK.Sequence ([SDK.Empty])])
                        ]
                      )
                  )
              , SDK.MethodDefinition
                  (OpenInputSessionGen)
                  (OpenInputSessionGen)
                  (SDK.ScopeOpen)
                  (SDK.Sequence ([SDK.Call (GetOpenedInputGen), SDK.Call (ReadOpenedInputGen)]))
              , SDK.MethodDefinition (GetOpenedInputGen) (GetOpenedInputGen) (SDK.ContextRequest) (SDK.Empty)
              , SDK.MethodDefinition (ReadOpenedInputGen) (GetOpenedInputGen) (SDK.ContextRequire) (SDK.Empty)
              , SDK.MethodDefinition
                  (RunShowTotalGen)
                  (RunShowTotalGen)
                  (SDK.HandlerMethod)
                  (SDK.Call (StreamRunningTotalGen))
              , SDK.MethodDefinition (StreamRunningTotalGen) (GetRunningTotalGen) (SDK.ContextRequire) (SDK.Empty)
              , SDK.MethodDefinition
                  (RunReportGen)
                  (RunReportGen)
                  (SDK.HandlerMethod)
                  (SDK.Call (StreamRunningTotalGen))
              , SDK.MethodDefinition
                  (NextLineFeedGen)
                  (NextLineFeedGen)
                  (SDK.StreamHandler)
                  (SDK.Sequence ([SDK.Call (OpenInputSessionGen), SDK.Call (ReadOpenedInputGen)]))
              , SDK.MethodDefinition
                  (GetTextLineGen)
                  (GetTextLineGen)
                  (SDK.ContextStream)
                  (SDK.Call (NextLineFeedGen))
              , SDK.MethodDefinition
                  (GetRunningTotalGen)
                  (GetRunningTotalGen)
                  (SDK.ContextStream)
                  (SDK.Call (RunTextCounterGen))
              ]
          , SDK.graphRoots =
              [ RunAnnounceGen
              , RunPrintLineGen
              , RunTextCounterGen
              , RunShowTotalGen
              , RunReportGen
              , NextLineFeedGen
              , GetTextLineGen
              , GetRunningTotalGen
              ]
          , SDK.graphReferences =
              [ (RunPrintLineGen, StreamTextLineGen)
              , (RunTextCounterGen, OpenInputSessionGen)
              , (RunTextCounterGen, StreamTextLineGen)
              , (RunTextCounterGen, ReadOpenedInputGen)
              , (OpenInputSessionGen, GetOpenedInputGen)
              , (OpenInputSessionGen, ReadOpenedInputGen)
              , (RunShowTotalGen, StreamRunningTotalGen)
              , (RunReportGen, StreamRunningTotalGen)
              , (NextLineFeedGen, OpenInputSessionGen)
              , (NextLineFeedGen, ReadOpenedInputGen)
              , (GetTextLineGen, NextLineFeedGen)
              , (GetRunningTotalGen, RunTextCounterGen)
              ]
          , SDK.graphScopes = [OpenInputSessionGen]
          , SDK.graphScopePaths = [[], [OpenInputSessionGen]]
          , SDK.graphRootPaths =
              [ (RunAnnounceGen, [[]])
              , (RunPrintLineGen, [[]])
              , (RunTextCounterGen, [[OpenInputSessionGen]])
              , (RunShowTotalGen, [[]])
              , (RunReportGen, [[]])
              , (NextLineFeedGen, [[OpenInputSessionGen]])
              , (GetTextLineGen, [[OpenInputSessionGen]])
              , (GetRunningTotalGen, [[OpenInputSessionGen]])
              ]
          , SDK.graphScopeOrder = []
          }
    , SDK.protoScopes =
        SDK.ScopeTree
          { SDK.scopeRoots = [OpenInputSessionGen]
          , SDK.scopeNodes =
              [ SDK.ScopeNode
                  { SDK.scopeIdentity = OpenInputSessionGen
                  , SDK.scopeParents = []
                  , SDK.scopeChildren = []
                  }
              ]
          , SDK.scopeLayers = [[OpenInputSessionGen]]
          , SDK.scopePaths = [[], [OpenInputSessionGen]]
          , SDK.scopeCandidates = []
          , SDK.scopeOpposed = []
          , SDK.scopeUndetermined = []
          }
    , SDK.protoScopeNames = [(OpenInputSessionGen, "InputSession")]
    , SDK.protoSources =
        [ (SDK.ReadPoint ([-2,1,0]) ("TextLine"), SDK.FromSession)
        , (SDK.ReadPoint ([2,0]) ("RunningTotal"), SDK.FromSession)
        , (SDK.ReadPoint ([1,0,1,0]) ("RunningTotal"), SDK.FromSession)
        ]
    , SDK.protoScopeOpenings =
        [ SDK.ScopeOpeningPlan
            { SDK.openingNode = [-2,1,0]
            , SDK.openingScope = "InputSession"
            , SDK.openingSources = []
            , SDK.openingKinds = [SDK.RegistrationSingleton]
            }
        , SDK.ScopeOpeningPlan
            { SDK.openingNode = [-2,0,1]
            , SDK.openingScope = "InputSession"
            , SDK.openingSources = []
            , SDK.openingKinds = [SDK.RegistrationSingleton]
            }
        , SDK.ScopeOpeningPlan
            { SDK.openingNode = [-2,0,0]
            , SDK.openingScope = "InputSession"
            , SDK.openingSources = []
            , SDK.openingKinds = [SDK.RegistrationSingleton]
            }
        , SDK.ScopeOpeningPlan
            { SDK.openingNode = [1,0,0,1]
            , SDK.openingScope = "InputSession"
            , SDK.openingSources = []
            , SDK.openingKinds = [SDK.RegistrationSingleton]
            }
        , SDK.ScopeOpeningPlan
            { SDK.openingNode = [1,-1,0,1]
            , SDK.openingScope = "InputSession"
            , SDK.openingSources = []
            , SDK.openingKinds = [SDK.RegistrationSingleton]
            }
        , SDK.ScopeOpeningPlan
            { SDK.openingNode = [1,-1,0,0]
            , SDK.openingScope = "InputSession"
            , SDK.openingSources = []
            , SDK.openingKinds = [SDK.RegistrationSingleton]
            }
        ]
    , SDK.protoDriving =
        SDK.DrivingPlan
          { SDK.drivingNodes =
              [ SDK.NodeDrive ([]) ([[0,0],[1,0,0,0],[1,0,0,1],[1,0,1,0],[2,0]]) ([]) (Nothing) ([]) ([]) ([])
              , SDK.NodeDrive ([0]) ([[0,0]]) ([]) (Nothing) ([]) ([]) ([])
              , SDK.NodeDrive ([0,0]) ([[0,0]]) ([]) (Nothing) ([]) ([]) ([])
              , SDK.NodeDrive ([1]) ([[1,0,0,0],[1,0,0,1],[1,0,1,0]]) ([]) (Just [1]) ([]) ([]) ([])
              , SDK.NodeDrive ([1,0]) ([[1,0,0,0],[1,0,0,1],[1,0,1,0]]) ([]) (Just [1]) ([]) ([]) ([])
              , SDK.NodeDrive ([1,0,0]) ([[1,0,0,0],[1,0,0,1]]) ([]) (Just [1]) ([]) ([]) ([])
              , SDK.NodeDrive ([1,0,0,0]) ([[1,0,0,0]]) (["LineParser"]) (Just [1]) ([]) ([]) ([])
              , SDK.NodeDrive ([1,0,0,1]) ([[1,0,0,1]]) (["LineParser"]) (Just [1]) ([]) ([]) ([])
              , SDK.NodeDrive ([1,0,1]) ([[1,0,1,0]]) ([]) (Just [1]) ([]) ([]) ([])
              , SDK.NodeDrive ([1,0,1,0]) ([[1,0,1,0]]) (["CountParser"]) (Just [1]) ([]) ([]) ([])
              , SDK.NodeDrive ([2]) ([[2,0]]) ([]) (Nothing) ([]) ([[1]]) ([])
              , SDK.NodeDrive ([2,0]) ([[2,0]]) ([]) (Nothing) ([]) ([[1]]) ([])
              , SDK.NodeDrive ([1,-1,0,0]) ([]) ([]) (Just [1]) ([]) ([]) ([])
              , SDK.NodeDrive ([1,-1,0,1]) ([]) ([]) (Just [1]) ([]) ([]) ([])
              , SDK.NodeDrive ([-2,0,0]) ([]) ([]) (Nothing) ([]) ([]) ([])
              , SDK.NodeDrive ([-2,0,1]) ([]) ([]) (Nothing) ([]) ([]) ([])
              , SDK.NodeDrive ([-2,1,0]) ([]) ([]) (Nothing) ([]) ([]) ([])
              ]
          , SDK.drivingUnits =
              [ SDK.UnitDrive
                  ([1,0,0])
                  ([[1,0,0,0],[1,0,0,1]])
                  ([("LineParser", [SDK.ReadAt ([1,0,0,0]), SDK.ReadAt ([1,0,0,1])]), ("CountParser", [])])
                  ([("CountParser", SDK.PublishedAt ([[1,0,0,1]]))])
              , SDK.UnitDrive
                  ([1,0,1])
                  ([[1,0,1,0]])
                  ([("LineParser", []), ("CountParser", [SDK.ReadAt ([1,0,1,0])])])
                  ([])
              ]
          , SDK.drivingSessions =
              [ SDK.SessionDrive (Nothing) ("LineParser") ("TextLine") (Nothing)
              , SDK.SessionDrive (Nothing) ("CountParser") ("RunningTotal") (Just "LineParser")
              , SDK.SessionDrive (Just [1]) ("LineParser") ("TextLine") (Nothing)
              , SDK.SessionDrive (Just [1]) ("CountParser") ("RunningTotal") (Nothing)
              ]
          , SDK.drivingRootNodes = [[0,0],[1,0,0,0],[1,0,0,1],[1,0,1,0],[2,0]]
          , SDK.drivingOutputSites = [([1,0,0,1],"CountParser")]
          , SDK.drivingRequests =
              [ ("InputResource", GetOpenedInputGen)
              , ("LineParser", GetTextLineGen)
              , ("CountParser", GetRunningTotalGen)
              ]
          }
    }
