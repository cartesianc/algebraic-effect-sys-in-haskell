# myframework L0 框架合同

## 0. 文档地位

    状态：FROZEN ARCHITECTURE CONTRACT
    层级：L0 / 最高语义层级
    版本：v5.2
    日期：2026-08-01
    维护属性：LONG-LIVED / CONTINUOUSLY EVOLVED
    稳定路径：docs/L0_EFFECT_LOOP_BOOTLOADER_SEMANTICS.zh.md
    实现状态：Stage 0—7 已实现；Stage 8—10 推进中
    Promotion：本语义 epoch 尚未 promotion

本文记录长期稳定的语义边界、版本状态和完成条件。

使用教程位于：

[myframework 使用入门](GETTING_STARTED.zh.md)

框架内部实现位于：

[myframework 框架开发者指南](DEVELOPER_GUIDE.zh.md)

文档优先级：

    L0 合同
      > versioned schema 与 witness contract
      > 框架开发者指南和专题文档
      > 当前源码
      > 迁移层与示例

## 1. 长期维护规则

1. 本文件路径长期保持稳定。
2. FROZEN 语义变更需要递增 L0 版本。
3. 版本记录包含日期、动机、兼容性和迁移责任。
4. OPEN 项完成设计后转为 FROZEN。
5. 当前实现状态随源码持续更新。
6. Release、promotion 和 SDK lock 记录 L0 版本与源码 revision。
7. 专题设计的最终结论回写本文。
8. Git 历史保存旧版本。
9. 同级权威合同不得分叉。
10. 文档和实现可以分批完成，状态标记必须准确。

状态标记：

| 标记 | 含义 |
|---|---|
| FROZEN | 已进入 L0 合同 |
| OPEN | 责任已确定，细节待设计 |
| IMPLEMENTED | 当前源码已有实现和局部证据 |
| MIGRATION | 当前源码保留的旧 epoch 表面 |

## 2. 框架边界

业务程序使用三个 authoring surface：

    AST
    Effect registry
    Handler

业务导入入口：

    import MyFramework

序列化边界包含：

- AST；
- Effect IR；
- schema；
- stable reference；
- R/MAP 表达式；
- Scoped EffSysRef；
- versioned policy；
- graph patch；
- Handler identity coverage。

业务 Facade 不要求手写 SchemaIdentity。Schema catalog 由 elaboration 生成，随后进入
序列化 artifact、validation、lowering、Runtime 和 SDK。

运行时边界包含：

- Handler closure；
- codec；
- 网络和数据库资源；
- 线程和同步对象；
- native continuation；
- HostKernel；
- BoundTrustBase。

Runtime、TrustBase、SDK materializer 和 promotion 工具属于维护面。

## 3. Effect 合同

### 3.1 六种 Effect

    C / U / R / D / E / MAP

| 类型 | 合同 |
|---|---|
| C | command Handle，接收 args 和 HandlerInput |
| U | command Handle，接收 args 和 HandlerInput |
| R | 惰性读取 typed value |
| D | command Handle，接收 args 和 HandlerInput |
| E | command Handle，接收 args 和 HandlerInput |
| MAP | 将一个或多个 R 对齐到 command params |

C/U/D/E 的字母标签不携带通用 CRUD、retry、transaction 或 idempotency policy。

### 3.2 Command record

    Effect fetchPage =
      { type   = C
      , input  = openSession
      , params = [url, headers]
      }

左侧 key 提供模块内身份。record 字段：

    type
    input?
    params

### 3.3 R record

    Effect requestSource =
      { type   = R
      , input  = sourceRef
      }

R 的结果 schema 由 typed R、Read codec、导入 catalog 或受检边界描述提供。普通业务
record 不包含 schema 字段。

R source 可以引用：

- Handler environment；
- 上游 R；
- command private observation；
- Loop-local state；
- Scoped EffSys query；
- versioned external input。

