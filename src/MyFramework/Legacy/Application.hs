module MyFramework.Legacy.Application
  ( LegacyApplicationArtifacts (..)
  , LegacyApplicationError (..)
  , compileLegacyProgram
  , legacyApplicationArtifacts
  ) where

import Data.List
  ( sortOn
  )
import qualified Data.Map.Strict as Map

import MyFramework.Effect
import MyFramework.Frontend
import MyFramework.Graph
import MyFramework.Legacy.Elaboration
  ( legacySchemaDefinition
  )
import MyFramework.Schema

data LegacyApplicationArtifacts = LegacyApplicationArtifacts
  { legacyApplicationRegistry :: EffectRegistry
  , legacyApplicationTransforms :: TransformRegistry
  , legacyApplicationAst :: AstPlan
  }
  deriving (Eq, Ord, Read, Show)

data LegacyApplicationError
  = LegacyFrontendFailure [FrontendError]
  | LegacyGraphFailure [GraphError]
  deriving (Eq, Ord, Read, Show)

legacyApplicationArtifacts ::
  ReferencedProgram ->
  Either [LegacyApplicationError] LegacyApplicationArtifacts
legacyApplicationArtifacts currentProgram =
  case resolveProgram currentProgram of
    Left currentErrors -> Left [LegacyFrontendFailure currentErrors]
    Right currentResolved ->
      Right
        LegacyApplicationArtifacts
          { legacyApplicationRegistry =
              EffectRegistry (sortOn (someEffectRefKey . effectIrRef) allEffects)
          , legacyApplicationTransforms =
              TransformRegistry (sortOn transformDeclRef allTransforms)
          , legacyApplicationAst = resolvedAst applicationIndex currentResolved
          }
  where
    currentReads =
      readRegistryFields (referencedProgramReads currentProgram)
    currentEffects =
      [ ( effectAddressFor (effectModuleName currentModule) currentKey
        , currentEffect
        )
      | currentModule <- referencedProgramEffects currentProgram
      , (currentKey, currentEffect) <-
          effectRecordFields (effectModuleRecord currentModule)
      ]
    readEffects = map (uncurry legacyReadEffect) currentReads
    commandEffects =
      [ legacyCommandEffect effectKindIndex currentAddress currentEffect
      | (currentAddress, currentEffect) <- currentEffects
      ]
    effectKindIndex =
      Map.fromList
        [ (currentAddress, legacyEffectKind (effectDeclType currentEffect))
        | (currentAddress, currentEffect) <- currentEffects
        ]
    aggregateReadEffects =
      [ legacyAggregateReadEffect currentAddress currentEffect
      | (currentAddress, currentEffect) <- currentEffects
      ]
    mapEffects =
      [ legacyMapEffect currentAddress currentEffect
      | (currentAddress, currentEffect) <- currentEffects
      ]
    allEffects = readEffects ++ commandEffects ++ aggregateReadEffects ++ mapEffects
    allTransforms =
      [ legacyTransform currentAddress currentEffect
      | (currentAddress, currentEffect) <- currentEffects
      ]
    currentApplications =
      [ ( currentAddress
        , legacyApplication currentAddress currentEffect
        )
      | (currentAddress, currentEffect) <- currentEffects
      ]
    applicationIndex = Map.fromList currentApplications

compileLegacyProgram ::
  ReferencedProgram ->
  Either [LegacyApplicationError] CompiledGraphs
compileLegacyProgram currentProgram = do
  currentArtifacts <- legacyApplicationArtifacts currentProgram
  case
      compileGraphs
        (legacyApplicationRegistry currentArtifacts)
        (legacyApplicationTransforms currentArtifacts)
        (legacyApplicationAst currentArtifacts) of
    Left currentErrors -> Left [LegacyGraphFailure currentErrors]
    Right currentGraphs -> Right currentGraphs

legacyReadEffect :: ReadKey -> SchemaIdentity -> EffectIR
legacyReadEffect currentKey currentSchema =
  EffectIR
    { effectIrRef = SomeEffectRef (legacyReadEffectKey currentKey) R
    , effectIrInput = Nothing
    , effectIrSpec =
        ReadEffect
          ReadSpec
            { readSpecValueSchema = legacySchemaId currentSchema
            , readSpecSource = ValueExternal ("legacy/read/" ++ readKeyText currentKey)
            }
    }

legacyCommandEffect ::
  Map.Map EffectAddress EffectKind ->
  EffectAddress ->
  EffectDecl ->
  EffectIR
