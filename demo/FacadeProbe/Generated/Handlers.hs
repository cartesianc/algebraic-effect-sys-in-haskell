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

module FacadeProbe.Generated.Handlers (handlerSourceFingerprint, getReportPath, readReportPath, getReplyPath, readReplyPath, getReportBody, readReportBody, getReplyBody, readReplyBody, getOpenedReport, readOpenedReport, getOpenedReply, readOpenedReply, openReportScope, closeReportScope, openReplyScope, closeReplyScope, runWriteReport, runWriteReply, runMarkReply, runReadReport, runReadReply, getReportStats, readReportStats, getReplyStats, readReplyStats, runShowReport, runShowReply, getReportState, readReportState, runOnBlank, runOnFilled, nextFeedA, nextFeedB, getLevelA, streamLevelA, getLevelB, streamLevelB, runShowA, runShowB, newScopeHandlers, scopeCleanups, errorHandlers, contextInjections) where

import qualified Framework.Generated as FrameworkRuntime
import qualified FacadeProbe.Generated.Effects as FrameworkGenerated
import qualified Control.Monad.IO.Class as FrameworkIO
import qualified Data.Proxy as FrameworkProxy
import qualified GHC.TypeLits as FrameworkTypes
import FacadeProbe.Types
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

-- 记录本编译副本实际使用的手写源码；启动前检查，避免执行过期方法体。
handlerSourceFingerprint :: Maybe String
handlerSourceFingerprint = Just "8488bf62322eb4c3bee75fff2599aeb8"

-- 以下由 gen 生成。每个 effect 一个类型标签：handler 在标签下执行，
-- 读取、raw 与错误按标签在编译期解析到这个 effect 的来源，不改写 handler 方法体。
newtype At (effect :: FrameworkTypes.Symbol) value = At { runAt :: FrameworkGenerated.App value }
  deriving (Functor, Applicative, Monad, FrameworkIO.MonadIO)

instance FrameworkTypes.KnownSymbol effect => FrameworkRuntime.Raises FrameworkGenerated.ReportLocationError (At effect) where
  raise (FrameworkGenerated.ReportLocationError description) = At (FrameworkRuntime.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) FrameworkGenerated.ReportLocationFailure description)

instance FrameworkTypes.KnownSymbol effect => FrameworkRuntime.Raises FrameworkGenerated.ReplyLocationError (At effect) where
  raise (FrameworkGenerated.ReplyLocationError description) = At (FrameworkRuntime.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) FrameworkGenerated.ReplyLocationFailure description)

instance FrameworkTypes.KnownSymbol effect => FrameworkRuntime.Raises FrameworkGenerated.ReportDraftError (At effect) where
  raise (FrameworkGenerated.ReportDraftError description) = At (FrameworkRuntime.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) FrameworkGenerated.ReportDraftFailure description)

instance FrameworkTypes.KnownSymbol effect => FrameworkRuntime.Raises FrameworkGenerated.ReplyDraftError (At effect) where
  raise (FrameworkGenerated.ReplyDraftError description) = At (FrameworkRuntime.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) FrameworkGenerated.ReplyDraftFailure description)

instance FrameworkTypes.KnownSymbol effect => FrameworkRuntime.Raises FrameworkGenerated.AcquireFileError (At effect) where
  raise (FrameworkGenerated.AcquireFileError description) = At (FrameworkRuntime.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) FrameworkGenerated.AcquireFileFailure description)

instance FrameworkTypes.KnownSymbol effect => FrameworkRuntime.Raises FrameworkGenerated.OpenTextFileError (At effect) where
  raise (FrameworkGenerated.OpenTextFileError description) = At (FrameworkRuntime.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) FrameworkGenerated.OpenTextFileFailure description)

instance FrameworkTypes.KnownSymbol effect => FrameworkRuntime.Raises FrameworkGenerated.CloseTextFileError (At effect) where
  raise (FrameworkGenerated.CloseTextFileError description) = At (FrameworkRuntime.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) FrameworkGenerated.CloseTextFileFailure description)

