{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE TypeFamilies #-}

-- 自动生成；只登记末端句柄，Node algebra 才 lower，业务组合仍在 handler 内。
module OpenFilesDemo.Generated.Program where

import Framework.SDK (Effect(..), EffectSpec(..), EffectTyping(..), Producer(..), ContextInput(..), ValueSource(..), TypeRef(..), Output)
import qualified Framework.SDK as SDK
import qualified Framework.Effect.Contract as FrameworkRoot
import OpenFilesDemo.Generated.Effects
import qualified OpenFilesDemo.Generated.Handlers as Handlers
import OpenFilesDemo.Types

-- 编译时注册快照；运行前核对声明，改变连接后须重新生成。
registeredEffects :: [EffectSpec]
registeredEffects =
  [ EffectSpec {name = "FileLocations", typing = Context {request = Just (Producer {handler = "getFileNames", produces = TypeRef "FileNames"}), require = Just "readFileNames"}, input = "Root", context = Nothing}
  , EffectSpec {name = "FileResources", typing = Context {request = Just (Producer {handler = "acquireFiles", produces = TypeRef "OpenedFiles"}), require = Just "readOpenedFiles"}, input = "Root", context = Just (ContextInput {request = Nothing, require = Just (From "FileLocations" (TypeRef "FileNames"))})}
  , EffectSpec {name = "FileSession", typing = Scoped {open = Just "openFiles", close = Just "closeFiles"}, input = "Root", context = Just (ContextInput {request = Just (From "FileResources" (TypeRef "OpenedFiles")), require = Just (From "FileResources" (TypeRef "OpenedFiles"))})}
  , EffectSpec {name = "HoldFiles", typing = Excu {handler = Just "holdFiles"}, input = "FileSession", context = Just (ContextInput {request = Just (From "FileLocations" (TypeRef "FileNames")), require = Nothing})}
  , EffectSpec {name = "InspectFiles", typing = Excu {handler = Just "inspectFiles"}, input = "HoldFiles", context = Just (ContextInput {request = Nothing, require = Just (From "FileResources" (TypeRef "OpenedFiles"))})}
  , EffectSpec {name = "FinishInspection", typing = Excu {handler = Just "finishInspection"}, input = "InspectFiles", context = Just (ContextInput {request = Nothing, require = Just (From "FileResources" (TypeRef "OpenedFiles"))})}
  ]

-- 生成身份连接到已有运行 scope 名；依赖只保存在下方显式 ScopeTree 中。
scopeNames :: [(MethodGen, String)]
scopeNames = [(OpenFilesGen, "FileSession")]

-- 运行只 fold 当前 workflow，并校验入口集合及生成常量；不重新构图。
programStructure :: SDK.AST -> Either (SDK.StructureError MethodGen) (SDK.ProgramStructure MethodGen)
programStructure = SDK.initializeGeneratedStructure
  [("HoldFiles", HoldFilesGen), ("InspectFiles", InspectFilesGen), ("FinishInspection", FinishInspectionGen)]
  scopeNames generatedEffectGraph generatedScopeTree


-- 仅汇总所选末端的成功产物，不保存共享绑定或增加完成包装。
data Results = HoldFilesResult (Produce HoldFiles) | InspectFilesResult (Produce InspectFiles) | FinishInspectionResult (Produce FinishInspection)
  deriving Show

-- 末端共享生成的 scope 句柄；只创建空状态，Node algebra 才 lower，业务调用仍在 instance 内。
compiledEntries :: IO [SDK.Target IO ContextValues Errors Results]
compiledEntries = do
  scopes <- Handlers.newScopeHandlers
  pure
    [ SDK.targetApp "HoldFiles" emptyContexts scopes (FrameworkRoot.withErrorHandlers Handlers.errorHandlers (SDK.withScopeCleanups Handlers.scopeCleanups (HoldFilesResult <$> holdFiles)))
    , SDK.targetApp "InspectFiles" emptyContexts scopes (FrameworkRoot.withErrorHandlers Handlers.errorHandlers (SDK.withScopeCleanups Handlers.scopeCleanups (InspectFilesResult <$> inspectFiles)))
    , SDK.targetApp "FinishInspection" emptyContexts scopes (FrameworkRoot.withErrorHandlers Handlers.errorHandlers (SDK.withScopeCleanups Handlers.scopeCleanups (FinishInspectionResult <$> finishInspection)))
    ]

-- SDK 装配入口，不需要用户提供节点执行器或重复选择 handler。
interpreter :: SDK.AST -> [EffectSpec] -> IO ()
interpreter = SDK.interpreter "OpenFilesDemo" registeredEffects Handlers.handlerSourceFingerprint programStructure compiledEntries
-- 生成时已完成方法展开与路径分析；运行时只读取显式 ADT 值。
generatedEffectGraph :: SDK.EffectGraph MethodGen
generatedEffectGraph = SDK.EffectGraph
  { SDK.graphMethods =
      [ SDK.MethodDefinition HoldFilesGen HoldFilesGen SDK.HandlerMethod (SDK.Sequence [SDK.Call GetFileNamesGen, SDK.Call OpenFilesGen])
      , SDK.MethodDefinition GetFileNamesGen GetFileNamesGen SDK.ContextRequest (SDK.Empty)
      , SDK.MethodDefinition OpenFilesGen OpenFilesGen SDK.ScopeOpen (SDK.Call AcquireFilesGen)
      , SDK.MethodDefinition AcquireFilesGen AcquireFilesGen SDK.ContextRequest (SDK.Call GetFileNamesGen)
      , SDK.MethodDefinition ReadFileNamesGen GetFileNamesGen SDK.ContextRequire (SDK.Empty)
      , SDK.MethodDefinition InspectFilesGen InspectFilesGen SDK.HandlerMethod (SDK.Sequence [SDK.Call HoldFilesGen, SDK.Call ReadOpenedFilesGen])
      , SDK.MethodDefinition ReadOpenedFilesGen AcquireFilesGen SDK.ContextRequire (SDK.Empty)
      , SDK.MethodDefinition FinishInspectionGen FinishInspectionGen SDK.HandlerMethod (SDK.Sequence [SDK.Call HoldFilesGen, SDK.Call ReadOpenedFilesGen, SDK.Call CloseFilesGen])
      , SDK.MethodDefinition CloseFilesGen OpenFilesGen SDK.ScopeClose (SDK.Call ReadOpenedFilesGen)
      ]
  , SDK.graphRoots = [HoldFilesGen, InspectFilesGen, FinishInspectionGen]
  , SDK.graphReferences = [(HoldFilesGen, GetFileNamesGen), (HoldFilesGen, OpenFilesGen), (OpenFilesGen, AcquireFilesGen), (AcquireFilesGen, ReadFileNamesGen), (InspectFilesGen, HoldFilesGen), (InspectFilesGen, ReadOpenedFilesGen), (FinishInspectionGen, HoldFilesGen), (FinishInspectionGen, ReadOpenedFilesGen), (FinishInspectionGen, CloseFilesGen), (CloseFilesGen, ReadOpenedFilesGen)]
  , SDK.graphScopes = [OpenFilesGen]
  , SDK.graphScopePaths = [[OpenFilesGen]]
  , SDK.graphRootPaths =
      [ (HoldFilesGen, [[OpenFilesGen]])
      , (InspectFilesGen, [[OpenFilesGen]])
      , (FinishInspectionGen, [[OpenFilesGen]])
      ]
  , SDK.graphScopeOrder = []
  }

-- 唯一的 ScopeTree：共同前序与注册前提已合并、检查环并约简。
generatedScopeTree :: SDK.ScopeTree MethodGen
generatedScopeTree = SDK.ScopeTree
  { SDK.scopeRoots = [OpenFilesGen]
  , SDK.scopeNodes =
      [ SDK.ScopeNode { SDK.scopeIdentity = OpenFilesGen, SDK.scopeParents = [], SDK.scopeChildren = [] }
      ]
  , SDK.scopeLayers = [[OpenFilesGen]]
  , SDK.scopePaths = [[OpenFilesGen]]
  , SDK.scopeCandidates = []
  , SDK.scopeOpposed = []
  , SDK.scopeUndetermined = []
  }
