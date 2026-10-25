{-# LANGUAGE DuplicateRecordFields #-}

-- 将注册和选定末端 lower 为普通 Haskell 源码；不执行业务。
module Framework.Codegen (Entry(..), lowerProgram) where

import Framework.Effect.Contract (EffectKind(..))
import Framework.Effect.Registration
import Data.List (intercalate, nub)
import Data.Maybe (maybeToList)

-- 3. 生成契约、superclass 和末端句柄登记。
-- 不生成外部 request 流水线；上游方法由用户 instance 直接引用。
-- Input 保存操作能力；Context 经 request/require 接入，不重挂生产者的注册。
data Entry = SingleTarget String | Workflow [String]

lowerProgram :: String -> [EffectSpec] -> Entry
             -> Either String (String, String, [(String, String, String)], String)
lowerProgram namespace specifications entry = do
  if any ((== "Root") . name) specifications
    then Left "Root is reserved for the superclass"
    else pure ()
  mapM_ checkInput specifications
  mapM_ checkError specifications
  mapM_ (contextNames specifications . pure . name) specifications
  if null selected
    then Left "Select at least one terminal effect for generation"
    else pure ()
  selectedMethods <- mapM findHandler selected
  declarations <- mapM declaration specifications
  singleEntry <- case entry of
    SingleTarget terminal -> do
      method <- findHandler terminal
      pure
        [ "-- 纯计算样例也只登记末端句柄，不在外部组合上游。"
        , "compiledTarget :: SDK.Target SDK.Identity ContextValues Errors (Produce " ++ terminal ++ ")"
        , "compiledTarget = SDK.targetPure " ++ show terminal ++ " emptyContexts"
        , "  (FrameworkRoot.withErrorHandlers Handlers.errorHandlers " ++ method ++ ")"
        , ""
        , "benchmark :: Output Errors (Produce " ++ terminal ++ ")"
        , "benchmark = SDK.bootPure compiledTarget"
        , ""
        , "registeredTarget :: String"
        , "registeredTarget = " ++ show terminal
        , ""
        , "-- 生成入口由 SDK 提供；业务无需另写 Codegen 模块。"
        , "runDemo :: Show value => [EffectSpec] -> String -> value -> IO ()"
        , "runDemo = SDK.runDemo " ++ show namespace ++ " registeredEffects registeredTarget Handlers.handlerSourceFingerprint"
        ]
    Workflow _ -> pure []
  pure
    ( unlines (contractHeader ++ runtimeAliases ++ concat declarations ++ errorDeclaration ++ contextDeclarations)
    , unlines (programHeader ++ registrationSnapshot ++ singleEntry ++ astInterpreter selectedMethods)
    , concatMap instanceWrappers specifications
    , scopeHandlers ++ errorHandlers
    )
  where
    selected = case entry of
      SingleTarget terminal -> [terminal]
      Workflow terminals -> nub terminals
    isWorkflow = case entry of
      Workflow _ -> True
      SingleTarget _ -> False
    contextSpecs = filter ((== ContextKind) . effectKind . typing) specifications
    contractHeader =
      [ "{-# LANGUAGE ConstraintKinds #-}"
      , "{-# LANGUAGE DataKinds #-}"
      , "{-# LANGUAGE EmptyDataDecls #-}"
      , "{-# LANGUAGE FlexibleContexts #-}"
      , "{-# LANGUAGE FlexibleInstances #-}"
      , "{-# LANGUAGE MultiParamTypeClasses #-}"
      , "{-# LANGUAGE TypeApplications #-}"
      , "{-# LANGUAGE TypeFamilies #-}"
      , "{-# LANGUAGE TypeOperators #-}"
      , "{-# LANGUAGE UndecidableInstances #-}"
      , "{-# LANGUAGE UndecidableSuperClasses #-}"
      , ""
      , "-- 自动生成；通过 SDK 的 effect-codegen 更新，手写注册与 handler 位于上级目录。"
      , "module " ++ namespace ++ ".Generated.Effects where"
      , ""
      , "import Framework.Effect.Contract (Effect(..), Registered)"
      , "import qualified Framework.Effect.Contract as FrameworkRoot"
      , "import qualified Framework.SDK as SDK"
      , "import " ++ namespace ++ ".Types"
      , ""
      ]
    programHeader =
      [ "{-# LANGUAGE DuplicateRecordFields #-}"
      , "{-# LANGUAGE TypeFamilies #-}"
      , ""
      , "-- 自动生成；只登记末端句柄，Node algebra 才 lower，业务组合仍在 handler 内。"
      , "module " ++ namespace ++ ".Generated.Program where"
      , ""
      , "import Framework.SDK (Effect(..), EffectSpec(..), EffectTyping(..), Producer(..), ContextInput(..), ValueSource(..), TypeRef(..), Output)"
      , "import qualified Framework.SDK as SDK"
      , "import qualified Framework.Effect.Contract as FrameworkRoot"
      , "import " ++ namespace ++ ".Generated.Effects"
      , "import qualified " ++ namespace ++ ".Generated.Handlers as Handlers"
      , "import " ++ namespace ++ ".Types"
      , ""
      ]
    runtimeAliases =
      [ "-- SDK 提供运行载体与空存储；Context 经声明的 request/require 取得。"
      , "type Root = SDK.Root ContextValues Errors"
      , if isWorkflow then "type App = SDK.App ContextValues Errors"
                      else "type Pure = SDK.Pure ContextValues Errors"
      , ""
      ]

    -- 注册时连接生产/读取入口；业务方法使用原生 Haskell 取值，不改写表达式。
    instanceWrappers specification =
      [ (name specification ++ "Effect", method, wrapper method)
      | method <- maybeToList (entryMethod (typing specification)) ++ closing
          ++ errorMethods specification ++ maybeToList reading ]
      where
        selectedName = name specification
        closing = case typing specification of
          Scoped _ method -> maybeToList method
          _ -> []
        reading = case typing specification of
          Context _ method -> method
          _ -> Nothing
        scopedDependencies = "FrameworkRuntime.withScopeDependencies "
          ++ show (upstreamScopes specification)
        rootWrapper = "FrameworkRoot.withErrorPath " ++ show (errorPath specification)
          ++ " . FrameworkRoot.handler @FrameworkGenerated.Root"
        wrapper method
          -- require 的覆盖实现同样检查来源声明，不刷新来源或改变消费者身份。
          | Just method == reading = "(" ++ rootWrapper
              ++ " . FrameworkRuntime.requireContext " ++ show selectedName
              ++ " FrameworkGenerated.ContextBindingError "
              ++ contextAccessTable "FrameworkRuntime." selectedName ++ ")"
          | otherwise = "(" ++ rootWrapper ++ " . " ++ (case typing specification of
              -- 先进入本 scope，再检查其上游；失效后的 close 仍可读取自己的 Context 以收尾。
              Scoped _ closingMethod ->
                "FrameworkRuntime." ++ (if Just method == closingMethod then "closeScope " else "openScope ")
                  ++ show selectedName ++ " FrameworkGenerated.ScopeBindingError . "
                  ++ scopedDependencies ++ " . FrameworkRuntime.enterHandler " ++ show selectedName
              _ -> scopedDependencies ++ " . " ++ operation) ++ ")"
        operation = case typing specification of
          Context (Just _) _ ->
            "FrameworkRuntime.callContext " ++ show selectedName
              ++ " FrameworkGenerated.ContextBindingError\n"
              ++ "  " ++ contextAccessTable "FrameworkRuntime." selectedName
              ++ "\n  " ++ observation "FrameworkRuntime." selectedName
              ++ "\n  FrameworkGenerated.bound" ++ selectedName
              ++ "\n  (\\value bindings -> bindings { FrameworkGenerated.bound" ++ selectedName ++ " = Just value })"
          _ -> "FrameworkRuntime.enterHandler " ++ show selectedName

    -- 生产与显式读取共用声明表；读取只校验来源，不采用 request 的刷新行为。
    contextAccessTable prefix selectedName = "[" ++ intercalate ", "
      [ "(" ++ show (name consumer) ++ ", " ++ prefix ++ access ++ ")"
      | consumer <- specifications
      , Just access <- [accessFor consumer] ] ++ "]"
      where
        accessFor consumer
          | fmap sourceName (requestInput consumer) == Just selectedName = Just "RequestValue"
          | fmap sourceName (requireInput consumer) == Just selectedName = Just "RequireValue"
          | otherwise = Nothing

    errorMethods specification = case typing specification of
      Error detecting resolving -> maybeToList detecting ++ maybeToList resolving
      _ -> []

    -- 同时保留原 Input 和 request 生产链；从 Root 方向向下，先原 Input 再 request。
    -- 共享祖先按身份去重；require 不启动生产链。
    operationInputs specification = nub (input specification : maybeToList (requestSource specification))
    upstreamScopes specification = nub (concatMap (scopeNames []) (operationInputs specification))
    errorPath specification = nub (scopeNames [] (name specification))
    orderedScopes = nub (concatMap errorPath specifications)
    scopeNames seen selectedName
      | selectedName `elem` seen = []
      | otherwise = concat
          [ concatMap (scopeNames (selectedName : seen)) (operationInputs specification)
            ++ (case typing specification of Scoped _ _ -> [selectedName]; _ -> [])
          | specification <- specifications, name specification == selectedName ]

    -- scope.request 指向资源生产者；它声明消费的 Context 值构成开启输入。
    -- 这里只生成观察协议，不调用生产者，不读取用户方法体。
    openingInputs specification = nub (concatMap (valueInputs []) (maybeToList (requestSource specification)))
    valueInputs seen selectedName
      | selectedName `elem` seen = []
      | otherwise = concat
          [ let direct = map sourceName (maybeToList (requestInput producer) ++ maybeToList (requireInput producer))
            in direct ++ concatMap (valueInputs (selectedName : seen)) direct
          | producer <- specifications, name producer == selectedName ]
    comparedInputs = nub (concatMap openingInputs
      [specification | specification <- specifications, effectKind (typing specification) == ScopedKind])
    observation prefix selectedName
      | selectedName `elem` comparedInputs = "(Just (" ++ prefix ++ "ScopeInput " ++ show selectedName ++ "))"
      | otherwise = "Nothing"

    findEffect effectName = case filter ((== effectName) . name) specifications of
      [specification] -> Right specification
      [] -> Left ("Unknown effect: " ++ effectName)
      _ -> Left ("Duplicate effect: " ++ effectName)

    -- target 和 request 均只引用 effect，从 typing 取得普通入口。
    -- Nothing 可保留为声明，但不能被选择为可执行入口。
    findHandler effectName = do
      specification <- findEffect effectName
      case typing specification of
        Error _ _ -> Left ("Error methods are activated by the Root failure protocol, not a Node target: " ++ effectName)
        _ -> case entryMethod (typing specification) of
          Just method -> Right method
          Nothing -> Left ("Effect has no callable entry (handler/open/Context.request = Nothing): " ++ effectName)

    -- 业务取值只引用 Context；Input 仍只注入句柄，不暗含业务产物。
    findRequest effectName = do
      specification <- findEffect effectName
      case typing specification of
        Context _ _ -> findHandler effectName
        _ -> Left ("request must reference a Context effect: " ++ effectName)

    -- 此限制只针对手写 Input。生成的 superclass 仍包含声明的 Context 能力。
    checkInput specification
      | input specification == "Root" = Right ()
      | otherwise = do
          predecessor <- findEffect (input specification)
          case typing predecessor of
            Context _ _ -> Left ("Input cannot reference Context " ++ name predecessor
              ++ " in " ++ name specification ++ "; declare context.request or context.require instead")
            _ -> Right ()

    -- Error 直接继承目标 Scoped；自动路由每份 scope 只安装一项策略。
    checkError specification = case typing specification of
      Error _ _ -> do
        predecessor <- findEffect (input specification)
        case typing predecessor of
          Scoped _ _ -> pure ()
          _ -> Left ("Error.input must reference a Scoped effect: " ++ name specification)
        case [name candidate | candidate <- specifications
              , effectKind (typing candidate) == ErrorKind
              , input candidate == input specification] of
          [_] -> pure ()
          _ -> Left ("Multiple Error policies for scope: " ++ input specification)
      _ -> pure ()

    -- 被 Input 后端复用的 scope 仍须提供完整开启／关闭协议。
    checkScope effectName = do
      specification <- findEffect effectName
      case typing specification of
        Scoped (Just _) (Just _) -> Right ()
        _ -> Left ("Input scope needs Scoped.open and Scoped.close: " ++ effectName)

    -- 业务产物只归 Context；Output 仍只在运行边界统一包装。
    valueContract specification = case typing specification of
      Context (Just Producer { produces = OutputRef _ _ }) _ ->
        Left ("Context.request must produce a business value, not Output: " ++ name specification)
      Context (Just Producer { produces = contract }) _ -> Right contract
      Context Nothing (Just _) ->
        Left ("Context.require needs a Context.request product contract: " ++ name specification)
      _ -> Right (TypeRef "()")

    declaration specification = do
      mapM_ findRequest (requestSource specification)
      valueType <- valueContract specification
      _ <- contextNames specifications [name specification]
      mapM_ checkScope (upstreamScopes specification)
      let effectName = name specification
          typeName = "'SDK." ++ show (effectKind (typing specification))
          upstream = input specification
          dependencies = maybeToList (requestInput specification) ++ maybeToList (requireInput specification)
          superclasses = nub (("Effect " ++ upstream ++ " m") :
            ["Effect " ++ sourceName dependency ++ " m" | dependency <- dependencies] ++
            ["Produce " ++ sourceName dependency ++ " ~ ("
              ++ reference (sourceType dependency) ++ ")" | dependency <- dependencies])
          ordinaryMethods =
            [ (method, case effectKind (typing specification) of
                PureKind -> "m ()"
                ExcuKind -> "m ()"
                ScopedKind -> "m ()"
                ErrorKind -> "m ()"
                _ -> "m (Produce " ++ effectName ++ ")")
            | method <- maybeToList (entryMethod (typing specification)) ]
          -- open／close 不产值；资源信息来自显式声明的上游 Context。
          closingMethods = case typing specification of
            Scoped _ closing -> [(method, "m ()") | method <- maybeToList closing]
            _ -> []
          methods = ordinaryMethods ++ closingMethods
            ++ [(method, "m ()") | method <- errorMethods specification]
          methodLines = ["  " ++ method ++ " :: " ++ signature | (method, signature) <- methods]
          readingLines = case typing specification of
            Context _ (Just method) ->
              [ "  " ++ method ++ " :: m (Produce " ++ effectName ++ ")"
              , "  " ++ method ++ " = (FrameworkRoot.withErrorPath " ++ show (errorPath specification)
                ++ " . FrameworkRoot.handler @Root) $"
              , "    SDK.readContext " ++ show effectName
                ++ " ContextBindingError " ++ contextAccessTable "SDK." effectName
                ++ " " ++ observation "SDK." effectName ++ " bound" ++ effectName
              ]
            _ -> []
          minimalLines = case methods of
            [] -> []
            _ -> ["  {-# MINIMAL " ++ intercalate ", " (map fst methods) ++ " #-}"]
          -- 消费契约由 context 的两种取值声明组成；双输入按 request、require 排列。
          -- 原生 <- 在方法体内取得声明的输入；不向业务方法增加位置参数。
          requireType = case map (reference . sourceType) dependencies of
            [] -> "SDK.Void"
            [contract] -> contract
            contracts -> "(" ++ intercalate ", " contracts ++ ")"
          produceLines = case typing specification of
            Context (Just _) _ -> ["  type Produce " ++ effectName ++ " = " ++ reference valueType]
            _ -> []
      pure ([ "data " ++ effectName
         , ""
         , "class (" ++ intercalate ", " superclasses ++ ") => " ++ effectName ++ "Effect m where"
         ]
         ++ methodLines ++ readingLines ++ minimalLines
         ++ [ ""
            , "instance (Monad m, Effect " ++ upstream ++ " m, " ++ effectName
              ++ "Effect m) => Effect " ++ effectName ++ " m where"
            , "  type Registration " ++ effectName ++ " = Registered "
              ++ effectName ++ "Effect " ++ upstream
            , "  type Typing " ++ effectName ++ " = " ++ typeName
            , "  type Require " ++ effectName ++ " = " ++ requireType
            ] ++ produceLines ++
            [ "  type Error " ++ effectName ++ " = " ++ effectName ++ "Error"
            , "  raise (" ++ effectName ++ "Error description) = SDK.failEffect " ++ show effectName
              ++ " " ++ effectName ++ "Failure description"
            , "  handler = FrameworkRoot.handler @Root"
            , ""
            ])

    errorDeclaration = concat
      [ [ "-- SDK 生成的本地错误只接收消息；类型唯一确定 raise 来源。"
        , "newtype " ++ name s ++ "Error = " ++ name s ++ "Error String"
        , "  deriving (Eq, Show, Read)"
        , ""
        ] | s <- specifications ] ++
      [ "-- 统一失败协议的分类标签；消息与来源由 SDK.Failure 保存。"
      , "data Errors = " ++ intercalate " | "
          ([name s ++ "Failure" | s <- specifications]
           ++ ["ContextBindingError SDK.ContextFault", "ScopeBindingError SDK.ScopeFault"])
      , "  deriving (Eq, Show)"
      , ""
      ]

    contextDeclarations =
      [ "-- SDK 内部存储：Nothing 仅表示本次运行尚未建立绑定，不是业务缺值。"
      , "data ContextValues = ContextValues"
      ] ++ (case ["bound" ++ name s ++ " :: Maybe (Produce " ++ name s ++ ")"
                  | s <- contextSpecs] of
        [] -> [""]
        fields -> ["  { " ++ intercalate "\n  , " fields, "  }", ""])
      ++ [ "emptyContexts :: ContextValues"
         , "emptyContexts = ContextValues" ++ concat [" Nothing" | _ <- contextSpecs]
         , ""
         ]

    reference (TypeRef typeName) = typeName
    reference (OutputRef cause value) =
      "SDK.Output (" ++ reference cause ++ ") (" ++ reference value ++ ")"

    -- 控制对象由生成的 handler 模块创建；不同链引用同份对象，不预执行 open。
    scopeHandlers
      | not isWorkflow = ""
      | otherwise = unlines
          [ "-- SDK 内部：每份 Scoped 句柄拥有自己的状态和 MVar；创建不执行业务方法。"
          , "newScopeHandlers :: IO [FrameworkRuntime.ScopeHandler FrameworkGenerated.ContextValues FrameworkGenerated.Errors]"
          , "newScopeHandlers = sequence"
          , "  [ " ++ intercalate "\n  , "
              ["FrameworkRuntime.newScopeHandler " ++ show (name specification) ++ " " ++ show (openingInputs specification)
                ++ " (" ++ show (requestSource specification) ++ ")"
              | specification <- specifications, effectKind (typing specification) == ScopedKind]
          , "  ]"
          ]

    -- 只保存类方法引用；安装时不检测、不处置，也不执行上游业务。
    errorHandlers = unlines
      [ ""
      , "-- Root 的异常入口，按 scope 的拓扑顺序从上向下检测。"
      , "errorHandlers :: [(String, FrameworkRoot.ErrorHandler FrameworkGenerated." ++ carrier ++ ")]"
      , "errorHandlers ="
      , "  [" ++ if null callbacks then "" else " " ++ intercalate "\n  , " callbacks
      , "  ]"
      ]
      where
        carrier = if isWorkflow then "App" else "Pure"
        callbacks =
          [ "(" ++ show selectedScope ++ ", FrameworkRoot.ErrorHandler " ++ show (name specification)
              ++ " (" ++ methodReference detecting ++ ") (" ++ methodReference resolving ++ "))"
          | selectedScope <- orderedScopes
          , specification <- specifications
          , input specification == selectedScope
          , Error detecting resolving <- [typing specification] ]
        methodReference Nothing = "Nothing"
        methodReference (Just method) = "Just " ++ method

    astInterpreter methods
      | not isWorkflow = []
      | otherwise =
          [ ""
          , "-- 仅汇总所选末端的成功产物，不保存共享绑定或增加完成包装。"
          , "data Results = " ++ intercalate " | "
              [terminal ++ "Result (Produce " ++ terminal ++ ")" | terminal <- selected]
          , "  deriving Show"
          , ""
          , "-- 末端共享生成的 scope 句柄；只创建空状态，Node algebra 才 lower，业务调用仍在 instance 内。"
          , "compiledEntries :: IO [SDK.Target IO ContextValues Errors Results]"
          , "compiledEntries = do"
          , "  scopes <- Handlers.newScopeHandlers"
          , "  pure"
          , "    [ " ++ intercalate "\n    , "
              ["SDK.targetApp " ++ show terminal ++ " emptyContexts scopes"
                ++ " (FrameworkRoot.withErrorHandlers Handlers.errorHandlers (" ++ terminal ++ "Result <$> " ++ method ++ "))"
              | (terminal, method) <- zip selected methods]
          , "    ]"
          , ""
          , "-- SDK 装配入口，不需要用户提供节点执行器或重复选择 handler。"
          , "interpreter :: SDK.AST -> [EffectSpec] -> IO ()"
          , "interpreter = SDK.interpreter " ++ show namespace ++ " registeredEffects Handlers.handlerSourceFingerprint compiledEntries"
          ]

    -- workflow 与纯 target 共用同一注册快照核对规则。
    registrationSnapshot =
      [ "-- 编译时注册快照；运行前核对声明，改变连接后须重新生成。"
      , "registeredEffects :: [EffectSpec]"
      , "registeredEffects ="
      , "  [ " ++ intercalate "\n  , " (map show specifications)
      , "  ]"
      , ""
      ]

