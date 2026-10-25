{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE UndecidableInstances #-}

module MyFramework.CURDE.Record
  ( RecordError (..)
  , RecordHandles (recordHandles)
  , effSysFromRecord
  , mergeEffSysDecls
  , sortRecordErrors
  ) where

import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import GHC.Generics
  ( C
  , D
  , Generic
  , K1 (..)
  , M1 (..)
  , Rep
  , S
  , Selector
  , U1 (..)
  , from
  , selName
  , (:*:) (..)
  , (:+:) (..)
  )

import MyFramework.CURDE.Types

-- | Stable errors produced while typed module records are merged into the one
-- unified serializable EffSys declaration.
data RecordError
  = RecordFieldSelectorMissing HandleId
  | RecordFieldNotHandle String
  | RecordSumTypeUnsupported
  | RecordDuplicateHandle HandleId
  deriving (Eq, Ord, Read, Show)

-- | A user record is authoring sugar only. Every field must be a typed Handle.
-- The record selector is a source-level module concern and does not have to be
-- identical to the Handle's globally qualified Symbol.
class RecordHandles record where
  recordHandles :: record -> Either [RecordError] [SomeHandleRef]

instance
  {-# OVERLAPPABLE #-}
  (Generic record, GRecordHandles (Rep record)) =>
  RecordHandles record where
  recordHandles =
    either
      (Left . sortRecordErrors)
      Right
      . gRecordHandles
      . from

class GRecordHandles representation where
  gRecordHandles ::
    representation parameter ->
    Either [RecordError] [SomeHandleRef]

instance
  GRecordHandles fields =>
  GRecordHandles (M1 D metadata fields) where
  gRecordHandles (M1 currentFields) =
    gRecordHandles currentFields

instance
  GRecordHandles fields =>
  GRecordHandles (M1 C metadata fields) where
  gRecordHandles (M1 currentFields) =
    gRecordHandles currentFields

instance
  (GRecordHandles left, GRecordHandles right) =>
  GRecordHandles (left :*: right) where
  gRecordHandles (left :*: right) =
    combineRecordResults
      (gRecordHandles left)
      (gRecordHandles right)

instance GRecordHandles U1 where
  gRecordHandles U1 =
    Right []

instance GRecordHandles (left :+: right) where
  gRecordHandles _ =
    Left [RecordSumTypeUnsupported]

instance
  {-# OVERLAPPING #-}
  Selector selector =>
  GRecordHandles
    (M1 S selector (K1 field (Handle name kind args result))) where
  gRecordHandles currentField@(M1 (K1 currentHandle))
    | null (selName currentField) =
        Left [RecordFieldSelectorMissing (handleId currentHandle)]
    | otherwise =
        Right [SomeHandleRef currentHandle]

instance
  {-# OVERLAPPABLE #-}
  Selector selector =>
  GRecordHandles (M1 S selector (K1 field value)) where
  gRecordHandles currentField =
    Left [RecordFieldNotHandle (selName currentField)]

-- | Erase one typed source-module record into a unified EffSys fragment.
-- Fragments are not separate EffSys registries; mergeEffSysDecls only concatenates
-- their Handle declarations and validates global identity uniqueness.
effSysFromRecord ::
  RecordHandles record =>
  record ->
  Either [RecordError] EffSysDecl
effSysFromRecord currentRecord = do
  currentHandles <- recordHandles currentRecord
  effSysDeclFromHandles currentHandles

mergeEffSysDecls :: [EffSysDecl] -> Either [RecordError] EffSysDecl
mergeEffSysDecls currentDecls =
  effSysDeclFromHandleDecls
    (concatMap effSysDeclHandles currentDecls)

effSysDeclFromHandles ::
  [SomeHandleRef] ->
  Either [RecordError] EffSysDecl
effSysDeclFromHandles currentHandles =
  effSysDeclFromHandleDecls (map eraseSomeHandle currentHandles)

effSysDeclFromHandleDecls ::
  [HandleDecl] ->
  Either [RecordError] EffSysDecl
effSysDeclFromHandleDecls currentHandles =
  case currentErrors of
    [] ->
      Right (EffSysDecl currentHandles)
    _ ->
      Left currentErrors
  where
    currentErrors =
      sortRecordErrors
        ( map
            RecordDuplicateHandle
            (duplicates (map handleDeclId currentHandles))
        )

sortRecordErrors :: [RecordError] -> [RecordError]
sortRecordErrors =
  Set.toAscList . Set.fromList

combineRecordResults ::
  Either [RecordError] [SomeHandleRef] ->
  Either [RecordError] [SomeHandleRef] ->
  Either [RecordError] [SomeHandleRef]
combineRecordResults leftResult rightResult =
  case (leftResult, rightResult) of
    (Right leftHandles, Right rightHandles) ->
      Right (leftHandles ++ rightHandles)
    (Left leftErrors, Left rightErrors) ->
      Left (leftErrors ++ rightErrors)
    (Left leftErrors, Right _) ->
      Left leftErrors
    (Right _, Left rightErrors) ->
      Left rightErrors

duplicates :: Ord value => [value] -> [value]
duplicates currentValues =
  Map.keys
    ( Map.filter
        (> (1 :: Int))
        (Map.fromListWith (+) [(currentValue, 1) | currentValue <- currentValues])
    )
