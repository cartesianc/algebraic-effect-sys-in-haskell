{-# LANGUAGE GADTs #-}

-- 末端句柄描述与 lower；scope 控制对象由生成句柄共享。程序只经 AST 启动，末端都在 App 载体上。
module Framework.Effect.Runtime
  ( App, Target, targetApp
  , targetName, lowerTarget, Handoff, noHandoff, RunStore, newRunStore, configureTargets, cleanupTargets
  ) where

import Framework.Effect.Contract (Failure)
import Framework.Effect.Runtime.App (App, RunStore, newRunStore, runAppWith)
import Framework.Effect.Scope
import Control.Exception (SomeException, evaluate)
import Data.List (nubBy)

-- 一个生成程序的 Node 共用同一存储契约。
data Target environment cause value where
  AppTarget :: (Show cause, Show value) => String -> environment -> Scopes environment cause -> App environment cause value
            -> Target environment cause value

targetName :: Target environment cause value -> String
targetName (AppTarget selected _ _ _) = selected

-- 生成区只登记句柄，不组合上游操作。
targetApp :: (Show cause, Show value) => String -> environment -> Scopes environment cause -> App environment cause value
          -> Target environment cause value
targetApp = AppTarget

-- 交给下一段调用的已捕获绑定（只含无 scope 归属的资产）；内容不对外公开。
-- alternative 用它把选择时读到的资产交给候选，使两段读同一份值。
newtype Handoff environment cause = Handoff (ScopeBindings environment cause)

noHandoff :: Handoff environment cause
noHandoff = Handoff []

-- Node algebra 只 lower 末端；scope 引用已绑定在句柄中。
-- 受控结果消费在使用闭包退出前完成，惰性读取不会落在自动 close 之后。
-- 末端共享同一次 interpreter 运行的资产 state，使 require 可读取先前 Node 产出的资产。
lowerTarget :: RunStore environment cause -> Handoff environment cause -> Target environment cause value
            -> IO (Either (Failure cause) value, Handoff environment cause)
lowerTarget store (Handoff given) (AppTarget _ environment scopes action) = do
  (outcome, captured) <- runAppWith (\value -> evaluate (foldr seq () (show value))) store given scopes environment action
  pure (outcome, Handoff captured)

-- 各末端通常捕获同批 scope；按控制对象身份去重，不按业务名称合并独立批次。
scopeHandlers :: [Target environment cause value] -> Scopes environment cause
scopeHandlers entries = nubBy sameHandler (concatMap targetScopes entries)
  where
    targetScopes :: Target environment cause value -> Scopes environment cause
    targetScopes (AppTarget _ _ scopes _) = scopes
    sameHandler left right = scopeInstances left == scopeInstances right

-- 在第一次业务调用前安装同一 ScopeTree 的祖先投影，供回收协调和 Error 导航读取。
configureTargets :: [(String, [String])] -> [Target environment cause value] -> IO ()
configureTargets relations = configureScopeRelations relations . scopeHandlers

cleanupTargets :: [Target environment cause value] -> IO [(Maybe SomeException, Failure cause)]
cleanupTargets = cleanupScopes . scopeHandlers
