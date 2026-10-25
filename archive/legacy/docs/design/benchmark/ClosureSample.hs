{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeApplications #-}

-- Verification and command-line runner. Start reading at Sample.hs.
module Main where

import Control.Exception
  ( AsyncException(UserInterrupt), bracket, finally, throwIO, try )
import Control.Monad (replicateM, unless)
import Data.IORef (modifyIORef', newIORef, readIORef)
import FileHandles
import Library
import Sample
import System.Environment (getArgs)

type Outcome = Either ReportFileError ReportRead

observe :: Trace -> String -> IO a -> IO a
observe trace label action = do
  trace (label ++ ":begin")
  action `finally` trace (label ++ ":end")

recorder :: IO (Start, IO ([String], [String]))
recorder = do
  events <- newIORef []
  messages <- newIORef []
  let trace event = modifyIORef' events (event :)
      sink message = modifyIORef' messages (message :)
      snapshot = (,) <$> (reverse <$> readIORef events)
                     <*> (reverse <$> readIORef messages)
  pure (Start trace sink, snapshot)

check :: (Eq a, Show a) => String -> a -> a -> IO ()
check label expected actual =
  unless (actual == expected) $
    error (label ++ ": expected " ++ show expected ++ ", got " ++ show actual)

-- A variant of the same graph: two Read expressions consume one activation.
-- The fixture supplies the open scope; the library compiles load -> report.
sharedRead :: Start -> FilePath -> IO Outcome
sharedRead start path = bracket (openImpl start path) (\session -> closeImpl session ()) $ \session ->
  let loadText = Effect
        { typing = Excu, input = supplied session, require = ofType @ReadRequest
        , handler = handlers @"readChars", bind = loadImpl, scope = noScope }
      reader = Effect
        { typing = Read, input = loadText, require = noRequire
        , handler = handlers @"readLoaded", bind = readLoadedImpl, scope = noScope }
      pair (ReadLoaded a) (ReadLoaded b) = ReportArgs ("read:" ++ a ++ "|" ++ b)
      report = Effect
        { typing = Excu, input = loadText
        , require = ofType @PrepareReport
        , handler = handlers @"writeReport", bind = reportImpl, scope = noScope }
      loadArguments = withArgs (argument id) noArguments
      reportArguments = withArgs (combine pair (readFrom reader) (readFrom reader)) loadArguments
  in compile report reportArguments (Take 2)

-- One registration accepts separate call-site expressions and environments.
parameterVariants :: Start -> FilePath -> IO (Either ReportFileError [String])
parameterVariants start path =
  bracket (openImpl start path) (\session -> closeImpl session ()) $ \session ->
    let loadText = Effect
          { typing = Excu, input = supplied session, require = ofType @ReadRequest
          , handler = handlers @"readChars", bind = loadImpl, scope = noScope }
        fromRequest = compile loadText (withArgs (argument id) noArguments)
        alwaysTwo = compile loadText (withArgs (argument (const (Take 2))) noArguments)
        text loaded = case readLoadedImpl loaded () of ReadLoaded value -> value
    in do
      first <- fromRequest FirstChar
      second <- alwaysTwo ()
      pure ((\a b -> [text a, text b]) <$> first <*> second)

verify :: FilePath -> FilePath -> IO ()
verify pathA pathB = do
  let normalEvents = ["open", "read", "report", "close"]
      normal label path request message = do
        (start, snapshot) <- recorder
        let action = sample start (Request path request)
        snapshot >>= check (label ++ " construction") ([], [])
        outcome <- action
        check label (Right (ReportRead message)) outcome
        snapshot >>= check (label ++ " trace") (normalEvents, [message])
        putStrLn ("PASS " ++ label)
  normal "file A / Take 2" pathA (Take 2) "read:AB"
  normal "file B / Take 2" pathB (Take 2) "read:WX"
  normal "file A / FirstChar" pathA FirstChar "read:A"

  (failureStart, failureSnapshot) <- recorder
  failure <- sample failureStart (Request pathA (Take 8))
  check "read failure" (Left (ReportFileError pathA)) failure
  failureSnapshot >>= check "failure trace"
    (["open", "read", "error", "close"], ["error:read"])
  putStrLn "PASS read failure closes the same scope"

  (repeatStart, repeatSnapshot) <- recorder
  let repeated = sample repeatStart (Request pathA (Take 2))
  results <- replicateM 2 repeated
  check "repeated invocation" (replicate 2 (Right (ReportRead "read:AB"))) results
  repeatSnapshot >>= check "repeated trace"
    (normalEvents ++ normalEvents, ["read:AB", "read:AB"])
  putStrLn "PASS two invocations create two scopes"

  (sharedStart, sharedSnapshot) <- recorder
  shared <- sharedRead sharedStart pathA
  check "shared result" (Right (ReportRead "read:AB|AB")) shared
  sharedSnapshot >>= check "shared trace" (normalEvents, ["read:AB|AB"])
  putStrLn "PASS two Read expressions share one compiled load"

  (parameterStart, parameterSnapshot) <- recorder
  variants <- parameterVariants parameterStart pathA
  check "parameter expressions" (Right ["A", "BC"]) variants
  parameterSnapshot >>= check "parameter expression trace"
    (["open", "read", "read", "close"], [])
  putStrLn "PASS one require ADT accepts different call-site expressions"

  (Start cancelTrace cancelSink, cancelSnapshot) <- recorder
  let trace event = do
        cancelTrace event
        if event == "read" then throwIO UserInterrupt else pure ()
  cancelled <- try (sample (Start trace cancelSink) (Request pathA (Take 2)))
                 :: IO (Either AsyncException Outcome)
  check "cancellation signal" (Left UserInterrupt) cancelled
  cancelSnapshot >>= check "cancellation trace" (["open", "read", "close"], [])
  putStrLn "PASS cancellation at the read boundary closes the scope"

  (observedStart@(Start observedTrace _), observedSnapshot) <- recorder
  observed <- observe observedTrace "sample" (sample observedStart (Request pathA (Take 2)))
  check "observed result" (Right (ReportRead "read:AB")) observed
  observedSnapshot >>= check "observed trace"
    (["sample:begin"] ++ normalEvents ++ ["sample:end"], ["read:AB"])
  putStrLn "PASS middleware preserves the result"

main :: IO ()
main = do
  args <- getArgs
  case args of
    ["--verify", pathA, pathB] -> verify pathA pathB
    [path] -> do
      outcome <- sample (Start (const (pure ())) putStrLn) (Request path (Take 2))
      print outcome
    _ -> error "Usage: runghc -idocs/design/benchmark docs/design/benchmark/ClosureSample.hs --verify fileA fileB | fileA"
