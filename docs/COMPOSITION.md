# 组合推导：声明组合怎样决定运行行为

更新：2026-11-17。本文是跨专题的对照入口：列出业务写下的组合会被 gen 推导成什么事实、运行时据此怎样驱动，以及完整规则在哪一份规范里。协议本身仍由各专题唯一维护（[主设计](LATEST_DESIGN.md)、[图与来源](EFFECT_GRAPH.md)、[Stream 规范](STREAM_LIFELONG.md)），本文不复制它们，只给出对应关系；框架每增加一种由组合推导的行为，就在这里增加一条。

<a id="why"></a>
## 1. 为什么 SDK 里找不到这些行为的名字

框架不按行为提供操作名。SDK 里没有 `map`、`filter`、`take`、`share`、`acquireRelease` 这样的方法，也没有让业务标注的 key、寿命、单例／多例、驱动方式或清理策略。业务只写四类结构：

| 结构 | 写在哪里 | 表达什么 |
| --- | --- | --- |
| 资产 | Types.hs 的 ADT 与 `Asset @T "名字"` | 跨操作流动的业务值及其唯一来源 |
| 注册 | Effects.hs 的 `typing`、`input`、`demands` | 操作类别、前驱、驱动与读取 |
| 原子方法 | Handlers.hs 的 instance | 一次读取、解析或 IO |
| workflow | AST 与 `Workflow/*.hs` | 哪些链在什么时候、以什么控制流启动 |

同一种声明元素放进不同组合，得到不同的运行行为。例如同一个 `Context` 声明：挂在原子句柄下是一次普通解析；挂在 Stream 下并声明 `stream = True` 是持续来源；Input 链上有 `streams` 时，按 AST 里是否已有发布位置，成为独立派生或沿用已有输出。又如 scope 的开启参数用 `requests` 还是 `requires` 进入，决定这次开启是多例还是单例。

这样设计的理由：

