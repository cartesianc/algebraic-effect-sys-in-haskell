-- 编译器 IO 驱动：Source/Shape 提供结构，Composition 统一计算，Emit 渲染，Assets 类检。
-- 流水线说明 v3（2026-11-17）：使用 Gen.Composition 的统一状态转换；本文件负责 IO。
module Framework.Gen (compileNamespace, inspectConsole, inspectWorkflow) where

import Control.Exception (evaluate)
import Framework.Gen.Check.Assets (checkAssets)
import Framework.Gen.Plan
import Framework.Gen.Composition
import Framework.Gen.Console (writeConsole)
import Framework.Gen.Emit.Assets (renderAssets)
import Framework.Gen.Emit.Effects (renderEffects)
import Framework.Gen.Emit.Handlers (renderHandlers)
import Framework.Gen.Emit.Program (renderProgram)
import Framework.Gen.Emit.Prototype (renderPrototype, renderPrototypeModule)
import Framework.Gen.Emit.Workflow (renderWorkflowReport)
import Framework.Gen.Names (handlerClass, nameHandlers)
import Framework.Gen.Frontend.Effects (assetSpellings, specFromJson, syntacticRegistrations)
import Framework.Gen.Frontend.Hanging (Outline(..), loadOutline)
import Framework.Gen.Frontend.Shape (shapeHandlers)
import Framework.Gen.Frontend.Source (HandlerSource, loadComposition, loadHandlers, loadWorkflowTree, namespaceDirectory, handlerFailures, handlerScopeNames)
import Data.List (nub)
import Framework.Language.AST (WorkflowF)
import Framework.Recursion (Fix)
import System.Directory (createDirectoryIfMissing, doesFileExist)
import System.Exit (die)
import System.FilePath ((</>))
import System.IO (IOMode(ReadMode, WriteMode), hGetContents, hPutStr, hSetEncoding, stdout, utf8, withFile)

-- 编译一个命名空间的 workflow 程序；程序只经 AST 启动，入口是 AST 中各 node 选中的末端。
compileNamespace :: String -> IO ()
compileNamespace namespace = do
  directory <- namespaceDirectory namespace
  let generated = directory </> "Generated"
  (prepared, source, contracts) <- prepareNamespace namespace
  let Prepared outline tree rows pending = prepared
  -- 构图本身只需数毫秒，不设结构缓存：读取并比较缓存比重算更慢。
  result <- either die pure (completeComposition pending)
  let unit = compositionUnit result
      structure = renderPrototype (compositionPrototype result)
      names = nameHandlers (maybe mempty handlerScopeNames source) (allMethods unit ++ historyEntries unit)
  handlers <- either (ioError . userError) pure (renderHandlers names unit source)
  -- 输出只读取机器完成态的接口事实。
  let program = renderProgram directory names (outlineChecks outline) (compositionUntracked result) (compositionUntrackedSources result) unit
      workflow = renderWorkflowReport namespace tree rows (outlineTargets outline) (outlineSites outline)
        (outlineSources outline)
      prototypeModule = renderPrototypeModule namespace structure
  -- 业务模块与契约的类型检查、顶层白名单与资产目录；通过后才更新生成区，未变文件保留时间戳。
  -- 生成的 Program／Prototype／Handlers 与 Main 是普通 Haskell，由构建做类型检查，这里不重复。
  assets <- checkAssets namespace contracts
    (nub (map assetRepresentation (unitAssets unit)))
    (map assetContract (unitAssets unit)) (maybe [] handlerFailures source)
  createDirectoryIfMissing True generated
  changed <- sequence
    [ writeIfChanged (generated </> "Effects.hs") contracts
    , writeIfChanged (generated </> "Prototype.hs") prototypeModule
    , writeIfChanged (generated </> "Program.hs") program
    , writeIfChanged (generated </> "Handlers.hs") handlers
    , writeIfChanged (generated </> "Assets.hs") (renderAssets namespace assets)
    , writeIfChanged (generated </> "Workflow.json") (workflow ++ "\n")
    ]
  putStrLn ("Generated " ++ generated ++ " (" ++ show (length (filter id changed)) ++ " files updated)")

-- 生成与 console 共用的前半段：同一组合机器在声明进程中走到接口检查点，再读取 Handlers。
-- 首次无 Handlers 也能生成同步契约。
data Prepared = Prepared Outline (Fix WorkflowF) [([String], Int)] PendingComposition

prepareNamespace :: String -> IO (Prepared, Maybe HandlerSource, String)
prepareNamespace namespace = do
  -- 固定形式的注册、AST 与 Hanging 按语法读出，组合在本进程执行；只有写法超出固定形式时才起 ghci 求值。
  registrations <- syntacticRegistrations namespace
  outline <- loadOutline namespace (assetSpellings <$> registrations)
  let syntactic = do
        rows' <- registrations
        specifications <- mapM (specFromJson (outlineTypes outline)) rows'
        (tree', hanging') <- outlineTree outline
        pure (specifications, tree', hanging')
  (interface, tree, rows) <- case syntactic of
    Just (specifications, tree', hanging') ->
      either die (\plan -> pure (plan, tree', hanging'))
        (beginCompositionRows namespace specifications tree' hanging' (outlineTargets outline))
    Nothing -> loadComposition namespace (outlineHasHanging outline) (outlineTargets outline)
  let contracts = renderEffects interface
      handlersInScope = [(handlerClass handler', handler') | handler' <- unitHandlers interface]
  source <- loadHandlers namespace contracts
  shapes <- either (ioError . userError) pure (traverse (shapeHandlers namespace handlersInScope) source)
  pending <- either die pure (prepareComposition interface shapes)
  pure (Prepared outline tree rows pending, source, contracts)

-- 在内存中完成组合并导出可视化面板所需的事实；不写生成区。
inspectConsole :: String -> IO ()
inspectConsole namespace = do
  (Prepared _ _ _ pending, source, _) <- prepareNamespace namespace
  result <- either die pure (completeComposition pending)
  writeConsole result source

-- AST 的独立分析：只加载 AST、Workflow 与可选的 Hanging，不读注册与 handler，不写生成区。
-- 输出与完整生成写入的 Generated/Workflow.json 格式相同：原样结构及其源码位置、规范形式与 NodeId、
-- Hanging 挂载、结构诊断和源码文件指纹。结构诊断不影响退出码；不能加载这些模块时照常以 GHC 诊断失败。
inspectWorkflow :: String -> IO ()
inspectWorkflow namespace = do
  outline <- loadOutline namespace Nothing
  (tree, rows) <- maybe (loadWorkflowTree namespace (outlineHasHanging outline)) pure (outlineTree outline)
  hSetEncoding stdout utf8
  putStrLn (renderWorkflowReport namespace tree rows (outlineTargets outline) (outlineSites outline)
    (outlineSources outline))

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
