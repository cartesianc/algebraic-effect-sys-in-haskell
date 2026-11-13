{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FunctionalDependencies #-}
{-# LANGUAGE MultiParamTypeClasses #-}

-- 执行载体必须实现的协议：ContextStore／ScopeStore／ErrorStore，以及协议故障与原始输出。
-- 生成代码经 Framework.Generated 调用这些协议；handler 的能力类与完成结果属于源语言（Framework.Language.Handler）。
-- 通用 Context 组合在 Runtime/Context.hs，IO 解释在 Runtime/App.hs。
module Framework.Runtime.Protocol
  ( failEffect, ErrorHandler(..), ErrorStore(..), runErrorHandler
  , ContextStore(..), ContextFault(..), ScopeStore(..), ScopeFault(..), ScopeInput(..), ScopeInputAccess(..)
  , RawOutput(..)
  ) where

import Control.Monad.Except (MonadError, catchError, throwError)
import Framework.Language.Handler (Failure(..), Output(..), ErrorReport(..))
import Framework.Language.History (History)
import Framework.Runtime.Identity (ActivationId)

-- Context 访问与发布协议 -------------------------------------------------------

-- SDK 内部存储协议：App 载体经 Reader 访问共享存储。
-- 用户的 Context 仍只实现生产方法；读取与发布回调由生成器连接。
class Monad m => ContextStore environment m | m -> environment where
  readContextBinding :: String -> (environment -> Maybe value)
                     -> m (Either ContextFault (Maybe value))
  publishContextBinding :: String -> (environment -> environment) -> m ()
  -- 资源生产与绑定发布作为一次交接；纯载体无需额外保护。
  protectContextBinding :: String -> m value -> m value
  protectContextBinding _ = id
  -- 一次 Context request 的激活覆盖生产、成功发布和返回；不改变调用者或资源使用者。
  enterRequest :: String -> m value -> m value
  enterRequest _ = id
  currentHandler :: m (Maybe String)
  enterHandler :: String -> m value -> m value
  enterContext :: String -> m value -> m value
  enterContext = enterHandler
  recordContextInput :: ScopeInputAccess -> String -> m ()
  recordContextInput _ _ = pure ()
  -- require 不生产：读取之前先取等待动作，读不到值时执行它。
  -- True 表示发布或执行进度已变化，需要重读；False 表示已证明生产机会耗尽，
  -- 调用方最后重读一次绑定，仍缺值才报错，避免漏掉退出前的成功发布。
  -- 返回 Nothing 表示当前不等待（诊断、收尾，或该来源是 scope 资源），缺值按 ContextNotInitialized 报出。
  awaitContext :: String -> m (Maybe (m Bool))
  awaitContext _ = pure Nothing
  -- 生成区按原子句柄方法名安装挂在它下面的 Context 生产入口。
  withAnchoredContexts :: [(String, [(String, m ())])] -> m value -> m value
  withAnchoredContexts _ = id
  anchoredContexts :: String -> m [(String, m ())]
  anchoredContexts _ = pure []
  -- 注入期间，挂接 Context 对该句柄的调用由本次 RawOutput 回答，不重复执行。
  replayedOutput :: String -> m (Maybe RawOutput)
  replayedOutput _ = pure Nothing
  -- 以根调用身份运行一次注入；失败留在注入内，不进入原链，也不触发 Error 诊断。
  injectOutput :: String -> RawOutput -> m () -> m ()
  injectOutput _ _ _ = pure ()
  -- 持续资产：本次调用已经取得的历史视图（lifelong 交付，或本次先前的会话读取），按发布顺序。
  readContextHistory :: String -> (environment -> Maybe value) -> m (Maybe (History value))
  readContextHistory _ _ = pure Nothing
  -- Receive 资产没有本次视图时，从 interpreter 托管的会话取得当前历史（至少一条），并捕获为本次视图。
  -- Nothing 表示当前不允许启动会话（诊断、收尾）；会话失败时传播它的原失败。
  awaitContextHistory :: String -> (environment -> Maybe value) -> m (Maybe (History value))
  awaitContextHistory _ _ = pure Nothing
  -- 解析器本次的原始输入；只有会话调用解析器时才安装。
  streamRawInput :: m (Maybe String)
  streamRawInput = pure Nothing

-- 原子句柄（Excu.handler、Scoped.open／close）的统一输出：是否成功，附带方法体交出的 list。
-- 只在 SDK 内部交给挂在该句柄下（可经一串 Pure）的 Context；没有挂接时被丢弃，注册与 handler 签名都看不到它。
data RawOutput = RawOutput
  { succeeded :: Bool
  , info :: [String]
  } deriving (Eq, Show)

-- CaseNotSelected：读取和类型资产的某个分支契约，而资产当前是另一个构造器。
data ContextFault = ContextNotInitialized
  | AmbiguousContextBinding String | CaseNotSelected String
  deriving (Eq, Show)

-- Scope 参数与生命周期能力 ----------------------------------------------------

-- 开启参数以 Context 来源及实际绑定的生产身份匹配，不比较业务值。
-- 身份由载体从已捕获的 Binding 取得，生成区无需为业务 ADT 引入 Eq。
data ScopeInput = ScopeInput String ActivationId deriving (Eq, Ord, Show)

data ScopeInputAccess = RequestedInput | RequiredInput deriving (Eq, Show)

-- SDK 内部生命周期能力；业务 instance 仍只实现 open／close。
data ScopeFault = ScopeNotOpen | ScopeIsClosed | ScopeReentry | ScopeInterrupted String
  | ScopeContextMissing String | ScopeContextMismatch String | ScopeInputsMissing [String] | ScopeInputAfterOpen String
  | ScopeCleanupInterrupted String | ScopeCleanupInProgress | ScopeInUse
  deriving (Eq, Show)

class Monad m => ScopeStore cause m | m -> cause where
  withScopeDependencies :: [String] -> m value -> m value
  -- Nothing 表示方法体没有执行：复用了同参的已开启实例，或重复 close 被跳过。
  openScope :: String -> (ScopeFault -> cause) -> m value -> m (Maybe value)
  closeScope :: String -> (ScopeFault -> cause) -> m value -> m (Maybe value)
  invalidateScope :: String -> Failure cause -> m ()

-- Error 回调与统一完成结果 -----------------------------------------------------

-- 回调由生成区装配；不让 Root 的 superclass 反向依赖业务 Error 类.
-- 匹配函数由注册的 handles 生成，只读取 Failure 的来源与分类，不解释业务消息。
data ErrorHandler cause m = ErrorHandler String (Failure cause -> Bool) (Maybe (m ())) (Maybe (m ()))

-- 回调表的键是推导出的关联 scope；Nothing 表示不定位 scope 实例的全局处置。
class Monad m => ErrorStore cause m | m -> cause where
  withErrorHandlers :: [(Maybe String, ErrorHandler cause m)] -> m value -> m value
  withErrorPath :: [String] -> m value -> m value
  handleFailure :: m value -> m value
  caughtFailure :: m (Maybe (Failure cause))

-- 类型匹配已完成粗定位；detect 只作可选的值级细化：未注册 detect 时直接 resolve，
-- detect 返回 Succ 才 resolve，Failed 表示不归此处。
-- 每次检测/处置的失败只进入报告，不能覆盖原始故障或递归激活自身。
runErrorHandler :: MonadError (Failure cause) m
                => Maybe String -> ErrorHandler cause m -> m (ErrorReport cause)
runErrorHandler selected (ErrorHandler name _ detecting resolving) = do
  detection <- traverse attempt detecting
  resolution <- case detection of
    Nothing -> traverse attempt resolving
    Just (Succ ()) -> traverse attempt resolving
    _ -> pure Nothing
  pure (ErrorReport selected name detection resolution)
  where
    attempt action = (Succ <$> action) `catchError` (pure . Failed)

-- 生成的 Raises instance 统一实现 raise：origin 是发生位置的 effect 名，cause 是 handler 的错误分类。
failEffect :: MonadError (Failure cause) m => String -> cause -> String -> m value
failEffect effectName cause description = throwError (Failure effectName cause description [] [] Nothing [])
