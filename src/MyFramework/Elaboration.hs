module MyFramework.Elaboration
  ( BindingKey (..)
  , ElaboratedBinding (..)
  , ElaboratedProgram (..)
  , ElaborationError (..)
  , ElaborationInputs (..)
  , SchemaEvidence (..)
  , SurfaceBinding (..)
  , SurfaceLiteral (..)
  , SurfaceProgram (..)
  , codecEvidence
  , elaborateProgram
  , emptyElaborationInputs
  , importedEvidence
  , legacyEvidence
  , typedEvidence
  ) where

import Data.List
  ( group
  , nub
  , sort
  , sortOn
  )
import qualified Data.Map.Strict as Map
import Data.Proxy
  ( Proxy
  )

import MyFramework.Schema

newtype BindingKey = BindingKey
  { bindingKeyText :: String
  }
  deriving (Eq, Ord, Read, Show)

data SurfaceLiteral
  = SurfaceUnit
  | SurfaceBool Bool
  | SurfaceInteger Integer
  | SurfaceDecimal String
  | SurfaceText String
  deriving (Eq, Ord, Read, Show)

data SurfaceBinding
  = SurfaceFromR BindingKey
  | SurfaceFromMap BindingKey
  | SurfaceLiteral SurfaceLiteral
  | SurfaceRecord [(String, SurfaceBinding)]
  | SurfaceEvidence BindingKey
  | SurfaceOpaque BindingKey
  | SurfaceLegacy SchemaDefinition SurfaceBinding
  | SurfaceEffSysRef BindingKey
  deriving (Eq, Ord, Read, Show)

data SurfaceProgram payload = SurfaceProgram
  { surfaceProgramPayload :: payload
  , surfaceProgramBindings :: [(BindingKey, SurfaceBinding)]
  }
  deriving (Eq, Ord, Read, Show)

data SchemaEvidence = SchemaEvidence
  { schemaEvidenceKey :: BindingKey
  , schemaEvidenceDefinition :: SchemaDefinition
  , schemaEvidenceOrigin :: SchemaOrigin
  , schemaEvidenceSerializable :: Bool
  , schemaEvidenceCodecAvailable :: Bool
  }
  deriving (Eq, Ord, Read, Show)

data ElaborationInputs = ElaborationInputs
  { elaborationEvidence :: [SchemaEvidence]
  }
  deriving (Eq, Ord, Read, Show)

data ElaboratedBinding = ElaboratedBinding
  { elaboratedBindingKey :: BindingKey
  , elaboratedBindingSource :: SurfaceBinding
  , elaboratedBindingSchema :: SchemaDescriptor
  }
  deriving (Eq, Ord, Read, Show)

data ElaboratedProgram payload = ElaboratedProgram
  { elaboratedProgramPayload :: payload
  , elaboratedProgramBindings :: [ElaboratedBinding]
  , elaboratedProgramSchemaCatalog :: SchemaCatalog
  , elaboratedProgramSchemaDigest :: String
  }
  deriving (Eq, Ord, Read, Show)

data ElaborationError
  = SchemaUnresolved BindingKey
  | SchemaConflict BindingKey ValueSchemaId ValueSchemaId
  | SchemaCycle [BindingKey]
  | SchemaCodecMissing BindingKey
  | SchemaVersionConflict
      BindingKey
      ValueSchemaVersion
      ValueSchemaVersion
  | RecordFieldMissing BindingKey [String]
  | RecordFieldUnexpected BindingKey [String]
  | MapOutputMismatch BindingKey BindingKey
  | NonSerializableBoundary BindingKey
  | DuplicateSurfaceBinding [BindingKey]
  | DuplicateRecordField BindingKey [String]
  deriving (Eq, Ord, Read, Show)

data ResolvedSchema = ResolvedSchema
  { resolvedDefinition :: SchemaDefinition
  , resolvedOrigins :: [SchemaOrigin]
  }

emptyElaborationInputs :: ElaborationInputs
emptyElaborationInputs =
  ElaborationInputs
    { elaborationEvidence = []
    }

typedEvidence ::
  HasSchema value =>
  BindingKey ->
  Proxy value ->
  SchemaEvidence
typedEvidence currentKey currentProxy =
  SchemaEvidence
    { schemaEvidenceKey = currentKey
    , schemaEvidenceDefinition = valueSchemaDefinition currentProxy
    , schemaEvidenceOrigin =
        SchemaFromType (bindingKeyText currentKey)
    , schemaEvidenceSerializable = True
    , schemaEvidenceCodecAvailable = False
    }

