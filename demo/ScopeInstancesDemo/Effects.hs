{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE TypeApplications #-}

module ScopeInstancesDemo.Effects (effects) where

import Framework.SDK (EffectSpec(..), EffectTyping(..), Asset(..), requests, requires)
import ScopeInstancesDemo.Types

-- 开启参数来自 Context（FileName 细化 FilePath），scope 没有 key 或产值字段；实例按开启值选择。
-- 三个使用者共用 handler checkSelection：每条使用闭包先由 requests 刷新参数，再经 Input 开启 FileSession，
-- 闭包退出时 SDK 自动 close；选择文件由独立的 Excu 节点改写，不在 handler 中开启或关闭 scope。
effects :: [EffectSpec]
effects =
  [ EffectSpec
      { name = "PrepareFiles"
      , typing = Excu { handler = Just "prepareFiles" }
      , input = "Root"
      , demands = []
      }
  , EffectSpec
      { name = "FileLocation"
      , typing = Context { asset = Asset @FilePath "FileName", parser = Just "selectedFile", require = True, stream = False }
      , input = "Root"
      , demands = []
      }
  , EffectSpec
      { name = "FileResource"
      , typing = Context { asset = Asset @FileHandle "OpenedFile", parser = Just "acquireFile", require = True, stream = False }
      , input = "Root"
      , demands = [requires "FileName"]
      }
  , EffectSpec
      { name = "FileSession"
      , typing = Scoped { open = Just "openSelectedFile", close = Just "closeSelectedFile" }
      , input = "Root"
      , demands = [requests "OpenedFile", requires "OpenedFile"]
      }
  , EffectSpec
      { name = "UseFirst"
      , typing = Excu { handler = Just "checkSelection" }
      , input = "FileSession"
      , demands = [requests "FileName", requires "FileName", requires "OpenedFile"]
      }
  , EffectSpec
      { name = "SelectSecond"
      , typing = Excu { handler = Just "selectSecond" }
      , input = "Root"
      , demands = []
      }
  , EffectSpec
      { name = "UseSecond"
      , typing = Excu { handler = Just "checkSelection" }
      , input = "FileSession"
      , demands = [requests "FileName", requires "FileName", requires "OpenedFile"]
      }
  , EffectSpec
      { name = "SelectFirst"
      , typing = Excu { handler = Just "selectFirst" }
      , input = "Root"
      , demands = []
      }
  , EffectSpec
      { name = "ReopenFirst"
      , typing = Excu { handler = Just "checkSelection" }
      , input = "FileSession"
      , demands = [requests "FileName", requires "FileName", requires "OpenedFile"]
      }
  , EffectSpec
      { name = "CheckJournal"
      , typing = Excu { handler = Just "checkJournal" }
      , input = "Root"
      , demands = []
      }
  ]
