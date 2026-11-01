{-# LANGUAGE DeriveFunctor #-}
{-# LANGUAGE DeriveTraversable #-}

-- 持续资产的读取视图：从来源首次成功发布到本次交付位置的有限、不可变序列。
-- 相等值的两次发布是两个条目；后台新增不改写已经取得的视图。
module Framework.Effect.History
  ( History, historyFromList, historyEntries, latest, historySize, currentHistory
  ) where

import Data.Foldable (toList)
import Data.Sequence (Seq, ViewR(..), viewr)
import qualified Data.Sequence as Seq

newtype History value = History (Seq value)
  deriving (Eq, Show, Functor, Foldable, Traversable)

-- 视图只由 SDK 构造；业务代码按条目读取，不能伪造历史。
historyFromList :: [value] -> History value
historyFromList = History . Seq.fromList

historyEntries :: History value -> [value]
historyEntries (History entries) = toList entries

-- 本次交付位置上的最新条目；视图为空时没有最新值。
latest :: History value -> Maybe value
latest (History entries) = case viewr entries of
  EmptyR -> Nothing
  _ :> value -> Just value

historySize :: History value -> Int
historySize (History entries) = Seq.length entries

-- lifelong 外读取有 request 的持续资产时按普通 require 取得一个值，呈现为只含一条的视图。
currentHistory :: value -> History value
currentHistory = History . Seq.singleton
