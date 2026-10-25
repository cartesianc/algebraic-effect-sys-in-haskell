{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE MultiParamTypeClasses #-}

-- 句柄描述与 lower；普通 Context 按调用保存，scope 控制对象由生成句柄共享。
module Framework.Effect.Runtime
  ( Pure, App, Target, Identity, targetPure, targetApp, bootPure
  , targetName, lowerTarget
  ) where

import Framework.Effect.Contract (ContextStore(..), ContextFault(..), ScopeStore(..), ScopeFault, Failure, Output(..))
import Framework.Effect.Runtime.App (App, runApp)
import Framework.Effect.Scope
import Control.Monad (forM_, when)
import Control.Monad.Except (ExceptT, MonadError, catchError, runExceptT, throwError)
import Control.Monad.Reader (ReaderT, ask, asks, local, runReaderT)
import Control.Monad.State.Strict (MonadState, State, evalState, gets, modify')
import Data.Functor.Identity (Identity(..))
import Data.List (nub)
import Data.Maybe (catMaybes)

data Calling = Calling
  { caller :: Maybe String
  , dependencies :: [String]
  , ownedScopes :: [String]
  }

emptyCalling :: Calling
emptyCalling = Calling Nothing [] []

visibleScopes :: Calling -> [String]
visibleScopes calling = nub (ownedScopes calling ++ dependencies calling)

addDependencies :: [String] -> Calling -> Calling
addDependencies selected calling = calling { dependencies = nub (selected ++ dependencies calling) }

ownScope :: String -> Calling -> Calling
ownScope selected calling = calling { ownedScopes = selected : ownedScopes calling }

data PureState environment cause = PureState
  { pureBindings :: environment
  , pureEmpty :: environment
  , pureScopes :: [(String, ScopeRecord environment cause)]
  }

newtype Pure environment cause value =
  PureRun (ReaderT Calling (ExceptT (Failure cause) (State (PureState environment cause))) value)
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
          when (selected `notElem` ownedScopes calling) $
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
      Just record | name `notElem` ownedScopes calling ->
        maybe (pure ()) throwError (scopeFailure (scopePhase record))
      _ -> pure ()
    action
  openScope = runPureScope OpenScope
  closeScope = runPureScope CloseScope
  invalidateScope selected failure = updatePureScope selected $ \record -> record
    { scopePhase = case scopePhase record of
        ScopeInvalid original -> ScopeInvalid original
        _ -> ScopeInvalid failure }

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
  AppTarget :: String -> environment -> Scopes environment cause -> App environment cause value
            -> Target IO environment cause value

targetName :: Target runtime environment cause value -> String
targetName (PureTarget selected _ _) = selected
targetName (AppTarget selected _ _ _) = selected

-- 生成区只登记句柄，不组合上游操作。
targetPure :: String -> environment -> Pure environment cause value -> Target Identity environment cause value
targetPure = PureTarget

targetApp :: String -> environment -> Scopes environment cause -> App environment cause value
          -> Target IO environment cause value
targetApp = AppTarget

-- Node algebra 只 lower 末端；scope 引用已绑定在句柄中，解释器不创建或重置状态。
lowerTarget :: Target runtime environment cause value -> runtime (Either (Failure cause) value)
lowerTarget (PureTarget _ environment action) = Identity (runPure environment action)
lowerTarget (AppTarget _ environment scopes action) = runApp scopes environment action

-- 无 AST 的纯计算 benchmark 入口，同样只 lower 所选末端。
bootPure :: Target Identity environment cause value -> Output cause value
bootPure = either Failed Succ . runIdentity . lowerTarget
