{-# LANGUAGE DuplicateRecordFields #-}

-- 输出 Generated/Program.hs 的程序部分：末端入口、选择读取与会话步骤的登记，以及绑定好元数据的 interpreter。
-- 原型本身由 Framework.Gen.Emit.Prototype 渲染并追加在后面。
module Framework.Gen.Emit.Program (renderProgram) where

import Data.List (intercalate, nub)
import Framework.Gen.Bind
import Framework.Gen.Names (contextProducer, contextReader, entryMethod)
import Framework.Language.Registration (EffectSpec(..))
import qualified Framework.Prototype as Prototype

renderProgram :: Unit -> String
renderProgram unit = unlines (programHeader ++ astInterpreter)
  where
    namespace = unitNamespace unit
    selected = map fst (unitTerminals unit)
    workflow = Prototype.plannedWorkflow (unitPlan unit)
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
    selectorContracts = nub (Prototype.workflowSelectors workflow)
    readerOfContract contractType =
      [ reader | AssetDeclaration declared _ owner <- unitAssets unit, declared == contractType
      , Just reader <- [contextReader (typing (specOf unit owner))] ]
    branchesOf contractType = [branchConstructor branch | branch <- unitBranches unit, branchBase branch == contractType]
    astInterpreter =
      [ ""
      , "-- 仅汇总所选末端的成功结果，不保存共享绑定或增加完成包装。"
      , "data Results = " ++ intercalate " | " [terminal ++ "Result ()" | terminal <- selected]
      , "  deriving Show"
      , ""
      , "-- 末端共享生成的 scope 句柄；只创建空状态，Node algebra 才 lower。"
      , "-- 第二个列表是各转折契约的读取末端：读取资产，返回它当前的构造器名。"
      , "-- 第三个列表是各持续资产的生产步骤：会话按需启动，Stream 单步取得原始输入，parser 发布一次资产。"
      , "compiledEntries :: IO ([SDK.Target ContextValues Errors Results], [SDK.Target ContextValues Errors String]"
      , "                     , [(String, SDK.SessionSteps ContextValues Errors)])"
      , "compiledEntries = do"
      , "  scopes <- Handlers.newScopeHandlers"
      , "  pure"
      , "    ( " ++ renderList "      "
          [ wrapTarget terminal (terminal ++ "Result <$> (() <$ Handlers." ++ method ++ ")")
          | (terminal, method) <- unitTerminals unit ]
      , "    , " ++ renderList "      "
          [ wrapTarget contractType ("caseOf" ++ contractType ++ " <$> Handlers." ++ reader)
          | contractType <- selectorContracts, reader <- readerOfContract contractType ]
      , "    , " ++ renderList "      " sessionSteps
      , "    )"
      , ""
      ] ++ concat
      [ if continuousContract unit contractType
          -- 持续资产读到交付视图：按本次交付的最新条目分派（交付视图至少有一条）。
          then [ "caseOf" ++ contractType ++ " :: SDK.History " ++ contractType ++ " -> String"
               , "caseOf" ++ contractType ++ " history = case SDK.latest history of"
               , "  Just (" ++ contractType ++ " value) -> case value of" ]
               ++ [ "    " ++ constructor ++ " {} -> " ++ show constructor | constructor <- branchesOf contractType ]
               ++ [ "  Nothing -> \"\"", "" ]
          else [ "caseOf" ++ contractType ++ " :: " ++ contractType ++ " -> String"
               , "caseOf" ++ contractType ++ " (" ++ contractType ++ " value) = case value of" ]
               ++ [ "  " ++ constructor ++ " {} -> " ++ show constructor | constructor <- branchesOf contractType ]
               ++ [ "" ]
      | contractType <- selectorContracts ] ++
      [ "-- SDK 装配入口，不需要用户提供节点执行器或重复选择 handler。"
      , "interpreter :: SDK.AST -> [EffectSpec] -> IO ()"
      , "interpreter = SDK.interpreter " ++ show namespace
          ++ " " ++ show ("demo/" ++ map (\character -> if character == '.' then '/' else character) namespace ++ "/Handlers.hs")
          ++ " Handlers.handlerSourceFingerprint generatedPrototype compiledEntries"
      ]
    -- 按 Context 注册名登记（与运行时绑定来源同名）：Stream 单步取得原始输入，parser 解析它并发布。
    sessionSteps =
      [ "(" ++ show (name specification) ++ ", SDK.receiveSteps ("
          ++ wrapTarget (input specification) ("Handlers." ++ handle) ++ ") ("
          ++ wrapTarget (name specification) ("() <$ Handlers." ++ parsing) ++ "))"
      | specification <- contextSpecs unit, Prototype.effectContinuous (protoOf unit (name specification))
      , Just parsing <- [contextProducer (typing specification)]
      , Just handle <- [entryMethod (specOf unit (input specification))] ]
    wrapTarget label action = "SDK.targetApp " ++ show label ++ " emptyContexts scopes"
      ++ " (SDK.withErrorHandlers Handlers.errorHandlers"
      ++ " (SDK.withAnchoredContexts Handlers.contextInjections"
      ++ " (SDK.withScopeCleanups Handlers.scopeCleanups (" ++ action ++ "))))"
    renderList _ [] = "[]"
    renderList indent items = "[ " ++ intercalate ("\n" ++ indent ++ ", ") items ++ "\n" ++ indent ++ "]"
