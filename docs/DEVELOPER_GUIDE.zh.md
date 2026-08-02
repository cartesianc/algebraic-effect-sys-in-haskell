# myframework 框架开发者指南

## 1. 读者和阅读顺序

本文服务于维护 myframework 编译器、AST、Effect core、Runtime、diagnosis、
TrustBase 和 SDK lowering 的开发者。

第一次使用 Facade 编写业务程序，请先读
[使用入门](GETTING_STARTED.zh.md)。

建议按以下顺序阅读源码：

1. src/MyFramework.hs
2. src/MyFramework/Facade.hs
3. src/MyFramework/Schema.hs
4. src/MyFramework/Elaboration.hs
5. src/MyFramework/Effect.hs
6. src/MyFramework/Graph.hs
7. src/MyFramework/Control/V52.hs
8. src/MyFramework/EffSys.hs
9. src/MyFramework/Hook.hs
10. src/MyFramework/Callback.hs
11. src/MyFramework/Ast.hs
12. src/MyFramework/Recursion.hs
13. src/MyFramework/Runtime.hs
14. src/MyFramework/Runtime/V52.hs
15. src/MyFramework/Runtime/Diagnosis.hs

## 2. 当前实现和目标合同

开发时先区分两个 epoch：

| 层 | 当前状态 |
|---|---|
| v2-compatible Facade | migration only，位于 MyFramework.Legacy.* |
| typed CURDE core | 已运行，提供 GADT Handle、RExpr、Implementation 和 demand graph |
| v5.2 Stage 3 | 已运行，提供 schema-free Facade、正式 MAP、Application 和三图分离 |
| v5.2 Stage 4 | 已运行，提供 defunctionalized Input CPS、统一 Runtime 和 occurrence single-flight |
| v5.2 Stage 5 | 已运行，提供 first-class EffSysRef、scope closure、live view 和 snapshot |
| v5.2 Stage 6 | 已运行，提供 hanging HookPlan、middleware wrapper 和 hook provenance |
| v5.2 Stage 7 | 已运行，提供 CallbackRef、事务 PipelinePatch 和 run-local continuation |
| v5.2 Stage 8 | 已运行，提供单 child Loop、versioned policy、revision replay、嵌套传播和 LIFO cleanup |
| v5.2 Stage 9 | 已运行，提供控制 hook、versioned Context、v5.2 FrameworkAsBusiness、EmptyBusiness 和 SDK source epoch |
| v5.2 Stage 10 | 待执行 self-artifact、显式 promotion 和 approved SDK 独立验证 |

当前源码可以作为迁移基础。v5.2 设计只有在 Facade、schema elaboration、lowering、runtime、
witness、self-artifact 和 SDK 全部闭合后才进入 current core。

## 3. 总体数据流

框架保留 typed runtime 维护入口。默认业务 Facade 已切换到 v5.2 program pipeline。

### 3.1 Legacy Frontend

    ReferencedProgram
      -> validateReferencedProgram
      -> resolveProgram
      -> runReferencedProgram
      -> FrontendRunResult

该路径用于 v2 artifact migration 和基线 witness。

### 3.2 Typed core

    EffSys + AstBlueprintSeed
      -> lowerCURDE
      -> LoweringResult
      -> prepareRuntime
      -> RuntimeProgram
      -> runRuntimeProgram
      -> RuntimeRun

RuntimeRun 包含：

    BranchSnapshot
    ControlResult
    DiagnosisResult

HandlerRegistry 在运行阶段传入，不进入 RuntimeProgram。

### 3.3 v5.2 elaboration pipeline

    SurfaceProgram
      + TypedDeclarations
      + CodecCatalog
      + ImportedSchemaCatalog
      -> elaborateProgram
      -> ElaboratedProgram
      -> validate
      -> lowerCURDE
      -> RuntimeProgram

SurfaceProgram 面向业务 authoring。ElaboratedProgram 面向编译、序列化、Runtime、
SDK 和 artifact witness。当前 Frontend 将两层合并在 ParamBinding 中，属于 migration。

## 4. Effect 模型

### 4.1 Typed Handle

核心 Handle 类型：

    Handle
      (name :: Symbol)
      (kind :: CURDE)
      args
      result

四个索引分别约束：

- 类型级名称；
- C/U/R/D/E kind；
- Handler 参数；
- observation 或 R 值。

SCURDE 提供 kind singleton。SchemaRef args 和 SchemaRef result 保存擦除前后的
schema 联系。

