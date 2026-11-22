{-# LANGUAGE ScopedTypeVariables #-}

-- 用 GHC 加载并类型检查业务模块与本次契约，检查顶层定义与 Types 的固定形式，并给出源码资产目录。
-- 生成的 Program／Prototype／Handlers 与手写 Main 不在这里编译：它们只是普通 Haskell，类型错误由构建报告；
-- 手写 Handlers 已在读取方法体时用同一契约检查过。只读取 GHC 已解析的名字和类型；不执行 handler。
module Framework.Gen.Check.Assets (checkAssets) where

import Control.Monad (forM, unless)
import Data.Foldable (toList)
import Data.Maybe (isJust)
import Control.Monad.IO.Class (liftIO)
import Data.List (intercalate, isInfixOf, isPrefixOf, nub, sortOn, stripPrefix)
import Framework.Gen.Check.TopLevel (checkMainSource, checkTopLevel)
import Framework.Gen.Frontend.Ghc (modulePath, sourceDirectory, withSourceTargets)
import Framework.Gen.Frontend.Source (parseSourceFile)
import qualified Framework.Language.Registration as R
import Framework.Prototype.Catalog
import GHC
import GHC.Core.DataCon (dataConName, dataConOrigArgTys)
import GHC.Core.TyCon (isAlgTyCon, synTyConRhs_maybe, tyConDataCons, tyConFieldLabels, tyConName)
import GHC.Core.TyCo.FVs (tyConsOfType)
import GHC.Core.TyCo.Rep (scaledThing)
import GHC.Data.FastString (unpackFS)
import GHC.Hs
import GHC.Types.FieldLabel (flSelector)
import GHC.Types.Name (nameModule_maybe, nameOccName, nameSrcSpan)
import GHC.Types.Name.Reader (rdrNameOcc)
import GHC.Types.Name.Occurrence (occNameString)
import GHC.Types.Unique.Set (nonDetEltsUniqSet)
import GHC.Unit.Module (moduleNameString, moduleUnit, unitString)
import GHC.Utils.Outputable (ppr, showSDocUnsafe)
import System.Directory (doesDirectoryExist, doesFileExist, listDirectory)
import System.FilePath (normalise, takeExtension)
import Text.Read (readMaybe)

-- 新契约只作为内存 target；检查失败不改写 Generated。
-- roots 是资产的表示类型，contracts 是生成的资产类型；二者组成资产目录。
-- earlier 是此前阶段已得出的顶层检查失败（手写 Handlers），与这里的失败一起报告。
checkAssets :: String -> String -> [R.TypeRef] -> [String] -> [String] -> IO [Asset]
checkAssets namespace effects roots contracts earlier = do
  sourceDir <- sourceDirectory
  files <- sourceFiles (modulePath sourceDir namespace)
  let mainFile = modulePath sourceDir (namespace ++ ".Main") ++ ".hs"
  hasMain <- doesFileExist mainFile
  mainFailures <- if hasMain then checkMainSource namespace . snd <$> parseSourceFile mainFile else pure []
  withSourceTargets $ \memoryTarget -> do
    let rootModule = namespace ++ ".Generated.AssetRoots"
        rootSource = unlines $
          ["{-# LANGUAGE DataKinds, TypeOperators, TypeFamilies #-}"
          , "module " ++ rootModule ++ " where", "import " ++ namespace ++ ".Types"
          , "import qualified " ++ namespace ++ ".Generated.Effects as GeneratedContracts"]
          ++ ["type AssetRoot" ++ show index ++ " = " ++ R.contractName root
               | (index, root) <- zip [0 :: Int ..] roots]
          ++ ["type GeneratedContract" ++ show index ++ " = GeneratedContracts." ++ contract
               | (index, contract) <- zip [0 :: Int ..] contracts]
        selectedFiles = [path | path <- files
          , normalise path `notElem` map normalise [modulePath sourceDir (namespace ++ ".Handlers") ++ ".hs", mainFile]]
    diskTargets <- mapM (\path -> guessTarget path Nothing Nothing) selectedFiles
    setTargets (memoryTarget rootModule rootSource : memoryTarget (namespace ++ ".Generated.Effects") effects : diskTargets)
    result <- load LoadAllTargets
    case result of
      Failed -> liftIO (ioError (userError "Cannot load the business modules and contracts; fix the native Haskell diagnostics above"))
      Succeeded -> pure ()
    graph <- getModuleGraph
    let summaries = mgModSummaries graph
        business summary = let selected = moduleNameString (moduleName (ms_mod summary))
          in not ("Framework." `isPrefixOf` selected || ".Generated." `isInfixOf` selected)
    checked <- forM (filter business summaries) $ \summary -> do
      parsed <- parseModule summary
      typecheckModule parsed
    -- 资产目录写出定义位置：模块可能从接口缓存加载（名字不带源码位置），
    -- 所以资产一律换成本次类型检查得到的定义；生成的契约模块同样检查一次。
    contractsChecked <- forM [summary | summary <- summaries
        , moduleNameString (moduleName (ms_mod summary)) == namespace ++ ".Generated.Effects"] $ \summary ->
      typecheckModule =<< parseModule summary
    rootSummary <- getModSummary (mkModuleName rootModule)
    rootInfo <- getModuleInfo (ms_mod rootSummary)
    let localTypes = [constructor | checkedModule <- checked
          , ATyCon constructor <- modInfoTyThings (tm_checked_module_info checkedModule)]
        rootAliases prefix = [(index, body) | Just info <- [rootInfo], ATyCon alias <- modInfoTyThings info
          , Just index <- [stripPrefix prefix (occNameString (nameOccName (tyConName alias))) >>= readMaybe]
          , Just body <- [synTyConRhs_maybe alias]]
        rootTypes = [constructor | (_ :: Int, body) <- rootAliases "AssetRoot", constructor <- typeConstructors body]
        generatedTypes = [constructor | (_ :: Int, body) <- rootAliases "GeneratedContract"
          , constructor <- typeConstructors body, isAlgTyCon constructor, constructor `notElem` localTypes]
        located = localTypes ++ [constructor | checkedModule <- contractsChecked
          , ATyCon constructor <- modInfoTyThings (tm_checked_module_info checkedModule)]
        definitionOf constructor = case [found | found <- located, found == constructor] of
          found : _ -> found
          [] -> constructor
        assets = nub (map definitionOf (assetClosure localTypes rootTypes ++ generatedTypes))
        typesModule = [checkedModule | checkedModule <- checked
          , moduleNameString (moduleName (ms_mod (pm_mod_summary (tm_parsed_module checkedModule)))) == namespace ++ ".Types"]
        failures = earlier ++ mainFailures ++ concatMap (checkTopLevel namespace) checked
          ++ concatMap (checkFixedForm roots) typesModule
    unless (null failures) $
      liftIO (ioError (userError (intercalate "\n" failures)))
    pure (sortOn assetType (map describeAsset assets))

sourceFiles :: FilePath -> IO [FilePath]
sourceFiles directory = do
  names <- sortOn id <$> listDirectory directory
  concat <$> forM names (\name -> do
    let path = directory ++ "/" ++ name
    nested <- doesDirectoryExist path
    if nested then if name == "Generated" then pure [] else sourceFiles path
      else pure [path | takeExtension path == ".hs"])

typeConstructors :: Type -> [TyCon]
typeConstructors = nonDetEltsUniqSet . tyConsOfType

-- 只沿业务定义展开；String、Handle 等库类型不因成为字段而被占有。
assetClosure :: [TyCon] -> [TyCon] -> [TyCon]
assetClosure local roots = expand [] (filter (`elem` local) roots)
  where
    expand seen [] =
      let aliases = [alias | alias <- local, alias `notElem` seen
            , Just body <- [synTyConRhs_maybe alias]
            , any (`elem` seen) (typeConstructors body)]
      in if null aliases then seen else expand seen aliases
    expand seen (selected : rest)
      | selected `elem` seen = expand seen rest
      | otherwise = expand (selected : seen)
          (rest ++ filter (`elem` local) (concatMap typeConstructors (contents selected)))
    contents selected = case synTyConRhs_maybe selected of
      Just body -> [body]
      Nothing | isAlgTyCon selected ->
        [scaledThing field | constructor <- tyConDataCons selected, field <- dataConOrigArgTys constructor]
      _ -> []

describeAsset :: TyCon -> Asset
describeAsset selected = Asset (describeName (tyConName selected))
  (if isAlgTyCon selected then map (describeName . dataConName) (tyConDataCons selected) else [])
  (if isAlgTyCon selected then map (describeName . flSelector) (tyConFieldLabels selected) else [])

describeName :: Name -> AssetSymbol
describeName name = AssetSymbol
  (maybe "" (moduleNameString . moduleName) (nameModule_maybe name))
  (occNameString (nameOccName name)) file line column
  where
    (file, line, column) = case nameSrcSpan name of
      RealSrcSpan location _ -> (map slash (unpackFS (srcSpanFile location)), srcSpanStartLine location, srcSpanStartCol location)
      _ -> ("", 0, 0)
    slash '\\' = '/'
    slash character = character

-- 资产固定形式 v1（2026-11-21）：资产都是由 String 构造的值，LSP 据此把 before-gen 的声明唯一地转换成 DTO。
-- Types.hs 只写单构造器的 data／newtype：至少一个字段，字段类型只能是 String、[String] 或本模块的另一个表示类型，
-- 固定 deriving (Eq, Show)；没有 import、instance、类型同义词、类型参数、GADT 语法、严格标记和中缀构造器，
-- 导出全部类型及构造器。资产的表示类型（Asset @T）只能是 String、[String] 或本模块的类型。
-- 文件句柄等原生对象只在 handler 自己的执行中持有，不进入资产。
-- 资产的表示类型来自注册的 Typeable：FilePath 等 String 的同义词与 String 无法区分，这里按 String 接受。
checkFixedForm :: [R.TypeRef] -> TypecheckedModule -> [String]
checkFixedForm roots checked =
  [ at (getLocA located) ++ "Types.hs must not import modules; asset fields are String, [String] or types of this module"
  | located <- hsmodImports parsed ]
  ++ exportFailures
  ++ concatMap declaration (hsmodDecls parsed)
  ++ [ "Asset representation " ++ registeredName root ++ " must be String, [String] or a type defined in "
       ++ moduleNameString (moduleName typesModule) ++ "; imports and re-exports retain the defining type"
     | root <- roots, not (validRoot root) ]
  where
    parsed = unLoc (pm_parsed_source (tm_parsed_module checked))
    localNames = [occNameString (rdrNameOcc (unLoc name)) | L _ (TyClD _ DataDecl { tcdLName = name }) <- hsmodDecls parsed]
    typesModule = ms_mod (pm_mod_summary (tm_parsed_module checked))
    owner = (unitString (moduleUnit typesModule), moduleNameString (moduleName typesModule))
    validRoot (R.TypeRef name Nothing) = name == "[Char]" || name == "[[Char]]"
    validRoot (R.TypeRef name (Just origin)) = origin == owner && name `elem` localNames
    validRoot R.OutputRef{} = False
    registeredName (R.TypeRef name (Just (unit, definingModule))) = unit ++ ":" ++ definingModule ++ "." ++ name
    registeredName root = R.contractName root
    exportFailures = case hsmodExports parsed of
      Nothing -> []
      Just (L location exported) ->
        let entries = [compact (showSDocUnsafe (ppr entry)) | entry <- exported]
            complete = [name ++ "(..)" | name <- localNames]
        in [ at (locA location) ++ "Types.hs must export every type with all constructors, e.g. T(..), or omit the export list"
           | not (all (`elem` complete) entries && all (`elem` entries) complete) ]
    declaration :: LHsDecl GhcPs -> [String]
    declaration (L location item) = case item of
      TyClD _ DataDecl { tcdLName = name, tcdTyVars = variables, tcdDataDefn = definition } ->
        let typeName = occNameString (rdrNameOcc (unLoc name))
            constructors = toList (dd_cons definition)
            derived = [compact (showSDocUnsafe (ppr clause)) | clause <- dd_derivs definition]
        in [ at (locA location) ++ typeName ++ " has type parameters; asset types have none"
           | not (null (hsq_explicit variables)) ]
           ++ [ at (locA location) ++ typeName ++ " must have exactly one constructor; alternatives are decided by effects, not by sum types"
              | length constructors /= 1 ]
           ++ concatMap (constructorFailures typeName) constructors
           ++ [ at (locA location) ++ typeName ++ " must derive exactly (Eq, Show)"
              | derived `notElem` [["deriving(Eq,Show)"], ["deriving(Show,Eq)"]] ]
      _ -> [ at (locA location) ++ "only single-constructor data and newtype declarations are allowed in Types.hs; found "
             ++ takeWhile (/= '\n') (showSDocUnsafe (ppr item)) ]
    constructorFailures :: String -> LConDecl GhcPs -> [String]
    constructorFailures typeName (L location constructor) = case constructor of
      ConDeclH98 { con_args = arguments, con_ex_tvs = existentials, con_mb_cxt = context } ->
        [ at (locA location) ++ typeName ++ " uses existential variables or a context" | not (null existentials) || isJust context ]
        ++ case arguments of
          PrefixCon _ fields -> fieldFailures [hsScaledThing field | field <- fields]
          RecCon (L _ fields) -> fieldFailures [cd_fld_type field | L _ field <- fields]
          InfixCon _ _ -> [at (locA location) ++ typeName ++ " uses an infix constructor; write it in prefix form"]
      _ -> [at (locA location) ++ typeName ++ " uses GADT syntax; write a single prefix or record constructor"]
      where
        fieldFailures :: [LHsType GhcPs] -> [String]
        fieldFailures [] = [at (locA location) ++ typeName ++ " has no field; an asset is built from String values"]
        fieldFailures fields =
          [ at (getLocA field) ++ typeName ++ " has field type " ++ text
              ++ "; fields are String, [String] or a type of this module, without strictness marks"
          | field <- fields, let text = compact (showSDocUnsafe (ppr field))
          , text `notElem` ("String" : "[String]" : localNames) ]
    compact = filter (/= ' ')
    at location = showSDocUnsafe (ppr location) ++ ": "
