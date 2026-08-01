module MyFramework.Handler.Adapter
  ( HandlerAdapter
  , HandlerContract (..)
  , handlerAdapter
  , handlerAdapterContract
  , handlerAdapterFunction
  , handlerAdapterInputCodec
  , handlerAdapterOutputCodec
  , handlerAdapterRef
  , runtimeHandlerFromAdapter
  ) where

import MyFramework.Effect
import MyFramework.Schema
import MyFramework.Runtime.V52
  ( RuntimeHandlerPhase (..)
  , RuntimeHandlerRegistration
  , RuntimeHandlerResult (..)
  , RuntimeInvocation (..)
  , RuntimeValue (..)
  , runtimeHandler
  )

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

-- | Erase an ordinary typed Haskell handler into the unified runtime.  Codec
-- decoding and encoding stay at this boundary; EffectIR remains closure-free.
runtimeHandlerFromAdapter ::
  HandlerAdapter kind input output ->
  RuntimeHandlerRegistration
runtimeHandlerFromAdapter currentAdapter =
  runtimeHandler
    (handlerContractEffect currentContract)
    runtimeInputSchema
    (Just outputSchemaId)
    invokeTyped
  where
    currentContract = handlerAdapterContract currentAdapter
    inputSchemaId =
      schemaDescriptorId (handlerContractInputSchema currentContract)
    outputSchemaId =
      schemaDescriptorId (handlerContractOutputSchema currentContract)
    runtimeInputSchema =
      case someEffectRefKind (handlerContractEffect currentContract) of
        R -> Nothing
        _ -> Just inputSchemaId
    invokeTyped currentInvocation =
      case runtimeInvocationValue currentInvocation of
        Nothing
          | someEffectRefKind (handlerContractEffect currentContract) == R ->
              runDecoded ""
          | runtimeInvocationPhase currentInvocation == RuntimeInputPhase ->
              pure
                ( HandlerFailed
                    "typed HandlerAdapter requires an EffectApplication value binding"
                )
          | otherwise ->
              pure (HandlerFailed "runtime value missing")
        Just currentValue
          | runtimeValueSchema currentValue /= inputSchemaId ->
              pure (HandlerFailed "runtime value schema does not match HandlerAdapter codec")
          | otherwise ->
              runDecoded (runtimeValuePayload currentValue)
    runDecoded currentPayload =
      case codecDecode (handlerAdapterInputCodec currentAdapter) currentPayload of
        Left currentError -> pure (HandlerFailed currentError)
        Right currentInput -> do
          currentResult <- handlerAdapterFunction currentAdapter currentInput
          pure
            ( case currentResult of
                Left currentError -> HandlerFailed currentError
                Right currentOutput ->
                  case codecEncode (handlerAdapterOutputCodec currentAdapter) currentOutput of
                    Left currentError -> HandlerFailed currentError
                    Right encodedOutput ->
                      HandlerSucceeded
                        (Just (RuntimeValue outputSchemaId encodedOutput))
            )
