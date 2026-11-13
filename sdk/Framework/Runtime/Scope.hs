-- Scope 的状态、使用登记与关闭预约；不执行业务 open／close 的方法体。
-- ScopeHandler 属于一份注册，持有运行实例表；ScopeInstance 属于一次资源获取；
-- ScopeUser 属于一个受控入口（或持续生产会话），记录它实际使用的实例。
-- 注册间依赖由 Prototype 的独立 ScopeTree 安装，活动调用父子关系不改写它。
--
-- 锁边界：coordinator 串行化归属认领、使用登记与关闭预约，锁内只改内存；
-- scopeInstances 保护实例表；scopeGate 保护单实例生命周期；scopeRecoveryGate
-- 串行化诊断。业务方法体和生命周期 gate 的等待由 Runtime/App 协调。
-- 实际使用与执行帧的待用关系均消失后，cleanupAvailable 按依赖释放。
module Framework.Runtime.Scope
  ( ScopePhase(..), ScopeRecord(..), ScopeOperation(..)
  , emptyScope, scopeFailure, beginScope, finishScope, interruptedScope
  , Scopes, ScopeBinding, ScopeBindings, ScopeHandler(..), ScopeInstance(..), ScopeInput(..)
  , ScopeCleanup(..), cleanupScopes, cleanupAvailable, newScopeHandler, findScope, getScope, selectScopeInstance
  , ScopeUser(..), newScopeUser, useScope, detachScopeUser, saveCleanupFailures
  , rememberUnownedBinding, claimBindingOwner
  , configureScopeRelations, scopeErrorPath, reserveScopeClose, finishScopeClose
  ) where

import Framework.Runtime.Binding (Binding(..), BindingOwnership(..), Bindings)
import Framework.Language.Handler (Failure(..))
import Framework.Runtime.Protocol (ScopeFault(..), ScopeInput(..))
import Framework.Runtime.Identity (Execution)
import Framework.Runtime.Frame (ExecutionFrame)
import Control.Concurrent.MVar (MVar, newMVar, newEmptyMVar, modifyMVar, readMVar, withMVar, putMVar)
import Control.Exception (SomeException, displayException, mask, try, finally, uninterruptibleMask_)
import Control.Monad (forM, forM_, when, void)
import Data.IORef (IORef, newIORef, readIORef, writeIORef, atomicModifyIORef')
import Data.List (find, sortOn, nub)
import Data.Maybe (isJust)
import Data.Unique (Unique, hashUnique, newUnique)

-- 生命周期状态 ---------------------------------------------------------------

data ScopePhase cause
  = ScopeIdle | ScopeOpening | ScopeActive | ScopeClosing
  | ScopeInvalid (Failure cause) | ScopeClosed (Failure cause)

data ScopeRecord environment cause = ScopeRecord
  { scopePhase :: ScopePhase cause
  , scopeBindings :: environment
  }

data ScopeOperation = OpenScope | CloseScope

emptyScope :: environment -> ScopeRecord environment cause
emptyScope environment = ScopeRecord ScopeIdle environment

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

-- 控制对象、实例和入口使用者 ---------------------------------------------------

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
  , scopeReachable :: IORef (ScopeInstance environment cause -> IO Bool)
  , scopePendingFailures :: IORef [(Maybe SomeException, Failure cause)]
  }

type ScopeBinding environment cause =
  Binding environment (String, ScopeInstance environment cause) (ScopeUser environment cause)

type ScopeBindings environment cause =
  Bindings environment (String, ScopeInstance environment cause) (ScopeUser environment cause)

type ScopeOwnership environment cause =
  BindingOwnership (String, ScopeInstance environment cause) (ScopeUser environment cause)

