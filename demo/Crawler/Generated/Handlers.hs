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
-- handler 是不带参数的类方法；SDK 按注册装配上游与读取来源，运行编译 Generated 副本。
{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE UndecidableInstances #-}

{-# OPTIONS_GHC -Werror=missing-methods #-}

module Crawler.Generated.Handlers (handlerSourceFingerprint, getStartURL, readStartURL, getLinkedURL, readLinkedURL, runFetchPage, runKeepPageBody, getStartPageSummary, readStartPageSummary, runPrintPage, runFetchLinkedPage, runKeepLinkedPageBody, getLinkedPageSummary, readLinkedPageSummary, runPrintLinkedPage, getCrawlSessionInfo, readCrawlSessionInfo, openCrawlSession, closeCrawlSession, newScopeHandlers, errorHandlers) where

import qualified Framework.Generated as FrameworkRuntime
import qualified Crawler.Generated.Effects as FrameworkGenerated
import qualified Control.Monad.IO.Class as FrameworkIO
import qualified Data.Proxy as FrameworkProxy
import qualified GHC.TypeLits as FrameworkTypes
import Crawler.Types
import Framework.SDK (Raises(..), Raw(..), Reads(..), rawoutput)
import Crawler.Generated.Effects
import Crawler.Types
import Control.Concurrent (forkFinally, killThread, newEmptyMVar, putMVar, takeMVar)
import Control.Exception (bracket, displayException, throwIO)
import Control.Monad.IO.Class (liftIO)
import Data.Char (isSpace)
import Data.List (intercalate)
import System.Exit (ExitCode(..))
import System.IO (hFlush, hGetContents', hSetEncoding, stdout, utf8)
import System.IO.Error (tryIOError)
import System.Process (CreateProcess(..), StdStream(..), proc, waitForProcess, withCreateProcess)
import Text.HTML.TagSoup
  ( canonicalizeTags, fromAttrib, innerText, isTagCloseName, isTagOpenName, parseTags, sections )


-- 3. Handler code：handler 只按表示类型 require；读的是哪份资产由绑定它的 effect 的 demands 决定。
-- 抓取是原子句柄，只执行 IO 并交出网页正文；Pure 去掉空白正文，解析由挂在 Pure 下的 Context 产值；
-- 打印只完成操作，不交出输出。
instance StartURLLayer m => StartURLHandler m where
  startURL = pure (PageURL "https://www.google.com")

instance LinkedURLLayer m => LinkedURLHandler m where
  linkedURL = pure (PageURL "https://www.baidu.com")

-- FetchPage 与 FetchLinkedPage 共用：Input CrawlSession 已开启，requests 已刷新 URL。
instance FetchPageLayer m => FetchPageHandler m where
  fetchPage = do
    PageURL url <- require @PageURL
    SessionInfo _ userAgent <- require @SessionInfo
    -- 参数直接传给 curl 进程，不经过 shell。
    let arguments =
          [ "--disable", "--silent", "--show-error", "--fail", "--location"
          , "--max-redirs", "3", "--connect-timeout", "5", "--max-time", "15"
          , "--proto", "=http,https", "--proto-redir", "=http,https"
          , "--globoff", "--max-filesize", "2097152"
          , "--user-agent", userAgent, "--url", url
          ]
    outcome <- liftIO $ tryIOError $
      withCreateProcess (proc "curl" arguments)
        { std_in = NoStream, std_out = CreatePipe, std_err = CreatePipe } $
        \_ (Just output) (Just errors) process -> do
          -- 网页按 UTF-8 解码；并行排空 stderr，避免管道阻塞。
          hSetEncoding output utf8
          completed <- newEmptyMVar
          bracket (forkFinally (hGetContents' errors) (putMVar completed)) killThread $ \_ -> do
            body <- hGetContents' output
            diagnostic <- takeMVar completed >>= either throwIO pure
            status <- waitForProcess process
            pure (status, body, diagnostic)
    case outcome of
      Left problem -> raise (FetchPageError (url ++ ": " ++ displayException problem))
      Right (ExitFailure _, _, message) -> raise (FetchPageError (url ++ ": " ++ message))
      Right (ExitSuccess, html, _) -> rawoutput [html]

-- Pure，两个抓取链共用：rawinput 是本次抓取交出的 list，只留下有内容的正文；没有 IO，也不读资产。
instance DropBlankBodiesLayer m => DropBlankBodiesHandler m where
  dropBlankBodies = do
    bodies <- rawinput
    rawoutput (filter (not . all isSpace) bodies)

-- 挂在 Pure 下，两个解析共用：rawinput 是去掉空白后的 list（一页正文）。AST 执行抓取时由 SDK 注入，
-- 本次输出经 Pure 交到这里，不重新抓取；被 requests 驱动时，rawinput 经 Pure 执行抓取句柄，启动整条链。
instance ExtractSummaryLayer m => ExtractSummaryHandler m where
  extractSummary = do
    fetched <- rawinput
    PageURL url <- require @PageURL
    html <- case fetched of
      [page] -> pure page
      _ -> raise (ExtractSummaryError (url ++ ": fetch returned no page body"))
    let tags = canonicalizeTags (parseTags html)
        titleTags = takeWhile (not . isTagCloseName "title")
                  (drop 1 (dropWhile (not . isTagOpenName "title") tags))
        title = unwords (words (innerText titleTags))
        -- 内容契约是 p 段落文本，不模拟浏览器渲染或执行脚本。
        paragraphs =
          [ unwords (words (innerText (takeWhile (not . isTagCloseName "p") (drop 1 part))))
          | part <- sections (isTagOpenName "p") tags
          ]
        content = intercalate "\n" (filter (not . null) paragraphs)
        links = [href | tag <- tags, isTagOpenName "a" tag
                      , let href = fromAttrib "href" tag, not (null href)]
    pure (PageSummary url title content links)

-- 打印解析阶段产出的资产，两个打印共用；尚未解析时 require 会按需驱动抓取链。
instance PrintSummaryLayer m => PrintSummaryHandler m where
  printSummary = do
    PageSummary url title content links <- require @PageSummary
    let report = unlines
          ([ "URL: " ++ url
           , "Title: " ++ title
           , "Content:"
           , if null content then "  (no paragraphs)" else content
           , "Links:"
           ] ++ (if null links then ["  (none)"] else map ("  " ++) links) ++ [""])
    outcome <- liftIO (tryIOError (putStr report >> hFlush stdout))
    either (\problem -> raise (PrintSummaryError (url ++ ": " ++ displayException problem))) pure outcome
    rawoutput []

-- 会话信息由 Context 生产，SDK 在 scope 内保存并供各抓取链读取。
instance SessionInfoLayer m => SessionInfoHandler m where
  sessionInfo = pure (SessionInfo "crawler-demo" "algebraic-effect-sys-in-haskell/1.0")

-- 无开启输入的 scope 在实际重叠使用时共享；最后一条使用闭包退出后自动 close。
instance OpenSessionLayer m => OpenSessionHandler m where
  openSession = do
    SessionInfo name _ <- require @SessionInfo
    liftIO (putStrLn ("[scope] open " ++ name))
    rawoutput []

instance CloseSessionLayer m => CloseSessionHandler m where
  closeSession = do
    SessionInfo name _ <- require @SessionInfo
    liftIO (putStrLn ("[scope] close " ++ name))
    rawoutput []

-- 记录本编译副本实际使用的手写源码；启动前检查，避免执行过期方法体。
handlerSourceFingerprint :: Maybe String
handlerSourceFingerprint = Just "f8c100e855fb22092ce2e75164d11d60"

-- 以下由 gen 生成。每个 effect 一个类型标签：handler 在标签下执行，
-- 读取、rawinput 与错误按标签在编译期解析到这个 effect 的来源，不改写 handler 方法体。
newtype Wrap (effect :: FrameworkTypes.Symbol) value = Wrap { runWrap :: FrameworkGenerated.App value }
  deriving (Functor, Applicative, Monad, FrameworkIO.MonadIO)

instance FrameworkRuntime.Root (Wrap effect) value

instance FrameworkTypes.KnownSymbol effect => FrameworkRuntime.Raises FrameworkGenerated.StartURLError (Wrap effect) where
  raise (FrameworkGenerated.StartURLError description) = Wrap (FrameworkRuntime.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) FrameworkGenerated.StartURLFailure description)

instance FrameworkTypes.KnownSymbol effect => FrameworkRuntime.Raises FrameworkGenerated.LinkedURLError (Wrap effect) where
  raise (FrameworkGenerated.LinkedURLError description) = Wrap (FrameworkRuntime.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) FrameworkGenerated.LinkedURLFailure description)

instance FrameworkTypes.KnownSymbol effect => FrameworkRuntime.Raises FrameworkGenerated.FetchPageError (Wrap effect) where
  raise (FrameworkGenerated.FetchPageError description) = Wrap (FrameworkRuntime.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) FrameworkGenerated.FetchPageFailure description)

instance FrameworkTypes.KnownSymbol effect => FrameworkRuntime.Raises FrameworkGenerated.DropBlankBodiesError (Wrap effect) where
  raise (FrameworkGenerated.DropBlankBodiesError description) = Wrap (FrameworkRuntime.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) FrameworkGenerated.DropBlankBodiesFailure description)

instance FrameworkTypes.KnownSymbol effect => FrameworkRuntime.Raises FrameworkGenerated.ExtractSummaryError (Wrap effect) where
  raise (FrameworkGenerated.ExtractSummaryError description) = Wrap (FrameworkRuntime.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) FrameworkGenerated.ExtractSummaryFailure description)

