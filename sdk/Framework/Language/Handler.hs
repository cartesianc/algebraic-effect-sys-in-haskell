{-# LANGUAGE MultiParamTypeClasses #-}

-- handler 在源语言中能用的全部能力，以及业务能观察到的完成结果。
-- 能力类的实例由 gen 按注册生成（Framework.Gen.Emit.Handlers）；执行载体的协议在 Framework.Runtime.Protocol。
module Framework.Language.Handler
  ( Reads(..), Raw(..), Raises(..)
  , Failure(..), Output(..), ErrorReport(..)
  ) where

-- handler 是对 m 泛型的类方法，只能使用 gen 按注册给出的 Layer：
-- Reads 按表示类型读取资产，来源由 effect 的 demands 在 gen 时解析；
-- Raw 读取直接 Input 本次交出的输出，只给挂接的 parser 与 Pure：Excu、Scoped.open、Pure 交出 [String]，
-- Stream 的一份原始输入读作单元素 list；
-- Raises 以本 handler 的错误失败，发生位置由 SDK 记录。
class Reads value m where
  require :: m value

class Raw m where
  raw :: m [String]

class Raises failure m where
  raise :: failure -> m value

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
