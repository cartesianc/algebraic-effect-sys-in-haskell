{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeAbstractions #-}
{-# LANGUAGE TypeApplications #-}

-- 纯注册描述与依赖解析，不执行 handler。
module Framework.Effect.Registration
  ( EffectTyping(..), Requester(..), requester, contractOf, contextReader, Handles(..), TypeRef(..), typeRef, contractName
  , EffectSpec(..), Demand(..), Access(..), requests, requires
  , ResolvedDemand(..), resolveDemands, contextNames
  , effectKind, entryMethod
  ) where

import Framework.Effect.Contract (EffectKind(..), Output)
import Control.Monad (unless)
import Data.Char (toUpper)
import Data.List (nub)
import Data.Proxy (Proxy(..))
import Data.Typeable (Typeable, splitTyConApp, typeRep, typeRepTyCon)

data EffectTyping
  = Pure { handler :: Maybe String }
  | Excu { handler :: Maybe String }
  | Scoped { open :: Maybe String, close :: Maybe String }
  -- handles 按错误类型匹配；作用的 scope 由 Input 链上最近的 Scoped 推导，不手写连接。
  | Error { detect :: Maybe String, resolve :: Maybe String, handles :: [Handles] }
  -- Context 只声明生产方法；require 的读取方法由生成器按契约名自动命名。
  | Context { request :: Maybe Requester }
  deriving (Eq, Show, Read)

-- Context 的生产入口。handler 名同时决定契约类型名：首字母大写后由生成器产出
-- newtype 契约 = 契约 表示类型，例如 handler "startURL" 与 PageURL 产出 newtype StartURL = StartURL PageURL。
data Requester = Requester
  { handler :: String
  , representation :: TypeRef
  } deriving (Eq, Show, Read)

-- 写作 requester "startURL" @PageURL：先 handler 名，后被包装的表示类型。
requester :: String -> forall value. Typeable value => Maybe Requester
requester method @value = Just (Requester method (typeRef @value))

-- 契约类型名由 handler 名推导，是生产方与消费方共享的唯一键。
contractOf :: Requester -> String
contractOf Requester { handler = method } = case method of
  first : rest -> toUpper first : rest
  [] -> []

-- require 读取方法名：read 加契约名，例如 readStartURL；消费方写 require @契约名，不直接调用它。
contextReader :: EffectTyping -> Maybe String
contextReader (Context (Just producing)) = Just ("read" ++ contractOf producing)
contextReader _ = Nothing

-- 业务 raise 与 SDK 协议故障分开声明；名字均指注册的 effect。
data Handles
  = RaisedBy String
  | ScopeFaultIn String
  | ContextFaultIn String
  deriving (Eq, Show, Read)

effectKind :: EffectTyping -> EffectKind
effectKind (Pure _) = PureKind
effectKind (Excu _) = ExcuKind
effectKind (Scoped _ _) = ScopedKind
effectKind Error {} = ErrorKind
effectKind (Context _) = ContextKind

-- 普通入口按角色确定，关闭方法不参与入口选择。
entryMethod :: EffectTyping -> Maybe String
entryMethod (Pure method) = method
entryMethod (Excu method) = method
entryMethod (Scoped opening _) = opening
-- Error 的两个方法由故障协议激活，不猜测一个普通 Node 入口。
entryMethod Error {} = Nothing
entryMethod (Context producing) = case producing of
  Just Requester { handler = method } -> Just method
  Nothing -> Nothing

-- 表示类型引用 Types.hs 中的原生类型；不复制其 ADT 结构。
-- 识别 Output 以拒绝把完成协议声明为业务产物；业务 ADT 仍是不透明名称。
data TypeRef = TypeRef String | OutputRef TypeRef TypeRef
  deriving (Eq, Show, Read)

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
  } deriving (Eq, Show, Read)

-- 消费方以契约名声明需要的值与取值模式；契约名即生产方 handler 名首字母大写。
-- 契约类型由生成器产出，手写声明看不到它，因此以名字引用。
data Access = RequestAccess | RequireAccess
  deriving (Eq, Show, Read)

data Demand = Demand
  { access :: Access
  , contract :: String
  } deriving (Eq, Show, Read)

requests :: String -> Demand
requests = Demand RequestAccess

requires :: String -> Demand
requires = Demand RequireAccess

data ResolvedDemand = ResolvedDemand
  { demandAccess :: Access
  , demandContract :: String
  , demandProvider :: String
  } deriving (Eq, Show, Read)

findEffect :: [EffectSpec] -> String -> Either String EffectSpec
findEffect specifications selected = case filter ((== selected) . name) specifications of
  [specification] -> Right specification
  [] -> Left ("Unknown effect: " ++ selected)
  _ -> Left ("Duplicate effect: " ++ selected)

produced :: EffectSpec -> Maybe String
produced specification = case typing specification of
  Context (Just producing) -> Just (contractOf producing)
  _ -> Nothing

-- 契约名来自 handler 名，而方法名在注册集合中唯一，因此每个契约恰好对应一个生产方。
resolveDemands :: [EffectSpec] -> EffectSpec -> Either String [ResolvedDemand]
resolveDemands specifications consumer = do
  let keys = [(access demand, contract demand) | demand <- demands consumer]
  unless (length keys == length (nub keys)) $
    Left ("Duplicate demand in " ++ name consumer ++ "; each contract may be requested and required once")
  mapM resolveOne (demands consumer)
  where
    resolveOne demand = do
      provider <- case [specification | specification <- specifications
            , name specification /= name consumer, produced specification == Just (contract demand)] of
        specification : _ -> pure specification
        [] -> Left ("No Context produces contract " ++ contract demand ++ " for " ++ name consumer
          ++ "; a contract is named after its producer's handler with the first letter capitalized")
      pure (ResolvedDemand (access demand) (contract demand) (name provider))

-- 收集声明前提所需的 Context，按依赖顺序去重；不根据业务值合并调用。
contextNames :: [EffectSpec] -> [String] -> Either String [String]
contextNames specifications selected = nub . concat <$> mapM (visit []) selected
  where
    visit _ "Root" = Right []
    visit seen selectedName
      | selectedName `elem` seen = Left ("Cyclic input/demand: " ++ selectedName)
      | otherwise = do
          specification <- findEffect specifications selectedName
          resolved <- resolveDemands specifications specification
          let providers = nub (map demandProvider resolved)
          upstream <- concat <$> mapM (visit (selectedName : seen)) (nub (input specification : providers))
          pure (upstream ++ providers)