codecEvidence ::
  BindingKey ->
  SchemaOrigin ->
  Codec value ->
  SchemaEvidence
codecEvidence currentKey currentOrigin currentCodec =
  SchemaEvidence
    { schemaEvidenceKey = currentKey
    , schemaEvidenceDefinition = codecDefinition currentCodec
    , schemaEvidenceOrigin = currentOrigin
    , schemaEvidenceSerializable = codecSerializable currentCodec
    , schemaEvidenceCodecAvailable = True
    }

importedEvidence ::
  BindingKey ->
  String ->
  SchemaDescriptor ->
  SchemaEvidence
importedEvidence currentKey currentArtifact currentDescriptor =
  SchemaEvidence
    { schemaEvidenceKey = currentKey
    , schemaEvidenceDefinition =
        schemaDescriptorDefinition currentDescriptor
    , schemaEvidenceOrigin =
        SchemaFromImportedArtifact currentArtifact
    , schemaEvidenceSerializable = True
    , schemaEvidenceCodecAvailable = False
    }

legacyEvidence ::
  BindingKey ->
  String ->
  SchemaDefinition ->
  SchemaEvidence
legacyEvidence currentKey currentSource currentDefinition =
  SchemaEvidence
    { schemaEvidenceKey = currentKey
    , schemaEvidenceDefinition = currentDefinition
    , schemaEvidenceOrigin =
        SchemaFromLegacyExplicit currentSource
    , schemaEvidenceSerializable = True
    , schemaEvidenceCodecAvailable = False
    }

elaborateProgram ::
  ElaborationInputs ->
  SurfaceProgram payload ->
  Either [ElaborationError] (ElaboratedProgram payload)
elaborateProgram currentInputs currentProgram
  | not (null allErrors) = Left allErrors
  | otherwise =
      Right
        ElaboratedProgram
          { elaboratedProgramPayload = surfaceProgramPayload currentProgram
          , elaboratedProgramBindings = elaboratedBindings
          , elaboratedProgramSchemaCatalog = currentCatalog
          , elaboratedProgramSchemaDigest =
              schemaCatalogDigest currentCatalog
          }
  where
    currentBindings = surfaceProgramBindings currentProgram
    bindingIndex = Map.fromList currentBindings
    evidenceIndex =
      Map.fromListWith
        (++)
        [ (schemaEvidenceKey currentEvidence, [currentEvidence])
        | currentEvidence <- elaborationEvidence currentInputs
        ]
    duplicateErrors =
      case duplicates (map fst currentBindings) of
        [] -> []
        currentDuplicates ->
          [DuplicateSurfaceBinding currentDuplicates]
    allErrors = sort (nub (duplicateErrors ++ resolutionErrors))
    resolutions =
      [ ( currentKey
        , currentBinding
        , resolveKey bindingIndex evidenceIndex [] currentKey
        )
      | (currentKey, currentBinding) <- currentBindings
      ]
    resolutionErrors =
      sort
        ( nub
            ( concat
                [ currentErrors
                | (_, _, Left currentErrors) <- resolutions
                ]
            )
        )
    elaboratedBindings =
      sortOn elaboratedBindingKey
        [ ElaboratedBinding
            { elaboratedBindingKey = currentKey
            , elaboratedBindingSource = currentBinding
            , elaboratedBindingSchema =
                descriptorWithOrigins currentResolved
            }
        | (currentKey, currentBinding, Right currentResolved) <- resolutions
        ]
    currentCatalog =
      buildSchemaCatalog
        [ (currentOrigin, resolvedDefinition currentResolved)
        | (_, _, Right currentResolved) <- resolutions
        , currentOrigin <- resolvedOrigins currentResolved
        ]

resolveKey ::
  Map.Map BindingKey SurfaceBinding ->
  Map.Map BindingKey [SchemaEvidence] ->
  [BindingKey] ->
  BindingKey ->
  Either [ElaborationError] ResolvedSchema
