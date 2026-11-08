{-# LANGUAGE ScopedTypeVariables #-}

-- 用 GHC 加载并类型检查业务模块与新生成的副本，检查顶层定义，并给出源码资产目录。
-- 只读取 GHC 已解析的名字和类型；不执行 handler。
module Framework.Gen.Assets (checkAssets) where

import Control.Monad (forM, unless)
import Control.Monad.IO.Class (liftIO)
import Data.Data (Data, cast, gmapQ)
import Data.List (intercalate, isInfixOf, isPrefixOf, nub, sortOn, stripPrefix)
import Data.Time.Clock (getCurrentTime)
import Framework.Gen.Catalog
import GHC
import GHC.Core.DataCon (dataConName, dataConOrigArgTys)
import GHC.Core.TyCon (isAlgTyCon, synTyConRhs_maybe, tyConDataCons, tyConFieldLabels, tyConName)
import GHC.Core.TyCo.FVs (tyConsOfType)
import GHC.Core.TyCo.Rep (scaledThing)
import GHC.Core.Type (splitTyConApp_maybe)
import GHC.Data.FastString (unpackFS)
import GHC.Data.StringBuffer (stringToStringBuffer)
import GHC.Driver.Backend (noBackend)
import GHC.Driver.Session (DynFlags(..), GhcLink(..))
import GHC.Hs
import GHC.Hs.Utils (CollectFlag(..), collectHsBindBinders)
import GHC.Types.FieldLabel (flSelector)
import GHC.Types.Name (nameModule_maybe, nameOccName, nameSrcSpan)
import GHC.Types.Name.Occurrence (occNameString)
import GHC.Types.Unique.Set (nonDetEltsUniqSet)
import GHC.Types.Var (Var, varName, varType)
import GHC.Unit.Module (moduleNameString)
import GHC.Utils.Outputable (ppr, showSDocUnsafe)
import System.Directory (doesDirectoryExist, listDirectory)
import System.FilePath (normalise, takeExtension, takeFileName)
import System.Process (readProcess)
import Text.Read (readMaybe)

-- 新契约及副本只作为内存 target；检查失败不改写 Generated。
-- 同时加载手写与生成模块，但不在同一业务导入链混入两份 instance。
-- roots 是资产的表示类型，contracts 是生成的资产类型；二者组成资产目录。
checkAssets :: String -> [(String, String)] -> [String] -> [String] -> Maybe String -> IO String
checkAssets namespace generated roots contracts native = do
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
          , "module " ++ rootModule ++ " where", "import " ++ namespace ++ ".Types"
          , "import qualified " ++ namespace ++ ".Generated.Effects as GeneratedContracts"]
          ++ ["type AssetRoot" ++ show index ++ " = " ++ contract
               | (index, contract) <- zip [0 :: Int ..] roots]
          ++ ["type GeneratedContract" ++ show index ++ " = GeneratedContracts." ++ contract
               | (index, contract) <- zip [0 :: Int ..] contracts]
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
      Failed -> liftIO (ioError (userError "Cannot load the business and generated modules; fix the native Haskell diagnostics above"))
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
        rootAliases prefix = [(index, body) | Just info <- [rootInfo], ATyCon alias <- modInfoTyThings info
          , Just index <- [stripPrefix prefix (occNameString (nameOccName (tyConName alias))) >>= readMaybe]
          , Just body <- [synTyConRhs_maybe alias]]
        rootTypes = [constructor | (_ :: Int, body) <- rootAliases "AssetRoot", constructor <- typeConstructors body]
        generatedTypes = [constructor | (_ :: Int, body) <- rootAliases "GeneratedContract"
          , constructor <- typeConstructors body, isAlgTyCon constructor, constructor `notElem` localTypes]
        assets = nub (assetClosure localTypes rootTypes ++ generatedTypes)
        failures = concatMap (checkTopLevel namespace) checked
    unless (null failures) $
      liftIO (ioError (userError (intercalate "\n" failures)))
    pure (renderAssets namespace (sortOn assetType (map describeAsset assets)))

modulePath :: String -> FilePath
-- 统一用正斜杠：Windows 下 </> 插入的反斜杠会在 GHC 记录文件名时丢失，资产目录的路径因此出错。
modulePath selected = "demo/" ++ map (\c -> if c == '.' then '/' else c) selected

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

