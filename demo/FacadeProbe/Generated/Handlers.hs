-- 自动生成的编译副本；请修改上级 Handlers.hs 后重新生成。
{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE UndecidableInstances #-}
-- handler 是不带参数的类方法：按表示类型 require 资产，用 raw 读取挂接上游的本次输出，
-- 用 raise 报告自己的失败；不出现上游 effect、scope、细化资产或 effect 错误。
{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE UndecidableInstances #-}

{-# OPTIONS_GHC -Werror=missing-methods #-}

module FacadeProbe.Generated.Handlers (handlerSourceFingerprint, getReportPath, readReportPath, getReplyPath, readReplyPath, getReportBody, readReportBody, getReplyBody, readReplyBody, getOpenedReport, readOpenedReport, getOpenedReply, readOpenedReply, openReportScope, closeReportScope, openReplyScope, closeReplyScope, runWriteReport, runWriteReply, runMarkReply, runReadReport, runReadReply, getReportStats, readReportStats, getReplyStats, readReplyStats, runShowReport, runShowReply, getReportState, readReportState, runOnBlank, runOnFilled, getCountA, readCountA, getCountB, readCountB, openFeedScopeA, openFeedScopeB, nextFeedA, nextFeedB, getLevelA, streamLevelA, getLevelB, streamLevelB, runShowA, runShowB, newScopeHandlers, errorHandlers) where

import qualified Framework.Generated as FrameworkRuntime
import qualified FacadeProbe.Generated.Effects as FrameworkGenerated
import qualified Control.Monad.IO.Class as FrameworkIO
import qualified Data.Proxy as FrameworkProxy
import qualified GHC.TypeLits as FrameworkTypes
import FacadeProbe.Types
import Framework.SDK (Raises(..), Raw(..), Reads(..))
import FacadeProbe.Generated.Effects
import FacadeProbe.Types
import Control.Concurrent (threadDelay)
import Control.Monad (when)
import Control.Monad.IO.Class (liftIO)
import Data.IORef (atomicModifyIORef', newIORef)
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
    pure []

instance CloseTextFileLayer m => CloseTextFileHandler m where
  closeTextFile = do
    TextFile path file <- require @TextFile
    liftIO (hClose file >> putStrLn ("[close] " ++ path))
    pure []

instance WriteTextLayer m => WriteTextHandler m where
  writeText = do
    TextFile path file <- require @TextFile
    Body text <- require @Body
    liftIO (hPutStr file text >> hFlush file >> putStrLn ("[write] " ++ path))
    pure []

instance MarkReadLayer m => MarkReadHandler m where
  markRead = do
    liftIO (putStrLn "[mark] before reading")
    pure []

instance ReadTextLayer m => ReadTextHandler m where
  readText = do
    path <- require @FilePath
    contents <- liftIO (readFile' path)
    pure [contents]

instance CountLinesLayer m => CountLinesHandler m where
  countLines = do
    output <- raw
    contents <- case output of
      [text] -> pure text
      _ -> raise (CountLinesError "no text")
    pure (LineCount (length (lines contents)))

instance ShowCountLayer m => ShowCountHandler m where
  showCount = do
    LineCount count <- require @LineCount
    liftIO (putStrLn ("[lines] " ++ show count))
    pure []

instance InspectFileLayer m => InspectFileHandler m where
  inspectFile = do
    path <- require @FilePath
    contents <- liftIO (readFile' path)
    pure (if null contents then Blank else Filled (Body contents))

instance DescribeBlankLayer m => DescribeBlankHandler m where
  describeBlank = do
    liftIO (putStrLn "[state] blank")
    pure []

instance DescribeFilledLayer m => DescribeFilledHandler m where
  describeFilled = do
    Body text <- require @Body
    liftIO (putStrLn ("[state] filled, " ++ show (length text) ++ " characters"))
    pure []

instance NewCounterLayer m => NewCounterHandler m where
  newCounter = liftIO (FeedCounter <$> newIORef 0)

instance OpenCounterLayer m => OpenCounterHandler m where
  openCounter = do
    FeedCounter _ <- require @FeedCounter
    pure []

instance NextALayer m => NextAHandler m where
  nextA = do
    FeedCounter counter <- require @FeedCounter
    liftIO (threadDelay 40000)
    number <- liftIO $ atomicModifyIORef' counter $ \previous ->
      let current = previous + 1 in (current, current)
    pure (show (number, 10 :: Int))

instance NextBLayer m => NextBHandler m where
  nextB = do
    FeedCounter counter <- require @FeedCounter
    liftIO (threadDelay 60000)
    number <- liftIO $ atomicModifyIORef' counter $ \previous ->
      let current = previous + 1 in (current, current)
    pure (show (number, 20 :: Int))

instance ParseLevelLayer m => ParseLevelHandler m where
  parseLevel = do
    reading <- concat <$> raw
    case reads reading of
      [((number, value), "")] -> pure (Level number value)
      _ -> raise (ParseLevelError reading)

-- ShowA 与 ShowB 共用；失败按 handler 固定为 ShowLevelError，origin 仍是具体的 effect。
instance ShowLevelLayer m => ShowLevelHandler m where
  showLevel = do
    Level number value <- require @Level
    liftIO (putStrLn ("[level] " ++ show value ++ " at delivery " ++ show number))
    when (number >= 3) (raise (ShowLevelError "enough deliveries"))
    pure []

-- 记录本编译副本实际使用的手写源码；启动前检查，避免执行过期方法体。
handlerSourceFingerprint :: Maybe String
handlerSourceFingerprint = Just "7a50893a4ee9920737b0ff1ec8675dc8"

-- 以下由 gen 生成。每个 effect 一个类型标签：handler 在标签下执行，
-- 读取、raw 与错误按标签在编译期解析到这个 effect 的来源，不改写 handler 方法体。
newtype Wrap (effect :: FrameworkTypes.Symbol) value = Wrap { runAt :: FrameworkGenerated.App value }
  deriving (Functor, Applicative, Monad, FrameworkIO.MonadIO)

instance FrameworkRuntime.Root (Wrap effect) value

instance FrameworkTypes.KnownSymbol effect => FrameworkRuntime.Raises FrameworkGenerated.ReportLocationError (Wrap effect) where
  raise (FrameworkGenerated.ReportLocationError description) = Wrap (FrameworkRuntime.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) FrameworkGenerated.ReportLocationFailure description)

instance FrameworkTypes.KnownSymbol effect => FrameworkRuntime.Raises FrameworkGenerated.ReplyLocationError (Wrap effect) where
  raise (FrameworkGenerated.ReplyLocationError description) = Wrap (FrameworkRuntime.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) FrameworkGenerated.ReplyLocationFailure description)

instance FrameworkTypes.KnownSymbol effect => FrameworkRuntime.Raises FrameworkGenerated.ReportDraftError (Wrap effect) where
  raise (FrameworkGenerated.ReportDraftError description) = Wrap (FrameworkRuntime.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) FrameworkGenerated.ReportDraftFailure description)

instance FrameworkTypes.KnownSymbol effect => FrameworkRuntime.Raises FrameworkGenerated.ReplyDraftError (Wrap effect) where
  raise (FrameworkGenerated.ReplyDraftError description) = Wrap (FrameworkRuntime.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) FrameworkGenerated.ReplyDraftFailure description)

instance FrameworkTypes.KnownSymbol effect => FrameworkRuntime.Raises FrameworkGenerated.AcquireFileError (Wrap effect) where
  raise (FrameworkGenerated.AcquireFileError description) = Wrap (FrameworkRuntime.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) FrameworkGenerated.AcquireFileFailure description)

instance FrameworkTypes.KnownSymbol effect => FrameworkRuntime.Raises FrameworkGenerated.OpenTextFileError (Wrap effect) where
  raise (FrameworkGenerated.OpenTextFileError description) = Wrap (FrameworkRuntime.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) FrameworkGenerated.OpenTextFileFailure description)