instance FrameworkTypes.KnownSymbol effect => FrameworkRuntime.Raises FrameworkGenerated.WriteTextError (At effect) where
  raise (FrameworkGenerated.WriteTextError description) = At (FrameworkRuntime.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) FrameworkGenerated.WriteTextFailure description)

instance FrameworkTypes.KnownSymbol effect => FrameworkRuntime.Raises FrameworkGenerated.MarkReadError (At effect) where
  raise (FrameworkGenerated.MarkReadError description) = At (FrameworkRuntime.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) FrameworkGenerated.MarkReadFailure description)

instance FrameworkTypes.KnownSymbol effect => FrameworkRuntime.Raises FrameworkGenerated.ReadTextError (At effect) where
  raise (FrameworkGenerated.ReadTextError description) = At (FrameworkRuntime.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) FrameworkGenerated.ReadTextFailure description)

instance FrameworkTypes.KnownSymbol effect => FrameworkRuntime.Raises FrameworkGenerated.CountLinesError (At effect) where
  raise (FrameworkGenerated.CountLinesError description) = At (FrameworkRuntime.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) FrameworkGenerated.CountLinesFailure description)

instance FrameworkTypes.KnownSymbol effect => FrameworkRuntime.Raises FrameworkGenerated.ShowCountError (At effect) where
  raise (FrameworkGenerated.ShowCountError description) = At (FrameworkRuntime.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) FrameworkGenerated.ShowCountFailure description)

instance FrameworkTypes.KnownSymbol effect => FrameworkRuntime.Raises FrameworkGenerated.InspectFileError (At effect) where
  raise (FrameworkGenerated.InspectFileError description) = At (FrameworkRuntime.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) FrameworkGenerated.InspectFileFailure description)

instance FrameworkTypes.KnownSymbol effect => FrameworkRuntime.Raises FrameworkGenerated.DescribeBlankError (At effect) where
  raise (FrameworkGenerated.DescribeBlankError description) = At (FrameworkRuntime.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) FrameworkGenerated.DescribeBlankFailure description)

instance FrameworkTypes.KnownSymbol effect => FrameworkRuntime.Raises FrameworkGenerated.DescribeFilledError (At effect) where
  raise (FrameworkGenerated.DescribeFilledError description) = At (FrameworkRuntime.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) FrameworkGenerated.DescribeFilledFailure description)

instance FrameworkTypes.KnownSymbol effect => FrameworkRuntime.Raises FrameworkGenerated.NextAError (At effect) where
  raise (FrameworkGenerated.NextAError description) = At (FrameworkRuntime.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) FrameworkGenerated.NextAFailure description)

instance FrameworkTypes.KnownSymbol effect => FrameworkRuntime.Raises FrameworkGenerated.NextBError (At effect) where
  raise (FrameworkGenerated.NextBError description) = At (FrameworkRuntime.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) FrameworkGenerated.NextBFailure description)

instance FrameworkTypes.KnownSymbol effect => FrameworkRuntime.Raises FrameworkGenerated.ParseLevelError (At effect) where
  raise (FrameworkGenerated.ParseLevelError description) = At (FrameworkRuntime.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) FrameworkGenerated.ParseLevelFailure description)

instance FrameworkTypes.KnownSymbol effect => FrameworkRuntime.Raises FrameworkGenerated.ShowLevelError (At effect) where
  raise (FrameworkGenerated.ShowLevelError description) = At (FrameworkRuntime.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) FrameworkGenerated.ShowLevelFailure description)

instance FrameworkRuntime.Reads ([Char]) (At "ReportFile") where
  require = At ((\(FrameworkGenerated.ReportPath value) -> value) <$> readReportPath)

instance FrameworkRuntime.Reads ([Char]) (At "ReplyFile") where
  require = At ((\(FrameworkGenerated.ReplyPath value) -> value) <$> readReplyPath)

instance FrameworkRuntime.Reads (TextFile) (At "ReportScope") where
  require = At ((\(FrameworkGenerated.OpenedReport value) -> value) <$> readOpenedReport)

