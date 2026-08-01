module MyFramework.TrustBase.Evidence
  ( ClaimCatalog (..)
  , ClaimCatalogViolation (..)
  , claimCatalogClaims
  , claimManifestEvidence
  , completeEvidence
  , crawlerFacadeClaimCatalog
  , crawlerFacadeEvidenceSchemaV2
  , evidenceFor
  , effectApplicationClaimCatalog
  , effectApplicationEvidenceSchemaV1
  , effSysRefClaimCatalog
  , effSysRefEvidenceSchemaV1
  , fixedPointDiffClaimCatalog
  , fixedPointDiffEvidenceSchemaV1
  , facadeV52ClaimCatalog
  , facadeV52EvidenceSchemaV1
  , inputCpsClaimCatalog
  , inputCpsEvidenceSchemaV1
  , hangingMiddlewareClaimCatalog
  , hangingMiddlewareEvidenceSchemaV1
  , pipelinePatchClaimCatalog
  , pipelinePatchEvidenceSchemaV1
  , promotionClaimCatalog
  , promotionEvidenceSchemaV1
  , l0SemanticsClaimCatalog
  , l0SemanticsEvidenceSchemaV3
  , referencedFrontendClaimCatalog
  , referencedFrontendEvidenceSchemaV1
  , referencedRuntimeClaimCatalog
  , referencedRuntimeEvidenceSchemaV1
  , sdkPackageClaimCatalog
  , sdkPackageEvidenceSchemaV1
  , schemaCatalogClaimCatalog
  , schemaCatalogClaimName
  , schemaCatalogEvidenceSchemaV1
  , schemaElaborationClaimCatalog
  , schemaElaborationEvidenceSchemaV1
  , selfInterpretClaimCatalog
  , selfInterpretEvidenceSchemaV3
  , trustBaseManifestClaimCatalog
  , trustBaseManifestEvidenceSchemaV1
  , trustBaseBindingClaimCatalog
  , trustBaseBindingEvidenceSchemaV1
  , validateEvidenceClaims
  ) where

import Data.List
  ( group
  , sort
  )

import MyFramework.TrustBase.FixedPoint
  ( fixedPointDiffClaimName
  , fixedPointDiffKeys
  )
import MyFramework.TrustBase.Manifest
  ( SchemaCatalogEntry (..)
  )
import MyFramework.TrustBase.Types
  ( ArtifactName (..)
  , ClaimName (..)
  , Evidence (..)
  , EvidenceStatus (..)
  , SchemaId (..)
  , SchemaName (..)
  , SchemaVersion (..)
  , renderSchemaId
  )

data ClaimCatalog = ClaimCatalog
  { claimCatalogName :: String
  , claimCatalogCoreClaims :: [ClaimName]
  , claimCatalogManifestClaim :: ClaimName
  }
  deriving (Eq, Show)

data ClaimCatalogViolation
  = DuplicateCatalogClaims [ClaimName]
  | EvidenceClaimOrderMismatch [ClaimName] [ClaimName]
  deriving (Eq, Show)

trustBaseManifestEvidenceSchemaV1 :: SchemaId
trustBaseManifestEvidenceSchemaV1 =
  SchemaId
    { schemaIdName = SchemaName "trust-base-manifest-evidence"
    , schemaIdVersion = SchemaVersion 1
    }

schemaCatalogEvidenceSchemaV1 :: SchemaId
schemaCatalogEvidenceSchemaV1 =
  SchemaId
    { schemaIdName = SchemaName "schema-catalog-evidence"
    , schemaIdVersion = SchemaVersion 1
    }

fixedPointDiffEvidenceSchemaV1 :: SchemaId
fixedPointDiffEvidenceSchemaV1 =
  SchemaId
    { schemaIdName = SchemaName "fixed-point-diff-evidence"
    , schemaIdVersion = SchemaVersion 1
    }

trustBaseBindingEvidenceSchemaV1 :: SchemaId
trustBaseBindingEvidenceSchemaV1 =
  SchemaId
    { schemaIdName = SchemaName "trustbase-binding-evidence"
    , schemaIdVersion = SchemaVersion 1
    }

