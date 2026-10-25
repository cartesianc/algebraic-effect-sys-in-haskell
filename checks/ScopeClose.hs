-- 运行：runghc -idemo -isdk checks/ScopeClose.hs
-- 仅测试生成方法的生命周期边界；这里的内部 Target 装配不是新增业务 facade。
module Main (main) where

import qualified Framework.SDK as SDK
import qualified Framework.Effect.Scope as Scope
import Framework.Effect.Binding (bindingValues)
import Framework.Workflow.Execution (runAST)
import ScopeReuseDemo.Generated.Effects
import qualified ScopeReuseDemo.Generated.Handlers as Handlers
import ScopeReuseDemo.Types
import Control.Exception (evaluate, finally)
import Control.Concurrent.MVar (readMVar)
import Control.Monad (unless, forM_)
import Data.IORef (readIORef)
import System.IO (IOMode(ReadMode), hClose, hGetContents, hIsClosed, withFile)

check :: Bool -> String -> IO ()
check condition description = do
  unless condition (ioError (userError ("FAIL: " ++ description)))
  putStrLn ("PASS: " ++ description)

completed :: Int -> SDK.Output Errors [()] -> IO ()
completed expected (SDK.Succ results) =
  unless (length results == expected) (ioError (userError "Unexpected completed call count"))
completed _ (SDK.Failed problem) = ioError (userError (show problem))

main :: IO ()
main = do
  scopes <- Handlers.newScopeHandlers
  handler <- Scope.getScope scopes "SharedFileScope"
  let target selected action = SDK.targetApp selected emptyContexts scopes action
      entries =
        [ target "prepare" prepareProbe
        , target "first" writeFirst
        , target "second" writeSecond
        , target "third" writeThird
        , target "close" closeSharedFile
        ]
      -- 异常清理也只在检查退出后进行，不作为重复 close 检测的成功依据。
      cleanup = do
        instances <- readMVar (Scope.scopeInstances handler)
        forM_ instances $ \slot -> do
          record <- readIORef (Scope.scopeRecord slot)
          case (lookup "FileResource" (Scope.scopeBindings record) >>= boundFileResource . bindingValues) of
            Nothing -> pure ()
            Just (OpenedFile _ file _) -> do
              closed <- hIsClosed file
              unless closed (hClose file)
  flip finally cleanup $ do
    runAST (SDK.chained
      [ SDK.node "prepare"
      , SDK.parallel (map SDK.node ["first", "second", "third"])
      ]) entries >>= completed 4
    [slot] <- readMVar (Scope.scopeInstances handler)
    record <- readIORef (Scope.scopeRecord slot)
    check (case Scope.scopePhase record of Scope.ScopeActive -> True; _ -> False)
      "scope is Active before the close calls"
    OpenedFile (FilePaths _ journal) file _ <-
      maybe (ioError (userError "Missing opened file")) pure
        ((lookup "FileResource" (Scope.scopeBindings record) >>= boundFileResource . bindingValues))
    runAST (SDK.parallel (replicate 3 (SDK.node "close"))) entries >>= completed 3
    check True "all three concurrent generated close calls returned successfully"
    runAST (SDK.node "close") entries >>= completed 1
    check True "another close after completion returned successfully"
    events <- withFile journal ReadMode $ \logFile -> do
      contents <- hGetContents logFile
      _ <- evaluate (length contents)
      pure (lines contents)
    check (events == ["file-open", "open-body", "close-body", "file-close"])
      "four close calls executed one close body and one hClose; no reopen"
    closed <- hIsClosed file
    check closed "the actual file Handle is closed"
    finalRecord <- readIORef (Scope.scopeRecord slot)
    check (case Scope.scopePhase finalRecord of Scope.ScopeClosed _ -> True; _ -> False)
      "scope remains Closed after all repeated calls"
