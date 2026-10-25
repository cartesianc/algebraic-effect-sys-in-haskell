-- 原生 Haskell 方法体；SDK 添加入口包装，运行编译 Generated 副本。
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE UndecidableInstances #-}

{-# OPTIONS_GHC -Werror=missing-methods #-}

module RequestBenchmark.Handlers () where

import Framework.SDK (Effect(..))
import RequestBenchmark.Generated.Effects
import RequestBenchmark.Types

-- 2. Context 通过 request/require 接入；保存与读取由 SDK 生成的入口接管。
instance DemoContextEffect Pure where
  loadDemoInputs = pure (DemoInputs (Start 20) (Render "number: "))

-- 3. Handler code（手写）：匹配数据并实现计算，能力由上游 Effect 继承。
-- SDK 不生成外部 request 流水线；上游调用发生在这些 instance 方法体内。
-- 错误构造器由 SDK 按 effect 名生成；用户只填写消息，raise 自动保留来源。
instance MakeNumberEffect Pure where
  makeNumber = do
    DemoInputs (Start number) _ <- loadDemoInputs
    if number < 0
      then raise (MakeNumberError ("Invalid start: " ++ show number))
      else pure (Number number)

instance Effect MakeNumber m => AddOneEffect m where
  addOne = do
    Number number <- makeNumber
    pure (Added (number + 1))

instance Effect AddOne m => RenderNumberEffect m where
  renderNumber = do
    Added number <- addOne
    -- 注册为 require；仍引用同一个上游类方法，SDK 读取先前保存的值。
    DemoInputs _ (Render prefix) <- loadDemoInputs
    pure (Rendered (prefix ++ show number))
