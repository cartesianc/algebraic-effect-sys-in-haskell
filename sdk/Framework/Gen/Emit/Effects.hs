{-# LANGUAGE DuplicateRecordFields #-}

-- 输出 Generated/Effects.hs：资产的名义类型、effect 方法身份、每个 handler 的类／Layer／错误，
-- 统一的错误分类与 Context 存储。只渲染绑定阶段定下的事实。
module Framework.Gen.Emit.Effects (renderEffects) where

import Data.Char (toUpper)
import Data.List (intercalate)
import Framework.Gen.Bind
import Framework.Gen.Names (handlerClass, handlerError, handlerFailure, handlerLayer)
import Framework.Language.Registration (EffectSpec(..), contextAsset, contractOf)

renderEffects :: Unit -> String
renderEffects unit = unlines (contractHeader ++ runtimeAliases ++ generatedContracts ++ methodIdentities
    ++ concatMap handlerContract (unitSignatures unit) ++ errorDeclaration ++ contextDeclarations)
  where
    contractHeader =
      [ "{-# LANGUAGE ConstraintKinds #-}"
      , "{-# LANGUAGE DeriveGeneric #-}"
      , "{-# LANGUAGE FlexibleContexts #-}"
      , "{-# LANGUAGE FlexibleInstances #-}"
      , "{-# LANGUAGE MonoLocalBinds #-}"
      , "{-# LANGUAGE StandaloneDeriving #-}"
      , "{-# LANGUAGE UndecidableInstances #-}"
      , ""
      , "-- 自动生成；通过 SDK 的 effect-codegen 更新，手写注册与 handler 位于上级目录。"
      , "module " ++ unitNamespace unit ++ ".Generated.Effects where"
      , ""
      , "import qualified Framework.Generated as SDK"
      , "import Control.Monad.IO.Class (MonadIO)"
      , "import " ++ unitNamespace unit ++ ".Types"
      , ""
      ]
    runtimeAliases =
      [ "-- SDK 提供运行载体；资产存储与错误分类由本文件给出。"
      , "type App = SDK.App ContextValues Errors"
      , ""
      ]
    -- 资产的名义类型只在生成区使用：handler 按表示类型读取，不构造或匹配它们。
    generatedContracts = case unitAssets unit of
      [] -> []
      declarations -> "-- 每个 Context 的资产类型：名字来自 Asset 声明，包装其表示类型。"
        : concat
          [ [ "newtype " ++ generated ++ " = " ++ generated ++ " (" ++ reference representation' ++ ")"
            , "deriving instance Eq (" ++ reference representation' ++ ") => Eq " ++ generated
            , "deriving instance Show (" ++ reference representation' ++ ") => Show " ++ generated
            , "" ]
          | AssetDeclaration generated representation' _ <- declarations ]
    genName [] = "MissingMethodGen"
    genName (first : rest) = toUpper first : rest ++ "Gen"
    methodIdentities =
      [ "-- effect 方法的定义身份；仅生成区使用，图中不以字符串匹配方法。"
      , "data MethodGen = " ++ intercalate " | " (map genName (allMethods unit))
      , "  deriving (Eq, Ord, Show, Read, SDK.Generic)"
      , "instance SDK.NFData MethodGen"
      , ""
      ]
    -- 每个 handler 一个类：Layer 是它能用的全部能力，来自绑定的 effect 的 demands 与类别。
    handlerContract (Signature handler' result layer bound) =
      [ "-- handler " ++ handler' ++ "：绑定到 " ++ intercalate "、" bound ++ "。"
      , "type " ++ handlerLayer handler' ++ " m = (" ++ intercalate ", "
          (init layer ++ ["SDK.Raises " ++ handlerError handler' ++ " m", last layer]) ++ ")"
      , "class " ++ handlerClass handler' ++ " m where"
      , "  " ++ handler' ++ " :: m " ++ parenthesized result
      , ""
      , "-- 失败属于 handler：发生位置由 SDK 记录，Error 按 RaisedBy " ++ show handler' ++ " 匹配。"
      , "newtype " ++ handlerError handler' ++ " = " ++ handlerError handler' ++ " String"
      , "  deriving (Eq, Show, Read)"
      , ""
      ]
    errorDeclaration =
      [ "-- 统一失败协议的分类标签：每个 handler 一个；消息与发生位置由 SDK.Failure 保存。"
      , "data Errors = " ++ intercalate " | "
          (map handlerFailure (unitHandlers unit)
           ++ ["ContextBindingError SDK.ContextFault", "ScopeBindingError SDK.ScopeFault"])
      , "  deriving (Eq, Show)"
      , ""
      ]
    contextDeclarations =
      [ "-- SDK 内部存储：Nothing 仅表示本次运行尚未建立绑定，不是业务缺值。"
      , "data ContextValues = ContextValues"
      ] ++ (case ["bound" ++ name s ++ " :: Maybe " ++ contractOf declared
                  | s <- contextSpecs unit, Just declared <- [contextAsset (typing s)]] of
        [] -> [""]
        fields -> ["  { " ++ intercalate "\n  , " fields, "  }", ""])
      ++ [ "emptyContexts :: ContextValues"
         , "emptyContexts = ContextValues" ++ concat [" Nothing" | _ <- contextSpecs unit]
         , ""
         ]