resolveKey bindingIndex evidenceIndex currentStack currentKey
  | currentKey `elem` currentStack =
      Left [SchemaCycle (cyclePath currentKey currentStack)]
  | otherwise =
      case Map.lookup currentKey bindingIndex of
        Nothing ->
          case resolveEvidence evidenceIndex currentKey of
            Right (Just currentEvidence) -> Right currentEvidence
            Right Nothing -> Left [SchemaUnresolved currentKey]
            Left currentErrors -> Left currentErrors
        Just currentBinding -> do
          inferred <-
            resolveBinding
              bindingIndex
              evidenceIndex
              (currentStack ++ [currentKey])
              currentKey
              currentBinding
          currentEvidence <- resolveEvidence evidenceIndex currentKey
          case currentEvidence of
            Nothing -> Right inferred
            Just expected ->
              unifyResolved currentKey inferred expected

resolveBinding ::
  Map.Map BindingKey SurfaceBinding ->
  Map.Map BindingKey [SchemaEvidence] ->
  [BindingKey] ->
  BindingKey ->
  SurfaceBinding ->
  Either [ElaborationError] ResolvedSchema
resolveBinding bindingIndex evidenceIndex currentStack currentKey currentBinding =
  case currentBinding of
    SurfaceFromR currentReference ->
      addOrigin
        (SchemaFromR (bindingKeyText currentReference))
        <$> resolveKey bindingIndex evidenceIndex currentStack currentReference
    SurfaceFromMap currentReference ->
      addOrigin
        (SchemaFromMap (bindingKeyText currentReference))
        <$> resolveKey bindingIndex evidenceIndex currentStack currentReference
    SurfaceLiteral currentLiteral ->
      Right
        ResolvedSchema
          { resolvedDefinition = literalDefinition currentLiteral
          , resolvedOrigins =
              [SchemaFromLiteral (literalKind currentLiteral)]
          }
    SurfaceRecord currentFields ->
      resolveRecord
        bindingIndex
        evidenceIndex
        currentStack
        currentKey
        currentFields
    SurfaceEvidence currentEvidenceKey ->
      case resolveEvidence evidenceIndex currentEvidenceKey of
        Left currentErrors -> Left currentErrors
        Right Nothing -> Left [SchemaUnresolved currentEvidenceKey]
        Right (Just currentEvidence) -> Right currentEvidence
    SurfaceOpaque currentBoundary ->
      case resolveBoundaryEvidence evidenceIndex currentBoundary of
        Left currentErrors -> Left currentErrors
        Right Nothing -> Left [SchemaCodecMissing currentBoundary]
        Right (Just currentEvidence) ->
          Right
            ( addOrigin
                (SchemaFromBoundaryCodec (bindingKeyText currentBoundary))
                currentEvidence
            )
    SurfaceLegacy currentDefinition currentChild ->
      case currentChild of
        SurfaceOpaque _ ->
          Right
            ResolvedSchema
              { resolvedDefinition = currentDefinition
              , resolvedOrigins =
                  [SchemaFromLegacyExplicit (bindingKeyText currentKey)]
              }
        _ -> do
          currentResolved <-
            resolveBinding
              bindingIndex
              evidenceIndex
              currentStack
              currentKey
              currentChild
          unifyResolved
            currentKey
            currentResolved
            ResolvedSchema
              { resolvedDefinition = currentDefinition
              , resolvedOrigins =
                  [SchemaFromLegacyExplicit (bindingKeyText currentKey)]
              }
    SurfaceEffSysRef currentReference ->
      addOrigin
        (SchemaFromEffSysRef (bindingKeyText currentReference))
        <$> resolveKey bindingIndex evidenceIndex currentStack currentReference

resolveRecord ::
  Map.Map BindingKey SurfaceBinding ->
  Map.Map BindingKey [SchemaEvidence] ->
  [BindingKey] ->
  BindingKey ->
  [(String, SurfaceBinding)] ->
  Either [ElaborationError] ResolvedSchema
