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

-- 分析与包装共用一次读取和解析的快照，不加载 instance 或执行业务。
-- 包装计划来自注册；原文件始终保留，只有 Generated 副本进入运行导入链。
prepareHandlers :: String -> [(String, String, String, String)] -> String
                -> ([(String, [((String, String), String)])], [(String, String)])
                -> IO (String, [((String, String), MethodShape String)], Maybe String)
prepareHandlers namespace wrappers scopeHandlers routes = do
  loaded <- loadHandlers namespace
  shapes <- case loaded of
    Nothing -> pure []
    Just (_, parsed, implicitPrelude, rebindableSyntax) -> do
      let methods = [(owner, method) | (owner, method, _, _) <- wrappers]
      analyzed <- either (ioError . userError) pure (analyzeModule namespace methods routes implicitPrelude parsed)
      if rebindableSyntax && any ((/= Empty) . snd) analyzed
        then ioError (userError "Effect structure analysis does not support RebindableSyntax; use standard Haskell effect composition")
        else pure analyzed
  let exists = isJust loaded
      generatedName = namespace ++ ".Generated.Handlers"
      sourceFingerprint = fmap (\(source, _, _, _) -> show (fingerprintString source)) loaded
      extraExports = "handlerSourceFingerprint" : [name | name <- ["newScopeHandlers", "scopeCleanups", "errorHandlers", "contextInjections"]
        , any ((name ++ " ::") `isPrefixOf`) (lines scopeHandlers)]
  generated <- case loaded of
    Nothing -> pure $ if null extraExports
      then "module " ++ generatedName ++ " () where\n"
      else "module " ++ generatedName ++ " (" ++ intercalate ", " extraExports ++ ") where\n"
        ++ "import qualified Framework.SDK as FrameworkRuntime\n"
        ++ "import qualified Framework.Effect.Contract as FrameworkRoot\n"
        ++ "import qualified " ++ namespace ++ ".Generated.Effects as FrameworkGenerated\n"
    Just (source, parsed, _, _) -> either (ioError . userError) pure
      (wrapModule namespace generatedName wrappers extraExports source parsed)
  -- 首次生成尚无业务 instance；保留契约与 scope 构造器，暂不安装业务回调。
  -- 用户填写 Handlers.hs 后重新生成，才恢复 close 与 Error 方法引用。
  let extraDefinitions
        | exists = scopeHandlers
        | otherwise = unlines (emptyCallbacks (lines scopeHandlers))
      emptyCallbacks [] = []
      emptyCallbacks (line : rest)
        | line `elem` ["scopeCleanups =", "errorHandlers =", "contextInjections ="] =
            "-- 尚未加载用户 instance；编写 Handlers.hs 后重新生成。"
              : (line ++ " []")
              : emptyCallbacks (dropWhile (\body -> null body || "  " `isPrefixOf` body) rest)
        | otherwise = line : emptyCallbacks rest
  pure ("-- 自动生成的编译副本；请修改上级 Handlers.hs 后重新生成。\n"
        ++ "{-# LANGUAGE ScopedTypeVariables #-}\n"
        ++ "{-# LANGUAGE TypeApplications #-}\n"
        ++ generated
        ++ "\n-- 记录本编译副本实际使用的手写源码；启动前检查，避免执行过期方法体。\n"
        ++ "handlerSourceFingerprint :: Maybe String\n"
        ++ "handlerSourceFingerprint = " ++ show sourceFingerprint ++ "\n"
        ++ (if null extraDefinitions then "" else "\n\n" ++ extraDefinitions), shapes,
        fmap (\(source, _, _, _) -> source) loaded)

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
-- 有构造器带多个字段的类型不算和类型资产，不生成分支契约。
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

wrapModule
  :: String -> String -> [(String, String, String, String)] -> [String] -> String -> HsModule GhcPs
  -> Either String String
