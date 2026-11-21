module Framework.Gen.Console (writeConsole) where

import Control.Monad (forM)
import Framework.Gen.Composition (CompositionResult(..))
import Framework.Gen.Frontend.Effects (output, semantic)
import Framework.Gen.Frontend.Source (HandlerSource(..), sourceOffset)
import Framework.Gen.Plan (Binding(..), EntryStep(..), RawSource(..), Unit(..))
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
      -- gen 已解析的入口剧本：方法体之前依次执行的步骤，以及 rawinput 读到的那次原子调用。
      -- 步骤里的 method 是另一份绑定的方法，前端按 method 找到它的绑定即可递归展开整条链。
      entryOf method = (method, lookup method owners)
      step kind (method, effect) = JSObject [("kind", JSString kind), ("method", JSString method),
        ("effect", maybe JSNull JSString effect)]
      before (RequestStep method) = step "requests" (entryOf method)
      before (InputStep method) = step "input" (entryOf method)
      before (SessionRequestStep producer) = step "session" ("", Just producer)
      raw (RawList method) = step "rawinput" (entryOf method)
      raw (RawStream method) = step "rawstream" (entryOf method)
      binding b = JSObject [("effect", JSString (bindingEffect b)), ("method", JSString (bindingMethod b)),
        ("handler", JSString (bindingHandler b)), ("source", maybe JSNull JSString (lookup (bindingHandler b) bodies)),
        ("before", JSArray (map before (bindingBefore b))), ("raw", maybe JSNull raw (bindingRaw b))]
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
