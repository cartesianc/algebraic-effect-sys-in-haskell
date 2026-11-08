{-# LANGUAGE DuplicateRecordFields #-}

-- 自动生成；只登记末端入口与原型，执行由 SDK 的 interpreter 完成。
module StreamDemo.Generated.Program where

import Framework.Generated (EffectSpec(..), EffectTyping(..), Asset(..), Handles(..), Demand(..), Access(..), TypeRef(..))
import qualified Framework.Generated as SDK
import StreamDemo.Generated.Effects
import qualified StreamDemo.Generated.Handlers as Handlers
import StreamDemo.Types


-- 仅汇总所选末端的成功结果，不保存共享绑定或增加完成包装。
data Results = AnnounceResult () | ShowTemperatureResult () | CheckTrendResult () | ReportHeartbeatResult ()
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
      , SDK.targetApp "ShowTemperature" emptyContexts scopes (SDK.withErrorHandlers Handlers.errorHandlers (SDK.withAnchoredContexts Handlers.contextInjections (SDK.withScopeCleanups Handlers.scopeCleanups (ShowTemperatureResult <$> (() <$ Handlers.runShowTemperature)))))
      , SDK.targetApp "CheckTrend" emptyContexts scopes (SDK.withErrorHandlers Handlers.errorHandlers (SDK.withAnchoredContexts Handlers.contextInjections (SDK.withScopeCleanups Handlers.scopeCleanups (CheckTrendResult <$> (() <$ Handlers.runCheckTrend)))))
      , SDK.targetApp "ReportHeartbeat" emptyContexts scopes (SDK.withErrorHandlers Handlers.errorHandlers (SDK.withAnchoredContexts Handlers.contextInjections (SDK.withScopeCleanups Handlers.scopeCleanups (ReportHeartbeatResult <$> (() <$ Handlers.runReportHeartbeat)))))
      ]
    , []
    , [ ("TemperatureParser", SDK.receiveSteps (SDK.targetApp "TemperatureFeed" emptyContexts scopes (SDK.withErrorHandlers Handlers.errorHandlers (SDK.withAnchoredContexts Handlers.contextInjections (SDK.withScopeCleanups Handlers.scopeCleanups (Handlers.nextTemperatureFeed))))) (SDK.targetApp "TemperatureParser" emptyContexts scopes (SDK.withErrorHandlers Handlers.errorHandlers (SDK.withAnchoredContexts Handlers.contextInjections (SDK.withScopeCleanups Handlers.scopeCleanups (() <$ Handlers.getTemperatureSample))))))
      , ("Heartbeat", SDK.receiveSteps (SDK.targetApp "HeartbeatClock" emptyContexts scopes (SDK.withErrorHandlers Handlers.errorHandlers (SDK.withAnchoredContexts Handlers.contextInjections (SDK.withScopeCleanups Handlers.scopeCleanups (Handlers.nextHeartbeatClock))))) (SDK.targetApp "Heartbeat" emptyContexts scopes (SDK.withErrorHandlers Handlers.errorHandlers (SDK.withAnchoredContexts Handlers.contextInjections (SDK.withScopeCleanups Handlers.scopeCleanups (() <$ Handlers.getBeat))))))
      ]
    )