### 4.2 Command

C、U、D、E 是 command kind。它们共享 CommandSpec：

    data CommandSpec args observation = CommandSpec
      { commandArgumentSchema :: SchemaRef args
      , commandObservation    :: ObservationSpec observation
      , commandInput          :: Maybe SomeHandleRef
      }

Command Handler：

    HandlerInput
      -> args
      -> IO (Either RuntimeFailure observation)

DiscardObservation 使用 NoObservation 类型，避免伪造一个可公开读取的结果值。

### 4.3 R

R Handle 固定参数类型为 Unit：

    Handle name R () value

ReadSource 当前包括：

    ReadFromHandler
    ReadFromInputValue
    ReadFromInputObservation

RExpr 是封闭、类型化、可擦除的值表达式：

    RReference
    RLiteral
    RProduct

RExpr 中没有宿主函数入口。复杂转换通过具名 R Handler 表达。

### 4.4 MAP

MAP 属于 v5 目标类型。它将现有 ParamBinding/RExpr 中的显式对齐责任提升为独立
Effect IR：

    MAP
      inputs  :: [RRef]
      output  :: ParamSchema
      transform :: TransformRef

MAP 的职责：

- 收集 R 值；
- 校验输入 schema；
- 执行具名转换；
- 产生 command args record；
- 保存可诊断的数据边。

### 4.5 六种类型总表

| 类型 | 输入 | 输出 | 执行者 |
|---|---|---|---|
| C | args + HandlerInput | status + private observation | Command Handler |
| U | args + HandlerInput | status + private observation | Command Handler |
| R | ReadSource + HandlerInput | typed value | Read Handler/runtime |
| D | args + HandlerInput | status + private observation | Command Handler |
| E | args + HandlerInput | status + private observation | Command Handler |
| MAP | one or more R values | args record | Transform Handler/runtime |

框架不会为 C/U/D/E 自动推导数据库语义。类型标签用于 Effect 分类、注册校验、
lowering 和诊断。

### 4.6 Schema-free Facade

v5.2 默认业务 Facade 不导出 SchemaIdentity constructor，也不要求用户调用
scalarType、recordType 或 unitType。

当前 API：

    r :: String -> SchemaIdentity -> R
    literal :: SchemaIdentity -> ParamLiteral -> Binding
    record :: SchemaIdentity -> [(Name, Binding)] -> Binding
    type Binding = ParamBinding

该 API 让业务代码直接构造 elaborated metadata。目标分层：

    data SurfaceBinding
      = FromR EffectRef
      | FromLiteral LiteralValue
      | FromRecord [(ParamKey, SurfaceBinding)]
      | FromMap EffectRef

    data ElaboratedBinding = ElaboratedBinding
      { bindingSource :: BindingSource
      , bindingSchema :: SchemaRef
      , schemaOrigin  :: SchemaOrigin
      }

业务前台示例：

    type R value = Effect 'R Unit value

    seedUrl :: R Url
    seedUrl = r "seed-url"

    request =
      record
        [ url     .= fromR seedUrl
        , headers .= fromR requestHeaders
        ]

类型、codec 和子 binding 为 elaborator 提供约束。record schema 由字段 key 与子
SchemaRef 规范化生成。这里的 R 是统一 Effect 类型的 typed facade alias，不建立独立
R registry。

### 4.7 Schema 证据来源

| source | 证据 |
|---|---|
| `R a`、`Effect args result` | 类型参数、HasSchema 或 Generic |
| literal | literal constructor |
| record | 字段 key 和子 schema |
| MAP | transform codec contract |
| Handler adapter | args/result codec |
| imported artifact | signed SchemaCatalog |
| FFI/opaque/dynamic JSON | versioned boundary codec |

任意 Haskell 函数值没有稳定的源码 binding 名和参数名。Typeable 提供类型 identity，
Generic 提供 datatype、constructor 和 record selector metadata。Handler 使用 EffectRef
注册，函数名不承担 Effect identity：

    register fetchPage fetchPageHandler

### 4.8 Elaborator 约束求解

elaborateProgram 执行：

1. 构建 R、MAP、command、binding、codec 和 imported schema 的约束集；
2. 从 typed declaration、literal 和 codec 建立已知 SchemaRef；
3. 沿 FromR、FromRecord、MAP output 和 Application 传播；
4. 对 MAP output 与 command params 进行字段和类型统一；
5. 生成 canonical SchemaDescriptor、SchemaId 和 provenance；
6. 收集全部 schema error；
7. 成功后产生 ElaboratedProgram。