- **组合在源码里可见**：关系写在固定声明里，读者和工具都能沿结构读出（[代码即文档](LATEST_DESIGN.md#code-as-documentation)）。按行为命名的方法会把组合藏进调用链。
- **判断在生成期完成**：gen 是编译器，能静态判定的组合由它决定并报错，运行时只执行编译结果（[gen 是编译器](LATEST_DESIGN.md#compiler)）。
- **原子方法不随控制流改变**：handler 只描述一次操作，同一个 handler 可以放进有限链或持续链，签名由它自己的读取与类别决定（见[第 7 节](#layer)）。

代价是：只读 SDK 的 API 无法列出框架能做什么，也看不出不同组合下业务实现的差异。本文补上这一份清单。

<a id="pipeline"></a>
## 2. 推导的路径

每条推导都按[自动装配必须有明确依据](LATEST_DESIGN.md#principles)的格式成立：输入前提 → 推导结构 → 运行行为 → 无法判定时的诊断。

    声明组合（注册、AST、handler 的读取结构）
    → gen 各阶段判定，写入 Prototype 的事实与生成代码
    → 运行时读取这些事实，选择特定的驱动
    → 不成立的组合在生成期报错，运行时不猜

| gen 阶段 | 推出的事实 | 运行时谁使用 |
| --- | --- | --- |
| 降级（Lower、Demand、Sessions） | 每个 demand 的唯一生产方；alternative 的转折契约与候选（`AlternativeProto`）；lifelong 的单元拆分与订阅（`lifelongUnits`、`lifelongSubscriptions`）；每份持续资产的生产方式（`sessionPlan :: BootPlan`） | Execution 的调度、Runtime 的会话启动 |
| 绑定（Assembly、Bind） | 每个绑定的驱动与前驱步骤、raw 来源、读取路由；handler 的 Layer 能力 | 生成的入口与 `At "E"` 实例 |
| 构图（Build） | 来源证明、EffectGraph、ScopeTree、scope 开启计划（`protoScopeOpenings`） | 取值、scope 共享与回收、Error 导航 |

运行时的分支只看这些事实，不看方法名，也不解释业务 IO。推导结果可以用 `cabal run 程序 -- --structure` 查看（[命令行](GUIDE.md#commands)），Layer 能力在 `Generated/Effects.hs` 里。

<a id="maintenance"></a>
## 3. 条目格式与维护

下面每一节是一张对照表，一行对应一种行为：

| 列 | 内容 |
| --- | --- |
| 行为 | 想得到的运行效果；可以对照其他框架的操作名 |
| 组合 | 业务要写的声明与 AST；“无需写法”表示由其他组合自动得到 |
| 推导 | gen 写入 Prototype 或生成代码的事实 |
| 驱动 | 运行时据此做什么 |
| 规范 | 完整规则所在的章节 |

维护规则：

- 新增一种由组合推导的行为时，先在所属专题写完整规则，再在这里加一行，并链接过去。
- 本文只写对应关系，不写协议细节、实现记录或验证结果；后两者在 [Next stages](NEXT_STAGES.md)。
- 未实现的行为只出现在各节的“尚未覆盖”中，不写成当前能力。

<a id="context"></a>
## 4. 取值与驱动

| 行为 | 组合 | 推导 | 驱动 | 规范 |
| --- | --- | --- | --- | --- |
| 先生产再读取 | `requests "T"` 与 `requires "T"` | 入口的驱动步骤；读取路由 | 进入入口时先执行 T 的生产链并发布，方法体 `require @T` 读这次发布 | [Context](LATEST_DESIGN.md#context)、[入口装配](LATEST_DESIGN.md#calls) |
| 只读已有的值 | 只写 `requires "T"` | 静态来源表 | 读可见来源的值，不生产；没有值时等待，可见生产者都结束仍无值时报 `ContextNotInitialized` | [可见范围与等待](LATEST_DESIGN.md#await-visibility) |
| 操作按顺序组合 | `input = "前驱"` | 入口的前驱步骤 | 在 handler 之前执行前驱；不传值 | [句柄与值](LATEST_DESIGN.md#handles-and-values) |
| 把原子输出解析成资产 | Context 的 Input 是原子句柄，parser 用 `raw` | 挂接连接、raw 来源 | 句柄执行后，parser 读本次输出并发布资产 | [Context](LATEST_DESIGN.md#context) |
| 输出的纯变换 | Input 链上串 Pure | Pure 链 | 句柄输出经 Pure 依次变换后交给 parser | [Pure](LATEST_DESIGN.md#pure) |
| 按资产的状态选分支 | `alternative` 的候选各 `requires` 同一资产的一个分支契约 | `AlternativeProto`：转折契约、构造器到候选的对应 | 选择读取相当于 `requests`：先生产转折资产，再只启动匹配构造器的候选 | [workflow](LATEST_DESIGN.md#workflow) |

<a id="scope"></a>
## 5. 资源（scope）

| 行为 | 组合 | 推导 | 驱动 | 规范 |
| --- | --- | --- | --- | --- |
| 注册级单例 | Scoped 没有开启参数 | scope 开启计划 | 同一注册共享实例，归根帧 | [单例与多例](LATEST_DESIGN.md#scope-identity) |
| 按一次生产共享 | 开启参数只经 `requires` 引用已有的生产 | 各参数可能的生产节点 | 读到同一次生产的开启共享同一实例 | 同上 |
| 每次新开（多例） | 当前执行用 `requests` 新生产了开启参数 | 同上 | 新的参数生产确定新实例，所属帧取最内层参数的帧 | 同上 |
| 不再使用时关闭 | 无需写法；close 写在 Scoped 上，可为 `Nothing` | 执行帧的待用关系、ScopeTree | 没有当前使用者、没有匹配的待用节点、没有保留它的子 scope 时同步关闭，子先父后 | [按可达性回收](LATEST_DESIGN.md#scope-gc) |
| 故障定位到资源 | Error 的 `handles`；关联 scope 不写 | 沿 Input／requests 找最近的 Scoped | 在 ScopeTree 的祖先路径上依次检测、处置 | [Error](LATEST_DESIGN.md#error) |

<a id="stream"></a>
## 6. 持续执行（Stream 与 lifelong）

持续执行没有专门的流操作 API。下面这些组合事实决定一份持续资产怎样生产、怎样被消费：

- Context 的 `stream = True`，以及它的 Input 链挂在 Stream 下还是链上有 `streams`；
- 同一 lifelong 里是否有执行它所挂原子句柄的 AST 位置；
- lifelong 怎样拆成单元，哪个节点订阅哪份资产，发布位置在哪个单元；
- 每个 effect 自己是否声明了 `streams`。

<a id="stream-effect-ts"></a>
### 6.1 与 Effect-TS Stream 的对照

下表左列是 Effect-TS 中语义相当的 Stream 操作，便于有流库经验的读者定位。相当指的是行为，不是接口：这里没有对应的方法，行为由右侧的组合推出。

| 行为（Effect-TS） | 组合 | 推导 | 驱动 | 规范 |
| --- | --- | --- | --- | --- |
| 拉取式来源，取不到时结束（`Stream.repeatEffectOption`） | Stream effect，加挂在它下面、`stream = True` 的 Context；来源没有下一份输入时 handler 调用 `streamEnd` | `BootPlan` 为 Receive；Stream handler 的 Layer 带 `StreamEnds` | 会话的生产任务循环执行 Stream 单步与 parser，每步发布一条；`streamEnd` 使会话封口 | [4](STREAM_LIFELONG.md#bootplan)、[9.4](STREAM_LIFELONG.md#end) |
| 惰性启动 | 无需写法 | 会话描述 | 进入 lifelong 时启动本边界的会话；lifelong 外第一次 `require` 时启动托管会话 | [7](STREAM_LIFELONG.md#sessions)、[8.3](STREAM_LIFELONG.md#production) |
| 逐条变换（`Stream.mapEffect`） | Context `stream = True`，Input 链上有 `streams "U"`，本 lifelong 没有它的发布位置 | `BootPlan` 为 Derive | 领取一条 U 的交付 → 执行被驱动的 Input 链 → parser 发布一条；可以逐级串联 | [4.2](STREAM_LIFELONG.md#derive)、[8.1](STREAM_LIFELONG.md#production) |
| 消费步骤的结果再成流，不重跑该步骤（`Stream.mapEffect` 后共享结果） | Context 挂在 lifelong 节点的原子句柄下 | `BootPlan` 为 `ReuseOutput [发布节点]` | 节点执行后由挂接 parser 发布，不另开任务；发布节点都结束或所在单元结束后封口 | [4.2](STREAM_LIFELONG.md#derive) |
| 多播（`Stream.broadcast`、`Stream.share`） | 多个单元或派生会话 `streams` 同一资产 | 同一 lifelong 中一份资产一个会话；读取方登记 | 每个读取方独立游标；保留量由读取义务决定，按历史读取时保留全部，没有背压 | [7](STREAM_LIFELONG.md#sessions)、[7.1](STREAM_LIFELONG.md#retention) |
| 逐条执行副作用（`Stream.runForEach`） | lifelong 中订阅该资产的节点 | `lifelongUnits`、`lifelongSubscriptions` | 单元逐条领取，每条一个 frame，同一单元的调用不重叠 | [6](STREAM_LIFELONG.md#scheduling) |
| 多个消费者并发 | `lifelong [parallel [...]]` 的各子项 | 单元拆分 | 各单元并发推进、互不等待 | [6.1](STREAM_LIFELONG.md#scheduling) |
| 带前缀历史的处理（`Stream.scan` 的可见范围） | `streams "T"`，方法体 `require @(History T)` | 该读取方按历史读取 | 每条交付附带到这一条为止的历史；累计值由 handler 从历史重算，不是增量状态 | [3.3](STREAM_LIFELONG.md#contracts)、[7.1](STREAM_LIFELONG.md#retention) |
| 按元素分派（`Stream.mapEffect` 中 `Match`） | lifelong 内的 alternative，转折资产是本 lifelong 的持续资产 | `AlternativeProto`；选择读取领取交付 | 每条交付按最新条目的构造器只启动一个候选 | [6.3](STREAM_LIFELONG.md#scheduling) |
| 消费方提前结束（`Stream.take`、`takeWhile`、`takeUntil`） | 订阅方的 handler 按条件调用 `endStream` | 自己声明 `streams` 的 Excu，其 Layer 带 `EndsStream` | 节点之后各轮跳过；同单元里由它发布的资产不再驱动读取位置；按读取方计数逐层离开 | [9.5](STREAM_LIFELONG.md#consumer-end) |
| 没有消费者时停止上游（`share` 的引用计数） | 无需写法 | 读取方登记 | 读取方全部离开时会话退役：停止生产任务 → 封口 → 回收只在会话中开启的 scope → 派生会话的上游也无人读取时一并退役 | [9.5](STREAM_LIFELONG.md#consumer-end) |
| 资源随流存续（`Stream.acquireRelease`、`Stream.scoped`） | 来源的 Input 上游放 Scoped（如 StreamDemo 的 `SensorLink`） | scope 开启计划、会话挂载 | 会话的使用登记跨步骤持有资源；会话退役后按可达性关闭 | [8.1](STREAM_LIFELONG.md#production)、[9.5](STREAM_LIFELONG.md#consumer-end) |
| 结束向下游传播并排空 | 无需写法 | — | 封口后读取方领完积压才结束；单元在所需来源排空或节点都结束订阅时结束；全部单元结束后 lifelong 返回 | [9.4](STREAM_LIFELONG.md#end) |
| 取最后一条（`Stream.runLast`），或随时读最新值 | lifelong 的后继或 lifelong 外写 `requires "T"` | 静态来源表 | 后继读每个来源最新一次发布；lifelong 外由托管会话交付，至少等到一条 | [9.4](STREAM_LIFELONG.md#end)、[8.3](STREAM_LIFELONG.md#production) |

与 Effect-TS 的主要差别：消费按单元逐条拉取，同一单元不并发处理多条；历史为读取方保留，没有容量与背压；含 lifelong 的程序中任何失败暂按临时规则终止整次运行（[9.1](STREAM_LIFELONG.md#failures)）。

<a id="stream-drive"></a>
### 6.2 运行时据哪些事实选择驱动

| 事实 | 运行时的分支 | 位置 |
| --- | --- | --- |
| `sessionPlan` | Receive 和 Derive 启动生产任务并按步骤循环；ReuseOutput 不启动任务，只登记交付状态 | `Runtime.sessionLauncher` |
| 读取方式（单元内是否有 `streams` 订阅、读取点或选择读取） | 登记为按历史读取或只读最新一条；会话据此决定保留多少条 | `Execution` 的 `access`、`Session.release` |
| 发布节点（`ReuseOutput` 的节点表） | 发布位置按节点计，节点结束或单元结束时撤下，全部撤下才封口 | `Execution` 的 `withdraw` |
| 发布节点所在的单元 | 单元读取自己发布的会话时不等待：本轮没有新发布则读取位置跳过，封口排空后其订阅结束，`require` 读已有的值；读取外部会话时阻塞等待，那是单元被驱动的方式 | `DeliveryFrame.frameLocal`、`awaitDeliveries`、`frameRead` |
| 节点的订阅是否结束 | 已结束的节点跳过；单元不再有活读取位置时离开会话；计数归零时退役 | `Execution.repeatUnit`、`Session.departSession` |

<a id="stream-missing"></a>
### 6.3 尚未覆盖

下列流操作目前没有对应的组合，延期理由见 [Stream 第 11 节](STREAM_LIFELONG.md#deferred)：

- 过滤（`filter`、`filterMap`）：派生持续资产的跳过；
- 一条产出多条（`mapConcat`、`flatMap`）；
- 多个持续来源共同触发一个 target（`merge`、`zip`、`zipLatest`）；
- 窗口、容量与背压（`buffer`、`grouped`、`sliding`）；
- 时间（`debounce`、`throttle`、`schedule`）；
- 分组（`groupByKey`）；
- 局部失败与重试（`catchAll`、`retry`），以及嵌套 lifelong。

<a id="layer"></a>
## 7. handler 的能力也由组合推出

Layer 是方法体可用能力的边界，同样不由业务填写，而是从绑定推出（[注册](LATEST_DESIGN.md#registration)）：

| 能力 | 什么组合给它 |
| --- | --- |
| `Reads T` | demands 中可读的资产，`streams` 时为 `History T` |
| `Raw` | 只有挂接的 parser 与 Pure |
| `Raises` | 每个 handler 的本地错误 |
| `StreamEnds`（`streamEnd`） | 绑定成 Stream 的 handler |
| `EndsStream`（`endStream`） | 自己声明了 `streams` 的 Excu；同链的前驱与 lifelong 里不订阅的普通节点不给 |

同一个 handler 绑定到多个 effect 时，各绑定推出的 Layer 必须一致。因此能力只按 handler 自己的类别和读取推出，不按它所处的控制流推出：普通原子操作放进 lifelong 不会多出能力，也就能在有限链与持续链之间复用。
