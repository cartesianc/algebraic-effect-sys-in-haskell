-- 原生 Haskell 方法体；SDK 添加入口包装，运行编译 Generated 副本。
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE UndecidableInstances #-}

{-# OPTIONS_GHC -Werror=missing-methods #-}

module RequestBenchmark.Handlers () where

import Framework.SDK (Effect(..))
import RequestBenchmark.Generated.Effects
import RequestBenchmark.Types

-- 2. Context 通过 demands 接入；request @T 重新生产，require @T 读取已有绑定。
instance DemoContextEffect Pure where
  demoInputs = pure (DemoInputs (InputSettings (Start 20) (Render "number: ")))

-- 3. Handler code（手写）：按契约取值并实现计算；来源由注册解析，不在方法体中指名。
-- 错误构造器由 SDK 按 effect 名生成；用户只填写消息，raise 自动保留来源。
instance MakeNumberEffect Pure where
  numberValue = do
    DemoInputs (InputSettings (Start number) _) <- request @DemoInputs
    if number < 0
      then raise (MakeNumberError ("Invalid start: " ++ show number))
      else pure (NumberValue number)

-- 泛型 instance 只依赖契约 Provides，不依赖具体生产方的类。
instance (Effect Root m, Provides NumberValue m) => AddOneEffect m where
  addedValue = do
    NumberValue number <- request @NumberValue
    pure (AddedValue (number + 1))

instance (Effect Root m, Provides AddedValue m, Provides DemoInputs m) => RenderNumberEffect m where
  renderedValue = do
    AddedValue number <- request @AddedValue
    -- 注册为 require；读取 MakeNumber 先前生产时保存的绑定，不再次执行生产。
    DemoInputs (InputSettings _ (Render prefix)) <- require @DemoInputs
    pure (RenderedValue (prefix ++ show number))
