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

-- 源语言的注册声明：用户在 Effects.hs 中写下的 ADT 与 demand 组合子，不执行 handler。
-- 名字推导、资产来源与访问规则属于编译器：Framework.Gen.Names、Framework.Gen.Composition。
module Framework.Language.Registration
  ( EffectTyping(..), EffectKind(..), effectKind, allEffects
  , Asset(.., Asset), contractOf, contextAsset
  , Handles(..), TypeRef(..), typeRef, contractName
  , EffectSpec(..), Demand(..), Access(..), requests, requires, streams
  ) where

import Framework.Language.Handler (Output)
import Control.DeepSeq (NFData)
import GHC.Generics (Generic)
import Data.Proxy (Proxy(..))
import Data.Typeable (Typeable, splitTyConApp, typeRep, typeRepTyCon)

-- 每个字段写 handler 名：handler 是不带参数的类方法，可以被多个注册复用。
-- effect 自己的方法由 gen 按 effect 名或资产名生成，只在生成区使用。
data EffectTyping
  -- 生产链中的纯值变换：用 raw 读上层（Excu、Scoped 或 Pure）交出的 [String]，变换后交给下面的 Pure 或 Context；
  -- 不声明 demands，不作为 AST 末端，必须绑定 handler。
  = Pure { handler :: Maybe String }
  -- 原子句柄：Excu 与 Scoped 的 open／close 交出 [String]，只交给挂在它下面（可经 Pure）的 Context 解析。
  | Excu { handler :: Maybe String }
  | Scoped { open :: Maybe String, close :: Maybe String }
  -- handles 按错误类型匹配；作用的 scope 由 Input 链上最近的 Scoped 推导，不手写连接。
  | Error { detect :: Maybe String, resolve :: Maybe String, handles :: [Handles] }
  -- Context 只有一个 parser handler，产出资产的表示类型。require = True 缓存最新值，
  -- stream = True 表示持续发布；Input 链由 Stream 或 streams demand 持续驱动时必须为 True，且要求 require = True。
  -- gen 按资产名生成 getT（驱动 parser）、readT 或 streamT（读取缓存）。
  | Context { asset :: Asset, parser :: Maybe String, require :: Bool, stream :: Bool }
  -- 持续生产节点。handler 每次调用取得一份原始输入（String），SDK 负责反复调用；
  -- 不作为 AST 末端，只经挂在它下面的 Context 解析后进入资产。
  | Stream { handler :: Maybe String }
  -- 驱动方式特殊的 Excu：没有 Input 前驱（input 写保留名 "None"），也不声明 demands；由 AST 的 middleware 标注挂载。
  -- 标注范围内，intercept 类别的 effect 在 Root 级调用点（交出值、raw、raise）同步执行它，handler 用 hooked* 拆出捕获。
  | Middleware { handler :: Maybe String, intercept :: [EffectKind] }
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

-- RaisedBy 写 handler 名：失败属于 handler，不属于调用它的链。
-- ScopeFaultIn／ContextFaultIn 写 effect 名，指 SDK 协议故障发生的注册。
data Handles
  = RaisedBy String
  | ScopeFaultIn String
  | ContextFaultIn String
  deriving (Eq, Show, Read, Generic, NFData)

-- 注册类别：只保留类别，handler 名由注册描述。
data EffectKind = PureKind | ExcuKind | ScopedKind | ErrorKind | ContextKind | StreamKind | MiddlewareKind
  deriving (Eq, Show, Read, Generic, NFData)

-- intercept 的全类别简写：首版捕获能交出 raw output 的 Excu、Scoped（open／close）与 Pure。
allEffects :: [EffectKind]
allEffects = [ExcuKind, ScopedKind, PureKind]

effectKind :: EffectTyping -> EffectKind
effectKind (Pure _) = PureKind
effectKind (Excu _) = ExcuKind
effectKind (Scoped _ _) = ScopedKind
effectKind Error {} = ErrorKind
effectKind Context {} = ContextKind
effectKind (Stream _) = StreamKind
effectKind Middleware {} = MiddlewareKind

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
-- 三种 demand 是驱动关系：requests 沿 Input 驱动资产的整条 Context 链（gen 在入口先调用 getT），
-- requires 只读取本次最新值，streams 在持续驱动位置读取本次交付。两者都按声明表示类型 require；
-- 记录、统计等数据形状由业务资产决定，不因持续驱动增加 SDK 包装。
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
