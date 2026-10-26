{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE TypeFamilies #-}

-- 自动生成；只登记末端句柄，Node algebra 才 lower，业务组合仍在 handler 内。
module FileDemo.Generated.Program where

import Framework.SDK (Effect(..), EffectSpec(..), EffectTyping(..), Producer(..), ContextInput(..), ValueSource(..), TypeRef(..), Output)
import qualified Framework.SDK as SDK
import qualified Framework.Effect.Contract as FrameworkRoot
import FileDemo.Generated.Effects
import qualified FileDemo.Generated.Handlers as Handlers
import FileDemo.Types

-- 编译时注册快照；运行前核对声明，改变连接后须重新生成。
registeredEffects :: [EffectSpec]
registeredEffects =
  [ EffectSpec {name = "FileLocation", typing = Context {request = Just (Producer {handler = "getFileName", produces = TypeRef "FileName"}), require = Just "readFileName"}, input = "Root", context = Nothing}
  , EffectSpec {name = "ValidateFileName", typing = Pure {handler = Just "validateFileName"}, input = "Root", context = Just (ContextInput {request = Nothing, require = Just (From "FileLocation" (TypeRef "FileName"))})}
  , EffectSpec {name = "FileResource", typing = Context {request = Just (Producer {handler = "acquireFile", produces = TypeRef "OpenedFile"}), require = Just "readOpenedFile"}, input = "ValidateFileName", context = Just (ContextInput {request = Nothing, require = Just (From "FileLocation" (TypeRef "FileName"))})}
  , EffectSpec {name = "FileSession", typing = Scoped {open = Just "openFileSession", close = Just "closeFileSession"}, input = "ValidateFileName", context = Just (ContextInput {request = Just (From "FileResource" (TypeRef "OpenedFile")), require = Just (From "FileResource" (TypeRef "OpenedFile"))})}
  , EffectSpec {name = "FileRecovery", typing = Error {detect = Just "detectFileSession", resolve = Just "resolveFileSession"}, input = "FileSession", context = Just (ContextInput {request = Nothing, require = Just (From "FileResource" (TypeRef "OpenedFile"))})}
  , EffectSpec {name = "ReadFile", typing = Context {request = Just (Producer {handler = "readFileText", produces = TypeRef "FileText"}), require = Just "readLastFileText"}, input = "FileSession", context = Just (ContextInput {request = Nothing, require = Just (From "FileResource" (TypeRef "OpenedFile"))})}
  , EffectSpec {name = "WriteFile", typing = Excu {handler = Just "writeFileText"}, input = "FileSession", context = Just (ContextInput {request = Just (From "ReadFile" (TypeRef "FileText")), require = Just (From "FileResource" (TypeRef "OpenedFile"))})}
  , EffectSpec {name = "FileWorkflow", typing = Excu {handler = Just "runFileWorkflow"}, input = "WriteFile", context = Just (ContextInput {request = Just (From "FileLocation" (TypeRef "FileName")), require = Nothing})}
  ]

-- 生成身份连接到已有运行 scope 名；依赖只保存在下方显式 ScopeTree 中。
scopeNames :: [(MethodGen, String)]
scopeNames = [(OpenFileSessionGen, "FileSession")]

-- 运行只 fold 当前 workflow，并校验入口集合及生成常量；不重新构图。
programStructure :: SDK.AST -> Either (SDK.StructureError MethodGen) (SDK.ProgramStructure MethodGen)
programStructure = SDK.initializeGeneratedStructure
  [("FileWorkflow", RunFileWorkflowGen)]
  scopeNames generatedEffectGraph generatedScopeTree


-- 仅汇总所选末端的成功产物，不保存共享绑定或增加完成包装。
data Results = FileWorkflowResult (Produce FileWorkflow)
  deriving Show

-- 末端共享生成的 scope 句柄；只创建空状态，Node algebra 才 lower，业务调用仍在 instance 内。
compiledEntries :: IO [SDK.Target IO ContextValues Errors Results]
compiledEntries = do
  scopes <- Handlers.newScopeHandlers
  pure
    [ SDK.targetApp "FileWorkflow" emptyContexts scopes (FrameworkRoot.withErrorHandlers Handlers.errorHandlers (SDK.withScopeCleanups Handlers.scopeCleanups (FileWorkflowResult <$> runFileWorkflow)))
    ]

-- SDK 装配入口，不需要用户提供节点执行器或重复选择 handler。
interpreter :: SDK.AST -> [EffectSpec] -> IO ()
interpreter = SDK.interpreter "FileDemo" registeredEffects Handlers.handlerSourceFingerprint programStructure compiledEntries
-- 生成时已完成方法展开与路径分析；运行时只读取显式 ADT 值。
generatedEffectGraph :: SDK.EffectGraph MethodGen
generatedEffectGraph = SDK.EffectGraph
  { SDK.graphMethods =
      [ SDK.MethodDefinition RunFileWorkflowGen RunFileWorkflowGen SDK.HandlerMethod (SDK.Sequence [SDK.Call GetFileNameGen, SDK.Call OpenFileSessionGen, SDK.Call WriteFileTextGen])
      , SDK.MethodDefinition GetFileNameGen GetFileNameGen SDK.ContextRequest (SDK.Empty)
      , SDK.MethodDefinition OpenFileSessionGen OpenFileSessionGen SDK.ScopeOpen (SDK.Call AcquireFileGen)
      , SDK.MethodDefinition AcquireFileGen AcquireFileGen SDK.ContextRequest (SDK.Sequence [SDK.Call ValidateFileNameGen, SDK.Call ReadFileNameGen])
      , SDK.MethodDefinition ValidateFileNameGen ValidateFileNameGen SDK.HandlerMethod (SDK.Call GetFileNameGen)
      , SDK.MethodDefinition ReadFileNameGen GetFileNameGen SDK.ContextRequire (SDK.Empty)
      , SDK.MethodDefinition WriteFileTextGen WriteFileTextGen SDK.HandlerMethod (SDK.Sequence [SDK.Call ReadFileTextGen, SDK.Call ReadOpenedFileGen])
      , SDK.MethodDefinition ReadFileTextGen ReadFileTextGen SDK.ContextRequest (SDK.Sequence [SDK.Call OpenFileSessionGen, SDK.Call ReadOpenedFileGen])
      , SDK.MethodDefinition ReadOpenedFileGen AcquireFileGen SDK.ContextRequire (SDK.Empty)
      ]
  , SDK.graphRoots = [RunFileWorkflowGen]
  , SDK.graphReferences = [(RunFileWorkflowGen, GetFileNameGen), (RunFileWorkflowGen, OpenFileSessionGen), (RunFileWorkflowGen, WriteFileTextGen), (OpenFileSessionGen, AcquireFileGen), (AcquireFileGen, ValidateFileNameGen), (AcquireFileGen, ReadFileNameGen), (ValidateFileNameGen, ReadFileNameGen), (WriteFileTextGen, ReadFileTextGen), (WriteFileTextGen, ReadOpenedFileGen), (ReadFileTextGen, OpenFileSessionGen), (ReadFileTextGen, ReadOpenedFileGen)]
  , SDK.graphScopes = [OpenFileSessionGen]
  , SDK.graphScopePaths = [[OpenFileSessionGen]]
  , SDK.graphRootPaths =
      [ (RunFileWorkflowGen, [[OpenFileSessionGen]])
      ]
  , SDK.graphScopeOrder = []
  }

-- 唯一的 ScopeTree：共同前序与注册前提已合并、检查环并约简。
generatedScopeTree :: SDK.ScopeTree MethodGen
generatedScopeTree = SDK.ScopeTree
  { SDK.scopeRoots = [OpenFileSessionGen]
  , SDK.scopeNodes =
      [ SDK.ScopeNode { SDK.scopeIdentity = OpenFileSessionGen, SDK.scopeParents = [], SDK.scopeChildren = [] }
      ]
  , SDK.scopeLayers = [[OpenFileSessionGen]]
  , SDK.scopePaths = [[OpenFileSessionGen]]
  , SDK.scopeCandidates = []
  , SDK.scopeOpposed = []
  , SDK.scopeUndetermined = []
  }
