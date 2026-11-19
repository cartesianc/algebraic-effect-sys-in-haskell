# 组合推导：结构怎样成为执行语义

更新：2026-11-18。组合逻辑是这个框架的核心设计原则：业务写下资产、effect、原子 handler 和 workflow 的关系，SDK 对这些结构进行运算，得到可以检查、生成和执行的含义。本文先说明这项原则，再列出各组合的推导依据；详细协议仍由[主设计](CORE_DESIGN.md)、[图与来源](EFFECT_GRAPH.md)和[Stream 规范](STREAM_LIFELONG.md)分别维护。

<a id="why"></a>
## 1. 组合逻辑为什么是框架核心

handler 描述一次原子操作；业务含义由它绑定的 effect、Input、demands 和 workflow 共同决定。同一个 handler 可以用于不同业务链，仍只实现自己的取值、解析或 IO。SDK 必须能够从这些声明计算出它应获得哪些能力、资产从哪里进入、谁驱动谁，以及哪些结构组合不成立。这项计算决定框架的表达方式，代码生成和运行调度都服务于它。

<a id="ad-hoc"></a>
### 组合产生的特设多态

同一个声明元素在不同的、可静态判定的关系中获得不同解释，本框架将它称为**组合产生的特设多态**。这个术语借用了程序语言中按使用上下文选择具体实现的思想：Haskell 类型类按类型选择实现，这里由 gen 按声明之间的结构关系选择装配含义。两者并不等同；这里的解释集合由 SDK 规定，业务通过已有声明进行组合。

| 声明元素 | 决定解释的关系 | gen 得到的含义 |
| --- | --- | --- |
| Context | Input 是普通句柄、Stream，或其链被持续资产驱动；AST 是否已有对应发布位置 | 一次解析、持续来源、独立派生或同次输出复用 |
| 资产读取 | 表示类型、refined asset、访问方式及挂载位置 | 唯一来源路由、固定捕获或按交付驱动 |
| Scoped 的开启参数 | 引用已有生产还是本次驱动新生产 | 实例共享依据与开启类别；实际身份留到运行时匹配 |

原子 handler 对组合保持不变：它只使用绑定契约给出的能力，完成本次读取、解析或 IO。同一份实现能用于不同业务关系，但每个绑定仍必须满足签名与读取约束；复用实现不合并实际调用。

生产与消费也是关系角色。一个 Context 链可以消费上游资产，同时向另一条链生产资产；它不必额外标注自己是生产者还是消费者。持续链 A 随 B 的增量发布，普通链 C 可以只读取 A 的一次固定结果。**持续生产能力不沿取值依赖自动传播；是否重复启动由组合中的驱动关系决定。** A 若保存记录，C 读到的就是业务记录；A 若做统计，C 读到的就是统计。SDK 不识别这些业务名称，也不给资产增加特殊的历史包装。

<a id="determinism"></a>
### 确定性：结构决定装配规则

