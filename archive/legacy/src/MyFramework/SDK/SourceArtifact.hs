module MyFramework.SDK.SourceArtifact
  ( SdkHandlerCoverage (..)
  , SdkSourceProgram (..)
  , SdkSourceInput (..)
  , SdkSourceArtifact (..)
  , SdkSourceIssueSeverity (..)
  , SdkSourceIssueCode (..)
  , SdkSourceIssue (..)
  , SdkSourceReport (..)
  , SdkGeneratedSource (..)
  , sdkSourceArtifactSchemaV4
  , sdkSourceReportSchemaV4
  , handlerCoverageFromRefs
  , handlerCoverageFromEffectKeys
  , mkSdkSourceInput
  , mkSdkSourceInputV52
  , sdkLoweringSemanticsDigest
  , canonicalizeSdkSourceInput
  , buildSdkSourceReport
  , sdkSourceReportReady
  , sdkSourceReportCanonical
  , sdkSourceCanonicalizesReferencedProgram
  , renderSdkSourceArtifactJson
  , renderSdkSourceReportJson
  , renderGeneratedSdkSource
  ) where

import Data.Char
  ( ord )
import Data.List
  ( intercalate
  , sort
  , sortOn
  )
import qualified Data.Set as Set
import Numeric
  ( showHex )

import MyFramework.Frontend
import qualified MyFramework.Facade as V52
import MyFramework.TrustBase.Core
  ( Digest (..)
  , SdkCoreLock (..)
  , TrustBaseRef
  , encodeSdkCoreLock
  , validateSdkCoreLock
  )
import MyFramework.TrustBase.Digest
  ( sha256 )

-- | Coverage remains metadata. Effect and R identities stay in separate
-- namespaces and are never flattened into a global handle id.
data SdkHandlerCoverage
  = SdkLegacyHandlerCoverage [EffectAddress] [ReadKey]
  | SdkV52HandlerCoverage [V52.EffectKey] [V52.EffectKey]
  deriving (Eq, Ord, Read, Show)

data SdkSourceProgram
  = SdkLegacyProgram ReferencedProgram
  | SdkV52Program V52.PreparedRuntime
  deriving (Eq, Ord, Read, Show)

data SdkSourceInput = SdkSourceInput
  { sdkSourceSdkVersion :: String
  , sdkSourceCoreLock :: SdkCoreLock
  , sdkSourceProgram :: SdkSourceProgram
  , sdkSourceHandlerCoverage :: Maybe SdkHandlerCoverage
  }
  deriving (Eq, Ord, Show)

data SdkSourceArtifact = SdkSourceArtifact
  { sdkSourceArtifactSchema :: String
  , sdkSourceArtifactSdkVersion :: String
  , sdkSourceArtifactCoreLock :: SdkCoreLock
  , sdkSourceArtifactProgram :: SdkSourceProgram
  , sdkSourceArtifactHandlerCoverage :: Maybe SdkHandlerCoverage
  }
  deriving (Eq, Ord, Show)

data SdkSourceIssueSeverity
  = SdkSourceWarning
  | SdkSourceBlocker
  deriving (Eq, Ord, Read, Show)

data SdkSourceIssueCode
  = EmptySdkSourceVersion
  | InvalidReferencedProgram
  | EmptyHandlerCoverageIdentity
  | InvalidSdkCoreLock
  | SdkSurfaceDigestMismatch
  | SdkLoweringDigestMismatch
  | UnknownEffectCoverageIdentity
  | UnknownReadCoverageIdentity
  deriving (Eq, Ord, Read, Show)

data SdkSourceIssue = SdkSourceIssue
  { sdkSourceIssueCode :: SdkSourceIssueCode
  , sdkSourceIssueSeverity :: SdkSourceIssueSeverity
  , sdkSourceIssueSubject :: String
  , sdkSourceIssueDetail :: String
  }
  deriving (Eq, Ord, Read, Show)

