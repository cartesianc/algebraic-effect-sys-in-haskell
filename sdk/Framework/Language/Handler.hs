{-# LANGUAGE MultiParamTypeClasses #-}

-- handler 在源语言中能用的全部能力，以及业务能观察到的完成结果。
-- 能力类的实例由 gen 按注册生成（Framework.Gen.Emit.Handlers）；执行载体的协议在 Framework.Runtime.Protocol。
module Framework.Language.Handler
  ( Reads(..), Raw(..), Emits(..), RawOutputs(..), Raises(..), StreamEnds(..), EndsStream(..), Hooks(..), Operation(..)
  , Failure(..), Output(..), ErrorReport(..)
  ) where

-- handler 是对 m 泛型的类方法，只能使用 gen 按注册给出的 Layer：
-- Reads 按表示类型读取资产，来源由 effect 的 demands 在 gen 时解析；
-- Raw 读取直接 Input 本次交出的输出，只给挂接的 parser 与 Pure。RawOutputs 交出原子列表，
-- Stream 的一份原始输入读作单元素 list；
-- Raises 以本 handler 的错误失败，发生位置由 SDK 记录；
-- StreamEnds 只给 Stream handler（生产方）：来源已经没有下一份输入时以 streamEnd 退出方法体；
-- EndsStream 只给由持续资产驱动的消费链上的 Excu handler（消费方）：不再消费这份持续资产时以 endStream 退出。
class Reads value m where
  require :: m value

class Raw m where
  rawinput :: m [String]

-- Stream 的一次交付。返回 () 时本条的 parser 已成功发布，来源方法可以继续交付。
class Emits m where
  rawemit :: String -> m ()

-- 业务显式交出列表时通知 RawOutput；Middleware 自身的输出使用默认实现。
class Applicative m => RawOutputs m where
  rawoutput :: [String] -> m [String]
  rawoutput = pure

class Raises failure m where
  raise :: failure -> m value

-- 正常返回 () 继续下一步。streamEnd 封住当前会话，保留包括本次调用在内的已发布交付。
class StreamEnds m where
  streamEnd :: m value

-- 消费方的出口：本次调用放弃（不交出结果），调用所在的订阅结束，之后不再为它领取交付。
-- 消费方结束不直接停产：读取方按引用计数逐层离开（节点 → 单元 → 会话），
-- 会话的读取方全部离开才停止生产。生成期只把它给 lifelong 节点的 original chain
-- 或 Derive 会话被驱动链上的 Excu，运行时按当前调用的位置找到唯一的订阅。
-- 它不是失败，不进入 Error 协议。
class EndsStream m where
  endStream :: m value

-- 触发本次 Middleware 的唯一操作。首字段总是当前绑定的业务方法名。
data Operation
  = Enter String
  | RawInput String [String]
  | RawOutput String [String]
  | RawEmit String String
  | Raise String String

-- 只有 Middleware 的标签获得 Hooks。一次调用始终读取触发它的同一项操作。
class Monad m => Hooks m where
  hook :: m Operation

-- SDK 统一失败协议：来源、生成的错误分类和消息；传播时不改写或再次包装。
data Failure cause = Failure
  { origin :: String
  , detail :: cause
  , message :: String
  , scopeTrace :: [String]
  -- 生命周期失败保存实际实例身份；Nothing 明确表示本次尚未选出实例。
  , scopeTargets :: [(String, Maybe Int)]
  , errorHandling :: Maybe [ErrorReport cause]
  -- 收尾故障附在原失败之后，不覆盖其来源、分类或诊断结果。
  , cleanupFailures :: [Failure cause]
  } deriving (Eq, Show)

-- 完成结果只在运行边界封装一次，不包含 Pending。
data Output cause value = Succ value | Failed (Failure cause)
  deriving (Eq, Show)

-- 一个 Error 注册对某次失败的检测与处置结果，附在 Failure 上供业务观察。
data ErrorReport cause = ErrorReport
  { reportScope :: Maybe String
  , reportEffect :: String
  , detectResult :: Maybe (Output cause ())
  , resolveResult :: Maybe (Output cause ())
  } deriving (Eq, Show)
