{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE ScopedTypeVariables #-}

-- 纯注册描述与依赖解析，不执行 handler。
module Framework.Effect.Registration
  ( EffectTyping(..), Producer(..), TypeRef(..), typeRef, EffectSpec(..), ContextInput(..), ValueSource(..)
  , effectKind, entryMethod, requestInput, requireInput, requestSource, sourceName, sourceType, contextNames
  ) where

import Framework.Effect.Contract (EffectKind(..), Output)
import Data.List (nub)
import Data.Maybe (maybeToList)
import Data.Proxy (Proxy(..))
import Data.Typeable (Typeable, splitTyConApp, typeRep, typeRepTyCon)

data EffectTyping
  = Pure { handler :: Maybe String }
  | Excu { handler :: Maybe String }
  | Scoped { open :: Maybe String, close :: Maybe String }
  | Context { request :: Maybe Producer, require :: Maybe String }
  deriving (Eq, Show, Read)

-- Context.request 声明业务产物；完成和失败协议由 SDK 提供。
data Producer = Producer
  { handler :: String
  , produces :: TypeRef
  } deriving (Eq, Show, Read)

effectKind :: EffectTyping -> EffectKind
effectKind (Pure _) = PureKind
effectKind (Excu _) = ExcuKind
effectKind (Scoped _ _) = ScopedKind
effectKind (Context _ _) = ContextKind

-- 普通入口按角色确定，关闭方法不参与入口选择。
entryMethod :: EffectTyping -> Maybe String
entryMethod (Pure method) = method
entryMethod (Excu method) = method
entryMethod (Scoped opening _) = opening
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

data EffectSpec = EffectSpec
  { name :: String
  , typing :: EffectTyping
  , input :: String
  , context :: Maybe ContextInput
  } deriving (Eq, Show, Read)

-- 消费方声明：request 重新求值，require 读取已有绑定；不是生产方的方法名。
data ContextInput = ContextInput
  { request :: Maybe ValueSource
  , require :: Maybe ValueSource
  } deriving (Eq, Show, Read)

-- 引用来源 effect 和接收的业务 ADT 类型，不构造业务值。
data ValueSource = From String TypeRef
  deriving (Eq, Show, Read)

sourceName :: ValueSource -> String
sourceName (From selected _) = selected

sourceType :: ValueSource -> TypeRef
sourceType (From _ contract) = contract

requestInput :: EffectSpec -> Maybe ValueSource
requestInput specification = case context specification of
  Just ContextInput { request = selected } -> selected
  Nothing -> Nothing

requireInput :: EffectSpec -> Maybe ValueSource
requireInput specification = case context specification of
  Just ContextInput { require = selected } -> selected
  Nothing -> Nothing

requestSource :: EffectSpec -> Maybe String
requestSource = fmap sourceName . requestInput

findEffect :: [EffectSpec] -> String -> Either String EffectSpec
findEffect specifications selected = case filter ((== selected) . name) specifications of
  [specification] -> Right specification
  [] -> Left ("Unknown effect: " ++ selected)
  _ -> Left ("Duplicate effect: " ++ selected)

-- 收集声明前提所需的 Context，按依赖顺序去重；不根据业务值或类型合并调用。
contextNames :: [EffectSpec] -> [String] -> Either String [String]
contextNames specifications selected = nub . concat <$> mapM (visit []) selected
  where
    visit _ "Root" = Right []
    visit seen selectedName
      | selectedName `elem` seen = Left ("Cyclic input/request/context: " ++ selectedName)
      | otherwise = do
          specification <- findEffect specifications selectedName
          let next = selectedName : seen
          requested <- mapM (checkSource False) (maybeToList (requestInput specification))
          required <- mapM (checkSource True) (maybeToList (requireInput specification))
          upstream <- concat <$> mapM (visit next)
            (nub (input specification : requested ++ required))
          pure (upstream ++ requested ++ required)
    checkSource reading dependency = do
      let selectedName = sourceName dependency
      source <- findEffect specifications selectedName
      case typing source of
        Context producing readingMethod
          | if reading then readingMethod /= Nothing else producing /= Nothing -> Right selectedName
        _ -> Left ((if reading then "context.require" else "context.request")
                   ++ " must reference a Context with the corresponding method: " ++ selectedName)
