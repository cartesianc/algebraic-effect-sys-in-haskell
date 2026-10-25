{-# LANGUAGE DefaultSignatures #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE TypeSynonymInstances #-}
{-# LANGUAGE UndecidableInstances #-}

module MyFramework.Schema
  ( Codec (..)
  , HasSchema (..)
  , SchemaCatalog (..)
  , SchemaDescriptor (..)
  , SchemaDefinition (..)
  , SchemaOrigin (..)
  , ValueScalar (..)
  , ValueSchemaId (..)
  , ValueSchemaShape (..)
  , ValueSchemaVersion (..)
  , buildSchemaCatalog
  , canonicalSchemaDefinition
  , codecDefinition
  , descriptorFor
  , renderSchemaCatalog
  , renderSchemaDefinition
  , schemaCatalogDigest
  ) where

import Data.List
  ( intercalate
  , nub
  , sort
  , sortOn
  )
import Data.Kind
  ( Type
  )
import Data.Proxy
  ( Proxy (..)
  )
import Data.Typeable
  ( Typeable
  , typeRep
  )
import GHC.Generics
  ( C
  , D
  , Generic (..)
  , K1
  , M1
  , S
  , Selector
  , U1
  , (:*:)
  , Rep
  , selName
  )

import MyFramework.TrustBase.Digest
  ( sha256
  )

newtype ValueSchemaId = ValueSchemaId
  { valueSchemaIdText :: String
  }
  deriving (Eq, Ord, Read, Show)

newtype ValueSchemaVersion = ValueSchemaVersion
  { valueSchemaVersionMajor :: Int
  }
  deriving (Eq, Ord, Read, Show)

data ValueScalar
  = ValueBool
  | ValueInteger
  | ValueDecimal
  | ValueText
  | ValueNominalScalar String
  deriving (Eq, Ord, Read, Show)

data ValueSchemaShape
  = ValueUnitShape
  | ValueScalarShape ValueScalar
  | ValueRecordShape [(String, SchemaDefinition)]
  | ValueProductShape [SchemaDefinition]
  | ValueOpaqueShape String
  deriving (Eq, Ord, Read, Show)

data SchemaDefinition = SchemaDefinition
  { schemaDefinitionDisplayName :: Maybe String
  , schemaDefinitionVersion :: ValueSchemaVersion
  , schemaDefinitionShape :: ValueSchemaShape
  }
  deriving (Eq, Ord, Read, Show)

data SchemaOrigin
  = SchemaFromType String
  | SchemaFromGeneric String
  | SchemaFromLiteral String
  | SchemaFromRecord
  | SchemaFromR String
  | SchemaFromMap String
  | SchemaFromHandlerCodec String
  | SchemaFromImportedArtifact String
  | SchemaFromEffSysRef String
  | SchemaFromLegacyExplicit String
  | SchemaFromBoundaryCodec String
  deriving (Eq, Ord, Read, Show)

data SchemaDescriptor = SchemaDescriptor
  { schemaDescriptorId :: ValueSchemaId
  , schemaDescriptorDefinition :: SchemaDefinition
  , schemaDescriptorOrigins :: [SchemaOrigin]
  }
  deriving (Eq, Ord, Read, Show)

newtype SchemaCatalog = SchemaCatalog
  { schemaCatalogEntries :: [SchemaDescriptor]
  }
  deriving (Eq, Ord, Read, Show)

data Codec value = Codec
  { codecName :: String
  , codecVersion :: ValueSchemaVersion
  , codecSchema :: SchemaDefinition
  , codecEncode :: value -> Either String String
  , codecDecode :: String -> Either String value
  , codecEquivalent :: value -> value -> Bool
  , codecSerializable :: Bool
  }

codecDefinition :: Codec value -> SchemaDefinition
codecDefinition currentCodec =
  (codecSchema currentCodec)
    { schemaDefinitionVersion = codecVersion currentCodec
    }

class HasSchema value where
  valueSchemaDefinition :: proxy value -> SchemaDefinition
  default valueSchemaDefinition ::
    ( GenericRecordFields (Rep value)
    , Typeable value
    ) =>
    proxy value ->
    SchemaDefinition
  valueSchemaDefinition _ =
    SchemaDefinition
      { schemaDefinitionDisplayName =
          Just (show (typeRep (Proxy :: Proxy value)))
      , schemaDefinitionVersion = ValueSchemaVersion 1
      , schemaDefinitionShape =
          ValueRecordShape
            (genericRecordFields (Proxy :: Proxy (Rep value)))
      }

instance HasSchema () where
  valueSchemaDefinition _ =
    SchemaDefinition
      { schemaDefinitionDisplayName = Just "Unit"
      , schemaDefinitionVersion = ValueSchemaVersion 1
      , schemaDefinitionShape = ValueUnitShape
      }

instance HasSchema Bool where
  valueSchemaDefinition _ = scalarDefinition "Bool" ValueBool

instance HasSchema Integer where
  valueSchemaDefinition _ = scalarDefinition "Integer" ValueInteger

instance HasSchema Int where
  valueSchemaDefinition _ = scalarDefinition "Int" ValueInteger

instance HasSchema Double where
  valueSchemaDefinition _ = scalarDefinition "Double" ValueDecimal

instance HasSchema String where
  valueSchemaDefinition _ = scalarDefinition "Text" ValueText

class GenericRecordFields (representation :: Type -> Type) where
  genericRecordFields :: proxy representation -> [(String, SchemaDefinition)]

instance GenericRecordFields child => GenericRecordFields (M1 D metadata child) where
  genericRecordFields _ =
    genericRecordFields (Proxy :: Proxy child)

instance GenericRecordFields child => GenericRecordFields (M1 C metadata child) where
  genericRecordFields _ =
    genericRecordFields (Proxy :: Proxy child)

instance
  (Selector selector, HasSchema field) =>
  GenericRecordFields (M1 S selector (K1 source field)) where
  genericRecordFields _ =
    [ ( selName
          (undefined :: M1 S selector (K1 source field) ())
      , valueSchemaDefinition (Proxy :: Proxy field)
      )
    ]

instance
  (GenericRecordFields left, GenericRecordFields right) =>
  GenericRecordFields (left :*: right) where
  genericRecordFields _ =
    genericRecordFields (Proxy :: Proxy left)
      ++ genericRecordFields (Proxy :: Proxy right)

instance GenericRecordFields U1 where
  genericRecordFields _ = []

scalarDefinition :: String -> ValueScalar -> SchemaDefinition
scalarDefinition currentName currentScalar =
  SchemaDefinition
    { schemaDefinitionDisplayName = Just currentName
    , schemaDefinitionVersion = ValueSchemaVersion 1
    , schemaDefinitionShape = ValueScalarShape currentScalar
    }

canonicalSchemaDefinition :: SchemaDefinition -> SchemaDefinition
canonicalSchemaDefinition currentDefinition =
  currentDefinition
    { schemaDefinitionShape =
        canonicalShape (schemaDefinitionShape currentDefinition)
    }

canonicalShape :: ValueSchemaShape -> ValueSchemaShape
canonicalShape currentShape =
  case currentShape of
    ValueUnitShape -> ValueUnitShape
    ValueScalarShape currentScalar -> ValueScalarShape currentScalar
    ValueRecordShape currentFields ->
      ValueRecordShape
        ( sortOn fst
            [ (currentName, canonicalSchemaDefinition currentChild)
            | (currentName, currentChild) <- currentFields
            ]
        )
    ValueProductShape currentItems ->
      ValueProductShape (map canonicalSchemaDefinition currentItems)
    ValueOpaqueShape currentIdentity ->
      ValueOpaqueShape currentIdentity

descriptorFor :: SchemaOrigin -> SchemaDefinition -> SchemaDescriptor
descriptorFor currentOrigin currentDefinition =
  SchemaDescriptor
    { schemaDescriptorId =
        ValueSchemaId
          (sha256 (renderSchemaDefinition canonicalDefinition))
    , schemaDescriptorDefinition = canonicalDefinition
    , schemaDescriptorOrigins = [currentOrigin]
    }
  where
    canonicalDefinition =
      canonicalSchemaDefinition currentDefinition

buildSchemaCatalog :: [(SchemaOrigin, SchemaDefinition)] -> SchemaCatalog
buildSchemaCatalog currentDefinitions =
  SchemaCatalog
    { schemaCatalogEntries =
        map mergeGroup
          (groupDescriptors (sortOn schemaDescriptorId allDescriptors))
    }
  where
    rootDescriptors =
      [ descriptorFor currentOrigin currentDefinition
      | (currentOrigin, currentDefinition) <- currentDefinitions
      ]
    childDescriptors =
      concat
        [ nestedDescriptors currentOrigin currentDefinition
        | (currentOrigin, currentDefinition) <- currentDefinitions
        ]
    allDescriptors = rootDescriptors ++ childDescriptors

groupDescriptors :: [SchemaDescriptor] -> [[SchemaDescriptor]]
groupDescriptors [] = []
groupDescriptors (currentDescriptor : remaining) =
  same : groupDescriptors rest
  where
    currentId = schemaDescriptorId currentDescriptor
    same =
      currentDescriptor
        : takeWhile ((== currentId) . schemaDescriptorId) remaining
    rest =
      dropWhile ((== currentId) . schemaDescriptorId) remaining

mergeGroup :: [SchemaDescriptor] -> SchemaDescriptor
mergeGroup [] =
  error "schema descriptor group cannot be empty"
mergeGroup (currentDescriptor : remaining) =
  currentDescriptor
    { schemaDescriptorOrigins =
        sort
          ( nub
              ( concatMap
                  schemaDescriptorOrigins
                  (currentDescriptor : remaining)
              )
          )
    }

nestedDescriptors :: SchemaOrigin -> SchemaDefinition -> [SchemaDescriptor]
nestedDescriptors currentOrigin currentDefinition =
  case schemaDefinitionShape currentDefinition of
    ValueRecordShape currentFields ->
      concatMap
        (\(_, currentChild) ->
            descriptorFor currentOrigin currentChild
              : nestedDescriptors currentOrigin currentChild
        )
        currentFields
    ValueProductShape currentItems ->
      concatMap
        (\currentChild ->
            descriptorFor currentOrigin currentChild
              : nestedDescriptors currentOrigin currentChild
        )
        currentItems
    _ -> []

schemaCatalogDigest :: SchemaCatalog -> String
schemaCatalogDigest =
  sha256 . renderSchemaCatalog

renderSchemaCatalog :: SchemaCatalog -> String
renderSchemaCatalog currentCatalog =
  intercalate
    "|"
    [ encodeText (valueSchemaIdText (schemaDescriptorId currentDescriptor))
        ++ encodeText
          (renderSchemaDefinition (schemaDescriptorDefinition currentDescriptor))
        ++ encodeText (show (schemaDescriptorOrigins currentDescriptor))
    | currentDescriptor <-
        sortOn schemaDescriptorId (schemaCatalogEntries currentCatalog)
    ]

renderSchemaDefinition :: SchemaDefinition -> String
renderSchemaDefinition currentDefinition =
  "version="
    ++ show
      ( valueSchemaVersionMajor
          (schemaDefinitionVersion canonicalDefinition)
      )
    ++ ";shape="
    ++ renderShape (schemaDefinitionShape canonicalDefinition)
  where
    canonicalDefinition =
      canonicalSchemaDefinition currentDefinition

renderShape :: ValueSchemaShape -> String
renderShape currentShape =
  case currentShape of
    ValueUnitShape -> "unit"
    ValueScalarShape currentScalar ->
      "scalar:" ++ encodeText (renderScalar currentScalar)
    ValueRecordShape currentFields ->
      "record:"
        ++ intercalate
          ","
          [ encodeText currentName
              ++ encodeText (renderSchemaDefinition currentChild)
          | (currentName, currentChild) <- currentFields
          ]
    ValueProductShape currentItems ->
      "product:"
        ++ intercalate
          ","
          (map (encodeText . renderSchemaDefinition) currentItems)
    ValueOpaqueShape currentIdentity ->
      "opaque:" ++ encodeText currentIdentity

renderScalar :: ValueScalar -> String
renderScalar currentScalar =
  case currentScalar of
    ValueBool -> "bool"
    ValueInteger -> "integer"
    ValueDecimal -> "decimal"
    ValueText -> "text"
    ValueNominalScalar currentName -> "nominal:" ++ currentName

encodeText :: String -> String
encodeText currentText =
  show (length currentText) ++ ":" ++ currentText
