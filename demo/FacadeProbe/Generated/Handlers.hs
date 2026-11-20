-- 自动生成的编译副本；请修改上级 Handlers.hs 后重新生成。
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE ScopedTypeVariables #-}
-- handler 是不带参数的类方法：按表示类型 require 资产，用 rawinput 读取挂接上游的本次输出，
-- 用 raise 报告自己的失败；不出现上游 effect、scope、细化资产或 effect 错误。
{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE UndecidableInstances #-}

{-# OPTIONS_GHC -Werror=missing-methods #-}

module FacadeProbe.Generated.Handlers (handlerSourceFingerprint, getReportPath, readReportPath, getReplyPath, readReplyPath, getReportBody, readReportBody, getReplyBody, readReplyBody, getOpenedReport, readOpenedReport, getOpenedReply, readOpenedReply, openReportScope, closeReportScope, openReplyScope, closeReplyScope, runWriteReport, runWriteReply, runMarkReply, runReadReport, runReadReply, getReportStats, readReportStats, getReplyStats, readReplyStats, runShowReport, runShowReply, getReportState, readReportState, runOnBlank, runOnFilled, getCountA, readCountA, getCountB, readCountB, openFeedScopeA, openFeedScopeB, nextFeedA, nextFeedB, getLevelA, streamLevelA, getLevelB, streamLevelB, runShowA, runShowB, newScopeHandlers, errorHandlers) where

import qualified Framework.Generated as SDK
import qualified FacadeProbe.Generated.Effects as Effects
import qualified Control.Monad.IO.Class as FrameworkIO
import qualified Data.Proxy as FrameworkProxy
import qualified GHC.TypeLits as FrameworkTypes
import Framework.SDK (Emits(rawemit), Raises(..), Raw(..), Reads(..), rawoutput)
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
    rawoutput []

instance CloseTextFileLayer m => CloseTextFileHandler m where
  closeTextFile = do
    TextFile path file <- require @TextFile
    liftIO (hClose file >> putStrLn ("[close] " ++ path))
    rawoutput []

instance WriteTextLayer m => WriteTextHandler m where
  writeText = do
    TextFile path file <- require @TextFile
    Body text <- require @Body
    liftIO (hPutStr file text >> hFlush file >> putStrLn ("[write] " ++ path))
    rawoutput []

instance MarkReadLayer m => MarkReadHandler m where
  markRead = do
    liftIO (putStrLn "[mark] before reading")
    rawoutput []

instance ReadTextLayer m => ReadTextHandler m where
  readText = do
    path <- require @FilePath
    contents <- liftIO (readFile' path)
    rawoutput [contents]

instance CountLinesLayer m => CountLinesHandler m where
  countLines = do
    output <- rawinput
    contents <- case output of
      [text] -> pure text
      _ -> raise (CountLinesError "no text")
    pure (LineCount (length (lines contents)))

instance ShowCountLayer m => ShowCountHandler m where
  showCount = do
    LineCount count <- require @LineCount
    liftIO (putStrLn ("[lines] " ++ show count))
    rawoutput []

instance InspectFileLayer m => InspectFileHandler m where
  inspectFile = do
    path <- require @FilePath
    contents <- liftIO (readFile' path)
    pure (if null contents then Blank else Filled (Body contents))

instance DescribeBlankLayer m => DescribeBlankHandler m where
  describeBlank = do
    liftIO (putStrLn "[state] blank")
    rawoutput []

instance DescribeFilledLayer m => DescribeFilledHandler m where
  describeFilled = do
    Body text <- require @Body
    liftIO (putStrLn ("[state] filled, " ++ show (length text) ++ " characters"))
    rawoutput []

instance NewCounterLayer m => NewCounterHandler m where
  newCounter = liftIO (FeedCounter <$> newIORef 0)

instance OpenCounterLayer m => OpenCounterHandler m where
  openCounter = do
    FeedCounter _ <- require @FeedCounter
    rawoutput []

instance NextALayer m => NextAHandler m where
  nextA = do
    FeedCounter counter <- require @FeedCounter
    liftIO (threadDelay 40000)
    number <- liftIO $ atomicModifyIORef' counter $ \previous ->
      let current = previous + 1 in (current, current)
    rawemit (show (number, 10 :: Int))

instance NextBLayer m => NextBHandler m where
  nextB = do
    FeedCounter counter <- require @FeedCounter
    liftIO (threadDelay 60000)
    number <- liftIO $ atomicModifyIORef' counter $ \previous ->
      let current = previous + 1 in (current, current)
    rawemit (show (number, 20 :: Int))

instance ParseLevelLayer m => ParseLevelHandler m where
  parseLevel = do
    reading <- concat <$> rawinput
    case reads reading of
      [((number, value), "")] -> pure (Level number value)
      _ -> raise (ParseLevelError reading)

-- ShowA 与 ShowB 共用；失败按 handler 固定为 ShowLevelError，origin 仍是具体的 effect。
instance ShowLevelLayer m => ShowLevelHandler m where
  showLevel = do
    Level number value <- require @Level
    liftIO (putStrLn ("[level] " ++ show value ++ " at delivery " ++ show number))
    when (number >= 3) (raise (ShowLevelError "enough deliveries"))
    rawoutput []

-- 记录本编译副本实际使用的手写源码；启动前检查，避免执行过期方法体。
handlerSourceFingerprint :: Maybe String
handlerSourceFingerprint = Just "0a0b686cffa24a432689b625d717b103"

-- 以下由 gen 生成。每个 effect 一个类型标签：handler 在标签下执行，
-- 读取、rawinput 与错误按标签在编译期解析到这个 effect 的来源，不改写 handler 方法体。
newtype Wrap (effect :: FrameworkTypes.Symbol) value = Wrap { runWrap :: Effects.App value }
  deriving (Functor, Applicative, Monad, FrameworkIO.MonadIO)

instance SDK.Root (Wrap effect) value

instance FrameworkTypes.KnownSymbol effect => SDK.Raises Effects.ReportLocationError (Wrap effect) where
  raise (Effects.ReportLocationError description) = Wrap (SDK.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) Effects.ReportLocationFailure description)

instance FrameworkTypes.KnownSymbol effect => SDK.Raises Effects.ReplyLocationError (Wrap effect) where
  raise (Effects.ReplyLocationError description) = Wrap (SDK.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) Effects.ReplyLocationFailure description)

instance FrameworkTypes.KnownSymbol effect => SDK.Raises Effects.ReportDraftError (Wrap effect) where
  raise (Effects.ReportDraftError description) = Wrap (SDK.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) Effects.ReportDraftFailure description)

instance FrameworkTypes.KnownSymbol effect => SDK.Raises Effects.ReplyDraftError (Wrap effect) where
  raise (Effects.ReplyDraftError description) = Wrap (SDK.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) Effects.ReplyDraftFailure description)

