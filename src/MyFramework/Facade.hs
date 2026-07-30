{-# LANGUAGE PatternSynonyms #-}

module MyFramework.Facade
  ( SchemaIdentity (..)
  , SchemaShape (..)
  , FieldName (..)
  , scalarType
  , recordType
  , unitType
  , Name
  , name
  , nameText
  , R
  , r
  , ReadKey
  , readKeyOf
  , readSchemaOf
  , Crude
  , pattern C
  , pattern U
  , pattern D
  , pattern E
  , Effect (..)
  , Binding
  , ParamLiteral (..)
  , fromR
  , literal
  , record
  , none
  , after
  , (.=)
  , ControlDecl
  , EffectModule
  , ReadRegistry
  , ReferencedProgram
  , EffectAddress
  , ResolvedChild (..)
  , ModuleView (..)
  , OccurrencePath (..)
  , ResolvedNode (..)
  , FrontendError (..)
  , chain
  , parallel
  , fallback
  , race
  , effects
  , readRegistry
  , program
  , address
  , validate
  , resolve
  , resolveAll
  ) where

import MyFramework.Frontend
  ( ControlDecl
  , EffectAddress
  , EffectDecl (..)
  , EffectModule
  , EffectType
  , FieldName (..)
  , FrontendError (..)
  , ModuleView (..)
  , OccurrencePath (..)
  , ParamBinding (..)
  , ParamLiteral (..)
  , ParamSource (..)
  , ReadKey
  , ReadRegistry
  , ReferencedProgram
  , ResolvedChild (..)
  , ResolvedNode (..)
  , SchemaIdentity (..)
  , SchemaShape (..)
  , unitType
  )
import qualified MyFramework.Frontend as Frontend

-- | One authoring name domain covers both control-module names and the local
-- child keys that the resolver later classifies as a module or an effect.
-- The distinction belongs to resolution, not to business authoring.
newtype Name = Name
  { nameText :: String
  }
  deriving (Eq, Ord, Read, Show)

name :: String -> Name
name =
  Name

-- | R is a separate typed, lazy data declaration.  It is not a CUDE action
-- and cannot appear in an effect input chain.
data R = R
  { readKeyOf :: ReadKey
  , readSchemaOf :: SchemaIdentity
  }
  deriving (Eq, Ord, Read, Show)

r :: String -> SchemaIdentity -> R
r currentName currentSchema =
  R
    { readKeyOf = Frontend.ReadKey currentName
    , readSchemaOf = currentSchema
    }

type Crude = EffectType

pattern C :: Crude
pattern C = Frontend.EffectC

pattern U :: Crude
pattern U = Frontend.EffectU

pattern D :: Crude
pattern D = Frontend.EffectD

pattern E :: Crude
pattern E = Frontend.EffectE

{-# COMPLETE C, U, D, E #-}

-- | A module-local effect record value.  Its key in 'effects' is its complete
-- local identity, so the value deliberately has no id field.
data Effect = Effect
  { crude :: Crude
  , input :: Maybe Name
  , params :: [(Name, Binding)]
  }
  deriving (Eq, Ord, Read, Show)

type Binding = ParamBinding

fromR :: R -> Binding
fromR currentRead =
  ParamBinding
    { paramBindingSchema = readSchemaOf currentRead
    , paramBindingSource =
        ParamFromRead (readKeyOf currentRead)
    }

literal :: SchemaIdentity -> ParamLiteral -> Binding
literal currentSchema currentValue =
  ParamBinding
    { paramBindingSchema = currentSchema
    , paramBindingSource = ParamFromLiteral currentValue
    }

record :: SchemaIdentity -> [(Name, Binding)] -> Binding
record currentSchema currentFields =
  ParamBinding
    { paramBindingSchema = currentSchema
    , paramBindingSource =
        ParamFromRecord
          [ (toParamKey currentName, currentBinding)
          | (currentName, currentBinding) <- currentFields
          ]
    }

none :: Maybe value
none =
  Nothing

after :: Name -> Maybe Name
after =
  Just

infixr 1 .=

(.=) :: key -> value -> (key, value)
(.=) =
  (,)

scalarType :: String -> SchemaIdentity
scalarType =
  Frontend.scalarType

recordType :: String -> [(FieldName, SchemaIdentity)] -> SchemaIdentity
recordType =
  Frontend.recordType

chain :: Name -> [Name] -> ControlDecl
chain currentModule currentChildren =
  Frontend.chain
    (toModuleName currentModule)
    (map toLocalKey currentChildren)

parallel :: Name -> [Name] -> ControlDecl
parallel currentModule currentChildren =
  Frontend.parallel
    (toModuleName currentModule)
    (map toLocalKey currentChildren)

fallback :: Name -> [Name] -> ControlDecl
fallback currentModule currentChildren =
  Frontend.fallback
    (toModuleName currentModule)
    (map toLocalKey currentChildren)

race :: Name -> [Name] -> ControlDecl
race currentModule currentChildren =
  Frontend.race
    (toModuleName currentModule)
    (map toLocalKey currentChildren)

effects :: Name -> [(Name, Effect)] -> EffectModule
effects currentModule currentEffects =
  Frontend.effects
    (toModuleName currentModule)
    [ (toLocalKey currentName, lowerEffect currentEffect)
    | (currentName, currentEffect) <- currentEffects
    ]

readRegistry :: [R] -> ReadRegistry
readRegistry currentReads =
  Frontend.readRecord
    [ (readKeyOf currentRead, readSchemaOf currentRead)
    | currentRead <- currentReads
    ]

program ::
  Name ->
  [ControlDecl] ->
  [EffectModule] ->
  ReadRegistry ->
  ReferencedProgram
program currentRoot =
  Frontend.referencedProgram (toModuleName currentRoot)

address :: Name -> Name -> EffectAddress
address currentModule currentEffect =
  Frontend.EffectAddress
    (toModuleName currentModule)
    (toLocalKey currentEffect)

validate :: ReferencedProgram -> [FrontendError]
validate =
  Frontend.validateReferencedProgram

resolve ::
  ReferencedProgram ->
  Name ->
  Either [FrontendError] ModuleView
resolve currentProgram currentModule =
  Frontend.resolveModule
    currentProgram
    (toModuleName currentModule)

resolveAll ::
  ReferencedProgram ->
  Either [FrontendError] ResolvedNode
resolveAll =
  Frontend.resolveProgram

lowerEffect :: Effect -> EffectDecl
lowerEffect currentEffect =
  EffectDecl
    { effectDeclType = crude currentEffect
    , effectDeclInput = toLocalKey <$> input currentEffect
    , effectDeclParams =
        [ (toParamKey currentName, currentBinding)
        | (currentName, currentBinding) <- params currentEffect
        ]
    }

toModuleName :: Name -> Frontend.ModuleName
toModuleName =
  Frontend.ModuleName . nameText

toLocalKey :: Name -> Frontend.LocalKey
toLocalKey =
  Frontend.LocalKey . nameText

toParamKey :: Name -> Frontend.ParamKey
toParamKey =
  Frontend.ParamKey . nameText
