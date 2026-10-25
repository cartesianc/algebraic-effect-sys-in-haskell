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


-- 仅汇总所选末端的成功产物，不保存共享绑定或增加完成包装。
data Results = FileWorkflowResult (Produce FileWorkflow)
  deriving Show

-- 末端共享生成的 scope 句柄；只创建空状态，Node algebra 才 lower，业务调用仍在 instance 内。
compiledEntries :: IO [SDK.Target IO ContextValues Errors Results]
compiledEntries = do
  scopes <- Handlers.newScopeHandlers
  pure
    [ SDK.targetApp "FileWorkflow" emptyContexts scopes (FrameworkRoot.withErrorHandlers Handlers.errorHandlers (FileWorkflowResult <$> runFileWorkflow))
    ]

-- 编译时注册快照；运行前核对声明，改变连接后须重新生成。
registeredEffects :: [EffectSpec]
registeredEffects =
  [ EffectSpec {name = "FileLocation", typing = Context {request = Just (Producer {handler = "getFileName", produces = TypeRef "FileName"}), require = Just "readFileName"}, input = "Root", context = Nothing}
  , EffectSpec {name = "ValidateFileName", typing = Pure {handler = Just "validateFileName"}, input = "Root", context = Just (ContextInput {request = Just (From "FileLocation" (TypeRef "FileName")), require = Nothing})}
  , EffectSpec {name = "FileResource", typing = Context {request = Just (Producer {handler = "acquireFile", produces = TypeRef "OpenedFile"}), require = Just "readOpenedFile"}, input = "ValidateFileName", context = Just (ContextInput {request = Nothing, require = Just (From "FileLocation" (TypeRef "FileName"))})}
  , EffectSpec {name = "FileSession", typing = Scoped {open = Just "openFileSession", close = Just "closeFileSession"}, input = "ValidateFileName", context = Just (ContextInput {request = Just (From "FileResource" (TypeRef "OpenedFile")), require = Just (From "FileResource" (TypeRef "OpenedFile"))})}
  , EffectSpec {name = "FileRecovery", typing = Error {detect = Just "detectFileSession", resolve = Just "resolveFileSession"}, input = "FileSession", context = Just (ContextInput {request = Nothing, require = Just (From "FileResource" (TypeRef "OpenedFile"))})}
  , EffectSpec {name = "ReadFile", typing = Context {request = Just (Producer {handler = "readFileText", produces = TypeRef "FileText"}), require = Just "readLastFileText"}, input = "FileSession", context = Just (ContextInput {request = Nothing, require = Just (From "FileResource" (TypeRef "OpenedFile"))})}
  , EffectSpec {name = "WriteFile", typing = Excu {handler = Just "writeFileText"}, input = "FileSession", context = Just (ContextInput {request = Just (From "ReadFile" (TypeRef "FileText")), require = Just (From "FileResource" (TypeRef "OpenedFile"))})}
  , EffectSpec {name = "FileWorkflow", typing = Excu {handler = Just "runFileWorkflow"}, input = "WriteFile", context = Nothing}
  ]

-- SDK 装配入口，不需要用户提供节点执行器或重复选择 handler。
interpreter :: SDK.AST -> [EffectSpec] -> IO ()
interpreter = SDK.interpreter "FileDemo" registeredEffects compiledEntries
