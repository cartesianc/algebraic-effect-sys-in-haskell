{-# LANGUAGE DataKinds #-}

module Main (main) where

import Control.Monad
  ( unless
  )
import Data.List
  ( intercalate
  , isInfixOf
  , sort
  )
import System.Exit
  ( exitFailure
  )
import Text.Read
  ( readMaybe
  )

import MyFramework.Effect
import MyFramework.Legacy.Migration hiding
  ( FrontendError (EffectInputCycle)
  )
import MyFramework.Graph
import MyFramework.Legacy.Application
import MyFramework.Schema

data FetchParams
data Page
data Source

data Check = Check
  { checkName :: String
  , checkPassed :: Bool
  , checkObserved :: String
  }

main :: IO ()
main = do
  let currentResult = compileGraphs validRegistry validTransforms repeatedPlan
      currentChecks =
        [ Check
            "effect-application-six-kinds-roundtrip"
            registryRoundTrip
            (show (map (someEffectRefKind . effectIrRef) (effectRegistryEffects validRegistry)))
        , Check
            "effect-application-roundtrip"
            (readMaybe (show fetchApplication) == Just fetchApplication)
            (show fetchApplication)
        , Check
            "effect-application-occurrences-independent"
            (occurrencesIndependent currentResult)
            (show (occurrenceIds currentResult))
        , Check
            "effect-application-ast-input-value-graphs-separated"
            (graphsSeparated currentResult)
            (show (graphSizes currentResult))
        , Check
            "effect-application-continuation-identity-stable"
            (continuationsStable currentResult)
            (show (continuationIds currentResult))
        , Check
            "effect-application-ast-path-provenance"
            (pathsPreserved currentResult)
            (show (occurrencePaths currentResult))
        , Check
            "effect-application-map-missing-rejected"
            (hasGraphError isMapMissing missingMapResult)
            (show missingMapResult)
        , Check
            "effect-application-output-mismatch-rejected"
            ( hasGraphError isArityMismatch outputMismatchResult
                && hasGraphError isParamMismatch outputMismatchResult
            )
            (show outputMismatchResult)
        , Check
            "effect-application-illegal-r-reference-rejected"
            (hasGraphError isValueReferenceKind invalidValueRefResult)
            (show invalidValueRefResult)
        , Check
            "effect-application-input-cycle-rejected"
            (hasGraphError isInputCycle inputCycleResult)
            (show inputCycleResult)
        , Check
            "effect-application-transform-registry-independent"
            (hasGraphError isTransformMissing missingTransformResult)
            (show missingTransformResult)
        , Check
            "effect-application-r-in-effect-registry"
            rLivesInEffectRegistry
            "R and MAP are ordinary EffectIR entries"
        , Check
            "effect-application-state-projection-separated"
            stateProjectionSeparated
            (show dormantProjection)
        , Check
            "effect-application-handler-param-order-preserved"
            handlerParamOrderPreserved
            (show commandParams)
        , Check
            "effect-application-legacy-migration-deterministic"
            legacyMigrationDeterministic
            ( if legacyMigrationDeterministic
                then "legacy ParamBinding lowered to deterministic R/MAP/Application"
                else show legacyCompileResult
            )
        ]
      succeeded = all checkPassed currentChecks
  putStrLn (renderReport currentChecks succeeded)
  unless succeeded exitFailure

unitId, textId, integerId, fetchArgsId :: ValueSchemaId
unitId = schemaId unitDefinition
textId = schemaId textDefinition
integerId = schemaId integerDefinition
fetchArgsId =
  schemaId
    ( SchemaDefinition
        (Just "FetchParams")
        (ValueSchemaVersion 1)
        ( ValueRecordShape
            [ ("url", textDefinition)
            , ("limit", integerDefinition)
            ]
        )
    )

schemaId :: SchemaDefinition -> ValueSchemaId
schemaId currentDefinition =
  schemaDescriptorId (descriptorFor SchemaFromRecord currentDefinition)

unitDefinition, textDefinition, integerDefinition :: SchemaDefinition
unitDefinition = SchemaDefinition (Just "Unit") (ValueSchemaVersion 1) ValueUnitShape
textDefinition =
  SchemaDefinition
    (Just "Text")
    (ValueSchemaVersion 1)
    (ValueScalarShape ValueText)
integerDefinition =
  SchemaDefinition
    (Just "Integer")
    (ValueSchemaVersion 1)
    (ValueScalarShape ValueInteger)

fetchRef :: EffectRef 'E FetchParams Page
fetchRef = eEffectRef (EffectKey "fetch")

authorizeRef :: EffectRef 'E () ()
authorizeRef = eEffectRef (EffectKey "authorize")

createRef :: EffectRef 'C () ()
createRef = cEffectRef (EffectKey "create")

updateRef :: EffectRef 'U () ()
updateRef = uEffectRef (EffectKey "update")

deleteRef :: EffectRef 'D () ()
deleteRef = dEffectRef (EffectKey "delete")

sourceRef :: R Source
sourceRef = rEffectRef (EffectKey "source")

requestMapRef :: EffectRef 'MAP Source FetchParams
requestMapRef = mapEffectRef (EffectKey "request-map")

requestTransform :: TransformRef
requestTransform = TransformRef "request-transform"

commandParams :: [ParamSpec]
commandParams =
  [ ParamSpec (ParamName "url") textId
  , ParamSpec (ParamName "limit") integerId
  ]

validRegistry :: EffectRegistry
validRegistry =
  EffectRegistry
    [ commandEffect authorizeRef Nothing (CommandSpec unitId [] unitId)
    , commandEffect createRef Nothing (CommandSpec unitId [] unitId)
    , commandEffect updateRef Nothing (CommandSpec unitId [] unitId)
    , commandEffect deleteRef Nothing (CommandSpec unitId [] unitId)
    , readEffect
        sourceRef
        Nothing
        (ReadSpec textId (ValueExternal "crawler.seed"))
    , mapEffect
        requestMapRef
        Nothing
        (MapSpec requestTransform textId commandParams)
    , commandEffect
        fetchRef
        (Just (eraseEffectRef authorizeRef))
        (CommandSpec fetchArgsId commandParams unitId)
    ]

validTransforms :: TransformRegistry
validTransforms =
  TransformRegistry
    [ TransformDecl
        { transformDeclRef = requestTransform
        , transformDeclInputSchema = textId
        , transformDeclOutput = commandParams
        }
    ]

fetchApplication :: EffectApplication
fetchApplication =
  effectApplication
    (ApplicationKey "fetch-application")
    fetchRef
    requestMapRef
    sourceRef

repeatedPlan :: AstPlan
repeatedPlan =
  AstPlanBranch
    (AstNodeKey "crawler")
    AstParallel
    [ AstPlanApplication (AstNodeKey "fetch") fetchApplication
    , AstPlanApplication (AstNodeKey "fetch") fetchApplication
    ]

registryRoundTrip :: Bool
registryRoundTrip =
  readMaybe (show validRegistry) == Just validRegistry
    && sortKinds
      == [C, U, R, D, E, E, MAP]
  where
    sortKinds =
      sort
        ( map
            (someEffectRefKind . effectIrRef)
            (effectRegistryEffects validRegistry)
        )

occurrencesIndependent :: Either [GraphError] CompiledGraphs -> Bool
occurrencesIndependent (Right currentGraphs) =
  case compiledOccurrences currentGraphs of
    [left, right] ->
      applicationOccurrenceId left /= applicationOccurrenceId right
        && applicationOccurrenceApplication left
          == applicationOccurrenceApplication right
    _ -> False
occurrencesIndependent (Left _) = False

graphsSeparated :: Either [GraphError] CompiledGraphs -> Bool
graphsSeparated (Right currentGraphs) =
  length (astGraphEdges (compiledAstGraph currentGraphs)) == 2
    && length (inputGraphEdges (compiledInputGraph currentGraphs)) == 2
    && length (valueGraphEdges (compiledValueGraph currentGraphs)) == 6
    && all
      ((== ValueObservation) . valueEdgeKind)
      ( filter
          ((== ValueObservationRole) . targetRole currentGraphs)
          (valueGraphEdges (compiledValueGraph currentGraphs))
      )
graphsSeparated (Left _) = False

targetRole :: CompiledGraphs -> ValueEdge -> ValueNodeRole
targetRole currentGraphs currentEdge =
  case
      [ valueNodeRole currentNode
      | currentNode <- valueGraphNodes (compiledValueGraph currentGraphs)
      , valueNodeId currentNode == valueEdgeTo currentEdge
      ] of
    currentRole : _ -> currentRole
    [] -> ValueReadRole

continuationsStable :: Either [GraphError] CompiledGraphs -> Bool
continuationsStable (Right currentGraphs) =
  case compileGraphs validRegistry validTransforms repeatedPlan of
    Right replayed ->
      continuationIds (Right currentGraphs) == continuationIds (Right replayed)
    Left _ -> False
continuationsStable (Left _) = False

pathsPreserved :: Either [GraphError] CompiledGraphs -> Bool
pathsPreserved (Right currentGraphs) =
  case map applicationOccurrencePath (compiledOccurrences currentGraphs) of
    [left, right] -> left /= right && renderAstPath left /= renderAstPath right
    _ -> False
pathsPreserved (Left _) = False

missingMapResult :: Either [GraphError] CompiledGraphs
missingMapResult =
  compileGraphs
    (EffectRegistry (filter ((/= MAP) . someEffectRefKind . effectIrRef) currentEffects))
    validTransforms
    repeatedPlan
  where
    currentEffects = effectRegistryEffects validRegistry

outputMismatchResult :: Either [GraphError] CompiledGraphs
outputMismatchResult =
  compileGraphs
    (EffectRegistry (map replaceMap (effectRegistryEffects validRegistry)))
    ( TransformRegistry
        [ TransformDecl requestTransform textId [head commandParams]
        ]
    )
    repeatedPlan
  where
    replaceMap currentEffect
      | someEffectRefKind (effectIrRef currentEffect) == MAP =
          currentEffect
            { effectIrSpec =
                MapEffect (MapSpec requestTransform textId [head commandParams])
            }
      | otherwise = currentEffect

invalidValueRefResult :: Either [GraphError] CompiledGraphs
invalidValueRefResult =
  compileGraphs
    (EffectRegistry (map replaceRead (effectRegistryEffects validRegistry)))
    validTransforms
    repeatedPlan
  where
    replaceRead currentEffect
      | someEffectRefKey (effectIrRef currentEffect) == effectRefKey sourceRef =
          currentEffect
            { effectIrSpec =
                ReadEffect
                  ( ReadSpec
                      textId
                      (ValueFromR (eraseEffectRef authorizeRef))
                  )
            }
      | otherwise = currentEffect

inputCycleResult :: Either [GraphError] CompiledGraphs
inputCycleResult =
  compileGraphs
    (EffectRegistry (map addCycle (effectRegistryEffects validRegistry)))
    validTransforms
    repeatedPlan
  where
    addCycle currentEffect
      | someEffectRefKey (effectIrRef currentEffect) == effectRefKey authorizeRef =
          currentEffect {effectIrInput = Just (eraseEffectRef fetchRef)}
      | otherwise = currentEffect

missingTransformResult :: Either [GraphError] CompiledGraphs
missingTransformResult =
  compileGraphs validRegistry (TransformRegistry []) repeatedPlan

rLivesInEffectRegistry :: Bool
rLivesInEffectRegistry =
  all
    (`elem` map (someEffectRefKind . effectIrRef) (effectRegistryEffects validRegistry))
    [R, MAP]

dormantProjection :: EffectStateProjection
dormantProjection =
  EffectStateProjection
    { effectStateRef = eraseEffectRef requestMapRef
    , effectStateStatus = EffectDormant
    , effectStateObservation = Nothing
    , effectStateFailure = Nothing
    , effectStateRevision = StateRevision 0
    }

stateProjectionSeparated :: Bool
stateProjectionSeparated =
  "EffectDormant" `notElem` words (show validRegistry)
    && "effectStateStatus" `isInfixOf` show dormantProjection

handlerParamOrderPreserved :: Bool
handlerParamOrderPreserved =
  case
      [ currentSpec
      | currentEffect <- effectRegistryEffects validRegistry
      , someEffectRefKey (effectIrRef currentEffect) == effectRefKey fetchRef
      , CommandEffect currentSpec <- [effectIrSpec currentEffect]
      ] of
    [currentSpec] -> commandSpecParams currentSpec == commandParams
    _ -> False

legacyCompileResult :: Either [LegacyApplicationError] CompiledGraphs
legacyCompileResult = compileLegacyProgram legacyProgram

legacyMigrationDeterministic :: Bool
legacyMigrationDeterministic =
  case (legacyApplicationArtifacts legacyProgram, legacyApplicationArtifacts legacyProgram) of
    (Right left, Right right) ->
      left == right
        && isLegacyCompileSuccessful legacyCompileResult
        && legacyKindsPresent left
    _ -> False

isLegacyCompileSuccessful :: Either error result -> Bool
isLegacyCompileSuccessful (Right _) = True
isLegacyCompileSuccessful (Left _) = False

legacyKindsPresent :: LegacyApplicationArtifacts -> Bool
legacyKindsPresent currentArtifacts =
  R `elem` currentKinds && MAP `elem` currentKinds
  where
    currentKinds =
      map
        (someEffectRefKind . effectIrRef)
        (effectRegistryEffects (legacyApplicationRegistry currentArtifacts))

legacyProgram :: ReferencedProgram
legacyProgram =
  referencedProgram
    legacyModule
    [chain legacyModule [prepareKey, fetchKey]]
    [ effects
        legacyModule
        [ ( prepareKey
          , EffectDecl EffectU Nothing []
          )
        , ( fetchKey
          , EffectDecl
              EffectE
              (Just prepareKey)
              [ ( ParamKey "url"
                , ParamBinding legacyUrlSchema (ParamFromRead legacyRead)
                )
              , ( ParamKey "limit"
                , ParamBinding
                    (scalarType "Integer")
                    (ParamFromLiteral (ParamInteger 5))
                )
              ]
          )
        ]
    ]
    (readRecord [(legacyRead, legacyUrlSchema)])
  where
    legacyModule = ModuleName "crawler"
    prepareKey = LocalKey "prepare"
    fetchKey = LocalKey "fetch"
    legacyRead = ReadKey "seed-url"
    legacyUrlSchema = scalarType "Url"

occurrenceIds ::
  Either [GraphError] CompiledGraphs ->
  [ApplicationOccurrenceId]
occurrenceIds =
  either (const []) (map applicationOccurrenceId . compiledOccurrences)

occurrencePaths :: Either [GraphError] CompiledGraphs -> [AstPath]
occurrencePaths =
  either (const []) (map applicationOccurrencePath . compiledOccurrences)

continuationIds :: Either [GraphError] CompiledGraphs -> [ContinuationId]
continuationIds =
  either
    (const [])
    (map inputEdgeContinuation . inputGraphEdges . compiledInputGraph)

graphSizes :: Either [GraphError] CompiledGraphs -> (Int, Int, Int)
graphSizes (Left _) = (0, 0, 0)
graphSizes (Right currentGraphs) =
  ( length (astGraphEdges (compiledAstGraph currentGraphs))
  , length (inputGraphEdges (compiledInputGraph currentGraphs))
  , length (valueGraphEdges (compiledValueGraph currentGraphs))
  )

hasGraphError ::
  (GraphError -> Bool) ->
  Either [GraphError] result ->
  Bool
hasGraphError currentPredicate =
  either (any currentPredicate) (const False)

isMapMissing, isArityMismatch, isParamMismatch :: GraphError -> Bool
isMapMissing ApplicationMapMissing {} = True
isMapMissing _ = False
isArityMismatch ApplicationParamArityMismatch {} = True
isArityMismatch _ = False
isParamMismatch ApplicationParamMismatch {} = True
isParamMismatch _ = False

isValueReferenceKind, isInputCycle, isTransformMissing :: GraphError -> Bool
isValueReferenceKind ValueReferenceMustBeR {} = True
isValueReferenceKind _ = False
isInputCycle EffectInputCycle {} = True
isInputCycle _ = False
isTransformMissing TransformMissing {} = True
isTransformMissing _ = False

renderReport :: [Check] -> Bool -> String
renderReport currentChecks succeeded =
  "{"
    ++ jsonField "schema" (jsonString "effect-application-witness.v1")
    ++ ","
    ++ jsonField
      "claims"
      ( jsonArray
          [ "{"
              ++ jsonField "name" (jsonString (checkName currentCheck))
              ++ ","
              ++ jsonField "passed" (jsonBool (checkPassed currentCheck))
              ++ ","
              ++ jsonField "observed" (jsonString (checkObserved currentCheck))
              ++ "}"
          | currentCheck <- currentChecks
          ]
      )
    ++ ","
    ++ jsonField "claimManifest" (jsonArray (map (jsonString . checkName) currentChecks))
    ++ ","
    ++ jsonField "passed" (jsonBool succeeded)
    ++ "}"

jsonField :: String -> String -> String
jsonField currentKey currentValue =
  jsonString currentKey ++ ":" ++ currentValue

jsonArray :: [String] -> String
jsonArray currentValues =
  "[" ++ intercalate "," currentValues ++ "]"

jsonBool :: Bool -> String
jsonBool True = "true"
jsonBool False = "false"

jsonString :: String -> String
jsonString currentText =
  "\"" ++ concatMap escapeJson currentText ++ "\""

escapeJson :: Char -> String
escapeJson currentCharacter =
  case currentCharacter of
    '"' -> "\\\""
    '\\' -> "\\\\"
    '\n' -> "\\n"
    '\r' -> "\\r"
    '\t' -> "\\t"
    _ -> [currentCharacter]
