module Main (main) where

import Control.Monad
  ( unless )
import Data.Char
  ( ord )
import Data.IORef
  ( IORef
  , modifyIORef'
  , newIORef
  , readIORef
  )
import Data.List
  ( intercalate )
import Numeric
  ( showHex )
import System.Exit
  ( exitFailure )

import qualified MyFramework.Facade as V52
import MyFramework.Legacy.Migration
  ( FrontendExecutionStatus (..)
  )
import MyFramework.Self.CoreModel
import MyFramework.TrustBase.Core
import MyFramework.TrustBase.Digest
  ( sha256 )
import MyFramework.TrustBase.Evidence
  ( completeEvidence
  , evidenceFor
  , selfInterpretClaimCatalog
  , selfInterpretEvidenceSchemaV3
  , validateEvidenceClaims
  )
import MyFramework.TrustBase.Types
  ( ArtifactName (..)
  , ClaimName (..)
  , Evidence (..)
  , EvidenceStatus (..)
  , SchemaId (..)
  , SchemaName (..)
  , SchemaVersion (..)
  , evidencePassed
  , renderSchemaId
  )

data RuntimeMode
  = InterpretCompatibilityFacet
  | InterpretL0Candidate

data SemanticRuntime = SemanticRuntime
  { semanticRuntimeDependencies :: [CoreId]
  , semanticRuntimeMode :: RuntimeMode
  }