### 3.4 MAP record

    Effect requestMap =
      { type   = MAP
      , inputs = [requestSource]
      , output = [url, headers]
      }

MAP output 必须与目标 command.params 对齐。Transform 使用稳定引用和 versioned
codec contract。Elaboration 将输入输出合同写入内部 schema catalog。

### 3.5 Module ownership

Effect 在 AST 模块内注册：

    effects fetch
      [ openSession
      , fetchPage
      , requestSource
      , requestMap
      ]

Lowering 生成内部 qualified address。Facade key 保持局部名称。

## 4. Schema-free Facade 与 elaboration

### 4.1 冻结结论

普通业务 authoring surface 只声明：

    stable key
    Effect type
    input reference
    params/value binding
    AST reference

以下构造不属于默认业务 Facade：

    scalarType
    recordType
    unitType
    SchemaIdentity constructor

Schema 继续存在于 elaborated IR。Facade、内部 IR 和 Runtime 的关系为：

    SurfaceProgram
      + typed declarations / CodecCatalog / imported SchemaCatalog
      -> elaborateProgram
      -> ElaboratedProgram
      -> validate
      -> lower
      -> RuntimeProgram

SurfaceProgram 允许保存、diff 和组合未 elaborated 的业务声明。执行、SDK 生成、
self-artifact 和 promotion 只接受完整 ElaboratedProgram。

### 4.2 Source IR 与 elaborated IR

Source binding 只保存值来源：

    data SurfaceBinding
      = FromR EffectRef
      | FromLiteral LiteralValue
      | FromRecord [(ParamKey, SurfaceBinding)]
      | FromMap EffectRef

Elaboration 生成：

    data ElaboratedBinding = ElaboratedBinding
      { source    :: BindingSource
      , schemaRef :: SchemaRef
      , origin    :: SchemaOrigin
      }

现有 `Binding = ParamBinding` 属于 migration 实现。v5.2 Facade 必须将两层分开。

### 4.3 Schema 信息来源

Elaboration 按以下来源建立约束：

| 来源 | schema 证据 |
|---|---|
| typed R / typed Effect | 类型参数及 HasSchema/Generic 派生 |
| literal | literal constructor |
| record binding | 字段 key 与子 binding schema |
| MAP | versioned transform codec contract |
| Handler adapter | args/result codec |
| imported artifact | 已签名 SchemaCatalog |
| opaque、FFI、动态 JSON | 显式 versioned boundary codec |

Handler 的过程函数无需携带框架 record。Adapter 或生成代码提供 codec contract，
EffectRef 提供语义身份。

### 4.4 Haskell 前台推导

推荐 typed surface：

    type R value = Effect 'R Unit value

    seedUrl :: R Url
    seedUrl = r "seed-url"

    fetchPage :: Effect FetchArgs Page
    fetchPage = effect "fetch-page" C ...

类型信息可以通过 Typeable、HasSchema、GHC.Generics 或 versioned codec 转成
SchemaRef。任意函数值不提供稳定的源码 binding 名和参数名。Handler 注册复用
EffectRef：

    register fetchPage fetchPageHandler

record 字段可以通过 Generic 获得。普通函数参数名不参与 schema 推导。

### 4.5 Canonical SchemaCatalog

ElaboratedProgram 保存 canonical SchemaCatalog：

    data SchemaDescriptor = SchemaDescriptor
      { schemaId      :: SchemaId
      , schemaShape   :: SchemaShape
      , schemaVersion :: SchemaVersion
      , schemaOrigin  :: SchemaOrigin
      }

规则：

1. display name 不参与语义相等；
2. Unit 使用固定 SchemaId；
3. literal scalar 使用 codec/type identity；
4. record descriptor 由有序字段 key 和子 SchemaId 规范化生成；
5. nominal/opaque 类型使用 versioned codec identity；
6. SchemaOrigin 用于 provenance 和 diagnosis，不参与值相等；
7. catalog 顺序、编码和 digest 必须确定性；
8. Effect key 和参数 key 不推导数据类型。

