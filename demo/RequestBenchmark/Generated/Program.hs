{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE TypeFamilies #-}

-- 自动生成；只登记末端句柄，Node algebra 才 lower，业务组合仍在 handler 内。
module RequestBenchmark.Generated.Program where

import Framework.SDK (Effect(..), EffectSpec(..), EffectTyping(..), Producer(..), ContextInput(..), ValueSource(..), TypeRef(..), Output)
import qualified Framework.SDK as SDK
import qualified Framework.Effect.Contract as FrameworkRoot
import RequestBenchmark.Generated.Effects
import qualified RequestBenchmark.Generated.Handlers as Handlers
import RequestBenchmark.Types

-- 编译时注册快照；运行前核对声明，改变连接后须重新生成。
registeredEffects :: [EffectSpec]
registeredEffects =
  [ EffectSpec {name = "DemoContext", typing = Context {request = Just (Producer {handler = "loadDemoInputs", produces = TypeRef "DemoInputs"}), require = Just "readDemoInputs"}, input = "Root", context = Nothing}
  , EffectSpec {name = "MakeNumber", typing = Context {request = Just (Producer {handler = "makeNumber", produces = TypeRef "NumberValue"}), require = Just "readNumber"}, input = "Root", context = Just (ContextInput {request = Just (From "DemoContext" (TypeRef "DemoInputs")), require = Nothing})}
  , EffectSpec {name = "AddOne", typing = Context {request = Just (Producer {handler = "addOne", produces = TypeRef "AddedValue"}), require = Just "readAddedNumber"}, input = "Root", context = Just (ContextInput {request = Just (From "MakeNumber" (TypeRef "NumberValue")), require = Nothing})}
  , EffectSpec {name = "RenderNumber", typing = Context {request = Just (Producer {handler = "renderNumber", produces = TypeRef "RenderedValue"}), require = Just "readRenderedNumber"}, input = "Root", context = Just (ContextInput {request = Just (From "AddOne" (TypeRef "AddedValue")), require = Just (From "DemoContext" (TypeRef "DemoInputs"))})}
  ]

-- 生成身份连接到已有运行 scope 名；依赖只保存在下方显式 ScopeTree 中。
scopeNames :: [(MethodGen, String)]
scopeNames = []

-- 运行只 fold 当前 workflow，并校验入口集合及生成常量；不重新构图。
programStructure :: SDK.AST -> Either (SDK.StructureError MethodGen) (SDK.ProgramStructure MethodGen)
programStructure = SDK.initializeGeneratedStructure
  [("RenderNumber", RenderNumberGen)]
  scopeNames generatedEffectGraph generatedScopeTree

-- 纯计算样例也只登记末端句柄，不在外部组合上游。
compiledTarget :: SDK.Target SDK.Identity ContextValues Errors (Produce RenderNumber)
compiledTarget = SDK.targetPure "RenderNumber" emptyContexts
  (FrameworkRoot.withErrorHandlers Handlers.errorHandlers renderNumber)

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
      [ SDK.MethodDefinition RenderNumberGen RenderNumberGen SDK.ContextRequest (SDK.Sequence [SDK.Call AddOneGen, SDK.Call LoadDemoInputsGen])
      , SDK.MethodDefinition AddOneGen AddOneGen SDK.ContextRequest (SDK.Call MakeNumberGen)
      , SDK.MethodDefinition MakeNumberGen MakeNumberGen SDK.ContextRequest (SDK.Call LoadDemoInputsGen)
      , SDK.MethodDefinition LoadDemoInputsGen LoadDemoInputsGen SDK.ContextRequest (SDK.Empty)
      , SDK.MethodDefinition ReadDemoInputsGen LoadDemoInputsGen SDK.ContextRequire (SDK.Empty)
      ]
  , SDK.graphRoots = [RenderNumberGen]
  , SDK.graphReferences = [(RenderNumberGen, AddOneGen), (RenderNumberGen, ReadDemoInputsGen), (AddOneGen, MakeNumberGen), (MakeNumberGen, LoadDemoInputsGen)]
  , SDK.graphScopes = []
  , SDK.graphScopePaths = [[]]
  , SDK.graphRootPaths =
      [ (RenderNumberGen, [[]])
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
