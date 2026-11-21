-- 编译器 IO 驱动：Source/Shape 提供结构，Composition 统一计算，Emit 渲染，Assets 类检。
-- 流水线说明 v3（2026-11-17）：使用 Gen.Composition 的统一状态转换；本文件负责 IO。
module Framework.Gen (compileWorkflow, inspectWorkflow) where

import Control.Exception (evaluate)
import Framework.Gen.Check.Assets (checkAssets)
import Framework.Gen.Plan
import Framework.Gen.Composition
import Framework.Gen.Emit.Assets (renderAssets)
import Framework.Gen.Emit.Effects (renderEffects)
import Framework.Gen.Emit.Handlers (renderHandlers)
import Framework.Gen.Emit.Program (renderProgram)
import Framework.Gen.Emit.Prototype (renderPrototype, renderPrototypeModule)
import Framework.Gen.Emit.Workflow (renderWorkflowReport)
import Framework.Gen.Names (handlerClass, nameHandlers)
import Framework.Gen.Frontend.Hanging (loadHanging, loadOutline)
import Framework.Gen.Frontend.Shape (shapeHandlers)
import Framework.Gen.Frontend.Source (loadComposition, loadHandlers, loadWorkflowTree, namespaceDirectory, handlerText, handlerScopeNames)
import Data.List (nub)
import System.Directory (createDirectoryIfMissing, doesFileExist)
import System.Exit (die)
import System.FilePath ((</>))
import System.IO (IOMode(ReadMode, WriteMode), hGetContents, hPutStr, hSetEncoding, stdout, utf8, withFile)
import System.IO.Error (tryIOError)
import Text.Read (readMaybe)

-- 编译一个命名空间的 workflow 程序；程序只经 AST 启动，入口是 AST 中各 node 选中的末端。
compileWorkflow :: String -> IO ()
compileWorkflow namespace = do
  let generated = namespaceDirectory namespace </> "Generated"
      cachePath = generated </> ".scope-cache"
  -- 同一组合机器在声明进程中走到接口检查点；首次无 Handlers 也能生成同步契约。
  (hasHanging, targets, hangingSources) <- loadHanging namespace
  interface <- loadComposition namespace hasHanging targets
  let contracts = renderEffects interface
      handlersInScope = [(handlerClass handler', handler') | handler' <- unitHandlers interface]
  source <- loadHandlers namespace contracts
  shapes <- either (ioError . userError) pure (traverse (shapeHandlers namespace handlersInScope) source)
  pending <- either die pure (prepareComposition interface shapes)
  dependencies <- mapM readUtf8 structureSources
  let cacheKey = show (compositionKey pending, dependencies)
  cached <- tryIOError (readExisting cachePath)
  let previous = either (const Nothing) (>>= readMaybe) cached
  (result, structure, reused) <- case previous of
    Just (key, value, rendered) | key == cacheKey -> do
      completed <- either die pure (completeComposition pending (Just value))
      pure (completed, rendered, True)
    _ -> do
      completed <- either die pure (completeComposition pending Nothing)
      pure (completed, renderPrototype (compositionPrototype completed), False)
  let unit = compositionUnit result
      prototype = compositionPrototype result
      names = nameHandlers (maybe mempty handlerScopeNames source) (allMethods unit ++ historyEntries unit)
  handlers <- either (ioError . userError) pure (renderHandlers names unit source)
  -- 输出只读取机器完成态的接口事实。
  let program = renderProgram names hangingSources unit
      prototypeModule = renderPrototypeModule namespace structure
  _ <- evaluate (length structure)
  -- 类型检查、顶层白名单与资产目录；通过后才更新生成区，未变文件保留时间戳
  assets <- checkAssets namespace
    [("Effects", contracts), ("Prototype", prototypeModule), ("Program", program), ("Handlers", handlers)]
    (nub (map assetRepresentation (unitAssets unit)))
    (map assetContract (unitAssets unit)) (fmap handlerText source)
  createDirectoryIfMissing True generated
  changed <- sequence
    [ writeIfChanged (generated </> "Effects.hs") contracts
    , writeIfChanged (generated </> "Prototype.hs") prototypeModule
    , writeIfChanged (generated </> "Program.hs") program
    , writeIfChanged (generated </> "Handlers.hs") handlers
    , writeIfChanged (generated </> "Assets.hs") (renderAssets namespace assets)
    ]
  _ <- writeIfChanged cachePath (show (cacheKey, prototype, structure))
  putStrLn ("Generated " ++ generated ++ " (" ++ show (length (filter id changed))
    ++ " files updated; structure " ++ (if reused then "reused" else "rebuilt") ++ ")")

-- AST 的独立分析：只加载 AST、Workflow 与可选的 Hanging，不读注册与 handler，不写生成区。
-- 输出原样结构及其源码位置、规范形式与 NodeId、Hanging 挂载和结构诊断（JSON）。
-- 结构诊断不影响退出码；不能加载这些模块时照常以 GHC 诊断失败。
inspectWorkflow :: String -> IO ()
inspectWorkflow namespace = do
  (hasHanging, targets, sites) <- loadOutline namespace
  (tree, rows) <- loadWorkflowTree namespace hasHanging
  hSetEncoding stdout utf8
  putStrLn (renderWorkflowReport namespace tree rows targets sites)

-- 构图缓存连同算法及渲染器源码精确比较，避免 SDK 改动后复用旧结构；声明与 Handlers 快照仍每次读取。
structureSources :: [FilePath]
structureSources =
  [ "sdk/Framework/Prototype.hs"
  , "sdk/Framework/Prototype/Types.hs"
  , "sdk/Framework/Prototype/Graph.hs"
  , "sdk/Framework/Prototype/Query.hs"
  , "sdk/Framework/Prototype/Validate.hs"
  , "sdk/Framework/Gen/Composition.hs"
  , "sdk/Framework/Gen/Names.hs"
  , "sdk/Framework/Gen/Plan.hs"
  , "sdk/Framework/Gen/Injector.hs"
  , "sdk/Framework/Gen/Booter.hs"
  , "sdk/Framework/Gen/Workflow.hs"
  , "sdk/Framework/Gen/Emit/Prototype.hs"
  , "sdk/Framework/Gen/Emit/Types.hs"
  , "sdk/Framework/Language/Registration.hs"
  , "sdk/Framework/Language/AST.hs"
  , "sdk/Framework/Recursion.hs"
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