data SdkSourceReport = SdkSourceReport
  { sdkSourceReportSchema :: String
  , sdkSourceReportInput :: SdkSourceInput
  , sdkSourceReportArtifact :: SdkSourceArtifact
  , sdkSourceReportIssues :: [SdkSourceIssue]
  }
  deriving (Eq, Ord, Show)

data SdkGeneratedSource = SdkGeneratedSource
  { sdkGeneratedSourcePath :: FilePath
  , sdkGeneratedSourceLines :: [String]
  }
  deriving (Eq, Ord, Read, Show)

sdkSourceArtifactSchemaV4 :: String
sdkSourceArtifactSchemaV4 =
  "myframework-sdk-source-artifact.v4"

sdkSourceReportSchemaV4 :: String
sdkSourceReportSchemaV4 =
  "myframework-sdk-source-report.v4"

sdkLoweringSemanticsDigest :: Digest
sdkLoweringSemanticsDigest =
  Digest
    ( sha256
        "myframework-sdk-lowering-semantics.l0-v5.2-program.v4"
    )

mkSdkSourceInput ::
  TrustBaseRef ->
  String ->
  ReferencedProgram ->
  Maybe SdkHandlerCoverage ->
  SdkSourceInput
mkSdkSourceInput currentCore currentVersion currentProgram currentCoverage =
  mkSdkSourceInputProgram
    currentCore
    currentVersion
    (SdkLegacyProgram currentProgram)
    currentCoverage

mkSdkSourceInputV52 ::
  TrustBaseRef ->
  String ->
  V52.PreparedRuntime ->
  Maybe SdkHandlerCoverage ->
  SdkSourceInput
mkSdkSourceInputV52 currentCore currentVersion currentProgram currentCoverage =
  mkSdkSourceInputProgram
    currentCore
    currentVersion
    (SdkV52Program currentProgram)
    currentCoverage

mkSdkSourceInputProgram ::
  TrustBaseRef ->
  String ->
  SdkSourceProgram ->
  Maybe SdkHandlerCoverage ->
  SdkSourceInput
mkSdkSourceInputProgram currentCore currentVersion currentProgram currentCoverage =
  provisionalInput
    { sdkSourceCoreLock =
        SdkCoreLock
          { sdkCoreRef = currentCore
          , sdkSurfaceDigest =
              Digest
                (sha256 (renderSdkSurfaceCommitment provisionalInput))
          , sdkLoweringDigest = sdkLoweringSemanticsDigest
          }
    }
  where
    provisionalInput =
      SdkSourceInput
        { sdkSourceSdkVersion = currentVersion
        , sdkSourceCoreLock =
            SdkCoreLock
              currentCore
              (Digest (replicate 64 '0'))
              sdkLoweringSemanticsDigest
        , sdkSourceProgram = currentProgram
        , sdkSourceHandlerCoverage = currentCoverage
        }

handlerCoverageFromRefs ::
  [EffectAddress] ->
  [ReadKey] ->
  SdkHandlerCoverage
handlerCoverageFromRefs currentEffects currentReads =
  SdkLegacyHandlerCoverage
    (uniqueSorted currentEffects)
    (uniqueSorted currentReads)

handlerCoverageFromEffectKeys ::
  [V52.EffectKey] ->
  [V52.EffectKey] ->
  SdkHandlerCoverage
handlerCoverageFromEffectKeys currentEffects currentReads =
  SdkV52HandlerCoverage
    (uniqueSorted currentEffects)
    (uniqueSorted currentReads)

canonicalizeSdkSourceInput :: SdkSourceInput -> SdkSourceInput
canonicalizeSdkSourceInput currentInput =
  currentInput
    { sdkSourceProgram =
        canonicalizeProgram (sdkSourceProgram currentInput)
    , sdkSourceHandlerCoverage =
        fmap canonicalizeCoverage (sdkSourceHandlerCoverage currentInput)
    }

