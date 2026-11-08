{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE UndecidableInstances #-}

{-# OPTIONS_GHC -Werror=missing-methods #-}

-- Today's explicit form of the same program: the baseline, and the source of the prototype.
module FacadeProbe.Handlers () where

import Framework.SDK (Effect(..), historySize, latest)
import FacadeProbe.Generated.Effects
import FacadeProbe.Types
import Control.Concurrent (threadDelay)
import Control.Monad (when)
import Control.Monad.IO.Class (liftIO)
import System.FilePath ((</>))
import System.IO (IOMode(WriteMode), hClose, hFlush, hPutStr, openFile, readFile')

instance ReportLocationInputs m => ReportLocationEffect m where
  getReportPath = do
    pure (ReportPath ("demo" </> "FacadeProbe" </> "output" </> "report.txt"))

instance ReplyLocationInputs m => ReplyLocationEffect m where
  getReplyPath = do
    pure (ReplyPath ("demo" </> "FacadeProbe" </> "output" </> "reply.txt"))

instance ReportDraftInputs m => ReportDraftEffect m where
  getReportBody = do
    pure (ReportBody (Body "report line 1\nreport line 2\nreport line 3\n"))

instance ReplyDraftInputs m => ReplyDraftEffect m where
  getReplyBody = do
    pure (ReplyBody (Body "reply line 1\n"))

instance ReportFileInputs m => ReportFileEffect m where
  getOpenedReport = do
    ReportPath path <- require @ReportPath
    file <- liftIO (openFile path WriteMode)
    pure (OpenedReport (TextFile path file))

instance ReplyFileInputs m => ReplyFileEffect m where
  getOpenedReply = do
    ReplyPath path <- require @ReplyPath
    file <- liftIO (openFile path WriteMode)
    pure (OpenedReply (TextFile path file))

instance ReportScopeInputs m => ReportScopeEffect m where
  openReport = do
    OpenedReport (TextFile path _) <- request @OpenedReport
    liftIO (putStrLn ("[open] " ++ path))
    pure Nothing
  closeReport = do
    OpenedReport (TextFile path file) <- require @OpenedReport
    liftIO (hClose file >> putStrLn ("[close] " ++ path))
    pure Nothing

instance ReplyScopeInputs m => ReplyScopeEffect m where
  openReply = do
    OpenedReply (TextFile path _) <- request @OpenedReply
    liftIO (putStrLn ("[open] " ++ path))
    pure Nothing
  closeReply = do
    OpenedReply (TextFile path file) <- require @OpenedReply
    liftIO (hClose file >> putStrLn ("[close] " ++ path))
    pure Nothing

instance WriteReportInputs m => WriteReportEffect m where
  writeReport = do
    openReport
    OpenedReport (TextFile path file) <- require @OpenedReport
    ReportBody (Body text) <- require @ReportBody
    liftIO (hPutStr file text >> hFlush file >> putStrLn ("[write] " ++ path))
    pure Nothing

instance WriteReplyInputs m => WriteReplyEffect m where
  writeReply = do
    openReply
    OpenedReply (TextFile path file) <- require @OpenedReply
    ReplyBody (Body text) <- require @ReplyBody
    liftIO (hPutStr file text >> hFlush file >> putStrLn ("[write] " ++ path))
    pure Nothing

instance MarkReplyInputs m => MarkReplyEffect m where
  markReply = do
    liftIO (putStrLn "[mark] before reading")
    pure Nothing

instance ReadReportInputs m => ReadReportEffect m where
  readReport = do
    ReportPath path <- require @ReportPath
    contents <- liftIO (readFile' path)
    pure (Just contents)

instance ReadReplyInputs m => ReadReplyEffect m where
  readReply = do
    markReply
    ReplyPath path <- require @ReplyPath
    contents <- liftIO (readFile' path)
    pure (Just contents)

instance ReportCounterInputs m => ReportCounterEffect m where
  getReportStats = do
    output <- readReport
    contents <- maybe (raise (ReportCounterError "no text")) pure output
    pure (ReportStats (LineCount (length (lines contents))))

instance ReplyCounterInputs m => ReplyCounterEffect m where
  getReplyStats = do
    output <- readReply
    contents <- maybe (raise (ReplyCounterError "no text")) pure output
    pure (ReplyStats (LineCount (length (lines contents))))

instance ShowReportInputs m => ShowReportEffect m where
  showReport = do
    ReportStats (LineCount count) <- require @ReportStats
    liftIO (putStrLn ("[lines] " ++ show count))
    pure Nothing

instance ShowReplyInputs m => ShowReplyEffect m where
  showReply = do
    ReplyStats (LineCount count) <- require @ReplyStats
    liftIO (putStrLn ("[lines] " ++ show count))
    pure Nothing

instance ReportInspectInputs m => ReportInspectEffect m where
  getReportState = do
    ReportPath path <- require @ReportPath
    contents <- liftIO (readFile' path)
    pure (ReportState (if null contents then Blank else Filled (Body contents)))

instance OnBlankInputs m => OnBlankEffect m where
  onBlank = do
    ReportStateBlank _ <- require @ReportStateBlank
    liftIO (putStrLn "[state] blank")
    pure Nothing

instance OnFilledInputs m => OnFilledEffect m where
  onFilled = do
    ReportStateFilled (Body text) <- require @ReportStateFilled
    liftIO (putStrLn ("[state] filled, " ++ show (length text) ++ " characters"))
    pure Nothing

instance FeedAInputs m => FeedAEffect m where
  nextA = do
    liftIO (threadDelay 40000)
    pure "10"

instance FeedBInputs m => FeedBEffect m where
  nextB = do
    liftIO (threadDelay 60000)
    pure "20"

instance ParserAInputs m => ParserAEffect m where
  getLevelA = do
    raw <- nextA
    case reads raw of
      [(value, "")] -> pure (LevelA (Level value))
      _ -> raise (ParserAError raw)

instance ParserBInputs m => ParserBEffect m where
  getLevelB = do
    raw <- nextB
    case reads raw of
      [(value, "")] -> pure (LevelB (Level value))
      _ -> raise (ParserBError raw)

instance ShowAInputs m => ShowAEffect m where
  showA = do
    samples <- require @LevelA
    case latest samples of
      Just (LevelA (Level value)) -> liftIO (putStrLn ("[level] " ++ show value ++ " at delivery " ++ show (historySize samples)))
      Nothing -> pure ()
    when (historySize samples >= 3) (raise (ShowAError "enough deliveries"))
    pure Nothing

instance ShowBInputs m => ShowBEffect m where
  showB = do
    samples <- require @LevelB
    case latest samples of
      Just (LevelB (Level value)) -> liftIO (putStrLn ("[level] " ++ show value ++ " at delivery " ++ show (historySize samples)))
      Nothing -> pure ()
    when (historySize samples >= 3) (raise (ShowBError "enough deliveries"))
    pure Nothing
