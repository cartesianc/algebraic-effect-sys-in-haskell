module Main (main) where

import Control.Monad
  ( unless )
import Data.List
  ( intercalate )
import System.Exit
  ( exitFailure )
import Text.Read
  ( readMaybe )

import MyFramework.CURDE
  ( scalarSchema
  , schemaRefIdentityOf
  )
import MyFramework.Legacy.Migration

data Check = Check
  { checkName :: String
  , checkPassed :: Bool
  , checkObserved :: String
  }

main :: IO ()
main = do
  let currentChecks =
        [ checkValidProgram
        , checkRootViewIsShallow
        , checkNestedViewsResolveByReference
        , checkOccurrencePath
        , checkRoundTrip
        , checkLocalEffectIdentity
        , checkAmbiguityRejected
        , checkMissingChildRejected
        , checkControlCycleRejected
        , checkMissingInputRejected
        , checkReadSchemaMismatchRejected
        , checkDuplicateEffectRejected
        , checkActionKindsExcludeR
        ]
      succeeded =
        all checkPassed currentChecks
  putStrLn (renderReport currentChecks succeeded)
  unless succeeded exitFailure

checkValidProgram :: Check
checkValidProgram =
  check
    "referenced-frontend-valid"
    (null (validateReferencedProgram validProgram))
    (show (validateReferencedProgram validProgram))

checkRootViewIsShallow :: Check
checkRootViewIsShallow =
  check
    "root-view-resolves-direct-references-only"
    expected
    (show currentView)
  where
    currentView =
      resolveModule validProgram appModule
    expected =
      currentView
        == Right
          ModuleView
            { moduleViewName = appModule
            , moduleViewKind = ControlChain
            , moduleViewChildren =
                [ ResolvedModule aModule
                , ResolvedEffect (EffectAddress appModule bKey)
                , ResolvedEffect (EffectAddress appModule fooKey)
                , ResolvedEffect (EffectAddress appModule foo2Key)
                ]
            }

checkNestedViewsResolveByReference :: Check
checkNestedViewsResolveByReference =
  check
    "nested-module-views-resolve-on-demand"
    expected
    (show (aView, a1View))
  where
    aView =
      resolveModule validProgram aModule
    a1View =
      resolveModule validProgram a1Module
    expected =
      fmap moduleViewKind aView == Right ControlParallel
        && fmap moduleViewKind a1View == Right ControlFallback
        && fmap moduleViewChildren a1View
          == Right
            [ ResolvedEffect (EffectAddress a1Module b1Key)
            , ResolvedEffect (EffectAddress a1Module b2Key)
            ]

checkOccurrencePath :: Check
checkOccurrencePath =
  check
    "effect-occurrence-path-preserves-reference-hierarchy"
    (expectedPath `elem` effectPaths)
    (show effectPaths)
  where
    effectPaths =
      case resolveProgram validProgram of
        Left _ -> []
        Right currentRoot -> collectEffectPaths currentRoot
    expectedPath =
      OccurrencePath ["app", "a", "a1", "b1"]

checkRoundTrip :: Check
checkRoundTrip =
  check
    "referenced-program-serializable-roundtrip"
    (readMaybe (show validProgram) == Just validProgram)
    (show (length (show validProgram)))

checkLocalEffectIdentity :: Check
checkLocalEffectIdentity =
  check
    "effect-keys-are-module-local"
    (null (validateReferencedProgram sharedLocalKeyProgram))
    (show (validateReferencedProgram sharedLocalKeyProgram))

checkAmbiguityRejected :: Check
checkAmbiguityRejected =
  check
    "module-effect-key-ambiguity-rejected"
    (ChildReferenceAmbiguous appModule aKey `elem` currentErrors)
    (show currentErrors)
  where
    currentErrors =
      validateReferencedProgram ambiguousProgram

checkMissingChildRejected :: Check
checkMissingChildRejected =
  check
    "missing-child-reference-rejected"
    (ChildReferenceMissing appModule missingKey `elem` currentErrors)
    (show currentErrors)
  where
    currentErrors =
      validateReferencedProgram missingChildProgram