resolveRecord bindingIndex evidenceIndex currentStack currentKey currentFields
  | not (null allFieldErrors) = Left allFieldErrors
  | otherwise =
      Right
        ResolvedSchema
          { resolvedDefinition =
              SchemaDefinition
                { schemaDefinitionDisplayName = Nothing
                , schemaDefinitionVersion = ValueSchemaVersion 1
                , schemaDefinitionShape =
                    ValueRecordShape
                      [ ( currentName
                        , resolvedDefinition currentResolved
                        )
                      | ( currentName
                        , Right currentResolved
                        ) <- fieldResolutions
                      ]
                }
          , resolvedOrigins =
              sort
                ( nub
                    ( SchemaFromRecord
                        : concat
                          [ resolvedOrigins currentResolved
                          | (_, Right currentResolved) <- fieldResolutions
                          ]
                    )
                )
          }
  where
    duplicateFields = duplicates (map fst currentFields)
    allFieldErrors =
      sort
        ( nub
            ( [DuplicateRecordField currentKey duplicateFields | not (null duplicateFields)]
                ++ fieldErrors
            )
        )
    fieldResolutions =
      [ ( currentName
        , resolveBinding
            bindingIndex
            evidenceIndex
            currentStack
            currentKey
            currentChild
        )
      | (currentName, currentChild) <- currentFields
      ]
    fieldErrors =
      sort
        ( nub
            ( concat
                [ currentErrors
                | (_, Left currentErrors) <- fieldResolutions
                ]
            )
        )

resolveEvidence ::
  Map.Map BindingKey [SchemaEvidence] ->
  BindingKey ->
  Either [ElaborationError] (Maybe ResolvedSchema)
resolveEvidence evidenceIndex currentKey =
  case Map.findWithDefault [] currentKey evidenceIndex of
    [] -> Right Nothing
    currentEvidence
      | any (not . schemaEvidenceSerializable) currentEvidence ->
          Left [NonSerializableBoundary currentKey]
      | not (null versionConflicts) ->
          Left versionConflicts
      | allDefinitionsAgree definitions ->
          Right
            ( Just
                ResolvedSchema
                  { resolvedDefinition = head definitions
                  , resolvedOrigins =
                      sort
                        (nub (map schemaEvidenceOrigin currentEvidence))
                  }
            )
      | otherwise ->
          Left
            [ SchemaConflict
                currentKey
                (schemaDescriptorId firstDescriptor)
                (schemaDescriptorId currentDescriptor)
            | currentDescriptor <- drop 1 descriptors
            , schemaDescriptorId currentDescriptor
                /= schemaDescriptorId firstDescriptor
            ]
      where
        definitions = map schemaEvidenceDefinition currentEvidence
        descriptors =
          [ descriptorFor
              (schemaEvidenceOrigin currentItem)
              (schemaEvidenceDefinition currentItem)
          | currentItem <- currentEvidence
          ]
        firstDescriptor = head descriptors
        versionConflicts = evidenceVersionConflicts currentKey definitions

resolveBoundaryEvidence ::
  Map.Map BindingKey [SchemaEvidence] ->
  BindingKey ->
  Either [ElaborationError] (Maybe ResolvedSchema)
resolveBoundaryEvidence evidenceIndex currentKey = do
  currentResolved <- resolveEvidence evidenceIndex currentKey
  case currentResolved of
    Nothing -> Right Nothing
    Just _
      | any schemaEvidenceCodecAvailable currentEvidence ->
          Right currentResolved
      | otherwise -> Left [SchemaCodecMissing currentKey]
  where
    currentEvidence = Map.findWithDefault [] currentKey evidenceIndex

unifyResolved ::
  BindingKey ->
  ResolvedSchema ->
  ResolvedSchema ->
  Either [ElaborationError] ResolvedSchema
unifyResolved currentKey inferred expected
  | semanticDefinitionEqual inferredDefinition expectedDefinition =
      Right
        ResolvedSchema
          { resolvedDefinition = preferredDefinition inferredDefinition expectedDefinition
          , resolvedOrigins =
              sort
                (nub (resolvedOrigins inferred ++ resolvedOrigins expected))
          }
  | schemaDefinitionShape inferredDefinition
      == schemaDefinitionShape expectedDefinition =
      Left
        [ SchemaVersionConflict
            currentKey
            (schemaDefinitionVersion inferredDefinition)
            (schemaDefinitionVersion expectedDefinition)
        ]
  | otherwise =
      Left
        ( recordDifferenceErrors currentKey inferredDefinition expectedDefinition
            ++ [ SchemaConflict
                  currentKey
                  (schemaDescriptorId inferredDescriptor)
                  (schemaDescriptorId expectedDescriptor)
               ]
        )
  where
    inferredDefinition = resolvedDefinition inferred
    expectedDefinition = resolvedDefinition expected
    inferredDescriptor =
      descriptorFor (headOrigin inferred) inferredDefinition
    expectedDescriptor =
      descriptorFor (headOrigin expected) expectedDefinition

