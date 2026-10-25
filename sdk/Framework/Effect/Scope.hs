-- SDK 的 scope 状态与并发开启保护；不另设业务产值契约。
module Framework.Effect.Scope
  ( ScopePhase(..), ScopeRecord(..), ScopeOperation(..)
  , emptyScope, scopeFailure, beginScope, finishScope, interruptedScope
  , Scopes, ScopeBindings, ScopeHandler(..), ScopeInstance(..), ScopeInput(..)
  , newScopeHandler, findScope, getScope, selectScopeInstance
  ) where

import Framework.Effect.Binding (Bindings)
import Framework.Effect.Contract (Failure(..), ScopeFault(..), ScopeInput(..))
import Control.Concurrent.MVar (MVar, newMVar, modifyMVar)
import Control.Exception (SomeException, displayException)
import Data.IORef (IORef, newIORef, readIORef)
import Data.List (find, sortOn)
import Data.Unique (hashUnique, newUnique)

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
scopeFault selected wrap fault = Failure selected (wrap fault) (show fault) [] [] Nothing

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
  }

type ScopeBindings environment cause = Bindings environment (String, ScopeInstance environment cause)

data ScopeInstance environment cause = ScopeInstance
  { scopeInputs :: [ScopeInput]
  , scopeGate :: MVar ()
  , scopeRecoveryGate :: MVar ()
  , scopeIdentity :: Int
  , scopeRecord :: IORef (ScopeRecord (ScopeBindings environment cause) cause)
  }

newScopeHandler :: String -> [String] -> Maybe String -> IO (ScopeHandler environment cause)
newScopeHandler selected inputs source = ScopeHandler selected inputs source <$> newMVar []

-- 已关闭的同参实例建立新一轮；旧引用仍指向旧的 Closed 实例。
selectScopeInstance :: ScopeHandler environment cause -> [ScopeInput]
                    -> IO (ScopeInstance environment cause)
selectScopeInstance handler inputs = modifyMVar (scopeInstances handler) $ \instances -> do
  let source (ScopeInput name _) = name
      matches slot = sortOn source inputs == sortOn source (scopeInputs slot)
      create = ScopeInstance inputs <$> newMVar () <*> newMVar () <*> (hashUnique <$> newUnique) <*> newIORef (emptyScope [])
      replace = do
        slot <- create
        pure (slot : filter (not . matches) instances, slot)
  case find matches instances of
    Nothing -> replace
    Just slot -> do
      phase <- scopePhase <$> readIORef (scopeRecord slot)
      case phase of
        ScopeClosed _ -> replace
        _ -> pure (instances, slot)

findScope :: Scopes environment cause -> String -> Maybe (ScopeHandler environment cause)
findScope scopes selected = find ((== selected) . scopeName) scopes

getScope :: Scopes environment cause -> String -> IO (ScopeHandler environment cause)
getScope scopes selected = case findScope scopes selected of
  Just handler -> pure handler
  Nothing -> ioError (userError ("Missing generated scope handler: " ++ selected ++ "; regenerate handlers"))

