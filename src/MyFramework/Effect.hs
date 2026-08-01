{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE ScopedTypeVariables #-}

module MyFramework.Effect
  ( ApplicationKey (..)
  , CommandEffectKind
  , CommandSpec (..)
  , EffectApplication (..)
  , EffectIR (..)
  , EffectKey (..)
  , EffectKind (..)
  , EffectRef
  , EffectRegistry (..)
  , EffectRuntimeStatus (..)
  , EffectSpec (..)
  , EffectStateProjection (..)
  , EncodedLiteral (..)
  , KnownEffectKind
  , MapSpec (..)
  , ParamName (..)
  , ParamSpec (..)
  , R
  , ReadSpec (..)
  , SomeEffectRef (..)
  , StateRevision (..)
  , TransformDecl (..)
  , TransformRef (..)
  , TransformRegistry (..)
  , ValueSourceSpec (..)
  , cEffectRef
  , commandEffect
  , dEffectRef
  , eEffectRef
  , effectApplication
  , effectRefKey
  , eraseEffectRef
  , mapEffect
  , mapEffectRef
  , rEffectRef
  , readEffect
  , reflectEffectKind
  , uEffectRef
  ) where

import Data.Proxy
  ( Proxy (..)
  )

import MyFramework.Schema
  ( ValueSchemaId
  )

-- | The six serializable effect kinds in the v5.2 core.
data EffectKind
  = C
  | U
  | R
  | D
  | E
  | MAP
  deriving (Eq, Ord, Read, Show)

newtype EffectKey = EffectKey
  { effectKeyText :: String
  }
  deriving (Eq, Ord, Read, Show)

-- | Stable typed reference.  Its phantom parameters carry the effect kind,
-- argument, and public result types without putting Haskell closures in IR.
newtype EffectRef (kind :: EffectKind) input output = EffectRef
  { effectRefKey :: EffectKey
  }
  deriving (Eq, Ord, Read, Show)

-- | R is an ordinary effect reference.  It has no independent registry.
type R value = EffectRef 'R () value

data SomeEffectRef = SomeEffectRef
  { someEffectRefKey :: EffectKey
  , someEffectRefKind :: EffectKind
  }
  deriving (Eq, Ord, Read, Show)

class KnownEffectKind (kind :: EffectKind) where
  reflectEffectKind :: proxy kind -> EffectKind

instance KnownEffectKind 'C where reflectEffectKind _ = C
instance KnownEffectKind 'U where reflectEffectKind _ = U
instance KnownEffectKind 'R where reflectEffectKind _ = R
instance KnownEffectKind 'D where reflectEffectKind _ = D
instance KnownEffectKind 'E where reflectEffectKind _ = E
instance KnownEffectKind 'MAP where reflectEffectKind _ = MAP

class KnownEffectKind kind => CommandEffectKind (kind :: EffectKind) where
  commandEffectWitness :: proxy kind -> ()

instance CommandEffectKind 'C where commandEffectWitness _ = ()
instance CommandEffectKind 'U where commandEffectWitness _ = ()
instance CommandEffectKind 'D where commandEffectWitness _ = ()
instance CommandEffectKind 'E where commandEffectWitness _ = ()

eraseEffectRef ::
  forall kind input output.
  KnownEffectKind kind =>
  EffectRef kind input output ->
  SomeEffectRef
eraseEffectRef currentRef =
  SomeEffectRef
    { someEffectRefKey = effectRefKey currentRef
    , someEffectRefKind = reflectEffectKind (Proxy :: Proxy kind)
    }

cEffectRef :: EffectKey -> EffectRef 'C input output
cEffectRef = EffectRef

uEffectRef :: EffectKey -> EffectRef 'U input output
uEffectRef = EffectRef

rEffectRef :: EffectKey -> R output
rEffectRef = EffectRef

dEffectRef :: EffectKey -> EffectRef 'D input output
dEffectRef = EffectRef

eEffectRef :: EffectKey -> EffectRef 'E input output
eEffectRef = EffectRef

mapEffectRef :: EffectKey -> EffectRef 'MAP input output
mapEffectRef = EffectRef

newtype ParamName = ParamName
  { paramNameText :: String
  }
  deriving (Eq, Ord, Read, Show)

data ParamSpec = ParamSpec
  { paramSpecName :: ParamName
  , paramSpecSchema :: ValueSchemaId
  }
  deriving (Eq, Ord, Read, Show)

newtype TransformRef = TransformRef
  { transformRefKey :: String
  }
  deriving (Eq, Ord, Read, Show)

data TransformDecl = TransformDecl
  { transformDeclRef :: TransformRef
  , transformDeclInputSchema :: ValueSchemaId
  , transformDeclOutput :: [ParamSpec]
  }
  deriving (Eq, Ord, Read, Show)

newtype TransformRegistry = TransformRegistry
  { transformRegistryDecls :: [TransformDecl]
  }
  deriving (Eq, Ord, Read, Show)

data EncodedLiteral
  = EncodedUnit
  | EncodedBool Bool
  | EncodedInteger Integer
  | EncodedDecimal String
  | EncodedText String
  deriving (Eq, Ord, Read, Show)

-- | Closed value-source IR used by R effects.  Every reference names another
-- R effect in the same EffectRegistry.
data ValueSourceSpec
  = ValueExternal String
  | ValueLiteral EncodedLiteral
  | ValueFromR SomeEffectRef
  | ValueRecord [(ParamName, ValueSourceSpec)]
  | ValueProduct [ValueSourceSpec]
  deriving (Eq, Ord, Read, Show)

data CommandSpec = CommandSpec
  { commandSpecParams :: [ParamSpec]
  , commandSpecObservationSchema :: ValueSchemaId
  }
  deriving (Eq, Ord, Read, Show)

data ReadSpec = ReadSpec
  { readSpecValueSchema :: ValueSchemaId
  , readSpecSource :: ValueSourceSpec
  }
  deriving (Eq, Ord, Read, Show)

data MapSpec = MapSpec
  { mapSpecTransform :: TransformRef
  , mapSpecInputSchema :: ValueSchemaId
  , mapSpecOutput :: [ParamSpec]
  }
  deriving (Eq, Ord, Read, Show)

data EffectSpec
  = CommandEffect CommandSpec
  | ReadEffect ReadSpec
  | MapEffect MapSpec
  deriving (Eq, Ord, Read, Show)

-- | Runtime state is intentionally absent from this record.
data EffectIR = EffectIR
  { effectIrRef :: SomeEffectRef
  , effectIrInput :: Maybe SomeEffectRef
  , effectIrSpec :: EffectSpec
  }
  deriving (Eq, Ord, Read, Show)

newtype EffectRegistry = EffectRegistry
  { effectRegistryEffects :: [EffectIR]
  }
  deriving (Eq, Ord, Read, Show)

commandEffect ::
  forall kind params observation.
  CommandEffectKind kind =>
  EffectRef kind params observation ->
  Maybe SomeEffectRef ->
  CommandSpec ->
  EffectIR
commandEffect currentRef currentInput currentSpec =
  commandEffectWitness (Proxy :: Proxy kind)
    `seq` EffectIR
      { effectIrRef = eraseEffectRef currentRef
      , effectIrInput = currentInput
      , effectIrSpec = CommandEffect currentSpec
      }

readEffect ::
  R value ->
  Maybe SomeEffectRef ->
  ReadSpec ->
  EffectIR
readEffect currentRef currentInput currentSpec =
  EffectIR
    { effectIrRef = eraseEffectRef currentRef
    , effectIrInput = currentInput
    , effectIrSpec = ReadEffect currentSpec
    }

mapEffect ::
  EffectRef 'MAP source params ->
  Maybe SomeEffectRef ->
  MapSpec ->
  EffectIR
mapEffect currentRef currentInput currentSpec =
  EffectIR
    { effectIrRef = eraseEffectRef currentRef
    , effectIrInput = currentInput
    , effectIrSpec = MapEffect currentSpec
    }

newtype ApplicationKey = ApplicationKey
  { applicationKeyText :: String
  }
  deriving (Eq, Ord, Read, Show)

-- | Erased, serializable application IR.  The smart constructor fixes the
-- typed authoring shape to command $ MAP $ R.
data EffectApplication = EffectApplication
  { effectApplicationKey :: ApplicationKey
  , effectApplicationCommand :: SomeEffectRef
  , effectApplicationMap :: SomeEffectRef
  , effectApplicationRead :: SomeEffectRef
  }
  deriving (Eq, Ord, Read, Show)

effectApplication ::
  forall commandKind params observation source.
  CommandEffectKind commandKind =>
  ApplicationKey ->
  EffectRef commandKind params observation ->
  EffectRef 'MAP source params ->
  R source ->
  EffectApplication
effectApplication currentKey currentCommand currentMap currentRead =
  commandEffectWitness (Proxy :: Proxy commandKind)
    `seq` EffectApplication
      { effectApplicationKey = currentKey
      , effectApplicationCommand = eraseEffectRef currentCommand
      , effectApplicationMap = eraseEffectRef currentMap
      , effectApplicationRead = eraseEffectRef currentRead
      }

data EffectRuntimeStatus
  = EffectDormant
  | EffectRunning
  | EffectSucceeded
  | EffectFailed
  | EffectCancelled
  | EffectSuspended
  deriving (Eq, Ord, Read, Show)

newtype StateRevision = StateRevision
  { stateRevisionValue :: Integer
  }
  deriving (Eq, Ord, Read, Show)

-- | Unified runtime projection for every kind, including MAP.  This is live
-- state owned by the runtime and never part of EffectIR serialization.
data EffectStateProjection = EffectStateProjection
  { effectStateRef :: SomeEffectRef
  , effectStateStatus :: EffectRuntimeStatus
  , effectStateObservation :: Maybe String
  , effectStateFailure :: Maybe String
  , effectStateRevision :: StateRevision
  }
  deriving (Eq, Ord, Read, Show)
