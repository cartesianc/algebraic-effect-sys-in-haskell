module MyFramework.Self.Model
  ( SelfModel
  , SelfModelUser
  , canonicalSelfModelJson
  , decodeSelfModel
  , decodeSelfModelJson
  , encodeSelfModel
  , selfCreateUserAddress
  , selfDeleteUserAddress
  , selfEmitAuditAddress
  , selfModel
  , selfModelEffectCoverage
  , selfModelJsonRoundTrip
  , selfModelProgram
  , selfModelReadCoverage
  , selfModelSchema
  , selfModelSdkVersion
  , selfModelSourceInput
  , selfModelTextRoundTrip
  , selfProgram
  , selfReadUserKey
  , selfUpdateUserAddress
  ) where

import Text.Read
  ( readMaybe )

import MyFramework.CURDE
  ( scalarSchema
  , schemaRefIdentityOf
  )
import MyFramework.Legacy.Facade
import MyFramework.SDK.SourceArtifact
  ( SdkSourceInput
  , buildSdkSourceReport
  , handlerCoverageFromRefs
  , mkSdkSourceInput
  , renderSdkSourceArtifactJson
  , sdkSourceArtifactSchemaV3
  , sdkSourceReportArtifact
  )
import MyFramework.TrustBase.Core
  ( CoreId (..)
  , Digest (..)
  , TrustBaseRef (..)
  )
import MyFramework.TrustBase.Digest
  ( sha256 )
import MyFramework.TrustBase.Json
  ( JsonValue (..)
  , jsonArrayItems
  , jsonObjectField
  , jsonStringValue
  , parseJson
  )
import MyFramework.TrustBase.Types
  ( ClaimName (..)
  , SchemaId (..)
  , SchemaName (..)
  , SchemaVersion (..)
  )

data SelfModelUser

data SelfModel = SelfModel
  { selfModelSchema :: String
  , selfModelSdkVersion :: String
  , selfModelProgram :: ReferencedProgram
  , selfModelEffectCoverage :: [EffectAddress]
  , selfModelReadCoverage :: [ReadKey]
  }
  deriving (Eq, Ord, Read, Show)

selfModelSchemaV3 :: String
selfModelSchemaV3 =
  "myframework-self-model.v3"

selfApp, selfSource, selfSink :: Name
selfApp = name "app"
selfSource = name "source"
selfSink = name "sink"

selfCreateUser, selfUpdateUser, selfDeleteUser, selfEmitAudit :: Name
selfCreateUser = name "createUser"
selfUpdateUser = name "updateUser"
selfDeleteUser = name "deleteUser"
selfEmitAudit = name "emitAudit"

selfUserParam :: Name
selfUserParam =
  name "user"

selfReadUserKey :: ReadKey
selfReadUserKey =
  readKeyOf selfReadUser

selfReadUser :: R
selfReadUser =
  r "readUser" selfUserSchema

selfUserSchema :: SchemaIdentity
selfUserSchema =
  schemaRefIdentityOf (scalarSchema "User")

selfCreateUserAddress :: EffectAddress
selfCreateUserAddress =
  address selfSource selfCreateUser

selfUpdateUserAddress :: EffectAddress
selfUpdateUserAddress =
  address selfSink selfUpdateUser

selfDeleteUserAddress :: EffectAddress
selfDeleteUserAddress =
  address selfSink selfDeleteUser

selfEmitAuditAddress :: EffectAddress
selfEmitAuditAddress =
  address selfSink selfEmitAudit

selfProgram :: ReferencedProgram
selfProgram =
  program
    selfApp
    [ chain selfApp [selfSource, selfSink]
    , chain selfSource [selfCreateUser]
    , chain
        selfSink
        [ selfUpdateUser
        , selfDeleteUser
        , selfEmitAudit
        ]
    ]
    [ effects
        selfSource
        [ ( selfCreateUser
          , Effect
              { crude = C
              , input = none
              , params = []
              }
          )
        ]
    , effects
        selfSink
        [ ( selfUpdateUser
          , Effect
              { crude = U
              , input = none
              , params =
                  [selfUserParam .= fromR selfReadUser]
              }
          )
        , ( selfDeleteUser
          , Effect
              { crude = D
              , input = after selfUpdateUser
              , params = []
              }
          )
        , ( selfEmitAudit
          , Effect
              { crude = E
              , input = after selfDeleteUser
              , params = []
              }
          )
        ]
    ]
    (readRegistry [selfReadUser])

selfModel :: Either [FrontendError] SelfModel
selfModel =
  case validate selfProgram of
    [] ->
      Right
        SelfModel
          { selfModelSchema = selfModelSchemaV3
          , selfModelSdkVersion = "0.1.0.0"
          , selfModelProgram = selfProgram
          , selfModelEffectCoverage =
              [ selfCreateUserAddress
              , selfUpdateUserAddress
              , selfDeleteUserAddress
              , selfEmitAuditAddress
              ]
          , selfModelReadCoverage =
              [selfReadUserKey]
          }
    currentErrors ->
      Left currentErrors

