-- Context 的一次成功绑定：值快照与执行出身不变，全部引用共享首次认领的资源归属。
-- 每次生产分配自己的归属单元，替换来源绑定不会改写旧绑定的值或关闭责任。
module Framework.Effect.Binding
  ( Binding(..), BindingOwnership(..), Bindings, newBinding, readBindingOwner, bind
  ) where

import Data.IORef (IORef, newIORef, readIORef)
import Framework.Effect.Runtime.Identity (Execution)

data Binding environment owner user = Binding
  { bindingValues :: environment
  , bindingOrigin :: Execution
  , bindingOwnership :: IORef (BindingOwnership owner user)
  }

-- 未认领时保存已经使用此绑定的受控入口；认领时由 scope 协议接入实际实例。
-- 认领和使用登记由该次运行的 scope 协调锁串行化，owner 快照可只读取得。
data BindingOwnership owner user = BindingOwnership
  { bindingOwner :: Maybe owner
  , bindingUsers :: [user]
  }

type Bindings environment owner user = [(String, Binding environment owner user)]

newBinding :: environment -> Execution -> Maybe owner -> IO (Binding environment owner user)
newBinding values origin owner = Binding values origin <$> newIORef (BindingOwnership owner [])

readBindingOwner :: Binding environment owner user -> IO (Maybe owner)
readBindingOwner = fmap bindingOwner . readIORef . bindingOwnership

bind :: String -> Binding environment owner user -> Bindings environment owner user -> Bindings environment owner user
bind source value values = (source, value) : filter ((/= source) . fst) values