主要错误：

    SchemaUnresolved
    SchemaConflict
    SchemaCycle
    SchemaCodecMissing
    SchemaVersionConflict
    RecordFieldMissing
    RecordFieldUnexpected
    MapOutputMismatch
    NonSerializableBoundary

Elaborator 是纯阶段。它不调用 Handler，也不从第一次运行值猜测 schema。

### 4.9 Canonical catalog

SchemaDescriptor 至少保存：

    SchemaId
    SchemaShape
    SchemaVersion
    SchemaOrigin

确定性要求：

- display name 不参与相等判断；
- Unit 使用固定 identity；
- scalar identity 来自 codec/type identity；
- record identity 来自规范化字段和子 SchemaId；
- opaque identity 来自 versioned codec；
- provenance 不参与值相等；
- catalog 编码、排序和 digest 跨构建稳定。

当前 Runtime 对 ScalarShape 接受 Bool、Integer、Decimal 和 Text。v5.2 elaborator 需要
保存可区分的 scalar codec identity，并在 Handler codec 边界完成严格检查。

## 5. AST

### 5.1 固定点

AST 使用固定点编码：

    newtype Fix f = Fix
      { unFix :: f (Fix f)
      }

    type Ast = Fix AstF

AstF 只描述一层：

    Leaf
    WithImplementation
    Chain
    Parallel
    Fallback
    Race
    Choice
    Wait
    Loop
    Middleware
    Callback
    Suspense
    Context

next 参数保存递归位置。AstF 派生 Functor、Foldable 和 Traversable。

### 5.2 Seed 和内部树

AstSeed 是序列化 authoring form。lowerAstSeed 执行全量、纯函数式转换：

    AstSeed -> Fix AstF

Seed 保存 stable reference 和 serializable declaration。Fix AstF 提供统一递归
解释接口。

### 5.3 AST 的责任

AST 管理：

- boot root；
- 模块层级；
- occurrence path；
- 顺序和并发；
- alternative；
- wait、suspense 和 loop；
- middleware/callback scope。

Effect demand graph 管理 Handle、Implementation、input 和参数引用。两类图在
lowering 阶段关联。

## 6. cata、ana 和 hylo

### 6.1 cata

当前递归内核实现 Fix、Algebra 和 cata：

    type Algebra f result =
      f result -> result

    cata ::
      Functor f =>
      Algebra f result ->
      Fix f ->
      result

定义：

    cata algebra =
      algebra
        . fmap (cata algebra)
        . unFix

cata 自底向上工作：

1. unFix 取出当前 AstF 层；
2. fmap 递归折叠 children；
3. algebra 接收已经折叠的 child result；
4. algebra 生成当前节点 result。

当前使用场景：

- AST lowering；
- Control plan 编译；
- layout 投影；
- 路径归因；
- validation summary；
- demand root 收集。

### 6.2 algebra

Algebra 定义每种 AST constructor 的解释：

    controlAlgebra ::
      AstF ControlFold ->
      ControlFold

Chain 可以映射到 ControlSequence，Parallel 映射到 ControlParallel，Leaf 解析成
DemandNodeId。新增 AstF constructor 时，所有相关 algebra 都要显式处理。

这项约束可以暴露遗漏的解释器分支。GHC 的 pattern exhaustiveness warning 提供
第一层保护，semantic witness 提供第二层保护。

### 6.3 ana

ana 是 unfold：

    type Coalgebra f seed =
      seed -> f seed

    ana ::
      Functor f =>
      Coalgebra f seed ->
      seed ->
      Fix f

概念定义：

    ana coalgebra =
      Fix
        . fmap (ana coalgebra)
        . coalgebra

适合场景：

- 从 JSON-RPC 引用解析器按需展开 AST；
- 从远程模块索引生成本地树；
- 从状态机 seed 生成有限控制结构。

当前 MyFramework.Recursion 尚未实现 ana。协议驱动 boot 语义完成设计后再加入。

### 6.4 hylo

hylo 组合 unfold 和 fold：

    hylo ::
      Functor f =>
      Algebra f result ->
      Coalgebra f seed ->
      seed ->
      result

概念定义：

    hylo algebra coalgebra =
      algebra
        . fmap (hylo algebra coalgebra)
        . coalgebra

