module MyFramework.Hook
  ( HangingHookDecl (..)
  , HookError (..)
  , HookPhase (..)
  , HookPlan (..)
  , HookPlanEntry (..)
  , MiddlewareRef (..)
  , compileHookPlan
  , emptyHookPlan
  ) where

import Data.List
  ( group
  , nub
  , sort
  )

import MyFramework.Effect
import MyFramework.EffSys
import MyFramework.Graph
import MyFramework.Hook.Types
import MyFramework.Runtime.V52
  ( ContinuationPlan
  , ContinuationPlanError
  , compileContinuationPlan
  )
import MyFramework.TrustBase.Digest
  ( sha256
  )

data HookError
  = HookMiddlewareDuplicate [MiddlewareRef]
  | HookScopeError MiddlewareRef EffSysError
  | HookApplicationGraphError MiddlewareRef GraphError
  | HookContinuationError ContinuationPlanError
  deriving (Eq, Ord, Read, Show)

compileHookPlan ::
  EffSysRegistryId ->
  EffectRegistry ->
  TransformRegistry ->
  CompiledGraphs ->
  ContinuationPlan ->
  [HangingHookDecl] ->
  Either [HookError] HookPlan
compileHookPlan currentRegistry currentEffects currentTransforms currentGraphs currentContinuation currentDecls
  | not (null duplicateErrors) = Left duplicateErrors
  | not (null scopeErrors) = Left scopeErrors
  | not (null graphErrors) = Left graphErrors
  | otherwise =
      case compileContinuationPlan detachedGraphs of
        Left currentErrors ->
          Left (map HookContinuationError currentErrors)
        Right _ ->
          Right
            HookPlan
              { hookPlanEntries = currentEntries
              , hookPlanDetachedGraphs = detachedGraphs
              }
  where
    duplicateRefs = duplicates (map hangingHookRef currentDecls)
    duplicateErrors =
      [HookMiddlewareDuplicate duplicateRefs | not (null duplicateRefs)]
    indexedDecls = zip [0 ..] currentDecls
    scopedResults =
      [ ( currentOrder
        , currentDecl
        , buildEffSysIR
            currentRegistry
            currentEffects
            currentTransforms
            currentGraphs
            currentContinuation
            (hangingHookScope currentDecl)
        )
      | (currentOrder, currentDecl) <- indexedDecls
      ]
    scopeErrors =
      [ HookScopeError (hangingHookRef currentDecl) currentError
      | (_, currentDecl, Left currentErrors) <- scopedResults
      , currentError <- currentErrors
      ]
    compiledApplications =
      [ ( currentOrder
        , currentDecl
        , compileDetached currentOrder currentDecl currentApplication
        )
      | (currentOrder, currentDecl) <- indexedDecls
      , Just currentApplication <- [hangingHookApplication currentDecl]
      ]
    graphErrors =
      [ HookApplicationGraphError (hangingHookRef currentDecl) currentError
      | (_, currentDecl, Left currentErrors) <- compiledApplications
      , currentError <- currentErrors
      ]
    detachedGraphs =
      mergeGraphs
        [ currentDetached
        | (_, _, Right currentDetached) <- compiledApplications
        ]
    detachedIndex =
      [ (currentOrder, head (compiledOccurrences currentDetached))
      | (currentOrder, _, Right currentDetached) <- compiledApplications
      , not (null (compiledOccurrences currentDetached))
      ]
    currentEntries =
      [ HookPlanEntry
          { hookPlanEntryRef = hangingHookRef currentDecl
          , hookPlanEntryScope = hangingHookScope currentDecl
          , hookPlanEntryResolvedRoot = effSysIrResolvedRoot currentScope
          , hookPlanEntryDeclarationOrder = currentOrder
          , hookPlanEntryPhase = HookPreStart
          , hookPlanEntryContinuationIds =
              map inputEdgeContinuation
                (inputGraphEdges (effSysIrInputGraph currentScope))
          , hookPlanEntryApplicationOccurrence =
              applicationOccurrenceId <$> lookup currentOrder detachedIndex
          , hookPlanEntryApplicationPath =
              applicationOccurrencePath <$> lookup currentOrder detachedIndex
          }
      | (currentOrder, currentDecl, Right currentScope) <- scopedResults
      ]
    compileDetached currentOrder currentDecl currentApplication =
      compileGraphs
        currentEffects
        currentTransforms
        ( AstPlanApplication
            ( AstNodeKey
                ( "hanging/"
                    ++ show currentOrder
                    ++ "/"
                    ++ middlewareRefText (hangingHookRef currentDecl)
                    ++ "/"
                    ++ sha256 (show currentApplication)
                )
            )
            currentApplication
        )

mergeGraphs :: [CompiledGraphs] -> CompiledGraphs
mergeGraphs currentGraphs =
  CompiledGraphs
    { compiledAstGraph = AstGraph (AstPath []) [] []
    , compiledInputGraph =
        InputGraph
          { inputGraphNodes = nub (concatMap (inputGraphNodes . compiledInputGraph) currentGraphs)
          , inputGraphEdges = nub (concatMap (inputGraphEdges . compiledInputGraph) currentGraphs)
          }
    , compiledValueGraph =
        ValueGraph
          { valueGraphNodes = nub (concatMap (valueGraphNodes . compiledValueGraph) currentGraphs)
          , valueGraphEdges = nub (concatMap (valueGraphEdges . compiledValueGraph) currentGraphs)
          }
    , compiledOccurrences = nub (concatMap compiledOccurrences currentGraphs)
    }

duplicates :: Ord item => [item] -> [item]
duplicates currentItems =
  [ head currentGroup
  | currentGroup <- group (sort currentItems)
  , length currentGroup > 1
  ]
