# TODO

按 stage 顺序实施，前一个 stage 验收后再开始下一个。每个 stage 列出已定规则、任务、验收标准和待定问题。

## Stage 1：原型链 `Framework.Prototype`

**目标**：把散落在 Codegen、Registration、Plan、Graph、Workflow/Structure、Workflow/AST、Workflow/Execution 中各自推导的链结构，收拢成一份运行前的静态数据。gencode 构建一次，生成区发射一个常量，运行时只读。

**进度**：Stage 1 实现及本轮验收已完成（2026-10-31）。Stage 2、Stage 3 尚未开始。

### 已定规则

- `sdk/Framework/Prototype.hs` 统一数据类型、声明解析、`preparePrototype`／`buildPreparedPrototype`、`buildPrototype`、`validatePrototype` 和标准查询。生成和运行模块读取这些事实；方法展开共用 `expandChain`。
- 原型只含数据，派生 `Eq`、`Show`、`Read`、`Generic`，有 `NFData` 实例；不含函数、类字典或资源。闭包（包装、`Target`）由生成区持有，按方法身份或 `NodeId` 索引原型。
- 生成区只发射一个结构常量 `generatedPrototype :: SDK.Prototype MethodGen`。
- 运行时完整求值并校验一次，之后只读，不重新推导。
- `NodeId` 采用 AST 下标路径，根为 `[]`、子项从零编号；alternative 的选择读取链为该分支路径加 `[-1]`。身份只在当前快照有效，结构变动后重新生成。
- origin/excu 与 ctx 是链定义的分类；AST 挂载使用独立的 `ChainProto`。重复挂载共享定义，Context 链定义不分配虚构的 AST 路径。
- 直接删除 `ProgramStructure` 及旧初始化接口，采用显式 Haskell ADT；不增加 JSON／aeson 或外部 LSP 协议。
- 运行时复用静态原型装配闭包；活动实例与出身接线见下方 runtime graph 补充阶段。静态原型不保存完整方法调用历史，Stage 1 不改变 state、request／require、once-spare 或 Error 语义。

### 数据结构

`method` 在 gencode 中是方法名 `String`，在生成区与运行时是 `MethodGen`。

```haskell
type NodeId = [Int]   -- AST 下标路径；alternative 的选择读取链为该 alternative 的路径加 [-1]

data Prototype method = Prototype
  { protoRegistrations :: [EffectSpec]               -- 注册快照
  , protoEffects       :: [EffectProto method]
  , protoMethods       :: [MethodDefinition method]  -- 已解析取值路由、并入挂接注入
  , protoWorkflow      :: WorkflowTree               -- 带 NodeId 的 AST 快照
  , protoChains        :: [ChainProto method]        -- 每个 node 一条，每个选择读取一条
  , protoChainDefinitions :: [ChainDefinition method] -- origin／ctx 链定义
  , protoGraph         :: EffectGraph method
  , protoScopes        :: ScopeTree method
  , protoScopeNames    :: [(method, String)]
  , protoSources       :: [(ReadPoint, Source)]      -- Stage 2 填充
  }

data EffectProto method = EffectProto
  { effectName :: String, effectKind :: EffectKind, effectInput :: String
  , effectMethods    :: [(MethodRole, method)]
  , effectDemands    :: [ResolvedDemand]
  , effectProduces   :: Maybe String                 -- Context 产出的契约
  , effectBranches   :: [(String, String)]           -- 分支契约 → 构造器
  , effectAnchor     :: Maybe String                 -- Context 挂接的原子句柄 effect
  , effectScopes     :: [String]                     -- 上游 Scoped
  , effectErrorScope :: Maybe String                 -- Error 关联 scope
  , effectInputChain :: [String]
  , effectScopeParents :: [String]
  , effectOpeningInputs :: [String]
  , effectNearestScopes :: [String]
  , effectResource :: Maybe String
  , effectContextDependencies :: [String]
  }

data WorkflowTree
  = NodeAt NodeId String
  | ChainedAt NodeId [WorkflowTree]
  | ParallelAt NodeId [WorkflowTree]
  | AlternativeAt NodeId AlternativeProto [WorkflowTree]

data AlternativeProto = AlternativeProto
  { alternativeContract :: String, alternativeSelector :: NodeId
  , alternativeCases :: [(NodeId, String)] }         -- 候选 → 构造器

data ChainRole = NodeChain | SelectorChain

data ChainProto method = ChainProto
  { chainNode :: NodeId, chainRole :: ChainRole
  , chainTerminal   :: String       -- 末端 effect；选择读取链为转折契约
  , chainEntry      :: method
  , chainReaches    :: [method]     -- 可能到达的方法
  , chainDrives     :: [String]     -- Stage 2 填充
  , chainReads      :: [String]     -- Stage 2 填充
  , chainScopePaths :: [[method]] }

data ChainKind = OriginChain | ContextChain
data ChainDefinition method = ChainDefinition
  { definitionKind :: ChainKind, definitionEffect :: String
  , definitionEntry :: method, definitionReaches :: [method] }

data ReadPoint = ReadPoint { readNode :: NodeId, readContract :: String }
data Source = FromChain NodeId | FromOwnChain
```

