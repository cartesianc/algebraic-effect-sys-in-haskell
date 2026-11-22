-- 剧本中执行位置的整数坐标。gen 写下的 NodeId（AST 挂载、选择、会话步骤与 lifelong 单元的路径）
-- 在建运行索引时补全前缀、按字典序排列：这正是位置树的先序遍历。坐标编号是先序序号，
-- 并记下子树中最后一个位置的序号，于是“在某个位置的子树里”是一次区间比较，不再比较路径前缀。
--
-- 一个坐标恰对应一个执行位置，因此对应一个 effect；同一 effect 出现在几个位置就有几个坐标，
-- 这份一对多关系由 gen 写进原型的来源与会话挂载，运行时只查表，不从坐标反推 effect。
module Framework.Prototype.Coordinate
  ( Coord, coordNumber, coordPath, coordinates, within
  ) where

import qualified Data.Map.Strict as Map
import Data.List (inits, isPrefixOf)
import Data.Ord (comparing)
import qualified Data.Set as Set
import Framework.Prototype.Types (NodeId)

data Coord = Coord
  { coordNumber :: !Int
  -- 子树中最后一个位置的先序序号（叶子为自身）。
  , coordLast :: !Int
  -- 原路径，只用于诊断与展示。
  , coordPath :: NodeId
  }

-- 相等与排序只比较编号。
instance Eq Coord where
  left == right = coordNumber left == coordNumber right

instance Ord Coord where
  compare = comparing coordNumber

-- 展示为原路径，诊断文本与改用坐标之前一致。
instance Show Coord where
  showsPrec precedence = showsPrec precedence . coordPath

-- position `within` subtree：position 是 subtree 自身或它的后代。
within :: Coord -> Coord -> Bool
within position subtree = coordNumber subtree <= coordNumber position && coordNumber position <= coordLast subtree

-- 给全部位置编号；前缀闭包使每个位置的祖先也有坐标。路径的字典序就是先序。
coordinates :: [NodeId] -> Map.Map NodeId Coord
coordinates nodes = Map.fromList
  [ (path, Coord number (number + descendants path rest) path)
  | (number, path, rest) <- zip3 [0 ..] ordered (drop 1 (tailsOf ordered)) ]
  where
    ordered = Set.toAscList (Set.fromList (concatMap inits nodes))
    tailsOf items = items : case items of
      [] -> []
      _ : remaining -> tailsOf remaining
    -- 先序中，后代紧跟在自身之后连续出现。
    descendants path rest = length (takeWhile (path `isPrefixOf`) rest)
