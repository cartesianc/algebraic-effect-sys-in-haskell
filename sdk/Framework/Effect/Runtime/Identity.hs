-- 一次运行中的入口身份和执行来源；与 scope 实例的关闭归属分开。
module Framework.Effect.Runtime.Identity
  ( Origin(..), ActivationId(..), Boot(..), Execution(..), executionOrigin
  ) where

import Framework.Prototype (NodeId)

-- NodeId 指向当前 Prototype 的挂载；序号只区分执行实例，不决定资产可见性。
data Origin = Origin
  { originNode :: NodeId
  , originSequence :: Integer
  } deriving (Eq, Ord, Show)

newtype ActivationId = ActivationId Integer
  deriving (Eq, Ord, Show)

-- 使用现有 AST 位置和 Context 注册身份；不增加业务 key。
data Boot = TargetedBoot NodeId | RequestBoot String
  deriving (Eq, Show)

-- 自动收尾保留最初的业务来源，同时明确本次执行属于哪个资源实例的清理。
-- 发布记录携带清理角色，具体实例引用继续保存在 bindingOwner 中。
data Execution
  = BusinessExecution Origin
  | CleanupExecution Origin String Int
  deriving (Eq, Show)

executionOrigin :: Execution -> Origin
executionOrigin (BusinessExecution selected) = selected
executionOrigin (CleanupExecution selected _ _) = selected
