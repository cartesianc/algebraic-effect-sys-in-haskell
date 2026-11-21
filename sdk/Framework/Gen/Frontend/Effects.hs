-- Parse one v1 registration without loading any business code. Namespace mode can
-- also inspect evaluated declarations in a trusted project, marking them read-only.
module Framework.Gen.Frontend.Effects (readEffect, readEffects, registrationSlot, semantic, output) where

import Control.Monad (unless)
import Control.Monad.IO.Class (liftIO)
import Data.Char (ord)
import Data.List (intercalate, sort)
import Framework.Gen.Frontend.Source (namespaceDirectory, parseSourceFile, sourceOffset)
import qualified Framework.Language.Registration as R
import GHC (getSessionDynFlags, runGhc)
import GHC.Data.FastString (mkFastString, unpackFS)
import GHC.Data.StringBuffer (stringToStringBuffer)
import GHC.Driver.Config.Parser (initParserOpts)
import GHC.Driver.Session (parseDynamicFilePragma)
import GHC.Hs
import qualified GHC.Parser as Parser
import GHC.Parser.Annotation (getLocA)
import GHC.Parser.Lexer (ParseResult(..), initParserState, unP)
import GHC.Parser.PostProcess (runPV, unECP)
import GHC.Types.Name.Occurrence (isTcOcc)
import GHC.Types.Name.Reader (rdrNameOcc)
import GHC.Types.SrcLoc
import GHC.Utils.Json (JsonDoc(..))
import GHC.Utils.Outputable (Outputable, ppr, showSDocUnsafe)
import Numeric (showHex)
import System.FilePath ((</>))
import System.Process (readProcess)
import Text.Read (readMaybe)

type Expr = LHsExpr GhcPs
type Decoder = Expr -> Either String JsonDoc

display :: Outputable a => a -> String
display = showSDocUnsafe . ppr

output :: [(String, JsonDoc)] -> IO ()
output fields = putStrLn (encode (JSObject (("schemaVersion", JSInt 1) : fields)))
  where
    encode JSNull = "null"
    encode (JSBool b) = if b then "true" else "false"
    encode (JSInt n) = show n
    encode (JSArray xs) = "[" ++ intercalate "," (map encode xs) ++ "]"
    encode (JSObject xs) = "{" ++ intercalate "," [quote k ++ ":" ++ encode v | (k,v) <- xs] ++ "}"
    encode (JSString s) = quote s
    -- Emit non-BMP characters directly as UTF-8. A JSON unicode escape has exactly four digits.
    quote s = "\"" ++ concatMap escape s ++ "\""
    escape '"' = "\\\""
    escape '\\' = "\\\\"
    escape c | ord c < 32 || (ord c >= 0xd800 && ord c <= 0xdfff) =
      let hex = showHex (ord c) "" in "\\u" ++ replicate (4 - length hex) '0' ++ hex
    escape c = [c]

readEffect :: IO ()
readEffect = do
  source <- getContents
  library <- takeWhile (\c -> c /= '\n' && c /= '\r') <$> readProcess "ghc" ["--print-libdir"] ""
  runGhc (Just library) $ do
    flags <- getSessionDynFlags
    (enabled, _, _) <- parseDynamicFilePragma flags [noLoc "-XTypeApplications"]
    let state = initParserState (initParserOpts enabled) (stringToStringBuffer source)
          (mkRealSrcLoc (mkFastString "<effect>") 1 1)
    liftIO $ case unP (Parser.parseExpression >>= runPV . unECP) state of
      PFailed _ -> fail "Invalid Haskell effect expression"
      POk _ expr -> do
        value <- either fail pure (registration expr)
        output [("effect", value)]

