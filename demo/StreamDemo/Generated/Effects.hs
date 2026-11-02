{-# LANGUAGE AllowAmbiguousTypes #-}
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
module StreamDemo.Generated.Effects where

import Framework.Effect.Contract (Effect(..), Registered)
import qualified Framework.Effect.Contract as FrameworkRoot
import qualified Framework.SDK as SDK
import Control.Monad.IO.Class (MonadIO)
import StreamDemo.Types

-- SDK 提供运行载体与空存储；Context 经声明的 request/require 取得。
type Root = SDK.Root ContextValues Errors
type App = SDK.App ContextValues Errors

-- 每个 Context 的契约类型：名字来自 handler 名，包装其表示类型；只能由该生产方构造。
newtype TemperatureSample = TemperatureSample (Temperature)
deriving instance Eq (Temperature) => Eq TemperatureSample
deriving instance Show (Temperature) => Show TemperatureSample

newtype Beat = Beat (Int)
deriving instance Eq (Int) => Eq Beat
deriving instance Show (Int) => Show Beat

-- 方法定义身份；仅生成区使用，图中不以字符串匹配方法。
data MethodGen = ConnectSensorGen | DisconnectSensorGen | NextReadingGen | GetTemperatureSampleGen | ReadTemperatureSampleGen | GetBeatGen | ReadBeatGen | AnnounceGen | ShowTemperatureGen | CheckTrendGen | ReportHeartbeatGen
  deriving (Eq, Ord, Show, Read, SDK.Generic)
instance SDK.NFData MethodGen

data SensorLink

type SensorLinkInputs m = (FrameworkRoot.Capability SensorLink m, Effect Root m, MonadIO m)
instance FrameworkRoot.Capability SensorLink App

class (Effect Root m) => SensorLinkEffect m where
  connectSensor :: m (Maybe String)
  disconnectSensor :: m (Maybe String)
  {-# MINIMAL connectSensor, disconnectSensor #-}

instance (Monad m, Effect Root m, SensorLinkEffect m) => Effect SensorLink m where
  type Registration SensorLink = Registered SensorLinkEffect Root
  type Typing SensorLink = 'SDK.ScopedKind
  type Require SensorLink = SDK.Void
  type Error SensorLink = SensorLinkError
  raise (SensorLinkError description) = SDK.failEffect "SensorLink" SensorLinkFailure description
  handler = FrameworkRoot.handler @Root

data TemperatureFeed

type TemperatureFeedInputs m = (FrameworkRoot.Capability TemperatureFeed m, Effect SensorLink m, SensorLinkEffect m, MonadIO m)
instance FrameworkRoot.Capability TemperatureFeed App

class (Effect SensorLink m) => TemperatureFeedEffect m where
  nextReading :: m String
  {-# MINIMAL nextReading #-}

instance (Monad m, Effect SensorLink m, TemperatureFeedEffect m) => Effect TemperatureFeed m where
  type Registration TemperatureFeed = Registered TemperatureFeedEffect SensorLink
  type Typing TemperatureFeed = 'SDK.StreamKind
  type Require TemperatureFeed = SDK.Void
  type Error TemperatureFeed = TemperatureFeedError
  raise (TemperatureFeedError description) = SDK.failEffect "TemperatureFeed" TemperatureFeedFailure description
  handler = FrameworkRoot.handler @Root

data TemperatureParser

type TemperatureParserInputs m = (FrameworkRoot.Capability TemperatureParser m, Effect TemperatureFeed m, TemperatureFeedEffect m, SensorLinkEffect m, MonadIO m)
instance FrameworkRoot.Capability TemperatureParser App

class (Effect TemperatureFeed m) => TemperatureParserEffect m where
  getTemperatureSample :: m (Produce TemperatureParser)
  readTemperatureSample :: m (SDK.History (Produce TemperatureParser))
  readTemperatureSample = (FrameworkRoot.withErrorPath ["SensorLink"] . FrameworkRoot.handler @Root) $
    SDK.readHistory "TemperatureParser" ContextBindingError [("ShowTemperature", SDK.RequireValue), ("CheckTrend", SDK.RequireValue)] boundTemperatureParser Nothing
  {-# MINIMAL getTemperatureSample #-}

instance (Monad m, Effect TemperatureFeed m, TemperatureParserEffect m) => Effect TemperatureParser m where
  type Registration TemperatureParser = Registered TemperatureParserEffect TemperatureFeed
  type Typing TemperatureParser = 'SDK.ContextKind
  type Require TemperatureParser = SDK.Void
  type Produce TemperatureParser = TemperatureSample
  type Error TemperatureParser = TemperatureParserError
  raise (TemperatureParserError description) = SDK.failEffect "TemperatureParser" TemperatureParserFailure description
  handler = FrameworkRoot.handler @Root

data Heartbeat

type HeartbeatInputs m = (FrameworkRoot.Capability Heartbeat m, Effect Root m, MonadIO m)
instance FrameworkRoot.Capability Heartbeat App

class (Effect Root m) => HeartbeatEffect m where
  getBeat :: m (Produce Heartbeat)
  readBeat :: m (SDK.History (Produce Heartbeat))
  readBeat = (FrameworkRoot.withErrorPath [] . FrameworkRoot.handler @Root) $
    SDK.readHistory "Heartbeat" ContextBindingError [("ReportHeartbeat", SDK.RequireValue)] boundHeartbeat (Just getBeat)
  {-# MINIMAL getBeat #-}

instance (Monad m, Effect Root m, HeartbeatEffect m) => Effect Heartbeat m where
  type Registration Heartbeat = Registered HeartbeatEffect Root
  type Typing Heartbeat = 'SDK.ContextKind
  type Require Heartbeat = SDK.Void
  type Produce Heartbeat = Beat
  type Error Heartbeat = HeartbeatError
  raise (HeartbeatError description) = SDK.failEffect "Heartbeat" HeartbeatFailure description
  handler = FrameworkRoot.handler @Root

data Announce

type AnnounceInputs m = (FrameworkRoot.Capability Announce m, Effect Root m, MonadIO m)
instance FrameworkRoot.Capability Announce App

class (Effect Root m) => AnnounceEffect m where
  announce :: m (Maybe String)
  {-# MINIMAL announce #-}

instance (Monad m, Effect Root m, AnnounceEffect m) => Effect Announce m where
  type Registration Announce = Registered AnnounceEffect Root
  type Typing Announce = 'SDK.ExcuKind
  type Require Announce = SDK.Void
  type Error Announce = AnnounceError
  raise (AnnounceError description) = SDK.failEffect "Announce" AnnounceFailure description
  handler = FrameworkRoot.handler @Root

data ShowTemperature

type ShowTemperatureInputs m = (FrameworkRoot.Capability ShowTemperature m, Effect Root m, Provides TemperatureSample m, MonadIO m)
instance FrameworkRoot.Capability ShowTemperature App

class (Effect Root m, Provides TemperatureSample m) => ShowTemperatureEffect m where
  showTemperature :: m (Maybe String)
  {-# MINIMAL showTemperature #-}

instance (Monad m, Effect Root m, ShowTemperatureEffect m) => Effect ShowTemperature m where
  type Registration ShowTemperature = Registered ShowTemperatureEffect Root
  type Typing ShowTemperature = 'SDK.ExcuKind
  type Require ShowTemperature = TemperatureSample
  type Error ShowTemperature = ShowTemperatureError
  raise (ShowTemperatureError description) = SDK.failEffect "ShowTemperature" ShowTemperatureFailure description
  handler = FrameworkRoot.handler @Root

data CheckTrend

type CheckTrendInputs m = (FrameworkRoot.Capability CheckTrend m, Effect Root m, Provides TemperatureSample m, MonadIO m)
instance FrameworkRoot.Capability CheckTrend App

class (Effect Root m, Provides TemperatureSample m) => CheckTrendEffect m where
  checkTrend :: m (Maybe String)
  {-# MINIMAL checkTrend #-}

instance (Monad m, Effect Root m, CheckTrendEffect m) => Effect CheckTrend m where
  type Registration CheckTrend = Registered CheckTrendEffect Root
  type Typing CheckTrend = 'SDK.ExcuKind
  type Require CheckTrend = TemperatureSample
  type Error CheckTrend = CheckTrendError
  raise (CheckTrendError description) = SDK.failEffect "CheckTrend" CheckTrendFailure description
  handler = FrameworkRoot.handler @Root

data ReportHeartbeat

type ReportHeartbeatInputs m = (FrameworkRoot.Capability ReportHeartbeat m, Effect Root m, Provides Beat m, MonadIO m)
instance FrameworkRoot.Capability ReportHeartbeat App

class (Effect Root m, Provides Beat m) => ReportHeartbeatEffect m where
  reportHeartbeat :: m (Maybe String)
  {-# MINIMAL reportHeartbeat #-}

instance (Monad m, Effect Root m, ReportHeartbeatEffect m) => Effect ReportHeartbeat m where
  type Registration ReportHeartbeat = Registered ReportHeartbeatEffect Root
  type Typing ReportHeartbeat = 'SDK.ExcuKind
  type Require ReportHeartbeat = Beat
  type Error ReportHeartbeat = ReportHeartbeatError
  raise (ReportHeartbeatError description) = SDK.failEffect "ReportHeartbeat" ReportHeartbeatFailure description
  handler = FrameworkRoot.handler @Root

-- 依值入口：request 重新生产，require 读取已有绑定；来源由注册解析，不由消费方指名。
-- Reading 是 require 的结果：持续资产为 History，其余为契约本身；只由资产自己的声明决定。
class Provides contract m where
  type Reading contract
  request :: m contract
  require :: m (Reading contract)

instance (TemperatureParserEffect App) => Provides TemperatureSample App where
  type Reading TemperatureSample = SDK.History TemperatureSample
  request = SDK.provideContext "TemperatureParser" "TemperatureSample" ContextBindingError []
  require = SDK.provideContext "TemperatureParser" "TemperatureSample" ContextBindingError [("ShowTemperature", readTemperatureSample), ("CheckTrend", readTemperatureSample)]

instance (HeartbeatEffect App) => Provides Beat App where
  type Reading Beat = SDK.History Beat
  request = SDK.provideContext "Heartbeat" "Beat" ContextBindingError []
  require = SDK.provideContext "Heartbeat" "Beat" ContextBindingError [("ReportHeartbeat", readBeat)]

-- SDK 生成的本地错误只接收消息；类型唯一确定 raise 来源。
newtype SensorLinkError = SensorLinkError String
  deriving (Eq, Show, Read)

-- SDK 生成的本地错误只接收消息；类型唯一确定 raise 来源。
newtype TemperatureFeedError = TemperatureFeedError String
  deriving (Eq, Show, Read)

-- SDK 生成的本地错误只接收消息；类型唯一确定 raise 来源。
newtype TemperatureParserError = TemperatureParserError String
  deriving (Eq, Show, Read)

-- SDK 生成的本地错误只接收消息；类型唯一确定 raise 来源。
newtype HeartbeatError = HeartbeatError String
  deriving (Eq, Show, Read)

-- SDK 生成的本地错误只接收消息；类型唯一确定 raise 来源。
newtype AnnounceError = AnnounceError String
  deriving (Eq, Show, Read)

-- SDK 生成的本地错误只接收消息；类型唯一确定 raise 来源。
newtype ShowTemperatureError = ShowTemperatureError String
  deriving (Eq, Show, Read)

-- SDK 生成的本地错误只接收消息；类型唯一确定 raise 来源。
newtype CheckTrendError = CheckTrendError String
  deriving (Eq, Show, Read)

-- SDK 生成的本地错误只接收消息；类型唯一确定 raise 来源。
newtype ReportHeartbeatError = ReportHeartbeatError String
  deriving (Eq, Show, Read)

-- 统一失败协议的分类标签；消息与来源由 SDK.Failure 保存。
data Errors = SensorLinkFailure | TemperatureFeedFailure | TemperatureParserFailure | HeartbeatFailure | AnnounceFailure | ShowTemperatureFailure | CheckTrendFailure | ReportHeartbeatFailure | ContextBindingError SDK.ContextFault | ScopeBindingError SDK.ScopeFault
  deriving (Eq, Show)

-- SDK 内部存储：Nothing 仅表示本次运行尚未建立绑定，不是业务缺值。
data ContextValues = ContextValues
  { boundTemperatureParser :: Maybe (Produce TemperatureParser)
  , boundHeartbeat :: Maybe (Produce Heartbeat)
  }

emptyContexts :: ContextValues
emptyContexts = ContextValues Nothing Nothing

