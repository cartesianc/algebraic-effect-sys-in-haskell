module MyFramework
  ( frameworkVersion
  , module MyFramework.Facade
  , module MyFramework.Handler.Adapter
  ) where

import MyFramework.Facade
import MyFramework.Handler.Adapter

frameworkVersion :: String
frameworkVersion = "0.2.0.0"
