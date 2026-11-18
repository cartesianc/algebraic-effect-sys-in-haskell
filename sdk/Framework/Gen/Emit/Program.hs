{-# LANGUAGE DuplicateRecordFields #-}

-- 输出 Generated/Program.hs 的程序部分：末端入口、选择读取与会话步骤的登记，以及绑定好元数据的 interpreter。
-- 原型本身由 Framework.Gen.Emit.Prototype 渲染并追加在后面。
module Framework.Gen.Emit.Program (renderProgram) where

import Data.List (intercalate)
import Framework.Gen.Plan

renderProgram :: Unit -> String
renderProgram unit = unlines (programHeader ++ astInterpreter)
  where
    namespace = unitNamespace unit
    selected = map fst (unitTerminals unit)
    programHeader =
      [ "{-# LANGUAGE DuplicateRecordFields #-}"
      , ""
      , "-- 自动生成；只登记末端入口与原型，执行由 SDK 的 interpreter 完成。"
      , "module " ++ namespace ++ ".Generated.Program where"
      , ""
      , "import Framework.Generated (EffectSpec(..), EffectTyping(..), Asset(..), Handles(..), Demand(..), Access(..), TypeRef(..))"
      , "import qualified Framework.Generated as SDK"
      , "import " ++ namespace ++ ".Generated.Effects"
      , "import qualified " ++ namespace ++ ".Generated.Handlers as Handlers"
      , "import " ++ namespace ++ ".Types"
      , ""
      ]
    selectors = unitSelectors unit
    astInterpreter =
      [ ""
      , "-- 仅汇总所选末端的成功结果，不保存共享绑定或增加完成包装。"
      , "data Results = " ++ intercalate " | " [terminal ++ "Result ()" | terminal <- selected]
      , "  deriving Show"
      , ""
      , "-- 末端共享生成的 scope 句柄；只创建空状态，Node algebra 才 lower。"
      , "-- 第二个列表是各转折契约的选择末端：驱动资产（持续资产领取本次交付），返回它当前的构造器名。"
      , "-- 第三个列表是各持续资产的生产步骤：会话按需启动，Stream 单步取得原始输入（或领取一条上游交付），parser 发布一次资产。"
      , "compiledEntries :: IO ([SDK.Target ContextValues Errors Results], [SDK.Target ContextValues Errors String]"
      , "                     , [(String, SDK.SessionSteps ContextValues Errors)])"
      , "compiledEntries = do"
      , "  scopes <- Handlers.newScopeHandlers"
      , "  pure"
      , "    ( " ++ renderList "      "
          [ wrapTarget terminal (terminal ++ "Result <$> (() <$ Handlers." ++ method ++ ")")
          | (terminal, method) <- unitTerminals unit ]
      , "    , " ++ renderList "      "
          [ wrapTarget contractType ("caseOf" ++ contractType ++ " <$> Handlers." ++ selector)
          | selectedSelector <- selectors
          , let contractType = selectorContract selectedSelector
                selector = selectorEntry selectedSelector ]
      , "    , " ++ renderList "      " sessionSteps
      , "    )"
      , ""
      ] ++ concat
      [ [ "caseOf" ++ contractType ++ " :: " ++ contractType ++ " -> String"
        , "caseOf" ++ contractType ++ " (" ++ contractType ++ " value) = case value of" ]
        ++ [ "  " ++ constructor ++ " {} -> " ++ show constructor | constructor <- selectorConstructors selectedSelector ]
        ++ [ "" ]
      | selectedSelector <- selectors
      , let contractType = selectorContract selectedSelector ] ++
      [ "-- SDK 装配入口，不需要用户提供节点执行器或重复选择 handler。"
      , "interpreter :: SDK.AST -> [EffectSpec] -> IO ()"
      , "interpreter = SDK.interpreter " ++ show namespace
          ++ " " ++ show ("demo/" ++ map (\character -> if character == '.' then '/' else character) namespace ++ "/Handlers.hs")
          ++ " Handlers.handlerSourceFingerprint generatedPrototype compiledEntries"
      ]
    -- 按 Context 注册名登记（与运行时绑定来源同名）。Receive：Stream 单步取得原始输入，parser 解析它并发布。
    -- Derive：领取一条上游交付后只执行 parser，它沿 Input 链执行被驱动的句柄并发布。
    sessionSteps = map renderSession (unitSessionEntries unit)
    renderSession entry = case entry of
      ReceiveEntry producer source parser -> "(" ++ show producer ++ ", SDK.receiveSteps ("
        ++ action source "" ++ ") (" ++ action parser "() <$ " ++ "))"
      DeriveEntry producer parser -> "(" ++ show producer ++ ", SDK.deriveSteps ("
        ++ action parser "() <$ " ++ "))"
      where action mounted prefix = wrapTarget (mountTarget mounted) (prefix ++ "Handlers." ++ mountMethod mounted)
    wrapTarget label action = "SDK.targetApp " ++ show label ++ " emptyContexts scopes"
      ++ " (SDK.withErrorHandlers Handlers.errorHandlers"
      ++ " (SDK.withAnchoredContexts Handlers.contextInjections"
      ++ " (SDK.withStreamContexts Handlers.streamContextInjections"
      ++ " (SDK.withScopeCleanups Handlers.scopeCleanups (" ++ action ++ ")))))"
    renderList _ [] = "[]"
    renderList indent items = "[ " ++ intercalate ("\n" ++ indent ++ ", ") items ++ "\n" ++ indent ++ "]"
