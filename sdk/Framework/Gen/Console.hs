module Framework.Gen.Console (writeConsole) where

import Control.Monad (forM)
import Framework.Gen.Composition (CompositionResult(..))
import Framework.Gen.Frontend.Effects (output, semantic)
import Framework.Gen.Frontend.Source (HandlerSource(..), sourceOffset)
import Framework.Gen.Plan (Binding(..), Unit(..))
import qualified Framework.Prototype as P
import Framework.Prototype.Graph (graphReferences)
import GHC.Hs
import GHC.Parser.Annotation (getLocA)
import GHC.Types.Name.Reader (rdrNameOcc)
import GHC.Types.Name.Occurrence (occNameString)
import GHC.Types.SrcLoc
import GHC.Utils.Json

writeConsole :: CompositionResult -> Maybe HandlerSource -> IO ()
writeConsole result source = do
  let proto = compositionPrototype result
      unit = compositionUnit result
      namespace = unitNamespace unit
      owners = [(method, P.effectName e) | e <- P.protoEffects proto, (_,method) <- P.effectMethods e]
      owner method = maybe (fail ("Missing effect for method " ++ method)) pure (lookup method owners)
      bodies = maybe [] methodSources source
      binding b = JSObject [("effect", JSString (bindingEffect b)), ("method", JSString (bindingMethod b)),
        ("handler", JSString (bindingHandler b)), ("source", maybe JSNull JSString (lookup (bindingHandler b) bodies))]
  edges <- forM (graphReferences (P.protoGraph proto)) $ \(caller, callee) -> do
    from <- owner caller
    to <- owner callee
    pure (JSObject [("from", JSString from), ("to", JSString to),
      ("caller", JSString caller), ("callee", JSString callee)])
  output [("namespace", JSString namespace), ("registrations", JSArray (map (semantic namespace) (P.protoRegistrations proto))),
    ("bindings", JSArray (map binding (unitBindings unit))), ("references", JSArray edges),
    ("workflow", workflow (P.protoWorkflow proto))]

methodSources :: HandlerSource -> [(String, String)]
methodSources source =
  [(occNameString (rdrNameOcc (unLoc n)), take (end - start) (drop start text))
  | L _ (InstD _ (ClsInstD _ decl)) <- hsmodDecls (handlerModule source)
  , b@(L _ FunBind {fun_id = n}) <- cid_binds decl
  , RealSrcSpan s _ <- [getLocA b]
  , let start = sourceOffset text (srcSpanStartLine s) (srcSpanStartCol s)
  , let end = sourceOffset text (srcSpanEndLine s) (srcSpanEndCol s)]
  where text = handlerText source

workflow :: P.WorkflowTree -> JsonDoc
workflow tree = case tree of
  P.NodeAt path name -> node path "Node" [] [("effect", JSString name)]
  P.ChainAt path xs -> node path "Chain" xs []
  P.ParallelAt path xs -> node path "Parallel" xs []
  P.AlternativeAt path plan xs -> node path "Alternative" xs [("selector", JSString (P.alternativeSource plan))]
  P.LifelongAt path _ xs -> node path "Lifelong" xs []
  where
    node path kind children extra = JSObject ([("path", JSArray (map JSInt path)),
      ("kind", JSString kind), ("children", JSArray (map workflow children))] ++ extra)
