{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE TypeApplications #-}

module OpenFilesDemo.Effects (effects) where

import Framework.SDK (EffectSpec(..), EffectTyping(..), Producer(..), requests, requires, typeRef)
import OpenFilesDemo.Types

-- Context 传递路径与资源，Scoped 管理一组文件的存续，Excu 执行观察与收尾。
-- closeFiles 是 FileSession 的类方法；FinishInspection 在本链 open 后显式关闭并检查结果。
effects :: [EffectSpec]
effects =
  [ EffectSpec
      { name = "FileLocations"
      , typing = Context
          { request = Just Producer
              { handler = "getFileNames", produces = typeRef @FileNames }
          , require = Just "readFileNames"
          }
      , input = "Root"
      , demands = []
      }
  , EffectSpec
      { name = "FileResources"
      , typing = Context
          { request = Just Producer
              { handler = "acquireFiles", produces = typeRef @OpenedFiles }
          , require = Just "readOpenedFiles"
          }
      , input = "Root"
      , demands = [requires @FileNames]
      }
  , EffectSpec
      { name = "FileSession"
      , typing = Scoped
          { open = Just "openFiles", close = Just "closeFiles" }
      , input = "Root"
      , demands = [requests @OpenedFiles, requires @OpenedFiles]
      }
  , EffectSpec
      { name = "HoldFiles"
      , typing = Excu { handler = Just "holdFiles" }
      , input = "FileSession"
      , demands = [requests @FileNames]
      }
  , EffectSpec
      { name = "InspectFiles"
      , typing = Excu { handler = Just "inspectFiles" }
      , input = "HoldFiles"
      , demands = [requires @OpenedFiles]
      }
  , EffectSpec
      { name = "FinishInspection"
      , typing = Excu { handler = Just "finishInspection" }
      , input = "InspectFiles"
      , demands = [requires @OpenedFiles]
      }
  ]
