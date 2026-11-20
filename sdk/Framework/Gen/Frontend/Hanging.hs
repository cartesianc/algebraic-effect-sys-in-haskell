-- GHC names identify branches before evaluating AST.ast erases their binding identity.
module Framework.Gen.Frontend.Hanging (loadHanging) where

import Control.Exception (evaluate)
import Control.Monad (forM, unless)
import Control.Monad.IO.Class (liftIO)
import Data.Data (Data, cast, gmapQ)
import Data.List (isPrefixOf, sort, sortOn)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Framework.Gen.Frontend.Ghc (modulePath, withSourceTargets)
import GHC
import GHC.Fingerprint (fingerprintString)
import GHC.Hs
import GHC.Types.Name (nameModule_maybe, nameOccName)
import GHC.Types.Name.Occurrence (occNameString)
import System.Directory (doesFileExist)
import System.IO (IOMode(ReadMode), hGetContents, hSetEncoding, hSetNewlineMode, universalNewlineMode, utf8, withFile)

type Targets = [[(String, [[Int]])]]
type SourceChecks = [(FilePath, Maybe String)]

loadHanging :: String -> IO (Bool, Targets, SourceChecks)
loadHanging namespace = do
  exists <- doesFileExist hangingFile
  if not exists then pure (False, [], [(hangingFile, Nothing)]) else
    withSourceTargets $ \_ -> do
      setTargets =<< mapM (\file -> guessTarget file Nothing Nothing) [hangingFile, modulePath astModule ++ ".hs"]
      result <- load LoadAllTargets
      case result of
        Failed -> abort "Cannot load Hanging and AST modules"
        Succeeded -> pure ()
      graph <- getModuleGraph
      let moduleLabel summary = moduleNameString (moduleName (ms_mod summary))
          relevant summary = let name = moduleLabel summary
                             in name == hangingModule || workflowModule name
      modules <- forM (sortOn moduleLabel (filter relevant (mgModSummaries graph))) $ \summary -> do
        checked <- typecheckModule =<< parseModule summary
        let name = moduleLabel summary
            path = modulePath name ++ ".hs"
        signature <- liftIO (fingerprint path)
        case tm_renamed_source checked of
          Just (group, _, _, _, _) -> pure (bindings (hs_valds group), (path, Just signature))
          Nothing -> abort ("Missing renamed source for " ++ name)
      let definitions = Map.fromList (concatMap fst modules)
      root <- exported astModule "ast"
      declaration <- exported hangingModule "hangingTree"
      rows <- either abort pure $ do
        body <- maybe (Left "Define hangingTree in Hanging.hs") singleBody (Map.lookup declaration definitions)
        entries <- listArgument body
        mapM (targetsOf workflowModule) entries
      let wanted = Set.fromList (concat rows)
      sites <- either abort pure (branchSites (Map.map layoutOf definitions) wanted root)
      pure (True, [[(qualified n, sort (Map.findWithDefault [] n sites)) | n <- row] | row <- rows], map snd modules)
  where
    astModule = namespace ++ ".AST"
    hangingModule = namespace ++ ".Hanging"
    hangingFile = modulePath hangingModule ++ ".hs"
    workflowModule name = name == astModule || isPrefixOf (namespace ++ ".Workflow.") name
    exported owner local = do
      summary <- getModSummary (mkModuleName owner)
      info <- getModuleInfo (ms_mod summary)
      case [n | n <- maybe [] modInfoExports info, spelling n == local] of
        [n] -> pure n
        _ -> abort (owner ++ " must export " ++ local)
    fingerprint path = withFile path ReadMode $ \file -> do
      hSetEncoding file utf8
      hSetNewlineMode file universalNewlineMode
      contents <- hGetContents file
      let value = show (fingerprintString contents)
      _ <- evaluate (length value)
      pure value

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
  OpApp _ fun operator arg | Just op <- variable operator, qualified op == "GHC.Internal.Base.$" -> append fun arg
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
data Layout = Children [Layout] | Reference Name | Opaque [Name]

layoutOf :: HsBind GhcRn -> Layout
layoutOf binding = either (const (Opaque (uses binding))) descend (singleBody binding)
  where
    descend expr = case application expr of
      (Just n, []) -> Reference n
      (Just n, [arg]) | ownerOf n == "Framework.Language.AST" ->
        case spelling n of
          "node" -> Children []
          ctor | elem ctor ["chained","parallel","alternative","lifelong"], Right xs <- list arg -> Children (map descend xs)
          _ -> Opaque (uses expr)
      _ -> Opaque (uses expr)
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
    deps (Children xs) = concatMap deps xs
    deps (Reference n) = [n]
    deps (Opaque ns) = ns
    walk seen path n
      | Set.notMember n relevant = Right []
      | Set.member n seen = Left ("Cyclic workflow reference at " ++ qualified n)
      | otherwise = do
          layout <- maybe (Left ("Cannot locate named workflow " ++ qualified n)) Right (Map.lookup n layouts)
          nested <- visit (Set.insert n seen) path layout
          pure ([(n,[reverse path]) | Set.member n wanted] ++ nested)
    visit seen path (Reference n) = walk seen path n
    visit seen path (Children xs) = concat <$> sequence [visit seen (i:path) x | (i,x) <- zip [0..] xs]
    visit _ _ (Opaque ns) = do
      unless (all (flip Set.notMember relevant) ns) (Left "Cannot prove a Hanging target's location; compose named branches using explicit workflow child lists")
      pure []
