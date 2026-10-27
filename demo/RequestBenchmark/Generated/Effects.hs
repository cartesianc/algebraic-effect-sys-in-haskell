{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE EmptyDataDecls #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE UndecidableInstances #-}
{-# LANGUAGE UndecidableSuperClasses #-}

-- 自动生成；通过 SDK 的 effect-codegen 更新，手写注册与 handler 位于上级目录。
module RequestBenchmark.Generated.Effects where

import Framework.Effect.Contract (Effect(..), Registered)
import qualified Framework.Effect.Contract as FrameworkRoot
import qualified Framework.SDK as SDK
import RequestBenchmark.Types

-- SDK 提供运行载体与空存储；Context 经声明的 request/require 取得。
type Root = SDK.Root ContextValues Errors
type Pure = SDK.Pure ContextValues Errors

-- 方法定义身份；仅生成区使用，图中不以字符串匹配方法。
data MethodGen = LoadDemoInputsGen | ReadDemoInputsGen | MakeNumberGen | ReadNumberGen | AddOneGen | ReadAddedNumberGen | RenderNumberGen | ReadRenderedNumberGen
  deriving (Eq, Ord, Show, Read, SDK.Generic)
instance SDK.NFData MethodGen

data DemoContext

class (Effect Root m) => DemoContextEffect m where
  loadDemoInputs :: m (Produce DemoContext)
  readDemoInputs :: m (Produce DemoContext)
  readDemoInputs = (FrameworkRoot.withErrorPath [] . FrameworkRoot.handler @Root) $
    SDK.readContext "DemoContext" ContextBindingError [("MakeNumber", SDK.RequestValue), ("RenderNumber", SDK.RequireValue)] Nothing boundDemoContext
  {-# MINIMAL loadDemoInputs #-}

instance (Monad m, Effect Root m, DemoContextEffect m) => Effect DemoContext m where
  type Registration DemoContext = Registered DemoContextEffect Root
  type Typing DemoContext = 'SDK.ContextKind
  type Require DemoContext = SDK.Void
  type Produce DemoContext = DemoInputs
  type Error DemoContext = DemoContextError
  raise (DemoContextError description) = SDK.failEffect "DemoContext" DemoContextFailure description
  handler = FrameworkRoot.handler @Root

data MakeNumber

class (Effect Root m, Provides DemoInputs m) => MakeNumberEffect m where
  makeNumber :: m (Produce MakeNumber)
  readNumber :: m (Produce MakeNumber)
  readNumber = (FrameworkRoot.withErrorPath [] . FrameworkRoot.handler @Root) $
    SDK.readContext "MakeNumber" ContextBindingError [("AddOne", SDK.RequestValue)] Nothing boundMakeNumber
  {-# MINIMAL makeNumber #-}

instance (Monad m, Effect Root m, MakeNumberEffect m) => Effect MakeNumber m where
  type Registration MakeNumber = Registered MakeNumberEffect Root
  type Typing MakeNumber = 'SDK.ContextKind
  type Require MakeNumber = DemoInputs
  type Produce MakeNumber = NumberValue
  type Error MakeNumber = MakeNumberError
  raise (MakeNumberError description) = SDK.failEffect "MakeNumber" MakeNumberFailure description
  handler = FrameworkRoot.handler @Root

data AddOne

class (Effect Root m, Provides NumberValue m) => AddOneEffect m where
  addOne :: m (Produce AddOne)
  readAddedNumber :: m (Produce AddOne)
  readAddedNumber = (FrameworkRoot.withErrorPath [] . FrameworkRoot.handler @Root) $
    SDK.readContext "AddOne" ContextBindingError [("RenderNumber", SDK.RequestValue)] Nothing boundAddOne
  {-# MINIMAL addOne #-}

instance (Monad m, Effect Root m, AddOneEffect m) => Effect AddOne m where
  type Registration AddOne = Registered AddOneEffect Root
  type Typing AddOne = 'SDK.ContextKind
  type Require AddOne = NumberValue
  type Produce AddOne = AddedValue
  type Error AddOne = AddOneError
  raise (AddOneError description) = SDK.failEffect "AddOne" AddOneFailure description
  handler = FrameworkRoot.handler @Root

data RenderNumber

class (Effect Root m, Provides AddedValue m, Provides DemoInputs m) => RenderNumberEffect m where
  renderNumber :: m (Produce RenderNumber)
  readRenderedNumber :: m (Produce RenderNumber)
  readRenderedNumber = (FrameworkRoot.withErrorPath [] . FrameworkRoot.handler @Root) $
    SDK.readContext "RenderNumber" ContextBindingError [] Nothing boundRenderNumber
  {-# MINIMAL renderNumber #-}

instance (Monad m, Effect Root m, RenderNumberEffect m) => Effect RenderNumber m where
  type Registration RenderNumber = Registered RenderNumberEffect Root
  type Typing RenderNumber = 'SDK.ContextKind
  type Require RenderNumber = (AddedValue, DemoInputs)
  type Produce RenderNumber = RenderedValue
  type Error RenderNumber = RenderNumberError
  raise (RenderNumberError description) = SDK.failEffect "RenderNumber" RenderNumberFailure description
  handler = FrameworkRoot.handler @Root

-- 依值入口：request 重新生产，require 读取已有绑定；来源由注册解析，不由消费方指名。
class Provides contract m where
  request :: m contract
  require :: m contract

instance (DemoContextEffect Pure) => Provides DemoInputs Pure where
  request = SDK.provideContext "DemoInputs" ContextBindingError [("MakeNumber", loadDemoInputs)]
  require = SDK.provideContext "DemoInputs" ContextBindingError [("RenderNumber", readDemoInputs)]

instance (MakeNumberEffect Pure) => Provides NumberValue Pure where
  request = SDK.provideContext "NumberValue" ContextBindingError [("AddOne", makeNumber)]
  require = SDK.provideContext "NumberValue" ContextBindingError []

instance (AddOneEffect Pure) => Provides AddedValue Pure where
  request = SDK.provideContext "AddedValue" ContextBindingError [("RenderNumber", addOne)]
  require = SDK.provideContext "AddedValue" ContextBindingError []

-- SDK 生成的本地错误只接收消息；类型唯一确定 raise 来源。
newtype DemoContextError = DemoContextError String
  deriving (Eq, Show, Read)

-- SDK 生成的本地错误只接收消息；类型唯一确定 raise 来源。
newtype MakeNumberError = MakeNumberError String
  deriving (Eq, Show, Read)

-- SDK 生成的本地错误只接收消息；类型唯一确定 raise 来源。
newtype AddOneError = AddOneError String
  deriving (Eq, Show, Read)

-- SDK 生成的本地错误只接收消息；类型唯一确定 raise 来源。
newtype RenderNumberError = RenderNumberError String
  deriving (Eq, Show, Read)

-- 统一失败协议的分类标签；消息与来源由 SDK.Failure 保存。
data Errors = DemoContextFailure | MakeNumberFailure | AddOneFailure | RenderNumberFailure | ContextBindingError SDK.ContextFault | ScopeBindingError SDK.ScopeFault
  deriving (Eq, Show)

-- SDK 内部存储：Nothing 仅表示本次运行尚未建立绑定，不是业务缺值。
data ContextValues = ContextValues
  { boundDemoContext :: Maybe (Produce DemoContext)
  , boundMakeNumber :: Maybe (Produce MakeNumber)
  , boundAddOne :: Maybe (Produce AddOne)
  , boundRenderNumber :: Maybe (Produce RenderNumber)
  }

emptyContexts :: ContextValues
emptyContexts = ContextValues Nothing Nothing Nothing Nothing

