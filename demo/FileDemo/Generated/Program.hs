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

-- 编译时注册快照；运行前核对声明，改变连接后须重新生成。
registeredEffects :: [EffectSpec]
registeredEffects =
  [ EffectSpec {name = "FileLocation", typing = Context {request = Just (Requester {handler = "fileName", representation = TypeRef "[Char]"})}, input = "Root", demands = []}
  , EffectSpec {name = "ValidateFileName", typing = Pure {handler = Just "validateFileName"}, input = "Root", demands = [Demand {access = RequireAccess, contract = "FileName"}]}
  , EffectSpec {name = "FileResource", typing = Context {request = Just (Requester {handler = "openedFile", representation = TypeRef "FileHandle"})}, input = "ValidateFileName", demands = [Demand {access = RequireAccess, contract = "FileName"}]}
  , EffectSpec {name = "FileSession", typing = Scoped {open = Just "openFileSession", close = Just "closeFileSession"}, input = "ValidateFileName", demands = [Demand {access = RequestAccess, contract = "OpenedFile"},Demand {access = RequireAccess, contract = "OpenedFile"}]}
  , EffectSpec {name = "FileRecovery", typing = Error {detect = Just "detectFileSession", resolve = Just "resolveFileSession", handles = [RaisedBy "ReadFile",RaisedBy "WriteFile"]}, input = "FileSession", demands = [Demand {access = RequireAccess, contract = "OpenedFile"}]}
  , EffectSpec {name = "ReadFile", typing = Excu {handler = Just "readFileContent"}, input = "FileSession", demands = [Demand {access = RequireAccess, contract = "OpenedFile"}]}
  , EffectSpec {name = "ExtractFileText", typing = Context {request = Just (Requester {handler = "fileText", representation = TypeRef "[Char]"})}, input = "ReadFile", demands = []}
  , EffectSpec {name = "WriteFile", typing = Excu {handler = Just "writeFileText"}, input = "ReadFile", demands = [Demand {access = RequireAccess, contract = "FileText"},Demand {access = RequireAccess, contract = "OpenedFile"}]}
  , EffectSpec {name = "FileWorkflow", typing = Excu {handler = Just "runFileWorkflow"}, input = "WriteFile", demands = [Demand {access = RequestAccess, contract = "FileName"}]}
  ]

-- 生成身份连接到已有运行 scope 名；依赖只保存在下方显式 ScopeTree 中。
scopeNames :: [(MethodGen, String)]
scopeNames = [(OpenFileSessionGen, "FileSession")]

-- 只校验生成常量；当前 workflow 在执行装配的一次 fold 中检查入口。
programStructure :: Either (SDK.StructureError MethodGen) (SDK.ProgramStructure MethodGen)
programStructure = SDK.initializeGeneratedStructure
  [("FileWorkflow", RunFileWorkflowGen)]
  scopeNames generatedEffectGraph generatedScopeTree


-- 仅汇总所选末端的成功产物，不保存共享绑定或增加完成包装。
data Results = FileWorkflowResult (Produce FileWorkflow)
  deriving Show

-- 末端共享生成的 scope 句柄；只创建空状态，Node algebra 才 lower，业务调用仍在 instance 内。
compiledEntries :: IO [SDK.Target ContextValues Errors Results]
compiledEntries = do
  scopes <- Handlers.newScopeHandlers
  pure
    [ SDK.targetApp "FileWorkflow" emptyContexts scopes (FrameworkRoot.withErrorHandlers Handlers.errorHandlers (FrameworkRoot.withAnchoredContexts Handlers.contextInjections (SDK.withScopeCleanups Handlers.scopeCleanups (FileWorkflowResult <$> (() <$ runFileWorkflow)))))
    ]

-- SDK 装配入口，不需要用户提供节点执行器或重复选择 handler。
interpreter :: SDK.AST -> [EffectSpec] -> IO ()
interpreter = SDK.interpreter "FileDemo" registeredEffects Handlers.handlerSourceFingerprint programStructure compiledEntries
-- 生成时已完成方法展开与路径分析；运行时只读取显式 ADT 值。
generatedEffectGraph :: SDK.EffectGraph MethodGen
generatedEffectGraph = SDK.EffectGraph
  { SDK.graphMethods =
      [ SDK.MethodDefinition RunFileWorkflowGen RunFileWorkflowGen SDK.HandlerMethod (SDK.Sequence [SDK.Call FileNameGen, SDK.Call OpenFileSessionGen, SDK.Call WriteFileTextGen])
      , SDK.MethodDefinition FileNameGen FileNameGen SDK.ContextRequest (SDK.Empty)
      , SDK.MethodDefinition OpenFileSessionGen OpenFileSessionGen SDK.ScopeOpen (SDK.Call OpenedFileGen)
      , SDK.MethodDefinition OpenedFileGen OpenedFileGen SDK.ContextRequest (SDK.Sequence [SDK.Call ValidateFileNameGen, SDK.Call ReadFileNameGen])
      , SDK.MethodDefinition ValidateFileNameGen ValidateFileNameGen SDK.HandlerMethod (SDK.Call ReadFileNameGen)
      , SDK.MethodDefinition ReadFileNameGen FileNameGen SDK.ContextRequire (SDK.Choice [SDK.Empty, SDK.Call FileNameGen])
      , SDK.MethodDefinition WriteFileTextGen WriteFileTextGen SDK.HandlerMethod (SDK.Sequence [SDK.Call ReadFileContentGen, SDK.Call ReadFileTextGen, SDK.Call ReadOpenedFileGen])
      , SDK.MethodDefinition ReadFileContentGen ReadFileContentGen SDK.HandlerMethod (SDK.Sequence [SDK.Sequence [SDK.Call OpenFileSessionGen, SDK.Call ReadOpenedFileGen], SDK.Choice [SDK.Empty, SDK.Sequence [SDK.Empty]]])
      , SDK.MethodDefinition ReadOpenedFileGen OpenedFileGen SDK.ContextRequire (SDK.Empty)
      , SDK.MethodDefinition ReadFileTextGen FileTextGen SDK.ContextRequire (SDK.Choice [SDK.Empty, SDK.Call FileTextGen])
      , SDK.MethodDefinition FileTextGen FileTextGen SDK.ContextRequest (SDK.Call ReadFileContentGen)
      ]
  , SDK.graphRoots = [RunFileWorkflowGen]
  , SDK.graphReferences = [(RunFileWorkflowGen, FileNameGen), (RunFileWorkflowGen, OpenFileSessionGen), (RunFileWorkflowGen, WriteFileTextGen), (OpenFileSessionGen, OpenedFileGen), (OpenedFileGen, ValidateFileNameGen), (OpenedFileGen, ReadFileNameGen), (ValidateFileNameGen, ReadFileNameGen), (ReadFileNameGen, FileNameGen), (WriteFileTextGen, ReadFileContentGen), (WriteFileTextGen, ReadFileTextGen), (WriteFileTextGen, ReadOpenedFileGen), (ReadFileContentGen, OpenFileSessionGen), (ReadFileContentGen, ReadOpenedFileGen), (ReadFileTextGen, FileTextGen), (FileTextGen, ReadFileContentGen)]
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