selfModelSourceInput :: SelfModel -> SdkSourceInput
selfModelSourceInput currentModel =
  mkSdkSourceInput
    selfModelCoreRef
    (selfModelSdkVersion currentModel)
    (selfModelProgram currentModel)
    ( Just
        ( handlerCoverageFromRefs
            (selfModelEffectCoverage currentModel)
            (selfModelReadCoverage currentModel)
        )
    )

selfModelCoreRef :: TrustBaseRef
selfModelCoreRef =
  TrustBaseRef
    { trustBaseCoreId = CoreId "self-model-fixture"
    , trustBaseArtifactDigest =
        Digest (sha256 "self-model-fixture-artifact")
    , trustBaseManifestDigest =
        Digest (sha256 "self-model-fixture-manifest")
    , trustBaseSchema =
        SchemaId
          (SchemaName "self-model-fixture")
          (SchemaVersion 1)
    , trustBaseKernelClaims =
        [ClaimName "l0-referenced-frontend-fixture"]
    }

canonicalSelfModelJson :: SelfModel -> String
canonicalSelfModelJson =
  renderSdkSourceArtifactJson
    . sdkSourceReportArtifact
    . buildSdkSourceReport
    . selfModelSourceInput

decodeSelfModelJson :: String -> Either String SelfModel
decodeSelfModelJson currentText = do
  currentJson <- parseJson currentText
  currentSchema <-
    jsonObjectField "schema" currentJson >>= jsonStringValue
  if currentSchema /= sdkSourceArtifactSchemaV3
    then Left "unsupported SelfModel JSON schema"
    else pure ()
  currentVersion <-
    jsonObjectField "sdkVersion" currentJson >>= jsonStringValue
  currentProgramValue <-
    jsonObjectField "program" currentJson
  currentProgram <-
    decodeProgram currentProgramValue
  currentCoverageValue <-
    jsonObjectField "handlerCoverage" currentJson
  (currentEffects, currentReads) <-
    decodeHandlerCoverage currentCoverageValue
  let currentModel =
        SelfModel
          { selfModelSchema = selfModelSchemaV3
          , selfModelSdkVersion = currentVersion
          , selfModelProgram = currentProgram
          , selfModelEffectCoverage = currentEffects
          , selfModelReadCoverage = currentReads
          }
  case validate currentProgram of
    [] ->
      Right currentModel
    currentErrors ->
      Left ("invalid referenced self model: " ++ show currentErrors)

decodeProgram :: JsonValue -> Either String ReferencedProgram
decodeProgram currentValue = do
  currentEncoding <-
    jsonObjectField "encoding" currentValue >>= jsonStringValue
  if currentEncoding /= "ReferencedProgram.ReadShow.v1"
    then Left "unsupported ReferencedProgram encoding"
    else pure ()
  currentDeclaration <-
    jsonObjectField "declaration" currentValue >>= jsonStringValue
  readValue "ReferencedProgram" currentDeclaration

decodeHandlerCoverage ::
  JsonValue ->
  Either String ([EffectAddress], [ReadKey])
decodeHandlerCoverage JsonNull =
  Right ([], [])
decodeHandlerCoverage currentValue = do
  currentKind <-
    jsonObjectField "kind" currentValue >>= jsonStringValue
  if currentKind /= "module-local"
    then Left "unsupported handler coverage kind"
    else pure ()
  currentEffectValues <-
    jsonObjectField "effects" currentValue >>= jsonArrayItems
  currentReadValues <-
    jsonObjectField "reads" currentValue >>= jsonArrayItems
  currentEffects <-
    traverse
      (jsonStringValue >=> readValue "EffectAddress")
      currentEffectValues
  currentReads <-
    traverse
      (jsonStringValue >=> readValue "ReadKey")
      currentReadValues
  pure (currentEffects, currentReads)

(>=>) ::
  (input -> Either error middle) ->
  (middle -> Either error output) ->
  input ->
  Either error output
(>=>) first second currentInput =
  first currentInput >>= second

readValue :: Read value => String -> String -> Either String value
readValue currentName currentText =
  case readMaybe currentText of
    Nothing ->
      Left ("invalid " ++ currentName)
    Just currentValue ->
      Right currentValue

selfModelJsonRoundTrip :: SelfModel -> Bool
selfModelJsonRoundTrip currentModel =
  case decodeSelfModelJson currentJson of
    Left _ ->
      False
    Right decodedModel ->
      canonicalSelfModelJson decodedModel == currentJson
  where
    currentJson =
      canonicalSelfModelJson currentModel

encodeSelfModel :: SelfModel -> String
encodeSelfModel =
  show

decodeSelfModel :: String -> Either String SelfModel
decodeSelfModel currentText =
  case readMaybe currentText of
    Nothing ->
      Left "invalid SelfModel"
    Just currentModel
      | selfModelSchema currentModel /= selfModelSchemaV3 ->
          Left "unsupported SelfModel schema"
      | not
          ( null
              ( validate
                  (selfModelProgram currentModel)
              )
          ) ->
          Left "invalid referenced SelfModel"
      | otherwise ->
          Right currentModel

selfModelTextRoundTrip :: SelfModel -> Bool
selfModelTextRoundTrip currentModel =
  decodeSelfModel (encodeSelfModel currentModel)
    == Right currentModel
