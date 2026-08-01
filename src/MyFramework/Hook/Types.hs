module MyFramework.Hook.Types
  ( HangingHookDecl (..)
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

data HookPhase
  = HookPreStart
  | HookAround
  deriving (Eq, Ord, Read, Show)

data HangingHookDecl = HangingHookDecl
  { hangingHookRef :: MiddlewareRef
  , hangingHookScope :: EffSysRef
  , hangingHookApplication :: Maybe EffectApplication
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

data HookPlan = HookPlan
  { hookPlanEntries :: [HookPlanEntry]
  , hookPlanDetachedGraphs :: CompiledGraphs
  }
  deriving (Eq, Ord, Read, Show)

emptyHookPlan :: HookPlan
emptyHookPlan =
  HookPlan
    { hookPlanEntries = []
    , hookPlanDetachedGraphs =
        CompiledGraphs
          { compiledAstGraph = AstGraph (AstPath []) [] []
          , compiledInputGraph = InputGraph [] []
          , compiledValueGraph = ValueGraph [] []
          , compiledOccurrences = []
          }
    }