instance FrameworkTypes.KnownSymbol effect => FrameworkRuntime.Raises FrameworkGenerated.PrintSummaryError (Wrap effect) where
  raise (FrameworkGenerated.PrintSummaryError description) = Wrap (FrameworkRuntime.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) FrameworkGenerated.PrintSummaryFailure description)

instance FrameworkTypes.KnownSymbol effect => FrameworkRuntime.Raises FrameworkGenerated.SessionInfoError (Wrap effect) where
  raise (FrameworkGenerated.SessionInfoError description) = Wrap (FrameworkRuntime.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) FrameworkGenerated.SessionInfoFailure description)

instance FrameworkTypes.KnownSymbol effect => FrameworkRuntime.Raises FrameworkGenerated.OpenSessionError (Wrap effect) where
  raise (FrameworkGenerated.OpenSessionError description) = Wrap (FrameworkRuntime.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) FrameworkGenerated.OpenSessionFailure description)

instance FrameworkTypes.KnownSymbol effect => FrameworkRuntime.Raises FrameworkGenerated.CloseSessionError (Wrap effect) where
  raise (FrameworkGenerated.CloseSessionError description) = Wrap (FrameworkRuntime.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) FrameworkGenerated.CloseSessionFailure description)

instance FrameworkRuntime.Reads (PageURL) (Wrap "FetchPage") where
  require = Wrap ((\(FrameworkGenerated.StartURL value) -> value) <$> readStartURL)

