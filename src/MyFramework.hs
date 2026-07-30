module MyFramework
  ( frameworkVersion
  , module MyFramework.Facade
  , module MyFramework.Frontend.Runtime
  ) where

import MyFramework.Facade
import MyFramework.Frontend.Runtime

frameworkVersion :: String
frameworkVersion = "0.1.0.0"