canonicalizeCoverage :: SdkHandlerCoverage -> SdkHandlerCoverage
canonicalizeCoverage currentCoverage =
  case currentCoverage of
    SdkLegacyHandlerCoverage currentEffects currentReads ->
      handlerCoverageFromRefs currentEffects currentReads
    SdkV52HandlerCoverage currentEffects currentReads ->
      handlerCoverageFromEffectKeys currentEffects currentReads

canonicalizeProgram :: SdkSourceProgram -> SdkSourceProgram
canonicalizeProgram currentProgram =
  case currentProgram of
    SdkLegacyProgram currentLegacy ->
      SdkLegacyProgram (canonicalizeReferencedProgram currentLegacy)
    SdkV52Program currentV52 -> SdkV52Program currentV52

canonicalizeReferencedProgram :: ReferencedProgram -> ReferencedProgram
canonicalizeReferencedProgram currentProgram =
  currentProgram
    { referencedProgramControls =
        sortOn controlDeclModule
          (referencedProgramControls currentProgram)
    , referencedProgramEffects =
        sortOn effectModuleName
          ( map
              canonicalizeEffectModule
              (referencedProgramEffects currentProgram)
          )
    , referencedProgramReads =
        ReadRegistry
          ( sort
              ( readRegistryFields
                  (referencedProgramReads currentProgram)
              )
          )
    }

canonicalizeEffectModule :: EffectModule -> EffectModule
canonicalizeEffectModule currentModule =
  currentModule
    { effectModuleRecord =
        EffectRecord
          ( sortOn fst
              [ (currentKey, canonicalizeEffect currentEffect)
              | (currentKey, currentEffect) <-
                  effectRecordFields (effectModuleRecord currentModule)
              ]
          )
    }

canonicalizeEffect :: EffectDecl -> EffectDecl
canonicalizeEffect currentEffect =
  currentEffect
    { effectDeclParams =
        canonicalizeParams (effectDeclParams currentEffect)
    }

canonicalizeParams ::
  [(ParamKey, ParamBinding)] ->
  [(ParamKey, ParamBinding)]
canonicalizeParams currentParams =
  sortOn fst
    [ ( currentKey
      , currentBinding
          { paramBindingSource =
              case paramBindingSource currentBinding of
                ParamFromRecord currentChildren ->
                  ParamFromRecord (canonicalizeParams currentChildren)
                currentSource ->
                  currentSource
          }
      )
    | (currentKey, currentBinding) <- currentParams
    ]

buildSdkSourceReport :: SdkSourceInput -> SdkSourceReport
buildSdkSourceReport originalInput =
  SdkSourceReport
    { sdkSourceReportSchema = sdkSourceReportSchemaV4
    , sdkSourceReportInput = canonicalInput
    , sdkSourceReportArtifact = sourceArtifactFrom canonicalInput
    , sdkSourceReportIssues = sourceIssues canonicalInput
    }
  where
    canonicalInput =
      canonicalizeSdkSourceInput originalInput

sdkSourceReportReady :: SdkSourceReport -> Bool
sdkSourceReportReady currentReport =
  sdkSourceReportCanonical currentReport
    && not
      ( any
          ((== SdkSourceBlocker) . sdkSourceIssueSeverity)
          (sdkSourceReportIssues currentReport)
      )

sdkSourceReportCanonical :: SdkSourceReport -> Bool
sdkSourceReportCanonical currentReport =
  sdkSourceReportSchema currentReport == sdkSourceReportSchemaV4
    && currentInput == canonicalizeSdkSourceInput currentInput
    && currentArtifact == sourceArtifactFrom currentInput
    && currentIssues == sourceIssues currentInput
    && currentIssues == uniqueSorted currentIssues
  where
    currentInput =
      sdkSourceReportInput currentReport
    currentArtifact =
      sdkSourceReportArtifact currentReport
    currentIssues =
      sdkSourceReportIssues currentReport

