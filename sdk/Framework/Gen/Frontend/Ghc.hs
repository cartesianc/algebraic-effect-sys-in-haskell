-- 名称解析与最终类检共享源码布局、包环境和内存 target，不执行 handler。
module Framework.Gen.Frontend.Ghc (withSourceTargets, sourceDirectory, modulePath, libraryDirectory) where

import Control.Monad.IO.Class (liftIO)
import Data.IORef (IORef, newIORef, readIORef, writeIORef)
import Data.Time.Clock (getCurrentTime)
import GHC
import GHC.Data.StringBuffer (stringToStringBuffer)
import GHC.Driver.Backend (noBackend)
import GHC.Driver.Session (DynFlags(..), GeneralFlag(Opt_WriteInterface), GhcLink(..), gopt_set)
import System.Environment (lookupEnv)
import System.FilePath (isPathSeparator, normalise)
import System.IO.Unsafe (unsafePerformIO)
import System.Process (readProcess)

-- GHC 库目录在一次生成中不变：只询问 ghc 一次，各会话与语法读取共用。
libraryDirectory :: IO FilePath
libraryDirectory = do
  known <- readIORef libraryCache
  case known of
    Just library -> pure library
    Nothing -> do
      library <- takeWhile (`notElem` "\r\n") <$> readProcess "ghc" ["--print-libdir"] ""
      writeIORef libraryCache (Just library)
      pure library

libraryCache :: IORef (Maybe FilePath)
libraryCache = unsafePerformIO (newIORef Nothing)
{-# NOINLINE libraryCache #-}

withSourceTargets :: ((String -> String -> Target) -> Ghc value) -> IO value
withSourceTargets action = do
  library <- libraryDirectory
  sourceDir <- sourceDirectory
  now <- getCurrentTime
  runGhc (Just library) $ do
    initial <- getSessionDynFlags
    logger <- getLogger
    packages <- liftIO (interpretPackageEnv logger initial)
    -- 只做类型检查（不生成代码），但把接口写进缓存目录：SDK 与未改动的业务模块下次按源码哈希直接复用，
    -- 不再每个会话都从源码重新检查。源码或内存 target 的内容变了，GHC 照常重新检查该模块及其下游。
    _ <- setSessionDynFlags (gopt_set packages Opt_WriteInterface)
      { backend = noBackend, ghcLink = NoLink, importPaths = [sourceDir, "sdk"], verbosity = 0
      , hiDir = Just interfaceCache, stubDir = Just interfaceCache, dumpDir = Just interfaceCache }
    let memoryTarget name source = Target
          { targetId = TargetFile (modulePath sourceDir name ++ ".hs") Nothing
          , targetAllowObjCode = False
          , targetUnitId = homeUnitId_ initial
          , targetContents = Just (stringToStringBuffer source, now)
          }
    action memoryTarget

-- 接口缓存放在构建目录下，可随时删除；不同检出各有自己的缓存。
interfaceCache :: FilePath
interfaceCache = "dist-newstyle/effect-codegen-interfaces"

-- 正斜杠也用于 GHC 的内存文件名和资产目录。
sourceDirectory :: IO FilePath
sourceDirectory = maybe "demo" (map slash . normalise) <$> lookupEnv "EFFECT_SOURCE_DIR"
  where slash c = if isPathSeparator c then '/' else c

modulePath :: FilePath -> String -> FilePath
modulePath sourceDir name = (if sourceDir == "." then "" else sourceDir ++ "/") ++ map (\c -> if c == '.' then '/' else c) name
