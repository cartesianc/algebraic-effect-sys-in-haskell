{-# LANGUAGE DuplicateRecordFields #-}

-- 构图：PrototypePlan 加上各 effect 方法的结构，构建 EffectGraph、ScopeTree、链挂载与资产来源，
-- 得到完整的 Prototype（编译产物），并检查注入、Stream 调用、持续资产的启动环与 Context 驱动。
module Framework.Gen.Build
  ( buildPrototype, checkDriven
  ) where

import Control.Monad (unless)
import Data.List (intercalate, nub)
import Data.Maybe (listToMaybe)
import Framework.Gen.Build.Graph (buildEffectGraph, buildScopeTree, completeScopeTree)
import Framework.Gen.Build.Sources (resolveSources)
import Framework.Language.Registration (EffectKind(..))
import Framework.Prototype.Graph
import Framework.Prototype.Query
import Framework.Prototype.Types
import Framework.Prototype.Validate (valid, unique, validatePrototype)

buildPrototype :: PrototypePlan -> [(String, MethodShape String)]
                       -> Either (PrototypeError String) (Prototype String)
buildPrototype plan shapes = do
  valid (unique (map fst shapes)) "Duplicate handler method in the structure generation plan"
  valid (all (`elem` map methodIdentity defaults) (map fst shapes)) "Unregistered handler method in the structure generation plan"
  let definitions = mergedDefinitions effects defaults shapes
      bodyOf = writtenBody defaults shapes
  -- 注入只回放挂接句柄：Context 只能直接或经一串 Pure 读到句柄，不能经其他方法再到达它。
  valid (null [(anchor, produced) | (anchor, produced) <- anchors effects
      , anchor `elem` reachableMethods definitions (calledMethods (replayedBody effects bodyOf anchor (bodyOf produced)))])
    "An injected Context reaches its anchor through another method; read the anchor with raw, directly or through Pure"
  mounted <- mapM mountedNode (allWorkflow workflow) >>= pure . concat
  selectors <- mapM mountedSelector [selected | selected@AlternativeAt {} <- allWorkflow workflow]
  sessions <- concat <$> mapM mountedSession lifelongSessionsOf
  finiteMounts <- concat <$> mapM mountedSession finite
  let mounts = mounted ++ selectors ++ sessions ++ finiteMounts
      entries = nub [method | (_, _, _, method) <- mounts]
      logical = withProducerReferences effects definitions
  graph <- either (Left . InvalidEffectGraph) Right (buildEffectGraph definitions (Choice (map Call entries)))
  names <- mapM scopeName orderedScopes
  declared <- mapM (scopeDeclaration names) orderedScopes
  scopes <- either (Left . InvalidEffectGraph) Right (completeScopeTree declared (buildScopeTree graph))
  let makeChain (identifier, role, terminal, method) = ChainProto identifier role terminal method
        (reachableMethods logical [method]) [] [] (maybe [] id (lookup method (graphRootPaths graph)))
      chainDefinitions = [ChainDefinition kind (effectName effect) method (reachableMethods logical [method])
        | effect <- effects, (role, method) <- effectMethods effect
        , Just kind <- [case role of
            HandlerMethod -> Just OriginChain
            ScopeOpen -> Just OriginChain
            ContextRequest -> Just ContextChain
            ContextRequire -> Just ContextChain
            ContextStream -> Just ContextChain
            StreamHandler -> Just ContextChain
            _ -> Nothing]]
      written = [definition { methodBody = maybe (methodBody definition) id
          (lookup (methodIdentity definition) shapes) } | definition <- defaults]
      defaultReaders = [methodIdentity definition | definition <- defaults
        , methodRole definition == ContextRequire, methodIdentity definition `notElem` map fst shapes]
      result = Prototype (plannedRegistrations plan) effects definitions workflow finite
        (map makeChain mounts) chainDefinitions graph scopes names [] []
  -- Stream 的方法只经会话执行：Stream 单步执行它取得下一份原始输入；挂在该 Stream 下的解析器调用它时，
  -- 由会话本次取得的输入回答，与挂在原子句柄下的 Context 调用句柄相同。其他方法直接调用会绕过会话另取一份。
  let streamMethods = [(effectName effect, method) | effect <- effects, (StreamHandler, method) <- effectMethods effect]
      parsing = [(parser, method) | effect <- effects, (ContextStream, parser) <- effectMethods effect
        , (source, method) <- streamMethods, source == effectInput effect]
  mapM_ (\definition -> case [called | called <- calledMethods (methodBody definition), called `elem` map snd streamMethods
        , (methodIdentity definition, called) `notElem` parsing] of
      [] -> pure ()
      called : _ -> Left (InvalidPrototype ("Method " ++ methodIdentity definition ++ " calls Stream method "
        ++ called ++ " directly; only its session and the parser Context hanging below that Stream may call it")))
    [definition | definition <- definitions, methodRole definition /= StreamHandler]
  -- 启动环：会话的生产链不能依赖其他持续资产，否则首次生产就要先等待另一份增量。
  let continuousMethods = [(contractType, method) | effect <- effects, effectContinuous effect
        , Just contractType <- [effectProduces effect], (role, method) <- effectMethods effect
        , role `elem` [ContextRequest, ContextRequire, ContextStream]]
  mapM_ (\chain -> do
      let others = nub [contractType | (contractType, method) <- continuousMethods
            , method `elem` chainReaches chain, contractType /= chainTerminal chain]
      unless (null others) $ Left (InvalidLifelong (chainNode chain) ("Production of continuous asset "
        ++ chainTerminal chain ++ " depends on continuous assets " ++ intercalate ", " others
        ++ "; its first delivery would wait for another stream")))
    [makeChain mount | mount <- sessions]
  analyzed <- resolveSources written defaultReaders result
  validatePrototype analyzed
  pure analyzed
  where
    effects = plannedEffects plan
    workflow = plannedWorkflow plan
    lifelongSessionsOf = concatMap (lifelongSessions . snd) (workflowLifelongs workflow)
    finite = finiteSessions effects
    -- 读取入口不调用生产方法：require 缺值时等待发布，图中没有读取到生产的边。
    defaults = [MethodDefinition method owner role Empty
      | effect <- effects, (_, owner) : _ <- [effectMethods effect], (role, method) <- effectMethods effect]
    orderedScopes = filter hasOpening $ nub
      (concat [effectScopes effect ++ [effectName effect | effectKind effect == ScopedKind] | effect <- effects])
    hasOpening selected = any (\effect -> effectName effect == selected
      && ScopeOpen `elem` map fst (effectMethods effect)) effects
    scopeName selected = do
      effect <- findEffectProto effects selected
      case lookup ScopeOpen (effectMethods effect) of
        Just opening -> pure (opening, selected)
        Nothing -> Left (InvalidPrototype ("Scope has no open method: " ++ selected))
    scopeDeclaration names selected = do
      effect <- findEffectProto effects selected
      method <- maybe (Left (UnknownPrototypeTarget selected)) Right (lookup selected [(name', identity) | (identity, name') <- names])
      parents <- mapM (\parent -> maybe (Left (UnknownPrototypeTarget parent)) Right
        (lookup parent [(name', identity) | (identity, name') <- names])) (effectScopeParents effect)
      pure (method, parents)
    mountedNode (NodeAt identifier selected) = do
      effect <- findEffectProto effects selected
      method <- ordinaryEntry effect
      pure [(identifier, NodeChain, selected, method)]
    mountedNode _ = pure []
    mountedSelector (AlternativeAt _ selected _) = case
      [method | effect <- effects, effectProduces effect == Just (alternativeContract selected)
        , Just method <- [selectorMethod effect]] of
      [method] -> pure (alternativeSelector selected, SelectorChain, alternativeContract selected, method)
      _ -> Left (UnknownPrototypeTarget (alternativeContract selected))
    mountedSelector _ = Left (InvalidPrototype "Expected alternative selector")
    -- 会话挂载依次为 Stream 单步与 parser；终端名记资产名。
    mountedSession described = do
      producer <- case [effect | effect <- effects, effectProduces effect == Just (sessionAsset described)] of
        [effect] -> pure effect
        _ -> Left (UnknownPrototypeTarget (sessionAsset described))
      let roleOf effect role = maybe (Left (InvalidPrototype ("Session for " ++ sessionAsset described
            ++ " has no " ++ show role ++ " method"))) Right (lookup role (effectMethods effect))
      methods <- case sessionPlan described of
        Receive source -> do
          streamEffect <- findEffectProto effects source
          handle <- roleOf streamEffect StreamHandler
          parser <- roleOf producer ContextStream
          pure [handle, parser]
      valid (length methods == length (sessionMounts described)) ("Session steps differ for " ++ sessionAsset described)
      pure [(mount, SessionChain, sessionAsset described, method) | (mount, method) <- zip (sessionMounts described) methods]

anchors :: [EffectProto method] -> [(method, method)]
anchors effects = [(anchorMethod, produced)
  | effect <- effects, Just anchorName <- [effectAnchor effect]
  , Just produced <- [lookup ContextRequest (effectMethods effect)]
  , anchor <- effects, effectName anchor == anchorName
  , (role, anchorMethod) <- effectMethods anchor, role `elem` [HandlerMethod, ScopeOpen]]

mergedDefinitions :: [EffectProto String] -> [MethodDefinition String] -> [(String, MethodShape String)]
                  -> [MethodDefinition String]
mergedDefinitions effects defaults shapes =
  [definition { methodBody = injected (methodIdentity definition) (bodyOf (methodIdentity definition)) } | definition <- defaults]
  where
    bodyOf = writtenBody defaults shapes
    injected selected body = case [replayedBody effects bodyOf selected (bodyOf produced) | (anchor, produced) <- anchors effects, anchor == selected] of
      [] -> body
      contexts -> Sequence [body, Choice [Empty, Sequence contexts]]

writtenBody :: [MethodDefinition String] -> [(String, MethodShape String)] -> String -> MethodShape String
writtenBody defaults shapes selected = case lookup selected shapes of
  Just shape -> shape
  Nothing -> maybe Empty methodBody (listToMaybe [definition | definition <- defaults, methodIdentity definition == selected])

-- 注入副本：挂接 Context 的生产方法体里，对句柄的调用由本次输出回答（Empty）；
-- 中间的 Pure 入口就地展开，同样回答到句柄为止。注入副本因此不再调用句柄或 Pure，图中不成环。
replayedBody :: [EffectProto String] -> (String -> MethodShape String) -> String -> MethodShape String -> MethodShape String
replayedBody effects bodyOf anchor = replay []
  where
    pureMethods = [method | effect <- effects, effectKind effect == PureKind, (_, method) <- effectMethods effect]
    replay seen shape = case shape of
      Call method
        | method == anchor -> Empty
        | method `elem` pureMethods, method `notElem` seen -> replay (method : seen) (bodyOf method)
      Sequence children -> Sequence (map (replay seen) children)
      Choice children -> Choice (map (replay seen) children)
      Recover body recovery -> Recover (replay seen body) (replay seen recovery)
      other -> other

withProducerReferences :: Eq method => [EffectProto method] -> [MethodDefinition method] -> [MethodDefinition method]
withProducerReferences effects definitions =
  [definition { methodBody = Sequence (methodBody definition : [Call produced
      | (anchor, produced) <- anchors effects, anchor == methodIdentity definition]) }
  | definition <- definitions]

-- 首次尚无 Handlers 时仅生成契约；有源码快照后必须另外执行这个驱动检查。
checkDriven :: Prototype String -> Either (PrototypeError String) ()
checkDriven prototype = valid (null undriven)
  ("Context never driven from the AST: " ++ intercalate ", " undriven
    ++ "; no terminal reaches its production or the handle it hangs below")
  where
    reached = reachableMethods (withProducerReferences (protoEffects prototype) (protoMethods prototype))
      (map chainEntry (protoChains prototype))
    undriven = [methodIdentity definition | definition <- protoMethods prototype
      , methodRole definition == ContextRequest, methodIdentity definition `notElem` reached]
