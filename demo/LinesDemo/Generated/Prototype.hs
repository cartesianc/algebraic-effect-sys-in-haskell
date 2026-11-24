{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE TypeApplications #-}

-- 自动生成；gen 编译出的静态结构，由 Program 交给 interpreter，运行前校验。
module LinesDemo.Generated.Prototype (generatedPrototype) where

import qualified Framework.Generated as SDK
import qualified LinesDemo.Types as AssetTypes
import LinesDemo.Generated.Effects (MethodGen(..))

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
                  (SDK.AssetDecl "OpenedInput" (SDK.typeRef @AssetTypes.InputFile))
                  (Just "acquireInput")
                  True
                  False
            , SDK.input = "Root"
            , SDK.demands = []
            }
        , SDK.EffectSpec
            { SDK.name = "InputSession"
            , SDK.typing = SDK.Scoped (Just "openInput") (Just "closeInput")
            , SDK.input = "Root"
            , SDK.demands =
                [SDK.Demand SDK.RequestAccess "OpenedInput", SDK.Demand SDK.RequireAccess "OpenedInput"]
            }
        , SDK.EffectSpec
            { SDK.name = "LineFeed"
            , SDK.typing = SDK.Stream (Just "nextLine")
            , SDK.input = "InputSession"
            , SDK.demands = [SDK.Demand SDK.RequireAccess "OpenedInput"]
            }
        , SDK.EffectSpec
            { SDK.name = "TraceLine"
            , SDK.typing = SDK.Middleware (Just "traceLine") [SDK.StreamKind, SDK.ScopedKind]
            , SDK.input = "None"
            , SDK.demands = []
            }
        , SDK.EffectSpec
            { SDK.name = "LineParser"
            , SDK.typing =
                SDK.Context (SDK.AssetDecl "TextLine" (SDK.typeRef @AssetTypes.Line)) (Just "parseLine") True True
            , SDK.input = "LineFeed"
            , SDK.demands = []
            }
        , SDK.EffectSpec
            { SDK.name = "PrintLine"
            , SDK.typing = SDK.Excu (Just "printLine")
            , SDK.input = "Root"
            , SDK.demands = [SDK.Demand SDK.StreamAccess "TextLine"]
            }
        , SDK.EffectSpec
            { SDK.name = "TextCounter"
            , SDK.typing = SDK.Excu (Just "countText")
            , SDK.input = "Root"
            , SDK.demands = [SDK.Demand SDK.StreamAccess "TextLine"]
            }
        , SDK.EffectSpec
            { SDK.name = "CountParser"
            , SDK.typing =
                SDK.Context
                  (SDK.AssetDecl "RunningTotal" (SDK.typeRef @AssetTypes.Total))
                  (Just "parseTotal")
                  True
                  True
            , SDK.input = "TextCounter"
            , SDK.demands = []
            }
        , SDK.EffectSpec
            { SDK.name = "ShowTotal"
            , SDK.typing = SDK.Excu (Just "showTotal")
            , SDK.input = "Root"
            , SDK.demands = [SDK.Demand SDK.StreamAccess "RunningTotal"]
            }
        , SDK.EffectSpec
            { SDK.name = "Report"
            , SDK.typing = SDK.Excu (Just "report")
            , SDK.input = "Root"
            , SDK.demands = [SDK.Demand SDK.RequireAccess "RunningTotal"]
            }
        ]
    , SDK.protoEffects =
        [ (SDK.effectProto "Announce" SDK.ExcuKind "Root")
            { SDK.effectMethods = [(SDK.HandlerMethod, RunAnnounceGen)]
            }
        , (SDK.effectProto "InputResource" SDK.ContextKind "Root")
            { SDK.effectMethods =
                [(SDK.ContextRequest, GetOpenedInputGen), (SDK.ContextRequire, ReadOpenedInputGen)]
            , SDK.effectProduces = Just "OpenedInput"
            }
        , (SDK.effectProto "InputSession" SDK.ScopedKind "Root")
            { SDK.effectMethods =
                [(SDK.ScopeOpen, OpenInputSessionGen), (SDK.ScopeClose, CloseInputSessionGen)]
            , SDK.effectDemands =
                [ SDK.ResolvedDemand SDK.RequestAccess "OpenedInput" "InputResource"
                , SDK.ResolvedDemand SDK.RequireAccess "OpenedInput" "InputResource"
                ]
            , SDK.effectNearestScopes = ["InputSession"]
            , SDK.effectResource = Just "InputResource"
            , SDK.effectContextDependencies = ["InputResource"]
            }
        , (SDK.effectProto "LineFeed" SDK.StreamKind "InputSession")
            { SDK.effectMethods = [(SDK.StreamHandler, NextLineFeedGen)]
            , SDK.effectDemands = [SDK.ResolvedDemand SDK.RequireAccess "OpenedInput" "InputResource"]
            , SDK.effectScopes = ["InputSession"]
            , SDK.effectInputChain = ["InputSession"]
            , SDK.effectScopeParents = ["InputSession"]
            , SDK.effectNearestScopes = ["InputSession"]
            , SDK.effectContextDependencies = ["InputResource"]
            }
        , (SDK.effectProto "TraceLine" SDK.MiddlewareKind "None")
            { SDK.effectMethods = [(SDK.MiddlewareHook, HookTraceLineGen)]
            }
        , (SDK.effectProto "LineParser" SDK.ContextKind "LineFeed")
            { SDK.effectMethods =
                [(SDK.ContextStream, GetTextLineGen), (SDK.ContextRequire, StreamTextLineGen)]
            , SDK.effectProduces = Just "TextLine"
            , SDK.effectScopes = ["InputSession"]
            , SDK.effectInputChain = ["LineFeed","InputSession"]
            , SDK.effectScopeParents = ["InputSession"]
            , SDK.effectNearestScopes = ["InputSession"]
            , SDK.effectContextDependencies = ["InputResource"]
            , SDK.effectContinuous = True
            , SDK.effectHistory = True
            }
        , (SDK.effectProto "PrintLine" SDK.ExcuKind "Root")
            { SDK.effectMethods = [(SDK.HandlerMethod, RunPrintLineGen)]
            , SDK.effectDemands = [SDK.ResolvedDemand SDK.StreamAccess "TextLine" "LineParser"]
            , SDK.effectContextDependencies = ["InputResource","LineParser"]
            }
        , (SDK.effectProto "TextCounter" SDK.ExcuKind "Root")
            { SDK.effectMethods = [(SDK.HandlerMethod, RunTextCounterGen)]
            , SDK.effectDemands = [SDK.ResolvedDemand SDK.StreamAccess "TextLine" "LineParser"]
            , SDK.effectContextDependencies = ["InputResource","LineParser"]
            }
        , (SDK.effectProto "CountParser" SDK.ContextKind "TextCounter")
            { SDK.effectMethods =
                [(SDK.ContextStream, GetRunningTotalGen), (SDK.ContextRequire, StreamRunningTotalGen)]
            , SDK.effectProduces = Just "RunningTotal"
            , SDK.effectAnchor = Just "TextCounter"
            , SDK.effectInputChain = ["TextCounter"]
            , SDK.effectContextDependencies = ["InputResource","LineParser"]
            , SDK.effectContinuous = True
            }
        , (SDK.effectProto "ShowTotal" SDK.ExcuKind "Root")
            { SDK.effectMethods = [(SDK.HandlerMethod, RunShowTotalGen)]
            , SDK.effectDemands = [SDK.ResolvedDemand SDK.StreamAccess "RunningTotal" "CountParser"]
            , SDK.effectContextDependencies = ["InputResource","LineParser","CountParser"]
            }
        , (SDK.effectProto "Report" SDK.ExcuKind "Root")
            { SDK.effectMethods = [(SDK.HandlerMethod, RunReportGen)]
            , SDK.effectDemands = [SDK.ResolvedDemand SDK.RequireAccess "RunningTotal" "CountParser"]
            , SDK.effectContextDependencies = ["InputResource","LineParser","CountParser"]
            }
        ]
    , SDK.protoMethods =
        [ SDK.MethodDefinition RunAnnounceGen RunAnnounceGen SDK.HandlerMethod SDK.Empty
        , SDK.MethodDefinition GetOpenedInputGen GetOpenedInputGen SDK.ContextRequest SDK.Empty
        , SDK.MethodDefinition ReadOpenedInputGen GetOpenedInputGen SDK.ContextRequire SDK.Empty
        , SDK.MethodDefinition
            OpenInputSessionGen
            OpenInputSessionGen
            SDK.ScopeOpen
            (SDK.Sequence [SDK.Call SDK.Invoke GetOpenedInputGen, SDK.Call SDK.ReadCurrent ReadOpenedInputGen])
        , SDK.MethodDefinition
            CloseInputSessionGen
            OpenInputSessionGen
            SDK.ScopeClose
            (SDK.Call SDK.ReadCurrent ReadOpenedInputGen)
        , SDK.MethodDefinition
            NextLineFeedGen
            NextLineFeedGen
            SDK.StreamHandler
            (SDK.Sequence [SDK.Call SDK.Invoke OpenInputSessionGen, SDK.Call SDK.ReadCurrent ReadOpenedInputGen])
        , SDK.MethodDefinition HookTraceLineGen HookTraceLineGen SDK.MiddlewareHook SDK.Empty
        , SDK.MethodDefinition
            GetTextLineGen
            GetTextLineGen
            SDK.ContextStream
            (SDK.Call SDK.Deliver NextLineFeedGen)
        , SDK.MethodDefinition StreamTextLineGen GetTextLineGen SDK.ContextRequire SDK.Empty
        , SDK.MethodDefinition
            RunPrintLineGen
            RunPrintLineGen
            SDK.HandlerMethod
            (SDK.Call SDK.ReadCurrent StreamTextLineGen)
        , SDK.MethodDefinition
            RunTextCounterGen
            RunTextCounterGen
            SDK.HandlerMethod
            (
              SDK.Sequence
                [SDK.Call SDK.ReadHistory StreamTextLineGen, SDK.Choice [SDK.Empty, SDK.Sequence [SDK.Empty]]]
            )
        , SDK.MethodDefinition
            GetRunningTotalGen
            GetRunningTotalGen
            SDK.ContextStream
            (SDK.Call SDK.ReadOutput RunTextCounterGen)
        , SDK.MethodDefinition StreamRunningTotalGen GetRunningTotalGen SDK.ContextRequire SDK.Empty
        , SDK.MethodDefinition
            RunShowTotalGen
            RunShowTotalGen
            SDK.HandlerMethod
            (SDK.Call SDK.ReadCurrent StreamRunningTotalGen)
        , SDK.MethodDefinition
            RunReportGen
            RunReportGen
            SDK.HandlerMethod
            (SDK.Call SDK.ReadCurrent StreamRunningTotalGen)
        ]
    , SDK.protoWorkflow =
        SDK.ChainAt
          []
          [ SDK.NodeAt [0] "Announce"
          , SDK.LifelongAt
              [1]
              (
                SDK.LifelongProto
                  { SDK.lifelongUnits = [[1,0],[1,1]]
                  , SDK.lifelongSubscriptions = [([1,0,0],"TextLine"),([1,0,1],"TextLine"),([1,1],"RunningTotal")]
                  , SDK.lifelongSessions =
                      [ SDK.SessionProto
                          { SDK.sessionAsset = "TextLine"
                          , SDK.sessionPlan = SDK.Receive "LineFeed"
                          , SDK.sessionMounts = [[1,-1,0,0],[1,-1,0,1]]
                          }
                      , SDK.SessionProto
                          { SDK.sessionAsset = "RunningTotal"
                          , SDK.sessionPlan = SDK.ReuseOutput [[1,0,1]]
                          , SDK.sessionMounts = []
                          }
                      ]
                  }
              )
              [ SDK.ChainAt
                  [1,0]
                  [ SDK.NodeAt [1,0,0] "PrintLine"
                  , SDK.NodeAt [1,0,1] "TextCounter"
                  ]
              , SDK.NodeAt [1,1] "ShowTotal"
              ]
          , SDK.NodeAt [2] "Report"
          ]
    , SDK.protoSessions =
        [ SDK.SessionProto
            { SDK.sessionAsset = "TextLine"
            , SDK.sessionPlan = SDK.Receive "LineFeed"
            , SDK.sessionMounts = [[-2,0,0],[-2,0,1]]
            }
        , SDK.SessionProto
            { SDK.sessionAsset = "RunningTotal"
            , SDK.sessionPlan = SDK.Derive "TextLine"
            , SDK.sessionMounts = [[-2,1,0]]
            }
        ]
    , SDK.protoChains =
        [ SDK.ChainProto
            { SDK.chainNode = [0]
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
            { SDK.chainNode = [1,0,1]
            , SDK.chainRole = SDK.NodeChain
            , SDK.chainTerminal = "TextCounter"
            , SDK.chainEntry = RunTextCounterGen
            , SDK.chainReaches = [RunTextCounterGen, StreamTextLineGen, GetRunningTotalGen]
            , SDK.chainDrives = ["RunningTotal"]
            , SDK.chainReads = []
            , SDK.chainScopePaths = [[]]
            }
        , SDK.ChainProto
            { SDK.chainNode = [1,1]
            , SDK.chainRole = SDK.NodeChain
            , SDK.chainTerminal = "ShowTotal"
            , SDK.chainEntry = RunShowTotalGen
            , SDK.chainReaches = [RunShowTotalGen, StreamRunningTotalGen]
            , SDK.chainDrives = []
            , SDK.chainReads = ["RunningTotal"]
            , SDK.chainScopePaths = [[]]
            }
        , SDK.ChainProto
            { SDK.chainNode = [2]
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
            , SDK.chainReaches = [GetRunningTotalGen, RunTextCounterGen, StreamTextLineGen]
            , SDK.chainDrives = ["RunningTotal"]
            , SDK.chainReads = ["TextLine"]
            , SDK.chainScopePaths = [[]]
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
            , SDK.definitionReaches = [RunTextCounterGen, StreamTextLineGen, GetRunningTotalGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.ContextChain
            , SDK.definitionEffect = "CountParser"
            , SDK.definitionEntry = GetRunningTotalGen
            , SDK.definitionReaches = [GetRunningTotalGen, RunTextCounterGen, StreamTextLineGen]
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
              [ SDK.MethodDefinition RunAnnounceGen RunAnnounceGen SDK.HandlerMethod SDK.Empty
              , SDK.MethodDefinition
                  RunPrintLineGen
                  RunPrintLineGen
                  SDK.HandlerMethod
                  (SDK.Call SDK.ReadCurrent StreamTextLineGen)
              , SDK.MethodDefinition StreamTextLineGen GetTextLineGen SDK.ContextRequire SDK.Empty
              , SDK.MethodDefinition
                  RunTextCounterGen
                  RunTextCounterGen
                  SDK.HandlerMethod
                  (
                    SDK.Sequence
                      [SDK.Call SDK.ReadHistory StreamTextLineGen, SDK.Choice [SDK.Empty, SDK.Sequence [SDK.Empty]]]
                  )
              , SDK.MethodDefinition
                  RunShowTotalGen
                  RunShowTotalGen
                  SDK.HandlerMethod
                  (SDK.Call SDK.ReadCurrent StreamRunningTotalGen)
              , SDK.MethodDefinition StreamRunningTotalGen GetRunningTotalGen SDK.ContextRequire SDK.Empty
              , SDK.MethodDefinition
                  RunReportGen
                  RunReportGen
                  SDK.HandlerMethod
                  (SDK.Call SDK.ReadCurrent StreamRunningTotalGen)
              , SDK.MethodDefinition
                  NextLineFeedGen
                  NextLineFeedGen
                  SDK.StreamHandler
                  (SDK.Sequence [SDK.Call SDK.Invoke OpenInputSessionGen, SDK.Call SDK.ReadCurrent ReadOpenedInputGen])
              , SDK.MethodDefinition
                  OpenInputSessionGen
                  OpenInputSessionGen
                  SDK.ScopeOpen
                  (SDK.Sequence [SDK.Call SDK.Invoke GetOpenedInputGen, SDK.Call SDK.ReadCurrent ReadOpenedInputGen])
              , SDK.MethodDefinition GetOpenedInputGen GetOpenedInputGen SDK.ContextRequest SDK.Empty
              , SDK.MethodDefinition ReadOpenedInputGen GetOpenedInputGen SDK.ContextRequire SDK.Empty
              , SDK.MethodDefinition
                  GetTextLineGen
                  GetTextLineGen
                  SDK.ContextStream
                  (SDK.Call SDK.Deliver NextLineFeedGen)
              , SDK.MethodDefinition
                  GetRunningTotalGen
                  GetRunningTotalGen
                  SDK.ContextStream
                  (SDK.Call SDK.ReadOutput RunTextCounterGen)
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
              , (RunTextCounterGen, StreamTextLineGen)
              , (RunShowTotalGen, StreamRunningTotalGen)
              , (RunReportGen, StreamRunningTotalGen)
              , (NextLineFeedGen, OpenInputSessionGen)
              , (NextLineFeedGen, ReadOpenedInputGen)
              , (OpenInputSessionGen, GetOpenedInputGen)
              , (OpenInputSessionGen, ReadOpenedInputGen)
              , (GetTextLineGen, NextLineFeedGen)
              , (GetRunningTotalGen, RunTextCounterGen)
              ]
          , SDK.graphScopes = [OpenInputSessionGen]
          , SDK.graphScopePaths = [[], [OpenInputSessionGen]]
          , SDK.graphRootPaths =
              [ (RunAnnounceGen, [[]])
              , (RunPrintLineGen, [[]])
              , (RunTextCounterGen, [[]])
              , (RunShowTotalGen, [[]])
              , (RunReportGen, [[]])
              , (NextLineFeedGen, [[OpenInputSessionGen]])
              , (GetTextLineGen, [[OpenInputSessionGen]])
              , (GetRunningTotalGen, [[]])
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
        [ (SDK.ReadPoint [-2,1,0] "TextLine", SDK.FromSession)
        , (SDK.ReadPoint [2] "RunningTotal", SDK.FromSession)
        , (SDK.ReadPoint [1,1] "RunningTotal", SDK.FromSession)
        ]
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
    , SDK.protoDriving =
        SDK.DrivingPlan
          { SDK.drivingNodes =
              [ SDK.NodeDrive [] [[0],[1,0,0],[1,0,1],[1,1],[2]] [] Nothing [] [] []
              , SDK.NodeDrive [0] [[0]] [] Nothing [] [] []
              , SDK.NodeDrive [1] [[1,0,0],[1,0,1],[1,1]] [] (Just [1]) [] [] []
              , SDK.NodeDrive [1,0] [[1,0,0],[1,0,1]] [] (Just [1]) [] [] []
              , SDK.NodeDrive [1,0,0] [[1,0,0]] ["LineParser"] (Just [1]) [] [] []
              , SDK.NodeDrive [1,0,1] [[1,0,1]] ["LineParser"] (Just [1]) [] [] []
              , SDK.NodeDrive [1,1] [[1,1]] ["CountParser"] (Just [1]) [] [] []
              , SDK.NodeDrive [2] [[2]] [] Nothing [] [[1]] []
              , SDK.NodeDrive [1,-1,0,0] [] [] (Just [1]) [] [] []
              , SDK.NodeDrive [1,-1,0,1] [] [] (Just [1]) [] [] []
              , SDK.NodeDrive [-2,0,0] [] [] Nothing [] [] []
              , SDK.NodeDrive [-2,0,1] [] [] Nothing [] [] []
              , SDK.NodeDrive [-2,1,0] [] [] Nothing [] [] []
              ]
          , SDK.drivingUnits =
              [ SDK.UnitDrive
                  [1,0]
                  [[1,0,0],[1,0,1]]
                  [("LineParser", [SDK.ReadAt [1,0,0], SDK.ReadAt [1,0,1]]), ("CountParser", [])]
                  [("CountParser", SDK.PublishedAt [[1,0,1]])]
              , SDK.UnitDrive [1,1] [[1,1]] [("LineParser", []), ("CountParser", [SDK.ReadAt [1,1]])] []
              ]
          , SDK.drivingSessions =
              [ SDK.SessionDrive Nothing "LineParser" "TextLine" Nothing
              , SDK.SessionDrive Nothing "CountParser" "RunningTotal" (Just "LineParser")
              , SDK.SessionDrive (Just [1]) "LineParser" "TextLine" Nothing
              , SDK.SessionDrive (Just [1]) "CountParser" "RunningTotal" Nothing
              ]
          , SDK.drivingRootNodes = [[0],[1,0,0],[1,0,1],[1,1],[2]]
          , SDK.drivingOutputSites = [([1,0,1],"CountParser")]
          , SDK.drivingRequests =
              [ ("InputResource", GetOpenedInputGen)
              , ("LineParser", GetTextLineGen)
              , ("CountParser", GetRunningTotalGen)
              ]
          , SDK.drivingMiddleware = [([1],["TraceLine"])]
          , SDK.drivingHooks =
              [([1,0,0],["TraceLine"]),([1,0,1],["TraceLine"]),([1,1],["TraceLine"]),([1,-1,0,0],["TraceLine"]),([1,-1,0,1],["TraceLine"])]
          }
    }