### 任务（实现状态）

- [x] 1.1 定义上述类型及 `PrototypeError`。
- [x] 1.2 标准遍历与查询：共享 `expandChain`、`reachableMethods`、`precedes`、`exclusive`（同一 alternative 的不同候选）、`visibleFrom`；后者仅提供结构关系，不启用 Stage 2 资产路由。
- [x] 1.3 `buildPrototype :: [EffectSpec] -> SumTypes -> [(String, MethodShape String)] -> Fix WorkflowF -> Either (PrototypeError String) (Prototype String)`；两阶段生成使用 `preparePrototype` 与 `buildPreparedPrototype`，依次构建：
  - 效应层：解析 demands、挂接、分支契约、上游 scope、Error 关联 scope；
  - 方法层：合并 Handlers 结构并入注入（现 `mergedDefinitions`）；
  - 工作流层：AST 编号，识别 alternative 的转折契约与候选构造器；
  - 链层：区分 origin／ctx 定义，每个 node 与选择读取各一条挂载，计算可达方法与 scope 路径；
  - 派生：`EffectGraph`、`ScopeTree`。
- [x] 1.4 gencode 的检查改为原型上的函数：注册规则、`checkDriven`、alternative 覆盖。
- [x] 1.5 Codegen 中的取值来源、上游 scope、开启输入、Error 关联与 Context 挂接改为读统一的 `EffectProto`。
- [x] 1.6 发射 `generatedPrototype`，合并原先分散的注册、scope、alternative、graph/tree 和初始化结构常量；Handlers 的资源、Error 与注入装配读取同一份已解析事实。
- [x] 1.7 运行时：`evaluate (force generatedPrototype)` 后调用 `validatePrototype`；核对注册快照，在单次装配 fold 中核对 AST 骨架和位置；Execution 按 `NodeId` 查入口与 alternative；`--structure` 渲染同一原型。
- [x] 1.8 `.scope-cache` 保存（输入 key、纯原型、渲染文本）。key 包含完整 `PrototypePlan`、规范化方法结构和算法源码；命中仍校验、检查驱动和源码资产。
- [x] 1.9 删除 `ProgramStructure`、`initializeGeneratedStructure` 和 `GraphPlan`，不保留兼容层。
- [x] 1.10 同步 README、DESIGN_METHOD、LATEST_DESIGN、EFFECT_GRAPH、AGENTS：静态原型保留链定义，执行仍经闭包；Stage 2 状态语义不在本轮实现。

### 验收（2026-10-31）

- 5 个 demo 已重新生成；仅 `Generated/Program.hs` 更新结构常量和 SDK 接线，手写源码、生成契约与 handler 包装未变。
- `cabal build all` 通过；`file-demo`、`open-files-demo`、`scope-reuse-demo`、`scope-instances-demo`、`crawler-demo` 均返回 `Succ`。现有样例中的文件保活、并发复用、获取／关闭计数、重复关闭及重开检查通过。
- 5 个 demo 的 `--structure` 均通过；保留原有方法、引用、scope 层次、父边及路径证据，并新增 NodeId、origin／ctx 链定义和挂载信息。
- FileDemo 连续生成两次均为 `0 files updated`，第二次报告 `structure reused`，确认缓存复用与无变化文件不写回。
- `git diff --check` 通过；未新增测试用例，验收使用既有 demo。

前三项设计决策已确认：AST 下标路径、直接迁移旧结构、显式 Haskell ADT。外部 LSP 的读取方式留给其自身设计，不构成 Stage 1 的 SDK 任务。

## Stage 1 补充：runtime graph

**进度**：实现及本轮验收已完成（2026-10-31），Stage 2 语义仍未启用。

**目标**：以一份共享 Prototype 为静态依据，接通活动 chain、scope 实例、入口使用登记与 Context 绑定出身。模块为 `Framework.Effect.Runtime.Identity` 和 `Framework.Effect.Runtime.Graph`；不累计完整方法执行历史。