data ScopeInstance environment cause = ScopeInstance
  { scopeInputs :: [ScopeInput]
  , scopeFrame :: ExecutionFrame
  , scopeFamily :: ScopeHandler environment cause
  , scopeGate :: MVar ()
  , scopeRecoveryGate :: MVar ()
  , scopeIdentity :: Int
  , scopeRecord :: IORef (ScopeRecord (ScopeBindings environment cause) cause)
  , scopeCleanup :: IORef (Maybe (ScopeCleanup cause))
  , scopeUsers :: IORef [(Unique, Execution)]
  , scopeParents :: IORef [ScopeInstance environment cause]
  , scopeRetiring :: IORef (Maybe (Unique, MVar ()))
  }

data ScopeUser environment cause = ScopeUser
  { scopeUserIdentity :: Unique
  , scopeUserExecution :: Execution
  , scopeUserInstances :: IORef [ScopeInstance environment cause]
  , scopeUserBindings :: IORef [IORef (ScopeOwnership environment cause)]
  , scopeUserCoordinator :: MVar ()
  }

-- 一次入口的实际使用登记；Context request 继承同一登记，不改变 ScopeTree。
newScopeUser :: Scopes environment cause -> Execution -> IO (ScopeUser environment cause)
newScopeUser handlers execution = do
  coordinator <- case handlers of
    first : _ -> readIORef (scopeCoordinator first)
    [] -> newMVar ()
  ScopeUser <$> newUnique <*> pure execution <*> newIORef [] <*> newIORef [] <*> pure coordinator

-- 捕获一次实际开启的实例和绑定；业务仍只实现原来的 close 方法。
data ScopeCleanup cause = ScopeCleanup
  (Unique -> SomeException -> IO (Failure cause))
  (Unique -> IO (Either (Failure cause) ()))

newScopeHandler :: String -> [String] -> Maybe String -> IO (ScopeHandler environment cause)
newScopeHandler selected inputs source = do
  handler <- ScopeHandler selected inputs source <$> newMVar []
    <*> (newMVar () >>= newIORef) <*> newIORef [] <*> newIORef []
    <*> newIORef (const (pure False)) <*> newIORef []
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

-- 归属、使用与实例选择 ---------------------------------------------------------

-- 锁内仅做内存登记；不运行 handler，也不等待 scopeGate 或关闭完成信号。
coordinated :: ScopeHandler environment cause -> IO value -> IO value
coordinated handler action = uninterruptibleMask_ $ do
  coordinator <- readIORef (scopeCoordinator handler)
  withMVar coordinator (const action)

coordinatedUser :: ScopeUser environment cause -> IO value -> IO value
coordinatedUser user action = uninterruptibleMask_ $
  withMVar (scopeUserCoordinator user) (const action)

-- 使用尚未认领的绑定也须登记，避免另一条链认领后关闭仍被本入口使用的资源。
-- 已有 owner 只交回调用方，由原有 useScope / 生命周期检查处理。
rememberUnownedBinding
  :: ScopeUser environment cause -> ScopeBinding environment cause
  -> IO (Maybe (String, ScopeInstance environment cause))
rememberUnownedBinding user value = coordinatedUser user $ do
  let ownership = bindingOwnership value
  state <- readIORef ownership
  case bindingOwner state of
    Just owner -> pure (Just owner)
    Nothing -> do
      when (scopeUserIdentity user `notElem` map scopeUserIdentity (bindingUsers state)) $ do
        writeIORef ownership state { bindingUsers = user : bindingUsers state }
        pending <- readIORef (scopeUserBindings user)
        when (ownership `notElem` pending) $
          writeIORef (scopeUserBindings user) (ownership : pending)
      pure Nothing