promotionEvidenceSchemaV1 :: SchemaId
promotionEvidenceSchemaV1 =
  SchemaId
    { schemaIdName = SchemaName "core-promotion-evidence"
    , schemaIdVersion = SchemaVersion 1
    }

selfInterpretEvidenceSchemaV3 :: SchemaId
selfInterpretEvidenceSchemaV3 =
  SchemaId
    { schemaIdName = SchemaName "core-self-interpret-evidence"
    , schemaIdVersion = SchemaVersion 3
    }

sdkPackageEvidenceSchemaV1 :: SchemaId
sdkPackageEvidenceSchemaV1 =
  SchemaId
    { schemaIdName = SchemaName "sdk-package-evidence"
    , schemaIdVersion = SchemaVersion 1
    }

l0SemanticsEvidenceSchemaV3 :: SchemaId
l0SemanticsEvidenceSchemaV3 =
  SchemaId
    { schemaIdName = SchemaName "curde-semantics-report"
    , schemaIdVersion = SchemaVersion 3
    }

referencedFrontendEvidenceSchemaV1 :: SchemaId
referencedFrontendEvidenceSchemaV1 =
  SchemaId
    { schemaIdName = SchemaName "referenced-frontend-witness"
    , schemaIdVersion = SchemaVersion 1
    }

referencedRuntimeEvidenceSchemaV1 :: SchemaId
referencedRuntimeEvidenceSchemaV1 =
  SchemaId
    { schemaIdName = SchemaName "referenced-runtime-witness"
    , schemaIdVersion = SchemaVersion 1
    }

crawlerFacadeEvidenceSchemaV2 :: SchemaId
crawlerFacadeEvidenceSchemaV2 =
  SchemaId
    { schemaIdName = SchemaName "crawler-facade-witness"
    , schemaIdVersion = SchemaVersion 2
    }

effectApplicationEvidenceSchemaV1 :: SchemaId
effectApplicationEvidenceSchemaV1 =
  SchemaId
    { schemaIdName = SchemaName "effect-application-witness"
    , schemaIdVersion = SchemaVersion 1
    }

facadeV52EvidenceSchemaV1 :: SchemaId
facadeV52EvidenceSchemaV1 =
  SchemaId
    { schemaIdName = SchemaName "facade-v52-witness"
    , schemaIdVersion = SchemaVersion 1
    }

inputCpsEvidenceSchemaV1 :: SchemaId
inputCpsEvidenceSchemaV1 =
  SchemaId
    { schemaIdName = SchemaName "input-cps-witness"
    , schemaIdVersion = SchemaVersion 1
    }

effSysRefEvidenceSchemaV1 :: SchemaId
effSysRefEvidenceSchemaV1 =
  SchemaId
    { schemaIdName = SchemaName "effsys-ref-witness"
    , schemaIdVersion = SchemaVersion 1
    }

hangingMiddlewareEvidenceSchemaV1 :: SchemaId
hangingMiddlewareEvidenceSchemaV1 =
  SchemaId
    { schemaIdName = SchemaName "hanging-middleware-witness"
    , schemaIdVersion = SchemaVersion 1
    }

pipelinePatchEvidenceSchemaV1 :: SchemaId
pipelinePatchEvidenceSchemaV1 =
  SchemaId
    { schemaIdName = SchemaName "pipeline-patch-witness"
    , schemaIdVersion = SchemaVersion 1
    }

schemaElaborationEvidenceSchemaV1 :: SchemaId
schemaElaborationEvidenceSchemaV1 =
  SchemaId
    { schemaIdName = SchemaName "schema-elaboration-witness"
    , schemaIdVersion = SchemaVersion 1
    }

-- | This catalog retains the stable names for the pure manifest invariants.
-- Operational artifact, executable, gate-command, and publication claims are
-- deliberately outside the minimal TrustBase.
trustBaseManifestClaimCatalog :: ClaimCatalog
trustBaseManifestClaimCatalog =
  ClaimCatalog
    { claimCatalogName = "trust-base-manifest"
    , claimCatalogCoreClaims =
        map
          ClaimName
          [ "trust-base-manifest-schema-version"
          , "trust-base-kernel-modules-exposed"
          , "trust-base-facade-modules-exposed"
          , "trust-base-core-surface-covered"
          , "trust-base-json-schemas-synced"
          , "trust-base-evidence-claims-synced"
          ]
    , claimCatalogManifestClaim =
        ClaimName "trust-base-manifest-claim-manifest"
    }