当前 `ScalarShape` 对 Bool、Integer、Decimal 和 Text 的宽松接受不满足 v5.2 scalar
identity 合同。新 elaborator 必须保留可区分的 scalar codec/type identity。

### 4.6 约束求解

elaborateProgram 按以下顺序工作：

1. 收集 R、MAP、command、binding、Handler adapter 和 imported catalog；
2. 为 typed declaration、literal、codec 和 imported schema 建立 seed constraint；
3. 沿 FromR、FromRecord、MAP output 和 Application 传播约束；
4. 对 command.params 与 MAP output 执行 record 对齐；
5. 规范化 descriptor 并生成 SchemaId；
6. 生成 provenance；
7. 返回完整 ElaboratedProgram 或全部错误。

错误至少包括：

    SchemaUnresolved
    SchemaConflict
    SchemaCycle
    SchemaCodecMissing
    SchemaVersionConflict
    RecordFieldMissing
    RecordFieldUnexpected
    MapOutputMismatch
    NonSerializableBoundary

Elaboration 收集错误，不启动 Handler，不执行网络或数据库 IO。

### 4.7 显式边界

显式 schema 入口只允许出现在无法推导的边界：

- FFI；
- opaque native value；
- 无类型动态 JSON；
- 外部协议；
- legacy artifact。

边界入口必须提供 stable SchemaId、version、codec 和 provenance。普通 params、R、MAP
和 AST authoring 不使用该入口。

### 4.8 运行与发布规则

Runtime 不以首个运行值推断 schema。该做法会破坏运行前验证、SDK 生成、重放和
artifact digest。

进入 validate/lower 前必须满足：

    every demanded value edge has one resolved SchemaRef
    every Handler adapter agrees with its EffectRef contract
    every MAP output aligns with command.params
    SchemaCatalog digest is reproducible

## 5. Application 与三类图

普通叶子：

    command $ MAP $ R

序列化形式：

    Apply
      { command :: EffectRef
      , mapper  :: EffectRef
      , reader  :: EffectRef
      }

框架保存三类图：

| 图 | 内容 |
|---|---|
| AST graph | Chain、Parallel、Fallback、Race、Choice、Wait、Loop 和 scope |
| input graph | command 之间的句柄控制依赖 |
| value graph | R、MAP 和 command params 之间的赋值关系 |

同一 command 可以在不同 AST 位置绑定不同 MAP/R。每个运行实例保存独立状态。

input closure 中带业务参数的 command 必须在当前 AST 词法作用域解析到唯一
application binding。Unit command 可以使用隐式 Unit binding。

## 6. input 与 CPS

设：

    B.input = A

执行顺序：

    A
    B

CPS lowering：

    compile B k =
      compile A
        (\outcome ->
          dispatch outcome B k)

continuation 使用统一控制结果：

    data Outcome
      = Succeeded
      | Failed Failure
      | Cancelled CancelReason
      | Suspended

    type Kont =
      Outcome -> Runtime Exit

业务值通过 R/MAP 求值。input 不传递业务返回值。

Source IR 的分类：

    free sequential effect algebra
    + explicit value graph
    + defunctionalized CPS lowering

完整 Free Monad bind 所需的 result -> nextProgram 不属于 input 字段。

普通 input graph 保持有根、无环。反馈执行使用 Loop。

## 7. AST 合同

规范节点：

    Application EffectApplication
    Chain [AstRef]
    Parallel [AstRef]
    Fallback [AstRef]
    Race [AstRef]
    Choice ChoiceKey [(ChoiceKey, AstRef)]
    Wait StatusExpr AstRef
    Loop AstRef
    Middleware MiddlewareRef AstRef
    Callback CallbackRef AstRef
    Suspense EffectRef
    Context ContextRef AstRef

arity：

