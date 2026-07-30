module Main (main) where

import Control.Monad
  ( unless )
import Data.IORef
  ( IORef
  , atomicModifyIORef'
  , newIORef
  , readIORef
  )
import Data.List
  ( intercalate )
import System.Exit
  ( exitFailure )

import MyFramework.CURDE
  ( SchemaIdentity
  , scalarSchema
  , schemaRefIdentityOf
  )
import MyFramework.Frontend
import MyFramework.Frontend.Runtime
import MyFramework.Handler
  ( RuntimeData (..)
  )

data Check = Check
  { checkName :: String
  , checkPassed :: Bool
  , checkObserved :: String
  }

main :: IO ()
main = do
  chainChecks <- runChainParallelChecks
  fallbackChecks <- runFallbackChecks
  invalidReadChecks <- runInvalidReadChecks
  raceChecks <- runRaceChecks
  let currentChecks =
        chainChecks
          ++ fallbackChecks
          ++ invalidReadChecks
          ++ raceChecks
      succeeded =
        all checkPassed currentChecks
  putStrLn (renderReport currentChecks succeeded)
  unless succeeded exitFailure

runChainParallelChecks :: IO [Check]
runChainParallelChecks = do
  currentLog <- newIORef []
  currentReadCount <- newIORef 0
  currentHandlers <-
    buildHandlers
      [ ( prepareAddress
        , successfulEffect currentLog "prepare"
        )
      , ( finalizeAddress
        , successfulEffect currentLog "finalize"
        )
      , ( workAAddress
        , successfulEffect currentLog "workA"
        )
      , ( workBAddress
        , successfulEffect currentLog "workB"
        )
      ]
      [ ( sourceRead
        , do
            increment currentReadCount
            pure (Right (RuntimeText "payload"))
        )
        ]
  case currentHandlers of
    Left currentError ->
      pure
        [ check
            "referenced-runtime-registry"
            False
            (show currentError)
        ]
    Right currentRegistry -> do
      currentRun <-
        runReferencedProgram runtimeProgram currentRegistry
      observedLog <- reverse <$> readIORef currentLog
      observedReadCount <- readIORef currentReadCount
      let currentSnapshot =
            frontendRunSnapshot currentRun
          effectCounts =
            countItems observedLog
      pure
        [ check
            "referenced-runtime-chain-parallel-succeeded"
            (frontendRunOutcome currentRun == Right ())
            (show currentRun)
        , check
            "referenced-runtime-module-input-single-flight"
            ( lookup "prepare" effectCounts == Just 1
                && lookup "workA" effectCounts == Just 1
                && lookup "workB" effectCounts == Just 1
                && lookup "finalize" effectCounts == Just 1
            )
            (show observedLog)
        , check
            "referenced-runtime-r-single-flight"
            (observedReadCount == 1)
            (show observedReadCount)
        , check
            "referenced-runtime-occurrence-snapshot"
            ( all ((== FrontendSucceeded) . snd)
                (frontendSnapshotEffects currentSnapshot)
                && frontendSnapshotReads currentSnapshot
                  == [(sourceRead, FrontendSucceeded)]
            )
            (show currentSnapshot)
        ]

runFallbackChecks :: IO [Check]
runFallbackChecks = do
  currentLog <- newIORef []
  currentHandlers <-
    buildHandlers
      [ ( badAddress
        , \_ -> do
            pushLog currentLog "bad"
            pure (Left "expected failure")
        )
      , ( goodAddress
        , successfulEffect currentLog "good"
        )
      ]
      []
  case currentHandlers of
    Left currentError ->
      pure [check "referenced-runtime-fallback-registry" False (show currentError)]
    Right currentRegistry -> do
      currentRun <-
        runReferencedProgram fallbackProgram currentRegistry
      observedLog <- reverse <$> readIORef currentLog
      pure
        [ check
            "referenced-runtime-fallback-uses-next-reference"
            ( frontendRunOutcome currentRun == Right ()
                && observedLog == ["bad", "good"]
            )
            (show (currentRun, observedLog))
        ]

runInvalidReadChecks :: IO [Check]
runInvalidReadChecks = do
  currentHandlers <-
    buildHandlers
      [(readConsumerAddress, const (pure (Right ())))]
      [(sourceRead, pure (Right (RuntimeRecord [])))]
  case currentHandlers of
    Left currentError ->
      pure [check "referenced-runtime-invalid-read-registry" False (show currentError)]
    Right currentRegistry -> do
      currentRun <-
        runReferencedProgram invalidReadProgram currentRegistry
      pure
        [ check
            "referenced-runtime-invalid-r-value-rejected"
            (case frontendRunOutcome currentRun of
                Left (FrontendReadValueInvalid currentKey _) ->
                  currentKey == sourceRead
                _ ->
                  False
            )
            (show currentRun)
        ]

runRaceChecks :: IO [Check]
runRaceChecks = do
  currentHandlers <-
    buildHandlers
      [ (raceAAddress, const (pure (Right ())))
      , (raceBAddress, const (pure (Right ())))
      ]
      []
  case currentHandlers of
    Left currentError ->
      pure [check "referenced-runtime-race-registry" False (show currentError)]
    Right currentRegistry -> do
      currentRun <-
        runReferencedProgram raceProgram currentRegistry
      pure
        [ check
            "referenced-runtime-undecided-race-is-explicitly-unsupported"
            ( case frontendRunOutcome currentRun of
                Left (FrontendControlUnsupported _ ControlRace) ->
                  True
                _ ->
                  False
            )
            (show currentRun)
        ]

