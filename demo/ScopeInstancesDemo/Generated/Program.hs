{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE TypeFamilies #-}

-- 自动生成；只登记末端句柄，Node algebra 才 lower，业务组合仍在 handler 内。
module ScopeInstancesDemo.Generated.Program where

import Framework.SDK (Effect(..), EffectSpec(..), EffectTyping(..), Producer(..), ContextInput(..), ValueSource(..), TypeRef(..), Output)
import qualified Framework.SDK as SDK
import ScopeInstancesDemo.Generated.Effects
import qualified ScopeInstancesDemo.Generated.Handlers as Handlers
import ScopeInstancesDemo.Types


-- 仅汇总所选末端的成功产物，不保存共享绑定或增加完成包装。
data Results = PrepareFilesResult (Produce PrepareFiles) | CheckIndependentResult (Produce CheckIndependent) | CheckReopenResult (Produce CheckReopen)
  deriving Show

-- 末端共享生成的 scope 句柄；只创建空状态，Node algebra 才 lower，业务调用仍在 instance 内。
compiledEntries :: IO [SDK.Target IO ContextValues Errors Results]
compiledEntries = do
  scopes <- Handlers.newScopeHandlers
  pure
    [ SDK.targetApp "PrepareFiles" emptyContexts scopes (PrepareFilesResult <$> prepareFiles)
    , SDK.targetApp "CheckIndependent" emptyContexts scopes (CheckIndependentResult <$> checkIndependent)
    , SDK.targetApp "CheckReopen" emptyContexts scopes (CheckReopenResult <$> checkReopen)
    ]

-- 编译时注册快照；运行前核对声明，改变连接后须重新生成。
registeredEffects :: [EffectSpec]
registeredEffects =
  [ EffectSpec {name = "PrepareFiles", typing = Excu {handler = Just "prepareFiles"}, input = "Root", context = Nothing}
  , EffectSpec {name = "FileLocation", typing = Context {request = Just (Producer {handler = "getFileName", produces = TypeRef "FileName"}), require = Just "readFileName"}, input = "Root", context = Nothing}
  , EffectSpec {name = "FileResource", typing = Context {request = Just (Producer {handler = "acquireFile", produces = TypeRef "OpenedFile"}), require = Just "readOpenedFile"}, input = "Root", context = Just (ContextInput {request = Just (From "FileLocation" (TypeRef "FileName")), require = Nothing})}
  , EffectSpec {name = "FileSession", typing = Scoped {open = Just "openFileSession", close = Just "closeFileSession"}, input = "Root", context = Just (ContextInput {request = Just (From "FileResource" (TypeRef "OpenedFile")), require = Just (From "FileResource" (TypeRef "OpenedFile"))})}
  , EffectSpec {name = "CheckIndependent", typing = Excu {handler = Just "checkIndependent"}, input = "FileSession", context = Just (ContextInput {request = Nothing, require = Just (From "FileResource" (TypeRef "OpenedFile"))})}
  , EffectSpec {name = "CheckReopen", typing = Excu {handler = Just "checkReopen"}, input = "FileSession", context = Just (ContextInput {request = Nothing, require = Just (From "FileResource" (TypeRef "OpenedFile"))})}
  ]

-- SDK 装配入口，不需要用户提供节点执行器或重复选择 handler。
interpreter :: SDK.AST -> [EffectSpec] -> IO ()
interpreter = SDK.interpreter "ScopeInstancesDemo" registeredEffects compiledEntries