instance FrameworkTypes.KnownSymbol effect => FrameworkRuntime.Raises FrameworkGenerated.CloseTextFileError (Wrap effect) where
  raise (FrameworkGenerated.CloseTextFileError description) = Wrap (FrameworkRuntime.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) FrameworkGenerated.CloseTextFileFailure description)

instance FrameworkTypes.KnownSymbol effect => FrameworkRuntime.Raises FrameworkGenerated.WriteTextError (Wrap effect) where
  raise (FrameworkGenerated.WriteTextError description) = Wrap (FrameworkRuntime.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) FrameworkGenerated.WriteTextFailure description)

instance FrameworkTypes.KnownSymbol effect => FrameworkRuntime.Raises FrameworkGenerated.MarkReadError (Wrap effect) where
  raise (FrameworkGenerated.MarkReadError description) = Wrap (FrameworkRuntime.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) FrameworkGenerated.MarkReadFailure description)

instance FrameworkTypes.KnownSymbol effect => FrameworkRuntime.Raises FrameworkGenerated.ReadTextError (Wrap effect) where
  raise (FrameworkGenerated.ReadTextError description) = Wrap (FrameworkRuntime.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) FrameworkGenerated.ReadTextFailure description)

instance FrameworkTypes.KnownSymbol effect => FrameworkRuntime.Raises FrameworkGenerated.CountLinesError (Wrap effect) where
  raise (FrameworkGenerated.CountLinesError description) = Wrap (FrameworkRuntime.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) FrameworkGenerated.CountLinesFailure description)

instance FrameworkTypes.KnownSymbol effect => FrameworkRuntime.Raises FrameworkGenerated.ShowCountError (Wrap effect) where
  raise (FrameworkGenerated.ShowCountError description) = Wrap (FrameworkRuntime.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) FrameworkGenerated.ShowCountFailure description)

