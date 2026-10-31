# TODO

按 stage 顺序实施，前一个 stage 验收后再开始下一个。每个 stage 列出已定规则、任务、验收标准和待定问题。

## Stage 1：原型链 `Framework.Prototype`

**目标**：把散落在 Codegen、Registration、Plan、Graph、Workflow/Structure、Workflow/AST、Workflow/Execution 中各自推导的链结构，收拢成一份运行前的静态数据。gencode 构建一次，生成区发射一个常量，运行时只读。

**进度**：Stage 1 实现及本轮验收已完成（2026-10-31）。Stage 2 进度见后文，Stage 3 尚未开始。

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
  , protoSources       :: [(ReadPoint, Source)]      -- 缺值读取路径的许可来源
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
  , chainDrives     :: [String]     -- 可能生产的基础契约
  , chainReads      :: [String]     -- 存在缺值读取路径的基础契约
  , chainScopePaths :: [[method]] }

data ChainKind = OriginChain | ContextChain
data ChainDefinition method = ChainDefinition
  { definitionKind :: ChainKind, definitionEffect :: String
  , definitionEntry :: method, definitionReaches :: [method] }

data ReadPoint = ReadPoint { readNode :: NodeId, readContract :: String }
data Source = FromOwnChain | FromChains [NodeId]
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

**进度**：实现及该次验收已完成（2026-10-31）；该次验收尚未启用 Stage 2，后续来源路由进度见下。

**目标**：以一份共享 Prototype 为静态依据，接通活动 chain、scope 实例、入口使用登记与 Context 绑定出身。模块为 `Framework.Effect.Runtime.Identity` 和 `Framework.Effect.Runtime.Graph`；不累计完整方法执行历史。

### 已确认的边界

- 两种启动：AST 启动选定末端；Context request 启动一次生产链。
- Context 启动覆盖生产、成功发布和返回，继承当前 origin 和入口使用登记；嵌套生产返回不触发入口 cleanup。
- “入口使用登记”明确原有使用闭包的资源边界；完整 AST 入口收尾后撤销使用，once-spare 和 Error 协议保留。
- `Origin` 为 NodeId 加本次执行序号；`ActivationId` 独立识别活动 chain。`Execution` 区分 `BusinessExecution Origin` 与 `CleanupExecution Origin scopeName instanceId`。绑定以 `bindingOrigin` 保存执行出身，资源关闭归属由共享的 `bindingOwnership` 单元保存；ScopeUser 保留 Unique 协调身份并携带 Execution。
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

**目标**：基于运行图已记录的绑定出身，改变保存与读取路由，由 AST 位置静态决定可见来源，取代运行级 state 的全局"后写覆盖"。同一契约在不同 origin 下独立保存，按需求值锁也按 origin 与 Context 来源区分。

**进度**：2.1–2.6 已实现，普通编译、五个现有 demo 及结构展示通过本轮验收；2.7 的外部穷举模型尚未实施。

### 已定规则

1. **出身**：复用运行图记录的实际生产与 origin 身份，将没有 scope 归属的绑定按 origin 调用（`NodeId` 加执行序号）区分保存。
2. **可见**：链 Y 能看到链 X 的产出，当且仅当 X 在每次执行中都先于 Y 完成（X 位于 Y 某个 `chained` 祖先中排在前面的子项），或者 X 就是 Y。`parallel` 的兄弟互不可见。
3. **驱动者**：对契约 T，下列链可能生产：显式 `request` T；调用 T 挂接的句柄；`require` T 的缺值路径触发生产。缺值生产的成立条件也纳入分析，不能把它当作每次必然发生的生产。
4. **读取点**：只有当前调用尚未捕获 T 的路径需要解析跨链来源。允许某些路径已捕获、另一些路径缺值；前者直接用已有绑定，后者须各自满足来源唯一。`Sequence` 按顺序传递捕获；`Choice` 和 `Recover` 保留可能路径，不假定故障前已经完成全部生产。
5. **缺值路径唯一**：在需要跨链解析的缺值路径上，同时可见的实际来源至多一个；否则报歧义，不按先后或距离挑选。候选可包含多个节点，证明覆盖 alternative 及缺值才生产的条件关系。已捕获路径可以有多个节点共同发布，读取仍由已有快照决定，不要求这些节点在所有执行路径上互斥。
6. **来源解析与 fallback**：本次调用已捕获的绑定 → 静态许可且本次实际已发布的唯一可见来源 → 本链按需求值。fallback 是一次普通 request：以当前 origin 成功发布并返回，之后可被 AST 可见的后继复用；不设"只有最初指定节点的产物才能传播"的限制。来源分析必须将这条条件生产路径纳入后继的唯一性检查。
7. **scope 例外只覆盖 owner 绑定**：资源实例仍按开启参数的 `Eq` 共享，已有 owner 的资源绑定随实际实例定位。scope 快照里没有 owner 的辅助值仍走按 origin 保存的权威表，不借资源复用绕过可见性。
8. **alternative**：选择读取链先于全部候选，选择阶段捕获的绑定经 `Handoff` 交给候选（已实现）。
9. **单次求值锁**：按（当前 origin，Context 来源）分配；并发的不同 origin 不因契约相同而合并生产，显式 request 仍每次执行。
10. **隔离**：诊断与自动 cleanup 中产生的值只进入其局部快照，不能覆盖业务 origin 的权威绑定或成为后继的业务来源。
11. **执行方式**：现有 App 的 bind 在取得值后继续方法体；新增来源分析和存储路由，不增加 call/cc、订阅调度器或 handler 语法。

### 任务

