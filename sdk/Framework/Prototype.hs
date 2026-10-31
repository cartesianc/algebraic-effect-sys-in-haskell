{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveFunctor #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DuplicateRecordFields #-}

-- 注册、方法定义与 AST 挂载的唯一静态原型；不包含闭包或运行中的资源。
module Framework.Prototype
  ( NodeId, SumTypes, Prototype(..), PrototypePlan(..), EffectProto(..)
  , WorkflowTree(..), AlternativeProto(..), ChainRole(..), ChainProto(..)
  , ChainKind(..), ChainDefinition(..), ReadPoint(..), Source(..), PrototypeError(..)
  , buildEffectProtos, preparePrototype, buildPreparedPrototype, buildPrototype
  , validatePrototype, validateWorkflow, matchWorkflowLayer, checkDriven
  , expandChain, reachableMethods, calledMethods
  , lookupChain, lookupWorkflow, workflowNode, workflowChildren
  , workflowTerminals, workflowSelectors, precedes, exclusive, visibleFrom
  ) where

import Control.DeepSeq (NFData)
import Control.Monad (unless)
import Data.Char (isAlphaNum, isUpper)
import Data.List (intercalate, intersect, isPrefixOf, nub, sort, (\\))
import Data.Maybe (listToMaybe, maybeToList)
import GHC.Generics (Generic)
import Framework.Effect.Contract (EffectKind(..))
import Framework.Effect.Graph
import Framework.Effect.Registration hiding (effectKind)
import qualified Framework.Effect.Registration as Registration
import Framework.Recursion (Fix(..), cata)
import Framework.Workflow.AST (AST, WorkflowF(..), foldAST)

type NodeId = [Int]
type SumTypes = [(String, [(String, Maybe String)])]

data Prototype method = Prototype
  { protoRegistrations :: [EffectSpec]
  , protoEffects :: [EffectProto method]
  , protoMethods :: [MethodDefinition method]
  , protoWorkflow :: WorkflowTree
  , protoChains :: [ChainProto method]
  , protoChainDefinitions :: [ChainDefinition method]
  , protoGraph :: EffectGraph method
  , protoScopes :: ScopeTree method
  , protoScopeNames :: [(method, String)]
  , protoSources :: [(ReadPoint, Source)]
  } deriving (Eq, Show, Read, Functor, Generic, NFData)

-- 声明接口先于 Handlers 存在；准备阶段只运行一次，方法解析后补全同一份计划。
data PrototypePlan = PrototypePlan
  { plannedRegistrations :: [EffectSpec]
  , plannedEffects :: [EffectProto String]
  , plannedWorkflow :: WorkflowTree
  } deriving (Eq, Show, Read, Generic, NFData)

data EffectProto method = EffectProto
  { effectName :: String
  , effectKind :: EffectKind
  , effectInput :: String
  , effectMethods :: [(MethodRole, method)]
  , effectDemands :: [ResolvedDemand]
  , effectProduces :: Maybe String
  , effectBranches :: [(String, String)]
  , effectAnchor :: Maybe String
  , effectScopes :: [String]
  , effectErrorScope :: Maybe String
  , effectInputChain :: [String]
  , effectScopeParents :: [String]
  , effectOpeningInputs :: [String]
  , effectNearestScopes :: [String]
  , effectResource :: Maybe String
  , effectContextDependencies :: [String]
  } deriving (Eq, Show, Read, Functor, Generic, NFData)

data WorkflowTree
  = NodeAt NodeId String
  | ChainedAt NodeId [WorkflowTree]
  | ParallelAt NodeId [WorkflowTree]
  | AlternativeAt NodeId AlternativeProto [WorkflowTree]
  deriving (Eq, Show, Read, Generic, NFData)

data AlternativeProto = AlternativeProto
  { alternativeContract :: String
  , alternativeSelector :: NodeId
  , alternativeCases :: [(NodeId, String)]
  } deriving (Eq, Show, Read, Generic, NFData)

data ChainRole = NodeChain | SelectorChain
  deriving (Eq, Show, Read, Generic, NFData)

data ChainProto method = ChainProto
  { chainNode :: NodeId
  , chainRole :: ChainRole
  , chainTerminal :: String
  , chainEntry :: method
  , chainReaches :: [method]
  , chainDrives :: [String]
  , chainReads :: [String]
  , chainScopePaths :: [[method]]
  } deriving (Eq, Show, Read, Functor, Generic, NFData)

-- 定义身份属于方法；NodeId 只属于 AST 挂载。同一 origin 定义可挂载多次，
-- Context 生产／读取链由 demand 进入，始终没有虚构的 AST 路径。
data ChainKind = OriginChain | ContextChain
  deriving (Eq, Show, Read, Generic, NFData)

data ChainDefinition method = ChainDefinition
  { definitionKind :: ChainKind
  , definitionEffect :: String
  , definitionEntry :: method
  , definitionReaches :: [method]
  } deriving (Eq, Show, Read, Functor, Generic, NFData)

data ReadPoint = ReadPoint { readNode :: NodeId, readContract :: String }
  deriving (Eq, Show, Read, Generic, NFData)

data Source = FromChain NodeId | FromOwnChain
  deriving (Eq, Show, Read, Generic, NFData)

data PrototypeError method
  = InvalidPrototype String
  | InvalidEffectGraph (GraphError method)
  | UnknownPrototypeTarget String
  | InvalidAlternative NodeId String
  | PrototypeWorkflowMismatch
  deriving (Eq, Show, Read, Functor, Generic, NFData)

valid :: Bool -> String -> Either (PrototypeError method) ()
valid condition reason = unless condition (Left (InvalidPrototype reason))

unique :: Eq value => [value] -> Bool
unique values = length values == length (nub values)

sameSet :: Ord value => [value] -> [value] -> Bool
sameSet left right = sort (nub left) == sort (nub right)

fromRegistration :: Either String value -> Either (PrototypeError String) value
fromRegistration = either (Left . InvalidPrototype) Right

-- 注册关系的标准解析。Codegen 读取这些事实生成契约与包装，不再自行推导。
buildEffectProtos :: [EffectSpec] -> SumTypes -> Either (PrototypeError String) [EffectProto String]
buildEffectProtos specifications sumTypes = do
  valid (unique (map name specifications)) "Duplicate effect name"
  valid (all ((/= "Root") . name) specifications) "Root is reserved"
  valid (unique [contractOf producing | specification <- specifications,
    Context (Just producing) <- [typing specification]]) "Duplicate Context contract"
  mapM_ (\specification -> mapM_ (\demand -> valid (validContractName (contract demand))
      ("Demanded contract must be a contract name such as StartURL: " ++ contract demand
        ++ " in " ++ name specification)) (demands specification)) specifications
  resolved <- mapM (fromRegistration . resolveDemands branchTable specifications) specifications
  dependencies <- mapM (fromRegistration . contextNames branchTable specifications . pure . name) specifications
  let table = zip (map name specifications) resolved
      resolvedOf selected = maybe [] id (lookup selected table)
      providers mode specification = nub
        [demandProvider demand | demand <- resolvedOf (name specification), demandAccess demand == mode]
      requested = providers RequestAccess
      required = providers RequireAccess
      requestSource = listToMaybe . requested
      operations specification = nub (input specification : requested specification)
      scopes seen selected
        | selected `elem` seen = []
        | otherwise = concat
            [concatMap (scopes (selected : seen)) (operations specification)
              ++ [selected | Scoped {} <- [typing specification]]
            | specification <- specifications, name specification == selected]
      upstream specification = nub (concatMap (scopes []) (operations specification))
      nearest seen selected
        | selected `elem` seen = []
        | otherwise = concat
            [case typing specification of
              Scoped {} -> [selected]
              _ -> concatMap (nearest (selected : seen)) (operations specification)
            | specification <- specifications, name specification == selected]
      errorScopes specification = nub
        (concatMap (nearest [name specification]) (operations specification))
      requiredSources seen selected
        | selected `elem` seen = []
        | otherwise = nub $ concat
            [let sources = required specification
             in sources ++ concatMap (requiredSources (selected : seen)) (operations specification ++ sources)
            | specification <- specifications, name specification == selected]
      parents specification = filter (/= name specification) $ nub
        (upstream specification ++ [name owner
          | source <- requiredSources [] (name specification)
          , source `notElem` requested specification
          , owner <- specifications, Scoped (Just _) _ <- [typing owner]
          , requestSource owner == Just source])
      valueInputs seen selected
        | selected `elem` seen = []
        | otherwise = concat
            [requested producer ++ required producer
              ++ concatMap (valueInputs (selected : seen)) (requested producer)
            | producer <- specifications, name producer == selected]
      inputAncestors "Root" = []
      inputAncestors selected = selected : concat
        [inputAncestors (input specification) | specification <- specifications, name specification == selected]
      make specification contextDependencies = EffectProto
        { effectName = name specification
        , effectKind = Registration.effectKind (typing specification)
        , effectInput = input specification
        , effectMethods = registeredMethods specification
        , effectDemands = resolvedOf (name specification)
        , effectProduces = case typing specification of
            Context (Just producing) -> Just (contractOf producing)
            _ -> Nothing
        , effectBranches = branchesOf specification
        , effectAnchor = case typing specification of
            Context {} -> listToMaybe
              [name anchor | anchor <- specifications, name anchor == input specification
                , Registration.effectKind (typing anchor) `elem` [ExcuKind, ScopedKind]
                , Just _ <- [entryMethod (typing anchor)]]
            _ -> Nothing
        , effectScopes = upstream specification
        , effectErrorScope = case typing specification of
            Error {} -> listToMaybe (errorScopes specification)
            _ -> Nothing
        , effectInputChain = inputAncestors (input specification)
        , effectScopeParents = parents specification
        , effectOpeningInputs = case typing specification of
            Scoped {} -> nub (concatMap (valueInputs []) (maybeToList (requestSource specification)))
            _ -> []
        , effectNearestScopes = nub (nearest [] (name specification))
        , effectResource = case typing specification of Scoped {} -> requestSource specification; _ -> Nothing
        , effectContextDependencies = contextDependencies
        }
      prototypes = zipWith make specifications dependencies
      findSpec selected = case filter ((== selected) . name) specifications of
        [specification] -> Right specification
        _ -> Left (UnknownPrototypeTarget selected)
      checkScope selected = do
        specification <- findSpec selected
        case typing specification of
          Scoped (Just _) (Just _) -> pure ()
          _ -> Left (InvalidPrototype ("Input scope needs Scoped.open and Scoped.close: " ++ selected))
      checkHandled (RaisedBy selected) = findSpec selected >> pure ()
      checkHandled (ScopeFaultIn selected) = do
        target <- findSpec selected
        valid (Registration.effectKind (typing target) == ScopedKind) ("ScopeFaultIn must name a Scoped effect: " ++ selected)
      checkHandled (ContextFaultIn selected) = do
        target <- findSpec selected
        valid (Registration.effectKind (typing target) == ContextKind) ("ContextFaultIn must name a Context effect: " ++ selected)
      check specification = do
        unless (input specification == "Root") $ do
          predecessor <- findSpec (input specification)
          valid (Registration.effectKind (typing predecessor) /= ContextKind)
            ("Input cannot reference Context " ++ name predecessor ++ " in " ++ name specification ++ "; use demands")
        mapM_ checkScope (upstream specification)
        case typing specification of
          Scoped opening closing -> do
            valid (length (requested specification) <= 1) ("Scoped requests at most one resource Context: " ++ name specification)
            valid (opening == Nothing || closing /= Nothing) ("Scoped.open needs Scoped.close for automatic cleanup: " ++ name specification)
          Context Nothing -> Left (InvalidPrototype ("Context needs request = requester \"handler\" @Representation: " ++ name specification))
          Context (Just producing) -> do
            case representation producing of
              TypeRef _ -> pure ()
              _ -> Left (InvalidPrototype ("Context.request must wrap a business value, not Output: " ++ name specification))
            valid (null [() | anchor <- specifications, name anchor == input specification,
              Scoped {} <- [typing anchor], requestSource anchor == Just (name specification)])
              ("Context " ++ name specification ++ " cannot hang below the scope that requests it as its resource")
          Error { handles = matched } -> do
            valid (not (null matched)) ("Error must declare the failures it handles: " ++ name specification)
            mapM_ checkHandled matched
            valid (length (errorScopes specification) <= 1) ("Error capability reaches several nearest scopes: " ++ name specification)
          _ -> pure ()
        valid (null [demand | demand <- demands specification, access demand == RequestAccess,
          contract demand `elem` map fst branchTable]) ("Branch contracts can only be required: " ++ name specification)
      handled specification = case typing specification of Error { handles = matched } -> matched; _ -> []
  mapM_ check specifications
  valid (unique (concatMap (map snd . effectMethods) prototypes)) "Registered method names must be unique"
  valid (null [(name left, name right)
    | (index, left) <- zip [0 :: Int ..] specifications, right <- drop (index + 1) specifications
    , not (null (handled left `intersect` handled right)), errorScopes left == errorScopes right])
    "Error policies handle the same failure for the same scope"
  pure prototypes
  where
    validContractName selected = case selected of
      first : rest -> isUpper first && all (\character -> isAlphaNum character || character `elem` "_'") rest
      [] -> False
    branchesOf specification = case typing specification of
      Context (Just producing) | TypeRef typeName <- representation producing
        , Just constructors <- lookup typeName sumTypes, length constructors > 1 ->
          [(contractOf producing ++ constructor, constructor) | (constructor, _) <- constructors]
      _ -> []
    branchTable = [(branch, contractOf producing)
      | specification <- specifications, Context (Just producing) <- [typing specification]
      , (branch, _) <- branchesOf specification]

registeredMethods :: EffectSpec -> [(MethodRole, String)]
registeredMethods specification = case typing specification of
  Pure method -> [(HandlerMethod, selected) | selected <- maybeToList method]
  Excu method -> [(HandlerMethod, selected) | selected <- maybeToList method]
  Scoped opening closing -> [(ScopeOpen, selected) | selected <- maybeToList opening]
    ++ [(ScopeClose, selected) | selected <- maybeToList closing]
  Error detecting resolving _ -> [(ErrorDetect, selected) | selected <- maybeToList detecting]
    ++ [(ErrorResolve, selected) | selected <- maybeToList resolving]
  selected@(Context producing) -> [(ContextRequest, method) | Just Requester { handler = method } <- [producing]]
    ++ [(ContextRequire, method) | method <- maybeToList (contextReader selected)]

workflowNode :: WorkflowTree -> NodeId
workflowNode (NodeAt identifier _) = identifier
workflowNode (ChainedAt identifier _) = identifier
workflowNode (ParallelAt identifier _) = identifier
workflowNode (AlternativeAt identifier _ _) = identifier

workflowChildren :: WorkflowTree -> [WorkflowTree]
workflowChildren (NodeAt _ _) = []
workflowChildren (ChainedAt _ children) = children
workflowChildren (ParallelAt _ children) = children
workflowChildren (AlternativeAt _ _ children) = children

workflowTerminals :: WorkflowTree -> [String]
workflowTerminals (NodeAt _ selected) = [selected]
workflowTerminals tree = concatMap workflowTerminals (workflowChildren tree)

workflowSelectors :: WorkflowTree -> [String]
workflowSelectors tree = case tree of
  AlternativeAt _ selected children -> alternativeContract selected : concatMap workflowSelectors children
  _ -> concatMap workflowSelectors (workflowChildren tree)

preparePrototype :: [EffectSpec] -> SumTypes -> Fix WorkflowF -> Either (PrototypeError String) PrototypePlan
preparePrototype specifications sumTypes tree = do
  effects <- buildEffectProtos specifications sumTypes
  workflow <- numberWorkflow effects tree
  pure (PrototypePlan specifications effects workflow)

numberWorkflow :: [EffectProto String] -> Fix WorkflowF -> Either (PrototypeError String) WorkflowTree
numberWorkflow effects tree = cata number tree []
  where
    number (Node selected) path = do
      effect <- findEffectProto effects selected
      valid (effectKind effect `notElem` [ContextKind, ErrorKind])
        ("AST terminal must be an original callable handle: " ++ selected)
      _ <- ordinaryEntry effect
      pure (NodeAt path selected)
    number (Chained children) path = ChainedAt path <$> descend path children
    number (Parallel children) path = ParallelAt path <$> descend path children
    number (Alternative children) path = do
      parts <- descend path children
      cases <- mapM (candidateCase effects path) parts
      contractType <- case nub (map fst cases) of
        [selected] -> Right selected
        _ -> invalid path "Candidates must depend on the same branch contract"
      let constructors = map snd cases
          declared = concat [map snd (effectBranches effect) | effect <- effects, effectProduces effect == Just contractType]
      unless (unique constructors && sort constructors == sort declared) $
        invalid path "Candidates must cover every constructor exactly once"
      pure (AlternativeAt path (AlternativeProto contractType (path ++ [-1])
        (zip (map workflowNode parts) constructors)) parts)
    descend path children = sequence [child (path ++ [index]) | (index, child) <- zip [0 ..] children]
    invalid path reason = Left (InvalidAlternative path reason)

-- 候选对应只读 effect 原型中的 requires 与 Input 祖先；生成和加载校验共用。
candidateCase :: [EffectProto method] -> NodeId -> WorkflowTree
              -> Either (PrototypeError method) (String, String)
candidateCase effects path subtree = do
  cases <- mapM terminalCase (workflowTerminals subtree)
  case nub cases of
    [selected] -> pure selected
    _ -> invalid "Every candidate terminal must select the same constructor"
  where
    terminalCase selected = do
      effect <- findEffectProto effects selected
      let inherited = selected : effectInputChain effect
          cases = nub [(base, constructor)
            | consumer <- effects, effectName consumer `elem` inherited
            , demand <- effectDemands consumer, demandAccess demand == RequireAccess
            , producer <- effects, Just base <- [effectProduces producer]
            , (branch, constructor) <- effectBranches producer, branch == demandContract demand]
      case cases of
        [selectedCase] -> pure selectedCase
        _ -> invalid ("Candidate must require exactly one branch contract: " ++ selected)
    invalid reason = Left (InvalidAlternative path reason)

findEffectProto :: [EffectProto method] -> String -> Either (PrototypeError method) (EffectProto method)
findEffectProto effects selected = case filter ((== selected) . effectName) effects of
  [effect] -> Right effect
  _ -> Left (UnknownPrototypeTarget selected)

ordinaryEntry :: EffectProto method -> Either (PrototypeError method) method
ordinaryEntry effect = case [method | (role, method) <- effectMethods effect, role `elem` [HandlerMethod, ScopeOpen]] of
  method : _ -> pure method
  [] -> Left (InvalidPrototype ("Effect has no callable entry (handler/open = Nothing): " ++ effectName effect))

buildPrototype :: [EffectSpec] -> SumTypes -> [(String, MethodShape String)] -> Fix WorkflowF
               -> Either (PrototypeError String) (Prototype String)
buildPrototype specifications sumTypes shapes tree = do
  prepared <- preparePrototype specifications sumTypes tree
  buildPreparedPrototype prepared shapes

buildPreparedPrototype :: PrototypePlan -> [(String, MethodShape String)]
                       -> Either (PrototypeError String) (Prototype String)
buildPreparedPrototype plan shapes = do
  valid (unique (map fst shapes)) "Duplicate handler method in the structure generation plan"
  valid (all (`elem` map methodIdentity defaults) (map fst shapes)) "Unregistered handler method in the structure generation plan"
  let definitions = mergedDefinitions effects defaults shapes
  valid (null [(anchor, produced) | (anchor, produced) <- anchors effects
      , definition <- definitions, methodIdentity definition == produced
      , anchor `elem` reachableMethods definitions (filter (/= anchor) (calledMethods (methodBody definition)))])
    "An injected Context reaches its anchor through another method; call the anchor directly"
  mounted <- mapM mountedNode (allWorkflow workflow) >>= pure . concat
  selectors <- mapM mountedSelector [selected | selected@AlternativeAt {} <- allWorkflow workflow]
  let mounts = mounted ++ selectors
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
            _ -> Nothing]]
      result = Prototype (plannedRegistrations plan) effects definitions workflow (map makeChain mounts)
        chainDefinitions graph scopes names []
  validatePrototype result
  pure result
  where
    effects = plannedEffects plan
    workflow = plannedWorkflow plan
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