instance FrameworkTypes.KnownSymbol effect => FrameworkRuntime.Raises FrameworkGenerated.InspectFileError (Wrap effect) where
  raise (FrameworkGenerated.InspectFileError description) = Wrap (FrameworkRuntime.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) FrameworkGenerated.InspectFileFailure description)

instance FrameworkTypes.KnownSymbol effect => FrameworkRuntime.Raises FrameworkGenerated.DescribeBlankError (Wrap effect) where
  raise (FrameworkGenerated.DescribeBlankError description) = Wrap (FrameworkRuntime.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) FrameworkGenerated.DescribeBlankFailure description)

instance FrameworkTypes.KnownSymbol effect => FrameworkRuntime.Raises FrameworkGenerated.DescribeFilledError (Wrap effect) where
  raise (FrameworkGenerated.DescribeFilledError description) = Wrap (FrameworkRuntime.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) FrameworkGenerated.DescribeFilledFailure description)

instance FrameworkTypes.KnownSymbol effect => FrameworkRuntime.Raises FrameworkGenerated.NewCounterError (Wrap effect) where
  raise (FrameworkGenerated.NewCounterError description) = Wrap (FrameworkRuntime.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) FrameworkGenerated.NewCounterFailure description)

instance FrameworkTypes.KnownSymbol effect => FrameworkRuntime.Raises FrameworkGenerated.OpenCounterError (Wrap effect) where
  raise (FrameworkGenerated.OpenCounterError description) = Wrap (FrameworkRuntime.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) FrameworkGenerated.OpenCounterFailure description)

instance FrameworkTypes.KnownSymbol effect => FrameworkRuntime.Raises FrameworkGenerated.NextAError (Wrap effect) where
  raise (FrameworkGenerated.NextAError description) = Wrap (FrameworkRuntime.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) FrameworkGenerated.NextAFailure description)

instance FrameworkTypes.KnownSymbol effect => FrameworkRuntime.Raises FrameworkGenerated.NextBError (Wrap effect) where
  raise (FrameworkGenerated.NextBError description) = Wrap (FrameworkRuntime.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) FrameworkGenerated.NextBFailure description)

instance FrameworkTypes.KnownSymbol effect => FrameworkRuntime.Raises FrameworkGenerated.ParseLevelError (Wrap effect) where
  raise (FrameworkGenerated.ParseLevelError description) = Wrap (FrameworkRuntime.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) FrameworkGenerated.ParseLevelFailure description)

instance FrameworkTypes.KnownSymbol effect => FrameworkRuntime.Raises FrameworkGenerated.ShowLevelError (Wrap effect) where
  raise (FrameworkGenerated.ShowLevelError description) = Wrap (FrameworkRuntime.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) FrameworkGenerated.ShowLevelFailure description)

instance FrameworkRuntime.Reads ([Char]) (Wrap "ReportFile") where
  require = Wrap ((\(FrameworkGenerated.ReportPath value) -> value) <$> readReportPath)

instance FrameworkRuntime.Reads ([Char]) (Wrap "ReplyFile") where
  require = Wrap ((\(FrameworkGenerated.ReplyPath value) -> value) <$> readReplyPath)

instance FrameworkRuntime.Reads (TextFile) (Wrap "ReportScope") where
  require = Wrap ((\(FrameworkGenerated.OpenedReport value) -> value) <$> readOpenedReport)

instance FrameworkRuntime.Reads (TextFile) (Wrap "ReplyScope") where
  require = Wrap ((\(FrameworkGenerated.OpenedReply value) -> value) <$> readOpenedReply)

instance FrameworkRuntime.Reads (TextFile) (Wrap "WriteReport") where
  require = Wrap ((\(FrameworkGenerated.OpenedReport value) -> value) <$> readOpenedReport)

instance FrameworkRuntime.Reads (Body) (Wrap "WriteReport") where
  require = Wrap ((\(FrameworkGenerated.ReportBody value) -> value) <$> readReportBody)

instance FrameworkRuntime.Reads (TextFile) (Wrap "WriteReply") where
  require = Wrap ((\(FrameworkGenerated.OpenedReply value) -> value) <$> readOpenedReply)

instance FrameworkRuntime.Reads (Body) (Wrap "WriteReply") where
  require = Wrap ((\(FrameworkGenerated.ReplyBody value) -> value) <$> readReplyBody)

instance FrameworkRuntime.Reads ([Char]) (Wrap "ReadReport") where
  require = Wrap ((\(FrameworkGenerated.ReportPath value) -> value) <$> readReportPath)

instance FrameworkRuntime.Reads ([Char]) (Wrap "ReadReply") where
  require = Wrap ((\(FrameworkGenerated.ReplyPath value) -> value) <$> readReplyPath)

instance FrameworkRuntime.Reads (LineCount) (Wrap "ShowReport") where
  require = Wrap ((\(FrameworkGenerated.ReportStats value) -> value) <$> readReportStats)

