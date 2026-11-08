-- gen：这个 EDSL 的编译器。源程序是一个 demo 命名空间下的 Types、Effects、AST 与 Handlers；
-- 产物是 Generated/ 下交给 GHC 编译的 Haskell（中间表示）和其中的 Prototype（静态结构）。
-- 链的组合、读取路由与合法性都在这里定下来，运行时只执行产物，不再推导。
--
-- 流水线按阶段执行，每个阶段一个模块，失败即停止，生成区只在全部阶段通过后写回：
--
--   1 读取  Framework.Gen.Source      解析 Types.hs 的和类型；在声明加载进程中求值 effects 与 ast
--   2 降级  Framework.Gen.Lower       注册与 workflow → PrototypePlan，注册级与 workflow 结构检查
--   3 绑定  Framework.Gen.Bind        每个 handler 绑定的前驱、驱动、raw、读取路由、签名与 Layer
--   4 形状  Framework.Gen.Shape       解析 Handlers.hs，提取方法体的读取形状（require @T、raw）
--   5 组成  Framework.Gen.Bind        按绑定把形状换成 effect 方法的结构，检查读取路由与未读声明
--   6 构图  Framework.Gen.Build       EffectGraph、ScopeTree、链挂载与资产来源，得到 Prototype；驱动检查
--   7 输出  Framework.Gen.Emit.*      Generated/Effects、Handlers、Program 的源码
--   8 类检  Framework.Gen.Assets      GHC 类型检查业务模块与输出，顶层白名单，资产目录 Generated/Assets
--
-- 不执行 handler 业务；构图结果按输入与 SDK 源码缓存在 Generated/.scope-cache。
module Framework.Gen (compileWorkflow) where

import Control.Exception (evaluate)
import Data.Maybe (isJust)
import Framework.Gen.Assets (checkAssets)
import Framework.Gen.Bind (Unit(..), AssetDeclaration(..), bindProgram, composeMethods, reference)
import Framework.Gen.Build (buildPrototype, checkDriven)
import Framework.Gen.Emit.Effects (renderEffects)
import Framework.Gen.Emit.Handlers (renderHandlers)
import Framework.Gen.Emit.Program (renderProgram)
import Framework.Gen.Emit.Prototype (renderPrototype)
import Framework.Gen.Names (handlerClass)
import Framework.Gen.Shape (shapeHandlers)
import Framework.Gen.Source (lowerDeclarations, loadHandlers, loadSumTypes, namespaceDirectory, handlerText)
import Framework.Prototype (validatePrototype)
import Data.List (nub)
import System.Directory (createDirectoryIfMissing, doesFileExist)
import System.Exit (die)
import System.FilePath ((</>))
import System.IO (IOMode(ReadMode, WriteMode), hGetContents, hPutStr, hSetEncoding, utf8, withFile)
import System.IO.Error (tryIOError)
import Text.Read (readMaybe)

-- 编译一个命名空间的 workflow 程序；程序只经 AST 启动，入口是 AST 中各 node 选中的末端。
compileWorkflow :: String -> IO ()
compileWorkflow namespace = do
  let generated = namespaceDirectory namespace </> "Generated"
      cachePath = generated </> ".scope-cache"
  -- 1 读取与 2 降级
  sumTypes <- loadSumTypes namespace
  plan <- lowerDeclarations namespace sumTypes
  -- 3 绑定
  unit <- either die pure (bindProgram namespace plan sumTypes)
  -- 4 形状：首次生成尚无 Handlers.hs 时没有方法体，只生成契约
  source <- loadHandlers namespace
  shapes <- either (ioError . userError) pure
    (maybe (Right []) (shapeHandlers namespace [(handlerClass handler', handler') | handler' <- unitHandlers unit]) source)
  handlers <- either (ioError . userError) pure (renderHandlers unit source)
  -- 5 组成：handler 方法体的结构按每个绑定换成 effect 方法的结构；尚无 Handlers 时不检查读取
  methods <- either die pure (composeMethods (isJust source) (unitBindings unit) (unitReads unit) shapes)
  -- 6 构图：缓存只省略纯构图，命中时仍校验；驱动检查每次执行，首次尚无 Handlers 时跳过
  dependencies <- mapM readUtf8 structureSources
  let cacheKey = show (plan, methods, dependencies)
  cached <- tryIOError (readExisting cachePath)
  let previous = either (const Nothing) (>>= readMaybe) cached
  (prototype, structure, reused) <- case previous of
    Just (key, value, rendered) | key == cacheKey -> do
      either (die . show) pure (validatePrototype value)
      pure (value, rendered, True)
    _ -> case buildPrototype plan methods of
      Left problem -> die (show problem)
      Right value -> pure (value, renderPrototype value, False)
  case source of
    Just _ -> either (die . show) pure (checkDriven prototype)
    Nothing -> pure ()
  -- 7 输出
  let contracts = renderEffects unit
      program = renderProgram unit ++ structure
  _ <- evaluate (length structure)
  -- 8 类型检查、顶层白名单与资产目录；通过后才更新生成区，未变文件保留时间戳
  assets <- checkAssets namespace
    [("Effects", contracts), ("Program", program), ("Handlers", handlers)]
    (nub [reference (assetRepresentation declared) | declared <- unitAssets unit])
    (map assetContract (unitAssets unit)) (fmap handlerText source)
  createDirectoryIfMissing True generated
  changed <- sequence
    [ writeIfChanged (generated </> "Effects.hs") contracts
    , writeIfChanged (generated </> "Program.hs") program
    , writeIfChanged (generated </> "Handlers.hs") handlers
    , writeIfChanged (generated </> "Assets.hs") assets
    ]
  _ <- writeIfChanged cachePath (show (cacheKey, prototype, structure))
  putStrLn ("Generated " ++ generated ++ " (" ++ show (length (filter id changed))
    ++ " files updated; structure " ++ (if reused then "reused" else "rebuilt") ++ ")")

-- 构图缓存连同算法及渲染器源码精确比较，避免 SDK 改动后复用旧结构；声明与 Handlers 快照仍每次读取。
structureSources :: [FilePath]
structureSources =
  [ "sdk/Framework/Prototype.hs"
  , "sdk/Framework/Prototype/Types.hs"
  , "sdk/Framework/Prototype/Graph.hs"
  , "sdk/Framework/Prototype/Query.hs"
  , "sdk/Framework/Prototype/Validate.hs"
  , "sdk/Framework/Gen/Lower.hs"
  , "sdk/Framework/Gen/Demand.hs"
  , "sdk/Framework/Gen/Names.hs"
  , "sdk/Framework/Gen/Bind.hs"
  , "sdk/Framework/Gen/Build.hs"
  , "sdk/Framework/Gen/Build/Graph.hs"
  , "sdk/Framework/Gen/Build/Sources.hs"
  , "sdk/Framework/Gen/Emit/Prototype.hs"
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
