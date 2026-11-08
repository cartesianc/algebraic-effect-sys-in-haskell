{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE TypeApplications #-}

module OpenFilesDemo.Effects (effects) where

import Framework.SDK (EffectSpec(..), EffectTyping(..), Asset(..), requests, requires)
import OpenFilesDemo.Types

-- Context 传递路径与资源，Scoped 管理一组文件的存续，Excu 执行观察。
-- 关闭只在链退出时由 SDK 完成；关闭后的检查读取开启时记下的快照，由 AST 排在后面。
effects :: [EffectSpec]
effects =
  [ EffectSpec
      { name = "FileLocations"
      , typing = Context { asset = Asset @[FilePath] "FileNames", parser = Just "listFiles", require = True, stream = False }
      , input = "Root"
      , demands = []
      }
  , EffectSpec
      { name = "FileResources"
      , typing = Context { asset = Asset @[FileHandle] "OpenedFiles", parser = Just "acquireFiles", require = True, stream = False }
      , input = "Root"
      , demands = [requires "FileNames"]
      }
  , EffectSpec
      { name = "FileSession"
      , typing = Scoped { open = Just "openFiles", close = Just "closeFiles" }
      , input = "Root"
      , demands = [requests "OpenedFiles", requires "OpenedFiles"]
      }
  , EffectSpec
      { name = "HoldFiles"
      , typing = Excu { handler = Just "holdFiles" }
      , input = "FileSession"
      , demands = [requests "FileNames"]
      }
  , EffectSpec
      { name = "InspectFiles"
      , typing = Excu { handler = Just "inspectFiles" }
      , input = "HoldFiles"
      , demands = [requires "OpenedFiles"]
      }
  -- 与 HoldFiles 复用同一个 handler：持有文件，链退出时由 SDK 关闭。
  , EffectSpec
      { name = "ReleaseFiles"
      , typing = Excu { handler = Just "holdFiles" }
      , input = "HoldFiles"
      , demands = []
      }
  -- 挂在 ReleaseFiles 下：它成功后记下本链持有的文件，scope 关闭后仍可读取。
  , EffectSpec
      { name = "InspectionSnapshot"
      , typing = Context { asset = Asset @[FileHandle] "InspectedFiles", parser = Just "snapshotFiles", require = True, stream = False }
      , input = "ReleaseFiles"
      , demands = [requires "OpenedFiles"]
      }
  , EffectSpec
      { name = "FinishInspection"
      , typing = Excu { handler = Just "finishInspection" }
      , input = "Root"
      , demands = [requires "InspectedFiles"]
      }
  ]