它可以在逻辑上省去中间 Fix tree，适合远程引用流直接生成 layout、validation report
或 lowering summary。

当前 runtime 需要稳定 AstPath、layout 和 diagnosis attribution，因此保留显式 AST。
hylo 进入实现前需要证明路径、错误累积和重放证据保持一致。

### 6.5 选择原则

| 需求 | 递归方案 |
|---|---|
| 已有完整 AST，生成 summary | cata |
| 从 seed 生成 AST | ana |
| 从 seed 直接生成 summary | hylo |
| child 原树也参与计算 | para |
| 需要历史折叠信息 | histo |

当前稳定合同只有 Fix + cata。

## 7. Interpreter 分层

框架中有四个 interpreter 阶段。

### 7.1 Frontend resolver

输入：

    ReferencedProgram

输出：

    ResolvedNode

它完成模块名和局部 key 分类、引用展开、路径分配和静态错误收集。

### 7.2 CURDE lowering

输入：

    EffSysDecl
    AstBlueprint

输出：

    CURDECore
      { EffSysDecl
      , [ImplementationDecl]
      , AstBlueprint
      , DemandGraph
      }

Lowering 从 AST application/binding 收集 demand root，再添加 input 和 RExpr 依赖。

### 7.3 Control compiler

输入：

    CURDECore

输出：

    ControlPlan

Control compiler 使用 cata 将 AstF 映射到 ControlTree。ControlDemand 保存已经解析的
DemandNodeId。Branch 节点保存调度结构。

### 7.4 Runtime interpreter

输入：

    RuntimeProgram
    HandlerRegistry
    RuntimeHooks

输出：

    RuntimeRun

Runtime interpreter 运行 Control plan，调用 demand evaluator，合并 branch snapshot，
最后生成 diagnosis。

## 8. RuntimeAction

RuntimeAction 位于 runtime hook API：

    newtype RuntimeAction = RuntimeAction
      { unRuntimeAction :: ControlAction
      }

    type ControlAction =
      BranchSnapshot ->
      IO ControlResult

它表示一个已经编译好的 child control computation。输入是分支快照，输出包含：

    data ControlResult = ControlResult
      { controlResultSnapshot    :: BranchSnapshot
      , controlResultOutcome     :: ControlOutcome
      , controlResultDiagnostics :: [ControlDiagnostic]
      }

主要用途：

- Middleware 包裹 child；
- Callback 包裹或替换 child；
- 测试 hook 返回成功、失败或挂起；
- 保持内部 demand callback 封闭。

相关函数：

    runtimeAction
    runRuntimeAction
    succeedRuntimeAction
    suspendRuntimeAction
    failRuntimeAction

RuntimeAction 不进入序列化 AST。它由 Runtime 在 ControlTree 已经验证后构造。

## 9. input、Free IR 与 CPS

v2 compatibility core 在 HandleDecl 中保存 input：

    handleDeclInput :: Maybe HandleId

DemandGraph 将其转换为 InputDependency edge。Runtime 从 demand root 递归求前置闭包。

v5.2 在 `MyFramework.Runtime.V52` 中把 `InputGraph` 编译为
`ContinuationPlan`。设 B.input = A：

    compile B k =
      compile A
        (\outcome ->
          dispatch outcome B k)

业务值走 R/MAP 图，continuation 只携带控制结果。

`ContinuationNode` 保存稳定 node id、occurrence、AstPath、EffectRef、前驱
continuation id 和可解析的 application occurrence。前驱绑定到 application 后，Runtime
执行该 application 的 R、MAP 与 command，并把 `Succeeded / Failed / Cancelled /
Suspended` 交给后继。无 application 的裸 input effect 走 lifecycle handler，调用参数为空。

运行前检查覆盖 Handler 缺失、Effect kind、输入/输出 schema、MAP 输出歧义。错误完整
返回后 Runtime 才允许 Handler IO。执行实例身份固定为：

    BootRunId + AstPath + EffectRef

single-flight key 使用该身份。同一 occurrence 的重复 demand 共享结果；不同 AstPath
分别执行。`RuntimeDiagnosis.runtimeDiagnosisInputTrace` 记录实际经过的 ContinuationId，
可与 InputGraph edge 对照。

Source IR 可以按 free-style algebra 理解：

- operation 保存为数据；
- AST 保存组合；
- interpreter 延迟；
- graph transform 可以在运行前检查。

