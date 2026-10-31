{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE ScopedTypeVariables #-}

-- IO 载体：Context 绑定携带值快照和 scope 归属，生命周期操作跟随该绑定。
module Framework.Effect.Runtime.App (App, runAppWith, withScopeCleanups) where

import Framework.Effect.Binding
import Framework.Effect.Contract
import Framework.Effect.Scope
import Framework.Effect.Runtime.Graph
import Framework.Effect.Runtime.Identity
import Framework.Prototype (NodeId)
import Control.Concurrent.MVar (readMVar, withMVar, takeMVar, tryTakeMVar, putMVar)
import Control.Exception (Exception, SomeException, fromException, mask, mask_, throwIO, try, finally)
import Control.Monad (filterM, forM, forM_, when)
import Control.Monad.Except (ExceptT, MonadError, catchError, runExceptT, throwError)
import Control.Monad.IO.Class (MonadIO(..))
import Control.Monad.Reader (ReaderT, ask, asks, local, runReaderT)
import Data.IORef (IORef, atomicModifyIORef', newIORef, readIORef, writeIORef)
import Data.List (find, nub, nubBy)
import Data.Maybe (catMaybes, fromMaybe, isJust, isNothing)
import Data.Unique (Unique, newUnique)

type Bound env cause = ScopeBinding env cause

data Environment env cause = Environment
  { emptyValues :: env
  , bindings :: IORef (ScopeBindings env cause)
  , scopes :: Scopes env cause
  , caller :: Maybe String
  , dependencies :: [String]
  , contexts :: [String]
  , openings :: [Opening env cause]
  , closings :: [Closing env cause]
  , errorHandlers :: [(Maybe String, ErrorHandler cause (App env cause))]
  , errorPath :: [String]
  , originalFailure :: Maybe (Failure cause)
  , diagnosticOwner :: Maybe (ScopeInstance env cause)
  , scopeCleanups :: [(String, App env cause ())]
  , cleaningScopes :: Bool
  , consumer :: ScopeUser env cause
  , cleanupPermit :: Maybe (Unique, ScopeInstance env cause)
  , cleanupBusy :: Maybe (Failure cause)
  , runtimeGraph :: RuntimeGraph env cause
  , activeActivation :: Maybe ActivationId
  , execution :: Execution
  -- 当前生产由 require 按需求值触发；进入任一 handler 后复位。
  , forcedRequire :: Bool
  -- 原子句柄方法名 → 挂在它下面的 Context 生产入口，由生成区安装。
  , anchoredEntries :: [(String, [(String, App env cause ())])]
  -- 注入期间各原子句柄的本次输出。
  , replays :: [(String, RawOutput)]
  }

data Opening env cause = Opening
  { family :: ScopeHandler env cause
  , wrapFault :: ScopeFault -> cause
  , observed :: IORef [(ScopeInputAccess, ScopeInput)]
  , produced :: IORef (ScopeBindings env cause)
  , holding :: IORef (Maybe (ScopeInstance env cause))
  , token :: Unique
  }

data Closing env cause = Closing
  { closeFamily :: ScopeHandler env cause
  , closeFault :: ScopeFault -> cause
  , closeHolding :: IORef (Maybe (ScopeInstance env cause, ScopePhase cause))
  , closeToken :: Unique
  , closeReserved :: IORef (Maybe (ScopeInstance env cause))
  }

-- 跳过已完成操作的剩余方法体；不是业务 Failure，不被 catchError 吞掉。
data Completed = Completed Unique
instance Show Completed where show _ = "SDK lifecycle operation already completed"
instance Exception Completed

newtype App env cause value = AppRun (ReaderT (Environment env cause) (ExceptT (Failure cause) IO) value)
  deriving (Functor, Applicative, Monad, MonadError (Failure cause))

rawIO :: IO value -> App env cause value
rawIO = AppRun . liftIO

instance MonadIO (App env cause) where
  liftIO action = do
    environment <- AppRun ask
    case closings environment of
      attempt : _ -> do
        acquired <- rawIO (readIORef (closeHolding attempt))
        case acquired of
          Nothing -> throwError (missingClose attempt)
          Just _ -> pure ()
      _ -> pure ()
    case openings environment of
      attempt : _ | not (any (`elem` scopeInputSources (family attempt)) (contexts environment)) ->
        rawIO (ensureOpen environment attempt) >>= either throwError pure
      _ -> pure ()
    rawIO action

inputName :: ScopeInput -> String
inputName (ScopeInput name _) = name

fault :: String -> (ScopeFault -> cause) -> ScopeFault -> Failure cause
fault name wrap problem = Failure name (wrap problem) (show problem) [] [] Nothing []

-- 没有业务 Context 的 scope 使用内部 unit 绑定；不是新增业务 effect 或配置 key。
resourceSource :: ScopeHandler env cause -> String
resourceSource handler = fromMaybe ("$scope:" ++ scopeName handler) (scopeContextSource handler)

ownedNames :: Environment env cause -> [String]
ownedNames environment = map (scopeName . family) (openings environment)
  ++ map (scopeName . closeFamily) (closings environment)

-- 捕获：只写入本次调用；用于读取已有绑定、恢复 scope 快照和认领归属，不改写运行级 state。
captureBinding :: Environment env cause -> String -> Bound env cause -> IO ()
captureBinding environment source value =
  atomicModifyIORef' (bindings environment) $ \current -> (bind source value current, ())

-- 尚未认领的资源也要记录本次使用；以后认领时一并接入实际实例。
-- 普通资产没有认领入口，只需读取其共享归属单元。
observeBindingOwner :: Environment env cause -> String -> Bound env cause
                    -> IO (Maybe (String, ScopeInstance env cause))
observeBindingOwner environment source value
  | any ((== Just source) . scopeContextSource) (scopes environment) =
      rememberUnownedBinding (consumer environment) value
  | otherwise = readBindingOwner value

-- 发布：普通业务的新产物按实际 Origin 保存；诊断与自动收尾只更新隔离的本次快照。
-- 资源绑定仍归具体 scope 实例；捕获、复用和认领归属不向业务资产表重新发布旧值。
publishBinding :: Environment env cause -> String -> Bound env cause -> IO ()
publishBinding environment source value = do
  owner <- observeBindingOwner environment source value
  captureBinding environment source value
  case execution environment of
    BusinessExecution origin
      | isNothing owner, isNothing (originalFailure environment)
      , not (cleaningScopes environment) -> publishAsset (runtimeGraph environment) origin source value
    _ -> pure ()

-- 已合法捕获的绑定保持快照。资源按实例归属解析，普通值只读静态来源指定的 Origin。
-- scope 保存的无 owner 辅助值不能绕过来源表，也不能盖过同一 Origin 后来的 request。
resolveBinding :: Environment env cause -> String -> IO (Either ContextFault (Maybe (Bound env cause)))
resolveBinding environment source = do
  current <- lookup source <$> readIORef (bindings environment)
  case current of
    Just value -> pure (Right (Just value))
    Nothing | isJust (originalFailure environment) -> pure (Right Nothing)
    Nothing -> do
      let visible = nub (ownedNames environment ++ dependencies environment)
      candidates <- fmap concat $ forM visible $ \name -> case findScope (scopes environment) name of
        Nothing -> pure []
        Just handler -> do
          instances <- readMVar (scopeInstances handler)
          fmap catMaybes $ forM instances $ \slot -> do
            value <- lookup source . scopeBindings <$> readIORef (scopeRecord slot)
            case value of
              Nothing -> pure Nothing
              Just bound -> do
                owner <- readBindingOwner bound
                case owner of
                  Nothing -> pure Nothing
                  Just (_, slotOwner) -> do
                    phase <- scopePhase <$> readIORef (scopeRecord slotOwner)
                    pure (if closed phase then Nothing else Just bound)
      -- 同一共享绑定可同时保存在多个 scope 快照中；重复引用不构成多个资源。
      case nubBy (\left right -> bindingOwnership left == bindingOwnership right) candidates of
        [] | cleaningScopes environment -> pure (Right Nothing)
        [] -> do
          asset <- readVisibleAsset (runtimeGraph environment) (executionOrigin (execution environment)) source
          case asset of
            Left problem -> pure (Left problem)
            Right Nothing -> pure (Right Nothing)
            Right (Just value) -> do
              captureBinding environment source value
              pure (Right (Just value))
        [value] -> captureBinding environment source value >> pure (Right (Just value))
        _ -> pure (Left (AmbiguousContextBinding source))
  where
    closed (ScopeClosed _) = True
    closed _ = False

owns :: Environment env cause -> ScopeInstance env cause -> IO Bool
owns environment slot = do
  opening <- mapM (readIORef . holding) (openings environment)
  closing <- mapM (readIORef . closeHolding) (closings environment)
  pure (any ((== scopeRecord slot) . scopeRecord)
    (catMaybes opening ++ map fst (catMaybes closing)))

-- 一个绑定只由一个具体实例负责关闭；名称相同不代表同一轮资源。
ownerMatches :: String -> ScopeInstance env cause -> Maybe (String, ScopeInstance env cause) -> Bool
ownerMatches name slot owner = case owner of
  Just (ownerName, original) -> ownerName == name && scopeRecord original == scopeRecord slot
  _ -> False

belongsToScope :: String -> ScopeInstance env cause -> Bound env cause -> IO Bool
belongsToScope name slot value = ownerMatches name slot <$> readBindingOwner value

checkBinding :: Environment env cause -> Maybe (String, ScopeInstance env cause) -> App env cause ()
checkBinding environment selectedOwner = forM_ selectedOwner $ \(_, slot) -> do
  owner <- rawIO (owns environment slot)
  busy <- rawIO (busyFailure environment)
  let diagnosing = maybe False ((== scopeRecord slot) . scopeRecord) (diagnosticOwner environment)
  when (not owner) $ do
    when (permitFor environment slot == Nothing) $
      rawIO (register busy slot) >>= either throwError pure
    phase <- rawIO (readPhase busy slot) >>= either throwError pure
    when (not diagnosing) $ maybe (pure ()) throwError (scopeFailure phase)
  where
    register busy slot = do
      waiting <- useScope (consumer environment) slot
      case waiting of
        Nothing -> pure (Right ())
        Just finished -> case busy of
          Just problem -> pure (Left problem)
          Nothing -> readMVar finished >> register busy slot
    readPhase Nothing slot = Right <$> withMVar (scopeGate slot)
      (const (scopePhase <$> readIORef (scopeRecord slot)))
    readPhase (Just problem) slot = mask_ $ do
      available <- tryTakeMVar (scopeGate slot)
      case available of
        Nothing -> pure (Left problem)
        Just () -> Right <$> (scopePhase <$> readIORef (scopeRecord slot))
          `finally` putMVar (scopeGate slot) ()

-- 持有其他生命周期锁时不等待外部关闭，防止两个 close/cleanup 相互等待。
busyFailure :: Environment env cause -> IO (Maybe (Failure cause))
busyFailure environment = case cleanupBusy environment of
  Just problem -> pure (Just problem)
  Nothing -> case closings environment of
    attempt : _ -> pure (Just (fault (scopeName (closeFamily attempt)) (closeFault attempt) ScopeInUse))
    [] -> do
      active <- forM (openings environment) $ \attempt -> do
        held <- readIORef (holding attempt)
        pure (fault (scopeName (family attempt)) (wrapFault attempt) ScopeInUse <$ held)
      pure $ case catMaybes active of
        problem : _ -> Just problem
        [] -> Nothing

setPhase :: ScopeInstance env cause -> ScopePhase cause -> IO ()
setPhase slot phase = atomicModifyIORef' (scopeRecord slot) $ \record ->
  (record { scopePhase = phase }, ())

saveBinding :: ScopeInstance env cause -> String -> Bound env cause -> IO ()
saveBinding slot source value = atomicModifyIORef' (scopeRecord slot) $ \record ->
  (record { scopeBindings = bind source value (scopeBindings record) }, ())

-- 复用只交接带实例归属的资源绑定。普通值在实际 require 时按 Origin 查询权威资产表，
-- 不从 scope 的旧快照预先捕获；开启参数同值的共享规则保持不变。
reuseBindings :: Environment env cause -> ScopeInstance env cause -> IO ()
reuseBindings environment slot = do
  saved <- scopeBindings <$> readIORef (scopeRecord slot)
  forM_ saved $ \(source, value) -> do
    owner <- readBindingOwner value
    when (isJust owner) $
      captureBinding environment source value

ensureOpen :: Environment env cause -> Opening env cause -> IO (Either (Failure cause) ())
ensureOpen environment attempt = do
  active <- readIORef (holding attempt)
  case active of
    Just _ -> pure (Right ())
    Nothing -> do
      inputs <- readIORef (observed attempt)
      let handler = family attempt
          name = scopeName handler
          missing = filter (`notElem` map (inputName . snd) inputs) (scopeInputSources handler)
      if not (null missing)
        then pure (Left (fault name (wrapFault attempt) (ScopeInputsMissing missing)))
        else do
          let acquire = mask $ \_ -> do
                selected <- selectScopeInstance (consumer environment) handler inputs
                case selected of
                  Left finished -> readMVar finished >> acquire
                  Right slot -> do
                    takeMVar (scopeGate slot)
                    phase <- scopePhase <$> readIORef (scopeRecord slot)
                    case phase of
                      ScopeClosed _ -> putMVar (scopeGate slot) () >> acquire
                      _ -> case beginScope OpenScope name (wrapFault attempt) phase of
                        Left problem -> putMVar (scopeGate slot) ()
                          >> pure (Left (scopeFailureTarget name (Just slot) problem))
                        Right False -> do
                          reuseBindings environment slot
                          putMVar (scopeGate slot) ()
                          throwIO (Completed (token attempt))
                        Right True -> do
                          writeIORef (holding attempt) (Just slot)
                          values <- readIORef (produced attempt)
                          atomicModifyIORef' (scopeRecord slot) $ \record ->
                            (record { scopePhase = ScopeOpening, scopeBindings = values }, ())
                          when (scopeContextSource handler == Nothing) $ do
                            let source = resourceSource handler
                            value <- newBinding (emptyValues environment) (execution environment) (Just (name, slot))
                            saveBinding slot source value
                            publishBinding environment source value
                          pure (Right ())
          acquire

missingClose :: Closing env cause -> Failure cause
missingClose attempt = fault (scopeName (closeFamily attempt)) (closeFault attempt)
  (ScopeContextMissing (resourceSource (closeFamily attempt)))

permitFor :: Environment env cause -> ScopeInstance env cause -> Maybe Unique
permitFor environment slot = case cleanupPermit environment of
  Just (ticket, target) | scopeRecord target == scopeRecord slot -> Just ticket
  _ -> Nothing

-- 在用户 close 方法实际 require 的位置，根据该绑定中的归属取得锁。
-- 同名资源重新开启产生另一份归属；旧绑定永远不会指向新实例。
beginClose :: Environment env cause -> Closing env cause -> Bound env cause -> IO (Either (Failure cause) ())
beginClose environment attempt value = do
  active <- readIORef (closeHolding attempt)
  boundOwner <- readBindingOwner value
  let owner = case boundOwner of
        Just (name, slot) | name == scopeName (closeFamily attempt) -> Just slot
        _ -> Nothing
  case active of
    Just (slot, _) -> case owner of
      Just selected | scopeRecord selected == scopeRecord slot -> pure (Right ())
      _ -> pure (Left (fault (scopeName (closeFamily attempt)) (closeFault attempt)
            (ScopeContextMismatch (resourceSource (closeFamily attempt)))))
    Nothing -> case owner of
      Nothing -> pure (Left (missingClose attempt))
      Just slot -> mask $ \_ -> do
        let name = scopeName (closeFamily attempt)
            permit = permitFor environment slot
            ticket = fromMaybe (closeToken attempt) permit
            user = Just (scopeUserIdentity (consumer environment))
        -- 其他资源的嵌套 close 用本次 consumer 保持到外层诊断结束。
        waiting <- case permit of
          Just _ -> pure Nothing
          Nothing -> useScope (consumer environment) slot
        ready <- case waiting of
          Just _ -> pure False
          Nothing -> reserveScopeClose user permit ticket slot
        if not ready
          then pure (Left (scopeFailureTarget name (Just slot) (fault name (closeFault attempt) ScopeInUse)))
          else do
            writeIORef (closeReserved attempt) (Just slot)
            takeMVar (scopeGate slot)
            phase <- scopePhase <$> readIORef (scopeRecord slot)
            case beginScope CloseScope name (closeFault attempt) phase of
              Left problem -> putMVar (scopeGate slot) ()
                >> pure (Left (scopeFailureTarget name (Just slot) problem))
              Right False -> do
                putMVar (scopeGate slot) ()
                throwIO (Completed (closeToken attempt))
              Right True -> do
                writeIORef (closeHolding attempt) (Just (slot, phase))
                setPhase slot ScopeClosing
                pure (Right ())

instance ContextStore env (App env cause) where
  enterRequest source (AppRun action) = AppRun $ do
    environment <- ask
    result <- liftIO $ mask $ \restore -> do
      let graph = runtimeGraph environment
      activation <- beginActivation graph (activeActivation environment) (execution environment)
        (RequestBoot source) (bindings environment) (consumer environment)
      let inside = environment { activeActivation = Just (activationId activation) }
      restore (runExceptT (runReaderT action inside))
        `finally` endActivation graph (activationId activation)
    either throwError pure result
  protectContextBinding source (AppRun action) = AppRun $ do
    environment <- ask
    case openings environment of
      attempt : _ | resourceSource (family attempt) == source -> do
        -- 允许阻塞 IO 被取消，但资源成功返回后到绑定发布之间不留异步取消窗口。
        result <- liftIO $ mask_ (runExceptT (runReaderT action environment))
        either throwError pure result
      _ -> action
  readContextBinding source select = do
    environment <- AppRun ask
    resolved <- rawIO (resolveBinding environment source)
    case resolved of
      Left problem -> pure (Left problem)
      Right Nothing -> pure (Right Nothing)
      Right (Just value) -> do
        observedOwner <- rawIO (observeBindingOwner environment source value)
        -- 认领冲突先于生命周期等待；读取别人的资源不能把关闭责任转给本次 open。
        selectedOwner <- case openings environment of
          attempt : _ | resourceSource (family attempt) == source -> do
            selected <- rawIO (readIORef (holding attempt))
            let name = scopeName (family attempt)
                mismatch = fault name (wrapFault attempt) (ScopeContextMismatch source)
            case observedOwner of
              Nothing -> pure ()
              Just (ownerName, _)
                | ownerName == name
                , maybe True (\slot -> ownerMatches name slot observedOwner) selected -> pure ()
              _ -> throwError mismatch
            case selected of
              Nothing -> pure observedOwner
              Just slot -> do
                -- 原子认领先于 checkBinding；不能先等另一个可能刚认领的 owner。
                -- 发布归属到保存 cleanup 的绑定之间不留异步取消窗口。
                claimed <- rawIO $ mask_ $ do
                  accepted <- claimBindingOwner value name slot
                  when accepted (saveBinding slot source value >> captureBinding environment source value)
                  pure accepted
                if claimed then pure (Just (name, slot)) else throwError mismatch
          _ -> pure observedOwner
        case closings environment of
          attempt : _ | resourceSource (closeFamily attempt) == source ->
            rawIO (beginClose environment attempt value) >>= either throwError pure
          _ -> pure ()
        checkBinding environment selectedOwner
        pure (Right (select (bindingValues value)))
  publishContextBinding source update = do
    environment <- AppRun ask
    owner <- case openings environment of
      attempt : _ | resourceSource (family attempt) == source -> do
        rawIO (ensureOpen environment attempt) >>= either throwError pure
        selected <- rawIO (readIORef (holding attempt))
        pure (fmap (\slot -> (scopeName (family attempt), slot)) selected)
      _ -> pure Nothing
    value <- rawIO (newBinding (update (emptyValues environment)) (execution environment) owner)
    rawIO (publishBinding environment source value)
    case openings environment of
      attempt : _ -> do
        rawIO (atomicModifyIORef' (produced attempt) (\values -> (bind source value values, ())))
        selected <- rawIO (readIORef (holding attempt))
        rawIO (maybe (pure ()) (\slot -> saveBinding slot source value) selected)
      _ -> pure ()
  currentHandler = AppRun (asks caller)
  enterHandler name (AppRun action) = AppRun (local (\env -> env { caller = Just name, forcedRequire = False }) action)
  enterContext name (AppRun action) = AppRun $ local
    (\env -> env { caller = Just name, contexts = name : contexts env, forcedRequire = False }) action
  -- 诊断、收尾与 scope 资源不按需求值：资源只能经 open 取得，诊断不预执行 Context。
  -- 当前 Origin 的同一来源持锁串行；锁内重新读取，不合并平行入口各自的补产。
  forceContext source (AppRun action) = AppRun $ do
    environment <- ask
    let resource = any ((== Just source) . scopeContextSource) (scopes environment)
        allowed = not resource && not (isJust (originalFailure environment))
          && not (cleaningScopes environment) && null (closings environment)
    if not allowed then pure Nothing else do
      lock <- liftIO (sourceLock (runtimeGraph environment) (executionOrigin (execution environment)) source)
      let inside = environment { caller = Nothing, forcedRequire = True }
      result <- liftIO (withMVar lock (const (runExceptT (runReaderT action inside))))
      either throwError (pure . Just) result
  productionAccess = AppRun $ do
    forced <- asks forcedRequire
    pure (if forced then RequiredInput else RequestedInput)
  withAnchoredContexts entries (AppRun action) = AppRun $ local
    (\environment -> environment { anchoredEntries = entries }) action
  anchoredContexts method = AppRun (asks (fromMaybe [] . lookup method . anchoredEntries))
  replayedOutput method = AppRun (asks (lookup method . replays))
  -- 诊断与收尾期间不注入。注入以根调用身份运行，失败只留在注入内：资产不发布，
  -- 原链照常继续；之后 require 该资产时按需求值，故障在那里按正常协议报出。
  injectOutput method raw (AppRun action) = AppRun $ do
    environment <- ask
    let allowed = not (isJust (originalFailure environment)) && not (cleaningScopes environment)
        inside = environment { caller = Nothing, forcedRequire = False, errorHandlers = []
                             , replays = (method, raw) : replays environment }
    when allowed $ () <$ liftIO (runExceptT (runReaderT action inside))
  recordContextInput access value = do
    environment <- AppRun ask
    case openings environment of
      attempt : _ | inputName value `elem` scopeInputSources (family attempt) -> do
        previous <- rawIO (readIORef (observed attempt))
        started <- rawIO (readIORef (holding attempt))
        case started of
          Just _ | value `notElem` map snd previous || access == RequestedInput -> throwError
            (fault (scopeName (family attempt)) (wrapFault attempt) (ScopeInputAfterOpen (inputName value)))
          _ -> pure ()
        let wasRequested = any (\(mode, old) -> inputName old == inputName value && mode == RequestedInput) previous
            mode = if wasRequested then RequestedInput else access
            updated = (mode, value) : filter ((/= inputName value) . inputName . snd) previous
        rawIO $ writeIORef (observed attempt) updated
        let missing = filter (`notElem` map (inputName . snd) updated) (scopeInputSources (family attempt))
        when (null missing) $ rawIO (ensureOpen environment attempt) >>= either throwError pure
      _ -> pure ()

instance ScopeStore cause (App env cause) where
  withScopeDependencies names (AppRun action) = AppRun $ local
    (\env -> env { dependencies = nub (names ++ dependencies env) }) action
  openScope = runOpen
  closeScope = runClose
  invalidateScope name problem = do
    environment <- AppRun ask
    handler <- rawIO (getScope (scopes environment) name)
    resolved <- rawIO (resolveBinding environment (resourceSource handler))
    selected <- case resolved of
      Right (Just value) -> rawIO (readBindingOwner value)
      _ -> pure Nothing
    case selected of
      Just (ownerName, slot) | ownerName == name -> do
        let invalidate = atomicModifyIORef' (scopeRecord slot) $ \record ->
              (record { scopePhase = case scopePhase record of
                  ScopeInvalid original -> ScopeInvalid original
                  _ -> ScopeInvalid problem }, ())
        owner <- rawIO (owns environment slot)
        rawIO (if owner then invalidate else withMVar (scopeGate slot) (const invalidate))
      _ -> throwError problem

instance ErrorStore cause (App env cause) where
  withErrorHandlers handlers (AppRun action) = AppRun $ local
    (\environment -> environment { errorHandlers = handlers }) action
  withErrorPath path (AppRun action) = AppRun $ local
    (\environment -> environment { errorPath = nub (path ++ errorPath environment) }) action
  caughtFailure = AppRun (asks originalFailure)
  handleFailure (AppRun action) = AppRun $ do
    environment <- ask
    if null (errorHandlers environment) || isJust (originalFailure environment)
      then action
      else action `catchError` \problem -> do
        let seeds = nub (scopeTrace problem ++ errorPath environment ++ map fst (scopeTargets problem))
        -- open/close 的内部调用还持有生命周期锁；退到锁外的 Root 后才诊断。
        if isJust (errorHandling problem)
          then throwError problem
          else if not (null (openings environment) && null (closings environment))
            then throwError problem { scopeTrace = seeds }
            else do
              path <- liftIO (scopeErrorPath (scopes environment) seeds)
              let traced = problem { scopeTrace = path }
                  matching (ErrorHandler _ matches _ _) = matches traced
                  -- 先按 handles 匹配故障类型；关联 scope 须在候选路径上，按父到子排序。
                  -- 无关联 scope 的处置随后执行，不定位任何实例。
                  located = [(Just selected, callback) | selected <- path
                    , (Just associated, callback) <- errorHandlers environment
                    , associated == selected, matching callback]
                  unlocated = [(Nothing, callback) | (Nothing, callback) <- errorHandlers environment
                    , matching callback]
              reports <- forM (located ++ unlocated) $ \(selected, callback) ->
                liftIO (runDiagnostic environment traced selected callback)
              throwError traced { errorHandling = Just reports }

-- 检测/处置共享本次故障的绑定快照。失败的 scope 可在此受限上下文中被检查、清理；
-- 不扫描其他实例，不修改业务调用已经捕获的值，也不重放业务 action。
runDiagnostic :: Environment env cause -> Failure cause -> Maybe String -> ErrorHandler cause (App env cause)
              -> IO (ErrorReport cause)
runDiagnostic environment problem selected callback = do
  captured <- readIORef (bindings environment)
  owners <- mapM (readBindingOwner . snd) captured
  let selectedFamily = selected >>= findScope (scopes environment)
      capturedOwner = do
        scopeLabel <- selected
        family <- selectedFamily
        boundOwner <- lookup (resourceSource family) (zip (map fst captured) owners)
        (ownerName, slot) <- boundOwner
        if ownerName == scopeLabel then Just slot else Nothing
  owner <- case selected of
    Nothing -> pure Nothing
    Just scopeLabel -> case lookup scopeLabel (scopeTargets problem) of
      Nothing -> pure capturedOwner
      Just Nothing -> pure Nothing
      Just (Just identity) -> do
        registered <- case selectedFamily of
          Nothing -> pure []
          Just family -> readMVar (scopeInstances family)
        let capturedSlots = [slot | Just (_, slot) <- owners]
        pure (find ((== identity) . scopeIdentity) (capturedSlots ++ registered))
  saved <- maybe (pure []) (fmap scopeBindings . readIORef . scopeRecord) owner
  let belongsElsewhere source boundOwner = case selected of
        Nothing -> False
        Just scopeLabel
          | Just source == (resourceSource <$> selectedFamily) ->
              not (maybe False (\slot -> ownerMatches scopeLabel slot boundOwner) owner)
          | otherwise -> case boundOwner of
              Just (ownerName, slot) | ownerName == scopeLabel -> maybe True ((/= scopeRecord slot) . scopeRecord) owner
              _ -> False
      -- 开启 B 失败时，不能把其他 scope 或其他参数实例的旧资源当成 B。
      capturedHere = [entry | (entry@(source, _), boundOwner) <- zip captured owners
        , not (belongsElsewhere source boundOwner)]
      restored = foldr (\(source, value) values -> bind source value values) capturedHere saved
      execute = do
        values <- newIORef restored
        let inside = environment
              { bindings = values, caller = Nothing, contexts = [], openings = [], closings = []
              , originalFailure = Just problem, diagnosticOwner = owner, forcedRequire = False, replays = [] }
            AppRun action = runErrorHandler selected callback
        result <- runExceptT (runReaderT action inside)
        -- runErrorHandler 接回 detect/resolve 的 Failure；不捕获取消等原生 IO 异常。
        case result of
          Right report -> pure report
          Left failure -> case callback of
            ErrorHandler name _ _ _ -> pure (ErrorReport selected name (Just (Failed failure)) Nothing)
  case owner of
    Nothing -> execute
    Just slot -> withMVar (scopeRecoveryGate slot) (const execute)

-- 此证据只描述这次失败所涉及的实例，不参与开启参数的 Eq 匹配。
scopeFailureTarget :: String -> Maybe (ScopeInstance env cause) -> Failure cause -> Failure cause
scopeFailureTarget selected owner problem
  | Nothing <- owner, isJust (lookup selected (scopeTargets problem)) = problem
  | otherwise = problem
      { scopeTargets = (selected, scopeIdentity <$> owner)
          : filter ((/= selected) . fst) (scopeTargets problem) }

-- 生成区安装 close 引用；安装本身不执行资源操作。
withScopeCleanups :: [(String, App env cause ())] -> App env cause value -> App env cause value
withScopeCleanups callbacks (AppRun action) = AppRun $ local
  (\environment -> environment { scopeCleanups = callbacks }) action

-- 在本次 open 退出前冻结绑定。后续 request、其他参数实例或重开都不会改变收尾目标。
-- open 已失败但资源已经发布时，同样保存清理动作；未发布的部分获取由原子获取操作负责。
captureScopeCleanup :: Environment env cause -> Opening env cause -> ScopeInstance env cause -> IO ()
captureScopeCleanup environment attempt slot =
  case lookup name (scopeCleanups environment) of
    Nothing -> pure ()
    Just (AppRun close) -> do
      saved <- scopeBindings <$> readIORef (scopeRecord slot)
      matched <- maybe (pure False) (belongsToScope name slot) (lookup (resourceSource (family attempt)) saved)
      when matched $ do
        captured <- readIORef (bindings environment)
        let snapshot = foldr (\(source, value) values -> bind source value values) captured saved
            cleanup permit = mask $ \restore -> do
              values <- newIORef snapshot
              let cleanupExecution = CleanupExecution (executionOrigin (execution environment)) name (scopeIdentity slot)
              cleanupUser <- newScopeUser (scopes environment) cleanupExecution
              let inside = environment
                    { bindings = values, caller = Nothing, dependencies = [], contexts = [], openings = [], closings = []
                    , errorPath = []
                    , originalFailure = Nothing, diagnosticOwner = Nothing, cleaningScopes = True, forcedRequire = False
                    , replays = []
                    , consumer = cleanupUser, cleanupPermit = Just (permit, slot)
                    , activeActivation = Nothing, execution = cleanupExecution
                    , cleanupBusy = Just (fault name (wrapFault attempt) ScopeInUse) }
              restore (runExceptT (runReaderT close inside)) `finally` detachScopeUser cleanupUser
            interrupted description = scopeFailureTarget name (Just slot)
              (fault name (wrapFault attempt) (ScopeCleanupInterrupted description))
        writeIORef (scopeCleanup slot) (Just (ScopeCleanup interrupted cleanup))
  where name = scopeName (family attempt)

runOpen :: String -> (ScopeFault -> cause) -> App env cause value -> App env cause (Maybe value)
runOpen name wrap (AppRun action) = AppRun $ do
  environment <- ask
  when (cleaningScopes environment || not (null (closings environment))) $
    throwError (fault name wrap ScopeCleanupInProgress)
  when (name `elem` ownedNames environment) (throwError (fault name wrap ScopeReentry))
  result <- liftIO $ mask $ \restore -> do
    handler <- getScope (scopes environment) name
    attempt <- Opening handler wrap <$> newIORef [] <*> newIORef [] <*> newIORef Nothing <*> newUnique
    let inside = environment { openings = attempt : openings environment }
        execute = do
          when (null (scopeInputSources handler)) $
            liftIO (ensureOpen inside attempt) >>= either throwError pure
          value <- runReaderT action inside
          liftIO (ensureOpen inside attempt) >>= either throwError pure
          selected <- liftIO (readIORef (holding attempt))
          forM_ selected $ \slot -> do
            saved <- liftIO (scopeBindings <$> readIORef (scopeRecord slot))
            when (resourceSource handler `notElem` map fst saved) $
              throwError (fault name wrap (ScopeContextMissing (resourceSource handler)))
          pure value
    outcome <- try (restore (runExceptT execute))
    acquired <- readIORef (holding attempt)
    forM_ acquired (captureScopeCleanup environment attempt)
    case outcome of
      Left (exception :: SomeException) -> do
        forM_ acquired $ \slot ->
          setPhase slot (interruptedScope name wrap exception) >> putMVar (scopeGate slot) ()
        case fromException exception of
          -- 复用同参的已开启实例：剩余 open 方法体未执行，没有新的输出。
          Just (Completed identity) | identity == token attempt -> pure (Right Nothing)
          _ -> throwIO exception
      Right completed -> case acquired of
        Nothing -> pure (either (Left . scopeFailureTarget name Nothing) (Right . Just) completed)
        Just slot -> do
          current <- scopePhase <$> readIORef (scopeRecord slot)
          let finalPhase = finishScope OpenScope name wrap current (() <$ completed)
          setPhase slot finalPhase
          putMVar (scopeGate slot) ()
          pure (either (Left . scopeFailureTarget name (Just slot)) (Right . Just)
            (maybe completed Left (scopeFailure finalPhase)))
  either throwError pure result

runClose :: String -> (ScopeFault -> cause) -> App env cause value -> App env cause (Maybe value)
runClose name wrap (AppRun action) = AppRun $ do
  environment <- ask
  when (name `elem` ownedNames environment) (throwError (fault name wrap ScopeReentry))
  result <- liftIO $ mask $ \restore -> do
    handler <- getScope (scopes environment) name
    attempt <- Closing handler wrap <$> newIORef Nothing <*> newUnique <*> newIORef Nothing
    let inside = environment { closings = attempt : closings environment }
        execute = do
          when (scopeContextSource handler == Nothing) $ do
            resolved <- liftIO (resolveBinding inside (resourceSource handler))
            case resolved of
              Right (Just value) -> liftIO (beginClose inside attempt value) >>= either throwError pure
              _ -> throwError (missingClose attempt)
          value <- runReaderT action inside
          active <- liftIO (readIORef (closeHolding attempt))
          case active of Nothing -> throwError (missingClose attempt); Just _ -> pure value
        releaseReservation = do
          -- 自动收尾的预约覆盖外层 Root 诊断，由 cleanupAvailable 统一结束。
          reserved <- readIORef (closeReserved attempt)
          forM_ reserved $ \slot -> when (permitFor environment slot == Nothing) $
            finishScopeClose (closeToken attempt) slot
    (do
      outcome <- try (restore (runExceptT execute))
      acquired <- readIORef (closeHolding attempt)
      case outcome of
        Left (exception :: SomeException) -> do
          forM_ acquired $ \(slot, initial) -> do
            setPhase slot (case initial of
              ScopeInvalid original -> ScopeInvalid original
              _ -> interruptedScope name wrap exception)
            putMVar (scopeGate slot) ()
          case fromException exception of
            -- 已成功关闭的实例跳过重复 close，没有新的输出。
            Just (Completed identity) | identity == closeToken attempt -> pure (Right Nothing)
            _ -> throwIO exception
        Right completed -> do
          forM_ acquired $ \(slot, initial) -> do
            setPhase slot (finishScope CloseScope name wrap initial (() <$ completed))
            putMVar (scopeGate slot) ()
          pure (either (Left . scopeFailureTarget name (fst <$> acquired)) (Right . Just) completed))
      `finally` releaseReservation
  either throwError pure result

-- consumer 覆盖整个末端调用、诊断和结果消费；嵌套方法返回不提前释放借用。
-- handoff 是交给本次调用的已捕获绑定（alternative 把选择时读到的资产交给候选）；
-- 返回值另带本次调用结束时捕获的无归属绑定，scope 资源绑定随实例收尾，不向外交出。
runAppWith :: (Either (Failure cause) value -> IO ()) -> RuntimeGraph env cause -> NodeId -> ScopeBindings env cause
           -> env -> App env cause value
           -> IO (Either (Failure cause) value, ScopeBindings env cause)
runAppWith consume graph node handoff initial action = do
  values <- newIORef handoff
  outcome <- runAppIn consume graph node values initial action
  captured <- readIORef values
  handoffBindings <- filterM (fmap isNothing . readBindingOwner . snd) captured
  pure (outcome, handoffBindings)

runAppIn :: (Either (Failure cause) value -> IO ()) -> RuntimeGraph env cause -> NodeId -> IORef (ScopeBindings env cause)
         -> env -> App env cause value -> IO (Either (Failure cause) value)
runAppIn consume graph node values initial (AppRun action) = mask $ \restore -> do
  origin <- newOrigin graph node
  let currentExecution = BusinessExecution origin
      handlers = runtimeScopes graph
  user <- newScopeUser handlers currentExecution
  activation <- beginActivation graph Nothing currentExecution (TargetedBoot node) values user
  let environment = Environment
        { emptyValues = initial, bindings = values, scopes = handlers
        , caller = Nothing, dependencies = [], contexts = [], openings = [], closings = []
        , errorHandlers = [], errorPath = [], originalFailure = Nothing, diagnosticOwner = Nothing
        , scopeCleanups = [], cleaningScopes = False, consumer = user
        , cleanupPermit = Nothing, cleanupBusy = Nothing, runtimeGraph = graph
        , activeActivation = Just (activationId activation), execution = currentExecution
        , forcedRequire = False, anchoredEntries = [], replays = [] }
  (do
      completed <- try $ restore $ do
        outcome <- runExceptT (runReaderT action environment)
        consume outcome
        pure outcome
      failures <- releaseScopeUser user handlers
      case completed of
        Left (exception :: SomeException) -> do
          saveCleanupFailures handlers failures
          throwIO exception
        Right outcome -> case [exception | (Just exception, _) <- failures] of
          exception : _ -> do
            let preserved = case outcome of
                  Left original -> [(Just exception, original { cleanupFailures = cleanupFailures original ++ map snd failures })]
                  Right _ -> failures
            saveCleanupFailures handlers preserved
            throwIO exception
          [] -> pure $ case (outcome, map snd failures) of
            (Left original, problems) -> Left original { cleanupFailures = cleanupFailures original ++ problems }
            (Right _, first : rest) -> Left first { cleanupFailures = cleanupFailures first ++ rest }
            (Right value, []) -> Right value)
    `finally` (endActivation graph (activationId activation) `finally` finishOrigin graph origin)