instance FrameworkRuntime.Reads (TextFile) (At "ReplyScope") where
  require = At ((\(FrameworkGenerated.OpenedReply value) -> value) <$> readOpenedReply)

instance FrameworkRuntime.Reads (TextFile) (At "WriteReport") where
  require = At ((\(FrameworkGenerated.OpenedReport value) -> value) <$> readOpenedReport)

instance FrameworkRuntime.Reads (Body) (At "WriteReport") where
  require = At ((\(FrameworkGenerated.ReportBody value) -> value) <$> readReportBody)

instance FrameworkRuntime.Reads (TextFile) (At "WriteReply") where
  require = At ((\(FrameworkGenerated.OpenedReply value) -> value) <$> readOpenedReply)

instance FrameworkRuntime.Reads (Body) (At "WriteReply") where
  require = At ((\(FrameworkGenerated.ReplyBody value) -> value) <$> readReplyBody)

instance FrameworkRuntime.Reads ([Char]) (At "ReadReport") where
  require = At ((\(FrameworkGenerated.ReportPath value) -> value) <$> readReportPath)

instance FrameworkRuntime.Reads ([Char]) (At "ReadReply") where
  require = At ((\(FrameworkGenerated.ReplyPath value) -> value) <$> readReplyPath)

instance FrameworkRuntime.Reads (LineCount) (At "ShowReport") where
  require = At ((\(FrameworkGenerated.ReportStats value) -> value) <$> readReportStats)

instance FrameworkRuntime.Reads (LineCount) (At "ShowReply") where
  require = At ((\(FrameworkGenerated.ReplyStats value) -> value) <$> readReplyStats)

instance FrameworkRuntime.Reads ([Char]) (At "ReportInspect") where
  require = At ((\(FrameworkGenerated.ReportPath value) -> value) <$> readReportPath)

instance FrameworkRuntime.Reads (()) (At "OnBlank") where
  require = At (FrameworkRuntime.projectContext "ReportInspect" "ReportStateBlank" FrameworkGenerated.ContextBindingError (\(FrameworkGenerated.ReportState value) -> case value of { Blank -> Just (); _ -> Nothing }) (readReportState))

instance FrameworkRuntime.Reads (Body) (At "OnFilled") where
  require = At (FrameworkRuntime.projectContext "ReportInspect" "ReportStateFilled" FrameworkGenerated.ContextBindingError (\(FrameworkGenerated.ReportState value) -> case value of { Filled field -> Just field; _ -> Nothing }) (readReportState))

instance FrameworkRuntime.Reads (FrameworkRuntime.History (Level)) (At "ShowA") where
  require = At (fmap (\(FrameworkGenerated.LevelA value) -> value) <$> streamLevelA)

instance FrameworkRuntime.Reads (FrameworkRuntime.History (Level)) (At "ShowB") where
  require = At (fmap (\(FrameworkGenerated.LevelB value) -> value) <$> streamLevelB)

instance FrameworkRuntime.Raw (At "ReportCounter") where
  raw = At (runReadReport)

instance FrameworkRuntime.Raw (At "ReplyCounter") where
  raw = At (runReadReply)

instance FrameworkRuntime.Raw (At "ParserA") where
  raw = At (Just <$> nextFeedA)

instance FrameworkRuntime.Raw (At "ParserB") where
  raw = At (Just <$> nextFeedB)

getReportPath :: FrameworkGenerated.App FrameworkGenerated.ReportPath
getReportPath = (FrameworkRuntime.withErrorPath [] . FrameworkRuntime.handleFailure . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.callContext "ReportLocation" FrameworkGenerated.ContextBindingError
    [("ReportFile", FrameworkRuntime.RequireValue), ("ReadReport", FrameworkRuntime.RequireValue), ("ReportInspect", FrameworkRuntime.RequireValue)]
    (Just (FrameworkRuntime.ScopeInput "ReportLocation"))
    FrameworkGenerated.boundReportLocation
    (\value bindings -> bindings { FrameworkGenerated.boundReportLocation = Just value })) $
  (FrameworkGenerated.ReportPath <$> runAt @"ReportLocation" FrameworkGenerated.reportLocation)