checkControlCycleRejected :: Check
checkControlCycleRejected =
  check
    "control-reference-cycle-rejected"
    (any isControlCycle currentErrors)
    (show currentErrors)
  where
    currentErrors =
      validateReferencedProgram controlCycleProgram
    isControlCycle currentError =
      case currentError of
        ControlReferenceCycle _ -> True
        _ -> False

checkMissingInputRejected :: Check
checkMissingInputRejected =
  check
    "cross-module-or-missing-input-rejected"
    ( EffectInputMissing appModule fooKey a2Key
        `elem` currentErrors
    )
    (show currentErrors)
  where
    currentErrors =
      validateReferencedProgram missingInputProgram

checkReadSchemaMismatchRejected :: Check
checkReadSchemaMismatchRejected =
  check
    "read-parameter-schema-mismatch-rejected"
    (any isSchemaMismatch currentErrors)
    (show currentErrors)
  where
    currentErrors =
      validateReferencedProgram mismatchedReadProgram
    isSchemaMismatch currentError =
      case currentError of
        ParamReadSchemaMismatch {} -> True
        _ -> False

checkDuplicateEffectRejected :: Check
checkDuplicateEffectRejected =
  check
    "duplicate-local-effect-key-rejected"
    (DuplicateEffectKey appModule fooKey `elem` currentErrors)
    (show currentErrors)
  where
    currentErrors =
      validateReferencedProgram duplicateEffectProgram

checkActionKindsExcludeR :: Check
checkActionKindsExcludeR =
  check
    "action-kind-is-cude-without-r"
    (roundTrip [EffectC, EffectU, EffectD, EffectE])
    (show [EffectC, EffectU, EffectD, EffectE])

check :: String -> Bool -> String -> Check
check =
  Check

roundTrip :: (Eq value, Read value, Show value) => value -> Bool
roundTrip currentValue =
  readMaybe (show currentValue) == Just currentValue

collectEffectPaths :: ResolvedNode -> [OccurrencePath]
collectEffectPaths currentNode =
  case currentNode of
    ResolvedControl _ _ _ currentChildren ->
      concatMap collectEffectPaths currentChildren
    ResolvedEffectLeaf currentPath _ _ ->
      [currentPath]

validProgram :: ReferencedProgram
validProgram =
  referencedProgram
    appModule
    [ chain appModule [aKey, bKey, fooKey, foo2Key]
    , parallel aModule [a1Key, a2Key, a3Key]
    , fallback a1Module [b1Key, b2Key]
    ]
    [ effects
        appModule
        [ (bKey, action EffectE Nothing [])
        , ( fooKey
          , action
              EffectC
              (Just bKey)
              [ readParam "value" fooSchema sourceFooRead
              ]
          )
        , ( foo2Key
          , action
              EffectE
              (Just fooKey)
              [ readParam "value" fooSchema sourceFooRead
              ]
          )
        ]
    , effects
        aModule
        [ (a2Key, action EffectE Nothing [])
        , (a3Key, action EffectE (Just a2Key) [])
        ]
    , effects
        a1Module
        [ ( b1Key
          , action
              EffectE
              Nothing
              [readParam "value" valueSchema sourceValueRead]
          )
        , ( b2Key
          , action
              EffectE
              (Just b1Key)
              [readParam "value" valueSchema sourceValueRead]
          )
        ]
    ]
    ( readRecord
        [ (sourceFooRead, fooSchema)
        , (sourceValueRead, valueSchema)
        ]
    )

sharedLocalKeyProgram :: ReferencedProgram
sharedLocalKeyProgram =
  validProgram
    { referencedProgramEffects =
        replaceEffectModule
          aModule
          (effects aModule [(a2Key, action EffectE Nothing []), (a3Key, action EffectE (Just a2Key) []), (fooKey, action EffectU Nothing [])])
          (referencedProgramEffects validProgram)
    }

ambiguousProgram :: ReferencedProgram
ambiguousProgram =
  validProgram
    { referencedProgramEffects =
        replaceEffectModule
          appModule
          ( effects
              appModule
              ( (aKey, action EffectE Nothing [])
                  : effectFieldsFor appModule validProgram
              )
          )
          (referencedProgramEffects validProgram)
    }

missingChildProgram :: ReferencedProgram
missingChildProgram =
  validProgram
    { referencedProgramControls =
        replaceControl
          appModule
          (chain appModule [aKey, bKey, fooKey, foo2Key, missingKey])
          (referencedProgramControls validProgram)
    }

