-- 名称解析与最终类检共享源码布局、包环境和内存 target，不执行 handler。
module Framework.Gen.Frontend.Ghc (withSourceTargets, sourceDirectory, modulePath) where

import Control.Monad.IO.Class (liftIO)
import Data.Time.Clock (getCurrentTime)
import GHC
import GHC.Data.StringBuffer (stringToStringBuffer)
import GHC.Driver.Backend (noBackend)
import GHC.Driver.Session (DynFlags(..), GhcLink(..))
import System.Environment (lookupEnv)
import System.FilePath (isPathSeparator, normalise)
import System.Process (readProcess)

withSourceTargets :: ((String -> String -> Target) -> Ghc value) -> IO value
withSourceTargets action = do
  library <- takeWhile (`notElem` "\r\n") <$> readProcess "ghc" ["--print-libdir"] ""
  sourceDir <- sourceDirectory
  now <- getCurrentTime
  runGhc (Just library) $ do
    initial <- getSessionDynFlags
    logger <- getLogger
    packages <- liftIO (interpretPackageEnv logger initial)
    _ <- setSessionDynFlags packages
      { backend = noBackend, ghcLink = NoLink, importPaths = [sourceDir, "sdk"], verbosity = 0 }
    let memoryTarget name source = Target
          { targetId = TargetFile (modulePath sourceDir name ++ ".hs") Nothing
          , targetAllowObjCode = False
          , targetUnitId = homeUnitId_ initial
          , targetContents = Just (stringToStringBuffer source, now)
          }
    action memoryTarget

-- 正斜杠也用于 GHC 的内存文件名和资产目录。
sourceDirectory :: IO FilePath
sourceDirectory = maybe "demo" (map slash . normalise) <$> lookupEnv "EFFECT_SOURCE_DIR"
  where slash c = if isPathSeparator c then '/' else c

modulePath :: FilePath -> String -> FilePath
modulePath sourceDir name = (if sourceDir == "." then "" else sourceDir ++ "/") ++ map (\c -> if c == '.' then '/' else c) name
