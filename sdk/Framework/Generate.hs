-- 先构造契约和结构，再用 GHC 源码分析检查资产；不执行 handler 业务。
module Framework.Generate (main) where

import Control.Exception (evaluate)
import Data.Char (isAlphaNum, isUpper)
import Framework.Codegen.Handlers (prepareHandlers, loadSumTypes, HandlerShape(..))
import Framework.Codegen.Assets (checkAssets)
import Framework.Codegen.Plan (checkDriven, renderGraphPlan)
import qualified Framework.Effect.Graph as Graph
import System.Directory (createDirectoryIfMissing, doesFileExist)
import System.Environment (getArgs, getExecutablePath, lookupEnv)
import System.Exit (ExitCode(..), die, exitWith)
import System.FilePath ((</>), pathSeparator)
import System.Process (rawSystem, readProcessWithExitCode)
import System.IO (IOMode(ReadMode, WriteMode), hGetContents, hPutStr, hSetEncoding, stderr, utf8, withFile)
import System.IO.Error (tryIOError)
import Text.Read (readMaybe)

main :: IO ()
main = do
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
    -- 程序只经 AST 启动，入口是 AST 中各 node 选中的末端。
    ["workflow", namespace]
      | validNamespace namespace -> do
          let modulePath = map (\character -> if character == '.' then pathSeparator else character) namespace
              directory = "demo" </> modulePath
              ast = namespace ++ ".AST.ast"
          -- 和类型的构造器信息由解析 Types.hs 得到，以字面量传给声明加载进程。
          sumTypes <- loadSumTypes namespace
          let expression = "print (Framework.Codegen.lowerProgram " ++ show namespace
                ++ " " ++ namespace ++ ".Effects.effects (Framework.Workflow.AST.targets " ++ ast
                ++ ") (Framework.Workflow.AST.alternativeGroups " ++ ast ++ ") " ++ show sumTypes ++ ")"
          (result, output, diagnostics) <- readProcessWithExitCode "ghci"
            [ "-ignore-dot-ghci", "-v0", "-XHaskell2010", "-idemo", "-isdk"
            , "sdk/Framework/Codegen.hs", directory </> "Effects.hs"
            , directory </> "AST.hs", "-e", expression
            ] ""
          hPutStr stderr diagnostics
          case result of
            ExitSuccess -> case readMaybe output of
              Nothing -> die "Cannot read the SDK handler wrapping plan"
              Just (Left problem) -> die problem
              Just (Right (contracts, program, wrappers, scopeHandlers, plan, assetRoots, routes, owners)) -> do
                (handlers, shapes, nativeSource) <- prepareHandlers namespace wrappers scopeHandlers routes
                let generated = directory </> "Generated"
                    cachePath = generated </> ".scope-cache"
                    normalized = [(method, normalizeShape shape) | ((_, method), shape) <- shapes]
                -- 驱动检查每次执行，不受 scope 缓存命中影响；首次生成尚无 Handlers.hs、没有方法结构，
                -- 先生成契约供编写 handler，有实现后再检查。
                case nativeSource of
                  Just _ -> either die pure (checkDriven plan normalized)
                  Nothing -> pure ()
                dependencies <- mapM readUtf8 structureSources
                let cacheKey = show (plan, normalized, dependencies)
                cached <- tryIOError (readExisting cachePath)
                let previous = either (const Nothing) (>>= readMaybe) cached
                (structure, reused) <- case previous of
                  Just (key, source) | key == cacheKey -> pure (source, True)
                  _ -> case renderGraphPlan plan normalized of
                    Left problem -> die problem
                    Right source -> pure (source, False)
                -- 完成声明、原生语法和纯结构分析后才更新生成区；未变文件保留时间戳。
                _ <- evaluate (length structure)
                assets <- checkAssets namespace
                  [("Effects", contracts), ("Program", program ++ structure), ("Handlers", handlers)]
                  assetRoots [(owner, method) | (owner, method, _, _) <- wrappers] owners nativeSource
                createDirectoryIfMissing True generated
                changed <- sequence
                  [ writeIfChanged (generated </> "Effects.hs") contracts
                  , writeIfChanged (generated </> "Program.hs") (program ++ structure)
                  , writeIfChanged (generated </> "Handlers.hs") handlers
                  , writeIfChanged (generated </> "Assets.hs") assets
                  ]
                _ <- writeIfChanged cachePath (show (cacheKey, structure))
                putStrLn ("Generated " ++ generated ++ " (" ++ show (length (filter id changed))
                  ++ " files updated; structure " ++ (if reused then "reused" else "rebuilt") ++ ")")
            _ -> exitWith result
    _ -> die "Usage: effect-codegen workflow Namespace"

-- 缓存只省略纯构图；声明与 Handlers 快照仍读取，资产检查每次执行。
-- 连同算法及渲染器源码精确比较，避免 SDK 改动后复用旧结构。
structureSources :: [FilePath]
structureSources =
  [ "sdk/Framework/Codegen/Plan.hs"
  , "sdk/Framework/Effect/Graph.hs"
  , "sdk/Framework/Recursion.hs"
  , "sdk/Framework/Workflow/AST.hs"
  , "sdk/Framework/Workflow/Structure.hs"
  ]

normalizeShape :: HandlerShape -> Graph.MethodShape String
normalizeShape Empty = Graph.Empty
normalizeShape (Call method) = Graph.Call method
normalizeShape (Sequence children) = Graph.Sequence (map normalizeShape children)
normalizeShape (Choice children) = Graph.Choice (map normalizeShape children)
normalizeShape (Recover body recovery) = Graph.Recover (normalizeShape body) (normalizeShape recovery)

readUtf8 :: FilePath -> IO String
readUtf8 path = withFile path ReadMode $ \handle -> do
  hSetEncoding handle utf8
  contents <- hGetContents handle
  _ <- evaluate (length contents)
  pure contents

readExisting :: FilePath -> IO (Maybe String)
readExisting path = do
  exists <- doesFileExist path
  if exists then Just <$> readUtf8 path else pure Nothing

writeIfChanged :: FilePath -> String -> IO Bool
writeIfChanged path source = do
  previous <- readExisting path
  if previous == Just source then pure False else do
    withFile path WriteMode $ \handle -> do
      hSetEncoding handle utf8
      hPutStr handle source
    pure True

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
