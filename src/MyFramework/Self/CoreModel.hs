module MyFramework.Self.CoreModel
  ( EmptyBusiness (..)
  , CoreCompatibilityFacet (..)
  , FrameworkAsBusiness
  , FrameworkInterpretError (..)
  , FrameworkSemanticObservation (..)
  , candidateHasNoPreviousCoreDependency
  , decodeFrameworkAsBusiness
  , encodeFrameworkAsBusiness
  , frameworkAsBusiness
  , frameworkAsBusinessClaims
  , frameworkAsBusinessCompatibility
  , frameworkAsBusinessEffectCoverage
  , frameworkAsBusinessProgram
  , frameworkAsBusinessReadCoverage
  , frameworkAsBusinessSchema
  , frameworkCloseEmptyAddress
  , frameworkCompileCataAddress
  , frameworkCoreProgram
  , coreCompatibilityFacet
  , coreCompatibilityFacetValid
  , coreCompatibilityDigest
  , frameworkLowerReferencedAddress
  , frameworkValidateFacadeAddress
  , interpretFrameworkAsBusiness
  ) where

import Data.List
  ( find
  , intercalate
  )
import Text.Read
  ( readMaybe )

import MyFramework.CURDE
  ( scalarSchema
  , schemaRefIdentityOf
  )
import MyFramework.Facade
import qualified MyFramework.Frontend as Frontend
import MyFramework.Frontend.Runtime
import MyFramework.TrustBase.Core
  ( CoreId )
import MyFramework.TrustBase.Digest
  ( sha256 )

-- | The terminal App argument contains no effect declaration, AST node,
-- handler, runtime value, or host capability.
data EmptyBusiness = EmptyBusiness
  deriving (Eq, Ord, Read, Show)

-- | Core is described by the same L0 referenced frontend as a business app.
-- No legacy EffSysDecl or AstBlueprintSeed is retained in this model.
data FrameworkAsBusiness = FrameworkAsBusiness
  { frameworkAsBusinessSchema :: String
  , frameworkAsBusinessProgram :: ReferencedProgram
  , frameworkAsBusinessEffectCoverage :: [EffectAddress]
  , frameworkAsBusinessReadCoverage :: [ReadKey]
  , frameworkAsBusinessCompatibility :: CoreCompatibilityFacet
  , frameworkAsBusinessClaims :: [String]
  }
  deriving (Eq, Ord, Read, Show)

-- | A one-way, content-addressed bridge from the approved core2 vocabulary
-- into the facade-epoch core0 vocabulary. It is compatibility metadata only:
-- the
-- canonical candidate remains 'frameworkAsBusinessProgram'.
data CoreCompatibilityFacet = CoreCompatibilityFacet
  { compatibilityFacetSchema :: String
  , compatibilityPreviousCoreId :: String
  , compatibilityPreviousSourceCommit :: String
  , compatibilityPreviousArtifactDigest :: String
  , compatibilityPreviousFrameworkSchema :: String
  , compatibilityPreviousPayloadDigest :: String
  , compatibilityPreviousObservationDigest :: String
  , compatibilityCandidateFrameworkSchema :: String
  , compatibilityStageMap :: [(String, String)]
  }
  deriving (Eq, Ord, Read, Show)

data FrameworkInterpretError
  = FrameworkHandlerRegistrationFailed FrontendRegistryError
  | FrameworkRuntimeFailed FrontendRuntimeFailure
  | FrameworkRuntimeDidNotClose String
  | FrameworkCompatibilityFailed String
  deriving (Eq, Show)

data FrameworkSemanticObservation = FrameworkSemanticObservation
  { frameworkObservationSemanticDigest :: String
  , frameworkObservationCompatibilityDigest :: String
  , frameworkObservationControlSucceeded :: Bool
  , frameworkObservationFinalExecutionStatus :: FrontendExecutionStatus
  , frameworkObservationRuntimeDependencies :: [CoreId]
  }
  deriving (Eq, Show)

frameworkCoreSchemaV4 :: String
frameworkCoreSchemaV4 =
  "myframework-framework-as-business.v4"

coreCompatibilityFacet :: CoreCompatibilityFacet
coreCompatibilityFacet =
  CoreCompatibilityFacet
    { compatibilityFacetSchema =
        "myframework-core-compatibility-facet.v1"
    , compatibilityPreviousCoreId = "core2"
    , compatibilityPreviousSourceCommit =
        "78598a77bff3d3e864347b7aafcc1764395e4319"
    , compatibilityPreviousArtifactDigest =
        "4e45128c8c133896cdf2eecf65113a7dffe017a9e3f77318b60e902003d17a0a"
    , compatibilityPreviousFrameworkSchema =
        "myframework-framework-as-business.v3"
    , compatibilityPreviousPayloadDigest =
        "2202c857e7834aa01007d9a270343eed25d823e695086716d39404d64c0261f7"
    , compatibilityPreviousObservationDigest =
        "1dcc4c82248f9e70573262ef45cdda2d14cbd7c2a7a8612948e276fe0280a08f"
    , compatibilityCandidateFrameworkSchema =
        frameworkCoreSchemaV4
    , compatibilityStageMap =
        [ ("validateFacade", "validateFacade")
        , ("lowerCurde", "lowerReferenced")
        , ("compileCata", "compileCata")
        , ("closeEmpty", "closeEmpty")
        ]
    }

