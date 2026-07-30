module MyFramework
  ( frameworkVersion
  , module MyFramework.Frontend
  , module MyFramework.Frontend.Runtime
  ) where

import MyFramework.Frontend
import MyFramework.Frontend.Runtime

frameworkVersion :: String
frameworkVersion = "0.1.0.0"
