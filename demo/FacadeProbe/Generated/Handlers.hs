-- 自动生成的编译副本；请修改上级 Handlers.hs 后重新生成。
{-# LANGUAGE AllowAmbiguousTypes #-}
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

module FacadeProbe.Generated.Handlers (handlerSourceFingerprint, getReportPath, readReportPath, getReplyPath, readReplyPath, getReportBody, readReportBody, getReplyBody, readReplyBody, getOpenedReport, readOpenedReport, getOpenedReply, readOpenedReply, openReportScope, closeReportScope, openReplyScope, closeReplyScope, runWriteReport, runWriteReply, runMarkReply, runReadReport, runReadReply, getReportStats, readReportStats, getReplyStats, readReplyStats, runShowReport, runShowReply, runInspectReport, getReportEmpty, readReportEmpty, getReportText, readReportText, runOnBlank, runOnFilled, nextFeedA, nextFeedB, getLevelA, streamLevelA, getLevelB, streamLevelB, runShowA, runShowB, historyLevelA, historyLevelB, newScopeHandlers, errorHandlers) where

import qualified Framework.Generated as SDK
import qualified FacadeProbe.Generated.Effects as Effects
import qualified Control.Monad.IO.Class as FrameworkIO
import qualified Data.Proxy as FrameworkProxy
import qualified GHC.TypeLits as FrameworkTypes
import Framework.SDK (Emits(rawemit), Raises(..), Raw(..), Reads(..), Streams(..), rawoutput)
import FacadeProbe.Generated.Effects
import FacadeProbe.Types
import Control.Concurrent (threadDelay)
import Control.Monad (when)
import Control.Monad.IO.Class (liftIO)
import System.FilePath ((</>))
import System.IO (readFile')

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
    path <- require @String
    liftIO (writeFile path "")
    pure (TextFile path)

instance OpenTextFileLayer m => OpenTextFileHandler m where
  openTextFile = do
    TextFile path <- require @TextFile
    liftIO (putStrLn ("[open] " ++ path))
    rawoutput []

instance CloseTextFileLayer m => CloseTextFileHandler m where
  closeTextFile = do
    TextFile path <- require @TextFile
    liftIO (putStrLn ("[close] " ++ path))
    rawoutput []

instance WriteTextLayer m => WriteTextHandler m where
  writeText = do
    TextFile path <- require @TextFile
    Body text <- require @Body
    liftIO (appendFile path text >> putStrLn ("[write] " ++ path))
    rawoutput []

instance MarkReadLayer m => MarkReadHandler m where
  markRead = do
    liftIO (putStrLn "[mark] before reading")
    rawoutput []

instance ReadTextLayer m => ReadTextHandler m where
  readText = do
    path <- require @String
    contents <- liftIO (readFile' path)
    rawoutput [contents]

instance CountLinesLayer m => CountLinesHandler m where
  countLines = do
    output <- rawinput
    contents <- case output of
      [text] -> pure text
      _ -> raise (CountLinesError "no text")
    pure (LineCount (show (length (lines contents))))

instance ShowCountLayer m => ShowCountHandler m where
  showCount = do
    LineCount count <- require @LineCount
    liftIO (putStrLn ("[lines] " ++ count))
    rawoutput []

instance InspectFileLayer m => InspectFileHandler m where
  inspectFile = do
    path <- require @String
    contents <- liftIO (readFile' path)
    rawoutput [contents]

-- 两个 parser 读同一次输出；不符合自己的情形就 raise，在 alternative 的选择中只算放弃。
instance ParseBlankReportLayer m => ParseBlankReportHandler m where
  parseBlankReport = do
    output <- rawinput
    case output of
      [""] -> pure (EmptyReport "")
      _ -> raise (ParseBlankReportError "the report is not empty")

instance ParseFilledReportLayer m => ParseFilledReportHandler m where
  parseFilledReport = do
    output <- rawinput
    case output of
      [text] | not (null text) -> pure (Body text)
      _ -> raise (ParseFilledReportError "the report is empty")

instance DescribeBlankLayer m => DescribeBlankHandler m where
  describeBlank = do
    liftIO (putStrLn "[state] blank")
    rawoutput []

instance DescribeFilledLayer m => DescribeFilledHandler m where
  describeFilled = do
    Body text <- require @Body
    liftIO (putStrLn ("[state] filled, " ++ show (length text) ++ " characters"))
    rawoutput []

instance NextALayer m => NextAHandler m where
  nextA = do
    liftIO (threadDelay 40000)
    rawemit (show (10 :: Int))

instance NextBLayer m => NextBHandler m where
  nextB = do
    liftIO (threadDelay 60000)
    rawemit (show (20 :: Int))

instance ParseLevelLayer m => ParseLevelHandler m where
  parseLevel = do
    reading <- concat <$> rawinput
    case reads reading :: [(Int, String)] of
      [(_, "")] -> pure (Level reading)
      _ -> raise (ParseLevelError reading)

-- ShowA 与 ShowB 共用；失败按 handler 固定为 ShowLevelError，origin 仍是具体的 effect。
-- 交付编号是 x:xs 的长度：本次交付加上同一会话中更早的交付。
instance ShowLevelLayer m => ShowLevelHandler m where
  showLevel = do
    Level value <- require @Level
    seen <- stream @Level
    let number = length seen
    liftIO (putStrLn ("[level] " ++ value ++ " at delivery " ++ show number))
    when (number >= 3) (raise (ShowLevelError "enough deliveries"))
    rawoutput []

-- 记录本编译副本实际使用的手写源码；启动前检查，避免执行过期方法体。
handlerSourceFingerprint :: Maybe String
handlerSourceFingerprint = Just "d63bccc6d7046f715bbc88151ceb1b57"

-- 以下由 gen 生成。每个 effect 一个类型标签：handler 在标签下执行，
-- 读取、rawinput 与错误按标签在编译期解析到这个 effect 的来源，不改写 handler 方法体。
newtype Wrap (effect :: FrameworkTypes.Symbol) (method :: FrameworkTypes.Symbol) value = Wrap { runWrap :: Effects.App value }
  deriving (Functor, Applicative, Monad, FrameworkIO.MonadIO, SDK.MonadThrow, SDK.MonadCatch, SDK.MonadMask)

-- 类型标签上的名字：effect 名与方法名只写在标签上，需要字符串时从这里取。
nameOf :: forall name. FrameworkTypes.KnownSymbol name => String
nameOf = FrameworkTypes.symbolVal (FrameworkProxy.Proxy @name)

-- 在标签下执行 handler，交给 Root 的 superhandler；方法名取自标签。close 的调用点用 callClose。
call :: forall effect method value. (FrameworkTypes.KnownSymbol method)
  => Wrap effect method value -> Effects.App value
call handler = runWrap (SDK.super (nameOf @method) handler)

callClose :: forall effect method value. (FrameworkTypes.KnownSymbol method)
  => Wrap effect method value -> Effects.App value
callClose handler = runWrap (SDK.superClose (nameOf @method) handler)

instance SDK.Root (Wrap effect method) value

instance (SDK.HandlerError problem Effects.Errors, FrameworkTypes.KnownSymbol effect)
    => SDK.Raises problem (Wrap effect method) where
  raise problem = Wrap (SDK.failEffect (nameOf @effect) failure description)
    where (failure, description) = SDK.raised problem

instance SDK.Reads [Char] (Wrap "ReportFile" method) where
  require = Wrap (SDK.coerce <$> readReportPath)

instance SDK.Reads [Char] (Wrap "ReplyFile" method) where
  require = Wrap (SDK.coerce <$> readReplyPath)

instance SDK.Reads TextFile (Wrap "ReportScope" method) where
  require = Wrap (SDK.coerce <$> readOpenedReport)

instance SDK.Reads TextFile (Wrap "ReplyScope" method) where
  require = Wrap (SDK.coerce <$> readOpenedReply)

instance SDK.Reads TextFile (Wrap "WriteReport" method) where
  require = Wrap (SDK.coerce <$> readOpenedReport)

instance SDK.Reads Body (Wrap "WriteReport" method) where
  require = Wrap (SDK.coerce <$> readReportBody)

instance SDK.Reads TextFile (Wrap "WriteReply" method) where
  require = Wrap (SDK.coerce <$> readOpenedReply)

instance SDK.Reads Body (Wrap "WriteReply" method) where
  require = Wrap (SDK.coerce <$> readReplyBody)

instance SDK.Reads [Char] (Wrap "ReadReport" method) where
  require = Wrap (SDK.coerce <$> readReportPath)

instance SDK.Reads [Char] (Wrap "ReadReply" method) where
  require = Wrap (SDK.coerce <$> readReplyPath)

instance SDK.Reads LineCount (Wrap "ShowReport" method) where
  require = Wrap (SDK.coerce <$> readReportStats)

instance SDK.Reads LineCount (Wrap "ShowReply" method) where
  require = Wrap (SDK.coerce <$> readReplyStats)

instance SDK.Reads [Char] (Wrap "InspectReport" method) where
  require = Wrap (SDK.coerce <$> readReportPath)

instance SDK.Reads EmptyReport (Wrap "OnBlank" method) where
  require = Wrap (SDK.coerce <$> readReportEmpty)

instance SDK.Reads Body (Wrap "OnFilled" method) where
  require = Wrap (SDK.coerce <$> readReportText)

instance SDK.Reads Level (Wrap "ShowA" method) where
  require = Wrap (SDK.coerce <$> streamLevelA)

instance SDK.Reads Level (Wrap "ShowB" method) where
  require = Wrap (SDK.coerce <$> streamLevelB)

instance SDK.Streams Level (Wrap "ShowA" method) where
  stream = Wrap (SDK.coerce <$> historyLevelA)

instance SDK.Streams Level (Wrap "ShowB" method) where
  stream = Wrap (SDK.coerce <$> historyLevelB)

instance SDK.Raw (Wrap "ReportCounter" "countLines") where
  rawinput = Wrap runReadReport

instance SDK.Raw (Wrap "ReplyCounter" "countLines") where
  rawinput = Wrap runReadReply

instance SDK.Raw (Wrap "ReportBlank" "parseBlankReport") where
  rawinput = Wrap runInspectReport

instance SDK.Raw (Wrap "ReportFilled" "parseFilledReport") where
  rawinput = Wrap runInspectReport

instance SDK.Raw (Wrap "ParserA" "parseLevel") where
  rawinput = Wrap SDK.emittedInput

instance SDK.Raw (Wrap "ParserB" "parseLevel") where
  rawinput = Wrap SDK.emittedInput

instance SDK.RawOutputs (Wrap effect method)

instance SDK.Emits (Wrap effect method) where
  rawemit text = Wrap (SDK.emitToParser text)

instance SDK.StreamEnds (Wrap effect method) where
  streamEnd = Wrap SDK.endSource

instance SDK.EndsStream (Wrap effect method) where
  endStream = Wrap SDK.endSubscription

getReportPath :: Effects.App Effects.ReportPath
getReportPath =
  SDK.handleFailure
  . SDK.callContext (SDK.Slot 0 "ReportLocation")
      (\value bindings -> bindings { Effects.boundReportLocation = Just value })
      Effects.boundReportLocation $
    Effects.ReportPath <$> call @"ReportLocation" @"reportLocation" Effects.reportLocation

readReportPath :: Effects.App Effects.ReportPath
readReportPath =
  SDK.handleFailure $
    SDK.readContext (SDK.Slot 0 "ReportLocation") Effects.ContextBindingError Effects.boundReportLocation

getReplyPath :: Effects.App Effects.ReplyPath
getReplyPath =
  SDK.handleFailure
  . SDK.callContext (SDK.Slot 1 "ReplyLocation")
      (\value bindings -> bindings { Effects.boundReplyLocation = Just value })
      Effects.boundReplyLocation $
    Effects.ReplyPath <$> call @"ReplyLocation" @"replyLocation" Effects.replyLocation

readReplyPath :: Effects.App Effects.ReplyPath
readReplyPath =
  SDK.handleFailure $
    SDK.readContext (SDK.Slot 1 "ReplyLocation") Effects.ContextBindingError Effects.boundReplyLocation

getReportBody :: Effects.App Effects.ReportBody
getReportBody =
  SDK.handleFailure
  . SDK.callContext (SDK.Slot 2 "ReportDraft")
      (\value bindings -> bindings { Effects.boundReportDraft = Just value })
      Effects.boundReportDraft $
    Effects.ReportBody <$> call @"ReportDraft" @"reportDraft" Effects.reportDraft

readReportBody :: Effects.App Effects.ReportBody
readReportBody =
  SDK.handleFailure $
    SDK.readContext (SDK.Slot 2 "ReportDraft") Effects.ContextBindingError Effects.boundReportDraft

getReplyBody :: Effects.App Effects.ReplyBody
getReplyBody =
  SDK.handleFailure
  . SDK.callContext (SDK.Slot 3 "ReplyDraft")
      (\value bindings -> bindings { Effects.boundReplyDraft = Just value })
      Effects.boundReplyDraft $
    Effects.ReplyBody <$> call @"ReplyDraft" @"replyDraft" Effects.replyDraft

readReplyBody :: Effects.App Effects.ReplyBody
readReplyBody =
  SDK.handleFailure $
    SDK.readContext (SDK.Slot 3 "ReplyDraft") Effects.ContextBindingError Effects.boundReplyDraft

getOpenedReport :: Effects.App Effects.OpenedReport
getOpenedReport =
  SDK.handleFailure
  . SDK.callContext (SDK.Slot 4 "ReportFile")
      (\value bindings -> bindings { Effects.boundReportFile = Just value })
      Effects.boundReportFile $
    getReportPath >> Effects.OpenedReport <$> call @"ReportFile" @"acquireFile" Effects.acquireFile

readOpenedReport :: Effects.App Effects.OpenedReport
readOpenedReport =
  SDK.handleFailure $
    SDK.readContext (SDK.Slot 4 "ReportFile") Effects.ContextBindingError Effects.boundReportFile

getOpenedReply :: Effects.App Effects.OpenedReply
getOpenedReply =
  SDK.handleFailure
  . SDK.callContext (SDK.Slot 5 "ReplyFile")
      (\value bindings -> bindings { Effects.boundReplyFile = Just value })
      Effects.boundReplyFile $
    getReplyPath >> Effects.OpenedReply <$> call @"ReplyFile" @"acquireFile" Effects.acquireFile

readOpenedReply :: Effects.App Effects.OpenedReply
readOpenedReply =
  SDK.handleFailure $
    SDK.readContext (SDK.Slot 5 "ReplyFile") Effects.ContextBindingError Effects.boundReplyFile

openReportScope :: Effects.App [String]
openReportScope =
  SDK.runOnce (SDK.Slot 6 "ReportScope")
  . SDK.withErrorPath ["ReportScope"]
  . SDK.handleFailure
  . SDK.atomicScope "openReportScope" [] []
  . SDK.openScope (SDK.Slot 6 "ReportScope") Effects.ScopeBindingError (Just (() <$ closeReportScope))
  . SDK.enterHandler (SDK.Slot 6 "ReportScope") $
    getOpenedReport >> call @"ReportScope" @"openTextFile" Effects.openTextFile

closeReportScope :: Effects.App [String]
closeReportScope =
  SDK.withErrorPath ["ReportScope"]
  . SDK.handleFailure
  . SDK.atomicScope "closeReportScope" [] []
  . SDK.closeScope (SDK.Slot 6 "ReportScope") Effects.ScopeBindingError
  . SDK.enterHandler (SDK.Slot 6 "ReportScope") $
    callClose @"ReportScope" @"closeTextFile" Effects.closeTextFile

openReplyScope :: Effects.App [String]
openReplyScope =
  SDK.runOnce (SDK.Slot 7 "ReplyScope")
  . SDK.withErrorPath ["ReplyScope"]
  . SDK.handleFailure
  . SDK.atomicScope "openReplyScope" [] []
  . SDK.openScope (SDK.Slot 7 "ReplyScope") Effects.ScopeBindingError (Just (() <$ closeReplyScope))
  . SDK.enterHandler (SDK.Slot 7 "ReplyScope") $
    getOpenedReply >> call @"ReplyScope" @"openTextFile" Effects.openTextFile

closeReplyScope :: Effects.App [String]
closeReplyScope =
  SDK.withErrorPath ["ReplyScope"]
  . SDK.handleFailure
  . SDK.atomicScope "closeReplyScope" [] []
  . SDK.closeScope (SDK.Slot 7 "ReplyScope") Effects.ScopeBindingError
  . SDK.enterHandler (SDK.Slot 7 "ReplyScope") $
    callClose @"ReplyScope" @"closeTextFile" Effects.closeTextFile

runWriteReport :: Effects.App [String]
runWriteReport =
  SDK.runOnce (SDK.Slot 8 "WriteReport")
  . SDK.withErrorPath ["ReportScope"]
  . SDK.handleFailure
  . SDK.atomicHandle "runWriteReport" [] []
  . SDK.withScopeDependencies [(SDK.Slot 6 "ReportScope")]
  . SDK.enterHandler (SDK.Slot 8 "WriteReport") $
    openReportScope >> getReportBody >> call @"WriteReport" @"writeText" Effects.writeText

runWriteReply :: Effects.App [String]
runWriteReply =
  SDK.runOnce (SDK.Slot 9 "WriteReply")
  . SDK.withErrorPath ["ReplyScope"]
  . SDK.handleFailure
  . SDK.atomicHandle "runWriteReply" [] []
  . SDK.withScopeDependencies [(SDK.Slot 7 "ReplyScope")]
  . SDK.enterHandler (SDK.Slot 9 "WriteReply") $
    openReplyScope >> getReplyBody >> call @"WriteReply" @"writeText" Effects.writeText

runMarkReply :: Effects.App [String]
runMarkReply =
  SDK.runOnce (SDK.Slot 10 "MarkReply")
  . SDK.handleFailure
  . SDK.atomicHandle "runMarkReply" [] []
  . SDK.enterHandler (SDK.Slot 10 "MarkReply") $
    call @"MarkReply" @"markRead" Effects.markRead

runReadReport :: Effects.App [String]
runReadReport =
  SDK.runOnce (SDK.Slot 11 "ReadReport")
  . SDK.handleFailure
  . SDK.atomicHandle "runReadReport" [((SDK.Slot 13 "ReportCounter"), () <$ getReportStats)] []
  . SDK.enterHandler (SDK.Slot 11 "ReadReport") $
    call @"ReadReport" @"readText" Effects.readText

runReadReply :: Effects.App [String]
runReadReply =
  SDK.runOnce (SDK.Slot 12 "ReadReply")
  . SDK.handleFailure
  . SDK.atomicHandle "runReadReply" [((SDK.Slot 14 "ReplyCounter"), () <$ getReplyStats)] []
  . SDK.enterHandler (SDK.Slot 12 "ReadReply") $
    runMarkReply >> call @"ReadReply" @"readText" Effects.readText

getReportStats :: Effects.App Effects.ReportStats
getReportStats =
  SDK.handleFailure
  . SDK.callContext (SDK.Slot 13 "ReportCounter")
      (\value bindings -> bindings { Effects.boundReportCounter = Just value })
      Effects.boundReportCounter $
    Effects.ReportStats <$> call @"ReportCounter" @"countLines" Effects.countLines

readReportStats :: Effects.App Effects.ReportStats
readReportStats =
  SDK.handleFailure $
    SDK.readContext (SDK.Slot 13 "ReportCounter") Effects.ContextBindingError Effects.boundReportCounter

getReplyStats :: Effects.App Effects.ReplyStats
getReplyStats =
  SDK.handleFailure
  . SDK.callContext (SDK.Slot 14 "ReplyCounter")
      (\value bindings -> bindings { Effects.boundReplyCounter = Just value })
      Effects.boundReplyCounter $
    Effects.ReplyStats <$> call @"ReplyCounter" @"countLines" Effects.countLines

readReplyStats :: Effects.App Effects.ReplyStats
readReplyStats =
  SDK.handleFailure $
    SDK.readContext (SDK.Slot 14 "ReplyCounter") Effects.ContextBindingError Effects.boundReplyCounter

runShowReport :: Effects.App [String]
runShowReport =
  SDK.runOnce (SDK.Slot 15 "ShowReport")
  . SDK.handleFailure
  . SDK.atomicHandle "runShowReport" [] []
  . SDK.enterHandler (SDK.Slot 15 "ShowReport") $
    SDK.producingFor [(SDK.Slot 13 "ReportCounter")] (runReadReport) >> getReportStats >> call @"ShowReport" @"showCount" Effects.showCount

runShowReply :: Effects.App [String]
runShowReply =
  SDK.runOnce (SDK.Slot 16 "ShowReply")
  . SDK.handleFailure
  . SDK.atomicHandle "runShowReply" [] []
  . SDK.enterHandler (SDK.Slot 16 "ShowReply") $
    SDK.producingFor [(SDK.Slot 14 "ReplyCounter")] (runReadReply) >> getReplyStats >> call @"ShowReply" @"showCount" Effects.showCount

runInspectReport :: Effects.App [String]
runInspectReport =
  SDK.runOnce (SDK.Slot 17 "InspectReport")
  . SDK.handleFailure
  . SDK.atomicHandle "runInspectReport" [] []
  . SDK.enterHandler (SDK.Slot 17 "InspectReport") $
    call @"InspectReport" @"inspectFile" Effects.inspectFile

getReportEmpty :: Effects.App Effects.ReportEmpty
getReportEmpty =
  SDK.handleFailure
  . SDK.callContext (SDK.Slot 18 "ReportBlank")
      (\value bindings -> bindings { Effects.boundReportBlank = Just value })
      Effects.boundReportBlank $
    Effects.ReportEmpty <$> call @"ReportBlank" @"parseBlankReport" Effects.parseBlankReport

readReportEmpty :: Effects.App Effects.ReportEmpty
readReportEmpty =
  SDK.handleFailure $
    SDK.readContext (SDK.Slot 18 "ReportBlank") Effects.ContextBindingError Effects.boundReportBlank

getReportText :: Effects.App Effects.ReportText
getReportText =
  SDK.handleFailure
  . SDK.callContext (SDK.Slot 19 "ReportFilled")
      (\value bindings -> bindings { Effects.boundReportFilled = Just value })
      Effects.boundReportFilled $
    Effects.ReportText <$> call @"ReportFilled" @"parseFilledReport" Effects.parseFilledReport

readReportText :: Effects.App Effects.ReportText
readReportText =
  SDK.handleFailure $
    SDK.readContext (SDK.Slot 19 "ReportFilled") Effects.ContextBindingError Effects.boundReportFilled

runOnBlank :: Effects.App [String]
runOnBlank =
  SDK.runOnce (SDK.Slot 20 "OnBlank")
  . SDK.handleFailure
  . SDK.atomicHandle "runOnBlank" [] []
  . SDK.enterHandler (SDK.Slot 20 "OnBlank") $
    call @"OnBlank" @"describeBlank" Effects.describeBlank

runOnFilled :: Effects.App [String]
runOnFilled =
  SDK.runOnce (SDK.Slot 21 "OnFilled")
  . SDK.handleFailure
  . SDK.atomicHandle "runOnFilled" [] []
  . SDK.enterHandler (SDK.Slot 21 "OnFilled") $
    call @"OnFilled" @"describeFilled" Effects.describeFilled

nextFeedA :: Effects.App ()
nextFeedA =
  SDK.handleFailure
  . SDK.enterHandler (SDK.Slot 22 "FeedA") $
    call @"FeedA" @"nextA" Effects.nextA

nextFeedB :: Effects.App ()
nextFeedB =
  SDK.handleFailure
  . SDK.enterHandler (SDK.Slot 23 "FeedB") $
    call @"FeedB" @"nextB" Effects.nextB

getLevelA :: Effects.App Effects.LevelA
getLevelA =
  SDK.handleFailure
  . SDK.callContext (SDK.Slot 24 "ParserA")
      (\value bindings -> bindings { Effects.boundParserA = Just value })
      Effects.boundParserA $
    Effects.LevelA <$> call @"ParserA" @"parseLevel" Effects.parseLevel

streamLevelA :: Effects.App Effects.LevelA
streamLevelA =
  SDK.handleFailure $
    SDK.readStreamContext (SDK.Slot 24 "ParserA") Effects.ContextBindingError Effects.boundParserA

historyLevelA :: Effects.App (SDK.Flow Effects.LevelA)
historyLevelA =
  SDK.handleFailure $
    SDK.readStreamHistory (SDK.Slot 24 "ParserA") Effects.ContextBindingError Effects.boundParserA

getLevelB :: Effects.App Effects.LevelB
getLevelB =
  SDK.handleFailure
  . SDK.callContext (SDK.Slot 25 "ParserB")
      (\value bindings -> bindings { Effects.boundParserB = Just value })
      Effects.boundParserB $
    Effects.LevelB <$> call @"ParserB" @"parseLevel" Effects.parseLevel

streamLevelB :: Effects.App Effects.LevelB
streamLevelB =
  SDK.handleFailure $
    SDK.readStreamContext (SDK.Slot 25 "ParserB") Effects.ContextBindingError Effects.boundParserB

historyLevelB :: Effects.App (SDK.Flow Effects.LevelB)
historyLevelB =
  SDK.handleFailure $
    SDK.readStreamHistory (SDK.Slot 25 "ParserB") Effects.ContextBindingError Effects.boundParserB

runShowA :: Effects.App [String]
runShowA =
  SDK.runOnce (SDK.Slot 26 "ShowA")
  . SDK.handleFailure
  . SDK.atomicHandle "runShowA" [] []
  . SDK.enterHandler (SDK.Slot 26 "ShowA") $
    call @"ShowA" @"showLevel" Effects.showLevel

runShowB :: Effects.App [String]
runShowB =
  SDK.runOnce (SDK.Slot 27 "ShowB")
  . SDK.handleFailure
  . SDK.atomicHandle "runShowB" [] []
  . SDK.enterHandler (SDK.Slot 27 "ShowB") $
    call @"ShowB" @"showLevel" Effects.showLevel

-- SDK 内部：scope 按上游到下游登记，退出时逆序收尾；创建不执行业务方法。
newScopeHandlers :: IO [SDK.ScopeHandler Effects.ContextValues Effects.Errors]
newScopeHandlers = sequence
  [ SDK.newScopeHandler (SDK.Slot 6 "ReportScope") [(SDK.Slot 0 "ReportLocation")] (Just (SDK.Slot 4 "ReportFile"))
  , SDK.newScopeHandler (SDK.Slot 7 "ReplyScope") [(SDK.Slot 1 "ReplyLocation")] (Just (SDK.Slot 5 "ReplyFile"))
  ]

-- Error 回调登记：按 handles 匹配故障的 handler 与协议分类；关联 scope 由 Input 链推导。
errorHandlers :: [(Maybe String, SDK.ErrorHandler Effects.Errors Effects.App)]
errorHandlers = []
