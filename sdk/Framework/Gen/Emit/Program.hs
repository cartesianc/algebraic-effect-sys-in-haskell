{-# LANGUAGE DuplicateRecordFields #-}

-- 输出 Generated/Program.hs：组合好的执行闭包（workflow、发布后的回调表、lifelong 之外的静态运行），
-- 以及绑定好元数据的 interpreter。原型数据由 Framework.Gen.Emit.Prototype 写成单独的 Generated/Prototype.hs。
-- 闭包的形状直接来自 gen 已确定的 workflow 与 lifelong 计划；运行时只执行它，不再遍历原型编排。
module Framework.Gen.Emit.Program (renderProgram) where

import Data.List (intercalate, nub)
import Framework.Gen.Booter (publishedWithin)
import Framework.Gen.Names (HandlerNames, entryName, helperName)
import Framework.Gen.Plan
import Framework.Prototype (ChainRole(..), variantLabel)
import qualified Framework.Prototype as P

renderProgram :: FilePath -> HandlerNames -> [(FilePath, Maybe String)] -> Unit -> String
renderProgram directory names hangingSources unit = unlines (programHeader ++ astInterpreter)
  where
    namespace = unitNamespace unit
    helper name = "Handlers." ++ helperName names name
    selected = map fst (unitTerminals unit)
    hooked = any ((== MiddlewareOperation) . bindingOperation) (unitBindings unit)
    effects = effectPrototypes unit
    workflow = P.plannedWorkflow (unitPlan unit)
    mounts = assemblyMounts (unitAssembly unit)
    programHeader =
      [ "{-# LANGUAGE DuplicateRecordFields #-}" ]
      ++ (if hooked then ["{-# LANGUAGE DataKinds #-}", "{-# LANGUAGE TypeApplications #-}"] else [])
      ++
      [ ""
      , "-- 自动生成；组合好的执行闭包，原型在 Generated/Prototype.hs，执行由 SDK 的 interpreter 完成。"
      , "module " ++ namespace ++ ".Generated.Program (Results(..), compiledProgram, interpreter, generatedPrototype) where"
      , ""
      , "import Framework.Generated (EffectSpec(..), EffectTyping(..), Asset(..), Handles(..), Demand(..), Access(..), TypeRef(..))"
      , "import qualified Framework.Generated as SDK"
      , "import " ++ namespace ++ ".Generated.Effects"
      , "import " ++ namespace ++ ".Generated.Prototype (generatedPrototype)"
      , "import qualified " ++ namespace ++ ".Generated.Handlers as Handlers"
      , ""
      ]
    astInterpreter =
      [ ""
      , "-- 仅汇总所选末端的成功结果，不保存共享绑定或增加完成包装。"
      , "data Results = " ++ intercalate " | " [terminal ++ "Result ()" | terminal <- selected]
      , "  deriving Show"
      , ""
      , "-- 末端共享生成的 scope 句柄；只创建空状态。"
      , "-- compiledWorkflow：AST 的执行闭包（Serial 顺序、Concurrent 并行、Choose 选择、Drive 是 lifelong 的位置）。"
      , "-- compiledReactions：资产每次发布后同步执行的回调（lifelong 的单元与派生步骤）；Nothing 作用范围是 event。"
      , "-- compiledStatic：lifelong 之外 requests 持续资产时，同步运行到结束的根来源。"
      , "compiledProgram :: IO (SDK.Compiled ContextValues Errors Results)"
      , "compiledProgram = do"
      , "  scopes <- " ++ helper "newScopeHandlers"
      , "  let target :: Show value => String -> App value -> SDK.Target ContextValues Errors value"
      , "      target label action = SDK.targetApp label emptyContexts scopes"
      , "        (SDK.withErrorHandlers " ++ helper "errorHandlers" ++ " action)"
      , "  pure SDK.Compiled"
      , "    { SDK.compiledWorkflow ="
      , "        " ++ indented "        " (closure workflow)
      , "    , SDK.compiledReactions = " ++ renderList "        " reactions
      , "    , SDK.compiledStatic = " ++ renderList "        " statics
      , "    }"
      , ""
      ] ++
      [ "-- SDK 装配入口，不需要用户提供节点执行器或重复选择 handler。"
      , "interpreter :: SDK.AST -> [EffectSpec] -> IO ()"
      , "interpreter = SDK.interpreter " ++ show namespace
          ++ " [" ++ intercalate ", " sourceChecks ++ "] generatedPrototype compiledProgram"
      ]
    sourceChecks = ["(" ++ sourcePath "Handlers.hs" ++ ", " ++ helper "handlerSourceFingerprint" ++ ")"]
      ++ map show hangingSources
    sourcePath file = show (directory ++ "/" ++ file)

    -- workflow 的一层闭包。lifelong 的单元不在这里执行：它们在回调表里，由驱动资产的发布调用。
    closure tree = case tree of
      P.NodeAt path terminal -> "SDK.Step " ++ show path ++ " (" ++ nodeTarget path terminal ++ ")"
      P.ChainAt path parts -> "SDK.Serial " ++ show path ++ " " ++ nested (map closure parts)
      -- 每个分支带上它执行期间可能发布的资产：其他分支里的 require 缺值时，只在仍可能有发布时等待。
      P.ParallelAt path parts -> "SDK.Concurrent " ++ show path ++ " " ++ nested
        [ "([" ++ intercalate ", " [slotLiteral "SDK." unit producer | asset <- publishedWithin effects workflow part
            , producer <- providerOf asset] ++ "], " ++ closure part ++ ")"
        | part <- parts ]
      P.AlternativeAt path choice parts -> "SDK.Choose " ++ show path ++ " " ++ show (P.alternativeSelector choice)
        ++ " (" ++ selectorTarget choice ++ ") " ++ nested
          [ "(" ++ show context ++ ", " ++ show (P.workflowNode part) ++ ", " ++ closure part ++ ")"
          | part <- parts, Just context <- [lookup (P.workflowNode part) (P.alternativeCases choice)] ]
      P.LifelongAt path described _ -> "SDK.Drive " ++ show path ++ " " ++ case
          [session | session <- P.lifelongSessions described, P.Receive _ <- [P.sessionPlan session]] of
        session : _ -> "(Just (" ++ source session ++ "))"
        [] -> "Nothing"
    nested [] = "[]"
    nested items = "\n  [ " ++ intercalate "\n  , " items ++ "\n  ]"

    -- 每个 lifelong 的单元是它驱动资产的回调；持续资产的回调只在该 lifelong 的来源运行期间有效，
    -- 普通资产（event）的回调整次运行有效。派生资产的步骤是上游的回调。
    reactions = filter (not . null) $
      [ "SDK.Reaction " ++ slotLiteral "SDK." unit producer ++ " " ++ scopeOf path producer
          ++ " (SDK.RunUnit " ++ show (P.workflowNode part) ++ " (" ++ indented "  " (closure part) ++ "))"
      | (path, described) <- P.workflowLifelongs workflow
      , Just (P.LifelongAt _ _ parts) <- [P.lookupWorkflow workflow path]
      , part <- parts
      , asset : _ <- [nub [subscribed | (node, subscribed) <- P.lifelongSubscriptions described
          , P.workflowNode part `isPrefix` node]]
      , producer <- providerOf asset ]
      ++ [ derive (Just path) session | (path, described) <- P.workflowLifelongs workflow
         , session <- P.lifelongSessions described ]
      ++ [ derive (Just (staticScope session)) session | session <- finite ]
    scopeOf path producer
      | P.effectContinuous (protoOf unit producer) = "(Just " ++ show path ++ ")"
      | otherwise = "Nothing"
    derive scope session = case (P.sessionPlan session, P.sessionMounts session) of
      (P.Derive upstream, [mount]) -> concat
        [ "SDK.Reaction " ++ slotLiteral "SDK." unit upstreamProducer ++ " (" ++ maybe "Nothing" (("Just " ++) . show) scope
          ++ ") (SDK.RunDerive " ++ show mount ++ " (" ++ mounted mount "() <$ " ++ "))"
        | upstreamProducer <- providerOf upstream ]
      _ -> ""

    -- lifelong 之外 requests 的持续资产：沿派生关系找到根来源，以根来源的挂载为静态运行的标识。
    finite = assemblyFiniteSessions (unitAssembly unit)
    statics =
      [ "(" ++ slotLiteral "SDK." unit producer ++ ", " ++ show (staticScope session) ++ ", " ++ source root ++ ")"
      | session <- finite, producer <- providerOf (P.sessionAsset session), Just root <- [rootOf session] ]
    rootOf session = case P.sessionPlan session of
      P.Receive _ -> Just session
      P.Derive upstream -> case [selectedSession | selectedSession <- finite, P.sessionAsset selectedSession == upstream] of
        selectedSession : _ -> rootOf selectedSession
        [] -> Nothing
      P.ReuseOutput _ -> Nothing
    staticScope session = maybe [] (take 2 . headOr [] . P.sessionMounts) (rootOf session)
    headOr fallback items = case items of
      item : _ -> item
      [] -> fallback

    -- Receive 的来源：Stream 方法与 parser 各一个挂载；behavior（stream = False）比较两次回调的值。
    source session = case P.sessionMounts session of
      [streamMount, parserMount] -> concat
        [ "SDK.StreamSource " ++ slotLiteral "SDK." unit producer
          ++ " (" ++ show streamMount ++ ", " ++ mounted streamMount "" ++ ")"
          ++ " (" ++ show parserMount ++ ", " ++ mounted parserMount "() <$ " ++ ")"
          ++ (if P.effectSampled (protoOf unit producer)
                then " (Just (\\earlier later -> bound" ++ producer ++ " earlier == bound" ++ producer ++ " later))"
                else " Nothing")
        | producer <- take 1 (providerOf (P.sessionAsset session)) ]
      _ -> error ("Receive session without its two mounts: " ++ P.sessionAsset session)

    providerOf asset = [P.effectName effect | effect <- effects, P.effectProduces effect == Just asset]

    -- 挂载的末端：按覆盖它的 Middleware 列表选取入口。
    nodeTarget path terminal = case [mount | mount <- mounts, mountNode mount == path, mountRole mount == NodeChain] of
      mount : _ -> wrapTarget (variantLabel terminal (mountHooks unit path))
        (terminal ++ "Result () <$ " ++ handlers (mountHooks unit path) (mountMethod mount))
      [] -> error ("Workflow node without an entry mount: " ++ show path)
    selectorTarget choice = case [plan | plan <- unitSelectors unit, selectorSource plan == P.alternativeSource choice] of
      plan : _ -> let hooks = mountHooks unit (P.alternativeSelector choice) in
        wrapTarget (variantLabel (selectorSource plan) hooks) ("SDK.chooseCase " ++ show (selectorEntry plan)
          ++ " ContextBindingError (" ++ handlers hooks (selectorEntry plan) ++ ") ["
          ++ intercalate ", " [ "(" ++ slotLiteral "SDK." unit context ++ ", () <$ " ++ handlers hooks request ++ ")"
                              | (context, request) <- selectorCases plan ] ++ "]")
      [] -> error ("Alternative without a selector plan: " ++ P.alternativeSource choice)
    mounted path prefix = case [mount | mount <- mounts, mountNode mount == path] of
      mount : _ -> wrapTarget (mountTarget mount) (prefix ++ handlers (mountHooks unit path) (mountMethod mount))
      [] -> error ("Session step without an entry mount: " ++ show path)
    isPrefix prefix path = take (length prefix) path == prefix
    -- 注入 v4：入口对 Middleware 列表多态，挂载登记时在类型上给出覆盖它的列表，GHC 在编译期选定该列表的 Captures 实例。
    -- 没有 Middleware 的程序照旧引用单态入口。
    handlers hooks name
      | hooked = "Handlers." ++ entryName names name ++ " @'[" ++ intercalate ", " (map show hooks) ++ "]"
      | otherwise = "Handlers." ++ entryName names name
    -- 挂接的 parser 与自动收尾的 close 已写在生成入口上；Target 只安装程序级的 Error 回调。
    wrapTarget label action = "target " ++ show label ++ " (" ++ action ++ ")"
    indented indent text = intercalate ("\n" ++ indent) (lines text)
    renderList _ [] = "[]"
    renderList indent items = "\n" ++ indent ++ "[ " ++ intercalate ("\n" ++ indent ++ ", ") (map (indented (indent ++ "  ")) items) ++ "\n" ++ indent ++ "]"
