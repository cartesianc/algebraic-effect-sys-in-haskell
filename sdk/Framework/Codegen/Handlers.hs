-- 保留原生 Haskell 方法体；生成独立结构副本，并添加注册声明的运行入口包装。
module Framework.Codegen.Handlers (prepareHandlers, loadSumTypes) where

import Control.Exception (evaluate)
import Control.Monad.IO.Class (liftIO)
import Data.Foldable (toList)
import Data.List (intercalate, isPrefixOf, sortOn)
import Data.Maybe (isJust)
import Framework.Codegen.Structure (analyzeModule)
import Framework.Effect.Graph (MethodShape(..))
import GHC (GhcPs, getSessionDynFlags, runGhc)
import GHC.Data.FastString (mkFastString)
import GHC.Data.StringBuffer (stringToStringBuffer)
import GHC.Driver.Config.Parser (initParserOpts)
import GHC.Driver.Session (flagSpecFlag, flagSpecName, parseDynamicFilePragma, xFlags, xopt)
import GHC.Hs
import GHC.Fingerprint (fingerprintString)
import qualified GHC.Parser as Parser
import GHC.Parser.Annotation (getLocA)
import GHC.Parser.Header (getOptions)
import GHC.Parser.Lexer (ParseResult(..), initParserState, unP)
import GHC.Types.Name.Occurrence (occNameString)
import GHC.Types.Name.Reader (rdrNameOcc)
import GHC.Types.SrcLoc
import System.Directory (doesFileExist)
import System.FilePath ((</>), pathSeparator)
import System.IO (IOMode(ReadMode), hGetContents, hSetEncoding, hSetNewlineMode, universalNewlineMode, utf8, withFile)
import System.Process (readProcess)

-- 分析与复制共用一次读取和解析的快照，不加载 instance 或执行业务。
-- handler 方法体原样复制；gen 生成的标签、路由与 effect 方法追加在副本末尾。
-- 原文件始终保留，只有 Generated 副本进入运行导入链。
prepareHandlers :: String -> [(String, String)] -> [String] -> String
                -> IO (String, [(String, MethodShape String)], Maybe String)
prepareHandlers namespace handlers exports support = do
  loaded <- loadHandlers namespace
  shapes <- case loaded of
    Nothing -> pure []
    Just (_, parsed, implicitPrelude, rebindableSyntax) -> do
      analyzed <- either (ioError . userError) pure (analyzeModule namespace handlers implicitPrelude parsed)
      if rebindableSyntax && any ((/= Empty) . snd) analyzed
        then ioError (userError "Effect structure analysis does not support RebindableSyntax; use standard Haskell in handler bodies")
        else pure analyzed
  let generatedName = namespace ++ ".Generated.Handlers"
      sourceFingerprint = fmap (\(source, _, _, _) -> show (fingerprintString source)) loaded
      extraExports = "handlerSourceFingerprint" : exports
  generated <- case loaded of
    -- 首次生成尚无 handler：只给出指纹，编写 Handlers.hs 后重新生成。
    Nothing -> pure ("module " ++ generatedName ++ " (handlerSourceFingerprint) where\n")
    Just (source, parsed, _, _) -> either (ioError . userError) pure
      (copyModule namespace generatedName extraExports source parsed)
  pure ("-- 自动生成的编译副本；请修改上级 Handlers.hs 后重新生成。\n"
        ++ concat ["{-# LANGUAGE " ++ extension ++ " #-}\n" | extension <- copyExtensions]
        ++ generated
        ++ "\n-- 记录本编译副本实际使用的手写源码；启动前检查，避免执行过期方法体。\n"
        ++ "handlerSourceFingerprint :: Maybe String\n"
        ++ "handlerSourceFingerprint = " ++ show sourceFingerprint ++ "\n"
        ++ (if isJust loaded then support else ""), shapes,
        fmap (\(source, _, _, _) -> source) loaded)

-- 追加代码需要的扩展；手写文件自己的扩展照常生效。
copyExtensions :: [String]
copyExtensions =
  [ "ConstraintKinds", "DataKinds", "FlexibleContexts", "FlexibleInstances", "GeneralizedNewtypeDeriving"
  , "KindSignatures", "MultiParamTypeClasses", "ScopedTypeVariables", "TypeApplications", "UndecidableInstances" ]

loadHandlers :: String -> IO (Maybe (String, HsModule GhcPs, Bool, Bool))
loadHandlers namespace = do
  let inputPath = namespaceDirectory namespace </> "Handlers.hs"
  exists <- doesFileExist inputPath
  if not exists then pure Nothing else Just <$> parseSourceFile inputPath

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

-- 只改模块名、导出表并补充导入；方法体与 instance 原样保留。
copyModule :: String -> String -> [String] -> String -> HsModule GhcPs -> Either String String
copyModule namespace generatedName extraExports source parsed = do
  moduleName <- maybe (Left "Handlers.hs must declare its module") Right (hsmodName parsed)
  rename <- replace (getLocA moduleName) generatedName
  exports <- case hsmodExports parsed of
    Just names -> do
      (start, _) <- range (getLocA names)
      pure [(start + 1, start + 1, intercalate ", " extraExports ++ if null (unLoc names) then "" else ", ")]
    Nothing -> pure []
  firstImport <- case hsmodImports parsed of
    first : _ -> Right first
    [] -> Left "Handlers.hs must import the generated handler contracts"
  (importStart, _) <- range (getLocA firstImport)
  let imports = (importStart, importStart,
        "import qualified Framework.Generated as FrameworkRuntime\n"
        ++ "import qualified Framework.Effect.Contract as FrameworkRoot\n"
        ++ "import qualified " ++ namespace ++ ".Generated.Effects as FrameworkGenerated\n"
        ++ "import qualified Control.Monad.IO.Class as FrameworkIO\n"
        ++ "import qualified Data.Proxy as FrameworkProxy\n"
        ++ "import qualified GHC.TypeLits as FrameworkTypes\n"
        ++ "import " ++ namespace ++ ".Types\n")
  pure (foldr apply source (sortOn (\(start, _, _) -> start) (rename : imports : exports)))
  where
    apply (start, end, replacement) remaining =
      take start remaining ++ replacement ++ drop end remaining
    range (RealSrcSpan span _) = Right
      (sourceOffset source (srcSpanStartLine span) (srcSpanStartCol span),
       sourceOffset source (srcSpanEndLine span) (srcSpanEndCol span))
    range _ = Left "Handler source has no concrete location"
    replace location replacement = do
      (start, end) <- range location
      pure (start, end, replacement)