1. **来源与装配确定。** 解释来自注册、AST 和可提取的 handler 读取关系。每个 refined asset 对应唯一 Context 来源；读取路由、能力与驱动装配由 gen 确定。
2. **运行按既定协议取值。** 同一 Context 可多次生产，普通 `require` 按共享最新值与固定捕获规则读取。首次捕获哪次发布可以受调度影响，这属于运行状态，不是装配歧义；详细读取协议见[主设计](CORE_DESIGN.md#await-visibility)。
3. **已能证明的结构错误在生成期报告。** 缺少合法解释或存在无法消除的资产来源、装配歧义时拒绝；没有证明不等于已经证明安全。已实现的最低限度检查与延期的完整分析分开维护，见[普通读取来源](EFFECT_GRAPH.md#missing-source)与[当前边界](NEXT_STAGES.md#current-limits)。

协议错误按“故障＋触发条件”划分生成期检查、运行状态与 SDK 不变量故障；现有 14 种故障的归属和证据边界统一见[协议故障表](EFFECT_GRAPH.md#protocol-faults)。生命周期资源读取在 `composeMethods` 按绑定方法检查，保持在同一组合计算内。

这些是设计要求，不是任意程序的可判定性保证。条件生产可能失败，业务 IO 可能永远阻塞；合法的来源计划不能保证每次执行都有值。`catchError` 可以处理运行失败，也不能为一条没有合法来源的依赖创造结构解释。

这项设计把三件事连在一起：

- **代码能够表达关系。** 注册和 workflow 是有限、明确的结构，读者、HLS、生成器和 agent 面对同一份原生 Haskell。关系应能沿源码追溯，见[代码即文档](CORE_DESIGN.md#code-as-documentation)。
- **编译器能够计算关系。** gen 把结构作为数据进行分析，形成类型约束、精细化 DI、来源证明和图；不要求原子方法理解整个调度器。
- **运行时能够执行关系。** interpreter 消费已经确定的结构，管理实际值、执行进度、会话与资源；业务 IO 的结果不由编译器猜测。

从业务一侧看，这三件事构成一门领域语言的前端与所有业务共用的后端，见[业务即 DSL](CORE_DESIGN.md#business-as-dsl)；与经典 algebraic effect 在解释机制上的异同见[主设计 3.12](CORE_DESIGN.md#algebraic-effects)。

因此，设计新能力时先确定“哪些结构关系对应什么执行含义”，再决定如何生成代码和维护运行状态。没有结构证据的行为应诊断或保留待定，不能以线程先后选择不同的资产契约；同一契约的并发发布则按明确的最新值协议执行。框架对组合的解释有明确适用条件，也不因为引入状态机就自动证明任意业务程序满足代数定律。

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
## 2. 统一计算的产物与规则定位

[Gen.Composition](../sdk/Framework/Gen/Composition.hs) 统一组合计算的入口和结果。它接收声明、workflow 与 handler 读取形状，输出确定的类型能力、路由、装配连接及 Prototype；Emit 渲染这些结果，runtime 执行计划。生产与消费是组合中的关系角色，不另加业务标签。

**解释只有一个权威来源。** Composition 调用 Injector 合成单入口的能力与装配，调用 Booter 合成挂载及驱动标记；Emit 和 runtime 消费这些结果。这里的“合成解释”对应框架对原子操作的回应与驱动，不新增业务 XxxHandler 类。多个合法运行路径或等价实现不构成歧义；只有既有协议无法确定解释且没有合法的运行选择规则时才拒绝。

**当前统一到这里：** 类型能力、读取与包装、scope/Error 回调、会话入口和单元／来源关联已有明确计算归属。内部仍使用不同阶段算法，不是通用规则求解器；物理分模块不产生新的解释权威。阶段状态、两个检查点和装配流程只在[主设计的编译流水线](CORE_DESIGN.md#generation)维护，缓存协议只在[图规范](EFFECT_GRAPH.md#cache)维护。

| 组合问题 | 计算入口或关系查询 | 结果交给谁 |
| --- | --- | --- |
| 哪份资产、哪种访问合法 | `buildEffectProtos`（内部解析 demands） | effect 原型、后续会话与读取计算 |
| workflow 怎样挂载并驱动，是否复用已有输出 | `Booter.numberWorkflow`、`Booter.planSessions`；共享查询 `bootPlan`／`finiteSessions` | 挂载、会话与 `OutputConnection` |
| handler 获得什么签名和入口 | `Composition.declareEffects` → `Injector.bindProgram`，声明先确定角色，装配再确定能力与路由 | `ReadRoute`、`Capability`、`EntryOperation`、选择器与会话入口；Emit 不再自行选取 |
| 调用结构怎样进入图与 ScopeTree | `composeMethods`、`buildStructure` | 方法图、链事实、无环 ScopeTree |
| 单元、会话、捕获与本轮进展关联 | `Booter.completeDriving` | Prototype 的驱动标记；runtime 查询动态进度 |
| 一个读取能用哪些生产，何时拒绝 | `resolveSources` | 来源证明、`protoSources`、scope 开启计划与静态诊断 |

阶段专用助手放在所属解释入口内；模块按前端、解释、装配合成、驱动合成、数据与输出分工。跨阶段传递事实，不让下游读取原注册再决定一次；具体目录与接口检查点见主设计。

这些入口是同一编译计算中的职责位置；维护者新增规则应先找到它依赖的事实，在对应计算中产生结果，交给后续步骤消费。不能在 Emit 或 runtime 再判断一遍，也不因“统一”而把取值、取消或资源状态搬到编译器。

`Prototype.Query` 保留编译器与原型校验共用的纯结构查询；GHC 语法提取、源码资产类检和文本输出仍各守边界。图缓存、路径集合与来源裁剪是内部算法，不等于运行时状态；统一入口没有消除路径分析的指数上界，见[构图与复用](EFFECT_GRAPH.md#reuse-boundary)。

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
- 每条规则先说明结构前提、解释与拒绝条件；本文维护组合原则、产物和规则定位，详细协议归所属专题，阶段状态与验证结果归 [Next stages](NEXT_STAGES.md)。
- 实现前先列明需要的静态事实与动态状态。已有 Prototype 事实足以表达时直接复用，不为统一入口再造一份计划；确需新增组合解释时，先扩展 `Gen.Composition` 对应计算及其事实产物，Emit 与 runtime 只消费该结果。
- runtime 依据已有许可关系匹配实际 `ActivationId`、执行帧、使用者与终态，不根据资产内容或 IO 形式重判业务类别。新增资源行为须说明使用了哪些开启计划、来源、会话挂载和 ScopeTree 事实，以及在哪个运行事件撤销使用；不能把生命周期协调写成第二套结构推导。
- 未实现的行为只出现在各节的“尚未覆盖”中，不写成当前能力。

<a id="context"></a>
## 4. 生产与消费

普通资产（`stream = False`）的生产与消费。这里没有“调用生产者”的写法：消费方只声明要驱动或读取哪份资产，由组合推出谁来生产、何时生产、读到哪一次。

<a id="context-produce"></a>
### 4.1 生产

| 行为 | 组合 | 推导 | 驱动 | 规范 |
| --- | --- | --- | --- | --- |
| 资产有唯一的生产方 | Context 以 `asset = Asset @T "名字"` 声明；消费方只写资产名 | 按资产名解析出唯一生产方，多个生产方即报错 | 不按距离或拓扑替用户选来源 | [Context](CORE_DESIGN.md#context)、[资产来源与访问约束](CORE_DESIGN.md#demand-contract) |
| 驱动一次新的生产 | 消费方 `requests "T"` | 入口的驱动步骤，排在前驱与方法体之前 | 每次进入入口都重新执行 T 的生产链并发布；不合并重复驱动 | [入口装配](CORE_DESIGN.md#calls) |
| 原子操作的输出解析成资产 | Context 的 Input 是 Excu 或 Scoped，parser 用 `raw` | 挂接连接（`contextInjections`）、raw 来源 | 句柄成功后，parser 读本次输出发布资产，句柄不重跑；普通 Context 的解析失败留在注入内部，资产不发布 | [原子输出挂接](CORE_DESIGN.md#context) |
| 同一个 parser，被驱动时自己取得输入 | 同上的 Context 被 `requests` 或选择读取驱动 | 同一份入口，raw 的回答方式不同 | raw 执行句柄入口，从头启动生产链；失败沿驱动方传播 | 同上 |
| 输出的纯变换 | Input 链上串 Pure | Pure 链，挂接点是最上面的原子句柄 | 句柄输出经 Pure 依次变换后交给 parser；Pure 不改变调用者身份，不会重复注入 | [Pure](CORE_DESIGN.md#pure) |
| 操作按顺序组合 | `input = "前驱"` | 入口的前驱步骤 | 在方法体之前执行前驱；不传值，前驱失败原样传播 | [句柄与值](CORE_DESIGN.md#handles-and-values) |
| 每个生产方法都有人驱动 | 无需写法 | 从各 AST 末端和选择读取求可达集合 | 生产方法无法从任何入口到达时，生成期报错 | [图与来源](EFFECT_GRAPH.md) |
| 相同上游出现在多条链上 | 两个 effect 以同一个 effect 为 Input | 各挂载保留自己的 NodeId | 各自执行，不按方法名去重；不把重复的 IO 当作幂等 | [结构共享与执行复用](EFFECT_GRAPH.md#reuse-boundary) |

<a id="context-consume"></a>
### 4.2 消费

| 行为 | 组合 | 推导 | 驱动 | 规范 |
| --- | --- | --- | --- | --- |
| 读取已有的值，不生产 | `requires "T"`，方法体 `require @T` | 读取权限与读取路由；读取点的来源（`protoSources`） | 先用本次捕获，再读许可来源的发布；没有值时等待，不补跑生产 | [Context](CORE_DESIGN.md#context) |
| 静态证明普通读取无来源 | 已到达的读取在所有已分析路径均无合法供值或捕获 | gen 在来源证明阶段拒绝，并定位读取点 | 不把结构错误交给运行时缺值处理 | [静态无来源诊断](EFFECT_GRAPH.md#missing-source) |
| 按类型读取，读到哪份由注册决定 | 同一表示类型细化成多份资产；handler 只写 `require @T` | 每个 effect 按“表示类型 + effect”生成读取实例 | 同一个 handler 绑到不同 effect，各自读到 demands 里那份资产 | [Context](CORE_DESIGN.md#context) |
| 按构造器读取和类型的分支 | `requires` 分支契约（如 `FileTextWritten`） | 分支契约目录，投影当前构造器 | 读到构造器的字段；构造器不匹配报 `CaseNotSelected` | [Context](CORE_DESIGN.md#context) |
| 读到哪一次发布 | 无需新写法；refined asset 决定唯一生产链 | 共享供值固定点与生产机会，持续资产另走会话 | 普通读取先用调用捕获，再取运行级最新 Binding；缺值等发布，不按 AST 位置过滤 | [图与来源](EFFECT_GRAPH.md#missing-source) |
| 等不到值时结束等待 | 无需写法 | 来源候选与执行帧的节点进度 | 候选都已退休仍无值时报 `ContextNotInitialized`；资源 Context 与诊断、收尾、close 期间不等待 | [可见范围与等待](CORE_DESIGN.md#await-visibility) |
| 声明的读取都有用处 | 无需写法 | 读取依据：方法体的读取或控制流的读取 | 声明了却没有任何依据的读取，生成期报错 | [资产来源与访问约束](CORE_DESIGN.md#demand-contract) |
| 按资产的状态选分支 | `alternative` 的候选各 `requires` 同一资产的一个分支契约；AST 不写条件 | `AlternativeProto`：转折契约、构造器到候选的对应 | 选择读取相当于 `requests`：先生产转折资产，只启动匹配的候选，并把选择时的捕获交给它 | [workflow](CORE_DESIGN.md#workflow) |

<a id="scope"></a>
## 5. 资源（scope）

scope 同样没有 key、寿命或 cleanup 策略的写法。何时开启、与谁共享、何时关闭、按什么顺序关闭、故障归到哪里，都从 Input、demands 与 AST 推出。

| 行为 | 组合 | 推导 | 驱动 | 规范 |
| --- | --- | --- | --- | --- |
| 在需要的链上开启 | Scoped 放在链的 Input 上 | 入口的前驱步骤 | 进入入口时先开启；已开启的实例复用，跳过 open 的方法体 | [入口装配](CORE_DESIGN.md#calls) |
| 注册级单例 | Scoped 的资源 Context 没有开启参数 | scope 开启计划，类别为注册级单例 | 同一注册共享实例，归根帧 | [单例与多例](CORE_DESIGN.md#scope-identity) |
| 按一次生产共享 | 开启参数只经 `requires` 引用已有的生产 | 各参数可能的生产节点（`protoScopeOpenings`） | 读到同一次生产的开启共享同一实例，保留原归属帧 | 同上 |
| 持续最新值作开启参数 | 资源 parser 声明 `requires` 并读 `require @T` | `FromSession` 开启计划 | 固定交付末条沿用原生产身份与帧，按交付／游标与后继读取位置判断待用 | [开启计划](EFFECT_GRAPH.md#scope-opening-retention) |
| 每次新开（多例） | 当前执行用 `requests` 新生产了开启参数 | 同上 | 新的参数生产确定新实例；本次生产的后继仍共享它 | 同上 |
| 实例属于哪一层 | 无需写法 | 参数生产所在的执行帧 | 取参数中最内层的帧，无参数取根帧；lifelong 本轮生产参数的实例归本轮 | 同上、[按可达性回收](CORE_DESIGN.md#scope-gc) |
| 一份资源只有一个关闭者 | Scoped `requests` 资源 Context | open 认领资源绑定 | 首次 open 认领为 owner，所有副本看到同一归属；其他实例认领报 `ScopeContextMismatch` | [scope](CORE_DESIGN.md#scope) |
| 只在已开启的链里读资源 | handler `require` 资源 | 资源读取点与所属 scope 的开启位置 | 资源在本链的 scope 开启前被读取，生成期拒绝；运行时不扫描其他活实例来补 | [Scope 开启计划](EFFECT_GRAPH.md#scope-opening-retention) |
| 不再使用时关闭 | 无需写法；close 写在 Scoped 上，可为 `Nothing` | 执行帧的待用关系、开启计划 | 没有当前使用者、匹配的待用或已有 ownership 保留，也没有保留它的子 scope 时同步关闭；`Nothing` 时只移出运行表 | [按可达性回收](CORE_DESIGN.md#scope-gc) |
| 关闭顺序 | 无需写法 | ScopeTree：静态路径上的共同必经前序，加上 Input／requests 链与资源来源给出的注册前提 | 子先父后；实例只保留同一受控链实际使用的父实例 | [图与来源](EFFECT_GRAPH.md) |
| 持续执行中复用与回收实例 | 来源的 Input 上游放 Scoped，开启参数按既有 demands 取得 | `SessionProto` 的挂载、`ScopeOpening` 的参数来源、`Source` 读取许可与 `ScopeTree` | 每步撤销实际使用；会话待用帧按实际参数身份保留后续所需实例，新 request 不直接关闭旧实例 | [Stream 资源边界](STREAM_LIFELONG.md#binding-retention)、[事实分工](EFFECT_GRAPH.md#scope-opening-retention) |
| 故障归到资源 | Error 的 `handles`；关联 scope 不写 | 沿 Input／requests 找最近的 Scoped，必须恰好一个 | 在同一棵 ScopeTree 的祖先路径上依次检测、处置 | [Error](CORE_DESIGN.md#error) |

<a id="scope-missing"></a>
### 尚未覆盖

待交付和已捕获值已有 ownership 的保留见[资源协议](STREAM_LIFELONG.md#binding-retention)。一个 Scoped 注册服务多种细化资源仍未实现（见 [Next stages](NEXT_STAGES.md#deferred)）。普通解析数据不继承生产资源的寿命；任意业务 ADT 内嵌资源的自动追踪不属于当前[资产契约](STREAM_LIFELONG.md#binding-retention)，不作为本轮待办。

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
| 资源随生产存续 | 来源的 Input 上游放 Scoped（如 StreamDemo 的 `SensorLink`） | scope 开启计划、会话挂载 | 按[第 5 节](#scope)的同一实例待用规则保持跨步骤复用；退役撤销会话预约 | [9.3](STREAM_LIFELONG.md#binding-retention) | `acquireRelease` |
| lifelong 的独立来源没有消费方时停止生产 | 无需写法 | lifelong 边界内 Receive／Derive 的读取方登记 | 读取方全部离开时会话退役：停止生产任务 → 封口 → 回收只在会话中开启的 scope；上游同属该边界且无人读取时一并退役。interpreter 托管会话在运行退出时停止，ReuseOutput 按发布位置封口 | [9.5](STREAM_LIFELONG.md#consumer-end) | 按引用计数共享的流 |
| 生产失败 | 无需写法 | — | 会话失败并通知运行监督；含 lifelong 的程序暂按临时规则终止整次运行 | [9.1](STREAM_LIFELONG.md#failures) | — |

<a id="stream-consume"></a>
### 6.2 消费

| 行为 | 组合 | 推导 | 驱动 | 规范 | 或可类比为 |
| --- | --- | --- | --- | --- | --- |
| 每条交付执行一次消费 | lifelong 中以 `streams` 订阅该资产的节点 | `lifelongUnits`、`lifelongSubscriptions` | 单元逐条领取，每条一个 frame，同一单元的调用不重叠，交付逐轮固定，普通资产仍可读取共享最新值 | [6](STREAM_LIFELONG.md#scheduling) | `runForEach` |
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

Layer 是方法体可用能力的边界，同样不由业务填写，而是从绑定推出（[注册](CORE_DESIGN.md#registration)）：

| 能力 | 什么组合给它 |
| --- | --- |
| `Reads T` | demands 中 `requires` 或 `streams` 的资产，T 为其声明表示类型；单独的 `requests` 不带来读取 |
| `Raw` | 只有挂接的 parser 与 Pure |
| `Raises` | 每个 handler 的本地错误，由输出时补入 |
| `Hooks`（`hookedOutput`／`hookedRaw`／`hookedError`） | 只有 Middleware |
| `StreamEnds`（`streamEnd`） | 绑定成 Stream 的 handler |
| `EndsStream`（`endStream`） | 自己声明了 `streams` 的 Excu；同链的前驱与 lifelong 里不订阅的普通节点不给 |
| `MonadIO` | Pure 以外 |

同一个 handler 绑定到多个 effect 时，各绑定推出的 Layer 必须一致。因此能力只按 handler 自己的类别和读取推出，不按它所处的控制流推出：普通原子操作放进 lifelong 不会多出能力，也就能在有限链与持续链之间复用。

<a id="middleware"></a>
## 8. 捕获（Middleware）

Middleware 是驱动方式特殊的 Excu，也是 Root 的 superclass 的注入方：注册给出 handler 与拦截的类别，作用范围由 AST 标注给出。捕获由 Root 级调用点的改写决定，不是另一种按关系选择解释的多态；被捕获的 handler 与它的 Input 关系都不改变。

| 行为 | 组合 | 推导 | 驱动 | 规范 |
| --- | --- | --- | --- | --- |
| 观察一段子树里交出的值、raw 与失败 | Middleware 注册（`input = "None"`）；AST 写 `middleware [node "M"] 子树` | 剥离标注后照常编号；标注位置存为 `drivingMiddleware` | 子树的结构、NodeId 与单元划分不变 | [Middleware](CORE_DESIGN.md#middleware) |
| 只捕获某几类 effect | `intercept = [ExcuKind, ...]`，或 `allEffects` | 被拦截类别的交出值、`raw`、`raise` 改写为带 handler 名的调用；其他调用点不变 | 调用点上执行生效的 Middleware，原值原样交回 | 同上 |
| 同一 handler 在不同子树表现不同 | 一处挂载在标注内，另一处不在 | 每个启动位置的生效集合（`drivingHooks`），按位置前缀取覆盖它的标注之并，会话步骤同样 | 按启动位置查表；未覆盖的挂载不执行 Middleware | 同上 |
| 拆出本次捕获 | 方法体 `hookedOutput`／`hookedRaw`／`hookedError` | 只为 Middleware 的标签生成 `Hooks` 实例 | 不是本次的那一种时为 `Nothing` | 同上 |
| Middleware 与被捕获的链不成环 | 无需写法 | 任何 effect 的 Input 都不能指向 Middleware；Middleware 没有 demands | Middleware 执行时生效集合为空，不再被捕获 | 同上 |

Middleware 与普通 Excu 一样可以 `raise`，失败从调用点传播；后续事项见 [Next stages](NEXT_STAGES.md#middleware)。
