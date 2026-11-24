{-# OPTIONS_GHC -fexpose-all-unfoldings -fspecialise-aggressively #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FunctionalDependencies #-}
{-# LANGUAGE MultiParamTypeClasses #-}

-- 执行载体必须实现的协议：ContextStore／ScopeStore／ErrorStore，以及协议故障与原始输出。
-- 生成代码经 Framework.Generated 调用这些协议；handler 的能力类与完成结果属于源语言（Framework.Language.Handler）。
-- 通用 Context 组合在 Runtime/Context.hs，IO 解释在 Runtime/App.hs。
module Framework.Runtime.Protocol
  ( Root(..), HandlerError(..), failEffect, ErrorHandler(..), ErrorStore(..), runErrorHandler
  , ContextStore(..), ContextFault(..), ScopeStore(..), ScopeFault(..), ScopeInput(..)
  ) where

import Control.Monad.Except (MonadError, catchError, throwError)
import Framework.Language.Handler (Failure(..), Output(..), ErrorReport(..))
import Framework.Runtime.Identity (ActivationId)
import Framework.Prototype.Slot (Slot)

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
  readContextBinding :: Slot -> (environment -> Maybe value)
                     -> m (Either ContextFault (Maybe value))
  publishContextBinding :: Slot -> (environment -> environment) -> m ()
  -- 资源生产与绑定发布作为一次交接；纯载体无需额外保护。
  protectContextBinding :: Slot -> m value -> m value
  protectContextBinding _ = id
  -- 一次 Context request 的激活覆盖生产、成功发布和返回；不改变调用者或资源使用者。
  enterRequest :: Slot -> m value -> m value
  enterRequest _ = id
  currentHandler :: m (Maybe Slot)
  enterHandler :: Slot -> m value -> m value
  enterContext :: Slot -> m value -> m value
  enterContext = enterHandler
  -- 读取或驱动取得某个 Context 后报告来源名；正在 open 时，载体据此记录开启参数的生产身份。
  recordContextInput :: Slot -> m ()
  recordContextInput _ = pure ()
  -- 同一次调用中每个 effect 只执行一次：Excu、Scoped.open 与 Pure 的本次输出，Context 是否已在本次发布。
  -- 记录随调用开始而清空（订阅回调预先记入交付的资产）；诊断与收尾各有自己的记录。
  recallOutput :: Slot -> m (Maybe [String])
  recallOutput _ = pure Nothing
  rememberOutput :: Slot -> [String] -> m ()
  rememberOutput _ _ = pure ()
  -- 锚点为这些 Context 生产：在 Scoped 的 open 中，它的 IO 属于开启输入的生产，与在 Context 里拉取时相同。
  producingFor :: [Slot] -> m value -> m value
  producingFor _ = id
  -- 输出联立的分支是否执行：诊断与收尾期间不执行。
  linkingAllowed :: m Bool
  linkingAllowed = pure True
  -- alternative 判定：以根调用身份执行一个候选的 Context；失败照常返回给调用方，
  -- 由选择逻辑记为放弃，不触发 Error 处置，也不进入原链。
  attemptOutput :: m () -> m ()
  attemptOutput = id
  -- require 缺值时的等待。contextTicket 在查值之前取得；awaitContext 在缺值后调用：True 表示已有变化或等到了变化，
  -- 重查一次；False 表示没有别的 parallel 分支还可能发布，或所有执行中的线程都在等待，读取方按缺值处理。
  -- 诊断、收尾、close 与资源读取不等待。
  contextTicket :: m Int
  contextTicket = pure 0
  awaitContext :: [Slot] -> Int -> m Bool
  awaitContext _ _ = pure False
  -- 持续资产仍返回声明的表示类型：本次回调的交付优先，否则读运行级最新值。不启动来源。
  readContextValue :: Slot -> (environment -> Maybe value) -> m (Maybe value)
  readContextValue _ _ = pure Nothing
  -- lifelong 之外 requests 一份持续资产：本次没有交付时同步运行它的来源直到结束（同一次运行只运行一次），
  -- 把整段历史固定给本次调用。Nothing 表示来源结束时一条都没有发布。
  requestContextValue :: Slot -> (environment -> Maybe value) -> m (Maybe value)
  requestContextValue _ _ = pure Nothing
  -- stream @T：与上面取同一个视图，返回本次值及更早的发布，最新在前。
  readContextHistory :: Slot -> (environment -> Maybe value) -> m (Maybe [value])
  readContextHistory _ _ = pure Nothing
  -- Stream handler 的 streamEnd：退出来源方法，由来源运行器接住并正常返回。
  -- 不是 Failure，不经过 Error 诊断，也不被方法体内的 catchError 接住。
  endSource :: m value
  -- 订阅方的 endStream：放弃本次调用，由回调接住，这个节点（或派生）之后不再被回调。同样不是 Failure。
  endSubscription :: m value

data ContextFault = ContextNotInitialized
  | AmbiguousContextBinding String
  deriving (Eq, Show)

-- Scope 参数与生命周期能力 ----------------------------------------------------

-- 开启参数以 Context 来源及实际绑定的生产身份匹配，不比较业务值。
-- 身份由载体从已捕获的 Binding 取得，生成区无需为业务 ADT 引入 Eq。
data ScopeInput = ScopeInput Slot ActivationId deriving (Eq, Ord, Show)

-- SDK 内部生命周期能力；业务 instance 仍只实现 open／close。
data ScopeFault = ScopeNotOpen | ScopeIsClosed | ScopeReentry | ScopeInterrupted String
  | ScopeContextMissing String | ScopeContextMismatch String | ScopeInputsMissing [String] | ScopeInputAfterOpen String
  | ScopeCleanupInterrupted String | ScopeCleanupInProgress | ScopeInUse
  deriving (Eq, Show)

class Monad m => ScopeStore cause m | m -> cause where
  withScopeDependencies :: [Slot] -> m value -> m value
  -- Nothing 表示方法体没有执行：复用了同参的已开启实例，或重复 close 被跳过。
  -- open 带上本 scope 的 close 入口（gen 按开启它的同一 Middleware 列表写出），开启成功时登记为自动收尾。
  openScope :: Slot -> (ScopeFault -> cause) -> Maybe (m ()) -> m value -> m (Maybe value)
  closeScope :: Slot -> (ScopeFault -> cause) -> m value -> m (Maybe value)
  invalidateScope :: Slot -> Failure cause -> m ()

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
