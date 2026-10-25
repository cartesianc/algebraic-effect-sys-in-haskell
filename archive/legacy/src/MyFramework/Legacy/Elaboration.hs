module MyFramework.Legacy.Elaboration
  ( elaborateReferencedProgram
  , legacySchemaDefinition
  , surfaceProgramFromReferenced
  ) where

import Data.Char
  ( toLower
  )

import MyFramework.Elaboration
import MyFramework.Frontend
import MyFramework.Schema

-- | Convert the v2 facade into a v5.2 surface program.  This module is a
-- migration boundary: the explicit v2 schema is admitted as seed evidence,
-- then checked by the same elaborator as every other source of evidence.
surfaceProgramFromReferenced ::
  ReferencedProgram ->
  (ElaborationInputs, SurfaceProgram ReferencedProgram)
surfaceProgramFromReferenced currentProgram =
  ( ElaborationInputs
      { elaborationEvidence =
          [ legacyEvidence
              (readBindingKey currentReadKey)
              ("read:" ++ readKeyText currentReadKey)
              (legacySchemaDefinition currentSchema)
          | (currentReadKey, currentSchema) <-
              readRegistryFields (referencedProgramReads currentProgram)
          ]
      }
  , SurfaceProgram
      { surfaceProgramPayload = currentProgram
      , surfaceProgramBindings =
          readBindings ++ concatMap moduleBindings effectModules
      }
  )
  where
    effectModules = referencedProgramEffects currentProgram
    readBindings =
      [ ( currentKey
        , SurfaceLegacy
            (legacySchemaDefinition currentSchema)
            (SurfaceOpaque currentKey)
        )
      | (currentReadKey, currentSchema) <-
          readRegistryFields (referencedProgramReads currentProgram)
      , let currentKey = readBindingKey currentReadKey
      ]

elaborateReferencedProgram ::
  ReferencedProgram ->
  Either [ElaborationError] (ElaboratedProgram ReferencedProgram)
elaborateReferencedProgram currentProgram =
  elaborateProgram currentInputs currentSurface
  where
    (currentInputs, currentSurface) =
      surfaceProgramFromReferenced currentProgram

moduleBindings :: EffectModule -> [(BindingKey, SurfaceBinding)]
moduleBindings currentModule =
  concatMap effectBindings
    (effectRecordFields (effectModuleRecord currentModule))
  where
    effectBindings (currentEffectKey, currentEffect) =
      concatMap
        (uncurry (paramBindings currentEffectKey []))
        (effectDeclParams currentEffect)
    paramBindings currentEffectKey currentPath currentParamKey currentBinding =
      ( currentBindingKey
      , SurfaceLegacy
          (legacySchemaDefinition (paramBindingSchema currentBinding))
          (sourceBinding currentSource)
      )
        : nestedBindings currentEffectKey nextPath currentSource
      where
        nextPath = currentPath ++ [currentParamKey]
        currentBindingKey =
          paramBindingKey
            (effectModuleName currentModule)
            currentEffectKey
            nextPath
        currentSource = paramBindingSource currentBinding

    nestedBindings currentEffectKey currentPath currentSource =
      case currentSource of
        ParamFromRecord currentFields ->
          concatMap
            (uncurry (paramBindings currentEffectKey currentPath))
            currentFields
        _ -> []

sourceBinding :: ParamSource -> SurfaceBinding
sourceBinding currentSource =
  case currentSource of
    ParamFromRead currentRead ->
      SurfaceFromR (readBindingKey currentRead)
    ParamFromLiteral currentLiteral ->
      SurfaceLiteral (surfaceLiteral currentLiteral)
    ParamFromRecord currentFields ->
      SurfaceRecord
        [ ( paramKeyText currentKey
          , SurfaceLegacy
              (legacySchemaDefinition (paramBindingSchema currentBinding))
              (sourceBinding (paramBindingSource currentBinding))
          )
        | (currentKey, currentBinding) <- currentFields
        ]

surfaceLiteral :: ParamLiteral -> SurfaceLiteral
surfaceLiteral currentLiteral =
  case currentLiteral of
    ParamText currentValue -> SurfaceText currentValue
    ParamInteger currentValue -> SurfaceInteger currentValue
    ParamBoolean currentValue -> SurfaceBool currentValue
    ParamUnit -> SurfaceUnit

legacySchemaDefinition :: SchemaIdentity -> SchemaDefinition
legacySchemaDefinition currentSchema =
  SchemaDefinition
    { schemaDefinitionDisplayName = Just (schemaIdentityName currentSchema)
    , schemaDefinitionVersion = ValueSchemaVersion 1
    , schemaDefinitionShape = legacyShape currentSchema
    }

legacyShape :: SchemaIdentity -> ValueSchemaShape
legacyShape currentSchema =
  case schemaIdentityShape currentSchema of
    UnitShape -> ValueUnitShape
    ScalarShape ->
      ValueScalarShape (legacyScalar (schemaIdentityName currentSchema))
    RecordShape currentFields ->
      ValueRecordShape
        [ (fieldNameText currentName, legacySchemaDefinition currentChild)
        | (currentName, currentChild) <- currentFields
        ]
    ProductShape currentItems ->
      ValueProductShape (map legacySchemaDefinition currentItems)

legacyScalar :: String -> ValueScalar
legacyScalar currentName =
  case map toLower currentName of
    "bool" -> ValueBool
    "boolean" -> ValueBool
    "int" -> ValueInteger
    "integer" -> ValueInteger
    "double" -> ValueDecimal
    "decimal" -> ValueDecimal
    "string" -> ValueText
    "text" -> ValueText
    _ -> ValueNominalScalar currentName

readBindingKey :: ReadKey -> BindingKey
readBindingKey currentKey =
  BindingKey ("legacy/read/" ++ readKeyText currentKey)

paramBindingKey ::
  ModuleName ->
  LocalKey ->
  [ParamKey] ->
  BindingKey
paramBindingKey currentModule currentEffect currentPath =
  BindingKey
    ( "legacy/param/"
        ++ moduleNameText currentModule
        ++ "/"
        ++ localKeyText currentEffect
        ++ concatMap (("/" ++) . paramKeyText) currentPath
    )
