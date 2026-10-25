-- 自动生成的编译副本；请修改上级 Handlers.hs 后重新生成。
{-# LANGUAGE TypeApplications #-}
-- 原生 Haskell 取值；SDK 生成方法入口包装，运行编译 Generated 副本。
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE UndecidableInstances #-}

{-# OPTIONS_GHC -Werror=missing-methods #-}

module ScopeReuseDemo.Generated.Handlers (newScopeHandlers, errorHandlers) where

import qualified Framework.SDK as FrameworkRuntime
import qualified Framework.Effect.Contract as FrameworkRoot
import qualified ScopeReuseDemo.Generated.Effects as FrameworkGenerated
import Framework.SDK (Effect(..))
import ScopeReuseDemo.Generated.Effects
import ScopeReuseDemo.Types
import Control.Exception (bracketOnError, displayException)
import Control.Monad (unless)
import Control.Monad.Except (catchError, throwError)
import Control.Monad.IO.Class (liftIO)
import Data.IORef (atomicModifyIORef', newIORef, readIORef)
import Data.List (sort)
import System.Directory (createDirectoryIfMissing)
import System.FilePath ((</>), takeDirectory)
import System.IO
  ( Handle, IOMode(ReadMode, ReadWriteMode), SeekMode(AbsoluteSeek)
  , hClose, hFlush, hGetChar, hIsClosed, hIsEOF, hPrint, hPutStr, hSeek
  , hSetEncoding, openFile, stderr, utf8, withFile )
import System.IO.Error (tryIOError)

instance FileLocationsEffect App where
  getFilePaths =
    (FrameworkRoot.withErrorPath [] . FrameworkRoot.handler @FrameworkGenerated.Root . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.callContext "FileLocations" FrameworkGenerated.ContextBindingError
      [("PrepareProbe", FrameworkRuntime.RequestValue), ("FileResource", FrameworkRuntime.RequestValue)]
      (Just (FrameworkRuntime.ScopeInput "FileLocations"))
      FrameworkGenerated.boundFileLocations
      (\value bindings -> bindings { FrameworkGenerated.boundFileLocations = Just value })) $
      let
        getFilePaths = pure (FilePaths
          ("demo" </> "ScopeReuseDemo" </> "output" </> "shared.txt")
          ("demo" </> "ScopeReuseDemo" </> "output" </> "events.txt"))
      in getFilePaths

instance PrepareProbeEffect App where
  prepareProbe =
    (FrameworkRoot.withErrorPath [] . FrameworkRoot.handler @FrameworkGenerated.Root . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.enterHandler "PrepareProbe") $
      let
        prepareProbe = do
          FilePaths path journal <- getFilePaths
          outcome <- liftIO $ tryIOError $ do
            createDirectoryIfMissing True (takeDirectory path)
            -- 仅重置本 demo 的两份产物，在三个分支启动前完成。
            writeFile path ""
            writeFile journal ""
          either (raise . PrepareProbeError . displayException) pure outcome
      in prepareProbe

instance FileResourceEffect App where
  acquireFile =
    (FrameworkRoot.withErrorPath [] . FrameworkRoot.handler @FrameworkGenerated.Root . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.callContext "FileResource" FrameworkGenerated.ContextBindingError
      [("SharedFileScope", FrameworkRuntime.RequestValue), ("WriteFirst", FrameworkRuntime.RequireValue), ("WriteSecond", FrameworkRuntime.RequireValue), ("WriteThird", FrameworkRuntime.RequireValue), ("VerifyReuse", FrameworkRuntime.RequireValue)]
      Nothing
      FrameworkGenerated.boundFileResource
      (\value bindings -> bindings { FrameworkGenerated.boundFileResource = Just value })) $
      let
        acquireFile = do
          paths@(FilePaths path journal) <- getFilePaths
          outcome <- liftIO $ tryIOError $
            bracketOnError (openFile path ReadWriteMode) hClose $ \file -> do
              hSetEncoding file utf8
              -- 记录真实资源获取；日志独立于 Context，重新产值不会清零它。
              appendFile journal "file-open\n"
              observed <- newIORef []
              pure (OpenedFile paths file observed)
          either (raise . FileResourceError . displayException) pure outcome
      in acquireFile

instance SharedFileScopeEffect App where
  openSharedFile =
    (FrameworkRoot.withErrorPath ["SharedFileScope"] . FrameworkRoot.handler @FrameworkGenerated.Root . FrameworkRuntime.openScope "SharedFileScope" FrameworkGenerated.ScopeBindingError . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.enterHandler "SharedFileScope") $
      let
        openSharedFile = do
          OpenedFile (FilePaths _ journal) _ _ <- acquireFile
          outcome <- liftIO (tryIOError (appendFile journal "open-body\n"))
          either (raise . SharedFileScopeError . displayException) pure outcome
      in openSharedFile

  closeSharedFile =
    (FrameworkRoot.withErrorPath ["SharedFileScope"] . FrameworkRoot.handler @FrameworkGenerated.Root . FrameworkRuntime.closeScope "SharedFileScope" FrameworkGenerated.ScopeBindingError . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.enterHandler "SharedFileScope") $
      let
        closeSharedFile = do
          OpenedFile (FilePaths _ journal) file _ <- readOpenedFile
          outcome <- liftIO $ tryIOError $ do
            appendFile journal "close-body\n"
            hClose file
            appendFile journal "file-close\n"
          either (raise . SharedFileScopeError . displayException) pure outcome
      in closeSharedFile

-- 三个 instance 都直接引用 superclass 的 open 和 Context.require。
-- 不在业务中加打开标志或互斥锁，重复开启的保护完全来自 SDK。
instance WriteFirstEffect App where
  writeFirst =
    (FrameworkRoot.withErrorPath ["SharedFileScope"] . FrameworkRoot.handler @FrameworkGenerated.Root . FrameworkRuntime.withScopeDependencies ["SharedFileScope"] . FrameworkRuntime.enterHandler "WriteFirst") $
      let
        writeFirst = do
          openSharedFile
          resource <- readOpenedFile
          outcome <- liftIO (tryIOError (writeAndRecord "first" resource))
          either (raise . WriteFirstError . displayException) pure outcome
      in writeFirst

instance WriteSecondEffect App where
  writeSecond =
    (FrameworkRoot.withErrorPath ["SharedFileScope"] . FrameworkRoot.handler @FrameworkGenerated.Root . FrameworkRuntime.withScopeDependencies ["SharedFileScope"] . FrameworkRuntime.enterHandler "WriteSecond") $
      let
        writeSecond = do
          openSharedFile
          resource <- readOpenedFile
          outcome <- liftIO (tryIOError (writeAndRecord "second" resource))
          either (raise . WriteSecondError . displayException) pure outcome
      in writeSecond

instance WriteThirdEffect App where
  writeThird =
    (FrameworkRoot.withErrorPath ["SharedFileScope"] . FrameworkRoot.handler @FrameworkGenerated.Root . FrameworkRuntime.withScopeDependencies ["SharedFileScope"] . FrameworkRuntime.enterHandler "WriteThird") $
      let
        writeThird = do
          openSharedFile
          resource <- readOpenedFile
          outcome <- liftIO (tryIOError (writeAndRecord "third" resource))
          either (raise . WriteThirdError . displayException) pure outcome
      in writeThird

instance VerifyReuseEffect App where
  verifyReuse =
    (FrameworkRoot.withErrorPath ["SharedFileScope"] . FrameworkRoot.handler @FrameworkGenerated.Root . FrameworkRuntime.withScopeDependencies ["SharedFileScope"] . FrameworkRuntime.enterHandler "VerifyReuse") $
      let
        verifyReuse = do
          OpenedFile (FilePaths _ journal) file observed <- readOpenedFile
          -- 此 Node 在 parallel 汇合后运行；读取过程中没有并发写入。
          -- 断言失败也显式收尾，并保留原始故障。
          (do
            outcome <- liftIO $ tryIOError $ do
              closed <- hIsClosed file
              events <- withFile journal ReadMode readFully
              writes <- readIORef observed
              hFlush file
              hSeek file AbsoluteSeek 0
              content <- readFully file
              pure (closed, lines events, writes, lines content)
            (closed, events, writes, content) <- either (raise . VerifyReuseError . displayException) pure outcome
            let openBodies = length (filter (== "open-body") events)
                fileOpens = length (filter (== "file-open") events)
                labels = ["first", "second", "third"]
                sameHandle = length writes == 3 && all ((== file) . snd) writes
            unless (not closed && "close-body" `notElem` events) $
              raise (VerifyReuseError "File closed before all three writes completed")
            unless (openBodies == 1 && fileOpens == 1) $
              raise (VerifyReuseError ("Repeated open: handler=" ++ show openBodies ++ ", file=" ++ show fileOpens))
            unless (sameHandle && sort (map fst writes) == labels) $
              raise (VerifyReuseError "The three writers did not observe the same Handle")
            unless (sort content == labels) $
              raise (VerifyReuseError ("Unexpected file contents: " ++ show content))
            liftIO $ do
              putStrLn "[check] three parallel writers completed without close"
              putStrLn "[check] open handler body: 1; actual resource open: 1"
              putStrLn "[check] same Handle: 3/3; each line written exactly once"
            ) `catchError` \failure -> do
              closeSharedFile `catchError` \closingFailure -> liftIO (hPrint stderr closingFailure)
              throwError failure
          closeSharedFile
          closeSharedFile
          outcome <- liftIO $ tryIOError $ do
            closed <- hIsClosed file
            events <- withFile journal ReadMode readFully
            pure (closed, lines events)
          (closed, events) <- either (raise . VerifyReuseError . displayException) pure outcome
          unless closed (raise (VerifyReuseError "File remained open after explicit close"))
          unless (length (filter (== "close-body") events) == 1
                  && length (filter (== "file-close") events) == 1) $
            raise (VerifyReuseError "Repeated close executed the body or hClose again")
          liftIO (putStrLn "[check] sequential close calls: 2; close body: 1; hClose: 1")
      in verifyReuse

-- 只实现单次文件写入和观察记录；上游 DI 引用仍在各 instance 内。
-- 不做 seek，允许三个调用共享当前位置；完成顺序不作为断言。
writeAndRecord :: String -> OpenedFile -> IO ()
writeAndRecord label (OpenedFile _ file observed) = do
  hPutStr file (label ++ "\n")
  hFlush file
  atomicModifyIORef' observed (\writes -> (writes ++ [(label, file)], ()))

readFully :: Handle -> IO String
readFully file = go []
  where
    go characters = do
      finished <- hIsEOF file
      if finished
        then pure (reverse characters)
        else hGetChar file >>= \character -> go (character : characters)


-- SDK 内部：每份 Scoped 句柄拥有自己的状态和 MVar；创建不执行业务方法。
newScopeHandlers :: IO [FrameworkRuntime.ScopeHandler FrameworkGenerated.ContextValues FrameworkGenerated.Errors]
newScopeHandlers = sequence
  [ FrameworkRuntime.newScopeHandler "SharedFileScope" ["FileLocations"] (Just "FileResource")
  ]

-- Root 的异常入口，按 scope 的拓扑顺序从上向下检测。
errorHandlers :: [(String, FrameworkRoot.ErrorHandler FrameworkGenerated.App)]
errorHandlers =
  [
  ]
