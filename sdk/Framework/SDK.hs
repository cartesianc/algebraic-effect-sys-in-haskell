{-# LANGUAGE DuplicateRecordFields #-}

-- Demo 的统一入口；Effect、recursion scheme、workflow 与代码生成分别实现。
module Framework.SDK
  ( module Framework.Effect
  , module Framework.Effect.Graph
  , module Framework.Workflow.Structure
  , AST, EffectNode, node, chained, parallel, alternative, interpreter
  , Generic, NFData
  ) where

import Framework.Effect
import Framework.Effect.Graph
import Framework.Effect.Runtime (cleanupTargets)
import Framework.Workflow.AST (AST, EffectNode, node, chained, parallel, alternative)
import Framework.Workflow.Execution (runStructuredAST)
import Framework.Workflow.Structure
import Control.DeepSeq (NFData, force)
import Control.Exception (SomeException, evaluate, mask, throwIO, try)
import Control.Monad (unless, void)
import GHC.Fingerprint (fingerprintString)
import GHC.Generics (Generic)
import System.Environment (getArgs)
import System.FilePath ((</>), pathSeparator)
import System.IO (IOMode(ReadMode), hGetContents, hPrint, hSetEncoding, hSetNewlineMode, stderr, stdout, universalNewlineMode, utf8, withFile)
import System.IO.Error (tryIOError)
import System.Process (callProcess)

-- 生成的 facade 绑定编译期注册与末端方法，用户只传 ast 和 effects。
-- Node 只登记末端句柄；algebra lower 后才具备具体执行入口。
interpreter
  :: (Show cause, Show value, Show method, Ord method, NFData method)
  => String
  -> [EffectSpec] -> Maybe String
  -> Either (StructureError method) (ProgramStructure method)
  -> [(String, (String, String))] -> [(String, [String])]
  -> IO ([Target environment cause value], [Target environment cause String]) -> AST -> [EffectSpec] -> IO ()
interpreter namespace registered sourceFingerprint initialize alternativeCases alternativeConstructors createEntries tree specifications = do
  hSetEncoding stdout utf8
  arguments <- getArgs
  case arguments of
    []
      | specifications /= registered ->
          staleGenerated namespace "Registrations changed"
      | otherwise -> do
          verifyHandlerSource namespace sourceFingerprint
          structure <- initializeBeforeBusiness
          (entries, selectors) <- createEntries
          mask $ \restore -> do
            completed <- tryAny $ restore $ do
              output <- runStructuredAST structure alternativeCases alternativeConstructors tree entries selectors
              let rendered = show output
              -- 各 Node 已在释放使用前消费自己的结果；这里完成汇总错误的显示。
              evaluate (foldr seq () rendered)
              pure (output, rendered)
            failures <- cleanupTargets entries
            case completed of
              Left exception -> do
                unless (null failures) (report (map snd failures))
                throwIO exception
              Right (output, rendered) -> do
                let result = appendCleanup (map snd failures) output
                case [exception | (Just exception, _) <- failures] of
                  exception : _ -> do
                    report result
                    throwIO exception
                  [] -> restore $ if null failures then putStrLn rendered else print result
    ["--generate"] -> generate namespace
    ["--structure"]
      | specifications /= registered -> staleRegistrations
      | otherwise -> do
          verifyHandlerSource namespace sourceFingerprint
          structure <- initializeBeforeBusiness
          rendered <- either (ioError . userError . show) pure (renderStructure structure (map fst alternativeConstructors) tree)
          putStr rendered
    _ -> ioError (userError "Usage: demo [--generate|--structure]")
  where
    staleRegistrations = ioError (userError
      ("Registrations changed; run: cabal run effect-codegen -- workflow " ++ namespace))
    initializeBeforeBusiness = do
      result <- evaluate (force initialize)
      either (ioError . userError . ("Cannot initialize effect structure: " ++) . show) pure result

-- 保留原始业务故障；主执行成功时，首个清理故障成为完成失败。
appendCleanup :: [Failure cause] -> Output cause value -> Output cause value
appendCleanup [] output = output
appendCleanup failures (Failed original) =
  Failed (original { cleanupFailures = cleanupFailures original ++ failures })
appendCleanup (first : rest) (Succ _) =
  Failed (first { cleanupFailures = cleanupFailures first ++ rest })

tryAny :: IO value -> IO (Either SomeException value)
tryAny = try

-- 报告失败不能覆盖已经选定的主异常或取消异常。
report :: Show value => value -> IO ()
report = void . tryAny . hPrint stderr

-- 与生成时使用相同的 UTF-8 和换行读取方式；比对源码与本编译副本保存的指纹。
verifyHandlerSource :: String -> Maybe String -> IO ()
verifyHandlerSource namespace expected = do
  let path = "demo" </> map (\character -> if character == '.' then pathSeparator else character) namespace </> "Handlers.hs"
  actual <- tryIOError $ withFile path ReadMode $ \handle -> do
    hSetEncoding handle utf8
    hSetNewlineMode handle universalNewlineMode
    source <- hGetContents handle
    _ <- evaluate (length source)
    pure (show (fingerprintString source))
  case actual of
    Right fingerprint | expected == Just fingerprint -> pure ()
    Right _ -> staleGenerated namespace (path ++ " changed or has not been generated")
    Left problem -> staleGenerated namespace ("Cannot verify " ++ path ++ ": " ++ show problem)

staleGenerated :: String -> String -> IO value
staleGenerated namespace reason = ioError (userError
  (reason ++ "; run from the repository root: cabal run effect-codegen -- workflow " ++ namespace))

-- 统一经过 SDK 生成命令；业务运行载体不依赖 GHC 的源码解析 API。
generate :: String -> IO ()
generate namespace = callProcess "cabal" ["run", "effect-codegen", "--", "workflow", namespace]
