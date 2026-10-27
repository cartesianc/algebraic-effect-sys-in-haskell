{-# LANGUAGE ScopedTypeVariables #-}

-- 只检查源码的显式名称引用。GHC 负责名称解析；不从推导出的实参类型传播资产。
module Framework.Codegen.Assets (checkAssets) where

import Control.Monad (forM, unless)
import Control.Monad.IO.Class (liftIO)
import Data.Data (Data, cast, gmapQ)
import Data.List (intercalate, isInfixOf, isPrefixOf, isSuffixOf, nub, sortOn, stripPrefix)
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
import Text.Read (readMaybe)

-- 新契约及包装副本只作为内存 target；检查失败不改写 Generated。
-- 同时加载手写与生成模块，但不在同一业务导入链混入两份 instance。
-- owners 列出 Context 产物类型、其生产方的类，以及该类型是否由生成器产出（refine @T @(Gen "X")）：
-- 这些类型只能在生产方的方法中构造。
checkAssets :: String -> [(String, String)] -> [String] -> [(String, String)] -> [(String, String, Bool)]
            -> Maybe String -> IO String
checkAssets namespace generated roots methods owners native = do
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
          ++ ["type OwnedContract" ++ show index ++ " = " ++ (if generated then "GeneratedContracts." else "") ++ contract
               | (index, (contract, generated)) <- zip [0 :: Int ..] ownedTypes]
        ownedTypes = nub [(contract, generated) | (contract, _, generated) <- owners]
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
        rootAliases prefix = [(index, body) | Just info <- [rootInfo], ATyCon alias <- modInfoTyThings info
          , Just index <- [stripPrefix prefix (occNameString (nameOccName (tyConName alias))) >>= readMaybe]
          , Just body <- [synTyConRhs_maybe alias]]
        rootTypes = [constructor | (_ :: Int, body) <- rootAliases "AssetRoot", constructor <- typeConstructors body]
        -- 生成的契约类型也是资产：普通函数不得显式使用；它们不在业务模块中，单独并入。
        assets = nub (assetClosure localTypes rootTypes
          ++ [selected | (_, _, selected) <- ownedTyCons, selected `notElem` localTypes])
        symbols = nub (concatMap assetNames assets)
        -- 只约束业务模块中定义的代数类型；库类型没有可归属的业务构造器。
        ownership = Ownership
          { ownedConstructors =
              [ (dataConName constructor, (contract, classes))
              | (contract, classes, selected) <- ownedTyCons, constructor <- tyConDataCons selected ]
          , ownedFields =
              [ (flSelector field, (contract, classes))
              | (contract, classes, selected) <- ownedTyCons, field <- tyConFieldLabels selected ]
          }
        ownedTyCons =
          [ (contract, [owner | (produced, owner, _) <- owners, produced == contract], selected)
          | (index, body) <- rootAliases "OwnedContract", (contract, generated) <- take 1 (drop index ownedTypes)
          , selected <- typeConstructors body, generated || selected `elem` localTypes, isAlgTyCon selected ]
        failures = concatMap (checkModule namespace methods symbols ownership) checked
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

-- 产物类型的构造器与字段 → (类型名, 允许构造它的生产方类)。
data Ownership = Ownership
  { ownedConstructors :: [(Name, (String, [String]))]
  , ownedFields :: [(Name, (String, [String]))]
  }

-- 表达式位置出现的名字。模式中的构造器只是解构，不算构造；视图模式的表达式部分仍计入。
expressionNames :: Data value => value -> [Name]
expressionNames value
  | Just name <- cast value = [name]
  | Just (pattern' :: Pat GhcRn) <- cast value = patternExpressionNames pattern'
  | otherwise = concat (gmapQ expressionNames value)

patternExpressionNames :: Pat GhcRn -> [Name]
patternExpressionNames (ViewPat _ expression inner) =
  expressionNames expression ++ patternExpressionNames (unLoc inner)
patternExpressionNames pattern' = concat (gmapQ nestedPatterns pattern')
  where
    nestedPatterns :: Data value => value -> [Name]
    nestedPatterns value
      | Just (nested :: Pat GhcRn) <- cast value = patternExpressionNames nested
      | otherwise = concat (gmapQ nestedPatterns value)

-- 记录更新也会产生该类型的新值；只取被更新的字段名，不取右侧表达式。
updatedFields :: Data value => value -> [Name]
updatedFields value
  | Just (expression :: HsExpr GhcRn) <- cast value, RecordUpd {rupd_flds = fields} <- expression =
      labelNames fields ++ concat (gmapQ updatedFields value)
  | otherwise = concat (gmapQ updatedFields value)
  where
    labelNames :: Data value => value -> [Name]
    labelNames nested
      | Just name <- cast nested = [name]
      | Just (_ :: HsExpr GhcRn) <- cast nested = []
      | otherwise = concat (gmapQ labelNames nested)

checkModule :: String -> [(String, String)] -> [Name] -> Ownership -> TypecheckedModule -> [String]
checkModule namespace methods assets ownership checked = case tm_renamed_source checked of
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
              FunBind {fun_id = identifier} | isMethod owner (unLoc identifier) ->
                localFunctions (unLoc binding) ++ constructedElsewhere owner (unLoc binding)
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
    -- 构造器归属：Context 产物只能由其生产方的方法构造或通过记录更新产生；
    -- 其他 instance 只能模式匹配取用。只看显式引用，不追踪 coerce 或值流向。
    constructedElsewhere :: Name -> HsBind GhcRn -> [String]
    constructedElsewhere owner binding =
      [ showSDocUnsafe (ppr (bindingLocation binding)) ++ ": " ++ occNameString (nameOccName owner)
          ++ " " ++ how ++ " " ++ occNameString (nameOccName symbol) ++ " of Context product " ++ contract
          ++ "; only " ++ intercalate ", " (map effectName classes)
          ++ " may produce it (other instances may pattern match it)"
      | (how, symbol, (contract, classes)) <- nub (constructed ++ updated)
      , occNameString (nameOccName owner) `notElem` classes ]
      where
        updated = [("updates field", symbol, entry) | symbol <- updatedFields binding
          , Just entry <- [lookup symbol (ownedFields ownership)]]
        -- GHC 在名称解析时把记录更新展开为重建构造器的表达式；同一类型已按记录更新报告时不再重复。
        updatedContracts = [contract | (_, _, (contract, _)) <- updated]
        constructed = [("constructs", symbol, entry) | symbol <- expressionNames binding
          , Just entry@(contract, _) <- [lookup symbol (ownedConstructors ownership)]
          , contract `notElem` updatedContracts]
    effectName className
      | "Effect" `isSuffixOf` className = take (length className - length "Effect") className
      | otherwise = className
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
