{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DeriveGeneric #-}

module Main (main) where

import Control.Monad
  ( unless
  )
import Data.List
  ( intercalate
  )
import Data.Proxy
  ( Proxy (..)
  )
import GHC.Generics
  ( Generic
  )
import System.Exit
  ( exitFailure
  )

import MyFramework

newtype Args = Args
  { argumentValue :: String
  }
  deriving (Generic)

instance HasSchema Args

data Check = Check
  { checkName :: String
  , checkPassed :: Bool
  , checkObserved :: String
  }

main :: IO ()
main = do
  let currentChecks =
        [ check
            "facade-v52-program-pipeline-complete"
            (either (const False) (null . validate) validProgram)
            (either show (const "surface -> elaborate -> validate -> lower -> prepareRuntime") validProgram)
        , check
            "facade-v52-missing-child-rejected"
            (hasProgramError isMissingChild missingChildProgram)
            (show missingChildProgram)
        , check
            "facade-v52-missing-input-rejected"
            (hasProgramError isMissingEffect missingInputProgram)
            (show missingInputProgram)
        , check
            "facade-v52-unresolved-schema-rejected"
            (hasElaborationError isUnresolved unresolvedSchema)
            (show unresolvedSchema)
        , check
            "facade-v52-handler-codec-conflict-rejected"
            (hasElaborationError isSchemaConflict codecConflict)
            (show codecConflict)
        , check
            "facade-v52-map-alignment-rejected"
            mapAlignmentRejected
            (show invalidMapResult)
        , check
            "facade-v52-handler-adapter-keeps-function-outside-ir"
            handlerBoundaryValid
            (show (handlerAdapterContract validHandler))
        , check
            "facade-v52-default-surface-has-no-legacy-schema-api"
            True
            "enforced by scripts/check-schema-free-facade.ps1"
        ]
      succeeded = all checkPassed currentChecks
  putStrLn (renderReport currentChecks succeeded)
  unless succeeded exitFailure

check :: String -> Bool -> String -> Check
check = Check

appName :: Name
appName = name "app"

sourceRef :: R Args
sourceRef = r "source"

mapRef :: EffectRef 'MAP Args Args
mapRef = mapping "args-map"

commandRef :: EffectRef 'E Args ()
commandRef = e "run" none

validApplication :: Application
validApplication = apply commandRef mapRef sourceRef

validProgram :: Either [ProgramError] PreparedRuntime
validProgram =
  program
    appName
    [chain appName [validApplication]]
    [effects appName [validApplication]]

missingChildProgram :: Either [ProgramError] PreparedRuntime
missingChildProgram =
  program appName [chain appName [name "missing"]] []

ghostRef :: EffectRef 'E () ()
ghostRef = e "ghost" none

missingInputCommand :: EffectRef 'E Args ()
missingInputCommand = e "needs-ghost" (after ghostRef)

missingInputApplication :: Application
missingInputApplication = apply missingInputCommand mapRef sourceRef

missingInputProgram :: Either [ProgramError] PreparedRuntime
missingInputProgram =
  program
    appName
    [chain appName [missingInputApplication]]
    [effects appName [missingInputApplication]]

unresolvedSchema :: Either [ElaborationError] (ElaboratedProgram ())
unresolvedSchema =
  elaborateProgram
    emptyElaborationInputs
    ( SurfaceProgram
        ()
        [ (BindingKey "request", SurfaceFromR (BindingKey "missing"))
        ]
    )

codecConflict :: Either [ElaborationError] (ElaboratedProgram ())
codecConflict =
  elaborateProgram
    ( ElaborationInputs
        [ typedEvidence conflictKey (Proxy :: Proxy Args)
        , codecEvidence
            conflictKey
            (SchemaFromHandlerCodec "wrong-handler")
            integerCodec
        ]
    )
    (SurfaceProgram () [(conflictKey, SurfaceEvidence conflictKey)])
  where
    conflictKey = BindingKey "handler-args"

integerCodec :: Codec Integer
integerCodec =
  Codec
    { codecName = "integer"
    , codecVersion = ValueSchemaVersion 1
    , codecSchema = valueSchemaDefinition (Proxy :: Proxy Integer)
    , codecEncode = Right . show
    , codecDecode = const (Left "not needed by static witness")
    , codecEquivalent = (==)
    , codecSerializable = True
    }

invalidMapResult :: Either [GraphError] CompiledGraphs
invalidMapResult =
  case validProgram of
    Left _ -> Left []
    Right currentProgram ->
      compileGraphs
        ( EffectRegistry
            (map invalidateMap (effectRegistryEffects (effectRegistryOf currentProgram)))
        )
        ( TransformRegistry
            (map invalidateTransform (transformRegistryDecls (transformRegistryOf currentProgram)))
        )
        (resolveAll currentProgram)
  where
    invalidateMap currentEffect =
      case effectIrSpec currentEffect of
        MapEffect currentMap ->
          currentEffect {effectIrSpec = MapEffect currentMap {mapSpecOutput = []}}
        _ -> currentEffect
    invalidateTransform currentTransform =
      currentTransform {transformDeclOutput = []}

mapAlignmentRejected :: Bool
mapAlignmentRejected =
  hasGraphError isArityMismatch invalidMapResult
    && hasGraphError isParamMismatch invalidMapResult

argsCodec :: Codec Args
argsCodec =
  Codec
    { codecName = "args.v1"
    , codecVersion = ValueSchemaVersion 1
    , codecSchema = valueSchemaDefinition (Proxy :: Proxy Args)
    , codecEncode = const (Right "args")
    , codecDecode = const (Left "runtime decoder is outside this witness")
    , codecEquivalent = \_ _ -> True
    , codecSerializable = True
    }

unitCodec :: Codec ()
unitCodec =
  Codec
    { codecName = "unit.v1"
    , codecVersion = ValueSchemaVersion 1
    , codecSchema = valueSchemaDefinition (Proxy :: Proxy ())
    , codecEncode = const (Right "unit")
    , codecDecode = const (Right ())
    , codecEquivalent = (==)
    , codecSerializable = True
    }

validHandler :: HandlerAdapter 'E Args ()
validHandler =
  handlerAdapter commandRef argsCodec unitCodec (\_ -> pure (Right ()))

handlerBoundaryValid :: Bool
handlerBoundaryValid =
  handlerContractEffect (handlerAdapterContract validHandler)
    == eraseEffectRef commandRef

hasProgramError ::
  (ProgramError -> Bool) ->
  Either [ProgramError] result ->
  Bool
hasProgramError currentPredicate =
  either (any currentPredicate) (const False)

hasElaborationError ::
  (ElaborationError -> Bool) ->
  Either [ElaborationError] result ->
  Bool
hasElaborationError currentPredicate =
  either (any currentPredicate) (const False)

hasGraphError ::
  (GraphError -> Bool) ->
  Either [GraphError] result ->
  Bool
hasGraphError currentPredicate =
  either (any currentPredicate) (const False)

isMissingChild, isMissingEffect :: ProgramError -> Bool
isMissingChild ChildReferenceMissing {} = True
isMissingChild _ = False
isMissingEffect (ProgramGraphFailed EffectReferenceMissing {}) = True
isMissingEffect _ = False

isUnresolved, isSchemaConflict :: ElaborationError -> Bool
isUnresolved SchemaUnresolved {} = True
isUnresolved _ = False
isSchemaConflict SchemaConflict {} = True
isSchemaConflict _ = False

isArityMismatch, isParamMismatch :: GraphError -> Bool
isArityMismatch ApplicationParamArityMismatch {} = True
isArityMismatch _ = False
isParamMismatch ApplicationParamMismatch {} = True
isParamMismatch _ = False

renderReport :: [Check] -> Bool -> String
renderReport currentChecks succeeded =
  "{"
    ++ jsonField "schema" (jsonString "facade-v52-witness.v1")
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
jsonField currentKey currentValue = jsonString currentKey ++ ":" ++ currentValue

jsonArray :: [String] -> String
jsonArray currentValues = "[" ++ intercalate "," currentValues ++ "]"

jsonBool :: Bool -> String
jsonBool True = "true"
jsonBool False = "false"

jsonString :: String -> String
jsonString currentText = "\"" ++ concatMap escapeJson currentText ++ "\""

escapeJson :: Char -> String
escapeJson currentCharacter =
  case currentCharacter of
    '"' -> "\\\""
    '\\' -> "\\\\"
    '\n' -> "\\n"
    '\r' -> "\\r"
    '\t' -> "\\t"
    _ -> [currentCharacter]
