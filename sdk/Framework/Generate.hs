-- 首次生成只编译注册与 AST/Target；handler 源码只解析，不加载或执行业务。
module Framework.Generate (main) where

import Data.Char (isAlphaNum, isUpper)
import Framework.Codegen.Handlers (renderHandlers)
import System.Directory (createDirectoryIfMissing)
import System.Environment (getArgs)
import System.Exit (ExitCode(..), die, exitWith)
import System.FilePath ((</>), pathSeparator)
import System.Process (readProcessWithExitCode)
import System.IO (IOMode(WriteMode), hPutStr, hSetEncoding, stderr, utf8, withFile)
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
              Just (Right (contracts, program, wrappers, scopeHandlers)) -> do
                handlers <- renderHandlers namespace wrappers scopeHandlers
                let generated = directory </> "Generated"
                    writeModule filename source = withFile (generated </> filename) WriteMode $ \handle -> do
                      hSetEncoding handle utf8
                      hPutStr handle source
                -- 声明和手写语法都成功解析后才重写生成区。
                createDirectoryIfMissing True generated
                writeModule "Effects.hs" contracts
                writeModule "Program.hs" program
                writeModule "Handlers.hs" handlers
                putStrLn ("Generated " ++ generated)
            _ -> exitWith result
    _ -> die "Usage: effect-codegen (workflow|target) Namespace"

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
