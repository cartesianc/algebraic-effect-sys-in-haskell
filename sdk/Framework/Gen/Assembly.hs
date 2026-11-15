-- 绑定阶段的结构装配：把 Lower 已确定的尾部、选择器、会话与输出连接解析成方法引用。
-- 算法说明 v2（2026-11-16）：Build、Sources 与 Emit 共用这份计划，不各自寻找生产入口。
-- 这里只保存编译期事实；Prototype 接收挂载与图，Generated 接收执行入口，不增加运行时解释器。
module Framework.Gen.Assembly
  ( Assembly(..), EntryMount(..), OutputConnection(..), assembleProgram
  , EntryStep(..), stepMethod, RawSource(..), rawMethod
  ) where

import Framework.Prototype
import Framework.Prototype.Validate (valid)

-- 调用顺序仍是 requests → Input → handler。角色用于保留装配依据；
-- 相同方法出现在两个步骤时仍执行两次，不能按名字或结构去重。
data EntryStep method = RequestStep method | InputStep method
  deriving (Eq, Show, Read)

stepMethod :: EntryStep method -> method
stepMethod (RequestStep method) = method
stepMethod (InputStep method) = method

-- raw 的直接输入已由 Bind 解析。Stream 单步产 String，需要包装成单元素 list；
-- 其余输入交出 list。是否已有本次输出由现有 replay 协议决定，不缓存另一调用的结果。
data RawSource method = RawList method | RawStream method
  deriving (Eq, Show, Read)

rawMethod :: RawSource method -> method
rawMethod (RawList method) = method
rawMethod (RawStream method) = method

-- 一个静态挂载；NodeId 保留每次 AST 出现的位置，同方法不合并挂载。
-- terminal 是结构展示的末端/契约，target 是运行入口的诊断标签：
-- 会话中 terminal 是资产名，target 分别是 Stream 与 parser 的 effect 名。
data EntryMount method = EntryMount
  { mountNode :: NodeId
  , mountRole :: ChainRole
  , mountTerminal :: String
  , mountTarget :: String
  , mountMethod :: method
  } deriving (Eq, Show, Read)

-- 同次输出的连接：anchor → parser。role 区分普通吞错注入与持续失败传播；
-- 每次注入只能回放当前 anchor，不能借此跳过其他前驱。
data OutputConnection method = OutputConnection
  { outputAnchor :: method
  , outputParser :: method
  , outputProducer :: String
  , outputRole :: MethodRole
  } deriving (Eq, Show, Read)

data Assembly method = Assembly
  { assemblyMounts :: [EntryMount method]
  , assemblyOutputs :: [OutputConnection method]
  } deriving (Eq, Show, Read)

assembleProgram :: PrototypePlan -> Either (PrototypeError String) (Assembly String)
assembleProgram plan = do
  mounted <- concat <$> mapM mountedNode (allWorkflow workflow)
  selectors <- mapM mountedSelector [selected | selected@AlternativeAt {} <- allWorkflow workflow]
  sessions <- concat <$> mapM mountedSession
    (concatMap (lifelongSessions . snd) (workflowLifelongs workflow) ++ finiteSessions effects)
  pure (Assembly (mounted ++ selectors ++ sessions) outputs)
  where
    effects = plannedEffects plan
    workflow = plannedWorkflow plan
    mountedNode (NodeAt identifier selected) = do
      effect <- findEffectProto effects selected
      method <- ordinaryEntry effect
      pure [EntryMount identifier NodeChain selected selected method]
    mountedNode _ = pure []
    mountedSelector (AlternativeAt _ selected _) = case
      [method | effect <- effects, effectProduces effect == Just (alternativeContract selected)
        , Just method <- [selectorMethod effect]] of
      [method] -> pure (EntryMount (alternativeSelector selected) SelectorChain
        (alternativeContract selected) (alternativeContract selected) method)
      _ -> Left (UnknownPrototypeTarget (alternativeContract selected))
    mountedSelector _ = Left (InvalidPrototype "Expected alternative selector")
    mountedSession described = do
      producer <- case [effect | effect <- effects, effectProduces effect == Just (sessionAsset described)] of
        [effect] -> pure effect
        _ -> Left (UnknownPrototypeTarget (sessionAsset described))
      let entry effect role = case lookup role (effectMethods effect) of
            Just method -> pure (effectName effect, method)
            Nothing -> Left (InvalidPrototype ("Session for " ++ sessionAsset described
              ++ " has no " ++ show role ++ " method"))
      steps <- case sessionPlan described of
        Receive source -> do
          streamEffect <- findEffectProto effects source
          handle <- entry streamEffect StreamHandler
          parser <- entry producer ContextStream
          pure [handle, parser]
        Derive _ -> (: []) <$> entry producer ContextStream
        -- 沿用 AST 输出，不另建生产步骤；位置证据已经在 Lower 的 BootPlan 中检查。
        ReuseOutput _ -> pure []
      valid (length steps == length (sessionMounts described)) ("Session steps differ for " ++ sessionAsset described)
      pure [EntryMount mount SessionChain (sessionAsset described) target method
        | (mount, (target, method)) <- zip (sessionMounts described) steps]
    -- 保留原注入顺序：同一 anchor 内先普通 Context，再持续 Context，各自按注册顺序。
    outputs =
      [ OutputConnection anchorMethod parser (effectName producer) role
      | anchor <- effects, (anchorRole, anchorMethod) <- effectMethods anchor
      , anchorRole `elem` [HandlerMethod, ScopeOpen]
      , role <- [ContextRequest, ContextStream], producer <- effects
      , effectAnchor producer == Just (effectName anchor)
      , Just parser <- [lookup role (effectMethods producer)] ]