readReportPath :: FrameworkGenerated.App FrameworkGenerated.ReportPath
readReportPath = (FrameworkRuntime.withErrorPath [] . FrameworkRuntime.handleFailure) $
  FrameworkRuntime.readContext "ReportLocation" FrameworkGenerated.ContextBindingError [("ReportFile", FrameworkRuntime.RequireValue), ("ReadReport", FrameworkRuntime.RequireValue), ("ReportInspect", FrameworkRuntime.RequireValue)] (Just (FrameworkRuntime.ScopeInput "ReportLocation")) FrameworkGenerated.boundReportLocation getReportPath

getReplyPath :: FrameworkGenerated.App FrameworkGenerated.ReplyPath
getReplyPath = (FrameworkRuntime.withErrorPath [] . FrameworkRuntime.handleFailure . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.callContext "ReplyLocation" FrameworkGenerated.ContextBindingError
    [("ReplyFile", FrameworkRuntime.RequireValue), ("ReadReply", FrameworkRuntime.RequireValue)]
    (Just (FrameworkRuntime.ScopeInput "ReplyLocation"))
    FrameworkGenerated.boundReplyLocation
    (\value bindings -> bindings { FrameworkGenerated.boundReplyLocation = Just value })) $
  (FrameworkGenerated.ReplyPath <$> runAt @"ReplyLocation" FrameworkGenerated.replyLocation)

readReplyPath :: FrameworkGenerated.App FrameworkGenerated.ReplyPath
readReplyPath = (FrameworkRuntime.withErrorPath [] . FrameworkRuntime.handleFailure) $
  FrameworkRuntime.readContext "ReplyLocation" FrameworkGenerated.ContextBindingError [("ReplyFile", FrameworkRuntime.RequireValue), ("ReadReply", FrameworkRuntime.RequireValue)] (Just (FrameworkRuntime.ScopeInput "ReplyLocation")) FrameworkGenerated.boundReplyLocation getReplyPath

getReportBody :: FrameworkGenerated.App FrameworkGenerated.ReportBody
getReportBody = (FrameworkRuntime.withErrorPath [] . FrameworkRuntime.handleFailure . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.callContext "ReportDraft" FrameworkGenerated.ContextBindingError
    [("WriteReport", FrameworkRuntime.RequireValue)]
    Nothing
    FrameworkGenerated.boundReportDraft
    (\value bindings -> bindings { FrameworkGenerated.boundReportDraft = Just value })) $
  (FrameworkGenerated.ReportBody <$> runAt @"ReportDraft" FrameworkGenerated.reportDraft)

readReportBody :: FrameworkGenerated.App FrameworkGenerated.ReportBody
readReportBody = (FrameworkRuntime.withErrorPath [] . FrameworkRuntime.handleFailure) $
  FrameworkRuntime.readContext "ReportDraft" FrameworkGenerated.ContextBindingError [("WriteReport", FrameworkRuntime.RequireValue)] Nothing FrameworkGenerated.boundReportDraft getReportBody

getReplyBody :: FrameworkGenerated.App FrameworkGenerated.ReplyBody
getReplyBody = (FrameworkRuntime.withErrorPath [] . FrameworkRuntime.handleFailure . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.callContext "ReplyDraft" FrameworkGenerated.ContextBindingError
    [("WriteReply", FrameworkRuntime.RequireValue)]
    Nothing
    FrameworkGenerated.boundReplyDraft
    (\value bindings -> bindings { FrameworkGenerated.boundReplyDraft = Just value })) $
  (FrameworkGenerated.ReplyBody <$> runAt @"ReplyDraft" FrameworkGenerated.replyDraft)

