{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE TypeApplications #-}

module ScopeReuseDemo.Effects (effects) where

import Framework.SDK (EffectSpec(..), EffectTyping(..), Producer(..), ContextInput(..), ValueSource(..), typeRef)
import ScopeReuseDemo.Types

-- Context 保存路径与活文件；Scoped 管理开启／关闭，日志记录实际开闭次数。
-- 三个 Excu 写入者是兄弟节点，input 均为同一个 SharedFileScope。
effects :: [EffectSpec]
effects =
  [ EffectSpec
      { name = "FileLocations"
      , typing = Context
          { request = Just Producer
              { handler = "getFilePaths", produces = typeRef @FilePaths }
          , require = Just "readFilePaths"
          }
      , input = "Root"
      , context = Nothing
      }
  , EffectSpec
      { name = "PrepareProbe"
      , typing = Excu { handler = Just "prepareProbe" }
      , input = "Root"
      , context = Just ContextInput
          { request = Just (From "FileLocations" (typeRef @FilePaths))
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
      , input = "Root"
      , context = Just ContextInput
          { request = Nothing
          , require = Just (From "FileLocations" (typeRef @FilePaths))
          }
      }
  , EffectSpec
      { name = "SharedFileScope"
      , typing = Scoped
          { open = Just "openSharedFile", close = Just "closeSharedFile" }
      , input = "Root"
      , context = Just ContextInput
          { request = Just (From "FileResource" (typeRef @OpenedFile))
          , require = Just (From "FileResource" (typeRef @OpenedFile))
          }
      }
  , EffectSpec
      { name = "WriteFirst"
      , typing = Excu { handler = Just "writeFirst" }
      , input = "SharedFileScope"
      , context = Just ContextInput
          { request = Just (From "FileLocations" (typeRef @FilePaths))
          , require = Just (From "FileResource" (typeRef @OpenedFile))
          }
      }
  , EffectSpec
      { name = "WriteSecond"
      , typing = Excu { handler = Just "writeSecond" }
      , input = "SharedFileScope"
      , context = Just ContextInput
          { request = Just (From "FileLocations" (typeRef @FilePaths))
          , require = Just (From "FileResource" (typeRef @OpenedFile))
          }
      }
  , EffectSpec
      { name = "WriteThird"
      , typing = Excu { handler = Just "writeThird" }
      , input = "SharedFileScope"
      , context = Just ContextInput
          { request = Just (From "FileLocations" (typeRef @FilePaths))
          , require = Just (From "FileResource" (typeRef @OpenedFile))
          }
      }
  , EffectSpec
      { name = "VerifyReuse"
      , typing = Excu { handler = Just "verifyReuse" }
      , input = "Root"
      , context = Just ContextInput
          { request = Just (From "FileLocations" (typeRef @FilePaths))
          , require = Nothing
          }
      }
  ]
