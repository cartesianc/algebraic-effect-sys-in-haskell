-- handler 是不带参数的类方法；SDK 按注册装配上游与读取来源，运行编译 Generated 副本。
{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE UndecidableInstances #-}

{-# OPTIONS_GHC -Werror=missing-methods #-}

module Crawler.Handlers () where

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
      Right (ExitSuccess, html, _) -> pure (Just html)

-- 挂在抓取句柄下，两个解析共用：raw 是本次抓取交出的正文。剧本执行抓取时由 SDK 注入，不重新抓取；
-- 尚未抓取时被 require，则 raw 驱动抓取句柄执行整条链。
instance ExtractSummaryLayer m => ExtractSummaryHandler m where
  extractSummary = do
    fetched <- raw
    PageURL url <- require @PageURL
    html <- maybe (raise (ExtractSummaryError (url ++ ": fetch returned no page body"))) pure fetched
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
    pure Nothing

-- 会话信息由 Context 生产，SDK 在 scope 内保存并供各抓取链读取。
instance SessionInfoLayer m => SessionInfoHandler m where
  sessionInfo = pure (SessionInfo "crawler-demo" "algebraic-effect-sys-in-haskell/1.0")

-- 无开启输入的 scope 在实际重叠使用时共享；最后一条使用闭包退出后自动 close。
instance OpenSessionLayer m => OpenSessionHandler m where
  openSession = do
    SessionInfo name _ <- require @SessionInfo
    liftIO (putStrLn ("[scope] open " ++ name))
    pure Nothing

instance CloseSessionLayer m => CloseSessionHandler m where
  closeSession = do
    SessionInfo name _ <- require @SessionInfo
    liftIO (putStrLn ("[scope] close " ++ name))
    pure Nothing
