module Main (main) where

import Control.Monad
  ( unless )
import Data.List
  ( intercalate )
import System.Exit
  ( exitFailure )

import MyFramework.CURDE
  ( SchemaIdentity )
import MyFramework.Frontend
import MyFramework.Self.ControlTrace
  ( compileControlTrace
  , controlTraceConstructorWitness
  )
import MyFramework.Self.Model

data Check = Check
  { checkName :: String
  , checkPassed :: Bool
  , checkObserved :: String
  }

main :: IO ()
main =
  case selfModel of
    Left currentErrors -> do
      putStrLn
        ( renderReport
            [ Check
                "self-model-builds"
                False
                (show currentErrors)
            ]
            False
        )
      exitFailure
    Right currentModel -> do
      let currentProgram =
            selfModelProgram currentModel
          currentValidation =
            validateReferencedProgram currentProgram
          currentResolution =
            resolveProgram currentProgram
          currentKinds =
            [ effectDeclType currentEffect
            | currentModule <- referencedProgramEffects currentProgram
            , (_, currentEffect) <-
                effectRecordFields (effectModuleRecord currentModule)
            ]
          currentChecks =
            [ Check
                "l0-referenced-program-valid"
                (null currentValidation)
                (show currentValidation)
            , Check
                "l0-referenced-program-resolves"
                (either (const False) (const True) currentResolution)
                (show currentResolution)
            , Check
                "l0-module-local-effect-records"
                ( map effectModuleName
                    (referencedProgramEffects currentProgram)
                    == [ModuleName "source", ModuleName "sink"]
                )
                (show (referencedProgramEffects currentProgram))
            , Check
                "l0-r-is-separate"
                ( readRegistryFields
                    (referencedProgramReads currentProgram)
                    == [(selfReadUserKey, userSchema currentProgram)]
                )
                (show (referencedProgramReads currentProgram))
            , Check
                "l0-effect-kinds-cude-without-r"
                (all (`elem` currentKinds) [EffectC, EffectU, EffectD, EffectE])
                (show currentKinds)
            , Check
                "l0-self-model-text-roundtrip"
                (selfModelTextRoundTrip currentModel)
                (show (selfModelTextRoundTrip currentModel))
            , Check
                "l0-self-model-json-roundtrip"
                ( selfModelJsonRoundTrip currentModel
                    && not (null (canonicalSelfModelJson currentModel))
                )
                (show (selfModelJsonRoundTrip currentModel))
            , Check
                "l0-resolver-control-trace"
                ( controlTraceConstructorWitness
                    && either
                      (const False)
                      (const True)
                      (compileControlTrace currentModel)
                )
                (show (compileControlTrace currentModel))
            ]
          succeeded =
            all checkPassed currentChecks
      putStrLn (renderReport currentChecks succeeded)
      unless succeeded exitFailure

userSchema :: ReferencedProgram -> SchemaIdentity
userSchema currentProgram =
  case
      [ currentSchema
      | (currentKey, currentSchema) <-
          readRegistryFields (referencedProgramReads currentProgram)
      , currentKey == selfReadUserKey
      ] of
    currentSchema : _ ->
      currentSchema
    [] ->
      error "validated self model lost readUser schema"

renderReport :: [Check] -> Bool -> String
renderReport currentChecks succeeded =
  "{"
    ++ jsonField "schema" (jsonString "curde-semantics-report.v3")
    ++ ","
    ++ jsonField "result" (jsonString (if succeeded then "passed" else "failed"))
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
