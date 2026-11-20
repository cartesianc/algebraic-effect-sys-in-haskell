{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE TypeApplications #-}

-- 自动生成；gen 编译出的静态结构，由 Program 交给 interpreter，运行前校验。
module FileDemo.Generated.Prototype (generatedPrototype) where

import qualified Framework.Generated as SDK
import qualified FileDemo.Types as AssetTypes
import FileDemo.Generated.Effects (MethodGen(..))

-- 生成时完成注册、方法、origin/ctx 链、资产来源、Workflow 和 scope 的统一分析。
-- NodeId 只在这份 AST 快照中有效；运行时校验后装配闭包。
generatedPrototype :: SDK.Prototype MethodGen
generatedPrototype =
  SDK.Prototype
    { SDK.protoRegistrations =
        [ SDK.EffectSpec
            { SDK.name = "LocateFile"
            , SDK.typing = SDK.Excu (Just "locateFile")
            , SDK.input = "Root"
            , SDK.demands = []
            }
        , SDK.EffectSpec
            { SDK.name = "ValidateFileName"
            , SDK.typing = SDK.Pure (Just "validateFileName")
            , SDK.input = "LocateFile"
            , SDK.demands = []
            }
        , SDK.EffectSpec
            { SDK.name = "FileLocation"
            , SDK.typing =
                SDK.Context (SDK.AssetDecl "FileName" (SDK.typeRef @[Char])) (Just "parseFileName") True False
            , SDK.input = "ValidateFileName"
            , SDK.demands = []
            }
        , SDK.EffectSpec
            { SDK.name = "FileResource"
            , SDK.typing =
                SDK.Context
                  (SDK.AssetDecl "OpenedFile" (SDK.typeRef @AssetTypes.FileHandle))
                  (Just "acquireFile")
                  True
                  False
            , SDK.input = "Root"
            , SDK.demands = [SDK.Demand SDK.RequestAccess "FileName", SDK.Demand SDK.RequireAccess "FileName"]
            }
        , SDK.EffectSpec
            { SDK.name = "FileSession"
            , SDK.typing = SDK.Scoped (Just "openSession") (Just "closeSession")
            , SDK.input = "Root"
            , SDK.demands =
                [SDK.Demand SDK.RequestAccess "OpenedFile", SDK.Demand SDK.RequireAccess "OpenedFile"]
            }
        , SDK.EffectSpec
            { SDK.name = "FileRecovery"
            , SDK.typing =
                SDK.Error
                  (Just "detectFileSession")
                  (Just "resolveFileSession")
                  [SDK.RaisedBy "readFileContent", SDK.RaisedBy "writeFirstLine", SDK.RaisedBy "appendLine"]
            , SDK.input = "FileSession"
            , SDK.demands = [SDK.Demand SDK.RequireAccess "OpenedFile"]
            }
        , SDK.EffectSpec
            { SDK.name = "ReadFile"
            , SDK.typing = SDK.Excu (Just "readFileContent")
            , SDK.input = "FileSession"
            , SDK.demands = [SDK.Demand SDK.RequireAccess "OpenedFile"]
            }
        , SDK.EffectSpec
            { SDK.name = "BlankText"
            , SDK.typing =
                SDK.Context
                  (SDK.AssetDecl "FileBlank" (SDK.typeRef @AssetTypes.EmptyText))
                  (Just "parseBlankText")
                  True
                  False
            , SDK.input = "ReadFile"
            , SDK.demands = []
            }
        , SDK.EffectSpec
            { SDK.name = "FilledText"
            , SDK.typing =
                SDK.Context
                  (SDK.AssetDecl "FileWritten" (SDK.typeRef @AssetTypes.WrittenText))
                  (Just "parseWrittenText")
                  True
                  False
            , SDK.input = "ReadFile"
            , SDK.demands = []
            }
        , SDK.EffectSpec
            { SDK.name = "WriteFirstLine"
            , SDK.typing = SDK.Excu (Just "writeFirstLine")
            , SDK.input = "FileSession"
            , SDK.demands =
                [SDK.Demand SDK.RequireAccess "FileBlank", SDK.Demand SDK.RequireAccess "OpenedFile"]
            }
        , SDK.EffectSpec
            { SDK.name = "AppendLine"
            , SDK.typing = SDK.Excu (Just "appendLine")
            , SDK.input = "FileSession"
            , SDK.demands =
                [SDK.Demand SDK.RequireAccess "FileWritten", SDK.Demand SDK.RequireAccess "OpenedFile"]
            }
        ]
    , SDK.protoEffects =
        [ (SDK.effectProto "LocateFile" SDK.ExcuKind "Root")
            { SDK.effectMethods = [(SDK.HandlerMethod, RunLocateFileGen)]
            }
        , (SDK.effectProto "ValidateFileName" SDK.PureKind "LocateFile")
            { SDK.effectMethods = [(SDK.HandlerMethod, RunValidateFileNameGen)]
            , SDK.effectInputChain = ["LocateFile"]
            }
        , (SDK.effectProto "FileLocation" SDK.ContextKind "ValidateFileName")
            { SDK.effectMethods =
                [(SDK.ContextRequest, GetFileNameGen), (SDK.ContextRequire, ReadFileNameGen)]
            , SDK.effectProduces = Just "FileName"
            , SDK.effectAnchor = Just "LocateFile"
            , SDK.effectInputChain = ["ValidateFileName","LocateFile"]
            }
        , (SDK.effectProto "FileResource" SDK.ContextKind "Root")
            { SDK.effectMethods =
                [(SDK.ContextRequest, GetOpenedFileGen), (SDK.ContextRequire, ReadOpenedFileGen)]
            , SDK.effectDemands =
                [ SDK.ResolvedDemand SDK.RequestAccess "FileName" "FileLocation"
                , SDK.ResolvedDemand SDK.RequireAccess "FileName" "FileLocation"
                ]
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
        , (SDK.effectProto "FileRecovery" SDK.ErrorKind "FileSession")
            { SDK.effectMethods =
                [(SDK.ErrorDetect, DetectFileRecoveryGen), (SDK.ErrorResolve, ResolveFileRecoveryGen)]
            , SDK.effectDemands = [SDK.ResolvedDemand SDK.RequireAccess "OpenedFile" "FileResource"]
            , SDK.effectScopes = ["FileSession"]
            , SDK.effectErrorScope = Just "FileSession"
            , SDK.effectInputChain = ["FileSession"]
            , SDK.effectScopeParents = ["FileSession"]
            , SDK.effectNearestScopes = ["FileSession"]
            , SDK.effectContextDependencies = ["FileLocation","FileResource"]
            }
        , (SDK.effectProto "ReadFile" SDK.ExcuKind "FileSession")
            { SDK.effectMethods = [(SDK.HandlerMethod, RunReadFileGen)]
            , SDK.effectDemands = [SDK.ResolvedDemand SDK.RequireAccess "OpenedFile" "FileResource"]
            , SDK.effectScopes = ["FileSession"]
            , SDK.effectInputChain = ["FileSession"]
            , SDK.effectScopeParents = ["FileSession"]
            , SDK.effectNearestScopes = ["FileSession"]
            , SDK.effectContextDependencies = ["FileLocation","FileResource"]
            }
        , (SDK.effectProto "BlankText" SDK.ContextKind "ReadFile")
            { SDK.effectMethods =
                [(SDK.ContextRequest, GetFileBlankGen), (SDK.ContextRequire, ReadFileBlankGen)]
            , SDK.effectProduces = Just "FileBlank"
            , SDK.effectAnchor = Just "ReadFile"
            , SDK.effectScopes = ["FileSession"]
            , SDK.effectInputChain = ["ReadFile","FileSession"]
            , SDK.effectScopeParents = ["FileSession"]
            , SDK.effectNearestScopes = ["FileSession"]
            , SDK.effectContextDependencies = ["FileLocation","FileResource"]
            }
        , (SDK.effectProto "FilledText" SDK.ContextKind "ReadFile")
            { SDK.effectMethods =
                [(SDK.ContextRequest, GetFileWrittenGen), (SDK.ContextRequire, ReadFileWrittenGen)]
            , SDK.effectProduces = Just "FileWritten"
            , SDK.effectAnchor = Just "ReadFile"
            , SDK.effectScopes = ["FileSession"]
            , SDK.effectInputChain = ["ReadFile","FileSession"]
            , SDK.effectScopeParents = ["FileSession"]
            , SDK.effectNearestScopes = ["FileSession"]
            , SDK.effectContextDependencies = ["FileLocation","FileResource"]
            }
        , (SDK.effectProto "WriteFirstLine" SDK.ExcuKind "FileSession")
            { SDK.effectMethods = [(SDK.HandlerMethod, RunWriteFirstLineGen)]
            , SDK.effectDemands =
                [ SDK.ResolvedDemand SDK.RequireAccess "FileBlank" "BlankText"
                , SDK.ResolvedDemand SDK.RequireAccess "OpenedFile" "FileResource"
                ]
            , SDK.effectScopes = ["FileSession"]
            , SDK.effectInputChain = ["FileSession"]
            , SDK.effectScopeParents = ["FileSession"]
            , SDK.effectNearestScopes = ["FileSession"]
            , SDK.effectContextDependencies = ["FileLocation","FileResource","BlankText"]
            }
        , (SDK.effectProto "AppendLine" SDK.ExcuKind "FileSession")
            { SDK.effectMethods = [(SDK.HandlerMethod, RunAppendLineGen)]
            , SDK.effectDemands =
                [ SDK.ResolvedDemand SDK.RequireAccess "FileWritten" "FilledText"
                , SDK.ResolvedDemand SDK.RequireAccess "OpenedFile" "FileResource"
                ]
            , SDK.effectScopes = ["FileSession"]
            , SDK.effectInputChain = ["FileSession"]
            , SDK.effectScopeParents = ["FileSession"]
            , SDK.effectNearestScopes = ["FileSession"]
            , SDK.effectContextDependencies = ["FileLocation","FileResource","FilledText"]
            }
        ]
    , SDK.protoMethods =
        [ SDK.MethodDefinition
            RunLocateFileGen
            RunLocateFileGen
            SDK.HandlerMethod
            (SDK.Sequence [SDK.Empty, SDK.Choice [SDK.Empty, SDK.Sequence [SDK.Empty]]])
        , SDK.MethodDefinition
            RunValidateFileNameGen
            RunValidateFileNameGen
            SDK.HandlerMethod
            (SDK.Call RunLocateFileGen)
        , SDK.MethodDefinition
            GetFileNameGen
            GetFileNameGen
            SDK.ContextRequest
            (SDK.Call RunValidateFileNameGen)
        , SDK.MethodDefinition ReadFileNameGen GetFileNameGen SDK.ContextRequire SDK.Empty
        , SDK.MethodDefinition
            GetOpenedFileGen
            GetOpenedFileGen
            SDK.ContextRequest
            (SDK.Sequence [SDK.Call GetFileNameGen, SDK.Call ReadFileNameGen])
        , SDK.MethodDefinition ReadOpenedFileGen GetOpenedFileGen SDK.ContextRequire SDK.Empty
        , SDK.MethodDefinition OpenFileSessionGen OpenFileSessionGen SDK.ScopeOpen (SDK.Call GetOpenedFileGen)
        , SDK.MethodDefinition
            CloseFileSessionGen
            OpenFileSessionGen
            SDK.ScopeClose
            (SDK.Call ReadOpenedFileGen)
        , SDK.MethodDefinition
            DetectFileRecoveryGen
            DetectFileRecoveryGen
            SDK.ErrorDetect
            (SDK.Call ReadOpenedFileGen)
        , SDK.MethodDefinition ResolveFileRecoveryGen DetectFileRecoveryGen SDK.ErrorResolve SDK.Empty
        , SDK.MethodDefinition
            RunReadFileGen
            RunReadFileGen
            SDK.HandlerMethod
            (
              SDK.Sequence
                [ SDK.Sequence [SDK.Call OpenFileSessionGen, SDK.Call ReadOpenedFileGen]
                , SDK.Choice [SDK.Empty, SDK.Sequence [SDK.Empty, SDK.Empty]]
                ]
            )
        , SDK.MethodDefinition GetFileBlankGen GetFileBlankGen SDK.ContextRequest (SDK.Call RunReadFileGen)
        , SDK.MethodDefinition ReadFileBlankGen GetFileBlankGen SDK.ContextRequire SDK.Empty
        , SDK.MethodDefinition
            GetFileWrittenGen
            GetFileWrittenGen
            SDK.ContextRequest
            (SDK.Call RunReadFileGen)
        , SDK.MethodDefinition ReadFileWrittenGen GetFileWrittenGen SDK.ContextRequire SDK.Empty
        , SDK.MethodDefinition
            RunWriteFirstLineGen
            RunWriteFirstLineGen
            SDK.HandlerMethod
            (SDK.Sequence [SDK.Call OpenFileSessionGen, SDK.Call ReadOpenedFileGen])
        , SDK.MethodDefinition
            RunAppendLineGen
            RunAppendLineGen
            SDK.HandlerMethod
            (SDK.Sequence [SDK.Call OpenFileSessionGen, SDK.Call ReadFileWrittenGen, SDK.Call ReadOpenedFileGen])
        ]
    , SDK.protoWorkflow =
        SDK.AlternativeAt
          []
          (
            SDK.AlternativeProto
              { SDK.alternativeSource = "ReadFile"
              , SDK.alternativeSelector = [-1]
              , SDK.alternativeCases = [([0],"BlankText"),([1],"FilledText")]
              }
          )
          [ SDK.NodeAt [0] "WriteFirstLine"
          , SDK.NodeAt [1] "AppendLine"
          ]
    , SDK.protoSessions = []
    , SDK.protoChains =
        [ SDK.ChainProto
            { SDK.chainNode = [0]
            , SDK.chainRole = SDK.NodeChain
            , SDK.chainTerminal = "WriteFirstLine"
            , SDK.chainEntry = RunWriteFirstLineGen
            , SDK.chainReaches =
                [ RunWriteFirstLineGen
                , OpenFileSessionGen
                , GetOpenedFileGen
                , GetFileNameGen
                , RunValidateFileNameGen
                , RunLocateFileGen
                , ReadFileNameGen
                , ReadOpenedFileGen
                ]
            , SDK.chainDrives = ["FileName"]
            , SDK.chainReads = []
            , SDK.chainScopePaths = [[OpenFileSessionGen]]
            }
        , SDK.ChainProto
            { SDK.chainNode = [1]
            , SDK.chainRole = SDK.NodeChain
            , SDK.chainTerminal = "AppendLine"
            , SDK.chainEntry = RunAppendLineGen
            , SDK.chainReaches =
                [ RunAppendLineGen
                , OpenFileSessionGen
                , GetOpenedFileGen
                , GetFileNameGen
                , RunValidateFileNameGen
                , RunLocateFileGen
                , ReadFileNameGen
                , ReadFileWrittenGen
                , ReadOpenedFileGen
                ]
            , SDK.chainDrives = ["FileName"]
            , SDK.chainReads = ["FileWritten"]
            , SDK.chainScopePaths = [[OpenFileSessionGen]]
            }
        , SDK.ChainProto
            { SDK.chainNode = [-1]
            , SDK.chainRole = SDK.SelectorChain
            , SDK.chainTerminal = "ReadFile"
            , SDK.chainEntry = RunReadFileGen
            , SDK.chainReaches =
                [ RunReadFileGen
                , OpenFileSessionGen
                , GetOpenedFileGen
                , GetFileNameGen
                , RunValidateFileNameGen
                , RunLocateFileGen
                , ReadFileNameGen
                , ReadOpenedFileGen
                , GetFileBlankGen
                , GetFileWrittenGen
                ]
            , SDK.chainDrives = ["FileBlank","FileName","FileWritten"]
            , SDK.chainReads = ["FileBlank","FileWritten"]
            , SDK.chainScopePaths = [[OpenFileSessionGen]]
            }
        ]
    , SDK.protoChainDefinitions =
        [ SDK.ChainDefinition
            { SDK.definitionKind = SDK.OriginChain
            , SDK.definitionEffect = "LocateFile"
            , SDK.definitionEntry = RunLocateFileGen
            , SDK.definitionReaches = [RunLocateFileGen, GetFileNameGen, RunValidateFileNameGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.OriginChain
            , SDK.definitionEffect = "ValidateFileName"
            , SDK.definitionEntry = RunValidateFileNameGen
            , SDK.definitionReaches = [RunValidateFileNameGen, RunLocateFileGen, GetFileNameGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.ContextChain
            , SDK.definitionEffect = "FileLocation"
            , SDK.definitionEntry = GetFileNameGen
            , SDK.definitionReaches = [GetFileNameGen, RunValidateFileNameGen, RunLocateFileGen]
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
            , SDK.definitionReaches =
                [GetOpenedFileGen, GetFileNameGen, RunValidateFileNameGen, RunLocateFileGen, ReadFileNameGen]
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
                [ OpenFileSessionGen
                , GetOpenedFileGen
                , GetFileNameGen
                , RunValidateFileNameGen
                , RunLocateFileGen
                , ReadFileNameGen
                ]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.OriginChain
            , SDK.definitionEffect = "ReadFile"
            , SDK.definitionEntry = RunReadFileGen
            , SDK.definitionReaches =
                [ RunReadFileGen
                , OpenFileSessionGen
                , GetOpenedFileGen
                , GetFileNameGen
                , RunValidateFileNameGen
                , RunLocateFileGen
                , ReadFileNameGen
                , ReadOpenedFileGen
                , GetFileBlankGen
                , GetFileWrittenGen
                ]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.ContextChain
            , SDK.definitionEffect = "BlankText"
            , SDK.definitionEntry = GetFileBlankGen
            , SDK.definitionReaches =
                [ GetFileBlankGen
                , RunReadFileGen
                , OpenFileSessionGen
                , GetOpenedFileGen
                , GetFileNameGen
                , RunValidateFileNameGen
                , RunLocateFileGen
                , ReadFileNameGen
                , ReadOpenedFileGen
                , GetFileWrittenGen
                ]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.ContextChain
            , SDK.definitionEffect = "BlankText"
            , SDK.definitionEntry = ReadFileBlankGen
            , SDK.definitionReaches = [ReadFileBlankGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.ContextChain
            , SDK.definitionEffect = "FilledText"
            , SDK.definitionEntry = GetFileWrittenGen
            , SDK.definitionReaches =
                [ GetFileWrittenGen
                , RunReadFileGen
                , OpenFileSessionGen
                , GetOpenedFileGen
                , GetFileNameGen
                , RunValidateFileNameGen
                , RunLocateFileGen
                , ReadFileNameGen
                , ReadOpenedFileGen
                , GetFileBlankGen
                ]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.ContextChain
            , SDK.definitionEffect = "FilledText"
            , SDK.definitionEntry = ReadFileWrittenGen
            , SDK.definitionReaches = [ReadFileWrittenGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.OriginChain
            , SDK.definitionEffect = "WriteFirstLine"
            , SDK.definitionEntry = RunWriteFirstLineGen
            , SDK.definitionReaches =
                [ RunWriteFirstLineGen
                , OpenFileSessionGen
                , GetOpenedFileGen
                , GetFileNameGen
                , RunValidateFileNameGen
                , RunLocateFileGen
                , ReadFileNameGen
                , ReadOpenedFileGen
                ]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.OriginChain
            , SDK.definitionEffect = "AppendLine"
            , SDK.definitionEntry = RunAppendLineGen
            , SDK.definitionReaches =
                [ RunAppendLineGen
                , OpenFileSessionGen
                , GetOpenedFileGen
                , GetFileNameGen
                , RunValidateFileNameGen
                , RunLocateFileGen
                , ReadFileNameGen
                , ReadFileWrittenGen
                , ReadOpenedFileGen
                ]
            }
        ]
    , SDK.protoGraph =
        SDK.EffectGraph
          { SDK.graphMethods =
              [ SDK.MethodDefinition
                  RunWriteFirstLineGen
                  RunWriteFirstLineGen
                  SDK.HandlerMethod
                  (SDK.Sequence [SDK.Call OpenFileSessionGen, SDK.Call ReadOpenedFileGen])
              , SDK.MethodDefinition OpenFileSessionGen OpenFileSessionGen SDK.ScopeOpen (SDK.Call GetOpenedFileGen)
              , SDK.MethodDefinition
                  GetOpenedFileGen
                  GetOpenedFileGen
                  SDK.ContextRequest
                  (SDK.Sequence [SDK.Call GetFileNameGen, SDK.Call ReadFileNameGen])
              , SDK.MethodDefinition
                  GetFileNameGen
                  GetFileNameGen
                  SDK.ContextRequest
                  (SDK.Call RunValidateFileNameGen)
              , SDK.MethodDefinition
                  RunValidateFileNameGen
                  RunValidateFileNameGen
                  SDK.HandlerMethod
                  (SDK.Call RunLocateFileGen)
              , SDK.MethodDefinition
                  RunLocateFileGen
                  RunLocateFileGen
                  SDK.HandlerMethod
                  (SDK.Sequence [SDK.Empty, SDK.Choice [SDK.Empty, SDK.Sequence [SDK.Empty]]])
              , SDK.MethodDefinition ReadFileNameGen GetFileNameGen SDK.ContextRequire SDK.Empty
              , SDK.MethodDefinition ReadOpenedFileGen GetOpenedFileGen SDK.ContextRequire SDK.Empty
              , SDK.MethodDefinition
                  RunAppendLineGen
                  RunAppendLineGen
                  SDK.HandlerMethod
                  (SDK.Sequence [SDK.Call OpenFileSessionGen, SDK.Call ReadFileWrittenGen, SDK.Call ReadOpenedFileGen])
              , SDK.MethodDefinition ReadFileWrittenGen GetFileWrittenGen SDK.ContextRequire SDK.Empty
              , SDK.MethodDefinition
                  RunReadFileGen
                  RunReadFileGen
                  SDK.HandlerMethod
                  (
                    SDK.Sequence
                      [ SDK.Sequence [SDK.Call OpenFileSessionGen, SDK.Call ReadOpenedFileGen]
                      , SDK.Choice [SDK.Empty, SDK.Sequence [SDK.Empty, SDK.Empty]]
                      ]
                  )
              ]
          , SDK.graphRoots = [RunWriteFirstLineGen, RunAppendLineGen, RunReadFileGen]
          , SDK.graphReferences =
              [ (RunWriteFirstLineGen, OpenFileSessionGen)
              , (RunWriteFirstLineGen, ReadOpenedFileGen)
              , (OpenFileSessionGen, GetOpenedFileGen)
              , (GetOpenedFileGen, GetFileNameGen)
              , (GetOpenedFileGen, ReadFileNameGen)
              , (GetFileNameGen, RunValidateFileNameGen)
              , (RunValidateFileNameGen, RunLocateFileGen)
              , (RunAppendLineGen, OpenFileSessionGen)
              , (RunAppendLineGen, ReadFileWrittenGen)
              , (RunAppendLineGen, ReadOpenedFileGen)
              , (RunReadFileGen, OpenFileSessionGen)
              , (RunReadFileGen, ReadOpenedFileGen)
              ]
          , SDK.graphScopes = [OpenFileSessionGen]
          , SDK.graphScopePaths = [[OpenFileSessionGen]]
          , SDK.graphRootPaths =
              [ (RunWriteFirstLineGen, [[OpenFileSessionGen]])
              , (RunAppendLineGen, [[OpenFileSessionGen]])
              , (RunReadFileGen, [[OpenFileSessionGen]])
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
          , SDK.scopePaths = [[OpenFileSessionGen]]
          , SDK.scopeCandidates = []
          , SDK.scopeOpposed = []
          , SDK.scopeUndetermined = []
          }
    , SDK.protoScopeNames = [(OpenFileSessionGen, "FileSession")]
    , SDK.protoSources =
        [ (SDK.ReadPoint [1] "FileWritten", SDK.FromChains [[-1]])
        , (SDK.ReadPoint [-1] "FileBlank", SDK.FromOwnChain)
        , (SDK.ReadPoint [-1] "FileWritten", SDK.FromOwnChain)
        ]
    , SDK.protoScopeOpenings =
        [ SDK.ScopeOpeningPlan
            { SDK.openingNode = [1]
            , SDK.openingScope = "FileSession"
            , SDK.openingSources = [("FileLocation", SDK.FromChains [[1]])]
            , SDK.openingKinds = [SDK.ExecutionMultiple]
            }
        , SDK.ScopeOpeningPlan
            { SDK.openingNode = [0]
            , SDK.openingScope = "FileSession"
            , SDK.openingSources = [("FileLocation", SDK.FromChains [[0]])]
            , SDK.openingKinds = [SDK.ExecutionMultiple]
            }
        , SDK.ScopeOpeningPlan
            { SDK.openingNode = [-1]
            , SDK.openingScope = "FileSession"
            , SDK.openingSources = [("FileLocation", SDK.FromChains [[-1]])]
            , SDK.openingKinds = [SDK.ExecutionMultiple]
            }
        ]
    , SDK.protoDriving =
        SDK.DrivingPlan
          { SDK.drivingNodes =
              [ SDK.NodeDrive [] [[0],[1]] [] Nothing [] [] []
              , SDK.NodeDrive [0] [[0]] [] Nothing [[-1]] [] []
              , SDK.NodeDrive [1] [[1]] [] Nothing [[-1]] [] []
              , SDK.NodeDrive [-1] [] [] Nothing [] [] []
              ]
          , SDK.drivingUnits = []
          , SDK.drivingSessions = []
          , SDK.drivingRootNodes = [[0],[1],[-1]]
          , SDK.drivingOutputSites = []
          , SDK.drivingRequests =
              [ ("FileLocation", GetFileNameGen)
              , ("FileResource", GetOpenedFileGen)
              , ("BlankText", GetFileBlankGen)
              , ("FilledText", GetFileWrittenGen)
              ]
          , SDK.drivingMiddleware = []
          , SDK.drivingHooks = []
          }
    }
