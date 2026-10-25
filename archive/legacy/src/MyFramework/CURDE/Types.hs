{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}

module MyFramework.CURDE.Types
  ( CURDE (..)
  , SCURDE (..)
  , curdeValue
  , HandleId (..)
  , renderHandleId
  , FieldName (..)
  , SchemaIdentity (..)
  , SchemaShape (..)
  , SchemaRef
  , schemaRef
  , scalarSchema
  , recordSchema
  , productSchema
  , schemaRefName
  , schemaRefShape
  , schemaRefIdentityOf
  , unitSchema
  , NoObservation
  , noObservationSchema
  , ObservationSpec (..)
  , ObservationContract (..)
  , ReadSource (..)
  , CommandKind (..)
  , CommandSpec (..)
  , ReadSpec (..)
  , Handle
  , SomeHandleRef (..)
  , SomeCommandHandleRef (..)
  , HandleDecl (..)
  , eraseHandle
  , eraseSomeHandle
  , c
  , u
  , r
  , d
  , e
  , handleId
  , handleKind
  , handleArgumentSchemaRef
  , handleResultSchemaRef
  , handleInput
  , handleReadSource
  , handleCommandKind
  , handleObservationSchemaRef
  , handlePublicValueSchemaRef
  , someHandleId
  , someHandleKind
  , someHandleArgumentSchemaIdentity
  , someHandleObservationContract
  , someHandlePublicValueSchemaIdentity
  , someHandleInput
  , someHandleReadSource
  , someCommandHandleId
  , someCommandHandleKind
  , someCommandHandleArgumentSchemaIdentity
  , EffSys (..)
  , effSys
  , effSysHandleIds
  , EffSysDecl (..)
  , eraseEffSys
  , effSysDeclHandleIds
  ) where

import Data.Proxy
  ( Proxy (..) )
import GHC.TypeLits
  ( KnownSymbol
  , Symbol
  , symbolVal
  )

-- | The five operation classes exposed by the serializable facade.
--
-- C/U/D/E expose only a status channel. Their observation channel is private
-- to the producing handle and becomes public only through an R handle.
data CURDE
  = C
  | U
  | R
  | D
  | E
  deriving (Eq, Ord, Read, Show)

data SCURDE (kind :: CURDE) where
  SC :: SCURDE 'C
  SU :: SCURDE 'U
  SR :: SCURDE 'R
  SD :: SCURDE 'D
  SE :: SCURDE 'E

instance Show (SCURDE kind) where
  show =
    show . curdeValue

curdeValue :: SCURDE kind -> CURDE
curdeValue currentKind =
  case currentKind of
    SC -> C
    SU -> U
    SR -> R
    SD -> D
    SE -> E

-- | Stable facade identity. Runtime attempts must use their own identity and
-- must never be folded into this value.
newtype HandleId = HandleId
  { handleIdQualifiedName :: String
  }
  deriving (Eq, Ord, Read, Show)

renderHandleId :: HandleId -> String
renderHandleId currentId =
  encodeIdentitySegment (handleIdQualifiedName currentId)
  where
    encodeIdentitySegment currentSegment =
      show (length currentSegment) ++ ":" ++ currentSegment

newtype FieldName = FieldName
  { fieldNameText :: String
  }
  deriving (Eq, Ord, Read, Show)

data SchemaIdentity = SchemaIdentity
  { schemaIdentityName :: String
  , schemaIdentityShape :: SchemaShape
  }
  deriving (Eq, Ord, Read, Show)

data SchemaShape
  = UnitShape
  | ScalarShape
  | RecordShape [(FieldName, SchemaIdentity)]
  | ProductShape [SchemaIdentity]
  deriving (Eq, Ord, Read, Show)

newtype SchemaRef value = SchemaRef
  { schemaRefIdentity :: SchemaIdentity
  }
  deriving (Eq, Ord)

instance Show (SchemaRef value) where
  show =
    schemaRefName

schemaRef :: String -> SchemaShape -> SchemaRef value
schemaRef currentName currentShape =
  SchemaRef
    SchemaIdentity
      { schemaIdentityName = currentName
      , schemaIdentityShape = currentShape
      }

scalarSchema :: String -> SchemaRef value
scalarSchema currentName =
  schemaRef currentName ScalarShape

recordSchema :: String -> [(FieldName, SchemaIdentity)] -> SchemaRef value
recordSchema currentName currentFields =
  schemaRef currentName (RecordShape currentFields)