instance FrameworkTypes.KnownSymbol effect => SDK.Raises Effects.AcquireFileError (Wrap effect) where
  raise (Effects.AcquireFileError description) = Wrap (SDK.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) Effects.AcquireFileFailure description)

instance FrameworkTypes.KnownSymbol effect => SDK.Raises Effects.OpenTextFileError (Wrap effect) where
  raise (Effects.OpenTextFileError description) = Wrap (SDK.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) Effects.OpenTextFileFailure description)

instance FrameworkTypes.KnownSymbol effect => SDK.Raises Effects.CloseTextFileError (Wrap effect) where
  raise (Effects.CloseTextFileError description) = Wrap (SDK.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) Effects.CloseTextFileFailure description)

instance FrameworkTypes.KnownSymbol effect => SDK.Raises Effects.WriteTextError (Wrap effect) where
  raise (Effects.WriteTextError description) = Wrap (SDK.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) Effects.WriteTextFailure description)

instance FrameworkTypes.KnownSymbol effect => SDK.Raises Effects.MarkReadError (Wrap effect) where
  raise (Effects.MarkReadError description) = Wrap (SDK.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) Effects.MarkReadFailure description)

instance FrameworkTypes.KnownSymbol effect => SDK.Raises Effects.ReadTextError (Wrap effect) where
  raise (Effects.ReadTextError description) = Wrap (SDK.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) Effects.ReadTextFailure description)

instance FrameworkTypes.KnownSymbol effect => SDK.Raises Effects.CountLinesError (Wrap effect) where
  raise (Effects.CountLinesError description) = Wrap (SDK.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) Effects.CountLinesFailure description)

instance FrameworkTypes.KnownSymbol effect => SDK.Raises Effects.ShowCountError (Wrap effect) where
  raise (Effects.ShowCountError description) = Wrap (SDK.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) Effects.ShowCountFailure description)