coreCompatibilityDigest :: CoreCompatibilityFacet -> String
coreCompatibilityDigest currentFacet =
  sha256
    ( intercalate
        "|"
        [ compatibilityFacetSchema currentFacet
        , compatibilityPreviousCoreId currentFacet
        , compatibilityPreviousSourceCommit currentFacet
        , compatibilityPreviousArtifactDigest currentFacet
        , compatibilityPreviousFrameworkSchema currentFacet
        , compatibilityPreviousPayloadDigest currentFacet
        , compatibilityPreviousObservationDigest currentFacet
        , compatibilityCandidateFrameworkSchema currentFacet
        , show (map fst (compatibilityStageMap currentFacet))
        , show (map snd (compatibilityStageMap currentFacet))
        ]
    )

frameworkCoreModule :: Name
frameworkCoreModule =
  name "frameworkCore"

frameworkSourceRead :: ReadKey
frameworkSourceRead =
  readKeyOf frameworkSource

frameworkSource :: R
frameworkSource =
  r "frameworkSource" frameworkSourceSchema

frameworkSourceSchema :: SchemaIdentity
frameworkSourceSchema =
  schemaRefIdentityOf (scalarSchema "FrameworkSource")

frameworkValidateFacadeKey :: Name
frameworkValidateFacadeKey =
  name "validateFacade"

frameworkLowerReferencedKey :: Name
frameworkLowerReferencedKey =
  name "lowerReferenced"

frameworkCompileCataKey :: Name
frameworkCompileCataKey =
  name "compileCata"

frameworkCloseEmptyKey :: Name
frameworkCloseEmptyKey =
  name "closeEmpty"

frameworkSourceParam :: Name
frameworkSourceParam =
  name "source"

frameworkValidateFacadeAddress :: EffectAddress
frameworkValidateFacadeAddress =
  address frameworkCoreModule frameworkValidateFacadeKey

frameworkLowerReferencedAddress :: EffectAddress
frameworkLowerReferencedAddress =
  address frameworkCoreModule frameworkLowerReferencedKey

frameworkCompileCataAddress :: EffectAddress
frameworkCompileCataAddress =
  address frameworkCoreModule frameworkCompileCataKey

frameworkCloseEmptyAddress :: EffectAddress
frameworkCloseEmptyAddress =
  address frameworkCoreModule frameworkCloseEmptyKey

frameworkCoreProgram :: ReferencedProgram
frameworkCoreProgram =
  program
    frameworkCoreModule
    [ chain
        frameworkCoreModule
        [ frameworkValidateFacadeKey
        , frameworkLowerReferencedKey
        , frameworkCompileCataKey
        , frameworkCloseEmptyKey
        ]
    ]
    [ effects
        frameworkCoreModule
        [ ( frameworkValidateFacadeKey
          , frameworkEffect none
          )
        , ( frameworkLowerReferencedKey
          , frameworkEffect (after frameworkValidateFacadeKey)
          )
        , ( frameworkCompileCataKey
          , frameworkEffect (after frameworkLowerReferencedKey)
          )
        , ( frameworkCloseEmptyKey
          , frameworkEffect (after frameworkCompileCataKey)
          )
        ]
    ]
    (readRegistry [frameworkSource])

frameworkEffect :: Maybe Name -> Effect
frameworkEffect currentInput =
  Effect
    { crude = E
    , input = currentInput
    , params =
        [frameworkSourceParam .= fromR frameworkSource]
    }

frameworkAsBusiness :: Either [FrontendError] FrameworkAsBusiness
frameworkAsBusiness =
  case validate frameworkCoreProgram of
    [] ->
      Right
        FrameworkAsBusiness
          { frameworkAsBusinessSchema = frameworkCoreSchemaV4
          , frameworkAsBusinessProgram = frameworkCoreProgram
          , frameworkAsBusinessEffectCoverage =
              [ frameworkValidateFacadeAddress
              , frameworkLowerReferencedAddress
              , frameworkCompileCataAddress
              , frameworkCloseEmptyAddress
              ]
          , frameworkAsBusinessReadCoverage =
              [frameworkSourceRead]
          , frameworkAsBusinessCompatibility =
              coreCompatibilityFacet
          , frameworkAsBusinessClaims =
              [ "l0-referenced-frontend"
              , "module-local-effect-record"
              , "r-separated-from-cude"
              , "resolver-driven-cata"
              , "occurrence-scoped-runtime"
              , "core2-v3-compatibility-facet:"
                  ++ compatibilityPreviousPayloadDigest
                    coreCompatibilityFacet
              , "empty-business-terminal"
              ]
          }
    currentErrors ->
      Left currentErrors

