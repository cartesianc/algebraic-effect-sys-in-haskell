{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE TypeFamilies #-}

-- 自动生成；只登记末端句柄，Node algebra 才 lower，业务组合仍在 handler 内。
module RequestBenchmark.Generated.Program where

import Framework.SDK (Effect(..), EffectSpec(..), EffectTyping(..), Requester(..), Handles(..), Demand(..), Access(..), TypeRef(..), Output)
import qualified Framework.SDK as SDK
import qualified Framework.Effect.Contract as FrameworkRoot
import RequestBenchmark.Generated.Effects hiding (request, require)
import qualified RequestBenchmark.Generated.Handlers as Handlers
import RequestBenchmark.Types

-- 编译时注册快照；运行前核对声明，改变连接后须重新生成。
registeredEffects :: [EffectSpec]
registeredEffects =
  [ EffectSpec {name = "DemoContext", typing = Context {request = Just (Requester {handler = "demoInputs", representation = TypeRef "InputSettings"}), require = Just "readDemoInputs"}, input = "Root", demands = []}
  , EffectSpec {name = "MakeNumber", typing = Context {request = Just (Requester {handler = "numberValue", representation = TypeRef "Int"}), require = Just "readNumberValue"}, input = "Root", demands = [Demand {access = RequestAccess, contract = "DemoInputs"}]}
  , EffectSpec {name = "AddOne", typing = Context {request = Just (Requester {handler = "addedValue", representation = TypeRef "Int"}), require = Just "readAddedValue"}, input = "Root", demands = [Demand {access = RequestAccess, contract = "NumberValue"}]}
  , EffectSpec {name = "RenderNumber", typing = Context {request = Just (Requester {handler = "renderedValue", representation = TypeRef "[Char]"}), require = Just "readRenderedValue"}, input = "Root", demands = [Demand {access = RequestAccess, contract = "AddedValue"},Demand {access = RequireAccess, contract = "DemoInputs"}]}
  ]

-- 生成身份连接到已有运行 scope 名；依赖只保存在下方显式 ScopeTree 中。
scopeNames :: [(MethodGen, String)]
scopeNames = []

-- 只校验生成常量；当前 workflow 在执行装配的一次 fold 中检查入口。
programStructure :: Either (SDK.StructureError MethodGen) (SDK.ProgramStructure MethodGen)
programStructure = SDK.initializeGeneratedStructure
  [("RenderNumber", RenderedValueGen)]
  scopeNames generatedEffectGraph generatedScopeTree

-- 纯计算样例也只登记末端句柄，不在外部组合上游。
compiledTarget :: SDK.Target SDK.Identity ContextValues Errors (Produce RenderNumber)
compiledTarget = SDK.targetPure "RenderNumber" emptyContexts
  (FrameworkRoot.withErrorHandlers Handlers.errorHandlers renderedValue)

benchmark :: Output Errors (Produce RenderNumber)
benchmark = SDK.bootPure compiledTarget

registeredTarget :: String
registeredTarget = "RenderNumber"

-- 生成入口由 SDK 提供；业务无需另写 Codegen 模块。
runDemo :: Show value => [EffectSpec] -> String -> value -> IO ()
runDemo = SDK.runDemo "RequestBenchmark" registeredEffects registeredTarget Handlers.handlerSourceFingerprint
-- 生成时已完成方法展开与路径分析；运行时只读取显式 ADT 值。
generatedEffectGraph :: SDK.EffectGraph MethodGen
generatedEffectGraph = SDK.EffectGraph
  { SDK.graphMethods =
      [ SDK.MethodDefinition RenderedValueGen RenderedValueGen SDK.ContextRequest (SDK.Sequence [SDK.Call AddedValueGen, SDK.Call ReadDemoInputsGen])
      , SDK.MethodDefinition AddedValueGen AddedValueGen SDK.ContextRequest (SDK.Call NumberValueGen)
      , SDK.MethodDefinition NumberValueGen NumberValueGen SDK.ContextRequest (SDK.Call DemoInputsGen)
      , SDK.MethodDefinition DemoInputsGen DemoInputsGen SDK.ContextRequest (SDK.Empty)
      , SDK.MethodDefinition ReadDemoInputsGen DemoInputsGen SDK.ContextRequire (SDK.Empty)
      ]
  , SDK.graphRoots = [RenderedValueGen]
  , SDK.graphReferences = [(RenderedValueGen, AddedValueGen), (RenderedValueGen, ReadDemoInputsGen), (AddedValueGen, NumberValueGen), (NumberValueGen, DemoInputsGen)]
  , SDK.graphScopes = []
  , SDK.graphScopePaths = [[]]
  , SDK.graphRootPaths =
      [ (RenderedValueGen, [[]])
      ]
  , SDK.graphScopeOrder = []
  }

-- 唯一的 ScopeTree：共同前序与注册前提已合并、检查环并约简。
generatedScopeTree :: SDK.ScopeTree MethodGen
generatedScopeTree = SDK.ScopeTree
  { SDK.scopeRoots = []
  , SDK.scopeNodes =
      []
  , SDK.scopeLayers = []
  , SDK.scopePaths = [[]]
  , SDK.scopeCandidates = []
  , SDK.scopeOpposed = []
  , SDK.scopeUndetermined = []
  }
