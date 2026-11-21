-- GHC names identify branches before evaluating AST.ast erases their binding identity.
-- The same module load gives Hanging its target positions and the AST command its source outline.
module Framework.Gen.Frontend.Hanging (Outline(..), loadOutline) where

import Control.Exception (evaluate)
import Control.Monad (forM, unless)
import Control.Monad.IO.Class (liftIO)
import Data.Data (Data, cast, gmapQ)
import Data.List (isPrefixOf, sort, sortOn)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Framework.Gen.Frontend.Ghc (modulePath, sourceDirectory, withSourceTargets)
import Framework.Gen.Workflow (SourceRange(..), SourceSite(..))
import Framework.Language.AST (WorkflowF(..))
import qualified Framework.Language.Registration as R
import Framework.Recursion (Fix(..))
import GHC
import GHC.Builtin.Types (mkListTy, stringTy)
import GHC.Core.TyCon (isTypeSynonymTyCon, synTyConRhs_maybe)
import GHC.Core.TyCo.Compare (eqType)
import GHC.Unit.Types (unitString)
import Data.List (nub)
import Data.Maybe (catMaybes)
import GHC.Builtin.Names (dollarIdKey)
import GHC.Data.FastString (unpackFS)
import GHC.Types.Unique (getUnique)
import Data.Char (ord)
import Data.Word (Word8)
import Foreign.Marshal.Array (withArrayLen)
import GHC.Fingerprint (fingerprintData, fingerprintString)
import GHC.Hs
import GHC.Types.Name (nameModule_maybe, nameOccName)
import GHC.Types.Name.Occurrence (occNameString)
import System.Directory (doesFileExist)
import System.IO (IOMode(ReadMode), hGetContents, hSetEncoding, hSetNewlineMode, universalNewlineMode, utf8, withBinaryFile, withFile)

type Targets = [[(String, [[Int]])]]
type SourceChecks = [(FilePath, Maybe String)]

-- 一次加载 AST、Workflow 与可选的 Hanging 模块得到的源码事实；不需要注册或 handler。
data Outline = Outline
  { outlineHasHanging :: Bool
  , outlineTargets :: Targets              -- Hanging 各行目标的限定名与全部源码位置
  , outlineChecks :: SourceChecks          -- 生成的 Program 在运行前核对的 Hanging 输入指纹
  , outlineSites :: [SourceSite]           -- 从 ast 出发能从源码读出的每个位置
  , outlineSources :: [(FilePath, Maybe String)]  -- 每个已加载模块的 MD5（换行统一为 LF）；Hanging 不存在时为 Nothing
  -- 从源码直接读出的原样业务树与 Hanging 各行；写法超出显式 node／组合列表时为 Nothing，由调用方求值。
  , outlineTree :: Maybe (Fix WorkflowF, [([String], Int)])
  -- 注册中资产表示类型的写法到 TypeRef 的解析（只在请求时，按 Effects 模块的作用域）。
  , outlineTypes :: [(String, R.TypeRef)]
  }

-- types 给出注册里写的资产类型时，同一次加载也加载 Effects 模块并解析这些类型。
loadOutline :: String -> Maybe [String] -> IO Outline
loadOutline namespace types = do
  sourceDir <- sourceDirectory
  let hangingFile = modulePath sourceDir (hangingModule namespace) ++ ".hs"
  exists <- doesFileExist hangingFile
  withSourceTargets $ \_ -> do
    (definitions, checks) <- loadWorkflowModules sourceDir namespace exists
      [modulePath sourceDir (namespace ++ ".Effects") ++ ".hs" | Just _ <- [types]]
    root <- exported (astModule namespace) "ast"
    targets <- if exists then hangingTargets namespace definitions root else pure []
    sites <- either abort pure (outline (Map.map layoutOf definitions) root)
    hashes <- liftIO (mapM (\(path, _) -> (,) path . Just <$> sourceDigest path) checks)
    rows <- if exists
      then (\declaration -> syntacticRows definitions declaration) <$> exported (hangingModule namespace) "hangingTree"
      else pure (Just [])
    resolved <- maybe (pure []) (resolveTypes namespace) types
    let absent = [(hangingFile, Nothing) | not exists]
        tree = (,) <$> syntacticTree definitions root <*> rows
    -- 没有 Hanging 时 Program 只核对它仍不存在，与此前的生成结果一致。
    pure (Outline exists targets (if exists then checks else absent) sites (hashes ++ absent) tree resolved)