完整 Free Monad bind 需要 result -> nextProgram。当前 input 保存固定引用，适合
free sequential algebra 和 defunctionalized CPS。

## 10. Eff graph 与 AST graph 边界

### 10.1 DemandGraph

DemandGraph 节点：

    HandleNode HandleId
    ImplementationNode ImplementationId

边类型：

    InvokeImplementation
    InputDependency
    ArgumentUse FieldPath

RootDemand 从 AST leaf/application 产生。

### 10.2 边界规则

AST 的 Chain、Parallel、Fallback、Race、Choice 和 Wait 不进入 DemandEdgeKind。
它们保留在 ControlTree。

DemandGraph 只保存真实前置条件：

- Handle 需要哪个 Implementation；
- Handle 需要哪个 input Handle；
- Implementation 参数使用哪个 R。

Lowering 同时保存 AstPath 作为归因信息。AstPath 不参与 prerequisite reachability。

### 10.3 demand closure

    demandClosure ::
      DemandGraph ->
      [DemandNodeId]

算法从 RootDemand 出发，沿 dependent -> prerequisite 边遍历。结果限定本次程序允许
触达的 Handle 和 Implementation。

收益：

- 未被 AST demand 的注册项保持 Unused；
- input 和参数依赖自动进入执行闭包；
- validation 可以检查缺失引用和非法环；
- diagnosis 可以沿真实数据/句柄边追踪；
- AST 调度错误和 Effect 依赖错误保持独立。

## 11. Diagnosis

### 11.1 输入

Diagnosis 使用：

    DemandGraph
    ControlPlan
    RuntimeState

运行入口：

    diagnoseDemand
    diagnoseFailedDemands

JSON schema：

    myframework.runtime-diagnosis.v1

### 11.2 失败通道

    ExecutionFailureChannel
    ReadFailureChannel
    ImplementationFailureChannel

通道分离保留原始事实。例如 command 已成功、随后 R 无法读取 observation，diagnosis
会记录 ReadObservationUnavailableReason，同时保留 command 的成功状态。

### 11.3 Trace

DiagnosisTraceStep 保存：

    direction
    from
    to
    DemandEdgeKind
    optional AstPath

方向：

    TowardPrerequisite
    TowardDependent

每一步对应真实 DemandGraph edge。Control 顺序不会被误判为数据依赖。

### 11.4 Impact

    DiagnosisRootImpact
    DiagnosisSuspectImpact
    DiagnosisPollutedImpact

Root 表示直接失败点。Suspect 表示证据不足或 observation 不可用。Polluted 表示依赖
失败值或失败执行的下游节点。

AstPath 将 impact 投影回 layout，渲染器可以高亮节点。Diagnosis 只读，不修改
RuntimeState。

### 11.5 使用

    currentRun <-
      runRuntimeProgram
        runtimeProgram
        handlers
        hooks

    let diagnosis =
          runtimeRunDiagnosisResult currentRun

    putStrLn
      (renderDiagnosisResultJson diagnosis)

## 12. 并发和异步

### 12.1 Haskell runtime 基础

框架当前使用：

    forkIO
    MVar
    mask
    onException
    killThread

GHC lightweight thread 由 RTS 调度。MVar 提供阻塞同步和一次性交付。等待 MVar 时
线程交还执行能力，无需业务层轮询。

### 12.2 Parallel

runParallelWorkers：

1. mask 保护 worker group 建立；
2. forkIO 启动每个 action；
3. worker 将 WorkerReport 写入独立 completion MVar；
4. 主线程等待全部 completion；
5. 异常路径执行 cancelAndDrainWorkers。

WorkerReport 保存声明索引和完成顺序。结果合并使用声明顺序，减少调度时序对最终
快照的影响。

### 12.3 Race

runRaceWorkers：

1. 并发启动 actions；
2. 选择首个满足成功谓词的 report；
3. 请求取消 loser；
4. drain 所有 completion；
5. 返回 winner、取消索引和完整 reports。

外部 IO 可能已经提交。Runtime 通过 CommitState 和 settlement audit 判断 Fallback
或 Race 是否能安全丢弃分支。

### 12.4 Single-flight

DemandCoordinator 按 HandleId 保存 HandleFlight。第一个请求成为 owner，后续请求
等待同一个 completion MVar。

single-flight 边界在 input 和 RExpr prerequisite 完成后建立。这样可以避免：

