{-# LANGUAGE DuplicateRecordFields #-}

-- 自动生成；组合好的执行闭包，原型在 Generated/Prototype.hs，执行由 SDK 的 interpreter 完成。
module ScopeReuseDemo.Generated.Program (Results(..), compiledProgram, interpreter, generatedPrototype) where

import Framework.Generated (EffectSpec(..), EffectTyping(..), Asset(..), Handles(..), Demand(..), Access(..), TypeRef(..))
import qualified Framework.Generated as SDK
import ScopeReuseDemo.Generated.Effects
import ScopeReuseDemo.Generated.Prototype (generatedPrototype)
import qualified ScopeReuseDemo.Generated.Handlers as Handlers


-- 仅汇总所选末端的成功结果，不保存共享绑定或增加完成包装。
data Results = PrepareProbeResult () | WriteFirstResult () | WriteSecondResult () | WriteThirdResult () | VerifyReuseResult ()
  deriving Show

-- 末端共享生成的 scope 句柄；只创建空状态。
-- compiledWorkflow：AST 的执行闭包（Serial 顺序、Concurrent 并行、Choose 选择、Drive 是 lifelong 的位置）。
-- compiledReactions：资产每次发布后同步执行的回调（lifelong 的单元与派生步骤）；Nothing 作用范围是 event。
-- compiledStatic：lifelong 之外 requests 持续资产时，同步运行到结束的根来源。
compiledProgram :: IO (SDK.Compiled ContextValues Errors Results)
compiledProgram = do
  scopes <- Handlers.newScopeHandlers
  let target :: Show value => String -> App value -> SDK.Target ContextValues Errors value
      target label action = SDK.targetApp label emptyContexts scopes
        (SDK.withErrorHandlers Handlers.errorHandlers action)
  pure SDK.Compiled
    { SDK.compiledWorkflow =
        SDK.Serial [] 
          [ SDK.Step [0] (target "PrepareProbe" (PrepareProbeResult () <$ Handlers.runPrepareProbe))
          , SDK.Concurrent [1] 
          [ ([(SDK.Slot 2 "FileResource")], SDK.Step [1,0] (target "WriteFirst" (WriteFirstResult () <$ Handlers.runWriteFirst)))
          , ([(SDK.Slot 2 "FileResource")], SDK.Step [1,1] (target "WriteSecond" (WriteSecondResult () <$ Handlers.runWriteSecond)))
          , ([(SDK.Slot 2 "FileResource")], SDK.Step [1,2] (target "WriteThird" (WriteThirdResult () <$ Handlers.runWriteThird)))
          ]
          , SDK.Step [2] (target "VerifyReuse" (VerifyReuseResult () <$ Handlers.runVerifyReuse))
          ]
    , SDK.compiledReactions = []
    , SDK.compiledStatic = []
    }

-- SDK 装配入口，不需要用户提供节点执行器或重复选择 handler。
interpreter :: SDK.AST -> [EffectSpec] -> IO ()
interpreter = SDK.interpreter "ScopeReuseDemo" [("demo/ScopeReuseDemo/Handlers.hs", Handlers.handlerSourceFingerprint), ("demo/ScopeReuseDemo/Hanging.hs",Nothing)] generatedPrototype compiledProgram
