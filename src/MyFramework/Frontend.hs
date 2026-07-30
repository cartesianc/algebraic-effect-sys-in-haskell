module MyFramework.Frontend
  ( SchemaIdentity (..)
  , SchemaShape (..)
  , FieldName (..)
  , scalarType
  , recordType
  , unitType
  , ModuleName (..)
  , LocalKey (..)
  , ReadKey (..)
  , ParamKey (..)
  , EffectType (..)
  , ParamLiteral (..)
  , ParamSource (..)
  , ParamBinding (..)
  , EffectDecl (..)
  , EffectRecord (..)
  , EffectModule (..)
  , ReadRegistry (..)
  , ControlKind (..)
  , ControlDecl (..)
  , ReferencedProgram (..)
  , EffectAddress (..)
  , ResolvedChild (..)
  , ModuleView (..)
  , OccurrencePath (..)
  , ResolvedNode (..)
  , FrontendError (..)
  , chain
  , parallel
  , fallback
  , race
  , effects
  , readRecord
  , referencedProgram
  , validateReferencedProgram
  , resolveModule
  , resolveProgram
  ) where

import Data.List
  ( group
  , nub
  , sort
  )
import qualified Data.Map.Strict as Map

import MyFramework.CURDE
  ( FieldName (..)
  , SchemaIdentity (..)
  , SchemaShape (..)
  )

scalarType :: String -> SchemaIdentity
scalarType currentName =
  SchemaIdentity currentName ScalarShape

recordType :: String -> [(FieldName, SchemaIdentity)] -> SchemaIdentity
recordType currentName currentFields =
  SchemaIdentity currentName (RecordShape currentFields)

unitType :: SchemaIdentity
unitType =
  SchemaIdentity "Unit" UnitShape

-- | A control declaration is also a module declaration. Module identity is
-- authored once here and is never copied into an effect key.
newtype ModuleName = ModuleName
  { moduleNameText :: String
  }
  deriving (Eq, Ord, Read, Show)

-- | An unqualified child key. Resolution decides whether the key names a
-- child module or an effect in the current module.
newtype LocalKey = LocalKey
  { localKeyText :: String
  }
  deriving (Eq, Ord, Read, Show)

-- | R belongs to an independent typed data registry, not to the CUDE action
-- input graph.
newtype ReadKey = ReadKey
  { readKeyText :: String
  }
  deriving (Eq, Ord, Read, Show)

newtype ParamKey = ParamKey
  { paramKeyText :: String
  }
  deriving (Eq, Ord, Read, Show)

-- | R is deliberately absent. Only C/U/D/E are executable action kinds.
data EffectType
  = EffectC
  | EffectU
  | EffectD
  | EffectE
  deriving (Eq, Ord, Read, Show)

data ParamLiteral
  = ParamText String
  | ParamInteger Integer
  | ParamBoolean Bool
  | ParamUnit
  deriving (Eq, Ord, Read, Show)

-- | Parameter expressions are closed serializable data. A read reference is
-- resolved lazily immediately before its owning effect is invoked.
data ParamSource
  = ParamFromRead ReadKey
  | ParamFromLiteral ParamLiteral
  | ParamFromRecord [(ParamKey, ParamBinding)]
  deriving (Eq, Ord, Read, Show)

data ParamBinding = ParamBinding
  { paramBindingSchema :: SchemaIdentity
  , paramBindingSource :: ParamSource
  }
  deriving (Eq, Ord, Read, Show)

-- | The record value contains no identity field. Its key in 'EffectRecord' is
-- the complete local effect identity.
data EffectDecl = EffectDecl
  { effectDeclType :: EffectType
  , effectDeclInput :: Maybe LocalKey
  , effectDeclParams :: [(ParamKey, ParamBinding)]
  }
  deriving (Eq, Ord, Read, Show)

newtype EffectRecord = EffectRecord
  { effectRecordFields :: [(LocalKey, EffectDecl)]
  }
  deriving (Eq, Ord, Read, Show)

