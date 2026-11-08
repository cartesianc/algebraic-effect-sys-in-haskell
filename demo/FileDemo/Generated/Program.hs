{-# LANGUAGE DuplicateRecordFields #-}

-- 自动生成；只登记末端入口与原型，执行由 SDK 的 interpreter 完成。
module FileDemo.Generated.Program where

import Framework.Generated (EffectSpec(..), EffectTyping(..), Asset(..), Handles(..), Demand(..), Access(..), TypeRef(..))
import qualified Framework.Generated as SDK
import FileDemo.Generated.Effects
import qualified FileDemo.Generated.Handlers as Handlers
import FileDemo.Types


-- 仅汇总所选末端的成功结果，不保存共享绑定或增加完成包装。
data Results = WriteFirstLineResult () | AppendLineResult ()
  deriving Show

-- 末端共享生成的 scope 句柄；只创建空状态，Node algebra 才 lower。
-- 第二个列表是各转折契约的读取末端：读取资产，返回它当前的构造器名。
-- 第三个列表是各持续资产的生产步骤：会话按需启动，Stream 单步取得原始输入，parser 发布一次资产。
compiledEntries :: IO ([SDK.Target ContextValues Errors Results], [SDK.Target ContextValues Errors String]
                     , [(String, SDK.SessionSteps ContextValues Errors)])
compiledEntries = do
  scopes <- Handlers.newScopeHandlers
  pure
    ( [ SDK.targetApp "WriteFirstLine" emptyContexts scopes (SDK.withErrorHandlers Handlers.errorHandlers (SDK.withAnchoredContexts Handlers.contextInjections (SDK.withScopeCleanups Handlers.scopeCleanups (WriteFirstLineResult <$> (() <$ Handlers.runWriteFirstLine)))))
      , SDK.targetApp "AppendLine" emptyContexts scopes (SDK.withErrorHandlers Handlers.errorHandlers (SDK.withAnchoredContexts Handlers.contextInjections (SDK.withScopeCleanups Handlers.scopeCleanups (AppendLineResult <$> (() <$ Handlers.runAppendLine)))))
      ]
    , [ SDK.targetApp "FileText" emptyContexts scopes (SDK.withErrorHandlers Handlers.errorHandlers (SDK.withAnchoredContexts Handlers.contextInjections (SDK.withScopeCleanups Handlers.scopeCleanups (caseOfFileText <$> Handlers.readFileText))))
      ]
    , []
    )

caseOfFileText :: FileText -> String
caseOfFileText (FileText value) = case value of
  Blank {} -> "Blank"
  Written {} -> "Written"

-- SDK 装配入口，不需要用户提供节点执行器或重复选择 handler。
interpreter :: SDK.AST -> [EffectSpec] -> IO ()
interpreter = SDK.interpreter "FileDemo" "demo/FileDemo/Handlers.hs" Handlers.handlerSourceFingerprint generatedPrototype compiledEntries
-- 生成时完成注册、方法、origin/ctx 链、资产来源、Workflow 和 scope 的统一分析。
-- NodeId 只在这份 AST 快照中有效；运行时校验后装配闭包。
generatedPrototype :: SDK.Prototype MethodGen
generatedPrototype =
  SDK.Prototype
    { SDK.protoRegistrations =
        [ SDK.EffectSpec
            { SDK.name = "FileLocation"
            , SDK.typing =
                SDK.Context (SDK.AssetDecl ("FileName") (SDK.TypeRef ("[Char]"))) (Just "locateFile") (True) (False)
            , SDK.input = "Root"
            , SDK.demands = []
            }
        , SDK.EffectSpec
            { SDK.name = "ValidateFileName"
            , SDK.typing = SDK.Pure (Just "validateFileName")
            , SDK.input = "Root"
            , SDK.demands = [SDK.Demand (SDK.RequireAccess) ("FileName")]
            }
        , SDK.EffectSpec
            { SDK.name = "FileResource"
            , SDK.typing =
                SDK.Context
                  (SDK.AssetDecl ("OpenedFile") (SDK.TypeRef ("FileHandle")))
                  (Just "acquireFile")
                  (True)
                  (False)
            , SDK.input = "ValidateFileName"
            , SDK.demands = [SDK.Demand (SDK.RequireAccess) ("FileName")]
            }
        , SDK.EffectSpec
            { SDK.name = "FileSession"
            , SDK.typing = SDK.Scoped (Just "openSession") (Just "closeSession")
            , SDK.input = "ValidateFileName"
            , SDK.demands =
                [SDK.Demand (SDK.RequestAccess) ("OpenedFile"), SDK.Demand (SDK.RequireAccess) ("OpenedFile")]
            }
        , SDK.EffectSpec
            { SDK.name = "FileRecovery"
            , SDK.typing =
                SDK.Error
                  (Just "detectFileSession")
                  (Just "resolveFileSession")
                  ([SDK.RaisedBy ("readFileContent"), SDK.RaisedBy ("writeFirstLine"), SDK.RaisedBy ("appendLine")])
            , SDK.input = "FileSession"
            , SDK.demands = [SDK.Demand (SDK.RequireAccess) ("OpenedFile")]
            }
        , SDK.EffectSpec
            { SDK.name = "ReadFile"
            , SDK.typing = SDK.Excu (Just "readFileContent")
            , SDK.input = "FileSession"
            , SDK.demands = [SDK.Demand (SDK.RequireAccess) ("OpenedFile")]
            }
        , SDK.EffectSpec
            { SDK.name = "ExtractFileText"
            , SDK.typing =
                SDK.Context
                  (SDK.AssetDecl ("FileText") (SDK.TypeRef ("TextState")))
                  (Just "parseFileText")
                  (True)
                  (False)
            , SDK.input = "ReadFile"
            , SDK.demands = []
            }
        , SDK.EffectSpec
            { SDK.name = "WriteFirstLine"
            , SDK.typing = SDK.Excu (Just "writeFirstLine")
            , SDK.input = "FileSession"
            , SDK.demands =
                [SDK.Demand (SDK.RequireAccess) ("FileTextBlank"), SDK.Demand (SDK.RequireAccess) ("OpenedFile")]
            }
        , SDK.EffectSpec
            { SDK.name = "AppendLine"
            , SDK.typing = SDK.Excu (Just "appendLine")
            , SDK.input = "FileSession"
            , SDK.demands =
                [SDK.Demand (SDK.RequireAccess) ("FileTextWritten"), SDK.Demand (SDK.RequireAccess) ("OpenedFile")]
            }
        ]
    , SDK.protoEffects =
        [ SDK.EffectProto
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
            { SDK.effectName = "ValidateFileName"
            , SDK.effectKind = SDK.PureKind
            , SDK.effectInput = "Root"
            , SDK.effectMethods = [(SDK.HandlerMethod, RunValidateFileNameGen)]
            , SDK.effectDemands = [SDK.ResolvedDemand (SDK.RequireAccess) ("FileName") ("FileLocation")]
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
            , SDK.effectContextDependencies = ["FileLocation"]
            , SDK.effectContinuous = False
            }
        , SDK.EffectProto
            { SDK.effectName = "FileResource"
            , SDK.effectKind = SDK.ContextKind
            , SDK.effectInput = "ValidateFileName"
            , SDK.effectMethods =
                [(SDK.ContextRequest, GetOpenedFileGen), (SDK.ContextRequire, ReadOpenedFileGen)]
            , SDK.effectDemands = [SDK.ResolvedDemand (SDK.RequireAccess) ("FileName") ("FileLocation")]
            , SDK.effectProduces = Just "OpenedFile"
            , SDK.effectBranches = []
            , SDK.effectAnchor = Nothing
            , SDK.effectScopes = []
            , SDK.effectErrorScope = Nothing
            , SDK.effectInputChain = ["ValidateFileName"]
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
            , SDK.effectInput = "ValidateFileName"
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
            , SDK.effectInputChain = ["ValidateFileName"]
            , SDK.effectScopeParents = []
            , SDK.effectOpeningInputs = ["FileLocation"]
            , SDK.effectNearestScopes = ["FileSession"]
            , SDK.effectResource = Just "FileResource"
            , SDK.effectContextDependencies = ["FileLocation","FileResource"]
            , SDK.effectContinuous = False
            }
        , SDK.EffectProto
            { SDK.effectName = "FileRecovery"
            , SDK.effectKind = SDK.ErrorKind
            , SDK.effectInput = "FileSession"
            , SDK.effectMethods =
                [(SDK.ErrorDetect, DetectFileRecoveryGen), (SDK.ErrorResolve, ResolveFileRecoveryGen)]
            , SDK.effectDemands = [SDK.ResolvedDemand (SDK.RequireAccess) ("OpenedFile") ("FileResource")]
            , SDK.effectProduces = Nothing
            , SDK.effectBranches = []
            , SDK.effectAnchor = Nothing
            , SDK.effectScopes = ["FileSession"]
            , SDK.effectErrorScope = Just "FileSession"
            , SDK.effectInputChain = ["FileSession","ValidateFileName"]
            , SDK.effectScopeParents = ["FileSession"]
            , SDK.effectOpeningInputs = []
            , SDK.effectNearestScopes = ["FileSession"]
            , SDK.effectResource = Nothing
            , SDK.effectContextDependencies = ["FileLocation","FileResource"]
            , SDK.effectContinuous = False
            }
        , SDK.EffectProto
            { SDK.effectName = "ReadFile"
            , SDK.effectKind = SDK.ExcuKind
            , SDK.effectInput = "FileSession"
            , SDK.effectMethods = [(SDK.HandlerMethod, RunReadFileGen)]
            , SDK.effectDemands = [SDK.ResolvedDemand (SDK.RequireAccess) ("OpenedFile") ("FileResource")]
            , SDK.effectProduces = Nothing
            , SDK.effectBranches = []
            , SDK.effectAnchor = Nothing
            , SDK.effectScopes = ["FileSession"]
            , SDK.effectErrorScope = Nothing
            , SDK.effectInputChain = ["FileSession","ValidateFileName"]
            , SDK.effectScopeParents = ["FileSession"]
            , SDK.effectOpeningInputs = []
            , SDK.effectNearestScopes = ["FileSession"]
            , SDK.effectResource = Nothing
            , SDK.effectContextDependencies = ["FileLocation","FileResource"]
            , SDK.effectContinuous = False
            }
        , SDK.EffectProto
            { SDK.effectName = "ExtractFileText"
            , SDK.effectKind = SDK.ContextKind
            , SDK.effectInput = "ReadFile"
            , SDK.effectMethods =
                [(SDK.ContextRequest, GetFileTextGen), (SDK.ContextRequire, ReadFileTextGen)]
            , SDK.effectDemands = []
            , SDK.effectProduces = Just "FileText"
            , SDK.effectBranches = [("FileTextBlank","Blank"),("FileTextWritten","Written")]
            , SDK.effectAnchor = Just "ReadFile"
            , SDK.effectScopes = ["FileSession"]
            , SDK.effectErrorScope = Nothing
            , SDK.effectInputChain = ["ReadFile","FileSession","ValidateFileName"]
            , SDK.effectScopeParents = ["FileSession"]
            , SDK.effectOpeningInputs = []
            , SDK.effectNearestScopes = ["FileSession"]
            , SDK.effectResource = Nothing
            , SDK.effectContextDependencies = ["FileLocation","FileResource"]
            , SDK.effectContinuous = False
            }
        , SDK.EffectProto
            { SDK.effectName = "WriteFirstLine"
            , SDK.effectKind = SDK.ExcuKind
            , SDK.effectInput = "FileSession"
            , SDK.effectMethods = [(SDK.HandlerMethod, RunWriteFirstLineGen)]
            , SDK.effectDemands =
                [ SDK.ResolvedDemand (SDK.RequireAccess) ("FileTextBlank") ("ExtractFileText")
                , SDK.ResolvedDemand (SDK.RequireAccess) ("OpenedFile") ("FileResource")
                ]
            , SDK.effectProduces = Nothing
            , SDK.effectBranches = []
            , SDK.effectAnchor = Nothing
            , SDK.effectScopes = ["FileSession"]
            , SDK.effectErrorScope = Nothing
            , SDK.effectInputChain = ["FileSession","ValidateFileName"]
            , SDK.effectScopeParents = ["FileSession"]
            , SDK.effectOpeningInputs = []
            , SDK.effectNearestScopes = ["FileSession"]
            , SDK.effectResource = Nothing
            , SDK.effectContextDependencies = ["FileLocation","FileResource","ExtractFileText"]
            , SDK.effectContinuous = False
            }
        , SDK.EffectProto
            { SDK.effectName = "AppendLine"
            , SDK.effectKind = SDK.ExcuKind
            , SDK.effectInput = "FileSession"
            , SDK.effectMethods = [(SDK.HandlerMethod, RunAppendLineGen)]
            , SDK.effectDemands =
                [ SDK.ResolvedDemand (SDK.RequireAccess) ("FileTextWritten") ("ExtractFileText")
                , SDK.ResolvedDemand (SDK.RequireAccess) ("OpenedFile") ("FileResource")
                ]
            , SDK.effectProduces = Nothing
            , SDK.effectBranches = []
            , SDK.effectAnchor = Nothing
            , SDK.effectScopes = ["FileSession"]
            , SDK.effectErrorScope = Nothing
            , SDK.effectInputChain = ["FileSession","ValidateFileName"]
            , SDK.effectScopeParents = ["FileSession"]
            , SDK.effectOpeningInputs = []
            , SDK.effectNearestScopes = ["FileSession"]
            , SDK.effectResource = Nothing
            , SDK.effectContextDependencies = ["FileLocation","FileResource","ExtractFileText"]
            , SDK.effectContinuous = False
            }
        ]
    , SDK.protoMethods =
        [ SDK.MethodDefinition (GetFileNameGen) (GetFileNameGen) (SDK.ContextRequest) (SDK.Empty)
        , SDK.MethodDefinition
            (ReadFileNameGen)
            (GetFileNameGen)
            (SDK.ContextRequire)
            (SDK.Choice ([SDK.Empty, SDK.Call (GetFileNameGen)]))
        , SDK.MethodDefinition
            (RunValidateFileNameGen)
            (RunValidateFileNameGen)
            (SDK.HandlerMethod)
            (SDK.Call (ReadFileNameGen))
        , SDK.MethodDefinition
            (GetOpenedFileGen)
            (GetOpenedFileGen)
            (SDK.ContextRequest)
            (SDK.Sequence ([SDK.Call (RunValidateFileNameGen), SDK.Call (ReadFileNameGen)]))
        , SDK.MethodDefinition (ReadOpenedFileGen) (GetOpenedFileGen) (SDK.ContextRequire) (SDK.Empty)
        , SDK.MethodDefinition
            (OpenFileSessionGen)
            (OpenFileSessionGen)
            (SDK.ScopeOpen)
            (SDK.Sequence ([SDK.Call (GetOpenedFileGen), SDK.Call (RunValidateFileNameGen)]))
        , SDK.MethodDefinition
            (CloseFileSessionGen)
            (OpenFileSessionGen)
            (SDK.ScopeClose)
            (SDK.Call (ReadOpenedFileGen))
        , SDK.MethodDefinition
            (DetectFileRecoveryGen)
            (DetectFileRecoveryGen)
            (SDK.ErrorDetect)
            (SDK.Call (ReadOpenedFileGen))
        , SDK.MethodDefinition (ResolveFileRecoveryGen) (DetectFileRecoveryGen) (SDK.ErrorResolve) (SDK.Empty)
        , SDK.MethodDefinition
            (RunReadFileGen)
            (RunReadFileGen)
            (SDK.HandlerMethod)
            (
              SDK.Sequence
                (
                  [ SDK.Sequence ([SDK.Call (OpenFileSessionGen), SDK.Call (ReadOpenedFileGen)])
                  , SDK.Choice ([SDK.Empty, SDK.Sequence ([SDK.Empty])])
                  ]
                )
            )
        , SDK.MethodDefinition
            (GetFileTextGen)
            (GetFileTextGen)
            (SDK.ContextRequest)
            (SDK.Call (RunReadFileGen))
        , SDK.MethodDefinition
            (ReadFileTextGen)
            (GetFileTextGen)
            (SDK.ContextRequire)
            (SDK.Choice ([SDK.Empty, SDK.Call (GetFileTextGen)]))
        , SDK.MethodDefinition
            (RunWriteFirstLineGen)
            (RunWriteFirstLineGen)
            (SDK.HandlerMethod)
            (SDK.Sequence ([SDK.Call (OpenFileSessionGen), SDK.Call (ReadOpenedFileGen)]))
        , SDK.MethodDefinition
            (RunAppendLineGen)
            (RunAppendLineGen)
            (SDK.HandlerMethod)
            (
              SDK.Sequence
                ([SDK.Call (OpenFileSessionGen), SDK.Call (ReadFileTextGen), SDK.Call (ReadOpenedFileGen)])
            )
        ]
    , SDK.protoWorkflow =
        SDK.AlternativeAt
          ([])
          (
            SDK.AlternativeProto
              { SDK.alternativeContract = "FileText"
              , SDK.alternativeSelector = [-1]
              , SDK.alternativeCases = [([0],"Blank"),([1],"Written")]
              }
          )
          (
            [ SDK.NodeAt ([0]) ("WriteFirstLine")
            , SDK.NodeAt ([1]) ("AppendLine")
            ]
          )
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
                , RunValidateFileNameGen
                , ReadFileNameGen
                , GetFileNameGen
                , ReadOpenedFileGen
                ]
            , SDK.chainDrives = ["FileName"]
            , SDK.chainReads = ["FileName"]
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
                , RunValidateFileNameGen
                , ReadFileNameGen
                , GetFileNameGen
                , ReadFileTextGen
                , GetFileTextGen
                , RunReadFileGen
                , ReadOpenedFileGen
                ]
            , SDK.chainDrives = ["FileName"]
            , SDK.chainReads = ["FileName"]
            , SDK.chainScopePaths = [[OpenFileSessionGen]]
            }
        , SDK.ChainProto
            { SDK.chainNode = [-1]
            , SDK.chainRole = SDK.SelectorChain
            , SDK.chainTerminal = "FileText"
            , SDK.chainEntry = ReadFileTextGen
            , SDK.chainReaches =
                [ ReadFileTextGen
                , GetFileTextGen
                , RunReadFileGen
                , OpenFileSessionGen
                , GetOpenedFileGen
                , RunValidateFileNameGen
                , ReadFileNameGen
                , GetFileNameGen
                , ReadOpenedFileGen
                ]
            , SDK.chainDrives = ["FileName","FileText"]
            , SDK.chainReads = ["FileName","FileText"]
            , SDK.chainScopePaths = [[], [OpenFileSessionGen]]
            }
        ]
    , SDK.protoChainDefinitions =
        [ SDK.ChainDefinition
            { SDK.definitionKind = SDK.ContextChain
            , SDK.definitionEffect = "FileLocation"
            , SDK.definitionEntry = GetFileNameGen
            , SDK.definitionReaches = [GetFileNameGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.ContextChain
            , SDK.definitionEffect = "FileLocation"
            , SDK.definitionEntry = ReadFileNameGen
            , SDK.definitionReaches = [ReadFileNameGen, GetFileNameGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.OriginChain
            , SDK.definitionEffect = "ValidateFileName"
            , SDK.definitionEntry = RunValidateFileNameGen
            , SDK.definitionReaches = [RunValidateFileNameGen, ReadFileNameGen, GetFileNameGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.ContextChain
            , SDK.definitionEffect = "FileResource"
            , SDK.definitionEntry = GetOpenedFileGen
            , SDK.definitionReaches =
                [GetOpenedFileGen, RunValidateFileNameGen, ReadFileNameGen, GetFileNameGen]
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
                [OpenFileSessionGen, GetOpenedFileGen, RunValidateFileNameGen, ReadFileNameGen, GetFileNameGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.OriginChain
            , SDK.definitionEffect = "ReadFile"
            , SDK.definitionEntry = RunReadFileGen
            , SDK.definitionReaches =
                [ RunReadFileGen
                , OpenFileSessionGen
                , GetOpenedFileGen
                , RunValidateFileNameGen
                , ReadFileNameGen
                , GetFileNameGen
                , ReadOpenedFileGen
                , GetFileTextGen
                ]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.ContextChain
            , SDK.definitionEffect = "ExtractFileText"
            , SDK.definitionEntry = GetFileTextGen
            , SDK.definitionReaches =
                [ GetFileTextGen
                , RunReadFileGen
                , OpenFileSessionGen
                , GetOpenedFileGen
                , RunValidateFileNameGen
                , ReadFileNameGen
                , GetFileNameGen
                , ReadOpenedFileGen
                ]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.ContextChain
            , SDK.definitionEffect = "ExtractFileText"
            , SDK.definitionEntry = ReadFileTextGen
            , SDK.definitionReaches =
                [ ReadFileTextGen
                , GetFileTextGen
                , RunReadFileGen
                , OpenFileSessionGen
                , GetOpenedFileGen
                , RunValidateFileNameGen
                , ReadFileNameGen
                , GetFileNameGen
                , ReadOpenedFileGen
                ]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.OriginChain
            , SDK.definitionEffect = "WriteFirstLine"
            , SDK.definitionEntry = RunWriteFirstLineGen
            , SDK.definitionReaches =
                [ RunWriteFirstLineGen
                , OpenFileSessionGen
                , GetOpenedFileGen
                , RunValidateFileNameGen
                , ReadFileNameGen
                , GetFileNameGen
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
                , RunValidateFileNameGen
                , ReadFileNameGen
                , GetFileNameGen
                , ReadFileTextGen
                , GetFileTextGen
                , RunReadFileGen
                , ReadOpenedFileGen
                ]
            }
        ]
    , SDK.protoGraph =
        SDK.EffectGraph
          { SDK.graphMethods =
              [ SDK.MethodDefinition
                  (RunWriteFirstLineGen)
                  (RunWriteFirstLineGen)
                  (SDK.HandlerMethod)
                  (SDK.Sequence ([SDK.Call (OpenFileSessionGen), SDK.Call (ReadOpenedFileGen)]))
              , SDK.MethodDefinition
                  (OpenFileSessionGen)
                  (OpenFileSessionGen)
                  (SDK.ScopeOpen)
                  (SDK.Sequence ([SDK.Call (GetOpenedFileGen), SDK.Call (RunValidateFileNameGen)]))
              , SDK.MethodDefinition
                  (GetOpenedFileGen)
                  (GetOpenedFileGen)
                  (SDK.ContextRequest)
                  (SDK.Sequence ([SDK.Call (RunValidateFileNameGen), SDK.Call (ReadFileNameGen)]))
              , SDK.MethodDefinition
                  (RunValidateFileNameGen)
                  (RunValidateFileNameGen)
                  (SDK.HandlerMethod)
                  (SDK.Call (ReadFileNameGen))
              , SDK.MethodDefinition
                  (ReadFileNameGen)
                  (GetFileNameGen)
                  (SDK.ContextRequire)
                  (SDK.Choice ([SDK.Empty, SDK.Call (GetFileNameGen)]))
              , SDK.MethodDefinition (GetFileNameGen) (GetFileNameGen) (SDK.ContextRequest) (SDK.Empty)
              , SDK.MethodDefinition (ReadOpenedFileGen) (GetOpenedFileGen) (SDK.ContextRequire) (SDK.Empty)
              , SDK.MethodDefinition
                  (RunAppendLineGen)
                  (RunAppendLineGen)
                  (SDK.HandlerMethod)
                  (
                    SDK.Sequence
                      ([SDK.Call (OpenFileSessionGen), SDK.Call (ReadFileTextGen), SDK.Call (ReadOpenedFileGen)])
                  )
              , SDK.MethodDefinition
                  (ReadFileTextGen)
                  (GetFileTextGen)
                  (SDK.ContextRequire)
                  (SDK.Choice ([SDK.Empty, SDK.Call (GetFileTextGen)]))
              , SDK.MethodDefinition
                  (GetFileTextGen)
                  (GetFileTextGen)
                  (SDK.ContextRequest)
                  (SDK.Call (RunReadFileGen))
              , SDK.MethodDefinition
                  (RunReadFileGen)
                  (RunReadFileGen)
                  (SDK.HandlerMethod)
                  (
                    SDK.Sequence
                      (
                        [ SDK.Sequence ([SDK.Call (OpenFileSessionGen), SDK.Call (ReadOpenedFileGen)])
                        , SDK.Choice ([SDK.Empty, SDK.Sequence ([SDK.Empty])])
                        ]
                      )
                  )
              ]
          , SDK.graphRoots = [RunWriteFirstLineGen, RunAppendLineGen, ReadFileTextGen]
          , SDK.graphReferences =
              [ (RunWriteFirstLineGen, OpenFileSessionGen)
              , (RunWriteFirstLineGen, ReadOpenedFileGen)
              , (OpenFileSessionGen, GetOpenedFileGen)
              , (OpenFileSessionGen, RunValidateFileNameGen)
              , (GetOpenedFileGen, RunValidateFileNameGen)
              , (GetOpenedFileGen, ReadFileNameGen)
              , (RunValidateFileNameGen, ReadFileNameGen)
              , (ReadFileNameGen, GetFileNameGen)
              , (RunAppendLineGen, OpenFileSessionGen)
              , (RunAppendLineGen, ReadFileTextGen)
              , (RunAppendLineGen, ReadOpenedFileGen)
              , (ReadFileTextGen, GetFileTextGen)
              , (GetFileTextGen, RunReadFileGen)
              , (RunReadFileGen, OpenFileSessionGen)
              , (RunReadFileGen, ReadOpenedFileGen)
              ]
          , SDK.graphScopes = [OpenFileSessionGen]
          , SDK.graphScopePaths = [[OpenFileSessionGen], []]
          , SDK.graphRootPaths =
              [ (RunWriteFirstLineGen, [[OpenFileSessionGen]])
              , (RunAppendLineGen, [[OpenFileSessionGen]])
              , (ReadFileTextGen, [[], [OpenFileSessionGen]])
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
        [ (SDK.ReadPoint ([1]) ("FileName"), SDK.FromOwnChain)
        , (SDK.ReadPoint ([0]) ("FileName"), SDK.FromOwnChain)
        , (SDK.ReadPoint ([-1]) ("FileName"), SDK.FromOwnChain)
        , (SDK.ReadPoint ([-1]) ("FileText"), SDK.FromOwnChain)
        ]
    }
