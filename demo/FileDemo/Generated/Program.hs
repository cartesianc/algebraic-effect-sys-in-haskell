{-# LANGUAGE DuplicateRecordFields #-}

-- 自动生成；只登记末端入口，原型在 Generated/Prototype.hs，执行由 SDK 的 interpreter 完成。
module FileDemo.Generated.Program where

import Framework.Generated (EffectSpec(..), EffectTyping(..), Asset(..), Handles(..), Demand(..), Access(..), TypeRef(..))
import qualified Framework.Generated as SDK
import FileDemo.Generated.Effects
import FileDemo.Generated.Prototype (generatedPrototype)
import qualified FileDemo.Generated.Handlers as Handlers
import FileDemo.Types


-- 仅汇总所选末端的成功结果，不保存共享绑定或增加完成包装。
data Results = WriteFirstLineResult () | AppendLineResult ()
  deriving Show

-- 末端共享生成的 scope 句柄；只创建空状态，Node algebra 才 lower。
-- 第二个列表是各转折契约的选择末端：驱动资产（持续资产领取本次交付），返回它当前的构造器名。
-- 第三个列表是各持续资产的生产步骤：会话按需启动，Receive 在每次 rawemit 时调用 parser，Derive 每领取一条上游交付调用一次。
compiledEntries :: IO ([SDK.Target ContextValues Errors Results], [SDK.Target ContextValues Errors String]
                     , [(String, SDK.SessionSteps ContextValues Errors)])
compiledEntries = do
  scopes <- Handlers.newScopeHandlers
  let target :: Show value => String -> App value -> SDK.Target ContextValues Errors value
      target label action = SDK.targetApp label emptyContexts scopes
        (SDK.withErrorHandlers Handlers.errorHandlers action)
  pure
    ( [ target "WriteFirstLine" (WriteFirstLineResult () <$ Handlers.runWriteFirstLine)
      , target "AppendLine" (AppendLineResult () <$ Handlers.runAppendLine)
      ]
    , [ target "FileText" (caseOfFileText <$> Handlers.getFileText)
      ]
    , []
    )

caseOfFileText :: FileText -> String
caseOfFileText (FileText value) = case value of
  Blank {} -> "Blank"
  Written {} -> "Written"

-- SDK 装配入口，不需要用户提供节点执行器或重复选择 handler。
interpreter :: SDK.AST -> [EffectSpec] -> IO ()
interpreter = SDK.interpreter "FileDemo" [("demo/FileDemo/Handlers.hs", Handlers.handlerSourceFingerprint), ("demo/FileDemo/Types.hs", Just "009315feb6ea88d9892bf958d9c746dc"), ("demo/FileDemo/Hanging.hs",Nothing)] generatedPrototype compiledEntries