data EffectModule = EffectModule
  { effectModuleName :: ModuleName
  , effectModuleRecord :: EffectRecord
  }
  deriving (Eq, Ord, Read, Show)

newtype ReadRegistry = ReadRegistry
  { readRegistryFields :: [(ReadKey, SchemaIdentity)]
  }
  deriving (Eq, Ord, Read, Show)

data ControlKind
  = ControlChain
  | ControlParallel
  | ControlFallback
  | ControlRace
  deriving (Eq, Ord, Read, Show)

-- | Each declaration is independently addressable. Children are references,
-- never embedded subtrees.
data ControlDecl = ControlDecl
  { controlDeclModule :: ModuleName
  , controlDeclKind :: ControlKind
  , controlDeclChildren :: [LocalKey]
  }
  deriving (Eq, Ord, Read, Show)

-- | This is an index/manifest, not a recursively nested Blueprint. Backends
-- may store every declaration separately and load it through a resolver.
data ReferencedProgram = ReferencedProgram
  { referencedProgramRoot :: ModuleName
  , referencedProgramControls :: [ControlDecl]
  , referencedProgramEffects :: [EffectModule]
  , referencedProgramReads :: ReadRegistry
  }
  deriving (Eq, Ord, Read, Show)

data EffectAddress = EffectAddress
  { effectAddressModule :: ModuleName
  , effectAddressKey :: LocalKey
  }
  deriving (Eq, Ord, Read, Show)

data ResolvedChild
  = ResolvedModule ModuleName
  | ResolvedEffect EffectAddress
  deriving (Eq, Ord, Read, Show)

data ModuleView = ModuleView
  { moduleViewName :: ModuleName
  , moduleViewKind :: ControlKind
  , moduleViewChildren :: [ResolvedChild]
  }
  deriving (Eq, Ord, Read, Show)

newtype OccurrencePath = OccurrencePath
  { occurrencePathSegments :: [String]
  }
  deriving (Eq, Ord, Read, Show)

data ResolvedNode
  = ResolvedControl
      OccurrencePath
      ModuleName
      ControlKind
      [ResolvedNode]
  | ResolvedEffectLeaf
      OccurrencePath
      EffectAddress
      EffectDecl
  deriving (Eq, Ord, Read, Show)

data FrontendError
  = DuplicateControlModule ModuleName
  | DuplicateEffectModule ModuleName
  | DuplicateEffectKey ModuleName LocalKey
  | DuplicateReadKey ReadKey
  | DuplicateParamKey ModuleName LocalKey [ParamKey] ParamKey
  | RootModuleMissing ModuleName
  | EffectModuleWithoutControl ModuleName
  | ChildReferenceMissing ModuleName LocalKey
  | ChildReferenceAmbiguous ModuleName LocalKey
  | ControlReferenceCycle [ModuleName]
  | EffectInputMissing ModuleName LocalKey LocalKey
  | EffectInputCycle ModuleName [LocalKey]
  | ParamReadMissing ModuleName LocalKey [ParamKey] ReadKey
  | ParamReadSchemaMismatch
      ModuleName
      LocalKey
      [ParamKey]
      ReadKey
      SchemaIdentity
      SchemaIdentity
  deriving (Eq, Ord, Read, Show)

chain :: ModuleName -> [LocalKey] -> ControlDecl
chain =
  ControlDecl `withKind` ControlChain

parallel :: ModuleName -> [LocalKey] -> ControlDecl
parallel =
  ControlDecl `withKind` ControlParallel

fallback :: ModuleName -> [LocalKey] -> ControlDecl
fallback =
  ControlDecl `withKind` ControlFallback

race :: ModuleName -> [LocalKey] -> ControlDecl
race =
  ControlDecl `withKind` ControlRace

withKind ::
  (ModuleName -> ControlKind -> [LocalKey] -> ControlDecl) ->
  ControlKind ->
  ModuleName ->
  [LocalKey] ->
  ControlDecl
