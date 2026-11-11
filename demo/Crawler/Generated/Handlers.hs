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

module Crawler.Generated.Handlers (handlerSourceFingerprint, getStartURL, readStartURL, getLinkedURL, readLinkedURL, runFetchPage, getStartPageSummary, readStartPageSummary, runPrintPage, runFetchLinkedPage, getLinkedPageSummary, readLinkedPageSummary, runPrintLinkedPage, getCrawlSessionInfo, readCrawlSessionInfo, openCrawlSession, closeCrawlSession, newScopeHandlers, scopeCleanups, errorHandlers, contextInjections) where

import qualified Framework.Generated as FrameworkRuntime
import qualified Crawler.Generated.Effects as FrameworkGenerated
import qualified Control.Monad.IO.Class as FrameworkIO
import qualified Data.Proxy as FrameworkProxy
import qualified GHC.TypeLits as FrameworkTypes
import Crawler.Types
import Framework.SDK (Raises(..), Raw(..), Reads(..))
import Crawler.Generated.Effects
import Crawler.Types
import Control.Concurrent (forkFinally, killThread, newEmptyMVar, putMVar, takeMVar)
import Control.Exception (bracket, displayException, throwIO)
import Control.Monad.IO.Class (liftIO)
import Data.List (intercalate)
import System.Exit (ExitCode(..))
import System.IO (hFlush, hGetContents', hSetEncoding, stdout, utf8)
import System.IO.Error (tryIOError)
import System.Process (CreateProcess(..), StdStream(..), proc, waitForProcess, withCreateProcess)
import Text.HTML.TagSoup
  ( canonicalizeTags, fromAttrib, innerText, isTagCloseName, isTagOpenName, parseTags, sections )


-- 3. Handler code：handler 只按表示类型 require；读的是哪份资产由绑定它的 effect 的 demands 决定。
-- 抓取是原子句柄，只执行 IO 并交出网页正文；解析由挂在它下面的 Context 产值；
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
      Right (ExitSuccess, html, _) -> pure [html]

-- 挂在抓取句柄下，两个解析共用：raw 是本次抓取交出的 list（一页正文）。剧本执行抓取时由 SDK 注入，不重新抓取；
-- 被 requests 驱动时，raw 执行抓取句柄，启动整条链。
instance ExtractSummaryLayer m => ExtractSummaryHandler m where
  extractSummary = do
    fetched <- raw
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
    pure []

-- 会话信息由 Context 生产，SDK 在 scope 内保存并供各抓取链读取。
instance SessionInfoLayer m => SessionInfoHandler m where
  sessionInfo = pure (SessionInfo "crawler-demo" "algebraic-effect-sys-in-haskell/1.0")

-- 无开启输入的 scope 在实际重叠使用时共享；最后一条使用闭包退出后自动 close。
instance OpenSessionLayer m => OpenSessionHandler m where
  openSession = do
    SessionInfo name _ <- require @SessionInfo
    liftIO (putStrLn ("[scope] open " ++ name))
    pure []

instance CloseSessionLayer m => CloseSessionHandler m where
  closeSession = do
    SessionInfo name _ <- require @SessionInfo
    liftIO (putStrLn ("[scope] close " ++ name))
    pure []

-- 记录本编译副本实际使用的手写源码；启动前检查，避免执行过期方法体。
handlerSourceFingerprint :: Maybe String
handlerSourceFingerprint = Just "54f798bb4e6e713b06a40810f5d67ebd"

-- 以下由 gen 生成。每个 effect 一个类型标签：handler 在标签下执行，
-- 读取、raw 与错误按标签在编译期解析到这个 effect 的来源，不改写 handler 方法体。
newtype At (effect :: FrameworkTypes.Symbol) value = At { runAt :: FrameworkGenerated.App value }
  deriving (Functor, Applicative, Monad, FrameworkIO.MonadIO)

instance FrameworkTypes.KnownSymbol effect => FrameworkRuntime.Raises FrameworkGenerated.StartURLError (At effect) where
  raise (FrameworkGenerated.StartURLError description) = At (FrameworkRuntime.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) FrameworkGenerated.StartURLFailure description)

