{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE ScopedTypeVariables #-}

-- IO 载体：把 ContextStore／ScopeStore／ErrorStore 解释为同一套受控执行协议。
-- Environment 保存当前调用、诊断或收尾的局部环境；RuntimeGraph 和 scope 控制对象
-- 在整个运行中共享。Binding 的值与出身不变，归属通过共享单元认领。
--
-- 调用链：Runtime.lowerTarget -> runAppWith -> 注册方法的生成包装 -> 对应 Store。
-- 完整调用负责诊断及结果消费，然后撤销使用；嵌套 request 只登记 activation。
-- open／close 在实际读取资源绑定时选择实例；不在 handler 外预先执行取值。
-- 本文件保留共享 Environment 的解释器实现，按绑定、Store、诊断、生命周期和根调用分组。
module Framework.Runtime.App (App, Launch(..), runAppWith, withScopeCleanups) where

import Framework.Runtime.Binding
import Framework.Language.Handler
import Framework.Runtime.Protocol
import Framework.Runtime.Scope
import Framework.Runtime.Graph
import Framework.Runtime.Identity
import Framework.Runtime.Frame (ExecutionFrame, owningFrame)
import Framework.Language.History (History, historyView)
import Framework.Runtime.Session (Broken, View, awaitHistory)
import Framework.Prototype (NodeId)
import Control.Concurrent.MVar (readMVar, withMVar, takeMVar, tryTakeMVar, putMVar)
import Control.Exception (Exception, SomeException, displayException, fromException, mask, mask_, throwIO, try, finally)
import Control.Monad (filterM, forM, forM_, when)
import Control.Monad.Except (ExceptT, MonadError, catchError, runExceptT, throwError)
import Control.Monad.IO.Class (MonadIO(..))
import Control.Monad.Reader (ReaderT, ask, asks, local, runReaderT)
import Data.IORef (IORef, atomicModifyIORef', newIORef, readIORef, writeIORef)
import Data.List (find, nub)
import Data.Maybe (catMaybes, fromMaybe, isJust, isNothing)
import Data.Sequence ((|>))
import Data.Unique (Unique, newUnique)

-- 调用环境与生命周期尝试 -------------------------------------------------------

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
  , currentFrame :: ExecutionFrame
  -- 原子句柄方法名 → 挂在它下面的 Context 生产入口，由生成区安装。
  , anchoredEntries :: [(String, [(String, App env cause ())])]
  -- 注入期间各原子句柄的本次输出。
  , replays :: [(String, RawOutput)]
  -- 持续资产在本次调用的历史视图：lifelong 交付或此前的会话读取；其他调用之后的发布不改写它。
  , views :: IORef [(String, View env cause)]
  -- 解析器本次的原始输入，只在会话调用解析器时安装。
  , streamRaw :: Maybe String
  -- 这些来源的发布进入会话历史，而不是按 Origin 的业务资产表：
  -- 会话步骤的本资产，以及 lifelong 单元内对该 lifelong 会话资产的显式 request。
  , sessionSinks :: [(String, Bound env cause -> IO ())]
  -- lifelong 单元执行中：本次 frame 对会话资产的领取（同一 frame 只领取一次，各调用共享）。
  , frameDeliver :: String -> Maybe (IO (Either (Broken cause) (View env cause)))
  }

-- 一次末端调用的起点：交接的绑定与视图；会话步骤另带原始输入，lifelong 单元另带本次 frame。
-- 会话步骤共用会话的使用登记：生产资源跨步骤保持，停止会话时才撤销这份使用。
data Launch env cause = Launch
  { launchBindings :: ScopeBindings env cause
  , launchViews :: [(String, View env cause)]
  , launchInput :: Maybe String
  , launchSinks :: [(String, Bound env cause -> IO ())]
  , launchDeliver :: String -> Maybe (IO (Either (Broken cause) (View env cause)))
  , launchUser :: Maybe (ScopeUser env cause)
  , launchFrame :: ExecutionFrame
  }

data Opening env cause = Opening
  { family :: ScopeHandler env cause
  , wrapFault :: ScopeFault -> cause
  , observed :: IORef [(ScopeInputAccess, ScopeInput)]
  , observedFrames :: IORef [(String, ExecutionFrame)]
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

-- 绑定捕获、发布与资源定位 -------------------------------------------------------

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
      , not (cleaningScopes environment) -> do
          -- 本次已有该资产的视图时，显式 request 的新发布接在本次视图末尾，不改写其他调用的交付。
          atomicModifyIORef' (views environment) $ \current ->
            ([(name, if name == source then view |> value else view) | (name, view) <- current], ())
          case lookup source (sessionSinks environment) of
            Just deliver -> deliver value
            Nothing -> publishAsset (runtimeGraph environment) origin source value
    _ -> pure ()

-- 已合法捕获的绑定保持快照。资源只能来自本链 open 的捕获；不从仍活着的其他实例猜测。
-- scope 保存的无 owner 辅助值不能绕过来源表，也不能盖过同一 Origin 后来的 request。
resolveBinding :: Environment env cause -> String -> IO (Either ContextFault (Maybe (Bound env cause)))
resolveBinding environment source = do
  current <- lookup source <$> readIORef (bindings environment)
  case current of
    Just value -> pure (Right (Just value))
    Nothing | isJust (originalFailure environment) -> pure (Right Nothing)
    Nothing | cleaningScopes environment
      || any ((== source) . resourceSource) (scopes environment) -> pure (Right Nothing)
    Nothing -> do
      asset <- readVisibleAsset (runtimeGraph environment) (executionOrigin (execution environment)) source
      case asset of
        Left problem -> pure (Left problem)
        Right Nothing -> pure (Right Nothing)
        Right (Just value) -> do
          captureBinding environment source value
          pure (Right (Just value))

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
-- 不从 scope 的旧快照预先捕获；实例共享只依据参数的生产身份。
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
          parameterFrames <- map snd <$> readIORef (observedFrames attempt)
          let ownerFrame = owningFrame (runtimeRootFrame (runtimeGraph environment)) parameterFrames
          let acquire = mask $ \_ -> do
                selected <- selectScopeInstance (consumer environment) handler ownerFrame inputs
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
                            value <- newBinding (emptyValues environment) (execution environment)
                              Nothing (scopeFrame slot) (Just (name, slot))
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

-- 载体协议解释 ---------------------------------------------------------------

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
    value <- rawIO (newBinding (update (emptyValues environment)) (execution environment)
      (activeActivation environment) (maybe (currentFrame environment) (scopeFrame . snd) owner) owner)
    rawIO (publishBinding environment source value)
    case openings environment of
      attempt : _ -> do
        rawIO (atomicModifyIORef' (produced attempt) (\values -> (bind source value values, ())))
        selected <- rawIO (readIORef (holding attempt))
        rawIO (maybe (pure ()) (\slot -> saveBinding slot source value) selected)
      _ -> pure ()
  currentHandler = AppRun (asks caller)
  enterHandler name (AppRun action) = AppRun (local (\env -> env { caller = Just name }) action)
  enterContext name (AppRun action) = AppRun $ local
    (\env -> env { caller = Just name, contexts = name : contexts env }) action
  -- 诊断、收尾与 scope 资源不等待：资源只能经 open 取得，诊断与收尾期间没有新的业务发布。
  -- 其余缺值读取在读之前取得发布信号；读不到就等下一次发布，醒来后按同一来源表重读。
  awaitContext source = AppRun $ do
    environment <- ask
    let resource = any ((== Just source) . scopeContextSource) (scopes environment)
        allowed = not resource && not (isJust (originalFailure environment))
          && not (cleaningScopes environment) && null (closings environment)
    if not allowed then pure Nothing else do
      signal <- liftIO (publicationSignal (runtimeGraph environment))
      pure (Just (rawIO (readMVar signal)))
  withAnchoredContexts entries (AppRun action) = AppRun $ local
    (\environment -> environment { anchoredEntries = entries }) action
  anchoredContexts method = AppRun (asks (fromMaybe [] . lookup method . anchoredEntries))
  replayedOutput method = AppRun (asks (lookup method . replays))
  -- 诊断与收尾期间不注入。注入以根调用身份运行，失败只留在注入内：资产不发布，
  -- 原链照常继续；之后 require 该资产时等待它的发布，不在读取处补产。
  injectOutput method raw (AppRun action) = AppRun $ do
    environment <- ask
    let allowed = not (isJust (originalFailure environment)) && not (cleaningScopes environment)
        inside = environment { caller = Nothing, errorHandlers = []
                             , replays = (method, raw) : replays environment }
    when allowed $ () <$ liftIO (runExceptT (runReaderT action inside))
  -- 本次已有视图时直接读取；lifelong 单元中尚未领取的会话资产在第一次读取时领取本次 frame 的交付。
  readContextHistory source select = do
    environment <- AppRun ask
    captured <- rawIO (lookup source <$> readIORef (views environment))
    case captured of
      Just view -> pure (Just (historyOf source select view))
      Nothing | deliveryAllowed environment, Just deliver <- frameDeliver environment source ->
        Just <$> captureDelivery environment source select (rawIO deliver)
      Nothing -> pure Nothing
  -- 诊断、收尾与 close 期间不启动会话；读到的历史捕获为本次视图。
  awaitContextHistory source select = do
    environment <- AppRun ask
    if not (deliveryAllowed environment) then pure Nothing else do
      session <- rawIO (obtainSession (runtimeGraph environment) (Nothing, source) [] [])
      Just <$> captureDelivery environment source select (rawIO (awaitHistory session))
  streamRawInput = AppRun (asks streamRaw)
  recordContextInput access source = do
    environment <- AppRun ask
    case openings environment of
      attempt : _ | source `elem` scopeInputSources (family attempt) -> do
        captured <- rawIO (lookup source <$> readIORef (bindings environment))
        (value, frame) <- case captured of
          Just bound | Just production <- bindingProduction bound ->
            pure (ScopeInput source production, bindingFrame bound)
          _ -> throwError (fault (scopeName (family attempt)) (wrapFault attempt) (ScopeInputsMissing [source]))
        previous <- rawIO (readIORef (observed attempt))
        started <- rawIO (readIORef (holding attempt))
        case started of
          Just _ | value `notElem` map snd previous -> throwError
            (fault (scopeName (family attempt)) (wrapFault attempt) (ScopeInputAfterOpen (inputName value)))
          _ -> pure ()
        let wasRequested = any (\(mode, old) -> inputName old == inputName value && mode == RequestedInput) previous
            mode = if wasRequested then RequestedInput else access
            updated = (mode, value) : filter ((/= inputName value) . inputName . snd) previous
        rawIO $ writeIORef (observed attempt) updated
        rawIO $ atomicModifyIORef' (observedFrames attempt) $ \frames ->
          ((source, frame) : filter ((/= source) . fst) frames, ())
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

-- 故障诊断与持续交付 -----------------------------------------------------------

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
              , originalFailure = Just problem, diagnosticOwner = owner, replays = [] }
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

-- 视图直接共享会话中的绑定序列，读取条目时才投影；每条发布都携带本资产的值。
historyOf :: String -> (env -> Maybe value) -> View env cause -> History value
historyOf source select view = historyView view $ \binding ->
  fromMaybe (error ("SDK: a delivery of " ++ source ++ " carries no value; regenerate the program"))
    (select (bindingValues binding))

deliveryAllowed :: Environment env cause -> Bool
deliveryAllowed environment = isNothing (originalFailure environment) && not (cleaningScopes environment)
  && null (closings environment)

-- 会话失败时传播它的原失败或原生异常；取得的视图捕获为本次视图，之后的发布不改写它。
captureDelivery :: Environment env cause -> String -> (env -> Maybe value)
                -> App env cause (Either (Broken cause) (View env cause)) -> App env cause (History value)
captureDelivery environment source select deliver = do
  delivered <- deliver
  case delivered of
    Left (Left exception) -> rawIO (throwIO exception)
    Left (Right problem) -> throwError problem
    Right view -> do
      rawIO $ atomicModifyIORef' (views environment) $ \current ->
        ((source, view) : filter ((/= source) . fst) current, ())
      pure (historyOf source select view)

-- 此证据只描述这次失败所涉及的实例，不参与开启参数的生产身份匹配。
scopeFailureTarget :: String -> Maybe (ScopeInstance env cause) -> Failure cause -> Failure cause
scopeFailureTarget selected owner problem
  | Nothing <- owner, isJust (lookup selected (scopeTargets problem)) = problem
  | otherwise = problem
      { scopeTargets = (selected, scopeIdentity <$> owner)
          : filter ((/= selected) . fst) (scopeTargets problem) }

-- 生命周期执行与清理闭包 -------------------------------------------------------

-- 生成区安装 close 引用；安装本身不执行资源操作。
withScopeCleanups :: [(String, App env cause ())] -> App env cause value -> App env cause value
withScopeCleanups callbacks (AppRun action) = AppRun $ local
  (\environment -> environment { scopeCleanups = callbacks }) action

-- 在本次 open 退出前冻结绑定。后续 request、其他参数实例或重开都不会改变收尾目标。
-- open 已失败但资源已经发布时，同样保存清理动作；未发布的部分获取由原子获取操作负责。
captureScopeCleanup :: forall env cause. Environment env cause -> Opening env cause -> ScopeInstance env cause -> IO ()
captureScopeCleanup environment attempt slot =
  case lookup name (scopeCleanups environment) of
    Nothing -> pure ()
    Just (AppRun close) -> do
      saved <- scopeBindings <$> readIORef (scopeRecord slot)
      matched <- maybe (pure False) (belongsToScope name slot) (lookup (resourceSource (family attempt)) saved)
      when matched $ do
        captured <- readIORef (bindings environment)
        let snapshot = foldr (\(source, value) values -> bind source value values) captured saved
            isolated permit action = mask $ \restore -> do
              values <- newIORef snapshot
              let cleanupExecution = CleanupExecution (executionOrigin (execution environment)) name (scopeIdentity slot)
              cleanupUser <- newScopeUser (scopes environment) cleanupExecution
              let inside = environment
                    { bindings = values, caller = Nothing, dependencies = [], contexts = [], openings = [], closings = []
                    , errorPath = []
                    , originalFailure = Nothing, diagnosticOwner = Nothing, cleaningScopes = True
                    , replays = []
                    , consumer = cleanupUser, cleanupPermit = Just (permit, slot)
                    , activeActivation = Nothing, execution = cleanupExecution
                    , cleanupBusy = Just (fault name (wrapFault attempt) ScopeInUse) }
              restore (action inside) `finally` detachScopeUser cleanupUser
            cleanup permit = isolated permit (runExceptT . runReaderT close)
            -- 生命周期锁已在 runClose 中释放；关闭预约仍保持到本次诊断完成。
            -- 诊断失败不能吞掉原来的取消，外层继续保存并传播该 SomeException。
            interrupted permit exception = isolated permit $ \inside -> do
              let problem = scopeFailureTarget name (Just slot)
                    (fault name (wrapFault attempt) (ScopeCleanupInterrupted (displayException exception)))
                  AppRun diagnosing = handleFailure (throwError problem :: App env cause ())
              result <- try (runExceptT (runReaderT diagnosing inside))
              pure $ case result of
                Left (_ :: SomeException) -> problem
                Right (Left diagnosed) -> diagnosed
                Right (Right ()) -> problem
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
    attempt <- Opening handler wrap <$> newIORef [] <*> newIORef [] <*> newIORef [] <*> newIORef Nothing <*> newUnique
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

-- 完整调用边界 ---------------------------------------------------------------

-- consumer 覆盖整个末端调用、诊断和结果消费；嵌套方法返回不提前释放借用。
-- handoff 是交给本次调用的已捕获绑定（alternative 把选择时读到的资产交给候选）；
-- 返回值另带本次调用结束时捕获的无归属绑定，scope 资源绑定随实例收尾，不向外交出。
runAppWith :: (Either (Failure cause) value -> IO ()) -> RuntimeGraph env cause -> NodeId -> Launch env cause
           -> env -> App env cause value
           -> IO (Either (Failure cause) value, ScopeBindings env cause, [(String, View env cause)])
runAppWith consume graph node launch initial action = do
  values <- newIORef (launchBindings launch)
  delivered <- newIORef (launchViews launch)
  outcome <- runAppIn consume graph node values delivered launch initial action
  captured <- readIORef values
  handoffBindings <- filterM (fmap isNothing . readBindingOwner . snd) captured
  handoffViews <- readIORef delivered
  pure (outcome, handoffBindings, handoffViews)

runAppIn :: (Either (Failure cause) value -> IO ()) -> RuntimeGraph env cause -> NodeId -> IORef (ScopeBindings env cause)
         -> IORef [(String, View env cause)] -> Launch env cause -> env -> App env cause value
         -> IO (Either (Failure cause) value)
runAppIn consume graph node values delivered launch initial (AppRun action) = mask $ \restore -> do
  origin <- newOrigin graph node
  let currentExecution = BusinessExecution origin
      handlers = runtimeScopes graph
  user <- maybe (newScopeUser handlers currentExecution) pure (launchUser launch)
  activation <- beginActivation graph Nothing currentExecution (TargetedBoot node) values user
  let environment = Environment
        { emptyValues = initial, bindings = values, scopes = handlers
        , caller = Nothing, dependencies = [], contexts = [], openings = [], closings = []
        , errorHandlers = [], errorPath = [], originalFailure = Nothing, diagnosticOwner = Nothing
        , scopeCleanups = [], cleaningScopes = False, consumer = user
        , cleanupPermit = Nothing, cleanupBusy = Nothing, runtimeGraph = graph
        , activeActivation = Just (activationId activation), execution = currentExecution
        , currentFrame = launchFrame launch
        , anchoredEntries = [], replays = []
        , views = delivered, streamRaw = launchInput launch, sessionSinks = launchSinks launch
        , frameDeliver = launchDeliver launch }
  (do
      completed <- try $ restore $ do
        outcome <- runExceptT (runReaderT action environment)
        consume outcome
        pure outcome
      -- 会话的使用登记在会话停止时才撤销。
      -- 节点进度由 Execution 在本调用（含交接）返回后完成，再回收相关 Scoped。
      -- 此处只撤销实际使用，避免重复扫描整批实例或早于进度更新进行关闭。
      maybe (detachScopeUser user) (const (pure ())) (launchUser launch)
      case completed of
        Left (exception :: SomeException) -> throwIO exception
        Right outcome -> pure outcome)
    `finally` endActivation graph (activationId activation)