instance FrameworkTypes.KnownSymbol effect => SDK.Raises Effects.InspectFileError (Wrap effect) where
  raise (Effects.InspectFileError description) = Wrap (SDK.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) Effects.InspectFileFailure description)

instance FrameworkTypes.KnownSymbol effect => SDK.Raises Effects.DescribeBlankError (Wrap effect) where
  raise (Effects.DescribeBlankError description) = Wrap (SDK.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) Effects.DescribeBlankFailure description)

instance FrameworkTypes.KnownSymbol effect => SDK.Raises Effects.DescribeFilledError (Wrap effect) where
  raise (Effects.DescribeFilledError description) = Wrap (SDK.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) Effects.DescribeFilledFailure description)

instance FrameworkTypes.KnownSymbol effect => SDK.Raises Effects.NewCounterError (Wrap effect) where
  raise (Effects.NewCounterError description) = Wrap (SDK.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) Effects.NewCounterFailure description)

instance FrameworkTypes.KnownSymbol effect => SDK.Raises Effects.OpenCounterError (Wrap effect) where
  raise (Effects.OpenCounterError description) = Wrap (SDK.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) Effects.OpenCounterFailure description)

instance FrameworkTypes.KnownSymbol effect => SDK.Raises Effects.NextAError (Wrap effect) where
  raise (Effects.NextAError description) = Wrap (SDK.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) Effects.NextAFailure description)

instance FrameworkTypes.KnownSymbol effect => SDK.Raises Effects.NextBError (Wrap effect) where
  raise (Effects.NextBError description) = Wrap (SDK.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) Effects.NextBFailure description)

instance FrameworkTypes.KnownSymbol effect => SDK.Raises Effects.ParseLevelError (Wrap effect) where
  raise (Effects.ParseLevelError description) = Wrap (SDK.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) Effects.ParseLevelFailure description)

instance FrameworkTypes.KnownSymbol effect => SDK.Raises Effects.ShowLevelError (Wrap effect) where
  raise (Effects.ShowLevelError description) = Wrap (SDK.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) Effects.ShowLevelFailure description)

instance SDK.Reads [Char] (Wrap "ReportFile") where
  require = Wrap (SDK.coerce <$> readReportPath)

instance SDK.Reads [Char] (Wrap "ReplyFile") where
  require = Wrap (SDK.coerce <$> readReplyPath)

instance SDK.Reads TextFile (Wrap "ReportScope") where
  require = Wrap (SDK.coerce <$> readOpenedReport)

instance SDK.Reads TextFile (Wrap "ReplyScope") where
  require = Wrap (SDK.coerce <$> readOpenedReply)

instance SDK.Reads TextFile (Wrap "WriteReport") where
  require = Wrap (SDK.coerce <$> readOpenedReport)

instance SDK.Reads Body (Wrap "WriteReport") where
  require = Wrap (SDK.coerce <$> readReportBody)

instance SDK.Reads TextFile (Wrap "WriteReply") where
  require = Wrap (SDK.coerce <$> readOpenedReply)

instance SDK.Reads Body (Wrap "WriteReply") where
  require = Wrap (SDK.coerce <$> readReplyBody)

instance SDK.Reads [Char] (Wrap "ReadReport") where
  require = Wrap (SDK.coerce <$> readReportPath)

instance SDK.Reads [Char] (Wrap "ReadReply") where
  require = Wrap (SDK.coerce <$> readReplyPath)

instance SDK.Reads LineCount (Wrap "ShowReport") where
  require = Wrap (SDK.coerce <$> readReportStats)

instance SDK.Reads LineCount (Wrap "ShowReply") where
  require = Wrap (SDK.coerce <$> readReplyStats)

instance SDK.Reads [Char] (Wrap "ReportInspect") where
  require = Wrap (SDK.coerce <$> readReportPath)

instance SDK.Reads () (Wrap "OnBlank") where
  require = Wrap (SDK.projectContext "ReportInspect" "ReportStateBlank" Effects.ContextBindingError (\(Effects.ReportState value) -> case value of { Blank -> Just (); _ -> Nothing }) (readReportState))

instance SDK.Reads Body (Wrap "OnFilled") where
  require = Wrap (SDK.projectContext "ReportInspect" "ReportStateFilled" Effects.ContextBindingError (\(Effects.ReportState value) -> case value of { Filled field -> Just field; _ -> Nothing }) (readReportState))

