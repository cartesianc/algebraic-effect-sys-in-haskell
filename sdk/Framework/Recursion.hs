{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE UndecidableInstances #-}

-- 通用 recursion scheme；不依赖 Effect、业务 AST 或 IO。
module Framework.Recursion (Fix(..), Algebra, cata) where



newtype Fix f = Fix (f (Fix f))

deriving instance Show (f (Fix f)) => Show (Fix f)
deriving instance Read (f (Fix f)) => Read (Fix f)

type Algebra f value = f value -> value

cata :: Functor f => Algebra f value -> Fix f -> value
cata algebra (Fix layer) = algebra (fmap (cata algebra) layer)