legacyCommandEffect effectKindIndex currentAddress currentEffect =
  EffectIR
    { effectIrRef = SomeEffectRef currentKey currentKind
    , effectIrInput =
        fmap
          ( \currentInput ->
              SomeEffectRef
                ( legacyCommandEffectKey
                    (effectAddressModule currentAddress)
                    currentInput
                )
                ( Map.findWithDefault
                    E
                    ( effectAddressFor
                        (effectAddressModule currentAddress)
                        currentInput
                    )
                    effectKindIndex
                )
          )
          (effectDeclInput currentEffect)
    , effectIrSpec =
        CommandEffect
          CommandSpec
            { commandSpecParams = legacyParams currentEffect
            , commandSpecObservationSchema = unitSchemaId
            }
    }
  where
    currentKey = legacyCommandEffectKeyFor currentAddress
    currentKind = legacyEffectKind (effectDeclType currentEffect)

legacyAggregateReadEffect :: EffectAddress -> EffectDecl -> EffectIR
legacyAggregateReadEffect currentAddress currentEffect =
  EffectIR
    { effectIrRef = SomeEffectRef (legacyAggregateReadKey currentAddress) R
    , effectIrInput = Nothing
    , effectIrSpec =
        ReadEffect
          ReadSpec
            { readSpecValueSchema = legacyArgumentSchemaId currentEffect
            , readSpecSource = legacyArgumentSource currentEffect
            }
    }

legacyMapEffect :: EffectAddress -> EffectDecl -> EffectIR
legacyMapEffect currentAddress currentEffect =
  EffectIR
    { effectIrRef = SomeEffectRef (legacyMapEffectKey currentAddress) MAP
    , effectIrInput = Nothing
    , effectIrSpec =
        MapEffect
          MapSpec
            { mapSpecTransform = legacyTransformRef currentAddress
            , mapSpecInputSchema = legacyArgumentSchemaId currentEffect
            , mapSpecOutput = legacyParams currentEffect
            }
    }

legacyTransform :: EffectAddress -> EffectDecl -> TransformDecl
legacyTransform currentAddress currentEffect =
  TransformDecl
    { transformDeclRef = legacyTransformRef currentAddress
    , transformDeclInputSchema = legacyArgumentSchemaId currentEffect
    , transformDeclOutput = legacyParams currentEffect
    }

legacyApplication :: EffectAddress -> EffectDecl -> EffectApplication
legacyApplication currentAddress currentEffect =
  EffectApplication
    { effectApplicationKey =
        ApplicationKey ("legacy/application/" ++ renderAddress currentAddress)
    , effectApplicationCommand =
        SomeEffectRef
          (legacyCommandEffectKeyFor currentAddress)
          (legacyEffectKind (effectDeclType currentEffect))
    , effectApplicationMap =
        SomeEffectRef (legacyMapEffectKey currentAddress) MAP
    , effectApplicationRead =
        SomeEffectRef (legacyAggregateReadKey currentAddress) R
    }

legacyParams :: EffectDecl -> [ParamSpec]
legacyParams currentEffect =
  [ ParamSpec
      { paramSpecName = ParamName (paramKeyText currentName)
      , paramSpecSchema = legacySchemaId (paramBindingSchema currentBinding)
      }
  | (currentName, currentBinding) <- effectDeclParams currentEffect
  ]

legacyArgumentSchemaId :: EffectDecl -> ValueSchemaId
legacyArgumentSchemaId currentEffect =
  schemaIdForDefinition
    ( case effectDeclParams currentEffect of
        [] -> unitDefinition
        currentParams ->
          SchemaDefinition
            { schemaDefinitionDisplayName = Nothing
            , schemaDefinitionVersion = ValueSchemaVersion 1
            , schemaDefinitionShape =
                ValueRecordShape
                  [ ( paramKeyText currentName
                    , legacySchemaDefinition (paramBindingSchema currentBinding)
                    )
                  | (currentName, currentBinding) <- currentParams
                  ]
            }
    )

legacyArgumentSource :: EffectDecl -> ValueSourceSpec
legacyArgumentSource currentEffect =
  case effectDeclParams currentEffect of
    [] -> ValueLiteral EncodedUnit
    currentParams ->
      ValueRecord
        [ ( ParamName (paramKeyText currentName)
          , legacyParamSource (paramBindingSource currentBinding)
          )
        | (currentName, currentBinding) <- currentParams
        ]