instance FrameworkRuntime.Reads (LineCount) (Wrap "ShowReply") where
  require = Wrap ((\(FrameworkGenerated.ReplyStats value) -> value) <$> readReplyStats)

instance FrameworkRuntime.Reads ([Char]) (Wrap "ReportInspect") where
  require = Wrap ((\(FrameworkGenerated.ReportPath value) -> value) <$> readReportPath)

instance FrameworkRuntime.Reads (()) (Wrap "OnBlank") where
  require = Wrap (FrameworkRuntime.projectContext "ReportInspect" "ReportStateBlank" FrameworkGenerated.ContextBindingError (\(FrameworkGenerated.ReportState value) -> case value of { Blank -> Just (); _ -> Nothing }) (readReportState))

instance FrameworkRuntime.Reads (Body) (Wrap "OnFilled") where
  require = Wrap (FrameworkRuntime.projectContext "ReportInspect" "ReportStateFilled" FrameworkGenerated.ContextBindingError (\(FrameworkGenerated.ReportState value) -> case value of { Filled field -> Just field; _ -> Nothing }) (readReportState))

instance FrameworkRuntime.Reads (FeedCounter) (Wrap "FeedScopeA") where
  require = Wrap ((\(FrameworkGenerated.CountA value) -> value) <$> readCountA)

instance FrameworkRuntime.Reads (FeedCounter) (Wrap "FeedScopeB") where
  require = Wrap ((\(FrameworkGenerated.CountB value) -> value) <$> readCountB)

instance FrameworkRuntime.Reads (FeedCounter) (Wrap "FeedA") where
  require = Wrap ((\(FrameworkGenerated.CountA value) -> value) <$> readCountA)

instance FrameworkRuntime.Reads (FeedCounter) (Wrap "FeedB") where
  require = Wrap ((\(FrameworkGenerated.CountB value) -> value) <$> readCountB)

instance FrameworkRuntime.Reads (Level) (Wrap "ShowA") where
  require = Wrap ((\(FrameworkGenerated.LevelA value) -> value) <$> streamLevelA)

instance FrameworkRuntime.Reads (Level) (Wrap "ShowB") where
  require = Wrap ((\(FrameworkGenerated.LevelB value) -> value) <$> streamLevelB)

instance FrameworkRuntime.Raw (Wrap "ReportCounter") where
  raw = Wrap (runReadReport)

instance FrameworkRuntime.Raw (Wrap "ReplyCounter") where
  raw = Wrap (runReadReply)

instance FrameworkRuntime.Raw (Wrap "ParserA") where
  raw = Wrap ((: []) <$> nextFeedA)

instance FrameworkRuntime.Raw (Wrap "ParserB") where
  raw = Wrap ((: []) <$> nextFeedB)

instance FrameworkRuntime.StreamEnds (Wrap "FeedA") where
  streamEnd = Wrap FrameworkRuntime.endSource

instance FrameworkRuntime.StreamEnds (Wrap "FeedB") where
  streamEnd = Wrap FrameworkRuntime.endSource

instance FrameworkRuntime.EndsStream (Wrap "ShowA") where
  endStream = Wrap FrameworkRuntime.endSubscription

instance FrameworkRuntime.EndsStream (Wrap "ShowB") where
  endStream = Wrap FrameworkRuntime.endSubscription

getReportPath :: FrameworkGenerated.App FrameworkGenerated.ReportPath
getReportPath = (FrameworkRuntime.withErrorPath [] . FrameworkRuntime.handleFailure . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.callContext "ReportLocation"
    (\value bindings -> bindings { FrameworkGenerated.boundReportLocation = Just value })) $
  (FrameworkGenerated.ReportPath <$> runAt @"ReportLocation" (FrameworkRuntime.super "reportLocation" FrameworkGenerated.reportLocation))

readReportPath :: FrameworkGenerated.App FrameworkGenerated.ReportPath
readReportPath = (FrameworkRuntime.withErrorPath [] . FrameworkRuntime.handleFailure) $
  FrameworkRuntime.readContext "ReportLocation" FrameworkGenerated.ContextBindingError FrameworkGenerated.boundReportLocation

getReplyPath :: FrameworkGenerated.App FrameworkGenerated.ReplyPath
getReplyPath = (FrameworkRuntime.withErrorPath [] . FrameworkRuntime.handleFailure . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.callContext "ReplyLocation"
    (\value bindings -> bindings { FrameworkGenerated.boundReplyLocation = Just value })) $
  (FrameworkGenerated.ReplyPath <$> runAt @"ReplyLocation" (FrameworkRuntime.super "replyLocation" FrameworkGenerated.replyLocation))

readReplyPath :: FrameworkGenerated.App FrameworkGenerated.ReplyPath
readReplyPath = (FrameworkRuntime.withErrorPath [] . FrameworkRuntime.handleFailure) $
  FrameworkRuntime.readContext "ReplyLocation" FrameworkGenerated.ContextBindingError FrameworkGenerated.boundReplyLocation

