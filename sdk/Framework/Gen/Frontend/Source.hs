-- 读取源程序（前端）：在声明加载进程中求值 effects 与 ast 并计算到接口检查点 Unit，
-- 解析 Types.hs 的和类型；用本次生成的契约对 Handlers.hs 做无代码类型检查，取得 GHC 解析的名称。
module Framework.Gen.Frontend.Source
  ( HandlerSource(..), NameUses, nameAtUse, loadComposition, loadWorkflowTree, loadHandlers, namespaceDirectory, sourceOffset, parseSourceFile
  ) where

import Control.Exception (evaluate)
import Control.Monad.IO.Class (liftIO)
import Data.Data (Data, cast, gmapQ)
import Data.Foldable (toList)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Framework.Gen.Plan (Unit)
import Framework.Gen.Check.TopLevel (checkTopLevel)
import Framework.Gen.Frontend.Ghc (libraryDirectory, withSourceTargets)
import Framework.Language.AST (WorkflowF)
import Framework.Recursion (Fix)
import GHC (GhcPs, GhcRn, LoadHowMuch(..), SuccessFlag(..), getModSummary, getModuleInfo, getSessionDynFlags,
            load, modInfoExports, ms_hspp_opts, ms_mod, parseModule, pm_parsed_source, runGhc, setTargets, tm_internals_,
            tm_renamed_source, typecheckModule)
import GHC.Fingerprint (fingerprintString)
import GHC.Data.FastString (mkFastString)
import GHC.Data.StringBuffer (stringToStringBuffer)
import GHC.Driver.Config.Parser (initParserOpts)
import GHC.Driver.Session (flagSpecFlag, flagSpecName, homeUnitId_, parseDynamicFilePragma, xFlags, xopt)
import GHC.Hs
import qualified GHC.Parser as Parser
import GHC.Parser.Annotation (getLocA)
import GHC.Parser.Header (getOptions)
import GHC.Parser.Lexer (ParseResult(..), initParserState, unP)
import GHC.Tc.Types (tcg_rdr_env)
import GHC.Types.Name (Name, nameOccName)
import GHC.Types.Name.Occurrence (OccName, occNameString)
import GHC.Types.Name.Reader (RdrName, globalRdrEnvElts, greName, rdrNameOcc, unQualOK)
import GHC.Unit.Module (mkModule, mkModuleName, moduleUnit)
import GHC.Types.SrcLoc
import System.Directory (doesFileExist)
import System.Exit (ExitCode(..), die, exitWith)
import System.FilePath ((</>), pathSeparator)
import System.IO (IOMode(ReadMode), hGetContents, hSetEncoding, hSetNewlineMode, universalNewlineMode, utf8, withFile)
import System.Process (CreateProcess(..), StdStream(..), proc, readProcess, waitForProcess, withCreateProcess)
import Text.Read (readMaybe)

-- effects 与 ast 是 Haskell 值，只有加载业务模块才能求值：在独立的 ghci 进程里调用
-- Framework.Gen.Composition.beginComposition，打印接口检查点再读回。
-- 同一次求值也打印原样业务树与 Hanging 各行，供 Generated/Workflow.json 使用。
loadComposition :: String -> Bool -> [[(String, [[Int]])]] -> IO (Unit, Fix WorkflowF, [([String], Int)])
loadComposition namespace hasHanging targets = do
  let directory = namespaceDirectory namespace
      tree = "(Framework.Language.AST.toWorkflowF " ++ namespace ++ ".AST.ast)"
      expression = "print (" ++ tree ++ ", " ++ hangingRowsOf namespace hasHanging
        ++ ", Framework.Gen.Composition.beginComposition " ++ show namespace ++ " " ++ namespace ++ ".Effects.effects "
        ++ tree ++ " " ++ mounts ++ " " ++ show targets ++ ")"
      mounts = if hasHanging then namespace ++ ".Hanging.hangingTree" else "(Framework.Language.AST.hanging [])"
  output <- printedByGhci
    (["sdk/Framework/Gen/Composition.hs", directory </> "Effects.hs", directory </> "AST.hs"]
      ++ [directory </> "Hanging.hs" | hasHanging]) expression
  case readMaybe output :: Maybe (Fix WorkflowF, [([String], Int)], Either String Unit) of
    Nothing -> die "Cannot read the SDK generation plan"
    Just (_, _, Left problem) -> die problem
    Just (source, rows, Right plan) -> pure (plan, source, rows)

