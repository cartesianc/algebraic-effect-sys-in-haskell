{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE TypeFamilies #-}

-- 自动生成；只登记末端句柄，Node algebra 才 lower，业务组合仍在 handler 内。
module FileDemo.Generated.Program where

import Framework.SDK (Effect(..), EffectSpec(..), EffectTyping(..), Requester(..), Handles(..), Demand(..), Access(..), TypeRef(..))
import qualified Framework.SDK as SDK
import qualified Framework.Effect.Contract as FrameworkRoot
import FileDemo.Generated.Effects hiding (request, require)
import qualified FileDemo.Generated.Handlers as Handlers
import FileDemo.Types


-- 仅汇总所选末端的成功产物，不保存共享绑定或增加完成包装。
data Results = WriteFirstLineResult (Produce WriteFirstLine) | AppendLineResult (Produce AppendLine)
  deriving Show

-- 末端共享生成的 scope 句柄；只创建空状态，Node algebra 才 lower，业务调用仍在 instance 内。
-- 第二个列表是各转折契约的读取末端：按 require 取得资产，返回它当前的构造器名。
compiledEntries :: IO ([SDK.Target ContextValues Errors Results], [SDK.Target ContextValues Errors String])
compiledEntries = do
  scopes <- Handlers.newScopeHandlers
  pure
    ( [ SDK.targetApp "WriteFirstLine" emptyContexts scopes (FrameworkRoot.withErrorHandlers Handlers.errorHandlers (FrameworkRoot.withAnchoredContexts Handlers.contextInjections (SDK.withScopeCleanups Handlers.scopeCleanups (WriteFirstLineResult <$> (() <$ writeFirstLine)))))
      , SDK.targetApp "AppendLine" emptyContexts scopes (FrameworkRoot.withErrorHandlers Handlers.errorHandlers (FrameworkRoot.withAnchoredContexts Handlers.contextInjections (SDK.withScopeCleanups Handlers.scopeCleanups (AppendLineResult <$> (() <$ appendLine)))))
      ]
    , [ SDK.targetApp "FileText" emptyContexts scopes (FrameworkRoot.withErrorHandlers Handlers.errorHandlers (FrameworkRoot.withAnchoredContexts Handlers.contextInjections (SDK.withScopeCleanups Handlers.scopeCleanups (caseOfFileText <$> readFileText))))
      ]
    )

caseOfFileText :: FileText -> String
caseOfFileText (FileText value) = case value of
  Blank {} -> "Blank"
  Written {} -> "Written"

-- SDK 装配入口，不需要用户提供节点执行器或重复选择 handler。
interpreter :: SDK.AST -> [EffectSpec] -> IO ()
interpreter = SDK.interpreter "FileDemo" Handlers.handlerSourceFingerprint generatedPrototype compiledEntries
-- 生成时完成注册、方法、origin/ctx 链、资产来源、Workflow 和 scope 的统一分析。
-- NodeId 只在这份 AST 快照中有效；运行时校验后装配闭包。
generatedPrototype :: SDK.Prototype MethodGen
generatedPrototype =
  SDK.Prototype
    { SDK.protoRegistrations =
        [ SDK.EffectSpec
            { SDK.name = "FileLocation"
            , SDK.typing = SDK.Context (Just (SDK.Requester ("fileName") (SDK.TypeRef ("[Char]"))))
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
            , SDK.typing = SDK.Context (Just (SDK.Requester ("openedFile") (SDK.TypeRef ("FileHandle"))))
            , SDK.input = "ValidateFileName"
            , SDK.demands = [SDK.Demand (SDK.RequireAccess) ("FileName")]
            }
        , SDK.EffectSpec
            { SDK.name = "FileSession"
            , SDK.typing = SDK.Scoped (Just "openFileSession") (Just "closeFileSession")
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
                  ([SDK.RaisedBy ("ReadFile"), SDK.RaisedBy ("WriteFirstLine"), SDK.RaisedBy ("AppendLine")])
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
            , SDK.typing = SDK.Context (Just (SDK.Requester ("fileText") (SDK.TypeRef ("TextState"))))
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
            { SDK.effectName = "ValidateFileName"
            , SDK.effectKind = SDK.PureKind
            , SDK.effectInput = "Root"
            , SDK.effectMethods = [(SDK.HandlerMethod, ValidateFileNameGen)]
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
            }
        , SDK.EffectProto
            { SDK.effectName = "FileResource"
            , SDK.effectKind = SDK.ContextKind
            , SDK.effectInput = "ValidateFileName"
            , SDK.effectMethods =
                [(SDK.ContextRequest, OpenedFileGen), (SDK.ContextRequire, ReadOpenedFileGen)]
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
            }
        , SDK.EffectProto
            { SDK.effectName = "FileRecovery"
            , SDK.effectKind = SDK.ErrorKind
            , SDK.effectInput = "FileSession"
            , SDK.effectMethods =
                [(SDK.ErrorDetect, DetectFileSessionGen), (SDK.ErrorResolve, ResolveFileSessionGen)]
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
            }
        , SDK.EffectProto
            { SDK.effectName = "ReadFile"
            , SDK.effectKind = SDK.ExcuKind
            , SDK.effectInput = "FileSession"
            , SDK.effectMethods = [(SDK.HandlerMethod, ReadFileContentGen)]
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
            }
        , SDK.EffectProto
            { SDK.effectName = "ExtractFileText"
            , SDK.effectKind = SDK.ContextKind
            , SDK.effectInput = "ReadFile"
            , SDK.effectMethods = [(SDK.ContextRequest, FileTextGen), (SDK.ContextRequire, ReadFileTextGen)]
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
            }
        , SDK.EffectProto
            { SDK.effectName = "WriteFirstLine"
            , SDK.effectKind = SDK.ExcuKind
            , SDK.effectInput = "FileSession"
            , SDK.effectMethods = [(SDK.HandlerMethod, WriteFirstLineGen)]
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
            }
        , SDK.EffectProto
            { SDK.effectName = "AppendLine"
            , SDK.effectKind = SDK.ExcuKind
            , SDK.effectInput = "FileSession"
            , SDK.effectMethods = [(SDK.HandlerMethod, AppendLineGen)]
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
            }
        ]
    , SDK.protoMethods =
        [ SDK.MethodDefinition (FileNameGen) (FileNameGen) (SDK.ContextRequest) (SDK.Empty)
        , SDK.MethodDefinition
            (ReadFileNameGen)
            (FileNameGen)
            (SDK.ContextRequire)
            (SDK.Choice ([SDK.Empty, SDK.Call (FileNameGen)]))
        , SDK.MethodDefinition
            (ValidateFileNameGen)
            (ValidateFileNameGen)
            (SDK.HandlerMethod)
            (SDK.Call (ReadFileNameGen))
        , SDK.MethodDefinition
            (OpenedFileGen)
            (OpenedFileGen)
            (SDK.ContextRequest)
            (SDK.Sequence ([SDK.Call (ValidateFileNameGen), SDK.Call (ReadFileNameGen)]))
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
            (DetectFileSessionGen)
            (DetectFileSessionGen)
            (SDK.ErrorDetect)
            (SDK.Call (ReadOpenedFileGen))
        , SDK.MethodDefinition
            (ResolveFileSessionGen)
            (DetectFileSessionGen)
            (SDK.ErrorResolve)
            (SDK.Call (CloseFileSessionGen))
        , SDK.MethodDefinition
            (ReadFileContentGen)
            (ReadFileContentGen)
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
            (FileTextGen)
            (FileTextGen)
            (SDK.ContextRequest)
            (SDK.Call (ReadFileContentGen))
        , SDK.MethodDefinition
            (ReadFileTextGen)
            (FileTextGen)
            (SDK.ContextRequire)
            (SDK.Choice ([SDK.Empty, SDK.Call (FileTextGen)]))
        , SDK.MethodDefinition
            (WriteFirstLineGen)
            (WriteFirstLineGen)
            (SDK.HandlerMethod)
            (
              SDK.Sequence
                ([SDK.Call (OpenFileSessionGen), SDK.Call (ReadFileTextGen), SDK.Call (ReadOpenedFileGen)])
            )
        , SDK.MethodDefinition
            (AppendLineGen)
            (AppendLineGen)
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
    , SDK.protoChains =
        [ SDK.ChainProto
            { SDK.chainNode = [0]
            , SDK.chainRole = SDK.NodeChain
            , SDK.chainTerminal = "WriteFirstLine"
            , SDK.chainEntry = WriteFirstLineGen
            , SDK.chainReaches =
                [ WriteFirstLineGen
                , OpenFileSessionGen
                , OpenedFileGen
                , ValidateFileNameGen
                , ReadFileNameGen
                , FileNameGen
                , ReadFileTextGen
                , FileTextGen
                , ReadFileContentGen
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
            , SDK.chainEntry = AppendLineGen
            , SDK.chainReaches =
                [ AppendLineGen
                , OpenFileSessionGen
                , OpenedFileGen
                , ValidateFileNameGen
                , ReadFileNameGen
                , FileNameGen
                , ReadFileTextGen
                , FileTextGen
                , ReadFileContentGen
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
                , FileTextGen
                , ReadFileContentGen
                , OpenFileSessionGen
                , OpenedFileGen
                , ValidateFileNameGen
                , ReadFileNameGen
                , FileNameGen
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
            { SDK.definitionKind = SDK.OriginChain
            , SDK.definitionEffect = "ValidateFileName"
            , SDK.definitionEntry = ValidateFileNameGen
            , SDK.definitionReaches = [ValidateFileNameGen, ReadFileNameGen, FileNameGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.ContextChain
            , SDK.definitionEffect = "FileResource"
            , SDK.definitionEntry = OpenedFileGen
            , SDK.definitionReaches = [OpenedFileGen, ValidateFileNameGen, ReadFileNameGen, FileNameGen]
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
                [OpenFileSessionGen, OpenedFileGen, ValidateFileNameGen, ReadFileNameGen, FileNameGen]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.OriginChain
            , SDK.definitionEffect = "ReadFile"
            , SDK.definitionEntry = ReadFileContentGen
            , SDK.definitionReaches =
                [ ReadFileContentGen
                , OpenFileSessionGen
                , OpenedFileGen
                , ValidateFileNameGen
                , ReadFileNameGen
                , FileNameGen
                , ReadOpenedFileGen
                , FileTextGen
                ]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.ContextChain
            , SDK.definitionEffect = "ExtractFileText"
            , SDK.definitionEntry = FileTextGen
            , SDK.definitionReaches =
                [ FileTextGen
                , ReadFileContentGen
                , OpenFileSessionGen
                , OpenedFileGen
                , ValidateFileNameGen
                , ReadFileNameGen
                , FileNameGen
                , ReadOpenedFileGen
                ]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.ContextChain
            , SDK.definitionEffect = "ExtractFileText"
            , SDK.definitionEntry = ReadFileTextGen
            , SDK.definitionReaches =
                [ ReadFileTextGen
                , FileTextGen
                , ReadFileContentGen
                , OpenFileSessionGen
                , OpenedFileGen
                , ValidateFileNameGen
                , ReadFileNameGen
                , FileNameGen
                , ReadOpenedFileGen
                ]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.OriginChain
            , SDK.definitionEffect = "WriteFirstLine"
            , SDK.definitionEntry = WriteFirstLineGen
            , SDK.definitionReaches =
                [ WriteFirstLineGen
                , OpenFileSessionGen
                , OpenedFileGen
                , ValidateFileNameGen
                , ReadFileNameGen
                , FileNameGen
                , ReadFileTextGen
                , FileTextGen
                , ReadFileContentGen
                , ReadOpenedFileGen
                ]
            }
        , SDK.ChainDefinition
            { SDK.definitionKind = SDK.OriginChain
            , SDK.definitionEffect = "AppendLine"
            , SDK.definitionEntry = AppendLineGen
            , SDK.definitionReaches =
                [ AppendLineGen
                , OpenFileSessionGen
                , OpenedFileGen
                , ValidateFileNameGen
                , ReadFileNameGen
                , FileNameGen
                , ReadFileTextGen
                , FileTextGen
                , ReadFileContentGen
                , ReadOpenedFileGen
                ]
            }
        ]
    , SDK.protoGraph =
        SDK.EffectGraph
          { SDK.graphMethods =
              [ SDK.MethodDefinition
                  (WriteFirstLineGen)
                  (WriteFirstLineGen)
                  (SDK.HandlerMethod)
                  (
                    SDK.Sequence
                      ([SDK.Call (OpenFileSessionGen), SDK.Call (ReadFileTextGen), SDK.Call (ReadOpenedFileGen)])
                  )
              , SDK.MethodDefinition
                  (OpenFileSessionGen)
                  (OpenFileSessionGen)
                  (SDK.ScopeOpen)
                  (SDK.Call (OpenedFileGen))
              , SDK.MethodDefinition
                  (OpenedFileGen)
                  (OpenedFileGen)
                  (SDK.ContextRequest)
                  (SDK.Sequence ([SDK.Call (ValidateFileNameGen), SDK.Call (ReadFileNameGen)]))
              , SDK.MethodDefinition
                  (ValidateFileNameGen)
                  (ValidateFileNameGen)
                  (SDK.HandlerMethod)
                  (SDK.Call (ReadFileNameGen))
              , SDK.MethodDefinition
                  (ReadFileNameGen)
                  (FileNameGen)
                  (SDK.ContextRequire)
                  (SDK.Choice ([SDK.Empty, SDK.Call (FileNameGen)]))
              , SDK.MethodDefinition (FileNameGen) (FileNameGen) (SDK.ContextRequest) (SDK.Empty)
              , SDK.MethodDefinition
                  (ReadFileTextGen)
                  (FileTextGen)
                  (SDK.ContextRequire)
                  (SDK.Choice ([SDK.Empty, SDK.Call (FileTextGen)]))
              , SDK.MethodDefinition
                  (FileTextGen)
                  (FileTextGen)
                  (SDK.ContextRequest)
                  (SDK.Call (ReadFileContentGen))
              , SDK.MethodDefinition
                  (ReadFileContentGen)
                  (ReadFileContentGen)
                  (SDK.HandlerMethod)
                  (
                    SDK.Sequence
                      (
                        [ SDK.Sequence ([SDK.Call (OpenFileSessionGen), SDK.Call (ReadOpenedFileGen)])
                        , SDK.Choice ([SDK.Empty, SDK.Sequence ([SDK.Empty])])
                        ]
                      )
                  )
              , SDK.MethodDefinition (ReadOpenedFileGen) (OpenedFileGen) (SDK.ContextRequire) (SDK.Empty)
              , SDK.MethodDefinition
                  (AppendLineGen)
                  (AppendLineGen)
                  (SDK.HandlerMethod)
                  (
                    SDK.Sequence
                      ([SDK.Call (OpenFileSessionGen), SDK.Call (ReadFileTextGen), SDK.Call (ReadOpenedFileGen)])
                  )
              ]
          , SDK.graphRoots = [WriteFirstLineGen, AppendLineGen, ReadFileTextGen]
          , SDK.graphReferences =
              [ (WriteFirstLineGen, OpenFileSessionGen)
              , (WriteFirstLineGen, ReadFileTextGen)
              , (WriteFirstLineGen, ReadOpenedFileGen)
              , (OpenFileSessionGen, OpenedFileGen)
              , (OpenedFileGen, ValidateFileNameGen)
              , (OpenedFileGen, ReadFileNameGen)
              , (ValidateFileNameGen, ReadFileNameGen)
              , (ReadFileNameGen, FileNameGen)
              , (ReadFileTextGen, FileTextGen)
              , (FileTextGen, ReadFileContentGen)
              , (ReadFileContentGen, OpenFileSessionGen)
              , (ReadFileContentGen, ReadOpenedFileGen)
              , (AppendLineGen, OpenFileSessionGen)
              , (AppendLineGen, ReadFileTextGen)
              , (AppendLineGen, ReadOpenedFileGen)
              ]
          , SDK.graphScopes = [OpenFileSessionGen]
          , SDK.graphScopePaths = [[OpenFileSessionGen], []]
          , SDK.graphRootPaths =
              [ (WriteFirstLineGen, [[OpenFileSessionGen]])
              , (AppendLineGen, [[OpenFileSessionGen]])
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
