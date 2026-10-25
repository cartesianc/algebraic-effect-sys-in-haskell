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
import Control.Exception (bracket, displayException, evaluate, throwIO)
import Control.Monad.IO.Class (liftIO)
import Data.List (intercalate)
import System.Exit (ExitCode(..))
import System.IO (hFlush, hGetContents, hSetEncoding, stdout, utf8)
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
    CrawlURLs page@(PageURL url) _ <- loadCrawlURLs
    CrawlSessionInfo _ userAgent <- readCrawlSession
    outcome <- liftIO (fetchURL userAgent page)
    either (\problem -> raise (FetchPageError (url ++ ": " ++ problem))) pure outcome

instance FetchLinkedPageEffect App where
  fetchLinkedPage = do
    openCrawlSession
    CrawlURLs _ page@(PageURL url) <- loadCrawlURLs
    CrawlSessionInfo _ userAgent <- readCrawlSession
    outcome <- liftIO (fetchURL userAgent page)
    either (\problem -> raise (FetchLinkedPageError (url ++ ": " ++ problem))) pure outcome

instance ExtractPageEffect App where
  extractPage = do
    page <- fetchPage
    pure (parsePage page)

instance ExtractLinkedPageEffect App where
  extractLinkedPage = do
    page <- fetchLinkedPage
    pure (parsePage page)

instance PrintPageEffect App where
  printPage = do
    page@(PageSummary url _ _ _) <- extractPage
    outcome <- liftIO (printSummary page)
    either (\problem -> raise (PrintPageError (url ++ ": " ++ problem))) pure outcome

instance PrintLinkedPageEffect App where
  printLinkedPage = do
    page@(PageSummary url _ _ _) <- extractLinkedPage
    outcome <- liftIO (printSummary page)
    either (\problem -> raise (PrintLinkedPageError (url ++ ": " ++ problem))) pure outcome

-- AST 汇合后的收尾节点，直接引用同一 Scoped 的关闭方法。
instance FinishCrawlEffect App where
  finishCrawl = closeCrawlSession

-- 以下函数只实现原子 IO 与解析；上游句柄引用位于上面的 instance 内。
fetchURL :: String -> PageURL -> IO (Either String FetchedPage)
fetchURL userAgent (PageURL url) = do
  -- 参数直接传给 curl 进程，不经过 shell。
  let arguments =
        [ "--disable", "--silent", "--show-error", "--fail", "--location"
        , "--max-redirs", "3", "--connect-timeout", "5", "--max-time", "15"
        , "--proto", "=http,https", "--proto-redir", "=http,https"
        , "--globoff", "--max-filesize", "2097152"
        , "--user-agent", userAgent, "--url", url
        ]
  outcome <- tryIOError (readCurl arguments)
  pure $ case outcome of
    Left problem -> Left (displayException problem)
    Right (ExitFailure _, _, message) -> Left message
    Right (ExitSuccess, html, _) -> Right (FetchedHTML url html)

-- 网页按 UTF-8 解码，避免 Windows 的 CP936 默认编码误读页面。
-- 同时排空 stderr，避免子进程因另一条管道写满而阻塞；诊断保留系统编码。
readCurl :: [String] -> IO (ExitCode, String, String)
readCurl arguments =
  withCreateProcess (proc "curl" arguments)
    { std_in = NoStream, std_out = CreatePipe, std_err = CreatePipe } $
    \_ (Just output) (Just errors) process -> do
      hSetEncoding output utf8
      completed <- newEmptyMVar
      bracket (forkFinally (readFully errors) (putMVar completed)) killThread $ \_ -> do
        body <- readFully output
        diagnostic <- takeMVar completed >>= either throwIO pure
        status <- waitForProcess process
        pure (status, body, diagnostic)
  where
    readFully pipe = do
      contents <- hGetContents pipe
      _ <- evaluate (length contents)
      pure contents

parsePage :: FetchedPage -> PageSummary
parsePage (FetchedHTML url html) =
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
  in PageSummary url title content links

printSummary :: PageSummary -> IO (Either String ())
printSummary (PageSummary url title content links) = do
  let report = unlines
        ([ "URL: " ++ url
         , "Title: " ++ title
         , "Content:"
         , if null content then "  (no paragraphs)" else content
         , "Links:"
         ] ++ (if null links then ["  (none)"] else map ("  " ++) links) ++ [""])
  outcome <- tryIOError (putStr report >> hFlush stdout)
  pure $ case outcome of
    Left problem -> Left (displayException problem)
    Right () -> Right ()

-- 会话信息由上游 Context 生产，SDK 在 scope 内保存并供各抓取链读取。
instance SessionContextEffect App where
  createCrawlSession = pure (CrawlSessionInfo "crawler-demo" "algebraic-effect-sys-in-haskell/1.0")

-- 同一 instance 实现开启／关闭；都直接引用 superclass handler，不返回信息。
-- 本次 AST 内无论多少条链调用 open，SDK 只执行一次方法体；结束节点显式 close。
instance CrawlSessionEffect App where
  openCrawlSession = do
    CrawlSessionInfo name _ <- createCrawlSession
    liftIO (putStrLn ("[scope] open " ++ name))
  closeCrawlSession = do
    CrawlSessionInfo name _ <- readCrawlSession
    liftIO (putStrLn ("[scope] close " ++ name))
