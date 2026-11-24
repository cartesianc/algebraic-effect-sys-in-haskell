{-# LANGUAGE ScopedTypeVariables #-}

-- 执行 gen 写出的闭包：workflow 逐层执行，资产发布后按回调表同步回调，lifelong 的位置运行它的 Stream 来源。
-- 这里不遍历原型编排，也不判断值将来会不会来；原型只提供执行帧需要的节点表与 scope 回收的静态事实。
-- 唯一的并发是 AST 里显式写出的 parallel。整次运行受监督：第一个失败或原生异常取消全部任务并以它结束。
-- 退出先取消并等待 AST 子任务，再撤销根帧并回收不可达实例。
module Framework.Runtime.Execution (runCompiled, compiledTargets) where

import Framework.Language.Handler (Failure, Output(..))
import Framework.Runtime
  ( Target, Handoff(..), noHandoff, lowerTarget, lowerWith, scopeHandlers
  , Compiled(..), Closure(..), StreamSource(..), Reaction(..), Response(..), Tracking(..) )
import Framework.Runtime.App (Launch(..), StreamPort(..))
import Framework.Runtime.Graph
  ( RuntimeGraph, newRuntimeGraph, configureRuntimeScopes, runtimeRootFrame, runtimeScopes, newOrigin
  , resetOrigins, collectRuntimeScopes, finishRuntime, withRuntimeRetention, runtimeRetentions
  , readHistory, dropHistory, installReactions, installStatic
  , Place(..), rootPlace, openBranches, leaveBranch, rejoinBranches
  , StaticRun, newStaticRun, finishStatic, awaitStatic )
import Framework.Runtime.Frame
import Framework.Runtime.Delivery (SourceEnded(..), SubscriptionEnded(..))
import Framework.Runtime.Binding (Binding(..), readBindingOwner)
import Framework.Runtime.Identity (Execution(..))
import Framework.Runtime.Scope (ScopeBinding, ScopeBindings, newScopeUser, inheritScopeUse, detachScopeUser)
import Framework.Runtime.Retention (Retention, detachedRetention)
import Framework.Prototype
import Framework.Prototype.Index
import Framework.Prototype.Coordinate (Coord)
import Framework.Prototype.Slot (Slot(..))
import Framework.Language.AST (AST)
import Control.Concurrent (MVar, ThreadId, forkIOWithUnmask, killThread, newEmptyMVar, putMVar, readMVar, tryPutMVar)
import Control.Concurrent.MVar (newMVar, modifyMVar)
import Control.Exception
  (SomeAsyncException, SomeException, finally, fromException, mask, throwIO, try, uninterruptibleMask_)
import Control.Monad (filterM, forM, forM_, void, when)
import Control.Monad.Except (ExceptT(..), runExceptT)
import Data.IORef (IORef, atomicModifyIORef', modifyIORef', newIORef, readIORef)
import qualified Data.IntMap.Strict as IntMap
import qualified Data.Map.Strict as Map
import Data.Maybe (isJust)
import qualified Data.Sequence as Seq

-- 执行期环境：本次执行所在的帧、运行监督、订阅回调交付的资产（入口里对它的 requests 直接读交付），
-- 以及所在的位置（parallel 分支与持续资产的作用范围）。runTracking 是 Untracked 时（gen 判定回收无关的单元），
-- 这次执行不建帧、不改帧进度、不登记保留根与执行身份；runFrame 仍是外层帧，只作为发布的所在帧传下去。
data Run environment cause = Run
  { runFrame :: ExecutionFrame
  , runFatal :: Either SomeException (Failure cause) -> IO ()
  , runPerformed :: [Slot]
  , runPlace :: Place
  , runTracking :: Tracking
  }

type Execution' environment cause value =
  Run environment cause -> Handoff environment cause -> ExceptT (Failure cause) IO [value]

type Worker value = (ThreadId, MVar (Either SomeException value))

-- 等待全部分支；父执行退出时先通知全部子任务停止，再等待清理。
-- killThread 同步等待异常被接收，因此每次投递有独立任务和完成信号，慢 close 不挡住其他投递。
withWorkers :: [IO value] -> ([Worker value] -> IO result) -> IO result
withWorkers actions use = mask $ \restore -> do
  owned <- newIORef []
  let acquire action = do
        worker <- spawn action
        modifyIORef' owned (worker :)
        pure worker
  (mapM acquire actions >>= restore . use)
    `finally` (readIORef owned >>= stop)
  where
    spawn work = do
      finished <- newEmptyMVar
      thread <- forkIOWithUnmask $ \unmask ->
        try (unmask work) >>= putMVar finished
      pure (thread, finished)
    stop workers = uninterruptibleMask_ $ do
      deliveries <- forM workers $ \(thread, _) -> do
        delivered <- newEmptyMVar
        _ <- forkIOWithUnmask $ \_ -> killThread thread `finally` putMVar delivered ()
        pure delivered
      mapM_ readMVar deliveries
      mapM_ (readMVar . snd) workers

runParalleled :: [IO value] -> IO [value]
runParalleled actions = withWorkers actions $ \workers -> do
  outcomes <- mapM (readMVar . snd) workers
  either throwIO pure (sequence outcomes)

-- 收尾照常完成，原操作的异常／取消优先；收尾中的取消也必须停止后续业务。
-- SDK Failure 是返回值，因此同步 close 的业务失败不会改变它。
retireAfter :: IO value -> ((IO () -> IO ()) -> IO ()) -> IO value
retireAfter action retirement = mask $ \restore -> do
  outcome <- try (restore action)
  retired <- try (retirement restore)
  case (outcome, retired) of
    (Left (exception :: SomeException), _)
      | Just (_ :: SomeAsyncException) <- fromException exception -> throwIO exception
    (_, Left (exception :: SomeException))
      | Just (_ :: SomeAsyncException) <- fromException exception -> throwIO exception
    (Left exception, _) -> throwIO exception
    (_, Left exception) -> throwIO exception
    (Right value, Right ()) -> pure value

withFrameNode :: RuntimeGraph environment cause -> Run environment cause -> Coord -> IO value -> IO value
withFrameNode graph run node action = mask $ \restore -> do
  startFrameNode (runFrame run) node
  retireAfter (restore action) $ \_ -> do
    retired <- completeFrameNode (runFrame run) node
    restore (collectRuntimeScopes graph retired)

-- 失败照常向上传播，同时报告监督；取消不是失败。
supervised :: Run environment cause -> IO (Either (Failure cause) value) -> IO (Either (Failure cause) value)
supervised run action = do
  outcome <- try action
  case outcome of
    Left (exception :: SomeException)
      | Just (_ :: SomeAsyncException) <- fromException exception -> throwIO exception
      | otherwise -> runFatal run (Left exception) >> throwIO exception
    Right (Left problem) -> runFatal run (Right problem) >> pure (Left problem)
    Right value -> pure value

-- 生成的全部末端：scope 句柄与收尾从这里取得。依次是 workflow 与单元的末端、选择读取、来源与派生步骤。
compiledTargets :: Compiled environment cause value
                -> ([Target environment cause value], [Target environment cause String], [Target environment cause ()])
compiledTargets compiled =
  ( [target | Step _ target <- flows]
  , [selector | Choose _ _ selector _ <- flows]
  , [parser | Reaction _ _ (RunDerive _ parser) <- compiledReactions compiled]
      ++ concat [sourceTargets source | source <- compiledSources compiled] )
  where
    flows = compiledFlows compiled
    sourceTargets source = [snd (sourceStream source), snd (sourceParser source)]

-- workflow 与各单元回调里的全部闭包层。
compiledFlows :: Compiled environment cause value -> [Closure environment cause value]
compiledFlows compiled = concatMap layers (compiledWorkflow compiled : [flow | Reaction _ _ (RunUnit _ _ flow) <- compiledReactions compiled])
  where
    layers flow = flow : case flow of
      Serial _ parts -> concatMap layers parts
      Concurrent _ parts -> concatMap (layers . snd) parts
      Choose _ _ _ candidates -> concat [layers candidate | (_, _, candidate) <- candidates]
      _ -> []

-- lifelong 的来源与静态运行的来源。
compiledSources :: Compiled environment cause value -> [StreamSource environment cause]
compiledSources compiled = [source | Drive _ (Just source) <- compiledFlows compiled]
  ++ [source | (_, _, source) <- compiledStatic compiled]

-- Prototype 已在 SDK 入口完整求值并校验；这里核对当前 AST 就是编译时的那一份，再执行生成的闭包。
runCompiled :: (Eq method, Show method)
            => Prototype method -> AST -> Compiled environment cause value -> IO (Output cause [value])
runCompiled prototype tree compiled = do
  either (ioError . userError . show) pure (validateWorkflow prototype tree)
  let index = indexPrototype prototype
      (entries, selectors, steps) = compiledTargets compiled
  store <- newRuntimeGraph index (scopeHandlers entries ++ scopeHandlers selectors ++ scopeHandlers steps)
  configureRuntimeScopes store
  ended <- newIORef []
  delivered <- newIORef Map.empty
  detached <- detachedRetention (runtimeRetentions store)
  statics <- newMVar Map.empty
  settled <- newEmptyMVar
  let settle = void . tryPutMVar settled
      machine = Machine index store (compiledTables index compiled) ended delivered detached
      root = Run (runtimeRootFrame store) (settle . Left) [] rootPlace Tracked
  installReactions store (reactTo machine root)
  installStatic store (staticRun machine root statics)
  retireAfter (do
      let work = do
            outcome <- try (runExceptT (execute machine (compiledWorkflow compiled) root noHandoff))
            settle (either (Left . Left) Right outcome)
      result <- withWorkers [work] (const (readMVar settled))
      case result of
        Left (Left exception) -> throwIO exception
        Left (Right problem) -> pure (Failed problem)
        Right (Right values) -> pure (Succ values)
        Right (Left problem) -> pure (Failed problem))
    (\_ -> do
      _ <- finishExecutionFrame (runtimeRootFrame store)
      finishRuntime store)

-- 一次运行的执行状态：哪些节点已 endStream，以及 behavior 在各作用范围里上一次回调的值。
data Machine method environment cause value = Machine
  { machineIndex :: PrototypeIndex method
  , machineGraph :: RuntimeGraph environment cause
  , machineTables :: Tables environment cause value
  , machineEnded :: IORef [Coord]
  , machineDelivered :: IORef (Map.Map (Int, Maybe NodeId) environment)
  -- Untracked 执行的保留根：从未登记，普通值是空操作，交来资源则报错（gen 的判定与交付不符）。
  , machineDetached :: Retention environment cause
  }

-- gen 写出的回调表、来源与静态运行按查找键排好，启动时建一次；发布、交付与激活的热路径只按键取，
-- 不再遍历整张表。内容与顺序都来自生成的程序，运行时不增删、不重新判断。
data Tables environment cause value = Tables
  -- 资产 → 回调（作用范围，回应），保持生成的顺序。
  { tableReactions :: IntMap.IntMap [(Maybe NodeId, Response environment cause value)]
  -- behavior 资产 → 比较器（写在它的来源上）。
  , tableSame :: IntMap.IntMap (environment -> environment -> Bool)
  -- 作用范围（lifelong 路径或静态运行标识）→ 由来源驱动的单元，以及这些单元的成员节点。
  , tableUnits :: Map.Map NodeId [NodeId]
  , tableMembers :: Map.Map NodeId [Coord]
  -- lifelong 路径 → 它的会话资产（来源开始与结束时放掉这些资产在该作用范围里的历史）。
  , tableDriveAssets :: Map.Map NodeId [Slot]
  -- 被 requests 的持续资产 → 静态运行的标识与根来源。
  , tableStatic :: IntMap.IntMap (NodeId, StreamSource environment cause)
  }

compiledTables :: PrototypeIndex method -> Compiled environment cause value -> Tables environment cause value
compiledTables index compiled = Tables
  { tableReactions = IntMap.fromListWith (flip (++))
      [(slotNumber asset, [(scope, response)]) | Reaction asset scope response <- compiledReactions compiled]
  , tableSame = IntMap.fromListWith keepFirst
      [(slotNumber (sourceAsset source), same) | source <- compiledSources compiled, Just same <- [sourceSame source]]
  , tableUnits = units
  , tableMembers = Map.map (\owned -> concat [nodeMembers (driveAt index (coordAt index unit)) | unit <- owned]) units
  , tableDriveAssets = Map.fromList
      [ (path, [slotOf index (provider (sessionAsset session)) | session <- lifelongSessions description])
      | (path, description) <- workflowLifelongs (protoWorkflow prototype) ]
  , tableStatic = IntMap.fromListWith keepFirst
      [(slotNumber asset, (scope, selected)) | (asset, scope, selected) <- compiledStatic compiled]
  }
  where
    prototype = indexedPrototype index
    units = Map.fromListWith (flip (++))
      [(scope, [unit]) | Reaction _ (Just scope) (RunUnit unit _ _) <- compiledReactions compiled]
    keepFirst _ earlier = earlier
    provider asset = case [effectName effect | effect <- protoEffects prototype, effectProduces effect == Just asset] of
      name : _ -> name
      [] -> asset

-- workflow 闭包的一层：执行这一层，退出时撤销本子树尚未进入的节点。
execute :: Machine method environment cause value -> Closure environment cause value -> Execution' environment cause value
execute machine flow run handoff = case flow of
  Step path target -> managed path $ ExceptT $ do
    let location = coordAt index path
    endedNow <- readIORef (machineEnded machine)
    if location `elem` endedNow then pure (Right []) else tracked (withFrameNode graph run location) $
      retained $ \retention -> do
        outcome <- try (lowerTarget graph (runTracking run) retention location (runFrame run) (runPlace run) handoff
          (runPerformed run) target)
        case outcome of
          Right (result, _) -> pure ((: []) <$> result)
          -- endStream：本次调用放弃，这个节点之后不再被回调；同一次回调中其余位置照常执行。
          Left SubscriptionEnded
            | null (runPerformed run) -> ioError (userError ("endStream at " ++ show path
                ++ " outside a lifelong subscription; regenerate with the SDK effect-codegen command"))
            | otherwise -> do
                atomicModifyIORef' (machineEnded machine) (\current -> (location : current, ()))
                pure (Right [])
  Serial path parts -> managed path $ concat <$> sequence [execute machine part run handoff | part <- parts]
  -- 各分支开始前一次登记全部分支可能发布的资产；分支退出（含失败与取消）时撤销登记并唤醒等待的 require。
  Concurrent path parts -> managed path $ ExceptT $ do
    identities <- openBranches graph (map fst parts)
    let within identity = run { runPlace = (runPlace run) { placeBranches = identity : placeBranches (runPlace run) } }
    outcomes <- runParalleled
      [ runExceptT (execute machine part (within identity) handoff) `finally` leaveBranch graph identities identity
      | (identity, (_, part)) <- zip identities parts ]
      `finally` rejoinBranches graph identities
    pure (concat <$> sequence outcomes)
  Choose path selectorPath selector candidates -> managed path $ ExceptT $ retained $ \retention -> do
    let location = coordAt index path
        selectorAt = coordAt index selectorPath
        members = nodeMembers (driveAt index location)
    endedNow <- readIORef (machineEnded machine)
    -- 候选中的节点都已结束订阅时，选择读取不再执行，整个 alternative 跳过。
    if not (null members) && all (`elem` endedNow) members then pure (Right []) else do
      chosen <- tracked (withFrameNode graph run selectorAt) $
        lowerTarget graph (runTracking run) retention selectorAt (runFrame run) (runPlace run) handoff (runPerformed run) selector
      case chosen of
        (Left problem, _) -> pure (Left problem)
        (Right constructor, captured) -> case [(node, candidate) | (name, node, candidate) <- candidates, name == constructor] of
          (selectedNode, candidate) : _ -> do
            tracked id $ do
              retired <- concat <$> mapM (skipFrameSubtree (runFrame run) . coordAt index)
                [node | (_, node, _) <- candidates, node /= selectedNode]
              collectRuntimeScopes graph retired
            runExceptT (execute machine candidate run captured)
          [] -> ioError (userError ("No alternative candidate for the Context " ++ constructor
            ++ "; regenerate with the SDK effect-codegen command"))
  -- lifelong 的位置：只有 Stream 来源需要运行。来源结束后放掉 socket 资产的历史（最新值保留给后继），
  -- 撤销这些单元在根帧里的未来位置；event 单元的回调整次运行有效，位置保留。
  Drive path source -> ExceptT $ supervised run $ do
    outcome <- maybe (pure Nothing) (\selected -> runSource machine run path selected handoff) source
    forM_ source $ \_ -> do
      dropHistory graph path (driveAssets machine path)
      retired <- concat <$> mapM (skipFrameSubtree (runFrame run) . coordAt index) (socketUnits machine path)
      collectRuntimeScopes graph retired
    pure (maybe (Right []) Left outcome)
  where
    index = machineIndex machine
    graph = machineGraph machine
    -- 每棵子树退出都撤销未进入的后继；parallel 的退出发生在等待所有子任务之后。
    -- Untracked 的执行没有自己的帧：外层帧（根帧）里这些位置是单元将来的回调，不能被它改动。
    managed path inner = ExceptT $ supervised run $ case runTracking run of
      Untracked -> runExceptT inner
      Tracked -> retireAfter (runExceptT inner) $ \restore -> do
        retired <- skipFrameSubtree (runFrame run) (coordAt index path)
        restore (collectRuntimeScopes graph retired)
    -- 只在登记的执行里改帧进度、建保留根；Untracked 用从未登记的保留根。
    tracked :: (IO result -> IO result) -> IO result -> IO result
    tracked frameWork action = case runTracking run of
      Tracked -> frameWork action
      Untracked -> action
    retained action = case runTracking run of
      Tracked -> withRuntimeRetention graph action
      Untracked -> action (machineDetached machine)

-- lifelong 的持续资产（来源、派生与复用输出）；来源结束时放掉它们的历史。
driveAssets :: Machine method environment cause value -> NodeId -> [Slot]
driveAssets machine path = Map.findWithDefault [] path (tableDriveAssets (machineTables machine))

-- 由来源驱动（订阅持续资产）的单元；只有 event 订阅的单元不在其中。
socketUnits :: Machine method environment cause value -> NodeId -> [NodeId]
socketUnits machine path = Map.findWithDefault [] path (tableUnits (machineTables machine))

-- 回调表的入口：一次发布之后，依次执行对这份资产有效的回调；第一个失败返回给发布方。
-- event 回调整次运行有效；其余回调只回应自己作用范围（所属 lifelong 或静态运行）里的发布。
-- behavior 的资产与同一作用范围里上一次回调的值相等时不回调。回调继承发布方的位置。
reactTo :: Machine method environment cause value -> Run environment cause
        -> Place -> Slot -> ScopeBinding environment cause -> ScopeBindings environment cause -> IO (Maybe (Failure cause))
reactTo machine run at source value captured = do
  let scope = placeScope at
      selected = [response | (reactionScope, response) <- IntMap.findWithDefault [] (slotNumber source) (tableReactions (machineTables machine))
        , maybe True ((== scope) . Just) reactionScope]
      key = (slotNumber source, scope)
  if null selected then pure Nothing else do
    changed <- case sameOf machine source of
      Nothing -> pure True
      Just same -> atomicModifyIORef' (machineDelivered machine) $ \earlier ->
        case Map.lookup key earlier of
          Just previous | same previous (bindingValues value) -> (earlier, False)
          _ -> (Map.insert key (bindingValues value) earlier, True)
    if not changed then pure Nothing
      else firstFailure [respond machine run { runPlace = at } source value captured response | response <- selected]
  where
    firstFailure [] = pure Nothing
    firstFailure (action : rest) = action >>= maybe (firstFailure rest) (pure . Just)

-- behavior 资产的比较：它的来源在生成的 Drive 或静态运行里写着。
sameOf :: Machine method environment cause value -> Slot -> Maybe (environment -> environment -> Bool)
sameOf machine source = IntMap.lookup (slotNumber source) (tableSame (machineTables machine))

-- 一次回调。Unit：单元在新的执行帧里执行一次，交付作为固定捕获交给它（持续资产另带到这一条为止的历史）；
-- 单元的节点都已 endStream 时不再执行。RunDerive：在派生挂载执行派生资产的 parser；被驱动链 endStream 后不再执行。
respond :: Machine method environment cause value -> Run environment cause -> Slot -> ScopeBinding environment cause
        -> ScopeBindings environment cause -> Response environment cause value -> IO (Maybe (Failure cause))
respond machine run source value captured response = case response of
  -- 回收无关的单元：不建帧、不重置 Origin、不登记保留根，交付与失败照常。
  RunUnit path Untracked flow -> do
    let unit = coordAt index path
        members = nodeMembers (driveAt index unit)
    endedNow <- readIORef (machineEnded machine)
    if not (null members) && all (`elem` endedNow) members then pure Nothing else do
      handoff <- delivery
      let inside = run { runPerformed = [source], runTracking = Untracked
            , runPlace = (runPlace run) { placeScope = Just (take (length path - 1) path) } }
      either Just (const Nothing) <$> runExceptT (execute machine flow inside handoff)
  RunUnit path Tracked flow -> do
    let unit = coordAt index path
        members = nodeMembers (driveAt index unit)
    endedNow <- readIORef (machineEnded machine)
    if not (null members) && all (`elem` endedNow) members then pure Nothing else do
      resetOrigins graph unit
      handoff <- delivery
      outcome <- withRuntimeRetention graph $ \_ -> mask $ \restore -> do
        frame <- newChildFrame (runtimeRootFrame graph) (unitFrameNodes (unitAt index unit)) []
        -- 单元在所属 lifelong 的作用范围里执行：它经输出联立发布的持续资产与派生按这个 lifelong 记历史、回调。
        let inside = run { runFrame = frame, runPerformed = [source], runTracking = Tracked
              , runPlace = (runPlace run) { placeScope = Just (take (length path - 1) path) } }
        retireAfter
          (restore (runExceptT (execute machine flow inside handoff))) $ \_ -> do
            retired <- finishExecutionFrame frame
            restore (collectRuntimeScopes graph retired)
      pure (either Just (const Nothing) outcome)
  RunDerive path parser -> do
    let mount = coordAt index path
    endedNow <- readIORef (machineEnded machine)
    if mount `elem` endedNow then pure Nothing else do
      handoff <- delivery
      outcome <- try (withRuntimeRetention graph $ \retention ->
        lowerTarget graph Tracked retention mount (runtimeRootFrame graph) (runPlace run) handoff [] parser)
      collectRuntimeScopes graph [mount]
      case outcome of
        Left SubscriptionEnded -> do
          atomicModifyIORef' (machineEnded machine) (\current -> (mount : current, ()))
          pure Nothing
        Right (result, _) -> pure (either Just (const Nothing) result)
  where
    index = machineIndex machine
    graph = machineGraph machine
    delivery = do
      view <- if effectContinuous (effectAt source) then readHistory graph False (placeScope (runPlace run)) source else pure Nothing
      pure (Handoff ((source, value) : captured) [(source, maybe (Seq.singleton value) id view) | effectContinuous (effectAt source)])
    effectAt selected = protoEffects (indexedPrototype index) !! slotNumber selected

-- 运行一个 Stream 来源直到它 streamEnd，或它在这个作用范围里的订阅单元全部 endStream。
-- 来源方法正常返回就再调用一次（下一步）；每次 rawemit 在来源的调用栈里执行一次 parser，parser 的发布同步回调。
-- 来源与每次 parser 各自登记实际使用；parser 继承来源本次已捕获的资源，原生产身份与关闭责任不变。
-- 返回 Just 是来源或回调的失败。
runSource :: Machine method environment cause value -> Run environment cause -> NodeId -> StreamSource environment cause
          -> Handoff environment cause -> IO (Maybe (Failure cause))
runSource machine run scope source (Handoff given views) = do
  -- 每次运行从空的历史与 behavior 比较开始：同一 lifelong 再次执行或另一处订阅同一来源时不沿用上一次的状态。
  dropHistory graph scope (driveAssets machine scope)
  atomicModifyIORef' (machineDelivered machine) (\earlier -> (Map.filterWithKey (\(_, at) _ -> at /= Just scope) earlier, ()))
  loop
  where
    at = (runPlace run) { placeScope = Just scope }
    index = machineIndex machine
    graph = machineGraph machine
    (streamPath, stream) = sourceStream source
    (parserPath, parser) = sourceParser source
    streamMount = coordAt index streamPath
    parserMount = coordAt index parserPath
    loop = do
      execution <- BusinessExecution <$> newOrigin graph streamMount
      taken <- try $ withStep execution $ \owner retention -> do
        let deliver text captured = withStep execution $ \parserOwner parserRetention -> do
              inheritScopeUse owner parserOwner
              resources <- filterM (fmap isJust . readBindingOwner . snd) captured
              let launch = Launch
                    { launchBindings = resources ++ [entry | entry@(name, _) <- given, name `notElem` map fst resources]
                    , launchViews = views, launchPort = ParserInput text, launchPerformed = []
                    , launchUser = Just parserOwner, launchFrame = runtimeRootFrame graph, launchRetention = parserRetention
                    , launchPlace = at, launchTracking = Tracked }
              (outcome, _, _) <- lowerWith graph parserMount launch parser
              -- 订阅单元全部 endStream：下一次 rawemit 之前结束来源。
              finished <- subscribersEnded
              when (finished && either (const False) (const True) outcome) (throwIO SourceEnded)
              pure outcome
        (outcome, _, _) <- lowerWith graph streamMount (Launch given views (SourcePort deliver) [] (Just owner)
          (runtimeRootFrame graph) retention at Tracked) stream
        pure outcome
      case taken of
        Left SourceEnded -> pure Nothing
        Right (Left problem) -> pure (Just problem)
        Right (Right ()) -> do
          finished <- subscribersEnded
          if finished then pure Nothing else loop
    withStep execution action = mask $ \restore -> do
      owner <- newScopeUser (runtimeScopes graph) execution
      restore (withRuntimeRetention graph (action owner)) `finally` (do
        detachScopeUser owner
        collectRuntimeScopes graph [streamMount, parserMount])
    subscribersEnded = do
      endedNow <- readIORef (machineEnded machine)
      let tables = machineTables machine
          units = Map.findWithDefault [] scope (tableUnits tables)
          members = Map.findWithDefault [] scope (tableMembers tables)
      pure (not (null units) && all (`elem` endedNow) members)

-- lifelong 之外 requests 一份持续资产：同步运行它的根来源直到结束（派生链的回调以静态运行的标识生效），
-- 同一个根来源在一次运行中只运行一次；并发的请求方等这一次运行结束。历史保留到运行结束。
staticRun :: Machine method environment cause value -> Run environment cause
          -> MVar (Map.Map NodeId (StaticRun cause)) -> Place -> Slot -> IO (Either (Failure cause) NodeId)
staticRun machine run statics at source = case IntMap.lookup (slotNumber source) (tableStatic (machineTables machine)) of
  Just (scope, selected) -> do
    -- 同一根来源只运行一次：它的派生资产在同一次运行里一并发布。
    (done, fresh) <- modifyMVar statics $ \started -> case Map.lookup scope started of
      Just done -> pure (started, (done, False))
      Nothing -> do
        done <- newStaticRun
        pure (Map.insert scope done started, (done, True))
    -- 运行抛出原生异常时也填入结果，等待的请求方不会悬挂；异常照常传播给发起者。
    outcome <- if fresh
      then do
        outcome <- try (runSource machine run { runPlace = at } scope selected noHandoff)
        finishStatic graph done (either (const Nothing) id outcome)
        either (\(exception :: SomeException) -> throwIO exception) pure outcome
      else awaitStatic graph done
    pure (maybe (Right scope) Left outcome)
  Nothing -> ioError (userError ("No static run for " ++ slotName source ++ "; regenerate with the SDK effect-codegen command"))
  where
    graph = machineGraph machine