instance FrameworkRuntime.Reads (SessionInfo) (Wrap "FetchPage") where
  require = Wrap ((\(FrameworkGenerated.CrawlSessionInfo value) -> value) <$> readCrawlSessionInfo)

instance FrameworkRuntime.Reads (PageURL) (Wrap "ExtractPage") where
  require = Wrap ((\(FrameworkGenerated.StartURL value) -> value) <$> readStartURL)

instance FrameworkRuntime.Reads (PageSummary) (Wrap "PrintPage") where
  require = Wrap ((\(FrameworkGenerated.StartPageSummary value) -> value) <$> readStartPageSummary)

instance FrameworkRuntime.Reads (PageURL) (Wrap "FetchLinkedPage") where
  require = Wrap ((\(FrameworkGenerated.LinkedURL value) -> value) <$> readLinkedURL)

instance FrameworkRuntime.Reads (SessionInfo) (Wrap "FetchLinkedPage") where
  require = Wrap ((\(FrameworkGenerated.CrawlSessionInfo value) -> value) <$> readCrawlSessionInfo)

instance FrameworkRuntime.Reads (PageURL) (Wrap "ExtractLinkedPage") where
  require = Wrap ((\(FrameworkGenerated.LinkedURL value) -> value) <$> readLinkedURL)

instance FrameworkRuntime.Reads (PageSummary) (Wrap "PrintLinkedPage") where
  require = Wrap ((\(FrameworkGenerated.LinkedPageSummary value) -> value) <$> readLinkedPageSummary)

instance FrameworkRuntime.Reads (SessionInfo) (Wrap "CrawlSession") where
  require = Wrap ((\(FrameworkGenerated.CrawlSessionInfo value) -> value) <$> readCrawlSessionInfo)

instance FrameworkRuntime.Raw (Wrap "KeepPageBody") where
  rawinput = Wrap (runFetchPage)

instance FrameworkRuntime.Raw (Wrap "ExtractPage") where
  rawinput = Wrap (runKeepPageBody)

instance FrameworkRuntime.Raw (Wrap "KeepLinkedPageBody") where
  rawinput = Wrap (runFetchLinkedPage)

instance FrameworkRuntime.Raw (Wrap "ExtractLinkedPage") where
  rawinput = Wrap (runKeepLinkedPageBody)

getStartURL :: FrameworkGenerated.App FrameworkGenerated.StartURL
getStartURL = (FrameworkRuntime.withErrorPath [] . FrameworkRuntime.handleFailure . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.callContext "StartPage"
    (\value bindings -> bindings { FrameworkGenerated.boundStartPage = Just value })) $
  (FrameworkGenerated.StartURL <$> runWrap @"StartPage" (FrameworkRuntime.super "startURL" FrameworkGenerated.startURL))

