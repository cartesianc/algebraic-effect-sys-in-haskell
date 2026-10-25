-- 保留原生 Haskell 方法体；只解析模块和方法边界，添加注册声明的入口包装。
module Framework.Codegen.Handlers (renderHandlers) where

import Control.Exception (evaluate)
import Control.Monad.IO.Class (liftIO)
import Data.List (sortOn)
import GHC (GhcPs, getSessionDynFlags, runGhc)
import GHC.Data.FastString (mkFastString)
import GHC.Data.StringBuffer (stringToStringBuffer)
import GHC.Driver.Config.Parser (initParserOpts)
import GHC.Driver.Session (parseDynamicFilePragma)
import GHC.Hs
import qualified GHC.Parser as Parser
import GHC.Parser.Annotation (getLocA)
import GHC.Parser.Header (getOptions)
import GHC.Parser.Lexer (ParseResult(..), initParserState, unP)
import GHC.Types.Name.Occurrence (occNameString)
import GHC.Types.Name.Reader (rdrNameOcc)
import GHC.Types.SrcLoc
import System.Directory (doesFileExist)
import System.FilePath ((</>), pathSeparator)
import System.IO (IOMode(ReadMode), hGetContents, hSetEncoding, utf8, withFile)
import System.Process (readProcess)

-- 包装计划来自注册；原文件始终保留，只有 Generated 副本进入运行导入链。
renderHandlers :: String -> [(String, String, String)] -> String -> IO String
renderHandlers namespace wrappers scopeHandlers = do
  let directory = "demo" </> map (\c -> if c == '.' then pathSeparator else c) namespace
      inputPath = directory </> "Handlers.hs"
      generatedName = namespace ++ ".Generated.Handlers"
  exists <- doesFileExist inputPath
  generated <- if not exists
    then pure $ if null scopeHandlers
      then "module " ++ generatedName ++ " () where\n"
      else "module " ++ generatedName ++ " (newScopeHandlers) where\n"
        ++ "import qualified Framework.SDK as FrameworkRuntime\n"
        ++ "import qualified " ++ namespace ++ ".Generated.Effects as FrameworkGenerated\n"
    else do
      source <- withFile inputPath ReadMode $ \handle -> do
        hSetEncoding handle utf8
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
          POk _ parsed -> liftIO $ either (ioError . userError) pure
            (wrapModule namespace generatedName wrappers (not (null scopeHandlers)) source (unLoc parsed))
  pure ("-- 自动生成的编译副本；请修改上级 Handlers.hs 后重新生成。\n"
        ++ "{-# LANGUAGE TypeApplications #-}\n"
        ++ generated ++ if null scopeHandlers then "" else "\n\n" ++ scopeHandlers)

wrapModule
  :: String -> String -> [(String, String, String)] -> Bool -> String -> HsModule GhcPs
  -> Either String String
wrapModule namespace generatedName wrappers hasScopes source parsed = do
  moduleName <- maybe (Left "Handlers.hs must declare its module") Right (hsmodName parsed)
  rename <- replace (getLocA moduleName) generatedName
  exports <- case hsmodExports parsed of
    Just names | hasScopes -> do
      (start, _) <- range (getLocA names)
      pure [(start + 1, start + 1, "newScopeHandlers" ++ if null (unLoc names) then "" else ", ")]
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
        Just selected -> concat <$> mapM (methodEdits selected) (cid_binds instanceDeclaration)
        Nothing -> pure []
    instanceEdits _ = pure []
    className located = case unLoc located of
      HsQualTy { hst_body = body } -> className body
      HsForAllTy { hst_body = body } -> className body
      HsParTy _ body -> className body
      HsAppTy _ function _ -> className function
      HsTyVar _ _ identifier -> Just (occNameString (rdrNameOcc (unLoc identifier)))
      _ -> Nothing
    methodEdits :: String -> LHsBind GhcPs -> Either String [(Int, Int, String)]
    methodEdits selected binding@(L _ FunBind { fun_id = identifier }) = do
      let method = occNameString (rdrNameOcc (unLoc identifier))
      case [wrapper | (owner, entry, wrapper) <- wrappers, owner == selected, entry == method] of
        [] -> pure []
        [wrapper] -> do
          (start, end) <- range (getLocA binding)
          let RealSrcSpan span _ = getLocA binding
              indentation = srcSpanStartCol span - 1
              original = take (end - start) (drop start source)
              originalLines = case lines original of
                [] -> []
                first : rest -> first : map (\line -> drop (columnOffset 1 (indentation + 1) line) line) rest
              indent extra = replicate (indentation + extra) ' '
              wrapped = method ++ " =\n" ++ unlines [indent 2 ++ line | line <- lines (wrapper ++ " $")]
                ++ indent 4 ++ "let\n"
                ++ unlines [indent 6 ++ line | line <- originalLines]
                ++ indent 4 ++ "in " ++ method
          pure [(start, end, wrapped)]
        _ -> Left ("Duplicate handler registration: " ++ selected ++ "." ++ method)
    methodEdits _ _ = pure []
