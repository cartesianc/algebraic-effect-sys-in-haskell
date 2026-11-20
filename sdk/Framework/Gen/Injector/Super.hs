-- Root 的 superhandler 在生成期的装配：按挂载的 Middleware 列表与捕获类别预选要调用的 Middleware。
-- Booter 给出每个挂载覆盖的列表，Injector 给出绑定的捕获类别；这里只求二者的静态交集，
-- Emit.Handlers 把结果写成 Captures 实例，运行时不再按 intercept 筛选。
module Framework.Gen.Injector.Super (captureKindOf, superSelections) where

import Data.List (nub)
import Framework.Gen.Plan
import Framework.Language.Registration (EffectKind)

-- 某类别是否有 Middleware 拦截。没有时调用点不经捕获，Root 直接执行 action。
-- 进入、rawoutput、rawemit 与 raise 用当前绑定的类别；rawinput 用被读取的那次原子调用的类别。
captureKindOf :: [EffectDeclaration] -> EffectKind -> Maybe EffectKind
captureKindOf declarations kind
  | any (elem kind . declarationIntercept) declarations = Just kind
  | otherwise = Nothing

-- 每个用到的列表 × 每个被拦截的类别，按列表的注册顺序选出拦截该类别的 Middleware。
-- 空选择同样登记：入口对列表多态，约束要求每个类别都有实例，空选择的实例直接执行 action。
superSelections :: Unit -> [SuperSelection]
superSelections unit =
  [ SuperSelection hooks kind
      [selected | selected <- hooks, Just kinds <- [lookup selected (unitMiddleware unit)], kind `elem` kinds]
  | hooks <- hookLists, kind <- capturedKinds ]
  where
    capturedKinds = nub (concatMap snd (unitMiddleware unit))
    -- 入口实际会以哪些列表实例化：空列表（未覆盖的挂载与 Error 回调），以及各挂载与会话步骤的列表。
    hookLists = nub ([] : [mountHooks unit (mountNode mount) | mount <- assemblyMounts (unitAssembly unit)]
      ++ [mountHooks unit (mountNode mounted) | entry <- unitSessionEntries unit, mounted <- sessionMounts entry])
    sessionMounts (ReceiveEntry _ source parser) = [source, parser]
    sessionMounts (DeriveEntry _ parser) = [parser]
