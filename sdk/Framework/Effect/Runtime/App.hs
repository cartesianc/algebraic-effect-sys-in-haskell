{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE ScopedTypeVariables #-}

-- IO 载体：Context 绑定携带值快照和 scope 归属，生命周期操作跟随该绑定。
module Framework.Effect.Runtime.App (App, runApp) where

import Framework.Effect.Binding
import Framework.Effect.Contract
import Framework.Effect.Scope
import Control.Concurrent.MVar (readMVar, withMVar, takeMVar, putMVar)
import Control.Exception (Exception, SomeException, fromException, mask, throwIO, try)
import Control.Monad (forM, forM_, when)
import Control.Monad.Except (ExceptT, MonadError, catchError, runExceptT, throwError)
import Control.Monad.IO.Class (MonadIO(..))
import Control.Monad.Reader (ReaderT, ask, asks, local, runReaderT)
import Data.IORef (IORef, atomicModifyIORef', newIORef, readIORef, writeIORef)
import Data.List (find, nub)
import Data.Maybe (catMaybes, fromMaybe, isJust)
import Data.Unique (Unique, newUnique)

type Bound env cause = Binding env (String, ScopeInstance env cause)

data Environment env cause = Environment
  { emptyValues :: env
  , bindings :: IORef (ScopeBindings env cause)
  , scopes :: Scopes env cause
  , caller :: Maybe String
  , dependencies :: [String]
  , contexts :: [String]
  , openings :: [Opening env cause]
  , closings :: [Closing env cause]
  , errorHandlers :: [(String, ErrorHandler (App env cause))]
  , errorPath :: [String]
  , originalFailure :: Maybe (Failure cause)
  , diagnosticOwner :: Maybe (ScopeInstance env cause)
  }

data Opening env cause = Opening
  { family :: ScopeHandler env cause
  , wrapFault :: ScopeFault -> cause
  , observed :: IORef [ScopeInput]
  , produced :: IORef (ScopeBindings env cause)
  , holding :: IORef (Maybe (ScopeInstance env cause))
  , token :: Unique
  }

data Closing env cause = Closing
  { closeFamily :: ScopeHandler env cause
  , closeFault :: ScopeFault -> cause
  , closeHolding :: IORef (Maybe (ScopeInstance env cause, ScopePhase cause))
  , closeToken :: Unique
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
fault name wrap problem = Failure name (wrap problem) (show problem) [] [] Nothing

-- 没有业务 Context 的 scope 使用内部 unit 绑定；不是新增业务 effect 或配置 key。
resourceSource :: ScopeHandler env cause -> String
resourceSource handler = fromMaybe ("$scope:" ++ scopeName handler) (scopeContextSource handler)

ownedNames :: Environment env cause -> [String]
ownedNames environment = map (scopeName . family) (openings environment)
  ++ map (scopeName . closeFamily) (closings environment)

rememberBinding :: Environment env cause -> String -> Bound env cause -> IO ()
rememberBinding environment source value = atomicModifyIORef' (bindings environment) $ \current ->
  (bind source value current, ())

-- 优先使用本次调用已捕获的不可变绑定。跨链首次读取只接受唯一来源绑定。
-- 多份绑定不按时间排序、不按 scope 数量选择、不执行生产者。
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
          fmap catMaybes $ forM instances $ \slot ->
            lookup source . scopeBindings <$> readIORef (scopeRecord slot)
      case candidates of
        [] -> pure (Right Nothing)
        [value] -> rememberBinding environment source value >> pure (Right (Just value))
        _ -> pure (Left (AmbiguousContextBinding source))

owns :: Environment env cause -> ScopeInstance env cause -> IO Bool
owns environment slot = do
  opening <- mapM (readIORef . holding) (openings environment)
  closing <- mapM (readIORef . closeHolding) (closings environment)
  pure (any ((== scopeRecord slot) . scopeRecord)
    (catMaybes opening ++ map fst (catMaybes closing)))

checkBinding :: Environment env cause -> Bound env cause -> App env cause ()
checkBinding environment value = forM_ (bindingOwners value) $ \(_, slot) -> do
  owner <- rawIO (owns environment slot)
  let diagnosing = maybe False ((== scopeRecord slot) . scopeRecord) (diagnosticOwner environment)
  when (not owner && not diagnosing) $ do
    phase <- rawIO (withMVar (scopeGate slot) (const (scopePhase <$> readIORef (scopeRecord slot))))
    maybe (pure ()) throwError (scopeFailure phase)

setPhase :: ScopeInstance env cause -> ScopePhase cause -> IO ()
setPhase slot phase = atomicModifyIORef' (scopeRecord slot) $ \record ->
  (record { scopePhase = phase }, ())

saveBinding :: ScopeInstance env cause -> String -> Bound env cause -> IO ()
saveBinding slot source value = atomicModifyIORef' (scopeRecord slot) $ \record ->
  (record { scopeBindings = bind source value (scopeBindings record)
          , scopeSources = nub (source : scopeSources record) }, ())

-- scope 只保留已经建立的绑定；复用时传递原绑定，绝不另设“当前 scope”指针。
reuseBindings :: Environment env cause -> ScopeInstance env cause -> IO ()
reuseBindings environment slot = do
  saved <- scopeBindings <$> readIORef (scopeRecord slot)
  forM_ saved $ \(source, value) -> rememberBinding environment source value

ensureOpen :: Environment env cause -> Opening env cause -> IO (Either (Failure cause) ())
ensureOpen environment attempt = do
  active <- readIORef (holding attempt)
  case active of
    Just _ -> pure (Right ())
    Nothing -> do
      inputs <- readIORef (observed attempt)
      let handler = family attempt
          name = scopeName handler
          missing = filter (`notElem` map inputName inputs) (scopeInputSources handler)
      if not (null missing)
        then pure (Left (fault name (wrapFault attempt) (ScopeInputsMissing missing)))
        else do
          let acquire = mask $ \_ -> do
                slot <- selectScopeInstance handler inputs
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
                        (record { scopePhase = ScopeOpening, scopeBindings = values
                                , scopeSources = map fst values }, ())
                      when (scopeContextSource handler == Nothing) $ do
                        let source = resourceSource handler
                            value = Binding (emptyValues environment) [(name, slot)]
                        saveBinding slot source value
                        rememberBinding environment source value
                      pure (Right ())
          acquire

missingClose :: Closing env cause -> Failure cause
missingClose attempt = fault (scopeName (closeFamily attempt)) (closeFault attempt)
  (ScopeContextMissing (resourceSource (closeFamily attempt)))

-- 在用户 close 方法实际 require 的位置，根据该绑定中的归属取得锁。
-- 同名资源重新开启产生另一份归属；旧绑定永远不会指向新实例。
beginClose :: Closing env cause -> Bound env cause -> IO (Either (Failure cause) ())
beginClose attempt value = do
  active <- readIORef (closeHolding attempt)
  case active of
    Just (slot, _) -> case lookup (scopeName (closeFamily attempt)) (bindingOwners value) of
      Just owner | scopeRecord owner == scopeRecord slot -> pure (Right ())
      _ -> pure (Left (fault (scopeName (closeFamily attempt)) (closeFault attempt)
            (ScopeContextMismatch (resourceSource (closeFamily attempt)))))
    Nothing -> case lookup (scopeName (closeFamily attempt)) (bindingOwners value) of
      Nothing -> pure (Left (missingClose attempt))
      Just slot -> mask $ \_ -> do
        takeMVar (scopeGate slot)
        phase <- scopePhase <$> readIORef (scopeRecord slot)
        let name = scopeName (closeFamily attempt)
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
  readContextBinding source select = do
    environment <- AppRun ask
    resolved <- rawIO (resolveBinding environment source)
    case resolved of
      Left problem -> pure (Left problem)
      Right Nothing -> pure (Right Nothing)
      Right (Just value) -> do
        case closings environment of
          attempt : _ | resourceSource (closeFamily attempt) == source ->
            rawIO (beginClose attempt value) >>= either throwError pure
          _ -> pure ()
        checkBinding environment value
        -- open 也可引用已生产的 Context；只附加本次归属，不改写原值。
        case openings environment of
          attempt : _ | resourceSource (family attempt) == source -> do
            selected <- rawIO (readIORef (holding attempt))
            case selected of
              Just slot -> do
                let name = scopeName (family attempt)
                case lookup name (bindingOwners value) of
                  Just original | scopeRecord original /= scopeRecord slot ->
                    throwError (fault name (wrapFault attempt) (ScopeContextMismatch source))
                  _ -> pure ()
                let bound = value { bindingOwners = [(name, slot)] }
                rawIO (saveBinding slot source bound >> rememberBinding environment source bound)
              Nothing -> pure ()
          _ -> pure ()
        pure (Right (select (bindingValues value)))
  publishContextBinding source update = do
    environment <- AppRun ask
    owner <- case openings environment of
      attempt : _ | resourceSource (family attempt) == source -> do
        rawIO (ensureOpen environment attempt) >>= either throwError pure
        selected <- rawIO (readIORef (holding attempt))
        pure [(scopeName (family attempt), slot) | Just slot <- [selected]]
      _ -> pure []
    let value = Binding (update (emptyValues environment)) owner
    rawIO (rememberBinding environment source value)
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
  recordContextInput value = do
    environment <- AppRun ask
    case openings environment of
      attempt : _ | inputName value `elem` scopeInputSources (family attempt) -> do
        previous <- rawIO (readIORef (observed attempt))
        started <- rawIO (readIORef (holding attempt))
        case started of
          Just _ | value `notElem` previous -> throwError
            (fault (scopeName (family attempt)) (wrapFault attempt) (ScopeInputAfterOpen (inputName value)))
          _ -> pure ()
        rawIO $ writeIORef (observed attempt)
          (value : filter ((/= inputName value) . inputName) previous)
        let missing = filter (`notElem` map inputName (value : previous)) (scopeInputSources (family attempt))
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
    case resolved of
      Right (Just value) | Just slot <- lookup name (bindingOwners value) -> do
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
        let traced = problem { scopeTrace = nub (scopeTrace problem ++ errorPath environment) }
        -- open/close 的内部调用还持有生命周期锁；退到锁外的 Root 后才诊断。
        if isJust (errorHandling problem)
          then throwError problem
          else if not (null (openings environment) && null (closings environment))
            then throwError traced
            else do
              reports <- forM
                [(selected, callback) | (selected, callback) <- errorHandlers environment
                                     , selected `elem` scopeTrace traced] $ \(selected, callback) ->
                  liftIO (runDiagnostic environment traced selected callback)
              throwError traced { errorHandling = Just reports }

-- 检测/处置共享本次故障的绑定快照。失败的 scope 可在此受限上下文中被检查、清理；
-- 不扫描其他实例，不修改业务调用已经捕获的值，也不重放业务 action。
runDiagnostic :: Environment env cause -> Failure cause -> String -> ErrorHandler (App env cause)
              -> IO (ErrorReport cause)
runDiagnostic environment problem selected callback = do
  captured <- readIORef (bindings environment)
  let capturedOwner = do
        family <- findScope (scopes environment) selected
        value <- lookup (resourceSource family) captured
        lookup selected (bindingOwners value)
  owner <- case lookup selected (scopeTargets problem) of
    Nothing -> pure capturedOwner
    Just Nothing -> pure Nothing
    Just (Just identity) -> do
      registered <- case findScope (scopes environment) selected of
        Nothing -> pure []
        Just family -> readMVar (scopeInstances family)
      let capturedSlots = concatMap (map snd . bindingOwners . snd) captured
      pure (find ((== identity) . scopeIdentity) (capturedSlots ++ registered))
  saved <- maybe (pure []) (fmap scopeBindings . readIORef . scopeRecord) owner
  let belongsElsewhere (_, value) = case lookup selected (bindingOwners value) of
        Nothing -> False
        Just slot -> maybe True ((/= scopeRecord slot) . scopeRecord) owner
      -- 开启 B 失败时，不能把 request 刷新失败后保留的 A 资源当成 B。
      capturedHere = filter (not . belongsElsewhere) captured
      restored = foldr (\(source, value) values -> bind source value values) capturedHere saved
      execute = do
        values <- newIORef restored
        let inside = environment
              { bindings = values, caller = Nothing, contexts = [], openings = [], closings = []
              , originalFailure = Just problem, diagnosticOwner = owner }
            AppRun action = runErrorHandler selected callback
        result <- runExceptT (runReaderT action inside)
        -- runErrorHandler 接回 detect/resolve 的 Failure；不捕获取消等原生 IO 异常。
        case result of
          Right report -> pure report
          Left failure -> case callback of
            ErrorHandler name _ _ -> pure (ErrorReport selected name (Just (Failed failure)) Nothing)
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

runOpen :: String -> (ScopeFault -> cause) -> App env cause () -> App env cause ()
runOpen name wrap (AppRun action) = AppRun $ do
  environment <- ask
  when (name `elem` ownedNames environment) (throwError (fault name wrap ScopeReentry))
  result <- liftIO $ mask $ \restore -> do
    handler <- getScope (scopes environment) name
    attempt <- Opening handler wrap <$> newIORef [] <*> newIORef [] <*> newIORef Nothing <*> newUnique
    let inside = environment { openings = attempt : openings environment }
        execute = do
          when (null (scopeInputSources handler)) $
            liftIO (ensureOpen inside attempt) >>= either throwError pure
          runReaderT action inside
          liftIO (ensureOpen inside attempt) >>= either throwError pure
          selected <- liftIO (readIORef (holding attempt))
          forM_ selected $ \slot -> do
            saved <- liftIO (scopeBindings <$> readIORef (scopeRecord slot))
            when (resourceSource handler `notElem` map fst saved) $
              throwError (fault name wrap (ScopeContextMissing (resourceSource handler)))
    outcome <- try (restore (runExceptT execute))
    acquired <- readIORef (holding attempt)
    case outcome of
      Left (exception :: SomeException) -> do
        forM_ acquired $ \slot ->
          setPhase slot (interruptedScope name wrap exception) >> putMVar (scopeGate slot) ()
        case fromException exception of
          Just (Completed identity) | identity == token attempt -> pure (Right ())
          _ -> throwIO exception
      Right completed -> case acquired of
        Nothing -> pure (either (Left . scopeFailureTarget name Nothing) Right completed)
        Just slot -> do
          current <- scopePhase <$> readIORef (scopeRecord slot)
          let finalPhase = finishScope OpenScope name wrap current completed
          setPhase slot finalPhase
          putMVar (scopeGate slot) ()
          pure (either (Left . scopeFailureTarget name (Just slot)) Right
            (maybe completed Left (scopeFailure finalPhase)))
  either throwError pure result

runClose :: String -> (ScopeFault -> cause) -> App env cause () -> App env cause ()
runClose name wrap (AppRun action) = AppRun $ do
  environment <- ask
  when (name `elem` ownedNames environment) (throwError (fault name wrap ScopeReentry))
  result <- liftIO $ mask $ \restore -> do
    handler <- getScope (scopes environment) name
    attempt <- Closing handler wrap <$> newIORef Nothing <*> newUnique
    let inside = environment { closings = attempt : closings environment }
        execute = do
          when (scopeContextSource handler == Nothing) $ do
            resolved <- liftIO (resolveBinding inside (resourceSource handler))
            case resolved of
              Right (Just value) -> liftIO (beginClose attempt value) >>= either throwError pure
              _ -> throwError (missingClose attempt)
          runReaderT action inside
          active <- liftIO (readIORef (closeHolding attempt))
          case active of Nothing -> throwError (missingClose attempt); Just _ -> pure ()
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
          Just (Completed identity) | identity == closeToken attempt -> pure (Right ())
          _ -> throwIO exception
      Right completed -> do
        forM_ acquired $ \(slot, initial) -> do
          setPhase slot (finishScope CloseScope name wrap initial completed)
          putMVar (scopeGate slot) ()
        pure (either (Left . scopeFailureTarget name (fst <$> acquired)) Right completed)
  either throwError pure result

runApp :: Scopes env cause -> env -> App env cause value -> IO (Either (Failure cause) value)
runApp handlers initial (AppRun action) = do
  values <- newIORef []
  runExceptT (runReaderT action (Environment initial values handlers Nothing [] [] [] [] [] [] Nothing Nothing))