wrapModule namespace generatedName wrappers extraExports source parsed = do
  moduleName <- maybe (Left "Handlers.hs must declare its module") Right (hsmodName parsed)
  rename <- replace (getLocA moduleName) generatedName
  exports <- case hsmodExports parsed of
    Just names | not (null extraExports) -> do
      (start, _) <- range (getLocA names)
      pure [(start + 1, start + 1, intercalate ", " extraExports ++ if null (unLoc names) then "" else ", ")]
    _ -> pure []
  firstImport <- case hsmodImports parsed of
    first : _ -> Right first
    [] -> Left "Handlers.hs must import the generated effect contracts"
  (importStart, _) <- range (getLocA firstImport)
  let imports = (importStart, importStart,
        "import qualified Framework.SDK as FrameworkRuntime\n"
        ++ "import qualified Framework.Effect.Contract as FrameworkRoot\n"
        ++ "import qualified " ++ namespace ++ ".Generated.Effects as FrameworkGenerated\n")
  edits <- concat <$> mapM instanceEdits (hsmodDecls parsed)
  pure (foldr apply source (sortOn (\(start, _, _) -> start) (rename : imports : exports ++ edits)))
  where
    apply (start, end, replacement) remaining =
      take start remaining ++ replacement ++ drop end remaining
    range (RealSrcSpan span _) = Right
      (offset (srcSpanStartLine span) (srcSpanStartCol span),
       offset (srcSpanEndLine span) (srcSpanEndCol span))
    range _ = Left "Handler source has no concrete location"
    replace location replacement = do
      (start, end) <- range location
      pure (start, end, replacement)
    offset line column =
      sum (map ((+ 1) . length) (take (line - 1) (lines source)))
      + columnOffset 1 column (lines source !! (line - 1))
    columnOffset current target remaining
      | current >= target = 0
      | otherwise = case remaining of
          [] -> 0
          character : rest -> 1 + columnOffset
            (if character == '\t' then current + 8 - (current - 1) `mod` 8 else current + 1)
            target rest
    instanceEdits (L _ (InstD _ (ClsInstD _ instanceDeclaration))) =
      case className (sig_body (unLoc (cid_poly_ty instanceDeclaration))) of
        Just selected -> do
          carrier <- carrierText (sig_body (unLoc (cid_poly_ty instanceDeclaration)))
          concat <$> mapM (methodEdits selected carrier) (cid_binds instanceDeclaration)
        Nothing -> pure []
    instanceEdits _ = pure []
    className located = case unLoc located of
      HsQualTy { hst_body = body } -> className body
      HsForAllTy { hst_body = body } -> className body
      HsParTy _ body -> className body
      HsAppTy _ function _ -> className function
      HsTyVar _ _ identifier -> Just (occNameString (rdrNameOcc (unLoc identifier)))
      _ -> Nothing
    -- instance 头的载体实参原文（通常是 m）；生成副本据此给局部绑定写出签名。
    carrierText located = case unLoc located of
      HsQualTy { hst_body = body } -> carrierText body
      HsForAllTy { hst_body = body } -> carrierText body
      HsParTy _ body -> carrierText body
      HsAppTy _ _ argument -> do
        (start, end) <- range (getLocA argument)
        pure (take (end - start) (drop start source))
      _ -> Left "Registered instance head must apply the effect class to its carrier"
    methodEdits :: String -> String -> LHsBind GhcPs -> Either String [(Int, Int, String)]
    methodEdits selected carrier binding@(L _ FunBind { fun_id = identifier }) = do
      let method = occNameString (rdrNameOcc (unLoc identifier))
      case [(wrapper, result) | (owner, entry, wrapper, result) <- wrappers, owner == selected, entry == method] of
        [] -> pure []
        [(wrapper, result)] -> do
          (start, end) <- range (getLocA binding)
          let RealSrcSpan span _ = getLocA binding
              indentation = srcSpanStartCol span - 1
              original = take (end - start) (drop start source)
              originalLines = case lines original of
                [] -> []
                first : rest -> first : map (\line -> drop (columnOffset 1 (indentation + 1) line) line) rest
              indent extra = replicate (indentation + extra) ' '
              -- 完整签名使局部绑定按 instance 上下文检查，不被泛化后经泛型 instance 改写约束。
              wrapped = method ++ " =\n" ++ unlines [indent 2 ++ line | line <- lines (wrapper ++ " $")]
                ++ indent 4 ++ "let\n"
                ++ indent 6 ++ method ++ " :: (" ++ carrier ++ ") (" ++ result ++ ")\n"
                ++ unlines [indent 6 ++ line | line <- originalLines]
                ++ indent 4 ++ "in " ++ method
          pure [(start, end, wrapped)]
        _ -> Left ("Duplicate handler registration: " ++ selected ++ "." ++ method)
    methodEdits _ _ _ = pure []
