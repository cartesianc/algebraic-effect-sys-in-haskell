{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE TypeFamilies #-}

-- 自动生成；只登记末端句柄，Node algebra 才 lower，业务组合仍在 handler 内。
module ScopeInstancesDemo.Generated.Program where

import Framework.SDK (Effect(..), EffectSpec(..), EffectTyping(..), Producer(..), Handles(..), Demand(..), Access(..), TypeRef(..), Output)
import qualified Framework.SDK as SDK
import qualified Framework.Effect.Contract as FrameworkRoot
import ScopeInstancesDemo.Generated.Effects hiding (request, require)
import qualified ScopeInstancesDemo.Generated.Handlers as Handlers
import ScopeInstancesDemo.Types

-- 编译时注册快照；运行前核对声明，改变连接后须重新生成。
registeredEffects :: [EffectSpec]
registeredEffects =
  [ EffectSpec {name = "PrepareFiles", typing = Excu {handler = Just "prepareFiles"}, input = "Root", demands = []}
  , EffectSpec {name = "FileLocation", typing = Context {request = Just (Producer {handler = "getFileName", produces = TypeRef "FileName"}), require = Just "readFileName"}, input = "Root", demands = []}
  , EffectSpec {name = "FileResource", typing = Context {request = Just (Producer {handler = "acquireFile", produces = TypeRef "OpenedFile"}), require = Just "readOpenedFile"}, input = "Root", demands = [Demand {access = RequireAccess, contract = TypeRef "FileName"}]}
  , EffectSpec {name = "FileSession", typing = Scoped {open = Just "openFileSession", close = Just "closeFileSession"}, input = "Root", demands = [Demand {access = RequestAccess, contract = TypeRef "OpenedFile"},Demand {access = RequireAccess, contract = TypeRef "OpenedFile"}]}
  , EffectSpec {name = "CheckIndependent", typing = Excu {handler = Just "checkIndependent"}, input = "FileSession", demands = [Demand {access = RequestAccess, contract = TypeRef "FileName"},Demand {access = RequireAccess, contract = TypeRef "OpenedFile"}]}
  , EffectSpec {name = "CheckReopen", typing = Excu {handler = Just "checkReopen"}, input = "FileSession", demands = [Demand {access = RequestAccess, contract = TypeRef "FileName"},Demand {access = RequireAccess, contract = TypeRef "OpenedFile"}]}
  ]

-- 生成身份连接到已有运行 scope 名；依赖只保存在下方显式 ScopeTree 中。
scopeNames :: [(MethodGen, String)]
scopeNames = [(OpenFileSessionGen, "FileSession")]

-- 只校验生成常量；当前 workflow 在执行装配的一次 fold 中检查入口。
programStructure :: Either (SDK.StructureError MethodGen) (SDK.ProgramStructure MethodGen)
programStructure = SDK.initializeGeneratedStructure
  [("PrepareFiles", PrepareFilesGen), ("CheckIndependent", CheckIndependentGen), ("CheckReopen", CheckReopenGen)]
  scopeNames generatedEffectGraph generatedScopeTree


-- 仅汇总所选末端的成功产物，不保存共享绑定或增加完成包装。
data Results = PrepareFilesResult (Produce PrepareFiles) | CheckIndependentResult (Produce CheckIndependent) | CheckReopenResult (Produce CheckReopen)
  deriving Show

-- 末端共享生成的 scope 句柄；只创建空状态，Node algebra 才 lower，业务调用仍在 instance 内。
compiledEntries :: IO [SDK.Target IO ContextValues Errors Results]
compiledEntries = do
  scopes <- Handlers.newScopeHandlers
  pure
    [ SDK.targetApp "PrepareFiles" emptyContexts scopes (FrameworkRoot.withErrorHandlers Handlers.errorHandlers (SDK.withScopeCleanups Handlers.scopeCleanups (PrepareFilesResult <$> prepareFiles)))
    , SDK.targetApp "CheckIndependent" emptyContexts scopes (FrameworkRoot.withErrorHandlers Handlers.errorHandlers (SDK.withScopeCleanups Handlers.scopeCleanups (CheckIndependentResult <$> checkIndependent)))
    , SDK.targetApp "CheckReopen" emptyContexts scopes (FrameworkRoot.withErrorHandlers Handlers.errorHandlers (SDK.withScopeCleanups Handlers.scopeCleanups (CheckReopenResult <$> checkReopen)))
    ]

-- SDK 装配入口，不需要用户提供节点执行器或重复选择 handler。
interpreter :: SDK.AST -> [EffectSpec] -> IO ()
interpreter = SDK.interpreter "ScopeInstancesDemo" registeredEffects Handlers.handlerSourceFingerprint programStructure compiledEntries
-- 生成时已完成方法展开与路径分析；运行时只读取显式 ADT 值。
generatedEffectGraph :: SDK.EffectGraph MethodGen
generatedEffectGraph = SDK.EffectGraph
  { SDK.graphMethods =
      [ SDK.MethodDefinition PrepareFilesGen PrepareFilesGen SDK.HandlerMethod (SDK.Empty)
      , SDK.MethodDefinition CheckIndependentGen CheckIndependentGen SDK.HandlerMethod (SDK.Sequence [SDK.Call GetFileNameGen, SDK.Call OpenFileSessionGen, SDK.Call ReadOpenedFileGen, SDK.Call OpenFileSessionGen, SDK.Call ReadOpenedFileGen, SDK.Call GetFileNameGen, SDK.Call OpenFileSessionGen, SDK.Call ReadOpenedFileGen, SDK.Call CloseFileSessionGen, SDK.Call CloseFileSessionGen])
      , SDK.MethodDefinition GetFileNameGen GetFileNameGen SDK.ContextRequest (SDK.Empty)
      , SDK.MethodDefinition OpenFileSessionGen OpenFileSessionGen SDK.ScopeOpen (SDK.Call AcquireFileGen)
      , SDK.MethodDefinition AcquireFileGen AcquireFileGen SDK.ContextRequest (SDK.Call ReadFileNameGen)
      , SDK.MethodDefinition ReadFileNameGen GetFileNameGen SDK.ContextRequire (SDK.Empty)
      , SDK.MethodDefinition ReadOpenedFileGen AcquireFileGen SDK.ContextRequire (SDK.Empty)
      , SDK.MethodDefinition CloseFileSessionGen OpenFileSessionGen SDK.ScopeClose (SDK.Call ReadOpenedFileGen)
      , SDK.MethodDefinition CheckReopenGen CheckReopenGen SDK.HandlerMethod (SDK.Sequence [SDK.Call GetFileNameGen, SDK.Call OpenFileSessionGen, SDK.Call ReadOpenedFileGen, SDK.Call CloseFileSessionGen, SDK.Call GetFileNameGen, SDK.Call OpenFileSessionGen, SDK.Call ReadOpenedFileGen, SDK.Call CloseFileSessionGen])
      ]
  , SDK.graphRoots = [PrepareFilesGen, CheckIndependentGen, CheckReopenGen]
  , SDK.graphReferences = [(CheckIndependentGen, GetFileNameGen), (CheckIndependentGen, OpenFileSessionGen), (CheckIndependentGen, ReadOpenedFileGen), (CheckIndependentGen, CloseFileSessionGen), (OpenFileSessionGen, AcquireFileGen), (AcquireFileGen, ReadFileNameGen), (CloseFileSessionGen, ReadOpenedFileGen), (CheckReopenGen, GetFileNameGen), (CheckReopenGen, OpenFileSessionGen), (CheckReopenGen, ReadOpenedFileGen), (CheckReopenGen, CloseFileSessionGen)]
  , SDK.graphScopes = [OpenFileSessionGen]
  , SDK.graphScopePaths = [[], [OpenFileSessionGen]]
  , SDK.graphRootPaths =
      [ (PrepareFilesGen, [[]])
      , (CheckIndependentGen, [[OpenFileSessionGen]])
      , (CheckReopenGen, [[OpenFileSessionGen]])
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
  , SDK.scopePaths = [[], [OpenFileSessionGen]]
  , SDK.scopeCandidates = []
  , SDK.scopeOpposed = []
  , SDK.scopeUndetermined = []
  }