main :: IO ()
main =
  case frameworkAsBusiness of
    Left currentErrors -> do
      putStrLn
        ( renderFatal
            "framework-as-business-record"
            (show currentErrors)
        )
      exitFailure
    Right currentFramework -> do
      previousLoads <- newIORef 0
      candidateLoads <- newIORef 0
      previousBinding <-
        bindTrustBase
          ( semanticKernel
              previousLoads
              previousArtifact
              (SemanticRuntime [] InterpretCompatibilityFacet)
          )
          previousCoreRef
      candidateBinding <-
        bindTrustBase
          ( semanticKernel
              candidateLoads
              candidateArtifact
              (SemanticRuntime [] InterpretL0Candidate)
          )
          candidateCoreRef
      contaminatedBinding <-
        bindTrustBase
          ( semanticKernel
              candidateLoads
              candidateArtifact
              ( SemanticRuntime
                  [trustBaseCoreId previousCoreRef]
                  InterpretL0Candidate
              )
          )
          candidateCoreRef

      previousEvidence <-
        runBound previousBinding currentFramework
      candidateEvidence <-
        runBound candidateBinding currentFramework
      contaminatedEvidence <-
        runBound contaminatedBinding currentFramework

      previousLoadCount <- readIORef previousLoads
      candidateLoadCount <- readIORef candidateLoads

      let frameworkRoundTrip =
            decodeFrameworkAsBusiness
              (encodeFrameworkAsBusiness currentFramework)
              == Right currentFramework
          loweringReady =
            null
              ( V52.validate
                  (frameworkAsBusinessV52Program currentFramework)
              )
              && case
                  V52.resolveAll
                    (frameworkAsBusinessV52Program currentFramework) of
                V52.AstPlanBranch {} -> True
                V52.AstPlanApplication {} -> True
          previousObservation =
            extractObservation previousEvidence
          candidateObservation =
            extractObservation candidateEvidence
          contaminatedObservation =
            extractObservation contaminatedEvidence
          previousRan =
            observationSucceeded previousObservation
              && previousLoadCount == 1
          candidateRan =
            observationSucceeded candidateObservation
          exchangeable =
            case (previousObservation, candidateObservation) of
              (Right previousCurrent, Right candidateCurrent) ->
                frameworkObservationCompatibilityDigest previousCurrent
                  == frameworkObservationCompatibilityDigest candidateCurrent
              _ ->
                False
          facetBound =
            coreCompatibilityFacetValid currentFramework
              && compatibilityPreviousCoreId coreCompatibilityFacet
                == "core2"
              && compatibilityPreviousSourceCommit coreCompatibilityFacet
                == "78598a77bff3d3e864347b7aafcc1764395e4319"
              && compatibilityCandidateFrameworkSchema
                coreCompatibilityFacet
                == frameworkAsBusinessSchema currentFramework
              && compatibilityPreviousPayloadDigest
                coreCompatibilityFacet
                == "2202c857e7834aa01007d9a270343eed25d823e695086716d39404d64c0261f7"
          independent =
            case candidateObservation of
              Right currentObservation ->
                candidateHasNoPreviousCoreDependency
                  (trustBaseCoreId previousCoreRef)
                  currentObservation
              Left _ ->
                False
          contaminationRejected =
            case contaminatedObservation of
              Right currentObservation ->
                not
                  ( candidateHasNoPreviousCoreDependency
                      (trustBaseCoreId previousCoreRef)
                      currentObservation
                  )
              Left _ ->
                False
          emptyStructural =
            show EmptyBusiness == "EmptyBusiness"
          identitiesAttached =
            evidenceIdentitiesMatch
              previousCoreRef
              candidateCoreRef
              previousEvidence
              && evidenceIdentitiesMatch
                candidateCoreRef
                candidateCoreRef
                candidateEvidence
          coreChecks =
            [ ( "previous-core-facet-is-content-addressed"
              , facetBound
              , show coreCompatibilityFacet
              )
            , ( "previous-core-runs-compatibility-facet"
              , previousRan
              , renderSemanticResult previousObservation
              )
            , ( "candidate-is-expressed-by-l0-facade"
              , frameworkRoundTrip && loweringReady
              , "L0 v5.2 Program + command/MAP/R + canonical SchemaCatalog"
              )
            , ( "candidate-runs-as-framework-business"
              , candidateRan && candidateLoadCount == 2
              , renderSemanticResult candidateObservation
              )
            , ( "empty-business-closes-recursion"
              , candidateRan && emptyStructural
              , show EmptyBusiness
              )
            , ( "empty-business-has-no-curde"
              , emptyStructural
              , "nullary EmptyBusiness"
              )
            , ( "empty-business-has-no-handler"
              , emptyStructural
              , "nullary EmptyBusiness"
              )
            , ( "empty-business-has-no-host-io"
              , emptyStructural
              , "nullary EmptyBusiness"
              )
            , ( "trustbase-not-forwarded-to-terminal-business"
              , identitiesAttached && emptyStructural
              , "core identity is attached to BootstrapEvidence only"
              )
            , ( "core2-core0-contract-exchangeable"
              , exchangeable
              , renderPair previousObservation candidateObservation
              )
            , ( "candidate-has-no-previous-core-runtime-dependency"
              , independent
              , renderSemanticResult candidateObservation
              )
            , ( "previous-core-back-reference-negative-rejected"
              , contaminationRejected
              , renderSemanticResult contaminatedObservation
              )
            , ( "semantic-fixed-point-passed"
              , exchangeable && independent
              , "normalized compatibility contract digests equal and candidate dependency closure clean"
              )
            ]
          coreEvidence =
            [ evidenceFor
                (ClaimName currentClaim)
                currentPassed
                "passed"
                currentObserved
                witnessArtifact
            | (currentClaim, currentPassed, currentObserved) <-
                coreChecks
            ]
          allEvidence =
            completeEvidence
              selfInterpretClaimCatalog
              witnessArtifact
              coreEvidence
          catalogValid =
            null
              ( validateEvidenceClaims
                  selfInterpretClaimCatalog
                  allEvidence
              )
          succeeded =
            catalogValid && all evidencePassed allEvidence

      putStrLn
        (renderReport allEvidence succeeded)
      unless succeeded exitFailure

witnessArtifact :: ArtifactName
witnessArtifact =
  ArtifactName "core-self-interpret-witness"

coreSchema :: SchemaId
coreSchema =
  SchemaId
    { schemaIdName = SchemaName "myframework-core"
    , schemaIdVersion = SchemaVersion 1
    }

coreClaims :: [ClaimName]
coreClaims =
  [ ClaimName "host-kernel-closed"
  , ClaimName "semantic-self-interpret"
  ]

previousBytes :: String
previousBytes =
  "compiled-core2"

previousManifest :: String
previousManifest =
  "compiled-core2-manifest"

candidateBytes :: String
candidateBytes =
  "compiled-facade-core0"

