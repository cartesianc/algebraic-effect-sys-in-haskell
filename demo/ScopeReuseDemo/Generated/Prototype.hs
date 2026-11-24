{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE TypeApplications #-}

-- 自动生成；gen 编译出的静态结构，由 Program 交给 interpreter，运行前校验。
module ScopeReuseDemo.Generated.Prototype (generatedPrototype) where

import qualified Framework.Generated as SDK
import qualified ScopeReuseDemo.Types as AssetTypes
import ScopeReuseDemo.Generated.Effects (MethodGen(..))

-- 生成时完成注册、方法、origin/ctx 链、资产来源、Workflow 和 scope 的统一分析。
-- NodeId 只在这份 AST 快照中有效；运行时校验后装配闭包。
generatedPrototype :: SDK.Prototype MethodGen
generatedPrototype =
  SDK.Prototype
    { SDK.protoRegistrations =
        [ SDK.EffectSpec
            { SDK.name = "FileLocations"
            , SDK.typing =
                SDK.Context
                  (SDK.AssetDecl "FilePaths" (SDK.typeRef @AssetTypes.SharedPaths))
                  (Just "sharedPaths")
                  True
                  False
            , SDK.input = "Root"
            , SDK.demands = []
            }
        , SDK.EffectSpec
            { SDK.name = "PrepareProbe"
            , SDK.typing = SDK.Excu (Just "prepareProbe")
            , SDK.input = "Root"
            , SDK.demands =
                [SDK.Demand SDK.RequestAccess "FilePaths", SDK.Demand SDK.RequireAccess "FilePaths"]
            }
        , SDK.EffectSpec
            { SDK.name = "FileResource"
            , SDK.typing =
                SDK.Context
                  (SDK.AssetDecl "OpenedFile" (SDK.typeRef @AssetTypes.SharedFile))
                  (Just "acquireFile")
                  True
                  False
            , SDK.input = "Root"
            , SDK.demands = [SDK.Demand SDK.RequireAccess "FilePaths"]
            }
        , SDK.EffectSpec
            { SDK.name = "SharedFileScope"
            , SDK.typing = SDK.Scoped (Just "openSharedFile") (Just "closeSharedFile")
            , SDK.input = "Root"
            , SDK.demands =
                [SDK.Demand SDK.RequestAccess "OpenedFile", SDK.Demand SDK.RequireAccess "OpenedFile"]
            }
        , SDK.EffectSpec
            { SDK.name = "WriteFirst"
            , SDK.typing = SDK.Excu (Just "writeFirst")
            , SDK.input = "SharedFileScope"
            , SDK.demands = [SDK.Demand SDK.RequireAccess "OpenedFile"]
            }
        , SDK.EffectSpec
            { SDK.name = "WriteSecond"
            , SDK.typing = SDK.Excu (Just "writeSecond")
            , SDK.input = "SharedFileScope"
            , SDK.demands = [SDK.Demand SDK.RequireAccess "OpenedFile"]
            }
        , SDK.EffectSpec
            { SDK.name = "WriteThird"
            , SDK.typing = SDK.Excu (Just "writeThird")
            , SDK.input = "SharedFileScope"
            , SDK.demands = [SDK.Demand SDK.RequireAccess "OpenedFile"]
            }
        , SDK.EffectSpec
            { SDK.name = "VerifyReuse"
            , SDK.typing = SDK.Excu (Just "verifyReuse")
            , SDK.input = "Root"
            , SDK.demands =
                [SDK.Demand SDK.RequestAccess "FilePaths", SDK.Demand SDK.RequireAccess "FilePaths"]
            }
        ]
    , SDK.protoEffects =
        [ (SDK.effectProto "FileLocations" SDK.ContextKind "Root")
            { SDK.effectMethods =
                [(SDK.ContextRequest, GetFilePathsGen), (SDK.ContextRequire, ReadFilePathsGen)]
            , SDK.effectProduces = Just "FilePaths"
            }
        , (SDK.effectProto "PrepareProbe" SDK.ExcuKind "Root")
            { SDK.effectMethods = [(SDK.HandlerMethod, RunPrepareProbeGen)]
            , SDK.effectDemands =
                [ SDK.ResolvedDemand SDK.RequestAccess "FilePaths" "FileLocations"
                , SDK.ResolvedDemand SDK.RequireAccess "FilePaths" "FileLocations"
                ]
            , SDK.effectContextDependencies = ["FileLocations"]
            }
        , (SDK.effectProto "FileResource" SDK.ContextKind "Root")
            { SDK.effectMethods =
                [(SDK.ContextRequest, GetOpenedFileGen), (SDK.ContextRequire, ReadOpenedFileGen)]
            , SDK.effectDemands = [SDK.ResolvedDemand SDK.RequireAccess "FilePaths" "FileLocations"]
            , SDK.effectProduces = Just "OpenedFile"
            , SDK.effectContextDependencies = ["FileLocations"]
            }
        , (SDK.effectProto "SharedFileScope" SDK.ScopedKind "Root")
            { SDK.effectMethods =
                [(SDK.ScopeOpen, OpenSharedFileScopeGen), (SDK.ScopeClose, CloseSharedFileScopeGen)]
            , SDK.effectDemands =
                [ SDK.ResolvedDemand SDK.RequestAccess "OpenedFile" "FileResource"
                , SDK.ResolvedDemand SDK.RequireAccess "OpenedFile" "FileResource"
                ]
            , SDK.effectOpeningInputs = ["FileLocations"]
            , SDK.effectNearestScopes = ["SharedFileScope"]
            , SDK.effectResource = Just "FileResource"
            , SDK.effectContextDependencies = ["FileLocations","FileResource"]
            }
        , (SDK.effectProto "WriteFirst" SDK.ExcuKind "SharedFileScope")
            { SDK.effectMethods = [(SDK.HandlerMethod, RunWriteFirstGen)]
            , SDK.effectDemands = [SDK.ResolvedDemand SDK.RequireAccess "OpenedFile" "FileResource"]
            , SDK.effectScopes = ["SharedFileScope"]
            , SDK.effectInputChain = ["SharedFileScope"]
            , SDK.effectScopeParents = ["SharedFileScope"]
            , SDK.effectNearestScopes = ["SharedFileScope"]
            , SDK.effectContextDependencies = ["FileLocations","FileResource"]
            }
        , (SDK.effectProto "WriteSecond" SDK.ExcuKind "SharedFileScope")
            { SDK.effectMethods = [(SDK.HandlerMethod, RunWriteSecondGen)]
            , SDK.effectDemands = [SDK.ResolvedDemand SDK.RequireAccess "OpenedFile" "FileResource"]
            , SDK.effectScopes = ["SharedFileScope"]
            , SDK.effectInputChain = ["SharedFileScope"]
            , SDK.effectScopeParents = ["SharedFileScope"]
            , SDK.effectNearestScopes = ["SharedFileScope"]
            , SDK.effectContextDependencies = ["FileLocations","FileResource"]
            }
        , (SDK.effectProto "WriteThird" SDK.ExcuKind "SharedFileScope")
            { SDK.effectMethods = [(SDK.HandlerMethod, RunWriteThirdGen)]
            , SDK.effectDemands = [SDK.ResolvedDemand SDK.RequireAccess "OpenedFile" "FileResource"]
            , SDK.effectScopes = ["SharedFileScope"]
            , SDK.effectInputChain = ["SharedFileScope"]
            , SDK.effectScopeParents = ["SharedFileScope"]
            , SDK.effectNearestScopes = ["SharedFileScope"]
            , SDK.effectContextDependencies = ["FileLocations","FileResource"]
            }
        , (SDK.effectProto "VerifyReuse" SDK.ExcuKind "Root")
            { SDK.effectMethods = [(SDK.HandlerMethod, RunVerifyReuseGen)]
            , SDK.effectDemands =
                [ SDK.ResolvedDemand SDK.RequestAccess "FilePaths" "FileLocations"
                , SDK.ResolvedDemand SDK.RequireAccess "FilePaths" "FileLocations"
                ]
            , SDK.effectContextDependencies = ["FileLocations"]
            }
        ]
    , SDK.protoMethods =
        [ SDK.MethodDefinition GetFilePathsGen GetFilePathsGen SDK.ContextRequest SDK.Empty
        , SDK.MethodDefinition ReadFilePathsGen GetFilePathsGen SDK.ContextRequire SDK.Empty
        , SDK.MethodDefinition
            RunPrepareProbeGen
            RunPrepareProbeGen
            SDK.HandlerMethod
            (SDK.Sequence [SDK.Call SDK.Invoke GetFilePathsGen, SDK.Call SDK.ReadCurrent ReadFilePathsGen])
        , SDK.MethodDefinition
            GetOpenedFileGen
            GetOpenedFileGen
            SDK.ContextRequest
            (SDK.Call SDK.ReadCurrent ReadFilePathsGen)
        , SDK.MethodDefinition ReadOpenedFileGen GetOpenedFileGen SDK.ContextRequire SDK.Empty
        , SDK.MethodDefinition
            OpenSharedFileScopeGen
            OpenSharedFileScopeGen
            SDK.ScopeOpen
            (SDK.Sequence [SDK.Call SDK.Invoke GetOpenedFileGen, SDK.Call SDK.ReadCurrent ReadOpenedFileGen])
        , SDK.MethodDefinition
            CloseSharedFileScopeGen
            OpenSharedFileScopeGen
            SDK.ScopeClose
            (SDK.Call SDK.ReadCurrent ReadOpenedFileGen)
        , SDK.MethodDefinition
            RunWriteFirstGen
            RunWriteFirstGen
            SDK.HandlerMethod
            (
              SDK.Sequence
                [SDK.Call SDK.Invoke OpenSharedFileScopeGen, SDK.Call SDK.ReadCurrent ReadOpenedFileGen]
            )
        , SDK.MethodDefinition
            RunWriteSecondGen
            RunWriteSecondGen
            SDK.HandlerMethod
            (
              SDK.Sequence
                [SDK.Call SDK.Invoke OpenSharedFileScopeGen, SDK.Call SDK.ReadCurrent ReadOpenedFileGen]
            )
        , SDK.MethodDefinition
            RunWriteThirdGen
            RunWriteThirdGen
            SDK.HandlerMethod
            (
              SDK.Sequence
                [SDK.Call SDK.Invoke OpenSharedFileScopeGen, SDK.Call SDK.ReadCurrent ReadOpenedFileGen]
            )
        , SDK.MethodDefinition
            RunVerifyReuseGen
            RunVerifyReuseGen
            SDK.HandlerMethod
            (SDK.Sequence [SDK.Call SDK.Invoke GetFilePathsGen, SDK.Call SDK.ReadCurrent ReadFilePathsGen])
        ]
    , SDK.protoWorkflow =
        SDK.ChainAt
          []
          [ SDK.NodeAt [0] "PrepareProbe"
          , SDK.ParallelAt
              [1]
              [ SDK.NodeAt [1,0] "WriteFirst"
              , SDK.NodeAt [1,1] "WriteSecond"
              , SDK.NodeAt [1,2] "WriteThird"
              ]
          , SDK.NodeAt [2] "VerifyReuse"
          ]
    , SDK.protoSessions = []
    , SDK.protoChains =
        [ SDK.ChainProto
            { SDK.chainNode = [0]
            , SDK.chainRole = SDK.NodeChain
            , SDK.chainTerminal = "PrepareProbe"
            , SDK.chainEntry = RunPrepareProbeGen
            , SDK.chainReaches = [RunPrepareProbeGen, GetFilePathsGen, ReadFilePathsGen]
            , SDK.chainDrives = ["FilePaths"]
            , SDK.chainReads = []
            , SDK.chainScopePaths = [[]]
            }
        , SDK.ChainProto
            { SDK.chainNode = [1,0]
            , SDK.chainRole = SDK.NodeChain
            , SDK.chainTerminal = "WriteFirst"
            , SDK.chainEntry = RunWriteFirstGen
            , SDK.chainReaches =
                [RunWriteFirstGen, OpenSharedFileScopeGen, GetOpenedFileGen, ReadFilePathsGen, ReadOpenedFileGen]
            , SDK.chainDrives = []
            , SDK.chainReads = ["FilePaths"]
            , SDK.chainScopePaths = [[OpenSharedFileScopeGen]]
            }
        , SDK.ChainProto
            { SDK.chainNode = [1,1]
            , SDK.chainRole = SDK.NodeChain
            , SDK.chainTerminal = "WriteSecond"
            , SDK.chainEntry = RunWriteSecondGen
            , SDK.chainReaches =
                [RunWriteSecondGen, OpenSharedFileScopeGen, GetOpenedFileGen, ReadFilePathsGen, ReadOpenedFileGen]
            , SDK.chainDrives = []
            , SDK.chainReads = ["FilePaths"]
            , SDK.chainScopePaths = [[OpenSharedFileScopeGen]]
            }
        , SDK.ChainProto
            { SDK.chainNode = [1,2]
            , SDK.chainRole = SDK.NodeChain
            , SDK.chainTerminal = "WriteThird"
            , SDK.chainEntry = RunWriteThirdGen
            , SDK.chainReaches =
                [RunWriteThirdGen, OpenSharedFileScopeGen, GetOpenedFileGen, ReadFilePathsGen, ReadOpenedFileGen]
            , SDK.chainDrives = []
            , SDK.chainReads = ["FilePaths"]
            , SDK.chainScopePaths = [[OpenSharedFileScopeGen]]
            }
        , SDK.ChainProto
            { SDK.chainNode = [2]
            , SDK.chainRole = SDK.NodeChain
            , SDK.chainTerminal = "VerifyReuse"
            , SDK.chainEntry = RunVerifyReuseGen
            , SDK.chainReaches = [RunVerifyReuseGen, GetFilePathsGen, ReadFilePathsGen]
            , SDK.chainDrives = ["FilePaths"]
            , SDK.chainReads = []
            , SDK.chainScopePaths = [[]]
            }
        ]
    , SDK.protoChainDefinitions =
        [ SDK.ChainDefinition
            { SDK.definitionKind = SDK.ContextChain
            , SDK.definitionEffect = "FileLocations"
            , SDK.definitionEntry = GetFilePathsGen
            , SDK.definitionReaches = [GetFilePathsGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.ContextChain
            , SDK.definitionEffect = "FileLocations"
            , SDK.definitionEntry = ReadFilePathsGen
            , SDK.definitionReaches = [ReadFilePathsGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.OriginChain
            , SDK.definitionEffect = "PrepareProbe"
            , SDK.definitionEntry = RunPrepareProbeGen
            , SDK.definitionReaches = [RunPrepareProbeGen, GetFilePathsGen, ReadFilePathsGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.ContextChain
            , SDK.definitionEffect = "FileResource"
            , SDK.definitionEntry = GetOpenedFileGen
            , SDK.definitionReaches = [GetOpenedFileGen, ReadFilePathsGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.ContextChain
            , SDK.definitionEffect = "FileResource"
            , SDK.definitionEntry = ReadOpenedFileGen
            , SDK.definitionReaches = [ReadOpenedFileGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.OriginChain
            , SDK.definitionEffect = "SharedFileScope"
            , SDK.definitionEntry = OpenSharedFileScopeGen
            , SDK.definitionReaches =
                [OpenSharedFileScopeGen, GetOpenedFileGen, ReadFilePathsGen, ReadOpenedFileGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.OriginChain
            , SDK.definitionEffect = "WriteFirst"
            , SDK.definitionEntry = RunWriteFirstGen
            , SDK.definitionReaches =
                [RunWriteFirstGen, OpenSharedFileScopeGen, GetOpenedFileGen, ReadFilePathsGen, ReadOpenedFileGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.OriginChain
            , SDK.definitionEffect = "WriteSecond"
            , SDK.definitionEntry = RunWriteSecondGen
            , SDK.definitionReaches =
                [RunWriteSecondGen, OpenSharedFileScopeGen, GetOpenedFileGen, ReadFilePathsGen, ReadOpenedFileGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.OriginChain
            , SDK.definitionEffect = "WriteThird"
            , SDK.definitionEntry = RunWriteThirdGen
            , SDK.definitionReaches =
                [RunWriteThirdGen, OpenSharedFileScopeGen, GetOpenedFileGen, ReadFilePathsGen, ReadOpenedFileGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.OriginChain
            , SDK.definitionEffect = "VerifyReuse"
            , SDK.definitionEntry = RunVerifyReuseGen
            , SDK.definitionReaches = [RunVerifyReuseGen, GetFilePathsGen, ReadFilePathsGen]
            }
        ]
    , SDK.protoGraph =
        SDK.EffectGraph
          { SDK.graphMethods =
              [ SDK.MethodDefinition
                  RunPrepareProbeGen
                  RunPrepareProbeGen
                  SDK.HandlerMethod
                  (SDK.Sequence [SDK.Call SDK.Invoke GetFilePathsGen, SDK.Call SDK.ReadCurrent ReadFilePathsGen])
              , SDK.MethodDefinition GetFilePathsGen GetFilePathsGen SDK.ContextRequest SDK.Empty
              , SDK.MethodDefinition ReadFilePathsGen GetFilePathsGen SDK.ContextRequire SDK.Empty
              , SDK.MethodDefinition
                  RunWriteFirstGen
                  RunWriteFirstGen
                  SDK.HandlerMethod
                  (
                    SDK.Sequence
                      [SDK.Call SDK.Invoke OpenSharedFileScopeGen, SDK.Call SDK.ReadCurrent ReadOpenedFileGen]
                  )
              , SDK.MethodDefinition
                  OpenSharedFileScopeGen
                  OpenSharedFileScopeGen
                  SDK.ScopeOpen
                  (SDK.Sequence [SDK.Call SDK.Invoke GetOpenedFileGen, SDK.Call SDK.ReadCurrent ReadOpenedFileGen])
              , SDK.MethodDefinition
                  GetOpenedFileGen
                  GetOpenedFileGen
                  SDK.ContextRequest
                  (SDK.Call SDK.ReadCurrent ReadFilePathsGen)
              , SDK.MethodDefinition ReadOpenedFileGen GetOpenedFileGen SDK.ContextRequire SDK.Empty
              , SDK.MethodDefinition
                  RunWriteSecondGen
                  RunWriteSecondGen
                  SDK.HandlerMethod
                  (
                    SDK.Sequence
                      [SDK.Call SDK.Invoke OpenSharedFileScopeGen, SDK.Call SDK.ReadCurrent ReadOpenedFileGen]
                  )
              , SDK.MethodDefinition
                  RunWriteThirdGen
                  RunWriteThirdGen
                  SDK.HandlerMethod
                  (
                    SDK.Sequence
                      [SDK.Call SDK.Invoke OpenSharedFileScopeGen, SDK.Call SDK.ReadCurrent ReadOpenedFileGen]
                  )
              , SDK.MethodDefinition
                  RunVerifyReuseGen
                  RunVerifyReuseGen
                  SDK.HandlerMethod
                  (SDK.Sequence [SDK.Call SDK.Invoke GetFilePathsGen, SDK.Call SDK.ReadCurrent ReadFilePathsGen])
              ]
          , SDK.graphRoots =
              [RunPrepareProbeGen, RunWriteFirstGen, RunWriteSecondGen, RunWriteThirdGen, RunVerifyReuseGen]
          , SDK.graphReferences =
              [ (RunPrepareProbeGen, GetFilePathsGen)
              , (RunPrepareProbeGen, ReadFilePathsGen)
              , (RunWriteFirstGen, OpenSharedFileScopeGen)
              , (RunWriteFirstGen, ReadOpenedFileGen)
              , (OpenSharedFileScopeGen, GetOpenedFileGen)
              , (OpenSharedFileScopeGen, ReadOpenedFileGen)
              , (GetOpenedFileGen, ReadFilePathsGen)
              , (RunWriteSecondGen, OpenSharedFileScopeGen)
              , (RunWriteSecondGen, ReadOpenedFileGen)
              , (RunWriteThirdGen, OpenSharedFileScopeGen)
              , (RunWriteThirdGen, ReadOpenedFileGen)
              , (RunVerifyReuseGen, GetFilePathsGen)
              , (RunVerifyReuseGen, ReadFilePathsGen)
              ]
          , SDK.graphScopes = [OpenSharedFileScopeGen]
          , SDK.graphScopePaths = [[], [OpenSharedFileScopeGen]]
          , SDK.graphRootPaths =
              [ (RunPrepareProbeGen, [[]])
              , (RunWriteFirstGen, [[OpenSharedFileScopeGen]])
              , (RunWriteSecondGen, [[OpenSharedFileScopeGen]])
              , (RunWriteThirdGen, [[OpenSharedFileScopeGen]])
              , (RunVerifyReuseGen, [[]])
              ]
          , SDK.graphScopeOrder = []
          }
    , SDK.protoScopes =
        SDK.ScopeTree
          { SDK.scopeRoots = [OpenSharedFileScopeGen]
          , SDK.scopeNodes =
              [ SDK.ScopeNode
                  { SDK.scopeIdentity = OpenSharedFileScopeGen
                  , SDK.scopeParents = []
                  , SDK.scopeChildren = []
                  }
              ]
          , SDK.scopeLayers = [[OpenSharedFileScopeGen]]
          , SDK.scopePaths = [[], [OpenSharedFileScopeGen]]
          , SDK.scopeCandidates = []
          , SDK.scopeOpposed = []
          , SDK.scopeUndetermined = []
          }
    , SDK.protoScopeNames = [(OpenSharedFileScopeGen, "SharedFileScope")]
    , SDK.protoSources =
        [ (SDK.ReadPoint [1,2] "FilePaths", SDK.FromChains [[0], [2]])
        , (SDK.ReadPoint [1,1] "FilePaths", SDK.FromChains [[0], [2]])
        , (SDK.ReadPoint [1,0] "FilePaths", SDK.FromChains [[0], [2]])
        ]
    , SDK.protoScopeOpenings =
        [ SDK.ScopeOpeningPlan
            { SDK.openingNode = [1,2]
            , SDK.openingScope = "SharedFileScope"
            , SDK.openingSources = [("FileLocations", SDK.FromChains [[0], [2]])]
            , SDK.openingKinds = [SDK.ProductionSingleton]
            }
        , SDK.ScopeOpeningPlan
            { SDK.openingNode = [1,1]
            , SDK.openingScope = "SharedFileScope"
            , SDK.openingSources = [("FileLocations", SDK.FromChains [[0], [2]])]
            , SDK.openingKinds = [SDK.ProductionSingleton]
            }
        , SDK.ScopeOpeningPlan
            { SDK.openingNode = [1,0]
            , SDK.openingScope = "SharedFileScope"
            , SDK.openingSources = [("FileLocations", SDK.FromChains [[0], [2]])]
            , SDK.openingKinds = [SDK.ProductionSingleton]
            }
        ]
    , SDK.protoDriving =
        SDK.DrivingPlan
          { SDK.drivingNodes =
              [ SDK.NodeDrive [] [[0],[1,0],[1,1],[1,2],[2]] [] Nothing [] [] []
              , SDK.NodeDrive [0] [[0]] [] Nothing [] [] []
              , SDK.NodeDrive [1] [[1,0],[1,1],[1,2]] [] Nothing [] [] []
              , SDK.NodeDrive [1,0] [[1,0]] [] Nothing [] [] [[2]]
              , SDK.NodeDrive [1,1] [[1,1]] [] Nothing [] [] [[2]]
              , SDK.NodeDrive [1,2] [[1,2]] [] Nothing [] [] [[2]]
              , SDK.NodeDrive [2] [[2]] [] Nothing [] [] []
              ]
          , SDK.drivingUnits = []
          , SDK.drivingSessions = []
          , SDK.drivingRootNodes = [[0],[1,0],[1,1],[1,2],[2]]
          , SDK.drivingOutputSites = []
          , SDK.drivingRequests = [("FileLocations", GetFilePathsGen), ("FileResource", GetOpenedFileGen)]
          , SDK.drivingMiddleware = []
          , SDK.drivingHooks = []
          }
    }