instance SDK.Reads FeedCounter (Wrap "FeedScopeA") where
  require = Wrap (SDK.coerce <$> readCountA)

instance SDK.Reads FeedCounter (Wrap "FeedScopeB") where
  require = Wrap (SDK.coerce <$> readCountB)

instance SDK.Reads FeedCounter (Wrap "FeedA") where
  require = Wrap (SDK.coerce <$> readCountA)

instance SDK.Reads FeedCounter (Wrap "FeedB") where
  require = Wrap (SDK.coerce <$> readCountB)

instance SDK.Reads Level (Wrap "ShowA") where
  require = Wrap (SDK.coerce <$> streamLevelA)

instance SDK.Reads Level (Wrap "ShowB") where
  require = Wrap (SDK.coerce <$> streamLevelB)

instance SDK.Raw (Wrap "ReportCounter") where
  rawinput = Wrap runReadReport

instance SDK.Raw (Wrap "ReplyCounter") where
  rawinput = Wrap runReadReply

instance SDK.Raw (Wrap "ParserA") where
  rawinput = Wrap SDK.emittedInput

instance SDK.Raw (Wrap "ParserB") where
  rawinput = Wrap SDK.emittedInput

instance SDK.RawOutputs (Wrap effect)

instance SDK.Emits (Wrap "FeedA") where
  rawemit text = Wrap (SDK.emitToParser text)

instance SDK.Emits (Wrap "FeedB") where
  rawemit text = Wrap (SDK.emitToParser text)

instance SDK.StreamEnds (Wrap "FeedA") where
  streamEnd = Wrap SDK.endSource

instance SDK.StreamEnds (Wrap "FeedB") where
  streamEnd = Wrap SDK.endSource

instance SDK.EndsStream (Wrap "ShowA") where
  endStream = Wrap SDK.endSubscription

instance SDK.EndsStream (Wrap "ShowB") where
  endStream = Wrap SDK.endSubscription

getReportPath :: Effects.App Effects.ReportPath
getReportPath =
  SDK.handleFailure
  . SDK.callContext "ReportLocation"
      (\value bindings -> bindings { Effects.boundReportLocation = Just value }) $
    Effects.ReportPath <$> runWrap @"ReportLocation" (SDK.super "reportLocation" Effects.reportLocation)

readReportPath :: Effects.App Effects.ReportPath
readReportPath =
  SDK.handleFailure $
    SDK.readContext "ReportLocation" Effects.ContextBindingError Effects.boundReportLocation

getReplyPath :: Effects.App Effects.ReplyPath
getReplyPath =
  SDK.handleFailure
  . SDK.callContext "ReplyLocation"
      (\value bindings -> bindings { Effects.boundReplyLocation = Just value }) $
    Effects.ReplyPath <$> runWrap @"ReplyLocation" (SDK.super "replyLocation" Effects.replyLocation)

readReplyPath :: Effects.App Effects.ReplyPath
readReplyPath =
  SDK.handleFailure $
    SDK.readContext "ReplyLocation" Effects.ContextBindingError Effects.boundReplyLocation

getReportBody :: Effects.App Effects.ReportBody
getReportBody =
  SDK.handleFailure
  . SDK.callContext "ReportDraft"
      (\value bindings -> bindings { Effects.boundReportDraft = Just value }) $
    Effects.ReportBody <$> runWrap @"ReportDraft" (SDK.super "reportDraft" Effects.reportDraft)

readReportBody :: Effects.App Effects.ReportBody
readReportBody =
  SDK.handleFailure $
    SDK.readContext "ReportDraft" Effects.ContextBindingError Effects.boundReportDraft

getReplyBody :: Effects.App Effects.ReplyBody
getReplyBody =
  SDK.handleFailure
  . SDK.callContext "ReplyDraft"
      (\value bindings -> bindings { Effects.boundReplyDraft = Just value }) $
    Effects.ReplyBody <$> runWrap @"ReplyDraft" (SDK.super "replyDraft" Effects.replyDraft)

readReplyBody :: Effects.App Effects.ReplyBody
readReplyBody =
  SDK.handleFailure $
    SDK.readContext "ReplyDraft" Effects.ContextBindingError Effects.boundReplyDraft