fixedPointDiffClaimCatalog :: ClaimCatalog
fixedPointDiffClaimCatalog =
  ClaimCatalog
    { claimCatalogName = "fixed-point-diff"
    , claimCatalogCoreClaims =
        map fixedPointDiffClaimName fixedPointDiffKeys
    , claimCatalogManifestClaim =
        ClaimName "fixed-point-diff-claim-manifest"
    }

trustBaseBindingClaimCatalog :: ClaimCatalog
trustBaseBindingClaimCatalog =
  ClaimCatalog
    { claimCatalogName = "trustbase-binding"
    , claimCatalogCoreClaims =
        map
          ClaimName
          [ "trustbase-ref-is-serializable"
          , "trustbase-binding-is-explicit"
          , "trustbase-artifact-digest-mismatch-rejected"
          , "trustbase-manifest-digest-mismatch-rejected"
          , "trustbase-core-id-mismatch-rejected"
          , "trustbase-schema-mismatch-rejected"
          , "trustbase-mismatch-precedes-runtime-load"
          , "bound-trustbase-runs-bootstrap-round"
          , "sdk-core-lock-is-explicit-and-serializable"
          ]
    , claimCatalogManifestClaim =
        ClaimName "trustbase-binding-claim-manifest"
    }

l0SemanticsClaimCatalog :: ClaimCatalog
l0SemanticsClaimCatalog =
  ClaimCatalog
    { claimCatalogName = "l0-semantics"
    , claimCatalogCoreClaims =
        map
          ClaimName
          [ "l0-referenced-program-valid"
          , "l0-referenced-program-resolves"
          , "l0-module-local-effect-records"
          , "l0-r-is-separate"
          , "l0-effect-kinds-cude-without-r"
          , "l0-self-model-text-roundtrip"
          , "l0-self-model-json-roundtrip"
          , "l0-resolver-control-trace"
          ]
    , claimCatalogManifestClaim =
        ClaimName "l0-semantics-claim-manifest"
    }

referencedFrontendClaimCatalog :: ClaimCatalog
referencedFrontendClaimCatalog =
  ClaimCatalog
    { claimCatalogName = "referenced-frontend"
    , claimCatalogCoreClaims =
        map
          ClaimName
          [ "referenced-frontend-valid"
          , "root-view-resolves-direct-references-only"
          , "nested-module-views-resolve-on-demand"
          , "effect-occurrence-path-preserves-reference-hierarchy"
          , "referenced-program-serializable-roundtrip"
          , "effect-keys-are-module-local"
          , "module-effect-key-ambiguity-rejected"
          , "missing-child-reference-rejected"
          , "control-reference-cycle-rejected"
          , "cross-module-or-missing-input-rejected"
          , "read-parameter-schema-mismatch-rejected"
          , "duplicate-local-effect-key-rejected"
          , "action-kind-is-cude-without-r"
          ]
    , claimCatalogManifestClaim =
        ClaimName "referenced-frontend-claim-manifest"
    }

crawlerFacadeClaimCatalog :: ClaimCatalog
crawlerFacadeClaimCatalog =
  ClaimCatalog
    { claimCatalogName = "crawler-facade"
    , claimCatalogCoreClaims =
        map
          ClaimName
          [ "crawler-facade-import-myframework-only"
          , "crawler-facade-schema-free-program-valid"
          , "crawler-facade-chain-fallback-parallel"
          , "crawler-facade-six-effect-registry"
          , "crawler-facade-command-map-r-applications"
          , "crawler-facade-canonical-schema-catalog"
          , "crawler-facade-occurrence-provenance"
          , "crawler-facade-qualified-effect-identity"
          ]
    , claimCatalogManifestClaim =
        ClaimName "crawler-facade-claim-manifest"
    }

