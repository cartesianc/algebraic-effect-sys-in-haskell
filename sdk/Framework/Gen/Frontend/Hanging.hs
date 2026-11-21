-- GHC names identify branches before evaluating AST.ast erases their binding identity.
-- The same module load gives Hanging its target positions and the AST command its source outline.
module Framework.Gen.Frontend.Hanging (loadHanging, loadOutline) where

import Control.Exception (evaluate)
import Control.Monad (forM, unless)
import Control.Monad.IO.Class (liftIO)
import Data.Data (Data, cast, gmapQ)
import Data.List (isPrefixOf, sort, sortOn)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Framework.Gen.Frontend.Ghc (modulePath, withSourceTargets)
import Framework.Gen.Workflow (SourceRange(..), SourceSite(..))
import GHC
import GHC.Builtin.Names (dollarIdKey)
import GHC.Data.FastString (unpackFS)
import GHC.Parser.Annotation (getLocA)
import GHC.Types.Unique (getUnique)
import GHC.Fingerprint (fingerprintString)
import GHC.Hs
import GHC.Types.Name (nameModule_maybe, nameOccName)
import GHC.Types.Name.Occurrence (occNameString)
import GHC.Types.SrcLoc (SrcSpan(..), srcSpanFile, srcSpanStartLine, srcSpanStartCol, srcSpanEndLine, srcSpanEndCol)
import System.Directory (doesFileExist)
import System.IO (IOMode(ReadMode), hGetContents, hSetEncoding, hSetNewlineMode, universalNewlineMode, utf8, withFile)

type Targets = [[(String, [[Int]])]]
type SourceChecks = [(FilePath, Maybe String)]

loadHanging :: String -> IO (Bool, Targets, SourceChecks)
loadHanging namespace = do
  exists <- doesFileExist (hangingFile namespace)
  if not exists then pure (False, [], [(hangingFile namespace, Nothing)]) else
    withSourceTargets $ \_ -> do
      (definitions, checks) <- loadWorkflowModules namespace True
      root <- exported (astModule namespace) "ast"
      targets <- hangingTargets namespace definitions root
      pure (True, targets, checks)

-- AST 的源码轮廓：从 ast 出发能从源码读出的每个位置，以及 Hanging 目标的源码位置。
-- 只加载 AST、Workflow 与可选的 Hanging 模块，不需要注册或 handler。
loadOutline :: String -> IO (Bool, Targets, [SourceSite])
loadOutline namespace = do
  exists <- doesFileExist (hangingFile namespace)
  withSourceTargets $ \_ -> do
    (definitions, _) <- loadWorkflowModules namespace exists
    root <- exported (astModule namespace) "ast"
    targets <- if exists then hangingTargets namespace definitions root else pure []
    sites <- either abort pure (outline (Map.map layoutOf definitions) root)
    pure (exists, targets, sites)

loadWorkflowModules :: String -> Bool -> Ghc (Map.Map Name (HsBind GhcRn), SourceChecks)
loadWorkflowModules namespace withHanging = do
  setTargets =<< mapM (\file -> guessTarget file Nothing Nothing)
    ([hangingFile namespace | withHanging] ++ [modulePath (astModule namespace) ++ ".hs"])
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
        path = modulePath name ++ ".hs"
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

astModule, hangingModule, hangingFile :: String -> String
astModule namespace = namespace ++ ".AST"
hangingModule namespace = namespace ++ ".Hanging"
hangingFile namespace = modulePath (hangingModule namespace) ++ ".hs"

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