controlCycleProgram :: ReferencedProgram
controlCycleProgram =
  validProgram
    { referencedProgramControls =
        replaceControl
          a1Module
          (fallback a1Module [appKey, b1Key, b2Key])
          (referencedProgramControls validProgram)
    }

missingInputProgram :: ReferencedProgram
missingInputProgram =
  validProgram
    { referencedProgramEffects =
        replaceEffectModule
          appModule
          ( effects
              appModule
              [ (bKey, action EffectE Nothing [])
              , (fooKey, action EffectC (Just a2Key) [])
              , (foo2Key, action EffectE (Just fooKey) [])
              ]
          )
          (referencedProgramEffects validProgram)
    }

mismatchedReadProgram :: ReferencedProgram
mismatchedReadProgram =
  validProgram
    { referencedProgramReads =
        readRecord
          [ (sourceFooRead, valueSchema)
          , (sourceValueRead, valueSchema)
          ]
    }

duplicateEffectProgram :: ReferencedProgram
duplicateEffectProgram =
  validProgram
    { referencedProgramEffects =
        replaceEffectModule
          appModule
          ( effects
              appModule
              ( (fooKey, action EffectE Nothing [])
                  : effectFieldsFor appModule validProgram
              )
          )
          (referencedProgramEffects validProgram)
    }

action ::
  EffectType ->
  Maybe LocalKey ->
  [(ParamKey, ParamBinding)] ->
  EffectDecl
action currentType currentInput currentParams =
  EffectDecl
    { effectDeclType = currentType
    , effectDeclInput = currentInput
    , effectDeclParams = currentParams
    }

readParam ::
  String ->
  SchemaIdentity ->
  ReadKey ->
  (ParamKey, ParamBinding)
readParam currentName currentSchema currentRead =
  ( ParamKey currentName
  , ParamBinding
      { paramBindingSchema = currentSchema
      , paramBindingSource = ParamFromRead currentRead
      }
  )

replaceControl ::
  ModuleName ->
  ControlDecl ->
  [ControlDecl] ->
  [ControlDecl]
replaceControl currentName replacement =
  map
    ( \currentControl ->
        if controlDeclModule currentControl == currentName
          then replacement
          else currentControl
    )

replaceEffectModule ::
  ModuleName ->
  EffectModule ->
  [EffectModule] ->
  [EffectModule]
replaceEffectModule currentName replacement =
  map
    ( \currentModule ->
        if effectModuleName currentModule == currentName
          then replacement
          else currentModule
    )

effectFieldsFor ::
  ModuleName ->
  ReferencedProgram ->
  [(LocalKey, EffectDecl)]
effectFieldsFor currentName currentProgram =
  case
      [ effectRecordFields (effectModuleRecord currentModule)
      | currentModule <- referencedProgramEffects currentProgram
      , effectModuleName currentModule == currentName
      ] of
    currentFields : _ -> currentFields
    [] -> []

appModule, aModule, a1Module :: ModuleName
appModule = ModuleName "app"
aModule = ModuleName "a"
a1Module = ModuleName "a1"

appKey, aKey, a1Key, a2Key, a3Key :: LocalKey
appKey = LocalKey "app"
aKey = LocalKey "a"
a1Key = LocalKey "a1"
a2Key = LocalKey "a2"
a3Key = LocalKey "a3"

bKey, fooKey, foo2Key, b1Key, b2Key, missingKey :: LocalKey
bKey = LocalKey "b"
fooKey = LocalKey "foo"
foo2Key = LocalKey "foo2"
b1Key = LocalKey "b1"
b2Key = LocalKey "b2"
missingKey = LocalKey "missing"

sourceFooRead, sourceValueRead :: ReadKey
sourceFooRead = ReadKey "sourceFoo"
sourceValueRead = ReadKey "sourceValue"

fooSchema, valueSchema :: SchemaIdentity
fooSchema = schemaRefIdentityOf (scalarSchema "Foo")
valueSchema = schemaRefIdentityOf (scalarSchema "Value")

renderReport :: [Check] -> Bool -> String
renderReport currentChecks succeeded =
  "{"
    ++ jsonField "schema" (jsonString "referenced-frontend-witness.v1")
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
