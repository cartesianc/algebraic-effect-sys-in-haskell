module MyFramework
  ( frameworkVersion
  , module MyFramework.Facade
  , module MyFramework.Handler.Adapter
  , module MyFramework.Runtime.V52
  ) where

import MyFramework.Facade
import MyFramework.Handler.Adapter
import MyFramework.Runtime.V52

frameworkVersion :: String
frameworkVersion = "0.2.0.0"
