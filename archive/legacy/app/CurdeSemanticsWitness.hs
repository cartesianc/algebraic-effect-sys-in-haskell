module Main (main) where

import Control.Monad (unless)
import Data.List (intercalate, isInfixOf, nub, sort)
import System.Exit (exitFailure)

import MyFramework
import MyFramework.Self.CoreModel
import MyFramework.TrustBase.FixedPoint (semanticWitnessValid)

data Check = Check
  { checkName :: String
  , checkPassed :: Bool
  , checkObserved :: String
  }

main :: IO ()
main =
  case frameworkAsBusiness of
    Left currentErrors -> do
      putStrLn (renderReport [Check "l0-v52-framework-builds" False (show currentErrors)] False)
      exitFailure
    Right currentFramework -> do
      let currentProgram = frameworkAsBusinessV52Program currentFramework
          currentEffects = effectRegistryEffects (effectRegistryOf currentProgram)
          currentKinds = sort (nub (map (someEffectRefKind . effectIrRef) currentEffects))
          currentGraphs = graphProgramOf (preparedRuntimeProgram currentProgram)
          currentAstEdges = astGraphEdges (compiledAstGraph currentGraphs)
          currentInputEdges = inputGraphEdges (compiledInputGraph currentGraphs)
          currentValueEdges = valueGraphEdges (compiledValueGraph currentGraphs)
          checks =
            [ Check
                "l0-v52-program-valid"
                (null (validate currentProgram))
                (show (validate currentProgram))
            , Check
                "l0-v52-schema-free-canonical-catalog"
                ( not (null (programSchemaDigest currentProgram))
                    && not ("SchemaIdentity" `isInfixOf` show (resolveAll currentProgram))
                )
                (programSchemaDigest currentProgram)
            , Check
                "l0-v52-effect-kinds-in-unified-registry"
                (all (`elem` [C, U, R, D, E, MAP]) currentKinds && R `elem` currentKinds && MAP `elem` currentKinds)
                (show currentKinds)
            , Check
                "l0-v52-command-map-r-applications"
                ( all applicationHasThreeEffects
                    (compiledOccurrences currentGraphs)
                )
                (show (compiledOccurrences currentGraphs))
            , Check
                "l0-v52-three-graphs-separated"
                ( not (null currentAstEdges)
                    && not (null currentValueEdges)
                    && all (not . inputLooksLikeAst) currentInputEdges
                )
                (show (length currentAstEdges, length currentInputEdges, length currentValueEdges))
            , Check
                "l0-v52-continuation-plan-serializable"
                (not (null (continuationPlanDigest (preparedRuntimeContinuationPlan currentProgram))))
                (continuationPlanDigest (preparedRuntimeContinuationPlan currentProgram))
            , Check
                "l0-v52-framework-encoding-has-no-legacy-program"
                (not ("ReferencedProgram" `isInfixOf` encodeFrameworkAsBusiness currentFramework))
                (frameworkAsBusinessSchema currentFramework)
            , Check
                "l0-v52-empty-business-is-zero-effect"
                ( case emptyBusinessProgram of
                    Right currentEmpty -> null (effectRegistryEffects (effectRegistryOf currentEmpty))
                    Left _ -> False
                )
                (show EmptyBusiness)
            ]
          succeeded = all checkPassed checks
          currentReport = renderReport checks succeeded
      putStrLn currentReport
      unless (succeeded && semanticWitnessValid currentReport) exitFailure

applicationHasThreeEffects :: ApplicationOccurrence -> Bool
applicationHasThreeEffects currentOccurrence =
  let currentApplication = applicationOccurrenceApplication currentOccurrence
   in someEffectRefKind (effectApplicationCommand currentApplication) `elem` [C, U, D, E]
        && someEffectRefKind (effectApplicationMap currentApplication) == MAP
        && someEffectRefKind (effectApplicationRead currentApplication) == R

inputLooksLikeAst :: InputEdge -> Bool
inputLooksLikeAst currentEdge =
  inputEdgePredecessor currentEdge == inputEdgeTarget currentEdge

renderReport :: [Check] -> Bool -> String
renderReport currentChecks succeeded =
  "{"
    ++ jsonField "schema" (jsonString "curde-semantics-report.v4")
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