encodeFrameworkAsBusiness :: FrameworkAsBusiness -> String
encodeFrameworkAsBusiness =
  show

decodeFrameworkAsBusiness ::
  String ->
  Either String FrameworkAsBusiness
decodeFrameworkAsBusiness currentText =
  case readMaybe currentText of
    Nothing ->
      Left "invalid FrameworkAsBusiness"
    Just currentFramework
      | frameworkAsBusinessSchema currentFramework
          /= frameworkCoreSchemaV4 ->
          Left "unsupported FrameworkAsBusiness schema"
      | not
          ( null
              ( validate
                  (frameworkAsBusinessProgram currentFramework)
              )
          ) ->
          Left "invalid referenced FrameworkAsBusiness program"
      | not (coreCompatibilityFacetValid currentFramework) ->
          Left "invalid core2 compatibility facet"
      | otherwise ->
          Right currentFramework

coreCompatibilityFacetValid :: FrameworkAsBusiness -> Bool
coreCompatibilityFacetValid currentFramework =
  frameworkAsBusinessCompatibility currentFramework
    == coreCompatibilityFacet
    && frameworkAsBusinessSchema currentFramework
      == compatibilityCandidateFrameworkSchema coreCompatibilityFacet
    && actualStages == map snd (compatibilityStageMap coreCompatibilityFacet)
  where
    actualStages =
      case
          [ Frontend.controlDeclChildren currentControl
          | currentControl <-
              Frontend.referencedProgramControls
                (frameworkAsBusinessProgram currentFramework)
          , Frontend.controlDeclModule currentControl
              == Frontend.effectAddressModule
                frameworkValidateFacadeAddress
          , Frontend.controlDeclKind currentControl
              == Frontend.ControlChain
          ] of
        currentStages : _ ->
          map Frontend.localKeyText currentStages
        [] ->
          []

interpretFrameworkAsBusiness ::
  [CoreId] ->
  FrameworkAsBusiness ->
  EmptyBusiness ->
  IO
    ( Either
        FrameworkInterpretError
        FrameworkSemanticObservation
    )
interpretFrameworkAsBusiness
  currentRuntimeDependencies
  currentFramework
  currentTerminal =
    case frameworkHandlerRegistry currentFramework currentTerminal of
      Left currentError ->
        pure (Left (FrameworkHandlerRegistrationFailed currentError))
      Right currentHandlers -> do
        currentRun <-
          runReferencedProgram
            (frameworkAsBusinessProgram currentFramework)
            currentHandlers
        let currentStatus =
              closeExecutionStatus currentRun
            currentControlSucceeded =
              frontendRunOutcome currentRun == Right ()
            currentClosed =
              currentControlSucceeded
                && currentStatus == FrontendSucceeded
        pure
          ( case frontendRunOutcome currentRun of
              Left currentFailure ->
                Left (FrameworkRuntimeFailed currentFailure)
              Right ()
                | currentClosed ->
                    Right
                      FrameworkSemanticObservation
                        { frameworkObservationSemanticDigest =
                            semanticObservationDigest
                              currentFramework
                              currentStatus
                        , frameworkObservationCompatibilityDigest =
                            coreCompatibilityDigest
                              (frameworkAsBusinessCompatibility currentFramework)
                        , frameworkObservationControlSucceeded =
                            True
                        , frameworkObservationFinalExecutionStatus =
                            currentStatus
                        , frameworkObservationRuntimeDependencies =
                            currentRuntimeDependencies
                        }
                | otherwise ->
                    Left
                      (FrameworkRuntimeDidNotClose (show currentRun))
          )

candidateHasNoPreviousCoreDependency ::
  CoreId ->
  FrameworkSemanticObservation ->
  Bool
candidateHasNoPreviousCoreDependency previousCore currentObservation =
  previousCore
    `notElem` frameworkObservationRuntimeDependencies currentObservation

frameworkHandlerRegistry ::
  FrameworkAsBusiness ->
  EmptyBusiness ->
  Either FrontendRegistryError FrontendHandlers
