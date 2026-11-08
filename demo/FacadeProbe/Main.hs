module FacadeProbe.Main (main) where

import FacadeProbe.AST (ast)
import FacadeProbe.Effects (effects)
import FacadeProbe.Generated.Program (interpreter)

main :: IO ()
main = interpreter ast effects
