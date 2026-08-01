module MyFramework.Handler.Adapter
  ( HandlerAdapter
  , HandlerContract (..)
  , handlerAdapter
  , handlerAdapterContract
  , handlerAdapterFunction
  , handlerAdapterInputCodec
  , handlerAdapterOutputCodec
  , handlerAdapterRef
  ) where

import MyFramework.Effect
import MyFramework.Schema

-- | Serializable portion of a Handler registration.  Function names do not
-- participate in identity; the EffectRef and versioned codecs carry it.
data HandlerContract = HandlerContract
  { handlerContractEffect :: SomeEffectRef
  , handlerContractInputSchema :: SchemaDescriptor
  , handlerContractOutputSchema :: SchemaDescriptor
  }
  deriving (Eq, Ord, Read, Show)

-- | The ordinary Haskell implementation stays behind the runtime boundary.
-- Only 'handlerAdapterContract' may enter an artifact.
data HandlerAdapter kind input output = HandlerAdapter
  { handlerAdapterRef :: EffectRef kind input output
  , handlerAdapterInputCodec :: Codec input
  , handlerAdapterOutputCodec :: Codec output
  , handlerAdapterFunction :: input -> IO (Either String output)
  , handlerAdapterContract :: HandlerContract
  }

handlerAdapter ::
  KnownEffectKind kind =>
  EffectRef kind input output ->
  Codec input ->
  Codec output ->
  (input -> IO (Either String output)) ->
  HandlerAdapter kind input output
handlerAdapter currentRef currentInputCodec currentOutputCodec currentFunction =
  HandlerAdapter
    { handlerAdapterRef = currentRef
    , handlerAdapterInputCodec = currentInputCodec
    , handlerAdapterOutputCodec = currentOutputCodec
    , handlerAdapterFunction = currentFunction
    , handlerAdapterContract =
        HandlerContract
          { handlerContractEffect = eraseEffectRef currentRef
          , handlerContractInputSchema =
              descriptorFor
                (SchemaFromHandlerCodec (codecName currentInputCodec))
                (codecDefinition currentInputCodec)
          , handlerContractOutputSchema =
              descriptorFor
                (SchemaFromHandlerCodec (codecName currentOutputCodec))
                (codecDefinition currentOutputCodec)
          }
    }