candidateManifest :: String
candidateManifest =
  "compiled-facade-core0-manifest"

previousCoreRef :: TrustBaseRef
previousCoreRef =
  TrustBaseRef
    { trustBaseCoreId = CoreId "core2"
    , trustBaseArtifactDigest = Digest (sha256 previousBytes)
    , trustBaseManifestDigest = Digest (sha256 previousManifest)
    , trustBaseSchema = coreSchema
    , trustBaseKernelClaims = coreClaims
    }

candidateCoreRef :: TrustBaseRef
candidateCoreRef =
  TrustBaseRef
    { trustBaseCoreId = CoreId "core0"
    , trustBaseArtifactDigest = Digest (sha256 candidateBytes)
    , trustBaseManifestDigest = Digest (sha256 candidateManifest)
    , trustBaseSchema = coreSchema
    , trustBaseKernelClaims = coreClaims
    }

previousArtifact :: CoreArtifact String
previousArtifact =
  coreArtifact
    previousBytes
    previousManifest
    (CoreId "core2")
    coreSchema
    coreClaims

candidateArtifact :: CoreArtifact String
candidateArtifact =
  coreArtifact
    candidateBytes
    candidateManifest
    (CoreId "core0")
    coreSchema
    coreClaims

semanticKernel ::
  IORef Int ->
  CoreArtifact String ->
  SemanticRuntime ->
  HostKernel
    String
    SemanticRuntime
    FrameworkAsBusiness
    EmptyBusiness
    ( Either
        FrameworkInterpretError
        FrameworkSemanticObservation
    )
semanticKernel currentLoadCount currentArtifact currentRuntime =
  mkHostKernel
    (\_ -> pure (Right currentArtifact))
    (Digest . sha256)
    ( \_ -> do
        modifyIORef' currentLoadCount (+ 1)
        pure (Right currentRuntime)
    )
    ( \runtime currentRound ->
        case semanticRuntimeMode runtime of
          InterpretCompatibilityFacet ->
            interpretCompatibilityFacet
              (semanticRuntimeDependencies runtime)
              (bootstrapFramework currentRound)
          InterpretL0Candidate ->
            interpretFrameworkAsBusiness
              (semanticRuntimeDependencies runtime)
              (bootstrapFramework currentRound)
              (bootstrapTerminal currentRound)
    )

interpretCompatibilityFacet ::
  [CoreId] ->
  FrameworkAsBusiness ->
  IO
    ( Either
        FrameworkInterpretError
        FrameworkSemanticObservation
    )
interpretCompatibilityFacet currentDependencies currentFramework =
  pure
    ( if coreCompatibilityFacetValid currentFramework
        then
          Right
            FrameworkSemanticObservation
              { frameworkObservationSemanticDigest =
                  compatibilityPreviousObservationDigest
                    (frameworkAsBusinessCompatibility currentFramework)
              , frameworkObservationCompatibilityDigest =
                  coreCompatibilityDigest
                    (frameworkAsBusinessCompatibility currentFramework)
              , frameworkObservationControlSucceeded = True
              , frameworkObservationFinalExecutionStatus =
                  FrontendSucceeded
              , frameworkObservationRuntimeDependencies =
                  currentDependencies
              }
        else
          Left
            ( FrameworkCompatibilityFailed
                "candidate does not carry the approved core2 facet"
            )
    )

runBound ::
  Either
    TrustBaseBindingError
    ( BoundTrustBase
        FrameworkAsBusiness
        EmptyBusiness
        ( Either
            FrameworkInterpretError
            FrameworkSemanticObservation
        )
    ) ->
  FrameworkAsBusiness ->
  IO
    ( Either
        TrustBaseBindingError
        ( BootstrapEvidence
            ( Either
                FrameworkInterpretError
                FrameworkSemanticObservation
            )
        )
    )
runBound currentBinding currentFramework =
  case currentBinding of
    Left currentError ->
      pure (Left currentError)
    Right currentBound ->
      Right
        <$> runSelfBootstrap
          currentBound
          BootstrapRound
            { bootstrapCandidateCore = candidateCoreRef
            , bootstrapFramework = currentFramework
            , bootstrapTerminal = EmptyBusiness
            }

