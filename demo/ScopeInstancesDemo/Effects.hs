{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE TypeApplications #-}

module ScopeInstancesDemo.Effects (effects) where

import Framework.SDK (EffectSpec(..), EffectTyping(..), requester, requests, requires)
import ScopeInstancesDemo.Types

-- 路径来源是 Context，scope 没有 key 或产值字段；demands 只声明契约，来源唯一解析。
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
      , typing = Context { request = requester "fileName" @FilePath }
      , input = "Root"
      , demands = []
      }
  , EffectSpec
      { name = "FileResource"
      , typing = Context { request = requester "openedFile" @FileHandle }
      , input = "Root"
      , demands = [requires "FileName"]
      }
  , EffectSpec
      { name = "FileSession"
      , typing = Scoped { open = Just "openFileSession", close = Just "closeFileSession" }
      , input = "Root"
      , demands = [requests "OpenedFile", requires "OpenedFile"]
      }
  , EffectSpec
      { name = "CheckIndependent"
      , typing = Excu { handler = Just "checkIndependent" }
      , input = "FileSession"
      , demands = [requests "FileName", requires "OpenedFile"]
      }
  , EffectSpec
      { name = "CheckReopen"
      , typing = Excu { handler = Just "checkReopen" }
      , input = "FileSession"
      , demands = [requests "FileName", requires "OpenedFile"]
      }
  ]