legacyParamSource :: ParamSource -> ValueSourceSpec
legacyParamSource currentSource =
  case currentSource of
    ParamFromRead currentRead ->
      ValueFromR (SomeEffectRef (legacyReadEffectKey currentRead) R)
    ParamFromLiteral currentLiteral ->
      ValueLiteral
        ( case currentLiteral of
            ParamText currentValue -> EncodedText currentValue
            ParamInteger currentValue -> EncodedInteger currentValue
            ParamBoolean currentValue -> EncodedBool currentValue
            ParamUnit -> EncodedUnit
        )
    ParamFromRecord currentFields ->
      ValueRecord
        [ ( ParamName (paramKeyText currentName)
          , legacyParamSource (paramBindingSource currentBinding)
          )
        | (currentName, currentBinding) <- currentFields
        ]

resolvedAst ::
  Map.Map EffectAddress EffectApplication ->
  ResolvedNode ->
  AstPlan
resolvedAst applicationIndex currentNode =
  case currentNode of
    ResolvedControl _ currentModule currentKind currentChildren ->
      AstPlanBranch
        (AstNodeKey (moduleNameText currentModule))
        (legacyBranchKind currentKind)
        (map (resolvedAst applicationIndex) currentChildren)
    ResolvedEffectLeaf _ currentAddress _ ->
      case Map.lookup currentAddress applicationIndex of
        Just currentApplication ->
          AstPlanApplication
            (AstNodeKey (localKeyText (effectAddressKey currentAddress)))
            currentApplication
        Nothing ->
          error "validated legacy program lost an effect application"

legacyBranchKind :: ControlKind -> AstBranchKind
legacyBranchKind currentKind =
  case currentKind of
    ControlChain -> AstChain
    ControlParallel -> AstParallel
    ControlFallback -> AstFallback
    ControlRace -> AstRace

legacyEffectKind :: EffectType -> EffectKind
legacyEffectKind currentKind =
  case currentKind of
    EffectC -> C
    EffectU -> U
    EffectD -> D
    EffectE -> E

legacySchemaId :: SchemaIdentity -> ValueSchemaId
legacySchemaId = schemaIdForDefinition . legacySchemaDefinition

schemaIdForDefinition :: SchemaDefinition -> ValueSchemaId
schemaIdForDefinition currentDefinition =
  schemaDescriptorId
    (descriptorFor SchemaFromRecord currentDefinition)

unitDefinition :: SchemaDefinition
unitDefinition =
  SchemaDefinition
    { schemaDefinitionDisplayName = Just "Unit"
    , schemaDefinitionVersion = ValueSchemaVersion 1
    , schemaDefinitionShape = ValueUnitShape
    }

unitSchemaId :: ValueSchemaId
unitSchemaId = schemaIdForDefinition unitDefinition

legacyReadEffectKey :: ReadKey -> EffectKey
legacyReadEffectKey currentKey =
  EffectKey ("legacy/read/" ++ readKeyText currentKey)

legacyCommandEffectKeyFor :: EffectAddress -> EffectKey
legacyCommandEffectKeyFor currentAddress =
  legacyCommandEffectKey
    (effectAddressModule currentAddress)
    (effectAddressKey currentAddress)

legacyCommandEffectKey :: ModuleName -> LocalKey -> EffectKey
legacyCommandEffectKey currentModule currentKey =
  EffectKey
    ( "legacy/effect/"
        ++ moduleNameText currentModule
        ++ "/"
        ++ localKeyText currentKey
    )

legacyAggregateReadKey :: EffectAddress -> EffectKey
legacyAggregateReadKey currentAddress =
  EffectKey ("legacy/application-r/" ++ renderAddress currentAddress)

legacyMapEffectKey :: EffectAddress -> EffectKey
legacyMapEffectKey currentAddress =
  EffectKey ("legacy/application-map/" ++ renderAddress currentAddress)

legacyTransformRef :: EffectAddress -> TransformRef
legacyTransformRef currentAddress =
  TransformRef ("legacy/transform/" ++ renderAddress currentAddress)

renderAddress :: EffectAddress -> String
renderAddress currentAddress =
  moduleNameText (effectAddressModule currentAddress)
    ++ "/"
    ++ localKeyText (effectAddressKey currentAddress)

effectAddressFor :: ModuleName -> LocalKey -> EffectAddress
effectAddressFor currentModule currentKey =
  EffectAddress
    { effectAddressModule = currentModule
    , effectAddressKey = currentKey
    }
