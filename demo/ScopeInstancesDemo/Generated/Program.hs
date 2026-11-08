{-# LANGUAGE DuplicateRecordFields #-}

-- 自动生成；只登记末端入口与原型，执行由 SDK 的 interpreter 完成。
module ScopeInstancesDemo.Generated.Program where

import Framework.Generated (EffectSpec(..), EffectTyping(..), Asset(..), Handles(..), Demand(..), Access(..), TypeRef(..))
import qualified Framework.Generated as SDK
import ScopeInstancesDemo.Generated.Effects
import qualified ScopeInstancesDemo.Generated.Handlers as Handlers
import ScopeInstancesDemo.Types


-- 仅汇总所选末端的成功结果，不保存共享绑定或增加完成包装。
data Results = PrepareFilesResult () | UseFirstResult () | SelectSecondResult () | UseSecondResult () | SelectFirstResult () | ReopenFirstResult () | CheckJournalResult ()
  deriving Show

-- 末端共享生成的 scope 句柄；只创建空状态，Node algebra 才 lower。
-- 第二个列表是各转折契约的选择末端：驱动资产（持续资产领取本次交付），返回它当前的构造器名。
-- 第三个列表是各持续资产的生产步骤：会话按需启动，Stream 单步取得原始输入，parser 发布一次资产。
compiledEntries :: IO ([SDK.Target ContextValues Errors Results], [SDK.Target ContextValues Errors String]
                     , [(String, SDK.SessionSteps ContextValues Errors)])
compiledEntries = do
  scopes <- Handlers.newScopeHandlers
  pure
    ( [ SDK.targetApp "PrepareFiles" emptyContexts scopes (SDK.withErrorHandlers Handlers.errorHandlers (SDK.withAnchoredContexts Handlers.contextInjections (SDK.withScopeCleanups Handlers.scopeCleanups (PrepareFilesResult <$> (() <$ Handlers.runPrepareFiles)))))
      , SDK.targetApp "UseFirst" emptyContexts scopes (SDK.withErrorHandlers Handlers.errorHandlers (SDK.withAnchoredContexts Handlers.contextInjections (SDK.withScopeCleanups Handlers.scopeCleanups (UseFirstResult <$> (() <$ Handlers.runUseFirst)))))
      , SDK.targetApp "SelectSecond" emptyContexts scopes (SDK.withErrorHandlers Handlers.errorHandlers (SDK.withAnchoredContexts Handlers.contextInjections (SDK.withScopeCleanups Handlers.scopeCleanups (SelectSecondResult <$> (() <$ Handlers.runSelectSecond)))))
      , SDK.targetApp "UseSecond" emptyContexts scopes (SDK.withErrorHandlers Handlers.errorHandlers (SDK.withAnchoredContexts Handlers.contextInjections (SDK.withScopeCleanups Handlers.scopeCleanups (UseSecondResult <$> (() <$ Handlers.runUseSecond)))))
      , SDK.targetApp "SelectFirst" emptyContexts scopes (SDK.withErrorHandlers Handlers.errorHandlers (SDK.withAnchoredContexts Handlers.contextInjections (SDK.withScopeCleanups Handlers.scopeCleanups (SelectFirstResult <$> (() <$ Handlers.runSelectFirst)))))
      , SDK.targetApp "ReopenFirst" emptyContexts scopes (SDK.withErrorHandlers Handlers.errorHandlers (SDK.withAnchoredContexts Handlers.contextInjections (SDK.withScopeCleanups Handlers.scopeCleanups (ReopenFirstResult <$> (() <$ Handlers.runReopenFirst)))))
      , SDK.targetApp "CheckJournal" emptyContexts scopes (SDK.withErrorHandlers Handlers.errorHandlers (SDK.withAnchoredContexts Handlers.contextInjections (SDK.withScopeCleanups Handlers.scopeCleanups (CheckJournalResult <$> (() <$ Handlers.runCheckJournal)))))
      ]
    , []
    , []
    )

-- SDK 装配入口，不需要用户提供节点执行器或重复选择 handler。
interpreter :: SDK.AST -> [EffectSpec] -> IO ()
interpreter = SDK.interpreter "ScopeInstancesDemo" "demo/ScopeInstancesDemo/Handlers.hs" Handlers.handlerSourceFingerprint generatedPrototype compiledEntries
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
                SDK.Context
                  (SDK.AssetDecl ("FileName") (SDK.TypeRef ("[Char]")))
                  (Just "selectedFile")
                  (True)
                  (False)
            , SDK.input = "Root"
            , SDK.demands = []
            }
        , SDK.EffectSpec
            { SDK.name = "FileResource"
            , SDK.typing =
                SDK.Context
                  (SDK.AssetDecl ("OpenedFile") (SDK.TypeRef ("FileHandle")))
                  (Just "acquireFile")
                  (True)
                  (False)
            , SDK.input = "Root"
            , SDK.demands = [SDK.Demand (SDK.RequireAccess) ("FileName")]
            }
        , SDK.EffectSpec
            { SDK.name = "FileSession"
            , SDK.typing = SDK.Scoped (Just "openSelectedFile") (Just "closeSelectedFile")
            , SDK.input = "Root"
            , SDK.demands =
                [SDK.Demand (SDK.RequestAccess) ("OpenedFile"), SDK.Demand (SDK.RequireAccess) ("OpenedFile")]
            }
        , SDK.EffectSpec
            { SDK.name = "UseFirst"
            , SDK.typing = SDK.Excu (Just "checkSelection")
            , SDK.input = "FileSession"
            , SDK.demands =
                [ SDK.Demand (SDK.RequestAccess) ("FileName")
                , SDK.Demand (SDK.RequireAccess) ("FileName")
                , SDK.Demand (SDK.RequireAccess) ("OpenedFile")
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
                [ SDK.Demand (SDK.RequestAccess) ("FileName")
                , SDK.Demand (SDK.RequireAccess) ("FileName")
                , SDK.Demand (SDK.RequireAccess) ("OpenedFile")
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
                [ SDK.Demand (SDK.RequestAccess) ("FileName")
                , SDK.Demand (SDK.RequireAccess) ("FileName")
                , SDK.Demand (SDK.RequireAccess) ("OpenedFile")
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
        [ SDK.EffectProto
            { SDK.effectName = "PrepareFiles"
            , SDK.effectKind = SDK.ExcuKind
            , SDK.effectInput = "Root"
            , SDK.effectMethods = [(SDK.HandlerMethod, RunPrepareFilesGen)]
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
            { SDK.effectName = "FileLocation"
            , SDK.effectKind = SDK.ContextKind
            , SDK.effectInput = "Root"
            , SDK.effectMethods =
                [(SDK.ContextRequest, GetFileNameGen), (SDK.ContextRequire, ReadFileNameGen)]
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
            , SDK.effectContinuous = False
            }
        , SDK.EffectProto
            { SDK.effectName = "FileResource"
            , SDK.effectKind = SDK.ContextKind
            , SDK.effectInput = "Root"
            , SDK.effectMethods =
                [(SDK.ContextRequest, GetOpenedFileGen), (SDK.ContextRequire, ReadOpenedFileGen)]
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
            , SDK.effectContinuous = False
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
            , SDK.effectContinuous = False
            }
        , SDK.EffectProto
            { SDK.effectName = "UseFirst"
            , SDK.effectKind = SDK.ExcuKind
            , SDK.effectInput = "FileSession"
            , SDK.effectMethods = [(SDK.HandlerMethod, RunUseFirstGen)]
            , SDK.effectDemands =
                [ SDK.ResolvedDemand (SDK.RequestAccess) ("FileName") ("FileLocation")
                , SDK.ResolvedDemand (SDK.RequireAccess) ("FileName") ("FileLocation")
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
            , SDK.effectContinuous = False
            }
        , SDK.EffectProto
            { SDK.effectName = "SelectSecond"
            , SDK.effectKind = SDK.ExcuKind
            , SDK.effectInput = "Root"
            , SDK.effectMethods = [(SDK.HandlerMethod, RunSelectSecondGen)]
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
            { SDK.effectName = "UseSecond"
            , SDK.effectKind = SDK.ExcuKind
            , SDK.effectInput = "FileSession"
            , SDK.effectMethods = [(SDK.HandlerMethod, RunUseSecondGen)]
            , SDK.effectDemands =
                [ SDK.ResolvedDemand (SDK.RequestAccess) ("FileName") ("FileLocation")
                , SDK.ResolvedDemand (SDK.RequireAccess) ("FileName") ("FileLocation")
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
            , SDK.effectContinuous = False
            }
        , SDK.EffectProto
            { SDK.effectName = "SelectFirst"
            , SDK.effectKind = SDK.ExcuKind
            , SDK.effectInput = "Root"
            , SDK.effectMethods = [(SDK.HandlerMethod, RunSelectFirstGen)]
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
            { SDK.effectName = "ReopenFirst"
            , SDK.effectKind = SDK.ExcuKind
            , SDK.effectInput = "FileSession"
            , SDK.effectMethods = [(SDK.HandlerMethod, RunReopenFirstGen)]
            , SDK.effectDemands =
                [ SDK.ResolvedDemand (SDK.RequestAccess) ("FileName") ("FileLocation")
                , SDK.ResolvedDemand (SDK.RequireAccess) ("FileName") ("FileLocation")
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
            , SDK.effectContinuous = False
            }
        , SDK.EffectProto
            { SDK.effectName = "CheckJournal"
            , SDK.effectKind = SDK.ExcuKind
            , SDK.effectInput = "Root"
            , SDK.effectMethods = [(SDK.HandlerMethod, RunCheckJournalGen)]
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
        ]
    , SDK.protoMethods =
        [ SDK.MethodDefinition (RunPrepareFilesGen) (RunPrepareFilesGen) (SDK.HandlerMethod) (SDK.Empty)
        , SDK.MethodDefinition (GetFileNameGen) (GetFileNameGen) (SDK.ContextRequest) (SDK.Empty)
        , SDK.MethodDefinition (ReadFileNameGen) (GetFileNameGen) (SDK.ContextRequire) (SDK.Empty)
        , SDK.MethodDefinition
            (GetOpenedFileGen)
            (GetOpenedFileGen)
            (SDK.ContextRequest)
            (SDK.Call (ReadFileNameGen))
        , SDK.MethodDefinition (ReadOpenedFileGen) (GetOpenedFileGen) (SDK.ContextRequire) (SDK.Empty)
        , SDK.MethodDefinition
            (OpenFileSessionGen)
            (OpenFileSessionGen)
            (SDK.ScopeOpen)
            (SDK.Sequence ([SDK.Call (GetOpenedFileGen), SDK.Call (ReadOpenedFileGen)]))
        , SDK.MethodDefinition
            (CloseFileSessionGen)
            (OpenFileSessionGen)
            (SDK.ScopeClose)
            (SDK.Call (ReadOpenedFileGen))
        , SDK.MethodDefinition
            (RunUseFirstGen)
            (RunUseFirstGen)
            (SDK.HandlerMethod)
            (
              SDK.Sequence
                (
                  [ SDK.Call (GetFileNameGen)
                  , SDK.Call (OpenFileSessionGen)
                  , SDK.Call (ReadFileNameGen)
                  , SDK.Call (ReadOpenedFileGen)
                  ]
                )
            )
        , SDK.MethodDefinition (RunSelectSecondGen) (RunSelectSecondGen) (SDK.HandlerMethod) (SDK.Empty)
        , SDK.MethodDefinition
            (RunUseSecondGen)
            (RunUseSecondGen)
            (SDK.HandlerMethod)
            (
              SDK.Sequence
                (
                  [ SDK.Call (GetFileNameGen)
                  , SDK.Call (OpenFileSessionGen)
                  , SDK.Call (ReadFileNameGen)
                  , SDK.Call (ReadOpenedFileGen)
                  ]
                )
            )
        , SDK.MethodDefinition (RunSelectFirstGen) (RunSelectFirstGen) (SDK.HandlerMethod) (SDK.Empty)
        , SDK.MethodDefinition
            (RunReopenFirstGen)
            (RunReopenFirstGen)
            (SDK.HandlerMethod)
            (
              SDK.Sequence
                (
                  [ SDK.Call (GetFileNameGen)
                  , SDK.Call (OpenFileSessionGen)
                  , SDK.Call (ReadFileNameGen)
                  , SDK.Call (ReadOpenedFileGen)
                  ]
                )
            )
        , SDK.MethodDefinition (RunCheckJournalGen) (RunCheckJournalGen) (SDK.HandlerMethod) (SDK.Empty)
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
                  [ SDK.NodeAt ([1,0]) ("UseFirst")
                  , SDK.NodeAt ([1,1]) ("SelectSecond")
                  , SDK.NodeAt ([1,2]) ("UseSecond")
                  , SDK.NodeAt ([1,3]) ("SelectFirst")
                  , SDK.NodeAt ([1,4]) ("ReopenFirst")
                  , SDK.NodeAt ([1,5]) ("CheckJournal")
                  ]
                )
            ]
          )
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
              [ SDK.MethodDefinition (RunPrepareFilesGen) (RunPrepareFilesGen) (SDK.HandlerMethod) (SDK.Empty)
              , SDK.MethodDefinition
                  (RunUseFirstGen)
                  (RunUseFirstGen)
                  (SDK.HandlerMethod)
                  (
                    SDK.Sequence
                      (
                        [ SDK.Call (GetFileNameGen)
                        , SDK.Call (OpenFileSessionGen)
                        , SDK.Call (ReadFileNameGen)
                        , SDK.Call (ReadOpenedFileGen)
                        ]
                      )
                  )
              , SDK.MethodDefinition (GetFileNameGen) (GetFileNameGen) (SDK.ContextRequest) (SDK.Empty)
              , SDK.MethodDefinition
                  (OpenFileSessionGen)
                  (OpenFileSessionGen)
                  (SDK.ScopeOpen)
                  (SDK.Sequence ([SDK.Call (GetOpenedFileGen), SDK.Call (ReadOpenedFileGen)]))
              , SDK.MethodDefinition
                  (GetOpenedFileGen)
                  (GetOpenedFileGen)
                  (SDK.ContextRequest)
                  (SDK.Call (ReadFileNameGen))
              , SDK.MethodDefinition (ReadFileNameGen) (GetFileNameGen) (SDK.ContextRequire) (SDK.Empty)
              , SDK.MethodDefinition (ReadOpenedFileGen) (GetOpenedFileGen) (SDK.ContextRequire) (SDK.Empty)
              , SDK.MethodDefinition (RunSelectSecondGen) (RunSelectSecondGen) (SDK.HandlerMethod) (SDK.Empty)
              , SDK.MethodDefinition
                  (RunUseSecondGen)
                  (RunUseSecondGen)
                  (SDK.HandlerMethod)
                  (
                    SDK.Sequence
                      (
                        [ SDK.Call (GetFileNameGen)
                        , SDK.Call (OpenFileSessionGen)
                        , SDK.Call (ReadFileNameGen)
                        , SDK.Call (ReadOpenedFileGen)
                        ]
                      )
                  )
              , SDK.MethodDefinition (RunSelectFirstGen) (RunSelectFirstGen) (SDK.HandlerMethod) (SDK.Empty)
              , SDK.MethodDefinition
                  (RunReopenFirstGen)
                  (RunReopenFirstGen)
                  (SDK.HandlerMethod)
                  (
                    SDK.Sequence
                      (
                        [ SDK.Call (GetFileNameGen)
                        , SDK.Call (OpenFileSessionGen)
                        , SDK.Call (ReadFileNameGen)
                        , SDK.Call (ReadOpenedFileGen)
                        ]
                      )
                  )
              , SDK.MethodDefinition (RunCheckJournalGen) (RunCheckJournalGen) (SDK.HandlerMethod) (SDK.Empty)
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
    }