-- 只求值业务树和 Hanging 各行的 hook 与目标数，不加载注册与 handler；树是业务写下的原样结构。
loadWorkflowTree :: String -> Bool -> IO (Fix WorkflowF, [([String], Int)])
loadWorkflowTree namespace hasHanging = do
  let directory = namespaceDirectory namespace
      expression = "print (Framework.Language.AST.toWorkflowF " ++ namespace ++ ".AST.ast, "
        ++ hangingRowsOf namespace hasHanging ++ ")"
  output <- printedByGhci ([directory </> "AST.hs"] ++ [directory </> "Hanging.hs" | hasHanging]) expression
  maybe (die "Cannot read the workflow tree") pure (readMaybe output)

hangingRowsOf :: String -> Bool -> String
hangingRowsOf namespace hasHanging
  | hasHanging = "Framework.Language.AST.hangingRows " ++ namespace ++ ".Hanging.hangingTree"
  | otherwise = "([] :: [([String], Int)])"

-- 在独立的 ghci 进程里加载业务模块并打印一个表达式。
-- GHC 的诊断直接写到本进程的 stderr，不经管道读回：GHC 按自己的区域编码输出，
-- 读回时的解码可能与之不一致（中文 Windows 上 chcp 65001 后即如此），会把诊断本身变成解码异常。
-- 只读回打印的结果，它经 show 转义，只含 ASCII。
printedByGhci :: [FilePath] -> String -> IO String
printedByGhci files expression = do
  let loader = (proc "ghci"
        ([ "-ignore-dot-ghci", "-v0", "-XHaskell2010", "-idemo", "-isdk"] ++ files ++ ["-e", expression]))
        { std_in = NoStream, std_out = CreatePipe, std_err = Inherit }
  (result, output) <- withCreateProcess loader $ \_ printed _ process -> case printed of
    Just handle -> do
      output <- hGetContents handle
      _ <- evaluate (length output)
      result <- waitForProcess process
      pure (result, output)
    Nothing -> die "Cannot read the ghci output"
  case result of
    ExitSuccess -> pure output
    _ -> exitWith result

-- 同一份源码的解析树保留业务写法，重命名树提供每处变量使用的定义身份。
data HandlerSource = HandlerSource
  { handlerText :: String
  , handlerModule :: HsModule GhcPs
  , handlerNames :: NameUses
  , handlerScopeNames :: Set.Set String
  , handlerImplicitPrelude :: Bool
  , handlerRebindable :: Bool
  , handlerFailures :: [String]  -- 手写 Handlers 的顶层白名单失败；与资产检查一起报告
  }