| 节点 | arity |
|---|---:|
| Application | 0 |
| Chain | n |
| Parallel | n |
| Fallback | n |
| Race | n |
| Choice | n |
| Wait | 1 |
| Loop | 1 |
| Middleware | 1 |
| Callback | 1 |
| Suspense | 0 |
| Context | 1 |

控制合同：

- Chain 按声明顺序执行；
- Parallel 隔离分支并保守合并；
- Fallback 按顺序尝试 alternatives，并检查提交安全；
- Race 选择首个成功分支，取消并 drain loser；
- Choice 运行 selected branch；
- Wait 观察 StatusExpr；
- Loop 建立局部反馈边界；
- Middleware 包裹 child；
- Callback 提交 continuation/input graph patch；
- Suspense 挂起当前控制点；
- Context 保留 versioned extension point。

内部递归类型：

    type Ast = Fix AstF

当前稳定递归合同：

    Fix
    Algebra
    cata

ana 和 hylo 保留给协议驱动展开，尚未进入稳定 core。

## 8. First-Class Effect

第一等 Effect 使用 Scoped EffSysRef：

    data EffSysRef = EffSysRef
      { astRoot  :: AstRef
      , registry :: RegistryRef
      }

EffSysRef 可以作为结构化参数传递。它选择一棵 AST 子树及其可达 Effect registry。

可查询内容：

- Effect IR；
- input pipeline；
- 运行状态；
- observation；
- failure；
- scope statistics。

静态声明和动态状态分层：

    EffSysIR
      declarations

    EffSysView
      EffSysIR
      runtime states

EffSysRef 是 live reference。确定性历史输入使用显式 EffSysSnapshot。

FCE 的类型基础：

    Free-style serializable IR
    + existential Handle/Handler package
    + schema witness
    + Scoped EffSysRef

Row polymorphism 属于未来可选 typed SDK layer。

传递 EffSysRef 提供数据可达性。执行由 AST demand 发起。

## 9. Handler 合同

Command Handler：

    HandlerInput
      -> args
      -> IO (Either RuntimeFailure observation)

Read Handler：

    HandlerInput
      -> IO (Either RuntimeFailure value)

Handler 注册验证：

- Handle identity；
- argument codec；
- result/observation codec；
- observation capture mode；
- input use contract。

C/U/D/E 的公开结果是 execution status。Private observation 通过显式 R 暴露到
value graph。

运行状态通道：

    ExecutionStatus
    ReadStatus
    Observation
    Validity
    ImplementationStatus

各通道独立记录。

## 10. Runtime 合同

编译链：

    validate
      -> lower
      -> compileControlPlan
      -> prepareRuntime
      -> runRuntimeProgram

RuntimeProgram 包含：

    DemandGraph
    ControlPlan
    AstLayout

一次运行创建：

    BootRunId
    RuntimeState
    ObservationStore
    DemandCoordinator
    RuntimeEvent history

AST ControlDemand 生成内部 boot token：

    BootRunId
    AstPath
    root DemandNodeId

每次 Handler 调用记录实际 DemandNodeId、HandleId 和 provenance。

DemandGraph edge：

    InvokeImplementation
    InputDependency
    ArgumentUse FieldPath

AST control edge 不进入 DemandGraph。AstPath 只用于 attribution。

同一 HandleId 的并发 demand 使用 single-flight。

## 11. RuntimeAction 与 Hook

RuntimeAction：

    newtype RuntimeAction =
      RuntimeAction ControlAction

    type ControlAction =
      BranchSnapshot ->
      IO ControlResult

RuntimeAction 用于：

- Middleware child wrapper；
- Callback child wrapper；
- Runtime hook；
- 测试成功、失败和挂起路径。

RuntimeAction 不进入序列化 AST。

Middleware 接收 Scoped EffSysRef 和 child action。它可以观察状态、统计事件、记录
metrics 和运行自己的 Effect application。

Callback 读取 continuation scope，并返回受检 PipelinePatch：

    InsertInput
    ReplaceInput
    RemoveInput
    RedirectInput

