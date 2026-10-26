-- 自动生成的编译副本；请修改上级 Handlers.hs 后重新生成。
{-# LANGUAGE TypeApplications #-}
-- 原生 Haskell 方法体；SDK 添加入口包装，运行编译 Generated 副本。
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE UndecidableInstances #-}

{-# OPTIONS_GHC -Werror=missing-methods #-}

module Crawler.Generated.Handlers (newScopeHandlers, scopeCleanups, errorHandlers) where

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
-- Context 经 request/require 接入；使用原生 <- 取得业务值，不由 boot 全局初始化。
-- URL、抓取与解析均由 Context 产值；打印只完成操作，不返回业务回执。
-- SDK 包装编译副本：request 成功保存，require 只读；本例仍声明重新抓取。
instance CrawlerContextEffect App where
  loadCrawlURLs =
    (FrameworkRoot.withErrorPath ["CrawlSession"] . FrameworkRoot.handler @FrameworkGenerated.Root . FrameworkRuntime.withScopeDependencies ["CrawlSession"] . FrameworkRuntime.callContext "CrawlerContext" FrameworkGenerated.ContextBindingError
      [("FetchPage", FrameworkRuntime.RequestValue), ("FetchLinkedPage", FrameworkRuntime.RequestValue)]
      Nothing
      FrameworkGenerated.boundCrawlerContext
      (\value bindings -> bindings { FrameworkGenerated.boundCrawlerContext = Just value })) $
      let
        loadCrawlURLs = pure (CrawlURLs
          (PageURL "https://www.google.com")
          (PageURL "https://www.baidu.com"))
      in loadCrawlURLs


instance FetchPageEffect App where
  fetchPage =
    (FrameworkRoot.withErrorPath ["CrawlSession"] . FrameworkRoot.handler @FrameworkGenerated.Root . FrameworkRuntime.withScopeDependencies ["CrawlSession"] . FrameworkRuntime.callContext "FetchPage" FrameworkGenerated.ContextBindingError
      [("ExtractPage", FrameworkRuntime.RequestValue)]
      Nothing
      FrameworkGenerated.boundFetchPage
      (\value bindings -> bindings { FrameworkGenerated.boundFetchPage = Just value })) $
      let
        fetchPage = do
          openCrawlSession
          CrawlURLs (PageURL url) _ <- loadCrawlURLs
          CrawlSessionInfo _ userAgent <- readCrawlSession
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
            Right (ExitSuccess, html, _) -> pure (FetchedHTML url html)
      in fetchPage

instance FetchLinkedPageEffect App where
  fetchLinkedPage =
    (FrameworkRoot.withErrorPath ["CrawlSession"] . FrameworkRoot.handler @FrameworkGenerated.Root . FrameworkRuntime.withScopeDependencies ["CrawlSession"] . FrameworkRuntime.callContext "FetchLinkedPage" FrameworkGenerated.ContextBindingError
      [("ExtractLinkedPage", FrameworkRuntime.RequestValue)]
      Nothing
      FrameworkGenerated.boundFetchLinkedPage
      (\value bindings -> bindings { FrameworkGenerated.boundFetchLinkedPage = Just value })) $
      let
        fetchLinkedPage = do
          openCrawlSession
          CrawlURLs _ (PageURL url) <- loadCrawlURLs
          CrawlSessionInfo _ userAgent <- readCrawlSession
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
            Right (ExitSuccess, html, _) -> pure (FetchedHTML url html)
      in fetchLinkedPage

instance ExtractPageEffect App where
  extractPage =
    (FrameworkRoot.withErrorPath ["CrawlSession"] . FrameworkRoot.handler @FrameworkGenerated.Root . FrameworkRuntime.withScopeDependencies ["CrawlSession"] . FrameworkRuntime.callContext "ExtractPage" FrameworkGenerated.ContextBindingError
      [("PrintPage", FrameworkRuntime.RequestValue)]
      Nothing
      FrameworkGenerated.boundExtractPage
      (\value bindings -> bindings { FrameworkGenerated.boundExtractPage = Just value })) $
      let
        extractPage = do
          FetchedHTML url html <- fetchPage
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
      in extractPage

instance ExtractLinkedPageEffect App where
  extractLinkedPage =
    (FrameworkRoot.withErrorPath ["CrawlSession"] . FrameworkRoot.handler @FrameworkGenerated.Root . FrameworkRuntime.withScopeDependencies ["CrawlSession"] . FrameworkRuntime.callContext "ExtractLinkedPage" FrameworkGenerated.ContextBindingError
      [("PrintLinkedPage", FrameworkRuntime.RequestValue)]
      Nothing
      FrameworkGenerated.boundExtractLinkedPage
      (\value bindings -> bindings { FrameworkGenerated.boundExtractLinkedPage = Just value })) $
      let
        extractLinkedPage = do
          FetchedHTML url html <- fetchLinkedPage
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
          pure (PageSummary url title content links)
      in extractLinkedPage

instance PrintPageEffect App where
  printPage =
    (FrameworkRoot.withErrorPath ["CrawlSession"] . FrameworkRoot.handler @FrameworkGenerated.Root . FrameworkRuntime.withScopeDependencies ["CrawlSession"] . FrameworkRuntime.enterHandler "PrintPage") $
      let
        printPage = do
          PageSummary url title content links <- extractPage
          let report = unlines
                ([ "URL: " ++ url
                 , "Title: " ++ title
                 , "Content:"
                 , if null content then "  (no paragraphs)" else content
                 , "Links:"
                 ] ++ (if null links then ["  (none)"] else map ("  " ++) links) ++ [""])
          outcome <- liftIO (tryIOError (putStr report >> hFlush stdout))
          either (\problem -> raise (PrintPageError (url ++ ": " ++ displayException problem))) pure outcome
      in printPage

instance PrintLinkedPageEffect App where
  printLinkedPage =
    (FrameworkRoot.withErrorPath ["CrawlSession"] . FrameworkRoot.handler @FrameworkGenerated.Root . FrameworkRuntime.withScopeDependencies ["CrawlSession"] . FrameworkRuntime.enterHandler "PrintLinkedPage") $
      let
        printLinkedPage = do
          PageSummary url title content links <- extractLinkedPage
          let report = unlines
                ([ "URL: " ++ url
                 , "Title: " ++ title
                 , "Content:"
                 , if null content then "  (no paragraphs)" else content
                 , "Links:"
                 ] ++ (if null links then ["  (none)"] else map ("  " ++) links) ++ [""])
          outcome <- liftIO (tryIOError (putStr report >> hFlush stdout))
          either (\problem -> raise (PrintLinkedPageError (url ++ ": " ++ displayException problem))) pure outcome
      in printLinkedPage

-- 会话信息由上游 Context 生产，SDK 在 scope 内保存并供各抓取链读取。
instance SessionContextEffect App where
  createCrawlSession =
    (FrameworkRoot.withErrorPath [] . FrameworkRoot.handler @FrameworkGenerated.Root . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.callContext "SessionContext" FrameworkGenerated.ContextBindingError
      [("FetchPage", FrameworkRuntime.RequireValue), ("FetchLinkedPage", FrameworkRuntime.RequireValue), ("CrawlSession", FrameworkRuntime.RequestValue)]
      Nothing
      FrameworkGenerated.boundSessionContext
      (\value bindings -> bindings { FrameworkGenerated.boundSessionContext = Just value })) $
      let
        createCrawlSession = pure (CrawlSessionInfo "crawler-demo" "algebraic-effect-sys-in-haskell/1.0")
      in createCrawlSession

-- 同一 instance 实现开启／关闭；都直接引用 superclass handler，不返回信息。
-- 无开启输入的 scope 在实际重叠使用时共享；最后一条使用闭包退出后自动 close。
instance CrawlSessionEffect App where
  openCrawlSession =
    (FrameworkRoot.withErrorPath ["CrawlSession"] . FrameworkRoot.handler @FrameworkGenerated.Root . FrameworkRuntime.openScope "CrawlSession" FrameworkGenerated.ScopeBindingError . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.enterHandler "CrawlSession") $
      let
        openCrawlSession = do
          CrawlSessionInfo name _ <- createCrawlSession
          liftIO (putStrLn ("[scope] open " ++ name))
      in openCrawlSession
  closeCrawlSession =
    (FrameworkRoot.withErrorPath ["CrawlSession"] . FrameworkRoot.handler @FrameworkGenerated.Root . FrameworkRuntime.closeScope "CrawlSession" FrameworkGenerated.ScopeBindingError . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.enterHandler "CrawlSession") $
      let
        closeCrawlSession = do
          CrawlSessionInfo name _ <- readCrawlSession
          liftIO (putStrLn ("[scope] close " ++ name))
      in closeCrawlSession


-- SDK 内部：scope 按上游到下游登记，退出时逆序收尾；创建不执行业务方法。
newScopeHandlers :: IO [FrameworkRuntime.ScopeHandler FrameworkGenerated.ContextValues FrameworkGenerated.Errors]
newScopeHandlers = sequence
  [ FrameworkRuntime.newScopeHandler "CrawlSession" [] (Just "SessionContext")
  ]

-- SDK 自动收尾入口；安装时不关闭资源。
scopeCleanups :: [(String, FrameworkGenerated.App ())]
scopeCleanups =
  [ ("CrawlSession", closeCrawlSession)
  ]

-- Error 回调登记；记录 scope 对应的 detect/resolve，不在此执行检测。
errorHandlers :: [(String, FrameworkRoot.ErrorHandler FrameworkGenerated.App)]
errorHandlers =
  [
  ]