- 同一 Handle 重复执行；
- 并行分支重复读取同一 R；
- 多个 dependent 观察不同完成结果。

### 12.5 BranchSnapshot

每个并发分支复制：

    RuntimeState
    ObservationStore

Parallel 使用保守 three-way merge。Fallback 和 single-flight 使用 strict delta
merge。冲突记录 RuntimeStateField、base、merged 和 branch value。

### 12.6 实际限制

- CPU 密集任务需要 threaded RTS 和合适的 capability 数量；
- forkIO 提供并发，CPU 并行度由 RTS 配置和 workload 决定；
- killThread 使用异步异常，外部系统提交无法自动回滚；
- mask 区域需要保持短小；
- Handler 必须自行处理资源释放、幂等和事务；
- MVar 协议错误可能导致死锁，worker completion 必须保证发布。

## 13. 类型安全

框架使用多层类型保护。

### 13.1 编译期

- DataKinds 将 C/U/R/D/E 提升到 kind；
- GADT Handle 保留 kind、args 和 result；
- CommandKind 排除 R command implementation；
- R Handle 固定 args = Unit；
- ObservationSpec 区分 capture 和 discard；
- SomeCommandHandleRef 的 constructor 排除 R；
- AstF 的穷尽匹配暴露新增 constructor 的遗漏；
- RuntimeProgram constructor 保持私有。

### 13.2 擦除边界

序列化需要擦除宿主类型：

    Handle -> HandleDecl
    Implementation -> ImplementationDecl
    RExpr -> RExprDecl
    EffSys -> EffSysDecl

SchemaIdentity、HandleId 和 kind witness 保留重建检查所需信息。

v5.2 的 SchemaIdentity 来自 elaboration。业务源码不直接构造它。

### 13.3 Runtime

- Handler codec 必须匹配 Handle schema；
- observation mode 必须匹配；
- ValueTag + Typeable 支持 opaque value 安全回收；
- ParamBinding 和 RExpr 在调用前验证；
- ElaboratedProgram 中每条 demanded value edge 都有唯一 SchemaRef；
- malformed serialization 在 lowering 阶段拒绝；
- runtime 不执行带 validation error 的 core。

类型系统无法证明外部 API 正确、Handler 幂等或数据库事务成功。相关合同需要
Handler 测试、policy Effect 和 witness。

## 14. First-Class Effect

v5.2 FCE 的载体是带 AST scope 的擦除后 EffSysRef：

    data EffSysRef = EffSysRef
      { effSysRefAstRoot :: String
      , effSysRefRegistry :: EffSysRegistryId
      }

它提供：

- Effect IR 查询；
- input pipeline 查询；
- 运行状态投影；
- observation 查询；
- scope 统计；
- callback patch 输入；
- Loop policy 输入。

`applyEffSys command map read ref` 把引用写入 R 的 `ValueEffSysRef`。ValueGraph
生成 `ValueEffSysRefRole -> ValueReadRole`，Runtime 将序列化引用交给 MAP。这个值不会
增加 demand。

`buildEffSysIR` 先截取 AST subtree，再沿 ContinuationPlan 纳入 input 可达 occurrence，
最后投影 InputGraph、ValueGraph、EffectRegistry 和 TransformRegistry。`EffSysView` 从
IORef 读取 live projection，`EffSysSnapshot` 保存可 round-trip 的历史值。查询 API 没有
Runtime 执行入口。

Facade 在 Handler 启动前验证 registry identity、scope root 唯一性和 consumer AstPath。
scope 外引用与 registry 不匹配均进入 `ProgramEffSysFailed`。

实现分工：

    Free-style IR
      保存和组合程序

    Existential package
      保存异构 Handle/Handler

    Schema witness
      检查擦除边界

    EffSysRef
      提供 first-class registry

Row polymorphism 留给未来 typed SDK library。它解决开放 Effect 集合的静态约束，
不会替代 EffSysRef 的值级序列化。

## 15. Middleware、Callback 和 Loop

### 15.1 Middleware

RuntimeHooks 中：

    runtimeHookMiddleware ::
      MiddlewareRef ->
      AstPath ->
      RuntimeAction ->
      RuntimeAction

Middleware 可以在 child 前后记录事件、读取快照、统计状态和运行自身 action。

