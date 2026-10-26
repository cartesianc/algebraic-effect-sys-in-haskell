-- 首次生成只编译注册与 AST/Target；handler 源码只解析，不加载或执行业务。
module Framework.Generate (main) where

import Control.Exception (evaluate)
import Data.Char (isAlphaNum, isUpper)
import Framework.Codegen.Handlers (prepareHandlers, HandlerShape(..))
import Framework.Codegen.Plan (renderGraphPlan)
import qualified Framework.Effect.Graph as Graph
import System.Directory (createDirectoryIfMissing, doesFileExist)
import System.Environment (getArgs)
import System.Exit (ExitCode(..), die, exitWith)
import System.FilePath ((</>), pathSeparator)
import System.Process (readProcessWithExitCode)
import System.IO (IOMode(ReadMode, WriteMode), hGetContents, hPutStr, hSetEncoding, stderr, utf8, withFile)
import System.IO.Error (tryIOError)
import Text.Read (readMaybe)

main :: IO ()
main = do
  arguments <- getArgs
  case arguments of
    [mode, namespace]
      | mode `elem` ["workflow", "target"], validNamespace namespace -> do
          let modulePath = map (\character -> if character == '.' then pathSeparator else character) namespace
              directory = "demo" </> modulePath
              entryModule = if mode == "workflow" then "AST" else "Target"
              entry = if mode == "workflow"
                then "Framework.Codegen.Workflow (Framework.Workflow.AST.targets " ++ namespace ++ ".AST.ast)"
                else "Framework.Codegen.SingleTarget " ++ namespace ++ ".Target.target"
              expression = "print (Framework.Codegen.lowerProgram " ++ show namespace
                ++ " " ++ namespace ++ ".Effects.effects (" ++ entry ++ "))"
          (result, output, diagnostics) <- readProcessWithExitCode "ghci"
            [ "-ignore-dot-ghci", "-v0", "-XHaskell2010", "-idemo", "-isdk"
            , "sdk/Framework/Codegen.hs", directory </> "Effects.hs"
            , directory </> entryModule ++ ".hs", "-e", expression
            ] ""
          hPutStr stderr diagnostics
          case result of
            ExitSuccess -> case readMaybe output of
              Nothing -> die "Cannot read the SDK handler wrapping plan"
              Just (Left problem) -> die problem
              Just (Right (contracts, program, wrappers, scopeHandlers, plan)) -> do
                (handlers, shapes) <- prepareHandlers namespace wrappers scopeHandlers
                let generated = directory </> "Generated"
                    cachePath = generated </> ".scope-cache"
                    normalized = [(method, normalizeShape shape) | ((_, method), shape) <- shapes]
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
                createDirectoryIfMissing True generated
                changed <- sequence
                  [ writeIfChanged (generated </> "Effects.hs") contracts
                  , writeIfChanged (generated </> "Program.hs") (program ++ structure)
                  , writeIfChanged (generated </> "Handlers.hs") handlers
                  ]
                _ <- writeIfChanged cachePath (show (cacheKey, structure))
                putStrLn ("Generated " ++ generated ++ " (" ++ show (length (filter id changed))
                  ++ " files updated; structure " ++ (if reused then "reused" else "rebuilt") ++ ")")
            _ -> exitWith result
    _ -> die "Usage: effect-codegen (workflow|target) Namespace"

-- 缓存只省略纯构图；声明仍加载，手写 Handlers 仍解析一次。
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