getReportBody :: FrameworkGenerated.App FrameworkGenerated.ReportBody
getReportBody = (FrameworkRuntime.withErrorPath [] . FrameworkRuntime.handleFailure . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.callContext "ReportDraft"
    (\value bindings -> bindings { FrameworkGenerated.boundReportDraft = Just value })) $
  (FrameworkGenerated.ReportBody <$> runAt @"ReportDraft" (FrameworkRuntime.super "reportDraft" FrameworkGenerated.reportDraft))

readReportBody :: FrameworkGenerated.App FrameworkGenerated.ReportBody
readReportBody = (FrameworkRuntime.withErrorPath [] . FrameworkRuntime.handleFailure) $
  FrameworkRuntime.readContext "ReportDraft" FrameworkGenerated.ContextBindingError FrameworkGenerated.boundReportDraft

getReplyBody :: FrameworkGenerated.App FrameworkGenerated.ReplyBody
getReplyBody = (FrameworkRuntime.withErrorPath [] . FrameworkRuntime.handleFailure . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.callContext "ReplyDraft"
    (\value bindings -> bindings { FrameworkGenerated.boundReplyDraft = Just value })) $
  (FrameworkGenerated.ReplyBody <$> runAt @"ReplyDraft" (FrameworkRuntime.super "replyDraft" FrameworkGenerated.replyDraft))

readReplyBody :: FrameworkGenerated.App FrameworkGenerated.ReplyBody
readReplyBody = (FrameworkRuntime.withErrorPath [] . FrameworkRuntime.handleFailure) $
  FrameworkRuntime.readContext "ReplyDraft" FrameworkGenerated.ContextBindingError FrameworkGenerated.boundReplyDraft

getOpenedReport :: FrameworkGenerated.App FrameworkGenerated.OpenedReport
getOpenedReport = (FrameworkRuntime.withErrorPath [] . FrameworkRuntime.handleFailure . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.callContext "ReportFile"
    (\value bindings -> bindings { FrameworkGenerated.boundReportFile = Just value })) $
  getReportPath >> (FrameworkGenerated.OpenedReport <$> runAt @"ReportFile" (FrameworkRuntime.super "acquireFile" FrameworkGenerated.acquireFile))

readOpenedReport :: FrameworkGenerated.App FrameworkGenerated.OpenedReport
readOpenedReport = (FrameworkRuntime.withErrorPath [] . FrameworkRuntime.handleFailure) $
  FrameworkRuntime.readContext "ReportFile" FrameworkGenerated.ContextBindingError FrameworkGenerated.boundReportFile

getOpenedReply :: FrameworkGenerated.App FrameworkGenerated.OpenedReply
getOpenedReply = (FrameworkRuntime.withErrorPath [] . FrameworkRuntime.handleFailure . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.callContext "ReplyFile"
    (\value bindings -> bindings { FrameworkGenerated.boundReplyFile = Just value })) $
  getReplyPath >> (FrameworkGenerated.OpenedReply <$> runAt @"ReplyFile" (FrameworkRuntime.super "acquireFile" FrameworkGenerated.acquireFile))

readOpenedReply :: FrameworkGenerated.App FrameworkGenerated.OpenedReply
readOpenedReply = (FrameworkRuntime.withErrorPath [] . FrameworkRuntime.handleFailure) $
  FrameworkRuntime.readContext "ReplyFile" FrameworkGenerated.ContextBindingError FrameworkGenerated.boundReplyFile

openReportScope :: FrameworkGenerated.App [String]
openReportScope = (FrameworkRuntime.withErrorPath ["ReportScope"] . FrameworkRuntime.handleFailure . FrameworkRuntime.atomicScope "openReportScope" [] [] . FrameworkRuntime.openScope "ReportScope" FrameworkGenerated.ScopeBindingError (Just (() <$ closeReportScope)) . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.enterHandler "ReportScope") $
  getOpenedReport >> runAt @"ReportScope" (FrameworkRuntime.super "openTextFile" FrameworkGenerated.openTextFile)

closeReportScope :: FrameworkGenerated.App [String]
closeReportScope = (FrameworkRuntime.withErrorPath ["ReportScope"] . FrameworkRuntime.handleFailure . FrameworkRuntime.atomicScope "closeReportScope" [] [] . FrameworkRuntime.closeScope "ReportScope" FrameworkGenerated.ScopeBindingError . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.enterHandler "ReportScope") $
  runAt @"ReportScope" (FrameworkRuntime.superClose "closeTextFile" FrameworkGenerated.closeTextFile)

