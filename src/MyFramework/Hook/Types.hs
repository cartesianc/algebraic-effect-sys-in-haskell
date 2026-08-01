module MyFramework.Hook.Types
  ( HangingHookDecl (..)
  , HangingCallbackDecl (..)
  , CallbackPlanEntry (..)
  , CallbackRef (..)
  , HookPhase (..)
  , HookPlan (..)
  , HookPlanEntry (..)
  , MiddlewareRef (..)
  , emptyHookPlan
  ) where

import MyFramework.Effect
import MyFramework.EffSys.Types
import MyFramework.Graph

newtype MiddlewareRef = MiddlewareRef
  { middlewareRefText :: String
  }
  deriving (Eq, Ord, Read, Show)

newtype CallbackRef = CallbackRef
  { callbackRefText :: String
  }
  deriving (Eq, Ord, Read, Show)

data HookPhase
  = HookPreStart
  | HookAround
  deriving (Eq, Ord, Read, Show)

data HangingHookDecl = HangingHookDecl
  { hangingHookRef :: MiddlewareRef
  , hangingHookScope :: EffSysRef
  , hangingHookApplication :: Maybe EffectApplication
  , hangingHookDeclarationOrder :: Int
  }
  deriving (Eq, Ord, Read, Show)

data HookPlanEntry = HookPlanEntry
  { hookPlanEntryRef :: MiddlewareRef
  , hookPlanEntryScope :: EffSysRef
  , hookPlanEntryResolvedRoot :: AstPath
  , hookPlanEntryDeclarationOrder :: Int
  , hookPlanEntryPhase :: HookPhase
  , hookPlanEntryContinuationIds :: [ContinuationId]
  , hookPlanEntryApplicationOccurrence :: Maybe ApplicationOccurrenceId
  , hookPlanEntryApplicationPath :: Maybe AstPath
  }
  deriving (Eq, Ord, Read, Show)

data HangingCallbackDecl = HangingCallbackDecl
  { hangingCallbackRef :: CallbackRef
  , hangingCallbackScope :: EffSysRef
  , hangingCallbackDeclarationOrder :: Int
  }
  deriving (Eq, Ord, Read, Show)

data CallbackPlanEntry = CallbackPlanEntry
  { callbackPlanEntryRef :: CallbackRef
  , callbackPlanEntryScope :: EffSysRef
  , callbackPlanEntryResolvedRoot :: AstPath
  , callbackPlanEntryDeclarationOrder :: Int
  , callbackPlanEntryPhase :: HookPhase
  , callbackPlanEntryContinuationIds :: [ContinuationId]
  , callbackPlanEntryScopedEffects :: [EffectKey]
  }
  deriving (Eq, Ord, Read, Show)

data HookPlan = HookPlan
  { hookPlanEntries :: [HookPlanEntry]
  , callbackPlanEntries :: [CallbackPlanEntry]
  , hookPlanDetachedGraphs :: CompiledGraphs
  }
  deriving (Eq, Ord, Read, Show)

emptyHookPlan :: HookPlan
emptyHookPlan =
  HookPlan
    { hookPlanEntries = []
    , callbackPlanEntries = []
    , hookPlanDetachedGraphs =
        CompiledGraphs
          { compiledAstGraph = AstGraph (AstPath []) [] []
          , compiledInputGraph = InputGraph [] []
          , compiledValueGraph = ValueGraph [] []
          , compiledOccurrences = []
          }
    }
