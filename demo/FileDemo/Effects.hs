{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE TypeApplications #-}

module FileDemo.Effects (effects) where

import Framework.SDK (EffectSpec(..), EffectTyping(..), Handles(..), Asset(..), requests, requires)
import FileDemo.Types

-- 注册是业务配置：每个字段写 handler 名，文件 IO 在 Handlers.hs 的 handler 中。
-- Context：parser 产出资产的表示类型；require = True 缓存最新值。Pure：无产值的纯检查。
-- Excu 与 Scoped 的 open／close 是原子句柄，可交出可选信息；SDK 保存 scope 生命周期状态。
-- input 是前驱：gen 在 handler 之前执行它。input 是原子句柄的 Context 挂在它下面，parser 用 raw 读取句柄的输出。
-- Asset @表示类型 "资产名" 把表示类型细化为以资产名命名的资产；handler 按表示类型 require，来源由 demands 决定。
-- requests 驱动资产的生产链，requires 只读取。Error：handles 写 handler 名，作用的 scope 由 Input 链推导。
effects :: [EffectSpec]
effects =
  [ EffectSpec
      { name = "FileLocation"
      , typing = Context { asset = Asset @FilePath "FileName", parser = Just "locateFile", require = True, stream = False }
      , input = "Root"
      , demands = []
      }
  , EffectSpec
      { name = "ValidateFileName"
      , typing = Pure { handler = Just "validateFileName" }
      , input = "Root"
      , demands = [requires "FileName"]
      }
  , EffectSpec
      { name = "FileResource"
      , typing = Context { asset = Asset @FileHandle "OpenedFile", parser = Just "acquireFile", require = True, stream = False }
      , input = "ValidateFileName"
      , demands = [requires "FileName"]
      }
  , EffectSpec
      { name = "FileSession"
      , typing = Scoped { open = Just "openSession", close = Just "closeSession" }
      , input = "ValidateFileName"
      , demands = [requests "OpenedFile", requires "OpenedFile"]
      }
  , EffectSpec
      { name = "FileRecovery"
      , typing = Error
          { detect = Just "detectFileSession", resolve = Just "resolveFileSession"
          , handles = [RaisedBy "readFileContent", RaisedBy "writeFirstLine", RaisedBy "appendLine"]
          }
      , input = "FileSession"
      , demands = [requires "OpenedFile"]
      }
  , EffectSpec
      { name = "ReadFile"
      , typing = Excu { handler = Just "readFileContent" }
      , input = "FileSession"
      , demands = [requires "OpenedFile"]
      }
  -- 文件状态是和类型资产：每个构造器另有分支契约 FileTextBlank、FileTextWritten。
  , EffectSpec
      { name = "ExtractFileText"
      , typing = Context { asset = Asset @TextState "FileText", parser = Just "parseFileText", require = True, stream = False }
      , input = "ReadFile"
      , demands = []
      }
  -- alternative 的两个候选：各自 requires 一个分支契约，由此对应文件状态的一个构造器。
  , EffectSpec
      { name = "WriteFirstLine"
      , typing = Excu { handler = Just "writeFirstLine" }
      , input = "FileSession"
      , demands = [requires "FileTextBlank", requires "OpenedFile"]
      }
  , EffectSpec
      { name = "AppendLine"
      , typing = Excu { handler = Just "appendLine" }
      , input = "FileSession"
      , demands = [requires "FileTextWritten", requires "OpenedFile"]
      }
  ]