instance FrameworkTypes.KnownSymbol effect => FrameworkRuntime.Raises FrameworkGenerated.LinkedURLError (At effect) where
  raise (FrameworkGenerated.LinkedURLError description) = At (FrameworkRuntime.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) FrameworkGenerated.LinkedURLFailure description)

instance FrameworkTypes.KnownSymbol effect => FrameworkRuntime.Raises FrameworkGenerated.FetchPageError (At effect) where
  raise (FrameworkGenerated.FetchPageError description) = At (FrameworkRuntime.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) FrameworkGenerated.FetchPageFailure description)

instance FrameworkTypes.KnownSymbol effect => FrameworkRuntime.Raises FrameworkGenerated.ExtractSummaryError (At effect) where
  raise (FrameworkGenerated.ExtractSummaryError description) = At (FrameworkRuntime.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) FrameworkGenerated.ExtractSummaryFailure description)

instance FrameworkTypes.KnownSymbol effect => FrameworkRuntime.Raises FrameworkGenerated.PrintSummaryError (At effect) where
  raise (FrameworkGenerated.PrintSummaryError description) = At (FrameworkRuntime.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) FrameworkGenerated.PrintSummaryFailure description)

instance FrameworkTypes.KnownSymbol effect => FrameworkRuntime.Raises FrameworkGenerated.SessionInfoError (At effect) where
  raise (FrameworkGenerated.SessionInfoError description) = At (FrameworkRuntime.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) FrameworkGenerated.SessionInfoFailure description)

instance FrameworkTypes.KnownSymbol effect => FrameworkRuntime.Raises FrameworkGenerated.OpenSessionError (At effect) where
  raise (FrameworkGenerated.OpenSessionError description) = At (FrameworkRuntime.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) FrameworkGenerated.OpenSessionFailure description)

instance FrameworkTypes.KnownSymbol effect => FrameworkRuntime.Raises FrameworkGenerated.CloseSessionError (At effect) where
  raise (FrameworkGenerated.CloseSessionError description) = At (FrameworkRuntime.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) FrameworkGenerated.CloseSessionFailure description)

instance FrameworkRuntime.Reads (PageURL) (At "FetchPage") where
  require = At ((\(FrameworkGenerated.StartURL value) -> value) <$> readStartURL)

instance FrameworkRuntime.Reads (SessionInfo) (At "FetchPage") where
  require = At ((\(FrameworkGenerated.CrawlSessionInfo value) -> value) <$> readCrawlSessionInfo)

instance FrameworkRuntime.Reads (PageURL) (At "ExtractPage") where
  require = At ((\(FrameworkGenerated.StartURL value) -> value) <$> readStartURL)

instance FrameworkRuntime.Reads (PageSummary) (At "PrintPage") where
  require = At ((\(FrameworkGenerated.StartPageSummary value) -> value) <$> readStartPageSummary)

instance FrameworkRuntime.Reads (PageURL) (At "FetchLinkedPage") where
  require = At ((\(FrameworkGenerated.LinkedURL value) -> value) <$> readLinkedURL)

instance FrameworkRuntime.Reads (SessionInfo) (At "FetchLinkedPage") where
  require = At ((\(FrameworkGenerated.CrawlSessionInfo value) -> value) <$> readCrawlSessionInfo)

instance FrameworkRuntime.Reads (PageURL) (At "ExtractLinkedPage") where
  require = At ((\(FrameworkGenerated.LinkedURL value) -> value) <$> readLinkedURL)

instance FrameworkRuntime.Reads (PageSummary) (At "PrintLinkedPage") where
  require = At ((\(FrameworkGenerated.LinkedPageSummary value) -> value) <$> readLinkedPageSummary)

instance FrameworkRuntime.Reads (SessionInfo) (At "CrawlSession") where
  require = At ((\(FrameworkGenerated.CrawlSessionInfo value) -> value) <$> readCrawlSessionInfo)

instance FrameworkRuntime.Raw (At "ExtractPage") where
  raw = At (runFetchPage)

instance FrameworkRuntime.Raw (At "ExtractLinkedPage") where
  raw = At (runFetchLinkedPage)

getStartURL :: FrameworkGenerated.App FrameworkGenerated.StartURL
getStartURL = (FrameworkRuntime.withErrorPath [] . FrameworkRuntime.handleFailure . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.callContext "StartPage"
    Nothing
    (\value bindings -> bindings { FrameworkGenerated.boundStartPage = Just value })) $
  (FrameworkGenerated.StartURL <$> runAt @"StartPage" FrameworkGenerated.startURL)