openReplyScope :: FrameworkGenerated.App [String]
openReplyScope = (FrameworkRuntime.withErrorPath ["ReplyScope"] . FrameworkRuntime.handleFailure . FrameworkRuntime.atomicScope "openReplyScope" [] [] . FrameworkRuntime.openScope "ReplyScope" FrameworkGenerated.ScopeBindingError (Just (() <$ closeReplyScope)) . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.enterHandler "ReplyScope") $
  getOpenedReply >> runAt @"ReplyScope" (FrameworkRuntime.super "openTextFile" FrameworkGenerated.openTextFile)

closeReplyScope :: FrameworkGenerated.App [String]
closeReplyScope = (FrameworkRuntime.withErrorPath ["ReplyScope"] . FrameworkRuntime.handleFailure . FrameworkRuntime.atomicScope "closeReplyScope" [] [] . FrameworkRuntime.closeScope "ReplyScope" FrameworkGenerated.ScopeBindingError . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.enterHandler "ReplyScope") $
  runAt @"ReplyScope" (FrameworkRuntime.superClose "closeTextFile" FrameworkGenerated.closeTextFile)

runWriteReport :: FrameworkGenerated.App [String]
runWriteReport = (FrameworkRuntime.withErrorPath ["ReportScope"] . FrameworkRuntime.handleFailure . FrameworkRuntime.atomicHandle "runWriteReport" [] [] . FrameworkRuntime.withScopeDependencies ["ReportScope"] . FrameworkRuntime.enterHandler "WriteReport") $
  getReportBody >> openReportScope >> runAt @"WriteReport" (FrameworkRuntime.super "writeText" FrameworkGenerated.writeText)

runWriteReply :: FrameworkGenerated.App [String]
runWriteReply = (FrameworkRuntime.withErrorPath ["ReplyScope"] . FrameworkRuntime.handleFailure . FrameworkRuntime.atomicHandle "runWriteReply" [] [] . FrameworkRuntime.withScopeDependencies ["ReplyScope"] . FrameworkRuntime.enterHandler "WriteReply") $
  getReplyBody >> openReplyScope >> runAt @"WriteReply" (FrameworkRuntime.super "writeText" FrameworkGenerated.writeText)

runMarkReply :: FrameworkGenerated.App [String]
runMarkReply = (FrameworkRuntime.withErrorPath [] . FrameworkRuntime.handleFailure . FrameworkRuntime.atomicHandle "runMarkReply" [] [] . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.enterHandler "MarkReply") $
  runAt @"MarkReply" (FrameworkRuntime.super "markRead" FrameworkGenerated.markRead)

runReadReport :: FrameworkGenerated.App [String]
runReadReport = (FrameworkRuntime.withErrorPath [] . FrameworkRuntime.handleFailure . FrameworkRuntime.atomicHandle "runReadReport" [("ReportCounter", () <$ getReportStats)] [] . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.enterHandler "ReadReport") $
  runAt @"ReadReport" (FrameworkRuntime.super "readText" FrameworkGenerated.readText)

runReadReply :: FrameworkGenerated.App [String]
runReadReply = (FrameworkRuntime.withErrorPath [] . FrameworkRuntime.handleFailure . FrameworkRuntime.atomicHandle "runReadReply" [("ReplyCounter", () <$ getReplyStats)] [] . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.enterHandler "ReadReply") $
  runMarkReply >> runAt @"ReadReply" (FrameworkRuntime.super "readText" FrameworkGenerated.readText)

getReportStats :: FrameworkGenerated.App FrameworkGenerated.ReportStats
getReportStats = (FrameworkRuntime.withErrorPath [] . FrameworkRuntime.handleFailure . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.callContext "ReportCounter"
    (\value bindings -> bindings { FrameworkGenerated.boundReportCounter = Just value })) $
  (FrameworkGenerated.ReportStats <$> runAt @"ReportCounter" (FrameworkRuntime.super "countLines" FrameworkGenerated.countLines))

readReportStats :: FrameworkGenerated.App FrameworkGenerated.ReportStats
readReportStats = (FrameworkRuntime.withErrorPath [] . FrameworkRuntime.handleFailure) $
  FrameworkRuntime.readContext "ReportCounter" FrameworkGenerated.ContextBindingError FrameworkGenerated.boundReportCounter

getReplyStats :: FrameworkGenerated.App FrameworkGenerated.ReplyStats
getReplyStats = (FrameworkRuntime.withErrorPath [] . FrameworkRuntime.handleFailure . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.callContext "ReplyCounter"
    (\value bindings -> bindings { FrameworkGenerated.boundReplyCounter = Just value })) $
  (FrameworkGenerated.ReplyStats <$> runAt @"ReplyCounter" (FrameworkRuntime.super "countLines" FrameworkGenerated.countLines))

readReplyStats :: FrameworkGenerated.App FrameworkGenerated.ReplyStats
readReplyStats = (FrameworkRuntime.withErrorPath [] . FrameworkRuntime.handleFailure) $
  FrameworkRuntime.readContext "ReplyCounter" FrameworkGenerated.ContextBindingError FrameworkGenerated.boundReplyCounter