withKind currentConstructor currentKind currentModule currentChildren =
  currentConstructor currentModule currentKind currentChildren

effects :: ModuleName -> [(LocalKey, EffectDecl)] -> EffectModule
effects currentModule currentFields =
  EffectModule
    { effectModuleName = currentModule
    , effectModuleRecord = EffectRecord currentFields
    }

readRecord :: [(ReadKey, SchemaIdentity)] -> ReadRegistry
readRecord =
  ReadRegistry

referencedProgram ::
  ModuleName ->
  [ControlDecl] ->
  [EffectModule] ->
  ReadRegistry ->
  ReferencedProgram
referencedProgram =
  ReferencedProgram

validateReferencedProgram :: ReferencedProgram -> [FrontendError]
validateReferencedProgram currentProgram =
  sort . nub $
    duplicateErrors
      ++ rootErrors
      ++ orphanEffectErrors
      ++ childErrors
      ++ controlCycleErrors
      ++ effectErrors
      ++ paramErrors
  where
    currentControls =
      referencedProgramControls currentProgram
    currentEffectModules =
      referencedProgramEffects currentProgram
    currentReads =
      readRegistryFields (referencedProgramReads currentProgram)
    controlMap =
      Map.fromList
        [ (controlDeclModule currentControl, currentControl)
        | currentControl <- currentControls
        ]
    effectModuleMap =
      Map.fromList
        [ (effectModuleName currentModule, effectModuleRecord currentModule)
        | currentModule <- currentEffectModules
        ]
    readMap =
      Map.fromList currentReads
    duplicateErrors =
      [ DuplicateControlModule currentModule
      | currentModule <-
          duplicateItems (map controlDeclModule currentControls)
      ]
        ++ [ DuplicateEffectModule currentModule
           | currentModule <-
               duplicateItems (map effectModuleName currentEffectModules)
           ]
        ++ concatMap duplicateEffectErrors currentEffectModules
        ++ [ DuplicateReadKey currentKey
           | currentKey <- duplicateItems (map fst currentReads)
           ]
    rootErrors =
      [ RootModuleMissing (referencedProgramRoot currentProgram)
      | Map.notMember (referencedProgramRoot currentProgram) controlMap
      ]
    orphanEffectErrors =
      [ EffectModuleWithoutControl currentModule
      | currentModule <- Map.keys effectModuleMap
      , Map.notMember currentModule controlMap
      ]
    childErrors =
      concatMap
        (validateChildren controlMap effectModuleMap)
        currentControls
    controlCycleErrors =
      map ControlReferenceCycle
        ( detectCycles
            (Map.keys controlMap)
            (controlChildren controlMap)
        )
    effectErrors =
      concatMap validateEffectModule currentEffectModules
    paramErrors =
      concatMap (validateModuleParams readMap) currentEffectModules

duplicateEffectErrors :: EffectModule -> [FrontendError]
duplicateEffectErrors currentModule =
  [ DuplicateEffectKey
      (effectModuleName currentModule)
      currentKey
  | currentKey <-
      duplicateItems
        (map fst (effectRecordFields (effectModuleRecord currentModule)))
  ]

validateChildren ::
  Map.Map ModuleName ControlDecl ->
  Map.Map ModuleName EffectRecord ->
  ControlDecl ->
  [FrontendError]
validateChildren controlMap effectModuleMap currentControl =
  concatMap validateChild (controlDeclChildren currentControl)
  where
    currentModule =
      controlDeclModule currentControl
    currentEffects =
      maybe [] effectRecordFields (Map.lookup currentModule effectModuleMap)
    effectKeys =
      map fst currentEffects
    validateChild currentKey =
      case
          ( Map.member (moduleFromLocal currentKey) controlMap
          , currentKey `elem` effectKeys
          ) of
        (False, False) ->
          [ChildReferenceMissing currentModule currentKey]
        (True, True) ->
          [ChildReferenceAmbiguous currentModule currentKey]
        _ ->
          []

