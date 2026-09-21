{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeApplications #-}

-- Read this file first: registrations, followed by parameter-adapting impls.
module Sample where

import Control.Exception (IOException)
import FileHandles
import Library

sample :: Start -> Request -> IO (Either ReportFileError ReportRead)
sample start = compile reportRead
  where
    fileSession = Effect
      { typing = Excu, input = supplied start
      , require = argument requestedPath
      , handler = handlers @"openFile", bind = openImpl
      , scope = closes closeFile reportFileError
      }

    loadText = Effect
      { typing = Excu, input = fileSession
      , require = argument requestedRead
      , handler = handlers @"readChars", bind = loadImpl
      , scope = noScope
      }

    readLoaded = Effect
      { typing = Read, input = loadText, require = noRequire
      , handler = handlers @"readLoaded", bind = readLoadedImpl
      , scope = noScope
      }

    prepareReport = Effect
      { typing = Map, input = readLoaded, require = noRequire
      , handler = handlers @"prepareReport", bind = prepareReportImpl
      , scope = noScope
      }

    reportRead = Effect
      { typing = Excu, input = loadText
      , require = mapped prepareReport (readFrom readLoaded)
      , handler = handlers @"writeReport", bind = reportImpl
      , scope = noScope
      }

    closeFile = Effect
      { typing = Close, input = fileSession, require = noRequire
      , handler = handlers @"closeFile", bind = closeImpl
      , scope = noScope
      }

    reportFileError = Effect
      { typing = X, input = fileSession, require = caughtError
      , handler = handlers @"reportFileError", bind = errorImpl
      , scope = noScope
      }

openImpl :: Start -> FilePath -> IO FileSession
openImpl = invoke @"openFile"

loadImpl :: FileSession -> ReadRequest -> IO LoadText
loadImpl upstream FirstChar = loadImpl upstream (Take 1)
loadImpl upstream (Take count) =
  LoadedText upstream <$> invoke @"readChars" upstream count

readLoadedImpl :: LoadText -> () -> ReadLoaded
readLoadedImpl = invoke @"readLoaded"

prepareReportImpl :: ReadLoaded -> () -> PrepareReport
prepareReportImpl = invoke @"prepareReport"

reportImpl :: LoadText -> PrepareReport -> IO ReportRead
reportImpl upstream (ReportArgs message) =
  invoke @"writeReport" upstream (ReportArgs message)

closeImpl :: FileSession -> () -> IO CloseFile
closeImpl = invoke @"closeFile"

errorImpl :: FileSession -> IOException -> IO ReportFileError
errorImpl = invoke @"reportFileError"
