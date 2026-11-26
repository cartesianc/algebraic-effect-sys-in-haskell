{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE ExplicitForAll #-}
{-# LANGUAGE PolyKinds #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE UndecidableInstances #-}

-- 资产固定形式的类型层部分：表示类型的语义规则由 GHC 求解，不按源码拼写比对。
-- 表示类型是一阶、单态、有限的积：恰好一个构造器，至少一个字段，没有严格标记；
-- 字段是基础字段（String、[String]、Int、Integer、Double、Bool，类型同义词按展开后的类型判断）
-- 或 Types.hs 的另一个表示类型；沿字段的引用不回到路径上已有的类型（没有出口的递归只有无限值或 ⊥）。
-- gen 在 Types.hs 通过语法检查后，于内存模块为每个本地类型派生 Generic 并断言 AssetForm；
-- 违反时 GHC 报告这里的 TypeError。文件形式（import、deriving、导出列表、声明种类）仍由 gen 在语法树上检查。
module Framework.Language.AssetForm (AssetForm, assetForm) where

import Data.Kind (Constraint, Type)
import GHC.Generics
import GHC.TypeLits (ErrorMessage(..), TypeError)

-- locals：Types.hs 定义的全部表示类型；t：被检查的表示类型。
type AssetForm (locals :: [Type]) (t :: Type) = Representation locals '[t] t (Rep t)

-- 断言的值本身没有用处，只为让约束出现在类型检查中。
assetForm :: forall (locals :: [Type]) (t :: Type). AssetForm locals t => ()
assetForm = ()

-- path 是从被检查的根类型到 t 的字段路径（最近的在前）。
type family Representation (locals :: [Type]) (path :: [Type]) (t :: Type) (rep :: Type -> Type) :: Constraint where
  Representation locals path t (D1 meta (C1 constructor fields)) = Fields locals path t fields
  Representation locals path t (D1 meta V1) =
    TypeError ('ShowType t ':<>: 'Text " has no constructor; an asset has exactly one")
  Representation locals path t (D1 meta (left :+: right)) =
    TypeError ('ShowType t ':<>: 'Text " has several constructors; alternatives are decided by effects, not by sum types")

type family Fields (locals :: [Type]) (path :: [Type]) (t :: Type) (fields :: Type -> Type) :: Constraint where
  Fields locals path t U1 =
    TypeError ('ShowType t ':<>: 'Text " has no field; an asset is built from base fields")
  Fields locals path t (left :*: right) = (Fields locals path t left, Fields locals path t right)
  Fields locals path t (S1 ('MetaSel name unpacked 'NoSourceStrictness decided) (Rec0 field)) =
    Field locals path t field (Elem field path) (Elem field locals)
  Fields locals path t (S1 selector (Rec0 field)) =
    TypeError ('ShowType t ':<>: 'Text " marks its field " ':<>: 'ShowType field
      ':<>: 'Text " strict or lazy; asset fields carry no strictness marks")

type family Field (locals :: [Type]) (path :: [Type]) (t :: Type) (field :: Type) (recursive :: Bool) (local :: Bool) :: Constraint where
  Field locals path t field 'True local =
    TypeError (Route path ('ShowType field)
      ':<>: 'Text " refer back to themselves through their fields; an asset is a finite value, so representation types are not recursive")
  Field locals path t field 'False 'True = Representation locals (field ': path) field (Rep field)
  Field locals path t field 'False 'False = Base t field

type family Base (t :: Type) (field :: Type) :: Constraint where
  Base t [Char] = ()
  Base t [[Char]] = ()
  Base t Int = ()
  Base t Integer = ()
  Base t Double = ()
  Base t Bool = ()
  Base t field =
    TypeError ('ShowType t ':<>: 'Text " has field type " ':<>: 'ShowType field
      ':<>: 'Text "; fields are String, [String], Int, Integer, Double, Bool or types of this module")

type family Elem (x :: Type) (xs :: [Type]) :: Bool where
  Elem x '[] = 'False
  Elem x (x ': rest) = 'True
  Elem x (y ': rest) = Elem x rest

-- 路径从根类型写到回指的字段，例如 Loop -> Mutual -> Loop。
type family Route (path :: [Type]) (shown :: ErrorMessage) :: ErrorMessage where
  Route '[] shown = shown
  Route (x ': rest) shown = Route rest ('ShowType x ':<>: 'Text " -> " ':<>: shown)