getOpenedReport :: Effects.App Effects.OpenedReport
getOpenedReport =
  SDK.handleFailure
  . SDK.callContext "ReportFile"
      (\value bindings -> bindings { Effects.boundReportFile = Just value }) $
    getReportPath >> Effects.OpenedReport <$> runWrap @"ReportFile" (SDK.super "acquireFile" Effects.acquireFile)

readOpenedReport :: Effects.App Effects.OpenedReport
readOpenedReport =
  SDK.handleFailure $
    SDK.readContext "ReportFile" Effects.ContextBindingError Effects.boundReportFile

getOpenedReply :: Effects.App Effects.OpenedReply
getOpenedReply =
  SDK.handleFailure
  . SDK.callContext "ReplyFile"
      (\value bindings -> bindings { Effects.boundReplyFile = Just value }) $
    getReplyPath >> Effects.OpenedReply <$> runWrap @"ReplyFile" (SDK.super "acquireFile" Effects.acquireFile)

readOpenedReply :: Effects.App Effects.OpenedReply
readOpenedReply =
  SDK.handleFailure $
    SDK.readContext "ReplyFile" Effects.ContextBindingError Effects.boundReplyFile

openReportScope :: Effects.App [String]
openReportScope =
  SDK.withErrorPath ["ReportScope"]
  . SDK.handleFailure
  . SDK.atomicScope "openReportScope" [] []
  . SDK.openScope "ReportScope" Effects.ScopeBindingError (Just (() <$ closeReportScope))
  . SDK.enterHandler "ReportScope" $
    getOpenedReport >> runWrap @"ReportScope" (SDK.super "openTextFile" Effects.openTextFile)

closeReportScope :: Effects.App [String]
closeReportScope =
  SDK.withErrorPath ["ReportScope"]
  . SDK.handleFailure
  . SDK.atomicScope "closeReportScope" [] []
  . SDK.closeScope "ReportScope" Effects.ScopeBindingError
  . SDK.enterHandler "ReportScope" $
    runWrap @"ReportScope" (SDK.superClose "closeTextFile" Effects.closeTextFile)

openReplyScope :: Effects.App [String]
openReplyScope =
  SDK.withErrorPath ["ReplyScope"]
  . SDK.handleFailure
  . SDK.atomicScope "openReplyScope" [] []
  . SDK.openScope "ReplyScope" Effects.ScopeBindingError (Just (() <$ closeReplyScope))
  . SDK.enterHandler "ReplyScope" $
    getOpenedReply >> runWrap @"ReplyScope" (SDK.super "openTextFile" Effects.openTextFile)

closeReplyScope :: Effects.App [String]
closeReplyScope =
  SDK.withErrorPath ["ReplyScope"]
  . SDK.handleFailure
  . SDK.atomicScope "closeReplyScope" [] []
  . SDK.closeScope "ReplyScope" Effects.ScopeBindingError
  . SDK.enterHandler "ReplyScope" $
    runWrap @"ReplyScope" (SDK.superClose "closeTextFile" Effects.closeTextFile)

runWriteReport :: Effects.App [String]
runWriteReport =
  SDK.withErrorPath ["ReportScope"]
  . SDK.handleFailure
  . SDK.atomicHandle "runWriteReport" [] []
  . SDK.withScopeDependencies ["ReportScope"]
  . SDK.enterHandler "WriteReport" $
    getReportBody >> openReportScope >> runWrap @"WriteReport" (SDK.super "writeText" Effects.writeText)

runWriteReply :: Effects.App [String]
runWriteReply =
  SDK.withErrorPath ["ReplyScope"]
  . SDK.handleFailure
  . SDK.atomicHandle "runWriteReply" [] []
  . SDK.withScopeDependencies ["ReplyScope"]
  . SDK.enterHandler "WriteReply" $
    getReplyBody >> openReplyScope >> runWrap @"WriteReply" (SDK.super "writeText" Effects.writeText)

runMarkReply :: Effects.App [String]
runMarkReply =
  SDK.handleFailure
  . SDK.atomicHandle "runMarkReply" [] []
  . SDK.enterHandler "MarkReply" $
    runWrap @"MarkReply" (SDK.super "markRead" Effects.markRead)

runReadReport :: Effects.App [String]
runReadReport =
  SDK.handleFailure
  . SDK.atomicHandle "runReadReport" [("ReportCounter", () <$ getReportStats)] []
  . SDK.enterHandler "ReadReport" $
    runWrap @"ReadReport" (SDK.super "readText" Effects.readText)