Stage 6 将 Scoped EffSysRef 交给 hanging middleware，并记录 hook 生命周期事件。
`astBlueprintHanging` 编译为独立 `HookPlan`；detached application 不进入 AST boot root。
Runtime 按 AST scope 深度和声明顺序构造 wrapper。`MiddlewareContext` 提供 scope ref、
AstPath、只读 snapshot、child RuntimeAction 和可选 own-application RuntimeAction。
capability boundary 不暴露 InputGraph、ValueGraph、ContinuationPlan 或 patch API。

### 15.2 Callback

    runtimeHookCallback ::
      HandleId ->
      AstPath ->
      RuntimeAction ->
      RuntimeAction

v5.2 Callback 使用独立 `CallbackRef`。`CallbackContext` 提供只读 ContinuationPlan
snapshot 和事务 `callbackContextSubmit`。Patch 支持：

    InsertInput target effect
    ReplaceInput target effect
    RemoveInput target
    RedirectInput source target

Runtime 在 occurrence 首次启动前验证 scope、EffectRef kind/schema identity、单前驱、cycle、
target lifecycle 和并发冲突。整批 patch 通过后更新本次 BootRun 的 continuation 副本。
任一错误保留提交前计划。`RuntimeDiagnosis` 保存 original plan、patch、CallbackRef、final
plan 和错误列表。全局 Program、registry 与其他 BootRun 不受影响。

Callback 已通过独立 witness 验证四种 patch、事务回滚、并发冲突、lifecycle gate 和
Diagnosis provenance。

### 15.3 Loop

    loop :: AstRef child => Name -> child -> ControlDecl
    loopWith :: AstRef child => Name -> VersionedLoopPolicy -> child -> ControlDecl

`Loop` 与 Chain、Parallel、Fallback、Race 同级，只接收一个 child。默认 policy 为：

    VersionedLoopPolicy
      (LoopPolicyRef "until-quiescent/default")
      (LoopPolicyVersion 1)
      (UntilQuiescent 1024)

每次 Loop 至少运行 child 一次。Runtime 只观察该次实际 demand 的 value handler batch，
使用 `handlerRegistrationOutputEquivalent` 判断变化；同一迭代的多次变化合并成一个
`StateRevision`。变化触发 child scope replay，外部 occurrence 保持 single-flight。
内层 Loop 先 settle，其 revision 再合并给外层。已启动资源按 Handler 启动顺序的逆序
执行 cleanup；cleanup failure 进入 Loop outcome 和 Diagnosis。缺少 equivalence 的动态
边界在 Handler IO 前被拒绝。

### 15.4 Choice、Wait、Suspense 和 Context

Facade 把四种节点编译成按 `AstPath` 索引的 `ControlPolicyRegistry`。编译期检查
节点 arity、Choice 选择键、Suspense EffectRef 和 Context identity。未知 Context 进入
`ProgramControlPolicyFailed`，不会到达 Runtime。

Wait 与 Suspense 的 Runtime 路径调用 `RuntimeControlHooks`：

    AstPath
      -> serialized versioned gate policy
      -> immutable RuntimeSnapshot
      -> IO ControlGate

Suspense hook 额外收到目标 EffectRef。hook 是 runtime-only closure，只能给出 Ready、
Blocked 或 Failed，不能修改 AST、三图或 ContinuationPlan。每次判定生成带 AstPath、
node kind、目标引用和结果的 RuntimeEvent。Context 当前提供 version 1 identity extension。

## 16. 框架优势

### 16.1 前台可序列化

AST、Effect、schema 和引用可以存储、diff、签名、生成 SDK 和进入 artifact witness。
Handler closure 留在 runtime registry。

业务 authoring 不重复声明 schema。Elaboration 将类型、codec、literal、record 和 MAP
约束转换成可序列化 SchemaCatalog。

### 16.2 控制图与依赖图分层

AST 保存调度。DemandGraph 保存真实依赖。R/MAP 保存值来源。每类错误可以在对应图
上检查，diagnosis 也能沿真实边回溯。

### 16.3 先验证后执行

Lowering 收集完整错误。prepareRuntime 拒绝带错误的 core。运行时不会使用
best-effort partial graph。

### 16.4 类型化 Handler 边界

GADT、schema、codec、existential package 和 runtime validation 共同保护异构
registry。后台实现可以使用普通 Haskell IO 和成熟库。

### 16.5 Haskell 并发

Lightweight thread、MVar、异步异常屏蔽和纯快照 merge 适合表达 Parallel、Race、
single-flight 和 cancel/drain。IO 密集业务可以获得直接收益。

