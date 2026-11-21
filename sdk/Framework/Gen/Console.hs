module Framework.Gen.Console (writeConsole) where

import Control.Monad (forM)
import Framework.Gen.Composition (CompositionResult(..))
import Framework.Gen.Frontend.Effects (output, semantic)
import Framework.Gen.Frontend.Source (HandlerSource(..), sourceOffset)
import Framework.Gen.Plan (Binding(..), EntryStep(..), RawSource(..), Unit(..))
import Framework.Language.Registration (EffectKind(..))
import Framework.Prototype.Graph (MethodRole(..))
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
      before (AnchorStep method produced) = case step "anchor" (entryOf method) of
        JSObject fields -> JSObject (fields ++ [("for", JSArray (map JSString produced))])
        other -> other
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
    ("chains", JSArray (consumerChains proto unit)),
    ("workflow", workflow (P.protoWorkflow proto))]

-- 消费链与生产分支，取自 gen 排好的入口步骤（算法说明 v3）：
-- parents 是 Excu／Scoped 的父节点，via 为 input（声明的 Input）或 anchor（requests 的资产生产链上的 Excu／Scoped）；
-- 已在另一父节点上游的项已被约简掉。父节点之间没有先后依赖，数组顺序只是执行顺序。
-- branches 是从锚点分出的生产分支：steps 自锚点之下依次为 Pure……Context，anchor 为空表示只有 Context 的生产链，
-- session 为真表示持续资产，由会话交付，不在本入口执行。
consumerChains :: P.Prototype String -> Unit -> [JsonDoc]
consumerChains proto unit =
  [ JSObject [("effect", JSString (bindingEffect entry)), ("kind", JSString (kindName (P.effectKind effect)))
    , ("parents", JSArray (concatMap parent (bindingBefore entry)))
    , ("branches", JSArray (concatMap branch (bindingBefore entry)))]
  | effect <- effects, P.effectKind effect `elem` [ExcuKind, ScopedKind]
  , Just method <- [lookup HandlerMethod (P.effectMethods effect) `orElse` lookup ScopeOpen (P.effectMethods effect)]
  , entry : _ <- [[b | b <- unitBindings unit, bindingEffect b == P.effectName effect, bindingMethod b == method]] ]
  where
    kindName kind = if kind == ScopedKind then "Scoped" else "Excu"
    orElse (Just found) _ = Just found
    orElse Nothing other = other
    effects = P.protoEffects proto
    named name = [effect | effect <- effects, P.effectName effect == name]
    owner method = take 1 [bindingEffect b | b <- unitBindings unit, bindingMethod b == method]
    parent (InputStep method) = [JSObject [("effect", JSString name), ("via", JSString "input")] | name <- owner method]
    parent (AnchorStep method produced) =
      [JSObject [("effect", JSString name), ("via", JSString "anchor"), ("for", JSArray (map (JSString . assetOf) produced))]
      | name <- owner method]
    parent _ = []
    branch (RequestStep method) = [productionBranch False name | name <- owner method]
    branch (SessionRequestStep producer) = [productionBranch True producer]
    branch _ = []
    assetOf name = case [contract | effect <- named name, Just contract <- [P.effectProduces effect]] of
      contract : _ -> contract
      [] -> name
    -- 自 Context 沿 Input 跳过 Pure，到 Excu／Scoped 为锚点；途经的 Pure 与 Context 是分支，锚点之下在前。
    productionBranch continuous context = JSObject
      [ ("asset", JSString (assetOf context)), ("context", JSString context)
      , ("anchor", maybe JSNull JSString anchor), ("steps", JSArray (map JSString path))
      , ("session", JSBool continuous) ]
      where (path, anchor) = walk [context] (inputOf context)
    walk path name = case named name of
      [effect] | P.effectKind effect == PureKind -> walk (name : path) (P.effectInput effect)
               | P.effectKind effect `elem` [ExcuKind, ScopedKind] -> (path, Just name)
      _ -> (path, Nothing)
    inputOf name = concat [P.effectInput effect | effect <- take 1 (named name)]

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
