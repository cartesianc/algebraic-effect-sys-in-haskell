-- 原生 Haskell 取值；SDK 生成方法入口包装，运行编译 Generated 副本。
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE UndecidableInstances #-}
{-# OPTIONS_GHC -Werror=missing-methods #-}

module ScopeInstancesDemo.Handlers () where

import Framework.SDK (Effect(..))
import ScopeInstancesDemo.Generated.Effects
import ScopeInstancesDemo.Types
import Control.Exception (bracketOnError, displayException)
import Control.Monad (unless)
import Control.Monad.IO.Class (liftIO)
import System.Directory (createDirectoryIfMissing)
import System.FilePath ((</>))
import System.IO (IOMode(ReadWriteMode), hClose, hFlush, hIsClosed, hPutStrLn, openFile, readFile')
import System.IO.Error (tryIOError)

instance PrepareFilesEffect App where
  prepareFiles = liftIO $ do
    createDirectoryIfMissing True outputDirectory
    mapM_ (`writeFile` "") [firstFile, secondFile, journal]
    writeFile selection firstFile

-- 参数确实由 instance 中的 IO 动态取得。观察日志不承担任何 scope 状态管理。
instance FileLocationEffect App where
  getFileName = do
    path <- liftIO (readFile' selection)
    liftIO (appendFile journal ("argument " ++ path ++ "\n"))
    pure (FileName path)

instance FileResourceEffect App where
  acquireFile = do
    FileName path <- getFileName
    outcome <- liftIO $ tryIOError $
      bracketOnError (openFile path ReadWriteMode) hClose $ \file -> do
        appendFile journal ("acquire " ++ path ++ "\n")
        pure (OpenedFile path file)
    either (raise . FileResourceError . displayException) pure outcome

-- 与原写法相同：没有参数、状态标记、key 或 SDK 消费方法。
instance FileSessionEffect App where
  openFileSession = do
    OpenedFile path _ <- acquireFile
    liftIO (appendFile journal ("open " ++ path ++ "\n"))
  closeFileSession = do
    OpenedFile path file <- readOpenedFile
    liftIO $ do
      hClose file
      appendFile journal ("close " ++ path ++ "\n")

instance CheckIndependentEffect App where
  checkIndependent = do
    liftIO (writeFile selection firstFile)
    openFileSession
    OpenedFile pathA fileA <- readOpenedFile
    openFileSession
    OpenedFile pathA' fileA' <- readOpenedFile
    unless (pathA == firstFile && pathA' == firstFile && fileA == fileA') $
      raise (CheckIndependentError "Equal arguments did not reuse the same Handle")
    liftIO (putStrLn "[check] equal opening values reuse the same file Handle")

    liftIO (writeFile selection secondFile)
    openFileSession
    OpenedFile pathB fileB <- readOpenedFile
    unless (pathB == secondFile && fileA /= fileB) $
      raise (CheckIndependentError "Different opening values did not select independent files")
    liftIO $ do
      hPutStrLn fileA "first"
      hPutStrLn fileB "second"
      hFlush fileA
      hFlush fileB
    closeFileSession
    closeFileSession
    (closedA, closedB) <- liftIO ((,) <$> hIsClosed fileA <*> hIsClosed fileB)
    unless (not closedA && closedB) $
      raise (CheckIndependentError "Closing the second instance affected the first")
    liftIO (putStrLn "[check] require selects the current instance; repeated close closes only file 2")
    -- 第一份保持开启；下一个 Node 是另一条 Input 链。

instance CheckReopenEffect App where
  checkReopen = do
    liftIO (writeFile selection firstFile)
    openFileSession
    OpenedFile pathA fileA <- readOpenedFile
    events <- liftIO (lines <$> readFile' journal)
    unless (pathA == firstFile && count ("acquire " ++ firstFile) events == 1) $
      raise (CheckReopenError "The other Input chain reopened the still-active first file")
    closeFileSession
    closedA <- liftIO (hIsClosed fileA)
    unless closedA (raise (CheckReopenError "First file was not closed"))
    liftIO (putStrLn "[check] another Node reuses file 1 across Input chains")

    liftIO (writeFile selection secondFile)
    openFileSession
    OpenedFile pathB fileB <- readOpenedFile
    closedB <- liftIO (hIsClosed fileB)
    unless (pathB == secondFile && not closedB) $
      raise (CheckReopenError "Opening a closed instance did not obtain a live file")
    liftIO $ hPutStrLn fileB "reopened" >> hFlush fileB
    closeFileSession
    finalClosed <- liftIO (hIsClosed fileB)
    finalEvents <- liftIO (lines <$> readFile' journal)
    let acquisitions = count ("acquire " ++ firstFile) finalEvents == 1
                    && count ("acquire " ++ secondFile) finalEvents == 2
        closes = count ("close " ++ firstFile) finalEvents == 1
              && count ("close " ++ secondFile) finalEvents == 2
        opens = count ("open " ++ firstFile) finalEvents == 1
             && count ("open " ++ secondFile) finalEvents == 2
        arguments = count ("argument " ++ firstFile) finalEvents == 3
                 && count ("argument " ++ secondFile) finalEvents == 2
    unless (finalClosed && acquisitions && closes && opens && arguments) $
      raise (CheckReopenError ("Unexpected lifecycle or extra Context evaluation: " ++ show finalEvents))
    liftIO $ do
      putStrLn "[check] closed file 2 reopened successfully; both files now closed"
      putStrLn "[check] actual acquisitions/closures: file 1 = 1/1; file 2 = 2/2"
      putStrLn "[check] five open calls, five argument requests; no extra Context evaluation"

outputDirectory, firstFile, secondFile, selection, journal :: FilePath
outputDirectory = "demo" </> "ScopeInstancesDemo" </> "output"
firstFile = outputDirectory </> "one.txt"
secondFile = outputDirectory </> "two.txt"
selection = outputDirectory </> "selected.txt"
journal = outputDirectory </> "events.txt"

count :: Eq value => value -> [value] -> Int
count expected = length . filter (== expected)