readStartURL :: FrameworkGenerated.App FrameworkGenerated.StartURL
readStartURL = (FrameworkRuntime.withErrorPath [] . FrameworkRuntime.handleFailure) $
  FrameworkRuntime.readContext "StartPage" FrameworkGenerated.ContextBindingError Nothing FrameworkGenerated.boundStartPage

getLinkedURL :: FrameworkGenerated.App FrameworkGenerated.LinkedURL
getLinkedURL = (FrameworkRuntime.withErrorPath [] . FrameworkRuntime.handleFailure . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.callContext "LinkedPage"
    Nothing
    (\value bindings -> bindings { FrameworkGenerated.boundLinkedPage = Just value })) $
  (FrameworkGenerated.LinkedURL <$> runAt @"LinkedPage" FrameworkGenerated.linkedURL)

readLinkedURL :: FrameworkGenerated.App FrameworkGenerated.LinkedURL
readLinkedURL = (FrameworkRuntime.withErrorPath [] . FrameworkRuntime.handleFailure) $
  FrameworkRuntime.readContext "LinkedPage" FrameworkGenerated.ContextBindingError Nothing FrameworkGenerated.boundLinkedPage

runFetchPage :: FrameworkGenerated.App [String]
runFetchPage = (FrameworkRuntime.withErrorPath ["CrawlSession"] . FrameworkRuntime.handleFailure . FrameworkRuntime.atomicHandle "runFetchPage" . FrameworkRuntime.withScopeDependencies ["CrawlSession"] . FrameworkRuntime.enterHandler "FetchPage") $
  getStartURL >> openCrawlSession >> runAt @"FetchPage" FrameworkGenerated.fetchPage

getStartPageSummary :: FrameworkGenerated.App FrameworkGenerated.StartPageSummary
getStartPageSummary = (FrameworkRuntime.withErrorPath ["CrawlSession"] . FrameworkRuntime.handleFailure . FrameworkRuntime.withScopeDependencies ["CrawlSession"] . FrameworkRuntime.callContext "ExtractPage"
    Nothing
    (\value bindings -> bindings { FrameworkGenerated.boundExtractPage = Just value })) $
  (FrameworkGenerated.StartPageSummary <$> runAt @"ExtractPage" FrameworkGenerated.extractSummary)

readStartPageSummary :: FrameworkGenerated.App FrameworkGenerated.StartPageSummary
readStartPageSummary = (FrameworkRuntime.withErrorPath ["CrawlSession"] . FrameworkRuntime.handleFailure) $
  FrameworkRuntime.readContext "ExtractPage" FrameworkGenerated.ContextBindingError Nothing FrameworkGenerated.boundExtractPage

runPrintPage :: FrameworkGenerated.App [String]
runPrintPage = (FrameworkRuntime.withErrorPath [] . FrameworkRuntime.handleFailure . FrameworkRuntime.atomicHandle "runPrintPage" . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.enterHandler "PrintPage") $
  runAt @"PrintPage" FrameworkGenerated.printSummary

runFetchLinkedPage :: FrameworkGenerated.App [String]
runFetchLinkedPage = (FrameworkRuntime.withErrorPath ["CrawlSession"] . FrameworkRuntime.handleFailure . FrameworkRuntime.atomicHandle "runFetchLinkedPage" . FrameworkRuntime.withScopeDependencies ["CrawlSession"] . FrameworkRuntime.enterHandler "FetchLinkedPage") $
  getLinkedURL >> openCrawlSession >> runAt @"FetchLinkedPage" FrameworkGenerated.fetchPage

getLinkedPageSummary :: FrameworkGenerated.App FrameworkGenerated.LinkedPageSummary
getLinkedPageSummary = (FrameworkRuntime.withErrorPath ["CrawlSession"] . FrameworkRuntime.handleFailure . FrameworkRuntime.withScopeDependencies ["CrawlSession"] . FrameworkRuntime.callContext "ExtractLinkedPage"
    Nothing
    (\value bindings -> bindings { FrameworkGenerated.boundExtractLinkedPage = Just value })) $
  (FrameworkGenerated.LinkedPageSummary <$> runAt @"ExtractLinkedPage" FrameworkGenerated.extractSummary)