sdkSourceCanonicalizesReferencedProgram ::
  SdkSourceInput ->
  SdkSourceReport ->
  Bool
sdkSourceCanonicalizesReferencedProgram originalInput currentReport =
  sdkSourceReportInput currentReport
    == canonicalizeSdkSourceInput originalInput
    && currentReport == buildSdkSourceReport originalInput

renderSdkSourceArtifactJson :: SdkSourceArtifact -> String
renderSdkSourceArtifactJson currentArtifact =
  jsonObject
    [ jsonField
        "schema"
        (jsonString (sdkSourceArtifactSchema currentArtifact))
    , jsonField
        "sdkVersion"
        (jsonString (sdkSourceArtifactSdkVersion currentArtifact))
    , jsonField
        "coreLock"
        (renderSdkCoreLockJson (sdkSourceArtifactCoreLock currentArtifact))
    , jsonField
        "program"
        (renderSdkProgramJson (sdkSourceArtifactProgram currentArtifact))
    , jsonField
        "handlerCoverage"
        ( jsonMaybe
            renderHandlerCoverageJson
            (sdkSourceArtifactHandlerCoverage currentArtifact)
        )
    ]

renderSdkSourceReportJson :: SdkSourceReport -> String
renderSdkSourceReportJson currentReport =
  jsonObject
    [ jsonField
        "schema"
        (jsonString (sdkSourceReportSchema currentReport))
    , jsonField
        "status"
        (jsonString (if sdkSourceReportReady currentReport then "ready" else "blocked"))
    , jsonField
        "artifact"
        (renderSdkSourceArtifactJson (sdkSourceReportArtifact currentReport))
    , jsonField
        "issues"
        (jsonArray (map renderSourceIssueJson (sdkSourceReportIssues currentReport)))
    ]

renderGeneratedSdkSource :: SdkSourceInput -> SdkGeneratedSource
renderGeneratedSdkSource currentInput =
  SdkGeneratedSource
    { sdkGeneratedSourcePath =
        "src/MyFramework/Generated/SourceArtifact.hs"
    , sdkGeneratedSourceLines =
        [ "module MyFramework.Generated.SourceArtifact"
        , "  ( sdkSourceArtifactJson"
        , "  , sdkSourceReportJson"
        , "  ) where"
        , ""
        , "sdkSourceArtifactJson :: String"
        , "sdkSourceArtifactJson ="
        , "  " ++ show artifactJson
        , ""
        , "sdkSourceReportJson :: String"
        , "sdkSourceReportJson ="
        , "  " ++ show reportJson
        ]
    }
  where
    currentReport =
      buildSdkSourceReport currentInput
    artifactJson =
      renderSdkSourceArtifactJson (sdkSourceReportArtifact currentReport)
    reportJson =
      renderSdkSourceReportJson currentReport

sourceArtifactFrom :: SdkSourceInput -> SdkSourceArtifact
sourceArtifactFrom currentInput =
  SdkSourceArtifact
    { sdkSourceArtifactSchema = sdkSourceArtifactSchemaV4
    , sdkSourceArtifactSdkVersion = sdkSourceSdkVersion currentInput
    , sdkSourceArtifactCoreLock = sdkSourceCoreLock currentInput
    , sdkSourceArtifactProgram = sdkSourceProgram currentInput
    , sdkSourceArtifactHandlerCoverage =
        sdkSourceHandlerCoverage currentInput
    }