schemaElaborationClaimCatalog :: ClaimCatalog
schemaElaborationClaimCatalog =
  ClaimCatalog
    { claimCatalogName = "schema-elaboration"
    , claimCatalogCoreClaims =
        map
          ClaimName
          [ "schema-elaboration-deterministic"
          , "schema-elaboration-generic-record"
          , "schema-elaboration-codec-roundtrip-equivalence"
          , "schema-elaboration-type-conflict-rejected"
          , "schema-elaboration-codec-conflict-rejected"
          , "schema-elaboration-imported-conflict-rejected"
          , "schema-elaboration-unresolved-rejected"
          , "schema-elaboration-cycle-rejected"
          , "schema-elaboration-codec-required"
          , "schema-elaboration-version-conflict-rejected"
          , "schema-elaboration-record-shape-rejected"
          , "schema-elaboration-nonserializable-boundary-rejected"
          , "schema-elaboration-legacy-behavior-preserved"
          , "schema-elaboration-no-handler-io"
          , "schema-elaboration-canonical-sha256"
          ]
    , claimCatalogManifestClaim =
        ClaimName "schema-elaboration-claim-manifest"
    }

effectApplicationClaimCatalog :: ClaimCatalog
effectApplicationClaimCatalog =
  ClaimCatalog
    { claimCatalogName = "effect-application"
    , claimCatalogCoreClaims =
        map
          ClaimName
          [ "effect-application-six-kinds-roundtrip"
          , "effect-application-roundtrip"
          , "effect-application-occurrences-independent"
          , "effect-application-ast-input-value-graphs-separated"
          , "effect-application-continuation-identity-stable"
          , "effect-application-ast-path-provenance"
          , "effect-application-map-missing-rejected"
          , "effect-application-output-mismatch-rejected"
          , "effect-application-illegal-r-reference-rejected"
          , "effect-application-input-cycle-rejected"
          , "effect-application-transform-registry-independent"
          , "effect-application-r-in-effect-registry"
          , "effect-application-state-projection-separated"
          , "effect-application-handler-param-order-preserved"
          , "effect-application-legacy-migration-deterministic"
          ]
    , claimCatalogManifestClaim =
        ClaimName "effect-application-claim-manifest"
    }

facadeV52ClaimCatalog :: ClaimCatalog
facadeV52ClaimCatalog =
  ClaimCatalog
    { claimCatalogName = "facade-v52"
    , claimCatalogCoreClaims =
        map
          ClaimName
          [ "facade-v52-program-pipeline-complete"
          , "facade-v52-missing-child-rejected"
          , "facade-v52-missing-input-rejected"
          , "facade-v52-unresolved-schema-rejected"
          , "facade-v52-handler-codec-conflict-rejected"
          , "facade-v52-map-alignment-rejected"
          , "facade-v52-handler-adapter-keeps-function-outside-ir"
          , "facade-v52-default-surface-has-no-legacy-schema-api"
          ]
    , claimCatalogManifestClaim =
        ClaimName "facade-v52-claim-manifest"
    }

inputCpsClaimCatalog :: ClaimCatalog
inputCpsClaimCatalog =
  ClaimCatalog
    { claimCatalogName = "input-cps"
    , claimCatalogCoreClaims =
        map
          ClaimName
          [ "input-cps-plan-defunctionalized-roundtrip"
          , "input-cps-continuation-carries-status-only"
          , "input-cps-success"
          , "input-cps-failure-short-circuit"
          , "input-cps-cancelled"
          , "input-cps-suspended"
          , "input-cps-runtime-order"
          , "input-cps-diagnosis-trace-matches-input-graph"
          , "input-cps-single-flight-same-occurrence"
          , "input-cps-occurrences-remain-independent"
          , "input-cps-business-values-use-value-phases"
          , "input-cps-typed-handler-adapter"
          , "input-cps-preparation-errors-before-handler-io"
          ]
    , claimCatalogManifestClaim =
        ClaimName "input-cps-claim-manifest"
    }

effSysRefClaimCatalog :: ClaimCatalog
effSysRefClaimCatalog =
  ClaimCatalog
    { claimCatalogName = "effsys-ref"
    , claimCatalogCoreClaims =
        map
          ClaimName
          [ "effsys-ref-ir-roundtrip"
          , "effsys-ref-scope-closure-three-graphs"
          , "effsys-ref-enters-value-graph"
          , "effsys-ref-parameter-does-not-add-demand"
          , "effsys-ref-snapshot-roundtrip"
          , "effsys-ref-view-and-snapshot-distinct"
          , "effsys-ref-query-ir-pipeline-state-observation-failure-stats"
          , "effsys-ref-query-does-not-start-handler"
          , "effsys-ref-cross-scope-rejected"
          , "effsys-ref-registry-mismatch-rejected"
          ]
    , claimCatalogManifestClaim = ClaimName "effsys-ref-claim-manifest"
    }