-- 首次认领同时接入所有尚未退出的使用者；只有同一个实例可重复认领。
-- 调用方已选定并持有开启实例；锁内不等待生命周期 gate，也不执行 handler。
claimBindingOwner :: ScopeBinding environment cause -> String -> ScopeInstance environment cause -> IO Bool
claimBindingOwner value name slot = coordinated (scopeFamily slot) $ do
  let ownership = bindingOwnership value
  state <- readIORef ownership
  case bindingOwner state of
    Just (originalName, original) ->
      pure (originalName == name && scopeRecord original == scopeRecord slot)
    Nothing -> do
      forM_ (bindingUsers state) $ \user -> rememberUse user slot
      writeIORef ownership (BindingOwnership (Just (name, slot)) [])
      pure True

rememberUse :: ScopeUser environment cause -> ScopeInstance environment cause -> IO ()
rememberUse user slot = do
  users <- readIORef (scopeUsers slot)
  used <- readIORef (scopeUserInstances user)
  -- 注册关系只给出候选；保留的是同一受控入口实际使用的父实例。
  -- requests 可以先于 Input，故后来取得父实例时也须补齐此前子实例的引用。
  forM_ used $ \other -> do
    rememberParent slot other
    rememberParent other slot
  when (scopeUserIdentity user `notElem` map fst users) $ do
    writeIORef (scopeUsers slot) ((scopeUserIdentity user, scopeUserExecution user) : users)
    atomicModifyIORef' (scopeUserInstances user) $ \slots ->
      (if any ((== scopeRecord slot) . scopeRecord) slots then slots else slot : slots, ())

rememberParent :: ScopeInstance environment cause -> ScopeInstance environment cause -> IO ()
rememberParent child parent = do
  candidates <- readIORef (scopeParentNames (scopeFamily child))
  when (scopeName (scopeFamily parent) `elem` candidates) $ do
    parents <- readIORef (scopeParents child)
    when (all ((/= scopeRecord parent) . scopeRecord) parents) $
      writeIORef (scopeParents child) (parent : parents)

-- 预约必须先于等待 opening。retiring 的旧实例不再接纳新使用者。
useScope :: ScopeUser environment cause -> ScopeInstance environment cause -> IO (Maybe (MVar ()))
useScope user slot = coordinated (scopeFamily slot) $ do
  retiring <- readIORef (scopeRetiring slot)
  case retiring of
    Just (_, finished) -> pure (Just finished)
    Nothing -> rememberUse user slot >> pure Nothing

parentClosing :: ScopeUser environment cause -> ScopeHandler environment cause -> IO (Maybe (MVar ()))
parentClosing user handler = do
  parents <- readIORef (scopeParentNames handler)
  used <- readIORef (scopeUserInstances user)
  states <- mapM (readIORef . scopeRetiring)
    (filter ((`elem` parents) . scopeName . scopeFamily) used)
  pure $ case [finished | Just (_, finished) <- states] of
    [] -> Nothing
    first : _ -> Just first

-- 实例身份只取实际参数的生产身份；同一次生产的读取和驱动观察不会另开实例。
-- 归属帧只在创建时保存，后继复用不能把本轮实例提升为外层常驻实例。
selectScopeInstance :: ScopeUser environment cause -> ScopeHandler environment cause
                    -> ExecutionFrame -> [ScopeInput]
                    -> IO (Either (MVar ()) (ScopeInstance environment cause))
selectScopeInstance user handler ownerFrame inputs = coordinated handler $ do
  waiting <- parentClosing user handler
  case waiting of
    Just finished -> pure (Left finished)
    Nothing -> modifyMVar (scopeInstances handler) select
  where
    select instances = do
      let source (ScopeInput name _) = name
          matches slot = sortOn source inputs == sortOn source (scopeInputs slot)
          create = do
            slot <- ScopeInstance inputs ownerFrame handler <$> newMVar () <*> newMVar () <*> (hashUnique <$> newUnique)
              <*> newIORef (emptyScope []) <*> newIORef Nothing <*> newIORef [] <*> newIORef [] <*> newIORef Nothing
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

-- 回调只读取执行帧和当前 publication；在 coordinator 内调用，不能等待或重新取锁。
pendingUse :: ScopeInstance environment cause -> IO Bool
pendingUse slot = readIORef (scopeReachable (scopeFamily slot)) >>= ($ slot)

