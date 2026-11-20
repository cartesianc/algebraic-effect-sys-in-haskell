{-# LANGUAGE DuplicateRecordFields #-}

-- 自动生成；gen 编译出的静态结构，由 Program 交给 interpreter，运行前校验。
module StreamDemo.Generated.Prototype (generatedPrototype) where

import qualified Framework.Generated as SDK
import StreamDemo.Generated.Effects (MethodGen(..))

-- 生成时完成注册、方法、origin/ctx 链、资产来源、Workflow 和 scope 的统一分析。
-- NodeId 只在这份 AST 快照中有效；运行时校验后装配闭包。
generatedPrototype :: SDK.Prototype MethodGen
generatedPrototype =
  SDK.Prototype
    { SDK.protoRegistrations =
        [ SDK.EffectSpec
            { SDK.name = "SensorResource"
            , SDK.typing =
                SDK.Context
                  (SDK.AssetDecl "SensorState" (SDK.TypeRef "SensorMemory"))
                  (Just "prepareSensor")
                  True
                  False
            , SDK.input = "Root"
            , SDK.demands = []
            }
        , SDK.EffectSpec
            { SDK.name = "SensorLink"
            , SDK.typing = SDK.Scoped (Just "connectSensor") (Just "disconnectSensor")
            , SDK.input = "Root"
            , SDK.demands =
                [SDK.Demand SDK.RequestAccess "SensorState", SDK.Demand SDK.RequireAccess "SensorState"]
            }
        , SDK.EffectSpec
            { SDK.name = "TemperatureFeed"
            , SDK.typing = SDK.Stream (Just "nextReading")
            , SDK.input = "SensorLink"
            , SDK.demands = []
            }
        , SDK.EffectSpec
            { SDK.name = "TemperatureParser"
            , SDK.typing =
                SDK.Context
                  (SDK.AssetDecl "TemperatureSample" (SDK.TypeRef "Temperature"))
                  (Just "parseTemperature")
                  True
                  True
            , SDK.input = "TemperatureFeed"
            , SDK.demands = [SDK.Demand SDK.RequireAccess "SensorState"]
            }
        , SDK.EffectSpec
            { SDK.name = "HeartbeatClock"
            , SDK.typing = SDK.Stream (Just "nextBeat")
            , SDK.input = "SensorLink"
            , SDK.demands = []
            }
        , SDK.EffectSpec
            { SDK.name = "Heartbeat"
            , SDK.typing = SDK.Context (SDK.AssetDecl "Beat" (SDK.TypeRef "Int")) (Just "parseBeat") True True
            , SDK.input = "HeartbeatClock"
            , SDK.demands = [SDK.Demand SDK.RequireAccess "SensorState"]
            }
        , SDK.EffectSpec
            { SDK.name = "Announce"
            , SDK.typing = SDK.Excu (Just "announce")
            , SDK.input = "Root"
            , SDK.demands = []
            }
        , SDK.EffectSpec
            { SDK.name = "ShowTemperature"
            , SDK.typing = SDK.Excu (Just "showTemperature")
            , SDK.input = "Root"
            , SDK.demands = [SDK.Demand SDK.StreamAccess "TemperatureSample"]
            }
        , SDK.EffectSpec
            { SDK.name = "CheckTrend"
            , SDK.typing = SDK.Excu (Just "checkTrend")
            , SDK.input = "Root"
            , SDK.demands = [SDK.Demand SDK.StreamAccess "TemperatureSample"]
            }
        , SDK.EffectSpec
            { SDK.name = "ReportHeartbeat"
            , SDK.typing = SDK.Excu (Just "reportHeartbeat")
            , SDK.input = "Root"
            , SDK.demands = [SDK.Demand SDK.StreamAccess "Beat"]
            }
        ]
    , SDK.protoEffects =
        [ (SDK.effectProto "SensorResource" SDK.ContextKind "Root")
            { SDK.effectMethods =
                [(SDK.ContextRequest, GetSensorStateGen), (SDK.ContextRequire, ReadSensorStateGen)]
            , SDK.effectProduces = Just "SensorState"
            }
        , (SDK.effectProto "SensorLink" SDK.ScopedKind "Root")
            { SDK.effectMethods = [(SDK.ScopeOpen, OpenSensorLinkGen), (SDK.ScopeClose, CloseSensorLinkGen)]
            , SDK.effectDemands =
                [ SDK.ResolvedDemand SDK.RequestAccess "SensorState" "SensorResource"
                , SDK.ResolvedDemand SDK.RequireAccess "SensorState" "SensorResource"
                ]
            , SDK.effectNearestScopes = ["SensorLink"]
            , SDK.effectResource = Just "SensorResource"
            , SDK.effectContextDependencies = ["SensorResource"]
            }
        , (SDK.effectProto "TemperatureFeed" SDK.StreamKind "SensorLink")
            { SDK.effectMethods = [(SDK.StreamHandler, NextTemperatureFeedGen)]
            , SDK.effectScopes = ["SensorLink"]
            , SDK.effectInputChain = ["SensorLink"]
            , SDK.effectScopeParents = ["SensorLink"]
            , SDK.effectNearestScopes = ["SensorLink"]
            , SDK.effectContextDependencies = ["SensorResource"]
            }
        , (SDK.effectProto "TemperatureParser" SDK.ContextKind "TemperatureFeed")
            { SDK.effectMethods =
                [(SDK.ContextStream, GetTemperatureSampleGen), (SDK.ContextRequire, StreamTemperatureSampleGen)]
            , SDK.effectDemands = [SDK.ResolvedDemand SDK.RequireAccess "SensorState" "SensorResource"]
            , SDK.effectProduces = Just "TemperatureSample"
            , SDK.effectScopes = ["SensorLink"]
            , SDK.effectInputChain = ["TemperatureFeed","SensorLink"]
            , SDK.effectScopeParents = ["SensorLink"]
            , SDK.effectNearestScopes = ["SensorLink"]
            , SDK.effectContextDependencies = ["SensorResource"]
            , SDK.effectContinuous = True
            }
        , (SDK.effectProto "HeartbeatClock" SDK.StreamKind "SensorLink")
            { SDK.effectMethods = [(SDK.StreamHandler, NextHeartbeatClockGen)]
            , SDK.effectScopes = ["SensorLink"]
            , SDK.effectInputChain = ["SensorLink"]
            , SDK.effectScopeParents = ["SensorLink"]
            , SDK.effectNearestScopes = ["SensorLink"]
            , SDK.effectContextDependencies = ["SensorResource"]
            }
        , (SDK.effectProto "Heartbeat" SDK.ContextKind "HeartbeatClock")
            { SDK.effectMethods = [(SDK.ContextStream, GetBeatGen), (SDK.ContextRequire, StreamBeatGen)]
            , SDK.effectDemands = [SDK.ResolvedDemand SDK.RequireAccess "SensorState" "SensorResource"]
            , SDK.effectProduces = Just "Beat"
            , SDK.effectScopes = ["SensorLink"]
            , SDK.effectInputChain = ["HeartbeatClock","SensorLink"]
            , SDK.effectScopeParents = ["SensorLink"]
            , SDK.effectNearestScopes = ["SensorLink"]
            , SDK.effectContextDependencies = ["SensorResource"]
            , SDK.effectContinuous = True
            }
        , (SDK.effectProto "Announce" SDK.ExcuKind "Root")
            { SDK.effectMethods = [(SDK.HandlerMethod, RunAnnounceGen)]
            }
        , (SDK.effectProto "ShowTemperature" SDK.ExcuKind "Root")
            { SDK.effectMethods = [(SDK.HandlerMethod, RunShowTemperatureGen)]
            , SDK.effectDemands =
                [SDK.ResolvedDemand SDK.StreamAccess "TemperatureSample" "TemperatureParser"]
            , SDK.effectContextDependencies = ["SensorResource","TemperatureParser"]
            }
        , (SDK.effectProto "CheckTrend" SDK.ExcuKind "Root")
            { SDK.effectMethods = [(SDK.HandlerMethod, RunCheckTrendGen)]
            , SDK.effectDemands =
                [SDK.ResolvedDemand SDK.StreamAccess "TemperatureSample" "TemperatureParser"]
            , SDK.effectContextDependencies = ["SensorResource","TemperatureParser"]
            }
        , (SDK.effectProto "ReportHeartbeat" SDK.ExcuKind "Root")
            { SDK.effectMethods = [(SDK.HandlerMethod, RunReportHeartbeatGen)]
            , SDK.effectDemands = [SDK.ResolvedDemand SDK.StreamAccess "Beat" "Heartbeat"]
            , SDK.effectContextDependencies = ["SensorResource","Heartbeat"]
            }
        ]
    , SDK.protoMethods =
        [ SDK.MethodDefinition GetSensorStateGen GetSensorStateGen SDK.ContextRequest SDK.Empty
        , SDK.MethodDefinition ReadSensorStateGen GetSensorStateGen SDK.ContextRequire SDK.Empty
        , SDK.MethodDefinition
            OpenSensorLinkGen
            OpenSensorLinkGen
            SDK.ScopeOpen
            (SDK.Sequence [SDK.Call GetSensorStateGen, SDK.Call ReadSensorStateGen])
        , SDK.MethodDefinition
            CloseSensorLinkGen
            OpenSensorLinkGen
            SDK.ScopeClose
            (SDK.Call ReadSensorStateGen)
        , SDK.MethodDefinition
            NextTemperatureFeedGen
            NextTemperatureFeedGen
            SDK.StreamHandler
            (SDK.Call OpenSensorLinkGen)
        , SDK.MethodDefinition
            GetTemperatureSampleGen
            GetTemperatureSampleGen
            SDK.ContextStream
            (SDK.Sequence [SDK.Call NextTemperatureFeedGen, SDK.Call ReadSensorStateGen])
        , SDK.MethodDefinition StreamTemperatureSampleGen GetTemperatureSampleGen SDK.ContextRequire SDK.Empty
        , SDK.MethodDefinition
            NextHeartbeatClockGen
            NextHeartbeatClockGen
            SDK.StreamHandler
            (SDK.Call OpenSensorLinkGen)
        , SDK.MethodDefinition
            GetBeatGen
            GetBeatGen
            SDK.ContextStream
            (SDK.Sequence [SDK.Call NextHeartbeatClockGen, SDK.Call ReadSensorStateGen])
        , SDK.MethodDefinition StreamBeatGen GetBeatGen SDK.ContextRequire SDK.Empty
        , SDK.MethodDefinition RunAnnounceGen RunAnnounceGen SDK.HandlerMethod SDK.Empty
        , SDK.MethodDefinition
            RunShowTemperatureGen
            RunShowTemperatureGen
            SDK.HandlerMethod
            (SDK.Call StreamTemperatureSampleGen)
        , SDK.MethodDefinition
            RunCheckTrendGen
            RunCheckTrendGen
            SDK.HandlerMethod
            (SDK.Call StreamTemperatureSampleGen)
        , SDK.MethodDefinition
            RunReportHeartbeatGen
            RunReportHeartbeatGen
            SDK.HandlerMethod
            (SDK.Call StreamBeatGen)
        ]
    , SDK.protoWorkflow =
        SDK.ChainedAt
          []
          [ SDK.ChainedAt
              [0]
              [ SDK.NodeAt [0,0] "Announce"
              ]
          , SDK.LifelongAt
              [1]
              (
                SDK.LifelongProto
                  { SDK.lifelongUnits = [[1,0],[1,1]]
                  , SDK.lifelongSubscriptions =
                      [([1,0,0],"TemperatureSample"),([1,0,1],"TemperatureSample"),([1,1,0],"Beat")]
                  , SDK.lifelongSessions =
                      [ SDK.SessionProto
                          { SDK.sessionAsset = "TemperatureSample"
                          , SDK.sessionPlan = SDK.Receive "TemperatureFeed"
                          , SDK.sessionMounts = [[1,-1,0,0],[1,-1,0,1]]
                          }
                      , SDK.SessionProto
                          { SDK.sessionAsset = "Beat"
                          , SDK.sessionPlan = SDK.Receive "HeartbeatClock"
                          , SDK.sessionMounts = [[1,-1,1,0],[1,-1,1,1]]
                          }
                      ]
                  }
              )
              [ SDK.ChainedAt
                  [1,0]
                  [ SDK.NodeAt [1,0,0] "ShowTemperature"
                  , SDK.NodeAt [1,0,1] "CheckTrend"
                  ]
              , SDK.ChainedAt
                  [1,1]
                  [ SDK.NodeAt [1,1,0] "ReportHeartbeat"
                  ]
              ]
          ]
    , SDK.protoSessions =
        [ SDK.SessionProto
            { SDK.sessionAsset = "TemperatureSample"
            , SDK.sessionPlan = SDK.Receive "TemperatureFeed"
            , SDK.sessionMounts = [[-2,0,0],[-2,0,1]]
            }
        , SDK.SessionProto
            { SDK.sessionAsset = "Beat"
            , SDK.sessionPlan = SDK.Receive "HeartbeatClock"
            , SDK.sessionMounts = [[-2,1,0],[-2,1,1]]
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
            , SDK.chainTerminal = "ShowTemperature"
            , SDK.chainEntry = RunShowTemperatureGen
            , SDK.chainReaches = [RunShowTemperatureGen, StreamTemperatureSampleGen]
            , SDK.chainDrives = []
            , SDK.chainReads = []
            , SDK.chainScopePaths = [[]]
            }
        , SDK.ChainProto
            { SDK.chainNode = [1,0,1]
            , SDK.chainRole = SDK.NodeChain
            , SDK.chainTerminal = "CheckTrend"
            , SDK.chainEntry = RunCheckTrendGen
            , SDK.chainReaches = [RunCheckTrendGen, StreamTemperatureSampleGen]
            , SDK.chainDrives = []
            , SDK.chainReads = []
            , SDK.chainScopePaths = [[]]
            }
        , SDK.ChainProto
            { SDK.chainNode = [1,1,0]
            , SDK.chainRole = SDK.NodeChain
            , SDK.chainTerminal = "ReportHeartbeat"
            , SDK.chainEntry = RunReportHeartbeatGen
            , SDK.chainReaches = [RunReportHeartbeatGen, StreamBeatGen]
            , SDK.chainDrives = []
            , SDK.chainReads = []
            , SDK.chainScopePaths = [[]]
            }
        , SDK.ChainProto
            { SDK.chainNode = [1,-1,0,0]
            , SDK.chainRole = SDK.SessionChain
            , SDK.chainTerminal = "TemperatureSample"
            , SDK.chainEntry = NextTemperatureFeedGen
            , SDK.chainReaches =
                [NextTemperatureFeedGen, OpenSensorLinkGen, GetSensorStateGen, ReadSensorStateGen]
            , SDK.chainDrives = []
            , SDK.chainReads = []
            , SDK.chainScopePaths = [[OpenSensorLinkGen]]
            }
        , SDK.ChainProto
            { SDK.chainNode = [1,-1,0,1]
            , SDK.chainRole = SDK.SessionChain
            , SDK.chainTerminal = "TemperatureSample"
            , SDK.chainEntry = GetTemperatureSampleGen
            , SDK.chainReaches =
                [ GetTemperatureSampleGen
                , NextTemperatureFeedGen
                , OpenSensorLinkGen
                , GetSensorStateGen
                , ReadSensorStateGen
                ]
            , SDK.chainDrives = ["TemperatureSample"]
            , SDK.chainReads = []
            , SDK.chainScopePaths = [[OpenSensorLinkGen]]
            }
        , SDK.ChainProto
            { SDK.chainNode = [1,-1,1,0]
            , SDK.chainRole = SDK.SessionChain
            , SDK.chainTerminal = "Beat"
            , SDK.chainEntry = NextHeartbeatClockGen
            , SDK.chainReaches =
                [NextHeartbeatClockGen, OpenSensorLinkGen, GetSensorStateGen, ReadSensorStateGen]
            , SDK.chainDrives = []
            , SDK.chainReads = []
            , SDK.chainScopePaths = [[OpenSensorLinkGen]]
            }
        , SDK.ChainProto
            { SDK.chainNode = [1,-1,1,1]
            , SDK.chainRole = SDK.SessionChain
            , SDK.chainTerminal = "Beat"
            , SDK.chainEntry = GetBeatGen
            , SDK.chainReaches =
                [GetBeatGen, NextHeartbeatClockGen, OpenSensorLinkGen, GetSensorStateGen, ReadSensorStateGen]
            , SDK.chainDrives = ["Beat"]
            , SDK.chainReads = []
            , SDK.chainScopePaths = [[OpenSensorLinkGen]]
            }
        , SDK.ChainProto
            { SDK.chainNode = [-2,0,0]
            , SDK.chainRole = SDK.SessionChain
            , SDK.chainTerminal = "TemperatureSample"
            , SDK.chainEntry = NextTemperatureFeedGen
            , SDK.chainReaches =
                [NextTemperatureFeedGen, OpenSensorLinkGen, GetSensorStateGen, ReadSensorStateGen]
            , SDK.chainDrives = []
            , SDK.chainReads = []
            , SDK.chainScopePaths = [[OpenSensorLinkGen]]
            }
        , SDK.ChainProto
            { SDK.chainNode = [-2,0,1]
            , SDK.chainRole = SDK.SessionChain
            , SDK.chainTerminal = "TemperatureSample"
            , SDK.chainEntry = GetTemperatureSampleGen
            , SDK.chainReaches =
                [ GetTemperatureSampleGen
                , NextTemperatureFeedGen
                , OpenSensorLinkGen
                , GetSensorStateGen
                , ReadSensorStateGen
                ]
            , SDK.chainDrives = ["TemperatureSample"]
            , SDK.chainReads = []
            , SDK.chainScopePaths = [[OpenSensorLinkGen]]
            }
        , SDK.ChainProto
            { SDK.chainNode = [-2,1,0]
            , SDK.chainRole = SDK.SessionChain
            , SDK.chainTerminal = "Beat"
            , SDK.chainEntry = NextHeartbeatClockGen
            , SDK.chainReaches =
                [NextHeartbeatClockGen, OpenSensorLinkGen, GetSensorStateGen, ReadSensorStateGen]
            , SDK.chainDrives = []
            , SDK.chainReads = []
            , SDK.chainScopePaths = [[OpenSensorLinkGen]]
            }
        , SDK.ChainProto
            { SDK.chainNode = [-2,1,1]
            , SDK.chainRole = SDK.SessionChain
            , SDK.chainTerminal = "Beat"
            , SDK.chainEntry = GetBeatGen
            , SDK.chainReaches =
                [GetBeatGen, NextHeartbeatClockGen, OpenSensorLinkGen, GetSensorStateGen, ReadSensorStateGen]
            , SDK.chainDrives = ["Beat"]
            , SDK.chainReads = []
            , SDK.chainScopePaths = [[OpenSensorLinkGen]]
            }
        ]
    , SDK.protoChainDefinitions =
        [ SDK.ChainDefinition
            { SDK.definitionKind = SDK.ContextChain
            , SDK.definitionEffect = "SensorResource"
            , SDK.definitionEntry = GetSensorStateGen
            , SDK.definitionReaches = [GetSensorStateGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.ContextChain
            , SDK.definitionEffect = "SensorResource"
            , SDK.definitionEntry = ReadSensorStateGen
            , SDK.definitionReaches = [ReadSensorStateGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.OriginChain
            , SDK.definitionEffect = "SensorLink"
            , SDK.definitionEntry = OpenSensorLinkGen
            , SDK.definitionReaches = [OpenSensorLinkGen, GetSensorStateGen, ReadSensorStateGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.ContextChain
            , SDK.definitionEffect = "TemperatureFeed"
            , SDK.definitionEntry = NextTemperatureFeedGen
            , SDK.definitionReaches =
                [NextTemperatureFeedGen, OpenSensorLinkGen, GetSensorStateGen, ReadSensorStateGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.ContextChain
            , SDK.definitionEffect = "TemperatureParser"
            , SDK.definitionEntry = GetTemperatureSampleGen
            , SDK.definitionReaches =
                [ GetTemperatureSampleGen
                , NextTemperatureFeedGen
                , OpenSensorLinkGen
                , GetSensorStateGen
                , ReadSensorStateGen
                ]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.ContextChain
            , SDK.definitionEffect = "TemperatureParser"
            , SDK.definitionEntry = StreamTemperatureSampleGen
            , SDK.definitionReaches = [StreamTemperatureSampleGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.ContextChain
            , SDK.definitionEffect = "HeartbeatClock"
            , SDK.definitionEntry = NextHeartbeatClockGen
            , SDK.definitionReaches =
                [NextHeartbeatClockGen, OpenSensorLinkGen, GetSensorStateGen, ReadSensorStateGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.ContextChain
            , SDK.definitionEffect = "Heartbeat"
            , SDK.definitionEntry = GetBeatGen
            , SDK.definitionReaches =
                [GetBeatGen, NextHeartbeatClockGen, OpenSensorLinkGen, GetSensorStateGen, ReadSensorStateGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.ContextChain
            , SDK.definitionEffect = "Heartbeat"
            , SDK.definitionEntry = StreamBeatGen
            , SDK.definitionReaches = [StreamBeatGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.OriginChain
            , SDK.definitionEffect = "Announce"
            , SDK.definitionEntry = RunAnnounceGen
            , SDK.definitionReaches = [RunAnnounceGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.OriginChain
            , SDK.definitionEffect = "ShowTemperature"
            , SDK.definitionEntry = RunShowTemperatureGen
            , SDK.definitionReaches = [RunShowTemperatureGen, StreamTemperatureSampleGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.OriginChain
            , SDK.definitionEffect = "CheckTrend"
            , SDK.definitionEntry = RunCheckTrendGen
            , SDK.definitionReaches = [RunCheckTrendGen, StreamTemperatureSampleGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.OriginChain
            , SDK.definitionEffect = "ReportHeartbeat"
            , SDK.definitionEntry = RunReportHeartbeatGen
            , SDK.definitionReaches = [RunReportHeartbeatGen, StreamBeatGen]
            }
        ]
    , SDK.protoGraph =
        SDK.EffectGraph
          { SDK.graphMethods =
              [ SDK.MethodDefinition RunAnnounceGen RunAnnounceGen SDK.HandlerMethod SDK.Empty
              , SDK.MethodDefinition
                  RunShowTemperatureGen
                  RunShowTemperatureGen
                  SDK.HandlerMethod
                  (SDK.Call StreamTemperatureSampleGen)
              , SDK.MethodDefinition StreamTemperatureSampleGen GetTemperatureSampleGen SDK.ContextRequire SDK.Empty
              , SDK.MethodDefinition
                  RunCheckTrendGen
                  RunCheckTrendGen
                  SDK.HandlerMethod
                  (SDK.Call StreamTemperatureSampleGen)
              , SDK.MethodDefinition
                  RunReportHeartbeatGen
                  RunReportHeartbeatGen
                  SDK.HandlerMethod
                  (SDK.Call StreamBeatGen)
              , SDK.MethodDefinition StreamBeatGen GetBeatGen SDK.ContextRequire SDK.Empty
              , SDK.MethodDefinition
                  NextTemperatureFeedGen
                  NextTemperatureFeedGen
                  SDK.StreamHandler
                  (SDK.Call OpenSensorLinkGen)
              , SDK.MethodDefinition
                  OpenSensorLinkGen
                  OpenSensorLinkGen
                  SDK.ScopeOpen
                  (SDK.Sequence [SDK.Call GetSensorStateGen, SDK.Call ReadSensorStateGen])
              , SDK.MethodDefinition GetSensorStateGen GetSensorStateGen SDK.ContextRequest SDK.Empty
              , SDK.MethodDefinition ReadSensorStateGen GetSensorStateGen SDK.ContextRequire SDK.Empty
              , SDK.MethodDefinition
                  GetTemperatureSampleGen
                  GetTemperatureSampleGen
                  SDK.ContextStream
                  (SDK.Sequence [SDK.Call NextTemperatureFeedGen, SDK.Call ReadSensorStateGen])
              , SDK.MethodDefinition
                  NextHeartbeatClockGen
                  NextHeartbeatClockGen
                  SDK.StreamHandler
                  (SDK.Call OpenSensorLinkGen)
              , SDK.MethodDefinition
                  GetBeatGen
                  GetBeatGen
                  SDK.ContextStream
                  (SDK.Sequence [SDK.Call NextHeartbeatClockGen, SDK.Call ReadSensorStateGen])
              ]
          , SDK.graphRoots =
              [ RunAnnounceGen
              , RunShowTemperatureGen
              , RunCheckTrendGen
              , RunReportHeartbeatGen
              , NextTemperatureFeedGen
              , GetTemperatureSampleGen
              , NextHeartbeatClockGen
              , GetBeatGen
              ]
          , SDK.graphReferences =
              [ (RunShowTemperatureGen, StreamTemperatureSampleGen)
              , (RunCheckTrendGen, StreamTemperatureSampleGen)
              , (RunReportHeartbeatGen, StreamBeatGen)
              , (NextTemperatureFeedGen, OpenSensorLinkGen)
              , (OpenSensorLinkGen, GetSensorStateGen)
              , (OpenSensorLinkGen, ReadSensorStateGen)
              , (GetTemperatureSampleGen, NextTemperatureFeedGen)
              , (GetTemperatureSampleGen, ReadSensorStateGen)
              , (NextHeartbeatClockGen, OpenSensorLinkGen)
              , (GetBeatGen, NextHeartbeatClockGen)
              , (GetBeatGen, ReadSensorStateGen)
              ]
          , SDK.graphScopes = [OpenSensorLinkGen]
          , SDK.graphScopePaths = [[], [OpenSensorLinkGen]]
          , SDK.graphRootPaths =
              [ (RunAnnounceGen, [[]])
              , (RunShowTemperatureGen, [[]])
              , (RunCheckTrendGen, [[]])
              , (RunReportHeartbeatGen, [[]])
              , (NextTemperatureFeedGen, [[OpenSensorLinkGen]])
              , (GetTemperatureSampleGen, [[OpenSensorLinkGen]])
              , (NextHeartbeatClockGen, [[OpenSensorLinkGen]])
              , (GetBeatGen, [[OpenSensorLinkGen]])
              ]
          , SDK.graphScopeOrder = []
          }
    , SDK.protoScopes =
        SDK.ScopeTree
          { SDK.scopeRoots = [OpenSensorLinkGen]
          , SDK.scopeNodes =
              [ SDK.ScopeNode
                  { SDK.scopeIdentity = OpenSensorLinkGen
                  , SDK.scopeParents = []
                  , SDK.scopeChildren = []
                  }
              ]
          , SDK.scopeLayers = [[OpenSensorLinkGen]]
          , SDK.scopePaths = [[], [OpenSensorLinkGen]]
          , SDK.scopeCandidates = []
          , SDK.scopeOpposed = []
          , SDK.scopeUndetermined = []
          }
    , SDK.protoScopeNames = [(OpenSensorLinkGen, "SensorLink")]
    , SDK.protoSources = []
    , SDK.protoScopeOpenings =
        [ SDK.ScopeOpeningPlan
            { SDK.openingNode = [-2,1,1]
            , SDK.openingScope = "SensorLink"
            , SDK.openingSources = []
            , SDK.openingKinds = [SDK.RegistrationSingleton]
            }
        , SDK.ScopeOpeningPlan
            { SDK.openingNode = [-2,1,0]
            , SDK.openingScope = "SensorLink"
            , SDK.openingSources = []
            , SDK.openingKinds = [SDK.RegistrationSingleton]
            }
        , SDK.ScopeOpeningPlan
            { SDK.openingNode = [-2,0,1]
            , SDK.openingScope = "SensorLink"
            , SDK.openingSources = []
            , SDK.openingKinds = [SDK.RegistrationSingleton]
            }
        , SDK.ScopeOpeningPlan
            { SDK.openingNode = [-2,0,0]
            , SDK.openingScope = "SensorLink"
            , SDK.openingSources = []
            , SDK.openingKinds = [SDK.RegistrationSingleton]
            }
        , SDK.ScopeOpeningPlan
            { SDK.openingNode = [1,-1,1,1]
            , SDK.openingScope = "SensorLink"
            , SDK.openingSources = []
            , SDK.openingKinds = [SDK.RegistrationSingleton]
            }
        , SDK.ScopeOpeningPlan
            { SDK.openingNode = [1,-1,1,0]
            , SDK.openingScope = "SensorLink"
            , SDK.openingSources = []
            , SDK.openingKinds = [SDK.RegistrationSingleton]
            }
        , SDK.ScopeOpeningPlan
            { SDK.openingNode = [1,-1,0,1]
            , SDK.openingScope = "SensorLink"
            , SDK.openingSources = []
            , SDK.openingKinds = [SDK.RegistrationSingleton]
            }
        , SDK.ScopeOpeningPlan
            { SDK.openingNode = [1,-1,0,0]
            , SDK.openingScope = "SensorLink"
            , SDK.openingSources = []
            , SDK.openingKinds = [SDK.RegistrationSingleton]
            }
        ]
    , SDK.protoDriving =
        SDK.DrivingPlan
          { SDK.drivingNodes =
              [ SDK.NodeDrive [] [[0,0],[1,0,0],[1,0,1],[1,1,0]] [] Nothing [] [] []
              , SDK.NodeDrive [0] [[0,0]] [] Nothing [] [] []
              , SDK.NodeDrive [0,0] [[0,0]] [] Nothing [] [] []
              , SDK.NodeDrive [1] [[1,0,0],[1,0,1],[1,1,0]] [] (Just [1]) [] [] []
              , SDK.NodeDrive [1,0] [[1,0,0],[1,0,1]] [] (Just [1]) [] [] []
              , SDK.NodeDrive [1,0,0] [[1,0,0]] ["TemperatureParser"] (Just [1]) [] [] []
              , SDK.NodeDrive [1,0,1] [[1,0,1]] ["TemperatureParser"] (Just [1]) [] [] []
              , SDK.NodeDrive [1,1] [[1,1,0]] [] (Just [1]) [] [] []
              , SDK.NodeDrive [1,1,0] [[1,1,0]] ["Heartbeat"] (Just [1]) [] [] []
              , SDK.NodeDrive [1,-1,0,0] [] [] (Just [1]) [] [] []
              , SDK.NodeDrive [1,-1,0,1] [] [] (Just [1]) [] [] []
              , SDK.NodeDrive [1,-1,1,0] [] [] (Just [1]) [] [] []
              , SDK.NodeDrive [1,-1,1,1] [] [] (Just [1]) [] [] []
              , SDK.NodeDrive [-2,0,0] [] [] Nothing [] [] []
              , SDK.NodeDrive [-2,0,1] [] [] Nothing [] [] []
              , SDK.NodeDrive [-2,1,0] [] [] Nothing [] [] []
              , SDK.NodeDrive [-2,1,1] [] [] Nothing [] [] []
              ]
          , SDK.drivingUnits =
              [ SDK.UnitDrive
                  [1,0]
                  [[1,0,0],[1,0,1]]
                  [("TemperatureParser", [SDK.ReadAt [1,0,0], SDK.ReadAt [1,0,1]]), ("Heartbeat", [])]
                  []
              , SDK.UnitDrive [1,1] [[1,1,0]] [("TemperatureParser", []), ("Heartbeat", [SDK.ReadAt [1,1,0]])] []
              ]
          , SDK.drivingSessions =
              [ SDK.SessionDrive Nothing "TemperatureParser" "TemperatureSample" Nothing
              , SDK.SessionDrive Nothing "Heartbeat" "Beat" Nothing
              , SDK.SessionDrive (Just [1]) "TemperatureParser" "TemperatureSample" Nothing
              , SDK.SessionDrive (Just [1]) "Heartbeat" "Beat" Nothing
              ]
          , SDK.drivingRootNodes = [[0,0],[1,0,0],[1,0,1],[1,1,0]]
          , SDK.drivingOutputSites = []
          , SDK.drivingRequests =
              [ ("SensorResource", GetSensorStateGen)
              , ("TemperatureParser", GetTemperatureSampleGen)
              , ("Heartbeat", GetBeatGen)
              ]
          , SDK.drivingMiddleware = []
          , SDK.drivingHooks = []
          }
    }