### 16.6 Diagnosis

失败通道、真实依赖 trace、AST attribution 和 impact overlay 让错误报告同时回答：

- 直接失败点；
- 前置依赖；
- 下游污染范围；
- 失败所在 AST 位置；
- 当时各状态通道的值。

### 16.7 自举和 SDK 证据

FrameworkAsBusiness、Stage1/Stage2 fixed point、TrustBase、promotion record 和
SDK core lock 建立从语义源码到发布产物的可验证链。

## 17. 设计限制

- Loop policy、revision replay、嵌套传播和 cleanup 已实现；
- schema-free SurfaceProgram、elaborator、MAP 和 Application 已实现；
- 默认 Facade 已移除显式 SchemaIdentity；
- 当前 ScalarShape 无法严格区分 Bool、Integer、Decimal 和 Text；
- 当前简化 Frontend runtime 未执行 Race；
- v5.2 Context 只接受已注册的 versioned identity；未知 identity 在 Runtime 前失败；
- ana 和 hylo 尚未进入 Recursion module；
- 外部 IO 的事务性依赖 Handler；
- Graph validation 不能证明业务算法正确；
- 类型擦除后的输入仍需 runtime schema validation；
- self-artifact 通过不会自动批准 promotion。

## 18. 修改框架时的工作流

### 18.1 找入口

按功能选择一个锚点：

| 需求 | 入口 |
|---|---|
| 业务语法 | MyFramework.Facade |
| schema elaboration | MyFramework.Frontend / future MyFramework.Elaboration |
| Effect 类型 | MyFramework.CURDE.Types |
| AST constructor | MyFramework.Ast |
| 递归 fold | MyFramework.Recursion |
| lowering | MyFramework.CURDE.Lowering |
| demand graph | MyFramework.CURDE.Core |
| Control interpreter | MyFramework.Control |
| runtime hook | MyFramework.Runtime |
| 并发 | MyFramework.Runtime.Concurrent |
| diagnosis | MyFramework.Runtime.Diagnosis |
| SDK | MyFramework.SDK |
| 自举和 promotion | MyFramework.Self / MyFramework.TrustBase |

### 18.2 同步责任

语义修改通常需要同步：

    Facade
    Surface/Elaborated IR
    SchemaCatalog and elaboration
    Core type/schema
    erased declaration
    lowering
    validation
    runtime
    witness
    claim manifest
    SDK lowering digest
    L0 version/status

### 18.3 本地检查

文档：

    git diff --check

普通代码：

    stack --work-dir .stack-work-codex build
    stack --work-dir .stack-work-codex exec curde-semantics-witness
    stack --work-dir .stack-work-codex exec crawler-facade-witness
    stack --work-dir .stack-work-codex exec curde-runtime-witness
    .\scripts\check-ast-execution-boundary.ps1

Release 和 self-artifact gate 只在候选 core 验证阶段运行。

## 19. 术语速查

| 术语 | 含义 |
|---|---|
| Effect | 可序列化 operation 声明 |
| Handle | 带 kind、args、result 的 typed Effect identity |
| Handler | Handle 的过程实现 |
| SurfaceProgram | 不含手写 SchemaIdentity 的业务 authoring IR |
| ElaboratedProgram | 已解析 SchemaRef、可进入 validation/lowering 的 IR |
| SchemaCatalog | canonical schema descriptor、version 和 digest 的集合 |
| SchemaOrigin | schema 推导来源的 provenance |
| RExpr | 当前 typed core 的封闭参数表达式 |
| MAP | v5 显式数据转换 Effect |
| AstF | AST 的一层 base functor |
| Fix | 递归结构的固定点 |
| cata | 从完整递归结构向上折叠 |
| ana | 从 seed 向下展开递归结构 |
| hylo | unfold 与 fold 的融合 |
| Algebra | f result -> result |
| Coalgebra | seed -> f seed |
| DemandGraph | Handle、Implementation、input 和参数使用图 |
| ControlPlan | AST 调度结构的可执行投影 |
| RuntimeAction | BranchSnapshot -> IO ControlResult 的公开包装 |
| BranchSnapshot | RuntimeState 与 ObservationStore 的分支快照 |
| single-flight | 同一 Handle 的并发请求共享一次执行 |
| diagnosis | 基于 DemandGraph 和 RuntimeState 的失败分析 |
| EffSysRef | v5 first-class scoped Effect registry |
