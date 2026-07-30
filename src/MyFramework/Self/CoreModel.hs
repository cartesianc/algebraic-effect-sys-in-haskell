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
  ( FieldName (..)
  , SchemaIdentity
  , scalarSchema
  , schemaRefIdentityOf
  )
import MyFramework.Frontend
import MyFramework.Frontend.Runtime
import MyFramework.Handler
  ( RuntimeData (..)
  )
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

-- | A one-way, content-addressed bridge from the approved core1 vocabulary
-- into the L0 core2 vocabulary.  It is compatibility metadata only: the
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

frameworkCoreSchemaV3 :: String
frameworkCoreSchemaV3 =
  "myframework-framework-as-business.v3"

coreCompatibilityFacet :: CoreCompatibilityFacet
coreCompatibilityFacet =
  CoreCompatibilityFacet
    { compatibilityFacetSchema =
        "myframework-core-compatibility-facet.v1"
    , compatibilityPreviousCoreId = "core1"
    , compatibilityPreviousSourceCommit =
        "a610ffb142b960c93f72f0b9fad72a7ecaa78c84"
    , compatibilityPreviousArtifactDigest =
        "952e9cd0a60420e01c294a96fb1763aef4fd984c356057534ab96cea0fc61d9e"
    , compatibilityPreviousFrameworkSchema =
        "myframework-framework-as-business.v1"
    , compatibilityPreviousPayloadDigest =
        "446e5e5b124cfcad358aa574d9e2c8385bac508964b419fb08982ce11d6b54c4"
    , compatibilityPreviousObservationDigest =
        "33fce4c303e89b47911cbad8827ffcd4ffa88e6adf8cd1f078acadbf71c8ded9"
    , compatibilityCandidateFrameworkSchema =
        frameworkCoreSchemaV3
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

frameworkCoreModule :: ModuleName
frameworkCoreModule =
  ModuleName "frameworkCore"

frameworkSourceRead :: ReadKey
frameworkSourceRead =
  ReadKey "frameworkSource"

frameworkSourceSchema :: SchemaIdentity
frameworkSourceSchema =
  schemaRefIdentityOf (scalarSchema "FrameworkSource")

frameworkValidateFacadeKey :: LocalKey
frameworkValidateFacadeKey =
  LocalKey "validateFacade"

frameworkLowerReferencedKey :: LocalKey
frameworkLowerReferencedKey =
  LocalKey "lowerReferenced"

frameworkCompileCataKey :: LocalKey
frameworkCompileCataKey =
  LocalKey "compileCata"

frameworkCloseEmptyKey :: LocalKey
frameworkCloseEmptyKey =
  LocalKey "closeEmpty"

frameworkValidateFacadeAddress :: EffectAddress
frameworkValidateFacadeAddress =
  EffectAddress frameworkCoreModule frameworkValidateFacadeKey

frameworkLowerReferencedAddress :: EffectAddress
frameworkLowerReferencedAddress =
  EffectAddress frameworkCoreModule frameworkLowerReferencedKey

frameworkCompileCataAddress :: EffectAddress
frameworkCompileCataAddress =
  EffectAddress frameworkCoreModule frameworkCompileCataKey

frameworkCloseEmptyAddress :: EffectAddress
frameworkCloseEmptyAddress =
  EffectAddress frameworkCoreModule frameworkCloseEmptyKey

frameworkCoreProgram :: ReferencedProgram
frameworkCoreProgram =
  referencedProgram
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
          , frameworkEffect Nothing
          )
        , ( frameworkLowerReferencedKey
          , frameworkEffect (Just frameworkValidateFacadeKey)
          )
        , ( frameworkCompileCataKey
          , frameworkEffect (Just frameworkLowerReferencedKey)
          )
        , ( frameworkCloseEmptyKey
          , frameworkEffect (Just frameworkCompileCataKey)
          )
        ]
    ]
    (readRecord [(frameworkSourceRead, frameworkSourceSchema)])

frameworkEffect :: Maybe LocalKey -> EffectDecl
frameworkEffect currentInput =
  EffectDecl
    { effectDeclType = EffectE
    , effectDeclInput = currentInput
    , effectDeclParams =
        [ ( ParamKey "source"
          , ParamBinding
              { paramBindingSchema = frameworkSourceSchema
              , paramBindingSource =
                  ParamFromRead frameworkSourceRead
              }
          )
        ]
    }

frameworkAsBusiness :: Either [FrontendError] FrameworkAsBusiness
frameworkAsBusiness =
  case validateReferencedProgram frameworkCoreProgram of
    [] ->
      Right
        FrameworkAsBusiness
          { frameworkAsBusinessSchema = frameworkCoreSchemaV3
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
              , "core1-v1-compatibility-facet:"
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
          /= frameworkCoreSchemaV3 ->
          Left "unsupported FrameworkAsBusiness schema"
      | not
          ( null
              ( validateReferencedProgram
                  (frameworkAsBusinessProgram currentFramework)
              )
          ) ->
          Left "invalid referenced FrameworkAsBusiness program"
      | not (coreCompatibilityFacetValid currentFramework) ->
          Left "invalid core1 compatibility facet"
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
          [ controlDeclChildren currentControl
          | currentControl <-
              referencedProgramControls
                (frameworkAsBusinessProgram currentFramework)
          , controlDeclModule currentControl == frameworkCoreModule
          , controlDeclKind currentControl == ControlChain
          ] of
        currentStages : _ ->
          map localKeyText currentStages
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
                      validateReferencedProgram
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
            resolveProgram
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
          resolveProgram
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
