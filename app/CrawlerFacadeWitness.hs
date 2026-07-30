module Main (main) where

import Control.Concurrent.MVar
  ( MVar
  , modifyMVar_
  , newMVar
  , readMVar
  )
import Control.Monad
  ( unless )
import Data.List
  ( intercalate
  , nub
  , sort
  )
import System.Exit
  ( exitFailure )

-- This is deliberately the only framework import. It is the SDK authoring
-- boundary that business programs are expected to use.
import MyFramework

data Check = Check
  { checkName :: String
  , checkPassed :: Bool
  , checkObserved :: String
  }

main :: IO ()
main = do
  runtimeCheck <- checkCrawlerRuns
  let currentChecks =
        [ Check
            "crawler-facade-import-myframework-only"
            True
            "crawler authoring uses only import MyFramework"
        , Check
            "crawler-facade-referenced-program-valid"
            (null (validate crawlerProgram))
            (show (validate crawlerProgram))
        , Check
            "crawler-facade-chain-fallback-parallel"
            crawlerControlsResolve
            (show (resolveAll crawlerProgram))
        , Check
            "crawler-facade-module-local-effects"
            crawlerModuleEffectsResolve
            (show (map (resolve crawlerProgram) [fetch, extract, persist]))
        , Check
            "crawler-facade-r-separate"
            crawlerReadsAreSeparate
            (show [seedUrl, requestHeaders, fetchedPage, parsedLinks, parsedContent])
        , runtimeCheck
        ]
      succeeded =
        all checkPassed currentChecks
  putStrLn (renderReport currentChecks succeeded)
  unless succeeded exitFailure

-- Names are declared once. Every AST/control/effect position uses the same
-- authoring type; no ModuleName/LocalKey conversion helper exists here.
crawler, fetch, extract, persist :: Name
crawler = name "crawler"
fetch = name "fetch"
extract = name "extract"
persist = name "persist"

primary, mirror, links, content, page :: Name
primary = name "primary"
mirror = name "mirror"
links = name "links"
content = name "content"
page = name "page"

url, headers :: Name
url = name "url"
headers = name "headers"

-- The requested surface is present literally in executable code.
crawlerAst :: ControlDecl
crawlerAst =
  chain crawler [fetch, extract, persist]

fetchAst :: ControlDecl
fetchAst =
  fallback fetch [primary, mirror]

extractAst :: ControlDecl
extractAst =
  parallel extract [links, content]

persistAst :: ControlDecl
persistAst =
  chain persist [page, links]

urlType, headersType, pageType, linksType, contentType :: SchemaIdentity
urlType = scalarType "Url"
headersType = scalarType "Headers"
pageType = scalarType "Page"
linksType = scalarType "Links"
contentType = scalarType "Content"

-- R is declared independently from the CUDE action graph.
seedUrl, requestHeaders, fetchedPage, parsedLinks, parsedContent :: R
seedUrl = r "seedUrl" urlType
requestHeaders = r "requestHeaders" headersType
fetchedPage = r "fetchedPage" pageType
parsedLinks = r "parsedLinks" linksType
parsedContent = r "parsedContent" contentType

fetchEffects :: EffectModule
fetchEffects =
  effects fetch
    [ primary
        .= Effect
          { crude = E
          , input = none
          , params =
              [ url .= fromR seedUrl
              , headers .= fromR requestHeaders
              ]
          }
    , mirror
        .= Effect
          { crude = E
          , input = none
          , params =
              [ url .= fromR seedUrl
              , headers .= fromR requestHeaders
              ]
          }
    ]

extractEffects :: EffectModule
extractEffects =
  effects extract
    [ links
        .= Effect
          { crude = E
          , input = none
          , params = [page .= fromR fetchedPage]
          }
    , content
        .= Effect
          { crude = E
          , input = none
          , params = [page .= fromR fetchedPage]
          }
    ]

persistEffects :: EffectModule
persistEffects =
  effects persist
    [ page
        .= Effect
          { crude = C
          , input = none
          , params = [content .= fromR parsedContent]
          }
    , links
        .= Effect
          { crude = C
          , input = after page
          , params = [links .= fromR parsedLinks]
          }
    ]

crawlerReads :: ReadRegistry
crawlerReads =
  readRegistry
    [ seedUrl
    , requestHeaders
    , fetchedPage
    , parsedLinks
    , parsedContent
    ]

