{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE PatternSynonyms #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeAbstractions #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE ViewPatterns #-}

-- 纯注册描述与依赖解析，不执行 handler。
module Framework.Effect.Registration
  ( EffectTyping(..), Asset(.., Asset), contractOf, contextAsset, contextProducer, contextReader
  , declaresStream, belowStream, continuousContext
  , Handles(..), TypeRef(..), typeRef, contractName
  , EffectSpec(..), Demand(..), Access(..), requests, requires, streams
  , ResolvedDemand(..), resolveDemands, contextNames
  , effectKind, entryMethod
  ) where

import Framework.Effect.Contract (EffectKind(..), Output)
import Control.Monad (unless)
import Control.DeepSeq (NFData)
import GHC.Generics (Generic)
import Data.List (nub)
import Data.Proxy (Proxy(..))
import Data.Typeable (Typeable, splitTyConApp, typeRep, typeRepTyCon)

data EffectTyping
  = Pure { handler :: Maybe String }
  | Excu { handler :: Maybe String }
  | Scoped { open :: Maybe String, close :: Maybe String }
  -- handles 按错误类型匹配；作用的 scope 由 Input 链上最近的 Scoped 推导，不手写连接。
  | Error { detect :: Maybe String, resolve :: Maybe String, handles :: [Handles] }
  -- Context 围绕一个具名资产声明方法角色；Just () 表示生成该角色的方法，Nothing 不生成。
  -- 方法名由资产名固定生成：request 为 get 加资产名，require 为 read 加资产名。
  -- input 是 Stream 时，request 声明的 getT 就是解析器，资产自动是持续资产，不再写 stream。
  -- 不在 Stream 下时 stream = Just () 表示持续资产，由 SDK 反复调用 request 供给。
  -- 持续资产的 require 返回 History，可以被 streams 订阅。
  | Context { asset :: Asset, request :: Maybe (), require :: Maybe (), stream :: Maybe () }
  -- 第六种 typing：持续生产节点。handler 每次调用取得一份原始输入（String），SDK 负责反复调用；
  -- 不作为 AST 末端，只经挂在它下面的 Context 解析后进入资产。
  | Stream { handler :: Maybe String }
  deriving (Eq, Show, Read, Generic, NFData)

-- 细化资产（refinement asset）：表示类型来自 Types.hs 或 Prelude，资产名给它一个独立的名义类型，
-- 生成器产出 newtype 资产名 = 资产名 表示类型，例如 newtype StartURL = StartURL PageURL。
-- 资产名就是契约名：消费方按它解析唯一的生产方，同一表示类型的不同细化互不相通。
data Asset = AssetDecl
  { assetName :: String
  , representation :: TypeRef
  } deriving (Eq, Show, Read, Generic, NFData)

-- 写作 Asset @PageURL "StartURL"：把表示类型 PageURL 细化为资产 StartURL。
-- 用于声明；作为模式时按表示类型核对。
pattern Asset :: forall value. Typeable value => String -> Asset
pattern Asset selected <- (matchAsset @value -> Just selected)
  where Asset selected = AssetDecl selected (typeRef @value)

matchAsset :: forall value. Typeable value => Asset -> Maybe String
matchAsset (AssetDecl selected declared)
  | declared == typeRef @value = Just selected
  | otherwise = Nothing

-- 契约名就是资产名，是生产方与消费方共享的唯一键。
contractOf :: Asset -> String
contractOf = assetName

contextAsset :: EffectTyping -> Maybe Asset
contextAsset (Context declared _ _ _) = Just declared
contextAsset _ = Nothing

-- request 生产方法名：get 加资产名，例如 getStartURL；消费方写 request @契约名，不直接调用它。
contextProducer :: EffectTyping -> Maybe String
contextProducer (Context declared (Just ()) _ _) = Just ("get" ++ contractOf declared)
contextProducer _ = Nothing

-- require 读取方法名：read 加资产名，例如 readStartURL；消费方写 require @契约名，不直接调用它。
contextReader :: EffectTyping -> Maybe String
contextReader (Context declared _ (Just ()) _) = Just ("read" ++ contractOf declared)
contextReader _ = Nothing

-- stream = Just ()：不在 Stream 下的持续资产，由会话反复执行 request。
declaresStream :: EffectTyping -> Bool
declaresStream (Context _ _ _ (Just ())) = True
declaresStream _ = False

-- input 是 Stream 的 Context 是它的解析器：request 声明的 getT 解析会话本次取得的原始输入。
-- getT 照常调用 Stream 的方法取得这份输入，写法与挂在原子句柄下的 Context 相同。
belowStream :: [EffectSpec] -> EffectSpec -> Bool
belowStream specifications specification = case typing specification of
  Context {} -> not (null [() | source <- specifications, name source == input specification, Stream {} <- [typing source]])
  _ -> False

-- 持续资产：require 返回 History，可以被 streams 订阅。由 Stream 下的解析器生产，或声明 stream = Just () 反复 request。
continuousContext :: [EffectSpec] -> EffectSpec -> Bool
continuousContext specifications specification =
  belowStream specifications specification || declaresStream (typing specification)

-- 业务 raise 与 SDK 协议故障分开声明；名字均指注册的 effect。
data Handles
  = RaisedBy String
  | ScopeFaultIn String
  | ContextFaultIn String
  deriving (Eq, Show, Read, Generic, NFData)

effectKind :: EffectTyping -> EffectKind
effectKind (Pure _) = PureKind
effectKind (Excu _) = ExcuKind
effectKind (Scoped _ _) = ScopedKind
effectKind Error {} = ErrorKind
effectKind Context {} = ContextKind
effectKind (Stream _) = StreamKind

-- 普通入口按角色确定，关闭方法不参与入口选择。
entryMethod :: EffectTyping -> Maybe String
entryMethod (Pure method) = method
entryMethod (Excu method) = method
entryMethod (Scoped opening _) = opening
-- Error 的两个方法由故障协议激活，不猜测一个普通 Node 入口。
entryMethod Error {} = Nothing
entryMethod selected@Context {} = contextProducer selected
-- Stream 的 handler 是它唯一的方法，但不作为 AST 末端；末端检查另行拒绝。
entryMethod (Stream method) = method

-- 表示类型引用 Types.hs 中的原生类型；不复制其 ADT 结构。
-- 识别 Output 以拒绝把完成协议声明为业务产物；业务 ADT 仍是不透明名称。
data TypeRef = TypeRef String | OutputRef TypeRef TypeRef
  deriving (Eq, Show, Read, Generic, NFData)

typeRef :: forall value. Typeable value => TypeRef
typeRef = describe (typeRep (Proxy :: Proxy value))
  where
    outputConstructor = typeRepTyCon (typeRep (Proxy :: Proxy (Output () ())))
    describe representation' = case splitTyConApp representation' of
      (constructor, [cause, value]) | constructor == outputConstructor ->
        OutputRef (describe cause) (describe value)
      _ -> TypeRef (show representation')

contractName :: TypeRef -> String
contractName (TypeRef selected) = selected
contractName (OutputRef cause value) = "Output (" ++ contractName cause ++ ") (" ++ contractName value ++ ")"

data EffectSpec = EffectSpec
  { name :: String
  , typing :: EffectTyping
  , input :: String
  , demands :: [Demand]
  } deriving (Eq, Show, Read, Generic, NFData)

-- 消费方以契约名声明需要的值与取值模式；契约名即生产方声明的资产名。
-- 契约类型由生成器产出，手写声明看不到它，因此以名字引用。
-- StreamAccess 以持续资产的新增量驱动消费，同时授予 require @T 读取交付视图；不授予 request。
data Access = RequestAccess | RequireAccess | StreamAccess
  deriving (Eq, Show, Read, Generic, NFData)

data Demand = Demand
  { access :: Access
  , contract :: String
  } deriving (Eq, Show, Read, Generic, NFData)

requests :: String -> Demand
requests = Demand RequestAccess

requires :: String -> Demand
requires = Demand RequireAccess

streams :: String -> Demand
streams = Demand StreamAccess

data ResolvedDemand = ResolvedDemand
  { demandAccess :: Access
  , demandContract :: String
  , demandProvider :: String
  } deriving (Eq, Show, Read, Generic, NFData)

findEffect :: [EffectSpec] -> String -> Either String EffectSpec
findEffect specifications selected = case filter ((== selected) . name) specifications of
  [specification] -> Right specification
  [] -> Left ("Unknown effect: " ++ selected)
  _ -> Left ("Duplicate effect: " ++ selected)

produced :: EffectSpec -> Maybe String
produced specification = contractOf <$> contextAsset (typing specification)

-- 资产名在注册集合中唯一，因此每个契约恰好对应一个生产方。
-- 取值模式须对应生产方已声明的角色：request 需要 request 角色，require 需要 require 角色。
-- branches：和类型资产的分支契约 → 基础契约；分支契约由基础契约的生产方提供（投影）。
resolveDemands :: [(String, String)] -> [EffectSpec] -> EffectSpec -> Either String [ResolvedDemand]
resolveDemands branches specifications consumer = do
  let keys = [(access demand, contract demand) | demand <- demands consumer]
  unless (length keys == length (nub keys)) $
    Left ("Duplicate demand in " ++ name consumer ++ "; each contract may be requested and required once")
  mapM resolveOne (demands consumer)
  where
    resolveOne demand = do
      let producedContract = maybe (contract demand) id (lookup (contract demand) branches)
      provider <- case [specification | specification <- specifications
            , name specification /= name consumer, produced specification == Just producedContract] of
        specification : _ -> pure specification
        [] -> Left ("No Context produces contract " ++ contract demand ++ " for " ++ name consumer
          ++ "; a contract is the asset name declared by its producer Context")
      case (access demand, typing provider) of
        (RequestAccess, _) | belowStream specifications provider -> Left ("Contract " ++ contract demand
          ++ " is parsed from Stream input by its session, so " ++ name consumer ++ " cannot request it")
        (RequestAccess, Context { request = Nothing }) -> Left ("Contract " ++ contract demand
          ++ " has no request role, so " ++ name consumer ++ " cannot request it")
        (RequireAccess, Context { require = Nothing }) -> Left ("Contract " ++ contract demand
          ++ " has no require role, so " ++ name consumer ++ " cannot require it")
        (StreamAccess, Context {}) | not (continuousContext specifications provider) -> Left ("Contract " ++ contract demand
          ++ " is not a continuous asset (hang its Context below a Stream, or declare stream = Just ()), so "
          ++ name consumer ++ " cannot subscribe to it")
        (StreamAccess, Context { require = Nothing }) -> Left ("Contract " ++ contract demand
          ++ " has no require role, so " ++ name consumer ++ " cannot read its deliveries")
        (StreamAccess, _) | producedContract /= contract demand -> Left ("Branch contract " ++ contract demand
          ++ " cannot be subscribed; subscribe to " ++ producedContract ++ " in " ++ name consumer)
        _ -> pure ()
      pure (ResolvedDemand (access demand) (contract demand) (name provider))

-- 收集声明前提所需的 Context，按依赖顺序去重；不根据业务值合并调用。
contextNames :: [(String, String)] -> [EffectSpec] -> [String] -> Either String [String]
contextNames branches specifications selected = nub . concat <$> mapM (visit []) selected
  where
    visit _ "Root" = Right []
    visit seen selectedName
      | selectedName `elem` seen = Left ("Cyclic input/demand: " ++ selectedName)
      | otherwise = do
          specification <- findEffect specifications selectedName
          resolved <- resolveDemands branches specifications specification
          let providers = nub (map demandProvider resolved)
          upstream <- concat <$> mapM (visit (selectedName : seen)) (nub (input specification : providers))
          pure (upstream ++ providers)
