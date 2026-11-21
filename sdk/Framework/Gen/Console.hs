module Framework.Gen.Console (writeConsole) where

import Control.Monad (forM)
import Framework.Gen.Composition (CompositionResult(..))
import Framework.Gen.Frontend.Effects (output, semantic)
import Framework.Gen.Frontend.Source (HandlerSource(..), sourceOffset)
import Framework.Gen.Plan (Binding(..), EntryStep(..), RawSource(..), Unit(..))
import Framework.Language.Registration (Access(..), EffectKind(..))
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
-- parents 是 Excu／Scoped 的父节点：via 为 input（声明的 Input）、anchor（requests 的资产生产链上的 Excu／Scoped）
-- 或 select（alternative 候选的判定资产所在的共同句柄）；已在另一父节点上游的项已被约简掉。
-- 生产分支上的 Context 自己 requests 的资产，其锚点也是本 effect 的父节点（through 为那个 Context）。
-- 父节点之间没有先后依赖，数组顺序只是执行顺序。
-- branches 是生产分支：steps 自锚点之下依次为 Pure……Context；anchor 为空表示只有 Context 的生产链；
-- feeds 为空时资产交给本 effect，否则交给分支上的那个 Context；session 为真表示持续资产，由会话交付。
consumerChains :: P.Prototype String -> Unit -> [JsonDoc]
consumerChains proto unit =
  [ JSObject [("effect", JSString name), ("kind", JSString (kindName (P.effectKind effect)))
    , ("parents", JSArray (map parentJson (parentsOf name entry)))
    , ("branches", JSArray (map branchJson (branchesOf name entry)))]
  | effect <- effects, P.effectKind effect `elem` [ExcuKind, ScopedKind]
  , let name = P.effectName effect
  , Just method <- [lookup HandlerMethod (P.effectMethods effect) `orElse` lookup ScopeOpen (P.effectMethods effect)]
  , entry : _ <- [[b | b <- unitBindings unit, bindingEffect b == name, bindingMethod b == method]] ]
  where
    kindName kind = if kind == ScopedKind then "Scoped" else "Excu"
    orElse (Just found) _ = Just found
    orElse Nothing other = other
    effects = P.protoEffects proto
    named name = [effect | effect <- effects, P.effectName effect == name]
    owner method = take 1 [bindingEffect b | b <- unitBindings unit, bindingMethod b == method]
    contextEntry context = take 1
      [ b | effect <- named context, Just method <- [lookup ContextRequest (P.effectMethods effect)]
      , b <- unitBindings unit, bindingMethod b == method ]
    -- (父节点, via, 资产, 经由的 Context)
    -- gen 已约简入口步骤；经由 Context 上提的锚点与 alternative 的共同句柄在这里再约简一次：
    -- 已在另一父节点上游的项不列出。
    parentsOf name entry = reduce (dedupe (selected ++ direct ++ nested))
      where
        reduce found = [item | item@(parent', _, _, _) <- found
          , not (any (\(other, _, _, _) -> other /= parent' && parent' `elem` ancestors [name] other) found)]
        direct = concatMap (stepParent Nothing) (bindingBefore entry)
        nested = concat [hoisted [name] context | (False, context, Nothing, _) <- directBranches entry]
        selected = [(selector, "select", [contract], Nothing) | (selector, contract, _) <- deciding name]
    ancestors seen found
      | found `elem` seen = []
      | otherwise = concat
          [ parent' : ancestors (found : seen) parent'
          | b <- take 1 [b | effect <- named found
                           , Just method <- [lookup HandlerMethod (P.effectMethods effect) `orElse` lookup ScopeOpen (P.effectMethods effect)]
                           , b <- unitBindings unit, bindingMethod b == method]
          , (parent', _, _, _) <- parentsOf found b ]
    stepParent through (InputStep method) = [(found, "input", [], through) | found <- owner method]
    stepParent through (AnchorStep method produced) = [(found, "anchor", map assetOf produced, through) | found <- owner method]
    stepParent _ _ = []
    -- 生产分支上的 Context 经它自己的 requests 到达的锚点。
    hoisted seen context
      | context `elem` seen = []
      | otherwise = concat
          [ concatMap (stepParent (Just context)) (bindingBefore b)
            ++ concat [hoisted (context : seen) inner | RequestStep method <- bindingBefore b, inner <- owner method]
          | b <- contextEntry context ]
    dedupe = foldr (\item kept -> if any (\(other, _, _, _) -> other == first item) kept then kept else item : kept) [] . reverse
      where first (found, _, _, _) = found
    parentJson (found, via, assets, through) = JSObject
      ([("effect", JSString found), ("via", JSString via)]
        ++ [("for", JSArray (map JSString assets)) | not (null assets)]
        ++ [("through", JSString context) | Just context <- [through]])
    -- (持续, Context, 交给谁, via)
    directBranches entry =
      [ (False, context, Nothing, "requests") | RequestStep method <- bindingBefore entry, context <- owner method ]
      ++ [ (True, producer, Nothing, "requests") | SessionRequestStep producer <- bindingBefore entry ]
    branchesOf name entry = nubBranches (directBranches entry ++ nestedBranches ++ selectedBranches)
      where
        nestedBranches = concat [inner [name] context | (False, context, Nothing, _) <- directBranches entry]
        selectedBranches = [(False, provider, Nothing, "select") | (_, _, provider) <- deciding name]
        inner seen context
          | context `elem` seen = []
          | otherwise = concat
              [ [(False, found, Just context, "requests") | RequestStep method <- bindingBefore b, found <- owner method]
                ++ [(True, producer, Just context, "requests") | SessionRequestStep producer <- bindingBefore b]
                ++ concat [inner (context : seen) found | RequestStep method <- bindingBefore b, found <- owner method]
              | b <- contextEntry context ]
    nubBranches = foldr (\item kept -> if item `elem` kept then kept else item : kept) [] . reverse
    -- alternative 候选：requires 的判定资产由共同句柄（selector）之下的 Context 解析。
    deciding name =
      [ (selector, P.demandContract demand, P.demandProvider demand)
      | (selector, candidates) <- alternatives (P.protoWorkflow proto), name `elem` candidates
      , effect <- named name, demand <- P.effectDemands effect, P.demandAccess demand == RequireAccess
      , snd (walk [] (inputOf (P.demandProvider demand))) == Just selector ]
    alternatives tree = case tree of
      P.AlternativeAt _ plan children -> (P.alternativeSource plan, [effect | P.NodeAt _ effect <- children]) : concatMap alternatives children
      P.ChainAt _ children -> concatMap alternatives children
      P.ParallelAt _ children -> concatMap alternatives children
      P.LifelongAt _ _ children -> concatMap alternatives children
      P.NodeAt _ _ -> []
    assetOf name = case [contract | effect <- named name, Just contract <- [P.effectProduces effect]] of
      contract : _ -> contract
      [] -> name
    -- 自 Context 沿 Input 跳过 Pure，到 Excu／Scoped 为锚点；途经的 Pure 与 Context 是分支，锚点之下在前。
    branchJson (continuous, context, feeds, via) = JSObject
      [ ("asset", JSString (assetOf context)), ("context", JSString context)
      , ("anchor", maybe JSNull JSString anchor), ("steps", JSArray (map JSString path))
      , ("feeds", maybe JSNull JSString feeds), ("via", JSString via), ("session", JSBool continuous) ]
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
