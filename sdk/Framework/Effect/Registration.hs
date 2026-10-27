{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}

-- 纯注册描述与依赖解析，不执行 handler。
module Framework.Effect.Registration
  ( EffectTyping(..), Producer(..), Handles(..), TypeRef(..), typeRef, contractName
  , EffectSpec(..), Demand(..), Access(..), requests, requires
  , ResolvedDemand(..), resolveDemands, contextNames
  , effectKind, entryMethod
  ) where

import Framework.Effect.Contract (EffectKind(..), Output)
import Control.Monad (unless)
import Data.List (intercalate, nub)
import Data.Proxy (Proxy(..))
import Data.Typeable (Typeable, splitTyConApp, typeRep, typeRepTyCon)

data EffectTyping
  = Pure { handler :: Maybe String }
  | Excu { handler :: Maybe String }
  | Scoped { open :: Maybe String, close :: Maybe String }
  -- handles 按错误类型匹配；作用的 scope 由 Input 链上最近的 Scoped 推导，不手写连接。
  | Error { detect :: Maybe String, resolve :: Maybe String, handles :: [Handles] }
  | Context { request :: Maybe Producer, require :: Maybe String }
  deriving (Eq, Show, Read)

-- Context.request 声明业务产物；完成和失败协议由 SDK 提供。
data Producer = Producer
  { handler :: String
  , produces :: TypeRef
  } deriving (Eq, Show, Read)

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
effectKind (Context _ _) = ContextKind

-- 普通入口按角色确定，关闭方法不参与入口选择。
entryMethod :: EffectTyping -> Maybe String
entryMethod (Pure method) = method
entryMethod (Excu method) = method
entryMethod (Scoped opening _) = opening
-- Error 的两个方法由故障协议激活，不猜测一个普通 Node 入口。
entryMethod Error {} = Nothing
entryMethod (Context producing _) = case producing of
  Just Producer { handler = method } -> Just method
  Nothing -> Nothing

-- 2. 注册只保存类型引用；data/newtype 定义与 deriving 由业务作者直接书写。
-- typeRef @BusinessType 检查引用的类型存在，不构造业务值，也不复制其 ADT 结构。
-- 识别 Output 以拒绝把完成协议再次声明为业务产物；业务 ADT 仍是不透明名称。
-- 代码生成使用类型的显示名称，该类型须在生成区所在模块中可见。
data TypeRef = TypeRef String | OutputRef TypeRef TypeRef
  deriving (Eq, Show, Read)

typeRef :: forall value. Typeable value => TypeRef
typeRef = describe (typeRep (Proxy :: Proxy value))
  where
    outputConstructor = typeRepTyCon (typeRep (Proxy :: Proxy (Output () ())))
    describe representation = case splitTyConApp representation of
      (constructor, [cause, value]) | constructor == outputConstructor ->
        OutputRef (describe cause) (describe value)
      _ -> TypeRef (show representation)

contractName :: TypeRef -> String
contractName (TypeRef selected) = selected
contractName (OutputRef cause value) = "Output (" ++ contractName cause ++ ") (" ++ contractName value ++ ")"

data EffectSpec = EffectSpec
  { name :: String
  , typing :: EffectTyping
  , input :: String
  , demands :: [Demand]
  } deriving (Eq, Show, Read)

-- 消费方只声明需要的契约类型与取值模式，不指名生产方；来源由生成器在注册集合中唯一解析。
-- 不同业务含义用 Types.hs 中不同的类型（必要时为 newtype）表达，类型即装配键。
data Access = RequestAccess | RequireAccess
  deriving (Eq, Show, Read)

data Demand = Demand
  { access :: Access
  , contract :: TypeRef
  } deriving (Eq, Show, Read)

requests :: forall value. Typeable value => Demand
requests = Demand RequestAccess (typeRef @value)

requires :: forall value. Typeable value => Demand
requires = Demand RequireAccess (typeRef @value)

data ResolvedDemand = ResolvedDemand
  { demandAccess :: Access
  , demandContract :: TypeRef
  , demandProvider :: String
  } deriving (Eq, Show, Read)

findEffect :: [EffectSpec] -> String -> Either String EffectSpec
findEffect specifications selected = case filter ((== selected) . name) specifications of
  [specification] -> Right specification
  [] -> Left ("Unknown effect: " ++ selected)
  _ -> Left ("Duplicate effect: " ++ selected)

produced :: EffectSpec -> Maybe TypeRef
produced specification = case typing specification of
  Context (Just Producer { produces = selected }) _ -> Just selected
  _ -> Nothing

-- 每个被需要的契约类型在注册集合中恰好有一个其他 Context 生产方，与 instance 一致性同理。
-- 多个候选一律报错并列出，不按距离、ScopeTree 或拓扑选择；新增生产方不会静默改变已有接线。
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
        [specification] -> pure specification
        [] -> Left ("No Context produces " ++ contractName (contract demand) ++ " for " ++ name consumer)
        candidates -> Left ("Several Contexts produce " ++ contractName (contract demand) ++ " for "
          ++ name consumer ++ ": " ++ intercalate ", " (map name candidates)
          ++ "; give each meaning its own type in Types.hs")
      case (access demand, typing provider) of
        (RequireAccess, Context _ Nothing) ->
          Left ("requires needs a Context with a require method: " ++ name provider)
        _ -> pure ()
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