runShowReport :: FrameworkGenerated.App [String]
runShowReport = (FrameworkRuntime.withErrorPath [] . FrameworkRuntime.handleFailure . FrameworkRuntime.atomicHandle "runShowReport" [] [] . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.enterHandler "ShowReport") $
  runAt @"ShowReport" (FrameworkRuntime.super "showCount" FrameworkGenerated.showCount)

runShowReply :: FrameworkGenerated.App [String]
runShowReply = (FrameworkRuntime.withErrorPath [] . FrameworkRuntime.handleFailure . FrameworkRuntime.atomicHandle "runShowReply" [] [] . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.enterHandler "ShowReply") $
  runAt @"ShowReply" (FrameworkRuntime.super "showCount" FrameworkGenerated.showCount)

getReportState :: FrameworkGenerated.App FrameworkGenerated.ReportState
getReportState = (FrameworkRuntime.withErrorPath [] . FrameworkRuntime.handleFailure . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.callContext "ReportInspect"
    (\value bindings -> bindings { FrameworkGenerated.boundReportInspect = Just value })) $
  (FrameworkGenerated.ReportState <$> runAt @"ReportInspect" (FrameworkRuntime.super "inspectFile" FrameworkGenerated.inspectFile))

readReportState :: FrameworkGenerated.App FrameworkGenerated.ReportState
readReportState = (FrameworkRuntime.withErrorPath [] . FrameworkRuntime.handleFailure) $
  FrameworkRuntime.readContext "ReportInspect" FrameworkGenerated.ContextBindingError FrameworkGenerated.boundReportInspect

runOnBlank :: FrameworkGenerated.App [String]
runOnBlank = (FrameworkRuntime.withErrorPath [] . FrameworkRuntime.handleFailure . FrameworkRuntime.atomicHandle "runOnBlank" [] [] . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.enterHandler "OnBlank") $
  runAt @"OnBlank" (FrameworkRuntime.super "describeBlank" FrameworkGenerated.describeBlank)

runOnFilled :: FrameworkGenerated.App [String]
runOnFilled = (FrameworkRuntime.withErrorPath [] . FrameworkRuntime.handleFailure . FrameworkRuntime.atomicHandle "runOnFilled" [] [] . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.enterHandler "OnFilled") $
  runAt @"OnFilled" (FrameworkRuntime.super "describeFilled" FrameworkGenerated.describeFilled)

getCountA :: FrameworkGenerated.App FrameworkGenerated.CountA
getCountA = (FrameworkRuntime.withErrorPath [] . FrameworkRuntime.handleFailure . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.callContext "CounterA"
    (\value bindings -> bindings { FrameworkGenerated.boundCounterA = Just value })) $
  (FrameworkGenerated.CountA <$> runAt @"CounterA" (FrameworkRuntime.super "newCounter" FrameworkGenerated.newCounter))

readCountA :: FrameworkGenerated.App FrameworkGenerated.CountA
readCountA = (FrameworkRuntime.withErrorPath [] . FrameworkRuntime.handleFailure) $
  FrameworkRuntime.readContext "CounterA" FrameworkGenerated.ContextBindingError FrameworkGenerated.boundCounterA

getCountB :: FrameworkGenerated.App FrameworkGenerated.CountB
getCountB = (FrameworkRuntime.withErrorPath [] . FrameworkRuntime.handleFailure . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.callContext "CounterB"
    (\value bindings -> bindings { FrameworkGenerated.boundCounterB = Just value })) $
  (FrameworkGenerated.CountB <$> runAt @"CounterB" (FrameworkRuntime.super "newCounter" FrameworkGenerated.newCounter))

readCountB :: FrameworkGenerated.App FrameworkGenerated.CountB
readCountB = (FrameworkRuntime.withErrorPath [] . FrameworkRuntime.handleFailure) $
  FrameworkRuntime.readContext "CounterB" FrameworkGenerated.ContextBindingError FrameworkGenerated.boundCounterB

openFeedScopeA :: FrameworkGenerated.App [String]
openFeedScopeA = (FrameworkRuntime.withErrorPath ["FeedScopeA"] . FrameworkRuntime.handleFailure . FrameworkRuntime.atomicScope "openFeedScopeA" [] [] . FrameworkRuntime.openScope "FeedScopeA" FrameworkGenerated.ScopeBindingError Nothing . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.enterHandler "FeedScopeA") $
  getCountA >> runAt @"FeedScopeA" (FrameworkRuntime.super "openCounter" FrameworkGenerated.openCounter)

openFeedScopeB :: FrameworkGenerated.App [String]
openFeedScopeB = (FrameworkRuntime.withErrorPath ["FeedScopeB"] . FrameworkRuntime.handleFailure . FrameworkRuntime.atomicScope "openFeedScopeB" [] [] . FrameworkRuntime.openScope "FeedScopeB" FrameworkGenerated.ScopeBindingError Nothing . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.enterHandler "FeedScopeB") $
  getCountB >> runAt @"FeedScopeB" (FrameworkRuntime.super "openCounter" FrameworkGenerated.openCounter)

