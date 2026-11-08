-- handler 是不带参数的类方法：按表示类型 require 资产，用 raw 读取挂接上游的本次输出，
-- 用 raise 报告自己的失败；不出现上游 effect、scope、细化资产或 effect 错误。
{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE UndecidableInstances #-}

{-# OPTIONS_GHC -Werror=missing-methods #-}

module FacadeProbe.Handlers () where

import Framework.SDK (History, Raises(..), Raw(..), Reads(..), historySize, latest)
import FacadeProbe.Generated.Effects
import FacadeProbe.Types
import Control.Concurrent (threadDelay)
import Control.Monad (when)
import Control.Monad.IO.Class (liftIO)
import System.FilePath ((</>))
import System.IO (IOMode(WriteMode), hClose, hFlush, hPutStr, openFile, readFile')

instance ReportLocationLayer m => ReportLocationHandler m where
  reportLocation = pure ("demo" </> "FacadeProbe" </> "output" </> "report.txt")

instance ReplyLocationLayer m => ReplyLocationHandler m where
  replyLocation = pure ("demo" </> "FacadeProbe" </> "output" </> "reply.txt")

instance ReportDraftLayer m => ReportDraftHandler m where
  reportDraft = pure (Body "report line 1\nreport line 2\nreport line 3\n")

instance ReplyDraftLayer m => ReplyDraftHandler m where
  replyDraft = pure (Body "reply line 1\n")

instance AcquireFileLayer m => AcquireFileHandler m where
  acquireFile = do
    path <- require @FilePath
    file <- liftIO (openFile path WriteMode)
    pure (TextFile path file)

instance OpenTextFileLayer m => OpenTextFileHandler m where
  openTextFile = do
    TextFile path _ <- require @TextFile
    liftIO (putStrLn ("[open] " ++ path))
    pure Nothing

instance CloseTextFileLayer m => CloseTextFileHandler m where
  closeTextFile = do
    TextFile path file <- require @TextFile
    liftIO (hClose file >> putStrLn ("[close] " ++ path))
    pure Nothing

instance WriteTextLayer m => WriteTextHandler m where
  writeText = do
    TextFile path file <- require @TextFile
    Body text <- require @Body
    liftIO (hPutStr file text >> hFlush file >> putStrLn ("[write] " ++ path))
    pure Nothing

instance MarkReadLayer m => MarkReadHandler m where
  markRead = do
    liftIO (putStrLn "[mark] before reading")
    pure Nothing

instance ReadTextLayer m => ReadTextHandler m where
  readText = do
    path <- require @FilePath
    contents <- liftIO (readFile' path)
    pure (Just contents)

instance CountLinesLayer m => CountLinesHandler m where
  countLines = do
    output <- raw
    contents <- maybe (raise (CountLinesError "no text")) pure output
    pure (LineCount (length (lines contents)))

instance ShowCountLayer m => ShowCountHandler m where
  showCount = do
    LineCount count <- require @LineCount
    liftIO (putStrLn ("[lines] " ++ show count))
    pure Nothing

instance InspectFileLayer m => InspectFileHandler m where
  inspectFile = do
    path <- require @FilePath
    contents <- liftIO (readFile' path)
    pure (if null contents then Blank else Filled (Body contents))

instance DescribeBlankLayer m => DescribeBlankHandler m where
  describeBlank = do
    liftIO (putStrLn "[state] blank")
    pure Nothing

instance DescribeFilledLayer m => DescribeFilledHandler m where
  describeFilled = do
    Body text <- require @Body
    liftIO (putStrLn ("[state] filled, " ++ show (length text) ++ " characters"))
    pure Nothing

instance NextALayer m => NextAHandler m where
  nextA = do
    liftIO (threadDelay 40000)
    pure "10"

instance NextBLayer m => NextBHandler m where
  nextB = do
    liftIO (threadDelay 60000)
    pure "20"

instance ParseLevelLayer m => ParseLevelHandler m where
  parseLevel = do
    reading <- maybe "" id <$> raw
    case reads reading of
      [(value, "")] -> pure (Level value)
      _ -> raise (ParseLevelError reading)

-- ShowA 与 ShowB 共用；失败按 handler 固定为 ShowLevelError，origin 仍是具体的 effect。
instance ShowLevelLayer m => ShowLevelHandler m where
  showLevel = do
    samples <- require @(History Level)
    case latest samples of
      Just (Level value) -> liftIO (putStrLn ("[level] " ++ show value ++ " at delivery " ++ show (historySize samples)))
      Nothing -> pure ()
    when (historySize samples >= 3) (raise (ShowLevelError "enough deliveries"))
    pure Nothing
