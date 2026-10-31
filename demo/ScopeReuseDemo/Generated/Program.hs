{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE TypeFamilies #-}

-- 自动生成；只登记末端句柄，Node algebra 才 lower，业务组合仍在 handler 内。
module ScopeReuseDemo.Generated.Program where

import Framework.SDK (Effect(..), EffectSpec(..), EffectTyping(..), Requester(..), Handles(..), Demand(..), Access(..), TypeRef(..))
import qualified Framework.SDK as SDK
import qualified Framework.Effect.Contract as FrameworkRoot
import ScopeReuseDemo.Generated.Effects hiding (request, require)
import qualified ScopeReuseDemo.Generated.Handlers as Handlers
import ScopeReuseDemo.Types


-- 仅汇总所选末端的成功产物，不保存共享绑定或增加完成包装。
data Results = PrepareProbeResult (Produce PrepareProbe) | WriteFirstResult (Produce WriteFirst) | WriteSecondResult (Produce WriteSecond) | WriteThirdResult (Produce WriteThird) | VerifyReuseResult (Produce VerifyReuse)
  deriving Show

-- 末端共享生成的 scope 句柄；只创建空状态，Node algebra 才 lower，业务调用仍在 instance 内。
-- 第二个列表是各转折契约的读取末端：按 require 取得资产，返回它当前的构造器名。
compiledEntries :: IO ([SDK.Target ContextValues Errors Results], [SDK.Target ContextValues Errors String])
compiledEntries = do
  scopes <- Handlers.newScopeHandlers
  pure
    ( [ SDK.targetApp "PrepareProbe" emptyContexts scopes (FrameworkRoot.withErrorHandlers Handlers.errorHandlers (FrameworkRoot.withAnchoredContexts Handlers.contextInjections (SDK.withScopeCleanups Handlers.scopeCleanups (PrepareProbeResult <$> (() <$ prepareProbe)))))
      , SDK.targetApp "WriteFirst" emptyContexts scopes (FrameworkRoot.withErrorHandlers Handlers.errorHandlers (FrameworkRoot.withAnchoredContexts Handlers.contextInjections (SDK.withScopeCleanups Handlers.scopeCleanups (WriteFirstResult <$> (() <$ writeFirst)))))
      , SDK.targetApp "WriteSecond" emptyContexts scopes (FrameworkRoot.withErrorHandlers Handlers.errorHandlers (FrameworkRoot.withAnchoredContexts Handlers.contextInjections (SDK.withScopeCleanups Handlers.scopeCleanups (WriteSecondResult <$> (() <$ writeSecond)))))
      , SDK.targetApp "WriteThird" emptyContexts scopes (FrameworkRoot.withErrorHandlers Handlers.errorHandlers (FrameworkRoot.withAnchoredContexts Handlers.contextInjections (SDK.withScopeCleanups Handlers.scopeCleanups (WriteThirdResult <$> (() <$ writeThird)))))
      , SDK.targetApp "VerifyReuse" emptyContexts scopes (FrameworkRoot.withErrorHandlers Handlers.errorHandlers (FrameworkRoot.withAnchoredContexts Handlers.contextInjections (SDK.withScopeCleanups Handlers.scopeCleanups (VerifyReuseResult <$> (() <$ verifyReuse)))))
      ]
    , []
    )

-- SDK 装配入口，不需要用户提供节点执行器或重复选择 handler。
interpreter :: SDK.AST -> [EffectSpec] -> IO ()
interpreter = SDK.interpreter "ScopeReuseDemo" Handlers.handlerSourceFingerprint generatedPrototype compiledEntries
-- 生成时完成注册、方法、origin/ctx 链、Workflow 和 scope 的统一分析。
-- NodeId 只在这份 AST 快照中有效；运行时校验后装配闭包。
generatedPrototype :: SDK.Prototype MethodGen
generatedPrototype =
  SDK.Prototype
    { SDK.protoRegistrations =
        [ SDK.EffectSpec
            { SDK.name = "FileLocations"
            , SDK.typing = SDK.Context (Just (SDK.Requester ("filePaths") (SDK.TypeRef ("SharedPaths"))))
            , SDK.input = "Root"
            , SDK.demands = []
            }
        , SDK.EffectSpec
            { SDK.name = "PrepareProbe"
            , SDK.typing = SDK.Excu (Just "prepareProbe")
            , SDK.input = "Root"
            , SDK.demands = [SDK.Demand (SDK.RequestAccess) ("FilePaths")]
            }
        , SDK.EffectSpec
            { SDK.name = "FileResource"
            , SDK.typing = SDK.Context (Just (SDK.Requester ("openedFile") (SDK.TypeRef ("SharedFile"))))
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
            , SDK.demands = [SDK.Demand (SDK.RequestAccess) ("FilePaths")]
            }
        ]
    , SDK.protoEffects =
        [ SDK.EffectProto
            { SDK.effectName = "FileLocations"
            , SDK.effectKind = SDK.ContextKind
            , SDK.effectInput = "Root"
            , SDK.effectMethods = [(SDK.ContextRequest, FilePathsGen), (SDK.ContextRequire, ReadFilePathsGen)]
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
            }
        , SDK.EffectProto
            { SDK.effectName = "PrepareProbe"
            , SDK.effectKind = SDK.ExcuKind
            , SDK.effectInput = "Root"
            , SDK.effectMethods = [(SDK.HandlerMethod, PrepareProbeGen)]
            , SDK.effectDemands = [SDK.ResolvedDemand (SDK.RequestAccess) ("FilePaths") ("FileLocations")]
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
            }
        , SDK.EffectProto
            { SDK.effectName = "FileResource"
            , SDK.effectKind = SDK.ContextKind
            , SDK.effectInput = "Root"
            , SDK.effectMethods =
                [(SDK.ContextRequest, OpenedFileGen), (SDK.ContextRequire, ReadOpenedFileGen)]
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
            }
        , SDK.EffectProto
            { SDK.effectName = "SharedFileScope"
            , SDK.effectKind = SDK.ScopedKind
            , SDK.effectInput = "Root"
            , SDK.effectMethods = [(SDK.ScopeOpen, OpenSharedFileGen), (SDK.ScopeClose, CloseSharedFileGen)]
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
            }
        , SDK.EffectProto
            { SDK.effectName = "WriteFirst"
            , SDK.effectKind = SDK.ExcuKind
            , SDK.effectInput = "SharedFileScope"
            , SDK.effectMethods = [(SDK.HandlerMethod, WriteFirstGen)]
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
            }
        , SDK.EffectProto
            { SDK.effectName = "WriteSecond"
            , SDK.effectKind = SDK.ExcuKind
            , SDK.effectInput = "SharedFileScope"
            , SDK.effectMethods = [(SDK.HandlerMethod, WriteSecondGen)]
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
            }
        , SDK.EffectProto
            { SDK.effectName = "WriteThird"
            , SDK.effectKind = SDK.ExcuKind
            , SDK.effectInput = "SharedFileScope"
            , SDK.effectMethods = [(SDK.HandlerMethod, WriteThirdGen)]
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
            }
        , SDK.EffectProto
            { SDK.effectName = "VerifyReuse"
            , SDK.effectKind = SDK.ExcuKind
            , SDK.effectInput = "Root"
            , SDK.effectMethods = [(SDK.HandlerMethod, VerifyReuseGen)]
            , SDK.effectDemands = [SDK.ResolvedDemand (SDK.RequestAccess) ("FilePaths") ("FileLocations")]
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
            }
        ]
    , SDK.protoMethods =
        [ SDK.MethodDefinition (FilePathsGen) (FilePathsGen) (SDK.ContextRequest) (SDK.Empty)
        , SDK.MethodDefinition
            (ReadFilePathsGen)
            (FilePathsGen)
            (SDK.ContextRequire)
            (SDK.Choice ([SDK.Empty, SDK.Call (FilePathsGen)]))
        , SDK.MethodDefinition
            (PrepareProbeGen)
            (PrepareProbeGen)
            (SDK.HandlerMethod)
            (SDK.Call (FilePathsGen))
        , SDK.MethodDefinition
            (OpenedFileGen)
            (OpenedFileGen)
            (SDK.ContextRequest)
            (SDK.Call (ReadFilePathsGen))
        , SDK.MethodDefinition (ReadOpenedFileGen) (OpenedFileGen) (SDK.ContextRequire) (SDK.Empty)
        , SDK.MethodDefinition
            (OpenSharedFileGen)
            (OpenSharedFileGen)
            (SDK.ScopeOpen)
            (SDK.Call (OpenedFileGen))
        , SDK.MethodDefinition
            (CloseSharedFileGen)
            (OpenSharedFileGen)
            (SDK.ScopeClose)
            (SDK.Call (ReadOpenedFileGen))
        , SDK.MethodDefinition
            (WriteFirstGen)
            (WriteFirstGen)
            (SDK.HandlerMethod)
            (SDK.Sequence ([SDK.Call (FilePathsGen), SDK.Call (OpenSharedFileGen), SDK.Call (ReadOpenedFileGen)]))
        , SDK.MethodDefinition
            (WriteSecondGen)
            (WriteSecondGen)
            (SDK.HandlerMethod)
            (SDK.Sequence ([SDK.Call (FilePathsGen), SDK.Call (OpenSharedFileGen), SDK.Call (ReadOpenedFileGen)]))
        , SDK.MethodDefinition
            (WriteThirdGen)
            (WriteThirdGen)
            (SDK.HandlerMethod)
            (SDK.Sequence ([SDK.Call (FilePathsGen), SDK.Call (OpenSharedFileGen), SDK.Call (ReadOpenedFileGen)]))
        , SDK.MethodDefinition (VerifyReuseGen) (VerifyReuseGen) (SDK.HandlerMethod) (SDK.Call (FilePathsGen))
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
    , SDK.protoChains =
        [ SDK.ChainProto
            { SDK.chainNode = [0,0]
            , SDK.chainRole = SDK.NodeChain
            , SDK.chainTerminal = "PrepareProbe"
            , SDK.chainEntry = PrepareProbeGen
            , SDK.chainReaches = [PrepareProbeGen, FilePathsGen]
            , SDK.chainDrives = []
            , SDK.chainReads = []
            , SDK.chainScopePaths = [[]]
            }
        , SDK.ChainProto
            { SDK.chainNode = [1,0]
            , SDK.chainRole = SDK.NodeChain
            , SDK.chainTerminal = "WriteFirst"
            , SDK.chainEntry = WriteFirstGen
            , SDK.chainReaches =
                [WriteFirstGen, FilePathsGen, OpenSharedFileGen, OpenedFileGen, ReadFilePathsGen, ReadOpenedFileGen]
            , SDK.chainDrives = []
            , SDK.chainReads = []
            , SDK.chainScopePaths = [[OpenSharedFileGen]]
            }
        , SDK.ChainProto
            { SDK.chainNode = [1,1]
            , SDK.chainRole = SDK.NodeChain
            , SDK.chainTerminal = "WriteSecond"
            , SDK.chainEntry = WriteSecondGen
            , SDK.chainReaches =
                [ WriteSecondGen
                , FilePathsGen
                , OpenSharedFileGen
                , OpenedFileGen
                , ReadFilePathsGen
                , ReadOpenedFileGen
                ]
            , SDK.chainDrives = []
            , SDK.chainReads = []
            , SDK.chainScopePaths = [[OpenSharedFileGen]]
            }
        , SDK.ChainProto
            { SDK.chainNode = [1,2]
            , SDK.chainRole = SDK.NodeChain
            , SDK.chainTerminal = "WriteThird"
            , SDK.chainEntry = WriteThirdGen
            , SDK.chainReaches =
                [WriteThirdGen, FilePathsGen, OpenSharedFileGen, OpenedFileGen, ReadFilePathsGen, ReadOpenedFileGen]
            , SDK.chainDrives = []
            , SDK.chainReads = []
            , SDK.chainScopePaths = [[OpenSharedFileGen]]
            }
        , SDK.ChainProto
            { SDK.chainNode = [2,0]
            , SDK.chainRole = SDK.NodeChain
            , SDK.chainTerminal = "VerifyReuse"
            , SDK.chainEntry = VerifyReuseGen
            , SDK.chainReaches = [VerifyReuseGen, FilePathsGen]
            , SDK.chainDrives = []
            , SDK.chainReads = []
            , SDK.chainScopePaths = [[]]
            }
        ]
    , SDK.protoChainDefinitions =
        [ SDK.ChainDefinition
            { SDK.definitionKind = SDK.ContextChain
            , SDK.definitionEffect = "FileLocations"
            , SDK.definitionEntry = FilePathsGen
            , SDK.definitionReaches = [FilePathsGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.ContextChain
            , SDK.definitionEffect = "FileLocations"
            , SDK.definitionEntry = ReadFilePathsGen
            , SDK.definitionReaches = [ReadFilePathsGen, FilePathsGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.OriginChain
            , SDK.definitionEffect = "PrepareProbe"
            , SDK.definitionEntry = PrepareProbeGen
            , SDK.definitionReaches = [PrepareProbeGen, FilePathsGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.ContextChain
            , SDK.definitionEffect = "FileResource"
            , SDK.definitionEntry = OpenedFileGen
            , SDK.definitionReaches = [OpenedFileGen, ReadFilePathsGen, FilePathsGen]
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
            , SDK.definitionEntry = OpenSharedFileGen
            , SDK.definitionReaches = [OpenSharedFileGen, OpenedFileGen, ReadFilePathsGen, FilePathsGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.OriginChain
            , SDK.definitionEffect = "WriteFirst"
            , SDK.definitionEntry = WriteFirstGen
            , SDK.definitionReaches =
                [WriteFirstGen, FilePathsGen, OpenSharedFileGen, OpenedFileGen, ReadFilePathsGen, ReadOpenedFileGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.OriginChain
            , SDK.definitionEffect = "WriteSecond"
            , SDK.definitionEntry = WriteSecondGen
            , SDK.definitionReaches =
                [ WriteSecondGen
                , FilePathsGen
                , OpenSharedFileGen
                , OpenedFileGen
                , ReadFilePathsGen
                , ReadOpenedFileGen
                ]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.OriginChain
            , SDK.definitionEffect = "WriteThird"
            , SDK.definitionEntry = WriteThirdGen
            , SDK.definitionReaches =
                [WriteThirdGen, FilePathsGen, OpenSharedFileGen, OpenedFileGen, ReadFilePathsGen, ReadOpenedFileGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.OriginChain
            , SDK.definitionEffect = "VerifyReuse"
            , SDK.definitionEntry = VerifyReuseGen
            , SDK.definitionReaches = [VerifyReuseGen, FilePathsGen]
            }
        ]
    , SDK.protoGraph =
        SDK.EffectGraph
          { SDK.graphMethods =
              [ SDK.MethodDefinition
                  (PrepareProbeGen)
                  (PrepareProbeGen)
                  (SDK.HandlerMethod)
                  (SDK.Call (FilePathsGen))
              , SDK.MethodDefinition (FilePathsGen) (FilePathsGen) (SDK.ContextRequest) (SDK.Empty)
              , SDK.MethodDefinition
                  (WriteFirstGen)
                  (WriteFirstGen)
                  (SDK.HandlerMethod)
                  (SDK.Sequence ([SDK.Call (FilePathsGen), SDK.Call (OpenSharedFileGen), SDK.Call (ReadOpenedFileGen)]))
              , SDK.MethodDefinition
                  (OpenSharedFileGen)
                  (OpenSharedFileGen)
                  (SDK.ScopeOpen)
                  (SDK.Call (OpenedFileGen))
              , SDK.MethodDefinition
                  (OpenedFileGen)
                  (OpenedFileGen)
                  (SDK.ContextRequest)
                  (SDK.Call (ReadFilePathsGen))
              , SDK.MethodDefinition
                  (ReadFilePathsGen)
                  (FilePathsGen)
                  (SDK.ContextRequire)
                  (SDK.Choice ([SDK.Empty, SDK.Call (FilePathsGen)]))
              , SDK.MethodDefinition (ReadOpenedFileGen) (OpenedFileGen) (SDK.ContextRequire) (SDK.Empty)
              , SDK.MethodDefinition
                  (WriteSecondGen)
                  (WriteSecondGen)
                  (SDK.HandlerMethod)
                  (SDK.Sequence ([SDK.Call (FilePathsGen), SDK.Call (OpenSharedFileGen), SDK.Call (ReadOpenedFileGen)]))
              , SDK.MethodDefinition
                  (WriteThirdGen)
                  (WriteThirdGen)
                  (SDK.HandlerMethod)
                  (SDK.Sequence ([SDK.Call (FilePathsGen), SDK.Call (OpenSharedFileGen), SDK.Call (ReadOpenedFileGen)]))
              , SDK.MethodDefinition (VerifyReuseGen) (VerifyReuseGen) (SDK.HandlerMethod) (SDK.Call (FilePathsGen))
              ]
          , SDK.graphRoots = [PrepareProbeGen, WriteFirstGen, WriteSecondGen, WriteThirdGen, VerifyReuseGen]
          , SDK.graphReferences =
              [ (PrepareProbeGen, FilePathsGen)
              , (WriteFirstGen, FilePathsGen)
              , (WriteFirstGen, OpenSharedFileGen)
              , (WriteFirstGen, ReadOpenedFileGen)
              , (OpenSharedFileGen, OpenedFileGen)
              , (OpenedFileGen, ReadFilePathsGen)
              , (ReadFilePathsGen, FilePathsGen)
              , (WriteSecondGen, FilePathsGen)
              , (WriteSecondGen, OpenSharedFileGen)
              , (WriteSecondGen, ReadOpenedFileGen)
              , (WriteThirdGen, FilePathsGen)
              , (WriteThirdGen, OpenSharedFileGen)
              , (WriteThirdGen, ReadOpenedFileGen)
              , (VerifyReuseGen, FilePathsGen)
              ]
          , SDK.graphScopes = [OpenSharedFileGen]
          , SDK.graphScopePaths = [[], [OpenSharedFileGen]]
          , SDK.graphRootPaths =
              [ (PrepareProbeGen, [[]])
              , (WriteFirstGen, [[OpenSharedFileGen]])
              , (WriteSecondGen, [[OpenSharedFileGen]])
              , (WriteThirdGen, [[OpenSharedFileGen]])
              , (VerifyReuseGen, [[]])
              ]
          , SDK.graphScopeOrder = []
          }
    , SDK.protoScopes =
        SDK.ScopeTree
          { SDK.scopeRoots = [OpenSharedFileGen]
          , SDK.scopeNodes =
              [ SDK.ScopeNode
                  { SDK.scopeIdentity = OpenSharedFileGen
                  , SDK.scopeParents = []
                  , SDK.scopeChildren = []
                  }
              ]
          , SDK.scopeLayers = [[OpenSharedFileGen]]
          , SDK.scopePaths = [[], [OpenSharedFileGen]]
          , SDK.scopeCandidates = []
          , SDK.scopeOpposed = []
          , SDK.scopeUndetermined = []
          }
    , SDK.protoScopeNames = [(OpenSharedFileGen, "SharedFileScope")]
    , SDK.protoSources = []
    }