-- 子实例的实际使用、待用关系和未完成的关闭都会保留父级。
liveInstance :: ScopeInstance environment cause -> IO Bool
liveInstance slot = do
  phase <- scopePhase <$> readIORef (scopeRecord slot)
  users <- readIORef (scopeUsers slot)
  cleanup <- readIORef (scopeCleanup slot)
  retiring <- readIORef (scopeRetiring slot)
  pending <- pendingUse slot
  pure $ isJust retiring || case phase of
    ScopeClosed _ -> False
    _ -> not (null users) || pending || isJust cleanup

hasLiveChildren :: ScopeInstance environment cause -> IO Bool
hasLiveChildren slot = do
  let handler = scopeFamily slot
  peers <- readIORef (scopePeers handler)
  children <- fmap concat $ forM peers $ \child -> do
    parents <- readIORef (scopeParentNames child)
    if scopeName handler `elem` parents then readMVar (scopeInstances child) else pure []
  or <$> forM children (\child -> do
    parents <- readIORef (scopeParents child)
    if any ((== scopeRecord slot) . scopeRecord) parents then liveInstance child else pure False)

-- 关闭预约与自动收尾 -----------------------------------------------------------

-- permit 仅由已预约的 cleanup 传回；显式 close 只可排除自身 consumer.
reserveScopeClose :: Maybe Unique -> Maybe Unique -> Unique -> ScopeInstance environment cause -> IO Bool
reserveScopeClose consumer permit ticket slot = coordinated (scopeFamily slot) $ do
  retiring <- readIORef (scopeRetiring slot)
  case retiring of
    Just (owner, _) -> pure (permit == Just owner)
    Nothing -> do
      phase <- scopePhase <$> readIORef (scopeRecord slot)
      users <- readIORef (scopeUsers slot)
      children <- hasLiveChildren slot
      pending <- pendingUse slot
      cleanup <- readIORef (scopeCleanup slot)
      let closed = case phase of ScopeClosed _ -> True; _ -> False
          consumed = consumer == Nothing && permit == Nothing && not (isJust cleanup)
      if consumed || (not closed && (any (\(user, _) -> Just user /= consumer) users || children || pending))
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
      void (pruneInstance slot)
    _ -> pure ()

-- 没有 close 的实例同样按可达性移出；旧绑定仍直接持有原实例。
-- 已尝试的 close 不再登记，失败也不会在下一次 sweep 或运行结束时重试。
-- 调用方持有协调锁。
pruneInstance :: ScopeInstance environment cause -> IO Bool
pruneInstance slot = do
  phase <- scopePhase <$> readIORef (scopeRecord slot)
  users <- readIORef (scopeUsers slot)
  cleanup <- readIORef (scopeCleanup slot)
  retiring <- readIORef (scopeRetiring slot)
  pending <- pendingUse slot
  children <- hasLiveChildren slot
  let closed = case phase of ScopeClosed _ -> True; _ -> False
      unreachable = null users && not pending && not children && not (isJust cleanup)
  if not (isJust retiring) && (closed || unreachable)
    then modifyMVar (scopeInstances (scopeFamily slot)) $ \slots -> do
      let retained = filter ((/= scopeRecord slot) . scopeRecord) slots
      pure (retained, length retained /= length slots)
    else pure False