### 已确认的边界

- 两种启动：AST 启动选定末端；Context request 启动一次生产链。
- Context 启动覆盖生产、成功发布和返回，继承当前 origin 和入口使用登记；嵌套生产返回不触发入口 cleanup。
- “入口使用登记”明确原有使用闭包的资源边界；完整 AST 入口收尾后撤销使用，once-spare 和 Error 协议保留。
- `Origin` 为 NodeId 加本次执行序号；`ActivationId` 独立识别活动 chain。`Execution` 区分 `BusinessExecution Origin` 与 `CleanupExecution Origin scopeName instanceId`。绑定以 `bindingOrigin` 保存执行出身，资源关闭归属仍在 `bindingOwner`；ScopeUser 保留 Unique 协调身份并携带 Execution。
- 运行图用存在类型引用实际 Prototype 和 ChainDefinition，不复制字符串图；scope 表引用原控制对象，运行级资产及求值锁迁入同一运行图。Context 记录在生产、发布、返回后 finally 移除，根记录覆盖诊断、结果消费及使用撤销收尾；cleanup 使用独立登记，不复活结束的父 activation。
- ScopeTree 保持独立构树、注册前提补全和无环检测，仍负责资源依赖及 Error 祖先导航；活动调用关系不替代 scope 父边。
- 业务 handler、facade 和生成语法不变。记录绑定出身不启用 Stage 2 可见性路由，也不改变来源求值锁。

### 实现与验收

- [x] 运行身份、共享静态原型及活动实例结构。
- [x] AST 与 Context 两种启动边界接线，生产到发布纳入同一记录。
- [x] scope 使用登记及绑定出身接线，嵌套返回保留外层资源使用。
- [x] 普通编译、现有 demo 和生成检查，结果如下。

### 本轮验收（2026-10-31）

- `cabal build all` 通过；`file-demo`、`open-files-demo`、`scope-reuse-demo`、`scope-instances-demo`、`crawler-demo` 全部返回 `Succ`。
- ScopeReuseDemo 实际共享 scope 的开启／关闭次数为 `1/1`；ScopeInstancesDemo 的 file1、file2 各为 `2/2`。OpenFilesDemo 的 10 个文件在链内及 GC 后保持可用，显式关闭检查通过。
- FileDemo 重新生成通过原生源码和资产检查，报告 `0 files updated; structure rebuilt`。本轮 Contract 变化使结构缓存失效并重建，生成文本未变。
- 手写业务源码与 Generated 代码本轮均未修改；未启用 Stage 2 可见性或求值锁新语义，未新增测试，验证使用现有 demo。
- `endActivation` 强制活动表的列表脊以释放已结束 frame；调整后的第二次 `cabal build all` 退出码为 0。
- FileDemo `--structure` 退出码为 0，正确显示 alternative 的 selector `[-1]` 及 origin／context 链定义，未执行业务。`git diff --check` 通过。

## Stage 2：资产可见性（依赖 Stage 1）

**目标**：基于运行图已记录的绑定出身，改变保存与读取路由，由 AST 位置静态决定可见来源，取代运行级 state 的"后写覆盖"。当前出身只是记录：`runtimeAssets` 每个来源仍只存一份、后写覆盖先写；单次求值锁仍按来源名分配（`sourceLock`）。因此并行兄弟读到哪一份仍取决于时序，不同上游值的生产也仍会被同一把锁合并。

### 已定规则

1. **出身**：复用运行图记录的实际生产与 origin 身份，将没有 scope 归属的绑定按 origin 调用（`NodeId` 加执行序号）区分保存。
2. **可见**：链 Y 能看到链 X 的产出，当且仅当 X 在每次执行中都先于 Y 完成（X 位于 Y 某个 `chained` 祖先中排在前面的子项），或者 X 就是 Y。`parallel` 的兄弟互不可见。
3. **驱动者**：对契约 T，下列链是驱动者：`request` T；调用 T 挂接的句柄；`require` T 且没有可见来源（按需求值）。
4. **读取点**：链中没有被本链自己对 T 的生产先行覆盖的 `require @T`。`Sequence` 中前面的子项先于后面的；`Choice` 取各分支的交集；`Recover` 的恢复分支不以正文中的生产为先行。部分路径覆盖、部分没有时报错。
5. **一律细化**：读取点的可见驱动者中，可能在同一次执行里共存的超过一个就报错，不论有无先后。同一 alternative 的不同候选互斥，计为一个来源。修复方式：细化（换 handler 名得到新契约），或调整 AST。
6. **来源解析**：本次调用已捕获的绑定 → 唯一的可见来源 → 本链按需求值。静态来源本次没有发布时，退回按需求值。
7. **例外**：scope 资源实例按开启参数的 `Eq` 共享，资源 Context 的绑定随实例归属。
8. **alternative**：选择读取链先于全部候选，选择阶段捕获的绑定经 `Handoff` 交给候选（已实现）。
9. **单次求值锁**：key 改为（出身，契约名）。