runReadReply :: Effects.App [String]
runReadReply =
  SDK.handleFailure
  . SDK.atomicHandle "runReadReply" [("ReplyCounter", () <$ getReplyStats)] []
  . SDK.enterHandler "ReadReply" $
    runMarkReply >> runWrap @"ReadReply" (SDK.super "readText" Effects.readText)

getReportStats :: Effects.App Effects.ReportStats
getReportStats =
  SDK.handleFailure
  . SDK.callContext "ReportCounter"
      (\value bindings -> bindings { Effects.boundReportCounter = Just value }) $
    Effects.ReportStats <$> runWrap @"ReportCounter" (SDK.super "countLines" Effects.countLines)

readReportStats :: Effects.App Effects.ReportStats
readReportStats =
  SDK.handleFailure $
    SDK.readContext "ReportCounter" Effects.ContextBindingError Effects.boundReportCounter

getReplyStats :: Effects.App Effects.ReplyStats
getReplyStats =
  SDK.handleFailure
  . SDK.callContext "ReplyCounter"
      (\value bindings -> bindings { Effects.boundReplyCounter = Just value }) $
    Effects.ReplyStats <$> runWrap @"ReplyCounter" (SDK.super "countLines" Effects.countLines)

readReplyStats :: Effects.App Effects.ReplyStats
readReplyStats =
  SDK.handleFailure $
    SDK.readContext "ReplyCounter" Effects.ContextBindingError Effects.boundReplyCounter

runShowReport :: Effects.App [String]
runShowReport =
  SDK.handleFailure
  . SDK.atomicHandle "runShowReport" [] []
  . SDK.enterHandler "ShowReport" $
    runWrap @"ShowReport" (SDK.super "showCount" Effects.showCount)

runShowReply :: Effects.App [String]
runShowReply =
  SDK.handleFailure
  . SDK.atomicHandle "runShowReply" [] []
  . SDK.enterHandler "ShowReply" $
    runWrap @"ShowReply" (SDK.super "showCount" Effects.showCount)

getReportState :: Effects.App Effects.ReportState
getReportState =
  SDK.handleFailure
  . SDK.callContext "ReportInspect"
      (\value bindings -> bindings { Effects.boundReportInspect = Just value }) $
    Effects.ReportState <$> runWrap @"ReportInspect" (SDK.super "inspectFile" Effects.inspectFile)

readReportState :: Effects.App Effects.ReportState
readReportState =
  SDK.handleFailure $
    SDK.readContext "ReportInspect" Effects.ContextBindingError Effects.boundReportInspect

runOnBlank :: Effects.App [String]
runOnBlank =
  SDK.handleFailure
  . SDK.atomicHandle "runOnBlank" [] []
  . SDK.enterHandler "OnBlank" $
    runWrap @"OnBlank" (SDK.super "describeBlank" Effects.describeBlank)

runOnFilled :: Effects.App [String]
runOnFilled =
  SDK.handleFailure
  . SDK.atomicHandle "runOnFilled" [] []
  . SDK.enterHandler "OnFilled" $
    runWrap @"OnFilled" (SDK.super "describeFilled" Effects.describeFilled)

getCountA :: Effects.App Effects.CountA
getCountA =
  SDK.handleFailure
  . SDK.callContext "CounterA"
      (\value bindings -> bindings { Effects.boundCounterA = Just value }) $
    Effects.CountA <$> runWrap @"CounterA" (SDK.super "newCounter" Effects.newCounter)

readCountA :: Effects.App Effects.CountA
readCountA =
  SDK.handleFailure $
    SDK.readContext "CounterA" Effects.ContextBindingError Effects.boundCounterA

getCountB :: Effects.App Effects.CountB
getCountB =
  SDK.handleFailure
  . SDK.callContext "CounterB"
      (\value bindings -> bindings { Effects.boundCounterB = Just value }) $
    Effects.CountB <$> runWrap @"CounterB" (SDK.super "newCounter" Effects.newCounter)

readCountB :: Effects.App Effects.CountB
readCountB =
  SDK.handleFailure $
    SDK.readContext "CounterB" Effects.ContextBindingError Effects.boundCounterB