runtimeProgram :: ReferencedProgram
runtimeProgram =
  referencedProgram
    appModule
    [ chain appModule [prepareKey, workersKey, finalizeKey]
    , parallel workersModule [workAKey, workBKey]
    ]
    [ effects
        appModule
        [ (prepareKey, action Nothing [])
        , (finalizeKey, action (Just prepareKey) [])
        ]
    , effects
        workersModule
        [ ( workAKey
          , action
              Nothing
              [readParam "payload" sourceSchema sourceRead]
          )
        , ( workBKey
          , action
              (Just workAKey)
              [readParam "payload" sourceSchema sourceRead]
          )
        ]
    ]
    (readRecord [(sourceRead, sourceSchema)])

fallbackProgram :: ReferencedProgram
fallbackProgram =
  referencedProgram
    fallbackModule
    [fallback fallbackModule [badKey, goodKey]]
    [ effects
        fallbackModule
        [ (badKey, action Nothing [])
        , (goodKey, action Nothing [])
        ]
    ]
    (readRecord [])

invalidReadProgram :: ReferencedProgram
invalidReadProgram =
  referencedProgram
    readModule
    [chain readModule [readConsumerKey]]
    [ effects
        readModule
        [ ( readConsumerKey
          , action
              Nothing
              [readParam "payload" sourceSchema sourceRead]
          )
        ]
    ]
    (readRecord [(sourceRead, sourceSchema)])

raceProgram :: ReferencedProgram
raceProgram =
  referencedProgram
    raceModule
    [race raceModule [raceAKey, raceBKey]]
    [ effects
        raceModule
        [ (raceAKey, action Nothing [])
        , (raceBKey, action Nothing [])
        ]
    ]
    (readRecord [])

action ::
  Maybe LocalKey ->
  [(ParamKey, ParamBinding)] ->
  EffectDecl
action currentInput currentParams =
  EffectDecl
    { effectDeclType = EffectE
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

buildHandlers ::
  [(EffectAddress, FrontendEffectHandler)] ->
  [(ReadKey, FrontendReadHandler)] ->
  IO (Either FrontendRegistryError FrontendHandlers)
buildHandlers currentEffects currentReads =
  pure $ do
    withReads <-
      foldl
        registerRead
        (Right emptyFrontendHandlers)
        currentReads
    foldl registerEffect (Right withReads) currentEffects
  where
    registerRead currentRegistry (currentKey, currentHandler) =
      currentRegistry
        >>= registerFrontendRead currentKey currentHandler
    registerEffect currentRegistry (currentAddress, currentHandler) =
      currentRegistry
        >>= registerFrontendEffect currentAddress currentHandler

successfulEffect ::
  IORef [String] ->
  String ->
  FrontendEffectHandler
successfulEffect currentLog currentName _ = do
  pushLog currentLog currentName
  pure (Right ())

pushLog :: IORef [String] -> String -> IO ()
pushLog currentLog currentValue =
  atomicModifyIORef'
    currentLog
    (\currentValues -> (currentValue : currentValues, ()))

increment :: IORef Int -> IO ()
increment currentRef =
  atomicModifyIORef'
    currentRef
    (\currentValue -> (currentValue + 1, ()))

countItems :: Ord item => [item] -> [(item, Int)]
countItems currentItems =
  foldl addItem [] currentItems
  where
    addItem currentCounts currentItem =
      case lookup currentItem currentCounts of
        Nothing ->
          currentCounts ++ [(currentItem, 1)]
        Just currentCount ->
          [ if existingItem == currentItem
              then (existingItem, currentCount + 1)
              else (existingItem, existingCount)
          | (existingItem, existingCount) <- currentCounts
          ]

prepareAddress, finalizeAddress, workAAddress, workBAddress :: EffectAddress
prepareAddress = EffectAddress appModule prepareKey
finalizeAddress = EffectAddress appModule finalizeKey
workAAddress = EffectAddress workersModule workAKey
workBAddress = EffectAddress workersModule workBKey

badAddress, goodAddress, readConsumerAddress :: EffectAddress
badAddress = EffectAddress fallbackModule badKey
goodAddress = EffectAddress fallbackModule goodKey
readConsumerAddress = EffectAddress readModule readConsumerKey

raceAAddress, raceBAddress :: EffectAddress
raceAAddress = EffectAddress raceModule raceAKey
raceBAddress = EffectAddress raceModule raceBKey

appModule, workersModule, fallbackModule, readModule, raceModule :: ModuleName
appModule = ModuleName "app"
workersModule = ModuleName "workers"
fallbackModule = ModuleName "fallback"
readModule = ModuleName "read"
raceModule = ModuleName "race"

prepareKey, workersKey, finalizeKey, workAKey, workBKey :: LocalKey
prepareKey = LocalKey "prepare"
workersKey = LocalKey "workers"
finalizeKey = LocalKey "finalize"
workAKey = LocalKey "workA"
workBKey = LocalKey "workB"

badKey, goodKey, readConsumerKey, raceAKey, raceBKey :: LocalKey
badKey = LocalKey "bad"
goodKey = LocalKey "good"
readConsumerKey = LocalKey "readConsumer"
raceAKey = LocalKey "raceA"
raceBKey = LocalKey "raceB"

sourceRead :: ReadKey
sourceRead = ReadKey "source"

sourceSchema :: SchemaIdentity
sourceSchema =
  schemaRefIdentityOf (scalarSchema "Source")

check :: String -> Bool -> String -> Check
check =
  Check

renderReport :: [Check] -> Bool -> String
renderReport currentChecks succeeded =
  "{"
    ++ jsonField "schema" (jsonString "referenced-runtime-witness.v1")
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

