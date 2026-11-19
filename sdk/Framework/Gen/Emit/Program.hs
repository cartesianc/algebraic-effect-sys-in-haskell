{-# LANGUAGE DuplicateRecordFields #-}

-- 输出 Generated/Program.hs 的程序部分：末端入口、选择读取与会话步骤的登记，以及绑定好元数据的 interpreter。
-- 原型本身由 Framework.Gen.Emit.Prototype 渲染并追加在后面。
module Framework.Gen.Emit.Program (renderProgram) where

import Data.List (intercalate)
import Framework.Gen.Plan
import Framework.Prototype (ChainRole(..), variantLabel)

renderProgram :: Maybe String -> Unit -> String
renderProgram typesFingerprint unit = unlines (programHeader ++ astInterpreter)
  where
    namespace = unitNamespace unit
    selected = map fst (unitTerminals unit)
    hooked = any ((== MiddlewareOperation) . bindingOperation) (unitBindings unit)
    programHeader =
      [ "{-# LANGUAGE DuplicateRecordFields #-}" ]
      ++ (if hooked then ["{-# LANGUAGE DataKinds #-}", "{-# LANGUAGE TypeApplications #-}"] else [])
      ++
      [ ""
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
          [ wrapTarget hooks (variantLabel terminal hooks) (terminal ++ "Result <$> (() <$ " ++ handlers hooks method ++ ")")
          | (terminal, method) <- unitTerminals unit, hooks <- variantsOf NodeChain terminal ]
      , "    , " ++ renderList "      "
          [ wrapTarget hooks (variantLabel contractType hooks) ("caseOf" ++ contractType ++ " <$> " ++ handlers hooks selector)
          | selectedSelector <- selectors
          , let contractType = selectorContract selectedSelector
                selector = selectorEntry selectedSelector
          , hooks <- variantsOf SelectorChain contractType ]
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
          ++ " [" ++ intercalate ", " sourceChecks ++ "] generatedPrototype compiledEntries"
      ]
    sourceChecks = ["(" ++ sourcePath "Handlers.hs" ++ ", Handlers.handlerSourceFingerprint)"]
      ++ ["(" ++ sourcePath "Types.hs" ++ ", " ++ show typesFingerprint ++ ")" | not (null selectors)]
    sourcePath file = show ("demo/" ++ map (\c -> if c == '.' then '/' else c) namespace ++ "/" ++ file)
    -- 按 Context 注册名登记（与运行时绑定来源同名）。Receive：Stream 单步取得原始输入，parser 解析它并发布。
    -- Derive：领取一条上游交付后只执行 parser，它沿 Input 链执行被驱动的句柄并发布。
    -- 会话按所在位置的 Middleware 集合登记；同一会话的各步骤位置被同一组标注覆盖。
    sessionSteps = map renderSession (unitSessionEntries unit)
    renderSession entry = case entry of
      ReceiveEntry producer source parser -> let hooks = mountHooks unit (mountNode source) in
        "(" ++ show (variantLabel producer hooks) ++ ", SDK.receiveSteps ("
        ++ action hooks source "" ++ ") (" ++ action hooks parser "() <$ " ++ "))"
      DeriveEntry producer parser -> let hooks = mountHooks unit (mountNode parser) in
        "(" ++ show (variantLabel producer hooks) ++ ", SDK.deriveSteps ("
        ++ action hooks parser "() <$ " ++ "))"
      where action hooks mounted prefix = wrapTarget hooks (mountTarget mounted)
              (prefix ++ handlers hooks (mountMethod mounted))
    -- 注入 v4：入口对 Middleware 列表多态，挂载登记时在类型上给出覆盖它的列表，GHC 在编译期选定 Root 的 superclass 实例。
    -- 没有 Middleware 的程序照旧引用单态入口。
    handlers hooks name
      | hooked = "(Handlers." ++ name ++ " @'[" ++ intercalate ", " (map show hooks) ++ "])"
      | otherwise = "Handlers." ++ name
    -- 原有列表（空）总是登记；被 middleware 标注覆盖的挂载另以覆盖它的列表登记。
    variantsOf role terminal = [] : [hooks | hooks <- unitVariants unit, hooks `elem`
      [mountHooks unit (mountNode mount) | mount <- assemblyMounts (unitAssembly unit)
        , mountRole mount == role, mountTerminal mount == terminal]]
    wrapTarget hooks label action = "SDK.targetApp " ++ show label ++ " emptyContexts scopes"
      ++ " (SDK.withErrorHandlers Handlers.errorHandlers"
      ++ " (SDK.withAnchoredContexts " ++ handlers hooks "contextInjections"
      ++ " (SDK.withStreamContexts " ++ handlers hooks "streamContextInjections"
      ++ " (SDK.withScopeCleanups " ++ handlers hooks "scopeCleanups" ++ " (" ++ action ++ ")))))"
    renderList _ [] = "[]"
    renderList indent items = "[ " ++ intercalate ("\n" ++ indent ++ ", ") items ++ "\n" ++ indent ++ "]"
