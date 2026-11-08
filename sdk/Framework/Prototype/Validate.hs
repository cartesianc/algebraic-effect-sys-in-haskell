{-# LANGUAGE DuplicateRecordFields #-}

-- Prototype 的自洽校验与 AST 快照核对。gen 在构图后与命中缓存时校验；
-- 运行与展示只用 matchWorkflowLayer／validateWorkflow 核对当前 AST 是否就是编译时的那一份。
module Framework.Prototype.Validate
  ( validatePrototype, validateWorkflow, matchWorkflowLayer
  , valid, unique, sameSet
  ) where

import Control.Monad (unless)
import Data.List (nub, sort, (\\))
import Framework.Language.AST (AST, WorkflowF(..), foldAST)
import Framework.Language.Registration (EffectKind(..), EffectSpec(..))
import qualified Framework.Language.Registration as Registration
import Framework.Prototype.Graph
import Framework.Prototype.Query
import Framework.Prototype.Types

valid :: Bool -> String -> Either (PrototypeError method) ()
valid condition reason = unless condition (Left (InvalidPrototype reason))

unique :: Eq value => [value] -> Bool
unique values = length values == length (nub values)

sameSet :: Ord value => [value] -> [value] -> Bool
sameSet left right = sort (nub left) == sort (nub right)

-- 运行装配和纯展示共用层校验，不再为执行检查重复 fold 当前 AST。
matchWorkflowLayer :: WorkflowF child -> WorkflowTree -> Either (PrototypeError method) [WorkflowTree]
matchWorkflowLayer (Node selected) (NodeAt _ expected)
  | selected == expected = pure []
matchWorkflowLayer (Chained children) (ChainedAt _ expected)
  | length children == length expected = pure expected
matchWorkflowLayer (Parallel children) (ParallelAt _ expected)
  | length children == length expected = pure expected
matchWorkflowLayer (Alternative children) (AlternativeAt _ _ expected)
  | length children == length expected = pure expected
matchWorkflowLayer (Lifelong children) (LifelongAt _ _ expected)
  | length children == length expected = pure expected
matchWorkflowLayer _ _ = Left PrototypeWorkflowMismatch

validateWorkflow :: Prototype method -> AST -> Either (PrototypeError method) ()
validateWorkflow prototype ast = foldAST check ast (protoWorkflow prototype)
  where
    check layer expected = do
      children <- matchWorkflowLayer layer expected
      sequence_ (zipWith ($) (childChecks layer) children)
    childChecks (Node _) = []
    childChecks (Chained children) = children
    childChecks (Parallel children) = children
    childChecks (Alternative children) = children
    childChecks (Lifelong children) = children

-- 只核对显式字段的自洽性，不展开 methodBody、不重构图或修正手调 scope 父边。
validatePrototype :: (Ord method, Show method) => Prototype method -> Either (PrototypeError method) ()
validatePrototype prototype = do
  valid (unique (map name registrations) && unique (map effectName effects)) "Duplicate registered effect"
  valid (map name registrations == map effectName effects) "Effect prototypes differ from registrations"
  valid (and [effectInput effect == input registration
      && effectKind effect == Registration.effectKind (typing registration)
    | (registration, effect) <- zip registrations effects]) "Effect metadata differs from registration snapshot"
  valid (unique allMethodIds) "Duplicate method definition"
  valid (sameSet allMethodIds (concatMap (map snd . effectMethods) effects)) "Effect method coverage differs"
  valid (and [any (\definition -> methodIdentity definition == method
      && methodRole definition == role && methodEffect definition == owner) definitions
    | effect <- effects, (_, owner) : _ <- [effectMethods effect], (role, method) <- effectMethods effect])
    "Method roles or effect identities differ from effect prototypes"
  valid (all (`elem` allMethodIds) [methodEffect definition | definition <- definitions]) "Unknown method effect identity"
  valid (all (`elem` allMethodIds) (concatMap (calledMethods . methodBody) definitions)) "Unknown method body reference"
  valid (unique methodIds) "Duplicate graph method identity"
  valid (all (`elem` definitions) (graphMethods graph)) "Graph definitions differ from prototype definitions"
  valid (unique (graphRoots graph)) "Duplicate graph root"
  valid (all (`elem` methodIds) (graphRoots graph)) "Unknown graph root"
  valid (sameSet (map chainEntry chains) (graphRoots graph)) "Mounted chains differ from graph roots"
  valid (all (knownPair methodIds) (graphReferences graph)) "Unknown method reference"
  valid (unique observedScopes) "Duplicate graph scope identity"
  valid (sameSet observedScopes [methodIdentity method | method <- graphMethods graph, methodRole method == ScopeOpen])
    "Graph scope identities do not match its open methods"
  valid (all (`elem` observedScopes) (concat (graphScopePaths graph))) "Unknown scope in graph path"
  valid (sameSet observedScopes (concat (graphScopePaths graph))) "Graph scope path coverage differs"
  valid (unique (map fst (graphRootPaths graph)) && sameSet (map fst (graphRootPaths graph)) (graphRoots graph)) "Graph entry path coverage differs"
  valid (all (all (all (`elem` observedScopes)) . snd) (graphRootPaths graph)) "Unknown scope in entry path"
  valid (sameSet (concatMap snd (graphRootPaths graph)) (graphScopePaths graph)
    || null (graphRoots graph) && graphScopePaths graph == [[]]) "Graph paths differ from entry paths"
  valid (all (knownPair observedScopes) (graphScopeOrder graph)) "Unknown scope in graph order"
  valid (unique (map fst names) && unique (map snd names)) "Duplicate scope identity or name"
  valid (sameSet names [(method, effectName effect) | effect <- effects, (ScopeOpen, method) <- effectMethods effect])
    "Scope names differ from the registered open methods"
  valid (all (\(identity, _) -> any (\definition -> methodIdentity definition == identity && methodRole definition == ScopeOpen) definitions) names)
    "Scope name does not reference an open method"
  valid (unique nodeIds) "Duplicate scope node"
  valid (sameSet (map fst names) nodeIds) "Scope names do not cover exactly the tree nodes"
  valid (all (`elem` nodeIds) observedScopes) "Missing observed scope identity"
  mapM_ validateScopeNode (scopeNodes tree)
  valid (sameSet parentEdges childEdges) "Scope parent and child references disagree"
  expectedLayers <- layers nodeIds
  valid (unique (scopeRoots tree) && sameSet (scopeRoots tree) [scopeIdentity node' | node' <- scopeNodes tree, null (scopeParents node')])
    "Scope roots disagree with parent references"
  valid (length expectedLayers == length (scopeLayers tree)
    && and (zipWith sameSet expectedLayers (scopeLayers tree)) && unique (concat (scopeLayers tree)))
    "Scope layers disagree with parent references"
  valid (sameSet (scopePaths tree) (graphScopePaths graph)) "Scope tree paths differ from the generated graph"
  valid (sameSet (scopeCandidates tree) (graphScopeOrder graph)) "Scope candidates differ from the generated graph"
  valid (all (knownPair nodeIds) (scopeOpposed tree ++ scopeUndetermined tree)) "Unknown scope in order evidence"
  checkWorkflow [] (protoWorkflow prototype)
  valid (protoSessions prototype == finiteSessions effects) "Interpreter sessions differ from the Receive assets"
  valid (unique (map chainNode chains)) "Duplicate mounted chain NodeId"
  valid (sameSet (map chainNode chains) expectedChainIds) "Mounted chain coverage differs from workflow"
  mapM_ validateChain chains
  valid (unique (map definitionEntry chainDefinitions)) "Duplicate chain definition"
  valid (sameSet (map definitionEntry chainDefinitions)
    [method | effect <- effects, (role, method) <- effectMethods effect
      , role `elem` [HandlerMethod, ScopeOpen, ContextRequest, ContextRequire, ContextStream, StreamHandler]])
    "Chain definitions do not cover the registered entries"
  mapM_ validateDefinition chainDefinitions
  valid (unique (map fst (protoSources prototype))) "Duplicate asset read point"
  mapM_ validateSource (protoSources prototype)
  mapM_ (\chain -> do
    valid (unique (chainDrives chain) && all (`elem` contracts) (chainDrives chain)) "Invalid driven asset contracts"
    valid (unique (chainReads chain) && sameSet (chainReads chain)
      [readContract point | (point, _) <- protoSources prototype, readNode point == chainNode chain])
      "Chain reads differ from the source table") chains
  where
    registrations = protoRegistrations prototype
    effects = protoEffects prototype
    definitions = protoMethods prototype
    allMethodIds = map methodIdentity definitions
    graph = protoGraph prototype
    tree = protoScopes prototype
    names = protoScopeNames prototype
    chains = protoChains prototype
    chainDefinitions = protoChainDefinitions prototype
    contracts = [contractType | effect <- effects, Just contractType <- [effectProduces effect]]
    validateSource (point, source) = do
      _ <- lookupChain prototype (readNode point)
      valid (readContract point `elem` contracts) "Read point has no base Context contract"
      case source of
        FromOwnChain -> pure ()
        FromSession -> valid (readContract point `elem` [sessionAsset session | session <- protoSessions prototype])
          "Session source has no interpreter session"
        FromChains selected -> do
          valid (not (null selected) && unique selected) "Invalid asset source alternatives"
          mapM_ (\node' -> do
            chain <- lookupChain prototype node'
            valid (node' /= readNode point && precedes (protoWorkflow prototype) node' (readNode point))
              "Asset source is not a completed visible chain"
            valid (readContract point `elem` chainDrives chain) "Asset source has no matching production") selected
    methodIds = map methodIdentity (graphMethods graph)
    observedScopes = graphScopes graph
    nodeIds = map scopeIdentity (scopeNodes tree)
    parentEdges = [(parent, scopeIdentity node') | node' <- scopeNodes tree, parent <- scopeParents node']
    childEdges = [(scopeIdentity node', child) | node' <- scopeNodes tree, child <- scopeChildren node']
    knownPair known (left, right) = left `elem` known && right `elem` known
    validateScopeNode node' = do
      let linked = scopeParents node' ++ scopeChildren node'
      valid (all (`elem` nodeIds) linked) "Unknown scope parent or child"
      valid (scopeIdentity node' `notElem` linked) "Scope node refers to itself"
      valid (unique (scopeParents node') && unique (scopeChildren node')) "Duplicate scope parent or child"
    parents selected = [parent | (parent, child) <- parentEdges, child == selected]
    layers [] = Right []
    layers remaining =
      let ready = [selected | selected <- remaining, all (`notElem` remaining) (parents selected)]
      in if null ready then Left (InvalidEffectGraph (CyclicScopeRelations remaining))
         else (ready :) <$> layers (remaining \\ ready)
    expectedChainIds = concat [case selected of
      NodeAt identifier _ -> [identifier]
      AlternativeAt _ choice _ -> [alternativeSelector choice]
      LifelongAt _ described _ -> concatMap sessionMounts (lifelongSessions described)
      _ -> [] | selected <- allWorkflow (protoWorkflow prototype)]
      ++ concatMap sessionMounts (protoSessions prototype)
    checkWorkflow expected selected = do
      valid (workflowNode selected == expected) "Workflow NodeId differs from AST path"
      case selected of
        NodeAt _ terminal -> do
          effect <- findEffectProto effects terminal
          valid (effectKind effect `notElem` [ContextKind, ErrorKind, StreamKind]) "Workflow node is not an origin chain"
        AlternativeAt identifier choice children -> do
          valid (alternativeSelector choice == identifier ++ [-1]) "Alternative selector has an invalid NodeId"
          valid (map fst (alternativeCases choice) == map workflowNode children) "Alternative case paths differ from children"
          let constructors = concat [map snd (effectBranches effect) | effect <- effects,
                effectProduces effect == Just (alternativeContract choice)]
              selectedCases = map snd (alternativeCases choice)
          valid (not (null constructors) && unique selectedCases && sameSet selectedCases constructors)
            "Alternative cases do not cover the contract constructors"
          declaredCases <- mapM (candidateCase effects identifier) children
          valid (declaredCases == [(alternativeContract choice, constructor) | constructor <- selectedCases])
            "Alternative cases differ from candidate requirements"
        LifelongAt identifier described children -> do
          let inner = concatMap allWorkflow children
              mounted = [(node', terminal) | NodeAt node' terminal <- inner]
          valid (null [() | LifelongAt {} <- inner]) "Lifelong is nested"
          valid (sameSet (lifelongUnits described) (concat [case child of
              ParallelAt _ grand -> map workflowNode grand
              _ -> [workflowNode child] | child <- children])) "Lifelong units differ from its children"
          valid (sameSet (map fst (lifelongSubscriptions described)) (map fst mounted)
            && unique (map fst (lifelongSubscriptions described))) "Lifelong subscriptions differ from its targets"
          valid (sameSet (map sessionAsset (lifelongSessions described)) (nub (map snd (lifelongSubscriptions described)))
            && unique (map sessionAsset (lifelongSessions described))) "Lifelong sessions differ from subscribed assets"
          valid (and [ sessionMounts session == [identifier ++ [-1, index, step] | step <- [0 .. steps - 1]]
            | (index, session) <- zip [0 ..] (lifelongSessions described)
            , let steps = sessionSteps (sessionPlan session) ])
            "Lifelong session mounts have invalid NodeIds"
          valid (and [ any (\effect -> effectContinuous effect && effectProduces effect == Just contractType) effects
            | (_, contractType) <- lifelongSubscriptions described ]) "Lifelong subscribes to a non-continuous asset"
        _ -> pure ()
      sequence_ [checkWorkflow (expected ++ [index]) child | (index, child) <- zip [0 ..] (workflowChildren selected)]
    validateChain chain = do
      valid (unique (chainReaches chain) && all (`elem` allMethodIds) (chainReaches chain)
        && chainEntry chain `elem` chainReaches chain) "Invalid reachable method set"
      valid (lookup (chainEntry chain) (graphRootPaths graph) == Just (chainScopePaths chain)) "Chain scope paths differ from graph root"
      valid ([definitionReaches definition | definition <- chainDefinitions,
        definitionEntry definition == chainEntry chain] == [chainReaches chain])
        "Mounted chain differs from its method definition"
      case chainRole chain of
        NodeChain -> case lookupWorkflow (protoWorkflow prototype) (chainNode chain) of
          Just (NodeAt _ terminal) -> do
            valid (terminal == chainTerminal chain) "Chain terminal differs from workflow"
            effect <- findEffectProto effects terminal
            entry <- ordinaryEntry effect
            valid (entry == chainEntry chain) "Chain entry differs from effect entry"
          _ -> Left (InvalidPrototype "Node chain has no workflow node")
        SelectorChain -> case [choice | AlternativeAt _ choice _ <- allWorkflow (protoWorkflow prototype),
            alternativeSelector choice == chainNode chain] of
          [choice] -> valid (alternativeContract choice == chainTerminal chain
            && chainEntry chain `elem` [method | effect <- effects, effectProduces effect == Just (chainTerminal chain)
              , (ContextRequire, method) <- effectMethods effect]) "Selector chain differs from alternative"
          _ -> Left (InvalidPrototype "Selector chain has no alternative")
        SessionChain -> case [ (session, step)
            | session <- concatMap (lifelongSessions . snd) (workflowLifelongs (protoWorkflow prototype))
                ++ protoSessions prototype
            , (step, mount) <- zip [0 :: Int ..] (sessionMounts session), mount == chainNode chain ] of
          [(session, step)] -> do
            producer <- case [effect | effect <- effects, effectProduces effect == Just (sessionAsset session)] of
              [effect] -> pure effect
              _ -> Left (InvalidPrototype "Session asset has no producer")
            let expectedRole = case (sessionPlan session, step) of
                  (Receive _, 0) -> Nothing
                  (Receive _, _) -> Just ContextStream
                streamEntries = case sessionPlan session of
                  Receive source -> [method | effect <- effects, effectName effect == source
                    , (StreamHandler, method) <- effectMethods effect]
                expected = maybe streamEntries (\role -> [method | (role', method) <- effectMethods producer, role' == role]) expectedRole
            valid (sessionAsset session == chainTerminal chain && expected == [chainEntry chain])
              "Session chain differs from its boot plan"
          _ -> Left (InvalidPrototype "Session chain has no session")
    validateDefinition definition = do
      effect <- findEffectProto effects (definitionEffect definition)
      let roles = [role | (role, method) <- effectMethods effect, method == definitionEntry definition]
          expectedRoles = case definitionKind definition of
            OriginChain -> [HandlerMethod, ScopeOpen]
            ContextChain -> [ContextRequest, ContextRequire, ContextStream, StreamHandler]
      valid (not (null roles) && all (`elem` expectedRoles) roles) "Chain kind differs from its method role"
      valid (unique (definitionReaches definition) && all (`elem` allMethodIds) (definitionReaches definition)
        && definitionEntry definition `elem` definitionReaches definition) "Invalid chain definition reachability"
