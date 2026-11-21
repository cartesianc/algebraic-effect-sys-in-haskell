-- 自动生成的编译副本；请修改上级 Handlers.hs 后重新生成。
{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE ScopedTypeVariables #-}
-- handler 是不带参数的类方法；SDK 按注册装配上游与读取来源，运行编译 Generated 副本。
{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE UndecidableInstances #-}

{-# OPTIONS_GHC -Werror=missing-methods #-}

module Crawler.Generated.Handlers (handlerSourceFingerprint, getStartURL, readStartURL, getLinkedURL, readLinkedURL, runFetchPage, runKeepPageBody, getStartPageSummary, readStartPageSummary, runPrintPage, runFetchLinkedPage, runKeepLinkedPageBody, getLinkedPageSummary, readLinkedPageSummary, runPrintLinkedPage, getCrawlSessionInfo, readCrawlSessionInfo, openCrawlSession, closeCrawlSession, newScopeHandlers, errorHandlers) where

import qualified Framework.Generated as SDK
import qualified Crawler.Generated.Effects as Effects
import qualified Control.Monad.IO.Class as FrameworkIO
import qualified Data.Proxy as FrameworkProxy
import qualified GHC.TypeLits as FrameworkTypes
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
  linkedURL = pure (PageURL "https://example.com")

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
handlerSourceFingerprint = Just "a548361ce474143faa352d3619e7e18f"

-- 以下由 gen 生成。每个 effect 一个类型标签：handler 在标签下执行，
-- 读取、rawinput 与错误按标签在编译期解析到这个 effect 的来源，不改写 handler 方法体。
newtype Wrap (effect :: FrameworkTypes.Symbol) (method :: FrameworkTypes.Symbol) value = Wrap { runWrap :: Effects.App value }
  deriving (Functor, Applicative, Monad, FrameworkIO.MonadIO)

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

instance SDK.Reads PageURL (Wrap "FetchPage" method) where
  require = Wrap (SDK.coerce <$> readStartURL)

instance SDK.Reads SessionInfo (Wrap "FetchPage" method) where
  require = Wrap (SDK.coerce <$> readCrawlSessionInfo)

instance SDK.Reads PageURL (Wrap "ExtractPage" method) where
  require = Wrap (SDK.coerce <$> readStartURL)

instance SDK.Reads PageSummary (Wrap "PrintPage" method) where
  require = Wrap (SDK.coerce <$> readStartPageSummary)

instance SDK.Reads PageURL (Wrap "FetchLinkedPage" method) where
  require = Wrap (SDK.coerce <$> readLinkedURL)

instance SDK.Reads SessionInfo (Wrap "FetchLinkedPage" method) where
  require = Wrap (SDK.coerce <$> readCrawlSessionInfo)

instance SDK.Reads PageURL (Wrap "ExtractLinkedPage" method) where
  require = Wrap (SDK.coerce <$> readLinkedURL)

instance SDK.Reads PageSummary (Wrap "PrintLinkedPage" method) where
  require = Wrap (SDK.coerce <$> readLinkedPageSummary)

instance SDK.Reads SessionInfo (Wrap "CrawlSession" method) where
  require = Wrap (SDK.coerce <$> readCrawlSessionInfo)

instance SDK.Raw (Wrap "KeepPageBody" "dropBlankBodies") where
  rawinput = Wrap runFetchPage

instance SDK.Raw (Wrap "ExtractPage" "extractSummary") where
  rawinput = Wrap runKeepPageBody

instance SDK.Raw (Wrap "KeepLinkedPageBody" "dropBlankBodies") where
  rawinput = Wrap runFetchLinkedPage

instance SDK.Raw (Wrap "ExtractLinkedPage" "extractSummary") where
  rawinput = Wrap runKeepLinkedPageBody

instance SDK.RawOutputs (Wrap effect method)

getStartURL :: Effects.App Effects.StartURL
getStartURL =
  SDK.handleFailure
  . SDK.callContext "StartPage"
      (\value bindings -> bindings { Effects.boundStartPage = Just value }) $
    Effects.StartURL <$> call @"StartPage" @"startURL" Effects.startURL

readStartURL :: Effects.App Effects.StartURL
readStartURL =
  SDK.handleFailure $
    SDK.readContext "StartPage" Effects.ContextBindingError Effects.boundStartPage

getLinkedURL :: Effects.App Effects.LinkedURL
getLinkedURL =
  SDK.handleFailure
  . SDK.callContext "LinkedPage"
      (\value bindings -> bindings { Effects.boundLinkedPage = Just value }) $
    Effects.LinkedURL <$> call @"LinkedPage" @"linkedURL" Effects.linkedURL

readLinkedURL :: Effects.App Effects.LinkedURL
readLinkedURL =
  SDK.handleFailure $
    SDK.readContext "LinkedPage" Effects.ContextBindingError Effects.boundLinkedPage

runFetchPage :: Effects.App [String]
runFetchPage =
  SDK.withErrorPath ["CrawlSession"]
  . SDK.handleFailure
  . SDK.atomicHandle "runFetchPage" [("ExtractPage", () <$ getStartPageSummary)] []
  . SDK.withScopeDependencies ["CrawlSession"]
  . SDK.enterHandler "FetchPage" $
    getStartURL >> openCrawlSession >> call @"FetchPage" @"fetchPage" Effects.fetchPage

runKeepPageBody :: Effects.App [String]
runKeepPageBody =
  SDK.withErrorPath ["CrawlSession"]
  . SDK.handleFailure
  . SDK.withScopeDependencies ["CrawlSession"] $
    call @"KeepPageBody" @"dropBlankBodies" Effects.dropBlankBodies

getStartPageSummary :: Effects.App Effects.StartPageSummary
getStartPageSummary =
  SDK.withErrorPath ["CrawlSession"]
  . SDK.handleFailure
  . SDK.withScopeDependencies ["CrawlSession"]
  . SDK.callContext "ExtractPage"
      (\value bindings -> bindings { Effects.boundExtractPage = Just value }) $
    Effects.StartPageSummary <$> call @"ExtractPage" @"extractSummary" Effects.extractSummary

readStartPageSummary :: Effects.App Effects.StartPageSummary
readStartPageSummary =
  SDK.withErrorPath ["CrawlSession"]
  . SDK.handleFailure $
    SDK.readContext "ExtractPage" Effects.ContextBindingError Effects.boundExtractPage

runPrintPage :: Effects.App [String]
runPrintPage =
  SDK.handleFailure
  . SDK.atomicHandle "runPrintPage" [] []
  . SDK.enterHandler "PrintPage" $
    call @"PrintPage" @"printSummary" Effects.printSummary

runFetchLinkedPage :: Effects.App [String]
runFetchLinkedPage =
  SDK.withErrorPath ["CrawlSession"]
  . SDK.handleFailure
  . SDK.atomicHandle "runFetchLinkedPage" [("ExtractLinkedPage", () <$ getLinkedPageSummary)] []
  . SDK.withScopeDependencies ["CrawlSession"]
  . SDK.enterHandler "FetchLinkedPage" $
    getLinkedURL >> openCrawlSession >> call @"FetchLinkedPage" @"fetchPage" Effects.fetchPage

runKeepLinkedPageBody :: Effects.App [String]
runKeepLinkedPageBody =
  SDK.withErrorPath ["CrawlSession"]
  . SDK.handleFailure
  . SDK.withScopeDependencies ["CrawlSession"] $
    call @"KeepLinkedPageBody" @"dropBlankBodies" Effects.dropBlankBodies

getLinkedPageSummary :: Effects.App Effects.LinkedPageSummary
getLinkedPageSummary =
  SDK.withErrorPath ["CrawlSession"]
  . SDK.handleFailure
  . SDK.withScopeDependencies ["CrawlSession"]
  . SDK.callContext "ExtractLinkedPage"
      (\value bindings -> bindings { Effects.boundExtractLinkedPage = Just value }) $
    Effects.LinkedPageSummary <$> call @"ExtractLinkedPage" @"extractSummary" Effects.extractSummary

readLinkedPageSummary :: Effects.App Effects.LinkedPageSummary
readLinkedPageSummary =
  SDK.withErrorPath ["CrawlSession"]
  . SDK.handleFailure $
    SDK.readContext "ExtractLinkedPage" Effects.ContextBindingError Effects.boundExtractLinkedPage

runPrintLinkedPage :: Effects.App [String]
runPrintLinkedPage =
  SDK.handleFailure
  . SDK.atomicHandle "runPrintLinkedPage" [] []
  . SDK.enterHandler "PrintLinkedPage" $
    call @"PrintLinkedPage" @"printSummary" Effects.printSummary

getCrawlSessionInfo :: Effects.App Effects.CrawlSessionInfo
getCrawlSessionInfo =
  SDK.handleFailure
  . SDK.callContext "SessionContext"
      (\value bindings -> bindings { Effects.boundSessionContext = Just value }) $
    Effects.CrawlSessionInfo <$> call @"SessionContext" @"sessionInfo" Effects.sessionInfo

readCrawlSessionInfo :: Effects.App Effects.CrawlSessionInfo
readCrawlSessionInfo =
  SDK.handleFailure $
    SDK.readContext "SessionContext" Effects.ContextBindingError Effects.boundSessionContext

openCrawlSession :: Effects.App [String]
openCrawlSession =
  SDK.withErrorPath ["CrawlSession"]
  . SDK.handleFailure
  . SDK.atomicScope "openCrawlSession" [] []
  . SDK.openScope "CrawlSession" Effects.ScopeBindingError (Just (() <$ closeCrawlSession))
  . SDK.enterHandler "CrawlSession" $
    getCrawlSessionInfo >> call @"CrawlSession" @"openSession" Effects.openSession

closeCrawlSession :: Effects.App [String]
closeCrawlSession =
  SDK.withErrorPath ["CrawlSession"]
  . SDK.handleFailure
  . SDK.atomicScope "closeCrawlSession" [] []
  . SDK.closeScope "CrawlSession" Effects.ScopeBindingError
  . SDK.enterHandler "CrawlSession" $
    callClose @"CrawlSession" @"closeSession" Effects.closeSession

-- SDK 内部：scope 按上游到下游登记，退出时逆序收尾；创建不执行业务方法。
newScopeHandlers :: IO [SDK.ScopeHandler Effects.ContextValues Effects.Errors]
newScopeHandlers = sequence
  [ SDK.newScopeHandler "CrawlSession" [] (Just "SessionContext")
  ]

-- Error 回调登记：按 handles 匹配故障的 handler 与协议分类；关联 scope 由 Input 链推导。
errorHandlers :: [(Maybe String, SDK.ErrorHandler Effects.Errors Effects.App)]
errorHandlers = []