controlChildren ::
  Map.Map ModuleName ControlDecl ->
  ModuleName ->
  [ModuleName]
controlChildren controlMap currentModule =
  case Map.lookup currentModule controlMap of
    Nothing ->
      []
    Just currentControl ->
      [ currentChildModule
      | currentKey <- controlDeclChildren currentControl
      , let currentChildModule = moduleFromLocal currentKey
      , Map.member currentChildModule controlMap
      ]

validateEffectModule :: EffectModule -> [FrontendError]
validateEffectModule currentModule =
  missingInputErrors ++ cycleErrors
  where
    currentName =
      effectModuleName currentModule
    currentFields =
      effectRecordFields (effectModuleRecord currentModule)
    currentKeys =
      map fst currentFields
    currentMap =
      Map.fromList currentFields
    missingInputErrors =
      [ EffectInputMissing currentName currentKey currentInput
      | (currentKey, currentEffect) <- currentFields
      , Just currentInput <- [effectDeclInput currentEffect]
      , currentInput `notElem` currentKeys
      ]
    cycleErrors =
      [ EffectInputCycle currentName currentCycle
      | currentCycle <-
          detectCycles
            currentKeys
            ( \currentKey ->
                case Map.lookup currentKey currentMap >>= effectDeclInput of
                  Nothing -> []
                  Just currentInput -> [currentInput]
            )
      ]

validateModuleParams ::
  Map.Map ReadKey SchemaIdentity ->
  EffectModule ->
  [FrontendError]
validateModuleParams readMap currentModule =
  concatMap validateOne currentFields
  where
    currentName =
      effectModuleName currentModule
    currentFields =
      effectRecordFields (effectModuleRecord currentModule)
    validateOne (currentEffectKey, currentEffect) =
      validateBindings
        readMap
        currentName
        currentEffectKey
        []
        (effectDeclParams currentEffect)

validateBindings ::
  Map.Map ReadKey SchemaIdentity ->
  ModuleName ->
  LocalKey ->
  [ParamKey] ->
  [(ParamKey, ParamBinding)] ->
  [FrontendError]
validateBindings
  readMap
  currentModule
  currentEffect
  currentPath
  currentBindings =
    duplicateParamErrors ++ concatMap validateBinding currentBindings
  where
    duplicateParamErrors =
      [ DuplicateParamKey
          currentModule
          currentEffect
          currentPath
          currentKey
      | currentKey <- duplicateItems (map fst currentBindings)
      ]
    validateBinding (currentKey, currentBinding) =
      case paramBindingSource currentBinding of
        ParamFromRead currentRead ->
          case Map.lookup currentRead readMap of
            Nothing ->
              [ ParamReadMissing
                  currentModule
                  currentEffect
                  (currentPath ++ [currentKey])
                  currentRead
              ]
            Just currentActualSchema
              | currentActualSchema /= paramBindingSchema currentBinding ->
                  [ ParamReadSchemaMismatch
                      currentModule
                      currentEffect
                      (currentPath ++ [currentKey])
                      currentRead
                      (paramBindingSchema currentBinding)
                      currentActualSchema
                  ]
              | otherwise ->
                  []
        ParamFromLiteral _ ->
          []
        ParamFromRecord currentChildren ->
          validateBindings
            readMap
            currentModule
            currentEffect
            (currentPath ++ [currentKey])
            currentChildren

resolveModule ::
  ReferencedProgram ->
  ModuleName ->
  Either [FrontendError] ModuleView
resolveModule currentProgram currentModule =
  case validateReferencedProgram currentProgram of
    [] ->
      resolveValidatedModule currentProgram currentModule
    currentErrors ->
      Left currentErrors

resolveValidatedModule ::
  ReferencedProgram ->
  ModuleName ->
  Either [FrontendError] ModuleView