hangingMiddlewareClaimCatalog :: ClaimCatalog
hangingMiddlewareClaimCatalog =
  ClaimCatalog
    { claimCatalogName = "hanging-middleware"
    , claimCatalogCoreClaims =
        map
          ClaimName
          [ "hanging-middleware-hook-plan-roundtrip"
          , "hanging-middleware-no-boot-root"
          , "hanging-middleware-scope-and-declaration-order"
          , "hanging-middleware-success-failure-cancelled-observed"
          , "hanging-middleware-scoped-snapshot-and-stats"
          , "hanging-middleware-own-effect-occurrence"
          , "hanging-middleware-runtime-events-provenance"
          , "hanging-middleware-missing-registry-fails-before-handler-io"
          , "hanging-middleware-prestart-continuation-provenance"
          ]
    , claimCatalogManifestClaim =
        ClaimName "hanging-middleware-claim-manifest"
    }

pipelinePatchClaimCatalog :: ClaimCatalog
pipelinePatchClaimCatalog =
  ClaimCatalog
    { claimCatalogName = "pipeline-patch"
    , claimCatalogCoreClaims =
        map
          ClaimName
          [ "pipeline-patch-four-operations"
          , "pipeline-patch-positive-runtime-success"
          , "pipeline-patch-transactional-rollback"
          , "pipeline-patch-cycle-kind-and-lifecycle-errors"
          , "pipeline-patch-partial-submit-does-not-commit"
          , "pipeline-patch-concurrent-conflict-deterministic"
          , "pipeline-patch-run-local-only"
          , "pipeline-patch-diagnosis-provenance"
          , "pipeline-patch-callback-prestart-phase"
          ]
    , claimCatalogManifestClaim = ClaimName "pipeline-patch-claim-manifest"
    }

referencedRuntimeClaimCatalog :: ClaimCatalog
referencedRuntimeClaimCatalog =
  ClaimCatalog
    { claimCatalogName = "referenced-runtime"
    , claimCatalogCoreClaims =
        map
          ClaimName
          [ "referenced-runtime-chain-parallel-succeeded"
          , "referenced-runtime-module-input-single-flight"
          , "referenced-runtime-r-single-flight"
          , "referenced-runtime-occurrence-snapshot"
          , "referenced-runtime-fallback-uses-next-reference"
          , "referenced-runtime-invalid-r-value-rejected"
          , "referenced-runtime-undecided-race-is-explicitly-unsupported"
          ]
    , claimCatalogManifestClaim =
        ClaimName "referenced-runtime-claim-manifest"
    }
selfInterpretClaimCatalog :: ClaimCatalog
selfInterpretClaimCatalog =
  ClaimCatalog
    { claimCatalogName = "core-self-interpret"
    , claimCatalogCoreClaims =
        map
          ClaimName
          [ "previous-core-facet-is-content-addressed"
          , "previous-core-runs-compatibility-facet"
          , "candidate-is-expressed-by-l0-facade"
          , "candidate-runs-as-framework-business"
          , "empty-business-closes-recursion"
          , "empty-business-has-no-curde"
          , "empty-business-has-no-handler"
          , "empty-business-has-no-host-io"
          , "trustbase-not-forwarded-to-terminal-business"
          , "core2-core0-contract-exchangeable"
          , "candidate-has-no-previous-core-runtime-dependency"
          , "previous-core-back-reference-negative-rejected"
          , "semantic-fixed-point-passed"
          ]
    , claimCatalogManifestClaim =
        ClaimName "core-self-interpret-claim-manifest"
    }

