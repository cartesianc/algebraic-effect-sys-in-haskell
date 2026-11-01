{-# LANGUAGE ExistentialQuantification #-}

-- 持续资产的读取视图：从来源首次成功发布到本次交付位置的有限、不可变序列。
-- 相等值的两次发布是两个条目；后台新增不改写已经取得的视图。
module Framework.Effect.History
  ( History, historyFromList, historyView, historyEntries, latest, historySize, currentHistory
  ) where

import Data.Foldable (toList)
import Data.Sequence (Seq, ViewR(..), viewr)
import qualified Data.Sequence as Seq

-- 视图共享会话里已有的发布序列，只在取用条目时投影出业务值：
-- 取得视图、latest 与 historySize 不随历史长度增长，historyEntries 才遍历全部条目。
data History value = forall source. History (Seq source) (source -> value)

instance Functor History where
  fmap transform (History entries project) = History entries (transform . project)

instance Foldable History where
  foldr step initial (History entries project) = foldr (step . project) initial entries
  length = historySize
  null history = historySize history == 0

instance Traversable History where
  traverse visit (History entries project) = (`History` id) <$> traverse (visit . project) entries

instance Eq value => Eq (History value) where
  left == right = historyEntries left == historyEntries right

instance Show value => Show (History value) where
  showsPrec precedence history = showParen (precedence > 10) $
    showString "historyFromList " . showsPrec 11 (historyEntries history)

-- 视图只由 SDK 构造；业务代码按条目读取，不能伪造历史。
historyFromList :: [value] -> History value
historyFromList values = History (Seq.fromList values) id

-- SDK 内部：以会话中的发布序列构造视图，投影在读取条目时进行。
historyView :: Seq source -> (source -> value) -> History value
historyView = History

historyEntries :: History value -> [value]
historyEntries (History entries project) = map project (toList entries)

-- 本次交付位置上的最新条目；视图为空时没有最新值。
latest :: History value -> Maybe value
latest (History entries project) = case viewr entries of
  EmptyR -> Nothing
  _ :> entry -> Just (project entry)

historySize :: History value -> Int
historySize (History entries _) = Seq.length entries

-- lifelong 外读取有 request 的持续资产时按普通 require 取得一个值，呈现为只含一条的视图。
currentHistory :: value -> History value
currentHistory value = History (Seq.singleton value) id
