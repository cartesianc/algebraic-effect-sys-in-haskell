-- 生成期的资产来源分析：输入是已解析方法体与统一 Prototype，
-- 输出仅补全 chainDrives、chainReads 和 protoSources，不运行业务或修改 ScopeTree。
-- 每个候选状态保留发布/捕获的相关性；先按消费单元及后续读取裁剪，再组合状态。
-- Query 提供同一套 AST 可见性关系；runtime 只使用分析结果，不重新执行本分析。
module Framework.Gen.Build.Sources (resolveSources) where

import Control.Monad (unless)
import Control.Monad.State.Strict (StateT, execStateT, gets, lift, modify')
import Data.List (intercalate, isPrefixOf, nub, sort)
import Framework.Prototype.Graph (MethodDefinition(..), MethodRole(..), MethodShape(..), GraphError(..))
import Framework.Language.Registration (Access(..))
import Framework.Prototype.Types
import Framework.Prototype.Query

-- 生成期只跟踪“已经发布／捕获了哪个 origin”，不求值业务值。
-- Nothing 表示资源实例或 Receive 交付的捕获，不作为普通资产的跨链发布位置。
data AssetState = AssetState
  -- 可跨链路由的发布位置与资产契约；有 owner 的资源不进入这份普通来源表。
  { assetPublications :: [(NodeId, String)]
  -- 本条分析路径已捕获的契约及其位置；Nothing 表示不按普通发布路由的捕获。
  , assetCaptures :: [(String, Maybe NodeId)]
  } deriving (Eq, Show)

-- Bool 为本出口是否成功；失败出口保留此前事实，供 Recover 或吞错注入继续分析。
data AssetExit = AssetExit Bool AssetState deriving (Eq, Show)

-- 跨候选状态累计最终查询事实；裁剪中间状态时不能丢掉这些已观察的读取/生产。
data AssetFacts = AssetFacts
  { assetDrives :: [(NodeId, String)]
  , assetReads :: [(ReadPoint, [NodeId])]
  }

-- 当前分析调用的环境；不表示 runtime 调用对象。重放句柄与活动方法分别防止
-- 注入时重复执行原子句柄，以及未被声明允许的递归展开。assetRelevant 是本次出口仍需保留的契约。
data AssetCall = AssetCall
  { assetRoot :: NodeId
  , assetCaller :: Maybe String
  , assetOpenings :: [String]
  , assetReplays :: [String]
  , assetActiveMethods :: [String]
  , assetClosing :: Bool
  , assetRelevant :: [String]
  }

type AssetAnalysis = StateT AssetFacts (Either (PrototypeError String))

-- 可选生产保留为状态分支：A 未发布时 B 的 require 才能补产，故 A/B 不会被
-- 简单的 may-set 误报为共存来源。parallel 从相同输入独立分析，随后合并发布，
-- 因而两个旁支的缺值补产仍能同时出现。状态按有限事实去重，不展开任何业务 IO。
-- 只保留本链或后续 workflow 可能读取的契约；在方法出口就裁剪，避免无关注入
-- 的成功／失败组合先指数展开。仍保留活跃契约之间的相关性，不退化为 may-set。
resolveSources :: [MethodDefinition String] -> [String] -> Prototype String
               -> Either (PrototypeError String) (Prototype String)
resolveSources definitions defaultReaders prototype = do
  facts <- flip execStateT (AssetFacts [] []) $ do
    _ <- workflow (protoWorkflow prototype) [] [] []
    -- interpreter 托管的会话各自从空环境启动，不是任何读取点的可见前驱。
    mapM_ (\mount -> root mount [] [] []) (concatMap sessionMounts (protoSessions prototype))
  let reads = [(point, if readContract point `elem` receiving then FromSession
                       else if null sources then FromOwnChain else FromChains (sort (nub sources)))
        | (point, sources) <- assetReads facts]
      annotate chain = chain
        { chainDrives = sort (nub [contractType | (node', contractType) <- assetDrives facts, node' == chainNode chain])
        , chainReads = sort (nub [readContract point | (point, _) <- reads, readNode point == chainNode chain])
        }
  mapM_ companionRead reads
  pure prototype { protoChains = map annotate (protoChains prototype), protoSources = reads }
  where
    effects = protoEffects prototype
    lifelongs = workflowLifelongs (protoWorkflow prototype)
    -- 会话生产步骤的其他普通发布随交付读取（伴随发布），每一步都会替换。读取位置必须在调用前
    -- 已经领取该会话的交付：由该资产驱动的 Node，或以它为转折资产的选择读取；否则读到哪一步取决于调度。
    companionRead (point, FromChains nodes) = do
      let producers = nub [sessionAsset session | (_, described) <- lifelongs
            , session <- lifelongSessions described, any (`elem` sessionMounts session) nodes]
          taken = [contractType | (_, described) <- lifelongs
              , (node', contractType) <- lifelongSubscriptions described, node' == readNode point]
            ++ [alternativeContract choice | AlternativeAt _ choice _ <- allWorkflow (protoWorkflow prototype)
              , alternativeSelector choice == readNode point]
          stray = filter (`notElem` taken) producers
      unless (null stray) $ Left (InvalidLifelong (readNode point) ("Asset " ++ readContract point
        ++ " is published by the production step of " ++ intercalate ", " stray
        ++ " and is replaced at every delivery; read it only in targets driven by " ++ intercalate ", " stray
        ++ ", or produce it before the lifelong"))
    companionRead _ = pure ()
    resources = [source | effect <- effects, Just source <- [effectResource effect]]
    receiving = [contractType | effect <- effects, effectContinuous effect
      , Just contractType <- [effectProduces effect]]
    -- 复用已完成的可达性分析，保守包含 native reader，以及 caller 的 require 声明
    -- 将直接 producer 方法调用路由成读取的情况；不依赖尚未算出的 chainReads。
    possibleReads = [(chainNode chain, nub
      [contractType | effect <- effects, Just contractType <- [effectProduces effect]
        , let reached role = maybe False (`elem` chainReaches chain) (lookup role (effectMethods effect))
        , reached ContextRequire || reached ContextRequest && any
            (\consumer -> any ((`elem` chainReaches chain) . snd) (effectMethods consumer)
              && any (\demand -> demandProvider demand == effectName effect
                && demandAccess demand == RequireAccess) (effectDemands consumer)) effects])
      | chain <- protoChains prototype]
    readsAt node' = maybe [] id (lookup node' possibleReads)
    readsIn tree = nub (localReads ++ concatMap readsIn (workflowChildren tree))
      where
        localReads = case tree of
          NodeAt node' _ -> readsAt node'
          AlternativeAt _ selected _ -> readsAt (alternativeSelector selected)
          LifelongAt _ described _ -> concatMap readsAt (concatMap sessionMounts (lifelongSessions described))
          _ -> []
    retainPublications relevant = filter ((`elem` relevant) . snd)
    retainState relevant state = state
      { assetPublications = retainPublications relevant (assetPublications state)
      , assetCaptures = filter ((`elem` relevant) . fst) (assetCaptures state)
      }
    retainExit relevant (AssetExit succeeded state) = AssetExit succeeded (retainState relevant state)
    -- Workflow 失败后没有恢复分支；读取／生产事实已单独记录，失败产物不再传给后继。
    -- 方法层的失败仍保留相关状态，供 Recover 和吞错注入继续分析。
    retainOutcome relevant (succeeded, publications) =
      (succeeded, if succeeded then retainPublications relevant publications else [])
    effectFor :: String -> AssetAnalysis (EffectProto String)
    effectFor method = case [effect | effect <- effects, method `elem` map snd (effectMethods effect)] of
      [effect] -> pure effect
      _ -> lift (Left (InvalidPrototype ("Asset analysis has no effect for method " ++ method)))
    definitionFor :: String -> AssetAnalysis (MethodDefinition String)
    definitionFor method = case [definition | definition <- definitions, methodIdentity definition == method] of
      [definition] -> pure definition
      _ -> lift (Left (InvalidPrototype ("Asset analysis has no body for method " ++ method)))
    capture :: String -> Maybe NodeId -> AssetState -> AssetState
    capture contractType origin state = state
      { assetCaptures = sort ((contractType, origin) : filter ((/= contractType) . fst) (assetCaptures state)) }
    recordRead :: NodeId -> String -> [NodeId] -> AssetAnalysis ()
    recordRead node' contractType sources = modify' $ \facts ->
      let point = ReadPoint node' contractType
          previous = maybe [] id (lookup point (assetReads facts))
          updated = (point, nub (previous ++ sources))
      in facts { assetReads = updated : filter ((/= point) . fst) (assetReads facts) }
    recordDrive :: NodeId -> String -> AssetAnalysis ()
    recordDrive node' contractType = modify' $ \facts -> facts
      { assetDrives = nub ((node', contractType) : assetDrives facts) }
    -- 在已经捕获的路径上不查询外部来源；所有缺值路径使用同一静态候选表。
    readAsset :: AssetCall -> EffectProto String -> AssetState -> AssetAnalysis [AssetExit]
    readAsset call effect state = case effectProduces effect of
      Nothing -> lift (Left (InvalidPrototype "Context reader has no contract"))
      Just contractType -> case lookup contractType (assetCaptures state) of
        Just _ -> pure [AssetExit True state, AssetExit False state]
        -- Receive 资产只由会话生产：没有本次交付时由 interpreter 托管的会话交付，不查询普通来源。
        Nothing | contractType `elem` receiving -> do
          recordRead (assetRoot call) contractType []
          pure [AssetExit True (capture contractType Nothing state), AssetExit False state]
        Nothing -> do
          let sources = nub [node' | (node', produced) <- assetPublications state, produced == contractType
                , visibleFrom (protoWorkflow prototype) node' (assetRoot call)]
              external = filter (/= assetRoot call) sources
          recordRead (assetRoot call) contractType external
          case sources of
            [] | effectName effect `elem` resources ->
              -- 资源可由仍活着的实例提供；缺失时失败，绝不按需求值。
              pure [AssetExit True (capture contractType Nothing state), AssetExit False state]
            [] | assetClosing call -> pure [AssetExit False state]
            [] -> case lookup ContextRequest (effectMethods effect) of
              Just producing -> method (call { assetCaller = Nothing }) producing state
              Nothing -> pure [AssetExit False state]
            [source] -> pure [AssetExit True (capture contractType (Just source) state), AssetExit False state]
            _ -> lift (Left (InvalidPrototype ("Asset " ++ contractType ++ " read at " ++ show (assetRoot call)
              ++ " has several visible sources " ++ show sources ++ "; refine the contract or the workflow")))
    publish :: AssetCall -> EffectProto String -> AssetState -> AssetAnalysis AssetState
    publish call effect state = case effectProduces effect of
      Nothing -> lift (Left (InvalidPrototype "Context production has no contract"))
      Just contractType -> do
        let owned = case assetOpenings call of
              current : _ -> any (\scope -> effectName scope == current
                && effectResource scope == Just (effectName effect)) effects
              [] -> False
            captured = capture contractType (if owned then Nothing else Just (assetRoot call)) state
        if owned then pure captured else do
          recordDrive (assetRoot call) contractType
          pure captured { assetPublications = sort (nub ((assetRoot call, contractType) : assetPublications state)) }
    successes :: (AssetState -> AssetAnalysis [AssetExit]) -> [AssetExit] -> AssetAnalysis [AssetExit]
    successes action exits = nub . concat <$> mapM (\exit@(AssetExit succeeded state) ->
      if succeeded then action state else pure [exit]) exits
    -- 每个不透明原子方法都可能失败；失败保留此前已捕获和已发布的事实。
    -- 这些失败前缀只会在 Recover 或吞错注入继续，正常 Sequence 仍失败停止。
    withFailures :: AssetState -> [AssetExit] -> [AssetExit]
    withFailures state exits = AssetExit False state : exits
      ++ [AssetExit False after | AssetExit True after <- exits]
    shape :: AssetCall -> MethodShape String -> AssetState -> AssetAnalysis [AssetExit]
    shape _ Empty state = pure [AssetExit True state, AssetExit False state]
    shape call (Call selected) state = method call selected state
    shape call (Sequence parts) state = sequential (shape call) parts [AssetExit True state]
    shape call (Choice parts) state = case parts of
      [] -> pure [AssetExit True state]
      _ -> nub . concat <$> mapM (\part -> shape call part state) parts
    shape call (Recover body recovery) state = do
      before <- shape call body state
      nub . concat <$> mapM (\exit@(AssetExit succeeded after) ->
        if succeeded then pure [exit] else shape call recovery after) before
    sequential :: (part -> AssetState -> AssetAnalysis [AssetExit]) -> [part] -> [AssetExit] -> AssetAnalysis [AssetExit]
    sequential _ [] exits = pure (nub exits)
    sequential action (part : rest) exits = do
      next <- successes (action part) exits
      sequential action rest next
    method :: AssetCall -> String -> AssetState -> AssetAnalysis [AssetExit]
    method call selected state
      | selected `elem` assetReplays call = pure [AssetExit True (retainState (assetRelevant call) state)]
      | selected `elem` assetActiveMethods call =
          lift (Left (InvalidEffectGraph (RecursiveMethod selected)))
      | otherwise = do
          effect <- effectFor selected
          definition <- definitionFor selected
          let entered = call { assetCaller = if methodRole definition == ContextRequire
                  then assetCaller call else Just (effectName effect)
                , assetActiveMethods = selected : assetActiveMethods call }
              role = methodRole definition
              access = case assetCaller call of
                Nothing -> Just RequestAccess
                Just consumer ->
                  let modes = [demandAccess demand | candidate <- effects, effectName candidate == consumer
                        , demand <- effectDemands candidate, demandProvider demand == effectName effect]
                  -- streams 同时授予读取交付视图，按 require 处理。
                  in if RequestAccess `elem` modes then Just RequestAccess
                     else if any (`elem` modes) [RequireAccess, StreamAccess] then Just RequireAccess else Nothing
          exits <- case role of
            ContextRequire | access == Nothing -> pure [AssetExit False state]
            ContextRequire | selected `elem` defaultReaders ->
              readAsset entered effect state
            ContextRequest -> case access of
              Nothing -> pure [AssetExit False state]
              Just RequestAccess -> do
                body <- shape entered (methodBody definition) state
                successes (\after -> do
                  published <- publish call effect after
                  pure [AssetExit True published]) body
              -- require 与 streams 都只读取，不进入生产。
              Just _ -> readAsset call effect state
            -- 解析器只由 Receive 会话挂载调用；成功即发布一次交付。
            ContextStream -> do
              body <- shape entered (methodBody definition) state
              successes (\after -> do
                published <- publish call effect after
                pure [AssetExit True published]) body
            ScopeOpen | assetClosing call -> pure [AssetExit False state]
            ScopeOpen -> do
              let inside = entered { assetOpenings = effectName effect : assetOpenings entered }
              body <- shape inside (methodBody definition) state
              fresh <- inject call selected body
              let restoreResource after = foldr (\contractType -> capture contractType Nothing) after
                    [contractType | producer <- effects, effectResource effect == Just (effectName producer)
                      , Just contractType <- [effectProduces producer]]
                  -- 无输入 scope 在进入方法体前选择复用；有输入时可在取得参数后
                  -- 跳过余下方法体，保守保留失败前缀中的已完成输入操作。
                  reused = if null (effectOpeningInputs effect) then [state]
                    else nub (state : [after | AssetExit _ after <- body])
              pure (fresh ++ [AssetExit True (restoreResource after) | after <- reused])
            ScopeClose -> do
              body <- shape (entered { assetClosing = True }) (methodBody definition) state
              -- 重复 close 可在取得资源绑定时跳过余下方法体并成功返回；不触发注入。
              pure (body ++ [AssetExit True after | after <- nub (state : [part | AssetExit _ part <- body])])
            _ -> shape entered (methodBody definition) state >>= inject call selected
          pure (nub (map (retainExit (assetRelevant call)) (withFailures state exits)))
    inject :: AssetCall -> String -> [AssetExit] -> AssetAnalysis [AssetExit]
    inject call anchor exits = do
      let producing = [(effectName effect, method') | effect <- effects
            , Just anchorName <- [effectAnchor effect]
            , owner <- effects, effectName owner == anchorName
            , (role, anchoredMethod) <- effectMethods owner
            , role `elem` [HandlerMethod, ScopeOpen], anchoredMethod == anchor
            , Just method' <- [lookup ContextRequest (effectMethods effect)]]
      if maybe False (`elem` map fst producing) (assetCaller call)
        then pure exits
        else successes (\state -> do
          let injectOne (_, produced) before = do
                results <- method (call { assetCaller = Nothing
                  , assetReplays = anchor : assetReplays call }) produced before
                -- 每个 parser 的失败都留在注入内，先前成功发布不会回滚。
                pure (nub [AssetExit True after | AssetExit _ after <- results])
          sequential injectOne producing [AssetExit True state]) exits
    root :: NodeId -> [String] -> [(String, Maybe NodeId)] -> [(NodeId, String)] -> AssetAnalysis [AssetExit]
    root node' future handoff publications = do
      chain <- lift (lookupChain prototype node')
      let relevant = nub (readsAt node' ++ future)
      method (AssetCall node' Nothing [] [] [] False relevant) (chainEntry chain)
        (retainState relevant (AssetState publications handoff))
    workflow :: WorkflowTree -> [String] -> [(NodeId, String)] -> [(String, Maybe NodeId)]
             -> AssetAnalysis [(Bool, [(NodeId, String)])]
    workflow tree future publications handoff = case tree of
      NodeAt node' _ -> do
        exits <- root node' future handoff publications
        pure (nub [retainOutcome future (succeeded, assetPublications state) | AssetExit succeeded state <- exits])
      ChainedAt _ children -> workflowSequence children future [(True, publications)] handoff
      ParallelAt _ children -> do
        -- 兄弟各读同一份前置状态；只把外层后继仍需要的产物交给组合，避免无关笛卡尔积。
        parts <- mapM (\child -> workflow child future publications handoff) children
        pure (foldl (combine future) [(True, retainPublications future publications)] parts)
      AlternativeAt _ choice children -> do
        selected <- root (alternativeSelector choice) (nub (concatMap readsIn children ++ future)) handoff publications
        nub . concat <$> mapM (\(AssetExit succeeded state) -> if not succeeded
          then pure [(False, [])]
          else nub . concat <$> mapM (\child -> workflow child future (assetPublications state)
              [(contractType, origin) | (contractType, Just origin') <- assetCaptures state
                , let origin = Just origin']) children) selected
      LifelongAt boundary described _ -> do
        -- 复用原型中的实际消费单元，只拆 lifelong 直接子项的那一层 parallel。
        units <- lift $ mapM (\node' -> case lookupWorkflow tree node' of
          Just unit -> Right unit
          Nothing -> Left (InvalidPrototype ("Missing lifelong unit at " ++ show node')))
          (lifelongUnits described)
        let sessions = lifelongSessions described
            mounts = concatMap sessionMounts sessions
            delivered = [(sessionAsset session, Just (last (sessionMounts session)))
              | session <- sessions, not (null (sessionMounts session))]
            combineStates before after = nub [sort (nub (left ++ right))
              | left <- before, right <- after]
        -- 每个单元只保留自己可能读取的发布；root 仍保留生产链自身的读取依赖，
        -- read/drive 事实独立累计。不能先按所有单元的读取并集展开，再于出口投影。
        prepared <- mapM (\unit -> do
          let relevant = readsIn unit
          produced <- mapM (\session -> do
            steps <- mapM (\mount -> do
              exits <- root mount relevant handoff publications
              pure (nub [retainPublications relevant (assetPublications state)
                | AssetExit True state <- exits])) (sessionMounts session)
            -- 各成功出口分别保留；Receive 的两个步骤先各自投影，再组合并去重。
            pure $ case foldl combineStates [[]] steps of
              [] -> [[]]
              states -> states) sessions
          pure (unit, retainPublications relevant publications, produced)) units
        let -- 显式 request 的交付没有伴随发布，且会被本边界的其他单元消费；
            -- 因此 request 固定点仍跨全部单元求解，生产步骤始终使用边界环境。
            analyzeUnits requested = do
              mapM_ (\(unit, initial, produced) -> do
                let options = [nub (if sessionAsset session `elem` requested then [] : states else states)
                      | (session, states) <- zip sessions produced]
                mapM_ (\state -> workflow unit [] state (handoff ++ delivered))
                  (foldl combineStates [initial] options)) prepared
              drives <- gets assetDrives
              let now = nub [contractType | (node', contractType) <- drives, boundary `isPrefixOf` node'
                    , node' `notElem` mounts, contractType `elem` map sessionAsset sessions]
              unless (all (`elem` requested) now) (analyzeUnits (nub (requested ++ now)))
        analyzeUnits []
        -- lifelong 没有正常结束：排在它后面的后继不会执行。
        pure [(False, [])]
    workflowSequence :: [WorkflowTree] -> [String] -> [(Bool, [(NodeId, String)])] -> [(String, Maybe NodeId)]
                     -> AssetAnalysis [(Bool, [(NodeId, String)])]
    workflowSequence children future states handoff = go positioned states
      where
        positioned = zip children (drop 1 (scanr (\child later -> nub (readsIn child ++ later)) future children))
        go [] outcomes = pure (nub (map (retainOutcome future) outcomes))
        go ((child, later) : rest) outcomes = do
          next <- nub . concat <$> mapM (\outcome@(succeeded, publications) -> if succeeded
            then workflow child later publications handoff else pure [outcome]) outcomes
          go rest next
    combine :: [String] -> [(Bool, [(NodeId, String)])] -> [(Bool, [(NodeId, String)])] -> [(Bool, [(NodeId, String)])]
    combine future before after = nub [retainOutcome future (leftOK && rightOK, sort (nub (left ++ right)))
      | (leftOK, left) <- before, (rightOK, right) <- after]
