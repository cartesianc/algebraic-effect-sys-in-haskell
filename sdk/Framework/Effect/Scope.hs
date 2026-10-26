-- SDK 的 scope 状态与并发开启保护；不另设业务产值契约。
module Framework.Effect.Scope
  ( ScopePhase(..), ScopeRecord(..), ScopeOperation(..)
  , emptyScope, scopeFailure, beginScope, finishScope, interruptedScope
  , Scopes, ScopeBindings, ScopeHandler(..), ScopeInstance(..), ScopeInput(..)
  , ScopeCleanup(..), cleanupScopes, newScopeHandler, findScope, getScope, selectScopeInstance
  , ScopeUser(..), newScopeUser, useScope, detachScopeUser, releaseScopeUser, saveCleanupFailures
  , configureScopeRelations, scopeErrorPath, reserveScopeClose, finishScopeClose
  ) where

import Framework.Effect.Binding (Bindings)
import Framework.Effect.Contract (Failure(..), ScopeFault(..), ScopeInput(..), ScopeInputAccess(..))
import Control.Concurrent.MVar (MVar, newMVar, newEmptyMVar, modifyMVar, readMVar, withMVar, putMVar)
import Control.Exception (SomeException, displayException, mask_, try, finally, uninterruptibleMask_)
import Control.Monad (forM, forM_, when)
import Data.IORef (IORef, newIORef, readIORef, writeIORef, atomicModifyIORef')
import Data.List (find, sortOn, nub)
import Data.Maybe (isJust)
import Data.Unique (Unique, hashUnique, newUnique)

data ScopePhase cause
  = ScopeIdle | ScopeOpening | ScopeActive | ScopeClosing
  | ScopeInvalid (Failure cause) | ScopeClosed (Failure cause)

data ScopeRecord environment cause = ScopeRecord
  { scopePhase :: ScopePhase cause
  , scopeBindings :: environment
  , scopeSources :: [String]
  }

data ScopeOperation = OpenScope | CloseScope

emptyScope :: environment -> ScopeRecord environment cause
emptyScope environment = ScopeRecord ScopeIdle environment []

scopeFailure :: ScopePhase cause -> Maybe (Failure cause)
scopeFailure (ScopeInvalid failure) = Just failure
scopeFailure (ScopeClosed failure) = Just failure
scopeFailure _ = Nothing

scopeFault :: String -> (ScopeFault -> cause) -> ScopeFault -> Failure cause
scopeFault selected wrap fault = Failure selected (wrap fault) (show fault) [] [] Nothing []

-- True 才执行方法体；Active 的再次 open 和 Closed 的再次 close 均直接完成。
-- Invalid 不自动重开；关闭仍可尝试释放已经取得的资源。
beginScope :: ScopeOperation -> String -> (ScopeFault -> cause) -> ScopePhase cause
           -> Either (Failure cause) Bool
beginScope OpenScope _ _ ScopeActive = Right False
beginScope OpenScope _ _ ScopeIdle = Right True
beginScope OpenScope _ _ (ScopeInvalid failure) = Left failure
beginScope OpenScope _ _ (ScopeClosed _) = Right True
beginScope CloseScope _ _ ScopeActive = Right True
beginScope CloseScope _ _ (ScopeInvalid _) = Right True
beginScope CloseScope _ _ (ScopeClosed _) = Right False
beginScope CloseScope selected wrap ScopeIdle = Left (scopeFault selected wrap ScopeNotOpen)
beginScope _ selected wrap _ = Left (scopeFault selected wrap ScopeReentry)

finishScope :: ScopeOperation -> String -> (ScopeFault -> cause) -> ScopePhase cause
            -> Either (Failure cause) () -> ScopePhase cause
finishScope OpenScope _ _ (ScopeInvalid original) _ = ScopeInvalid original
finishScope _ _ _ (ScopeInvalid original) (Left _) = ScopeInvalid original
finishScope _ _ _ _ (Left failure) = ScopeInvalid failure
finishScope OpenScope _ _ _ (Right ()) = ScopeActive
finishScope CloseScope selected wrap _ (Right ()) = ScopeClosed (scopeFault selected wrap ScopeIsClosed)

interruptedScope :: String -> (ScopeFault -> cause) -> SomeException -> ScopePhase cause
interruptedScope selected wrap exception =
  ScopeInvalid (scopeFault selected wrap (ScopeInterrupted (displayException exception)))

-- 生成的 handler 创建各自的控制对象；末端句柄只保存对同份对象的引用。
-- 集合本身不可变，生命周期状态和锁属于各个 scope，不属于 AST。
type Scopes environment cause = [ScopeHandler environment cause]

-- 同一注册的实例集合；锁只保护查找／创建，不覆盖不同实例的业务 IO。
data ScopeHandler environment cause = ScopeHandler
  { scopeName :: String
  , scopeInputSources :: [String]
  , scopeContextSource :: Maybe String
  , scopeInstances :: MVar [ScopeInstance environment cause]
  , scopeCoordinator :: IORef (MVar ())
  , scopePeers :: IORef (Scopes environment cause)
  , scopeParentNames :: IORef [String]
  , scopePendingFailures :: IORef [(Maybe SomeException, Failure cause)]
  }

type ScopeBindings environment cause = Bindings environment (String, ScopeInstance environment cause)

data ScopeInstance environment cause = ScopeInstance
  { scopeInputs :: [ScopeInput]
  , scopeShared :: Bool
  , scopeFamily :: ScopeHandler environment cause
  , scopeGate :: MVar ()
  , scopeRecoveryGate :: MVar ()
  , scopeIdentity :: Int
  , scopeRecord :: IORef (ScopeRecord (ScopeBindings environment cause) cause)
  , scopeCleanup :: IORef (Maybe (ScopeCleanup cause))
  , scopeUsers :: IORef [Unique]
  , scopeRetiring :: IORef (Maybe (Unique, MVar ()))
  }

data ScopeUser environment cause = ScopeUser
  { scopeUserIdentity :: Unique
  , scopeUserInstances :: IORef [ScopeInstance environment cause]
  }

newScopeUser :: IO (ScopeUser environment cause)
newScopeUser = ScopeUser <$> newUnique <*> newIORef []

-- 捕获一次实际开启的实例和绑定；业务仍只实现原来的 close 方法。
data ScopeCleanup cause = ScopeCleanup
  (String -> Failure cause)
  (Unique -> IO (Either (Failure cause) ()))

newScopeHandler :: String -> [String] -> Maybe String -> IO (ScopeHandler environment cause)
newScopeHandler selected inputs source = do
  handler <- ScopeHandler selected inputs source <$> newMVar []
    <*> (newMVar () >>= newIORef) <*> newIORef [] <*> newIORef [] <*> newIORef []
  writeIORef (scopePeers handler) [handler]
  pure handler

-- 只在一批业务启动前配置。重复配置保留状态和同一协调锁，空关系不抹掉既有关系。
configureScopeRelations :: [(String, [String])] -> Scopes environment cause -> IO ()
configureScopeRelations _ [] = pure ()
configureScopeRelations relations handlers@(first : _) = do
  coordinator <- readIORef (scopeCoordinator first)
  forM_ handlers $ \handler -> do
    writeIORef (scopeCoordinator handler) coordinator
    writeIORef (scopePeers handler) handlers
    forM_ (lookup (scopeName handler) relations) (writeIORef (scopeParentNames handler) . nub)

-- Error 导航读取同一棵已校验树的祖先投影；不另存 Error 图。
-- 同层保留 handler 顺序；尚未配置树的显式种子仍可进入诊断。
scopeErrorPath :: Scopes environment cause -> [String] -> IO [String]
scopeErrorPath handlers seeds = do
  relationships <- forM handlers $ \handler -> do
    parents <- readIORef (scopeParentNames handler)
    pure (scopeName handler, parents)
  let selected = nub (seeds ++ concat [parents | (name, parents) <- relationships, name `elem` seeds])
      ordered = filter (`elem` selected) (nub (map fst relationships ++ selected))
      parents name = maybe [] id (lookup name relationships)
      topDown [] = []
      topDown remaining =
        let ready = [name | name <- remaining, all (`notElem` remaining) (parents name)]
        in ready ++ topDown (filter (`notElem` ready) remaining)
  pure (topDown ordered)

-- 锁内仅做内存登记；不运行 handler，也不等待 scopeGate 或关闭完成信号。
coordinated :: ScopeHandler environment cause -> IO value -> IO value
coordinated handler action = uninterruptibleMask_ $ do
  coordinator <- readIORef (scopeCoordinator handler)
  withMVar coordinator (const action)

rememberUse :: ScopeUser environment cause -> ScopeInstance environment cause -> IO ()
rememberUse user slot = do
  users <- readIORef (scopeUsers slot)
  when (scopeUserIdentity user `notElem` users) $ do
    writeIORef (scopeUsers slot) (scopeUserIdentity user : users)
    atomicModifyIORef' (scopeUserInstances user) $ \slots ->
      (if any ((== scopeRecord slot) . scopeRecord) slots then slots else slot : slots, ())

-- 预约必须先于等待 opening。retiring 的旧实例不再接纳新使用者。
useScope :: ScopeUser environment cause -> ScopeInstance environment cause -> IO (Maybe (MVar ()))
useScope user slot = coordinated (scopeFamily slot) $ do
  retiring <- readIORef (scopeRetiring slot)
  case retiring of
    Just (_, finished) -> pure (Just finished)
    Nothing -> rememberUse user slot >> pure Nothing

parentClosing :: ScopeHandler environment cause -> IO (Maybe (MVar ()))
parentClosing handler = do
  parents <- readIORef (scopeParentNames handler)
  peers <- readIORef (scopePeers handler)
  states <- fmap concat $ forM (filter ((`elem` parents) . scopeName) peers) $ \parent -> do
    slots <- readMVar (scopeInstances parent)
    mapM (readIORef . scopeRetiring) slots
  pure $ case [finished | Just (_, finished) <- states] of
    [] -> Nothing
    first : _ -> Just first

-- 已关闭的同参实例建立新一轮；旧引用仍指向旧的 Closed 实例。
selectScopeInstance :: ScopeUser environment cause -> ScopeHandler environment cause
                    -> [(ScopeInputAccess, ScopeInput)]
                    -> IO (Either (MVar ()) (ScopeInstance environment cause))
selectScopeInstance user handler observations = coordinated handler $ do
  waiting <- parentClosing handler
  case waiting of
    Just finished -> pure (Left finished)
    Nothing -> modifyMVar (scopeInstances handler) select
  where
    inputs = map snd observations
    shared = all ((/= RequestedInput) . fst) observations
    select instances = do
      let source (ScopeInput name _) = name
          matches slot = shared && scopeShared slot && sortOn source inputs == sortOn source (scopeInputs slot)
          create = do
            slot <- ScopeInstance inputs shared handler <$> newMVar () <*> newMVar () <*> (hashUnique <$> newUnique)
              <*> newIORef (emptyScope []) <*> newIORef Nothing <*> newIORef [] <*> newIORef Nothing
            rememberUse user slot
            pure (slot : instances, Right slot)
      eligible <- fmap concat $ forM (filter matches instances) $ \slot -> do
        phase <- scopePhase <$> readIORef (scopeRecord slot)
        retiring <- readIORef (scopeRetiring slot)
        pure $ case (phase, retiring) of
          (ScopeClosed _, Nothing) -> []
          _ -> [slot]
      case eligible of
        [] -> create
        slot : _ -> do
          retiring <- readIORef (scopeRetiring slot)
          case retiring of
            Just (_, finished) -> pure (instances, Left finished)
            Nothing -> rememberUse user slot >> pure (instances, Right slot)

-- 失败且尚未发布资源的实例不是活资源；保留故障证据但不挡住父级收尾。
liveInstance :: ScopeInstance environment cause -> IO Bool
liveInstance slot = do
  phase <- scopePhase <$> readIORef (scopeRecord slot)
  users <- readIORef (scopeUsers slot)
  cleanup <- readIORef (scopeCleanup slot)
  retiring <- readIORef (scopeRetiring slot)
  pure $ isJust retiring || case phase of
    ScopeClosed _ -> False
    _ -> not (null users) || isJust cleanup

hasLiveChildren :: ScopeInstance environment cause -> IO Bool
hasLiveChildren slot = do
  let handler = scopeFamily slot
  peers <- readIORef (scopePeers handler)
  children <- fmap concat $ forM peers $ \child -> do
    parents <- readIORef (scopeParentNames child)
    if scopeName handler `elem` parents then readMVar (scopeInstances child) else pure []
  or <$> mapM liveInstance children

-- permit 仅由已预约的 cleanup 传回；显式 close 只可排除自身 consumer。
reserveScopeClose :: Maybe Unique -> Maybe Unique -> Unique -> ScopeInstance environment cause -> IO Bool
reserveScopeClose consumer permit ticket slot = coordinated (scopeFamily slot) $ do
  retiring <- readIORef (scopeRetiring slot)
  case retiring of
    Just (owner, _) -> pure (permit == Just owner)
    Nothing -> do
      phase <- scopePhase <$> readIORef (scopeRecord slot)
      users <- readIORef (scopeUsers slot)
      children <- hasLiveChildren slot
      let closed = case phase of ScopeClosed _ -> True; _ -> False
      if not closed && (any (\user -> Just user /= consumer) users || children)
        then pure False
        else do
          finished <- newEmptyMVar
          writeIORef (scopeRetiring slot) (Just (ticket, finished))
          pure True

finishScopeClose :: Unique -> ScopeInstance environment cause -> IO ()
finishScopeClose ticket slot = uninterruptibleMask_ $ coordinated (scopeFamily slot) $ do
  retiring <- readIORef (scopeRetiring slot)
  case retiring of
    Just (owner, finished) | owner == ticket -> do
      writeIORef (scopeRetiring slot) Nothing
      putMVar finished ()
    _ -> pure ()

releaseScopeUser :: ScopeUser environment cause -> Scopes environment cause
                 -> IO [(Maybe SomeException, Failure cause)]
releaseScopeUser user handlers = do
  detachScopeUser user
  cleanupAvailable handlers

-- 清理动作也可临时借用别的资源；退出只撤销这些借用，由外层 sweep 收尾。
detachScopeUser :: ScopeUser environment cause -> IO ()
detachScopeUser user = do
  slots <- readIORef (scopeUserInstances user)
  forM_ slots $ \slot -> uninterruptibleMask_ $ coordinated (scopeFamily slot) $
    atomicModifyIORef' (scopeUsers slot) (\users -> (filter (/= scopeUserIdentity user) users, ()))
  writeIORef (scopeUserInstances user) []

saveCleanupFailures :: Scopes environment cause -> [(Maybe SomeException, Failure cause)] -> IO ()
saveCleanupFailures [] _ = pure ()
saveCleanupFailures (handler : _) failures =
  atomicModifyIORef' (scopePendingFailures handler) (\saved -> (saved ++ failures, ()))

-- interpreter 已等待全部受管理任务退出。按依赖的逆序收尾，一份失败不跳过其余实例。
-- 保留原生异常，边界在收尾完成后重新抛出；失败不能伪装成成功的资源释放。
cleanupScopes :: Scopes environment cause -> IO [(Maybe SomeException, Failure cause)]
cleanupScopes handlers = do
  pending <- fmap concat $ forM handlers $ \handler ->
    atomicModifyIORef' (scopePendingFailures handler) (\saved -> ([], saved))
  failures <- cleanupAvailable handlers
  pure (pending ++ failures)

-- 每轮最多尝试每个实例一次。叶实例释放后重扫之前被挡住的祖先；失败留待外层重试。
cleanupAvailable :: Scopes environment cause -> IO [(Maybe SomeException, Failure cause)]
cleanupAvailable handlers = mask_ (sweep [] [])
  where
    sweep attempted failures = do
      slots <- uninterruptibleMask_ $ concat <$> mapM (readMVar . scopeInstances) (reverse handlers)
      results <- forM [slot | slot <- slots, scopeRecord slot `notElem` attempted] $ \slot -> do
        phase <- scopePhase <$> readIORef (scopeRecord slot)
        cleanup <- readIORef (scopeCleanup slot)
        case (phase, cleanup) of
          (ScopeClosed _, _) -> pure Nothing
          (_, Nothing) -> pure Nothing
          (_, Just (ScopeCleanup interrupted action)) -> do
            ticket <- newUnique
            ready <- reserveScopeClose Nothing Nothing ticket slot
            if not ready then pure Nothing else do
              outcome <- try (action ticket) `finally` finishScopeClose ticket slot
              let reported = case outcome of
                    Left exception -> [(Just exception, interrupted (displayException exception))]
                    Right (Left failure) -> [(Nothing, failure)]
                    Right (Right ()) -> []
              pure (Just (scopeRecord slot, reported))
      let completed = [result | Just result <- results]
      if null completed then pure failures
        else sweep (map fst completed ++ attempted) (failures ++ concatMap snd completed)

findScope :: Scopes environment cause -> String -> Maybe (ScopeHandler environment cause)
findScope scopes selected = find ((== selected) . scopeName) scopes

getScope :: Scopes environment cause -> String -> IO (ScopeHandler environment cause)
getScope scopes selected = case findScope scopes selected of
  Just handler -> pure handler
  Nothing -> ioError (userError ("Missing generated scope handler: " ++ selected ++ "; regenerate handlers"))