resolveValidatedModule currentProgram currentModule =
  case Map.lookup currentModule controlMap of
    Nothing ->
      Left [RootModuleMissing currentModule]
    Just currentControl ->
      Right
        ModuleView
          { moduleViewName = currentModule
          , moduleViewKind = controlDeclKind currentControl
          , moduleViewChildren =
              map (resolveChild currentModule) (controlDeclChildren currentControl)
          }
  where
    controlMap =
      Map.fromList
        [ (controlDeclModule currentControl, currentControl)
        | currentControl <- referencedProgramControls currentProgram
        ]
    resolveChild parentModule currentKey
      | Map.member (moduleFromLocal currentKey) controlMap =
          ResolvedModule (moduleFromLocal currentKey)
      | otherwise =
          ResolvedEffect
            EffectAddress
              { effectAddressModule = parentModule
              , effectAddressKey = currentKey
              }

resolveProgram ::
  ReferencedProgram ->
  Either [FrontendError] ResolvedNode
resolveProgram currentProgram =
  case validateReferencedProgram currentProgram of
    [] ->
      Right
        (resolveControl rootPath (referencedProgramRoot currentProgram))
    currentErrors ->
      Left currentErrors
  where
    rootModule =
      referencedProgramRoot currentProgram
    rootPath =
      OccurrencePath [moduleNameText rootModule]
    controlMap =
      Map.fromList
        [ (controlDeclModule currentControl, currentControl)
        | currentControl <- referencedProgramControls currentProgram
        ]
    effectMap =
      Map.fromList
        [ ( effectAddress
              (effectModuleName currentModule)
              currentKey
          , currentEffect
          )
        | currentModule <- referencedProgramEffects currentProgram
        , (currentKey, currentEffect) <-
            effectRecordFields (effectModuleRecord currentModule)
        ]
    resolveControl currentPath currentModule =
      case Map.lookup currentModule controlMap of
        Nothing ->
          error "validated referenced program lost a control module"
        Just currentControl ->
          ResolvedControl
            currentPath
            currentModule
            (controlDeclKind currentControl)
            [ resolveChild currentPath currentModule currentKey
            | currentKey <- controlDeclChildren currentControl
            ]
    resolveChild currentPath currentModule currentKey =
      let
        childPath =
          appendOccurrence currentPath (localKeyText currentKey)
        childModule =
          moduleFromLocal currentKey
      in
        case Map.lookup childModule controlMap of
          Just _ ->
            resolveControl childPath childModule
          Nothing ->
            case
                Map.lookup
                  (effectAddress currentModule currentKey)
                  effectMap of
              Just currentEffect ->
                ResolvedEffectLeaf
                  childPath
                  (effectAddress currentModule currentKey)
                  currentEffect
              Nothing ->
                error "validated referenced program lost an effect"

effectAddress :: ModuleName -> LocalKey -> EffectAddress
effectAddress currentModule currentKey =
  EffectAddress
    { effectAddressModule = currentModule
    , effectAddressKey = currentKey
    }

appendOccurrence :: OccurrencePath -> String -> OccurrencePath
appendOccurrence (OccurrencePath currentSegments) currentSegment =
  OccurrencePath (currentSegments ++ [currentSegment])

moduleFromLocal :: LocalKey -> ModuleName
moduleFromLocal =
  ModuleName . localKeyText

duplicateItems :: Ord item => [item] -> [item]
duplicateItems currentItems =
  [ head currentGroup
  | currentGroup <- group (sort currentItems)
  , length currentGroup > 1
  ]

detectCycles ::
  Ord node =>
  [node] ->
  (node -> [node]) ->
  [[node]]
detectCycles currentNodes childrenOf =
  nub . sort $
    concatMap (walk []) currentNodes
  where
    walk currentPath currentNode =
      case break (== currentNode) currentPath of
        (_, _ : cycleTail) ->
          [cycleTail ++ [currentNode]]
        _ ->
          concatMap
            (walk (currentPath ++ [currentNode]))
            (childrenOf currentNode)
