-- 原生 Haskell 方法体；SDK 添加入口包装，运行编译 Generated 副本。
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE UndecidableInstances #-}

{-# OPTIONS_GHC -Werror=missing-methods #-}

module Crawler.Handlers () where

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
  loadCrawlURLs = pure (CrawlURLs
    (PageURL "https://www.google.com")
    (PageURL "https://www.baidu.com"))


instance FetchPageEffect App where
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

instance FetchLinkedPageEffect App where
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

instance ExtractPageEffect App where
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

instance ExtractLinkedPageEffect App where
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

instance PrintPageEffect App where
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

instance PrintLinkedPageEffect App where
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

-- 会话信息由上游 Context 生产，SDK 在 scope 内保存并供各抓取链读取。
instance SessionContextEffect App where
  createCrawlSession = pure (CrawlSessionInfo "crawler-demo" "algebraic-effect-sys-in-haskell/1.0")

-- 同一 instance 实现开启／关闭；都直接引用 superclass handler，不返回信息。
-- 无开启输入的 scope 在实际重叠使用时共享；最后一条使用闭包退出后自动 close。
instance CrawlSessionEffect App where
  openCrawlSession = do
    CrawlSessionInfo name _ <- createCrawlSession
    liftIO (putStrLn ("[scope] open " ++ name))
  closeCrawlSession = do
    CrawlSessionInfo name _ <- readCrawlSession
    liftIO (putStrLn ("[scope] close " ++ name))