semanticDefinitionEqual :: SchemaDefinition -> SchemaDefinition -> Bool
semanticDefinitionEqual left right =
  schemaDefinitionVersion left == schemaDefinitionVersion right
    && schemaDefinitionShape (canonicalSchemaDefinition left)
      == schemaDefinitionShape (canonicalSchemaDefinition right)

preferredDefinition :: SchemaDefinition -> SchemaDefinition -> SchemaDefinition
preferredDefinition inferred expected =
  case schemaDefinitionDisplayName expected of
    Just _ -> expected
    Nothing -> inferred

allDefinitionsAgree :: [SchemaDefinition] -> Bool
allDefinitionsAgree [] = True
allDefinitionsAgree (currentDefinition : remaining) =
  all (semanticDefinitionEqual currentDefinition) remaining

evidenceVersionConflicts ::
  BindingKey ->
  [SchemaDefinition] ->
  [ElaborationError]
evidenceVersionConflicts currentKey currentDefinitions =
  [ SchemaVersionConflict
      currentKey
      (schemaDefinitionVersion left)
      (schemaDefinitionVersion right)
  | left <- currentDefinitions
  , right <- currentDefinitions
  , schemaDefinitionShape (canonicalSchemaDefinition left)
      == schemaDefinitionShape (canonicalSchemaDefinition right)
  , schemaDefinitionVersion left /= schemaDefinitionVersion right
  ]

recordDifferenceErrors ::
  BindingKey ->
  SchemaDefinition ->
  SchemaDefinition ->
  [ElaborationError]
recordDifferenceErrors currentKey inferred expected =
  case
      ( schemaDefinitionShape (canonicalSchemaDefinition inferred)
      , schemaDefinitionShape (canonicalSchemaDefinition expected)
      ) of
    (ValueRecordShape inferredFields, ValueRecordShape expectedFields) ->
      missingErrors ++ unexpectedErrors
      where
        inferredNames = map fst inferredFields
        expectedNames = map fst expectedFields
        missing = [currentName | currentName <- expectedNames, currentName `notElem` inferredNames]
        unexpected = [currentName | currentName <- inferredNames, currentName `notElem` expectedNames]
        missingErrors
          | null missing = []
          | otherwise = [RecordFieldMissing currentKey missing]
        unexpectedErrors
          | null unexpected = []
          | otherwise = [RecordFieldUnexpected currentKey unexpected]
    _ -> []

descriptorWithOrigins :: ResolvedSchema -> SchemaDescriptor
descriptorWithOrigins currentResolved =
  (descriptorFor (headOrigin currentResolved) (resolvedDefinition currentResolved))
    { schemaDescriptorOrigins = resolvedOrigins currentResolved
    }

headOrigin :: ResolvedSchema -> SchemaOrigin
headOrigin currentResolved =
  case resolvedOrigins currentResolved of
    currentOrigin : _ -> currentOrigin
    [] -> SchemaFromRecord

addOrigin :: SchemaOrigin -> ResolvedSchema -> ResolvedSchema
addOrigin currentOrigin currentResolved =
  currentResolved
    { resolvedOrigins =
        sort (nub (currentOrigin : resolvedOrigins currentResolved))
    }

literalDefinition :: SurfaceLiteral -> SchemaDefinition
literalDefinition currentLiteral =
  SchemaDefinition
    { schemaDefinitionDisplayName = Just (literalKind currentLiteral)
    , schemaDefinitionVersion = ValueSchemaVersion 1
    , schemaDefinitionShape =
        case currentLiteral of
          SurfaceUnit -> ValueUnitShape
          SurfaceBool _ -> ValueScalarShape ValueBool
          SurfaceInteger _ -> ValueScalarShape ValueInteger
          SurfaceDecimal _ -> ValueScalarShape ValueDecimal
          SurfaceText _ -> ValueScalarShape ValueText
    }

literalKind :: SurfaceLiteral -> String
literalKind currentLiteral =
  case currentLiteral of
    SurfaceUnit -> "Unit"
    SurfaceBool _ -> "Bool"
    SurfaceInteger _ -> "Integer"
    SurfaceDecimal _ -> "Decimal"
    SurfaceText _ -> "Text"

cyclePath :: BindingKey -> [BindingKey] -> [BindingKey]
cyclePath currentKey currentStack =
  dropWhile (/= currentKey) currentStack ++ [currentKey]

duplicates :: Ord value => [value] -> [value]
duplicates =
  map head
    . filter ((> 1) . length)
    . group
    . sort