readReplyBody :: FrameworkGenerated.App FrameworkGenerated.ReplyBody
readReplyBody = (FrameworkRuntime.withErrorPath [] . FrameworkRuntime.handleFailure) $
  FrameworkRuntime.readContext "ReplyDraft" FrameworkGenerated.ContextBindingError [("WriteReply", FrameworkRuntime.RequireValue)] Nothing FrameworkGenerated.boundReplyDraft getReplyBody

getOpenedReport :: FrameworkGenerated.App FrameworkGenerated.OpenedReport
getOpenedReport = (FrameworkRuntime.withErrorPath [] . FrameworkRuntime.handleFailure . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.callContext "ReportFile" FrameworkGenerated.ContextBindingError
    [("ReportScope", FrameworkRuntime.RequestValue), ("WriteReport", FrameworkRuntime.RequireValue)]
    Nothing
    FrameworkGenerated.boundReportFile
    (\value bindings -> bindings { FrameworkGenerated.boundReportFile = Just value })) $
  (FrameworkGenerated.OpenedReport <$> runAt @"ReportFile" FrameworkGenerated.acquireFile)

readOpenedReport :: FrameworkGenerated.App FrameworkGenerated.OpenedReport
readOpenedReport = (FrameworkRuntime.withErrorPath [] . FrameworkRuntime.handleFailure) $
  FrameworkRuntime.readContext "ReportFile" FrameworkGenerated.ContextBindingError [("ReportScope", FrameworkRuntime.RequestValue), ("WriteReport", FrameworkRuntime.RequireValue)] Nothing FrameworkGenerated.boundReportFile getOpenedReport

getOpenedReply :: FrameworkGenerated.App FrameworkGenerated.OpenedReply
getOpenedReply = (FrameworkRuntime.withErrorPath [] . FrameworkRuntime.handleFailure . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.callContext "ReplyFile" FrameworkGenerated.ContextBindingError
    [("ReplyScope", FrameworkRuntime.RequestValue), ("WriteReply", FrameworkRuntime.RequireValue)]
    Nothing
    FrameworkGenerated.boundReplyFile
    (\value bindings -> bindings { FrameworkGenerated.boundReplyFile = Just value })) $
  (FrameworkGenerated.OpenedReply <$> runAt @"ReplyFile" FrameworkGenerated.acquireFile)

readOpenedReply :: FrameworkGenerated.App FrameworkGenerated.OpenedReply
readOpenedReply = (FrameworkRuntime.withErrorPath [] . FrameworkRuntime.handleFailure) $
  FrameworkRuntime.readContext "ReplyFile" FrameworkGenerated.ContextBindingError [("ReplyScope", FrameworkRuntime.RequestValue), ("WriteReply", FrameworkRuntime.RequireValue)] Nothing FrameworkGenerated.boundReplyFile getOpenedReply

openReportScope :: FrameworkGenerated.App (Maybe String)
openReportScope = (FrameworkRuntime.withErrorPath ["ReportScope"] . FrameworkRuntime.handleFailure . FrameworkRuntime.atomicScope "openReportScope" . FrameworkRuntime.openScope "ReportScope" FrameworkGenerated.ScopeBindingError . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.enterHandler "ReportScope") $
  getOpenedReport >> runAt @"ReportScope" FrameworkGenerated.openTextFile

closeReportScope :: FrameworkGenerated.App (Maybe String)
closeReportScope = (FrameworkRuntime.withErrorPath ["ReportScope"] . FrameworkRuntime.handleFailure . FrameworkRuntime.atomicScope "closeReportScope" . FrameworkRuntime.closeScope "ReportScope" FrameworkGenerated.ScopeBindingError . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.enterHandler "ReportScope") $
  runAt @"ReportScope" FrameworkGenerated.closeTextFile

openReplyScope :: FrameworkGenerated.App (Maybe String)
openReplyScope = (FrameworkRuntime.withErrorPath ["ReplyScope"] . FrameworkRuntime.handleFailure . FrameworkRuntime.atomicScope "openReplyScope" . FrameworkRuntime.openScope "ReplyScope" FrameworkGenerated.ScopeBindingError . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.enterHandler "ReplyScope") $
  getOpenedReply >> runAt @"ReplyScope" FrameworkGenerated.openTextFile