sourceIssues :: SdkSourceInput -> [SdkSourceIssue]
sourceIssues currentInput =
  uniqueSorted
    ( versionIssues
        ++ programIssues
        ++ coreLockIssues
        ++ coverageIssues
    )
  where
    versionIssues =
      [ sourceIssue
          SdkSourceBlocker
          EmptySdkSourceVersion
          "sdkVersion"
          "the generated artifact must identify its SDK semantic version"
      | null (sdkSourceSdkVersion currentInput)
      ]
    currentProgram =
      sdkSourceProgram currentInput
    currentProgramErrors =
      case currentProgram of
        SdkLegacyProgram currentLegacy -> map show (validateReferencedProgram currentLegacy)
        SdkV52Program currentV52 -> map show (V52.validate currentV52)
    programIssues =
      [ sourceIssue
          SdkSourceBlocker
          InvalidReferencedProgram
          "program"
          (show currentProgramErrors)
      | not (null currentProgramErrors)
      ]
    currentCoreLock =
      sdkSourceCoreLock currentInput
    expectedSurfaceDigest =
      Digest (sha256 (renderSdkSurfaceCommitment currentInput))
    coreLockIssues =
      [ sourceIssue
          SdkSourceBlocker
          InvalidSdkCoreLock
          "coreLock"
          (show currentViolations)
      | let currentViolations =
              validateSdkCoreLock currentCoreLock
      , not (null currentViolations)
      ]
        ++ [ sourceIssue
               SdkSourceBlocker
               SdkSurfaceDigestMismatch
               "coreLock.surfaceDigest"
               ( "expected "
                   ++ show expectedSurfaceDigest
                   ++ "; observed "
                   ++ show (sdkSurfaceDigest currentCoreLock)
               )
           | sdkSurfaceDigest currentCoreLock
               /= expectedSurfaceDigest
           ]
        ++ [ sourceIssue
               SdkSourceBlocker
               SdkLoweringDigestMismatch
               "coreLock.loweringDigest"
               ( "expected "
                   ++ show sdkLoweringSemanticsDigest
                   ++ "; observed "
                   ++ show (sdkLoweringDigest currentCoreLock)
               )
           | sdkLoweringDigest currentCoreLock
               /= sdkLoweringSemanticsDigest
           ]
    coverageIssues =
      case sdkSourceHandlerCoverage currentInput of
        Nothing ->
          []
        Just currentCoverage ->
          invalidCoverageIssues currentCoverage
            ++ unknownCoverageIssues currentCoverage
    invalidCoverageIssues currentCoverage =
      case currentCoverage of
        SdkLegacyHandlerCoverage currentEffects currentReads ->
          [ sourceIssue SdkSourceWarning EmptyHandlerCoverageIdentity "effect" (show currentAddress)
          | currentAddress <- currentEffects
          , not (validEffectAddress currentAddress)
          ]
            ++ [ sourceIssue SdkSourceWarning EmptyHandlerCoverageIdentity "read" (show currentRead)
               | currentRead <- currentReads
               , null (readKeyText currentRead)
               ]
        SdkV52HandlerCoverage currentEffects currentReads ->
          [ sourceIssue SdkSourceWarning EmptyHandlerCoverageIdentity "effect" (show currentKey)
          | currentKey <- currentEffects
          , null (V52.effectKeyText currentKey)
          ]
            ++ [ sourceIssue SdkSourceWarning EmptyHandlerCoverageIdentity "read" (show currentKey)
               | currentKey <- currentReads
               , null (V52.effectKeyText currentKey)
               ]
    unknownCoverageIssues currentCoverage =
      case (currentProgram, currentCoverage) of
        (SdkLegacyProgram currentLegacy, SdkLegacyHandlerCoverage currentEffects currentReads) ->
          let declaredEffects =
                Set.fromList
                  [ EffectAddress (effectModuleName currentModule) currentKey
                  | currentModule <- referencedProgramEffects currentLegacy
                  , (currentKey, _) <- effectRecordFields (effectModuleRecord currentModule)
                  ]
              declaredReads =
                Set.fromList (map fst (readRegistryFields (referencedProgramReads currentLegacy)))
           in [ sourceIssue SdkSourceWarning UnknownEffectCoverageIdentity "effect" (show currentAddress)
              | currentAddress <- currentEffects
              , Set.notMember currentAddress declaredEffects
              ]
                ++ [ sourceIssue SdkSourceWarning UnknownReadCoverageIdentity "read" (show currentRead)
                   | currentRead <- currentReads
                   , Set.notMember currentRead declaredReads
                   ]
        (SdkV52Program currentV52, SdkV52HandlerCoverage currentEffects currentReads) ->
          let currentRegistry = V52.effectRegistryEffects (V52.effectRegistryOf currentV52)
              declaredEffects =
                Set.fromList (map (V52.someEffectRefKey . V52.effectIrRef) currentRegistry)
              declaredReads =
                Set.fromList
                  [ V52.someEffectRefKey (V52.effectIrRef currentEffect)
                  | currentEffect <- currentRegistry
                  , V52.someEffectRefKind (V52.effectIrRef currentEffect) == V52.R
                  ]
           in [ sourceIssue SdkSourceWarning UnknownEffectCoverageIdentity "effect" (show currentKey)
              | currentKey <- currentEffects
              , Set.notMember currentKey declaredEffects
              ]
                ++ [ sourceIssue SdkSourceWarning UnknownReadCoverageIdentity "read" (show currentKey)
                   | currentKey <- currentReads
                   , Set.notMember currentKey declaredReads
                   ]
        _ ->
          [ sourceIssue
              SdkSourceBlocker
              UnknownEffectCoverageIdentity
              "handlerCoverage"
              "coverage epoch does not match program epoch"
          ]

