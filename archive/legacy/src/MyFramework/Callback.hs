module MyFramework.Callback
  ( PipelinePatch (..)
  , PipelinePatchError (..)
  , PipelinePatchId (..)
  , PipelineTargetLifecycle (..)
  ) where

import MyFramework.Effect
import MyFramework.Graph

newtype PipelinePatchId = PipelinePatchId
  { pipelinePatchIdText :: String
  }
  deriving (Eq, Ord, Read, Show)

data PipelinePatch
  = InsertInput InputNodeId SomeEffectRef
  | ReplaceInput InputNodeId SomeEffectRef
  | RemoveInput InputNodeId
  | RedirectInput InputNodeId InputNodeId
  deriving (Eq, Ord, Read, Show)

data PipelineTargetLifecycle
  = PipelineTargetDormant
  | PipelineTargetStarted
  | PipelineTargetCompleted
  deriving (Eq, Ord, Read, Show)

data PipelinePatchError
  = PipelinePatchTargetMissing InputNodeId
  | PipelinePatchEffectMissing EffectKey
  | PipelinePatchEffectKindMismatch EffectKey EffectKind EffectKind
  | PipelinePatchEffectOutsideScope EffectKey AstPath
  | PipelinePatchScopeViolation InputNodeId AstPath
  | PipelinePatchTargetAlreadyStarted InputNodeId PipelineTargetLifecycle
  | PipelinePatchInputArityViolation InputNodeId Int
  | PipelinePatchCycle [InputNodeId]
  | PipelinePatchRedirectSourceMissing InputNodeId
  | PipelinePatchConcurrentConflict InputNodeId PipelinePatchId
  deriving (Eq, Ord, Read, Show)
