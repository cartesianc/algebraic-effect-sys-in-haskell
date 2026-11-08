-- 先构造契约和结构，再用 GHC 源码分析检查资产；不执行 handler 业务。
module Framework.Generate (main) where

import Control.Exception (evaluate)
import Data.Char (isAlphaNum, isUpper)
import Data.Maybe (isJust)
import Framework.Codegen (GeneratedCode(..), composeMethods)
import Framework.Codegen.Handlers (prepareHandlers, loadSumTypes)
import Framework.Codegen.Assets (checkAssets)
import Framework.Codegen.Plan (renderPrototype)
import Framework.Prototype (buildPreparedPrototype, checkDriven, validatePrototype)
import System.Directory (createDirectoryIfMissing, doesFileExist)
import System.Environment (getArgs, getExecutablePath, lookupEnv)
import System.Exit (ExitCode(..), die, exitWith)
import System.FilePath ((</>), pathSeparator)
import System.Process
  (CreateProcess(..), StdStream(..), proc, rawSystem, waitForProcess, withCreateProcess)
import System.IO (IOMode(ReadMode, WriteMode), hGetContents, hPutStr, hSetEncoding, stderr, utf8, withFile)
import System.IO.Error (tryIOError)
import Text.Read (readMaybe)

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
    -- 程序只经 AST 启动，入口是 AST 中各 node 选中的末端。
    ["workflow", namespace]
      | validNamespace namespace -> do
          let modulePath = map (\character -> if character == '.' then pathSeparator else character) namespace
              directory = "demo" </> modulePath
              ast = namespace ++ ".AST.ast"
          -- 和类型的构造器信息由解析 Types.hs 得到，以字面量传给声明加载进程。
          sumTypes <- loadSumTypes namespace
          let expression = "print (Framework.Codegen.lowerProgram " ++ show namespace
                ++ " " ++ namespace ++ ".Effects.effects (Framework.Workflow.AST.toWorkflowF " ++ ast
                ++ ") " ++ show sumTypes ++ ")"
          -- GHC 的诊断直接写到本进程的 stderr，不经管道读回：GHC 按自己的区域编码输出，
          -- 读回时的解码可能与之不一致（中文 Windows 上 chcp 65001 后即如此），会把诊断本身变成解码异常。
          -- 只读回打印的结果，它经 show 转义，只含 ASCII。
          let loader = (proc "ghci"
                [ "-ignore-dot-ghci", "-v0", "-XHaskell2010", "-idemo", "-isdk"
                , "sdk/Framework/Codegen.hs", directory </> "Effects.hs"
                , directory </> "AST.hs", "-e", expression
                ]) { std_in = NoStream, std_out = CreatePipe, std_err = Inherit }
          (result, output) <- withCreateProcess loader $ \_ printed _ process -> case printed of
            Just handle -> do
              output <- hGetContents handle
              _ <- evaluate (length output)
              result <- waitForProcess process
              pure (result, output)
            Nothing -> die "Cannot read the SDK generation plan"
          case result of
            ExitSuccess -> case readMaybe output of
              Nothing -> die "Cannot read the SDK generation plan"
              Just (Left problem) -> die problem
              Just (Right generatedCode) -> do
                let contracts = codeEffects generatedCode
                    program = codeProgram generatedCode
                    plan = codePrototypePlan generatedCode
                (handlers, shapes, nativeSource) <- prepareHandlers namespace
                  (codeHandlers generatedCode) (codeExports generatedCode) (codeSupport generatedCode)
                -- handler 方法体的结构按每个绑定换成 effect 方法的结构；首次尚无 Handlers 时不检查读取。
                methods <- either die pure (composeMethods (isJust nativeSource)
                  (codeBindings generatedCode) (codeReads generatedCode) shapes)
                let generated = directory </> "Generated"
                    cachePath = generated </> ".scope-cache"
                dependencies <- mapM readUtf8 structureSources
                let cacheKey = show (plan, methods, dependencies)
                cached <- tryIOError (readExisting cachePath)
                let previous = either (const Nothing) (>>= readMaybe) cached
                (prototype, structure, reused) <- case previous of
                  Just (key, value, source) | key == cacheKey -> do
                    either (die . show) pure (validatePrototype value)
                    pure (value, source, True)
                  _ -> case buildPreparedPrototype plan methods of
                    Left problem -> die (show problem)
                    Right value -> pure (value, renderPrototype value, False)
                -- 驱动检查每次执行，不受缓存命中影响；首次尚无 Handlers 时先生成契约。
                case nativeSource of
                  Just _ -> either (die . show) pure (checkDriven prototype)
                  Nothing -> pure ()
                -- 完成声明、原生语法和纯结构分析后才更新生成区；未变文件保留时间戳。
                _ <- evaluate (length structure)
                assets <- checkAssets namespace
                  [("Effects", contracts), ("Program", program ++ structure), ("Handlers", handlers)]
                  (codeAssetRoots generatedCode) (codeAssetContracts generatedCode) nativeSource
                createDirectoryIfMissing True generated
                changed <- sequence
                  [ writeIfChanged (generated </> "Effects.hs") contracts
                  , writeIfChanged (generated </> "Program.hs") (program ++ structure)
                  , writeIfChanged (generated </> "Handlers.hs") handlers
                  , writeIfChanged (generated </> "Assets.hs") assets
                  ]
                _ <- writeIfChanged cachePath (show (cacheKey, prototype, structure))
                putStrLn ("Generated " ++ generated ++ " (" ++ show (length (filter id changed))
                  ++ " files updated; structure " ++ (if reused then "reused" else "rebuilt") ++ ")")
            _ -> exitWith result
    _ -> die "Usage: effect-codegen workflow Namespace"

-- 缓存只省略纯构图；声明与 Handlers 快照仍读取，资产检查每次执行。
-- 连同算法及渲染器源码精确比较，避免 SDK 改动后复用旧结构。
structureSources :: [FilePath]
structureSources =
  [ "sdk/Framework/Prototype.hs"
  , "sdk/Framework/Prototype/Types.hs"
  , "sdk/Framework/Prototype/Query.hs"
  , "sdk/Framework/Prototype/Sources.hs"
  , "sdk/Framework/Codegen.hs"
  , "sdk/Framework/Codegen/Plan.hs"
  , "sdk/Framework/Effect/Registration.hs"
  , "sdk/Framework/Effect/Demand.hs"
  , "sdk/Framework/Effect/Contract.hs"
  , "sdk/Framework/Effect/Graph.hs"
  , "sdk/Framework/Recursion.hs"
  , "sdk/Framework/Workflow/AST.hs"
  , "sdk/Framework/Workflow/Structure.hs"
  ]

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
