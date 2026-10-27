{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE MultiParamTypeClasses #-}

-- 句柄描述与 lower；普通 Context 按调用保存，scope 控制对象由生成句柄共享。
module Framework.Effect.Runtime
  ( Pure, App, Target, Identity, targetPure, targetApp, bootPure
  , targetName, lowerTarget, configureTargets, cleanupTargets
  ) where

import Framework.Effect.Contract (ContextStore(..), ContextFault(..), ScopeStore(..), ScopeFault, Failure(..), Output(..), ErrorStore(..), ErrorHandler(..), runErrorHandler)
import Framework.Effect.Runtime.App (App, runAppWith)
import Framework.Effect.Scope
import Control.Exception (SomeException, evaluate)
import Control.Monad (forM_, when)
import Control.Monad.Except (ExceptT, MonadError, catchError, runExceptT, throwError)
import Control.Monad.Reader (ReaderT, ask, asks, local, runReaderT)
import Control.Monad.State.Strict (MonadState, State, evalState, gets, modify')
import Data.Functor.Identity (Identity(..))
import Data.List (nub, nubBy)
import Data.Maybe (catMaybes, isJust)

data Calling environment cause = Calling
  { caller :: Maybe String
  , dependencies :: [String]
  , ownedScopes :: [String]
  , errorHandlers :: [(Maybe String, ErrorHandler cause (Pure environment cause))]
  , errorPath :: [String]
  , originalFailure :: Maybe (Failure cause)
  , diagnosticScope :: Maybe String
  }

emptyCalling :: Calling environment cause
emptyCalling = Calling Nothing [] [] [] [] Nothing Nothing

visibleScopes :: Calling environment cause -> [String]
visibleScopes calling = nub (ownedScopes calling ++ dependencies calling)

addDependencies :: [String] -> Calling environment cause -> Calling environment cause
addDependencies selected calling = calling { dependencies = nub (selected ++ dependencies calling) }

ownScope :: String -> Calling environment cause -> Calling environment cause
ownScope selected calling = calling { ownedScopes = selected : ownedScopes calling }

data PureState environment cause = PureState
  { pureBindings :: environment
  , pureEmpty :: environment
  , pureScopes :: [(String, ScopeRecord environment cause)]
  }

newtype Pure environment cause value =
  PureRun (ReaderT (Calling environment cause) (ExceptT (Failure cause) (State (PureState environment cause))) value)
  deriving (Functor, Applicative, Monad, MonadState (PureState environment cause), MonadError (Failure cause))

instance ContextStore environment (Pure environment cause) where
  readContextBinding source select = do
    localValue <- gets (select . pureBindings)
    case localValue of
      Just value -> pure (Right (Just value))
      Nothing -> do
        calling <- PureRun ask
        records <- gets pureScopes
        values <- mapM (readOne calling records) (visibleScopes calling)
        pure $ case catMaybes values of
          [] -> Right Nothing
          [value] -> Right (Just value)
          _ -> Left (AmbiguousContextBinding source)
    where
      readOne calling records selected = case lookup selected records of
        Nothing -> pure Nothing
        Just record -> do
          when (selected `notElem` ownedScopes calling && Just selected /= diagnosticScope calling) $
            maybe (pure ()) throwError (scopeFailure (scopePhase record))
          pure (if source `elem` scopeSources record then select (scopeBindings record) else Nothing)
  publishContextBinding source update = do
    calling <- PureRun ask
    modify' $ \state -> state
      { pureBindings = update (pureBindings state)
      , pureScopes =
          [ (selected, if selected `elem` take 1 (ownedScopes calling) then record
              { scopeBindings = update (scopeBindings record)
              , scopeSources = nub (source : scopeSources record) } else record)
          | (selected, record) <- pureScopes state ] }
  currentHandler = PureRun (asks caller)
  enterHandler selected (PureRun action) = PureRun (local (\calling -> calling { caller = Just selected }) action)

instance ScopeStore cause (Pure environment cause) where
  withScopeDependencies selected (PureRun action) = PureRun $ local (addDependencies selected) $ do
    calling <- ask
    records <- gets pureScopes
    forM_ (dependencies calling) $ \name -> case lookup name records of
      Just record | name `notElem` ownedScopes calling && Just name /= diagnosticScope calling ->
        maybe (pure ()) throwError (scopeFailure (scopePhase record))
      _ -> pure ()
    action
  openScope = runPureScope OpenScope
  closeScope = runPureScope CloseScope
  invalidateScope selected failure = updatePureScope selected $ \record -> record
    { scopePhase = case scopePhase record of
        ScopeInvalid original -> ScopeInvalid original
        _ -> ScopeInvalid failure }

instance ErrorStore cause (Pure environment cause) where
  withErrorHandlers handlers (PureRun action) = PureRun $ local
    (\calling -> calling { errorHandlers = handlers }) action
  withErrorPath path (PureRun action) = PureRun $ local
    (\calling -> calling { errorPath = nub (path ++ errorPath calling) }) action
  caughtFailure = PureRun (asks originalFailure)
  handleFailure (PureRun action) = PureRun $ do
    calling <- ask
    if null (errorHandlers calling) || isJust (originalFailure calling)
      then action
      else action `catchError` \problem -> do
        let traced = problem { scopeTrace = nub (scopeTrace problem ++ errorPath calling) }
        if isJust (errorHandling problem)
          then throwError problem
          else if not (null (ownedScopes calling))
            then throwError traced
            else do
              -- 按 handles 匹配故障类型；有关联 scope 时还须位于候选路径上，不猜测其他实例。
              reports <- mapM (diagnose calling traced)
                [(selected, callback) | (selected, callback@(ErrorHandler _ matches _ _)) <- errorHandlers calling
                                     , matches traced
                                     , maybe True (`elem` scopeTrace traced) selected]
              throwError traced { errorHandling = Just reports }
    where
      diagnose calling problem (selected, callback) = do
        saved <- gets pureBindings
        let PureRun action = runErrorHandler selected callback
        report <- local (const calling
          { caller = Nothing, ownedScopes = [], originalFailure = Just problem
          , diagnosticScope = selected }) action
        modify' (\state -> state { pureBindings = saved })
        pure report

updatePureScope :: String -> (ScopeRecord environment cause -> ScopeRecord environment cause)
                -> Pure environment cause ()
updatePureScope selected update = modify' $ \state ->
  let record = maybe (emptyScope (pureEmpty state)) id (lookup selected (pureScopes state))
  in state { pureScopes = (selected, update record) : filter ((/= selected) . fst) (pureScopes state) }

runPureScope :: ScopeOperation -> String -> (ScopeFault -> cause)
             -> Pure environment cause () -> Pure environment cause ()
runPureScope operation selected wrap (PureRun action) = do
  records <- gets pureScopes
  let initial = maybe ScopeIdle scopePhase (lookup selected records)
  execute <- either throwError pure (beginScope operation selected wrap initial)
  when execute $ do
    let running = case operation of OpenScope -> ScopeOpening; CloseScope -> ScopeClosing
    updatePureScope selected (\record -> record { scopePhase = running })
    result <- (Right <$> PureRun (local (ownScope selected) action)) `catchError` (pure . Left)
    updatePureScope selected $ \record -> record
      { scopePhase = finishScope operation selected wrap
          (case initial of ScopeInvalid _ -> initial; _ -> scopePhase record) result }
    completed <- gets (maybe ScopeIdle scopePhase . lookup selected . pureScopes)
    case (operation, scopeFailure completed) of
      (OpenScope, Just failure) -> throwError failure
      _ -> either throwError pure result

-- 裸载体的运行器只供 lower 使用。
runPure :: environment -> Pure environment cause value -> Either (Failure cause) value
runPure environment (PureRun action) =
  evalState (runExceptT (runReaderT action emptyCalling)) (PureState environment environment [])

-- 一个生成程序的 Node 共用同一存储契约；普通 Context 在每次 lower 时仍独立。
data Target runtime environment cause value where
  PureTarget :: String -> environment -> Pure environment cause value -> Target Identity environment cause value
  AppTarget :: (Show cause, Show value) => String -> environment -> Scopes environment cause -> App environment cause value
            -> Target IO environment cause value

targetName :: Target runtime environment cause value -> String
targetName (PureTarget selected _ _) = selected
targetName (AppTarget selected _ _ _) = selected

-- 生成区只登记句柄，不组合上游操作。
targetPure :: String -> environment -> Pure environment cause value -> Target Identity environment cause value
targetPure = PureTarget

targetApp :: (Show cause, Show value) => String -> environment -> Scopes environment cause -> App environment cause value
          -> Target IO environment cause value
targetApp = AppTarget

-- Node algebra 只 lower 末端；scope 引用已绑定在句柄中。
-- 受控结果消费在使用闭包退出前完成，惰性读取不会落在自动 close 之后。
lowerTarget :: Target runtime environment cause value -> runtime (Either (Failure cause) value)
lowerTarget (PureTarget _ environment action) = Identity (runPure environment action)
lowerTarget (AppTarget _ environment scopes action) =
  runAppWith (\value -> evaluate (foldr seq () (show value))) scopes environment action

-- 各末端通常捕获同批 scope；按控制对象身份去重，不按业务名称合并独立批次。
scopeHandlers :: [Target IO environment cause value] -> Scopes environment cause
scopeHandlers entries = nubBy sameHandler (concatMap targetScopes entries)
  where
    targetScopes :: Target IO environment cause value -> Scopes environment cause
    targetScopes (AppTarget _ _ scopes _) = scopes
    sameHandler left right = scopeInstances left == scopeInstances right

-- 在第一次业务调用前安装同一 ScopeTree 的祖先投影，供回收协调和 Error 导航读取。
configureTargets :: [(String, [String])] -> [Target IO environment cause value] -> IO ()
configureTargets relations = configureScopeRelations relations . scopeHandlers

cleanupTargets :: [Target IO environment cause value] -> IO [(Maybe SomeException, Failure cause)]
cleanupTargets = cleanupScopes . scopeHandlers

-- 无 AST 的纯计算 benchmark 入口，同样只 lower 所选末端。
bootPure :: Target Identity environment cause value -> Output cause value
bootPure = either Failed Succ . runIdentity . lowerTarget