-- 首次生成时还没有 Handlers.hs：返回 Nothing，只生成契约。
loadHandlers :: String -> String -> IO (Maybe HandlerSource)
loadHandlers namespace contracts = do
  let inputPath = namespaceDirectory namespace </> "Handlers.hs"
  exists <- doesFileExist inputPath
  if not exists then pure Nothing else do
    source <- readSource inputPath
    withSourceTargets $ \memoryTarget -> do
      let handlers = namespace ++ ".Handlers"
      setTargets [memoryTarget handlers source, memoryTarget (namespace ++ ".Generated.Effects") contracts]
      flags <- getSessionDynFlags
      loaded <- load (LoadDependenciesOf (mkModule (homeUnitId_ flags) (mkModuleName handlers)))
      case loaded of
        Failed -> liftIO (ioError (userError ("Cannot load the imports of " ++ handlers)))
        Succeeded -> do
          summary <- getModSummary (mkModuleName handlers)
          parsed <- parseModule summary
          checked <- typecheckModule parsed
          case tm_renamed_source checked of
            Nothing -> liftIO (ioError (userError ("Missing renamed source for " ++ handlers)))
            Just (group, _, _, _, _) -> do
              -- 生成副本还会无修饰地导入本程序的 Types。内部包装名需要避开两边可见的名字。
              let sibling suffix = mkModule (moduleUnit (ms_mod summary)) (mkModuleName (namespace ++ suffix))
              types <- getModuleInfo (sibling ".Types")
              let enabled name = any (\flag -> flagSpecName flag == name && xopt (flagSpecFlag flag) (ms_hspp_opts summary)) xFlags
                  -- 生成副本沿用手写 import，并额外导入 Types。仅限定可见的外部名不会占用本地拼写。
                  visible = [greName entry | entry <- globalRdrEnvElts (tcg_rdr_env (fst (tm_internals_ checked))), unQualOK entry]
              pure (Just HandlerSource
                { handlerText = source
                , handlerModule = unLoc (pm_parsed_source parsed)
                , handlerNames = Map.fromList (variableUses group)
                , handlerScopeNames = Set.fromList [occNameString (nameOccName name)
                    | name <- visible ++ maybe [] modInfoExports types]
                , handlerImplicitPrelude = enabled "ImplicitPrelude"
                , handlerRebindable = enabled "RebindableSyntax"
                , handlerFailures = checkTopLevel namespace checked
                })

-- Name 的定义位置和变量的使用位置不同。用同一次 parse/rename 的 token 范围对齐，
-- 拼写用于区分重命名展开时可能共享位置的名称；无源码位置的合成变量不属于手写表达式。
type NameUses = Map.Map (RealSrcSpan, OccName) Name

variableUses :: Data a => a -> [((RealSrcSpan, OccName), Name)]
variableUses tree
  | Just (HsVar _ identifier) <- (cast tree :: Maybe (HsExpr GhcRn)) =
      case getLocA identifier of
        RealSrcSpan location _ -> let name = unLoc identifier in [((location, nameOccName name), name)]
        _ -> []
  | otherwise = concat (gmapQ variableUses tree)

nameAtUse :: NameUses -> LocatedN RdrName -> Maybe Name
nameAtUse names identifier = case getLocA identifier of
  RealSrcSpan span _ -> Map.lookup (span, rdrNameOcc (unLoc identifier)) names
  _ -> Nothing

namespaceDirectory :: String -> FilePath
namespaceDirectory namespace = "demo" </> map (\c -> if c == '.' then pathSeparator else c) namespace

readSource :: FilePath -> IO String
readSource inputPath = withFile inputPath ReadMode $ \handle -> do
  hSetEncoding handle utf8
  hSetNewlineMode handle universalNewlineMode
  contents <- hGetContents handle
  _ <- evaluate (length contents)
  pure contents

-- 和类型只需要声明形状；按该文件自己的语言扩展解析。
parseSourceFile :: FilePath -> IO (String, HsModule GhcPs)
parseSourceFile inputPath = do
  source <- readSource inputPath
  library <- libraryDirectory
  runGhc (Just library) $ do
    initial <- getSessionDynFlags
    let buffer = stringToStringBuffer source
        (_, options) = getOptions (initParserOpts initial) buffer inputPath
    (flags, _, _) <- parseDynamicFilePragma initial options
    let state = initParserState (initParserOpts flags) buffer
          (mkRealSrcLoc (mkFastString inputPath) 1 1)
    case unP Parser.parseModule state of
      PFailed _ -> liftIO (ioError (userError ("Cannot parse " ++ inputPath ++ "; check its Haskell syntax")))
      POk _ parsed -> pure (source, unLoc parsed)

-- 行列号（列按 GHC 的制表位规则）换算为源码字符偏移。
sourceOffset :: String -> Int -> Int -> Int
sourceOffset source line column =
  sum (map ((+ 1) . length) (take (line - 1) (lines source)))
  + columnOffset 1 (lines source !! (line - 1))
  where
    columnOffset current remaining
      | current >= column = 0
      | otherwise = case remaining of
          [] -> 0
          character : rest -> 1 + columnOffset
            (if character == '\t' then current + 8 - (current - 1) `mod` 8 else current + 1) rest
