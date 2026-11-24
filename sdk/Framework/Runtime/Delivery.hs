{-# OPTIONS_GHC -fexpose-all-unfoldings -fspecialise-aggressively #-}
-- 持续资产的交付视图与两个结束信号。没有会话、队列或游标：
-- 发布在发布方的调用栈里同步回调订阅方，视图只是回调时交给订阅方的那一段历史。
module Framework.Runtime.Delivery
  ( View, lastBinding, SourceEnded(..), SubscriptionEnded(..)
  ) where

import Control.Exception (Exception)
import Data.Sequence (Seq, ViewR(..), viewr)
import Framework.Runtime.Scope (ScopeBinding)

-- 按发布时间排列，最后一条是本次交付的 Binding；之前的条目只供 stream @T 读取历史。
-- 绑定保留自己的生产身份、执行帧和共享归属。
type View environment cause = Seq (ScopeBinding environment cause)

lastBinding :: Seq value -> Maybe value
lastBinding entries = case viewr entries of
  EmptyR -> Nothing
  _ :> value -> Just value

-- SDK 内部的正常结束信号，以异常形式越过方法体；不是业务 Failure，不进入 Error 协议，
-- 也不被方法体内的 catchError 接住。
-- SourceEnded：Stream handler 调用 streamEnd，或它的订阅方全部 endStream 后下一次 rawemit；来源运行器接住并正常返回。
data SourceEnded = SourceEnded
instance Show SourceEnded where show _ = "SDK stream source ended"
instance Exception SourceEnded

-- SubscriptionEnded：订阅方 handler 调用 endStream。回调的那个节点之后不再执行；派生步骤调用时该派生不再回调。
data SubscriptionEnded = SubscriptionEnded
instance Show SubscriptionEnded where show _ = "SDK stream subscription ended"
instance Exception SubscriptionEnded