validEffectAddress :: EffectAddress -> Bool
validEffectAddress currentAddress =
  not
    ( null
        (moduleNameText (effectAddressModule currentAddress))
    )
    && not (null (localKeyText (effectAddressKey currentAddress)))

sourceIssue ::
  SdkSourceIssueSeverity ->
  SdkSourceIssueCode ->
  String ->
  String ->
  SdkSourceIssue
sourceIssue currentSeverity currentCode currentSubject currentDetail =
  SdkSourceIssue
    { sdkSourceIssueCode = currentCode
    , sdkSourceIssueSeverity = currentSeverity
    , sdkSourceIssueSubject = currentSubject
    , sdkSourceIssueDetail = currentDetail
    }

renderSdkSurfaceCommitment :: SdkSourceInput -> String
renderSdkSurfaceCommitment currentInput =
  intercalate
    "\n"
    [ sdkSourceSdkVersion canonicalInput
    , show (sdkSourceProgram canonicalInput)
    , show (sdkSourceHandlerCoverage canonicalInput)
    ]
  where
    canonicalInput =
      canonicalizeSdkSourceInput currentInput

renderSdkCoreLockJson :: SdkCoreLock -> String
renderSdkCoreLockJson currentLock =
  jsonObject
    [ jsonField "encoding" (jsonString "SdkCoreLock.v1")
    , jsonField
        "value"
        (jsonString (encodeSdkCoreLock currentLock))
    ]

renderSdkProgramJson :: SdkSourceProgram -> String
renderSdkProgramJson currentProgram =
  case currentProgram of
    SdkLegacyProgram currentLegacy ->
      jsonObject
        [ jsonField "encoding" (jsonString "ReferencedProgram.ReadShow.v1")
        , jsonField "declaration" (jsonString (show currentLegacy))
        ]
    SdkV52Program currentV52 ->
      jsonObject
        [ jsonField "encoding" (jsonString "PreparedRuntime.v5.2.ReadShow.v1")
        , jsonField "declaration" (jsonString (show currentV52))
        , jsonField "schemaDigest" (jsonString (V52.programSchemaDigest currentV52))
        ]

