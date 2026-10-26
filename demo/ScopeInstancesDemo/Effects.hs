{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE TypeApplications #-}

module ScopeInstancesDemo.Effects (effects) where

import Framework.SDK
  (EffectSpec(..), EffectTyping(..), Producer(..), ContextInput(..), ValueSource(..), typeRef)
import ScopeInstancesDemo.Types

-- 注册形状没有变化；路径来源是 Context，scope 没有 key 或产值字段。
effects :: [EffectSpec]
effects =
  [ EffectSpec
      { name = "PrepareFiles"
      , typing = Excu { handler = Just "prepareFiles" }
      , input = "Root"
      , context = Nothing
      }
  , EffectSpec
      { name = "FileLocation"
      , typing = Context
          { request = Just Producer { handler = "getFileName", produces = typeRef @FileName }
          , require = Just "readFileName"
          }
      , input = "Root"
      , context = Nothing
      }
  , EffectSpec
      { name = "FileResource"
      , typing = Context
          { request = Just Producer { handler = "acquireFile", produces = typeRef @OpenedFile }
          , require = Just "readOpenedFile"
          }
      , input = "Root"
      , context = Just ContextInput
          { request = Nothing, require = Just (From "FileLocation" (typeRef @FileName)) }
      }
  , EffectSpec
      { name = "FileSession"
      , typing = Scoped { open = Just "openFileSession", close = Just "closeFileSession" }
      , input = "Root"
      , context = Just ContextInput
          { request = Just (From "FileResource" (typeRef @OpenedFile))
          , require = Just (From "FileResource" (typeRef @OpenedFile))
          }
      }
  , EffectSpec
      { name = "CheckIndependent"
      , typing = Excu { handler = Just "checkIndependent" }
      , input = "FileSession"
      , context = Just ContextInput
          { request = Just (From "FileLocation" (typeRef @FileName))
          , require = Just (From "FileResource" (typeRef @OpenedFile)) }
      }
  , EffectSpec
      { name = "CheckReopen"
      , typing = Excu { handler = Just "checkReopen" }
      , input = "FileSession"
      , context = Just ContextInput
          { request = Just (From "FileLocation" (typeRef @FileName))
          , require = Just (From "FileResource" (typeRef @OpenedFile)) }
      }
  ]
