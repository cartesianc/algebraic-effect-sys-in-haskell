{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE TypeFamilies #-}

-- 自动生成；只登记末端句柄，Node algebra 才 lower，业务组合仍在 handler 内。
module ScopeReuseDemo.Generated.Program where

import Framework.SDK (Effect(..), EffectSpec(..), EffectTyping(..), Producer(..), ContextInput(..), ValueSource(..), TypeRef(..), Output)
import qualified Framework.SDK as SDK
import ScopeReuseDemo.Generated.Effects
import qualified ScopeReuseDemo.Generated.Handlers as Handlers
import ScopeReuseDemo.Types


-- 仅汇总所选末端的成功产物，不保存共享绑定或增加完成包装。
data Results = PrepareProbeResult (Produce PrepareProbe) | WriteFirstResult (Produce WriteFirst) | WriteSecondResult (Produce WriteSecond) | WriteThirdResult (Produce WriteThird) | VerifyReuseResult (Produce VerifyReuse)
  deriving Show

-- 末端共享生成的 scope 句柄；只创建空状态，Node algebra 才 lower，业务调用仍在 instance 内。
compiledEntries :: IO [SDK.Target IO ContextValues Errors Results]
compiledEntries = do
  scopes <- Handlers.newScopeHandlers
  pure
    [ SDK.targetApp "PrepareProbe" emptyContexts scopes (PrepareProbeResult <$> prepareProbe)
    , SDK.targetApp "WriteFirst" emptyContexts scopes (WriteFirstResult <$> writeFirst)
    , SDK.targetApp "WriteSecond" emptyContexts scopes (WriteSecondResult <$> writeSecond)
    , SDK.targetApp "WriteThird" emptyContexts scopes (WriteThirdResult <$> writeThird)
    , SDK.targetApp "VerifyReuse" emptyContexts scopes (VerifyReuseResult <$> verifyReuse)
    ]

-- 编译时注册快照；运行前核对声明，改变连接后须重新生成。
registeredEffects :: [EffectSpec]
registeredEffects =
  [ EffectSpec {name = "FileLocations", typing = Context {request = Just (Producer {handler = "getFilePaths", produces = TypeRef "FilePaths"}), require = Just "readFilePaths"}, input = "Root", context = Nothing}
  , EffectSpec {name = "PrepareProbe", typing = Excu {handler = Just "prepareProbe"}, input = "Root", context = Just (ContextInput {request = Just (From "FileLocations" (TypeRef "FilePaths")), require = Nothing})}
  , EffectSpec {name = "FileResource", typing = Context {request = Just (Producer {handler = "acquireFile", produces = TypeRef "OpenedFile"}), require = Just "readOpenedFile"}, input = "Root", context = Just (ContextInput {request = Just (From "FileLocations" (TypeRef "FilePaths")), require = Nothing})}
  , EffectSpec {name = "SharedFileScope", typing = Scoped {open = Just "openSharedFile", close = Just "closeSharedFile"}, input = "Root", context = Just (ContextInput {request = Just (From "FileResource" (TypeRef "OpenedFile")), require = Just (From "FileResource" (TypeRef "OpenedFile"))})}
  , EffectSpec {name = "WriteFirst", typing = Excu {handler = Just "writeFirst"}, input = "SharedFileScope", context = Just (ContextInput {request = Nothing, require = Just (From "FileResource" (TypeRef "OpenedFile"))})}
  , EffectSpec {name = "WriteSecond", typing = Excu {handler = Just "writeSecond"}, input = "SharedFileScope", context = Just (ContextInput {request = Nothing, require = Just (From "FileResource" (TypeRef "OpenedFile"))})}
  , EffectSpec {name = "WriteThird", typing = Excu {handler = Just "writeThird"}, input = "SharedFileScope", context = Just (ContextInput {request = Nothing, require = Just (From "FileResource" (TypeRef "OpenedFile"))})}
  , EffectSpec {name = "VerifyReuse", typing = Excu {handler = Just "verifyReuse"}, input = "SharedFileScope", context = Just (ContextInput {request = Nothing, require = Just (From "FileResource" (TypeRef "OpenedFile"))})}
  ]

-- SDK 装配入口，不需要用户提供节点执行器或重复选择 handler。
interpreter :: SDK.AST -> [EffectSpec] -> IO ()
interpreter = SDK.interpreter "ScopeReuseDemo" registeredEffects compiledEntries