Patch 在目标启动前执行 scope、schema、arity、cycle 和 provenance 检查。

## 12. Loop 与状态反馈

Loop 与 Chain、Parallel、Fallback 位于同一 AST algebra 层。Loop 只有一个 child。

Loop 提供：

- local state scope；
- iteration boundary；
- dependency subscription；
- child replay authority；
- settle/exit；
- cleanup boundary。

Loop 外的 Application 按一次 boot demand 执行一次。R 值变化只更新值存储和事件。

useState/useEffect 可以作为未来 Facade sugar。它们必须 lower 到 R、MAP、command
application 和 Loop。

OPEN：

- dependency equality；
- policy 声明位置；
- update batching；
- cleanup failure algebra；
- nested Loop propagation；
- useState/useEffect 最终参数顺序。

## 13. Diagnosis 合同

Diagnosis 输入：

    DemandGraph
    ControlPlan
    RuntimeState

失败通道：

    ExecutionFailureChannel
    ReadFailureChannel
    ImplementationFailureChannel

Trace 只沿真实 DemandGraph edge：

    TowardPrerequisite
    TowardDependent

Impact：

    Root
    Suspect
    Polluted

AstPath 将 impact 投影回 layout。Diagnosis 是只读投影。

## 14. 并发合同

Runtime 使用 GHC lightweight thread、MVar 和受控异步异常。

Parallel：

- branch snapshot isolation；
- 等待全部 worker；
- declaration-order merge；
- exception cancel/drain；
- conservative conflict normalization。

Race：

- first-success selection；
- loser cancellation；
- completion drain；
- settlement audit；
- uncertainty report。

Fallback：

- branch isolation；
- strict delta merge；
- external commit safety。

外部资源释放、事务和幂等由 Handler 或显式 policy Effect 提供。

## 15. 序列化和验证

序列化 IR 不包含：

- Handler closure；
- 宿主函数；
- runtime resource；
- native continuation；
- existential runtime payload。

Lowering 至少拒绝：

1. 未解析 AST、Effect、R、MAP 或 EffSysRef；
2. 重复身份；
3. command application 缺少 MAP/R；
4. MAP output 与 params 不一致；
5. schema 不兼容；
6. input binding 缺失；
7. input 非法环；
8. scope 越界；
9. AST arity 错误；
10. Callback patch 越界、成环或提交过晚；
11. runtime demand 缺少 AST provenance；
12. artifact schema 和 lowering digest 不匹配。

Runtime 不执行带 validation error 的 core。

## 16. 自举和发布

    Host TCB
      -> current core0
      -> FrameworkAsBusiness / core1
      -> materialized core2 candidate
      -> semantic fixed point
      -> artifact fixed point
      -> explicit promotion
      -> next core0

语义 fixed point 检查：

- 公开 Facade 表达；
- normalized observation；
- runtime behavior；
- previous-core back-reference；
- EmptyBusiness closure。

Artifact fixed point 检查：

- Stage1/Stage2 source manifest；
- file digest；
- schema/claim manifest；
- semantic/runtime evidence；
- SDK report。

普通 release gate：

    .\scripts\check-release.ps1

重型 self-artifact gate：

    .\scripts\check-release.ps1 -IncludeSelfArtifact

Validation 生成 pending evidence。维护者显式 approve 后生成 approved promotion record
和 current pointer。

SDK 只接受 approved core，并执行：

- source closure materialization；
- core lock；
- package manifest；
- independent build；
- package witness；
- optional prerelease。

## 17. 当前实现状态

