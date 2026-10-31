{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE TypeFamilies #-}

-- 自动生成；只登记末端句柄，Node algebra 才 lower，业务组合仍在 handler 内。
module ScopeInstancesDemo.Generated.Program where

import Framework.SDK (Effect(..), EffectSpec(..), EffectTyping(..), Requester(..), Handles(..), Demand(..), Access(..), TypeRef(..))
import qualified Framework.SDK as SDK
import qualified Framework.Effect.Contract as FrameworkRoot
import ScopeInstancesDemo.Generated.Effects hiding (request, require)
import qualified ScopeInstancesDemo.Generated.Handlers as Handlers
import ScopeInstancesDemo.Types


-- 仅汇总所选末端的成功产物，不保存共享绑定或增加完成包装。
data Results = PrepareFilesResult (Produce PrepareFiles) | CheckIndependentResult (Produce CheckIndependent) | CheckReopenResult (Produce CheckReopen)
  deriving Show

-- 末端共享生成的 scope 句柄；只创建空状态，Node algebra 才 lower，业务调用仍在 instance 内。
-- 第二个列表是各转折契约的读取末端：按 require 取得资产，返回它当前的构造器名。
compiledEntries :: IO ([SDK.Target ContextValues Errors Results], [SDK.Target ContextValues Errors String])
compiledEntries = do
  scopes <- Handlers.newScopeHandlers
  pure
    ( [ SDK.targetApp "PrepareFiles" emptyContexts scopes (FrameworkRoot.withErrorHandlers Handlers.errorHandlers (FrameworkRoot.withAnchoredContexts Handlers.contextInjections (SDK.withScopeCleanups Handlers.scopeCleanups (PrepareFilesResult <$> (() <$ prepareFiles)))))
      , SDK.targetApp "CheckIndependent" emptyContexts scopes (FrameworkRoot.withErrorHandlers Handlers.errorHandlers (FrameworkRoot.withAnchoredContexts Handlers.contextInjections (SDK.withScopeCleanups Handlers.scopeCleanups (CheckIndependentResult <$> (() <$ checkIndependent)))))
      , SDK.targetApp "CheckReopen" emptyContexts scopes (FrameworkRoot.withErrorHandlers Handlers.errorHandlers (FrameworkRoot.withAnchoredContexts Handlers.contextInjections (SDK.withScopeCleanups Handlers.scopeCleanups (CheckReopenResult <$> (() <$ checkReopen)))))
      ]
    , []
    )

-- SDK 装配入口，不需要用户提供节点执行器或重复选择 handler。
interpreter :: SDK.AST -> [EffectSpec] -> IO ()
interpreter = SDK.interpreter "ScopeInstancesDemo" Handlers.handlerSourceFingerprint generatedPrototype compiledEntries
-- 生成时完成注册、方法、origin/ctx 链、Workflow 和 scope 的统一分析。
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
            , SDK.typing = SDK.Context (Just (SDK.Requester ("fileName") (SDK.TypeRef ("[Char]"))))
            , SDK.input = "Root"
            , SDK.demands = []
            }
        , SDK.EffectSpec
            { SDK.name = "FileResource"
            , SDK.typing = SDK.Context (Just (SDK.Requester ("openedFile") (SDK.TypeRef ("FileHandle"))))
            , SDK.input = "Root"
            , SDK.demands = [SDK.Demand (SDK.RequireAccess) ("FileName")]
            }
        , SDK.EffectSpec
            { SDK.name = "FileSession"
            , SDK.typing = SDK.Scoped (Just "openFileSession") (Just "closeFileSession")
            , SDK.input = "Root"
            , SDK.demands =
                [SDK.Demand (SDK.RequestAccess) ("OpenedFile"), SDK.Demand (SDK.RequireAccess) ("OpenedFile")]
            }
        , SDK.EffectSpec
            { SDK.name = "CheckIndependent"
            , SDK.typing = SDK.Excu (Just "checkIndependent")
            , SDK.input = "FileSession"
            , SDK.demands =
                [SDK.Demand (SDK.RequestAccess) ("FileName"), SDK.Demand (SDK.RequireAccess) ("OpenedFile")]
            }
        , SDK.EffectSpec
            { SDK.name = "CheckReopen"
            , SDK.typing = SDK.Excu (Just "checkReopen")
            , SDK.input = "FileSession"
            , SDK.demands =
                [SDK.Demand (SDK.RequestAccess) ("FileName"), SDK.Demand (SDK.RequireAccess) ("OpenedFile")]
            }
        ]
    , SDK.protoEffects =
        [ SDK.EffectProto
            { SDK.effectName = "PrepareFiles"
            , SDK.effectKind = SDK.ExcuKind
            , SDK.effectInput = "Root"
            , SDK.effectMethods = [(SDK.HandlerMethod, PrepareFilesGen)]
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
            }
        , SDK.EffectProto
            { SDK.effectName = "FileLocation"
            , SDK.effectKind = SDK.ContextKind
            , SDK.effectInput = "Root"
            , SDK.effectMethods = [(SDK.ContextRequest, FileNameGen), (SDK.ContextRequire, ReadFileNameGen)]
            , SDK.effectDemands = []
            , SDK.effectProduces = Just "FileName"
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
            { SDK.effectName = "FileResource"
            , SDK.effectKind = SDK.ContextKind
            , SDK.effectInput = "Root"
            , SDK.effectMethods =
                [(SDK.ContextRequest, OpenedFileGen), (SDK.ContextRequire, ReadOpenedFileGen)]
            , SDK.effectDemands = [SDK.ResolvedDemand (SDK.RequireAccess) ("FileName") ("FileLocation")]
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
            , SDK.effectContextDependencies = ["FileLocation"]
            }
        , SDK.EffectProto
            { SDK.effectName = "FileSession"
            , SDK.effectKind = SDK.ScopedKind
            , SDK.effectInput = "Root"
            , SDK.effectMethods = [(SDK.ScopeOpen, OpenFileSessionGen), (SDK.ScopeClose, CloseFileSessionGen)]
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
            , SDK.effectOpeningInputs = ["FileLocation"]
            , SDK.effectNearestScopes = ["FileSession"]
            , SDK.effectResource = Just "FileResource"
            , SDK.effectContextDependencies = ["FileLocation","FileResource"]
            }
        , SDK.EffectProto
            { SDK.effectName = "CheckIndependent"
            , SDK.effectKind = SDK.ExcuKind
            , SDK.effectInput = "FileSession"
            , SDK.effectMethods = [(SDK.HandlerMethod, CheckIndependentGen)]
            , SDK.effectDemands =
                [ SDK.ResolvedDemand (SDK.RequestAccess) ("FileName") ("FileLocation")
                , SDK.ResolvedDemand (SDK.RequireAccess) ("OpenedFile") ("FileResource")
                ]
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
            , SDK.effectContextDependencies = ["FileLocation","FileResource"]
            }
        , SDK.EffectProto
            { SDK.effectName = "CheckReopen"
            , SDK.effectKind = SDK.ExcuKind
            , SDK.effectInput = "FileSession"
            , SDK.effectMethods = [(SDK.HandlerMethod, CheckReopenGen)]
            , SDK.effectDemands =
                [ SDK.ResolvedDemand (SDK.RequestAccess) ("FileName") ("FileLocation")
                , SDK.ResolvedDemand (SDK.RequireAccess) ("OpenedFile") ("FileResource")
                ]
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
            , SDK.effectContextDependencies = ["FileLocation","FileResource"]
            }
        ]
    , SDK.protoMethods =
        [ SDK.MethodDefinition (PrepareFilesGen) (PrepareFilesGen) (SDK.HandlerMethod) (SDK.Empty)
        , SDK.MethodDefinition (FileNameGen) (FileNameGen) (SDK.ContextRequest) (SDK.Empty)
        , SDK.MethodDefinition
            (ReadFileNameGen)
            (FileNameGen)
            (SDK.ContextRequire)
            (SDK.Choice ([SDK.Empty, SDK.Call (FileNameGen)]))
        , SDK.MethodDefinition
            (OpenedFileGen)
            (OpenedFileGen)
            (SDK.ContextRequest)
            (SDK.Call (ReadFileNameGen))
        , SDK.MethodDefinition (ReadOpenedFileGen) (OpenedFileGen) (SDK.ContextRequire) (SDK.Empty)
        , SDK.MethodDefinition
            (OpenFileSessionGen)
            (OpenFileSessionGen)
            (SDK.ScopeOpen)
            (SDK.Call (OpenedFileGen))
        , SDK.MethodDefinition
            (CloseFileSessionGen)
            (OpenFileSessionGen)
            (SDK.ScopeClose)
            (SDK.Call (ReadOpenedFileGen))
        , SDK.MethodDefinition
            (CheckIndependentGen)
            (CheckIndependentGen)
            (SDK.HandlerMethod)
            (
              SDK.Sequence
                (
                  [ SDK.Call (FileNameGen)
                  , SDK.Call (OpenFileSessionGen)
                  , SDK.Call (ReadOpenedFileGen)
                  , SDK.Call (OpenFileSessionGen)
                  , SDK.Call (ReadOpenedFileGen)
                  , SDK.Call (FileNameGen)
                  , SDK.Call (OpenFileSessionGen)
                  , SDK.Call (ReadOpenedFileGen)
                  , SDK.Call (CloseFileSessionGen)
                  , SDK.Call (CloseFileSessionGen)
                  ]
                )
            )
        , SDK.MethodDefinition
            (CheckReopenGen)
            (CheckReopenGen)
            (SDK.HandlerMethod)
            (
              SDK.Sequence
                (
                  [ SDK.Call (FileNameGen)
                  , SDK.Call (OpenFileSessionGen)
                  , SDK.Call (ReadOpenedFileGen)
                  , SDK.Call (CloseFileSessionGen)
                  , SDK.Call (FileNameGen)
                  , SDK.Call (OpenFileSessionGen)
                  , SDK.Call (ReadOpenedFileGen)
                  , SDK.Call (CloseFileSessionGen)
                  ]
                )
            )
        ]
    , SDK.protoWorkflow =
        SDK.ChainedAt
          ([])
          (
            [ SDK.ChainedAt
                ([0])
                (
                  [ SDK.NodeAt ([0,0]) ("PrepareFiles")
                  ]
                )
            , SDK.ChainedAt
                ([1])
                (
                  [ SDK.NodeAt ([1,0]) ("CheckIndependent")
                  , SDK.NodeAt ([1,1]) ("CheckReopen")
                  ]
                )
            ]
          )
    , SDK.protoChains =
        [ SDK.ChainProto
            { SDK.chainNode = [0,0]
            , SDK.chainRole = SDK.NodeChain
            , SDK.chainTerminal = "PrepareFiles"
            , SDK.chainEntry = PrepareFilesGen
            , SDK.chainReaches = [PrepareFilesGen]
            , SDK.chainDrives = []
            , SDK.chainReads = []
            , SDK.chainScopePaths = [[]]
            }
        , SDK.ChainProto
            { SDK.chainNode = [1,0]
            , SDK.chainRole = SDK.NodeChain
            , SDK.chainTerminal = "CheckIndependent"
            , SDK.chainEntry = CheckIndependentGen
            , SDK.chainReaches =
                [ CheckIndependentGen
                , FileNameGen
                , OpenFileSessionGen
                , OpenedFileGen
                , ReadFileNameGen
                , ReadOpenedFileGen
                , CloseFileSessionGen
                ]
            , SDK.chainDrives = []
            , SDK.chainReads = []
            , SDK.chainScopePaths = [[OpenFileSessionGen]]
            }
        , SDK.ChainProto
            { SDK.chainNode = [1,1]
            , SDK.chainRole = SDK.NodeChain
            , SDK.chainTerminal = "CheckReopen"
            , SDK.chainEntry = CheckReopenGen
            , SDK.chainReaches =
                [ CheckReopenGen
                , FileNameGen
                , OpenFileSessionGen
                , OpenedFileGen
                , ReadFileNameGen
                , ReadOpenedFileGen
                , CloseFileSessionGen
                ]
            , SDK.chainDrives = []
            , SDK.chainReads = []
            , SDK.chainScopePaths = [[OpenFileSessionGen]]
            }
        ]
    , SDK.protoChainDefinitions =
        [ SDK.ChainDefinition
            { SDK.definitionKind = SDK.OriginChain
            , SDK.definitionEffect = "PrepareFiles"
            , SDK.definitionEntry = PrepareFilesGen
            , SDK.definitionReaches = [PrepareFilesGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.ContextChain
            , SDK.definitionEffect = "FileLocation"
            , SDK.definitionEntry = FileNameGen
            , SDK.definitionReaches = [FileNameGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.ContextChain
            , SDK.definitionEffect = "FileLocation"
            , SDK.definitionEntry = ReadFileNameGen
            , SDK.definitionReaches = [ReadFileNameGen, FileNameGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.ContextChain
            , SDK.definitionEffect = "FileResource"
            , SDK.definitionEntry = OpenedFileGen
            , SDK.definitionReaches = [OpenedFileGen, ReadFileNameGen, FileNameGen]
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
            , SDK.definitionReaches = [OpenFileSessionGen, OpenedFileGen, ReadFileNameGen, FileNameGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.OriginChain
            , SDK.definitionEffect = "CheckIndependent"
            , SDK.definitionEntry = CheckIndependentGen
            , SDK.definitionReaches =
                [ CheckIndependentGen
                , FileNameGen
                , OpenFileSessionGen
                , OpenedFileGen
                , ReadFileNameGen
                , ReadOpenedFileGen
                , CloseFileSessionGen
                ]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.OriginChain
            , SDK.definitionEffect = "CheckReopen"
            , SDK.definitionEntry = CheckReopenGen
            , SDK.definitionReaches =
                [ CheckReopenGen
                , FileNameGen
                , OpenFileSessionGen
                , OpenedFileGen
                , ReadFileNameGen
                , ReadOpenedFileGen
                , CloseFileSessionGen
                ]
            }
        ]
    , SDK.protoGraph =
        SDK.EffectGraph
          { SDK.graphMethods =
              [ SDK.MethodDefinition (PrepareFilesGen) (PrepareFilesGen) (SDK.HandlerMethod) (SDK.Empty)
              , SDK.MethodDefinition
                  (CheckIndependentGen)
                  (CheckIndependentGen)
                  (SDK.HandlerMethod)
                  (
                    SDK.Sequence
                      (
                        [ SDK.Call (FileNameGen)
                        , SDK.Call (OpenFileSessionGen)
                        , SDK.Call (ReadOpenedFileGen)
                        , SDK.Call (OpenFileSessionGen)
                        , SDK.Call (ReadOpenedFileGen)
                        , SDK.Call (FileNameGen)
                        , SDK.Call (OpenFileSessionGen)
                        , SDK.Call (ReadOpenedFileGen)
                        , SDK.Call (CloseFileSessionGen)
                        , SDK.Call (CloseFileSessionGen)
                        ]
                      )
                  )
              , SDK.MethodDefinition (FileNameGen) (FileNameGen) (SDK.ContextRequest) (SDK.Empty)
              , SDK.MethodDefinition
                  (OpenFileSessionGen)
                  (OpenFileSessionGen)
                  (SDK.ScopeOpen)
                  (SDK.Call (OpenedFileGen))
              , SDK.MethodDefinition
                  (OpenedFileGen)
                  (OpenedFileGen)
                  (SDK.ContextRequest)
                  (SDK.Call (ReadFileNameGen))
              , SDK.MethodDefinition
                  (ReadFileNameGen)
                  (FileNameGen)
                  (SDK.ContextRequire)
                  (SDK.Choice ([SDK.Empty, SDK.Call (FileNameGen)]))
              , SDK.MethodDefinition (ReadOpenedFileGen) (OpenedFileGen) (SDK.ContextRequire) (SDK.Empty)
              , SDK.MethodDefinition
                  (CloseFileSessionGen)
                  (OpenFileSessionGen)
                  (SDK.ScopeClose)
                  (SDK.Call (ReadOpenedFileGen))
              , SDK.MethodDefinition
                  (CheckReopenGen)
                  (CheckReopenGen)
                  (SDK.HandlerMethod)
                  (
                    SDK.Sequence
                      (
                        [ SDK.Call (FileNameGen)
                        , SDK.Call (OpenFileSessionGen)
                        , SDK.Call (ReadOpenedFileGen)
                        , SDK.Call (CloseFileSessionGen)
                        , SDK.Call (FileNameGen)
                        , SDK.Call (OpenFileSessionGen)
                        , SDK.Call (ReadOpenedFileGen)
                        , SDK.Call (CloseFileSessionGen)
                        ]
                      )
                  )
              ]
          , SDK.graphRoots = [PrepareFilesGen, CheckIndependentGen, CheckReopenGen]
          , SDK.graphReferences =
              [ (CheckIndependentGen, FileNameGen)
              , (CheckIndependentGen, OpenFileSessionGen)
              , (CheckIndependentGen, ReadOpenedFileGen)
              , (CheckIndependentGen, CloseFileSessionGen)
              , (OpenFileSessionGen, OpenedFileGen)
              , (OpenedFileGen, ReadFileNameGen)
              , (ReadFileNameGen, FileNameGen)
              , (CloseFileSessionGen, ReadOpenedFileGen)
              , (CheckReopenGen, FileNameGen)
              , (CheckReopenGen, OpenFileSessionGen)
              , (CheckReopenGen, ReadOpenedFileGen)
              , (CheckReopenGen, CloseFileSessionGen)
              ]
          , SDK.graphScopes = [OpenFileSessionGen]
          , SDK.graphScopePaths = [[], [OpenFileSessionGen]]
          , SDK.graphRootPaths =
              [ (PrepareFilesGen, [[]])
              , (CheckIndependentGen, [[OpenFileSessionGen]])
              , (CheckReopenGen, [[OpenFileSessionGen]])
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
    }