closeReplyScope :: FrameworkGenerated.App (Maybe String)
closeReplyScope = (FrameworkRuntime.withErrorPath ["ReplyScope"] . FrameworkRuntime.handleFailure . FrameworkRuntime.atomicScope "closeReplyScope" . FrameworkRuntime.closeScope "ReplyScope" FrameworkGenerated.ScopeBindingError . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.enterHandler "ReplyScope") $
  runAt @"ReplyScope" FrameworkGenerated.closeTextFile

runWriteReport :: FrameworkGenerated.App (Maybe String)
runWriteReport = (FrameworkRuntime.withErrorPath ["ReportScope"] . FrameworkRuntime.handleFailure . FrameworkRuntime.atomicHandle "runWriteReport" . FrameworkRuntime.withScopeDependencies ["ReportScope"] . FrameworkRuntime.enterHandler "WriteReport") $
  openReportScope >> runAt @"WriteReport" FrameworkGenerated.writeText

runWriteReply :: FrameworkGenerated.App (Maybe String)
runWriteReply = (FrameworkRuntime.withErrorPath ["ReplyScope"] . FrameworkRuntime.handleFailure . FrameworkRuntime.atomicHandle "runWriteReply" . FrameworkRuntime.withScopeDependencies ["ReplyScope"] . FrameworkRuntime.enterHandler "WriteReply") $
  openReplyScope >> runAt @"WriteReply" FrameworkGenerated.writeText

runMarkReply :: FrameworkGenerated.App (Maybe String)
runMarkReply = (FrameworkRuntime.withErrorPath [] . FrameworkRuntime.handleFailure . FrameworkRuntime.atomicHandle "runMarkReply" . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.enterHandler "MarkReply") $
  runAt @"MarkReply" FrameworkGenerated.markRead

runReadReport :: FrameworkGenerated.App (Maybe String)
runReadReport = (FrameworkRuntime.withErrorPath [] . FrameworkRuntime.handleFailure . FrameworkRuntime.atomicHandle "runReadReport" . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.enterHandler "ReadReport") $
  runAt @"ReadReport" FrameworkGenerated.readText

runReadReply :: FrameworkGenerated.App (Maybe String)
runReadReply = (FrameworkRuntime.withErrorPath [] . FrameworkRuntime.handleFailure . FrameworkRuntime.atomicHandle "runReadReply" . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.enterHandler "ReadReply") $
  runMarkReply >> runAt @"ReadReply" FrameworkGenerated.readText

getReportStats :: FrameworkGenerated.App FrameworkGenerated.ReportStats
getReportStats = (FrameworkRuntime.withErrorPath [] . FrameworkRuntime.handleFailure . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.callContext "ReportCounter" FrameworkGenerated.ContextBindingError
    [("ShowReport", FrameworkRuntime.RequireValue)]
    Nothing
    FrameworkGenerated.boundReportCounter
    (\value bindings -> bindings { FrameworkGenerated.boundReportCounter = Just value })) $
  (FrameworkGenerated.ReportStats <$> runAt @"ReportCounter" FrameworkGenerated.countLines)

readReportStats :: FrameworkGenerated.App FrameworkGenerated.ReportStats
readReportStats = (FrameworkRuntime.withErrorPath [] . FrameworkRuntime.handleFailure) $
  FrameworkRuntime.readContext "ReportCounter" FrameworkGenerated.ContextBindingError [("ShowReport", FrameworkRuntime.RequireValue)] Nothing FrameworkGenerated.boundReportCounter getReportStats

getReplyStats :: FrameworkGenerated.App FrameworkGenerated.ReplyStats
getReplyStats = (FrameworkRuntime.withErrorPath [] . FrameworkRuntime.handleFailure . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.callContext "ReplyCounter" FrameworkGenerated.ContextBindingError
    [("ShowReply", FrameworkRuntime.RequireValue)]
    Nothing
    FrameworkGenerated.boundReplyCounter
    (\value bindings -> bindings { FrameworkGenerated.boundReplyCounter = Just value })) $
  (FrameworkGenerated.ReplyStats <$> runAt @"ReplyCounter" FrameworkGenerated.countLines)