calledMethods :: MethodShape method -> [method]
calledMethods Empty = []
calledMethods (Call method) = [method]
calledMethods (Sequence children) = concatMap calledMethods children
calledMethods (Choice children) = concatMap calledMethods children
calledMethods (Recover body recovery) = calledMethods body ++ calledMethods recovery

reachableMethods :: Eq method => [MethodDefinition method] -> [method] -> [method]
reachableMethods definitions = visit []
  where
    visit seen [] = seen
    visit seen (method : rest)
      | method `elem` seen = visit seen rest
      | otherwise = visit (seen ++ [method])
          (concat [calledMethods (methodBody definition) | definition <- definitions, methodIdentity definition == method] ++ rest)

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

allWorkflow :: WorkflowTree -> [WorkflowTree]
allWorkflow tree = tree : concatMap allWorkflow (workflowChildren tree)

knownWorkflowPosition :: WorkflowTree -> NodeId -> Bool
knownWorkflowPosition tree selected = any ((== selected) . workflowNode) nodes
  || selected `elem` [alternativeSelector choice | AlternativeAt _ choice _ <- nodes]
  where nodes = allWorkflow tree

lookupChain :: Prototype method -> NodeId -> Either (PrototypeError method) (ChainProto method)
lookupChain prototype identifier = case filter ((== identifier) . chainNode) (protoChains prototype) of
  [chain] -> pure chain
  _ -> Left (InvalidPrototype ("Missing or duplicate chain at " ++ show identifier))

