{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}

-- Provider code: domain data and the actual implementations of named methods.
module FileHandles where

import Control.Exception (IOException, onException)
import Control.Monad (replicateM)
import Library
import System.IO (Handle, IOMode(ReadMode), hClose, hGetChar, openFile)

type Trace = String -> IO ()
type Sink = String -> IO ()
data Start = Start Trace Sink
data FileSession = FileSession FilePath Handle Trace Sink
data ReadRequest = FirstChar | Take Int
data Request = Request FilePath ReadRequest
data LoadText = LoadedText FileSession String
data ReadLoaded = ReadLoaded String
data PrepareReport = ReportArgs String
data ReportRead = ReportRead String deriving (Eq, Show)
data ReportFileError = ReportFileError FilePath deriving (Eq, Show)
data CloseFile = Closed deriving (Eq, Show)

requestedPath :: Request -> FilePath
requestedPath (Request path _) = path

requestedRead :: Request -> ReadRequest
requestedRead (Request _ request) = request

instance Handler "openFile" 'KExcu Start FilePath FileSession where
  invoke (Start trace sink) path = do
    file <- openFile path ReadMode
    (trace "open" >> pure (FileSession path file trace sink))
      `onException` hClose file

instance Handler "readChars" 'KExcu FileSession Int String where
  invoke (FileSession _ file trace _) count = do
    trace "read"
    replicateM count (hGetChar file)

instance Handler "readLoaded" 'KRead LoadText () ReadLoaded where
  invoke (LoadedText _ text) () = ReadLoaded text

instance Handler "prepareReport" 'KMap ReadLoaded () PrepareReport where
  invoke (ReadLoaded text) () = ReportArgs ("read:" ++ text)

instance Handler "writeReport" 'KExcu LoadText PrepareReport ReportRead where
  invoke (LoadedText (FileSession _ _ trace sink) _) (ReportArgs message) = do
    trace "report"
    sink message
    pure (ReportRead message)

instance Handler "closeFile" 'KClose FileSession () CloseFile where
  invoke (FileSession _ file trace _) () = do
    hClose file
    trace "close"
    pure Closed

instance Handler "reportFileError" 'KX FileSession IOException ReportFileError where
  invoke (FileSession path _ trace sink) _ = do
    trace "error"
    sink "error:read"
    pure (ReportFileError path)
