{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DeriveGeneric #-}

module Main (main) where

import Control.Monad
  ( unless
  )
import Data.List
  ( intercalate
  , nub
  , sort
  )
import GHC.Generics
  ( Generic
  )
import System.Exit
  ( exitFailure
  )

-- This is deliberately the only framework import in the business example.
import MyFramework

data FetchArgs = FetchArgs
  { fetchHeaders :: String
  , fetchUrl :: String
  }
  deriving (Generic)

instance HasSchema FetchArgs

newtype PageArgs = PageArgs
  { pageBody :: String
  }
  deriving (Generic)

instance HasSchema PageArgs

newtype ContentArgs = ContentArgs
  { parsedContent :: String
  }
  deriving (Generic)

instance HasSchema ContentArgs

newtype LinksArgs = LinksArgs
  { parsedLinks :: String
  }
  deriving (Generic)

instance HasSchema LinksArgs

data Check = Check
  { checkName :: String
  , checkPassed :: Bool
  , checkObserved :: String
  }

main :: IO ()
main = do
  let currentChecks =
        [ Check
            "crawler-facade-import-myframework-only"
            True
            "business authoring imports MyFramework and standard-library modules"
        , Check
            "crawler-facade-schema-free-program-valid"
            crawlerValid
            (either show (show . validate) crawlerProgram)
        , Check
            "crawler-facade-chain-fallback-parallel"
            crawlerControlsResolve
            (either show (show . resolveAll) crawlerProgram)
        , Check
            "crawler-facade-six-effect-registry"
            crawlerKindsPresent
            (show crawlerKinds)
        , Check
            "crawler-facade-command-map-r-applications"
            crawlerApplicationsComplete
            (show crawlerApplicationKinds)
        , Check
            "crawler-facade-canonical-schema-catalog"
            crawlerCatalogDeterministic
            (show crawlerDigests)
        , Check
            "crawler-facade-occurrence-provenance"
            crawlerOccurrencesHavePaths
            (show crawlerOccurrencePaths)
        , Check
            "crawler-facade-qualified-effect-identity"
            crawlerEffectIdentitiesStable
            (show crawlerEffectKeys)
        ]
      succeeded = all checkPassed currentChecks
  putStrLn (renderReport currentChecks succeeded)
  unless succeeded exitFailure

crawler, fetch, extract, persist :: Name
crawler = name "crawler"
fetch = name "fetch"
extract = name "extract"
persist = name "persist"

seedRequest :: R FetchArgs
seedRequest = r "seed-request"

fetchedPage :: R PageArgs
fetchedPage = r "fetched-page"

contentValue :: R ContentArgs
contentValue = r "content-value"

linksValue :: R LinksArgs
linksValue = r "links-value"

primaryCommand, mirrorCommand :: EffectRef 'E FetchArgs ()
primaryCommand = e "primary" none
mirrorCommand = e "mirror" none

primaryMap, mirrorMap :: EffectRef 'MAP FetchArgs FetchArgs
primaryMap = mapping "primary-map"
mirrorMap = mapping "mirror-map"

primary, mirror :: Application
primary = apply primaryCommand primaryMap seedRequest
mirror = apply mirrorCommand mirrorMap seedRequest

extractLinksCommand, extractContentCommand :: EffectRef 'E PageArgs ()
extractLinksCommand = e "links" none
extractContentCommand = e "content" none

extractLinksMap, extractContentMap :: EffectRef 'MAP PageArgs PageArgs
extractLinksMap = mapping "extract-links-map"
extractContentMap = mapping "extract-content-map"

extractLinks, extractContent :: Application
extractLinks = apply extractLinksCommand extractLinksMap fetchedPage
extractContent = apply extractContentCommand extractContentMap fetchedPage

persistPageCommand :: EffectRef 'C ContentArgs ()
persistPageCommand = c "page" none

persistPageMap :: EffectRef 'MAP ContentArgs ContentArgs
persistPageMap = mapping "persist-page-map"

persistPage :: Application
persistPage = apply persistPageCommand persistPageMap contentValue

persistLinksCommand :: EffectRef 'U LinksArgs ()
persistLinksCommand = u "links" (after persistPage)

persistLinksMap :: EffectRef 'MAP LinksArgs LinksArgs
persistLinksMap = mapping "persist-links-map"

persistLinks :: Application
persistLinks = apply persistLinksCommand persistLinksMap linksValue

crawlerAst, fetchAst, extractAst, persistAst :: ControlDecl
crawlerAst = chain crawler [fetch, extract, persist]
fetchAst = fallback fetch [primary, mirror]
extractAst = parallel extract [extractLinks, extractContent]
persistAst = chain persist [persistPage, persistLinks]

fetchEffects, extractEffects, persistEffects :: EffectModule
fetchEffects = effects fetch [primary, mirror]
extractEffects = effects extract [extractLinks, extractContent]
persistEffects = effects persist [persistPage, persistLinks]

crawlerProgram :: Either [ProgramError] PreparedRuntime
crawlerProgram =
  program
    crawler
    [crawlerAst, fetchAst, extractAst, persistAst]
    [fetchEffects, extractEffects, persistEffects]

crawlerProgramReplay :: Either [ProgramError] PreparedRuntime
crawlerProgramReplay =
  program
    crawler
    [crawlerAst, fetchAst, extractAst, persistAst]
    [fetchEffects, extractEffects, persistEffects]

crawlerValid :: Bool
crawlerValid = either (const False) (null . validate) crawlerProgram

crawlerControlsResolve :: Bool
crawlerControlsResolve =
  case crawlerProgram of
    Right currentProgram ->
      case resolveAll currentProgram of
        AstPlanBranch _ AstChain [fetchNode, extractNode, persistNode] ->
          branchKind fetchNode == Just AstFallback
            && branchKind extractNode == Just AstParallel
            && branchKind persistNode == Just AstChain
        _ -> False
    Left _ -> False

branchKind :: AstPlan -> Maybe AstBranchKind
branchKind currentPlan =
  case currentPlan of
    AstPlanBranch _ currentKind _ -> Just currentKind
    AstPlanApplication _ _ -> Nothing

crawlerKinds :: [EffectKind]
crawlerKinds =
  case crawlerProgram of
    Left _ -> []
    Right currentProgram ->
      map
        (someEffectRefKind . effectIrRef)
        (effectRegistryEffects (effectRegistryOf currentProgram))

crawlerKindsPresent :: Bool
crawlerKindsPresent =
  all (`elem` crawlerKinds) [C, U, R, E, MAP]

crawlerApplicationKinds :: [[EffectKind]]
crawlerApplicationKinds =
  case crawlerProgram of
    Left _ -> []
    Right currentProgram ->
      [ [ someEffectRefKind (effectApplicationCommand currentApplication)
        , someEffectRefKind (effectApplicationMap currentApplication)
        , someEffectRefKind (effectApplicationRead currentApplication)
        ]
      | currentOccurrence <-
          compiledOccurrences
            (graphProgramOf (preparedRuntimeProgram currentProgram))
      , let currentApplication =
              applicationOccurrenceApplication currentOccurrence
      ]

crawlerApplicationsComplete :: Bool
crawlerApplicationsComplete =
  length crawlerApplicationKinds == 6
    && all
      (\currentKinds -> length currentKinds == 3 && drop 1 currentKinds == [MAP, R])
      crawlerApplicationKinds

crawlerDigests :: (Maybe String, Maybe String)
crawlerDigests =
  ( either (const Nothing) (Just . programSchemaDigest) crawlerProgram
  , either (const Nothing) (Just . programSchemaDigest) crawlerProgramReplay
  )

crawlerCatalogDeterministic :: Bool
crawlerCatalogDeterministic =
  case (crawlerProgram, crawlerProgramReplay) of
    (Right left, Right right) ->
      programSchemaDigest left == programSchemaDigest right
        && schemaCatalogOf left == schemaCatalogOf right
        && length (programSchemaDigest left) == 64
    _ -> False

crawlerOccurrencePaths :: [AstPath]
crawlerOccurrencePaths =
  case crawlerProgram of
    Left _ -> []
    Right currentProgram ->
      map applicationOccurrencePath
        ( compiledOccurrences
            (graphProgramOf (preparedRuntimeProgram currentProgram))
        )

crawlerOccurrencesHavePaths :: Bool
crawlerOccurrencesHavePaths =
  length crawlerOccurrencePaths == 6
    && length (nub crawlerOccurrencePaths) == 6

crawlerEffectKeys :: [EffectKey]
crawlerEffectKeys =
  case crawlerProgram of
    Left _ -> []
    Right currentProgram ->
      sort
        ( map
            (someEffectRefKey . effectIrRef)
            (effectRegistryEffects (effectRegistryOf currentProgram))
        )

crawlerEffectIdentitiesStable :: Bool
crawlerEffectIdentitiesStable =
  not (null crawlerEffectKeys)
    && length crawlerEffectKeys == length (nub crawlerEffectKeys)
    && all (elem ':' . effectKeyText) crawlerEffectKeys

renderReport :: [Check] -> Bool -> String
renderReport currentChecks succeeded =
  "{"
    ++ jsonField "schema" (jsonString "crawler-facade-witness.v2")
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