| 语义面 | 状态 |
|---|---|
| MyFramework 单一业务导入 | IMPLEMENTED |
| ReferencedProgram Facade | MIGRATION；位于 MyFramework.Legacy.* |
| 独立 R registry | MIGRATION；新 IR 已移除 |
| C/U/R/D/E/MAP Effect record | IMPLEMENTED |
| typed Handle、GADT、schema witness | IMPLEMENTED |
| 显式 SchemaIdentity Facade | MIGRATION；默认入口不导出 |
| schema-free SurfaceProgram | IMPLEMENTED |
| deterministic schema elaborator | IMPLEMENTED |
| canonical SchemaCatalog 与 provenance | IMPLEMENTED |
| existential Handle/Handler registry | IMPLEMENTED |
| Fix + cata | IMPLEMENTED |
| demand graph 与 Control plan | IMPLEMENTED |
| typed runtime、branch merge、single-flight | IMPLEMENTED |
| runtime diagnosis | IMPLEMENTED |
| TrustBase、fixed point、promotion、SDK | IMPLEMENTED，绑定旧 epoch |
| 正式 MAP Effect | IMPLEMENTED |
| command $ MAP $ R Application | IMPLEMENTED |
| AST / InputGraph / ValueGraph 分离 | IMPLEMENTED |
| input CPS witness | OPEN IMPLEMENTATION |
| Scoped EffSys FCE | OPEN IMPLEMENTATION |
| hanging middleware scope | OPEN IMPLEMENTATION |
| callback PipelinePatch | OPEN IMPLEMENTATION |
| Loop 完整反馈语义 | OPEN |
| ana/hylo | OPEN |
| v5.2 FrameworkAsBusiness 主表达 | IMPLEMENTED；Runtime/Promotion 待后续 Stage |

## 18. v5.2 完成条件

1. Facade 覆盖全部 FROZEN authoring surface；
2. 普通业务 Facade 不导出或要求 SchemaIdentity constructor；
3. SurfaceBinding 与 ElaboratedBinding 分层；
4. schema elaborator 从 typed declaration、codec、literal、record、MAP 和 imported
   catalog 完成约束求解；
5. unresolved、conflict 和 non-serializable boundary 在 Handler 启动前失败；
6. SchemaCatalog 编码和 digest 具有确定性；
7. crawler Facade witness 不包含 scalarType、recordType、unitType 或显式 schema；
8. 六种 Effect 进入 versioned IR；
9. Application 明确保存 command、MAP 和 R；
10. AST、input、value graph 分离；
11. Runtime 通过 CPS lowering 执行 input；
12. Scoped EffSys 支持参数、查询、view 和 snapshot；
13. Middleware 和 Callback 通过正式 witness；
14. Loop 反馈算法完成冻结和实现；
15. Handler closure 保持在 artifact IR 外；
16. 使用入门中的 v5.2 示例可以通过公开 SDK 编译；
17. ordinary release gate 通过；
18. heavy self-artifact gate 通过；
19. 维护者批准 promotion；
20. SDK 从新 core 生成并完成独立验证。

## 19. OPEN 设计清单

1. n 元 AST 节点的最小 child 数量；
2. Choice、Wait、Suspense、Context 完整 schema；
3. Middleware/Callback 最终 Facade；
4. PipelinePatch 完整代数；
5. EffSysRef query 和 snapshot wire format；
6. Loop policy 与 cleanup；
7. useState/useEffect 语法；
8. cyclic continuation graph 扩展；
9. row-polymorphic SDK layer；
10. JSON-RPC ana/hylo boot protocol；
11. row record surface 的库选择；
12. typed record deriving 与外部 codec 的优先级细节。

OPEN 项进入公开合同需要新 L0 版本。

## 20. 版本记录

| 版本 | 日期 | 说明 |
|---|---|---|
| v5.2 | 2026-08-01 | 冻结 schema-free Facade、Surface/Elaborated IR 分层、确定性 schema elaboration 和边界 codec 合同 |
| v5.1 | 2026-08-01 | 分离使用文档、内部开发文档和 L0 合同；L0 收缩为长期语义边界 |
| v5.0 | 2026-08-01 | 合并 Effect–MAP、input CPS、Scoped EffSys FCE、AST、自举和 SDK 设计 |
