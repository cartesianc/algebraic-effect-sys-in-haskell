{-# LANGUAGE GADTs #-}
{-# LANGUAGE ScopedTypeVariables #-}

-- 末端句柄描述与 lower；scope 控制对象由生成句柄共享。程序只经 AST 启动，末端都在 App 载体上。
module Framework.Effect.Runtime
  ( App, Target, targetApp
  , targetName, lowerTarget, Handoff, noHandoff, scopeHandlers, cleanupTargets
  , Frame, newFrame, frameDelivery, boundarySession
  , SessionSteps, receiveSteps, requestSteps, sessionLauncher
  ) where

import Framework.Effect.Contract (Failure)
import Framework.Effect.Runtime.App (App, Launch(..), runAppWith)
import Framework.Effect.Runtime.Graph
  (RuntimeGraph, PrototypeReference(..), runtimePrototype, runtimeScopes, newOrigin, obtainSession, currentPublications)
import Framework.Effect.Runtime.Identity (Execution(..))
import Framework.Effect.Runtime.Session
import Framework.Effect.Scope
import Framework.Prototype
import Control.Concurrent (forkIOWithUnmask)
import Control.Concurrent.MVar (MVar, modifyMVar, newEmptyMVar, newMVar, putMVar, readMVar, tryReadMVar)
import Control.Exception
  (SomeAsyncException, SomeException, evaluate, finally, fromException, mask, throwIO, try, uninterruptibleMask_)
import Control.Monad (forM)
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
-- alternative 用它把选择时读到的资产交给候选，使两段读同一份值。
data Handoff environment cause = Handoff (ScopeBindings environment cause) [(String, View environment cause)]

noHandoff :: Handoff environment cause
noHandoff = Handoff [] []

-- lifelong 单元的一次执行：本 lifelong 的各会话及该单元的游标。每个会话资产在一次执行中只领取一次，
-- 第一个需要它的调用领取，其余调用（包括同一执行内并行的节点）共享同一份固定视图与伴随发布；
-- 单元内对这些资产的显式 request 发布进入对应会话。
data Frame environment cause = Frame
  { frameSessions :: [(String, (Session environment cause, Cursor))]
  , frameTaken :: MVar [(String, MVar (Either (Broken cause) (Delivery environment cause)))]
  }

newFrame :: [(String, (Session environment cause, Cursor))] -> IO (Frame environment cause)
newFrame sessions = Frame sessions <$> newMVar []

-- 进入 lifelong 时取得本边界的会话：生产步骤从进入时的交接开始，与来源分析给会话挂载的环境一致。
boundarySession :: RuntimeGraph environment cause -> NodeId -> String -> Handoff environment cause
                -> IO (Session environment cause)
boundarySession graph boundary source (Handoff given views) = obtainSession graph (Just boundary, source) given views

-- 不是本 lifelong 的会话资产时为 Nothing。没有新发布时挂起；有积压时立即领取下一条。
frameDelivery :: Frame environment cause -> String -> Maybe (IO (Either (Broken cause) (View environment cause)))
frameDelivery frame source = fmap (fmap fst) <$> frameTake frame source

frameTake :: Frame environment cause -> String -> Maybe (IO (Either (Broken cause) (Delivery environment cause)))
frameTake frame source = do
  (session, cursor) <- lookup source (frameSessions frame)
  pure $ do
    (slot, fresh) <- modifyMVar (frameTaken frame) $ \taken -> case lookup source taken of
      Just slot -> pure (taken, (slot, False))
      Nothing -> do
        slot <- newEmptyMVar
        pure ((source, slot) : taken, (slot, True))
    if not fresh then readMVar slot else mask $ \restore -> do
      outcome <- try (restore (takeDelivery session cursor))
      -- 领取被取消时也填入结果，同一 frame 的其他等待方不会悬挂。
      putMVar slot (either (Left . Left) id outcome)
      either throwIO pure outcome

frameDeliveries :: Frame environment cause -> IO [(String, Delivery environment cause)]
frameDeliveries frame = do
  taken <- readMVar (frameTaken frame)
  fmap concat $ forM taken $ \(source, slot) -> do
    filled <- tryReadMVar slot
    pure [(source, delivery) | Just (Right delivery) <- [filled]]

-- Node algebra 只 lower 末端；scope 引用已绑定在句柄中。
-- 受控结果消费在撤销入口使用登记前完成，惰性读取不会落在自动 close 之后。
-- 末端共享同一次 interpreter 运行的资产 state，使 require 可读取先前 Node 产出的资产。
-- 在 lifelong 单元的 frame 中，已领取的交付优先于交接视图，尚未领取的会话资产在第一次读取时领取。
-- 已领取交付的伴随发布作为已捕获绑定交给本次调用，交接中已经捕获的值优先（与来源分析一致）；
-- 生成期保证读取伴随资产的位置在调用前已经领取了对应会话的交付。
-- 单元内显式 request 产生的交付没有会话生产步骤，不带伴随发布。
lowerTarget :: RuntimeGraph environment cause -> NodeId -> Maybe (Frame environment cause) -> Handoff environment cause
            -> Target environment cause value -> IO (Either (Failure cause) value, Handoff environment cause)
lowerTarget graph location frame (Handoff given views) target = do
  taken <- maybe (pure []) frameDeliveries frame
  let merged = [(source, view) | (source, (view, _)) <- taken]
        ++ [entry | entry@(source, _) <- views, source `notElem` map fst taken]
      companions = [entry | (_, (_, published)) <- taken, entry@(source, _) <- published, source `notElem` map fst given]
      sinks = [(source, appendDelivery session []) | Just current <- [frame], (source, (session, _)) <- frameSessions current]
      launch = Launch (given ++ companions) merged Nothing sinks (\source -> frame >>= (`frameDelivery` source)) Nothing
  (outcome, captured, delivered) <- lowerWith graph location launch target
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
-- 每条交付带上本次生产步骤（各挂载当前一次执行）已经发布的普通资产，作为伴随发布。
-- 各步骤共用会话的 scope 使用登记，生产资源跨步骤保持；会话停止时撤销登记，资源交给退出清理。
-- 生产失败（已经过 Error 协议诊断）或原生异常使会话失败并停止，并通知运行监督；
-- 取消只结束任务，步骤内照常收尾。
-- 启动到登记在不可中断区内完成，取消不会落在任务已启动、尚未登记之间。任务继承这一屏蔽，只在生产时解除：
-- 报告失败、撤销使用登记和填写完成信号都不会被停止请求打断，stopSession 一定等得到完成信号。
sessionLauncher :: RuntimeGraph environment cause -> [(String, SessionSteps environment cause)]
                -> (Broken cause -> IO ()) -> Session environment cause -> IO ()
sessionLauncher graph steps onBroken session = uninterruptibleMask_ $ do
  finished <- newEmptyMVar
  owner <- case mounts of
    Just (mount : _) -> newOrigin graph mount >>= newScopeUser (runtimeScopes graph) . BusinessExecution
    _ -> ioError (userError ("No session steps for " ++ source ++ " at " ++ show boundary
      ++ "; regenerate with the SDK effect-codegen command"))
  thread <- forkIOWithUnmask $ \unmask -> (`finally` putMVar finished ()) $ (`finally` detachScopeUser owner) $ do
    outcome <- try (unmask (produce owner))
    case outcome of
      Left (exception :: SomeException)
        | Just (_ :: SomeAsyncException) <- fromException exception -> pure ()
        | otherwise -> broken (Left exception)
      Right problem -> broken (Right problem)
  setSessionWorker session thread finished
  where
    (boundary, source) = sessionKey session
    mounts = sessionMountsOf (runtimePrototype graph) boundary source
    produce owner = case (lookup source steps, mounts) of
      (Just (ReceiveSteps stream parser), Just [streamMount, parserMount]) -> loop $ do
        (raw, _, _) <- lowerWith graph streamMount (step owner Nothing []) stream
        case raw of
          Left problem -> pure (Left problem)
          Right text -> first <$> lowerWith graph parserMount (step owner (Just text) sink) parser
      (Just (RequestSteps request), Just [requestMount]) ->
        loop (first <$> lowerWith graph requestMount (step owner Nothing sink) request)
      _ -> ioError (userError ("Session steps differ from the prototype mounts for " ++ source
        ++ "; regenerate with the SDK effect-codegen command"))
    sink = [(source, \value -> do
      companions <- currentPublications graph (maybe [] id mounts)
      appendDelivery session companions value)]
    -- 每一步从边界交接的新副本开始，共用会话的使用登记。
    step owner input sinks = Launch (sessionBindings session) (sessionViews session) input sinks noDelivery (Just owner)
    noDelivery = const Nothing
    first (outcome, _, _) = outcome
    broken reason = breakSession session reason >> onBroken reason
    -- 逐次执行直到第一次失败；失败交回不可中断区报告。
    loop step = step >>= either pure (const (loop step))

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
