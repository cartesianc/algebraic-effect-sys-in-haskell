-- Context 的一次成功绑定：值快照和资源归属一起传递。
-- 替换一个来源的绑定不会改写已经被其他调用捕获的旧绑定。
module Framework.Effect.Binding (Binding(..), Bindings, bind) where

data Binding environment owner = Binding
  { bindingValues :: environment
  , bindingOwners :: [owner]
  }

type Bindings environment owner = [(String, Binding environment owner)]

bind :: String -> Binding environment owner -> Bindings environment owner -> Bindings environment owner
bind source value values = (source, value) : filter ((/= source) . fst) values
