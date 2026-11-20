{-# LANGUAGE DuplicateRecordFields #-}

-- 自动生成；gen 编译出的静态结构，由 Program 交给 interpreter，运行前校验。
module ScopeInstancesDemo.Generated.Prototype (generatedPrototype) where

import qualified Framework.Generated as SDK
import ScopeInstancesDemo.Generated.Effects (MethodGen(..))

-- 生成时完成注册、方法、origin/ctx 链、资产来源、Workflow 和 scope 的统一分析。
-- NodeId 只在这份 AST 快照中有效；运行时校验后装配闭包。
generatedPrototype :: SDK.Prototype MethodGen
generatedPrototype =
  SDK.Prototype
    { SDK.protoRegistrations =
        [ SDK.EffectSpec
            { SDK.name = "PrepareFiles"
            , SDK.typing = SDK.Excu (Just "prepareFiles")
            , SDK.input = "Root"
            , SDK.demands = []
            }
        , SDK.EffectSpec
            { SDK.name = "FileLocation"
            , SDK.typing =
                SDK.Context (SDK.AssetDecl "FileName" (SDK.TypeRef "[Char]")) (Just "selectedFile") True False
            , SDK.input = "Root"
            , SDK.demands = []
            }
        , SDK.EffectSpec
            { SDK.name = "FileResource"
            , SDK.typing =
                SDK.Context (SDK.AssetDecl "OpenedFile" (SDK.TypeRef "FileHandle")) (Just "acquireFile") True False
            , SDK.input = "Root"
            , SDK.demands = [SDK.Demand SDK.RequireAccess "FileName"]
            }
        , SDK.EffectSpec
            { SDK.name = "FileSession"
            , SDK.typing = SDK.Scoped (Just "openSelectedFile") (Just "closeSelectedFile")
            , SDK.input = "Root"
            , SDK.demands =
                [SDK.Demand SDK.RequestAccess "OpenedFile", SDK.Demand SDK.RequireAccess "OpenedFile"]
            }
        , SDK.EffectSpec
            { SDK.name = "UseFirst"
            , SDK.typing = SDK.Excu (Just "checkSelection")
            , SDK.input = "FileSession"
            , SDK.demands =
                [ SDK.Demand SDK.RequestAccess "FileName"
                , SDK.Demand SDK.RequireAccess "FileName"
                , SDK.Demand SDK.RequireAccess "OpenedFile"
                ]
            }
        , SDK.EffectSpec
            { SDK.name = "SelectSecond"
            , SDK.typing = SDK.Excu (Just "selectSecond")
            , SDK.input = "Root"
            , SDK.demands = []
            }
        , SDK.EffectSpec
            { SDK.name = "UseSecond"
            , SDK.typing = SDK.Excu (Just "checkSelection")
            , SDK.input = "FileSession"
            , SDK.demands =
                [ SDK.Demand SDK.RequestAccess "FileName"
                , SDK.Demand SDK.RequireAccess "FileName"
                , SDK.Demand SDK.RequireAccess "OpenedFile"
                ]
            }
        , SDK.EffectSpec
            { SDK.name = "SelectFirst"
            , SDK.typing = SDK.Excu (Just "selectFirst")
            , SDK.input = "Root"
            , SDK.demands = []
            }
        , SDK.EffectSpec
            { SDK.name = "ReopenFirst"
            , SDK.typing = SDK.Excu (Just "checkSelection")
            , SDK.input = "FileSession"
            , SDK.demands =
                [ SDK.Demand SDK.RequestAccess "FileName"
                , SDK.Demand SDK.RequireAccess "FileName"
                , SDK.Demand SDK.RequireAccess "OpenedFile"
                ]
            }
        , SDK.EffectSpec
            { SDK.name = "CheckJournal"
            , SDK.typing = SDK.Excu (Just "checkJournal")
            , SDK.input = "Root"
            , SDK.demands = []
            }
        ]
    , SDK.protoEffects =
        [ (SDK.effectProto "PrepareFiles" SDK.ExcuKind "Root")
            { SDK.effectMethods = [(SDK.HandlerMethod, RunPrepareFilesGen)]
            }
        , (SDK.effectProto "FileLocation" SDK.ContextKind "Root")
            { SDK.effectMethods =
                [(SDK.ContextRequest, GetFileNameGen), (SDK.ContextRequire, ReadFileNameGen)]
            , SDK.effectProduces = Just "FileName"
            }
        , (SDK.effectProto "FileResource" SDK.ContextKind "Root")
            { SDK.effectMethods =
                [(SDK.ContextRequest, GetOpenedFileGen), (SDK.ContextRequire, ReadOpenedFileGen)]
            , SDK.effectDemands = [SDK.ResolvedDemand SDK.RequireAccess "FileName" "FileLocation"]
            , SDK.effectProduces = Just "OpenedFile"
            , SDK.effectContextDependencies = ["FileLocation"]
            }
        , (SDK.effectProto "FileSession" SDK.ScopedKind "Root")
            { SDK.effectMethods = [(SDK.ScopeOpen, OpenFileSessionGen), (SDK.ScopeClose, CloseFileSessionGen)]
            , SDK.effectDemands =
                [ SDK.ResolvedDemand SDK.RequestAccess "OpenedFile" "FileResource"
                , SDK.ResolvedDemand SDK.RequireAccess "OpenedFile" "FileResource"
                ]
            , SDK.effectOpeningInputs = ["FileLocation"]
            , SDK.effectNearestScopes = ["FileSession"]
            , SDK.effectResource = Just "FileResource"
            , SDK.effectContextDependencies = ["FileLocation","FileResource"]
            }
        , (SDK.effectProto "UseFirst" SDK.ExcuKind "FileSession")
            { SDK.effectMethods = [(SDK.HandlerMethod, RunUseFirstGen)]
            , SDK.effectDemands =
                [ SDK.ResolvedDemand SDK.RequestAccess "FileName" "FileLocation"
                , SDK.ResolvedDemand SDK.RequireAccess "FileName" "FileLocation"
                , SDK.ResolvedDemand SDK.RequireAccess "OpenedFile" "FileResource"
                ]
            , SDK.effectScopes = ["FileSession"]
            , SDK.effectInputChain = ["FileSession"]
            , SDK.effectScopeParents = ["FileSession"]
            , SDK.effectNearestScopes = ["FileSession"]
            , SDK.effectContextDependencies = ["FileLocation","FileResource"]
            }
        , (SDK.effectProto "SelectSecond" SDK.ExcuKind "Root")
            { SDK.effectMethods = [(SDK.HandlerMethod, RunSelectSecondGen)]
            }
        , (SDK.effectProto "UseSecond" SDK.ExcuKind "FileSession")
            { SDK.effectMethods = [(SDK.HandlerMethod, RunUseSecondGen)]
            , SDK.effectDemands =
                [ SDK.ResolvedDemand SDK.RequestAccess "FileName" "FileLocation"
                , SDK.ResolvedDemand SDK.RequireAccess "FileName" "FileLocation"
                , SDK.ResolvedDemand SDK.RequireAccess "OpenedFile" "FileResource"
                ]
            , SDK.effectScopes = ["FileSession"]
            , SDK.effectInputChain = ["FileSession"]
            , SDK.effectScopeParents = ["FileSession"]
            , SDK.effectNearestScopes = ["FileSession"]
            , SDK.effectContextDependencies = ["FileLocation","FileResource"]
            }
        , (SDK.effectProto "SelectFirst" SDK.ExcuKind "Root")
            { SDK.effectMethods = [(SDK.HandlerMethod, RunSelectFirstGen)]
            }
        , (SDK.effectProto "ReopenFirst" SDK.ExcuKind "FileSession")
            { SDK.effectMethods = [(SDK.HandlerMethod, RunReopenFirstGen)]
            , SDK.effectDemands =
                [ SDK.ResolvedDemand SDK.RequestAccess "FileName" "FileLocation"
                , SDK.ResolvedDemand SDK.RequireAccess "FileName" "FileLocation"
                , SDK.ResolvedDemand SDK.RequireAccess "OpenedFile" "FileResource"
                ]
            , SDK.effectScopes = ["FileSession"]
            , SDK.effectInputChain = ["FileSession"]
            , SDK.effectScopeParents = ["FileSession"]
            , SDK.effectNearestScopes = ["FileSession"]
            , SDK.effectContextDependencies = ["FileLocation","FileResource"]
            }
        , (SDK.effectProto "CheckJournal" SDK.ExcuKind "Root")
            { SDK.effectMethods = [(SDK.HandlerMethod, RunCheckJournalGen)]
            }
        ]
    , SDK.protoMethods =
        [ SDK.MethodDefinition RunPrepareFilesGen RunPrepareFilesGen SDK.HandlerMethod SDK.Empty
        , SDK.MethodDefinition GetFileNameGen GetFileNameGen SDK.ContextRequest SDK.Empty
        , SDK.MethodDefinition ReadFileNameGen GetFileNameGen SDK.ContextRequire SDK.Empty
        , SDK.MethodDefinition GetOpenedFileGen GetOpenedFileGen SDK.ContextRequest (SDK.Call ReadFileNameGen)
        , SDK.MethodDefinition ReadOpenedFileGen GetOpenedFileGen SDK.ContextRequire SDK.Empty
        , SDK.MethodDefinition
            OpenFileSessionGen
            OpenFileSessionGen
            SDK.ScopeOpen
            (SDK.Sequence [SDK.Call GetOpenedFileGen, SDK.Call ReadOpenedFileGen])
        , SDK.MethodDefinition
            CloseFileSessionGen
            OpenFileSessionGen
            SDK.ScopeClose
            (SDK.Call ReadOpenedFileGen)
        , SDK.MethodDefinition
            RunUseFirstGen
            RunUseFirstGen
            SDK.HandlerMethod
            (
              SDK.Sequence
                [ SDK.Call GetFileNameGen
                , SDK.Call OpenFileSessionGen
                , SDK.Call ReadFileNameGen
                , SDK.Call ReadOpenedFileGen
                ]
            )
        , SDK.MethodDefinition RunSelectSecondGen RunSelectSecondGen SDK.HandlerMethod SDK.Empty
        , SDK.MethodDefinition
            RunUseSecondGen
            RunUseSecondGen
            SDK.HandlerMethod
            (
              SDK.Sequence
                [ SDK.Call GetFileNameGen
                , SDK.Call OpenFileSessionGen
                , SDK.Call ReadFileNameGen
                , SDK.Call ReadOpenedFileGen
                ]
            )
        , SDK.MethodDefinition RunSelectFirstGen RunSelectFirstGen SDK.HandlerMethod SDK.Empty
        , SDK.MethodDefinition
            RunReopenFirstGen
            RunReopenFirstGen
            SDK.HandlerMethod
            (
              SDK.Sequence
                [ SDK.Call GetFileNameGen
                , SDK.Call OpenFileSessionGen
                , SDK.Call ReadFileNameGen
                , SDK.Call ReadOpenedFileGen
                ]
            )
        , SDK.MethodDefinition RunCheckJournalGen RunCheckJournalGen SDK.HandlerMethod SDK.Empty
        ]
    , SDK.protoWorkflow =
        SDK.ChainedAt
          []
          [ SDK.ChainedAt
              [0]
              [ SDK.NodeAt [0,0] "PrepareFiles"
              ]
          , SDK.ChainedAt
              [1]
              [ SDK.NodeAt [1,0] "UseFirst"
              , SDK.NodeAt [1,1] "SelectSecond"
              , SDK.NodeAt [1,2] "UseSecond"
              , SDK.NodeAt [1,3] "SelectFirst"
              , SDK.NodeAt [1,4] "ReopenFirst"
              , SDK.NodeAt [1,5] "CheckJournal"
              ]
          ]
    , SDK.protoSessions = []
    , SDK.protoChains =
        [ SDK.ChainProto
            { SDK.chainNode = [0,0]
            , SDK.chainRole = SDK.NodeChain
            , SDK.chainTerminal = "PrepareFiles"
            , SDK.chainEntry = RunPrepareFilesGen
            , SDK.chainReaches = [RunPrepareFilesGen]
            , SDK.chainDrives = []
            , SDK.chainReads = []
            , SDK.chainScopePaths = [[]]
            }
        , SDK.ChainProto
            { SDK.chainNode = [1,0]
            , SDK.chainRole = SDK.NodeChain
            , SDK.chainTerminal = "UseFirst"
            , SDK.chainEntry = RunUseFirstGen
            , SDK.chainReaches =
                [ RunUseFirstGen
                , GetFileNameGen
                , OpenFileSessionGen
                , GetOpenedFileGen
                , ReadFileNameGen
                , ReadOpenedFileGen
                ]
            , SDK.chainDrives = ["FileName"]
            , SDK.chainReads = []
            , SDK.chainScopePaths = [[OpenFileSessionGen]]
            }
        , SDK.ChainProto
            { SDK.chainNode = [1,1]
            , SDK.chainRole = SDK.NodeChain
            , SDK.chainTerminal = "SelectSecond"
            , SDK.chainEntry = RunSelectSecondGen
            , SDK.chainReaches = [RunSelectSecondGen]
            , SDK.chainDrives = []
            , SDK.chainReads = []
            , SDK.chainScopePaths = [[]]
            }
        , SDK.ChainProto
            { SDK.chainNode = [1,2]
            , SDK.chainRole = SDK.NodeChain
            , SDK.chainTerminal = "UseSecond"
            , SDK.chainEntry = RunUseSecondGen
            , SDK.chainReaches =
                [ RunUseSecondGen
                , GetFileNameGen
                , OpenFileSessionGen
                , GetOpenedFileGen
                , ReadFileNameGen
                , ReadOpenedFileGen
                ]
            , SDK.chainDrives = ["FileName"]
            , SDK.chainReads = []
            , SDK.chainScopePaths = [[OpenFileSessionGen]]
            }
        , SDK.ChainProto
            { SDK.chainNode = [1,3]
            , SDK.chainRole = SDK.NodeChain
            , SDK.chainTerminal = "SelectFirst"
            , SDK.chainEntry = RunSelectFirstGen
            , SDK.chainReaches = [RunSelectFirstGen]
            , SDK.chainDrives = []
            , SDK.chainReads = []
            , SDK.chainScopePaths = [[]]
            }
        , SDK.ChainProto
            { SDK.chainNode = [1,4]
            , SDK.chainRole = SDK.NodeChain
            , SDK.chainTerminal = "ReopenFirst"
            , SDK.chainEntry = RunReopenFirstGen
            , SDK.chainReaches =
                [ RunReopenFirstGen
                , GetFileNameGen
                , OpenFileSessionGen
                , GetOpenedFileGen
                , ReadFileNameGen
                , ReadOpenedFileGen
                ]
            , SDK.chainDrives = ["FileName"]
            , SDK.chainReads = []
            , SDK.chainScopePaths = [[OpenFileSessionGen]]
            }
        , SDK.ChainProto
            { SDK.chainNode = [1,5]
            , SDK.chainRole = SDK.NodeChain
            , SDK.chainTerminal = "CheckJournal"
            , SDK.chainEntry = RunCheckJournalGen
            , SDK.chainReaches = [RunCheckJournalGen]
            , SDK.chainDrives = []
            , SDK.chainReads = []
            , SDK.chainScopePaths = [[]]
            }
        ]
    , SDK.protoChainDefinitions =
        [ SDK.ChainDefinition
            { SDK.definitionKind = SDK.OriginChain
            , SDK.definitionEffect = "PrepareFiles"
            , SDK.definitionEntry = RunPrepareFilesGen
            , SDK.definitionReaches = [RunPrepareFilesGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.ContextChain
            , SDK.definitionEffect = "FileLocation"
            , SDK.definitionEntry = GetFileNameGen
            , SDK.definitionReaches = [GetFileNameGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.ContextChain
            , SDK.definitionEffect = "FileLocation"
            , SDK.definitionEntry = ReadFileNameGen
            , SDK.definitionReaches = [ReadFileNameGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.ContextChain
            , SDK.definitionEffect = "FileResource"
            , SDK.definitionEntry = GetOpenedFileGen
            , SDK.definitionReaches = [GetOpenedFileGen, ReadFileNameGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.ContextChain
            , SDK.definitionEffect = "FileResource"
            , SDK.definitionEntry = ReadOpenedFileGen
            , SDK.definitionReaches = [ReadOpenedFileGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.OriginChain
            , SDK.definitionEffect = "FileSession"
            , SDK.definitionEntry = OpenFileSessionGen
            , SDK.definitionReaches =
                [OpenFileSessionGen, GetOpenedFileGen, ReadFileNameGen, ReadOpenedFileGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.OriginChain
            , SDK.definitionEffect = "UseFirst"
            , SDK.definitionEntry = RunUseFirstGen
            , SDK.definitionReaches =
                [ RunUseFirstGen
                , GetFileNameGen
                , OpenFileSessionGen
                , GetOpenedFileGen
                , ReadFileNameGen
                , ReadOpenedFileGen
                ]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.OriginChain
            , SDK.definitionEffect = "SelectSecond"
            , SDK.definitionEntry = RunSelectSecondGen
            , SDK.definitionReaches = [RunSelectSecondGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.OriginChain
            , SDK.definitionEffect = "UseSecond"
            , SDK.definitionEntry = RunUseSecondGen
            , SDK.definitionReaches =
                [ RunUseSecondGen
                , GetFileNameGen
                , OpenFileSessionGen
                , GetOpenedFileGen
                , ReadFileNameGen
                , ReadOpenedFileGen
                ]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.OriginChain
            , SDK.definitionEffect = "SelectFirst"
            , SDK.definitionEntry = RunSelectFirstGen
            , SDK.definitionReaches = [RunSelectFirstGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.OriginChain
            , SDK.definitionEffect = "ReopenFirst"
            , SDK.definitionEntry = RunReopenFirstGen
            , SDK.definitionReaches =
                [ RunReopenFirstGen
                , GetFileNameGen
                , OpenFileSessionGen
                , GetOpenedFileGen
                , ReadFileNameGen
                , ReadOpenedFileGen
                ]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.OriginChain
            , SDK.definitionEffect = "CheckJournal"
            , SDK.definitionEntry = RunCheckJournalGen
            , SDK.definitionReaches = [RunCheckJournalGen]
            }
        ]
    , SDK.protoGraph =
        SDK.EffectGraph
          { SDK.graphMethods =
              [ SDK.MethodDefinition RunPrepareFilesGen RunPrepareFilesGen SDK.HandlerMethod SDK.Empty
              , SDK.MethodDefinition
                  RunUseFirstGen
                  RunUseFirstGen
                  SDK.HandlerMethod
                  (
                    SDK.Sequence
                      [ SDK.Call GetFileNameGen
                      , SDK.Call OpenFileSessionGen
                      , SDK.Call ReadFileNameGen
                      , SDK.Call ReadOpenedFileGen
                      ]
                  )
              , SDK.MethodDefinition GetFileNameGen GetFileNameGen SDK.ContextRequest SDK.Empty
              , SDK.MethodDefinition
                  OpenFileSessionGen
                  OpenFileSessionGen
                  SDK.ScopeOpen
                  (SDK.Sequence [SDK.Call GetOpenedFileGen, SDK.Call ReadOpenedFileGen])
              , SDK.MethodDefinition GetOpenedFileGen GetOpenedFileGen SDK.ContextRequest (SDK.Call ReadFileNameGen)
              , SDK.MethodDefinition ReadFileNameGen GetFileNameGen SDK.ContextRequire SDK.Empty
              , SDK.MethodDefinition ReadOpenedFileGen GetOpenedFileGen SDK.ContextRequire SDK.Empty
              , SDK.MethodDefinition RunSelectSecondGen RunSelectSecondGen SDK.HandlerMethod SDK.Empty
              , SDK.MethodDefinition
                  RunUseSecondGen
                  RunUseSecondGen
                  SDK.HandlerMethod
                  (
                    SDK.Sequence
                      [ SDK.Call GetFileNameGen
                      , SDK.Call OpenFileSessionGen
                      , SDK.Call ReadFileNameGen
                      , SDK.Call ReadOpenedFileGen
                      ]
                  )
              , SDK.MethodDefinition RunSelectFirstGen RunSelectFirstGen SDK.HandlerMethod SDK.Empty
              , SDK.MethodDefinition
                  RunReopenFirstGen
                  RunReopenFirstGen
                  SDK.HandlerMethod
                  (
                    SDK.Sequence
                      [ SDK.Call GetFileNameGen
                      , SDK.Call OpenFileSessionGen
                      , SDK.Call ReadFileNameGen
                      , SDK.Call ReadOpenedFileGen
                      ]
                  )
              , SDK.MethodDefinition RunCheckJournalGen RunCheckJournalGen SDK.HandlerMethod SDK.Empty
              ]
          , SDK.graphRoots =
              [ RunPrepareFilesGen
              , RunUseFirstGen
              , RunSelectSecondGen
              , RunUseSecondGen
              , RunSelectFirstGen
              , RunReopenFirstGen
              , RunCheckJournalGen
              ]
          , SDK.graphReferences =
              [ (RunUseFirstGen, GetFileNameGen)
              , (RunUseFirstGen, OpenFileSessionGen)
              , (RunUseFirstGen, ReadFileNameGen)
              , (RunUseFirstGen, ReadOpenedFileGen)
              , (OpenFileSessionGen, GetOpenedFileGen)
              , (OpenFileSessionGen, ReadOpenedFileGen)
              , (GetOpenedFileGen, ReadFileNameGen)
              , (RunUseSecondGen, GetFileNameGen)
              , (RunUseSecondGen, OpenFileSessionGen)
              , (RunUseSecondGen, ReadFileNameGen)
              , (RunUseSecondGen, ReadOpenedFileGen)
              , (RunReopenFirstGen, GetFileNameGen)
              , (RunReopenFirstGen, OpenFileSessionGen)
              , (RunReopenFirstGen, ReadFileNameGen)
              , (RunReopenFirstGen, ReadOpenedFileGen)
              ]
          , SDK.graphScopes = [OpenFileSessionGen]
          , SDK.graphScopePaths = [[], [OpenFileSessionGen]]
          , SDK.graphRootPaths =
              [ (RunPrepareFilesGen, [[]])
              , (RunUseFirstGen, [[OpenFileSessionGen]])
              , (RunSelectSecondGen, [[]])
              , (RunUseSecondGen, [[OpenFileSessionGen]])
              , (RunSelectFirstGen, [[]])
              , (RunReopenFirstGen, [[OpenFileSessionGen]])
              , (RunCheckJournalGen, [[]])
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
          , SDK.scopePaths = [[], [OpenFileSessionGen]]
          , SDK.scopeCandidates = []
          , SDK.scopeOpposed = []
          , SDK.scopeUndetermined = []
          }
    , SDK.protoScopeNames = [(OpenFileSessionGen, "FileSession")]
    , SDK.protoSources = []
    , SDK.protoScopeOpenings =
        [ SDK.ScopeOpeningPlan
            { SDK.openingNode = [1,4]
            , SDK.openingScope = "FileSession"
            , SDK.openingSources = [("FileLocation", SDK.FromChains [[1,4]])]
            , SDK.openingKinds = [SDK.ExecutionMultiple]
            }
        , SDK.ScopeOpeningPlan
            { SDK.openingNode = [1,2]
            , SDK.openingScope = "FileSession"
            , SDK.openingSources = [("FileLocation", SDK.FromChains [[1,2]])]
            , SDK.openingKinds = [SDK.ExecutionMultiple]
            }
        , SDK.ScopeOpeningPlan
            { SDK.openingNode = [1,0]
            , SDK.openingScope = "FileSession"
            , SDK.openingSources = [("FileLocation", SDK.FromChains [[1,0]])]
            , SDK.openingKinds = [SDK.ExecutionMultiple]
            }
        ]
    , SDK.protoDriving =
        SDK.DrivingPlan
          { SDK.drivingNodes =
              [ SDK.NodeDrive [] [[0,0],[1,0],[1,1],[1,2],[1,3],[1,4],[1,5]] [] Nothing [] [] []
              , SDK.NodeDrive [0] [[0,0]] [] Nothing [] [] []
              , SDK.NodeDrive [0,0] [[0,0]] [] Nothing [] [] []
              , SDK.NodeDrive [1] [[1,0],[1,1],[1,2],[1,3],[1,4],[1,5]] [] Nothing [] [] []
              , SDK.NodeDrive [1,0] [[1,0]] [] Nothing [] [] []
              , SDK.NodeDrive [1,1] [[1,1]] [] Nothing [] [] []
              , SDK.NodeDrive [1,2] [[1,2]] [] Nothing [] [] []
              , SDK.NodeDrive [1,3] [[1,3]] [] Nothing [] [] []
              , SDK.NodeDrive [1,4] [[1,4]] [] Nothing [] [] []
              , SDK.NodeDrive [1,5] [[1,5]] [] Nothing [] [] []
              ]
          , SDK.drivingUnits = []
          , SDK.drivingSessions = []
          , SDK.drivingRootNodes = [[0,0],[1,0],[1,1],[1,2],[1,3],[1,4],[1,5]]
          , SDK.drivingOutputSites = []
          , SDK.drivingRequests = [("FileLocation", GetFileNameGen), ("FileResource", GetOpenedFileGen)]
          , SDK.drivingMiddleware = []
          , SDK.drivingHooks = []
          }
    }
