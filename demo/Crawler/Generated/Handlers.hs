-- 自动生成的编译副本；请修改上级 Handlers.hs 后重新生成。
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}
-- 原生 Haskell 方法体；SDK 添加入口包装，运行编译 Generated 副本。
{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE UndecidableInstances #-}

{-# OPTIONS_GHC -Werror=missing-methods #-}

module Crawler.Generated.Handlers (handlerSourceFingerprint, newScopeHandlers, scopeCleanups, errorHandlers, contextInjections) where

import qualified Framework.SDK as FrameworkRuntime
import qualified Framework.Effect.Contract as FrameworkRoot
import qualified Crawler.Generated.Effects as FrameworkGenerated
import Framework.SDK (Effect(..))
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


-- 3. Handler code：instance 直接引用 superclass 类方法；SDK 不从外部补跑 Input。
-- Context 按契约取值：request @T 重新生产，require @T 读取已有值；来源由注册解析。
-- 抓取是原子句柄，只执行 IO 并交出网页正文；解析由挂在它下面的 Context 产值；
-- 打印只完成操作，不交出输出。
instance StartPageInputs m => StartPageEffect m where
  startURL =
    (FrameworkRoot.withErrorPath [] . FrameworkRoot.handler @FrameworkGenerated.Root . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.callContext "StartPage" FrameworkGenerated.ContextBindingError
      [("FetchPage", FrameworkRuntime.RequestValue), ("ExtractPage", FrameworkRuntime.RequireValue)]
      Nothing
      FrameworkGenerated.boundStartPage
      (\value bindings -> bindings { FrameworkGenerated.boundStartPage = Just value })) $
      let
        startURL :: (m) (FrameworkGenerated.StartURL)
        startURL = pure (StartURL (PageURL "https://www.google.com"))
      in startURL

instance LinkedPageInputs m => LinkedPageEffect m where
  linkedURL =
    (FrameworkRoot.withErrorPath [] . FrameworkRoot.handler @FrameworkGenerated.Root . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.callContext "LinkedPage" FrameworkGenerated.ContextBindingError
      [("FetchLinkedPage", FrameworkRuntime.RequestValue), ("ExtractLinkedPage", FrameworkRuntime.RequireValue)]
      Nothing
      FrameworkGenerated.boundLinkedPage
      (\value bindings -> bindings { FrameworkGenerated.boundLinkedPage = Just value })) $
      let
        linkedURL :: (m) (FrameworkGenerated.LinkedURL)
        linkedURL = pure (LinkedURL (PageURL "https://www.baidu.com"))
      in linkedURL


instance FetchPageInputs m => FetchPageEffect m where
  fetchStartPage =
    (FrameworkRoot.withErrorPath ["CrawlSession"] . FrameworkRoot.handler @FrameworkGenerated.Root . FrameworkRuntime.atomicHandle "fetchStartPage" . FrameworkRuntime.withScopeDependencies ["CrawlSession"] . FrameworkRuntime.enterHandler "FetchPage") $
      let
        fetchStartPage :: (m) (Maybe String)
        fetchStartPage = do
          openCrawlSession
          StartURL (PageURL url) <- request @StartURL
          CrawlSessionInfo (SessionInfo _ userAgent) <- require @CrawlSessionInfo
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
            Right (ExitSuccess, html, _) -> pure (Just html)
      in fetchStartPage

instance FetchLinkedPageInputs m => FetchLinkedPageEffect m where
  fetchLinkedPage =
    (FrameworkRoot.withErrorPath ["CrawlSession"] . FrameworkRoot.handler @FrameworkGenerated.Root . FrameworkRuntime.atomicHandle "fetchLinkedPage" . FrameworkRuntime.withScopeDependencies ["CrawlSession"] . FrameworkRuntime.enterHandler "FetchLinkedPage") $
      let
        fetchLinkedPage :: (m) (Maybe String)
        fetchLinkedPage = do
          openCrawlSession
          LinkedURL (PageURL url) <- request @LinkedURL
          CrawlSessionInfo (SessionInfo _ userAgent) <- require @CrawlSessionInfo
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
                hSetEncoding output utf8
                completed <- newEmptyMVar
                bracket (forkFinally (hGetContents' errors) (putMVar completed)) killThread $ \_ -> do
                  body <- hGetContents' output
                  diagnostic <- takeMVar completed >>= either throwIO pure
                  status <- waitForProcess process
                  pure (status, body, diagnostic)
          case outcome of
            Left problem -> raise (FetchLinkedPageError (url ++ ": " ++ displayException problem))
            Right (ExitFailure _, _, message) -> raise (FetchLinkedPageError (url ++ ": " ++ message))
            Right (ExitSuccess, html, _) -> pure (Just html)
      in fetchLinkedPage

-- 挂在抓取句柄下：解析本次抓取交出的正文。剧本执行抓取时由 SDK 注入，不重新抓取；
-- 尚未抓取时被 require，则由这里调用抓取句柄驱动整条链。
instance ExtractPageInputs m => ExtractPageEffect m where
  startPageSummary =
    (FrameworkRoot.withErrorPath ["CrawlSession"] . FrameworkRoot.handler @FrameworkGenerated.Root . FrameworkRuntime.withScopeDependencies ["CrawlSession"] . FrameworkRuntime.callContext "ExtractPage" FrameworkGenerated.ContextBindingError
      [("PrintPage", FrameworkRuntime.RequireValue)]
      Nothing
      FrameworkGenerated.boundExtractPage
      (\value bindings -> bindings { FrameworkGenerated.boundExtractPage = Just value })) $
      let
        startPageSummary :: (m) (FrameworkGenerated.StartPageSummary)
        startPageSummary = do
          fetched <- fetchStartPage
          StartURL (PageURL url) <- require @StartURL
          html <- maybe (raise (ExtractPageError (url ++ ": fetch returned no page body"))) pure fetched
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
          pure (StartPageSummary (PageSummary url title content links))
      in startPageSummary

instance ExtractLinkedPageInputs m => ExtractLinkedPageEffect m where
  linkedPageSummary =
    (FrameworkRoot.withErrorPath ["CrawlSession"] . FrameworkRoot.handler @FrameworkGenerated.Root . FrameworkRuntime.withScopeDependencies ["CrawlSession"] . FrameworkRuntime.callContext "ExtractLinkedPage" FrameworkGenerated.ContextBindingError
      [("PrintLinkedPage", FrameworkRuntime.RequireValue)]
      Nothing
      FrameworkGenerated.boundExtractLinkedPage
      (\value bindings -> bindings { FrameworkGenerated.boundExtractLinkedPage = Just value })) $
      let
        linkedPageSummary :: (m) (FrameworkGenerated.LinkedPageSummary)
        linkedPageSummary = do
          fetched <- fetchLinkedPage
          LinkedURL (PageURL url) <- require @LinkedURL
          html <- maybe (raise (ExtractLinkedPageError (url ++ ": fetch returned no page body"))) pure fetched
          let tags = canonicalizeTags (parseTags html)
              titleTags = takeWhile (not . isTagCloseName "title")
                        (drop 1 (dropWhile (not . isTagOpenName "title") tags))
              title = unwords (words (innerText titleTags))
              paragraphs =
                [ unwords (words (innerText (takeWhile (not . isTagCloseName "p") (drop 1 part))))
                | part <- sections (isTagOpenName "p") tags
                ]
              content = intercalate "\n" (filter (not . null) paragraphs)
              links = [href | tag <- tags, isTagOpenName "a" tag
                            , let href = fromAttrib "href" tag, not (null href)]
          pure (LinkedPageSummary (PageSummary url title content links))
      in linkedPageSummary

-- 打印读取解析阶段产出的资产，不再抓取；尚未解析时 require 会按需驱动抓取链。
instance PrintPageInputs m => PrintPageEffect m where
  printPage =
    (FrameworkRoot.withErrorPath [] . FrameworkRoot.handler @FrameworkGenerated.Root . FrameworkRuntime.atomicHandle "printPage" . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.enterHandler "PrintPage") $
      let
        printPage :: (m) (Maybe String)
        printPage = do
          StartPageSummary (PageSummary url title content links) <- require @StartPageSummary
          let report = unlines
                ([ "URL: " ++ url
                 , "Title: " ++ title
                 , "Content:"
                 , if null content then "  (no paragraphs)" else content
                 , "Links:"
                 ] ++ (if null links then ["  (none)"] else map ("  " ++) links) ++ [""])
          outcome <- liftIO (tryIOError (putStr report >> hFlush stdout))
          either (\problem -> raise (PrintPageError (url ++ ": " ++ displayException problem))) pure outcome
          pure Nothing
      in printPage

instance PrintLinkedPageInputs m => PrintLinkedPageEffect m where
  printLinkedPage =
    (FrameworkRoot.withErrorPath [] . FrameworkRoot.handler @FrameworkGenerated.Root . FrameworkRuntime.atomicHandle "printLinkedPage" . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.enterHandler "PrintLinkedPage") $
      let
        printLinkedPage :: (m) (Maybe String)
        printLinkedPage = do
          LinkedPageSummary (PageSummary url title content links) <- require @LinkedPageSummary
          let report = unlines
                ([ "URL: " ++ url
                 , "Title: " ++ title
                 , "Content:"
                 , if null content then "  (no paragraphs)" else content
                 , "Links:"
                 ] ++ (if null links then ["  (none)"] else map ("  " ++) links) ++ [""])
          outcome <- liftIO (tryIOError (putStr report >> hFlush stdout))
          either (\problem -> raise (PrintLinkedPageError (url ++ ": " ++ displayException problem))) pure outcome
          pure Nothing
      in printLinkedPage

-- 会话信息由上游 Context 生产，SDK 在 scope 内保存并供各抓取链读取。
instance SessionContextInputs m => SessionContextEffect m where
  crawlSessionInfo =
    (FrameworkRoot.withErrorPath [] . FrameworkRoot.handler @FrameworkGenerated.Root . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.callContext "SessionContext" FrameworkGenerated.ContextBindingError
      [("FetchPage", FrameworkRuntime.RequireValue), ("FetchLinkedPage", FrameworkRuntime.RequireValue), ("CrawlSession", FrameworkRuntime.RequestValue)]
      Nothing
      FrameworkGenerated.boundSessionContext
      (\value bindings -> bindings { FrameworkGenerated.boundSessionContext = Just value })) $
      let
        crawlSessionInfo :: (m) (FrameworkGenerated.CrawlSessionInfo)
        crawlSessionInfo = pure (CrawlSessionInfo (SessionInfo "crawler-demo" "algebraic-effect-sys-in-haskell/1.0"))
      in crawlSessionInfo

-- 同一 instance 实现开启／关闭；都直接引用 superclass handler，不交出输出。
-- 无开启输入的 scope 在实际重叠使用时共享；最后一条使用闭包退出后自动 close。
instance CrawlSessionInputs m => CrawlSessionEffect m where
  openCrawlSession =
    (FrameworkRoot.withErrorPath ["CrawlSession"] . FrameworkRoot.handler @FrameworkGenerated.Root . FrameworkRuntime.atomicScope "openCrawlSession" . FrameworkRuntime.openScope "CrawlSession" FrameworkGenerated.ScopeBindingError . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.enterHandler "CrawlSession") $
      let
        openCrawlSession :: (m) (Maybe String)
        openCrawlSession = do
          CrawlSessionInfo (SessionInfo name _) <- request @CrawlSessionInfo
          liftIO (putStrLn ("[scope] open " ++ name))
          pure Nothing
      in openCrawlSession
  closeCrawlSession =
    (FrameworkRoot.withErrorPath ["CrawlSession"] . FrameworkRoot.handler @FrameworkGenerated.Root . FrameworkRuntime.atomicScope "closeCrawlSession" . FrameworkRuntime.closeScope "CrawlSession" FrameworkGenerated.ScopeBindingError . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.enterHandler "CrawlSession") $
      let
        closeCrawlSession :: (m) (Maybe String)
        closeCrawlSession = do
          CrawlSessionInfo (SessionInfo name _) <- require @CrawlSessionInfo
          liftIO (putStrLn ("[scope] close " ++ name))
          pure Nothing
      in closeCrawlSession

-- 记录本编译副本实际使用的手写源码；启动前检查，避免执行过期方法体。
handlerSourceFingerprint :: Maybe String
handlerSourceFingerprint = Just "e88bac73d6b7d51fd7cdd390528fad4e"


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

-- Error 回调登记：按 handles 匹配故障来源与分类；关联 scope 由 Input 链推导。
errorHandlers :: [(Maybe String, FrameworkRoot.ErrorHandler FrameworkGenerated.Errors FrameworkGenerated.App)]
errorHandlers =
  [
  ]

-- 挂在原子句柄下的 Context：句柄的输出交给它解析并发布为资产；没有挂接时输出被丢弃。
contextInjections :: [(String, [(String, FrameworkGenerated.App ())])]
contextInjections =
  [ ("fetchStartPage", [("ExtractPage", () <$ startPageSummary)])
  , ("fetchLinkedPage", [("ExtractLinkedPage", () <$ linkedPageSummary)])
  ]