productSchema :: String -> [SchemaIdentity] -> SchemaRef value
productSchema currentName currentItems =
  schemaRef currentName (ProductShape currentItems)

schemaRefName :: SchemaRef value -> String
schemaRefName =
  schemaIdentityName . schemaRefIdentity

schemaRefShape :: SchemaRef value -> SchemaShape
schemaRefShape =
  schemaIdentityShape . schemaRefIdentity

schemaRefIdentityOf :: SchemaRef value -> SchemaIdentity
schemaRefIdentityOf =
  schemaRefIdentity

unitSchema :: SchemaRef ()
unitSchema =
  schemaRef "Unit" UnitShape

-- | Explicit marker for a command whose physical result is discarded.
data NoObservation

noObservationSchema :: SchemaRef NoObservation
noObservationSchema =
  schemaRef "NoObservation" UnitShape

data ObservationSpec observation where
  DiscardObservation :: ObservationSpec NoObservation
  CaptureObservation :: SchemaRef observation -> ObservationSpec observation

instance Eq (ObservationSpec observation) where
  DiscardObservation == DiscardObservation = True
  CaptureObservation left == CaptureObservation right = left == right
  _ == _ = False

instance Ord (ObservationSpec observation) where
  compare DiscardObservation DiscardObservation = EQ
  compare DiscardObservation (CaptureObservation _) = LT
  compare (CaptureObservation _) DiscardObservation = GT
  compare (CaptureObservation left) (CaptureObservation right) =
    compare left right

instance Show (ObservationSpec observation) where
  show DiscardObservation =
    "DiscardObservation"
  show (CaptureObservation currentSchema) =
    "CaptureObservation " ++ show currentSchema

-- | Erased observation information used by validation. A captured command
-- value is not a public value channel.
data ObservationContract
  = ObservationDiscarded
  | ObservationCaptured SchemaIdentity
  deriving (Eq, Ord, Read, Show)

data ReadSource
  = ReadFromHandler
  | ReadFromInputValue
  | ReadFromInputObservation
  deriving (Eq, Ord, Read, Show)

data CommandKind (kind :: CURDE) where
  CCommand :: CommandKind 'C
  UCommand :: CommandKind 'U
  DCommand :: CommandKind 'D
  ECommand :: CommandKind 'E

instance Show (CommandKind kind) where
  show currentKind =
    case currentKind of
      CCommand -> "C"
      UCommand -> "U"
      DCommand -> "D"
      ECommand -> "E"

data CommandSpec args observation = CommandSpec
  { commandArgumentSchema :: SchemaRef args
  , commandObservation :: ObservationSpec observation
  , commandInput :: Maybe SomeHandleRef
  }

data ReadSpec value = ReadSpec
  { readResultSchema :: SchemaRef value
  , readInput :: Maybe SomeHandleRef
  , readSource :: ReadSource
  }

-- | A typed facade handle. The single 'Maybe' input makes the one-input
-- invariant structural rather than a convention checked after construction.
data Handle
  (name :: Symbol)
  (kind :: CURDE)
  args
  result = Handle
  { handleKindWitness :: SCURDE kind
  , handleIdentity :: HandleId
  , handleArguments :: SchemaRef args
  , handleResult :: SchemaRef result
  , handleInputReference :: Maybe SomeHandleRef
  , handleObservationSpecification :: Maybe (ObservationSpec result)
  , handleSource :: Maybe ReadSource
  }

instance Show (Handle name kind args result) where
  show currentHandle =
    "Handle "
      ++ show (handleKind currentHandle)
      ++ " "
      ++ show (handleId currentHandle)

data SomeHandleRef where
  SomeHandleRef :: Handle name kind args result -> SomeHandleRef

instance Eq SomeHandleRef where
  left == right =
    someHandleId left == someHandleId right

instance Ord SomeHandleRef where
  compare left right =
    compare (someHandleId left) (someHandleId right)

instance Show SomeHandleRef where
  show currentHandle =
    "SomeHandleRef "
      ++ show (someHandleKind currentHandle)
      ++ " "
      ++ show (someHandleId currentHandle)

-- | Existential wrapper that cannot contain R. It is the erased target type
-- used by serializable implementation bindings.
data SomeCommandHandleRef where
  SomeCommandHandleRef ::
    CommandKind kind ->
    Handle name kind args observation ->
    SomeCommandHandleRef

instance Eq SomeCommandHandleRef where
  left == right =
    someCommandHandleId left == someCommandHandleId right

instance Ord SomeCommandHandleRef where
  compare left right =
    compare (someCommandHandleId left) (someCommandHandleId right)

