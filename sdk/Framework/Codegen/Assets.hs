{-# LANGUAGE ScopedTypeVariables #-}

-- 只检查源码的显式名称引用。GHC 负责名称解析；不从推导出的实参类型传播资产。
module Framework.Codegen.Assets (checkAssets) where

import Control.Monad (forM, unless)
import Control.Monad.IO.Class (liftIO)
import Data.Data (Data, cast, gmapQ)
import Data.List (intercalate, isInfixOf, isPrefixOf, nub, sortOn)
import Data.Time.Clock (getCurrentTime)
import Framework.Effect.Asset
import GHC
import GHC.Core.DataCon (dataConName, dataConOrigArgTys)
import GHC.Core.TyCon (isAlgTyCon, synTyConRhs_maybe, tyConDataCons, tyConFieldLabels, tyConName)
import GHC.Core.TyCo.FVs (tyConsOfType)
import GHC.Core.TyCo.Rep (scaledThing)
import GHC.Core.Type (isFunTy)
import GHC.Data.FastString (unpackFS)
import GHC.Data.StringBuffer (stringToStringBuffer)
import GHC.Driver.Backend (noBackend)
import GHC.Driver.Session (DynFlags(..), GhcLink(..))
import GHC.Hs
import GHC.Hs.Utils (CollectFlag(..), collectHsBindBinders)
import GHC.Tc.Utils.TcType (tcSplitSigmaTy)
import GHC.Types.FieldLabel (flSelector)
import GHC.Types.Name (nameModule_maybe, nameOccName, nameSrcSpan)
import GHC.Types.Name.Occurrence (occNameString)
import GHC.Types.Unique.Set (nonDetEltsUniqSet)
import GHC.Types.Var (Var, varName, varType)
import GHC.Unit.Module (moduleNameString)
import GHC.Utils.Outputable (ppr, showSDocUnsafe)
import System.Directory (doesDirectoryExist, listDirectory)
import System.FilePath ((</>), normalise, takeExtension, takeFileName)
import System.Process (readProcess)

-- 新契约及包装副本只作为内存 target；检查失败不改写 Generated。
-- 同时加载手写与生成模块，但不在同一业务导入链混入两份 instance。
checkAssets :: String -> [(String, String)] -> [String] -> [(String, String)]
            -> Maybe String -> IO String
checkAssets namespace generated roots methods native = do
  library <- takeWhile (`notElem` "\r\n") <$> readProcess "ghc" ["--print-libdir"] ""
  files <- sourceFiles (modulePath namespace)
  now <- getCurrentTime
  runGhc (Just library) $ do
    initial <- getSessionDynFlags
    logger <- getLogger
    packages <- liftIO (interpretPackageEnv logger initial)
    _ <- setSessionDynFlags packages
      { backend = noBackend, ghcLink = NoLink, importPaths = ["demo", "sdk"], verbosity = 0 }
    let memoryTarget moduleName source = Target
          { targetId = TargetFile (modulePath moduleName ++ ".hs") Nothing
          , targetAllowObjCode = False
          , targetUnitId = homeUnitId_ initial
          , targetContents = Just (stringToStringBuffer source, now)
          }
        rootModule = namespace ++ ".Generated.AssetRoots"
        rootSource = unlines $
          ["{-# LANGUAGE DataKinds, TypeOperators, TypeFamilies #-}"
          , "module " ++ rootModule ++ " where", "import " ++ namespace ++ ".Types"]
          ++ ["type AssetRoot" ++ show index ++ " = " ++ contract
               | (index, contract) <- zip [0 :: Int ..] roots]
        candidates = case native of
          Nothing -> filter ((== "Effects") . fst) generated
          Just _ -> generated
        selectedFiles = [path | path <- files
          , normalise path /= normalise (modulePath (namespace ++ ".Handlers") ++ ".hs")
          , native /= Nothing || takeFileName path /= "Main.hs"]
    diskTargets <- mapM (\path -> guessTarget path Nothing Nothing) selectedFiles
    setTargets (memoryTarget rootModule rootSource : diskTargets
      ++ [memoryTarget (namespace ++ ".Generated." ++ suffix) source | (suffix, source) <- candidates]
      ++ [memoryTarget (namespace ++ ".Handlers") source | Just source <- [native]])
    result <- load LoadAllTargets
    case result of
      Failed -> liftIO (ioError (userError "Cannot resolve asset references; fix the native Haskell diagnostics above"))
      Succeeded -> pure ()
    graph <- getModuleGraph
    let summaries = mgModSummaries graph
        business summary = let selected = moduleNameString (moduleName (ms_mod summary))
          in not ("Framework." `isPrefixOf` selected || ".Generated." `isInfixOf` selected)
    checked <- forM (filter business summaries) $ \summary -> do
      parsed <- parseModule summary
      typecheckModule parsed
    rootSummary <- getModSummary (mkModuleName rootModule)
    rootInfo <- getModuleInfo (ms_mod rootSummary)
    let localTypes = [constructor | checkedModule <- checked
          , ATyCon constructor <- modInfoTyThings (tm_checked_module_info checkedModule)]
        rootTypes = [constructor | Just info <- [rootInfo], ATyCon alias <- modInfoTyThings info
          , Just body <- [synTyConRhs_maybe alias], constructor <- typeConstructors body]
        assets = assetClosure localTypes rootTypes
        symbols = nub (concatMap assetNames assets)
        failures = concatMap (checkModule namespace methods symbols) checked
    unless (null failures) $ liftIO (ioError (userError (intercalate "\n" failures)))
    pure (renderAssets namespace (sortOn assetType (map describeAsset assets)))

modulePath :: String -> FilePath
modulePath selected = "demo" </> map (\c -> if c == '.' then '/' else c) selected

sourceFiles :: FilePath -> IO [FilePath]
sourceFiles directory = do
  names <- sortOn id <$> listDirectory directory
  concat <$> forM names (\name -> do
    let path = directory </> name
    nested <- doesDirectoryExist path
    if nested then if name == "Generated" then pure [] else sourceFiles path
      else pure [path | takeExtension path == ".hs"])

typeConstructors :: Type -> [TyCon]
typeConstructors = nonDetEltsUniqSet . tyConsOfType

-- 只沿业务定义展开；String、Handle 等库类型不因成为字段而被占有。
-- 别名双向补全，避免用 type Alias = Asset 绕过显式引用检查。
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

assetNames :: TyCon -> [Name]
assetNames selected = tyConName selected : if isAlgTyCon selected
  then map dataConName (tyConDataCons selected) ++ map flSelector (tyConFieldLabels selected)
  else []

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

-- 遍历 renamed source 的 Name；绝不遍历 typechecked expression 的推导类型。
-- 这样泛型方法收到 Asset 实参不会产生新的显式资产引用。
explicitNames :: Data value => value -> [Name]
explicitNames value
  | Just name <- cast value = [name]
  | otherwise = concat (gmapQ explicitNames value)

-- 类型检查仅用来区分局部函数绑定与局部数据绑定，包括无参 point-free 函数。
-- 不把这里得到的函数参数／返回类型当作资产引用。
functionBindings :: Data value => value -> [Name]
functionBindings value
  | Just (identifier :: Var) <- cast value =
      let (_, _, body) = tcSplitSigmaTy (varType identifier)
      in [varName identifier | isFunTy body]
  | Just (_ :: Type) <- cast value = []
  | otherwise = concat (gmapQ functionBindings value)

checkModule :: String -> [(String, String)] -> [Name] -> TypecheckedModule -> [String]
checkModule namespace methods assets checked = case tm_renamed_source checked of
  Nothing -> ["Asset checking requires renamed source"]
  Just (group, _, _, _, _) -> checkTop group
  where
    functions = nub (functionBindings (tm_typechecked_source checked))
    sourceModule = moduleNameString (moduleName (ms_mod (pm_mod_summary (tm_parsed_module checked))))
    isMethod owner name =
      (occNameString (nameOccName owner), occNameString (nameOccName name)) `elem` methods
      && fmap (moduleNameString . moduleName) (nameModule_maybe owner) == Just (namespace ++ ".Generated.Effects")
    reject :: Data value => SrcSpan -> value -> [String]
    reject location value = case nub (filter (`elem` assets) (explicitNames value)) of
      [] -> []
      found -> [showSDocUnsafe (ppr location) ++ ": ordinary definition explicitly uses effect asset(s): "
        ++ intercalate ", " [assetModule symbol ++ "." ++ assetName symbol | symbol <- map describeName found]
        ++ "; move this asset operation into a registered instance method (generic calls are allowed)"]
    checkTop :: HsGroup GhcRn -> [String]
    checkTop group = checkValues False (hs_valds group)
      ++ concatMap checkClasses (hs_tyclds group)
      ++ concat [reject (getLocA declaration) declaration | declaration <- hs_fords group]
      ++ concat [reject (getLocA declaration) declaration | declaration <- hs_ruleds group]
    checkClasses :: TyClGroup GhcRn -> [String]
    checkClasses group = concatMap checkInstance (group_instds group)
      ++ concatMap checkClass (group_tyclds group)
    checkClass :: LTyClDecl GhcRn -> [String]
    checkClass (L location ClassDecl {tcdSigs = signatures, tcdMeths = bindings}) =
      concatMap (reject (locA location)) signatures ++ concatMap (checkBinding False . unLoc) bindings
    checkClass _ = [] -- data/newtype/type 与 deriving 是合法契约声明。
    checkInstance :: LInstDecl GhcRn -> [String]
    checkInstance (L location (ClsInstD _ declaration)) =
      case className (sig_body (unLoc (cid_poly_ty declaration))) of
        Just owner | any ((== occNameString (nameOccName owner)) . fst) methods
          , fmap (moduleNameString . moduleName) (nameModule_maybe owner) == Just (namespace ++ ".Generated.Effects") ->
            concatMap (\binding -> case unLoc binding of
              FunBind {fun_id = identifier} | isMethod owner (unLoc identifier) -> localFunctions (unLoc binding)
              other -> checkBinding False other) (cid_binds declaration)
        _ -> reject (locA location) (cid_poly_ty declaration)
          ++ concatMap (reject (locA location)) (cid_sigs declaration)
          ++ concatMap (checkBinding False . unLoc) (cid_binds declaration)
    checkInstance _ = []
    checkValues :: Bool -> HsValBinds GhcRn -> [String]
    checkValues local bindings = case bindings of
      ValBinds _ values signatures -> check values signatures
      XValBindsLR (NValBinds groups signatures) -> check (concatMap snd groups) signatures
      where
        check values signatures = concatMap (checkBinding local . unLoc) values
          ++ concatMap (checkSignature local) signatures
    checkSignature :: Bool -> LSig GhcRn -> [String]
    checkSignature local signature@(L location value) = case value of
      TypeSig _ names _ | not local || any ((`elem` functions) . unLoc) names -> reject (locA location) signature
      TypeSig {} -> []
      _ -> reject (locA location) signature
    checkBinding :: Bool -> HsBind GhcRn -> [String]
    checkBinding False binding@FunBind {fun_id = identifier}
      | sourceModule == namespace ++ ".Effects", occNameString (nameOccName (unLoc identifier)) == "effects" =
          localFunctions binding -- 唯一注册声明允许 typeRef @Asset；不豁免其余 helper。
    checkBinding local binding
      | not local || any (`elem` functions) (collectHsBindBinders CollNoDictBinders binding) =
          reject (bindingLocation binding) binding
      | otherwise = localFunctions binding
    bindingLocation :: HsBind GhcRn -> SrcSpan
    bindingLocation FunBind {fun_id = identifier} = getLocA identifier
    bindingLocation PatBind {pat_lhs = pattern'} = getLocA pattern'
    bindingLocation _ = noSrcSpan
    localFunctions :: Data value => value -> [String]
    localFunctions value
      | Just (HsValBinds _ bindings :: HsLocalBinds GhcRn) <- cast value = checkValues True bindings
      | otherwise = concat (gmapQ localFunctions value)

className :: LHsType GhcRn -> Maybe Name
className located = case unLoc located of
  HsQualTy {hst_body = body} -> className body
  HsForAllTy {hst_body = body} -> className body
  HsParTy _ body -> className body
  HsAppTy _ function _ -> className function
  HsTyVar _ _ identifier -> Just (unLoc identifier)
  _ -> Nothing

renderAssets :: String -> [Asset] -> String
renderAssets namespace assets = unlines
  [ "-- 自动生成的源码资产目录；不包含业务值或 Context 来源，不参与运行时生命周期。"
  , "module " ++ namespace ++ ".Generated.Assets (generatedAssets) where"
  , ""
  , "import Framework.Effect.Asset (Asset(..), AssetSymbol(..))"
  , ""
  , "generatedAssets :: [Asset]"
  , "generatedAssets ="
  , if null assets then "  []" else "  [ " ++ intercalate "\n  , " (map renderAsset assets) ++ "\n  ]"
  ]
  where
    renderAsset asset = "Asset\n      { assetType = " ++ show (assetType asset)
      ++ "\n      , assetConstructors =" ++ symbols (assetConstructors asset)
      ++ "\n      , assetFields =" ++ symbols (assetFields asset)
      ++ "\n      }"
    symbols [] = " []"
    symbols values = "\n          [ " ++ intercalate "\n          , " (map show values) ++ "\n          ]"
