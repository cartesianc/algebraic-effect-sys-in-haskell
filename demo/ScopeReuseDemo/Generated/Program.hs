{-# LANGUAGE DuplicateRecordFields #-}

-- 自动生成；只登记末端入口与原型，执行由 SDK 的 interpreter 完成。
module ScopeReuseDemo.Generated.Program where

import Framework.Generated (EffectSpec(..), EffectTyping(..), Asset(..), Handles(..), Demand(..), Access(..), TypeRef(..))
import qualified Framework.Generated as SDK
import qualified Framework.Effect.Contract as FrameworkRoot
import ScopeReuseDemo.Generated.Effects
import qualified ScopeReuseDemo.Generated.Handlers as Handlers
import ScopeReuseDemo.Types


-- 仅汇总所选末端的成功结果，不保存共享绑定或增加完成包装。
data Results = PrepareProbeResult () | WriteFirstResult () | WriteSecondResult () | WriteThirdResult () | VerifyReuseResult ()
  deriving Show

-- 末端共享生成的 scope 句柄；只创建空状态，Node algebra 才 lower。
-- 第二个列表是各转折契约的读取末端：读取资产，返回它当前的构造器名。
-- 第三个列表是各持续资产的生产步骤：会话按需启动，Stream 单步取得原始输入，parser 发布一次资产。
compiledEntries :: IO ([SDK.Target ContextValues Errors Results], [SDK.Target ContextValues Errors String]
                     , [(String, SDK.SessionSteps ContextValues Errors)])
compiledEntries = do
  scopes <- Handlers.newScopeHandlers
  pure
    ( [ SDK.targetApp "PrepareProbe" emptyContexts scopes (FrameworkRoot.withErrorHandlers Handlers.errorHandlers (FrameworkRoot.withAnchoredContexts Handlers.contextInjections (SDK.withScopeCleanups Handlers.scopeCleanups (PrepareProbeResult <$> (() <$ Handlers.runPrepareProbe)))))
      , SDK.targetApp "WriteFirst" emptyContexts scopes (FrameworkRoot.withErrorHandlers Handlers.errorHandlers (FrameworkRoot.withAnchoredContexts Handlers.contextInjections (SDK.withScopeCleanups Handlers.scopeCleanups (WriteFirstResult <$> (() <$ Handlers.runWriteFirst)))))
      , SDK.targetApp "WriteSecond" emptyContexts scopes (FrameworkRoot.withErrorHandlers Handlers.errorHandlers (FrameworkRoot.withAnchoredContexts Handlers.contextInjections (SDK.withScopeCleanups Handlers.scopeCleanups (WriteSecondResult <$> (() <$ Handlers.runWriteSecond)))))
      , SDK.targetApp "WriteThird" emptyContexts scopes (FrameworkRoot.withErrorHandlers Handlers.errorHandlers (FrameworkRoot.withAnchoredContexts Handlers.contextInjections (SDK.withScopeCleanups Handlers.scopeCleanups (WriteThirdResult <$> (() <$ Handlers.runWriteThird)))))
      , SDK.targetApp "VerifyReuse" emptyContexts scopes (FrameworkRoot.withErrorHandlers Handlers.errorHandlers (FrameworkRoot.withAnchoredContexts Handlers.contextInjections (SDK.withScopeCleanups Handlers.scopeCleanups (VerifyReuseResult <$> (() <$ Handlers.runVerifyReuse)))))
      ]
    , []
    , []
    )

-- SDK 装配入口，不需要用户提供节点执行器或重复选择 handler。
interpreter :: SDK.AST -> [EffectSpec] -> IO ()
interpreter = SDK.interpreter "ScopeReuseDemo" "demo/ScopeReuseDemo/Handlers.hs" Handlers.handlerSourceFingerprint generatedPrototype compiledEntries
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
                  (SDK.AssetDecl ("FilePaths") (SDK.TypeRef ("SharedPaths")))
                  (Just "sharedPaths")
                  (True)
                  (False)
            , SDK.input = "Root"
            , SDK.demands = []
            }
        , SDK.EffectSpec
            { SDK.name = "PrepareProbe"
            , SDK.typing = SDK.Excu (Just "prepareProbe")
            , SDK.input = "Root"
            , SDK.demands =
                [SDK.Demand (SDK.RequestAccess) ("FilePaths"), SDK.Demand (SDK.RequireAccess) ("FilePaths")]
            }
        , SDK.EffectSpec
            { SDK.name = "FileResource"
            , SDK.typing =
                SDK.Context
                  (SDK.AssetDecl ("OpenedFile") (SDK.TypeRef ("SharedFile")))
                  (Just "acquireFile")
                  (True)
                  (False)
            , SDK.input = "Root"
            , SDK.demands = [SDK.Demand (SDK.RequireAccess) ("FilePaths")]
            }
        , SDK.EffectSpec
            { SDK.name = "SharedFileScope"
            , SDK.typing = SDK.Scoped (Just "openSharedFile") (Just "closeSharedFile")
            , SDK.input = "Root"
            , SDK.demands =
                [SDK.Demand (SDK.RequestAccess) ("OpenedFile"), SDK.Demand (SDK.RequireAccess) ("OpenedFile")]
            }
        , SDK.EffectSpec
            { SDK.name = "WriteFirst"
            , SDK.typing = SDK.Excu (Just "writeFirst")
            , SDK.input = "SharedFileScope"
            , SDK.demands =
                [SDK.Demand (SDK.RequestAccess) ("FilePaths"), SDK.Demand (SDK.RequireAccess) ("OpenedFile")]
            }
        , SDK.EffectSpec
            { SDK.name = "WriteSecond"
            , SDK.typing = SDK.Excu (Just "writeSecond")
            , SDK.input = "SharedFileScope"
            , SDK.demands =
                [SDK.Demand (SDK.RequestAccess) ("FilePaths"), SDK.Demand (SDK.RequireAccess) ("OpenedFile")]
            }
        , SDK.EffectSpec
            { SDK.name = "WriteThird"
            , SDK.typing = SDK.Excu (Just "writeThird")
            , SDK.input = "SharedFileScope"
            , SDK.demands =
                [SDK.Demand (SDK.RequestAccess) ("FilePaths"), SDK.Demand (SDK.RequireAccess) ("OpenedFile")]
            }
        , SDK.EffectSpec
            { SDK.name = "VerifyReuse"
            , SDK.typing = SDK.Excu (Just "verifyReuse")
            , SDK.input = "Root"
            , SDK.demands =
                [SDK.Demand (SDK.RequestAccess) ("FilePaths"), SDK.Demand (SDK.RequireAccess) ("FilePaths")]
            }
        ]
    , SDK.protoEffects =
        [ SDK.EffectProto
            { SDK.effectName = "FileLocations"
            , SDK.effectKind = SDK.ContextKind
            , SDK.effectInput = "Root"
            , SDK.effectMethods =
                [(SDK.ContextRequest, GetFilePathsGen), (SDK.ContextRequire, ReadFilePathsGen)]
            , SDK.effectDemands = []
            , SDK.effectProduces = Just "FilePaths"
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
            { SDK.effectName = "PrepareProbe"
            , SDK.effectKind = SDK.ExcuKind
            , SDK.effectInput = "Root"
            , SDK.effectMethods = [(SDK.HandlerMethod, RunPrepareProbeGen)]
            , SDK.effectDemands =
                [ SDK.ResolvedDemand (SDK.RequestAccess) ("FilePaths") ("FileLocations")
                , SDK.ResolvedDemand (SDK.RequireAccess) ("FilePaths") ("FileLocations")
                ]
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
            , SDK.effectContextDependencies = ["FileLocations"]
            , SDK.effectContinuous = False
            }
        , SDK.EffectProto
            { SDK.effectName = "FileResource"
            , SDK.effectKind = SDK.ContextKind
            , SDK.effectInput = "Root"
            , SDK.effectMethods =
                [(SDK.ContextRequest, GetOpenedFileGen), (SDK.ContextRequire, ReadOpenedFileGen)]
            , SDK.effectDemands = [SDK.ResolvedDemand (SDK.RequireAccess) ("FilePaths") ("FileLocations")]
            , SDK.effectProduces = Just "OpenedFile"
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
            { SDK.effectName = "SharedFileScope"
            , SDK.effectKind = SDK.ScopedKind
            , SDK.effectInput = "Root"
            , SDK.effectMethods =
                [(SDK.ScopeOpen, OpenSharedFileScopeGen), (SDK.ScopeClose, CloseSharedFileScopeGen)]
            , SDK.effectDemands =
                [ SDK.ResolvedDemand (SDK.RequestAccess) ("OpenedFile") ("FileResource")
                , SDK.ResolvedDemand (SDK.RequireAccess) ("OpenedFile") ("FileResource")
                ]
            , SDK.effectProduces = Nothing
            , SDK.effectBranches = []
            , SDK.effectAnchor = Nothing
            , SDK.effectScopes = []
            , SDK.effectErrorScope = Nothing
            , SDK.effectInputChain = []
            , SDK.effectScopeParents = []
            , SDK.effectOpeningInputs = ["FileLocations"]
            , SDK.effectNearestScopes = ["SharedFileScope"]
            , SDK.effectResource = Just "FileResource"
            , SDK.effectContextDependencies = ["FileLocations","FileResource"]
            , SDK.effectContinuous = False
            }
        , SDK.EffectProto
            { SDK.effectName = "WriteFirst"
            , SDK.effectKind = SDK.ExcuKind
            , SDK.effectInput = "SharedFileScope"
            , SDK.effectMethods = [(SDK.HandlerMethod, RunWriteFirstGen)]
            , SDK.effectDemands =
                [ SDK.ResolvedDemand (SDK.RequestAccess) ("FilePaths") ("FileLocations")
                , SDK.ResolvedDemand (SDK.RequireAccess) ("OpenedFile") ("FileResource")
                ]
            , SDK.effectProduces = Nothing
            , SDK.effectBranches = []
            , SDK.effectAnchor = Nothing
            , SDK.effectScopes = ["SharedFileScope"]
            , SDK.effectErrorScope = Nothing
            , SDK.effectInputChain = ["SharedFileScope"]
            , SDK.effectScopeParents = ["SharedFileScope"]
            , SDK.effectOpeningInputs = []
            , SDK.effectNearestScopes = ["SharedFileScope"]
            , SDK.effectResource = Nothing
            , SDK.effectContextDependencies = ["FileLocations","FileResource"]
            , SDK.effectContinuous = False
            }
        , SDK.EffectProto
            { SDK.effectName = "WriteSecond"
            , SDK.effectKind = SDK.ExcuKind
            , SDK.effectInput = "SharedFileScope"
            , SDK.effectMethods = [(SDK.HandlerMethod, RunWriteSecondGen)]
            , SDK.effectDemands =
                [ SDK.ResolvedDemand (SDK.RequestAccess) ("FilePaths") ("FileLocations")
                , SDK.ResolvedDemand (SDK.RequireAccess) ("OpenedFile") ("FileResource")
                ]
            , SDK.effectProduces = Nothing
            , SDK.effectBranches = []
            , SDK.effectAnchor = Nothing
            , SDK.effectScopes = ["SharedFileScope"]
            , SDK.effectErrorScope = Nothing
            , SDK.effectInputChain = ["SharedFileScope"]
            , SDK.effectScopeParents = ["SharedFileScope"]
            , SDK.effectOpeningInputs = []
            , SDK.effectNearestScopes = ["SharedFileScope"]
            , SDK.effectResource = Nothing
            , SDK.effectContextDependencies = ["FileLocations","FileResource"]
            , SDK.effectContinuous = False
            }
        , SDK.EffectProto
            { SDK.effectName = "WriteThird"
            , SDK.effectKind = SDK.ExcuKind
            , SDK.effectInput = "SharedFileScope"
            , SDK.effectMethods = [(SDK.HandlerMethod, RunWriteThirdGen)]
            , SDK.effectDemands =
                [ SDK.ResolvedDemand (SDK.RequestAccess) ("FilePaths") ("FileLocations")
                , SDK.ResolvedDemand (SDK.RequireAccess) ("OpenedFile") ("FileResource")
                ]
            , SDK.effectProduces = Nothing
            , SDK.effectBranches = []
            , SDK.effectAnchor = Nothing
            , SDK.effectScopes = ["SharedFileScope"]
            , SDK.effectErrorScope = Nothing
            , SDK.effectInputChain = ["SharedFileScope"]
            , SDK.effectScopeParents = ["SharedFileScope"]
            , SDK.effectOpeningInputs = []
            , SDK.effectNearestScopes = ["SharedFileScope"]
            , SDK.effectResource = Nothing
            , SDK.effectContextDependencies = ["FileLocations","FileResource"]
            , SDK.effectContinuous = False
            }
        , SDK.EffectProto
            { SDK.effectName = "VerifyReuse"
            , SDK.effectKind = SDK.ExcuKind
            , SDK.effectInput = "Root"
            , SDK.effectMethods = [(SDK.HandlerMethod, RunVerifyReuseGen)]
            , SDK.effectDemands =
                [ SDK.ResolvedDemand (SDK.RequestAccess) ("FilePaths") ("FileLocations")
                , SDK.ResolvedDemand (SDK.RequireAccess) ("FilePaths") ("FileLocations")
                ]
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
            , SDK.effectContextDependencies = ["FileLocations"]
            , SDK.effectContinuous = False
            }
        ]
    , SDK.protoMethods =
        [ SDK.MethodDefinition (GetFilePathsGen) (GetFilePathsGen) (SDK.ContextRequest) (SDK.Empty)
        , SDK.MethodDefinition
            (ReadFilePathsGen)
            (GetFilePathsGen)
            (SDK.ContextRequire)
            (SDK.Choice ([SDK.Empty, SDK.Call (GetFilePathsGen)]))
        , SDK.MethodDefinition
            (RunPrepareProbeGen)
            (RunPrepareProbeGen)
            (SDK.HandlerMethod)
            (SDK.Sequence ([SDK.Call (GetFilePathsGen), SDK.Call (ReadFilePathsGen)]))
        , SDK.MethodDefinition
            (GetOpenedFileGen)
            (GetOpenedFileGen)
            (SDK.ContextRequest)
            (SDK.Call (ReadFilePathsGen))
        , SDK.MethodDefinition (ReadOpenedFileGen) (GetOpenedFileGen) (SDK.ContextRequire) (SDK.Empty)
        , SDK.MethodDefinition
            (OpenSharedFileScopeGen)
            (OpenSharedFileScopeGen)
            (SDK.ScopeOpen)
            (SDK.Sequence ([SDK.Call (GetOpenedFileGen), SDK.Call (ReadOpenedFileGen)]))
        , SDK.MethodDefinition
            (CloseSharedFileScopeGen)
            (OpenSharedFileScopeGen)
            (SDK.ScopeClose)
            (SDK.Call (ReadOpenedFileGen))
        , SDK.MethodDefinition
            (RunWriteFirstGen)
            (RunWriteFirstGen)
            (SDK.HandlerMethod)
            (
              SDK.Sequence
                ([SDK.Call (GetFilePathsGen), SDK.Call (OpenSharedFileScopeGen), SDK.Call (ReadOpenedFileGen)])
            )
        , SDK.MethodDefinition
            (RunWriteSecondGen)
            (RunWriteSecondGen)
            (SDK.HandlerMethod)
            (
              SDK.Sequence
                ([SDK.Call (GetFilePathsGen), SDK.Call (OpenSharedFileScopeGen), SDK.Call (ReadOpenedFileGen)])
            )
        , SDK.MethodDefinition
            (RunWriteThirdGen)
            (RunWriteThirdGen)
            (SDK.HandlerMethod)
            (
              SDK.Sequence
                ([SDK.Call (GetFilePathsGen), SDK.Call (OpenSharedFileScopeGen), SDK.Call (ReadOpenedFileGen)])
            )
        , SDK.MethodDefinition
            (RunVerifyReuseGen)
            (RunVerifyReuseGen)
            (SDK.HandlerMethod)
            (SDK.Sequence ([SDK.Call (GetFilePathsGen), SDK.Call (ReadFilePathsGen)]))
        ]
    , SDK.protoWorkflow =
        SDK.ChainedAt
          ([])
          (
            [ SDK.ChainedAt
                ([0])
                (
                  [ SDK.NodeAt ([0,0]) ("PrepareProbe")
                  ]
                )
            , SDK.ParallelAt
                ([1])
                (
                  [ SDK.NodeAt ([1,0]) ("WriteFirst")
                  , SDK.NodeAt ([1,1]) ("WriteSecond")
                  , SDK.NodeAt ([1,2]) ("WriteThird")
                  ]
                )
            , SDK.ChainedAt
                ([2])
                (
                  [ SDK.NodeAt ([2,0]) ("VerifyReuse")
                  ]
                )
            ]
          )
    , SDK.protoSessions = []
    , SDK.protoChains =
        [ SDK.ChainProto
            { SDK.chainNode = [0,0]
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
                [ RunWriteFirstGen
                , GetFilePathsGen
                , OpenSharedFileScopeGen
                , GetOpenedFileGen
                , ReadFilePathsGen
                , ReadOpenedFileGen
                ]
            , SDK.chainDrives = ["FilePaths"]
            , SDK.chainReads = []
            , SDK.chainScopePaths = [[OpenSharedFileScopeGen]]
            }
        , SDK.ChainProto
            { SDK.chainNode = [1,1]
            , SDK.chainRole = SDK.NodeChain
            , SDK.chainTerminal = "WriteSecond"
            , SDK.chainEntry = RunWriteSecondGen
            , SDK.chainReaches =
                [ RunWriteSecondGen
                , GetFilePathsGen
                , OpenSharedFileScopeGen
                , GetOpenedFileGen
                , ReadFilePathsGen
                , ReadOpenedFileGen
                ]
            , SDK.chainDrives = ["FilePaths"]
            , SDK.chainReads = []
            , SDK.chainScopePaths = [[OpenSharedFileScopeGen]]
            }
        , SDK.ChainProto
            { SDK.chainNode = [1,2]
            , SDK.chainRole = SDK.NodeChain
            , SDK.chainTerminal = "WriteThird"
            , SDK.chainEntry = RunWriteThirdGen
            , SDK.chainReaches =
                [ RunWriteThirdGen
                , GetFilePathsGen
                , OpenSharedFileScopeGen
                , GetOpenedFileGen
                , ReadFilePathsGen
                , ReadOpenedFileGen
                ]
            , SDK.chainDrives = ["FilePaths"]
            , SDK.chainReads = []
            , SDK.chainScopePaths = [[OpenSharedFileScopeGen]]
            }
        , SDK.ChainProto
            { SDK.chainNode = [2,0]
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
            , SDK.definitionReaches = [ReadFilePathsGen, GetFilePathsGen]
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
            , SDK.definitionReaches = [GetOpenedFileGen, ReadFilePathsGen, GetFilePathsGen]
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
                [OpenSharedFileScopeGen, GetOpenedFileGen, ReadFilePathsGen, GetFilePathsGen, ReadOpenedFileGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.OriginChain
            , SDK.definitionEffect = "WriteFirst"
            , SDK.definitionEntry = RunWriteFirstGen
            , SDK.definitionReaches =
                [ RunWriteFirstGen
                , GetFilePathsGen
                , OpenSharedFileScopeGen
                , GetOpenedFileGen
                , ReadFilePathsGen
                , ReadOpenedFileGen
                ]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.OriginChain
            , SDK.definitionEffect = "WriteSecond"
            , SDK.definitionEntry = RunWriteSecondGen
            , SDK.definitionReaches =
                [ RunWriteSecondGen
                , GetFilePathsGen
                , OpenSharedFileScopeGen
                , GetOpenedFileGen
                , ReadFilePathsGen
                , ReadOpenedFileGen
                ]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.OriginChain
            , SDK.definitionEffect = "WriteThird"
            , SDK.definitionEntry = RunWriteThirdGen
            , SDK.definitionReaches =
                [ RunWriteThirdGen
                , GetFilePathsGen
                , OpenSharedFileScopeGen
                , GetOpenedFileGen
                , ReadFilePathsGen
                , ReadOpenedFileGen
                ]
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
                  (RunPrepareProbeGen)
                  (RunPrepareProbeGen)
                  (SDK.HandlerMethod)
                  (SDK.Sequence ([SDK.Call (GetFilePathsGen), SDK.Call (ReadFilePathsGen)]))
              , SDK.MethodDefinition (GetFilePathsGen) (GetFilePathsGen) (SDK.ContextRequest) (SDK.Empty)
              , SDK.MethodDefinition
                  (ReadFilePathsGen)
                  (GetFilePathsGen)
                  (SDK.ContextRequire)
                  (SDK.Choice ([SDK.Empty, SDK.Call (GetFilePathsGen)]))
              , SDK.MethodDefinition
                  (RunWriteFirstGen)
                  (RunWriteFirstGen)
                  (SDK.HandlerMethod)
                  (
                    SDK.Sequence
                      ([SDK.Call (GetFilePathsGen), SDK.Call (OpenSharedFileScopeGen), SDK.Call (ReadOpenedFileGen)])
                  )
              , SDK.MethodDefinition
                  (OpenSharedFileScopeGen)
                  (OpenSharedFileScopeGen)
                  (SDK.ScopeOpen)
                  (SDK.Sequence ([SDK.Call (GetOpenedFileGen), SDK.Call (ReadOpenedFileGen)]))
              , SDK.MethodDefinition
                  (GetOpenedFileGen)
                  (GetOpenedFileGen)
                  (SDK.ContextRequest)
                  (SDK.Call (ReadFilePathsGen))
              , SDK.MethodDefinition (ReadOpenedFileGen) (GetOpenedFileGen) (SDK.ContextRequire) (SDK.Empty)
              , SDK.MethodDefinition
                  (RunWriteSecondGen)
                  (RunWriteSecondGen)
                  (SDK.HandlerMethod)
                  (
                    SDK.Sequence
                      ([SDK.Call (GetFilePathsGen), SDK.Call (OpenSharedFileScopeGen), SDK.Call (ReadOpenedFileGen)])
                  )
              , SDK.MethodDefinition
                  (RunWriteThirdGen)
                  (RunWriteThirdGen)
                  (SDK.HandlerMethod)
                  (
                    SDK.Sequence
                      ([SDK.Call (GetFilePathsGen), SDK.Call (OpenSharedFileScopeGen), SDK.Call (ReadOpenedFileGen)])
                  )
              , SDK.MethodDefinition
                  (RunVerifyReuseGen)
                  (RunVerifyReuseGen)
                  (SDK.HandlerMethod)
                  (SDK.Sequence ([SDK.Call (GetFilePathsGen), SDK.Call (ReadFilePathsGen)]))
              ]
          , SDK.graphRoots =
              [RunPrepareProbeGen, RunWriteFirstGen, RunWriteSecondGen, RunWriteThirdGen, RunVerifyReuseGen]
          , SDK.graphReferences =
              [ (RunPrepareProbeGen, GetFilePathsGen)
              , (RunPrepareProbeGen, ReadFilePathsGen)
              , (ReadFilePathsGen, GetFilePathsGen)
              , (RunWriteFirstGen, GetFilePathsGen)
              , (RunWriteFirstGen, OpenSharedFileScopeGen)
              , (RunWriteFirstGen, ReadOpenedFileGen)
              , (OpenSharedFileScopeGen, GetOpenedFileGen)
              , (OpenSharedFileScopeGen, ReadOpenedFileGen)
              , (GetOpenedFileGen, ReadFilePathsGen)
              , (RunWriteSecondGen, GetFilePathsGen)
              , (RunWriteSecondGen, OpenSharedFileScopeGen)
              , (RunWriteSecondGen, ReadOpenedFileGen)
              , (RunWriteThirdGen, GetFilePathsGen)
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
    , SDK.protoSources = []
    }