-- 原样业务树：node 的字面量、四种组合的显式列表与对命名分支的引用，与 toWorkflowF 求值的结果相同。
-- 其他写法（helper 计算、非显式列表、外部定义）返回 Nothing。
syntacticTree :: Map.Map Name (HsBind GhcRn) -> Name -> Maybe (Fix WorkflowF)
syntacticTree definitions = named Set.empty
  where
    named seen n
      | Set.member n seen = Nothing
      | otherwise = do
          binding <- Map.lookup n definitions
          body <- either (const Nothing) Just (singleBody binding)
          expression (Set.insert n seen) body
    expression seen e = case application e of
      (Just n, []) -> named seen n
      (Just n, [argument]) | ownerOf n == "Framework.Language.AST" ->
        let children = either (const Nothing) Just (list argument) >>= mapM (expression seen)
        in case spelling n of
          "node" -> Fix . Node <$> stringLiteral argument
          "chain" -> Fix . Chain <$> children
          "parallel" -> Fix . Parallel <$> children
          "alternative" -> Fix . Alternative <$> children
          "lifelong" -> Fix . Lifelong <$> children
          _ -> Nothing
      _ -> Nothing

-- Hanging 各行的 hook 与目标数，与 hangingRows 求值的结果相同。
syntacticRows :: Map.Map Name (HsBind GhcRn) -> Name -> Maybe [([String], Int)]
syntacticRows definitions declaration = do
  body <- Map.lookup declaration definitions >>= either (const Nothing) Just . singleBody
  entries <- either (const Nothing) Just (listArgument body)
  forM entries $ \entry -> case application entry of
    (Just n, [hooks, targets]) | qualified n == "Framework.Language.AST.middleware" -> do
      names <- either (const Nothing) Just (list hooks) >>= mapM hookName
      branches <- either (const Nothing) Just (list targets)
      pure (names, length branches)
    _ -> Nothing
  where
    hookName e = case application e of
      (Just n, [argument]) | qualified n == "Framework.Language.AST.node" -> stringLiteral argument
      _ -> Nothing

stringLiteral :: LHsExpr GhcRn -> Maybe String
stringLiteral e = case unparen e of
  HsLit _ (HsString _ text) -> Just (unpackFS text)
  _ -> Nothing

-- 与 typeRef 求值的结果相同：String（及其同义词）与 [String] 是内建表示，其余是定义模块中的 data／newtype。
-- 解析不了的写法（其他同义词、歧义名字）不给出，调用方改用求值。
resolveTypes :: String -> [String] -> Ghc [(String, R.TypeRef)]
resolveTypes namespace spellings = do
  -- 改名后的 Effects 模块给出注册里每个类型名的定义身份；不求值，也不需要解释执行。
  summary <- getModSummary (mkModuleName (namespace ++ ".Effects"))
  checked <- typecheckModule =<< parseModule summary
  let written = case tm_renamed_source checked of
        Just (group, _, _, _, _) -> nub (typeNames group)
        Nothing -> []
  fmap catMaybes $ forM (nub spellings) $ \spelled -> case spelled of
    "[String]" -> pure (Just (spelled, R.TypeRef "[[Char]]" Nothing))
    _ -> do
      let local = reverse (takeWhile (/= '.') (reverse spelled))
      things <- catMaybes <$> mapM lookupName [n | n <- written, spelling n == local]
      pure $ case [constructor | ATyCon constructor <- things] of
        [constructor] -> (,) spelled <$> refOf constructor
        _ -> Nothing
  where
    refOf constructor
      | isTypeSynonymTyCon constructor = case synTyConRhs_maybe constructor of
          Just rhs | rhs `eqType` stringTy -> Just (R.TypeRef "[Char]" Nothing)
                   | rhs `eqType` mkListTy stringTy -> Just (R.TypeRef "[[Char]]" Nothing)
          _ -> Nothing
      | otherwise = case nameModule_maybe (getName constructor) of
          Just owner -> Just (R.TypeRef (spelling (getName constructor))
            (Just (unitString (moduleUnit owner), moduleNameString (moduleName owner))))
          Nothing -> Nothing

