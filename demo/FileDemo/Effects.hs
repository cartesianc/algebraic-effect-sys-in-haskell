{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE TypeApplications #-}

module FileDemo.Effects (effects) where

import Framework.SDK (EffectSpec(..), EffectTyping(..), Handles(..), requester, requests, requires)
import FileDemo.Types

-- 注册只描述分类、方法和依赖；文件 IO 与上游方法引用在 Handlers.hs。
-- Context：生产／读取业务值。Pure：无产值的纯检查。
-- Excu 与 Scoped 的 open／close 是原子句柄，可交出可选信息；SDK 保存 scope 生命周期状态。
-- input 指向原子句柄的 Context 挂在该句柄下，解析它交出的信息（ExtractFileText 挂在 ReadFile 下）。
-- requester "handler名" @表示类型：handler 名首字母大写即契约名；demands 以契约名引用。
-- Error：handles 声明处理的故障类型；作用的 scope 由 Input 链上最近的 Scoped 推导。
effects :: [EffectSpec]
effects =
  [ EffectSpec
      { name = "FileLocation"
      , typing = Context { request = requester "fileName" @FilePath }
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
      , typing = Context { request = requester "openedFile" @FileHandle }
      , input = "ValidateFileName"
      , demands = [requires "FileName"]
      }
  , EffectSpec
      { name = "FileSession"
      , typing = Scoped
          { open = Just "openFileSession", close = Just "closeFileSession" }
      , input = "ValidateFileName"
      , demands = [requests "OpenedFile", requires "OpenedFile"]
      }
  , EffectSpec
      { name = "FileRecovery"
      , typing = Error
          { detect = Just "detectFileSession", resolve = Just "resolveFileSession"
          , handles = [RaisedBy "ReadFile", RaisedBy "WriteFile"]
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
  , EffectSpec
      { name = "ExtractFileText"
      , typing = Context { request = requester "fileText" @String }
      , input = "ReadFile"
      , demands = []
      }
  , EffectSpec
      { name = "WriteFile"
      , typing = Excu { handler = Just "writeFileText" }
      , input = "ReadFile"
      , demands = [requires "FileText", requires "OpenedFile"]
      }
  , EffectSpec
      { name = "FileWorkflow"
      , typing = Excu { handler = Just "runFileWorkflow" }
      , input = "WriteFile"
      , demands = [requests "FileName"]
      }
  ]