openFeedScopeA :: Effects.App [String]
openFeedScopeA =
  SDK.withErrorPath ["FeedScopeA"]
  . SDK.handleFailure
  . SDK.atomicScope "openFeedScopeA" [] []
  . SDK.openScope "FeedScopeA" Effects.ScopeBindingError Nothing
  . SDK.enterHandler "FeedScopeA" $
    getCountA >> runWrap @"FeedScopeA" (SDK.super "openCounter" Effects.openCounter)

openFeedScopeB :: Effects.App [String]
openFeedScopeB =
  SDK.withErrorPath ["FeedScopeB"]
  . SDK.handleFailure
  . SDK.atomicScope "openFeedScopeB" [] []
  . SDK.openScope "FeedScopeB" Effects.ScopeBindingError Nothing
  . SDK.enterHandler "FeedScopeB" $
    getCountB >> runWrap @"FeedScopeB" (SDK.super "openCounter" Effects.openCounter)

nextFeedA :: Effects.App ()
nextFeedA =
  SDK.withErrorPath ["FeedScopeA"]
  . SDK.handleFailure
  . SDK.withScopeDependencies ["FeedScopeA"]
  . SDK.enterHandler "FeedA" $
    openFeedScopeA >> runWrap @"FeedA" (SDK.super "nextA" Effects.nextA)

nextFeedB :: Effects.App ()
nextFeedB =
  SDK.withErrorPath ["FeedScopeB"]
  . SDK.handleFailure
  . SDK.withScopeDependencies ["FeedScopeB"]
  . SDK.enterHandler "FeedB" $
    openFeedScopeB >> runWrap @"FeedB" (SDK.super "nextB" Effects.nextB)

getLevelA :: Effects.App Effects.LevelA
getLevelA =
  SDK.withErrorPath ["FeedScopeA"]
  . SDK.handleFailure
  . SDK.withScopeDependencies ["FeedScopeA"]
  . SDK.callContext "ParserA"
      (\value bindings -> bindings { Effects.boundParserA = Just value }) $
    Effects.LevelA <$> runWrap @"ParserA" (SDK.super "parseLevel" Effects.parseLevel)

streamLevelA :: Effects.App Effects.LevelA
streamLevelA =
  SDK.withErrorPath ["FeedScopeA"]
  . SDK.handleFailure $
    SDK.readStreamContext "ParserA" Effects.ContextBindingError Effects.boundParserA

getLevelB :: Effects.App Effects.LevelB
getLevelB =
  SDK.withErrorPath ["FeedScopeB"]
  . SDK.handleFailure
  . SDK.withScopeDependencies ["FeedScopeB"]
  . SDK.callContext "ParserB"
      (\value bindings -> bindings { Effects.boundParserB = Just value }) $
    Effects.LevelB <$> runWrap @"ParserB" (SDK.super "parseLevel" Effects.parseLevel)

streamLevelB :: Effects.App Effects.LevelB
streamLevelB =
  SDK.withErrorPath ["FeedScopeB"]
  . SDK.handleFailure $
    SDK.readStreamContext "ParserB" Effects.ContextBindingError Effects.boundParserB

runShowA :: Effects.App [String]
runShowA =
  SDK.handleFailure
  . SDK.atomicHandle "runShowA" [] []
  . SDK.enterHandler "ShowA" $
    runWrap @"ShowA" (SDK.super "showLevel" Effects.showLevel)

runShowB :: Effects.App [String]
runShowB =
  SDK.handleFailure
  . SDK.atomicHandle "runShowB" [] []
  . SDK.enterHandler "ShowB" $
    runWrap @"ShowB" (SDK.super "showLevel" Effects.showLevel)

-- SDK 内部：scope 按上游到下游登记，退出时逆序收尾；创建不执行业务方法。
newScopeHandlers :: IO [SDK.ScopeHandler Effects.ContextValues Effects.Errors]
newScopeHandlers = sequence
  [ SDK.newScopeHandler "ReportScope" ["ReportLocation"] (Just "ReportFile")
  , SDK.newScopeHandler "ReplyScope" ["ReplyLocation"] (Just "ReplyFile")
  , SDK.newScopeHandler "FeedScopeA" [] (Just "CounterA")
  , SDK.newScopeHandler "FeedScopeB" [] (Just "CounterB")
  ]

-- Error 回调登记：按 handles 匹配故障的 handler 与协议分类；关联 scope 由 Input 链推导。
errorHandlers :: [(Maybe String, SDK.ErrorHandler Effects.Errors Effects.App)]
errorHandlers = []
