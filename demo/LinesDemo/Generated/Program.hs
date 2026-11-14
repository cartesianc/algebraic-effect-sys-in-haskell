{-# LANGUAGE DuplicateRecordFields #-}

-- 自动生成；只登记末端入口与原型，执行由 SDK 的 interpreter 完成。
module LinesDemo.Generated.Program where

import Framework.Generated (EffectSpec(..), EffectTyping(..), Asset(..), Handles(..), Demand(..), Access(..), TypeRef(..))
import qualified Framework.Generated as SDK
import LinesDemo.Generated.Effects
import qualified LinesDemo.Generated.Handlers as Handlers
import LinesDemo.Types


-- 仅汇总所选末端的成功结果，不保存共享绑定或增加完成包装。
data Results = AnnounceResult () | PrintLineResult () | ReportResult ()
  deriving Show

-- 末端共享生成的 scope 句柄；只创建空状态，Node algebra 才 lower。
-- 第二个列表是各转折契约的选择末端：驱动资产（持续资产领取本次交付），返回它当前的构造器名。
-- 第三个列表是各持续资产的生产步骤：会话按需启动，Stream 单步取得原始输入，parser 发布一次资产。
compiledEntries :: IO ([SDK.Target ContextValues Errors Results], [SDK.Target ContextValues Errors String]
                     , [(String, SDK.SessionSteps ContextValues Errors)])
compiledEntries = do
  scopes <- Handlers.newScopeHandlers
  pure
    ( [ SDK.targetApp "Announce" emptyContexts scopes (SDK.withErrorHandlers Handlers.errorHandlers (SDK.withAnchoredContexts Handlers.contextInjections (SDK.withScopeCleanups Handlers.scopeCleanups (AnnounceResult <$> (() <$ Handlers.runAnnounce)))))
      , SDK.targetApp "PrintLine" emptyContexts scopes (SDK.withErrorHandlers Handlers.errorHandlers (SDK.withAnchoredContexts Handlers.contextInjections (SDK.withScopeCleanups Handlers.scopeCleanups (PrintLineResult <$> (() <$ Handlers.runPrintLine)))))
      , SDK.targetApp "Report" emptyContexts scopes (SDK.withErrorHandlers Handlers.errorHandlers (SDK.withAnchoredContexts Handlers.contextInjections (SDK.withScopeCleanups Handlers.scopeCleanups (ReportResult <$> (() <$ Handlers.runReport)))))
      ]
    , []
    , [ ("LineParser", SDK.receiveSteps (SDK.targetApp "LineFeed" emptyContexts scopes (SDK.withErrorHandlers Handlers.errorHandlers (SDK.withAnchoredContexts Handlers.contextInjections (SDK.withScopeCleanups Handlers.scopeCleanups (Handlers.nextLineFeed))))) (SDK.targetApp "LineParser" emptyContexts scopes (SDK.withErrorHandlers Handlers.errorHandlers (SDK.withAnchoredContexts Handlers.contextInjections (SDK.withScopeCleanups Handlers.scopeCleanups (() <$ Handlers.getTextLine))))))
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
            { SDK.name = "Report"
            , SDK.typing = SDK.Excu (Just "report")
            , SDK.input = "Root"
            , SDK.demands = []
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
            { SDK.effectName = "Report"
            , SDK.effectKind = SDK.ExcuKind
            , SDK.effectInput = "Root"
            , SDK.effectMethods = [(SDK.HandlerMethod, RunReportGen)]
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
        , SDK.MethodDefinition (RunReportGen) (RunReportGen) (SDK.HandlerMethod) (SDK.Empty)
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
                    { SDK.lifelongUnits = [[1,0]]
                    , SDK.lifelongSubscriptions = [([1,0,0],"TextLine")]
                    , SDK.lifelongSessions =
                        [ SDK.SessionProto
                            { SDK.sessionAsset = "TextLine"
                            , SDK.sessionPlan = SDK.Receive ("LineFeed")
                            , SDK.sessionMounts = [[1,-1,0,0],[1,-1,0,1]]
                            }
                        ]
                    }
                )
                (
                  [ SDK.ChainedAt
                      ([1,0])
                      (
                        [ SDK.NodeAt ([1,0,0]) ("PrintLine")
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
            { SDK.chainNode = [1,0,0]
            , SDK.chainRole = SDK.NodeChain
            , SDK.chainTerminal = "PrintLine"
            , SDK.chainEntry = RunPrintLineGen
            , SDK.chainReaches = [RunPrintLineGen, StreamTextLineGen]
            , SDK.chainDrives = []
            , SDK.chainReads = []
            , SDK.chainScopePaths = [[]]
            }
        , SDK.ChainProto
            { SDK.chainNode = [2,0]
            , SDK.chainRole = SDK.NodeChain
            , SDK.chainTerminal = "Report"
            , SDK.chainEntry = RunReportGen
            , SDK.chainReaches = [RunReportGen]
            , SDK.chainDrives = []
            , SDK.chainReads = []
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
            , SDK.definitionEffect = "Report"
            , SDK.definitionEntry = RunReportGen
            , SDK.definitionReaches = [RunReportGen]
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
              , SDK.MethodDefinition (RunReportGen) (RunReportGen) (SDK.HandlerMethod) (SDK.Empty)
              , SDK.MethodDefinition
                  (NextLineFeedGen)
                  (NextLineFeedGen)
                  (SDK.StreamHandler)
                  (SDK.Sequence ([SDK.Call (OpenInputSessionGen), SDK.Call (ReadOpenedInputGen)]))
              , SDK.MethodDefinition
                  (OpenInputSessionGen)
                  (OpenInputSessionGen)
                  (SDK.ScopeOpen)
                  (SDK.Sequence ([SDK.Call (GetOpenedInputGen), SDK.Call (ReadOpenedInputGen)]))
              , SDK.MethodDefinition (GetOpenedInputGen) (GetOpenedInputGen) (SDK.ContextRequest) (SDK.Empty)
              , SDK.MethodDefinition (ReadOpenedInputGen) (GetOpenedInputGen) (SDK.ContextRequire) (SDK.Empty)
              , SDK.MethodDefinition
                  (GetTextLineGen)
                  (GetTextLineGen)
                  (SDK.ContextStream)
                  (SDK.Call (NextLineFeedGen))
              ]
          , SDK.graphRoots =
              [RunAnnounceGen, RunPrintLineGen, RunReportGen, NextLineFeedGen, GetTextLineGen]
          , SDK.graphReferences =
              [ (RunPrintLineGen, StreamTextLineGen)
              , (NextLineFeedGen, OpenInputSessionGen)
              , (NextLineFeedGen, ReadOpenedInputGen)
              , (OpenInputSessionGen, GetOpenedInputGen)
              , (OpenInputSessionGen, ReadOpenedInputGen)
              , (GetTextLineGen, NextLineFeedGen)
              ]
          , SDK.graphScopes = [OpenInputSessionGen]
          , SDK.graphScopePaths = [[], [OpenInputSessionGen]]
          , SDK.graphRootPaths =
              [ (RunAnnounceGen, [[]])
              , (RunPrintLineGen, [[]])
              , (RunReportGen, [[]])
              , (NextLineFeedGen, [[OpenInputSessionGen]])
              , (GetTextLineGen, [[OpenInputSessionGen]])
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
    , SDK.protoSources = []
    , SDK.protoScopeOpenings =
        [ SDK.ScopeOpeningPlan
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
    }