-- 源码中写出的全部类型名（HsTyVar）。
typeNames :: Data a => a -> [Name]
typeNames x = case (cast x :: Maybe (HsType GhcRn)) of
  Just (HsTyVar _ _ n) -> [unLoc n]
  _ -> concat (gmapQ typeNames x)

loadWorkflowModules :: FilePath -> String -> Bool -> [FilePath] -> Ghc (Map.Map Name (HsBind GhcRn), SourceChecks)
loadWorkflowModules sourceDir namespace withHanging extra = do
  setTargets =<< mapM (\file -> guessTarget file Nothing Nothing)
    ([modulePath sourceDir (hangingModule namespace) ++ ".hs" | withHanging] ++ [modulePath sourceDir (astModule namespace) ++ ".hs"] ++ extra)
  result <- load LoadAllTargets
  case result of
    Failed -> abort (if withHanging then "Cannot load Hanging and AST modules" else "Cannot load AST modules")
    Succeeded -> pure ()
  graph <- getModuleGraph
  let moduleLabel summary = moduleNameString (moduleName (ms_mod summary))
      relevant summary = let name = moduleLabel summary
                         in (withHanging && name == hangingModule namespace) || workflowModule namespace name
  modules <- forM (sortOn moduleLabel (filter relevant (mgModSummaries graph))) $ \summary -> do
    checked <- typecheckModule =<< parseModule summary
    let name = moduleLabel summary
        path = modulePath sourceDir name ++ ".hs"
    signature <- liftIO (fingerprint path)
    case tm_renamed_source checked of
      Just (group, _, _, _, _) -> pure (bindings (hs_valds group), (path, Just signature))
      Nothing -> abort ("Missing renamed source for " ++ name)
  pure (Map.fromList (concatMap fst modules), map snd modules)
  where
    fingerprint path = withFile path ReadMode $ \file -> do
      hSetEncoding file utf8
      hSetNewlineMode file universalNewlineMode
      contents <- hGetContents file
      let value = show (fingerprintString contents)
      _ <- evaluate (length value)
      pure value

-- 源码文件 MD5（十六进制），取 CRLF 换成 LF 后的字节：与 Program 的指纹一样不随检出的换行方式变化。
-- 读取方用 hashlib.md5(data.replace(b"\r\n", b"\n")).hexdigest() 得到同一个值。
sourceDigest :: FilePath -> IO String
sourceDigest path = withBinaryFile path ReadMode $ \file -> do
  contents <- hGetContents file
  let bytes = map (fromIntegral . ord) (unix contents) :: [Word8]
  digest <- withArrayLen bytes (\count pointer -> fingerprintData pointer count)
  let value = show digest
  _ <- evaluate (length value)
  pure value
  where
    unix ('\r' : '\n' : rest) = '\n' : unix rest
    unix (character : rest) = character : unix rest
    unix [] = []

hangingTargets :: String -> Map.Map Name (HsBind GhcRn) -> Name -> Ghc Targets
hangingTargets namespace definitions root = do
  declaration <- exported (hangingModule namespace) "hangingTree"
  rows <- either abort pure $ do
    body <- maybe (Left "Define hangingTree in Hanging.hs") singleBody (Map.lookup declaration definitions)
    entries <- listArgument body
    mapM (targetsOf (workflowModule namespace)) entries
  let wanted = Set.fromList (concat rows)
  sites <- either abort pure (branchSites (Map.map layoutOf definitions) wanted root)
  pure [[(qualified n, sort (Map.findWithDefault [] n sites)) | n <- row] | row <- rows]

