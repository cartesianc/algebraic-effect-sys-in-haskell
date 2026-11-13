{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE TypeApplications #-}

module ScopeReuseDemo.Effects (effects) where

import Framework.SDK (EffectSpec(..), EffectTyping(..), Asset(..), requests, requires)
import ScopeReuseDemo.Types

-- Context 保存路径与活文件；Scoped 管理开启／关闭，日志记录实际开闭次数。
-- 三个 Excu 写入者读取 PrepareProbe 的同一次路径生产，按生产身份共享 SharedFileScope。
effects :: [EffectSpec]
effects =
  [ EffectSpec
      { name = "FileLocations"
      , typing = Context { asset = Asset @SharedPaths "FilePaths", parser = Just "sharedPaths", require = True, stream = False }
      , input = "Root"
      , demands = []
      }
  , EffectSpec
      { name = "PrepareProbe"
      , typing = Excu { handler = Just "prepareProbe" }
      , input = "Root"
      , demands = [requests "FilePaths", requires "FilePaths"]
      }
  , EffectSpec
      { name = "FileResource"
      , typing = Context { asset = Asset @SharedFile "OpenedFile", parser = Just "acquireFile", require = True, stream = False }
      , input = "Root"
      , demands = [requires "FilePaths"]
      }
  , EffectSpec
      { name = "SharedFileScope"
      , typing = Scoped { open = Just "openSharedFile", close = Just "closeSharedFile" }
      , input = "Root"
      , demands = [requests "OpenedFile", requires "OpenedFile"]
      }
  , EffectSpec
      { name = "WriteFirst"
      , typing = Excu { handler = Just "writeFirst" }
      , input = "SharedFileScope"
      , demands = [requires "OpenedFile"]
      }
  , EffectSpec
      { name = "WriteSecond"
      , typing = Excu { handler = Just "writeSecond" }
      , input = "SharedFileScope"
      , demands = [requires "OpenedFile"]
      }
  , EffectSpec
      { name = "WriteThird"
      , typing = Excu { handler = Just "writeThird" }
      , input = "SharedFileScope"
      , demands = [requires "OpenedFile"]
      }
  , EffectSpec
      { name = "VerifyReuse"
      , typing = Excu { handler = Just "verifyReuse" }
      , input = "Root"
      , demands = [requests "FilePaths", requires "FilePaths"]
      }
  ]
