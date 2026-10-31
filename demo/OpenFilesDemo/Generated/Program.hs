{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE TypeFamilies #-}

-- 自动生成；只登记末端句柄，Node algebra 才 lower，业务组合仍在 handler 内。
module OpenFilesDemo.Generated.Program where

import Framework.SDK (Effect(..), EffectSpec(..), EffectTyping(..), Requester(..), Handles(..), Demand(..), Access(..), TypeRef(..))
import qualified Framework.SDK as SDK
import qualified Framework.Effect.Contract as FrameworkRoot
import OpenFilesDemo.Generated.Effects hiding (request, require)
import qualified OpenFilesDemo.Generated.Handlers as Handlers
import OpenFilesDemo.Types


-- 仅汇总所选末端的成功产物，不保存共享绑定或增加完成包装。
data Results = HoldFilesResult (Produce HoldFiles) | InspectFilesResult (Produce InspectFiles) | FinishInspectionResult (Produce FinishInspection)
  deriving Show

-- 末端共享生成的 scope 句柄；只创建空状态，Node algebra 才 lower，业务调用仍在 instance 内。
-- 第二个列表是各转折契约的读取末端：按 require 取得资产，返回它当前的构造器名。
compiledEntries :: IO ([SDK.Target ContextValues Errors Results], [SDK.Target ContextValues Errors String])
compiledEntries = do
  scopes <- Handlers.newScopeHandlers
  pure
    ( [ SDK.targetApp "HoldFiles" emptyContexts scopes (FrameworkRoot.withErrorHandlers Handlers.errorHandlers (FrameworkRoot.withAnchoredContexts Handlers.contextInjections (SDK.withScopeCleanups Handlers.scopeCleanups (HoldFilesResult <$> (() <$ holdFiles)))))
      , SDK.targetApp "InspectFiles" emptyContexts scopes (FrameworkRoot.withErrorHandlers Handlers.errorHandlers (FrameworkRoot.withAnchoredContexts Handlers.contextInjections (SDK.withScopeCleanups Handlers.scopeCleanups (InspectFilesResult <$> (() <$ inspectFiles)))))
      , SDK.targetApp "FinishInspection" emptyContexts scopes (FrameworkRoot.withErrorHandlers Handlers.errorHandlers (FrameworkRoot.withAnchoredContexts Handlers.contextInjections (SDK.withScopeCleanups Handlers.scopeCleanups (FinishInspectionResult <$> (() <$ finishInspection)))))
      ]
    , []
    )

-- SDK 装配入口，不需要用户提供节点执行器或重复选择 handler。
interpreter :: SDK.AST -> [EffectSpec] -> IO ()
interpreter = SDK.interpreter "OpenFilesDemo" Handlers.handlerSourceFingerprint generatedPrototype compiledEntries
-- 生成时完成注册、方法、origin/ctx 链、Workflow 和 scope 的统一分析。
-- NodeId 只在这份 AST 快照中有效；运行时校验后装配闭包。
generatedPrototype :: SDK.Prototype MethodGen
generatedPrototype =
  SDK.Prototype
    { SDK.protoRegistrations =
        [ SDK.EffectSpec
            { SDK.name = "FileLocations"
            , SDK.typing = SDK.Context (Just (SDK.Requester ("fileNames") (SDK.TypeRef ("[[Char]]"))))
            , SDK.input = "Root"
            , SDK.demands = []
            }
        , SDK.EffectSpec
            { SDK.name = "FileResources"
            , SDK.typing = SDK.Context (Just (SDK.Requester ("openedFiles") (SDK.TypeRef ("[FileHandle]"))))
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
            { SDK.name = "FinishInspection"
            , SDK.typing = SDK.Excu (Just "finishInspection")
            , SDK.input = "InspectFiles"
            , SDK.demands = [SDK.Demand (SDK.RequireAccess) ("OpenedFiles")]
            }
        ]
    , SDK.protoEffects =
        [ SDK.EffectProto
            { SDK.effectName = "FileLocations"
            , SDK.effectKind = SDK.ContextKind
            , SDK.effectInput = "Root"
            , SDK.effectMethods = [(SDK.ContextRequest, FileNamesGen), (SDK.ContextRequire, ReadFileNamesGen)]
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
            }
        , SDK.EffectProto
            { SDK.effectName = "FileResources"
            , SDK.effectKind = SDK.ContextKind
            , SDK.effectInput = "Root"
            , SDK.effectMethods =
                [(SDK.ContextRequest, OpenedFilesGen), (SDK.ContextRequire, ReadOpenedFilesGen)]
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
            }
        , SDK.EffectProto
            { SDK.effectName = "FileSession"
            , SDK.effectKind = SDK.ScopedKind
            , SDK.effectInput = "Root"
            , SDK.effectMethods = [(SDK.ScopeOpen, OpenFilesGen), (SDK.ScopeClose, CloseFilesGen)]
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
            }
        , SDK.EffectProto
            { SDK.effectName = "HoldFiles"
            , SDK.effectKind = SDK.ExcuKind
            , SDK.effectInput = "FileSession"
            , SDK.effectMethods = [(SDK.HandlerMethod, HoldFilesGen)]
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
            }
        , SDK.EffectProto
            { SDK.effectName = "InspectFiles"
            , SDK.effectKind = SDK.ExcuKind
            , SDK.effectInput = "HoldFiles"
            , SDK.effectMethods = [(SDK.HandlerMethod, InspectFilesGen)]
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
            }
        , SDK.EffectProto
            { SDK.effectName = "FinishInspection"
            , SDK.effectKind = SDK.ExcuKind
            , SDK.effectInput = "InspectFiles"
            , SDK.effectMethods = [(SDK.HandlerMethod, FinishInspectionGen)]
            , SDK.effectDemands = [SDK.ResolvedDemand (SDK.RequireAccess) ("OpenedFiles") ("FileResources")]
            , SDK.effectProduces = Nothing
            , SDK.effectBranches = []
            , SDK.effectAnchor = Nothing
            , SDK.effectScopes = ["FileSession"]
            , SDK.effectErrorScope = Nothing
            , SDK.effectInputChain = ["InspectFiles","HoldFiles","FileSession"]
            , SDK.effectScopeParents = ["FileSession"]
            , SDK.effectOpeningInputs = []
            , SDK.effectNearestScopes = ["FileSession"]
            , SDK.effectResource = Nothing
            , SDK.effectContextDependencies = ["FileLocations","FileResources"]
            }
        ]
    , SDK.protoMethods =
        [ SDK.MethodDefinition (FileNamesGen) (FileNamesGen) (SDK.ContextRequest) (SDK.Empty)
        , SDK.MethodDefinition
            (ReadFileNamesGen)
            (FileNamesGen)
            (SDK.ContextRequire)
            (SDK.Choice ([SDK.Empty, SDK.Call (FileNamesGen)]))
        , SDK.MethodDefinition
            (OpenedFilesGen)
            (OpenedFilesGen)
            (SDK.ContextRequest)
            (SDK.Call (ReadFileNamesGen))
        , SDK.MethodDefinition (ReadOpenedFilesGen) (OpenedFilesGen) (SDK.ContextRequire) (SDK.Empty)
        , SDK.MethodDefinition (OpenFilesGen) (OpenFilesGen) (SDK.ScopeOpen) (SDK.Call (OpenedFilesGen))
        , SDK.MethodDefinition (CloseFilesGen) (OpenFilesGen) (SDK.ScopeClose) (SDK.Call (ReadOpenedFilesGen))
        , SDK.MethodDefinition
            (HoldFilesGen)
            (HoldFilesGen)
            (SDK.HandlerMethod)
            (SDK.Sequence ([SDK.Call (FileNamesGen), SDK.Call (OpenFilesGen)]))
        , SDK.MethodDefinition
            (InspectFilesGen)
            (InspectFilesGen)
            (SDK.HandlerMethod)
            (SDK.Sequence ([SDK.Call (HoldFilesGen), SDK.Call (ReadOpenedFilesGen)]))
        , SDK.MethodDefinition
            (FinishInspectionGen)
            (FinishInspectionGen)
            (SDK.HandlerMethod)
            (SDK.Sequence ([SDK.Call (HoldFilesGen), SDK.Call (ReadOpenedFilesGen), SDK.Call (CloseFilesGen)]))
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
                  [ SDK.NodeAt ([1,0]) ("FinishInspection")
                  ]
                )
            ]
          )
    , SDK.protoChains =
        [ SDK.ChainProto
            { SDK.chainNode = [0,0]
            , SDK.chainRole = SDK.NodeChain
            , SDK.chainTerminal = "HoldFiles"
            , SDK.chainEntry = HoldFilesGen
            , SDK.chainReaches = [HoldFilesGen, FileNamesGen, OpenFilesGen, OpenedFilesGen, ReadFileNamesGen]
            , SDK.chainDrives = []
            , SDK.chainReads = []
            , SDK.chainScopePaths = [[OpenFilesGen]]
            }
        , SDK.ChainProto
            { SDK.chainNode = [0,1]
            , SDK.chainRole = SDK.NodeChain
            , SDK.chainTerminal = "InspectFiles"
            , SDK.chainEntry = InspectFilesGen
            , SDK.chainReaches =
                [ InspectFilesGen
                , HoldFilesGen
                , FileNamesGen
                , OpenFilesGen
                , OpenedFilesGen
                , ReadFileNamesGen
                , ReadOpenedFilesGen
                ]
            , SDK.chainDrives = []
            , SDK.chainReads = []
            , SDK.chainScopePaths = [[OpenFilesGen]]
            }
        , SDK.ChainProto
            { SDK.chainNode = [1,0]
            , SDK.chainRole = SDK.NodeChain
            , SDK.chainTerminal = "FinishInspection"
            , SDK.chainEntry = FinishInspectionGen
            , SDK.chainReaches =
                [ FinishInspectionGen
                , HoldFilesGen
                , FileNamesGen
                , OpenFilesGen
                , OpenedFilesGen
                , ReadFileNamesGen
                , ReadOpenedFilesGen
                , CloseFilesGen
                ]
            , SDK.chainDrives = []
            , SDK.chainReads = []
            , SDK.chainScopePaths = [[OpenFilesGen]]
            }
        ]
    , SDK.protoChainDefinitions =
        [ SDK.ChainDefinition
            { SDK.definitionKind = SDK.ContextChain
            , SDK.definitionEffect = "FileLocations"
            , SDK.definitionEntry = FileNamesGen
            , SDK.definitionReaches = [FileNamesGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.ContextChain
            , SDK.definitionEffect = "FileLocations"
            , SDK.definitionEntry = ReadFileNamesGen
            , SDK.definitionReaches = [ReadFileNamesGen, FileNamesGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.ContextChain
            , SDK.definitionEffect = "FileResources"
            , SDK.definitionEntry = OpenedFilesGen
            , SDK.definitionReaches = [OpenedFilesGen, ReadFileNamesGen, FileNamesGen]
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
            , SDK.definitionEntry = OpenFilesGen
            , SDK.definitionReaches = [OpenFilesGen, OpenedFilesGen, ReadFileNamesGen, FileNamesGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.OriginChain
            , SDK.definitionEffect = "HoldFiles"
            , SDK.definitionEntry = HoldFilesGen
            , SDK.definitionReaches =
                [HoldFilesGen, FileNamesGen, OpenFilesGen, OpenedFilesGen, ReadFileNamesGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.OriginChain
            , SDK.definitionEffect = "InspectFiles"
            , SDK.definitionEntry = InspectFilesGen
            , SDK.definitionReaches =
                [ InspectFilesGen
                , HoldFilesGen
                , FileNamesGen
                , OpenFilesGen
                , OpenedFilesGen
                , ReadFileNamesGen
                , ReadOpenedFilesGen
                ]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.OriginChain
            , SDK.definitionEffect = "FinishInspection"
            , SDK.definitionEntry = FinishInspectionGen
            , SDK.definitionReaches =
                [ FinishInspectionGen
                , HoldFilesGen
                , FileNamesGen
                , OpenFilesGen
                , OpenedFilesGen
                , ReadFileNamesGen
                , ReadOpenedFilesGen
                , CloseFilesGen
                ]
            }
        ]
    , SDK.protoGraph =
        SDK.EffectGraph
          { SDK.graphMethods =
              [ SDK.MethodDefinition
                  (HoldFilesGen)
                  (HoldFilesGen)
                  (SDK.HandlerMethod)
                  (SDK.Sequence ([SDK.Call (FileNamesGen), SDK.Call (OpenFilesGen)]))
              , SDK.MethodDefinition (FileNamesGen) (FileNamesGen) (SDK.ContextRequest) (SDK.Empty)
              , SDK.MethodDefinition (OpenFilesGen) (OpenFilesGen) (SDK.ScopeOpen) (SDK.Call (OpenedFilesGen))
              , SDK.MethodDefinition
                  (OpenedFilesGen)
                  (OpenedFilesGen)
                  (SDK.ContextRequest)
                  (SDK.Call (ReadFileNamesGen))
              , SDK.MethodDefinition
                  (ReadFileNamesGen)
                  (FileNamesGen)
                  (SDK.ContextRequire)
                  (SDK.Choice ([SDK.Empty, SDK.Call (FileNamesGen)]))
              , SDK.MethodDefinition
                  (InspectFilesGen)
                  (InspectFilesGen)
                  (SDK.HandlerMethod)
                  (SDK.Sequence ([SDK.Call (HoldFilesGen), SDK.Call (ReadOpenedFilesGen)]))
              , SDK.MethodDefinition (ReadOpenedFilesGen) (OpenedFilesGen) (SDK.ContextRequire) (SDK.Empty)
              , SDK.MethodDefinition
                  (FinishInspectionGen)
                  (FinishInspectionGen)
                  (SDK.HandlerMethod)
                  (SDK.Sequence ([SDK.Call (HoldFilesGen), SDK.Call (ReadOpenedFilesGen), SDK.Call (CloseFilesGen)]))
              , SDK.MethodDefinition (CloseFilesGen) (OpenFilesGen) (SDK.ScopeClose) (SDK.Call (ReadOpenedFilesGen))
              ]
          , SDK.graphRoots = [HoldFilesGen, InspectFilesGen, FinishInspectionGen]
          , SDK.graphReferences =
              [ (HoldFilesGen, FileNamesGen)
              , (HoldFilesGen, OpenFilesGen)
              , (OpenFilesGen, OpenedFilesGen)
              , (OpenedFilesGen, ReadFileNamesGen)
              , (ReadFileNamesGen, FileNamesGen)
              , (InspectFilesGen, HoldFilesGen)
              , (InspectFilesGen, ReadOpenedFilesGen)
              , (FinishInspectionGen, HoldFilesGen)
              , (FinishInspectionGen, ReadOpenedFilesGen)
              , (FinishInspectionGen, CloseFilesGen)
              , (CloseFilesGen, ReadOpenedFilesGen)
              ]
          , SDK.graphScopes = [OpenFilesGen]
          , SDK.graphScopePaths = [[OpenFilesGen]]
          , SDK.graphRootPaths =
              [ (HoldFilesGen, [[OpenFilesGen]])
              , (InspectFilesGen, [[OpenFilesGen]])
              , (FinishInspectionGen, [[OpenFilesGen]])
              ]
          , SDK.graphScopeOrder = []
          }
    , SDK.protoScopes =
        SDK.ScopeTree
          { SDK.scopeRoots = [OpenFilesGen]
          , SDK.scopeNodes =
              [ SDK.ScopeNode
                  { SDK.scopeIdentity = OpenFilesGen
                  , SDK.scopeParents = []
                  , SDK.scopeChildren = []
                  }
              ]
          , SDK.scopeLayers = [[OpenFilesGen]]
          , SDK.scopePaths = [[OpenFilesGen]]
          , SDK.scopeCandidates = []
          , SDK.scopeOpposed = []
          , SDK.scopeUndetermined = []
          }
    , SDK.protoScopeNames = [(OpenFilesGen, "FileSession")]
    , SDK.protoSources = []
    }