-- SDK 装配入口，不需要用户提供节点执行器或重复选择 handler。
interpreter :: SDK.AST -> [EffectSpec] -> IO ()
interpreter = SDK.interpreter "StreamDemo" "demo/StreamDemo/Handlers.hs" Handlers.handlerSourceFingerprint generatedPrototype compiledEntries
-- 生成时完成注册、方法、origin/ctx 链、资产来源、Workflow 和 scope 的统一分析。
-- NodeId 只在这份 AST 快照中有效；运行时校验后装配闭包。
generatedPrototype :: SDK.Prototype MethodGen
generatedPrototype =
  SDK.Prototype
    { SDK.protoRegistrations =
        [ SDK.EffectSpec
            { SDK.name = "SensorLink"
            , SDK.typing = SDK.Scoped (Just "connectSensor") (Just "disconnectSensor")
            , SDK.input = "Root"
            , SDK.demands = []
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
                  (SDK.AssetDecl ("TemperatureSample") (SDK.TypeRef ("Temperature")))
                  (Just "parseTemperature")
                  (True)
                  (True)
            , SDK.input = "TemperatureFeed"
            , SDK.demands = []
            }
        , SDK.EffectSpec
            { SDK.name = "HeartbeatClock"
            , SDK.typing = SDK.Stream (Just "nextBeat")
            , SDK.input = "Root"
            , SDK.demands = []
            }
        , SDK.EffectSpec
            { SDK.name = "Heartbeat"
            , SDK.typing =
                SDK.Context (SDK.AssetDecl ("Beat") (SDK.TypeRef ("Int"))) (Just "parseBeat") (True) (True)
            , SDK.input = "HeartbeatClock"
            , SDK.demands = []
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
            , SDK.demands = [SDK.Demand (SDK.StreamAccess) ("TemperatureSample")]
            }
        , SDK.EffectSpec
            { SDK.name = "CheckTrend"
            , SDK.typing = SDK.Excu (Just "checkTrend")
            , SDK.input = "Root"
            , SDK.demands = [SDK.Demand (SDK.StreamAccess) ("TemperatureSample")]
            }
        , SDK.EffectSpec
            { SDK.name = "ReportHeartbeat"
            , SDK.typing = SDK.Excu (Just "reportHeartbeat")
            , SDK.input = "Root"
            , SDK.demands = [SDK.Demand (SDK.StreamAccess) ("Beat")]
            }
        ]
    , SDK.protoEffects =
        [ SDK.EffectProto
            { SDK.effectName = "SensorLink"
            , SDK.effectKind = SDK.ScopedKind
            , SDK.effectInput = "Root"
            , SDK.effectMethods = [(SDK.ScopeOpen, OpenSensorLinkGen), (SDK.ScopeClose, CloseSensorLinkGen)]
            , SDK.effectDemands = []
            , SDK.effectProduces = Nothing
            , SDK.effectBranches = []
            , SDK.effectAnchor = Nothing
            , SDK.effectScopes = []
            , SDK.effectErrorScope = Nothing
            , SDK.effectInputChain = []
            , SDK.effectScopeParents = []
            , SDK.effectOpeningInputs = []
            , SDK.effectNearestScopes = ["SensorLink"]
            , SDK.effectResource = Nothing
            , SDK.effectContextDependencies = []
            , SDK.effectContinuous = False
            }
        , SDK.EffectProto
            { SDK.effectName = "TemperatureFeed"
            , SDK.effectKind = SDK.StreamKind
            , SDK.effectInput = "SensorLink"
            , SDK.effectMethods = [(SDK.StreamHandler, NextTemperatureFeedGen)]
            , SDK.effectDemands = []
            , SDK.effectProduces = Nothing
            , SDK.effectBranches = []
            , SDK.effectAnchor = Nothing
            , SDK.effectScopes = ["SensorLink"]
            , SDK.effectErrorScope = Nothing
            , SDK.effectInputChain = ["SensorLink"]
            , SDK.effectScopeParents = ["SensorLink"]
            , SDK.effectOpeningInputs = []
            , SDK.effectNearestScopes = ["SensorLink"]
            , SDK.effectResource = Nothing
            , SDK.effectContextDependencies = []
            , SDK.effectContinuous = False
            }
        , SDK.EffectProto
            { SDK.effectName = "TemperatureParser"
            , SDK.effectKind = SDK.ContextKind
            , SDK.effectInput = "TemperatureFeed"
            , SDK.effectMethods =
                [(SDK.ContextStream, GetTemperatureSampleGen), (SDK.ContextRequire, StreamTemperatureSampleGen)]
            , SDK.effectDemands = []
            , SDK.effectProduces = Just "TemperatureSample"
            , SDK.effectBranches = []
            , SDK.effectAnchor = Nothing
            , SDK.effectScopes = ["SensorLink"]
            , SDK.effectErrorScope = Nothing
            , SDK.effectInputChain = ["TemperatureFeed","SensorLink"]
            , SDK.effectScopeParents = ["SensorLink"]
            , SDK.effectOpeningInputs = []
            , SDK.effectNearestScopes = ["SensorLink"]
            , SDK.effectResource = Nothing
            , SDK.effectContextDependencies = []
            , SDK.effectContinuous = True
            }
        , SDK.EffectProto
            { SDK.effectName = "HeartbeatClock"
            , SDK.effectKind = SDK.StreamKind
            , SDK.effectInput = "Root"
            , SDK.effectMethods = [(SDK.StreamHandler, NextHeartbeatClockGen)]
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
            { SDK.effectName = "Heartbeat"
            , SDK.effectKind = SDK.ContextKind
            , SDK.effectInput = "HeartbeatClock"
            , SDK.effectMethods = [(SDK.ContextStream, GetBeatGen), (SDK.ContextRequire, StreamBeatGen)]
            , SDK.effectDemands = []
            , SDK.effectProduces = Just "Beat"
            , SDK.effectBranches = []
            , SDK.effectAnchor = Nothing
            , SDK.effectScopes = []
            , SDK.effectErrorScope = Nothing
            , SDK.effectInputChain = ["HeartbeatClock"]
            , SDK.effectScopeParents = []
            , SDK.effectOpeningInputs = []
            , SDK.effectNearestScopes = []
            , SDK.effectResource = Nothing
            , SDK.effectContextDependencies = []
            , SDK.effectContinuous = True
            }
        , SDK.EffectProto
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
            { SDK.effectName = "ShowTemperature"
            , SDK.effectKind = SDK.ExcuKind
            , SDK.effectInput = "Root"
            , SDK.effectMethods = [(SDK.HandlerMethod, RunShowTemperatureGen)]
            , SDK.effectDemands =
                [SDK.ResolvedDemand (SDK.StreamAccess) ("TemperatureSample") ("TemperatureParser")]
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
            , SDK.effectContextDependencies = ["TemperatureParser"]
            , SDK.effectContinuous = False
            }
        , SDK.EffectProto
            { SDK.effectName = "CheckTrend"
            , SDK.effectKind = SDK.ExcuKind
            , SDK.effectInput = "Root"
            , SDK.effectMethods = [(SDK.HandlerMethod, RunCheckTrendGen)]
            , SDK.effectDemands =
                [SDK.ResolvedDemand (SDK.StreamAccess) ("TemperatureSample") ("TemperatureParser")]
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
            , SDK.effectContextDependencies = ["TemperatureParser"]
            , SDK.effectContinuous = False
            }
        , SDK.EffectProto
            { SDK.effectName = "ReportHeartbeat"
            , SDK.effectKind = SDK.ExcuKind
            , SDK.effectInput = "Root"
            , SDK.effectMethods = [(SDK.HandlerMethod, RunReportHeartbeatGen)]
            , SDK.effectDemands = [SDK.ResolvedDemand (SDK.StreamAccess) ("Beat") ("Heartbeat")]
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
            , SDK.effectContextDependencies = ["Heartbeat"]
            , SDK.effectContinuous = False
            }
        ]
    , SDK.protoMethods =
        [ SDK.MethodDefinition (OpenSensorLinkGen) (OpenSensorLinkGen) (SDK.ScopeOpen) (SDK.Empty)
        , SDK.MethodDefinition (CloseSensorLinkGen) (OpenSensorLinkGen) (SDK.ScopeClose) (SDK.Empty)
        , SDK.MethodDefinition
            (NextTemperatureFeedGen)
            (NextTemperatureFeedGen)
            (SDK.StreamHandler)
            (SDK.Call (OpenSensorLinkGen))
        , SDK.MethodDefinition
            (GetTemperatureSampleGen)
            (GetTemperatureSampleGen)
            (SDK.ContextStream)
            (SDK.Call (NextTemperatureFeedGen))
        , SDK.MethodDefinition
            (StreamTemperatureSampleGen)
            (GetTemperatureSampleGen)
            (SDK.ContextRequire)
            (SDK.Empty)
        , SDK.MethodDefinition (NextHeartbeatClockGen) (NextHeartbeatClockGen) (SDK.StreamHandler) (SDK.Empty)
        , SDK.MethodDefinition
            (GetBeatGen)
            (GetBeatGen)
            (SDK.ContextStream)
            (SDK.Call (NextHeartbeatClockGen))
        , SDK.MethodDefinition (StreamBeatGen) (GetBeatGen) (SDK.ContextRequire) (SDK.Empty)
        , SDK.MethodDefinition (RunAnnounceGen) (RunAnnounceGen) (SDK.HandlerMethod) (SDK.Empty)
        , SDK.MethodDefinition
            (RunShowTemperatureGen)
            (RunShowTemperatureGen)
            (SDK.HandlerMethod)
            (SDK.Call (StreamTemperatureSampleGen))
        , SDK.MethodDefinition
            (RunCheckTrendGen)
            (RunCheckTrendGen)
            (SDK.HandlerMethod)
            (SDK.Call (StreamTemperatureSampleGen))
        , SDK.MethodDefinition
            (RunReportHeartbeatGen)
            (RunReportHeartbeatGen)
            (SDK.HandlerMethod)
            (SDK.Call (StreamBeatGen))
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
                    { SDK.lifelongUnits = [[1,0],[1,1]]
                    , SDK.lifelongSubscriptions =
                        [([1,0,0],"TemperatureSample"),([1,0,1],"TemperatureSample"),([1,1,0],"Beat")]
                    , SDK.lifelongSessions =
                        [ SDK.SessionProto
                            { SDK.sessionAsset = "TemperatureSample"
                            , SDK.sessionPlan = SDK.Receive ("TemperatureFeed")
                            , SDK.sessionMounts = [[1,-1,0,0],[1,-1,0,1]]
                            }
                        , SDK.SessionProto
                            { SDK.sessionAsset = "Beat"
                            , SDK.sessionPlan = SDK.Receive ("HeartbeatClock")
                            , SDK.sessionMounts = [[1,-1,1,0],[1,-1,1,1]]
                            }
                        ]
                    }
                )
                (
                  [ SDK.ChainedAt
                      ([1,0])
                      (
                        [ SDK.NodeAt ([1,0,0]) ("ShowTemperature")
                        , SDK.NodeAt ([1,0,1]) ("CheckTrend")
                        ]
                      )
                  , SDK.ChainedAt
                      ([1,1])
                      (
                        [ SDK.NodeAt ([1,1,0]) ("ReportHeartbeat")
                        ]
                      )
                  ]
                )
            ]
          )
    , SDK.protoSessions =
        [ SDK.SessionProto
            { SDK.sessionAsset = "TemperatureSample"
            , SDK.sessionPlan = SDK.Receive ("TemperatureFeed")
            , SDK.sessionMounts = [[-2,0,0],[-2,0,1]]
            }
        , SDK.SessionProto
            { SDK.sessionAsset = "Beat"
            , SDK.sessionPlan = SDK.Receive ("HeartbeatClock")
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
            , SDK.chainReaches = [NextTemperatureFeedGen, OpenSensorLinkGen]
            , SDK.chainDrives = []
            , SDK.chainReads = []
            , SDK.chainScopePaths = [[OpenSensorLinkGen]]
            }
        , SDK.ChainProto
            { SDK.chainNode = [1,-1,0,1]
            , SDK.chainRole = SDK.SessionChain
            , SDK.chainTerminal = "TemperatureSample"
            , SDK.chainEntry = GetTemperatureSampleGen
            , SDK.chainReaches = [GetTemperatureSampleGen, NextTemperatureFeedGen, OpenSensorLinkGen]
            , SDK.chainDrives = ["TemperatureSample"]
            , SDK.chainReads = []
            , SDK.chainScopePaths = [[OpenSensorLinkGen]]
            }
        , SDK.ChainProto
            { SDK.chainNode = [1,-1,1,0]
            , SDK.chainRole = SDK.SessionChain
            , SDK.chainTerminal = "Beat"
            , SDK.chainEntry = NextHeartbeatClockGen
            , SDK.chainReaches = [NextHeartbeatClockGen]
            , SDK.chainDrives = []
            , SDK.chainReads = []
            , SDK.chainScopePaths = [[]]
            }
        , SDK.ChainProto
            { SDK.chainNode = [1,-1,1,1]
            , SDK.chainRole = SDK.SessionChain
            , SDK.chainTerminal = "Beat"
            , SDK.chainEntry = GetBeatGen
            , SDK.chainReaches = [GetBeatGen, NextHeartbeatClockGen]
            , SDK.chainDrives = ["Beat"]
            , SDK.chainReads = []
            , SDK.chainScopePaths = [[]]
            }
        , SDK.ChainProto
            { SDK.chainNode = [-2,0,0]
            , SDK.chainRole = SDK.SessionChain
            , SDK.chainTerminal = "TemperatureSample"
            , SDK.chainEntry = NextTemperatureFeedGen
            , SDK.chainReaches = [NextTemperatureFeedGen, OpenSensorLinkGen]
            , SDK.chainDrives = []
            , SDK.chainReads = []
            , SDK.chainScopePaths = [[OpenSensorLinkGen]]
            }
        , SDK.ChainProto
            { SDK.chainNode = [-2,0,1]
            , SDK.chainRole = SDK.SessionChain
            , SDK.chainTerminal = "TemperatureSample"
            , SDK.chainEntry = GetTemperatureSampleGen
            , SDK.chainReaches = [GetTemperatureSampleGen, NextTemperatureFeedGen, OpenSensorLinkGen]
            , SDK.chainDrives = ["TemperatureSample"]
            , SDK.chainReads = []
            , SDK.chainScopePaths = [[OpenSensorLinkGen]]
            }
        , SDK.ChainProto
            { SDK.chainNode = [-2,1,0]
            , SDK.chainRole = SDK.SessionChain
            , SDK.chainTerminal = "Beat"
            , SDK.chainEntry = NextHeartbeatClockGen
            , SDK.chainReaches = [NextHeartbeatClockGen]
            , SDK.chainDrives = []
            , SDK.chainReads = []
            , SDK.chainScopePaths = [[]]
            }
        , SDK.ChainProto
            { SDK.chainNode = [-2,1,1]
            , SDK.chainRole = SDK.SessionChain
            , SDK.chainTerminal = "Beat"
            , SDK.chainEntry = GetBeatGen
            , SDK.chainReaches = [GetBeatGen, NextHeartbeatClockGen]
            , SDK.chainDrives = ["Beat"]
            , SDK.chainReads = []
            , SDK.chainScopePaths = [[]]
            }
        ]
    , SDK.protoChainDefinitions =
        [ SDK.ChainDefinition
            { SDK.definitionKind = SDK.OriginChain
            , SDK.definitionEffect = "SensorLink"
            , SDK.definitionEntry = OpenSensorLinkGen
            , SDK.definitionReaches = [OpenSensorLinkGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.ContextChain
            , SDK.definitionEffect = "TemperatureFeed"
            , SDK.definitionEntry = NextTemperatureFeedGen
            , SDK.definitionReaches = [NextTemperatureFeedGen, OpenSensorLinkGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.ContextChain
            , SDK.definitionEffect = "TemperatureParser"
            , SDK.definitionEntry = GetTemperatureSampleGen
            , SDK.definitionReaches = [GetTemperatureSampleGen, NextTemperatureFeedGen, OpenSensorLinkGen]
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
            , SDK.definitionReaches = [NextHeartbeatClockGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.ContextChain
            , SDK.definitionEffect = "Heartbeat"
            , SDK.definitionEntry = GetBeatGen
            , SDK.definitionReaches = [GetBeatGen, NextHeartbeatClockGen]
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
              [ SDK.MethodDefinition (RunAnnounceGen) (RunAnnounceGen) (SDK.HandlerMethod) (SDK.Empty)
              , SDK.MethodDefinition
                  (RunShowTemperatureGen)
                  (RunShowTemperatureGen)
                  (SDK.HandlerMethod)
                  (SDK.Call (StreamTemperatureSampleGen))
              , SDK.MethodDefinition
                  (StreamTemperatureSampleGen)
                  (GetTemperatureSampleGen)
                  (SDK.ContextRequire)
                  (SDK.Empty)
              , SDK.MethodDefinition
                  (RunCheckTrendGen)
                  (RunCheckTrendGen)
                  (SDK.HandlerMethod)
                  (SDK.Call (StreamTemperatureSampleGen))
              , SDK.MethodDefinition
                  (RunReportHeartbeatGen)
                  (RunReportHeartbeatGen)
                  (SDK.HandlerMethod)
                  (SDK.Call (StreamBeatGen))
              , SDK.MethodDefinition (StreamBeatGen) (GetBeatGen) (SDK.ContextRequire) (SDK.Empty)
              , SDK.MethodDefinition
                  (NextTemperatureFeedGen)
                  (NextTemperatureFeedGen)
                  (SDK.StreamHandler)
                  (SDK.Call (OpenSensorLinkGen))
              , SDK.MethodDefinition (OpenSensorLinkGen) (OpenSensorLinkGen) (SDK.ScopeOpen) (SDK.Empty)
              , SDK.MethodDefinition
                  (GetTemperatureSampleGen)
                  (GetTemperatureSampleGen)
                  (SDK.ContextStream)
                  (SDK.Call (NextTemperatureFeedGen))
              , SDK.MethodDefinition (NextHeartbeatClockGen) (NextHeartbeatClockGen) (SDK.StreamHandler) (SDK.Empty)
              , SDK.MethodDefinition
                  (GetBeatGen)
                  (GetBeatGen)
                  (SDK.ContextStream)
                  (SDK.Call (NextHeartbeatClockGen))
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
              , (GetTemperatureSampleGen, NextTemperatureFeedGen)
              , (GetBeatGen, NextHeartbeatClockGen)
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
              , (NextHeartbeatClockGen, [[]])
              , (GetBeatGen, [[]])
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
    }