-- Only the outer list needs a source location. Its entries may use local helpers.
registrationSlot :: String -> IO ()
registrationSlot namespace = do
  (source, parsed) <- parseSourceFile (namespaceDirectory namespace </> "Effects.hs")
  case [body | L _ (ValD _ FunBind {fun_id = L _ n, fun_matches = MG {mg_alts = L _
                [L _ Match {m_grhss = GRHSs {grhssGRHSs = [L _ (GRHS _ [] body)]}}]}}) <- hsmodDecls parsed,
                display n == "effects"] of
    [body] | Just empty <- listEmpty body, RealSrcSpan span' _ <- getLocA body -> do
      let line = srcSpanEndLine span'
          column = sourceOffset source line (srcSpanEndCol span') - sourceOffset source line 1 - 1
      output [("line", JSInt line), ("index", JSInt column), ("empty", JSBool empty)]
    _ -> fail "effects must be an explicit list to append a registration"
  where
    listEmpty (L _ (ExplicitList _ entries)) = Just (null entries)
    listEmpty e | var e == "[]" = Just True
    listEmpty _ = Nothing

readEffects :: String -> IO ()
readEffects namespace = do
  let path = namespaceDirectory namespace </> "Effects.hs"
  (_, parsed) <- parseSourceFile path
  case [body | L _ (ValD _ FunBind {fun_id = L _ n, fun_matches = MG {mg_alts = L _
                [L _ Match {m_grhss = GRHSs {grhssGRHSs = [L _ (GRHS _ [] body)],
                  grhssLocalBinds = EmptyLocalBinds {}}}]}}) <- hsmodDecls parsed, display n == "effects"] of
    [e] | var e == "[]" -> output [("editable", JSBool True), ("registrations", JSArray [])]
    [L _ (ExplicitList _ entries)] | Right rows <- traverse located entries ->
      output [("editable", JSBool True), ("registrations", JSArray rows)]
    _ -> do
      -- GHCi evaluates only the registration value; the workflow and handlers are not loaded.
      let args = ["-ignore-dot-ghci", "-v0", "-idemo", "-isdk", path, "-e",
                  "print (" ++ namespace ++ ".Effects.effects :: [Framework.Language.Registration.EffectSpec])"]
      printed <- readProcess "ghci" args ""
      specs <- maybe (fail "Cannot decode SDK registrations") pure (readMaybe printed)
      output [("editable", JSBool False), ("registrations", JSArray (map (semantic namespace) specs))]
  where
    located expr = do
      value <- registration expr
      case getLocA expr of
        RealSrcSpan span' _ -> pure (JSObject [("effect", value), ("range", JSArray
          (map JSInt [srcSpanStartLine span', srcSpanStartCol span', srcSpanEndLine span', srcSpanEndCol span']))])
        _ -> Left "Registration has no source range"

bad :: Expr -> String -> Either String a
bad e message = Left (display (getLocA e) ++ ": " ++ message)

var :: Expr -> String
var (L _ (HsVar _ n)) = display (unLoc n)
var _ = ""

literal :: Decoder
literal (L _ (HsLit _ (HsString _ s))) = Right (JSString (unpackFS s))
literal e = bad e "Expected a string literal"

array :: Decoder -> Decoder
array _ e | var e == "[]" = Right (JSArray [])
array decode (L _ (ExplicitList _ xs)) = JSArray <$> traverse decode xs
array _ e = bad e "Expected a list literal"

method :: Decoder
method e | var e == "Nothing" = Right JSNull
method (L _ (HsApp _ f arg)) | var f == "Just" = literal arg
method e = bad e "Expected Nothing or Just a string literal"

boolean :: Decoder
boolean e | var e == "True" = Right (JSBool True)
          | var e == "False" = Right (JSBool False)
          | otherwise = bad e "Expected True or False"

namedApplication :: String -> String -> [String] -> Decoder
namedApplication tag field names (L _ (HsApp _ f x)) | var f `elem` names = do
  value <- literal x
  pure (JSObject [(tag, JSString (var f)), (field, value)])
namedApplication _ _ names e = bad e ("Expected one of " ++ unwords names)

asset :: Decoder
asset e@(L _ (HsApp _ (L _ (HsAppType _ f ty)) arg)) | var f == "Asset" = do
  contract <- literal arg
  let body = hswc_body ty
  spelling <- case unLoc body of
    HsTyVar _ _ name | isTcOcc (rdrNameOcc (unLoc name)) -> Right (display body)
    HsListTy _ item | display item == "String" -> Right "[String]"
    _ -> bad e "Expected an asset representation type name or [String]"
  pure (JSObject [("type", JSString spelling), ("contract", contract)])
asset e = bad e "Expected Asset @T and a contract literal"

intercepts :: Decoder
intercepts e | var e == "allEffects" = Right (JSArray (map (JSString . show) R.allEffects))
intercepts e = array kind e
  where
    kind x | var x `elem` map show R.allEffects = Right (JSString (var x))
           | otherwise = bad x "Unsupported middleware intercept kind"