renderHandlerCoverageJson :: SdkHandlerCoverage -> String
renderHandlerCoverageJson currentCoverage =
  case currentCoverage of
    SdkLegacyHandlerCoverage currentEffects currentReads ->
      jsonObject
        [ jsonField "kind" (jsonString "module-local")
        , jsonField "effects" (jsonArray (map (jsonString . show) currentEffects))
        , jsonField "reads" (jsonArray (map (jsonString . show) currentReads))
        ]
    SdkV52HandlerCoverage currentEffects currentReads ->
      jsonObject
        [ jsonField "kind" (jsonString "effect-key.v5.2")
        , jsonField "effects" (jsonArray (map (jsonString . show) currentEffects))
        , jsonField "reads" (jsonArray (map (jsonString . show) currentReads))
        ]

renderSourceIssueJson :: SdkSourceIssue -> String
renderSourceIssueJson currentIssue =
  jsonObject
    [ jsonField
        "code"
        (jsonString (renderSourceIssueCode (sdkSourceIssueCode currentIssue)))
    , jsonField
        "severity"
        ( jsonString
            (renderSourceIssueSeverity (sdkSourceIssueSeverity currentIssue))
        )
    , jsonField
        "subject"
        (jsonString (sdkSourceIssueSubject currentIssue))
    , jsonField
        "detail"
        (jsonString (sdkSourceIssueDetail currentIssue))
    ]

renderSourceIssueCode :: SdkSourceIssueCode -> String
renderSourceIssueCode currentCode =
  case currentCode of
    InvalidSdkCoreLock ->
      "invalid-sdk-core-lock"
    SdkSurfaceDigestMismatch ->
      "sdk-surface-digest-mismatch"
    SdkLoweringDigestMismatch ->
      "sdk-lowering-digest-mismatch"
    EmptySdkSourceVersion ->
      "empty-sdk-source-version"
    InvalidReferencedProgram ->
      "invalid-referenced-program"
    EmptyHandlerCoverageIdentity ->
      "empty-handler-coverage-identity"
    UnknownEffectCoverageIdentity ->
      "unknown-effect-coverage-identity"
    UnknownReadCoverageIdentity ->
      "unknown-read-coverage-identity"

renderSourceIssueSeverity :: SdkSourceIssueSeverity -> String
renderSourceIssueSeverity currentSeverity =
  case currentSeverity of
    SdkSourceWarning -> "warning"
    SdkSourceBlocker -> "blocker"

uniqueSorted :: Ord item => [item] -> [item]
uniqueSorted =
  Set.toAscList . Set.fromList

jsonObject :: [String] -> String
jsonObject fields =
  "{" ++ joinWith "," fields ++ "}"

jsonField :: String -> String -> String
jsonField currentName currentValue =
  jsonString currentName ++ ":" ++ currentValue

jsonArray :: [String] -> String
jsonArray values =
  "[" ++ joinWith "," values ++ "]"

jsonMaybe :: (value -> String) -> Maybe value -> String
jsonMaybe _ Nothing =
  "null"
jsonMaybe renderValue (Just currentValue) =
  renderValue currentValue

jsonString :: String -> String
jsonString currentValue =
  "\"" ++ concatMap jsonChar currentValue ++ "\""

jsonChar :: Char -> String
jsonChar currentChar =
  case currentChar of
    '"' -> "\\\""
    '\\' -> "\\\\"
    '\n' -> "\\n"
    '\r' -> "\\r"
    '\t' -> "\\t"
    '\b' -> "\\b"
    '\f' -> "\\f"
    _
      | ord currentChar < 32 ->
          unicodeEscape currentChar
      | otherwise ->
          [currentChar]

unicodeEscape :: Char -> String
unicodeEscape currentChar =
  "\\u"
    ++ replicate (4 - length currentDigits) '0'
    ++ currentDigits
  where
    currentDigits =
      showHex (ord currentChar) ""

joinWith :: String -> [String] -> String
joinWith _ [] =
  ""
joinWith _ [currentItem] =
  currentItem
joinWith currentSeparator (currentItem : remainingItems) =
  currentItem
    ++ currentSeparator
    ++ joinWith currentSeparator remainingItems