instance Show SomeCommandHandleRef where
  show currentHandle =
    "SomeCommandHandleRef "
      ++ show (someCommandHandleKind currentHandle)
      ++ " "
      ++ show (someCommandHandleId currentHandle)

-- | Serializable handle contract. No typed handle, handler, runtime resource,
-- or closure crosses this boundary.
data HandleDecl = HandleDecl
  { handleDeclId :: HandleId
  , handleDeclKind :: CURDE
  , handleDeclArgumentSchema :: SchemaIdentity
  , handleDeclObservation :: Maybe ObservationContract
  , handleDeclPublicValueSchema :: Maybe SchemaIdentity
  , handleDeclInput :: Maybe HandleId
  , handleDeclReadSource :: Maybe ReadSource
  }
  deriving (Eq, Ord, Read, Show)

c ::
  forall name args observation.
  KnownSymbol name =>
  CommandSpec args observation ->
  Handle name 'C args observation
c =
  commandHandle @name SC CCommand

u ::
  forall name args observation.
  KnownSymbol name =>
  CommandSpec args observation ->
  Handle name 'U args observation
u =
  commandHandle @name SU UCommand

r ::
  forall name value.
  KnownSymbol name =>
  ReadSpec value ->
  Handle name 'R () value
r currentSpec =
  Handle
    { handleKindWitness = SR
    , handleIdentity = handleIdFor @name
    , handleArguments = unitSchema
    , handleResult = readResultSchema currentSpec
    , handleInputReference = readInput currentSpec
    , handleObservationSpecification = Nothing
    , handleSource = Just (readSource currentSpec)
    }

d ::
  forall name args observation.
  KnownSymbol name =>
  CommandSpec args observation ->
  Handle name 'D args observation
d =
  commandHandle @name SD DCommand

e ::
  forall name args observation.
  KnownSymbol name =>
  CommandSpec args observation ->
  Handle name 'E args observation
e =
  commandHandle @name SE ECommand

commandHandle ::
  forall name kind args observation.
  KnownSymbol name =>
  SCURDE kind ->
  CommandKind kind ->
  CommandSpec args observation ->
  Handle name kind args observation
commandHandle currentKind _ currentSpec =
  Handle
    { handleKindWitness = currentKind
    , handleIdentity = handleIdFor @name
    , handleArguments = commandArgumentSchema currentSpec
    , handleResult = observationSchemaRef (commandObservation currentSpec)
    , handleInputReference = commandInput currentSpec
    , handleObservationSpecification =
        Just (commandObservation currentSpec)
    , handleSource = Nothing
    }

observationSchemaRef :: ObservationSpec observation -> SchemaRef observation
observationSchemaRef currentSpec =
  case currentSpec of
    DiscardObservation ->
      noObservationSchema
    CaptureObservation currentSchema ->
      currentSchema

handleIdFor ::
  forall name.
  KnownSymbol name =>
  HandleId
handleIdFor =
  HandleId (symbolVal (Proxy @name))

handleId :: Handle name kind args result -> HandleId
handleId =
  handleIdentity

handleKind :: Handle name kind args result -> CURDE
handleKind =
  curdeValue . handleKindWitness

handleArgumentSchemaRef :: Handle name kind args result -> SchemaRef args
handleArgumentSchemaRef =
  handleArguments

handleResultSchemaRef :: Handle name kind args result -> SchemaRef result
handleResultSchemaRef =
  handleResult

handleInput :: Handle name kind args result -> Maybe SomeHandleRef
handleInput =
  handleInputReference

handleReadSource :: Handle name kind args result -> Maybe ReadSource
handleReadSource =
  handleSource

handleCommandKind ::
  Handle name kind args observation ->
  Maybe (CommandKind kind)
handleCommandKind currentHandle =
  case handleKindWitness currentHandle of
    SC -> Just CCommand
    SU -> Just UCommand
    SR -> Nothing
    SD -> Just DCommand
    SE -> Just ECommand

-- | Only CUDE handles can expose this accessor, and its result is still the
-- private observation channel rather than a public expression value.
handleObservationSchemaRef ::
  Handle name kind args result ->
  Maybe (SchemaRef result)
handleObservationSchemaRef currentHandle =
  case handleObservationSpecification currentHandle of
    Just (CaptureObservation currentSchema) ->
      Just currentSchema
    _ ->
      Nothing

-- | R is the only public typed value channel.
handlePublicValueSchemaRef ::
  Handle name kind args result ->
  Maybe (SchemaRef result)
