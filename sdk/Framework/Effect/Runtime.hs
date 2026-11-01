{-# LANGUAGE GADTs #-}
{-# LANGUAGE ScopedTypeVariables #-}

-- 末端句柄描述与 lower；scope 控制对象由生成句柄共享。程序只经 AST 启动，末端都在 App 载体上。
module Framework.Effect.Runtime
  ( App, Target, targetApp
  , targetName, lowerTarget, Handoff, noHandoff, deliveredHandoff, scopeHandlers, cleanupTargets
  , SessionSteps, receiveSteps, requestSteps, sessionLauncher
  ) where

import Framework.Effect.Contract (Failure)
import Framework.Effect.Runtime.App (App, Launch(..), runAppWith)
import Framework.Effect.Runtime.Graph (RuntimeGraph, PrototypeReference(..), runtimePrototype)
import Framework.Effect.Runtime.Session
import Framework.Effect.Scope
import Framework.Prototype
import Control.Concurrent (forkIOWithUnmask)
import Control.Concurrent.MVar (newEmptyMVar, putMVar)
import Control.Exception (AsyncException, SomeException, evaluate, fromException, try)
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

-- 交给下一段调用的已捕获绑定（只含无 scope 归属的资产）与持续资产的交付视图；内容不对外公开。
-- alternative 用它把选择时读到的资产交给候选，使两段读同一份值；lifelong 单元用它带入本次交付。
data Handoff environment cause = Handoff (ScopeBindings environment cause) [(String, View environment cause)]

noHandoff :: Handoff environment cause
noHandoff = Handoff [] []

-- 一次单元执行领取的交付：同一执行的各节点共享这份固定视图。
deliveredHandoff :: [(String, View environment cause)] -> Handoff environment cause
deliveredHandoff = Handoff []

-- Node algebra 只 lower 末端；scope 引用已绑定在句柄中。
-- 受控结果消费在撤销入口使用登记前完成，惰性读取不会落在自动 close 之后。
-- 末端共享同一次 interpreter 运行的资产 state，使 require 可读取先前 Node 产出的资产。
lowerTarget :: RuntimeGraph environment cause -> NodeId -> Handoff environment cause -> Target environment cause value
            -> IO (Either (Failure cause) value, Handoff environment cause)
lowerTarget graph location (Handoff given views) target = do
  (outcome, captured, delivered) <- lowerWith graph location (Launch given views Nothing Nothing) target
  pure (outcome, Handoff captured delivered)

lowerWith :: RuntimeGraph environment cause -> NodeId -> Launch environment cause -> Target environment cause value
          -> IO (Either (Failure cause) value, ScopeBindings environment cause, [(String, View environment cause)])
lowerWith graph location launch (AppTarget _ environment _ action) =
  runAppWith (\value -> evaluate (foldr seq () (show value))) graph location launch environment action

-- 各末端通常捕获同批 scope；按控制对象身份去重，不按业务名称合并独立批次。
scopeHandlers :: [Target environment cause value] -> Scopes environment cause
scopeHandlers entries = nubBy sameHandler (concatMap targetScopes entries)
  where
    targetScopes :: Target environment cause value -> Scopes environment cause
    targetScopes (AppTarget _ _ scopes _) = scopes
    sameHandler left right = scopeInstances left == scopeInstances right

cleanupTargets :: [Target environment cause value] -> IO [(Maybe SomeException, Failure cause)]
cleanupTargets = cleanupScopes . scopeHandlers

-- 生成区按资产登记的生产步骤：Receive 为 Stream 单步与解析器，RepeatRequest 为 request。
-- 解析器与 request 的包装各自发布一次资产；会话不再次发布返回值。
data SessionSteps environment cause
  = ReceiveSteps (Target environment cause String) (Target environment cause ())
  | RequestSteps (Target environment cause ())

receiveSteps :: Target environment cause String -> Target environment cause () -> SessionSteps environment cause
receiveSteps = ReceiveSteps

requestSteps :: Target environment cause () -> SessionSteps environment cause
requestSteps = RequestSteps

-- 为新会话启动生产任务：按原型找到该边界的会话挂载，逐次执行生产步骤，把发布写入会话历史。
-- 生产失败（已经过 Error 协议诊断）或原生异常使会话失败并停止；取消只结束任务，步骤内照常收尾。
sessionLauncher :: RuntimeGraph environment cause -> [(String, SessionSteps environment cause)]
                -> Session environment cause -> IO ()
sessionLauncher graph steps session = do
  finished <- newEmptyMVar
  thread <- forkIOWithUnmask $ \unmask -> do
    outcome <- try (unmask produce)
    case outcome of
      Left (exception :: SomeException)
        | Just (_ :: AsyncException) <- fromException exception -> pure ()
        | otherwise -> breakSession session (Left exception)
      Right () -> pure ()
    putMVar finished ()
  setSessionWorker session thread finished
  where
    (boundary, source) = sessionKey session
    produce = case (lookup source steps, sessionMountsOf (runtimePrototype graph) boundary source) of
      (Just (ReceiveSteps stream parser), Just [streamMount, parserMount]) -> loop $ do
        (raw, _, _) <- lowerWith graph streamMount (Launch [] [] Nothing Nothing) stream
        case raw of
          Left problem -> pure (Left problem)
          Right text -> first <$> lowerWith graph parserMount (Launch [] [] (Just text) sink) parser
      (Just (RequestSteps request), Just [requestMount]) ->
        loop (first <$> lowerWith graph requestMount (Launch [] [] Nothing sink) request)
      _ -> ioError (userError ("No session steps for " ++ source ++ " at " ++ show boundary
        ++ "; regenerate with the SDK effect-codegen command"))
    sink = Just (source, appendDelivery session)
    first (outcome, _, _) = outcome
    loop step = do
      outcome <- step
      case outcome of
        Left problem -> breakSession session (Right problem)
        Right () -> loop step

-- 会话挂载只来自同一份原型：lifelong 边界的会话，或 interpreter 托管的会话；原型按资产名记录。
sessionMountsOf :: PrototypeReference -> Maybe NodeId -> String -> Maybe [NodeId]
sessionMountsOf (PrototypeReference prototype) boundary source =
  case [sessionMounts session | session <- candidates
       , Just (sessionAsset session) == lookup source produced] of
    [mounts] -> Just mounts
    _ -> Nothing
  where
    produced = [(effectName effect, contractType) | effect <- protoEffects prototype
      , Just contractType <- [effectProduces effect]]
    candidates = case boundary of
      Nothing -> protoSessions prototype
      Just lifelong -> [session | (identifier, described) <- workflowLifelongs (protoWorkflow prototype)
        , identifier == lifelong, session <- lifelongSessions described]
