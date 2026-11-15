{-# LANGUAGE DuplicateRecordFields #-}

-- 构图：PrototypePlan、Assembly 加上各 effect 方法的结构，构建 EffectGraph、ScopeTree、链挂载与资产来源，
-- 得到完整的 Prototype（编译产物），并检查注入、Stream 调用、持续资产的启动环与 Context 驱动。
module Framework.Gen.Build
  ( buildPrototype, checkDriven
  ) where

import Control.Monad (unless)
import Data.List (intercalate, nub)
import Data.Maybe (listToMaybe)
import Framework.Gen.Assembly
import Framework.Gen.Build.Graph (buildEffectGraph, buildScopeTree, completeScopeTree)
import Framework.Gen.Build.Sources (resolveSources)
import Framework.Language.Registration (EffectKind(..))
import Framework.Prototype.Graph
import Framework.Prototype.Query
import Framework.Prototype.Types
import Framework.Prototype.Validate (valid, unique, validatePrototype)

-- 算法说明 v2（2026-11-16）：依赖顺序是“已解析 Assembly + 已组成方法”→ EffectGraph
-- → 路径 ScopeTree + 注册前提 → 链事实上的来源/开启计划 → 自洽与驱动检查。
-- Assembly 同时供 Emit 与 Sources 使用，挂载及 anchor/parser 连接不在这里重新推导。
-- 挂载表保留每个 NodeId；entries 的 nub 只避免从相同静态方法重复建根，运行仍逐挂载启动。
-- logical 另含挂接生产的可达边，供驱动/读取查询；不能把它当作执行顺序或 scope 路径。
buildPrototype :: PrototypePlan -> Assembly String -> [(String, MethodShape String)]
                       -> Either (PrototypeError String) (Prototype String)
buildPrototype plan assembly shapes = do
  valid (unique (map fst shapes)) "Duplicate handler method in the structure generation plan"
  valid (all (`elem` map methodIdentity defaults) (map fst shapes)) "Unregistered handler method in the structure generation plan"
  let definitions = mergedDefinitions effects connections defaults shapes
      bodyOf = writtenBody defaults shapes
  -- 注入只回放挂接句柄：Context 只能直接或经一串 Pure 读到句柄，不能经其他方法再到达它。
  valid (null [(anchor, produced) | connection <- connections
      , let anchor = outputAnchor connection
            produced = outputParser connection
      , anchor `elem` reachableMethods definitions (calledMethods (replayedBody effects bodyOf anchor (bodyOf produced)))])
    "An injected Context reaches its anchor through another method; read the anchor with raw, directly or through Pure"
  let mounts = assemblyMounts assembly
      sessions = [mount | mount <- mounts, mountNode mount `elem` concatMap sessionMounts lifelongSessionsOf]
      entries = nub (map mountMethod mounts)
      logical = withProducerReferences connections definitions
  graph <- either (Left . InvalidEffectGraph) Right (buildEffectGraph definitions (Choice (map Call entries)))
  names <- mapM scopeName orderedScopes
  declared <- mapM (scopeDeclaration names) orderedScopes
  scopes <- either (Left . InvalidEffectGraph) Right (completeScopeTree declared (buildScopeTree graph))
  let makeChain mount = ChainProto (mountNode mount) (mountRole mount) (mountTerminal mount) (mountMethod mount)
        (reachableMethods logical [mountMethod mount]) [] []
        (maybe [] id (lookup (mountMethod mount) (graphRootPaths graph)))
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
  -- 驱动它的那份上游资产除外：每一步在领取一条上游交付之后才执行，读到的就是这条交付。
  let continuousMethods = [(contractType, method) | effect <- effects, effectContinuous effect
        , Just contractType <- [effectProduces effect], (role, method) <- effectMethods effect
        , role == ContextRequire]
      drivenBy terminal = concat [drivingAssets effects producer
        | producer <- effects, effectProduces producer == Just terminal]
  mapM_ (\chain -> do
      let others = nub [contractType | (contractType, method) <- continuousMethods
            , method `elem` chainReaches chain, contractType /= chainTerminal chain
            , contractType `notElem` drivenBy (chainTerminal chain)]
      unless (null others) $ Left (InvalidLifelong (chainNode chain) ("Production of continuous asset "
        ++ chainTerminal chain ++ " depends on continuous assets " ++ intercalate ", " others
        ++ "; its first delivery would wait for another stream")))
    [makeChain mount | mount <- sessions]
  -- 沿用 AST 输出的 parser 没有独立会话挂载，但仍须遵守相同的读取边界。
  -- 只分析交接后的 parser（raw 对 anchor 的调用已抹去），避免把合法下游消费算进来。
  mapM_ (\(session, nodes) -> do
      producer <- case [effect | effect <- effects, effectProduces effect == Just (sessionAsset session)] of
        [effect] -> pure effect
        _ -> Left (UnknownPrototypeTarget (sessionAsset session))
      parser <- maybe (Left (InvalidPrototype "Reused output has no parser")) Right
        (lookup ContextStream (effectMethods producer))
      anchor <- maybe (Left (InvalidPrototype "Reused output has no atomic anchor")) (findEffectProto effects)
        (effectAnchor producer) >>= ordinaryEntry
      let reached = reachableMethods logical
            (calledMethods (replayedBody effects bodyOf anchor (bodyOf parser)))
          others = nub [contractType | (contractType, method) <- continuousMethods
            , method `elem` reached, contractType `notElem` drivingAssets effects producer]
          position = case nodes of first : _ -> first; [] -> []
      unless (null others) $ Left (InvalidLifelong position ("Parser for reused output " ++ sessionAsset session
        ++ " reads other continuous assets " ++ intercalate ", " others
        ++ "; it may read only the asset driving the original operation")))
    [(session, nodes) | session <- lifelongSessionsOf, ReuseOutput nodes <- [sessionPlan session]]
  analyzed <- resolveSources connections written defaultReaders result
  validatePrototype analyzed
  pure analyzed
  where
    connections = assemblyOutputs assembly
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

mergedDefinitions :: [EffectProto String] -> [OutputConnection String] -> [MethodDefinition String] -> [(String, MethodShape String)]
                  -> [MethodDefinition String]
mergedDefinitions effects connections defaults shapes =
  [definition { methodBody = injected (methodIdentity definition) (bodyOf (methodIdentity definition)) } | definition <- defaults]
  where
    bodyOf = writtenBody defaults shapes
    injected selected body = case
      [replayedBody effects bodyOf selected (bodyOf (outputParser connection))
      | connection <- connections, outputAnchor connection == selected] of
      [] -> body
      contexts -> Sequence [body, Choice [Empty, Sequence contexts]]

writtenBody :: [MethodDefinition String] -> [(String, MethodShape String)] -> String -> MethodShape String
writtenBody defaults shapes selected = case lookup selected shapes of
  Just shape -> shape
  Nothing -> maybe Empty methodBody (listToMaybe [definition | definition <- defaults, methodIdentity definition == selected])

-- 同次输出复用（算法说明 v2）：沿 Assembly 的连接改写注入副本，原生产方法仍可独立驱动。
-- 连接与生成的注入表同源；这里消除的是分析副本中的回放调用，不修改手写方法体。
-- 挂接 Context 的 raw 到达 anchor 时由已有输出回答，所以该调用在副本中是 Empty；
-- 中间 Pure 的结构就地展开，以便保留其读取/控制结构，同时消去对 anchor 的重复执行边。
-- 这只消除“句柄输出交给自己的 parser，parser 又索取同次输出”的结构回边；
-- 不是寻找任意公共前缀，也不任意断开业务依赖。其他回到 anchor 的路径由前面的检查拒绝。
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

withProducerReferences :: Eq method => [OutputConnection method] -> [MethodDefinition method] -> [MethodDefinition method]
withProducerReferences connections definitions =
  [definition { methodBody = Sequence (methodBody definition : [Call (outputParser connection)
      | connection <- connections, outputAnchor connection == methodIdentity definition]) }
  | definition <- definitions]

-- 首次尚无 Handlers 时仅生成契约；有源码快照后必须另外执行这个驱动检查。
checkDriven :: Assembly String -> Prototype String -> Either (PrototypeError String) ()
checkDriven assembly prototype = valid (null undriven)
  ("Context never driven from the AST: " ++ intercalate ", " undriven
    ++ "; no terminal reaches its production or the handle it hangs below")
  where
    reached = reachableMethods (withProducerReferences (assemblyOutputs assembly) (protoMethods prototype))
      (map chainEntry (protoChains prototype))
    undriven = [methodIdentity definition | definition <- protoMethods prototype
      , methodRole definition == ContextRequest, methodIdentity definition `notElem` reached]
