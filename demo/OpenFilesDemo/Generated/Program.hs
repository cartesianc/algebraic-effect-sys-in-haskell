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
  , EffectSpec {name = "FileResources", typing = Context {request = Just (Producer {handler = "acquireFiles", produces = TypeRef "OpenedFiles"}), require = Just "readOpenedFiles"}, input = "Root", context = Just (ContextInput {request = Just (From "FileLocations" (TypeRef "FileNames")), require = Nothing})}
  , EffectSpec {name = "FileSession", typing = Scoped {open = Just "openFiles", close = Just "closeFiles"}, input = "Root", context = Just (ContextInput {request = Just (From "FileResources" (TypeRef "OpenedFiles")), require = Just (From "FileResources" (TypeRef "OpenedFiles"))})}
  , EffectSpec {name = "HoldFiles", typing = Excu {handler = Just "holdFiles"}, input = "FileSession", context = Nothing}
  , EffectSpec {name = "InspectFiles", typing = Excu {handler = Just "inspectFiles"}, input = "HoldFiles", context = Just (ContextInput {request = Nothing, require = Just (From "FileResources" (TypeRef "OpenedFiles"))})}
  , EffectSpec {name = "FinishInspection", typing = Excu {handler = Just "finishInspection"}, input = "InspectFiles", context = Just (ContextInput {request = Nothing, require = Just (From "FileResources" (TypeRef "OpenedFiles"))})}
  ]


-- 仅汇总所选末端的成功产物，不保存共享绑定或增加完成包装。
data Results = HoldFilesResult (Produce HoldFiles) | InspectFilesResult (Produce InspectFiles) | FinishInspectionResult (Produce FinishInspection)
  deriving Show

-- 末端共享生成的 scope 句柄；只创建空状态，Node algebra 才 lower，业务调用仍在 instance 内。
compiledEntries :: IO [SDK.Target IO ContextValues Errors Results]
compiledEntries = do
  scopes <- Handlers.newScopeHandlers
  pure
    [ SDK.targetApp "HoldFiles" emptyContexts scopes (FrameworkRoot.withErrorHandlers Handlers.errorHandlers (HoldFilesResult <$> holdFiles))
    , SDK.targetApp "InspectFiles" emptyContexts scopes (FrameworkRoot.withErrorHandlers Handlers.errorHandlers (InspectFilesResult <$> inspectFiles))
    , SDK.targetApp "FinishInspection" emptyContexts scopes (FrameworkRoot.withErrorHandlers Handlers.errorHandlers (FinishInspectionResult <$> finishInspection))
    ]

-- SDK 装配入口，不需要用户提供节点执行器或重复选择 handler。
interpreter :: SDK.AST -> [EffectSpec] -> IO ()
interpreter = SDK.interpreter "OpenFilesDemo" registeredEffects Handlers.handlerSourceFingerprint compiledEntries