record :: String -> [(String, Decoder)] -> Decoder
record tag fields e@(L _ RecordCon {rcon_con = constructor, rcon_flds = HsRecFields {rec_flds = bindings, rec_dotdot = dots}}) = do
  let entries = [(display (unLoc (foLabel (unLoc (hfbLHS b)))), hfbRHS b) | L _ b <- bindings, not (hfbPun b)]
  unless (display (unLoc constructor) == tag && length entries == length bindings && null dots
          && sort (map fst entries) == sort (map fst fields)) (bad e ("Expected all fields of " ++ tag))
  values <- traverse (\(name, decode) -> do
    expr <- maybe (bad e ("Missing " ++ name)) Right (lookup name entries)
    value <- decode expr
    pure (name, value)) fields
  pure (JSObject ([("kind", JSString tag) | tag /= "EffectSpec"] ++ values))
record tag _ e = bad e ("Expected " ++ tag ++ " record")

registration :: Decoder
registration = record "EffectSpec"
  [("name", literal), ("typing", typing), ("input", literal),
   ("demands", array (namedApplication "access" "contract" ["requests","requires","streams"]))]

typing :: Decoder
typing e@(L _ RecordCon {rcon_con = n}) = case display (unLoc n) of
  tag | tag `elem` ["Pure","Excu","Stream"] -> record tag [("handler",method)] e
  "Scoped" -> record "Scoped" [("open",method),("close",method)] e
  "Error" -> record "Error" [("detect",method),("resolve",method),
    ("handles",array (namedApplication "kind" "target" ["RaisedBy","ScopeFaultIn","ContextFaultIn"]))] e
  "Context" -> record "Context" [("asset",asset),("parser",method),("require",boolean),("stream",boolean)] e
  "Middleware" -> record "Middleware" [("handler",method),("intercept",intercepts)] e
  _ -> bad e "Unknown EffectTyping constructor"
typing e = bad e "Expected an EffectTyping record"

-- Protocol-external Haskell expressions have values but no editable template spelling.
semantic :: String -> R.EffectSpec -> JsonDoc
semantic namespace (R.EffectSpec n t i ds) = JSObject (("effect", effect) : identity)
  where
    effect = JSObject [("name", JSString n), ("typing", kind t), ("input", JSString i),
                       ("demands", JSArray (map demand ds))]
    identity = case t of
      R.Context (R.AssetDecl _ (R.TypeRef name (Just (unit, owner)))) _ _ _ ->
        [("assetDefinition", JSObject [("unit", JSString unit), ("module", JSString owner), ("name", JSString name)])]
      _ -> []
    typeName (R.TypeRef "[Char]" Nothing) = "String"
    typeName (R.TypeRef "[[Char]]" Nothing) = "[String]"
    typeName (R.TypeRef name (Just (_, owner))) | owner /= namespace ++ ".Types" = owner ++ "." ++ name
    typeName ref = R.contractName ref
    obj k fields = JSObject (("kind", JSString k) : fields)
    opt = maybe JSNull JSString
    kind (R.Pure h) = obj "Pure" [("handler", opt h)]
    kind (R.Excu h) = obj "Excu" [("handler", opt h)]
    kind (R.Stream h) = obj "Stream" [("handler", opt h)]
    kind (R.Scoped o c) = obj "Scoped" [("open", opt o), ("close", opt c)]
    kind (R.Error d r hs) = obj "Error" [("detect", opt d), ("resolve", opt r), ("handles", JSArray (map target hs))]
    kind (R.Middleware h ks) = obj "Middleware" [("handler", opt h), ("intercept", JSArray (map (JSString . show) ks))]
    kind (R.Context (R.AssetDecl contract ref) p r s) = obj "Context"
      [("asset", JSObject [("type", JSString (typeName ref)), ("contract", JSString contract)]),
       ("parser", opt p), ("require", JSBool r), ("stream", JSBool s)]
    target (R.RaisedBy h) = obj "RaisedBy" [("target", JSString h)]
    target (R.ScopeFaultIn s) = obj "ScopeFaultIn" [("target", JSString s)]
    target (R.ContextFaultIn c) = obj "ContextFaultIn" [("target", JSString c)]
    demand (R.Demand mode contract) = JSObject [("access", JSString (case mode of
      R.RequestAccess -> "requests"; R.RequireAccess -> "requires"; R.StreamAccess -> "streams")), ("contract", JSString contract)]
