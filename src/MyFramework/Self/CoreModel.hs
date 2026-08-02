{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DeriveGeneric #-}

module MyFramework.Self.CoreModel
  ( EmptyBusiness (..)
  , CoreCompatibilityFacet (..)
  , FrameworkAsBusiness
  , FrameworkExecutionStatus (..)
  , FrameworkInterpretError (..)
  , FrameworkSemanticObservation (..)
  , candidateHasNoPreviousCoreDependency
  , decodeFrameworkAsBusiness
  , encodeFrameworkAsBusiness
  , frameworkAsBusiness
  , frameworkAsBusinessClaims
  , frameworkAsBusinessCompatibility
  , frameworkAsBusinessEffectCoverage
  , frameworkAsBusinessV52Program
  , frameworkAsBusinessReadCoverage
  , frameworkAsBusinessSchema
  , emptyBusinessProgram
  , coreCompatibilityFacet
  , coreCompatibilityFacetValid
  , coreCompatibilityDigest
  , interpretFrameworkAsBusiness
  ) where

import Data.List
  ( intercalate
  , isInfixOf
  )
import Text.Read
  ( readMaybe )

import GHC.Generics
  ( Generic
  )
import qualified MyFramework.Facade as V52
import qualified MyFramework.Runtime.V52 as Runtime
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
  , frameworkAsBusinessV52Program :: V52.PreparedRuntime
  , frameworkAsBusinessEffectCoverage :: [V52.EffectKey]
  , frameworkAsBusinessReadCoverage :: [V52.EffectKey]
  , frameworkAsBusinessCompatibility :: CoreCompatibilityFacet
  , frameworkAsBusinessClaims :: [String]
  }
  deriving (Eq, Ord, Read, Show)

-- | A one-way, content-addressed bridge from the approved core2 vocabulary
-- into the facade-epoch core0 vocabulary. It is compatibility metadata only:
-- the
-- canonical candidate remains 'frameworkAsBusinessV52Program'.
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
  = FrameworkHandlerRegistrationFailed [Runtime.RuntimeHandlerRegistryError]
  | FrameworkRuntimePreparationFailed [Runtime.RuntimePreparationError]
  | FrameworkRuntimeFailed Runtime.RuntimeFault
  | FrameworkRuntimeDidNotClose String
  | FrameworkCompatibilityFailed String
  deriving (Eq, Show)

data FrameworkSemanticObservation = FrameworkSemanticObservation
  { frameworkObservationSemanticDigest :: String
  , frameworkObservationCompatibilityDigest :: String
  , frameworkObservationControlSucceeded :: Bool
  , frameworkObservationFinalExecutionStatus :: FrameworkExecutionStatus
  , frameworkObservationRuntimeDependencies :: [CoreId]
  }
  deriving (Eq, Show)

data FrameworkExecutionStatus
  = FrameworkPending
  | FrameworkSucceeded
  | FrameworkFailed
  deriving (Eq, Ord, Read, Show)

frameworkCoreSchemaV6 :: String
frameworkCoreSchemaV6 =
  "myframework-framework-as-business.v6"

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
        frameworkCoreSchemaV6
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

data FrameworkSourceArgs = FrameworkSourceArgs
  { frameworkSourceValue :: String
  }
  deriving (Eq, Generic, Read, Show)

instance V52.HasSchema FrameworkSourceArgs

frameworkCoreV52Module :: V52.Name
frameworkCoreV52Module = V52.name "frameworkCore"

frameworkV52Source :: V52.R FrameworkSourceArgs
frameworkV52Source = V52.r "frameworkSource"

frameworkValidateV52Command ::
  V52.EffectRef 'V52.E FrameworkSourceArgs ()
frameworkValidateV52Command = V52.e "validateFacade" V52.none

frameworkValidateV52Map ::
  V52.EffectRef 'V52.MAP FrameworkSourceArgs FrameworkSourceArgs
frameworkValidateV52Map = V52.mapping "validateFacadeMap"

frameworkValidateV52 :: V52.Application
frameworkValidateV52 =
  V52.apply
    frameworkValidateV52Command
    frameworkValidateV52Map
    frameworkV52Source

frameworkLowerV52Command ::
  V52.EffectRef 'V52.E FrameworkSourceArgs ()
frameworkLowerV52Command =
  V52.e "lowerReferenced" (V52.after frameworkValidateV52)

frameworkLowerV52Map ::
  V52.EffectRef 'V52.MAP FrameworkSourceArgs FrameworkSourceArgs
frameworkLowerV52Map = V52.mapping "lowerReferencedMap"

frameworkLowerV52 :: V52.Application
frameworkLowerV52 =
  V52.apply frameworkLowerV52Command frameworkLowerV52Map frameworkV52Source