data ModuleRole = EffectsModule | WorkflowModule | MainModule | OtherModule deriving Eq

-- 业务模块的顶层只允许类型声明、instance，以及固定的注册、workflow 与入口值：
-- Effects 的 effects，AST 与 Workflow 模块中类型为 AST 的命名 workflow，Main 的 main。
-- 顶层普通函数一律拒绝：值操作写在 handler 方法体内，经注册进入 effect 链，才能被静态分析。
-- 方法体内的局部函数与 lambda 不受限制。
checkTopLevel :: String -> TypecheckedModule -> [String]
checkTopLevel namespace checked = case tm_renamed_source checked of
  Nothing -> ["Top-level checking requires renamed source"]
  Just (group, _, _, _, _) ->
    [ at (getLocA binding) ++ "top-level definition " ++ occNameString (nameOccName binder) ++ " is not allowed in "
        ++ sourceModule ++ "; " ++ advice
    | binding <- topBindings (hs_valds group)
    , binder <- collectHsBindBinders CollNoDictBinders (unLoc binding), not (allowed binder) ]
    ++ [ at (getLocA declaration) ++ "class declaration " ++ occNameString (nameOccName (unLoc (tcdLName (unLoc declaration))))
          ++ " is not allowed in " ++ sourceModule ++ "; handler classes are generated from registrations"
       | classes <- hs_tyclds group, declaration@(L _ ClassDecl {}) <- group_tyclds classes ]
    ++ [ at (getLocA declaration) ++ "foreign declaration is not allowed in " ++ sourceModule
       | declaration <- hs_fords group ]
    ++ [ at (getLocA declaration) ++ "rewrite rule is not allowed in " ++ sourceModule
       | declaration <- hs_ruleds group ]
  where
    sourceModule = moduleNameString (moduleName (ms_mod (pm_mod_summary (tm_parsed_module checked))))
    role
      | sourceModule == namespace ++ ".Effects" = EffectsModule
      | sourceModule == namespace ++ ".Main" = MainModule
      | sourceModule == namespace ++ ".AST" || (namespace ++ ".Workflow.") `isPrefixOf` sourceModule = WorkflowModule
      | otherwise = OtherModule
    allowed binder = case role of
      EffectsModule -> occNameString (nameOccName binder) == "effects"
      MainModule -> occNameString (nameOccName binder) == "main"
      WorkflowModule -> any (workflowType . snd) (filter ((== binder) . fst) typed)
      OtherModule -> False
    advice = case role of
      EffectsModule -> "Effects.hs defines only effects; local helpers may stay in its where clause"
      WorkflowModule -> "workflow modules define only named AST values"
      MainModule -> "Main.hs defines only main"
      OtherModule -> "write value operations inside handler methods (local functions there are fine)"
    workflowType selected = case splitTyConApp_maybe selected of
      Just (constructor, []) -> fmap (moduleNameString . moduleName) (nameModule_maybe (tyConName constructor))
        == Just "Framework.Language.AST"
      _ -> False
    typed = typedVariables (tm_typechecked_source checked)
    at location = showSDocUnsafe (ppr location) ++ ": "

topBindings :: HsValBinds GhcRn -> [LHsBind GhcRn]
topBindings bindings = case bindings of
  ValBinds _ values _ -> values
  XValBindsLR (NValBinds groups _) -> concatMap snd groups

-- 类型检查后的绑定名与其类型；不遍历类型本身。
typedVariables :: Data value => value -> [(Name, Type)]
typedVariables value
  | Just (identifier :: Var) <- cast value = [(varName identifier, varType identifier)]
  | Just (_ :: Type) <- cast value = []
  | otherwise = concat (gmapQ typedVariables value)

renderAssets :: String -> [Asset] -> String
renderAssets namespace assets = unlines
  [ "-- 自动生成的源码资产目录；不包含业务值或 Context 来源，不参与运行时生命周期。"
  , "module " ++ namespace ++ ".Generated.Assets (generatedAssets) where"
  , ""
  , "import Framework.Gen.Catalog (Asset(..), AssetSymbol(..))"
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
