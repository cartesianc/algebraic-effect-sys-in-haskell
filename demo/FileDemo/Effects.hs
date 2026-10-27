{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE TypeApplications #-}

module FileDemo.Effects (effects) where

import Framework.SDK (EffectSpec(..), EffectTyping(..), Producer(..), Handles(..), requests, requires, typeRef)
import FileDemo.Types

-- 注册只描述分类、方法和依赖；文件 IO 与上游方法引用在 Handlers.hs。
-- Context：生产／读取业务值。Pure：无产值的纯检查。Excu：无产值的操作。
-- Scoped：同一个 class 的 open／close 都是 m ()，SDK 保存生命周期状态。
-- demands 只写需要的契约；每个契约只有一个生产方，来源由生成器唯一解析。
-- Error：handles 声明处理的故障类型；作用的 scope 由 Input 链上最近的 Scoped 推导。
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
      , demands = []
      }
  , EffectSpec
      { name = "ValidateFileName"
      , typing = Pure { handler = Just "validateFileName" }
      , input = "Root"
      , demands = [requires @FileName]
      }
  , EffectSpec
      { name = "FileResource"
      , typing = Context
          { request = Just Producer
              { handler = "acquireFile", produces = typeRef @OpenedFile }
          , require = Just "readOpenedFile"
          }
      , input = "ValidateFileName"
      , demands = [requires @FileName]
      }
  , EffectSpec
      { name = "FileSession"
      , typing = Scoped
          { open = Just "openFileSession", close = Just "closeFileSession" }
      , input = "ValidateFileName"
      , demands = [requests @OpenedFile, requires @OpenedFile]
      }
  , EffectSpec
      { name = "FileRecovery"
      , typing = Error
          { detect = Just "detectFileSession", resolve = Just "resolveFileSession"
          , handles = [RaisedBy "ReadFile", RaisedBy "WriteFile"]
          }
      , input = "FileSession"
      , demands = [requires @OpenedFile]
      }
  , EffectSpec
      { name = "ReadFile"
      , typing = Context
          { request = Just Producer
              { handler = "readFileText", produces = typeRef @FileText }
          , require = Just "readLastFileText"
          }
      , input = "FileSession"
      , demands = [requires @OpenedFile]
      }
  , EffectSpec
      { name = "WriteFile"
      , typing = Excu { handler = Just "writeFileText" }
      , input = "FileSession"
      , demands = [requests @FileText, requires @OpenedFile]
      }
  , EffectSpec
      { name = "FileWorkflow"
      , typing = Excu { handler = Just "runFileWorkflow" }
      , input = "WriteFile"
      , demands = [requests @FileName]
      }
  ]