frameworkCompileV52Command ::
  V52.EffectRef 'V52.E FrameworkSourceArgs ()
frameworkCompileV52Command =
  V52.e "compileCata" (V52.after frameworkLowerV52)

frameworkCompileV52Map ::
  V52.EffectRef 'V52.MAP FrameworkSourceArgs FrameworkSourceArgs
frameworkCompileV52Map = V52.mapping "compileCataMap"

frameworkCompileV52 :: V52.Application
frameworkCompileV52 =
  V52.apply frameworkCompileV52Command frameworkCompileV52Map frameworkV52Source

frameworkCloseV52Command ::
  V52.EffectRef 'V52.E FrameworkSourceArgs ()
frameworkCloseV52Command =
  V52.e "closeEmpty" (V52.after frameworkCompileV52)

frameworkCloseV52Map ::
  V52.EffectRef 'V52.MAP FrameworkSourceArgs FrameworkSourceArgs
frameworkCloseV52Map = V52.mapping "closeEmptyMap"

frameworkCloseV52 :: V52.Application
frameworkCloseV52 =
  V52.apply frameworkCloseV52Command frameworkCloseV52Map frameworkV52Source

frameworkCoreV52Program :: Either [V52.ProgramError] V52.PreparedRuntime
frameworkCoreV52Program =
  V52.program
    frameworkCoreV52Module
    [ V52.chain
        frameworkCoreV52Module
        [ frameworkValidateV52
        , frameworkLowerV52
        , frameworkCompileV52
        , frameworkCloseV52
        ]
    ]
    [ V52.effects
        frameworkCoreV52Module
        [ frameworkValidateV52
        , frameworkLowerV52
        , frameworkCompileV52
        , frameworkCloseV52
        ]
    ]

emptyBusinessProgram :: Either [V52.ProgramError] V52.PreparedRuntime
emptyBusinessProgram =
  V52.program
    (V52.name "emptyBusiness")
    [V52.chain (V52.name "emptyBusiness") ([] :: [V52.Name])]
    [V52.effects (V52.name "emptyBusiness") []]

frameworkAsBusiness :: Either [String] FrameworkAsBusiness
frameworkAsBusiness =
  case frameworkCoreV52Program of
    Right currentV52Program ->
      Right
        FrameworkAsBusiness
          { frameworkAsBusinessSchema = frameworkCoreSchemaV6
          , frameworkAsBusinessV52Program = currentV52Program
          , frameworkAsBusinessEffectCoverage =
              [ V52.someEffectRefKey (V52.effectIrRef currentEffect)
              | currentEffect <-
                  V52.effectRegistryEffects
                    (V52.effectRegistryOf currentV52Program)
              ]
          , frameworkAsBusinessReadCoverage =
              [ V52.someEffectRefKey (V52.effectIrRef currentEffect)
              | currentEffect <-
                  V52.effectRegistryEffects
                    (V52.effectRegistryOf currentV52Program)
              , V52.someEffectRefKind (V52.effectIrRef currentEffect) == V52.R
              ]
          , frameworkAsBusinessCompatibility =
              coreCompatibilityFacet
          , frameworkAsBusinessClaims =
              [ "l0-v5.2-schema-free-facade"
              , "command-map-r-application"
              , "canonical-schema-catalog:"
                  ++ V52.programSchemaDigest currentV52Program
              , "module-local-effect-record"
              , "r-in-unified-effect-registry"
              , "resolver-driven-v5.2-runtime"
              , "occurrence-scoped-runtime"
              , "core2-v3-compatibility-facet:"
                  ++ compatibilityPreviousPayloadDigest
                    coreCompatibilityFacet
              , "empty-business-terminal"
              ]
          }
    Left currentV52Errors -> Left (map show currentV52Errors)

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
          /= frameworkCoreSchemaV6 ->
          Left "unsupported FrameworkAsBusiness schema"
      | not
          ( null
              ( V52.validate
                  (frameworkAsBusinessV52Program currentFramework)
              )
          ) ->
          Left "invalid v5.2 FrameworkAsBusiness program"
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
      case V52.resolveAll (frameworkAsBusinessV52Program currentFramework) of
        V52.AstPlanBranch _ V52.AstChain currentStages ->
          map v52StageName currentStages
        _ -> []