astModule, hangingModule :: String -> String
astModule namespace = namespace ++ ".AST"
hangingModule namespace = namespace ++ ".Hanging"

workflowModule :: String -> String -> Bool
workflowModule namespace name = name == astModule namespace || isPrefixOf (namespace ++ ".Workflow.") name

exported :: String -> String -> Ghc Name
exported owner local = do
  summary <- getModSummary (mkModuleName owner)
  info <- getModuleInfo (ms_mod summary)
  case [n | n <- maybe [] modInfoExports info, spelling n == local] of
    [n] -> pure n
    _ -> abort (owner ++ " must export " ++ local)

abort :: String -> Ghc a
abort = liftIO . ioError . userError

spelling :: Name -> String
spelling = occNameString . nameOccName

ownerOf :: Name -> String
ownerOf = maybe "" (moduleNameString . moduleName) . nameModule_maybe

qualified :: Name -> String
qualified n = ownerOf n ++ "." ++ spelling n

bindings :: HsValBinds GhcRn -> [(Name, HsBind GhcRn)]
bindings values =
  [(unLoc identifier, binding) | L _ binding@FunBind {fun_id = identifier} <- top]
  where top = case values of
          ValBinds _ bs _ -> bs
          XValBindsLR (NValBinds groups _) -> concatMap snd groups

singleBody :: HsBind GhcRn -> Either String (LHsExpr GhcRn)
singleBody FunBind {fun_matches = MG {mg_alts = L _ [L _ Match {m_grhss =
    GRHSs {grhssGRHSs = [L _ (GRHS _ [] body)], grhssLocalBinds = EmptyLocalBinds {}}}]}} = Right body
singleBody _ = Left "Expected a named declaration with one unconditional expression"

unparen :: LHsExpr GhcRn -> HsExpr GhcRn
unparen (L _ (HsPar _ expr)) = unparen expr
unparen (L _ (ExprWithTySig _ expr _)) = unparen expr
unparen expr = unLoc expr

variable :: LHsExpr GhcRn -> Maybe Name
variable expr = case unparen expr of
  HsVar _ name -> Just (unLoc name)
  _ -> Nothing

application :: LHsExpr GhcRn -> (Maybe Name, [LHsExpr GhcRn])
application expr = case unparen expr of
  HsApp _ fun arg -> append fun arg
  OpApp _ fun operator arg | Just op <- variable operator, getUnique op == dollarIdKey -> append fun arg
  _ -> (variable expr, [])
  where append fun arg = let (name, args) = application fun in (name, args ++ [arg])

list :: LHsExpr GhcRn -> Either String [LHsExpr GhcRn]
list expr = case unparen expr of
  ExplicitList _ xs -> Right xs
  _ -> Left "Use an explicit list in a Hanging declaration"

listArgument :: LHsExpr GhcRn -> Either String [LHsExpr GhcRn]
listArgument expr = case application expr of
  (Just n, [xs]) | qualified n == "Framework.Language.AST.hanging" -> list xs
  _ -> Left "Expected hanging [...] in Hanging.hs"

targetsOf :: (String -> Bool) -> LHsExpr GhcRn -> Either String [Name]
targetsOf permitted expr = case application expr of
  (Just n, [_, targets]) | qualified n == "Framework.Language.AST.middleware" -> list targets >>= mapM target
  _ -> Left "Expected middleware [nodes] [namedBranches] in Hanging.hs"
  where
    target expression | Just n <- variable expression, permitted (ownerOf n) = Right n
                      | otherwise = Left "A Hanging target must reference a named AST or Workflow branch; give the subtree a name"

