{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE TypeFamilies #-}

-- What gen would generate from the target registrations: one class per handler, with
-- an Inputs alias derived from the representation types its bindings demand.
-- No class or alias mentions an Input chain, an effect or a refined asset.
module FacadeProbe.Contracts
  ( module FacadeProbe.Contracts, Provides(..), History, latest, historySize, MonadIO, liftIO
  ) where

import Control.Monad.IO.Class (MonadIO, liftIO)
import FacadeProbe.Generated.Effects (Provides(..))
import FacadeProbe.Types
import Framework.SDK (History, historySize, latest)

class FailWith m where
  failWith :: String -> m value

class UpstreamOutput m where
  upstreamOutput :: m (Maybe String)

class UpstreamRaw m where
  upstreamRaw :: m String

type Reads value m = (Provides value m, Reading value ~ value)

type AcquireFileInputs m = (Reads FilePath m, MonadIO m)
class AcquireFileHandler m where acquireFile :: m TextFile

type OpenTextFileInputs m = (Provides TextFile m, MonadIO m)
class OpenTextFileHandler m where openTextFile :: m (Maybe String)

type CloseTextFileInputs m = (Reads TextFile m, MonadIO m)
class CloseTextFileHandler m where closeTextFile :: m (Maybe String)

type WriteTextInputs m = (Reads TextFile m, Reads Body m, MonadIO m)
class WriteTextHandler m where writeText :: m (Maybe String)

type ReadTextInputs m = (Reads FilePath m, MonadIO m)
class ReadTextHandler m where readText :: m (Maybe String)

type CountLinesInputs m = (UpstreamOutput m, FailWith m, Monad m)
class CountLinesHandler m where countLines :: m LineCount

type ShowCountInputs m = (Reads LineCount m, MonadIO m)
class ShowCountHandler m where showCount :: m (Maybe String)

type MarkReadInputs m = MonadIO m
class MarkReadHandler m where markRead :: m (Maybe String)

type InspectFileInputs m = (Reads FilePath m, MonadIO m)
class InspectFileHandler m where inspectFile :: m FileState

type DescribeBlankInputs m = MonadIO m
class DescribeBlankHandler m where describeBlank :: m (Maybe String)

type DescribeFilledInputs m = (Reads Body m, MonadIO m)
class DescribeFilledHandler m where describeFilled :: m (Maybe String)

type ParseLevelInputs m = (UpstreamRaw m, FailWith m, Monad m)
class ParseLevelHandler m where parseLevel :: m Level

type ShowLevelInputs m = (Reads (History Level) m, FailWith m, MonadIO m)
class ShowLevelHandler m where showLevel :: m (Maybe String)