v52StageName :: V52.AstPlan -> String
v52StageName currentStage =
  case currentStage of
    V52.AstPlanApplication currentKey _ ->
      V52.astNodeKeyText currentKey
    V52.AstPlanBranch currentKey _ _ ->
      V52.astNodeKeyText currentKey

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
    case V52.validate (frameworkAsBusinessV52Program currentFramework) of
      currentErrors@(_ : _) ->
        pure
          ( Left
              ( FrameworkRuntimeDidNotClose
                  ("v5.2 program invalid: " ++ show currentErrors)
              )
          )
      [] ->
        case frameworkHandlerRegistry currentFramework currentTerminal of
          Left currentError ->
            pure (Left (FrameworkHandlerRegistrationFailed currentError))
          Right currentHandlers -> do
            currentRun <-
              V52.runPreparedRuntime
                currentHandlers
                (frameworkAsBusinessV52Program currentFramework)
            case currentRun of
              Left currentErrors ->
                pure (Left (FrameworkRuntimePreparationFailed currentErrors))
              Right currentResult ->
                case Runtime.unifiedRuntimeOutcome currentResult of
                  Runtime.Failed currentFailure ->
                    pure (Left (FrameworkRuntimeFailed currentFailure))
                  Runtime.Succeeded
                    | closeExecuted currentResult -> do
                        emptyClosed <- runEmptyBusiness
                        pure
                          ( if emptyClosed
                              then
                                Right
                                  FrameworkSemanticObservation
                                    { frameworkObservationSemanticDigest =
                                        semanticObservationDigest
                                          currentFramework
                                          FrameworkSucceeded
                                    , frameworkObservationCompatibilityDigest =
                                        coreCompatibilityDigest
                                          (frameworkAsBusinessCompatibility currentFramework)
                                    , frameworkObservationControlSucceeded = True
                                    , frameworkObservationFinalExecutionStatus = FrameworkSucceeded
                                    , frameworkObservationRuntimeDependencies = currentRuntimeDependencies
                                    }
                              else
                                Left
                                  ( FrameworkRuntimeDidNotClose
                                      "EmptyBusiness did not close with zero effects and zero handlers"
                                  )
                          )
                    | otherwise ->
                        pure
                          (Left (FrameworkRuntimeDidNotClose (show currentResult)))
                  currentOutcome ->
                    pure
                      ( Left
                          ( FrameworkRuntimeDidNotClose
                              ("framework suspended or cancelled: " ++ show currentOutcome)
                          )
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
  Either [Runtime.RuntimeHandlerRegistryError] Runtime.RuntimeHandlerRegistry
frameworkHandlerRegistry currentFramework currentTerminal =
  Runtime.runtimeHandlerRegistry
    [ frameworkRegistration currentFramework currentTerminal currentEffect
    | currentEffect <-
        V52.effectRegistryEffects
          (V52.effectRegistryOf (frameworkAsBusinessV52Program currentFramework))
    ]

frameworkRegistration ::
  FrameworkAsBusiness ->
  EmptyBusiness ->
  V52.EffectIR ->
  Runtime.RuntimeHandlerRegistration
frameworkRegistration currentFramework currentTerminal currentEffect =
  Runtime.runtimeHandler
    currentRef
    currentInputSchema
    currentOutputSchema
    invoke
  where
    currentRef = V52.effectIrRef currentEffect
    currentKey = V52.effectKeyText (V52.someEffectRefKey currentRef)
    (currentInputSchema, currentOutputSchema) =
      case V52.effectIrSpec currentEffect of
        V52.ReadEffect currentSpec ->
          (Nothing, Just (V52.readSpecValueSchema currentSpec))
        V52.MapEffect currentSpec ->
          (Just (V52.mapSpecInputSchema currentSpec), Just frameworkSourceSchemaId)
        V52.CommandEffect currentSpec ->
          ( Just (V52.commandSpecArgumentSchema currentSpec)
          , Just (V52.commandSpecObservationSchema currentSpec)
          )
    invoke currentInvocation =
      case Runtime.runtimeInvocationPhase currentInvocation of
        Runtime.RuntimeInputPhase -> pure (Runtime.HandlerSucceeded Nothing)
        Runtime.RuntimeReadPhase ->
          pure
            ( Runtime.HandlerSucceeded
                ( Just
                    ( Runtime.RuntimeValue
                        frameworkSourceSchemaId
                        ( show
                            ( FrameworkSourceArgs
                                (encodeFrameworkAsBusiness currentFramework)
                            )
                        )
                    )
                )
            )
        Runtime.RuntimeMapPhase ->
          pure
            ( case Runtime.runtimeInvocationValue currentInvocation of
                Just currentValue ->
                  Runtime.HandlerSucceeded
                    (Just currentValue {Runtime.runtimeValueSchema = frameworkSourceSchemaId})
                Nothing -> Runtime.HandlerFailed "framework MAP input missing"
            )
        Runtime.RuntimeCommandPhase ->
          pure
            ( case Runtime.runtimeInvocationValue currentInvocation >>= extractFrameworkSource of
                Nothing -> Runtime.HandlerFailed "framework command input is invalid"
                Just currentSource ->
                  case validateFrameworkStage currentKey currentSource of
                    Left currentError -> Runtime.HandlerFailed currentError
                    Right () ->
                      Runtime.HandlerSucceeded
                        (Just (Runtime.RuntimeValue frameworkUnitSchemaId "()"))
            )
        Runtime.RuntimeLoopPhase ->
          pure (Runtime.HandlerFailed "Loop phase cannot invoke a framework handler")
    validateFrameworkStage currentStage currentSource = do
      decodedFramework <- decodeFrameworkAsBusiness currentSource
      if decodedFramework /= currentFramework
        then Left "framework source does not match candidate"
        else
          if "validateFacade" `isInfixOf` currentStage
            then
              case V52.validate (frameworkAsBusinessV52Program decodedFramework) of
                [] -> Right ()
                currentErrors -> Left ("v5.2 validation failed: " ++ show currentErrors)
            else
              if "lowerReferenced" `isInfixOf` currentStage
                then ensureResolved decodedFramework
                else
                  if "compileCata" `isInfixOf` currentStage
                    then
                      if null (V52.programSchemaDigest (frameworkAsBusinessV52Program decodedFramework))
                        then Left "compiled schema digest is empty"
                        else ensureResolved decodedFramework
                    else
                      if "closeEmpty" `isInfixOf` currentStage
                        && currentTerminal == EmptyBusiness
                        && not (null (frameworkAsBusinessSchema decodedFramework))
                        then Right ()
                        else Left ("unknown framework command: " ++ currentStage)
    ensureResolved currentDecoded =
      if null (show (V52.resolveAll (frameworkAsBusinessV52Program currentDecoded)))
        then Left "resolved v5.2 control is empty"
        else Right ()

extractFrameworkSource :: Runtime.RuntimeValue -> Maybe String
extractFrameworkSource currentValue =
  case readMaybe (Runtime.runtimeValuePayload currentValue) of
    Just (FrameworkSourceArgs currentSource) -> Just currentSource
    Nothing -> Nothing

frameworkSourceSchemaId :: V52.ValueSchemaId
frameworkSourceSchemaId =
  V52.schemaDescriptorId
    ( V52.descriptorFor
        (V52.SchemaFromType "framework-as-business.v6")
        (V52.valueSchemaDefinition (Nothing :: Maybe FrameworkSourceArgs))
    )

frameworkUnitSchemaId :: V52.ValueSchemaId
frameworkUnitSchemaId =
  V52.schemaDescriptorId
    ( V52.descriptorFor
        (V52.SchemaFromType "framework-as-business.v6")
        (V52.valueSchemaDefinition (Nothing :: Maybe ()))
    )

closeExecuted :: Runtime.UnifiedRuntimeRun -> Bool
closeExecuted currentRun =
  any isCloseEvent
    (Runtime.runtimeSnapshotEvents (Runtime.unifiedRuntimeSnapshot currentRun))
  where
    isCloseEvent (Runtime.RuntimeHandlerFinished currentInstance Runtime.RuntimeCommandPhase currentResult) =
      "closeEmpty"
        `isInfixOf` V52.effectKeyText
          (V52.someEffectRefKey (Runtime.executionInstanceEffect currentInstance))
        && handlerResultSucceeded currentResult
    isCloseEvent _ = False

handlerResultSucceeded :: Runtime.RuntimeHandlerResult -> Bool
handlerResultSucceeded Runtime.HandlerSucceeded {} = True
handlerResultSucceeded (Runtime.HandlerSucceededBatch (_ : _)) = True
handlerResultSucceeded _ = False

runEmptyBusiness :: IO Bool
runEmptyBusiness =
  case (emptyBusinessProgram, Runtime.runtimeHandlerRegistry []) of
    (Right currentProgram, Right currentHandlers) -> do
      currentRun <- V52.runPreparedRuntime currentHandlers currentProgram
      pure
        ( case currentRun of
            Right currentResult ->
              Runtime.unifiedRuntimeOutcome currentResult == Runtime.Succeeded
                && null
                  [ ()
                  | Runtime.RuntimeHandlerStarted {} <-
                      Runtime.runtimeSnapshotEvents
                        (Runtime.unifiedRuntimeSnapshot currentResult)
                  ]
            Left _ -> False
        )
    _ -> pure False

semanticObservationDigest ::
  FrameworkAsBusiness ->
  FrameworkExecutionStatus ->
  String
semanticObservationDigest currentFramework currentStatus =
  sha256
    ( intercalate
        "|"
        [ frameworkAsBusinessSchema currentFramework
        , show (frameworkAsBusinessV52Program currentFramework)
        , show (frameworkAsBusinessEffectCoverage currentFramework)
        , show (frameworkAsBusinessReadCoverage currentFramework)
        , show (frameworkAsBusinessCompatibility currentFramework)
        , show (frameworkAsBusinessClaims currentFramework)
        , show currentStatus
        ]
    )