frameworkHandlerRegistry currentFramework currentTerminal = do
  withRead <-
    registerFrontendRead
      frameworkSourceRead
      ( pure
          ( Right
              (RuntimeText (encodeFrameworkAsBusiness currentFramework))
          )
      )
      emptyFrontendHandlers
  withValidate <-
    registerFrontendEffect
      frameworkValidateFacadeAddress
      (frameworkValidateHandler currentFramework)
      withRead
  withLower <-
    registerFrontendEffect
      frameworkLowerReferencedAddress
      (frameworkLowerHandler currentFramework)
      withValidate
  withCompile <-
    registerFrontendEffect
      frameworkCompileCataAddress
      (frameworkCompileHandler currentFramework)
      withLower
  registerFrontendEffect
    frameworkCloseEmptyAddress
    (frameworkCloseHandler currentFramework currentTerminal)
    withCompile

frameworkValidateHandler ::
  FrameworkAsBusiness ->
  FrontendEffectHandler
frameworkValidateHandler currentFramework currentArguments =
  case extractFrameworkSource currentArguments of
    Left currentError ->
      pure (Left currentError)
    Right currentSource ->
      pure
        ( case decodeFrameworkAsBusiness currentSource of
            Left currentError ->
              Left currentError
            Right decodedFramework
              | decodedFramework /= currentFramework ->
                  Left "framework source does not match candidate"
              | otherwise ->
                  case
                      validate
                        (frameworkAsBusinessProgram decodedFramework) of
                    [] ->
                      Right ()
                    currentErrors ->
                      Left
                        ( "frontend validation failed: "
                            ++ show currentErrors
                        )
        )

frameworkLowerHandler ::
  FrameworkAsBusiness ->
  FrontendEffectHandler
frameworkLowerHandler currentFramework currentArguments =
  pure $ do
    currentSource <- extractFrameworkSource currentArguments
    decodedFramework <-
      decodeFrameworkAsBusiness currentSource
    if decodedFramework /= currentFramework
      then Left "lowering source does not match candidate"
      else
        case
            resolveAll
              (frameworkAsBusinessProgram decodedFramework) of
          Left currentErrors ->
            Left ("referenced lowering failed: " ++ show currentErrors)
          Right _ ->
            Right ()

frameworkCompileHandler ::
  FrameworkAsBusiness ->
  FrontendEffectHandler
frameworkCompileHandler currentFramework currentArguments =
  pure $ do
    currentSource <- extractFrameworkSource currentArguments
    decodedFramework <-
      decodeFrameworkAsBusiness currentSource
    currentRoot <-
      case
          resolveAll
            (frameworkAsBusinessProgram decodedFramework) of
        Left currentErrors ->
          Left ("resolver-driven cata failed: " ++ show currentErrors)
        Right currentResolved ->
          Right currentResolved
    if null (show currentRoot)
      || decodedFramework /= currentFramework
      then Left "resolved framework control is empty or mismatched"
      else Right ()

frameworkCloseHandler ::
  FrameworkAsBusiness ->
  EmptyBusiness ->
  FrontendEffectHandler
frameworkCloseHandler currentFramework EmptyBusiness currentArguments =
  pure $ do
    currentSource <- extractFrameworkSource currentArguments
    decodedFramework <-
      decodeFrameworkAsBusiness currentSource
    if decodedFramework == currentFramework
      && not (null (frameworkAsBusinessSchema currentFramework))
      then Right ()
      else Left "terminal close did not receive candidate framework"

extractFrameworkSource :: RuntimeData -> Either String String
extractFrameworkSource currentArguments =
  case currentArguments of
    RuntimeRecord currentFields ->
      case
          [ currentValue
          | (FieldName currentName, currentValue) <- currentFields
          , currentName == "source"
          ] of
        [RuntimeText currentSource] ->
          Right currentSource
        [] ->
          Left "missing framework source parameter"
        _ ->
          Left "invalid framework source parameter"
    _ ->
      Left "framework effect arguments must be a record"

closeExecutionStatus :: FrontendRunResult -> FrontendExecutionStatus
closeExecutionStatus currentRun =
  case
      find
        ( (== frameworkCloseEmptyAddress)
            . effectOccurrenceAddress
            . fst
        )
        (frontendSnapshotEffects (frontendRunSnapshot currentRun)) of
    Nothing ->
      FrontendPending
    Just (_, currentStatus) ->
      currentStatus

semanticObservationDigest ::
  FrameworkAsBusiness ->
  FrontendExecutionStatus ->
  String
semanticObservationDigest currentFramework currentStatus =
  sha256
    ( intercalate
        "|"
        [ frameworkAsBusinessSchema currentFramework
        , show (frameworkAsBusinessProgram currentFramework)
        , show (frameworkAsBusinessEffectCoverage currentFramework)
        , show (frameworkAsBusinessReadCoverage currentFramework)
        , show (frameworkAsBusinessCompatibility currentFramework)
        , show (frameworkAsBusinessClaims currentFramework)
        , show currentStatus
        ]
    )