readStartURL :: FrameworkGenerated.App FrameworkGenerated.StartURL
readStartURL = (FrameworkRuntime.withErrorPath [] . FrameworkRuntime.handleFailure) $
  FrameworkRuntime.readContext "StartPage" FrameworkGenerated.ContextBindingError FrameworkGenerated.boundStartPage

getLinkedURL :: FrameworkGenerated.App FrameworkGenerated.LinkedURL
getLinkedURL = (FrameworkRuntime.withErrorPath [] . FrameworkRuntime.handleFailure . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.callContext "LinkedPage"
    (\value bindings -> bindings { FrameworkGenerated.boundLinkedPage = Just value })) $
  (FrameworkGenerated.LinkedURL <$> runWrap @"LinkedPage" (FrameworkRuntime.super "linkedURL" FrameworkGenerated.linkedURL))

readLinkedURL :: FrameworkGenerated.App FrameworkGenerated.LinkedURL
readLinkedURL = (FrameworkRuntime.withErrorPath [] . FrameworkRuntime.handleFailure) $
  FrameworkRuntime.readContext "LinkedPage" FrameworkGenerated.ContextBindingError FrameworkGenerated.boundLinkedPage

runFetchPage :: FrameworkGenerated.App [String]
runFetchPage = (FrameworkRuntime.withErrorPath ["CrawlSession"] . FrameworkRuntime.handleFailure . FrameworkRuntime.atomicHandle "runFetchPage" [("ExtractPage", () <$ getStartPageSummary)] [] . FrameworkRuntime.withScopeDependencies ["CrawlSession"] . FrameworkRuntime.enterHandler "FetchPage") $
  getStartURL >> openCrawlSession >> runWrap @"FetchPage" (FrameworkRuntime.super "fetchPage" FrameworkGenerated.fetchPage)

runKeepPageBody :: FrameworkGenerated.App [String]
runKeepPageBody = (FrameworkRuntime.withErrorPath ["CrawlSession"] . FrameworkRuntime.handleFailure . FrameworkRuntime.withScopeDependencies ["CrawlSession"]) $
  runWrap @"KeepPageBody" (FrameworkRuntime.super "dropBlankBodies" FrameworkGenerated.dropBlankBodies)

getStartPageSummary :: FrameworkGenerated.App FrameworkGenerated.StartPageSummary
getStartPageSummary = (FrameworkRuntime.withErrorPath ["CrawlSession"] . FrameworkRuntime.handleFailure . FrameworkRuntime.withScopeDependencies ["CrawlSession"] . FrameworkRuntime.callContext "ExtractPage"
    (\value bindings -> bindings { FrameworkGenerated.boundExtractPage = Just value })) $
  (FrameworkGenerated.StartPageSummary <$> runWrap @"ExtractPage" (FrameworkRuntime.super "extractSummary" FrameworkGenerated.extractSummary))

readStartPageSummary :: FrameworkGenerated.App FrameworkGenerated.StartPageSummary
readStartPageSummary = (FrameworkRuntime.withErrorPath ["CrawlSession"] . FrameworkRuntime.handleFailure) $
  FrameworkRuntime.readContext "ExtractPage" FrameworkGenerated.ContextBindingError FrameworkGenerated.boundExtractPage

runPrintPage :: FrameworkGenerated.App [String]
runPrintPage = (FrameworkRuntime.withErrorPath [] . FrameworkRuntime.handleFailure . FrameworkRuntime.atomicHandle "runPrintPage" [] [] . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.enterHandler "PrintPage") $
  runWrap @"PrintPage" (FrameworkRuntime.super "printSummary" FrameworkGenerated.printSummary)

runFetchLinkedPage :: FrameworkGenerated.App [String]
runFetchLinkedPage = (FrameworkRuntime.withErrorPath ["CrawlSession"] . FrameworkRuntime.handleFailure . FrameworkRuntime.atomicHandle "runFetchLinkedPage" [("ExtractLinkedPage", () <$ getLinkedPageSummary)] [] . FrameworkRuntime.withScopeDependencies ["CrawlSession"] . FrameworkRuntime.enterHandler "FetchLinkedPage") $
  getLinkedURL >> openCrawlSession >> runWrap @"FetchLinkedPage" (FrameworkRuntime.super "fetchPage" FrameworkGenerated.fetchPage)