-- 清理动作也可临时借用别的资源；退出只撤销这些借用，由外层 sweep 收尾。
detachScopeUser :: ScopeUser environment cause -> IO ()
detachScopeUser user = coordinatedUser user $ do
  pending <- readIORef (scopeUserBindings user)
  forM_ pending $ \ownership -> do
    state <- readIORef ownership
    let owner = bindingOwner state
        remaining = filter ((/= scopeUserIdentity user) . scopeUserIdentity) (bindingUsers state)
    owner `seq` length remaining `seq` writeIORef ownership (BindingOwnership owner remaining)
  writeIORef (scopeUserBindings user) []
  -- 与认领共用一次协调事务：先撤销未认领使用，再读取已经接入的全部实例。
  -- 认领不可能在读出 instances 后另行追加而逃过本次撤销。
  slots <- readIORef (scopeUserInstances user)
  forM_ slots $ \slot -> do
    atomicModifyIORef' (scopeUsers slot) (\users -> (filter ((/= scopeUserIdentity user) . fst) users, ()))
    void (pruneInstance slot)
  writeIORef (scopeUserInstances user) []

saveCleanupFailures :: Scopes environment cause -> [(Maybe SomeException, Failure cause)] -> IO ()
saveCleanupFailures [] _ = pure ()
saveCleanupFailures (handler : _) failures =
  atomicModifyIORef' (scopePendingFailures handler) (\saved -> (saved ++ failures, ()))

-- interpreter 已等待全部受管理任务退出。按依赖的逆序收尾，一份失败不跳过其余实例。
-- 返回此前记录与本次的关闭故障供汇总报告；其中只有取消由边界重新抛出。
cleanupScopes :: Scopes environment cause -> IO [(Maybe SomeException, Failure cause)]
cleanupScopes handlers = do
  pending <- fmap concat $ forM handlers $ \handler ->
    atomicModifyIORef' (scopePendingFailures handler) (\saved -> ([], saved))
  failures <- cleanupAvailable handlers
  pure (pending ++ failures)

-- 叶实例释放后重扫之前被挡住的祖先。一次关闭无论成败都消费登记；
-- 原生异常连同诊断结果一并返回，其余实例照常收尾；是否传播（只传播取消）由调用方决定。
cleanupAvailable :: Scopes environment cause -> IO [(Maybe SomeException, Failure cause)]
cleanupAvailable handlers = mask $ \restore -> sweep restore [] []
  where
    sweep restore attempted failures = do
      slots <- uninterruptibleMask_ $ concat <$> mapM (readMVar . scopeInstances) (reverse handlers)
      results <- forM [slot | slot <- slots, scopeRecord slot `notElem` attempted] $ \slot -> do
        phase <- scopePhase <$> readIORef (scopeRecord slot)
        cleanup <- readIORef (scopeCleanup slot)
        case (phase, cleanup) of
          (ScopeClosed _, _) -> prune slot
          (_, Nothing) -> prune slot
          (_, Just (ScopeCleanup interrupted action)) -> do
            ticket <- newUnique
            ready <- reserveScopeClose Nothing Nothing ticket slot
            if not ready then pure Nothing else do
              reported <- (do
                outcome <- try (restore (action ticket))
                case outcome of
                  Left exception -> do
                    failure <- interrupted ticket exception
                    pure [(Just exception, failure)]
                  Right (Left failure) -> pure [(Nothing, failure)]
                  Right (Right ()) -> pure []) `finally` do
                    writeIORef (scopeCleanup slot) Nothing
                    finishScopeClose ticket slot
              pure (Just (scopeRecord slot, reported))
      let completed = [result | Just result <- results]
      if null completed then pure failures
        else sweep restore (map fst completed ++ attempted) (failures ++ concatMap snd completed)
    prune slot = do
      removed <- coordinated (scopeFamily slot) (pruneInstance slot)
      pure (if removed then Just (scopeRecord slot, []) else Nothing)

findScope :: Scopes environment cause -> String -> Maybe (ScopeHandler environment cause)
findScope scopes selected = find ((== selected) . scopeName) scopes

getScope :: Scopes environment cause -> String -> IO (ScopeHandler environment cause)
getScope scopes selected = case findScope scopes selected of
  Just handler -> pure handler
  Nothing -> ioError (userError ("Missing generated scope handler: " ++ selected ++ "; regenerate handlers"))