- [x] 2.1 在原型模块实现 `driveSet`、`readPoints`、`resolveSources`，沿 AST 控制结构传播有限抽象状态；结果填入 `chainDrives`、`chainReads`、`protoSources`。
- [x] 2.2 gencode 检查需要跨链解析的缺值路径上同时可见来源至多一个；条件 fallback 纳入证明，部分路径已捕获允许。
- [x] 2.3 运行时：绑定按出身保存，读取按 `protoSources` 查询，删除全局"后写覆盖"的回退。
- [x] 2.4 `sourceLock` 按 origin 与 Context 来源分配；诊断／cleanup 发布保持局部隔离，scope 例外只作用于 owner 绑定。
- [x] 2.5 `--structure` 展示每个读取点的来源。
- [x] 2.6 将规则同步到 LATEST_DESIGN、README、DESIGN_METHOD、EFFECT_GRAPH 与 AGENTS。
- [ ] 2.7 后续验证：在 LSP 仓库写运行时语义的可执行模型，枚举 5 个节点以内的 AST 及全部执行交错，检查"读取来源唯一且与静态表一致"。该外部模型本轮未实施，本仓库也未完成这种穷举验证；当前只使用普通编译和既有 demo，不新增测试。

### 本轮验收（2026-10-31）

- `cabal build all` 退出码为 0；`file-demo`、`open-files-demo`、`scope-reuse-demo`、`scope-instances-demo`、`crawler-demo` 均退出 0 并返回 `Succ`。
- OpenFilesDemo 的 10/10 个文件在链内及 GC 后可用，写入通过，显式 close 后 10/10 关闭。
- ScopeReuseDemo 本次实际开启／关闭次数为 `1/1`，三行内容各写入一次；各链已由自身 request 捕获 FilePaths，共享的 OpenedFile 继续按 owner 协议处理。
- ScopeInstancesDemo 的 file1、file2 开启／关闭次数各为 `2/2`。
- 五个 demo 的 `--structure` 均退出 0；Crawler 两个打印入口的来源表分别指向 `[0,0]` 和 `[0,1]`。FileDemo 候选优先读取 selector 经 `Handoff` 交付的快照，来源表仅描述缺值路径，允许为 `FromOwnChain`。
- 最终算法下重新生成五个 demo，均报告 `0 files updated; structure rebuilt`；随后 FileDemo 重复生成退出 0，报告 `0 files updated; structure reused`，缓存复用通过。
- 手写 Handlers 与 facade 无差异，生成区仅五个 `Generated/Program.hs` 更新原型内容；`git diff --check` 通过。
- 本轮使用普通编译和已有 demo，未新增测试。上述结果不包含 2.7 的外部穷举模型验证；后续 Scope 归属修复单独记录如下。

### 已知不覆盖

| 模式 | 原因 | 需要 |
| --- | --- | --- |
| 谁先完成用谁 | 意图不满足因果性，报歧义是正确的 | race 构造 |
| 运行时才知道数量的扇出 | 当前 DSL 无法表达 | 集合资产或带索引的出身 |
| 外部事件触发的生产 | Hanging 未接入 | 事件入口 |
| 跨轮次状态 | 一律细化下无法为每轮命名契约 | Stage 3 |

### Scope 共享归属修复（已实现）

目标是修复资源 Context 在 open 外先被 request、被多个入口捕获后，首次认领仅改变本地副本的问题。

- [x] 每次 request 分配独立 Binding 及共享 ownership IORef；值和 Execution 出身不变，捕获、权威表、scope 快照及 Handoff 共用归属单元。首次认领无 owner → 唯一实例，同实例幂等、不同实例拒绝。
- [x] 无 owner 资源在发布／require 返回前登记 ScopeUser；claim 在现有 scopeCoordinator 内将仍活跃的持有者接入实例，detach 在同锁内撤销待认领登记与实例使用。普通资产不登记待认领使用者，正常 open 内已有 owner 的生产路径保持原协议。
- [x] claim 先于等待实例生命周期锁，claim 到保存资源绑定保持 masked；不删除 publication、不修改 origin、不重新发布，保留 Stage 2 的单调发布事实。runtimeAssets 只接收发布时无 owner 的绑定，后续 claim 保留该 publication 引用；open 内一开始就有 owner 的产物仍只留在 scope／局部快照。
- [x] 资源重复快照按共享归属单元去重，独立 request 不合并；同步设计说明并完成既有编译／demo 验收。

本项不增加用户 key、handler 语法或 ScopeTree 算法，不追踪独立 request 是否私下包装了同一个底层 Handle。Stage 2 的外部穷举模型仍未完成，stream 尚未实现。

常规回归验收（2026-10-31）：

- `cabal build all` 退出 0；`file-demo`、`open-files-demo`、`scope-reuse-demo`、`scope-instances-demo`、`crawler-demo` 均退出 0 并返回 `Succ`。
- OpenFilesDemo 的 10/10 个文件在链内及 GC 后可用，write／flush 通过，显式 close 后 10/10 关闭。
- ScopeReuseDemo 实际开启／关闭次数为 `1/1`，三行各写入一次；ScopeInstancesDemo 的 file1、file2 开启／关闭次数各为 `2/2`。
- FileDemo gencode 退出 0，报告 `0 files updated; structure reused`；`git diff --check` 通过。手写 Handlers、facade 和全部 Generated 文件无差异，本轮仅修改四个 runtime 源码文件与六份文档。
- 验收使用既有 demo，未新增测试；这些结果不代表新增的并发认领／持有者交接路径已有专项执行覆盖，也不包含并发交错穷举。

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