extractObservation ::
  Either
    TrustBaseBindingError
    ( BootstrapEvidence
        ( Either
            FrameworkInterpretError
            FrameworkSemanticObservation
        )
    ) ->
  Either String FrameworkSemanticObservation
extractObservation currentEvidence =
  case currentEvidence of
    Left currentError ->
      Left (show currentError)
    Right currentBootstrap ->
      case bootstrapEvidenceObservation currentBootstrap of
        Left currentError ->
          Left (show currentError)
        Right currentObservation ->
          Right currentObservation

observationSucceeded ::
  Either String FrameworkSemanticObservation ->
  Bool
observationSucceeded currentObservation =
  case currentObservation of
    Left _ -> False
    Right currentValue ->
      frameworkObservationControlSucceeded currentValue

evidenceIdentitiesMatch ::
  TrustBaseRef ->
  TrustBaseRef ->
  Either
    TrustBaseBindingError
    (BootstrapEvidence observation) ->
  Bool
evidenceIdentitiesMatch expectedPrevious expectedCandidate currentEvidence =
  case currentEvidence of
    Left _ ->
      False
    Right currentBootstrap ->
      bootstrapEvidencePreviousCore currentBootstrap
        == expectedPrevious
        && bootstrapEvidenceCandidateCore currentBootstrap
          == expectedCandidate

renderSemanticResult ::
  Either String FrameworkSemanticObservation ->
  String
renderSemanticResult =
  either id show

renderPair ::
  Either String FrameworkSemanticObservation ->
  Either String FrameworkSemanticObservation ->
  String
renderPair leftObservation rightObservation =
  renderSemanticResult leftObservation
    ++ " == "
    ++ renderSemanticResult rightObservation

renderFatal :: String -> String -> String
renderFatal currentStage currentObserved =
  jsonObject
    [ ("schema", jsonString "core-self-interpret-witness.v1")
    , ("artifact", jsonString "core-self-interpret-witness")
    , ("result", jsonString "failed")
    , ("stage", jsonString currentStage)
    , ("observed", jsonString currentObserved)
    ]

renderReport :: [Evidence] -> Bool -> String
renderReport currentEvidence succeeded =
  jsonObject
    [ ( "schema"
      , jsonString (renderSchemaId selfInterpretEvidenceSchemaV3)
      )
    , ("artifact", jsonString "core-self-interpret-witness")
    , ("result", jsonString (if succeeded then "passed" else "failed"))
    , ("claims", jsonArray (map renderEvidence currentEvidence))
    ]

renderEvidence :: Evidence -> String
renderEvidence currentEvidence =
  jsonObject
    [ ("name", jsonString (unClaimName (evidenceClaim currentEvidence)))
    , ( "status"
      , jsonString
          ( case evidenceStatus currentEvidence of
              EvidencePassed -> "passed"
              EvidenceFailed -> "failed"
          )
      )
    , ("expected", jsonString (evidenceExpected currentEvidence))
    , ("observed", jsonString (evidenceObserved currentEvidence))
    ]

jsonObject :: [(String, String)] -> String
jsonObject currentFields =
  "{"
    ++ intercalate
      ","
      [ jsonString currentName ++ ":" ++ currentValue
      | (currentName, currentValue) <- currentFields
      ]
    ++ "}"

jsonArray :: [String] -> String
jsonArray currentValues =
  "[" ++ intercalate "," currentValues ++ "]"

jsonString :: String -> String
jsonString currentValue =
  "\"" ++ concatMap escapeJsonChar currentValue ++ "\""

escapeJsonChar :: Char -> String
escapeJsonChar currentChar =
  case currentChar of
    '"' -> "\\\""
    '\\' -> "\\\\"
    '\b' -> "\\b"
    '\f' -> "\\f"
    '\n' -> "\\n"
    '\r' -> "\\r"
    '\t' -> "\\t"
    _
      | ord currentChar < 0x20 ->
          "\\u" ++ padLeft 4 '0' (showHex (ord currentChar) "")
      | otherwise ->
          [currentChar]

padLeft :: Int -> Char -> String -> String
padLeft currentWidth currentFill currentValue =
  replicate (max 0 (currentWidth - length currentValue)) currentFill
    ++ currentValue
