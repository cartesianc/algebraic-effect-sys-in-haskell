{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE PatternSynonyms #-}
{-# LANGUAGE ScopedTypeVariables #-}

module MyFramework.Facade
  ( Application
  , AstRef
  , ControlDecl
  , EffectInputRef
  , EffectModule
  , Name
  , Program
  , ProgramError (..)
  , ProgramIR (..)
  , R
  , pattern R
  , PreparedRuntime (..)
  , applicationName
  , applicationRef
  , apply
  , applyEffSys
  , after
  , c
  , chain
  , d
  , e
  , effectRegistryOf
  , effects
  , effSys
  , fallback
  , graphProgramOf
  , mapping
  , name
  , nameText
  , none
  , parallel
  , prepareRuntime
  , program
  , programElaborated
  , programSchemaCatalog
  , programSchemaDigest
  , programSurface
  , r
  , race
  , resolveAll
  , runPreparedRuntime
  , schemaCatalogOf
  , scopedEffSys
  , transformRegistryOf
  , u
  , validate
  , module MyFramework.Effect
  , module MyFramework.Elaboration
  , module MyFramework.Graph
  , module MyFramework.Schema
  ) where

import Data.List
  ( group
  , nub
  , sort
  , sortOn
  )
import qualified Data.Map.Strict as Map
import Data.Proxy
  ( Proxy (..)
  )

import MyFramework.Effect hiding
  ( R
  , cEffectRef
  , dEffectRef
  , eEffectRef
  , mapEffectRef
  , rEffectRef
  , uEffectRef
  )
import qualified MyFramework.Effect as CoreEffect
import MyFramework.EffSys
import MyFramework.Elaboration
import MyFramework.Graph
import MyFramework.Schema
import MyFramework.Runtime.V52
  ( ContinuationPlan
  , ContinuationPlanError
  , RuntimeHandlerRegistry
  , RuntimePreparationError
  , UnifiedRuntimeRun
  , compileContinuationPlan
  , executeRuntime
  )

newtype Name = Name
  { nameText :: String
  }
  deriving (Eq, Ord, Read, Show)

name :: String -> Name
name = Name

-- | Public R remains the typed core EffectRef alias.
type R value = EffectRef 'CoreEffect.R () value

pattern R :: EffectKind
pattern R = CoreEffect.R

c :: String -> Maybe SomeEffectRef -> EffectRef 'C input output
c currentKey currentInput =
  withEffectInput currentInput (CoreEffect.cEffectRef (EffectKey currentKey))

u :: String -> Maybe SomeEffectRef -> EffectRef 'U input output
u currentKey currentInput =
  withEffectInput currentInput (CoreEffect.uEffectRef (EffectKey currentKey))

r :: String -> R output
r = CoreEffect.rEffectRef . EffectKey

d :: String -> Maybe SomeEffectRef -> EffectRef 'D input output
d currentKey currentInput =
  withEffectInput currentInput (CoreEffect.dEffectRef (EffectKey currentKey))

e :: String -> Maybe SomeEffectRef -> EffectRef 'E input output
e currentKey currentInput =
  withEffectInput currentInput (CoreEffect.eEffectRef (EffectKey currentKey))

mapping :: String -> EffectRef 'MAP source params
mapping = CoreEffect.mapEffectRef . EffectKey

none :: Maybe value
none = Nothing

class EffectInputRef value where
  effectInputRef :: value -> SomeEffectRef

instance KnownEffectKind kind => EffectInputRef (EffectRef kind input output) where
  effectInputRef = eraseEffectRef

instance EffectInputRef Application where
  effectInputRef = effectApplicationCommand . applicationIR

after :: EffectInputRef value => value -> Maybe SomeEffectRef
after = Just . effectInputRef

data Application = Application
  { applicationName :: Name
  , applicationIR :: EffectApplication
  , applicationEffectIR :: [EffectIR]
  , applicationTransformIR :: TransformDecl
  , applicationSurfaceBindings :: [(BindingKey, SurfaceBinding)]
  , applicationSchemaEvidence :: [SchemaEvidence]
  }
  deriving (Eq, Ord, Read, Show)

applicationRef :: Application -> SomeEffectRef
applicationRef = effectApplicationCommand . applicationIR

apply ::
  forall commandKind params observation source.
  ( CommandEffectKind commandKind
  , HasSchema params
  , HasSchema observation
  , HasSchema source
  ) =>
  EffectRef commandKind params observation ->
  EffectRef 'MAP source params ->
  R source ->
  Application
apply currentCommand currentMap currentRead =
  Application
    { applicationName = Name (effectKeyText commandKey)
    , applicationIR =
        effectApplication
          (ApplicationKey (effectKeyText commandKey))
          currentCommand
          currentMap
          currentRead
    , applicationEffectIR =
        [ commandEffect
            currentCommand
            (effectRefInput currentCommand)
            (CommandSpec paramsSchemaId currentParams observationSchemaId)
        , mapEffect
            currentMap
            (effectRefInput currentMap)
            ( MapSpec
                currentTransformRef
                sourceSchemaId
                currentParams
            )
        , readEffect
            currentRead
            (effectRefInput currentRead)
            ( ReadSpec
                sourceSchemaId
                (ValueExternal (effectKeyText readKey))
            )
        ]
    , applicationTransformIR =
        TransformDecl
          { transformDeclRef = currentTransformRef
          , transformDeclInputSchema = sourceSchemaId
          , transformDeclOutput = currentParams
          }
    , applicationSurfaceBindings =
        [ evidenceBinding sourceBindingKey
        , evidenceBinding paramsBindingKey
        , evidenceBinding observationBindingKey
        ]
    , applicationSchemaEvidence =
        [ typedEvidence sourceBindingKey (Proxy :: Proxy source)
        , typedEvidence paramsBindingKey (Proxy :: Proxy params)
        , typedEvidence observationBindingKey (Proxy :: Proxy observation)
        ]
    }
  where
    commandKey = effectRefKey currentCommand
    mapKey = effectRefKey currentMap
    readKey = effectRefKey currentRead
    sourceDefinition = valueSchemaDefinition (Proxy :: Proxy source)
    paramsDefinition = valueSchemaDefinition (Proxy :: Proxy params)
    observationDefinition = valueSchemaDefinition (Proxy :: Proxy observation)
    sourceSchemaId = definitionId sourceDefinition
    paramsSchemaId = definitionId paramsDefinition
    observationSchemaId = definitionId observationDefinition
    currentParams = paramsForDefinition paramsDefinition
    currentTransformRef =
      TransformRef (effectKeyText mapKey ++ "/transform")
    sourceBindingKey =
      BindingKey (effectKeyText readKey ++ "/value")
    paramsBindingKey =
      BindingKey (effectKeyText mapKey ++ "/output")
    observationBindingKey =
      BindingKey (effectKeyText commandKey ++ "/observation")

applyEffSys ::
  forall commandKind params observation.
  ( CommandEffectKind commandKind
  , HasSchema params
  , HasSchema observation
  ) =>
  EffectRef commandKind params observation ->
  EffectRef 'MAP EffSysRef params ->
  R EffSysRef ->
  EffSysRef ->
  Application
applyEffSys currentCommand currentMap currentRead currentEffSysRef =
  currentApplication
    { applicationEffectIR =
        map replaceReadSource (applicationEffectIR currentApplication)
    }
  where
    currentApplication = apply currentCommand currentMap currentRead
    currentReadKey = effectRefKey currentRead
    replaceReadSource currentEffect
      | someEffectRefKey (effectIrRef currentEffect) == currentReadKey =
          case effectIrSpec currentEffect of
            ReadEffect currentSpec ->
              currentEffect
                { effectIrSpec =
                    ReadEffect
                      currentSpec
                        { readSpecSource = ValueEffSysRef currentEffSysRef
                        }
                }
            _ -> currentEffect
      | otherwise = currentEffect

effSys :: Name -> Name -> EffSysRef
effSys currentRegistry currentAstRoot =
  declaredEffSysRef (nameText currentRegistry) (nameText currentAstRoot)

evidenceBinding :: BindingKey -> (BindingKey, SurfaceBinding)
evidenceBinding currentKey =
  (currentKey, SurfaceEvidence currentKey)

definitionId :: SchemaDefinition -> ValueSchemaId
definitionId currentDefinition =
  schemaDescriptorId (descriptorFor SchemaFromRecord currentDefinition)

paramsForDefinition :: SchemaDefinition -> [ParamSpec]
paramsForDefinition currentDefinition =
  case schemaDefinitionShape currentDefinition of
    ValueUnitShape -> []
    ValueRecordShape currentFields ->
      [ ParamSpec
          { paramSpecName = ParamName currentName
          , paramSpecSchema = definitionId currentChild
          }
      | (currentName, currentChild) <- currentFields
      ]
    _ ->
      [ ParamSpec
          { paramSpecName = ParamName "value"
          , paramSpecSchema = definitionId currentDefinition
          }
      ]

class AstRef reference where
  astReferenceName :: reference -> Name

instance AstRef Name where
  astReferenceName = id

instance AstRef Application where
  astReferenceName = applicationName

data ControlDecl = ControlDecl
  { controlName :: Name
  , controlKind :: AstBranchKind
  , controlChildren :: [Name]
  }
  deriving (Eq, Ord, Read, Show)

chain :: AstRef child => Name -> [child] -> ControlDecl
chain = control AstChain

parallel :: AstRef child => Name -> [child] -> ControlDecl
parallel = control AstParallel

fallback :: AstRef child => Name -> [child] -> ControlDecl
fallback = control AstFallback

race :: AstRef child => Name -> [child] -> ControlDecl
race = control AstRace

control :: AstRef child => AstBranchKind -> Name -> [child] -> ControlDecl
control currentKind currentName currentChildren =
  ControlDecl
    { controlName = currentName
    , controlKind = currentKind
    , controlChildren = map astReferenceName currentChildren
    }

data EffectModule = EffectModule
  { effectModuleName :: Name
  , effectModuleApplications :: [Application]
  }
  deriving (Eq, Ord, Read, Show)

effects :: Name -> [Application] -> EffectModule
effects currentModule currentApplications =
  EffectModule
    { effectModuleName = currentModule
    , effectModuleApplications =
        map (qualifyApplication currentModule) currentApplications
    }

data ProgramIR = ProgramIR
  { programIrEffects :: EffectRegistry
  , programIrTransforms :: TransformRegistry
  , programIrAst :: AstPlan
  , programIrEffSysRegistry :: EffSysRegistryId
  }
  deriving (Eq, Ord, Read, Show)

data Program = Program
  { programSurface :: SurfaceProgram ProgramIR
  , programElaborated :: ElaboratedProgram ProgramIR
  , graphProgramOf :: CompiledGraphs
  , programContinuationPlan :: ContinuationPlan
  }
  deriving (Eq, Ord, Read, Show)

data PreparedRuntime = PreparedRuntime
  { preparedRuntimeProgram :: Program
  , preparedRuntimeContinuationPlan :: ContinuationPlan
  }
  deriving (Eq, Ord, Read, Show)

data ProgramError
  = DuplicateControlName [Name]
  | DuplicateEffectModuleName [Name]
  | DuplicateApplicationName Name [Name]
  | RootControlMissing Name
  | EffectModuleWithoutControl Name
  | ChildReferenceMissing Name Name
  | ChildReferenceAmbiguous Name Name
  | ControlReferenceCycle [Name]
  | EffectDefinitionConflict EffectKey
  | TransformDefinitionConflict TransformRef
  | SurfaceBindingConflict BindingKey
  | ProgramElaborationFailed ElaborationError
  | ProgramGraphFailed GraphError
  | ProgramContinuationFailed ContinuationPlanError
  | ProgramEffSysFailed EffSysError
  deriving (Eq, Ord, Read, Show)

program ::
  Name ->
  [ControlDecl] ->
  [EffectModule] ->
  Either [ProgramError] PreparedRuntime
program currentRoot currentControls currentModules = do
  currentIr <- buildProgramIr currentRoot currentControls currentModules
  currentBindings <-
    mapLeft id
      ( uniqueSurfaceBindings
          ( concatMap
              (concatMap applicationSurfaceBindings . effectModuleApplications)
              currentModules
          )
      )
  let
      currentEvidence =
        concatMap
          (concatMap applicationSchemaEvidence . effectModuleApplications)
          currentModules
      currentSurface =
        SurfaceProgram
          { surfaceProgramPayload = currentIr
          , surfaceProgramBindings = currentBindings
          }
  currentElaborated <-
    mapLeft
      (map ProgramElaborationFailed)
      ( elaborateProgram
          (ElaborationInputs currentEvidence)
          currentSurface
      )
  currentGraphs <-
    mapLeft
      (map ProgramGraphFailed)
      ( compileGraphs
          (programIrEffects currentIr)
          (programIrTransforms currentIr)
          (programIrAst currentIr)
      )
  let currentEffSysErrors =
        validateEffSysReferences
          (programIrEffSysRegistry currentIr)
          (programIrEffects currentIr)
          currentGraphs
  if null currentEffSysErrors
    then pure ()
    else Left (map ProgramEffSysFailed currentEffSysErrors)
  currentContinuationPlan <-
    mapLeft
      (map ProgramContinuationFailed)
      (compileContinuationPlan currentGraphs)
  pure
    ( prepareRuntime
        Program
          { programSurface = currentSurface
          , programElaborated = currentElaborated
          , graphProgramOf = currentGraphs
          , programContinuationPlan = currentContinuationPlan
          }
    )

uniqueSurfaceBindings ::
  [(BindingKey, SurfaceBinding)] ->
  Either [ProgramError] [(BindingKey, SurfaceBinding)]
uniqueSurfaceBindings currentBindings
  | null currentErrors = Right [head currentGroup | currentGroup <- currentGroups]
  | otherwise = Left currentErrors
  where
    currentGroups = groupOn fst currentBindings
    currentErrors =
      [ SurfaceBindingConflict (fst (head currentGroup))
      | currentGroup <- currentGroups
      , length (nub (map snd currentGroup)) > 1
      ]

prepareRuntime :: Program -> PreparedRuntime
prepareRuntime currentProgram =
  PreparedRuntime
    { preparedRuntimeProgram = currentProgram
    , preparedRuntimeContinuationPlan = programContinuationPlan currentProgram
    }

runPreparedRuntime ::
  RuntimeHandlerRegistry ->
  PreparedRuntime ->
  IO (Either [RuntimePreparationError] UnifiedRuntimeRun)
runPreparedRuntime currentHandlers currentPrepared =
  executeRuntime
    (programIrEffects currentIr)
    (programIrAst currentIr)
    (graphProgramOf currentProgram)
    (preparedRuntimeContinuationPlan currentPrepared)
    currentHandlers
  where
    currentProgram = preparedRuntimeProgram currentPrepared
    currentIr = elaboratedProgramPayload (programElaborated currentProgram)

scopedEffSys ::
  EffSysRef ->
  PreparedRuntime ->
  Either [EffSysError] EffSysIR
scopedEffSys currentRef currentPrepared =
  buildEffSysIR
    (programIrEffSysRegistry currentIr)
    (programIrEffects currentIr)
    (programIrTransforms currentIr)
    (graphProgramOf currentProgram)
    (preparedRuntimeContinuationPlan currentPrepared)
    currentRef
  where
    currentProgram = preparedRuntimeProgram currentPrepared
    currentIr = elaboratedProgramPayload (programElaborated currentProgram)

validate :: PreparedRuntime -> [ProgramError]
validate _ = []

resolveAll :: PreparedRuntime -> AstPlan
resolveAll = programIrAst . elaboratedProgramPayload . programElaborated . preparedRuntimeProgram

programSchemaCatalog :: PreparedRuntime -> SchemaCatalog
programSchemaCatalog =
  elaboratedProgramSchemaCatalog
    . programElaborated
    . preparedRuntimeProgram

schemaCatalogOf :: PreparedRuntime -> SchemaCatalog
schemaCatalogOf = programSchemaCatalog

programSchemaDigest :: PreparedRuntime -> String
programSchemaDigest =
  elaboratedProgramSchemaDigest
    . programElaborated
    . preparedRuntimeProgram

effectRegistryOf :: PreparedRuntime -> EffectRegistry
effectRegistryOf =
  programIrEffects
    . elaboratedProgramPayload
    . programElaborated
    . preparedRuntimeProgram

transformRegistryOf :: PreparedRuntime -> TransformRegistry
transformRegistryOf =
  programIrTransforms
    . elaboratedProgramPayload
    . programElaborated
    . preparedRuntimeProgram

buildProgramIr ::
  Name ->
  [ControlDecl] ->
  [EffectModule] ->
  Either [ProgramError] ProgramIR
buildProgramIr currentRoot currentControls currentModules
  | not (null currentErrors) = Left currentErrors
  | otherwise =
      Right
        ProgramIR
          { programIrEffects = EffectRegistry uniqueEffects
          , programIrTransforms = TransformRegistry uniqueTransforms
          , programIrAst = resolveControl [] currentRoot
          , programIrEffSysRegistry = EffSysRegistryId (nameText currentRoot)
          }
  where
    controlIndex = Map.fromList [(controlName currentControl, currentControl) | currentControl <- currentControls]
    moduleIndex = Map.fromList [(effectModuleName currentModule, currentModule) | currentModule <- currentModules]
    duplicateControlErrors =
      [DuplicateControlName currentDuplicates | let currentDuplicates = duplicates (map controlName currentControls), not (null currentDuplicates)]
    duplicateModuleErrors =
      [DuplicateEffectModuleName currentDuplicates | let currentDuplicates = duplicates (map effectModuleName currentModules), not (null currentDuplicates)]
    duplicateApplicationErrors =
      [ DuplicateApplicationName
          (effectModuleName currentModule)
          currentDuplicates
      | currentModule <- currentModules
      , let currentDuplicates =
              duplicates
                (map applicationName (effectModuleApplications currentModule))
      , not (null currentDuplicates)
      ]
    rootErrors = [RootControlMissing currentRoot | Map.notMember currentRoot controlIndex]
    orphanErrors =
      [ EffectModuleWithoutControl (effectModuleName currentModule)
      | currentModule <- currentModules
      , Map.notMember (effectModuleName currentModule) controlIndex
      ]
    childErrors = concatMap validateChildren currentControls
    controlCycleErrors = map ControlReferenceCycle (controlCycles controlIndex)
    allEffects =
      concatMap
        (concatMap applicationEffectIR . effectModuleApplications)
        currentModules
    allTransforms =
      map applicationTransformIR
        (concatMap effectModuleApplications currentModules)
    (effectConflictErrors, uniqueEffects) =
      uniqueDefinitions
        (someEffectRefKey . effectIrRef)
        EffectDefinitionConflict
        allEffects
    (transformConflictErrors, uniqueTransforms) =
      uniqueDefinitions
        transformDeclRef
        TransformDefinitionConflict
        allTransforms
    currentErrors =
      sort . nub $
        duplicateControlErrors
          ++ duplicateModuleErrors
          ++ duplicateApplicationErrors
          ++ rootErrors
          ++ orphanErrors
          ++ childErrors
          ++ controlCycleErrors
          ++ effectConflictErrors
          ++ transformConflictErrors
    validateChildren currentControl =
      concatMap (validateChild currentControl) (controlChildren currentControl)
    validateChild currentControl currentChild =
      case (Map.member currentChild controlIndex, applicationInModule (controlName currentControl) currentChild) of
        (False, False) -> [ChildReferenceMissing (controlName currentControl) currentChild]
        (True, True) -> [ChildReferenceAmbiguous (controlName currentControl) currentChild]
        _ -> []
    applicationInModule currentModule currentChild =
      case Map.lookup currentModule moduleIndex of
        Nothing -> False
        Just currentEffectModule ->
          any ((== currentChild) . applicationName) (effectModuleApplications currentEffectModule)
    resolveControl currentStack currentName =
      case Map.lookup currentName controlIndex of
        Nothing -> AstPlanBranch (AstNodeKey (nameText currentName)) AstChain []
        Just currentControl ->
          AstPlanBranch
            (AstNodeKey (nameText currentName))
            (controlKind currentControl)
            [ if Map.member currentChild controlIndex
                then resolveControl (currentName : currentStack) currentChild
                else resolveApplication currentName currentChild
            | currentChild <- controlChildren currentControl
            ]
    resolveApplication currentModule currentChild =
      case
          [ currentApplication
          | currentEffectModule <- maybeToList (Map.lookup currentModule moduleIndex)
          , currentApplication <- effectModuleApplications currentEffectModule
          , applicationName currentApplication == currentChild
          ] of
        currentApplication : _ ->
          AstPlanApplication
            (AstNodeKey (nameText currentChild))
            (applicationIR currentApplication)
        [] -> AstPlanBranch (AstNodeKey (nameText currentChild)) AstChain []

qualifyApplication :: Name -> Application -> Application
qualifyApplication currentModule currentApplication =
  currentApplication
    { applicationIR = qualifyApplicationIr currentModule (applicationIR currentApplication)
    , applicationEffectIR = map (qualifyEffectIr currentModule) (applicationEffectIR currentApplication)
    , applicationTransformIR = qualifyTransform currentModule (applicationTransformIR currentApplication)
    , applicationSurfaceBindings =
        [ ( qualifyBindingKey currentModule currentKey
          , qualifySurfaceBinding currentModule currentBinding
          )
        | (currentKey, currentBinding) <- applicationSurfaceBindings currentApplication
        ]
    , applicationSchemaEvidence =
        [ currentEvidence
            { schemaEvidenceKey = qualifyBindingKey currentModule (schemaEvidenceKey currentEvidence)
            }
        | currentEvidence <- applicationSchemaEvidence currentApplication
        ]
    }

qualifyApplicationIr :: Name -> EffectApplication -> EffectApplication
qualifyApplicationIr currentModule currentApplication =
  currentApplication
    { effectApplicationKey =
        ApplicationKey
          (qualifiedText currentModule (applicationKeyText (effectApplicationKey currentApplication)))
    , effectApplicationCommand = qualifyRef currentModule (effectApplicationCommand currentApplication)
    , effectApplicationMap = qualifyRef currentModule (effectApplicationMap currentApplication)
    , effectApplicationRead = qualifyRef currentModule (effectApplicationRead currentApplication)
    }

qualifyEffectIr :: Name -> EffectIR -> EffectIR
qualifyEffectIr currentModule currentEffect =
  currentEffect
    { effectIrRef = qualifyRef currentModule (effectIrRef currentEffect)
    , effectIrInput = fmap (qualifyRef currentModule) (effectIrInput currentEffect)
    , effectIrSpec = qualifyEffectSpec currentModule (effectIrSpec currentEffect)
    }

qualifyEffectSpec :: Name -> EffectSpec -> EffectSpec
qualifyEffectSpec currentModule currentSpec =
  case currentSpec of
    CommandEffect currentCommand -> CommandEffect currentCommand
    MapEffect currentMap ->
      MapEffect
        currentMap
          { mapSpecTransform = qualifyTransformRef currentModule (mapSpecTransform currentMap)
          }
    ReadEffect currentRead ->
      ReadEffect
        currentRead
          { readSpecSource = qualifyValueSource currentModule (readSpecSource currentRead)
          }

qualifyValueSource :: Name -> ValueSourceSpec -> ValueSourceSpec
qualifyValueSource currentModule currentSource =
  case currentSource of
    ValueExternal currentName -> ValueExternal (qualifiedText currentModule currentName)
    ValueLiteral currentValue -> ValueLiteral currentValue
    ValueFromR currentRef -> ValueFromR (qualifyRef currentModule currentRef)
    ValueRecord currentFields ->
      ValueRecord [(currentName, qualifyValueSource currentModule currentChild) | (currentName, currentChild) <- currentFields]
    ValueProduct currentItems -> ValueProduct (map (qualifyValueSource currentModule) currentItems)
    ValueEffSysRef currentRef -> ValueEffSysRef currentRef

qualifyTransform :: Name -> TransformDecl -> TransformDecl
qualifyTransform currentModule currentTransform =
  currentTransform
    { transformDeclRef = qualifyTransformRef currentModule (transformDeclRef currentTransform)
    }

qualifyTransformRef :: Name -> TransformRef -> TransformRef
qualifyTransformRef currentModule currentRef =
  TransformRef (qualifiedText currentModule (transformRefKey currentRef))

qualifyRef :: Name -> SomeEffectRef -> SomeEffectRef
qualifyRef currentModule currentRef =
  currentRef
    { someEffectRefKey = qualifyEffectKey currentModule (someEffectRefKey currentRef)
    }

qualifyEffectKey :: Name -> EffectKey -> EffectKey
qualifyEffectKey currentModule currentKey =
  EffectKey (qualifiedText currentModule (effectKeyText currentKey))

qualifyBindingKey :: Name -> BindingKey -> BindingKey
qualifyBindingKey currentModule currentKey =
  BindingKey (qualifiedText currentModule (bindingKeyText currentKey))

qualifySurfaceBinding :: Name -> SurfaceBinding -> SurfaceBinding
qualifySurfaceBinding currentModule currentBinding =
  case currentBinding of
    SurfaceFromR currentKey -> SurfaceFromR (qualifyBindingKey currentModule currentKey)
    SurfaceFromMap currentKey -> SurfaceFromMap (qualifyBindingKey currentModule currentKey)
    SurfaceLiteral currentValue -> SurfaceLiteral currentValue
    SurfaceRecord currentFields ->
      SurfaceRecord [(currentName, qualifySurfaceBinding currentModule currentChild) | (currentName, currentChild) <- currentFields]
    SurfaceEvidence currentKey -> SurfaceEvidence (qualifyBindingKey currentModule currentKey)
    SurfaceOpaque currentKey -> SurfaceOpaque (qualifyBindingKey currentModule currentKey)
    SurfaceLegacy currentSchema currentChild -> SurfaceLegacy currentSchema (qualifySurfaceBinding currentModule currentChild)
    SurfaceEffSysRef currentKey -> SurfaceEffSysRef (qualifyBindingKey currentModule currentKey)

qualifiedText :: Name -> String -> String
qualifiedText currentModule currentLocal =
  show (length (nameText currentModule))
    ++ ":"
    ++ nameText currentModule
    ++ show (length currentLocal)
    ++ ":"
    ++ currentLocal

uniqueDefinitions ::
  (Ord key, Eq value) =>
  (value -> key) ->
  (key -> ProgramError) ->
  [value] ->
  ([ProgramError], [value])
uniqueDefinitions currentKey currentError currentValues =
  ( [ currentError (currentKey (head currentGroup))
    | currentGroup <- currentGroups
    , length (nub currentGroup) > 1
    ]
  , [head currentGroup | currentGroup <- currentGroups]
  )
  where
    currentGroups = groupOn currentKey currentValues

controlCycles :: Map.Map Name ControlDecl -> [[Name]]
controlCycles controlIndex =
  sort . nub $
    [ currentCycle
    | currentName <- Map.keys controlIndex
    , Just currentCycle <- [walk [] currentName]
    ]
  where
    walk currentPath currentName
      | currentName `elem` currentPath =
          Just (dropWhile (/= currentName) currentPath ++ [currentName])
      | otherwise =
          case Map.lookup currentName controlIndex of
            Nothing -> Nothing
            Just currentControl ->
              firstJust
                [ walk (currentPath ++ [currentName]) currentChild
                | currentChild <- controlChildren currentControl
                , Map.member currentChild controlIndex
                ]

firstJust :: [Maybe value] -> Maybe value
firstJust currentValues =
  case [currentValue | Just currentValue <- currentValues] of
    currentValue : _ -> Just currentValue
    [] -> Nothing

duplicates :: Ord value => [value] -> [value]
duplicates currentValues =
  [ head currentGroup
  | currentGroup <- group (sort currentValues)
  , length currentGroup > 1
  ]

groupOn :: Ord key => (value -> key) -> [value] -> [[value]]
groupOn currentKey =
  groupAdjacent . sortOn currentKey
  where
    groupAdjacent [] = []
    groupAdjacent (currentValue : remaining) =
      let (same, rest) = span ((== currentKey currentValue) . currentKey) remaining
       in (currentValue : same) : groupAdjacent rest

maybeToList :: Maybe value -> [value]
maybeToList Nothing = []
maybeToList (Just currentValue) = [currentValue]

mapLeft :: (left -> otherLeft) -> Either left right -> Either otherLeft right
mapLeft currentFunction currentValue =
  case currentValue of
    Left currentLeft -> Left (currentFunction currentLeft)
    Right currentRight -> Right currentRight
