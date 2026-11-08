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
  valid (null [(anchor, produced) | (anchor, produced) <- anchors effects
      , definition <- definitions, methodIdentity definition == produced
      , anchor `elem` reachableMethods definitions (filter (/= anchor) (calledMethods (methodBody definition)))])
    "An injected Context reaches its anchor through another method; call the anchor directly"
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
        (map makeChain mounts) chainDefinitions graph scopes names []
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
    resources = [resource | effect <- effects, Just resource <- [effectResource effect]]
    defaults = [MethodDefinition method owner role (defaultBody effect role)
      | effect <- effects, (_, owner) : _ <- [effectMethods effect], (role, method) <- effectMethods effect]
    defaultBody effect ContextRequire
      | effectName effect `notElem` resources
      , Just producing <- lookup ContextRequest (effectMethods effect) = Choice [Empty, Call producing]
    defaultBody _ _ = Empty
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
        , (ContextRequire, method) <- effectMethods effect] of
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
  [definition { methodBody = injected (methodIdentity definition) (written definition) } | definition <- defaults]
  where
    written definition = maybe (methodBody definition) id (lookup (methodIdentity definition) shapes)
    bodyOf selected = maybe Empty written (listToMaybe [definition | definition <- defaults, methodIdentity definition == selected])
    injected selected body = case [replayed selected (bodyOf produced) | (anchor, produced) <- anchors effects, anchor == selected] of
      [] -> body
      contexts -> Sequence [body, Choice [Empty, Sequence contexts]]
    replayed anchor shape = case shape of
      Call method | method == anchor -> Empty
      Sequence children -> Sequence (map (replayed anchor) children)
      Choice children -> Choice (map (replayed anchor) children)
      Recover body recovery -> Recover (replayed anchor body) (replayed anchor recovery)
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
