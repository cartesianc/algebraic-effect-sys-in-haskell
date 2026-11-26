{-# OPTIONS_GHC -fexpose-all-unfoldings -fspecialise-aggressively #-}
{-# LANGUAGE GADTs #-}

-- 生成的执行闭包与末端句柄。gen 在 Generated/Program.hs 写出组合好的 workflow（顺序、并行、选择、来源运行）、
-- 发布后的订阅回调表与 lifelong 外的静态运行；Runtime.Execution 只执行它们，不在运行期遍历原型编排。
-- Target 只保存末端句柄与共享 scope；Handoff 交接捕获值与持续资产的视图。
module Framework.Runtime
  ( App, Target, targetApp
  , targetName, lowerTarget, lowerWith, Handoff(..), noHandoff, handoffWithoutResources, scopeHandlers, cleanupTargets
  , Compiled(..), Closure(..), StreamSource(..), Reaction(..), Response(..), Tracking(..)
  ) where

import Framework.Language.Handler (Failure)
import Framework.Runtime.App (App, Launch(..), StreamPort(..), runAppWith)
import Framework.Runtime.Graph (RuntimeGraph, Place, Tracking(..), runtimeScopes)
import Framework.Runtime.Identity (Origin(..), executionOrigin)
import Framework.Runtime.Frame (ExecutionFrame, captureFrameDeliveries)
import Framework.Runtime.Binding (Binding(..), readBindingOwner)
import Framework.Runtime.Retention (Retention, keepBindings)
import Framework.Runtime.Delivery (View, lastBinding)
import Framework.Runtime.Scope
import Framework.Prototype.Coordinate (Coord)
import Framework.Prototype.Slot (Slot(..))
import Framework.Prototype.Types (NodeId)
import Control.DeepSeq (NFData, rnf)
import Control.Exception (SomeException, evaluate)
import Control.Monad (filterM, when)
import Data.List (nubBy)
import Data.Maybe (isNothing, mapMaybe)

-- 末端句柄与调用交接 -----------------------------------------------------------

-- 一个生成程序的 Node 共用同一存储契约。
data Target environment cause value where
  AppTarget :: (Show cause, Show value, NFData value) => String -> environment -> Scopes environment cause
            -> App environment cause value -> Target environment cause value

targetName :: Target environment cause value -> String
targetName (AppTarget selected _ _ _) = selected

-- 生成区只登记句柄，不组合上游操作。
targetApp :: (Show cause, Show value, NFData value) => String -> environment -> Scopes environment cause
          -> App environment cause value -> Target environment cause value
targetApp = AppTarget

-- 交给下一段调用的已捕获绑定（只含无 scope 归属的资产）与持续资产的视图；内容不对外公开。
-- alternative 用它把选择时读到的资产交给候选；订阅回调用它把交付交给单元。
data Handoff environment cause = Handoff (ScopeBindings environment cause) [(Slot, View environment cause)]

noHandoff :: Handoff environment cause
noHandoff = Handoff [] []

-- 普通跨入口交接不传资源；同一来源步骤的内部交接在来源运行器中处理。
-- 只有 alternative 把选择读取的捕获交给候选，由它在调用返回后立即过滤。
handoffWithoutResources :: Handoff environment cause -> IO (Handoff environment cause)
handoffWithoutResources (Handoff captured delivered) =
  (`Handoff` delivered) <$> filterM (fmap isNothing . readBindingOwner . snd) captured

-- 末端的一次调用。performed 是订阅回调交付的资产：入口里对它的 requests 直接读这条交付。
-- 交付及其伴随绑定作为本次执行帧的已固定输入登记，scope 回收据此保留它们开启的实例；
-- Untracked 的执行没有自己的帧，不登记。
-- 受控结果消费在撤销入口使用登记前完成，惰性读取不会落在自动 close 之后。
-- 返回的交接是调用结束时的完整捕获，交给下一段调用前用 handoffWithoutResources 过滤。
lowerTarget :: RuntimeGraph environment cause -> Tracking -> Retention environment cause -> Coord -> ExecutionFrame -> Place
            -> Handoff environment cause -> [Slot] -> Target environment cause value
            -> IO (Either (Failure cause) value, Handoff environment cause)
lowerTarget graph tracking retention location executionFrame at (Handoff given views) performed target = do
  -- 交接通常只有普通值：先判断有没有资源，没有就不拼出待保留的列表。
  when (any (bindingResource . snd) given || any (maybe False bindingResource . lastBinding . snd) views) $
    keepBindings retention (map snd given ++ mapMaybe (lastBinding . snd) views)
  when (tracking == Tracked) $ captureFrameDeliveries executionFrame
    [(originNode (executionOrigin (bindingOrigin value)), source, production)
      | (source, value) <- given, source `elem` performed, Just production <- [bindingProduction value]
      , source `notElem` [resource | family <- runtimeScopes graph, Just resource <- [scopeContextSource family]]]
  let launch = Launch
        { launchBindings = given, launchViews = views, launchPort = NoStreamPort, launchPerformed = performed
        , launchUser = Nothing, launchFrame = executionFrame, launchRetention = retention, launchPlace = at
        , launchTracking = tracking }
  (outcome, captured, delivered) <- lowerWith graph location launch target
  pure (outcome, Handoff captured delivered)

lowerWith :: RuntimeGraph environment cause -> Coord -> Launch environment cause -> Target environment cause value
          -> IO (Either (Failure cause) value, ScopeBindings environment cause, [(Slot, View environment cause)])
-- 结果在撤销使用登记前完整求值：成功值用 NFData，失败仍完整展开一次（失败少见，原因类型只要求 Show）。
lowerWith graph location launch (AppTarget _ environment _ action) =
  runAppWith consume graph location launch environment action
  where
    consume (Right value) = evaluate (rnf value)
    consume (Left problem) = evaluate (foldr seq () (show problem))

-- 各末端通常捕获同批 scope；按控制对象身份去重，不按业务名称合并独立批次。
scopeHandlers :: [Target environment cause value] -> Scopes environment cause
scopeHandlers entries = nubBy sameHandler (concatMap targetScopes entries)
  where
    targetScopes :: Target environment cause value -> Scopes environment cause
    targetScopes (AppTarget _ _ scopes _) = scopes
    sameHandler left right = scopeInstances left == scopeInstances right

cleanupTargets :: [Target environment cause value] -> IO [(Maybe SomeException, Failure cause)]
cleanupTargets = cleanupScopes . scopeHandlers

-- 生成的执行闭包 ---------------------------------------------------------------

-- gen 写出的整份程序：workflow、发布后的回调表，以及 lifelong 外 requests 持续资产时的静态运行。
data Compiled environment cause value = Compiled
  { compiledWorkflow :: Closure environment cause value
  , compiledReactions :: [Reaction environment cause value]
  -- (被 requests 的持续资产, 静态运行的标识, 它的根来源)。派生链的回调以这个标识为作用范围。
  , compiledStatic :: [(Slot, NodeId, StreamSource environment cause)]
  }

-- workflow 的执行闭包，按 AST 的规范形式逐层写出；NodeId 是该层的挂载位置。
-- Step：执行一个挂载的末端。Choose：执行选择读取，再执行判定出的候选。
-- Concurrent：各分支并发执行；每个分支带着 gen 写明的、它执行期间可能发布的资产（含回调与派生接着发布的），
-- 其他分支里的 require 缺值时据此决定是否等待。
-- Drive：lifelong 的位置。有 Stream 来源时同步运行它，来源结束或订阅全部 endStream 后返回；
-- 没有来源（只有 event 订阅）时什么也不做，回调已经在回调表里。
data Closure environment cause value
  = Step NodeId (Target environment cause value)
  | Serial NodeId [Closure environment cause value]
  | Concurrent NodeId [([Slot], Closure environment cause value)]
  | Choose NodeId NodeId (Target environment cause String) [(String, NodeId, Closure environment cause value)]
  | Drive NodeId (Maybe (StreamSource environment cause))

-- Stream 来源：Stream 方法与 parser 各有一个挂载。每次 rawemit 在来源的调用栈里执行一次 parser，
-- parser 的发布再同步回调订阅方。sourceSame 是 behavior 的比较：与上一次回调的值相等时不回调。
data StreamSource environment cause = StreamSource
  { sourceAsset :: Slot
  , sourceStream :: (NodeId, Target environment cause ())
  , sourceParser :: (NodeId, Target environment cause ())
  , sourceSame :: Maybe (environment -> environment -> Bool)
  }

-- 资产每次发布后执行的回调。reactionScope：Nothing 是 event，整次运行有效；
-- Just 是所属 lifelong（或静态运行）的标识，只回应这个作用范围里的发布（来源运行期间及其回调中）。
data Reaction environment cause value = Reaction
  { reactionAsset :: Slot
  , reactionScope :: Maybe NodeId
  , reactionResponse :: Response environment cause value
  }

-- Unit：lifelong 的一个单元执行一次，交付的资产固定给它。Tracking 是 gen 的回收无关判定：
-- Untracked 的单元不建执行帧、不登记保留根与执行身份，endStream、失败与等待照常。
-- RunDerive：在派生挂载执行派生资产的 parser，它沿 Input 链执行被驱动的句柄并发布。
data Response environment cause value
  = RunUnit NodeId Tracking (Closure environment cause value)
  | RunDerive NodeId (Target environment cause ())