readReplyStats :: FrameworkGenerated.App FrameworkGenerated.ReplyStats
readReplyStats = (FrameworkRuntime.withErrorPath [] . FrameworkRuntime.handleFailure) $
  FrameworkRuntime.readContext "ReplyCounter" FrameworkGenerated.ContextBindingError [("ShowReply", FrameworkRuntime.RequireValue)] Nothing FrameworkGenerated.boundReplyCounter getReplyStats

runShowReport :: FrameworkGenerated.App (Maybe String)
runShowReport = (FrameworkRuntime.withErrorPath [] . FrameworkRuntime.handleFailure . FrameworkRuntime.atomicHandle "runShowReport" . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.enterHandler "ShowReport") $
  runAt @"ShowReport" FrameworkGenerated.showCount

runShowReply :: FrameworkGenerated.App (Maybe String)
runShowReply = (FrameworkRuntime.withErrorPath [] . FrameworkRuntime.handleFailure . FrameworkRuntime.atomicHandle "runShowReply" . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.enterHandler "ShowReply") $
  runAt @"ShowReply" FrameworkGenerated.showCount

getReportState :: FrameworkGenerated.App FrameworkGenerated.ReportState
getReportState = (FrameworkRuntime.withErrorPath [] . FrameworkRuntime.handleFailure . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.callContext "ReportInspect" FrameworkGenerated.ContextBindingError
    [("OnBlank", FrameworkRuntime.RequireValue), ("OnFilled", FrameworkRuntime.RequireValue)]
    Nothing
    FrameworkGenerated.boundReportInspect
    (\value bindings -> bindings { FrameworkGenerated.boundReportInspect = Just value })) $
  (FrameworkGenerated.ReportState <$> runAt @"ReportInspect" FrameworkGenerated.inspectFile)

readReportState :: FrameworkGenerated.App FrameworkGenerated.ReportState
readReportState = (FrameworkRuntime.withErrorPath [] . FrameworkRuntime.handleFailure) $
  FrameworkRuntime.readContext "ReportInspect" FrameworkGenerated.ContextBindingError [("OnBlank", FrameworkRuntime.RequireValue), ("OnFilled", FrameworkRuntime.RequireValue)] Nothing FrameworkGenerated.boundReportInspect getReportState

runOnBlank :: FrameworkGenerated.App (Maybe String)
runOnBlank = (FrameworkRuntime.withErrorPath [] . FrameworkRuntime.handleFailure . FrameworkRuntime.atomicHandle "runOnBlank" . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.enterHandler "OnBlank") $
  runAt @"OnBlank" FrameworkGenerated.describeBlank

runOnFilled :: FrameworkGenerated.App (Maybe String)
runOnFilled = (FrameworkRuntime.withErrorPath [] . FrameworkRuntime.handleFailure . FrameworkRuntime.atomicHandle "runOnFilled" . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.enterHandler "OnFilled") $
  runAt @"OnFilled" FrameworkGenerated.describeFilled

nextFeedA :: FrameworkGenerated.App String
nextFeedA = (FrameworkRuntime.withErrorPath [] . FrameworkRuntime.handleFailure . FrameworkRuntime.streamHandle . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.enterHandler "FeedA") $
  runAt @"FeedA" FrameworkGenerated.nextA

nextFeedB :: FrameworkGenerated.App String
nextFeedB = (FrameworkRuntime.withErrorPath [] . FrameworkRuntime.handleFailure . FrameworkRuntime.streamHandle . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.enterHandler "FeedB") $
  runAt @"FeedB" FrameworkGenerated.nextB