nextFeedA :: FrameworkGenerated.App String
nextFeedA = (FrameworkRuntime.withErrorPath ["FeedScopeA"] . FrameworkRuntime.handleFailure . FrameworkRuntime.streamHandle . FrameworkRuntime.withScopeDependencies ["FeedScopeA"] . FrameworkRuntime.enterHandler "FeedA") $
  openFeedScopeA >> runAt @"FeedA" (FrameworkRuntime.super "nextA" FrameworkGenerated.nextA)

nextFeedB :: FrameworkGenerated.App String
nextFeedB = (FrameworkRuntime.withErrorPath ["FeedScopeB"] . FrameworkRuntime.handleFailure . FrameworkRuntime.streamHandle . FrameworkRuntime.withScopeDependencies ["FeedScopeB"] . FrameworkRuntime.enterHandler "FeedB") $
  openFeedScopeB >> runAt @"FeedB" (FrameworkRuntime.super "nextB" FrameworkGenerated.nextB)

getLevelA :: FrameworkGenerated.App FrameworkGenerated.LevelA
getLevelA = (FrameworkRuntime.withErrorPath ["FeedScopeA"] . FrameworkRuntime.handleFailure . FrameworkRuntime.withScopeDependencies ["FeedScopeA"] . FrameworkRuntime.callContext "ParserA"
    (\value bindings -> bindings { FrameworkGenerated.boundParserA = Just value })) $
  (FrameworkGenerated.LevelA <$> runAt @"ParserA" (FrameworkRuntime.super "parseLevel" FrameworkGenerated.parseLevel))

streamLevelA :: FrameworkGenerated.App FrameworkGenerated.LevelA
streamLevelA = (FrameworkRuntime.withErrorPath ["FeedScopeA"] . FrameworkRuntime.handleFailure) $
  FrameworkRuntime.readStreamContext "ParserA" FrameworkGenerated.ContextBindingError FrameworkGenerated.boundParserA

getLevelB :: FrameworkGenerated.App FrameworkGenerated.LevelB
getLevelB = (FrameworkRuntime.withErrorPath ["FeedScopeB"] . FrameworkRuntime.handleFailure . FrameworkRuntime.withScopeDependencies ["FeedScopeB"] . FrameworkRuntime.callContext "ParserB"
    (\value bindings -> bindings { FrameworkGenerated.boundParserB = Just value })) $
  (FrameworkGenerated.LevelB <$> runAt @"ParserB" (FrameworkRuntime.super "parseLevel" FrameworkGenerated.parseLevel))

streamLevelB :: FrameworkGenerated.App FrameworkGenerated.LevelB
streamLevelB = (FrameworkRuntime.withErrorPath ["FeedScopeB"] . FrameworkRuntime.handleFailure) $
  FrameworkRuntime.readStreamContext "ParserB" FrameworkGenerated.ContextBindingError FrameworkGenerated.boundParserB

runShowA :: FrameworkGenerated.App [String]
runShowA = (FrameworkRuntime.withErrorPath [] . FrameworkRuntime.handleFailure . FrameworkRuntime.atomicHandle "runShowA" [] [] . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.enterHandler "ShowA") $
  runAt @"ShowA" (FrameworkRuntime.super "showLevel" FrameworkGenerated.showLevel)

runShowB :: FrameworkGenerated.App [String]
runShowB = (FrameworkRuntime.withErrorPath [] . FrameworkRuntime.handleFailure . FrameworkRuntime.atomicHandle "runShowB" [] [] . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.enterHandler "ShowB") $
  runAt @"ShowB" (FrameworkRuntime.super "showLevel" FrameworkGenerated.showLevel)

-- SDK 内部：scope 按上游到下游登记，退出时逆序收尾；创建不执行业务方法。
newScopeHandlers :: IO [FrameworkRuntime.ScopeHandler FrameworkGenerated.ContextValues FrameworkGenerated.Errors]
newScopeHandlers = sequence
  [ FrameworkRuntime.newScopeHandler "ReportScope" ["ReportLocation"] (Just "ReportFile")
  , FrameworkRuntime.newScopeHandler "ReplyScope" ["ReplyLocation"] (Just "ReplyFile")
  , FrameworkRuntime.newScopeHandler "FeedScopeA" [] (Just "CounterA")
  , FrameworkRuntime.newScopeHandler "FeedScopeB" [] (Just "CounterB")
  ]

-- Error 回调登记：按 handles 匹配故障的 handler 与协议分类；关联 scope 由 Input 链推导。
errorHandlers :: [(Maybe String, FrameworkRuntime.ErrorHandler FrameworkGenerated.Errors FrameworkGenerated.App)]
errorHandlers =
  [
  ]
