module MyFramework.Self.ControlTrace
  ( ControlTrace
  , ControlTraceError (..)
  , compileControlTrace
  , controlNodeCatalog
  , controlTraceConstructorWitness
  , controlTraceConstructorChecks
  , controlTraceLines
  , renderControlTraceJson
  ) where

import Data.Char
  ( ord )
import Data.List
  ( intercalate )
import Numeric
  ( showHex )

import MyFramework.Frontend
import MyFramework.Self.Model
  ( SelfModel
  , selfModelProgram
  )

newtype ControlTrace = ControlTrace
  { controlTraceLines :: [String]
  }
  deriving (Eq, Ord, Read, Show)

newtype ControlTraceError
  = ControlTraceResolutionFailed [FrontendError]
  deriving (Eq, Show)

controlNodeCatalog :: [String]
controlNodeCatalog =
  [ "Effect"
  , "Chain"
  , "Parallel"
  , "Fallback"
  , "Race"
  ]

compileControlTrace :: SelfModel -> Either ControlTraceError ControlTrace
compileControlTrace currentModel =
  case resolveProgram (selfModelProgram currentModel) of
    Left currentErrors ->
      Left (ControlTraceResolutionFailed currentErrors)
    Right currentRoot ->
      Right (ControlTrace (renderNode currentRoot))

renderNode :: ResolvedNode -> [String]
renderNode currentNode =
  currentLine : concatMap renderNode currentChildren
  where
    currentLine =
      intercalate
        "|"
        [ renderOccurrence currentNode
        , nodeTag currentNode
        , nodePayload currentNode
        ]
    currentChildren =
      case currentNode of
        ResolvedControl _ _ _ children ->
          children
        ResolvedEffectLeaf {} ->
          []

renderOccurrence :: ResolvedNode -> String
renderOccurrence currentNode =
  case currentNode of
    ResolvedControl currentPath _ _ _ ->
      renderPath currentPath
    ResolvedEffectLeaf currentPath _ _ ->
      renderPath currentPath

renderPath :: OccurrencePath -> String
renderPath =
  intercalate "/" . occurrencePathSegments

nodeTag :: ResolvedNode -> String
nodeTag currentNode =
  case currentNode of
    ResolvedEffectLeaf {} ->
      "Effect"
    ResolvedControl _ _ currentKind _ ->
      controlKindTag currentKind

controlKindTag :: ControlKind -> String
controlKindTag currentKind =
  case currentKind of
    ControlChain -> "Chain"
    ControlParallel -> "Parallel"
    ControlFallback -> "Fallback"
    ControlRace -> "Race"

nodePayload :: ResolvedNode -> String
nodePayload currentNode =
  case currentNode of
    ResolvedEffectLeaf _ currentAddress currentEffect ->
      show currentAddress
        ++ ";type="
        ++ show (effectDeclType currentEffect)
    ResolvedControl _ currentModule _ currentChildren ->
      "module="
        ++ moduleNameText currentModule
        ++ ";children="
        ++ show (length currentChildren)

controlTraceConstructorWitness :: Bool
controlTraceConstructorWitness =
  map fst controlTraceConstructorChecks == controlNodeCatalog
    && all snd controlTraceConstructorChecks

controlTraceConstructorChecks :: [(String, Bool)]
controlTraceConstructorChecks =
  [ ("Effect", nodeTag sampleEffect == "Effect")
  , ("Chain", controlKindTag ControlChain == "Chain")
  , ("Parallel", controlKindTag ControlParallel == "Parallel")
  , ("Fallback", controlKindTag ControlFallback == "Fallback")
  , ("Race", controlKindTag ControlRace == "Race")
  ]

sampleEffect :: ResolvedNode
sampleEffect =
  ResolvedEffectLeaf
    (OccurrencePath ["sample", "effect"])
    (EffectAddress (ModuleName "sample") (LocalKey "effect"))
    EffectDecl
      { effectDeclType = EffectE
      , effectDeclInput = Nothing
      , effectDeclParams = []
      }

renderControlTraceJson :: ControlTrace -> String
renderControlTraceJson currentTrace =
  "["
    ++ intercalate
      ","
      (map jsonString (controlTraceLines currentTrace))
    ++ "]"

jsonString :: String -> String
jsonString currentValue =
  "\"" ++ concatMap escapeJsonChar currentValue ++ "\""

escapeJsonChar :: Char -> String
escapeJsonChar currentChar =
  case currentChar of
    '"' -> "\\\""
    '\\' -> "\\\\"
    '\b' -> "\\b"
    '\f' -> "\\f"
    '\n' -> "\\n"
    '\r' -> "\\r"
    '\t' -> "\\t"
    _
      | ord currentChar < 0x20 ->
          "\\u"
            ++ padLeft 4 '0' (showHex (ord currentChar) "")
      | otherwise ->
          [currentChar]

padLeft :: Int -> Char -> String -> String
padLeft currentWidth currentFill currentValue =
  replicate (max 0 (currentWidth - length currentValue)) currentFill
    ++ currentValue
