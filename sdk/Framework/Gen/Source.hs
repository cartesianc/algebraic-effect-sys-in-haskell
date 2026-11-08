-- 读取源程序（前端）：在声明加载进程中求值 effects 与 ast 并降级为 PrototypePlan，
-- 用 GHC 解析器读取 Types.hs 的和类型与 Handlers.hs 的语法树。只解析和求值声明，不加载 handler 或执行业务。
module Framework.Gen.Source
  ( HandlerSource(..), lowerDeclarations, loadHandlers, loadSumTypes, namespaceDirectory, sourceOffset
  ) where

import Control.Exception (evaluate)
import Control.Monad.IO.Class (liftIO)
import Data.Foldable (toList)
import Framework.Prototype.Types (PrototypePlan, SumTypes)
import GHC (GhcPs, getSessionDynFlags, runGhc)
import GHC.Data.FastString (mkFastString)
import GHC.Data.StringBuffer (stringToStringBuffer)
import GHC.Driver.Config.Parser (initParserOpts)
import GHC.Driver.Session (flagSpecFlag, flagSpecName, parseDynamicFilePragma, xFlags, xopt)
import GHC.Hs
import qualified GHC.Parser as Parser
import GHC.Parser.Annotation (getLocA)
import GHC.Parser.Header (getOptions)
import GHC.Parser.Lexer (ParseResult(..), initParserState, unP)
import GHC.Types.Name.Occurrence (occNameString)
import GHC.Types.Name.Reader (rdrNameOcc)
import GHC.Types.SrcLoc
import System.Directory (doesFileExist)
import System.Exit (ExitCode(..), die, exitWith)
import System.FilePath ((</>), pathSeparator)
import System.IO (IOMode(ReadMode), hGetContents, hSetEncoding, hSetNewlineMode, universalNewlineMode, utf8, withFile)
import System.Process (CreateProcess(..), StdStream(..), proc, readProcess, waitForProcess, withCreateProcess)
import Text.Read (readMaybe)

-- effects 与 ast 是 Haskell 值，只有加载业务模块才能求值：在独立的 ghci 进程里调用
-- Framework.Gen.Lower.lowerProgram，打印降级结果再读回。和类型的构造器信息以字面量传入。
lowerDeclarations :: String -> SumTypes -> IO PrototypePlan
lowerDeclarations namespace sumTypes = do
  let directory = namespaceDirectory namespace
      expression = "print (Framework.Gen.Lower.lowerProgram " ++ namespace ++ ".Effects.effects"
        ++ " (Framework.Language.AST.toWorkflowF " ++ namespace ++ ".AST.ast) " ++ show sumTypes ++ ")"
  -- GHC 的诊断直接写到本进程的 stderr，不经管道读回：GHC 按自己的区域编码输出，
  -- 读回时的解码可能与之不一致（中文 Windows 上 chcp 65001 后即如此），会把诊断本身变成解码异常。
  -- 只读回打印的结果，它经 show 转义，只含 ASCII。
  let loader = (proc "ghci"
        [ "-ignore-dot-ghci", "-v0", "-XHaskell2010", "-idemo", "-isdk"
        , "sdk/Framework/Gen/Lower.hs", directory </> "Effects.hs"
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
      Just (Right plan) -> pure plan
    _ -> exitWith result

-- 手写 Handlers.hs 的一次读取与解析快照；分析与复制共用它，不加载 instance 或执行业务。
data HandlerSource = HandlerSource
  { handlerText :: String
  , handlerModule :: HsModule GhcPs
  , handlerImplicitPrelude :: Bool
  , handlerRebindable :: Bool
  }

-- 首次生成时还没有 Handlers.hs：返回 Nothing，只生成契约。
loadHandlers :: String -> IO (Maybe HandlerSource)
loadHandlers namespace = do
  let inputPath = namespaceDirectory namespace </> "Handlers.hs"
  exists <- doesFileExist inputPath
  if not exists then pure Nothing else do
    (source, parsed, implicitPrelude, rebindableSyntax) <- parseSourceFile inputPath
    pure (Just (HandlerSource source parsed implicitPrelude rebindableSyntax))

namespaceDirectory :: String -> FilePath
namespaceDirectory namespace = "demo" </> map (\c -> if c == '.' then pathSeparator else c) namespace

-- 以文件自身的语言扩展解析源码；只读取语法树，不加载或执行模块。
parseSourceFile :: FilePath -> IO (String, HsModule GhcPs, Bool, Bool)
parseSourceFile inputPath = do
  source <- withFile inputPath ReadMode $ \handle -> do
    hSetEncoding handle utf8
    hSetNewlineMode handle universalNewlineMode
    contents <- hGetContents handle
    _ <- evaluate (length contents)
    pure contents
  library <- takeWhile (`notElem` "\r\n") <$> readProcess "ghc" ["--print-libdir"] ""
  runGhc (Just library) $ do
    initial <- getSessionDynFlags
    let buffer = stringToStringBuffer source
        (_, options) = getOptions (initParserOpts initial) buffer inputPath
    (flags, _, _) <- parseDynamicFilePragma initial options
    let state = initParserState (initParserOpts flags) buffer
          (mkRealSrcLoc (mkFastString inputPath) 1 1)
    case unP Parser.parseModule state of
      PFailed _ -> liftIO (ioError (userError ("Cannot parse " ++ inputPath ++ "; check its Haskell syntax")))
      POk _ parsed ->
        let enabled name = any (\option -> flagSpecName option == name && xopt (flagSpecFlag option) flags) xFlags
        in pure (source, unLoc parsed, enabled "ImplicitPrelude", enabled "RebindableSyntax")

-- Types.hs 中的和类型：至少两个构造器、每个构造器至多一个字段；字段类型取源码原文。
-- 多字段和类型仍是合法业务 ADT；这里只支持上述自动投影形状，其余不生成分支契约。
loadSumTypes :: String -> IO [(String, [(String, Maybe String)])]
loadSumTypes namespace = do
  let inputPath = namespaceDirectory namespace </> "Types.hs"
  exists <- doesFileExist inputPath
  if not exists then pure [] else do
    (source, parsed, _, _) <- parseSourceFile inputPath
    let text located = case getLocA located of
          RealSrcSpan span _ ->
            let start = sourceOffset source (srcSpanStartLine span) (srcSpanStartCol span)
                end = sourceOffset source (srcSpanEndLine span) (srcSpanEndCol span)
            in Just (dropWhile (`elem` "!~ ") (take (end - start) (drop start source)))
          _ -> Nothing
        fields declaration = case unLoc declaration of
          ConDeclH98 { con_name = constructor, con_args = arguments } ->
            let named = occNameString (rdrNameOcc (unLoc constructor))
            in case arguments of
              PrefixCon _ [] -> Just (named, Nothing)
              PrefixCon _ [HsScaled _ argument] -> (\found -> (named, Just found)) <$> text argument
              RecCon (L _ [L _ ConDeclField { cd_fld_names = [_], cd_fld_type = argument }]) ->
                (\found -> (named, Just found)) <$> text argument
              _ -> Nothing
          _ -> Nothing
    pure
      [ (occNameString (rdrNameOcc typeName), constructors)
      | L _ (TyClD _ DataDecl { tcdLName = L _ typeName, tcdDataDefn = HsDataDefn { dd_cons = declared } }) <- hsmodDecls parsed
      , let candidates = map fields (toList declared)
      , length candidates > 1, all (/= Nothing) candidates
      , let constructors = [found | Just found <- candidates] ]

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
