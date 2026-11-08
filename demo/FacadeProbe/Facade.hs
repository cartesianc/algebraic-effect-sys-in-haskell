{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE UndecidableInstances #-}

-- The target handwritten Handlers. Every method is a class method without parameters;
-- nothing here names an upstream effect, a scope, a refined asset or an effect error.
module FacadeProbe.Facade () where

import FacadeProbe.Contracts
import FacadeProbe.Types
import Control.Concurrent (threadDelay)
import Control.Monad (when)
import System.IO (IOMode(WriteMode), hClose, hFlush, hPutStr, openFile, readFile')

instance AcquireFileInputs m => AcquireFileHandler m where
  acquireFile = do
    path <- require @FilePath
    file <- liftIO (openFile path WriteMode)
    pure (TextFile path file)

instance OpenTextFileInputs m => OpenTextFileHandler m where
  openTextFile = do
    TextFile path _ <- request @TextFile
    liftIO (putStrLn ("[open] " ++ path))
    pure Nothing

instance CloseTextFileInputs m => CloseTextFileHandler m where
  closeTextFile = do
    TextFile path file <- require @TextFile
    liftIO (hClose file >> putStrLn ("[close] " ++ path))
    pure Nothing

instance WriteTextInputs m => WriteTextHandler m where
  writeText = do
    TextFile path file <- require @TextFile
    Body text <- require @Body
    liftIO (hPutStr file text >> hFlush file >> putStrLn ("[write] " ++ path))
    pure Nothing

instance ReadTextInputs m => ReadTextHandler m where
  readText = do
    path <- require @FilePath
    contents <- liftIO (readFile' path)
    pure (Just contents)

instance CountLinesInputs m => CountLinesHandler m where
  countLines = do
    output <- upstreamOutput
    contents <- maybe (failWith "no text") pure output
    pure (LineCount (length (lines contents)))

instance ShowCountInputs m => ShowCountHandler m where
  showCount = do
    LineCount count <- require @LineCount
    liftIO (putStrLn ("[lines] " ++ show count))
    pure Nothing

instance MarkReadInputs m => MarkReadHandler m where
  markRead = do
    liftIO (putStrLn "[mark] before reading")
    pure Nothing

instance InspectFileInputs m => InspectFileHandler m where
  inspectFile = do
    path <- require @FilePath
    contents <- liftIO (readFile' path)
    pure (if null contents then Blank else Filled (Body contents))

instance DescribeBlankInputs m => DescribeBlankHandler m where
  describeBlank = do
    liftIO (putStrLn "[state] blank")
    pure Nothing

instance DescribeFilledInputs m => DescribeFilledHandler m where
  describeFilled = do
    Body text <- require @Body
    liftIO (putStrLn ("[state] filled, " ++ show (length text) ++ " characters"))
    pure Nothing

instance ParseLevelInputs m => ParseLevelHandler m where
  parseLevel = do
    raw <- upstreamRaw
    case reads raw of
      [(value, "")] -> pure (Level value)
      _ -> failWith raw

instance ShowLevelInputs m => ShowLevelHandler m where
  showLevel = do
    samples <- require @(History Level)
    case latest samples of
      Just (Level value) -> liftIO (putStrLn ("[level] " ++ show value ++ " at delivery " ++ show (historySize samples)))
      Nothing -> pure ()
    when (historySize samples >= 3) (failWith "enough deliveries")
    pure Nothing