runKeepLinkedPageBody :: FrameworkGenerated.App [String]
runKeepLinkedPageBody = (FrameworkRuntime.withErrorPath ["CrawlSession"] . FrameworkRuntime.handleFailure . FrameworkRuntime.withScopeDependencies ["CrawlSession"]) $
  runWrap @"KeepLinkedPageBody" (FrameworkRuntime.super "dropBlankBodies" FrameworkGenerated.dropBlankBodies)

getLinkedPageSummary :: FrameworkGenerated.App FrameworkGenerated.LinkedPageSummary
getLinkedPageSummary = (FrameworkRuntime.withErrorPath ["CrawlSession"] . FrameworkRuntime.handleFailure . FrameworkRuntime.withScopeDependencies ["CrawlSession"] . FrameworkRuntime.callContext "ExtractLinkedPage"
    (\value bindings -> bindings { FrameworkGenerated.boundExtractLinkedPage = Just value })) $
  (FrameworkGenerated.LinkedPageSummary <$> runWrap @"ExtractLinkedPage" (FrameworkRuntime.super "extractSummary" FrameworkGenerated.extractSummary))

readLinkedPageSummary :: FrameworkGenerated.App FrameworkGenerated.LinkedPageSummary
readLinkedPageSummary = (FrameworkRuntime.withErrorPath ["CrawlSession"] . FrameworkRuntime.handleFailure) $
  FrameworkRuntime.readContext "ExtractLinkedPage" FrameworkGenerated.ContextBindingError FrameworkGenerated.boundExtractLinkedPage

runPrintLinkedPage :: FrameworkGenerated.App [String]
runPrintLinkedPage = (FrameworkRuntime.withErrorPath [] . FrameworkRuntime.handleFailure . FrameworkRuntime.atomicHandle "runPrintLinkedPage" [] [] . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.enterHandler "PrintLinkedPage") $
  runWrap @"PrintLinkedPage" (FrameworkRuntime.super "printSummary" FrameworkGenerated.printSummary)

getCrawlSessionInfo :: FrameworkGenerated.App FrameworkGenerated.CrawlSessionInfo
getCrawlSessionInfo = (FrameworkRuntime.withErrorPath [] . FrameworkRuntime.handleFailure . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.callContext "SessionContext"
    (\value bindings -> bindings { FrameworkGenerated.boundSessionContext = Just value })) $
  (FrameworkGenerated.CrawlSessionInfo <$> runWrap @"SessionContext" (FrameworkRuntime.super "sessionInfo" FrameworkGenerated.sessionInfo))

readCrawlSessionInfo :: FrameworkGenerated.App FrameworkGenerated.CrawlSessionInfo
readCrawlSessionInfo = (FrameworkRuntime.withErrorPath [] . FrameworkRuntime.handleFailure) $
  FrameworkRuntime.readContext "SessionContext" FrameworkGenerated.ContextBindingError FrameworkGenerated.boundSessionContext

openCrawlSession :: FrameworkGenerated.App [String]
openCrawlSession = (FrameworkRuntime.withErrorPath ["CrawlSession"] . FrameworkRuntime.handleFailure . FrameworkRuntime.atomicScope "openCrawlSession" [] [] . FrameworkRuntime.openScope "CrawlSession" FrameworkGenerated.ScopeBindingError (Just (() <$ closeCrawlSession)) . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.enterHandler "CrawlSession") $
  getCrawlSessionInfo >> runWrap @"CrawlSession" (FrameworkRuntime.super "openSession" FrameworkGenerated.openSession)

closeCrawlSession :: FrameworkGenerated.App [String]
closeCrawlSession = (FrameworkRuntime.withErrorPath ["CrawlSession"] . FrameworkRuntime.handleFailure . FrameworkRuntime.atomicScope "closeCrawlSession" [] [] . FrameworkRuntime.closeScope "CrawlSession" FrameworkGenerated.ScopeBindingError . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.enterHandler "CrawlSession") $
  runWrap @"CrawlSession" (FrameworkRuntime.superClose "closeSession" FrameworkGenerated.closeSession)

-- SDK 内部：scope 按上游到下游登记，退出时逆序收尾；创建不执行业务方法。
newScopeHandlers :: IO [FrameworkRuntime.ScopeHandler FrameworkGenerated.ContextValues FrameworkGenerated.Errors]
newScopeHandlers = sequence
  [ FrameworkRuntime.newScopeHandler "CrawlSession" [] (Just "SessionContext")
  ]

-- Error 回调登记：按 handles 匹配故障的 handler 与协议分类；关联 scope 由 Input 链推导。
errorHandlers :: [(Maybe String, FrameworkRuntime.ErrorHandler FrameworkGenerated.Errors FrameworkGenerated.App)]
errorHandlers =
  [
  ]
