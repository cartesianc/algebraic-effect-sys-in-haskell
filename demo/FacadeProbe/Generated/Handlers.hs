-- 自动生成的编译副本；请修改上级 Handlers.hs 后重新生成。
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE UndecidableInstances #-}

{-# OPTIONS_GHC -Werror=missing-methods #-}

-- Today's explicit form of the same program: the baseline, and the source of the prototype.
module FacadeProbe.Generated.Handlers (handlerSourceFingerprint, newScopeHandlers, scopeCleanups, errorHandlers, contextInjections) where

import qualified Framework.SDK as FrameworkRuntime
import qualified Framework.Effect.Contract as FrameworkRoot
import qualified FacadeProbe.Generated.Effects as FrameworkGenerated
import Framework.SDK (Effect(..), historySize, latest)
import FacadeProbe.Generated.Effects
import FacadeProbe.Types
import FacadeProbe.Contracts
import FacadeProbe.Facade ()
import Control.Concurrent (threadDelay)
import Control.Monad (when)
import Control.Monad.IO.Class (liftIO)
import System.FilePath ((</>))
import System.IO (IOMode(WriteMode), hClose, hFlush, hPutStr, openFile, readFile')

instance ReportLocationInputs m => ReportLocationEffect m where
  getReportPath =
    (FrameworkRoot.withErrorPath [] . FrameworkRoot.handler @FrameworkGenerated.Root . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.callContext "ReportLocation" FrameworkGenerated.ContextBindingError
      [("ReportFile", FrameworkRuntime.RequireValue), ("ReadReport", FrameworkRuntime.RequireValue), ("ReportInspect", FrameworkRuntime.RequireValue)]
      (Just (FrameworkRuntime.ScopeInput "ReportLocation"))
      FrameworkGenerated.boundReportLocation
      (\value bindings -> bindings { FrameworkGenerated.boundReportLocation = Just value })) $
      let
        getReportPath :: (m) (FrameworkGenerated.ReportPath)
        getReportPath = do
          pure (ReportPath ("demo" </> "FacadeProbe" </> "output" </> "report.txt"))
      in getReportPath

instance ReplyLocationInputs m => ReplyLocationEffect m where
  getReplyPath =
    (FrameworkRoot.withErrorPath [] . FrameworkRoot.handler @FrameworkGenerated.Root . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.callContext "ReplyLocation" FrameworkGenerated.ContextBindingError
      [("ReplyFile", FrameworkRuntime.RequireValue), ("ReadReply", FrameworkRuntime.RequireValue)]
      (Just (FrameworkRuntime.ScopeInput "ReplyLocation"))
      FrameworkGenerated.boundReplyLocation
      (\value bindings -> bindings { FrameworkGenerated.boundReplyLocation = Just value })) $
      let
        getReplyPath :: (m) (FrameworkGenerated.ReplyPath)
        getReplyPath = do
          pure (ReplyPath ("demo" </> "FacadeProbe" </> "output" </> "reply.txt"))
      in getReplyPath

instance ReportDraftInputs m => ReportDraftEffect m where
  getReportBody =
    (FrameworkRoot.withErrorPath [] . FrameworkRoot.handler @FrameworkGenerated.Root . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.callContext "ReportDraft" FrameworkGenerated.ContextBindingError
      [("WriteReport", FrameworkRuntime.RequireValue)]
      Nothing
      FrameworkGenerated.boundReportDraft
      (\value bindings -> bindings { FrameworkGenerated.boundReportDraft = Just value })) $
      let
        getReportBody :: (m) (FrameworkGenerated.ReportBody)
        getReportBody = do
          pure (ReportBody (Body "report line 1\nreport line 2\nreport line 3\n"))
      in getReportBody

instance ReplyDraftInputs m => ReplyDraftEffect m where
  getReplyBody =
    (FrameworkRoot.withErrorPath [] . FrameworkRoot.handler @FrameworkGenerated.Root . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.callContext "ReplyDraft" FrameworkGenerated.ContextBindingError
      [("WriteReply", FrameworkRuntime.RequireValue)]
      Nothing
      FrameworkGenerated.boundReplyDraft
      (\value bindings -> bindings { FrameworkGenerated.boundReplyDraft = Just value })) $
      let
        getReplyBody :: (m) (FrameworkGenerated.ReplyBody)
        getReplyBody = do
          pure (ReplyBody (Body "reply line 1\n"))
      in getReplyBody

instance (ReportFileInputs m, AcquireFileHandler m) => ReportFileEffect m where
  getOpenedReport =
    (FrameworkRoot.withErrorPath [] . FrameworkRoot.handler @FrameworkGenerated.Root . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.callContext "ReportFile" FrameworkGenerated.ContextBindingError
      [("ReportScope", FrameworkRuntime.RequestValue), ("WriteReport", FrameworkRuntime.RequireValue)]
      Nothing
      FrameworkGenerated.boundReportFile
      (\value bindings -> bindings { FrameworkGenerated.boundReportFile = Just value })) $
      let
        getOpenedReport :: (m) (FrameworkGenerated.OpenedReport)
        getOpenedReport = OpenedReport <$> acquireFile
      in getOpenedReport

instance (ReplyFileInputs m, AcquireFileHandler m) => ReplyFileEffect m where
  getOpenedReply =
    (FrameworkRoot.withErrorPath [] . FrameworkRoot.handler @FrameworkGenerated.Root . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.callContext "ReplyFile" FrameworkGenerated.ContextBindingError
      [("ReplyScope", FrameworkRuntime.RequestValue), ("WriteReply", FrameworkRuntime.RequireValue)]
      Nothing
      FrameworkGenerated.boundReplyFile
      (\value bindings -> bindings { FrameworkGenerated.boundReplyFile = Just value })) $
      let
        getOpenedReply :: (m) (FrameworkGenerated.OpenedReply)
        getOpenedReply = OpenedReply <$> acquireFile
      in getOpenedReply

instance (ReportScopeInputs m, OpenTextFileHandler m, CloseTextFileHandler m) => ReportScopeEffect m where
  openReport =
    (FrameworkRoot.withErrorPath ["ReportScope"] . FrameworkRoot.handler @FrameworkGenerated.Root . FrameworkRuntime.atomicScope "openReport" . FrameworkRuntime.openScope "ReportScope" FrameworkGenerated.ScopeBindingError . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.enterHandler "ReportScope") $
      let
        openReport :: (m) (Maybe String)
        openReport = openTextFile
      in openReport
  closeReport =
    (FrameworkRoot.withErrorPath ["ReportScope"] . FrameworkRoot.handler @FrameworkGenerated.Root . FrameworkRuntime.atomicScope "closeReport" . FrameworkRuntime.closeScope "ReportScope" FrameworkGenerated.ScopeBindingError . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.enterHandler "ReportScope") $
      let
        closeReport :: (m) (Maybe String)
        closeReport = closeTextFile
      in closeReport

instance (ReplyScopeInputs m, OpenTextFileHandler m, CloseTextFileHandler m) => ReplyScopeEffect m where
  openReply =
    (FrameworkRoot.withErrorPath ["ReplyScope"] . FrameworkRoot.handler @FrameworkGenerated.Root . FrameworkRuntime.atomicScope "openReply" . FrameworkRuntime.openScope "ReplyScope" FrameworkGenerated.ScopeBindingError . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.enterHandler "ReplyScope") $
      let
        openReply :: (m) (Maybe String)
        openReply = openTextFile
      in openReply
  closeReply =
    (FrameworkRoot.withErrorPath ["ReplyScope"] . FrameworkRoot.handler @FrameworkGenerated.Root . FrameworkRuntime.atomicScope "closeReply" . FrameworkRuntime.closeScope "ReplyScope" FrameworkGenerated.ScopeBindingError . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.enterHandler "ReplyScope") $
      let
        closeReply :: (m) (Maybe String)
        closeReply = closeTextFile
      in closeReply

instance (WriteReportInputs m, WriteTextHandler m) => WriteReportEffect m where
  writeReport =
    (FrameworkRoot.withErrorPath ["ReportScope"] . FrameworkRoot.handler @FrameworkGenerated.Root . FrameworkRuntime.atomicHandle "writeReport" . FrameworkRuntime.withScopeDependencies ["ReportScope"] . FrameworkRuntime.enterHandler "WriteReport") $
      let
        writeReport :: (m) (Maybe String)
        writeReport = openReport >> writeText
      in writeReport

instance (WriteReplyInputs m, WriteTextHandler m) => WriteReplyEffect m where
  writeReply =
    (FrameworkRoot.withErrorPath ["ReplyScope"] . FrameworkRoot.handler @FrameworkGenerated.Root . FrameworkRuntime.atomicHandle "writeReply" . FrameworkRuntime.withScopeDependencies ["ReplyScope"] . FrameworkRuntime.enterHandler "WriteReply") $
      let
        writeReply :: (m) (Maybe String)
        writeReply = openReply >> writeText
      in writeReply

instance (MarkReplyInputs m, MarkReadHandler m) => MarkReplyEffect m where
  markReply =
    (FrameworkRoot.withErrorPath [] . FrameworkRoot.handler @FrameworkGenerated.Root . FrameworkRuntime.atomicHandle "markReply" . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.enterHandler "MarkReply") $
      let
        markReply :: (m) (Maybe String)
        markReply = markRead
      in markReply

instance (ReadReportInputs m, ReadTextHandler m) => ReadReportEffect m where
  readReport =
    (FrameworkRoot.withErrorPath [] . FrameworkRoot.handler @FrameworkGenerated.Root . FrameworkRuntime.atomicHandle "readReport" . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.enterHandler "ReadReport") $
      let
        readReport :: (m) (Maybe String)
        readReport = readText
      in readReport

instance (ReadReplyInputs m, ReadTextHandler m) => ReadReplyEffect m where
  readReply =
    (FrameworkRoot.withErrorPath [] . FrameworkRoot.handler @FrameworkGenerated.Root . FrameworkRuntime.atomicHandle "readReply" . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.enterHandler "ReadReply") $
      let
        readReply :: (m) (Maybe String)
        readReply = markReply >> readText
      in readReply

instance (ReportCounterInputs m, CountLinesHandler m) => ReportCounterEffect m where
  getReportStats =
    (FrameworkRoot.withErrorPath [] . FrameworkRoot.handler @FrameworkGenerated.Root . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.callContext "ReportCounter" FrameworkGenerated.ContextBindingError
      [("ShowReport", FrameworkRuntime.RequireValue)]
      Nothing
      FrameworkGenerated.boundReportCounter
      (\value bindings -> bindings { FrameworkGenerated.boundReportCounter = Just value })) $
      let
        getReportStats :: (m) (FrameworkGenerated.ReportStats)
        getReportStats = ReportStats <$> countLines
      in getReportStats

instance (ReplyCounterInputs m, CountLinesHandler m) => ReplyCounterEffect m where
  getReplyStats =
    (FrameworkRoot.withErrorPath [] . FrameworkRoot.handler @FrameworkGenerated.Root . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.callContext "ReplyCounter" FrameworkGenerated.ContextBindingError
      [("ShowReply", FrameworkRuntime.RequireValue)]
      Nothing
      FrameworkGenerated.boundReplyCounter
      (\value bindings -> bindings { FrameworkGenerated.boundReplyCounter = Just value })) $
      let
        getReplyStats :: (m) (FrameworkGenerated.ReplyStats)
        getReplyStats = ReplyStats <$> countLines
      in getReplyStats

instance (ShowReportInputs m, ShowCountHandler m) => ShowReportEffect m where
  showReport =
    (FrameworkRoot.withErrorPath [] . FrameworkRoot.handler @FrameworkGenerated.Root . FrameworkRuntime.atomicHandle "showReport" . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.enterHandler "ShowReport") $
      let
        showReport :: (m) (Maybe String)
        showReport = showCount
      in showReport

instance (ShowReplyInputs m, ShowCountHandler m) => ShowReplyEffect m where
  showReply =
    (FrameworkRoot.withErrorPath [] . FrameworkRoot.handler @FrameworkGenerated.Root . FrameworkRuntime.atomicHandle "showReply" . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.enterHandler "ShowReply") $
      let
        showReply :: (m) (Maybe String)
        showReply = showCount
      in showReply

instance (ReportInspectInputs m, InspectFileHandler m) => ReportInspectEffect m where
  getReportState =
    (FrameworkRoot.withErrorPath [] . FrameworkRoot.handler @FrameworkGenerated.Root . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.callContext "ReportInspect" FrameworkGenerated.ContextBindingError
      [("OnBlank", FrameworkRuntime.RequireValue), ("OnFilled", FrameworkRuntime.RequireValue)]
      Nothing
      FrameworkGenerated.boundReportInspect
      (\value bindings -> bindings { FrameworkGenerated.boundReportInspect = Just value })) $
      let
        getReportState :: (m) (FrameworkGenerated.ReportState)
        getReportState = ReportState <$> inspectFile
      in getReportState

instance (OnBlankInputs m, DescribeBlankHandler m) => OnBlankEffect m where
  onBlank =
    (FrameworkRoot.withErrorPath [] . FrameworkRoot.handler @FrameworkGenerated.Root . FrameworkRuntime.atomicHandle "onBlank" . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.enterHandler "OnBlank") $
      let
        onBlank :: (m) (Maybe String)
        onBlank = describeBlank
      in onBlank

instance (OnFilledInputs m, DescribeFilledHandler m) => OnFilledEffect m where
  onFilled =
    (FrameworkRoot.withErrorPath [] . FrameworkRoot.handler @FrameworkGenerated.Root . FrameworkRuntime.atomicHandle "onFilled" . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.enterHandler "OnFilled") $
      let
        onFilled :: (m) (Maybe String)
        onFilled = describeFilled
      in onFilled

instance FeedAInputs m => FeedAEffect m where
  nextA =
    (FrameworkRoot.withErrorPath [] . FrameworkRoot.handler @FrameworkGenerated.Root . FrameworkRuntime.streamHandle . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.enterHandler "FeedA") $
      let
        nextA :: (m) (String)
        nextA = do
          liftIO (threadDelay 40000)
          pure "10"
      in nextA

instance FeedBInputs m => FeedBEffect m where
  nextB =
    (FrameworkRoot.withErrorPath [] . FrameworkRoot.handler @FrameworkGenerated.Root . FrameworkRuntime.streamHandle . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.enterHandler "FeedB") $
      let
        nextB :: (m) (String)
        nextB = do
          liftIO (threadDelay 60000)
          pure "20"
      in nextB

instance (ParserAInputs m, ParseLevelHandler m) => ParserAEffect m where
  getLevelA =
    (FrameworkRoot.withErrorPath [] . FrameworkRoot.handler @FrameworkGenerated.Root . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.callContext "ParserA" FrameworkGenerated.ContextBindingError
      [("ShowA", FrameworkRuntime.RequireValue)]
      Nothing
      FrameworkGenerated.boundParserA
      (\value bindings -> bindings { FrameworkGenerated.boundParserA = Just value })) $
      let
        getLevelA :: (m) (FrameworkGenerated.LevelA)
        getLevelA = LevelA <$> parseLevel
      in getLevelA

instance (ParserBInputs m, ParseLevelHandler m) => ParserBEffect m where
  getLevelB =
    (FrameworkRoot.withErrorPath [] . FrameworkRoot.handler @FrameworkGenerated.Root . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.callContext "ParserB" FrameworkGenerated.ContextBindingError
      [("ShowB", FrameworkRuntime.RequireValue)]
      Nothing
      FrameworkGenerated.boundParserB
      (\value bindings -> bindings { FrameworkGenerated.boundParserB = Just value })) $
      let
        getLevelB :: (m) (FrameworkGenerated.LevelB)
        getLevelB = LevelB <$> parseLevel
      in getLevelB

instance (ShowAInputs m, ShowLevelHandler m) => ShowAEffect m where
  showA =
    (FrameworkRoot.withErrorPath [] . FrameworkRoot.handler @FrameworkGenerated.Root . FrameworkRuntime.atomicHandle "showA" . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.enterHandler "ShowA") $
      let
        showA :: (m) (Maybe String)
        showA = showLevel
      in showA

instance (ShowBInputs m, ShowLevelHandler m) => ShowBEffect m where
  showB =
    (FrameworkRoot.withErrorPath [] . FrameworkRoot.handler @FrameworkGenerated.Root . FrameworkRuntime.atomicHandle "showB" . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.enterHandler "ShowB") $
      let
        showB :: (m) (Maybe String)
        showB = showLevel
      in showB

-- 记录本编译副本实际使用的手写源码；启动前检查，避免执行过期方法体。
handlerSourceFingerprint :: Maybe String
handlerSourceFingerprint = Just "4ebfaea79402e14d9f12bd790ada677b"


-- SDK 内部：scope 按上游到下游登记，退出时逆序收尾；创建不执行业务方法。
newScopeHandlers :: IO [FrameworkRuntime.ScopeHandler FrameworkGenerated.ContextValues FrameworkGenerated.Errors]
newScopeHandlers = sequence
  [ FrameworkRuntime.newScopeHandler "ReportScope" ["ReportLocation"] (Just "ReportFile")
  , FrameworkRuntime.newScopeHandler "ReplyScope" ["ReplyLocation"] (Just "ReplyFile")
  ]

-- SDK 自动收尾入口；安装时不关闭资源。
scopeCleanups :: [(String, FrameworkGenerated.App ())]
scopeCleanups =
  [ ("ReportScope", () <$ closeReport)
  , ("ReplyScope", () <$ closeReply)
  ]

-- Error 回调登记：按 handles 匹配故障来源与分类；关联 scope 由 Input 链推导。
errorHandlers :: [(Maybe String, FrameworkRoot.ErrorHandler FrameworkGenerated.Errors FrameworkGenerated.App)]
errorHandlers =
  [
  ]

-- 挂在原子句柄下的 Context：句柄的输出交给它解析并发布为资产；没有挂接时输出被丢弃。
contextInjections :: [(String, [(String, FrameworkGenerated.App ())])]
contextInjections =
  [ ("readReport", [("ReportCounter", () <$ getReportStats)])
  , ("readReply", [("ReplyCounter", () <$ getReplyStats)])
  ]


route :: String -> [(String, App value)] -> App value
route contract = FrameworkRuntime.provideContext "FacadeProbe" contract FrameworkGenerated.ContextBindingError

reportPath', replyPath' :: App FilePath
reportPath' = require @ReportPath >>= \(ReportPath value) -> pure value
replyPath' = require @ReplyPath >>= \(ReplyPath value) -> pure value

opened, replied :: App TextFile
opened = require @OpenedReport >>= \(OpenedReport value) -> pure value
replied = require @OpenedReply >>= \(OpenedReply value) -> pure value

instance Provides FilePath App where
  type Reading FilePath = FilePath
  request = route "FilePath" []
  require = route "FilePath"
    [ ("ReportFile", reportPath'), ("ReadReport", reportPath'), ("ReportInspect", reportPath')
    , ("ReplyFile", replyPath'), ("ReadReply", replyPath') ]

instance Provides TextFile App where
  type Reading TextFile = TextFile
  request = route "TextFile"
    [ ("ReportScope", request @OpenedReport >>= \(OpenedReport value) -> pure value)
    , ("ReplyScope", request @OpenedReply >>= \(OpenedReply value) -> pure value) ]
  require = route "TextFile"
    [ ("ReportScope", opened), ("WriteReport", opened), ("ReplyScope", replied), ("WriteReply", replied) ]

instance Provides Body App where
  type Reading Body = Body
  request = route "Body" []
  require = route "Body"
    [ ("WriteReport", require @ReportBody >>= \(ReportBody value) -> pure value)
    , ("WriteReply", require @ReplyBody >>= \(ReplyBody value) -> pure value)
    , ("OnFilled", require @ReportStateFilled >>= \(ReportStateFilled value) -> pure value) ]

instance Provides LineCount App where
  type Reading LineCount = LineCount
  request = route "LineCount" []
  require = route "LineCount"
    [ ("ShowReport", require @ReportStats >>= \(ReportStats value) -> pure value)
    , ("ShowReply", require @ReplyStats >>= \(ReplyStats value) -> pure value) ]

instance Provides (History Level) App where
  type Reading (History Level) = History Level
  request = route "History Level" []
  require = route "History Level"
    [ ("ShowA", fmap (\(LevelA value) -> value) <$> require @LevelA)
    , ("ShowB", fmap (\(LevelB value) -> value) <$> require @LevelB) ]

instance UpstreamOutput App where
  upstreamOutput = route "upstream output"
    [ ("ReportCounter", readReport), ("ReplyCounter", readReply) ]

instance UpstreamRaw App where
  upstreamRaw = route "upstream raw"
    [ ("ParserA", nextA), ("ParserB", nextB) ]

instance FailWith App where
  failWith message = route "failure"
    [ ("ReportCounter", raise (ReportCounterError message))
    , ("ReplyCounter", raise (ReplyCounterError message))
    , ("ParserA", raise (ParserAError message))
    , ("ParserB", raise (ParserBError message))
    , ("ShowA", raise (ShowAError message))
    , ("ShowB", raise (ShowBError message)) ]
