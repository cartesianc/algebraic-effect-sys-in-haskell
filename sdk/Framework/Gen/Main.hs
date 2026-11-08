-- effect-codegen 的命令行入口：准备进程环境，校验命名空间，然后交给编译流水线 Framework.Gen。
module Framework.Gen.Main (main) where

import Data.Char (isAlphaNum, isUpper)
import Framework.Gen (compileWorkflow)
import System.Environment (getArgs, getExecutablePath, lookupEnv)
import System.Exit (die, exitWith)
import System.IO (hSetEncoding, stderr, utf8)
import System.Process (rawSystem)

main :: IO ()
main = do
  -- 进程内 GHC 的诊断含非 ASCII 符号；固定为 UTF-8，避免按区域编码输出时诊断本身失败。
  hSetEncoding stderr utf8
  arguments <- getArgs
  -- GHC API 也需要 Cabal 的依赖可见性；复用项目 package environment，
  -- 不硬编码业务库白名单或本机 package-db 路径。
  packageEnvironment <- lookupEnv "GHC_ENVIRONMENT"
  case packageEnvironment of
    Nothing -> do
      executable <- getExecutablePath
      rawSystem "cabal" (["exec", "--", executable] ++ arguments) >>= exitWith
    Just _ -> pure ()
  case arguments of
    ["workflow", namespace] | validNamespace namespace -> compileWorkflow namespace
    _ -> die "Usage: effect-codegen workflow Namespace"

-- 命名空间会进入模块引用；只接受完整的 Haskell 模块名。
validNamespace :: String -> Bool
validNamespace selected = all validPart (parts selected)
  where
    parts value = case break (== '.') value of
      (part, []) -> [part]
      (part, _ : rest) -> part : parts rest
    validPart [] = False
    validPart (first : rest) = isUpper first
      && all (\character -> isAlphaNum character || character `elem` "_'") rest