getLevelA :: FrameworkGenerated.App FrameworkGenerated.LevelA
getLevelA = (FrameworkRuntime.withErrorPath [] . FrameworkRuntime.handleFailure . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.callContext "ParserA" FrameworkGenerated.ContextBindingError
    [("ShowA", FrameworkRuntime.RequireValue)]
    Nothing
    FrameworkGenerated.boundParserA
    (\value bindings -> bindings { FrameworkGenerated.boundParserA = Just value })) $
  (FrameworkGenerated.LevelA <$> runAt @"ParserA" FrameworkGenerated.parseLevel)

streamLevelA :: FrameworkGenerated.App (FrameworkRuntime.History FrameworkGenerated.LevelA)
streamLevelA = (FrameworkRuntime.withErrorPath [] . FrameworkRuntime.handleFailure) $
  FrameworkRuntime.readHistory "ParserA" FrameworkGenerated.ContextBindingError [("ShowA", FrameworkRuntime.RequireValue)] FrameworkGenerated.boundParserA Nothing

getLevelB :: FrameworkGenerated.App FrameworkGenerated.LevelB
getLevelB = (FrameworkRuntime.withErrorPath [] . FrameworkRuntime.handleFailure . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.callContext "ParserB" FrameworkGenerated.ContextBindingError
    [("ShowB", FrameworkRuntime.RequireValue)]
    Nothing
    FrameworkGenerated.boundParserB
    (\value bindings -> bindings { FrameworkGenerated.boundParserB = Just value })) $
  (FrameworkGenerated.LevelB <$> runAt @"ParserB" FrameworkGenerated.parseLevel)

streamLevelB :: FrameworkGenerated.App (FrameworkRuntime.History FrameworkGenerated.LevelB)
streamLevelB = (FrameworkRuntime.withErrorPath [] . FrameworkRuntime.handleFailure) $
  FrameworkRuntime.readHistory "ParserB" FrameworkGenerated.ContextBindingError [("ShowB", FrameworkRuntime.RequireValue)] FrameworkGenerated.boundParserB Nothing

runShowA :: FrameworkGenerated.App (Maybe String)
runShowA = (FrameworkRuntime.withErrorPath [] . FrameworkRuntime.handleFailure . FrameworkRuntime.atomicHandle "runShowA" . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.enterHandler "ShowA") $
  runAt @"ShowA" FrameworkGenerated.showLevel

runShowB :: FrameworkGenerated.App (Maybe String)
runShowB = (FrameworkRuntime.withErrorPath [] . FrameworkRuntime.handleFailure . FrameworkRuntime.atomicHandle "runShowB" . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.enterHandler "ShowB") $
  runAt @"ShowB" FrameworkGenerated.showLevel

-- SDK 内部：scope 按上游到下游登记，退出时逆序收尾；创建不执行业务方法。
newScopeHandlers :: IO [FrameworkRuntime.ScopeHandler FrameworkGenerated.ContextValues FrameworkGenerated.Errors]
newScopeHandlers = sequence
  [ FrameworkRuntime.newScopeHandler "ReportScope" ["ReportLocation"] (Just "ReportFile")
  , FrameworkRuntime.newScopeHandler "ReplyScope" ["ReplyLocation"] (Just "ReplyFile")
  ]

-- SDK 自动收尾入口；安装时不关闭资源。
scopeCleanups :: [(String, FrameworkGenerated.App ())]
scopeCleanups =
  [ ("ReportScope", () <$ closeReportScope)
  , ("ReplyScope", () <$ closeReplyScope)
  ]

-- Error 回调登记：按 handles 匹配故障的 handler 与协议分类；关联 scope 由 Input 链推导。
errorHandlers :: [(Maybe String, FrameworkRuntime.ErrorHandler FrameworkGenerated.Errors FrameworkGenerated.App)]
errorHandlers =
  [
  ]

-- 挂在原子句柄下的 Context：句柄的输出交给它的 parser 解析并发布为资产；没有挂接时输出被丢弃。
contextInjections :: [(String, [(String, FrameworkGenerated.App ())])]
contextInjections =
  [ ("runReadReport", [("ReportCounter", () <$ getReportStats)])
  , ("runReadReply", [("ReplyCounter", () <$ getReplyStats)])
  ]