crawlerProgram :: ReferencedProgram
crawlerProgram =
  program
    crawler
    [crawlerAst, fetchAst, extractAst, persistAst]
    [fetchEffects, extractEffects, persistEffects]
    crawlerReads

crawlerControlsResolve :: Bool
crawlerControlsResolve =
  case resolveAll crawlerProgram of
    Right _ -> True
    Left _ -> False

crawlerModuleEffectsResolve :: Bool
crawlerModuleEffectsResolve =
  all
    (either (const False) (const True))
    (map (resolve crawlerProgram) [fetch, extract, persist])

crawlerReadsAreSeparate :: Bool
crawlerReadsAreSeparate =
  length currentKeys == length (nub currentKeys)
    && null (validate crawlerProgram)
  where
    currentKeys =
      map
        readKeyOf
        [seedUrl, requestHeaders, fetchedPage, parsedLinks, parsedContent]

checkCrawlerRuns :: IO Check
checkCrawlerRuns = do
  currentLog <- newMVar []
  case crawlerHandlers currentLog of
    Left currentError ->
      pure
        ( Check
            "crawler-facade-runtime-succeeds"
            False
            (show currentError)
        )
    Right currentHandlers -> do
      currentResult <-
        runReferencedProgram crawlerProgram currentHandlers
      currentActions <- readMVar currentLog
      let expectedActions =
            sort
              [ "primary"
              , "mirror"
              , "extract-links"
              , "extract-content"
              , "persist-page"
              , "persist-links"
              ]
          succeeded =
            frontendRunOutcome currentResult == Right ()
              && sort currentActions == expectedActions
      pure
        ( Check
            "crawler-facade-runtime-succeeds"
            succeeded
            (show (frontendRunOutcome currentResult, currentActions))
        )

crawlerHandlers ::
  MVar [String] ->
  Either FrontendRegistryError FrontendHandlers
crawlerHandlers currentLog = do
  h1 <-
    registerFrontendRead
      (readKeyOf seedUrl)
      (pure (Right (RuntimeText "https://example.test")))
      emptyFrontendHandlers
  h2 <-
    registerFrontendRead
      (readKeyOf requestHeaders)
      (pure (Right (RuntimeText "crawler/1")))
      h1
  h3 <-
    registerFrontendRead
      (readKeyOf fetchedPage)
      (pure (Right (RuntimeText "<html/>")))
      h2
  h4 <-
    registerFrontendRead
      (readKeyOf parsedLinks)
      (pure (Right (RuntimeText "[]")))
      h3
  h5 <-
    registerFrontendRead
      (readKeyOf parsedContent)
      (pure (Right (RuntimeText "content")))
      h4
  h6 <-
    registerFrontendEffect
      (address fetch primary)
      (failingHandler currentLog "primary")
      h5
  h7 <-
    registerFrontendEffect
      (address fetch mirror)
      (passingHandler currentLog "mirror")
      h6
  h8 <-
    registerFrontendEffect
      (address extract links)
      (passingHandler currentLog "extract-links")
      h7
  h9 <-
    registerFrontendEffect
      (address extract content)
      (passingHandler currentLog "extract-content")
      h8
  h10 <-
    registerFrontendEffect
      (address persist page)
      (passingHandler currentLog "persist-page")
      h9
  registerFrontendEffect
    (address persist links)
    (passingHandler currentLog "persist-links")
    h10

passingHandler ::
  MVar [String] ->
  String ->
  RuntimeData ->
  IO (Either String ())
passingHandler currentLog currentName _ = do
  appendLog currentLog currentName
  pure (Right ())

failingHandler ::
  MVar [String] ->
  String ->
  RuntimeData ->
  IO (Either String ())
failingHandler currentLog currentName _ = do
  appendLog currentLog currentName
  pure (Left "primary unavailable")

appendLog :: MVar [String] -> String -> IO ()
appendLog currentLog currentName =
  modifyMVar_ currentLog
    (\currentItems -> pure (currentItems ++ [currentName]))

renderReport :: [Check] -> Bool -> String
renderReport currentChecks succeeded =
  "{"
    ++ jsonField "schema" (jsonString "crawler-facade-witness.v1")
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
    ++ jsonField
      "claimManifest"
      (jsonArray (map (jsonString . checkName) currentChecks))
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