### 任务

- [ ] 2.1 在原型模块实现 `driveSet`、`readPoints`、`resolveSources`，按 AST 执行顺序一次遍历；结果填入 `chainDrives`、`chainReads`、`protoSources`。
- [ ] 2.2 gencode 检查：唯一来源，报错示例 `Asset StartPageSummary read by PrintPage has several sources FetchA, FetchB; refine one handler or reorder the AST`；部分路径先行。
- [ ] 2.3 运行时：绑定按出身保存，读取按 `protoSources` 查询，删除"后写覆盖"的回退。
- [ ] 2.4 `sourceLock` 改用（出身，契约名）。
- [ ] 2.5 `--structure` 展示每个读取点的来源。
- [ ] 2.6 实现后把规则写进 LATEST_DESIGN 与 README。
- [ ] 2.7 验证：在 LSP 仓库写一个运行时语义的可执行模型，枚举 5 个节点以内的 AST 及全部执行交错，检查"读取来源唯一且与静态表一致"。本仓库在探索阶段不新增测试。

### 验收

5 个 demo 不需要修改即可通过检查，运行结果不变：

- Crawler：PrintPage 读 StartPageSummary 的唯一来源是 FetchPage；
- ScopeReuseDemo：各链对 FilePaths 的读取被本链的 `request` 先行覆盖，不是读取点；共享的 OpenedFile 属于规则 7；
- FileDemo：候选读 FileName 和分支契约，来源都是选择读取链；
- ScopeInstancesDemo、OpenFilesDemo：全部 `chained`，按顺序可见。

### 已知不覆盖

| 模式 | 原因 | 需要 |
| --- | --- | --- |
| 谁先完成用谁 | 意图不满足因果性，报歧义是正确的 | race 构造 |
| 运行时才知道数量的扇出 | 当前 DSL 无法表达 | 集合资产或带索引的出身 |
| 外部事件触发的生产 | Hanging 未接入 | 事件入口 |
| 跨轮次状态 | 一律细化下无法为每轮命名契约 | Stage 3 |

## Stage 3：stream（依赖 Stage 2）

**目标**：持续获取新输入。每次成功发布都是一个增量，值相等也算两次。

### 已定方向

- 作为 Context 的第三种取值模式：`demands` 中写 `streams "T"`，方法体中 `stream @T` 一次取一个增量；重复由 AST 中的 lifelong 负责。这是声明语法变更，开始前须单独确认。
- 每个契约一条只追加的发布日志，增量带出身；`require` 读日志的最后一项，语义不变。
- 消费者的游标只订阅对它可见的出身；多个出身汇入同一游标，按 Stage 2 规则 5 报错。
- 跨轮次的值传递由 stream 承担。

### 待定（开始前逐项确认）

- [ ] 游标后没有新增量时：等待，还是像 thunk 一样强制生产一次（建议后者，并按（出身，契约名）加锁）
- [ ] 游标起点：只看订阅之后的发布，还是先给当前最新值
- [ ] 游标归属：按消费者注册共享（工作队列），还是按 lifelong 实例各自一个（广播）
- [ ] 日志保留：所有游标越过后删除；生产方 scope 关闭时，未消费的增量按值保留
- [ ] 背压：日志无界，还是有界并阻塞生产方
- [ ] 节奏：生产入口声明"阻塞到有新输入"还是"采样加周期或触发源"
- [ ] lifelong 的使用闭包：整体一个还是每轮一个；每轮是新调用，失败不跨轮重试
- [ ] 会取走数据的来源被多条链同时调用时的诊断

### 任务（待定项确认后细化）

- [ ] 3.1 lifelong 的 AST 构造
- [ ] 3.2 `streams` 声明与 `stream @T` 的生成
- [ ] 3.3 发布日志与游标的运行时
- [ ] 3.4 检查与 `--structure`

## 跨仓库：LSP 与可视化配置

- [ ] 外部 LSP 按自身需要接入 SDK 原型和检查结果；读取协议与展示格式在该工具中另行设计，本仓库 Stage 1 不引入专用导出。
- [ ] 悬停显示读取点的来源，画布上从来源链连线到读取点，歧义时提示细化。
