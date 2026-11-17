# 组合推导：结构怎样成为执行语义

更新：2026-11-17。组合逻辑是这个框架的核心设计原则：业务写下资产、effect、原子 handler 和 workflow 的关系，SDK 对这些结构进行运算，得到可以检查、生成和执行的含义。同一声明元素随组合关系取得不同解释，这种组合产生的特设多态在生成期确定。本文先说明这项原则及其确定性要求，再列出各组合的推导依据；详细协议仍由[主设计](LATEST_DESIGN.md)、[图与来源](EFFECT_GRAPH.md)和[Stream 规范](STREAM_LIFELONG.md)分别维护。

<a id="why"></a>
## 1. 组合逻辑为什么是框架核心

handler 描述一次原子操作；业务含义由它绑定的 effect、Input、demands 和 workflow 共同决定。同一个 handler 可以用于不同业务链，仍只实现自己的取值、解析或 IO。SDK 必须能够从这些声明计算出它应获得哪些能力、资产从哪里进入、谁驱动谁，以及哪些结构组合不成立。这项计算决定框架的表达方式，代码生成和运行调度都服务于它。

<a id="ad-hoc"></a>
### 组合产生的特设多态

“特设多态”（ad-hoc polymorphism）是程序语言中已有的术语：同一个名字有多种含义，由使用处的上下文决定取哪一种。Haskell 的类型类是常见的形式：同一个类方法按类型选择 instance，选择在编译期完成；找不到可用的 instance，或可用的 instance 不止一个，都是编译错误。与之相对的是参数多态：一份定义对所有类型统一成立，不感知具体是哪种类型。

本框架借用这个术语描述组合语义。被选择的是声明元素的解释，决定选择的上下文是元素所处的组合关系，做选择的是 gen：

| 类型类中的特设多态 | 本框架的组合多态 |
| --- | --- |
| 类方法名 | 声明元素：Context、`requests`／`requires`／`streams`、Scoped 的开启参数、AST 中的位置 |
| 决定选择的类型 | 元素所处的组合关系：Input 是什么、由谁驱动、挂在 AST 的哪里、以哪种访问方式进入 |
| instance | SDK 规定的一种解释，例如一次解析、持续来源、独立派生、复用已有输出、单例或多例 |
| 编译器解析 instance | gen 的组合计算，在生成期选定解释，写入 Prototype 与生成代码 |
| 没有或多于一个 instance 时报错 | 没有解释或有多种解释的组合由 gen 拒绝 |

例如同一个 Context 声明：Input 是原子句柄时，解释为对本次输出的一次解析；Input 是 Stream 时，解释为持续来源的逐条解析；Input 链被 `streams` 驱动时，再按 AST 中是否已有同次输出的发布位置，解释为独立派生或复用已有输出。又如 scope 的开启参数：以 `requests` 进入时，每次开启对应一次新的生产，实例是多例；以 `requires` 进入时，引用已有的一次生产，实例是单例。业务不为这些情况分别书写装配，也不标注自己处在哪种情况。

上表只用于说明结构上的对应，两者并不相同：类型类按 Haskell 类型选择，用户可以增加 instance；这里按结构关系选择，解释的集合由 SDK 规定，业务只能组合已有的声明，不能注册新的解释。

原子 handler 一侧则像参数多态那样保持统一：它不感知自己被放进哪种组合，签名只由绑定类别与读取决定，不随控制流改变。例如只有自己以 `streams` 订阅持续资产的 Excu 获得 `endStream`，同一条链上作为 Input 前驱的原子操作不获得它；同一个 handler 因而能在持续链与有限链之间复用。两者的分工是：**声明元素随组合关系取得解释，原子实现对组合保持不变。**

生产与消费也是关系角色。一个 Context 链可以消费上游资产，同时向另一条链生产资产；它不必额外标注自己是生产者还是消费者。持续链 A 随 B 的增量发布，普通链 C 可以只读取 A 的一次固定结果。**持续生产能力不沿取值依赖自动传播；是否重复启动由组合中的驱动关系决定。** A 若保存记录，C 读到的就是业务记录；A 若做统计，C 读到的就是统计。SDK 不识别这些业务名称，也不给资产增加特殊的历史包装。

