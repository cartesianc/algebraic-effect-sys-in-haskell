{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE TypeFamilies #-}

-- 自动生成；只登记末端句柄，Node algebra 才 lower，业务组合仍在 handler 内。
module StreamDemo.Generated.Program where

import Framework.Generated (Effect(..), EffectSpec(..), EffectTyping(..), Asset(..), Handles(..), Demand(..), Access(..), TypeRef(..))
import qualified Framework.Generated as SDK
import qualified Framework.Effect.Contract as FrameworkRoot
import StreamDemo.Generated.Effects hiding (request, require)
import qualified StreamDemo.Generated.Handlers as Handlers
import StreamDemo.Types


-- 仅汇总所选末端的成功产物，不保存共享绑定或增加完成包装。
data Results = AnnounceResult (Produce Announce) | ShowTemperatureResult (Produce ShowTemperature) | CheckTrendResult (Produce CheckTrend) | ReportHeartbeatResult (Produce ReportHeartbeat)
  deriving Show

-- 末端共享生成的 scope 句柄；只创建空状态，Node algebra 才 lower，业务调用仍在 instance 内。
-- 第二个列表是各转折契约的读取末端：按 require 取得资产，返回它当前的构造器名。
-- 第三个列表是各持续资产的生产步骤：会话按需启动，解析器或 request 自己发布一次资产。
compiledEntries :: IO ([SDK.Target ContextValues Errors Results], [SDK.Target ContextValues Errors String]
                     , [(String, SDK.SessionSteps ContextValues Errors)])
compiledEntries = do
  scopes <- Handlers.newScopeHandlers
  pure
    ( [ SDK.targetApp "Announce" emptyContexts scopes (FrameworkRoot.withErrorHandlers Handlers.errorHandlers (FrameworkRoot.withAnchoredContexts Handlers.contextInjections (SDK.withScopeCleanups Handlers.scopeCleanups (AnnounceResult <$> (() <$ announce)))))
      , SDK.targetApp "ShowTemperature" emptyContexts scopes (FrameworkRoot.withErrorHandlers Handlers.errorHandlers (FrameworkRoot.withAnchoredContexts Handlers.contextInjections (SDK.withScopeCleanups Handlers.scopeCleanups (ShowTemperatureResult <$> (() <$ showTemperature)))))
      , SDK.targetApp "CheckTrend" emptyContexts scopes (FrameworkRoot.withErrorHandlers Handlers.errorHandlers (FrameworkRoot.withAnchoredContexts Handlers.contextInjections (SDK.withScopeCleanups Handlers.scopeCleanups (CheckTrendResult <$> (() <$ checkTrend)))))
      , SDK.targetApp "ReportHeartbeat" emptyContexts scopes (FrameworkRoot.withErrorHandlers Handlers.errorHandlers (FrameworkRoot.withAnchoredContexts Handlers.contextInjections (SDK.withScopeCleanups Handlers.scopeCleanups (ReportHeartbeatResult <$> (() <$ reportHeartbeat)))))
      ]
    , []
    , [ ("TemperatureParser", SDK.receiveSteps (SDK.targetApp "TemperatureFeed" emptyContexts scopes (FrameworkRoot.withErrorHandlers Handlers.errorHandlers (FrameworkRoot.withAnchoredContexts Handlers.contextInjections (SDK.withScopeCleanups Handlers.scopeCleanups (nextReading))))) (SDK.targetApp "TemperatureParser" emptyContexts scopes (FrameworkRoot.withErrorHandlers Handlers.errorHandlers (FrameworkRoot.withAnchoredContexts Handlers.contextInjections (SDK.withScopeCleanups Handlers.scopeCleanups (() <$ getTemperatureSample))))))
      , ("Heartbeat", SDK.requestSteps (SDK.targetApp "Heartbeat" emptyContexts scopes (FrameworkRoot.withErrorHandlers Handlers.errorHandlers (FrameworkRoot.withAnchoredContexts Handlers.contextInjections (SDK.withScopeCleanups Handlers.scopeCleanups (() <$ getBeat))))))
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
                  (Just ())
                  (Just ())
                  (Nothing)
            , SDK.input = "TemperatureFeed"
            , SDK.demands = []
            }
        , SDK.EffectSpec
            { SDK.name = "Heartbeat"
            , SDK.typing =
                SDK.Context (SDK.AssetDecl ("Beat") (SDK.TypeRef ("Int"))) (Just ()) (Just ()) (Just ())
            , SDK.input = "Root"
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
            , SDK.effectMethods = [(SDK.ScopeOpen, ConnectSensorGen), (SDK.ScopeClose, DisconnectSensorGen)]
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
            , SDK.effectMethods = [(SDK.StreamHandler, NextReadingGen)]
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
                [(SDK.ContextStream, GetTemperatureSampleGen), (SDK.ContextRequire, ReadTemperatureSampleGen)]
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
            { SDK.effectName = "Heartbeat"
            , SDK.effectKind = SDK.ContextKind
            , SDK.effectInput = "Root"
            , SDK.effectMethods = [(SDK.ContextRequest, GetBeatGen), (SDK.ContextRequire, ReadBeatGen)]
            , SDK.effectDemands = []
            , SDK.effectProduces = Just "Beat"
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
            , SDK.effectContinuous = True
            }
        , SDK.EffectProto
            { SDK.effectName = "Announce"
            , SDK.effectKind = SDK.ExcuKind
            , SDK.effectInput = "Root"
            , SDK.effectMethods = [(SDK.HandlerMethod, AnnounceGen)]
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
            , SDK.effectMethods = [(SDK.HandlerMethod, ShowTemperatureGen)]
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
            , SDK.effectMethods = [(SDK.HandlerMethod, CheckTrendGen)]
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
            , SDK.effectMethods = [(SDK.HandlerMethod, ReportHeartbeatGen)]
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
        [ SDK.MethodDefinition (ConnectSensorGen) (ConnectSensorGen) (SDK.ScopeOpen) (SDK.Empty)
        , SDK.MethodDefinition (DisconnectSensorGen) (ConnectSensorGen) (SDK.ScopeClose) (SDK.Empty)
        , SDK.MethodDefinition
            (NextReadingGen)
            (NextReadingGen)
            (SDK.StreamHandler)
            (SDK.Call (ConnectSensorGen))
        , SDK.MethodDefinition
            (GetTemperatureSampleGen)
            (GetTemperatureSampleGen)
            (SDK.ContextStream)
            (SDK.Call (NextReadingGen))
        , SDK.MethodDefinition
            (ReadTemperatureSampleGen)
            (GetTemperatureSampleGen)
            (SDK.ContextRequire)
            (SDK.Empty)
        , SDK.MethodDefinition (GetBeatGen) (GetBeatGen) (SDK.ContextRequest) (SDK.Empty)
        , SDK.MethodDefinition
            (ReadBeatGen)
            (GetBeatGen)
            (SDK.ContextRequire)
            (SDK.Choice ([SDK.Empty, SDK.Call (GetBeatGen)]))
        , SDK.MethodDefinition (AnnounceGen) (AnnounceGen) (SDK.HandlerMethod) (SDK.Empty)
        , SDK.MethodDefinition
            (ShowTemperatureGen)
            (ShowTemperatureGen)
            (SDK.HandlerMethod)
            (SDK.Call (ReadTemperatureSampleGen))
        , SDK.MethodDefinition
            (CheckTrendGen)
            (CheckTrendGen)
            (SDK.HandlerMethod)
            (SDK.Call (ReadTemperatureSampleGen))
        , SDK.MethodDefinition
            (ReportHeartbeatGen)
            (ReportHeartbeatGen)
            (SDK.HandlerMethod)
            (SDK.Call (ReadBeatGen))
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
                            , SDK.sessionPlan = SDK.RepeatRequest
                            , SDK.sessionMounts = [[1,-1,1,0]]
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
        ]
    , SDK.protoChains =
        [ SDK.ChainProto
            { SDK.chainNode = [0,0]
            , SDK.chainRole = SDK.NodeChain
            , SDK.chainTerminal = "Announce"
            , SDK.chainEntry = AnnounceGen
            , SDK.chainReaches = [AnnounceGen]
            , SDK.chainDrives = []
            , SDK.chainReads = []
            , SDK.chainScopePaths = [[]]
            }
        , SDK.ChainProto
            { SDK.chainNode = [1,0,0]
            , SDK.chainRole = SDK.NodeChain
            , SDK.chainTerminal = "ShowTemperature"
            , SDK.chainEntry = ShowTemperatureGen
            , SDK.chainReaches = [ShowTemperatureGen, ReadTemperatureSampleGen]
            , SDK.chainDrives = []
            , SDK.chainReads = []
            , SDK.chainScopePaths = [[]]
            }
        , SDK.ChainProto
            { SDK.chainNode = [1,0,1]
            , SDK.chainRole = SDK.NodeChain
            , SDK.chainTerminal = "CheckTrend"
            , SDK.chainEntry = CheckTrendGen
            , SDK.chainReaches = [CheckTrendGen, ReadTemperatureSampleGen]
            , SDK.chainDrives = []
            , SDK.chainReads = []
            , SDK.chainScopePaths = [[]]
            }
        , SDK.ChainProto
            { SDK.chainNode = [1,1,0]
            , SDK.chainRole = SDK.NodeChain
            , SDK.chainTerminal = "ReportHeartbeat"
            , SDK.chainEntry = ReportHeartbeatGen
            , SDK.chainReaches = [ReportHeartbeatGen, ReadBeatGen, GetBeatGen]
            , SDK.chainDrives = []
            , SDK.chainReads = []
            , SDK.chainScopePaths = [[]]
            }
        , SDK.ChainProto
            { SDK.chainNode = [1,-1,0,0]
            , SDK.chainRole = SDK.SessionChain
            , SDK.chainTerminal = "TemperatureSample"
            , SDK.chainEntry = NextReadingGen
            , SDK.chainReaches = [NextReadingGen, ConnectSensorGen]
            , SDK.chainDrives = []
            , SDK.chainReads = []
            , SDK.chainScopePaths = [[ConnectSensorGen]]
            }
        , SDK.ChainProto
            { SDK.chainNode = [1,-1,0,1]
            , SDK.chainRole = SDK.SessionChain
            , SDK.chainTerminal = "TemperatureSample"
            , SDK.chainEntry = GetTemperatureSampleGen
            , SDK.chainReaches = [GetTemperatureSampleGen, NextReadingGen, ConnectSensorGen]
            , SDK.chainDrives = ["TemperatureSample"]
            , SDK.chainReads = []
            , SDK.chainScopePaths = [[ConnectSensorGen]]
            }
        , SDK.ChainProto
            { SDK.chainNode = [1,-1,1,0]
            , SDK.chainRole = SDK.SessionChain
            , SDK.chainTerminal = "Beat"
            , SDK.chainEntry = GetBeatGen
            , SDK.chainReaches = [GetBeatGen]
            , SDK.chainDrives = ["Beat"]
            , SDK.chainReads = []
            , SDK.chainScopePaths = [[]]
            }
        , SDK.ChainProto
            { SDK.chainNode = [-2,0,0]
            , SDK.chainRole = SDK.SessionChain
            , SDK.chainTerminal = "TemperatureSample"
            , SDK.chainEntry = NextReadingGen
            , SDK.chainReaches = [NextReadingGen, ConnectSensorGen]
            , SDK.chainDrives = []
            , SDK.chainReads = []
            , SDK.chainScopePaths = [[ConnectSensorGen]]
            }
        , SDK.ChainProto
            { SDK.chainNode = [-2,0,1]
            , SDK.chainRole = SDK.SessionChain
            , SDK.chainTerminal = "TemperatureSample"
            , SDK.chainEntry = GetTemperatureSampleGen
            , SDK.chainReaches = [GetTemperatureSampleGen, NextReadingGen, ConnectSensorGen]
            , SDK.chainDrives = ["TemperatureSample"]
            , SDK.chainReads = []
            , SDK.chainScopePaths = [[ConnectSensorGen]]
            }
        ]
    , SDK.protoChainDefinitions =
        [ SDK.ChainDefinition
            { SDK.definitionKind = SDK.OriginChain
            , SDK.definitionEffect = "SensorLink"
            , SDK.definitionEntry = ConnectSensorGen
            , SDK.definitionReaches = [ConnectSensorGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.ContextChain
            , SDK.definitionEffect = "TemperatureFeed"
            , SDK.definitionEntry = NextReadingGen
            , SDK.definitionReaches = [NextReadingGen, ConnectSensorGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.ContextChain
            , SDK.definitionEffect = "TemperatureParser"
            , SDK.definitionEntry = GetTemperatureSampleGen
            , SDK.definitionReaches = [GetTemperatureSampleGen, NextReadingGen, ConnectSensorGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.ContextChain
            , SDK.definitionEffect = "TemperatureParser"
            , SDK.definitionEntry = ReadTemperatureSampleGen
            , SDK.definitionReaches = [ReadTemperatureSampleGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.ContextChain
            , SDK.definitionEffect = "Heartbeat"
            , SDK.definitionEntry = GetBeatGen
            , SDK.definitionReaches = [GetBeatGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.ContextChain
            , SDK.definitionEffect = "Heartbeat"
            , SDK.definitionEntry = ReadBeatGen
            , SDK.definitionReaches = [ReadBeatGen, GetBeatGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.OriginChain
            , SDK.definitionEffect = "Announce"
            , SDK.definitionEntry = AnnounceGen
            , SDK.definitionReaches = [AnnounceGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.OriginChain
            , SDK.definitionEffect = "ShowTemperature"
            , SDK.definitionEntry = ShowTemperatureGen
            , SDK.definitionReaches = [ShowTemperatureGen, ReadTemperatureSampleGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.OriginChain
            , SDK.definitionEffect = "CheckTrend"
            , SDK.definitionEntry = CheckTrendGen
            , SDK.definitionReaches = [CheckTrendGen, ReadTemperatureSampleGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.OriginChain
            , SDK.definitionEffect = "ReportHeartbeat"
            , SDK.definitionEntry = ReportHeartbeatGen
            , SDK.definitionReaches = [ReportHeartbeatGen, ReadBeatGen, GetBeatGen]
            }
        ]
    , SDK.protoGraph =
        SDK.EffectGraph
          { SDK.graphMethods =
              [ SDK.MethodDefinition (AnnounceGen) (AnnounceGen) (SDK.HandlerMethod) (SDK.Empty)
              , SDK.MethodDefinition
                  (ShowTemperatureGen)
                  (ShowTemperatureGen)
                  (SDK.HandlerMethod)
                  (SDK.Call (ReadTemperatureSampleGen))
              , SDK.MethodDefinition
                  (ReadTemperatureSampleGen)
                  (GetTemperatureSampleGen)
                  (SDK.ContextRequire)
                  (SDK.Empty)
              , SDK.MethodDefinition
                  (CheckTrendGen)
                  (CheckTrendGen)
                  (SDK.HandlerMethod)
                  (SDK.Call (ReadTemperatureSampleGen))
              , SDK.MethodDefinition
                  (ReportHeartbeatGen)
                  (ReportHeartbeatGen)
                  (SDK.HandlerMethod)
                  (SDK.Call (ReadBeatGen))
              , SDK.MethodDefinition
                  (ReadBeatGen)
                  (GetBeatGen)
                  (SDK.ContextRequire)
                  (SDK.Choice ([SDK.Empty, SDK.Call (GetBeatGen)]))
              , SDK.MethodDefinition (GetBeatGen) (GetBeatGen) (SDK.ContextRequest) (SDK.Empty)
              , SDK.MethodDefinition
                  (NextReadingGen)
                  (NextReadingGen)
                  (SDK.StreamHandler)
                  (SDK.Call (ConnectSensorGen))
              , SDK.MethodDefinition (ConnectSensorGen) (ConnectSensorGen) (SDK.ScopeOpen) (SDK.Empty)
              , SDK.MethodDefinition
                  (GetTemperatureSampleGen)
                  (GetTemperatureSampleGen)
                  (SDK.ContextStream)
                  (SDK.Call (NextReadingGen))
              ]
          , SDK.graphRoots =
              [ AnnounceGen
              , ShowTemperatureGen
              , CheckTrendGen
              , ReportHeartbeatGen
              , NextReadingGen
              , GetTemperatureSampleGen
              , GetBeatGen
              ]
          , SDK.graphReferences =
              [ (ShowTemperatureGen, ReadTemperatureSampleGen)
              , (CheckTrendGen, ReadTemperatureSampleGen)
              , (ReportHeartbeatGen, ReadBeatGen)
              , (ReadBeatGen, GetBeatGen)
              , (NextReadingGen, ConnectSensorGen)
              , (GetTemperatureSampleGen, NextReadingGen)
              ]
          , SDK.graphScopes = [ConnectSensorGen]
          , SDK.graphScopePaths = [[], [ConnectSensorGen]]
          , SDK.graphRootPaths =
              [ (AnnounceGen, [[]])
              , (ShowTemperatureGen, [[]])
              , (CheckTrendGen, [[]])
              , (ReportHeartbeatGen, [[]])
              , (NextReadingGen, [[ConnectSensorGen]])
              , (GetTemperatureSampleGen, [[ConnectSensorGen]])
              , (GetBeatGen, [[]])
              ]
          , SDK.graphScopeOrder = []
          }
    , SDK.protoScopes =
        SDK.ScopeTree
          { SDK.scopeRoots = [ConnectSensorGen]
          , SDK.scopeNodes =
              [ SDK.ScopeNode
                  { SDK.scopeIdentity = ConnectSensorGen
                  , SDK.scopeParents = []
                  , SDK.scopeChildren = []
                  }
              ]
          , SDK.scopeLayers = [[ConnectSensorGen]]
          , SDK.scopePaths = [[], [ConnectSensorGen]]
          , SDK.scopeCandidates = []
          , SDK.scopeOpposed = []
          , SDK.scopeUndetermined = []
          }
    , SDK.protoScopeNames = [(ConnectSensorGen, "SensorLink")]
    , SDK.protoSources = []
    }
