{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE ScopedTypeVariables #-}

module Main (main) where

import Control.Monad
  ( unless
  )
import Data.IORef
  ( IORef
  , modifyIORef'
  , newIORef
  , readIORef
  , writeIORef
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
import Text.Read
  ( readMaybe
  )

import MyFramework

data MonitorParams = MonitorParams
  { monitorScope :: String
  }
  deriving (Eq, Generic, Read, Show)

instance HasSchema MonitorParams

data MonitorObservation = MonitorObservation
  { monitorAccepted :: Bool
  }
  deriving (Eq, Generic, Read, Show)

instance HasSchema MonitorObservation

data Check = Check
  { checkName :: String
  , checkPassed :: Bool
  , checkObserved :: String
  }

main :: IO ()
main =
  case monitorProgram of
    Left currentErrors -> do
      putStrLn (renderReport [Check "effsys-ref-program-valid" False (show currentErrors)] False)
      exitFailure
    Right currentPrepared ->
      case scopedEffSys monitorEffSysRef currentPrepared of
        Left currentErrors -> do
          putStrLn (renderReport [Check "effsys-ref-scope-builds" False (show currentErrors)] False)
          exitFailure
        Right currentIr -> do
          handlerCount <- newIORef 0
          observedRef <- newIORef Nothing
          currentRun <- runMonitor handlerCount observedRef currentPrepared
          countBeforeQueries <- readIORef handlerCount
          observedValue <- readIORef observedRef
          case currentRun of
            Left currentErrors -> do
              putStrLn (renderReport [Check "effsys-ref-runtime-valid" False (show currentErrors)] False)
              exitFailure
            Right completedRun -> do
              let currentSnapshot = effSysSnapshotFromRuntime currentIr completedRun
                  currentOccurrence = head (effSysIrOccurrences currentIr)
                  currentPath = applicationOccurrencePath currentOccurrence
                  currentCommand =
                    someEffectRefKey
                      ( effectApplicationCommand
                          (applicationOccurrenceApplication currentOccurrence)
                      )
                  currentStats = queryEffSysStats currentIr currentSnapshot
                  queryResult =
                    ( queryEffSysEffect currentCommand currentIr
                    , queryEffSysInputPipeline currentCommand currentIr
                    , queryEffSysState currentPath currentCommand currentSnapshot
                    , queryEffSysObservation currentPath currentCommand currentSnapshot
                    , queryEffSysFailure currentPath currentCommand currentSnapshot
                    , currentStats
                    )
              snapshotRef <- newIORef currentSnapshot
              let currentView = effSysView monitorEffSysRef snapshotRef
              firstView <- readEffSysView currentView
              let revisedSnapshot =
                    currentSnapshot
                      { effSysSnapshotRevision = StateRevision 1
                      }
              writeIORef snapshotRef revisedSnapshot
              secondView <- readEffSysView currentView
              countAfterQueries <- readIORef handlerCount
              let currentChecks =
                    [ Check
                        "effsys-ref-ir-roundtrip"
                        ( readMaybe (show currentIr) == Just currentIr
                            && not (null (effSysIrDigest currentIr))
                        )
                        (effSysIrDigest currentIr)
                    , Check
                        "effsys-ref-scope-closure-three-graphs"
                        ( not (null (astGraphNodes (effSysIrAstGraph currentIr)))
                            && not (null (inputGraphNodes (effSysIrInputGraph currentIr)))
                            && not (null (valueGraphNodes (effSysIrValueGraph currentIr)))
                        )
                        (show (scopeGraphSizes currentIr))
                    , Check
                        "effsys-ref-enters-value-graph"
                        ( any ((== ValueEffSysRefRole) . valueNodeRole) (valueGraphNodes (effSysIrValueGraph currentIr))
                            && any ((== ValueEffSysDependency) . valueEdgeKind) (valueGraphEdges (effSysIrValueGraph currentIr))
                        )
                        "ValueEffSysRefRole -> ValueReadRole"
                    , Check
                        "effsys-ref-parameter-does-not-add-demand"
                        (countBeforeQueries == 2 && observedValue == Just monitorEffSysRef)
                        (show (countBeforeQueries, observedValue))
                    , Check
                        "effsys-ref-snapshot-roundtrip"
                        (readMaybe (show currentSnapshot) == Just currentSnapshot)
                        (show (length (effSysSnapshotEntries currentSnapshot)))
                    , Check
                        "effsys-ref-view-and-snapshot-distinct"
                        ( effSysSnapshotRevision firstView == StateRevision 0
                            && effSysSnapshotRevision secondView == StateRevision 1
                            && effSysSnapshotRevision currentSnapshot == StateRevision 0
                        )
                        (show (effSysSnapshotRevision firstView, effSysSnapshotRevision secondView))
                    , Check
                        "effsys-ref-query-ir-pipeline-state-observation-failure-stats"
                        ( queryComplete queryResult
                            && effSysStatsSucceeded currentStats >= 2
                            && effSysStatsFailed currentStats == 0
                        )
                        (showQuery queryResult)
                    , Check
                        "effsys-ref-query-does-not-start-handler"
                        (countAfterQueries == countBeforeQueries)
                        (show (countBeforeQueries, countAfterQueries))
                    , Check
                        "effsys-ref-cross-scope-rejected"
                        crossScopeRejected
                        (show crossScopeProgram)
                    , Check
                        "effsys-ref-registry-mismatch-rejected"
                        registryMismatchRejected
                        (show registryMismatchProgram)
                    ]
                  succeeded = all checkPassed currentChecks
              putStrLn (renderReport currentChecks succeeded)
              unless succeeded exitFailure

monitorEffSysRef :: EffSysRef
monitorEffSysRef = effSys (name "scope") (name "scope")

monitorCommand :: EffectRef 'E MonitorParams MonitorObservation
monitorCommand = e "monitor" none

monitorRead :: R EffSysRef
monitorRead = r "monitor-scope"

monitorMap :: EffectRef 'MAP EffSysRef MonitorParams
monitorMap = mapping "monitor-map"

monitorApplication :: Application
monitorApplication =
  applyEffSys monitorCommand monitorMap monitorRead monitorEffSysRef

monitorProgram :: Either [ProgramError] PreparedRuntime
monitorProgram =
  program
    (name "scope")
    [chain (name "scope") [monitorApplication]]
    [effects (name "scope") [monitorApplication]]

schemaId :: forall value. HasSchema value => Proxy value -> ValueSchemaId
schemaId _ =
  schemaDescriptorId
    ( descriptorFor
        (SchemaFromType "effsys-ref-witness")
        (valueSchemaDefinition (Proxy :: Proxy value))
    )

effSysSchema, paramsSchema, observationSchema :: ValueSchemaId
effSysSchema = schemaId (Proxy :: Proxy EffSysRef)
paramsSchema = schemaId (Proxy :: Proxy MonitorParams)
observationSchema = schemaId (Proxy :: Proxy MonitorObservation)

runMonitor ::
  IORef Int ->
  IORef (Maybe EffSysRef) ->
  PreparedRuntime ->
  IO (Either [RuntimePreparationError] UnifiedRuntimeRun)
runMonitor currentCount currentObserved currentPrepared =
  case runtimeHandlerRegistry currentRegistrations of
    Left _ -> pure (Left [RuntimeHandlerMissing (EffectKey "effsys-handler-registry")])
    Right currentHandlers -> runPreparedRuntime currentHandlers currentPrepared
  where
    currentRegistrations =
      [ registrationFor currentEffect
      | currentEffect <- effectRegistryEffects (effectRegistryOf currentPrepared)
      , case effectIrSpec currentEffect of
          ReadEffect _ -> False
          _ -> True
      ]
    registrationFor currentEffect =
      case effectIrSpec currentEffect of
        MapEffect currentSpec ->
          runtimeHandler
            (effectIrRef currentEffect)
            (Just (mapSpecInputSchema currentSpec))
            (Just paramsSchema)
            (\currentInvocation -> do
                modifyIORef' currentCount (+ 1)
                case runtimeInvocationValue currentInvocation >>= readMaybe . runtimeValuePayload of
                  Just currentRef -> do
                    writeIORef currentObserved (Just currentRef)
                    pure (HandlerSucceeded (Just (RuntimeValue paramsSchema (show (MonitorParams "scope")))))
                  Nothing -> pure (HandlerFailed "EffSysRef decode failed")
            )
        CommandEffect currentSpec ->
          runtimeHandler
            (effectIrRef currentEffect)
            (Just (commandSpecArgumentSchema currentSpec))
            (Just (commandSpecObservationSchema currentSpec))
            (\_ -> do
                modifyIORef' currentCount (+ 1)
                pure (HandlerSucceeded (Just (RuntimeValue observationSchema (show (MonitorObservation True)))))
            )
        ReadEffect _ ->
          runtimeHandler
            (effectIrRef currentEffect)
            Nothing
            (Just effSysSchema)
            (const (pure (HandlerFailed "ValueEffSysRef must not invoke a read handler")))

scopeGraphSizes :: EffSysIR -> (Int, Int, Int)
scopeGraphSizes currentIr =
  ( length (astGraphNodes (effSysIrAstGraph currentIr))
  , length (inputGraphNodes (effSysIrInputGraph currentIr))
  , length (valueGraphNodes (effSysIrValueGraph currentIr))
  )

queryComplete ::
  ( Maybe EffectIR
  , [ContinuationNode]
  , Maybe ContinuationOutcome
  , Maybe RuntimeValue
  , Maybe RuntimeFault
  , EffSysStats
  ) ->
  Bool
queryComplete (currentEffect, currentPipeline, currentState, currentObservation, currentFailure, _) =
  case (currentEffect, currentPipeline, currentState, currentObservation, currentFailure) of
    (Just _, _ : _, Just Succeeded, Just _, Nothing) -> True
    _ -> False

showQuery ::
  ( Maybe EffectIR
  , [ContinuationNode]
  , Maybe ContinuationOutcome
  , Maybe RuntimeValue
  , Maybe RuntimeFault
  , EffSysStats
  ) ->
  String
showQuery (_, currentPipeline, currentState, currentObservation, currentFailure, currentStats) =
  show (length currentPipeline, currentState, currentObservation, currentFailure, currentStats)

crossScopeRef :: EffSysRef
crossScopeRef = effSys (name "root") (name "inside")

outsideApplication :: Application
outsideApplication =
  applyEffSys
    (e "outside-monitor" none :: EffectRef 'E MonitorParams MonitorObservation)
    (mapping "outside-map" :: EffectRef 'MAP EffSysRef MonitorParams)
    (r "outside-scope" :: R EffSysRef)
    crossScopeRef

crossScopeProgram :: Either [ProgramError] PreparedRuntime
crossScopeProgram =
  program
    (name "root")
    [ chain (name "root") [name "inside", name "outside"]
    , chain (name "inside") ([] :: [Name])
    , chain (name "outside") [outsideApplication]
    ]
    [effects (name "outside") [outsideApplication]]

crossScopeRejected :: Bool
crossScopeRejected =
  case crossScopeProgram of
    Left currentErrors -> any isOutside currentErrors
    Right _ -> False
  where
    isOutside ProgramEffSysFailed { } = True
    isOutside _ = False

registryMismatchProgram :: Either [ProgramError] PreparedRuntime
registryMismatchProgram =
  program
    (name "scope")
    [chain (name "scope") [mismatchedApplication]]
    [effects (name "scope") [mismatchedApplication]]
  where
    mismatchedApplication =
      applyEffSys
        (e "mismatch" none :: EffectRef 'E MonitorParams MonitorObservation)
        (mapping "mismatch-map" :: EffectRef 'MAP EffSysRef MonitorParams)
        (r "mismatch-scope" :: R EffSysRef)
        (effSys (name "another-registry") (name "scope"))

registryMismatchRejected :: Bool
registryMismatchRejected =
  case registryMismatchProgram of
    Left currentErrors -> any isMismatch currentErrors
    Right _ -> False
  where
    isMismatch (ProgramEffSysFailed EffSysRegistryMismatch {}) = True
    isMismatch _ = False

renderReport :: [Check] -> Bool -> String
renderReport currentChecks succeeded =
  "{"
    ++ jsonField "schema" (jsonString "effsys-ref-witness.v1")
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
