module MyFramework.EffSys.Types
  ( EffSysRef (..)
  , EffSysRegistryId (..)
  ) where

import MyFramework.Schema

newtype EffSysRegistryId = EffSysRegistryId
  { effSysRegistryIdText :: String
  }
  deriving (Eq, Ord, Read, Show)

-- | First-class, serializable capability value.  The AST root is resolved to
-- one stable AstPath during program validation.
data EffSysRef = EffSysRef
  { effSysRefAstRoot :: String
  , effSysRefRegistry :: EffSysRegistryId
  }
  deriving (Eq, Ord, Read, Show)

instance HasSchema EffSysRef where
  valueSchemaDefinition _ =
    SchemaDefinition
      { schemaDefinitionDisplayName = Just "EffSysRef"
      , schemaDefinitionVersion = ValueSchemaVersion 1
      , schemaDefinitionShape =
          ValueRecordShape
            [ ( "astRoot"
              , SchemaDefinition
                  { schemaDefinitionDisplayName = Just "AstRoot"
                  , schemaDefinitionVersion = ValueSchemaVersion 1
                  , schemaDefinitionShape = ValueScalarShape ValueText
                  }
              )
            , ( "registry"
              , SchemaDefinition
                  { schemaDefinitionDisplayName = Just "EffSysRegistryId"
                  , schemaDefinitionVersion = ValueSchemaVersion 1
                  , schemaDefinitionShape = ValueScalarShape ValueText
                  }
              )
            ]
      }
