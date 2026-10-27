{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE TypeFamilies #-}

-- 自动生成；只登记末端句柄，Node algebra 才 lower，业务组合仍在 handler 内。
module ScopeReuseDemo.Generated.Program where

import Framework.SDK (Effect(..), EffectSpec(..), EffectTyping(..), Requester(..), Handles(..), Demand(..), Access(..), TypeRef(..), Output)
import qualified Framework.SDK as SDK
import qualified Framework.Effect.Contract as FrameworkRoot
import ScopeReuseDemo.Generated.Effects hiding (request, require)
import qualified ScopeReuseDemo.Generated.Handlers as Handlers
import ScopeReuseDemo.Types

-- 编译时注册快照；运行前核对声明，改变连接后须重新生成。
registeredEffects :: [EffectSpec]
registeredEffects =
  [ EffectSpec {name = "FileLocations", typing = Context {request = Just (Requester {handler = "filePaths", representation = TypeRef "SharedPaths"})}, input = "Root", demands = []}
  , EffectSpec {name = "PrepareProbe", typing = Excu {handler = Just "prepareProbe"}, input = "Root", demands = [Demand {access = RequestAccess, contract = "FilePaths"}]}
  , EffectSpec {name = "FileResource", typing = Context {request = Just (Requester {handler = "openedFile", representation = TypeRef "SharedFile"})}, input = "Root", demands = [Demand {access = RequireAccess, contract = "FilePaths"}]}
  , EffectSpec {name = "SharedFileScope", typing = Scoped {open = Just "openSharedFile", close = Just "closeSharedFile"}, input = "Root", demands = [Demand {access = RequestAccess, contract = "OpenedFile"},Demand {access = RequireAccess, contract = "OpenedFile"}]}
  , EffectSpec {name = "WriteFirst", typing = Excu {handler = Just "writeFirst"}, input = "SharedFileScope", demands = [Demand {access = RequestAccess, contract = "FilePaths"},Demand {access = RequireAccess, contract = "OpenedFile"}]}
  , EffectSpec {name = "WriteSecond", typing = Excu {handler = Just "writeSecond"}, input = "SharedFileScope", demands = [Demand {access = RequestAccess, contract = "FilePaths"},Demand {access = RequireAccess, contract = "OpenedFile"}]}
  , EffectSpec {name = "WriteThird", typing = Excu {handler = Just "writeThird"}, input = "SharedFileScope", demands = [Demand {access = RequestAccess, contract = "FilePaths"},Demand {access = RequireAccess, contract = "OpenedFile"}]}
  , EffectSpec {name = "VerifyReuse", typing = Excu {handler = Just "verifyReuse"}, input = "Root", demands = [Demand {access = RequestAccess, contract = "FilePaths"}]}
  ]

-- 生成身份连接到已有运行 scope 名；依赖只保存在下方显式 ScopeTree 中。
scopeNames :: [(MethodGen, String)]
scopeNames = [(OpenSharedFileGen, "SharedFileScope")]

-- 只校验生成常量；当前 workflow 在执行装配的一次 fold 中检查入口。
programStructure :: Either (SDK.StructureError MethodGen) (SDK.ProgramStructure MethodGen)
programStructure = SDK.initializeGeneratedStructure
  [("PrepareProbe", PrepareProbeGen), ("WriteFirst", WriteFirstGen), ("WriteSecond", WriteSecondGen), ("WriteThird", WriteThirdGen), ("VerifyReuse", VerifyReuseGen)]
  scopeNames generatedEffectGraph generatedScopeTree


-- 仅汇总所选末端的成功产物，不保存共享绑定或增加完成包装。
data Results = PrepareProbeResult (Produce PrepareProbe) | WriteFirstResult (Produce WriteFirst) | WriteSecondResult (Produce WriteSecond) | WriteThirdResult (Produce WriteThird) | VerifyReuseResult (Produce VerifyReuse)
  deriving Show

-- 末端共享生成的 scope 句柄；只创建空状态，Node algebra 才 lower，业务调用仍在 instance 内。
compiledEntries :: IO [SDK.Target IO ContextValues Errors Results]
compiledEntries = do
  scopes <- Handlers.newScopeHandlers
  pure
    [ SDK.targetApp "PrepareProbe" emptyContexts scopes (FrameworkRoot.withErrorHandlers Handlers.errorHandlers (FrameworkRoot.withAnchoredContexts Handlers.contextInjections (SDK.withScopeCleanups Handlers.scopeCleanups (PrepareProbeResult <$> (() <$ prepareProbe)))))
    , SDK.targetApp "WriteFirst" emptyContexts scopes (FrameworkRoot.withErrorHandlers Handlers.errorHandlers (FrameworkRoot.withAnchoredContexts Handlers.contextInjections (SDK.withScopeCleanups Handlers.scopeCleanups (WriteFirstResult <$> (() <$ writeFirst)))))
    , SDK.targetApp "WriteSecond" emptyContexts scopes (FrameworkRoot.withErrorHandlers Handlers.errorHandlers (FrameworkRoot.withAnchoredContexts Handlers.contextInjections (SDK.withScopeCleanups Handlers.scopeCleanups (WriteSecondResult <$> (() <$ writeSecond)))))
    , SDK.targetApp "WriteThird" emptyContexts scopes (FrameworkRoot.withErrorHandlers Handlers.errorHandlers (FrameworkRoot.withAnchoredContexts Handlers.contextInjections (SDK.withScopeCleanups Handlers.scopeCleanups (WriteThirdResult <$> (() <$ writeThird)))))
    , SDK.targetApp "VerifyReuse" emptyContexts scopes (FrameworkRoot.withErrorHandlers Handlers.errorHandlers (FrameworkRoot.withAnchoredContexts Handlers.contextInjections (SDK.withScopeCleanups Handlers.scopeCleanups (VerifyReuseResult <$> (() <$ verifyReuse)))))
    ]

-- SDK 装配入口，不需要用户提供节点执行器或重复选择 handler。
interpreter :: SDK.AST -> [EffectSpec] -> IO ()
interpreter = SDK.interpreter "ScopeReuseDemo" registeredEffects Handlers.handlerSourceFingerprint programStructure compiledEntries
-- 生成时已完成方法展开与路径分析；运行时只读取显式 ADT 值。
generatedEffectGraph :: SDK.EffectGraph MethodGen
generatedEffectGraph = SDK.EffectGraph
  { SDK.graphMethods =
      [ SDK.MethodDefinition PrepareProbeGen PrepareProbeGen SDK.HandlerMethod (SDK.Call FilePathsGen)
      , SDK.MethodDefinition FilePathsGen FilePathsGen SDK.ContextRequest (SDK.Empty)
      , SDK.MethodDefinition WriteFirstGen WriteFirstGen SDK.HandlerMethod (SDK.Sequence [SDK.Call FilePathsGen, SDK.Call OpenSharedFileGen, SDK.Call ReadOpenedFileGen])
      , SDK.MethodDefinition OpenSharedFileGen OpenSharedFileGen SDK.ScopeOpen (SDK.Call OpenedFileGen)
      , SDK.MethodDefinition OpenedFileGen OpenedFileGen SDK.ContextRequest (SDK.Call ReadFilePathsGen)
      , SDK.MethodDefinition ReadFilePathsGen FilePathsGen SDK.ContextRequire (SDK.Choice [SDK.Empty, SDK.Call FilePathsGen])
      , SDK.MethodDefinition ReadOpenedFileGen OpenedFileGen SDK.ContextRequire (SDK.Empty)
      , SDK.MethodDefinition WriteSecondGen WriteSecondGen SDK.HandlerMethod (SDK.Sequence [SDK.Call FilePathsGen, SDK.Call OpenSharedFileGen, SDK.Call ReadOpenedFileGen])
      , SDK.MethodDefinition WriteThirdGen WriteThirdGen SDK.HandlerMethod (SDK.Sequence [SDK.Call FilePathsGen, SDK.Call OpenSharedFileGen, SDK.Call ReadOpenedFileGen])
      , SDK.MethodDefinition VerifyReuseGen VerifyReuseGen SDK.HandlerMethod (SDK.Call FilePathsGen)
      ]
  , SDK.graphRoots = [PrepareProbeGen, WriteFirstGen, WriteSecondGen, WriteThirdGen, VerifyReuseGen]
  , SDK.graphReferences = [(PrepareProbeGen, FilePathsGen), (WriteFirstGen, FilePathsGen), (WriteFirstGen, OpenSharedFileGen), (WriteFirstGen, ReadOpenedFileGen), (OpenSharedFileGen, OpenedFileGen), (OpenedFileGen, ReadFilePathsGen), (ReadFilePathsGen, FilePathsGen), (WriteSecondGen, FilePathsGen), (WriteSecondGen, OpenSharedFileGen), (WriteSecondGen, ReadOpenedFileGen), (WriteThirdGen, FilePathsGen), (WriteThirdGen, OpenSharedFileGen), (WriteThirdGen, ReadOpenedFileGen), (VerifyReuseGen, FilePathsGen)]
  , SDK.graphScopes = [OpenSharedFileGen]
  , SDK.graphScopePaths = [[], [OpenSharedFileGen]]
  , SDK.graphRootPaths =
      [ (PrepareProbeGen, [[]])
      , (WriteFirstGen, [[OpenSharedFileGen]])
      , (WriteSecondGen, [[OpenSharedFileGen]])
      , (WriteThirdGen, [[OpenSharedFileGen]])
      , (VerifyReuseGen, [[]])
      ]
  , SDK.graphScopeOrder = []
  }

-- 唯一的 ScopeTree：共同前序与注册前提已合并、检查环并约简。
generatedScopeTree :: SDK.ScopeTree MethodGen
generatedScopeTree = SDK.ScopeTree
  { SDK.scopeRoots = [OpenSharedFileGen]
  , SDK.scopeNodes =
      [ SDK.ScopeNode { SDK.scopeIdentity = OpenSharedFileGen, SDK.scopeParents = [], SDK.scopeChildren = [] }
      ]
  , SDK.scopeLayers = [[OpenSharedFileGen]]
  , SDK.scopePaths = [[], [OpenSharedFileGen]]
  , SDK.scopeCandidates = []
  , SDK.scopeOpposed = []
  , SDK.scopeUndetermined = []
  }
