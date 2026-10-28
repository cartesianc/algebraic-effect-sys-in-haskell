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
  , EffectSpec {name = "FileRecovery", typing = Error {detect = Just "detectFileSession", resolve = Just "resolveFileSession", handles = [RaisedBy "ReadFile",RaisedBy "WriteFirstLine",RaisedBy "AppendLine"]}, input = "FileSession", demands = [Demand {access = RequireAccess, contract = "OpenedFile"}]}
  , EffectSpec {name = "ReadFile", typing = Excu {handler = Just "readFileContent"}, input = "FileSession", demands = [Demand {access = RequireAccess, contract = "OpenedFile"}]}
  , EffectSpec {name = "ExtractFileText", typing = Context {request = Just (Requester {handler = "fileText", representation = TypeRef "TextState"})}, input = "ReadFile", demands = []}
  , EffectSpec {name = "WriteFirstLine", typing = Excu {handler = Just "writeFirstLine"}, input = "FileSession", demands = [Demand {access = RequireAccess, contract = "FileTextBlank"},Demand {access = RequireAccess, contract = "OpenedFile"}]}
  , EffectSpec {name = "AppendLine", typing = Excu {handler = Just "appendLine"}, input = "FileSession", demands = [Demand {access = RequireAccess, contract = "FileTextWritten"},Demand {access = RequireAccess, contract = "OpenedFile"}]}
  ]

-- 生成身份连接到已有运行 scope 名；依赖只保存在下方显式 ScopeTree 中。
scopeNames :: [(MethodGen, String)]
scopeNames = [(OpenFileSessionGen, "FileSession")]

-- 只校验生成常量；当前 workflow 在执行装配的一次 fold 中检查入口。
programStructure :: Either (SDK.StructureError MethodGen) (SDK.ProgramStructure MethodGen)
programStructure = SDK.initializeGeneratedStructure
  [("WriteFirstLine", WriteFirstLineGen), ("AppendLine", AppendLineGen), ("FileText", ReadFileTextGen)]
  scopeNames generatedEffectGraph generatedScopeTree


-- 仅汇总所选末端的成功产物，不保存共享绑定或增加完成包装。
data Results = WriteFirstLineResult (Produce WriteFirstLine) | AppendLineResult (Produce AppendLine)
  deriving Show

-- alternative 的候选：末端 → (转折契约, 构造器)。由 gencode 从注册推出；
-- 运行时只据此在已装配的闭包之间选择，不保存或重组 effect chain。
alternativeCases :: [(String, (String, String))]
alternativeCases = [("WriteFirstLine",("FileText","Blank")),("AppendLine",("FileText","Written"))]

-- 各转折契约的全部构造器；运行时据此重新核对当前 AST 的分组，过期配置不执行。
alternativeConstructors :: [(String, [String])]
alternativeConstructors = [("FileText",["Blank","Written"])]

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
interpreter = SDK.interpreter "FileDemo" registeredEffects Handlers.handlerSourceFingerprint programStructure alternativeCases alternativeConstructors compiledEntries
-- 生成时已完成方法展开与路径分析；运行时只读取显式 ADT 值。
generatedEffectGraph :: SDK.EffectGraph MethodGen
generatedEffectGraph = SDK.EffectGraph
  { SDK.graphMethods =
      [ SDK.MethodDefinition WriteFirstLineGen WriteFirstLineGen SDK.HandlerMethod (SDK.Sequence [SDK.Call OpenFileSessionGen, SDK.Call ReadFileTextGen, SDK.Call ReadOpenedFileGen])
      , SDK.MethodDefinition OpenFileSessionGen OpenFileSessionGen SDK.ScopeOpen (SDK.Call OpenedFileGen)
      , SDK.MethodDefinition OpenedFileGen OpenedFileGen SDK.ContextRequest (SDK.Sequence [SDK.Call ValidateFileNameGen, SDK.Call ReadFileNameGen])
      , SDK.MethodDefinition ValidateFileNameGen ValidateFileNameGen SDK.HandlerMethod (SDK.Call ReadFileNameGen)
      , SDK.MethodDefinition ReadFileNameGen FileNameGen SDK.ContextRequire (SDK.Choice [SDK.Empty, SDK.Call FileNameGen])
      , SDK.MethodDefinition FileNameGen FileNameGen SDK.ContextRequest (SDK.Empty)
      , SDK.MethodDefinition ReadFileTextGen FileTextGen SDK.ContextRequire (SDK.Choice [SDK.Empty, SDK.Call FileTextGen])
      , SDK.MethodDefinition FileTextGen FileTextGen SDK.ContextRequest (SDK.Call ReadFileContentGen)
      , SDK.MethodDefinition ReadFileContentGen ReadFileContentGen SDK.HandlerMethod (SDK.Sequence [SDK.Sequence [SDK.Call OpenFileSessionGen, SDK.Call ReadOpenedFileGen], SDK.Choice [SDK.Empty, SDK.Sequence [SDK.Empty]]])
      , SDK.MethodDefinition ReadOpenedFileGen OpenedFileGen SDK.ContextRequire (SDK.Empty)
      , SDK.MethodDefinition AppendLineGen AppendLineGen SDK.HandlerMethod (SDK.Sequence [SDK.Call OpenFileSessionGen, SDK.Call ReadFileTextGen, SDK.Call ReadOpenedFileGen])
      ]
  , SDK.graphRoots = [WriteFirstLineGen, AppendLineGen, ReadFileTextGen]
  , SDK.graphReferences = [(WriteFirstLineGen, OpenFileSessionGen), (WriteFirstLineGen, ReadFileTextGen), (WriteFirstLineGen, ReadOpenedFileGen), (OpenFileSessionGen, OpenedFileGen), (OpenedFileGen, ValidateFileNameGen), (OpenedFileGen, ReadFileNameGen), (ValidateFileNameGen, ReadFileNameGen), (ReadFileNameGen, FileNameGen), (ReadFileTextGen, FileTextGen), (FileTextGen, ReadFileContentGen), (ReadFileContentGen, OpenFileSessionGen), (ReadFileContentGen, ReadOpenedFileGen), (AppendLineGen, OpenFileSessionGen), (AppendLineGen, ReadFileTextGen), (AppendLineGen, ReadOpenedFileGen)]
  , SDK.graphScopes = [OpenFileSessionGen]
  , SDK.graphScopePaths = [[OpenFileSessionGen], []]
  , SDK.graphRootPaths =
      [ (WriteFirstLineGen, [[OpenFileSessionGen]])
      , (AppendLineGen, [[OpenFileSessionGen]])
      , (ReadFileTextGen, [[], [OpenFileSessionGen]])
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
  , SDK.scopePaths = [[OpenFileSessionGen], []]
  , SDK.scopeCandidates = []
  , SDK.scopeOpposed = []
  , SDK.scopeUndetermined = []
  }