-- A named alias does not add a path element. Unrelated Haskell computations need no interpretation.
-- Each structural expression keeps the source span where it is written.
data Layout = Children SrcSpan [Layout] | Reference Name | Opaque SrcSpan [Name]

layoutOf :: HsBind GhcRn -> Layout
layoutOf binding = either (const (Opaque noSrcSpan (uses binding))) descend (singleBody binding)
  where
    descend expr = case application expr of
      (Just n, []) -> Reference n
      (Just n, [arg]) | ownerOf n == "Framework.Language.AST" ->
        case spelling n of
          "node" -> Children (getLocA expr) []
          ctor | elem ctor ["chain","parallel","alternative","lifelong"], Right xs <- list arg -> Children (getLocA expr) (map descend xs)
          _ -> Opaque (getLocA expr) (uses expr)
      _ -> Opaque (getLocA expr) (uses expr)
    uses :: Data a => a -> [Name]
    uses x | Just (HsVar _ n) <- (cast x :: Maybe (HsExpr GhcRn)) = [unLoc n]
           | otherwise = concat (gmapQ uses x)

branchSites :: Map.Map Name Layout -> Set.Set Name -> Name -> Either String (Map.Map Name [[Int]])
branchSites layouts wanted root = Map.fromListWith (++) <$> walk Set.empty [] root
  where
    -- Only expand definitions that can reach a target. This preserves unrelated native expressions.
    parents = Map.fromListWith (++) [(child,[parent]) | (parent,layout) <- Map.toList layouts, child <- deps layout]
    closure seen [] = seen
    closure seen (n:ns) | Set.member n seen = closure seen ns
                        | otherwise = closure (Set.insert n seen) (Map.findWithDefault [] n parents ++ ns)
    relevant = closure Set.empty (Set.toList wanted)
    deps (Children _ xs) = concatMap deps xs
    deps (Reference n) = [n]
    deps (Opaque _ ns) = ns
    walk seen path n
      | Set.notMember n relevant = Right []
      | Set.member n seen = Left ("Cyclic workflow reference at " ++ qualified n)
      | otherwise = do
          layout <- maybe (Left ("Cannot locate named workflow " ++ qualified n)) Right (Map.lookup n layouts)
          nested <- visit (Set.insert n seen) path layout
          pure ([(n,[reverse path]) | Set.member n wanted] ++ nested)
    visit seen path (Reference n) = walk seen path n
    visit seen path (Children _ xs) = concat <$> sequence [visit seen (i:path) x | (i,x) <- zip [0..] xs]
    visit _ _ (Opaque _ ns) = do
      unless (all (flip Set.notMember relevant) ns) (Left "Cannot prove a Hanging target's location; compose named branches using explicit workflow child lists")
      pure []

-- Every position reachable from ast. A named reference adds its name at the same position;
-- an expression that is not an explicit node/branch is reported as unreadable, without children.
outline :: Map.Map Name Layout -> Name -> Either String [SourceSite]
outline layouts root = walk Set.empty [] [] root
  where
    walk seen path names n
      | Set.member n seen = Left ("Cyclic workflow reference at " ++ qualified n)
      | otherwise = case Map.lookup n layouts of
          Nothing -> Right [SourceSite path (names ++ [qualified n]) Nothing False]
          Just layout -> visit (Set.insert n seen) path (names ++ [qualified n]) layout
    visit seen path names layout = case layout of
      Reference n -> walk seen path names n
      Children span xs -> (SourceSite path names (range span) True :) . concat
        <$> sequence [visit seen (path ++ [index]) [] x | (index, x) <- zip [0 ..] xs]
      Opaque span _ -> Right [SourceSite path names (range span) False]
    range span = case span of
      RealSrcSpan real _ -> Just (SourceRange (map slash (unpackFS (srcSpanFile real)))
        (srcSpanStartLine real) (srcSpanStartCol real) (srcSpanEndLine real) (srcSpanEndCol real))
      _ -> Nothing
    slash c = if c == '\\' then '/' else c
