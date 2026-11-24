{-# OPTIONS_GHC -fexpose-all-unfoldings -fspecialise-aggressively #-}
-- Context 的一次成功绑定：值快照与执行出身不变，全部引用共享首次认领的资源归属。
-- 每次生产分配自己的归属单元，替换来源绑定不会改写旧绑定的值或关闭责任。
module Framework.Runtime.Binding
  ( Binding(..), BindingOwnership(..), Bindings, newBinding, readBindingOwner, bind
  ) where

import Data.IORef (IORef, newIORef, readIORef)
import Framework.Runtime.Identity (Execution, ActivationId)
import Framework.Runtime.Frame (ExecutionFrame)
import Framework.Prototype.Slot (Slot)

data Binding environment owner user = Binding
  { bindingValues :: environment
  , bindingOrigin :: Execution
  -- 成功生产的 activation 与执行帧独立于业务 Origin 和关闭归属；交接不重发身份。
  , bindingProduction :: Maybe ActivationId
  , bindingFrame :: ExecutionFrame
  -- 注册已指定的资源 Context（也含无资源 scope 的内部绑定）；认领前也可识别。
  -- 不是对任意业务 ADT 内嵌句柄的推断。
  , bindingResource :: !Bool
  , bindingOwnership :: IORef (BindingOwnership owner user)
  }

-- 未认领时保存已经使用此绑定的受控入口；认领时由 scope 协议接入实际实例。
-- 认领和使用登记由该次运行的 scope 协调锁串行化，owner 快照可只读取得。
data BindingOwnership owner user = BindingOwnership
  { bindingOwner :: Maybe owner
  , bindingUsers :: [user]
  }

-- 按 gen 分配的 effect 编号寻址；名字只留在 Slot 里供诊断。
type Bindings environment owner user = [(Slot, Binding environment owner user)]

newBinding :: environment -> Execution -> Maybe ActivationId -> ExecutionFrame -> Bool -> Maybe owner
           -> IO (Binding environment owner user)
newBinding values origin production frame resource owner =
  Binding values origin production frame resource <$> newIORef (BindingOwnership owner [])

readBindingOwner :: Binding environment owner user -> IO (Maybe owner)
readBindingOwner = fmap bindingOwner . readIORef . bindingOwnership

bind :: Slot -> Binding environment owner user -> Bindings environment owner user -> Bindings environment owner user
bind source value values = (source, value) : filter ((/= source) . fst) values
