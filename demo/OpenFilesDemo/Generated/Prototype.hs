{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE TypeApplications #-}

-- 自动生成；gen 编译出的静态结构，由 Program 交给 interpreter，运行前校验。
module OpenFilesDemo.Generated.Prototype (generatedPrototype) where

import qualified Framework.Generated as SDK
import qualified OpenFilesDemo.Types as AssetTypes
import OpenFilesDemo.Generated.Effects (MethodGen(..))

-- 生成时完成注册、方法、origin/ctx 链、资产来源、Workflow 和 scope 的统一分析。
-- NodeId 只在这份 AST 快照中有效；运行时校验后装配闭包。
generatedPrototype :: SDK.Prototype MethodGen
generatedPrototype =
  SDK.Prototype
    { SDK.protoRegistrations =
        [ SDK.EffectSpec
            { SDK.name = "FileLocations"
            , SDK.typing =
                SDK.Context (SDK.AssetDecl "FileNames" (SDK.typeRef @[[Char]])) (Just "listFiles") True False
            , SDK.input = "Root"
            , SDK.demands = []
            }
        , SDK.EffectSpec
            { SDK.name = "FileResources"
            , SDK.typing =
                SDK.Context
                  (SDK.AssetDecl "OpenedFiles" (SDK.typeRef @AssetTypes.FileHandles))
                  (Just "acquireFiles")
                  True
                  False
            , SDK.input = "Root"
            , SDK.demands = [SDK.Demand SDK.RequireAccess "FileNames"]
            }
        , SDK.EffectSpec
            { SDK.name = "FileSession"
            , SDK.typing = SDK.Scoped (Just "openFiles") (Just "closeFiles")
            , SDK.input = "Root"
            , SDK.demands =
                [SDK.Demand SDK.RequestAccess "OpenedFiles", SDK.Demand SDK.RequireAccess "OpenedFiles"]
            }
        , SDK.EffectSpec
            { SDK.name = "HoldFiles"
            , SDK.typing = SDK.Excu (Just "holdFiles")
            , SDK.input = "FileSession"
            , SDK.demands = [SDK.Demand SDK.RequestAccess "FileNames"]
            }
        , SDK.EffectSpec
            { SDK.name = "InspectFiles"
            , SDK.typing = SDK.Excu (Just "inspectFiles")
            , SDK.input = "HoldFiles"
            , SDK.demands = [SDK.Demand SDK.RequireAccess "OpenedFiles"]
            }
        , SDK.EffectSpec
            { SDK.name = "ReleaseFiles"
            , SDK.typing = SDK.Excu (Just "holdFiles")
            , SDK.input = "HoldFiles"
            , SDK.demands = []
            }
        , SDK.EffectSpec
            { SDK.name = "FinishInspection"
            , SDK.typing = SDK.Excu (Just "finishInspection")
            , SDK.input = "Root"
            , SDK.demands =
                [SDK.Demand SDK.RequestAccess "FileNames", SDK.Demand SDK.RequireAccess "FileNames"]
            }
        ]
    , SDK.protoEffects =
        [ (SDK.effectProto "FileLocations" SDK.ContextKind "Root")
            { SDK.effectMethods =
                [(SDK.ContextRequest, GetFileNamesGen), (SDK.ContextRequire, ReadFileNamesGen)]
            , SDK.effectProduces = Just "FileNames"
            }
        , (SDK.effectProto "FileResources" SDK.ContextKind "Root")
            { SDK.effectMethods =
                [(SDK.ContextRequest, GetOpenedFilesGen), (SDK.ContextRequire, ReadOpenedFilesGen)]
            , SDK.effectDemands = [SDK.ResolvedDemand SDK.RequireAccess "FileNames" "FileLocations"]
            , SDK.effectProduces = Just "OpenedFiles"
            , SDK.effectContextDependencies = ["FileLocations"]
            }
        , (SDK.effectProto "FileSession" SDK.ScopedKind "Root")
            { SDK.effectMethods = [(SDK.ScopeOpen, OpenFileSessionGen), (SDK.ScopeClose, CloseFileSessionGen)]
            , SDK.effectDemands =
                [ SDK.ResolvedDemand SDK.RequestAccess "OpenedFiles" "FileResources"
                , SDK.ResolvedDemand SDK.RequireAccess "OpenedFiles" "FileResources"
                ]
            , SDK.effectOpeningInputs = ["FileLocations"]
            , SDK.effectNearestScopes = ["FileSession"]
            , SDK.effectResource = Just "FileResources"
            , SDK.effectContextDependencies = ["FileLocations","FileResources"]
            }
        , (SDK.effectProto "HoldFiles" SDK.ExcuKind "FileSession")
            { SDK.effectMethods = [(SDK.HandlerMethod, RunHoldFilesGen)]
            , SDK.effectDemands = [SDK.ResolvedDemand SDK.RequestAccess "FileNames" "FileLocations"]
            , SDK.effectScopes = ["FileSession"]
            , SDK.effectInputChain = ["FileSession"]
            , SDK.effectScopeParents = ["FileSession"]
            , SDK.effectNearestScopes = ["FileSession"]
            , SDK.effectContextDependencies = ["FileLocations","FileResources"]
            }
        , (SDK.effectProto "InspectFiles" SDK.ExcuKind "HoldFiles")
            { SDK.effectMethods = [(SDK.HandlerMethod, RunInspectFilesGen)]
            , SDK.effectDemands = [SDK.ResolvedDemand SDK.RequireAccess "OpenedFiles" "FileResources"]
            , SDK.effectScopes = ["FileSession"]
            , SDK.effectInputChain = ["HoldFiles","FileSession"]
            , SDK.effectScopeParents = ["FileSession"]
            , SDK.effectNearestScopes = ["FileSession"]
            , SDK.effectContextDependencies = ["FileLocations","FileResources"]
            }
        , (SDK.effectProto "ReleaseFiles" SDK.ExcuKind "HoldFiles")
            { SDK.effectMethods = [(SDK.HandlerMethod, RunReleaseFilesGen)]
            , SDK.effectScopes = ["FileSession"]
            , SDK.effectInputChain = ["HoldFiles","FileSession"]
            , SDK.effectScopeParents = ["FileSession"]
            , SDK.effectNearestScopes = ["FileSession"]
            , SDK.effectContextDependencies = ["FileLocations","FileResources"]
            }
        , (SDK.effectProto "FinishInspection" SDK.ExcuKind "Root")
            { SDK.effectMethods = [(SDK.HandlerMethod, RunFinishInspectionGen)]
            , SDK.effectDemands =
                [ SDK.ResolvedDemand SDK.RequestAccess "FileNames" "FileLocations"
                , SDK.ResolvedDemand SDK.RequireAccess "FileNames" "FileLocations"
                ]
            , SDK.effectContextDependencies = ["FileLocations"]
            }
        ]
    , SDK.protoMethods =
        [ SDK.MethodDefinition GetFileNamesGen GetFileNamesGen SDK.ContextRequest SDK.Empty
        , SDK.MethodDefinition ReadFileNamesGen GetFileNamesGen SDK.ContextRequire SDK.Empty
        , SDK.MethodDefinition
            GetOpenedFilesGen
            GetOpenedFilesGen
            SDK.ContextRequest
            (SDK.Call ReadFileNamesGen)
        , SDK.MethodDefinition ReadOpenedFilesGen GetOpenedFilesGen SDK.ContextRequire SDK.Empty
        , SDK.MethodDefinition
            OpenFileSessionGen
            OpenFileSessionGen
            SDK.ScopeOpen
            (SDK.Sequence [SDK.Call GetOpenedFilesGen, SDK.Call ReadOpenedFilesGen])
        , SDK.MethodDefinition
            CloseFileSessionGen
            OpenFileSessionGen
            SDK.ScopeClose
            (SDK.Call ReadOpenedFilesGen)
        , SDK.MethodDefinition
            RunHoldFilesGen
            RunHoldFilesGen
            SDK.HandlerMethod
            (SDK.Sequence [SDK.Call GetFileNamesGen, SDK.Call OpenFileSessionGen])
        , SDK.MethodDefinition
            RunInspectFilesGen
            RunInspectFilesGen
            SDK.HandlerMethod
            (SDK.Sequence [SDK.Call RunHoldFilesGen, SDK.Call ReadOpenedFilesGen])
        , SDK.MethodDefinition
            RunReleaseFilesGen
            RunReleaseFilesGen
            SDK.HandlerMethod
            (SDK.Call RunHoldFilesGen)
        , SDK.MethodDefinition
            RunFinishInspectionGen
            RunFinishInspectionGen
            SDK.HandlerMethod
            (SDK.Sequence [SDK.Call GetFileNamesGen, SDK.Call ReadFileNamesGen])
        ]
    , SDK.protoWorkflow =
        SDK.ChainAt
          []
          [ SDK.NodeAt [0] "HoldFiles"
          , SDK.NodeAt [1] "InspectFiles"
          , SDK.NodeAt [2] "ReleaseFiles"
          , SDK.NodeAt [3] "FinishInspection"
          ]
    , SDK.protoSessions = []
    , SDK.protoChains =
        [ SDK.ChainProto
            { SDK.chainNode = [0]
            , SDK.chainRole = SDK.NodeChain
            , SDK.chainTerminal = "HoldFiles"
            , SDK.chainEntry = RunHoldFilesGen
            , SDK.chainReaches =
                [ RunHoldFilesGen
                , GetFileNamesGen
                , OpenFileSessionGen
                , GetOpenedFilesGen
                , ReadFileNamesGen
                , ReadOpenedFilesGen
                ]
            , SDK.chainDrives = ["FileNames"]
            , SDK.chainReads = []
            , SDK.chainScopePaths = [[OpenFileSessionGen]]
            }
        , SDK.ChainProto
            { SDK.chainNode = [1]
            , SDK.chainRole = SDK.NodeChain
            , SDK.chainTerminal = "InspectFiles"
            , SDK.chainEntry = RunInspectFilesGen
            , SDK.chainReaches =
                [ RunInspectFilesGen
                , RunHoldFilesGen
                , GetFileNamesGen
                , OpenFileSessionGen
                , GetOpenedFilesGen
                , ReadFileNamesGen
                , ReadOpenedFilesGen
                ]
            , SDK.chainDrives = ["FileNames"]
            , SDK.chainReads = []
            , SDK.chainScopePaths = [[OpenFileSessionGen]]
            }
        , SDK.ChainProto
            { SDK.chainNode = [2]
            , SDK.chainRole = SDK.NodeChain
            , SDK.chainTerminal = "ReleaseFiles"
            , SDK.chainEntry = RunReleaseFilesGen
            , SDK.chainReaches =
                [ RunReleaseFilesGen
                , RunHoldFilesGen
                , GetFileNamesGen
                , OpenFileSessionGen
                , GetOpenedFilesGen
                , ReadFileNamesGen
                , ReadOpenedFilesGen
                ]
            , SDK.chainDrives = ["FileNames"]
            , SDK.chainReads = []
            , SDK.chainScopePaths = [[OpenFileSessionGen]]
            }
        , SDK.ChainProto
            { SDK.chainNode = [3]
            , SDK.chainRole = SDK.NodeChain
            , SDK.chainTerminal = "FinishInspection"
            , SDK.chainEntry = RunFinishInspectionGen
            , SDK.chainReaches = [RunFinishInspectionGen, GetFileNamesGen, ReadFileNamesGen]
            , SDK.chainDrives = ["FileNames"]
            , SDK.chainReads = []
            , SDK.chainScopePaths = [[]]
            }
        ]
    , SDK.protoChainDefinitions =
        [ SDK.ChainDefinition
            { SDK.definitionKind = SDK.ContextChain
            , SDK.definitionEffect = "FileLocations"
            , SDK.definitionEntry = GetFileNamesGen
            , SDK.definitionReaches = [GetFileNamesGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.ContextChain
            , SDK.definitionEffect = "FileLocations"
            , SDK.definitionEntry = ReadFileNamesGen
            , SDK.definitionReaches = [ReadFileNamesGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.ContextChain
            , SDK.definitionEffect = "FileResources"
            , SDK.definitionEntry = GetOpenedFilesGen
            , SDK.definitionReaches = [GetOpenedFilesGen, ReadFileNamesGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.ContextChain
            , SDK.definitionEffect = "FileResources"
            , SDK.definitionEntry = ReadOpenedFilesGen
            , SDK.definitionReaches = [ReadOpenedFilesGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.OriginChain
            , SDK.definitionEffect = "FileSession"
            , SDK.definitionEntry = OpenFileSessionGen
            , SDK.definitionReaches =
                [OpenFileSessionGen, GetOpenedFilesGen, ReadFileNamesGen, ReadOpenedFilesGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.OriginChain
            , SDK.definitionEffect = "HoldFiles"
            , SDK.definitionEntry = RunHoldFilesGen
            , SDK.definitionReaches =
                [ RunHoldFilesGen
                , GetFileNamesGen
                , OpenFileSessionGen
                , GetOpenedFilesGen
                , ReadFileNamesGen
                , ReadOpenedFilesGen
                ]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.OriginChain
            , SDK.definitionEffect = "InspectFiles"
            , SDK.definitionEntry = RunInspectFilesGen
            , SDK.definitionReaches =
                [ RunInspectFilesGen
                , RunHoldFilesGen
                , GetFileNamesGen
                , OpenFileSessionGen
                , GetOpenedFilesGen
                , ReadFileNamesGen
                , ReadOpenedFilesGen
                ]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.OriginChain
            , SDK.definitionEffect = "ReleaseFiles"
            , SDK.definitionEntry = RunReleaseFilesGen
            , SDK.definitionReaches =
                [ RunReleaseFilesGen
                , RunHoldFilesGen
                , GetFileNamesGen
                , OpenFileSessionGen
                , GetOpenedFilesGen
                , ReadFileNamesGen
                , ReadOpenedFilesGen
                ]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.OriginChain
            , SDK.definitionEffect = "FinishInspection"
            , SDK.definitionEntry = RunFinishInspectionGen
            , SDK.definitionReaches = [RunFinishInspectionGen, GetFileNamesGen, ReadFileNamesGen]
            }
        ]
    , SDK.protoGraph =
        SDK.EffectGraph
          { SDK.graphMethods =
              [ SDK.MethodDefinition
                  RunHoldFilesGen
                  RunHoldFilesGen
                  SDK.HandlerMethod
                  (SDK.Sequence [SDK.Call GetFileNamesGen, SDK.Call OpenFileSessionGen])
              , SDK.MethodDefinition GetFileNamesGen GetFileNamesGen SDK.ContextRequest SDK.Empty
              , SDK.MethodDefinition
                  OpenFileSessionGen
                  OpenFileSessionGen
                  SDK.ScopeOpen
                  (SDK.Sequence [SDK.Call GetOpenedFilesGen, SDK.Call ReadOpenedFilesGen])
              , SDK.MethodDefinition
                  GetOpenedFilesGen
                  GetOpenedFilesGen
                  SDK.ContextRequest
                  (SDK.Call ReadFileNamesGen)
              , SDK.MethodDefinition ReadFileNamesGen GetFileNamesGen SDK.ContextRequire SDK.Empty
              , SDK.MethodDefinition ReadOpenedFilesGen GetOpenedFilesGen SDK.ContextRequire SDK.Empty
              , SDK.MethodDefinition
                  RunInspectFilesGen
                  RunInspectFilesGen
                  SDK.HandlerMethod
                  (SDK.Sequence [SDK.Call RunHoldFilesGen, SDK.Call ReadOpenedFilesGen])
              , SDK.MethodDefinition
                  RunReleaseFilesGen
                  RunReleaseFilesGen
                  SDK.HandlerMethod
                  (SDK.Call RunHoldFilesGen)
              , SDK.MethodDefinition
                  RunFinishInspectionGen
                  RunFinishInspectionGen
                  SDK.HandlerMethod
                  (SDK.Sequence [SDK.Call GetFileNamesGen, SDK.Call ReadFileNamesGen])
              ]
          , SDK.graphRoots =
              [RunHoldFilesGen, RunInspectFilesGen, RunReleaseFilesGen, RunFinishInspectionGen]
          , SDK.graphReferences =
              [ (RunHoldFilesGen, GetFileNamesGen)
              , (RunHoldFilesGen, OpenFileSessionGen)
              , (OpenFileSessionGen, GetOpenedFilesGen)
              , (OpenFileSessionGen, ReadOpenedFilesGen)
              , (GetOpenedFilesGen, ReadFileNamesGen)
              , (RunInspectFilesGen, RunHoldFilesGen)
              , (RunInspectFilesGen, ReadOpenedFilesGen)
              , (RunReleaseFilesGen, RunHoldFilesGen)
              , (RunFinishInspectionGen, GetFileNamesGen)
              , (RunFinishInspectionGen, ReadFileNamesGen)
              ]
          , SDK.graphScopes = [OpenFileSessionGen]
          , SDK.graphScopePaths = [[OpenFileSessionGen], []]
          , SDK.graphRootPaths =
              [ (RunHoldFilesGen, [[OpenFileSessionGen]])
              , (RunInspectFilesGen, [[OpenFileSessionGen]])
              , (RunReleaseFilesGen, [[OpenFileSessionGen]])
              , (RunFinishInspectionGen, [[]])
              ]
          , SDK.graphScopeOrder = []
          }
    , SDK.protoScopes =
        SDK.ScopeTree
          { SDK.scopeRoots = [OpenFileSessionGen]
          , SDK.scopeNodes =
              [ SDK.ScopeNode
                  { SDK.scopeIdentity = OpenFileSessionGen
                  , SDK.scopeParents = []
                  , SDK.scopeChildren = []
                  }
              ]
          , SDK.scopeLayers = [[OpenFileSessionGen]]
          , SDK.scopePaths = [[OpenFileSessionGen], []]
          , SDK.scopeCandidates = []
          , SDK.scopeOpposed = []
          , SDK.scopeUndetermined = []
          }
    , SDK.protoScopeNames = [(OpenFileSessionGen, "FileSession")]
    , SDK.protoSources = []
    , SDK.protoScopeOpenings =
        [ SDK.ScopeOpeningPlan
            { SDK.openingNode = [2]
            , SDK.openingScope = "FileSession"
            , SDK.openingSources = [("FileLocations", SDK.FromChains [[2]])]
            , SDK.openingKinds = [SDK.ExecutionMultiple]
            }
        , SDK.ScopeOpeningPlan
            { SDK.openingNode = [1]
            , SDK.openingScope = "FileSession"
            , SDK.openingSources = [("FileLocations", SDK.FromChains [[1]])]
            , SDK.openingKinds = [SDK.ExecutionMultiple]
            }
        , SDK.ScopeOpeningPlan
            { SDK.openingNode = [0]
            , SDK.openingScope = "FileSession"
            , SDK.openingSources = [("FileLocations", SDK.FromChains [[0]])]
            , SDK.openingKinds = [SDK.ExecutionMultiple]
            }
        ]
    , SDK.protoDriving =
        SDK.DrivingPlan
          { SDK.drivingNodes =
              [ SDK.NodeDrive [] [[0],[1],[2],[3]] [] Nothing [] [] []
              , SDK.NodeDrive [0] [[0]] [] Nothing [] [] []
              , SDK.NodeDrive [1] [[1]] [] Nothing [] [] []
              , SDK.NodeDrive [2] [[2]] [] Nothing [] [] []
              , SDK.NodeDrive [3] [[3]] [] Nothing [] [] []
              ]
          , SDK.drivingUnits = []
          , SDK.drivingSessions = []
          , SDK.drivingRootNodes = [[0],[1],[2],[3]]
          , SDK.drivingOutputSites = []
          , SDK.drivingRequests = [("FileLocations", GetFileNamesGen), ("FileResources", GetOpenedFilesGen)]
          , SDK.drivingMiddleware = []
          , SDK.drivingHooks = []
          }
    }
