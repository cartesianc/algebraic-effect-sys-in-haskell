{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FunctionalDependencies #-}
{-# LANGUAGE MultiParamTypeClasses #-}

-- 执行载体必须实现的协议：ContextStore／ScopeStore／ErrorStore，以及协议故障与原始输出。
-- 生成代码经 Framework.Generated 调用这些协议；handler 的能力类与完成结果属于源语言（Framework.Language.Handler）。
-- 通用 Context 组合在 Runtime/Context.hs，IO 解释在 Runtime/App.hs。
module Framework.Runtime.Protocol
  ( Root(..), HandlerError(..), failEffect, ErrorHandler(..), ErrorStore(..), runErrorHandler
  , ContextStore(..), ContextFault(..), ScopeStore(..), ScopeFault(..), ScopeInput(..)
  , RawOutput(..)
  ) where

import Control.Monad.Except (MonadError, catchError, throwError)
import Framework.Language.Handler (Failure(..), Output(..), ErrorReport(..))
import Framework.Runtime.Identity (ActivationId)

-- 生成入口在绑定的标签上调用 super；Middleware 与原子业务方法都不持有推进权。
-- result 保留 parser、Stream、Error 等各自的返回类型。空策略直接执行原 action。
class Monad m => Root m result where
  super :: String -> m result -> m result
  super _ = id
  -- Scoped.close 的调用点由 gen 确定并改用它：GC 已预约的 close 在进入通知失败时仍须执行。
  superClose :: String -> m result -> m result
  superClose = super

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
  -- 读取或驱动取得某个 Context 后报告来源名；正在 open 时，载体据此记录开启参数的生产身份。
  recordContextInput :: String -> m ()
  recordContextInput _ = pure ()
  -- require 不生产：读取之前先取等待动作，读不到值时执行它。
  -- True 表示发布或执行进度已变化，需要重读；False 表示已证明生产机会耗尽，
  -- 调用方最后重读一次绑定，仍缺值才报错，避免漏掉退出前的成功发布。
  -- 返回 Nothing 表示当前不等待（诊断、收尾，或该来源是 scope 资源），缺值按 ContextNotInitialized 报出。
  awaitContext :: String -> m (Maybe (m Bool))
  awaitContext _ = pure Nothing
  -- 持续 Context 沿用原始链这次输出。gen 把挂在句柄下的持续 parser 写在入口上，
  -- 只有本次执行位置是原型指定的发布位置时才取得它们；普通注入和持续注入分别保持各自的失败协议。
  activeStreamContexts :: [(String, m ())] -> m [(String, m ())]
  activeStreamContexts _ = pure []
  -- 注入期间，挂接 Context 对该句柄的调用由本次 RawOutput 回答，不重复执行。
  replayedOutput :: String -> m (Maybe RawOutput)
  replayedOutput _ = pure Nothing
  -- 以根调用身份运行一次注入；失败留在注入内，不进入原链，也不触发 Error 诊断。
  injectOutput :: String -> RawOutput -> m () -> m ()
  injectOutput _ _ _ = pure ()
  -- 同次输出交接给持续 parser，失败按持续执行协议传播，不吞掉。
  injectStreamOutput :: String -> RawOutput -> m () -> m ()
  injectStreamOutput _ _ = id
  -- 持续资产仍返回声明的表示类型：从本次固定交付或已经捕获的绑定投影。
  readContextValue :: String -> (environment -> Maybe value) -> m (Maybe value)
  readContextValue _ _ = pure Nothing
  -- 没有固定交付时，按已生成的会话计划取得一次当前值；这次读取不会重复启动调用者。
  -- Nothing 表示当前不允许启动会话（诊断、收尾）；会话失败时传播它的原失败。
  awaitContextValue :: String -> (environment -> Maybe value) -> m (Maybe value)
  awaitContextValue _ _ = pure Nothing
  -- stream @T：与上面两者取同一个固定视图，返回本次值及同会话更早的发布，最新在前。
  readContextHistory :: String -> (environment -> Maybe value) -> m (Maybe [value])
  readContextHistory _ _ = pure Nothing
  awaitContextHistory :: String -> (environment -> Maybe value) -> m (Maybe [value])
  awaitContextHistory _ _ = pure Nothing
  -- Stream handler 的 streamEnd：退出本次生产步骤，由生产任务接住并正常结束会话。
  -- 不是 Failure，不经过 Error 诊断，也不被方法体内的 catchError 接住。
  endSource :: m value
  -- 消费方的 endStream：放弃本次调用，由调用所在的单元调度（lifelong 节点）或 Derive 生产任务接住，
  -- 结束这一处订阅。同样不是 Failure。
  endSubscription :: m value

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

-- SDK 内部生命周期能力；业务 instance 仍只实现 open／close。
data ScopeFault = ScopeNotOpen | ScopeIsClosed | ScopeReentry | ScopeInterrupted String
  | ScopeContextMissing String | ScopeContextMismatch String | ScopeInputsMissing [String] | ScopeInputAfterOpen String
  | ScopeCleanupInterrupted String | ScopeCleanupInProgress | ScopeInUse
  deriving (Eq, Show)

class Monad m => ScopeStore cause m | m -> cause where
  withScopeDependencies :: [String] -> m value -> m value
  -- Nothing 表示方法体没有执行：复用了同参的已开启实例，或重复 close 被跳过。
  -- open 带上本 scope 的 close 入口（gen 按开启它的同一 Middleware 列表写出），开启成功时登记为自动收尾。
  openScope :: String -> (ScopeFault -> cause) -> Maybe (m ()) -> m value -> m (Maybe value)
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

-- 生成的错误类型到失败分类的对应，写在 Generated/Effects.hs 的错误声明旁；
-- 生成的 Raises instance 按它取分类与描述，所有标签共用一份实现。
class HandlerError problem cause where
  raised :: problem -> (cause, String)

-- 生成的 Raises instance 统一实现 raise：origin 是发生位置的 effect 名，cause 是 handler 的错误分类。
failEffect :: MonadError (Failure cause) m => String -> cause -> String -> m value
failEffect effectName cause description = throwError (Failure effectName cause description [] [] Nothing [])