promotionClaimCatalog :: ClaimCatalog
promotionClaimCatalog =
  ClaimCatalog
    { claimCatalogName = "core-promotion"
    , claimCatalogCoreClaims =
        map
          ClaimName
          [ "promotion-core-manifest-content-addressed"
          , "promotion-core-manifest-roundtrip"
          , "promotion-evidence-reports-validated"
          , "promotion-evidence-digests-bound"
          , "promotion-record-roundtrip"
          , "promotion-previous-core-back-reference-rejected"
          , "promotion-candidate-manifest-mismatch-rejected"
          , "promotion-invalid-semantic-report-rejected"
          , "promotion-pending-cannot-be-current"
          , "promotion-approved-pointer-matches-candidate"
          , "promotion-current-pointer-roundtrip"
          ]
    , claimCatalogManifestClaim =
        ClaimName "core-promotion-claim-manifest"
    }

sdkPackageClaimCatalog :: ClaimCatalog
sdkPackageClaimCatalog =
  ClaimCatalog
    { claimCatalogName = "sdk-package"
    , claimCatalogCoreClaims =
        map
          ClaimName
          [ "sdk-core-lock-valid"
          , "sdk-surface-digest-tamper-blocked"
          , "sdk-lowering-digest-tamper-blocked"
          , "sdk-pending-core-rejected"
          , "sdk-approved-artifact-digest-bound"
          , "sdk-package-materialized"
          , "sdk-package-verifies"
          , "sdk-package-manifest-binds-core-lock"
          ]
    , claimCatalogManifestClaim =
        ClaimName "sdk-package-claim-manifest"
    }

schemaCatalogClaimCatalog :: [SchemaCatalogEntry] -> ClaimCatalog
schemaCatalogClaimCatalog entries =
  ClaimCatalog
    { claimCatalogName = "schema-catalog"
    , claimCatalogCoreClaims =
        map schemaCatalogClaimName entries
    , claimCatalogManifestClaim =
        ClaimName "schema-catalog-claim-manifest"
    }

schemaCatalogClaimName :: SchemaCatalogEntry -> ClaimName
schemaCatalogClaimName entry =
  ClaimName
    ( "schema-catalog-output:"
        ++ renderSchemaId (schemaCatalogEntrySchema entry)
    )

claimCatalogClaims :: ClaimCatalog -> [ClaimName]
claimCatalogClaims catalog =
  claimCatalogCoreClaims catalog
    ++ [claimCatalogManifestClaim catalog]

evidenceFor ::
  ClaimName ->
  Bool ->
  String ->
  String ->
  ArtifactName ->
  Evidence
evidenceFor claim passed expected observed artifact =
  Evidence
    { evidenceClaim = claim
    , evidenceStatus =
        if passed
          then EvidencePassed
          else EvidenceFailed
    , evidenceExpected = expected
    , evidenceObserved = observed
    , evidenceArtifact = artifact
    }

claimManifestEvidence ::
  ClaimCatalog ->
  ArtifactName ->
  [Evidence] ->
  Evidence
claimManifestEvidence catalog artifact coreEvidence =
  evidenceFor
    (claimCatalogManifestClaim catalog)
    synced
    (claimCatalogName catalog ++ " evidence claims match the stable catalog")
    observed
    artifact
  where
    expected =
      claimCatalogCoreClaims catalog
    actual =
      map evidenceClaim coreEvidence
    synced =
      null (duplicateClaims (claimCatalogClaims catalog))
        && actual == expected
    observed
      | synced =
          "claim catalog synced: "
            ++ show (length actual)
            ++ " core claims"
      | otherwise =
          "expected "
            ++ show expected
            ++ "; actual "
            ++ show actual

completeEvidence ::
  ClaimCatalog ->
  ArtifactName ->
  [Evidence] ->
  [Evidence]
completeEvidence catalog artifact coreEvidence =
  coreEvidence
    ++ [claimManifestEvidence catalog artifact coreEvidence]

validateEvidenceClaims ::
  ClaimCatalog ->
  [Evidence] ->
  [ClaimCatalogViolation]
validateEvidenceClaims catalog payloads =
  duplicateViolations
    ++ orderViolations
  where
    expected =
      claimCatalogClaims catalog
    actual =
      map evidenceClaim payloads
    duplicateViolations =
      case duplicateClaims expected of
        [] -> []
        repeated -> [DuplicateCatalogClaims repeated]
    orderViolations
      | expected == actual = []
      | otherwise = [EvidenceClaimOrderMismatch expected actual]

duplicateClaims :: [ClaimName] -> [ClaimName]
duplicateClaims =
  map head
    . filter ((> 1) . length)
    . group
    . sort