<a id="determinism"></a>
### 确定性：解释在生成期唯一确定

组合多态之所以可用，是因为解释是确定的。本框架对确定性的要求有三条：

1. **只看结构。** 解释只取决于注册、AST 与 handler 读取形状中可以静态读出的关系，不取决于调度时序、业务 IO 的结果或运行中的值。
2. **唯一。** gen 接受的每一种组合恰好得到一种解释；可能得到多种解释时拒绝。例如一个读取点有多个可见来源，或不同单元在同一轮可能发布同一份资产，都在生成期报错。
3. **不兜底。** 得不到解释的组合在生成期拒绝，不留到运行时再猜测或报错。例如挂在 `streams` 消费节点下的 Context 必须声明 `stream = True`；lifelong 中的节点必须正好订阅一份持续资产，除驱动它的资产外不能再读取其他持续资产。

确定的是“这段组合是什么意思”，不是业务结果。运行时仍决定实际的值、IO 是否成功、交付何时到达，这些都按已经确定的协议处理，不改变组合的解释。确定性也不证明任意业务程序满足代数定律。

**当前边界。** 组合计算已有统一入口（[第 2 节](#pipeline)），但各声明元素的解释仍分布在其中的声明、会话、绑定、构图与来源分析各步，尚未整理成逐个元素的显式解释点。已知一处不满足“不兜底”：同一 lifelong 单元里，`require` 普通资产的节点排在唯一发布它的节点之前时，gen 接受这个组合，运行时首轮才以 `ContextNotInitialized` 失败，见[当前限制](NEXT_STAGES.md#current-limits)。

这项设计把三件事连在一起：

- **代码能够表达关系。** 注册和 workflow 是有限、明确的结构，读者、HLS、生成器和 agent 面对同一份原生 Haskell。关系应能沿源码追溯，见[代码即文档](LATEST_DESIGN.md#code-as-documentation)。
- **编译器能够计算关系。** gen 把结构作为数据进行分析，形成类型约束、精细化 DI、来源证明和图；不要求原子方法理解整个调度器。
- **运行时能够执行关系。** interpreter 消费已经确定的结构，管理实际值、执行进度、会话与资源；业务 IO 的结果不由编译器猜测。

因此，设计新能力时先确定“哪些结构关系对应什么执行含义”，并写明没有解释或有多种解释时 gen 怎样拒绝，再决定如何生成代码和维护运行状态。没有结构证据的行为应诊断或保留待定，不能以自动装配为名依赖偶然时序。框架对组合的解释有明确适用条件，也不因为引入状态机就自动证明任意业务程序满足代数定律。

### 代码长什么样

下面是 [FileDemo/Effects.hs](../demo/FileDemo/Effects.hs) 的注册节选；省略同文件的其他 effect：

```haskell
EffectSpec
  { name = "FileResource"
  , typing = Context
      { asset = Asset @FileHandle "OpenedFile"
      , parser = Just "acquireFile"
      , require = True
      , stream = False
      }
  , input = "Root"
  , demands = [requests "FileName", requires "FileName"]
  }
```

对应 [FileDemo/Handlers.hs](../demo/FileDemo/Handlers.hs) 的完整 instance 节选（省略模块头与 import）：

```haskell
instance AcquireFileLayer m => AcquireFileHandler m where
  acquireFile = do
    path <- require @FilePath
    outcome <- liftIO $ tryIOError $
      bracketOnError (openFile path ReadWriteMode) hClose $ \file -> do
        hSetEncoding file utf8
        putStrLn ("[open] " ++ path)
        pure (FileHandle path file)
    either (raise . AcquireFileError . displayException) pure outcome
```

这段注册同时表达“驱动 FileName 的生产”和“读取该资产”。gen 据此确定有序生产步骤、唯一读取路由与 `Reads FilePath` 能力；`acquireFile` 不调用生产者。换一个合法绑定可以复用这份原子实现，资产来源仍由那个 effect 的声明确定。完整资产、instance、workflow 和入口沿[指南的代码形态](GUIDE.md#code-shape)阅读。

SDK 没有逐一提供 `map`、`filter`、`take`、`share`、`acquireRelease` 这样的业务组合方法。组合的能力不能只靠方法名清单呈现，因此后文按“声明组合 → 推导事实 → 运行行为”登记；这些类比不代表与其他框架同名操作的语义完全相同。

<a id="pipeline"></a>
## 2. 一台组合状态机，产生同一份含义

[Gen.Composition](../sdk/Framework/Gen/Composition.hs) 是编译期组合计算的统一实现。输入是已加载的 effect／资产／workflow，以及前端提取的 handler 读取形状；状态转换逐步补全关系、检查约束，最终给出接口装配与 Prototype。声明解析、会话推导、绑定、构图和来源证明都在这个模块内计算。

```text
声明结构 + handler 读取形状
        ↓
组合状态机：解析 → 编号与绑定 → 方法组成 → 图与来源证明
        ↓
确定的类型能力、读取路由、入口/输出连接、会话计划、Prototype
        ↓
Emit 按结果生成 Haskell；runtime 执行生成结果
```

状态机统一的是**语义计算的权威**。局部遍历、路径组合和环检查是它的内部运算，不保留各自对外决定装配行为的分析入口。Emit 可以按产物分文件，但只投影已确定的状态：例如持续来源的 Receive／Derive／ReuseOutput 在组合计算中确定，输出阶段直接使用；类型能力也先形成结构结果，再渲染为 Layer 约束。

这不要求整个 SDK 的算法全部搬进一份文件。`Prototype.Query` 保留供机器和原型校验共用的纯结构关系查询，包括 `bootPlan`、`finiteSessions` 等；它们服务于同一模型，不是另一套拥有编译阶段和装配状态的计算机。GHC 语法提取、源码资产类检、文本渲染和运行期资源管理也各守原有边界。

| 计算中的事实 | 产物的用途 |
| --- | --- |
| 唯一资产来源、访问方式、表示类型和读取视图 | 生成契约、读取路由与 handler 的类型能力 |
| AST 位置、alternative 候选、lifelong 单元与持续连接 | 生成末端、选择入口、会话启动和订阅计划 |
| 有序驱动／前驱、raw 来源、原子输出连接 | 生成入口和注入；同一组事实参与方法组成与来源证明 |
| 方法图、ScopeTree、读取来源和 scope 开启计划 | 静态校验与展示；运行时取值、等待、共享和回收的依据 |

实际转换由 `advanceComposition` 统一定义，入口分成两个等待检查点：

```text
beginComposition
  Declared → Related → Numbered → AwaitingBodies Unit

prepareComposition（补入 Maybe handler 形状）
  ResolvingBodies → AwaitingGraph PendingComposition

completeComposition（补入可选的缓存原型）
  BuildingStructure → ProvingSources → Checking → Complete
                                    缓存命中 ──┘
```

`Source.loadComposition` 在 ghci 中调用 `beginComposition`，把具有 Eq／Show／Read 的纯 `Unit` 交回生成器。Unit 保存 `ReadRoute`、`ReaderPlan`、`SelectorPlan`、`SessionEntry` 和 `Capability` 等确定事实；它不包含 GHC AST、类字典或执行函数。最终 `CompositionResult` 同时携带 Unit 与 Prototype。

首次尚无 Handlers 时，`prepareComposition` 接收 `Nothing`；已有文件时接收 `Just shapes`，即使提取结果为空列表，也不按缺少文件处理。机器先完成契约所需的结构计算，供业务写出能通过 HLS 的 instance，再按是否已有方法体决定读取与驱动检查。`completeComposition` 即使命中缓存，也会进入 `Checking` 校验原型；已有 handler 时还执行驱动检查。前端只加载声明和解析形状，不执行业务。

统一计算也不要求只扫描一次输入。不同阶段需要的方法摘要、来源路径和临时集合属于一次编译的工作状态；内部图 memo 和来源分析的 StateT 是局部计算证据，不是运行时状态机；来源分析保留路径相关性，并在组合前裁剪无关事实。某些路径族仍可能指数增长，状态机不能消除问题本身的复杂度，详见[构图与复用边界](EFFECT_GRAPH.md#reuse-boundary)。

运行时继续只读 Prototype，另行维护 RuntimeGraph、执行帧、资产、会话和 scope 实例。静态计算决定的合法路线与实际发生的生产、取消、资源关闭是两个层面。持续资产的生产计划与读取方的驱动关系分别由同一计算确定；读取固定值不会替普通链增加订阅。推导结果通过[结构查看](GUIDE.md#commands)与 Generated 中的接口、路由共同呈现。

<a id="maintenance"></a>
## 3. 条目格式与维护

下面每一节是一张对照表，一行对应一种行为：

| 列 | 内容 |
| --- | --- |
| 行为 | 想得到的运行效果，用本框架的词描述 |
| 组合 | 业务要写的声明与 AST；“无需写法”表示由其他组合自动得到 |
| 推导 | gen 写入 Prototype 或生成代码的事实 |
| 驱动 | 运行时据此做什么 |
| 规范 | 完整规则所在的章节 |
| 或可类比为 | 可选；帮助理解的粗略类比，不表示语义或实现相同 |

维护规则：

- 新增一种由组合推导的行为时，先在所属专题写完整规则，再在这里加一行，并链接过去。
- 每一行都应说明在哪些结构关系下取得这种解释；相近的组合可能得到两种解释或得不到解释时，所属专题写明 gen 的拒绝诊断，满足[确定性](#determinism)。
- 本文维护组合原则、统一计算边界和行为对应关系；详细协议归所属专题，阶段状态与验证结果归 [Next stages](NEXT_STAGES.md)。
- 未实现的行为只出现在各节的“尚未覆盖”中，不写成当前能力。

<a id="context"></a>
## 4. 生产与消费

普通资产（`stream = False`）的生产与消费。这里没有“调用生产者”的写法：消费方只声明要驱动或读取哪份资产，由组合推出谁来生产、何时生产、读到哪一次。

<a id="context-produce"></a>
### 4.1 生产

| 行为 | 组合 | 推导 | 驱动 | 规范 |
| --- | --- | --- | --- | --- |
| 资产有唯一的生产方 | Context 以 `asset = Asset @T "名字"` 声明；消费方只写资产名 | 按资产名解析出唯一生产方，多个生产方即报错 | 不按距离或拓扑替用户选来源 | [Context](LATEST_DESIGN.md#context)、[资产来源与访问约束](LATEST_DESIGN.md#demand-contract) |
| 驱动一次新的生产 | 消费方 `requests "T"` | 入口的驱动步骤，排在前驱与方法体之前 | 每次进入入口都重新执行 T 的生产链并发布；不合并重复驱动 | [入口装配](LATEST_DESIGN.md#calls) |
| 原子操作的输出解析成资产 | Context 的 Input 是 Excu 或 Scoped，parser 用 `raw` | 挂接连接（`contextInjections`）、raw 来源 | 句柄成功后，parser 读本次输出发布资产，句柄不重跑；普通 Context 的解析失败留在注入内部，资产不发布 | [原子输出挂接](LATEST_DESIGN.md#context) |
| 同一个 parser，被驱动时自己取得输入 | 同上的 Context 被 `requests` 或选择读取驱动 | 同一份入口，raw 的回答方式不同 | raw 执行句柄入口，从头启动生产链；失败沿驱动方传播 | 同上 |
| 输出的纯变换 | Input 链上串 Pure | Pure 链，挂接点是最上面的原子句柄 | 句柄输出经 Pure 依次变换后交给 parser；Pure 不改变调用者身份，不会重复注入 | [Pure](LATEST_DESIGN.md#pure) |
| 操作按顺序组合 | `input = "前驱"` | 入口的前驱步骤 | 在方法体之前执行前驱；不传值，前驱失败原样传播 | [句柄与值](LATEST_DESIGN.md#handles-and-values) |
| 每个生产方法都有人驱动 | 无需写法 | 从各 AST 末端和选择读取求可达集合 | 生产方法无法从任何入口到达时，生成期报错 | [图与来源](EFFECT_GRAPH.md) |
| 相同上游出现在多条链上 | 两个 effect 以同一个 effect 为 Input | 各挂载保留自己的 NodeId | 各自执行，不按方法名去重；不把重复的 IO 当作幂等 | [结构共享与执行复用](EFFECT_GRAPH.md#reuse-boundary) |

<a id="context-consume"></a>
### 4.2 消费

| 行为 | 组合 | 推导 | 驱动 | 规范 |
| --- | --- | --- | --- | --- |
| 读取已有的值，不生产 | `requires "T"`，方法体 `require @T` | 读取权限与读取路由；读取点的来源（`protoSources`） | 先用本次捕获，再读许可来源的发布；没有值时等待，不补跑生产 | [Context](LATEST_DESIGN.md#context) |
| 按类型读取，读到哪份由注册决定 | 同一表示类型细化成多份资产；handler 只写 `require @T` | 每个 effect 按“表示类型 + effect”生成读取实例 | 同一个 handler 绑到不同 effect，各自读到 demands 里那份资产 | [Context](LATEST_DESIGN.md#context) |
| 按构造器读取和类型的分支 | `requires` 分支契约（如 `FileTextWritten`） | 分支契约目录，投影当前构造器 | 读到构造器的字段；构造器不匹配报 `CaseNotSelected` | [Context](LATEST_DESIGN.md#context) |
| 读到哪一次发布 | 无需写法，由 AST 的先后决定 | 每个读取点保存许可的来源：本链、AST 保证先完成的前驱，或会话 | parallel 兄弟互不可见；需要跨链读取时同时可见的来源至多一个，否则生成期报错 | [图与来源](EFFECT_GRAPH.md) |
| 等不到值时结束等待 | 无需写法 | 来源候选与执行帧的节点进度 | 候选都已退休仍无值时报 `ContextNotInitialized`；资源 Context 与诊断、收尾、close 期间不等待 | [可见范围与等待](LATEST_DESIGN.md#await-visibility) |
| 声明的读取都有用处 | 无需写法 | 读取依据：方法体的读取或控制流的读取 | 声明了却没有任何依据的读取，生成期报错 | [资产来源与访问约束](LATEST_DESIGN.md#demand-contract) |
| 按资产的状态选分支 | `alternative` 的候选各 `requires` 同一资产的一个分支契约；AST 不写条件 | `AlternativeProto`：转折契约、构造器到候选的对应 | 选择读取相当于 `requests`：先生产转折资产，只启动匹配的候选，并把选择时的捕获交给它 | [workflow](LATEST_DESIGN.md#workflow) |

<a id="scope"></a>
## 5. 资源（scope）

scope 同样没有 key、寿命或 cleanup 策略的写法。何时开启、与谁共享、何时关闭、按什么顺序关闭、故障归到哪里，都从 Input、demands 与 AST 推出。

| 行为 | 组合 | 推导 | 驱动 | 规范 |
| --- | --- | --- | --- | --- |
| 在需要的链上开启 | Scoped 放在链的 Input 上 | 入口的前驱步骤 | 进入入口时先开启；已开启的实例复用，跳过 open 的方法体 | [入口装配](LATEST_DESIGN.md#calls) |
| 注册级单例 | Scoped 的资源 Context 没有开启参数 | scope 开启计划，类别为注册级单例 | 同一注册共享实例，归根帧 | [单例与多例](LATEST_DESIGN.md#scope-identity) |
| 按一次生产共享 | 开启参数只经 `requires` 引用已有的生产 | 各参数可能的生产节点（`protoScopeOpenings`） | 读到同一次生产的开启共享同一实例，保留原归属帧 | 同上 |
| 持续最新值作开启参数 | 资源 parser 声明 `requires` 并读 `require @T` | `FromSession` 开启计划 | 固定交付末条沿用原生产身份与帧，按交付／游标与后继读取位置判断待用 | [开启计划](EFFECT_GRAPH.md#scope-opening-retention) |
| 每次新开（多例） | 当前执行用 `requests` 新生产了开启参数 | 同上 | 新的参数生产确定新实例；本次生产的后继仍共享它 | 同上 |
| 实例属于哪一层 | 无需写法 | 参数生产所在的执行帧 | 取参数中最内层的帧，无参数取根帧；lifelong 本轮生产参数的实例归本轮 | 同上、[按可达性回收](LATEST_DESIGN.md#scope-gc) |
| 一份资源只有一个关闭者 | Scoped `requests` 资源 Context | open 认领资源绑定 | 首次 open 认领为 owner，所有副本看到同一归属；其他实例认领报 `ScopeContextMismatch` | [scope](LATEST_DESIGN.md#scope) |
| 只在已开启的链里读资源 | handler `require` 资源 | 资源读取点与所属 scope 的开启位置 | 资源在本链的 scope 开启前被读取，生成期拒绝；运行时不扫描其他活实例来补 | [Scope 开启计划](EFFECT_GRAPH.md#scope-opening-retention) |
| 不再使用时关闭 | 无需写法；close 写在 Scoped 上，可为 `Nothing` | 执行帧的待用关系、开启计划 | 没有当前使用者、没有匹配的待用节点、没有保留它的子 scope 时同步关闭；`Nothing` 时只移出运行表 | [按可达性回收](LATEST_DESIGN.md#scope-gc) |
| 关闭顺序 | 无需写法 | ScopeTree：静态路径上的共同必经前序，加上 Input／requests 链与资源来源给出的注册前提 | 子先父后；实例只保留同一受控链实际使用的父实例 | [图与来源](EFFECT_GRAPH.md) |
| 资源随持续生产存续 | 来源的 Input 上游放 Scoped | 会话挂载、开启计划 | 会话的使用登记跨生产步骤持有资源；会话退役后按可达性关闭（见[第 6 节](#stream)） | [Stream 8.1](STREAM_LIFELONG.md#production)、[9.5](STREAM_LIFELONG.md#consumer-end) |
| 故障归到资源 | Error 的 `handles`；关联 scope 不写 | 沿 Input／requests 找最近的 Scoped，必须恰好一个 | 在同一棵 ScopeTree 的祖先路径上依次检测、处置 | [Error](LATEST_DESIGN.md#error) |

<a id="scope-missing"></a>
### 尚未覆盖

待交付数据和业务资产内嵌资源的持有登记、一个 Scoped 注册服务多种细化资源，仍未实现（见 [Next stages](NEXT_STAGES.md)）。业务资产保存记录不自动合并其中各资源的 owner。

<a id="stream"></a>
## 6. 持续执行（Stream 与 lifelong）

持续执行没有专门的流操作 API。下面这些组合事实决定一份持续资产怎样生产、怎样被消费：

- Context 的 `stream = True`，以及它的 Input 链挂在 Stream 下还是链上有 `streams`；
- 同一 lifelong 里是否有执行它所挂原子句柄的 AST 位置；
- lifelong 怎样拆成单元，哪个节点订阅哪份资产，发布位置在哪个单元；
- 每个 effect 自己是否声明了 `streams`。

熟悉流处理库的读者，也许可以把其中一些行为粗略地看成 Effect-TS 中某些 Stream 操作，表格最后一列给出这样的类比，只为方便理解。框架并不以任何流库为参照，也没有对应的方法；深究起来，实现与语义都不相同，阅读时请以本文和 Stream 规范为准。

<a id="stream-produce"></a>
### 6.1 生产

| 行为 | 组合 | 推导 | 驱动 | 规范 | 或可类比为 |
| --- | --- | --- | --- | --- | --- |
| 持续来源，取不到下一份输入时结束 | Stream effect，加挂在它下面、`stream = True` 的 Context；来源没有下一份输入时 handler 调用 `streamEnd` | `BootPlan` 为 Receive；Stream handler 的 Layer 带 `StreamEnds` | 会话的生产任务循环执行 Stream 单步与 parser，每步发布一条；`streamEnd` 使会话封口 | [4](STREAM_LIFELONG.md#bootplan)、[9.4](STREAM_LIFELONG.md#end) | `repeatEffectOption` |
| 首次需要时才开始生产 | 无需写法 | 会话描述 | 进入 lifelong 时启动本边界的会话；lifelong 外第一次 `require` 时启动托管会话 | [7](STREAM_LIFELONG.md#sessions)、[8.3](STREAM_LIFELONG.md#production) | 流的惰性 |
| 由上游每条交付驱动产出一条 | Context `stream = True`，Input 链上有 `streams "U"`，本 lifelong 没有它的发布位置 | `BootPlan` 为 Derive | 领取一条 U 的交付 → 执行被驱动的 Input 链 → parser 发布一条；可以逐级串联 | [4.2](STREAM_LIFELONG.md#derive)、[8.1](STREAM_LIFELONG.md#production) | `mapEffect` |
| 消费步骤的输出成为新的持续资产，不重跑该步骤 | Context 挂在 lifelong 节点的原子句柄下 | `BootPlan` 为 `ReuseOutput [发布节点]` | 节点执行后由挂接 parser 发布，不另开任务；发布节点都结束或所在单元结束后封口 | [4.2](STREAM_LIFELONG.md#derive) | `mapEffect` 的结果再被共享 |
| 每步生产带上同一步的辅助产物 | 生产链上的其他 Context 照常发布 | 独立生产任务的伴随发布 | 每条交付附带同一步发布的普通资产，消费方读到的是同一步的产物 | [7](STREAM_LIFELONG.md#sessions) | — |
| 资源随生产存续 | 来源的 Input 上游放 Scoped（如 StreamDemo 的 `SensorLink`） | scope 开启计划、会话挂载 | 会话的使用登记跨步骤持有资源；会话退役后按可达性关闭 | [8.1](STREAM_LIFELONG.md#production)、[9.5](STREAM_LIFELONG.md#consumer-end) | `acquireRelease` |
| lifelong 的独立来源没有消费方时停止生产 | 无需写法 | lifelong 边界内 Receive／Derive 的读取方登记 | 读取方全部离开时会话退役：停止生产任务 → 封口 → 回收只在会话中开启的 scope；上游同属该边界且无人读取时一并退役。interpreter 托管会话在运行退出时停止，ReuseOutput 按发布位置封口 | [9.5](STREAM_LIFELONG.md#consumer-end) | 按引用计数共享的流 |
| 生产失败 | 无需写法 | — | 会话失败并通知运行监督；含 lifelong 的程序暂按临时规则终止整次运行 | [9.1](STREAM_LIFELONG.md#failures) | — |

<a id="stream-consume"></a>
### 6.2 消费

| 行为 | 组合 | 推导 | 驱动 | 规范 | 或可类比为 |
| --- | --- | --- | --- | --- | --- |
| 每条交付执行一次消费 | lifelong 中以 `streams` 订阅该资产的节点 | `lifelongUnits`、`lifelongSubscriptions` | 单元逐条领取，每条一个 frame，同一单元的调用不重叠，上一轮的普通产物不带入下一轮 | [6](STREAM_LIFELONG.md#scheduling) | `runForEach` |
| 多个消费单元并发推进 | `lifelong [parallel [...]]` 的各子项 | 单元拆分 | 各单元并发推进、互不等待 | [6.1](STREAM_LIFELONG.md#scheduling) | 多播后分别运行 |
| 一份资产有多个消费方 | 多个单元或派生会话 `streams` 同一资产 | 同一边界中一份资产一个会话；读取方登记 | 每个读取方独立游标；保留未领取交付及最新值，目前没有背压 | [7](STREAM_LIFELONG.md#sessions)、[7.1](STREAM_LIFELONG.md#retention) | `broadcast`、`share` |
| 派生持续资产被普通链读取一次 | A 的 Input 链订阅 B；C 或普通 Context 链 `requires` A | A 的独立 Derive 计划、普通读取路由与托管上游关系 | 首次需求建立 A/B；A 随 B 继续发布，C 取得一次固定 T 后继续，不继承订阅 | [8.3](STREAM_LIFELONG.md#production) | 持续来源的一次采样 |
| 只读当作不变的值 | 单元内 `requires "T"` | 该读取方只读最新一条 | 不订阅；本轮第一次读取时领取一条交付，同一轮共享；本单元发布的资产则读已有的一条 | [6.3](STREAM_LIFELONG.md#scheduling)、[9.5](STREAM_LIFELONG.md#consumer-end) | — |
| 按每条交付的状态选择分支 | lifelong 内的 alternative，转折资产是本 lifelong 的持续资产 | `AlternativeProto`；选择读取领取交付 | 每条交付按最新条目的构造器只启动一个候选 | [6.3](STREAM_LIFELONG.md#scheduling) | 在逐条处理里做 `Match` |
| 同一单元里既发布又读取 | 单元中已先行或必经并行的节点发布，其他位置直接或经 Derive 订阅该产物 | 发布位置、单一派生上游与实际轮帧 | 等本轮发布和派生处理稳定；仍无新交付才跳过本轮，封口排空后其订阅结束 | [9.5](STREAM_LIFELONG.md#consumer-end) | — |
| 消费方不再消费 | 订阅方的 handler 按条件调用 `endStream` | 自己声明 `streams` 的 Excu，其 Layer 带 `EndsStream` | 节点之后各轮跳过；按读取方计数逐层离开（节点 → 单元 → 会话） | [9.5](STREAM_LIFELONG.md#consumer-end) | `take`、`takeWhile` |
| 结束向下游传播并排空 | 无需写法 | — | 封口后读取方领完积压才结束；单元在所需来源排空或节点都结束订阅时结束；全部单元结束后 lifelong 返回 | [9.4](STREAM_LIFELONG.md#end) | 流的完成 |
| 结束后或在外部读最新的值 | lifelong 的后继或 lifelong 外写 `requires "T"` | 静态来源表；后继读取的来源保留 | 后继读每个来源最新一次发布；lifelong 外由托管会话交付，至少等到一条 | [9.4](STREAM_LIFELONG.md#end)、[8.3](STREAM_LIFELONG.md#production) | `runLast` |

类比在许多地方并不成立，例如：资产是有唯一来源、按名字细化的业务值；消费按单元逐条推进，同一单元不并发处理多条；保留未领取交付但没有容量背压；`require` 读的是当作不变的值，不是订阅；含 lifelong 的程序中任何失败暂按临时规则终止整次运行。累计记录、平均值或其他状态由业务 handler 与资产表达。

<a id="stream-drive"></a>
### 6.3 运行时据哪些事实选择驱动

| 事实 | 运行时的分支 | 位置 |
| --- | --- | --- |
| `sessionPlan` | Receive 和 Derive 启动生产任务并按步骤循环；ReuseOutput 不启动任务，只登记交付状态 | `Runtime.sessionLauncher` |
| 读取关系（单元内的订阅、普通读取点或选择读取） | 登记读取方游标，按未领取位置保留交付；普通有限读取只捕获当前值 | `Execution` 的 `access`、`Session.release` |
| 发布节点（`ReuseOutput` 的节点表） | 发布位置按节点计，节点结束或单元结束时撤下，全部撤下才封口 | `Execution` 的 `withdraw` |
| 发布节点所在的单元与派生上游 | 本单元直接或间接发布的来源，等节点退休和派生处理追平后才判断本轮无交付；外部来源继续等待后续增量 | `DeliveryFrame.frameLocal`、`frameStable`、`Session.sessionCaughtUp` |
| 节点的订阅是否结束 | 已结束的节点跳过；单元不再有活读取位置时离开会话；lifelong 独立会话的读取方计数归零时退役 | `Execution.repeatUnit`、`Session.departSession` |

<a id="stream-missing"></a>
### 6.4 尚未覆盖

下列行为目前没有对应的组合，延期理由见 [Stream 第 11 节](STREAM_LIFELONG.md#deferred)：

- 跳过某些交付，不产出（派生持续资产的跳过）；
- 一条交付产出多条；
- 多个持续来源共同触发一个 target；
- 交付队列的容量与背压；
- 按时间节奏驱动（时间周期声明）；
- 局部失败与重试，以及嵌套 lifelong。

<a id="layer"></a>
## 7. handler 的能力也由组合推出

Layer 是方法体可用能力的边界，同样不由业务填写，而是从绑定推出（[注册](LATEST_DESIGN.md#registration)）：

| 能力 | 什么组合给它 |
| --- | --- |
| `Reads T` | demands 中 `requires` 或 `streams` 的资产，T 为其声明表示类型；单独的 `requests` 不带来读取 |
| `Raw` | 只有挂接的 parser 与 Pure |
| `Raises` | 每个 handler 的本地错误，由输出时补入 |
| `StreamEnds`（`streamEnd`） | 绑定成 Stream 的 handler |
| `EndsStream`（`endStream`） | 自己声明了 `streams` 的 Excu；同链的前驱与 lifelong 里不订阅的普通节点不给 |
| `MonadIO` | Pure 以外 |

同一个 handler 绑定到多个 effect 时，各绑定推出的 Layer 必须一致。因此能力只按 handler 自己的类别和读取推出，不按它所处的控制流推出：普通原子操作放进 lifelong 不会多出能力，也就能在有限链与持续链之间复用。
