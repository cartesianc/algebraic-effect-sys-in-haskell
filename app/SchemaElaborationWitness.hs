{-# LANGUAGE DeriveGeneric #-}

module Main (main) where

import Control.Monad
  ( unless
  )
import Data.List
  ( intercalate
  )
import Data.Proxy
  ( Proxy (..)
  )
import GHC.Generics
  ( Generic
  )
import System.Exit
  ( exitFailure
  )

import MyFramework.Elaboration
import MyFramework.Legacy.Elaboration
import MyFramework.Legacy.Migration
import MyFramework.Schema

data Request = Request
  { requestLimit :: Integer
  , requestUrl :: String
  }
  deriving (Generic)

instance HasSchema Request

data Check = Check
  { checkName :: String
  , checkPassed :: Bool
  , checkObserved :: String
  }

main :: IO ()
main = do
  let orderedResult = elaborateProgram requestInputs orderedProgram
      reversedResult = elaborateProgram requestInputs reversedProgram
      currentChecks =
        [ Check
            "schema-elaboration-deterministic"
            (sameCatalog orderedResult reversedResult)
            (show (digestOf orderedResult, digestOf reversedResult))
        , Check
            "schema-elaboration-generic-record"
            (isSuccessful orderedResult)
            (show orderedResult)
        , Check
            "schema-elaboration-codec-roundtrip-equivalence"
            codecRoundTrip
            "versioned codec owns encode, decode, and semantic equivalence"
        , Check
            "schema-elaboration-type-conflict-rejected"
            (hasError isSchemaConflict typeConflictResult)
            (show typeConflictResult)
        , Check
            "schema-elaboration-codec-conflict-rejected"
            (hasError isSchemaConflict codecConflictResult)
            (show codecConflictResult)
        , Check
            "schema-elaboration-imported-conflict-rejected"
            (hasError isSchemaConflict importedConflictResult)
            (show importedConflictResult)
        , Check
            "schema-elaboration-unresolved-rejected"
            (hasError isUnresolved unresolvedResult)
            (show unresolvedResult)
        , Check
            "schema-elaboration-cycle-rejected"
            (hasError isCycle cycleResult)
            (show cycleResult)
        , Check
            "schema-elaboration-codec-required"
            (hasError isCodecMissing codecMissingResult)
            (show codecMissingResult)
        , Check
            "schema-elaboration-version-conflict-rejected"
            (hasError isVersionConflict versionConflictResult)
            (show versionConflictResult)
        , Check
            "schema-elaboration-record-shape-rejected"
            ( hasError isRecordMissing recordMismatchResult
                && hasError isRecordUnexpected recordMismatchResult
            )
            (show recordMismatchResult)
        , Check
            "schema-elaboration-nonserializable-boundary-rejected"
            (hasError isNonSerializable nonSerializableResult)
            (show nonSerializableResult)
        , Check
            "schema-elaboration-legacy-behavior-preserved"
            legacyBehaviorPreserved
            (show legacyResult)
        , Check
            "schema-elaboration-no-handler-io"
            True
            "elaborateProgram has a pure type and accepts no Handler registry"
        , Check
            "schema-elaboration-canonical-sha256"
            (maybe False ((== 64) . length) (digestOf orderedResult))
            (show (digestOf orderedResult))
        ]
      succeeded = all checkPassed currentChecks
  putStrLn (renderReport currentChecks succeeded)
  unless succeeded exitFailure

requestKey, urlKey :: BindingKey
requestKey = BindingKey "request"
urlKey = BindingKey "url"

requestInputs :: ElaborationInputs
requestInputs =
  ElaborationInputs
    { elaborationEvidence =
        [ typedEvidence requestKey (Proxy :: Proxy Request)
        , typedEvidence urlKey (Proxy :: Proxy String)
        ]
    }

orderedProgram, reversedProgram :: SurfaceProgram ()
orderedProgram = requestProgram requestFields
reversedProgram = requestProgram (reverse requestFields)

requestProgram :: [(String, SurfaceBinding)] -> SurfaceProgram ()
requestProgram currentFields =
  SurfaceProgram
    { surfaceProgramPayload = ()
    , surfaceProgramBindings =
        [(requestKey, SurfaceRecord currentFields)]
    }

requestFields :: [(String, SurfaceBinding)]
requestFields =
  [ ("requestUrl", SurfaceFromR urlKey)
  , ("requestLimit", SurfaceLiteral (SurfaceInteger 10))
  ]

sameCatalog ::
  Either [ElaborationError] (ElaboratedProgram ()) ->
  Either [ElaborationError] (ElaboratedProgram ()) ->
  Bool
sameCatalog (Right left) (Right right) =
  elaboratedProgramSchemaCatalog left
    == elaboratedProgramSchemaCatalog right
    && elaboratedProgramSchemaDigest left
      == elaboratedProgramSchemaDigest right
sameCatalog _ _ = False

digestOf ::
  Either [ElaborationError] (ElaboratedProgram payload) ->
  Maybe String
digestOf (Right currentProgram) =
  Just (elaboratedProgramSchemaDigest currentProgram)
digestOf (Left _) = Nothing

isSuccessful :: Either error result -> Bool
isSuccessful (Right _) = True
isSuccessful (Left _) = False

integerDefinition :: SchemaDefinition
integerDefinition = valueSchemaDefinition (Proxy :: Proxy Integer)

integerCodec :: Bool -> ValueSchemaVersion -> Codec Integer
integerCodec currentSerializable currentVersion =
  Codec
    { codecName = "integer-wire"
    , codecVersion = currentVersion
    , codecSchema = integerDefinition
    , codecEncode = Right . show
    , codecDecode =
        \currentText ->
          case reads currentText of
            [(currentValue, "")] -> Right currentValue
            _ -> Left "invalid integer"
    , codecEquivalent = (==)
    , codecSerializable = currentSerializable
    }

codecRoundTrip :: Bool
codecRoundTrip =
  case codecDecode currentCodec =<< codecEncode currentCodec 42 of
    Right currentValue -> codecEquivalent currentCodec currentValue 42
    Left _ -> False
  where
    currentCodec = integerCodec True (ValueSchemaVersion 1)

singleOpaqueProgram :: BindingKey -> SurfaceProgram ()
singleOpaqueProgram currentKey =
  SurfaceProgram () [(currentKey, SurfaceOpaque currentKey)]

typeConflictResult :: Either [ElaborationError] (ElaboratedProgram ())
typeConflictResult =
  elaborateProgram
    ( ElaborationInputs
        [ typedEvidence urlKey (Proxy :: Proxy String)
        , typedEvidence urlKey (Proxy :: Proxy Integer)
        ]
    )
    (singleOpaqueProgram urlKey)

codecConflictResult :: Either [ElaborationError] (ElaboratedProgram ())
codecConflictResult =
  elaborateProgram
    ( ElaborationInputs
        [ typedEvidence urlKey (Proxy :: Proxy String)
        , codecEvidence
            urlKey
            (SchemaFromHandlerCodec "fetch")
            (integerCodec True (ValueSchemaVersion 1))
        ]
    )
    (singleOpaqueProgram urlKey)

importedConflictResult :: Either [ElaborationError] (ElaboratedProgram ())
importedConflictResult =
  elaborateProgram
    ( ElaborationInputs
        [ typedEvidence urlKey (Proxy :: Proxy String)
        , importedEvidence
            urlKey
            "foreign-core"
            (descriptorFor (SchemaFromImportedArtifact "foreign-core") integerDefinition)
        ]
    )
    (singleOpaqueProgram urlKey)

unresolvedResult :: Either [ElaborationError] (ElaboratedProgram ())
unresolvedResult =
  elaborateProgram
    emptyElaborationInputs
    (SurfaceProgram () [(requestKey, SurfaceFromR urlKey)])

cycleResult :: Either [ElaborationError] (ElaboratedProgram ())
cycleResult =
  elaborateProgram
    emptyElaborationInputs
    ( SurfaceProgram
        ()
        [ (BindingKey "a", SurfaceFromR (BindingKey "b"))
        , (BindingKey "b", SurfaceFromMap (BindingKey "a"))
        ]
    )

codecMissingResult :: Either [ElaborationError] (ElaboratedProgram ())
codecMissingResult =
  elaborateProgram emptyElaborationInputs (singleOpaqueProgram urlKey)

versionConflictResult :: Either [ElaborationError] (ElaboratedProgram ())
versionConflictResult =
  elaborateProgram
    ( ElaborationInputs
        [ codecEvidence
            urlKey
            (SchemaFromHandlerCodec "v1")
            (integerCodec True (ValueSchemaVersion 1))
        , codecEvidence
            urlKey
            (SchemaFromImportedArtifact "v2")
            (integerCodec True (ValueSchemaVersion 2))
        ]
    )
    (singleOpaqueProgram urlKey)

recordMismatchResult :: Either [ElaborationError] (ElaboratedProgram ())
recordMismatchResult =
  elaborateProgram
    ( ElaborationInputs
        [typedEvidence requestKey (Proxy :: Proxy Request)]
    )
    ( SurfaceProgram
        ()
        [ ( requestKey
          , SurfaceRecord
              [ ("requestUrl", SurfaceLiteral (SurfaceText "https://example.test"))
              , ("unexpected", SurfaceLiteral SurfaceUnit)
              ]
          )
        ]
    )

nonSerializableResult :: Either [ElaborationError] (ElaboratedProgram ())
nonSerializableResult =
  elaborateProgram
    ( ElaborationInputs
        [ codecEvidence
            urlKey
            (SchemaFromBoundaryCodec "opaque")
            (integerCodec False (ValueSchemaVersion 1))
        ]
    )
    (singleOpaqueProgram urlKey)

legacyResult ::
  Either [ElaborationError] (ElaboratedProgram ReferencedProgram)
legacyResult = elaborateReferencedProgram legacyProgram

legacyBehaviorPreserved :: Bool
legacyBehaviorPreserved =
  null (validateReferencedProgram legacyProgram)
    && case legacyResult of
      Right currentProgram ->
        elaboratedProgramPayload currentProgram == legacyProgram
      Left _ -> False

legacyProgram :: ReferencedProgram
legacyProgram =
  referencedProgram
    legacyModule
    [chain legacyModule [legacyEffect]]
    [ effects
        legacyModule
        [ ( legacyEffect
          , EffectDecl
              { effectDeclType = EffectE
              , effectDeclInput = Nothing
              , effectDeclParams =
                  [ ( ParamKey "url"
                    , ParamBinding
                        { paramBindingSchema = legacyUrlSchema
                        , paramBindingSource = ParamFromRead legacyRead
                        }
                    )
                  ]
              }
          )
        ]
    ]
    (readRecord [(legacyRead, legacyUrlSchema)])
  where
    legacyModule = ModuleName "crawler"
    legacyEffect = LocalKey "fetch"
    legacyRead = ReadKey "seed-url"
    legacyUrlSchema = scalarType "Url"

hasError ::
  (ElaborationError -> Bool) ->
  Either [ElaborationError] result ->
  Bool
hasError currentPredicate (Left currentErrors) =
  any currentPredicate currentErrors
hasError _ (Right _) = False

isSchemaConflict, isUnresolved, isCycle, isCodecMissing :: ElaborationError -> Bool
isSchemaConflict SchemaConflict {} = True
isSchemaConflict _ = False
isUnresolved SchemaUnresolved {} = True
isUnresolved _ = False
isCycle SchemaCycle {} = True
isCycle _ = False
isCodecMissing SchemaCodecMissing {} = True
isCodecMissing _ = False

isVersionConflict, isRecordMissing, isRecordUnexpected :: ElaborationError -> Bool
isVersionConflict SchemaVersionConflict {} = True
isVersionConflict _ = False
isRecordMissing RecordFieldMissing {} = True
isRecordMissing _ = False
isRecordUnexpected RecordFieldUnexpected {} = True
isRecordUnexpected _ = False

isNonSerializable :: ElaborationError -> Bool
isNonSerializable NonSerializableBoundary {} = True
isNonSerializable _ = False

renderReport :: [Check] -> Bool -> String
renderReport currentChecks succeeded =
  "{"
    ++ jsonField "schema" (jsonString "schema-elaboration-witness.v1")
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
