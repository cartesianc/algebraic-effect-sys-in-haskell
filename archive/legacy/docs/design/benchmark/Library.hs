{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE FunctionalDependencies #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE UndecidableInstances #-}

-- The small library used by the semantic benchmark. Production integration,
-- heterogeneous registration and static linear ownership remain separate work.
module Library where

import Control.Exception (IOException, bracket, catch)
import Control.Monad (void)
import Data.Kind (Type)
import GHC.TypeLits (Symbol)

data Kind = KExcu | KRead | KMap | KClose | KX
data Typing (kind :: Kind) where
  Excu :: Typing 'KExcu
  Read :: Typing 'KRead
  Map :: Typing 'KMap
  Close :: Typing 'KClose
  X :: Typing 'KX

type family Action (kind :: Kind) result where
  Action 'KExcu result = IO result
  Action 'KRead result = result
  Action 'KMap result = result
  Action 'KClose result = IO result
  Action 'KX result = IO result

class Handler (name :: Symbol) (kind :: Kind) source args result
    | name source -> kind args result where
  invoke :: source -> args -> Action kind result
  {-# MINIMAL invoke #-}

data Handlers name kind source args result where
  Handlers :: Handler name kind source args result
           => Handlers name kind source args result

handlers :: Handler name kind source args result
         => Handlers name kind source args result
handlers = Handlers

data Supplied value = Supplied value
supplied :: value -> Supplied value
supplied = Supplied

-- A registration selects the argument ADT. Values are supplied by a call site.
data Requirement args = Requirement

ofType :: forall args. Requirement args
ofType = Requirement

noRequire :: Requirement ()
noRequire = Requirement

-- require and bind share args, so the selected ADT also fixes the impl input.
data Effect failure upstream args name kind opArgs opResult result = Effect
  { typing :: Typing kind
  , input :: upstream
  , require :: Requirement args
  , handler :: Handlers name kind (Ready upstream) opArgs opResult
  , bind :: Handler name kind (Ready upstream) opArgs opResult
         => Ready upstream -> args -> Action kind result
  , scope :: Scope failure result
  }

type family Ready node :: Type where
  Ready (Supplied value) = value
  Ready (Effect failure upstream args name kind opArgs opResult result) = result

-- Parameters are pure expressions evaluated against this activation's result.
data Parameters env source value = Parameters (env -> source -> value)

argument :: (env -> value) -> Parameters env source value
argument select = Parameters (\env _ -> select env)

prepare :: Parameters env source value -> env -> source -> value
prepare (Parameters expression) = expression

-- A typed parameter spine for one invocation of the declared input chain.
-- The Effect graph owns dependencies; this spine supplies only their arguments.
data Arguments env node where
  NoArguments :: Arguments env (Supplied value)
  WithArgs :: Parameters env (Ready upstream) args
           -> Arguments env upstream
           -> Arguments env (Effect failure upstream args name kind opArgs opResult result)

noArguments :: Arguments env (Supplied value)
noArguments = NoArguments

withArgs :: Parameters env (Ready upstream) args
         -> Arguments env upstream
         -> Arguments env (Effect failure upstream args name kind opArgs opResult result)
withArgs = WithArgs

-- Bind is applied while its registered class dictionary is in scope.
applyBound :: Effect failure upstream args name kind opArgs opResult result
           -> Ready upstream -> args -> Action kind result
applyBound (Effect _ _ _ Handlers implementation _) = implementation

readFrom :: Effect failure upstream () name 'KRead opArgs opResult result
         -> Parameters env (Ready upstream) result
readFrom (Effect _ _ _ Handlers implementation _) =
  Parameters (\_ ready -> implementation ready ())

mapped :: Effect failure upstream () name 'KMap opArgs opResult result
       -> Parameters env source (Ready upstream)
       -> Parameters env source result
mapped (Effect _ _ _ Handlers implementation _) values = Parameters $ \env ready ->
  implementation (prepare values env ready) ()

combine :: (a -> b -> value) -> Parameters env source a
        -> Parameters env source b -> Parameters env source value
combine f left right = Parameters $ \env ready ->
  f (prepare left env ready) (prepare right env ready)

data Scope failure resource
  = NoScope
  | Managed (resource -> IO ()) (resource -> IOException -> IO failure)

noScope :: Scope failure resource
noScope = NoScope

-- Scope references compile to operations on the resource already acquired.
-- The finalizers' input chains are not acquired a second time.
closes :: (Ready closeUpstream ~ resource, Ready errorUpstream ~ resource)
       => Effect failure closeUpstream () closeName 'KClose closeArgs closeResult closed
       -> Effect failure errorUpstream IOException errorName 'KX errorArgs errorResult failure
       -> Scope failure resource
closes closeEffect errorEffect = Managed
  (\resource -> void (applyBound closeEffect resource ()))
  (\resource err -> applyBound errorEffect resource err)

liftAction :: Typing kind -> Action kind result -> IO result
liftAction Excu action = action
liftAction Read value = pure value
liftAction Map value = pure value
liftAction Close action = action
liftAction X action = action

type Connected env failure value =
  forall result. env -> (value -> IO (Either failure result)) -> IO (Either failure result)

class Lower env failure node where
  connect :: node -> Arguments env node -> Connected env failure (Ready node)

instance Lower env failure (Supplied value) where
  connect (Supplied value) NoArguments _ next = next value

instance (failure ~ nodeFailure, Lower env failure upstream)
      => Lower env failure (Effect nodeFailure upstream args name kind opArgs opResult result) where
  connect (Effect kind upstream Requirement Handlers implementation lifetime)
          (WithArgs parameters upstreamArguments) =
    let parent = connect @env @failure upstream upstreamArguments
    in \env next -> parent env $ \ready ->
      let action = liftAction kind (implementation ready (prepare parameters env ready))
      in case lifetime of
        NoScope -> action >>= next
        Managed release recover ->
          bracket action release $ \resource ->
            next resource `catch` (\err -> Left <$> recover resource err)

compile :: forall env failure node. Lower env failure node
        => node -> Arguments env node -> env -> IO (Either failure (Ready node))
compile registration arguments env =
  connect @env @failure registration arguments env (\result -> pure (Right result))
