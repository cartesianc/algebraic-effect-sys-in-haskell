-- 自动生成的编译副本；请修改上级 Handlers.hs 后重新生成。
{-# LANGUAGE TypeApplications #-}
-- 原生 Haskell 方法体；SDK 添加入口包装，运行编译 Generated 副本。
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE UndecidableInstances #-}

{-# OPTIONS_GHC -Werror=missing-methods #-}

module RequestBenchmark.Generated.Handlers (handlerSourceFingerprint, errorHandlers, contextInjections) where

import qualified Framework.SDK as FrameworkRuntime
import qualified Framework.Effect.Contract as FrameworkRoot
import qualified RequestBenchmark.Generated.Effects as FrameworkGenerated
import Framework.SDK (Effect(..))
import RequestBenchmark.Generated.Effects
import RequestBenchmark.Types

-- 2. Context 通过 demands 接入；request @T 重新生产，require @T 读取已有绑定。
instance DemoContextEffect Pure where
  demoInputs =
    (FrameworkRoot.withErrorPath [] . FrameworkRoot.handler @FrameworkGenerated.Root . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.callContext "DemoContext" FrameworkGenerated.ContextBindingError
      [("MakeNumber", FrameworkRuntime.RequestValue), ("RenderNumber", FrameworkRuntime.RequireValue)]
      Nothing
      FrameworkGenerated.boundDemoContext
      (\value bindings -> bindings { FrameworkGenerated.boundDemoContext = Just value })) $
      let
        demoInputs = pure (DemoInputs (InputSettings (Start 20) (Render "number: ")))
      in demoInputs

-- 3. Handler code（手写）：按契约取值并实现计算；来源由注册解析，不在方法体中指名。
-- 错误构造器由 SDK 按 effect 名生成；用户只填写消息，raise 自动保留来源。
instance MakeNumberEffect Pure where
  numberValue =
    (FrameworkRoot.withErrorPath [] . FrameworkRoot.handler @FrameworkGenerated.Root . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.callContext "MakeNumber" FrameworkGenerated.ContextBindingError
      [("AddOne", FrameworkRuntime.RequestValue)]
      Nothing
      FrameworkGenerated.boundMakeNumber
      (\value bindings -> bindings { FrameworkGenerated.boundMakeNumber = Just value })) $
      let
        numberValue = do
          DemoInputs (InputSettings (Start number) _) <- request @DemoInputs
          if number < 0
            then raise (MakeNumberError ("Invalid start: " ++ show number))
            else pure (NumberValue number)
      in numberValue

-- 泛型 instance 只依赖契约 Provides，不依赖具体生产方的类。
instance (Effect Root m, Provides NumberValue m) => AddOneEffect m where
  addedValue =
    (FrameworkRoot.withErrorPath [] . FrameworkRoot.handler @FrameworkGenerated.Root . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.callContext "AddOne" FrameworkGenerated.ContextBindingError
      [("RenderNumber", FrameworkRuntime.RequestValue)]
      Nothing
      FrameworkGenerated.boundAddOne
      (\value bindings -> bindings { FrameworkGenerated.boundAddOne = Just value })) $
      let
        addedValue = do
          NumberValue number <- request @NumberValue
          pure (AddedValue (number + 1))
      in addedValue

instance (Effect Root m, Provides AddedValue m, Provides DemoInputs m) => RenderNumberEffect m where
  renderedValue =
    (FrameworkRoot.withErrorPath [] . FrameworkRoot.handler @FrameworkGenerated.Root . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.callContext "RenderNumber" FrameworkGenerated.ContextBindingError
      []
      Nothing
      FrameworkGenerated.boundRenderNumber
      (\value bindings -> bindings { FrameworkGenerated.boundRenderNumber = Just value })) $
      let
        renderedValue = do
          AddedValue number <- request @AddedValue
          -- 注册为 require；读取 MakeNumber 先前生产时保存的绑定，不再次执行生产。
          DemoInputs (InputSettings _ (Render prefix)) <- require @DemoInputs
          pure (RenderedValue (prefix ++ show number))
      in renderedValue

-- 记录本编译副本实际使用的手写源码；启动前检查，避免执行过期方法体。
handlerSourceFingerprint :: Maybe String
handlerSourceFingerprint = Just "d45ae57cc89e56a56928b02fcaaefbaf"



-- Error 回调登记：按 handles 匹配故障来源与分类；关联 scope 由 Input 链推导。
errorHandlers :: [(Maybe String, FrameworkRoot.ErrorHandler FrameworkGenerated.Errors FrameworkGenerated.Pure)]
errorHandlers =
  [
  ]

-- 挂在原子句柄下的 Context：句柄的输出交给它解析并发布为资产；没有挂接时输出被丢弃。
contextInjections :: [(String, [(String, FrameworkGenerated.Pure ())])]
contextInjections =
  [
  ]