lookupWorkflow :: WorkflowTree -> NodeId -> Maybe WorkflowTree
lookupWorkflow tree identifier = listToMaybe [node' | node' <- allWorkflow tree, workflowNode node' == identifier]

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

-- 这些查询只给出结构关系；Stage 1 不据此改变资产读写语义。
precedes :: WorkflowTree -> NodeId -> NodeId -> Bool
precedes tree before after = knownWorkflowPosition tree before && knownWorkflowPosition tree after
  && any orders (allWorkflow tree)
  where
    orders (ChainedAt _ children) = or
      [workflowNode left `isPrefixOf` before && workflowNode right `isPrefixOf` after
      | (index, left) <- zip [0 :: Int ..] children, right <- drop (index + 1) children]
    orders (AlternativeAt _ selected children) = before == alternativeSelector selected
      && any (\child -> workflowNode child `isPrefixOf` after) children
    orders _ = False

exclusive :: WorkflowTree -> NodeId -> NodeId -> Bool
exclusive tree left right = knownWorkflowPosition tree left && knownWorkflowPosition tree right
  && any separate (allWorkflow tree)
  where
    separate (AlternativeAt _ _ children) = or
      [workflowNode first `isPrefixOf` left && workflowNode second `isPrefixOf` right
      | first <- children, second <- children, workflowNode first /= workflowNode second]
    separate _ = False

visibleFrom :: WorkflowTree -> NodeId -> NodeId -> Bool
visibleFrom tree source target = source == target && knownWorkflowPosition tree source
  || precedes tree source target

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
  valid (unique (map chainNode chains)) "Duplicate mounted chain NodeId"
  valid (sameSet (map chainNode chains) expectedChainIds) "Mounted chain coverage differs from workflow"
  mapM_ validateChain chains
  valid (unique (map definitionEntry chainDefinitions)) "Duplicate chain definition"
  valid (sameSet (map definitionEntry chainDefinitions)
    [method | effect <- effects, (role, method) <- effectMethods effect
      , role `elem` [HandlerMethod, ScopeOpen, ContextRequest, ContextRequire]])
    "Chain definitions do not cover the registered entries"
  mapM_ validateDefinition chainDefinitions
  valid (null (protoSources prototype) && all (\chain -> null (chainDrives chain) && null (chainReads chain)) chains)
    "Asset visibility annotations are reserved for the next stage"
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
      _ -> [] | selected <- allWorkflow (protoWorkflow prototype)]
    checkWorkflow expected selected = do
      valid (workflowNode selected == expected) "Workflow NodeId differs from AST path"
      case selected of
        NodeAt _ terminal -> do
          effect <- findEffectProto effects terminal
          valid (effectKind effect `notElem` [ContextKind, ErrorKind]) "Workflow node is not an origin chain"
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
    validateDefinition definition = do
      effect <- findEffectProto effects (definitionEffect definition)
      let roles = [role | (role, method) <- effectMethods effect, method == definitionEntry definition]
          expectedRoles = case definitionKind definition of
            OriginChain -> [HandlerMethod, ScopeOpen]
            ContextChain -> [ContextRequest, ContextRequire]
      valid (not (null roles) && all (`elem` expectedRoles) roles) "Chain kind differs from its method role"
      valid (unique (definitionReaches definition) && all (`elem` allMethodIds) (definitionReaches definition)
        && definitionEntry definition `elem` definitionReaches definition) "Invalid chain definition reachability"
