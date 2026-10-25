{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE TypeApplications #-}

module FileDemo.Effects (effects) where

import Framework.SDK (EffectSpec(..), EffectTyping(..), Producer(..), ContextInput(..), ValueSource(..), typeRef)
import FileDemo.Types

-- 注册只描述分类、方法和依赖；文件 IO 与上游方法引用在 Handlers.hs。
-- Context：生产／读取业务值。Pure：无产值的纯检查。Excu：无产值的操作。
-- Scoped：同一个 class 的 open／close 都是 m ()，SDK 保存生命周期状态。
-- Error typing 的 detect／resolve 尚未实现；raise 是统一失败协议，不是 Error typing。
effects :: [EffectSpec]
effects =
  [ EffectSpec
      { name = "FileLocation"
      , typing = Context
          { request = Just Producer
              { handler = "getFileName", produces = typeRef @FileName }
          , require = Just "readFileName"
          }
      , input = "Root"
      , context = Nothing
      }
  , EffectSpec
      { name = "ValidateFileName"
      , typing = Pure { handler = Just "validateFileName" }
      , input = "Root"
      , context = Just ContextInput
          { request = Just (From "FileLocation" (typeRef @FileName))
          , require = Nothing
          }
      }
  , EffectSpec
      { name = "FileResource"
      , typing = Context
          { request = Just Producer
              { handler = "acquireFile", produces = typeRef @OpenedFile }
          , require = Just "readOpenedFile"
          }
      , input = "ValidateFileName"
      , context = Just ContextInput
          { request = Nothing
          , require = Just (From "FileLocation" (typeRef @FileName))
          }
      }
  , EffectSpec
      { name = "FileSession"
      , typing = Scoped
          { open = Just "openFileSession", close = Just "closeFileSession" }
      , input = "ValidateFileName"
      , context = Just ContextInput
          { request = Just (From "FileResource" (typeRef @OpenedFile))
          , require = Just (From "FileResource" (typeRef @OpenedFile))
          }
      }
  , EffectSpec
      { name = "ReadFile"
      , typing = Context
          { request = Just Producer
              { handler = "readFileText", produces = typeRef @FileText }
          , require = Just "readLastFileText"
          }
      , input = "FileSession"
      , context = Just ContextInput
          { request = Nothing
          , require = Just (From "FileResource" (typeRef @OpenedFile))
          }
      }
  , EffectSpec
      { name = "WriteFile"
      , typing = Excu { handler = Just "writeFileText" }
      , input = "FileSession"
      , context = Just ContextInput
          { request = Just (From "ReadFile" (typeRef @FileText))
          , require = Just (From "FileResource" (typeRef @OpenedFile))
          }
      }
  , EffectSpec
      { name = "FileWorkflow"
      , typing = Excu { handler = Just "runFileWorkflow" }
      , input = "WriteFile"
      , context = Nothing
      }
  ]
