{-# LANGUAGE DuplicateRecordFields #-}

-- 自动生成；只登记末端入口与原型，执行由 SDK 的 interpreter 完成。
module OpenFilesDemo.Generated.Program where

import Framework.Generated (EffectSpec(..), EffectTyping(..), Asset(..), Handles(..), Demand(..), Access(..), TypeRef(..))
import qualified Framework.Generated as SDK
import qualified Framework.Effect.Contract as FrameworkRoot
import OpenFilesDemo.Generated.Effects
import qualified OpenFilesDemo.Generated.Handlers as Handlers
import OpenFilesDemo.Types


-- 仅汇总所选末端的成功结果，不保存共享绑定或增加完成包装。
data Results = HoldFilesResult () | InspectFilesResult () | ReleaseFilesResult () | FinishInspectionResult ()
  deriving Show

-- 末端共享生成的 scope 句柄；只创建空状态，Node algebra 才 lower。
-- 第二个列表是各转折契约的读取末端：读取资产，返回它当前的构造器名。
-- 第三个列表是各持续资产的生产步骤：会话按需启动，Stream 单步取得原始输入，parser 发布一次资产。
compiledEntries :: IO ([SDK.Target ContextValues Errors Results], [SDK.Target ContextValues Errors String]
                     , [(String, SDK.SessionSteps ContextValues Errors)])
compiledEntries = do
  scopes <- Handlers.newScopeHandlers
  pure
    ( [ SDK.targetApp "HoldFiles" emptyContexts scopes (FrameworkRoot.withErrorHandlers Handlers.errorHandlers (FrameworkRoot.withAnchoredContexts Handlers.contextInjections (SDK.withScopeCleanups Handlers.scopeCleanups (HoldFilesResult <$> (() <$ Handlers.runHoldFiles)))))
      , SDK.targetApp "InspectFiles" emptyContexts scopes (FrameworkRoot.withErrorHandlers Handlers.errorHandlers (FrameworkRoot.withAnchoredContexts Handlers.contextInjections (SDK.withScopeCleanups Handlers.scopeCleanups (InspectFilesResult <$> (() <$ Handlers.runInspectFiles)))))
      , SDK.targetApp "ReleaseFiles" emptyContexts scopes (FrameworkRoot.withErrorHandlers Handlers.errorHandlers (FrameworkRoot.withAnchoredContexts Handlers.contextInjections (SDK.withScopeCleanups Handlers.scopeCleanups (ReleaseFilesResult <$> (() <$ Handlers.runReleaseFiles)))))
      , SDK.targetApp "FinishInspection" emptyContexts scopes (FrameworkRoot.withErrorHandlers Handlers.errorHandlers (FrameworkRoot.withAnchoredContexts Handlers.contextInjections (SDK.withScopeCleanups Handlers.scopeCleanups (FinishInspectionResult <$> (() <$ Handlers.runFinishInspection)))))
      ]
    , []
    , []
    )

-- SDK 装配入口，不需要用户提供节点执行器或重复选择 handler。
interpreter :: SDK.AST -> [EffectSpec] -> IO ()
interpreter = SDK.interpreter "OpenFilesDemo" "demo/OpenFilesDemo/Handlers.hs" Handlers.handlerSourceFingerprint generatedPrototype compiledEntries
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
                  (SDK.AssetDecl ("FileNames") (SDK.TypeRef ("[[Char]]")))
                  (Just "listFiles")
                  (True)
                  (False)
            , SDK.input = "Root"
            , SDK.demands = []
            }
        , SDK.EffectSpec
            { SDK.name = "FileResources"
            , SDK.typing =
                SDK.Context
                  (SDK.AssetDecl ("OpenedFiles") (SDK.TypeRef ("[FileHandle]")))
                  (Just "acquireFiles")
                  (True)
                  (False)
            , SDK.input = "Root"
            , SDK.demands = [SDK.Demand (SDK.RequireAccess) ("FileNames")]
            }
        , SDK.EffectSpec
            { SDK.name = "FileSession"
            , SDK.typing = SDK.Scoped (Just "openFiles") (Just "closeFiles")
            , SDK.input = "Root"
            , SDK.demands =
                [SDK.Demand (SDK.RequestAccess) ("OpenedFiles"), SDK.Demand (SDK.RequireAccess) ("OpenedFiles")]
            }
        , SDK.EffectSpec
            { SDK.name = "HoldFiles"
            , SDK.typing = SDK.Excu (Just "holdFiles")
            , SDK.input = "FileSession"
            , SDK.demands = [SDK.Demand (SDK.RequestAccess) ("FileNames")]
            }
        , SDK.EffectSpec
            { SDK.name = "InspectFiles"
            , SDK.typing = SDK.Excu (Just "inspectFiles")
            , SDK.input = "HoldFiles"
            , SDK.demands = [SDK.Demand (SDK.RequireAccess) ("OpenedFiles")]
            }
        , SDK.EffectSpec
            { SDK.name = "ReleaseFiles"
            , SDK.typing = SDK.Excu (Just "holdFiles")
            , SDK.input = "HoldFiles"
            , SDK.demands = []
            }
        , SDK.EffectSpec
            { SDK.name = "InspectionSnapshot"
            , SDK.typing =
                SDK.Context
                  (SDK.AssetDecl ("InspectedFiles") (SDK.TypeRef ("[FileHandle]")))
                  (Just "snapshotFiles")
                  (True)
                  (False)
            , SDK.input = "ReleaseFiles"
            , SDK.demands = [SDK.Demand (SDK.RequireAccess) ("OpenedFiles")]
            }
        , SDK.EffectSpec
            { SDK.name = "FinishInspection"
            , SDK.typing = SDK.Excu (Just "finishInspection")
            , SDK.input = "Root"
            , SDK.demands = [SDK.Demand (SDK.RequireAccess) ("InspectedFiles")]
            }
        ]
    , SDK.protoEffects =
        [ SDK.EffectProto
            { SDK.effectName = "FileLocations"
            , SDK.effectKind = SDK.ContextKind
            , SDK.effectInput = "Root"
            , SDK.effectMethods =
                [(SDK.ContextRequest, GetFileNamesGen), (SDK.ContextRequire, ReadFileNamesGen)]
            , SDK.effectDemands = []
            , SDK.effectProduces = Just "FileNames"
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
            { SDK.effectName = "FileResources"
            , SDK.effectKind = SDK.ContextKind
            , SDK.effectInput = "Root"
            , SDK.effectMethods =
                [(SDK.ContextRequest, GetOpenedFilesGen), (SDK.ContextRequire, ReadOpenedFilesGen)]
            , SDK.effectDemands = [SDK.ResolvedDemand (SDK.RequireAccess) ("FileNames") ("FileLocations")]
            , SDK.effectProduces = Just "OpenedFiles"
            , SDK.effectBranches = []
            , SDK.effectAnchor = Nothing
            , SDK.effectScopes = []
            , SDK.effectErrorScope = Nothing
            , SDK.effectInputChain = []
            , SDK.effectScopeParents = []
            , SDK.effectOpeningInputs = []
            , SDK.effectNearestScopes = []
            , SDK.effectResource = Nothing
            , SDK.effectContextDependencies = ["FileLocations"]
            , SDK.effectContinuous = False
            }
        , SDK.EffectProto
            { SDK.effectName = "FileSession"
            , SDK.effectKind = SDK.ScopedKind
            , SDK.effectInput = "Root"
            , SDK.effectMethods = [(SDK.ScopeOpen, OpenFileSessionGen), (SDK.ScopeClose, CloseFileSessionGen)]
            , SDK.effectDemands =
                [ SDK.ResolvedDemand (SDK.RequestAccess) ("OpenedFiles") ("FileResources")
                , SDK.ResolvedDemand (SDK.RequireAccess) ("OpenedFiles") ("FileResources")
                ]
            , SDK.effectProduces = Nothing
            , SDK.effectBranches = []
            , SDK.effectAnchor = Nothing
            , SDK.effectScopes = []
            , SDK.effectErrorScope = Nothing
            , SDK.effectInputChain = []
            , SDK.effectScopeParents = []
            , SDK.effectOpeningInputs = ["FileLocations"]
            , SDK.effectNearestScopes = ["FileSession"]
            , SDK.effectResource = Just "FileResources"
            , SDK.effectContextDependencies = ["FileLocations","FileResources"]
            , SDK.effectContinuous = False
            }
        , SDK.EffectProto
            { SDK.effectName = "HoldFiles"
            , SDK.effectKind = SDK.ExcuKind
            , SDK.effectInput = "FileSession"
            , SDK.effectMethods = [(SDK.HandlerMethod, RunHoldFilesGen)]
            , SDK.effectDemands = [SDK.ResolvedDemand (SDK.RequestAccess) ("FileNames") ("FileLocations")]
            , SDK.effectProduces = Nothing
            , SDK.effectBranches = []
            , SDK.effectAnchor = Nothing
            , SDK.effectScopes = ["FileSession"]
            , SDK.effectErrorScope = Nothing
            , SDK.effectInputChain = ["FileSession"]
            , SDK.effectScopeParents = ["FileSession"]
            , SDK.effectOpeningInputs = []
            , SDK.effectNearestScopes = ["FileSession"]
            , SDK.effectResource = Nothing
            , SDK.effectContextDependencies = ["FileLocations","FileResources"]
            , SDK.effectContinuous = False
            }
        , SDK.EffectProto
            { SDK.effectName = "InspectFiles"
            , SDK.effectKind = SDK.ExcuKind
            , SDK.effectInput = "HoldFiles"
            , SDK.effectMethods = [(SDK.HandlerMethod, RunInspectFilesGen)]
            , SDK.effectDemands = [SDK.ResolvedDemand (SDK.RequireAccess) ("OpenedFiles") ("FileResources")]
            , SDK.effectProduces = Nothing
            , SDK.effectBranches = []
            , SDK.effectAnchor = Nothing
            , SDK.effectScopes = ["FileSession"]
            , SDK.effectErrorScope = Nothing
            , SDK.effectInputChain = ["HoldFiles","FileSession"]
            , SDK.effectScopeParents = ["FileSession"]
            , SDK.effectOpeningInputs = []
            , SDK.effectNearestScopes = ["FileSession"]
            , SDK.effectResource = Nothing
            , SDK.effectContextDependencies = ["FileLocations","FileResources"]
            , SDK.effectContinuous = False
            }
        , SDK.EffectProto
            { SDK.effectName = "ReleaseFiles"
            , SDK.effectKind = SDK.ExcuKind
            , SDK.effectInput = "HoldFiles"
            , SDK.effectMethods = [(SDK.HandlerMethod, RunReleaseFilesGen)]
            , SDK.effectDemands = []
            , SDK.effectProduces = Nothing
            , SDK.effectBranches = []
            , SDK.effectAnchor = Nothing
            , SDK.effectScopes = ["FileSession"]
            , SDK.effectErrorScope = Nothing
            , SDK.effectInputChain = ["HoldFiles","FileSession"]
            , SDK.effectScopeParents = ["FileSession"]
            , SDK.effectOpeningInputs = []
            , SDK.effectNearestScopes = ["FileSession"]
            , SDK.effectResource = Nothing
            , SDK.effectContextDependencies = ["FileLocations","FileResources"]
            , SDK.effectContinuous = False
            }
        , SDK.EffectProto
            { SDK.effectName = "InspectionSnapshot"
            , SDK.effectKind = SDK.ContextKind
            , SDK.effectInput = "ReleaseFiles"
            , SDK.effectMethods =
                [(SDK.ContextRequest, GetInspectedFilesGen), (SDK.ContextRequire, ReadInspectedFilesGen)]
            , SDK.effectDemands = [SDK.ResolvedDemand (SDK.RequireAccess) ("OpenedFiles") ("FileResources")]
            , SDK.effectProduces = Just "InspectedFiles"
            , SDK.effectBranches = []
            , SDK.effectAnchor = Just "ReleaseFiles"
            , SDK.effectScopes = ["FileSession"]
            , SDK.effectErrorScope = Nothing
            , SDK.effectInputChain = ["ReleaseFiles","HoldFiles","FileSession"]
            , SDK.effectScopeParents = ["FileSession"]
            , SDK.effectOpeningInputs = []
            , SDK.effectNearestScopes = ["FileSession"]
            , SDK.effectResource = Nothing
            , SDK.effectContextDependencies = ["FileLocations","FileResources"]
            , SDK.effectContinuous = False
            }
        , SDK.EffectProto
            { SDK.effectName = "FinishInspection"
            , SDK.effectKind = SDK.ExcuKind
            , SDK.effectInput = "Root"
            , SDK.effectMethods = [(SDK.HandlerMethod, RunFinishInspectionGen)]
            , SDK.effectDemands =
                [SDK.ResolvedDemand (SDK.RequireAccess) ("InspectedFiles") ("InspectionSnapshot")]
            , SDK.effectProduces = Nothing
            , SDK.effectBranches = []
            , SDK.effectAnchor = Nothing
            , SDK.effectScopes = []
            , SDK.effectErrorScope = Nothing
            , SDK.effectInputChain = []
            , SDK.effectScopeParents = ["FileSession"]
            , SDK.effectOpeningInputs = []
            , SDK.effectNearestScopes = []
            , SDK.effectResource = Nothing
            , SDK.effectContextDependencies = ["FileLocations","FileResources","InspectionSnapshot"]
            , SDK.effectContinuous = False
            }
        ]
    , SDK.protoMethods =
        [ SDK.MethodDefinition (GetFileNamesGen) (GetFileNamesGen) (SDK.ContextRequest) (SDK.Empty)
        , SDK.MethodDefinition
            (ReadFileNamesGen)
            (GetFileNamesGen)
            (SDK.ContextRequire)
            (SDK.Choice ([SDK.Empty, SDK.Call (GetFileNamesGen)]))
        , SDK.MethodDefinition
            (GetOpenedFilesGen)
            (GetOpenedFilesGen)
            (SDK.ContextRequest)
            (SDK.Call (ReadFileNamesGen))
        , SDK.MethodDefinition (ReadOpenedFilesGen) (GetOpenedFilesGen) (SDK.ContextRequire) (SDK.Empty)
        , SDK.MethodDefinition
            (OpenFileSessionGen)
            (OpenFileSessionGen)
            (SDK.ScopeOpen)
            (SDK.Sequence ([SDK.Call (GetOpenedFilesGen), SDK.Call (ReadOpenedFilesGen)]))
        , SDK.MethodDefinition
            (CloseFileSessionGen)
            (OpenFileSessionGen)
            (SDK.ScopeClose)
            (SDK.Call (ReadOpenedFilesGen))
        , SDK.MethodDefinition
            (RunHoldFilesGen)
            (RunHoldFilesGen)
            (SDK.HandlerMethod)
            (SDK.Sequence ([SDK.Call (GetFileNamesGen), SDK.Call (OpenFileSessionGen)]))
        , SDK.MethodDefinition
            (RunInspectFilesGen)
            (RunInspectFilesGen)
            (SDK.HandlerMethod)
            (SDK.Sequence ([SDK.Call (RunHoldFilesGen), SDK.Call (ReadOpenedFilesGen)]))
        , SDK.MethodDefinition
            (RunReleaseFilesGen)
            (RunReleaseFilesGen)
            (SDK.HandlerMethod)
            (
              SDK.Sequence
                (
                  [ SDK.Call (RunHoldFilesGen)
                  , SDK.Choice ([SDK.Empty, SDK.Sequence ([SDK.Call (ReadOpenedFilesGen)])])
                  ]
                )
            )
        , SDK.MethodDefinition
            (GetInspectedFilesGen)
            (GetInspectedFilesGen)
            (SDK.ContextRequest)
            (SDK.Call (ReadOpenedFilesGen))
        , SDK.MethodDefinition
            (ReadInspectedFilesGen)
            (GetInspectedFilesGen)
            (SDK.ContextRequire)
            (SDK.Choice ([SDK.Empty, SDK.Call (GetInspectedFilesGen)]))
        , SDK.MethodDefinition
            (RunFinishInspectionGen)
            (RunFinishInspectionGen)
            (SDK.HandlerMethod)
            (SDK.Call (ReadInspectedFilesGen))
        ]
    , SDK.protoWorkflow =
        SDK.ChainedAt
          ([])
          (
            [ SDK.ChainedAt
                ([0])
                (
                  [ SDK.NodeAt ([0,0]) ("HoldFiles")
                  , SDK.NodeAt ([0,1]) ("InspectFiles")
                  ]
                )
            , SDK.ChainedAt
                ([1])
                (
                  [ SDK.NodeAt ([1,0]) ("ReleaseFiles")
                  , SDK.NodeAt ([1,1]) ("FinishInspection")
                  ]
                )
            ]
          )
    , SDK.protoSessions = []
    , SDK.protoChains =
        [ SDK.ChainProto
            { SDK.chainNode = [0,0]
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
            { SDK.chainNode = [0,1]
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
            { SDK.chainNode = [1,0]
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
                , GetInspectedFilesGen
                ]
            , SDK.chainDrives = ["FileNames","InspectedFiles"]
            , SDK.chainReads = []
            , SDK.chainScopePaths = [[OpenFileSessionGen]]
            }
        , SDK.ChainProto
            { SDK.chainNode = [1,1]
            , SDK.chainRole = SDK.NodeChain
            , SDK.chainTerminal = "FinishInspection"
            , SDK.chainEntry = RunFinishInspectionGen
            , SDK.chainReaches =
                [RunFinishInspectionGen, ReadInspectedFilesGen, GetInspectedFilesGen, ReadOpenedFilesGen]
            , SDK.chainDrives = ["InspectedFiles"]
            , SDK.chainReads = ["InspectedFiles","OpenedFiles"]
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
            , SDK.definitionReaches = [ReadFileNamesGen, GetFileNamesGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.ContextChain
            , SDK.definitionEffect = "FileResources"
            , SDK.definitionEntry = GetOpenedFilesGen
            , SDK.definitionReaches = [GetOpenedFilesGen, ReadFileNamesGen, GetFileNamesGen]
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
                [OpenFileSessionGen, GetOpenedFilesGen, ReadFileNamesGen, GetFileNamesGen, ReadOpenedFilesGen]
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
                , GetInspectedFilesGen
                ]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.ContextChain
            , SDK.definitionEffect = "InspectionSnapshot"
            , SDK.definitionEntry = GetInspectedFilesGen
            , SDK.definitionReaches = [GetInspectedFilesGen, ReadOpenedFilesGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.ContextChain
            , SDK.definitionEffect = "InspectionSnapshot"
            , SDK.definitionEntry = ReadInspectedFilesGen
            , SDK.definitionReaches = [ReadInspectedFilesGen, GetInspectedFilesGen, ReadOpenedFilesGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.OriginChain
            , SDK.definitionEffect = "FinishInspection"
            , SDK.definitionEntry = RunFinishInspectionGen
            , SDK.definitionReaches =
                [RunFinishInspectionGen, ReadInspectedFilesGen, GetInspectedFilesGen, ReadOpenedFilesGen]
            }
        ]
    , SDK.protoGraph =
        SDK.EffectGraph
          { SDK.graphMethods =
              [ SDK.MethodDefinition
                  (RunHoldFilesGen)
                  (RunHoldFilesGen)
                  (SDK.HandlerMethod)
                  (SDK.Sequence ([SDK.Call (GetFileNamesGen), SDK.Call (OpenFileSessionGen)]))
              , SDK.MethodDefinition (GetFileNamesGen) (GetFileNamesGen) (SDK.ContextRequest) (SDK.Empty)
              , SDK.MethodDefinition
                  (OpenFileSessionGen)
                  (OpenFileSessionGen)
                  (SDK.ScopeOpen)
                  (SDK.Sequence ([SDK.Call (GetOpenedFilesGen), SDK.Call (ReadOpenedFilesGen)]))
              , SDK.MethodDefinition
                  (GetOpenedFilesGen)
                  (GetOpenedFilesGen)
                  (SDK.ContextRequest)
                  (SDK.Call (ReadFileNamesGen))
              , SDK.MethodDefinition
                  (ReadFileNamesGen)
                  (GetFileNamesGen)
                  (SDK.ContextRequire)
                  (SDK.Choice ([SDK.Empty, SDK.Call (GetFileNamesGen)]))
              , SDK.MethodDefinition (ReadOpenedFilesGen) (GetOpenedFilesGen) (SDK.ContextRequire) (SDK.Empty)
              , SDK.MethodDefinition
                  (RunInspectFilesGen)
                  (RunInspectFilesGen)
                  (SDK.HandlerMethod)
                  (SDK.Sequence ([SDK.Call (RunHoldFilesGen), SDK.Call (ReadOpenedFilesGen)]))
              , SDK.MethodDefinition
                  (RunReleaseFilesGen)
                  (RunReleaseFilesGen)
                  (SDK.HandlerMethod)
                  (
                    SDK.Sequence
                      (
                        [ SDK.Call (RunHoldFilesGen)
                        , SDK.Choice ([SDK.Empty, SDK.Sequence ([SDK.Call (ReadOpenedFilesGen)])])
                        ]
                      )
                  )
              , SDK.MethodDefinition
                  (RunFinishInspectionGen)
                  (RunFinishInspectionGen)
                  (SDK.HandlerMethod)
                  (SDK.Call (ReadInspectedFilesGen))
              , SDK.MethodDefinition
                  (ReadInspectedFilesGen)
                  (GetInspectedFilesGen)
                  (SDK.ContextRequire)
                  (SDK.Choice ([SDK.Empty, SDK.Call (GetInspectedFilesGen)]))
              , SDK.MethodDefinition
                  (GetInspectedFilesGen)
                  (GetInspectedFilesGen)
                  (SDK.ContextRequest)
                  (SDK.Call (ReadOpenedFilesGen))
              ]
          , SDK.graphRoots =
              [RunHoldFilesGen, RunInspectFilesGen, RunReleaseFilesGen, RunFinishInspectionGen]
          , SDK.graphReferences =
              [ (RunHoldFilesGen, GetFileNamesGen)
              , (RunHoldFilesGen, OpenFileSessionGen)
              , (OpenFileSessionGen, GetOpenedFilesGen)
              , (OpenFileSessionGen, ReadOpenedFilesGen)
              , (GetOpenedFilesGen, ReadFileNamesGen)
              , (ReadFileNamesGen, GetFileNamesGen)
              , (RunInspectFilesGen, RunHoldFilesGen)
              , (RunInspectFilesGen, ReadOpenedFilesGen)
              , (RunReleaseFilesGen, RunHoldFilesGen)
              , (RunReleaseFilesGen, ReadOpenedFilesGen)
              , (RunFinishInspectionGen, ReadInspectedFilesGen)
              , (ReadInspectedFilesGen, GetInspectedFilesGen)
              , (GetInspectedFilesGen, ReadOpenedFilesGen)
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
    , SDK.protoSources =
        [ (SDK.ReadPoint ([1,1]) ("InspectedFiles"), SDK.FromChains ([[1,0]]))
        , (SDK.ReadPoint ([1,1]) ("OpenedFiles"), SDK.FromOwnChain)
        ]
    }