readLinkedPageSummary :: FrameworkGenerated.App FrameworkGenerated.LinkedPageSummary
readLinkedPageSummary = (FrameworkRuntime.withErrorPath ["CrawlSession"] . FrameworkRuntime.handleFailure) $
  FrameworkRuntime.readContext "ExtractLinkedPage" FrameworkGenerated.ContextBindingError Nothing FrameworkGenerated.boundExtractLinkedPage

runPrintLinkedPage :: FrameworkGenerated.App [String]
runPrintLinkedPage = (FrameworkRuntime.withErrorPath [] . FrameworkRuntime.handleFailure . FrameworkRuntime.atomicHandle "runPrintLinkedPage" . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.enterHandler "PrintLinkedPage") $
  runAt @"PrintLinkedPage" FrameworkGenerated.printSummary

getCrawlSessionInfo :: FrameworkGenerated.App FrameworkGenerated.CrawlSessionInfo
getCrawlSessionInfo = (FrameworkRuntime.withErrorPath [] . FrameworkRuntime.handleFailure . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.callContext "SessionContext"
    Nothing
    (\value bindings -> bindings { FrameworkGenerated.boundSessionContext = Just value })) $
  (FrameworkGenerated.CrawlSessionInfo <$> runAt @"SessionContext" FrameworkGenerated.sessionInfo)

readCrawlSessionInfo :: FrameworkGenerated.App FrameworkGenerated.CrawlSessionInfo
readCrawlSessionInfo = (FrameworkRuntime.withErrorPath [] . FrameworkRuntime.handleFailure) $
  FrameworkRuntime.readContext "SessionContext" FrameworkGenerated.ContextBindingError Nothing FrameworkGenerated.boundSessionContext

openCrawlSession :: FrameworkGenerated.App [String]
openCrawlSession = (FrameworkRuntime.withErrorPath ["CrawlSession"] . FrameworkRuntime.handleFailure . FrameworkRuntime.atomicScope "openCrawlSession" . FrameworkRuntime.openScope "CrawlSession" FrameworkGenerated.ScopeBindingError . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.enterHandler "CrawlSession") $
  getCrawlSessionInfo >> runAt @"CrawlSession" FrameworkGenerated.openSession

closeCrawlSession :: FrameworkGenerated.App [String]
closeCrawlSession = (FrameworkRuntime.withErrorPath ["CrawlSession"] . FrameworkRuntime.handleFailure . FrameworkRuntime.atomicScope "closeCrawlSession" . FrameworkRuntime.closeScope "CrawlSession" FrameworkGenerated.ScopeBindingError . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.enterHandler "CrawlSession") $
  runAt @"CrawlSession" FrameworkGenerated.closeSession

-- SDK 内部：scope 按上游到下游登记，退出时逆序收尾；创建不执行业务方法。
newScopeHandlers :: IO [FrameworkRuntime.ScopeHandler FrameworkGenerated.ContextValues FrameworkGenerated.Errors]
newScopeHandlers = sequence
  [ FrameworkRuntime.newScopeHandler "CrawlSession" [] (Just "SessionContext")
  ]

-- SDK 自动收尾入口；安装时不关闭资源。
scopeCleanups :: [(String, FrameworkGenerated.App ())]
scopeCleanups =
  [ ("CrawlSession", () <$ closeCrawlSession)
  ]

-- Error 回调登记：按 handles 匹配故障的 handler 与协议分类；关联 scope 由 Input 链推导。
errorHandlers :: [(Maybe String, FrameworkRuntime.ErrorHandler FrameworkGenerated.Errors FrameworkGenerated.App)]
errorHandlers =
  [
  ]

-- 挂在原子句柄下的 Context：句柄的输出交给它的 parser 解析并发布为资产；没有挂接时输出被丢弃。
contextInjections :: [(String, [(String, FrameworkGenerated.App ())])]
contextInjections =
  [ ("runFetchPage", [("ExtractPage", () <$ getStartPageSummary)])
  , ("runFetchLinkedPage", [("ExtractLinkedPage", () <$ getLinkedPageSummary)])
  ]