handlePublicValueSchemaRef currentHandle =
  case handleKindWitness currentHandle of
    SR -> Just (handleResult currentHandle)
    _ -> Nothing

someHandleId :: SomeHandleRef -> HandleId
someHandleId (SomeHandleRef currentHandle) =
  handleId currentHandle

someHandleKind :: SomeHandleRef -> CURDE
someHandleKind (SomeHandleRef currentHandle) =
  handleKind currentHandle

someHandleArgumentSchemaIdentity :: SomeHandleRef -> SchemaIdentity
someHandleArgumentSchemaIdentity (SomeHandleRef currentHandle) =
  schemaRefIdentityOf (handleArgumentSchemaRef currentHandle)

someHandleObservationContract :: SomeHandleRef -> Maybe ObservationContract
someHandleObservationContract (SomeHandleRef currentHandle) =
  case handleObservationSpecification currentHandle of
    Nothing ->
      Nothing
    Just DiscardObservation ->
      Just ObservationDiscarded
    Just (CaptureObservation currentSchema) ->
      Just (ObservationCaptured (schemaRefIdentityOf currentSchema))

someHandlePublicValueSchemaIdentity :: SomeHandleRef -> Maybe SchemaIdentity
someHandlePublicValueSchemaIdentity (SomeHandleRef currentHandle) =
  schemaRefIdentityOf <$> handlePublicValueSchemaRef currentHandle

someHandleInput :: SomeHandleRef -> Maybe SomeHandleRef
someHandleInput (SomeHandleRef currentHandle) =
  handleInput currentHandle

someHandleReadSource :: SomeHandleRef -> Maybe ReadSource
someHandleReadSource (SomeHandleRef currentHandle) =
  handleReadSource currentHandle

someCommandHandleId :: SomeCommandHandleRef -> HandleId
someCommandHandleId (SomeCommandHandleRef _ currentHandle) =
  handleId currentHandle

someCommandHandleKind :: SomeCommandHandleRef -> CURDE
someCommandHandleKind (SomeCommandHandleRef _ currentHandle) =
  handleKind currentHandle

someCommandHandleArgumentSchemaIdentity ::
  SomeCommandHandleRef ->
  SchemaIdentity
someCommandHandleArgumentSchemaIdentity
  (SomeCommandHandleRef _ currentHandle) =
    schemaRefIdentityOf (handleArgumentSchemaRef currentHandle)

eraseHandle :: Handle name kind args result -> HandleDecl
eraseHandle currentHandle =
  HandleDecl
    { handleDeclId = handleId currentHandle
    , handleDeclKind = handleKind currentHandle
    , handleDeclArgumentSchema =
        schemaRefIdentityOf (handleArgumentSchemaRef currentHandle)
    , handleDeclObservation =
        case handleObservationSpecification currentHandle of
          Nothing ->
            Nothing
          Just DiscardObservation ->
            Just ObservationDiscarded
          Just (CaptureObservation currentSchema) ->
            Just (ObservationCaptured (schemaRefIdentityOf currentSchema))
    , handleDeclPublicValueSchema =
        schemaRefIdentityOf <$> handlePublicValueSchemaRef currentHandle
    , handleDeclInput =
        someHandleId <$> handleInput currentHandle
    , handleDeclReadSource =
        handleReadSource currentHandle
    }

eraseSomeHandle :: SomeHandleRef -> HandleDecl
eraseSomeHandle (SomeHandleRef currentHandle) =
  eraseHandle currentHandle

-- | The single typed effect declaration graph. Source modules may contribute
-- records independently, but lowering consumes exactly one unified value.
newtype EffSys = EffSys
  { effSysHandles :: [SomeHandleRef]
  }
  deriving (Eq, Show)

effSys :: [SomeHandleRef] -> EffSys
effSys =
  EffSys

effSysHandleIds :: EffSys -> [HandleId]
effSysHandleIds =
  map someHandleId . effSysHandles

-- | Serializable unified effect graph. Module visibility belongs to AST/SDK
-- policy and is deliberately absent from runtime dependency semantics.
newtype EffSysDecl = EffSysDecl
  { effSysDeclHandles :: [HandleDecl]
  }
  deriving (Eq, Ord, Read, Show)

eraseEffSys :: EffSys -> EffSysDecl
eraseEffSys =
  EffSysDecl . map eraseSomeHandle . effSysHandles

effSysDeclHandleIds :: EffSysDecl -> [HandleId]
effSysDeclHandleIds =
  map handleDeclId . effSysDeclHandles
