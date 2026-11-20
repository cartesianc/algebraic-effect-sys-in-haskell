# Next stages

<a id="stages"></a>
项目已进入 **prebeta**。手写业务代码的形态和已实现的运行语义构成 LSP 的基线。编辑器可以据此理解一个程序，后续涉及注册写法、handler 能力或可观察运行行为的变化仍须单独确认。

<a id="urgent"></a>
## Urgent stage · 持续资产按 x:xs 读取、资产固定形式与 alternative

五项均来自 2026-11-21 的设计讨论。**U1、U4、U5（同输入的 option）已实现（2026-11-21）**；U2、U3 按用户确认暂不实施，真 race 尚未实现。每项分三部分：“上下文”说明问题和代码证据；“已定”是用户确认的结论，实施时不再重新讨论；“待确认”是讨论中提出、尚未拍板的方案，动手前须逐条取得确认。五项都会改变注册写法、handler 能力或可观察运行行为，按工作约定须单独确认。`AGENTS.md`、[COMPOSITION](COMPOSITION.md#ad-hoc) 与 [STREAM_LIFELONG](STREAM_LIFELONG.md#contracts) 中“累计记录由业务资产表达、不设历史类型特例”的表述已随 U1 改为[按 x:xs 读取](STREAM_LIFELONG.md#flow)。

建议顺序：U1 → U2、U3（与 U1 共用运行时改动）→ U4（依赖 U1 去掉 `IORef`）。U5 与前四项独立。

<a id="urgent-flow"></a>
### U1　持续资产按 x:xs 读取（已实现）

**状态：已实现（2026-11-21）。** 当前规则见 [STREAM_LIFELONG：按 x:xs 读取](STREAM_LIFELONG.md#flow)。实施按下面的方案与分层表完成，未增加声明语法。三个 demo 同时去掉了只为承载 `IORef` 而存在的注册：LinesDemo 的 `TextCounter` 不再读 `OpenedInput`（Input 改为 Root），StreamDemo 删去 `SensorResource`，FacadeProbe 删去 `CounterA/B` 与 `FeedScopeA/B`。历史的回收按用户确认的暂行方案只做 end GC：来源停止且读取方全部离开时放掉（`Runtime/Session.hs` 的 `release`），没有容量上限，从不停止的来源保留到运行结束。流结束后的保存（[U2](#urgent-history)）与背压（[U3](#urgent-backpressure)）暂不实施。

**上下文（实施前）。** 当时的持续资产只实现了驱动，作为数据的一半没有实现。

- 会话已有读取 x:xs 所需的大部分结构：有序交付队列（`Runtime/Session.hs` 的 `stateEntries` 与绝对序号 `stateBase`），每个读取方一个游标（`Cursor`），`release` 按最小游标裁剪，`stateSignal` 用于等待，`stateStopped` 区分 `Drained` 和 `Broke`。但每次执行只推进一格。
- 生成的 `streamT`（`readStreamContext`）读本读取方游标位置的一条，`readT`（`readContext`）读整次运行共享的最新值。两者都只返回一个值，又都包装成同一个 `require`，handler 分不出来。
- 结果是计数、窗口、与前一条比较这类跨条逻辑都无法表达，只能把 `IORef` 放进资源资产绕过框架：`LinesDemo` 的 `InputFile`（`IORef Total`），`StreamDemo` 的 `SensorMemory`（`SensorLink` 拿它充当开启参数，它不是真正的资源），`FacadeProbe` 的 `FeedCounter`。`IORef` 没有 `Show`，于是 `Types.hs` 出现手写 instance。这类累计对 gen、静态图和 LSP 都不可见。

**已定。** 1–5 为第一轮结论，6–10 为第二轮结论。U1 没有待确认项，可以直接实施。

1. 持续资产是第三种资产，按 `x:xs` 读取：可以只读 `x`，必须能读 `xs`。
2. `require` 对值资产和持续资产都只读一次增量。
3. `streams` 声明读取持续资产，读到的是来源运行中、尚未结束的历史。
4. 未来部分的读取是惰性的：尾部在被需要时才生产。这一点属于 U2、U3 的范围，U1 不涉及。
5. 持续 Context 对 Stream `rawemit` 的解析必须落到这个结构上。
6. **`xs` 是过去。** 读取方在某次交付时拿到 `x :> xs`：`x` 是本次交付，`xs` 是同一会话中更早到达的交付，最新的在前。只执行一次的读取方，`x` 是它捕获的那一条。U1 的 `xs` 都已经发布，读取它不需要等待，也不拉动来源。
7. **声明不变。** 持续资产照旧写 `Asset @Line "TextLine"`。`stream = True` 就表示这个资产是 `Flow Line`、元素是 `Line`。不写 `Asset @(Flow Line)`，没有不兼容的语法改动。
8. **refine 做在元素上。** 照旧生成 `newtype TextLine = TextLine Line`。契约名标识“这一条流”，元素同为 `Line` 的两条流互不相通。`Flow` 的参数是 representational 角色，`Flow TextLine` 可以直接 `coerce` 成 `Flow Line`。
9. **demands 不变。** demands 里写的是契约名，不写 `Flow`。会话是否需要保留历史，由 gen 从 handler 方法体中的 `stream @T` 静态得出。
10. **不引入 HKT 或 DataKinds。** 资产形状只有“值”和“流”两种，而且是封闭的，业务代码从不需要对形状做多态。gen 按 `stream` 字段区分形状，再生成对应的能力实例。

业务可见的写法：

```haskell
-- Framework.Language.Handler，经 Framework.SDK 导出
data Flow a = a :> Flow a | Done
  deriving (Eq, Show, Functor, Foldable, Traversable)
infixr 5 :>

class Streams value m where
  stream :: m (Flow value)    -- 只给 demands 中以 streams 读取该资产的 effect
```

```haskell
-- LinesDemo：TextCounter 不再借用 InputFile 里的 IORef 计数
countText = do
  seen <- stream @Line                      -- 本次交付 :> 更早的交付
  rawoutput [show (length seen), show (sum [length text | Line text <- toList seen])]

printLine = do                              -- 只读增量的写法不变
  Line text <- require @Line
  ...
```

**实施方案。**

| 层 | 改动 |
| --- | --- |
| 源语言 `Language/Handler` | 新增 `Flow` 和 `Streams`，由 `Framework.SDK` 导出 |
| gen 形状 `Frontend/Shape` | 识别 `stream @T`，记作对表示类型 `T` 的历史读取 |
| gen 组合 `Composition` | 历史读取按与 `require` 相同的路由解析为对读取方法的调用，所以方法图不变。另外收集被历史读取的契约，只允许持续资产。这份契约列表进入组合缓存键，并在建图后标在生产该资产的 Context 上 |
| gen 接口 `Injector`、`Plan`、`Emit/Types` | 每个以 `streams` 读取的路由，在 Layer 中加上 `SDK.Streams T m`。这只由声明决定，首次生成契约时就已确定 |
| gen 输出 `Emit/Handlers` | 为持续资产生成历史读取入口，并为相应标签生成 `Streams` 实例，内容是对 `Flow` 做 `coerce` |
| 原型 `Prototype/Types` | `EffectProto` 新增 `effectHistory :: Bool`，默认 `False`，只在被历史读取的持续 Context 上为 `True` |
| 运行时 `Session` | 被标记的资产，会话从开头起保留全部交付，不随游标裁剪。交付视图从“只含本条”改为“历史开头到本条”。现有读取都只取视图的最后一条，行为不变 |
| 运行时 `Protocol`、`App`、`Context` | 新增历史读取：沿用现有的捕获与等待路径取得视图，把它倒序投影成 `Flow` |

代价：被标记资产的会话会在整个生命周期内保留全部交付。没有 `stream @T` 读取的资产不受影响。

**验收。** 三个 demo 去掉 `IORef` 和手写 instance，计数、窗口、编号都改用 `stream @T` 读取历史完成。8 个命名空间重新生成，`cabal build all` 无警告，`scripts/check.ps1` 通过，LinesDemo 的统计输出与改动前一致。完成后更新 STREAM_LIFELONG、GUIDE、COMPOSITION 和 `AGENTS.md` 中的相应表述。

<a id="urgent-history"></a>
### U2　流结束后的 history 保存

**上下文。** COMPOSITION 中的 history 指流结束、会话退役并回收之后，数据仍由另一个位置保存下来，供后来的读取方使用，此时可能还没有消费链读过它。现行规则让托管派生在首次登记时“从当时最新一条开始”（`attachReader`，见[有限读取](STREAM_LIFELONG.md#production)），登记晚于发布时，history 会丢失。

**已定。** 有两层历史：运行中的 `x:xs` 由 U1 提供；流结束后的保存属于组合关系。2026-11-21 用户确认：目前流结束后历史随 end GC 放掉即可，保存者暂不实施；下面的方案保留待以后确认。

**待确认。**

- 保存者是 `stream = False`、且 Input 链上有 `streams` 的 Context。链上的 Excu 执行一次，用 `stream @T` 从开头走完整串，结果由这个 Context 解析成一份值资产。现行规则“`stream = True` 当且仅当 Input 链上有 `streams`”（[注册](CORE_DESIGN.md#registration)）会拒绝这个组合，需要放开。
- gen 静态识别保存者，在来源会话开始时就接入它，从第 0 条读取。它作为正常读取方计入背压。保存下来的值是普通资产的最新绑定，保留到 interpreter 退出。读取方用 `requires` 读这份值，不登记位置。
- 同一个流在不同会话（lifelong 会话和托管会话）各跑一次时，保存者怎么对应，还没有定。

<a id="urgent-backpressure"></a>
### U3　背压随 U1 收窄

**上下文。** 见下文[持续交付的背压](#backpressure)。

**已定。** U1 的 `x:xs` 惰性求值。由此，单读取方和无读取方两种情形自然解决：没有需求时来源停在 `rawemit`，托管会话也不再在有限读取返回后继续生产。2026-11-21 用户确认：U1 实现的是只读过去的 `xs`，历史保留暂行靠 end GC 回收，惰性尾部与背压暂不实施。

**待确认。**

- 多读取方：有读取方要第 n 条、且最慢读取方落后不超过 k 条时，才发布第 n 条，否则 `rawemit` 挂起。k 的默认值，以及能否在注册中声明，都还没有定。
- 已声明但尚未启动的读取方不计入背压，只让会话保留它要读的那段历史。否则排在 lifelong 之后、读取整串的节点会让来源停住，lifelong 结束不了，这个节点也就永远不会启动。在它启动前缓冲会增长，gen 可以对“排在持续来源的 lifelong 之后读取整串”给出警告。
- 已离开、未注销的读取方要及时从位置表中移除，沿用现有的读取方离开与撤销待用机制。

<a id="urgent-assets"></a>
### U4　资产的固定形式（已实现）

**状态：已实现（2026-11-21）。** 当前规则见 [ASSETS：固定形式](ASSETS.md#fixed-form)与[指南：资产书写](GUIDE.md#types)。用户确认：一切资产本质上都是不同形式的 `String`；固定形式之外的资产由 gen 在生成期报错（`Gen/Check/Assets.hs` 的 `checkFixedForm`，检查 `程序名.Types` 模块和全部 `Asset @T` 的表示类型）；没有资源资产这一类：文件句柄等 OS 对象只在 handler 自己的执行中持有，作为 handler 本身由运行时持有，不作为资产被持有。

- demo 随之改写：数字字段保存原文本、读取方在 handler 中解析（LinesDemo `Total String String`，StreamDemo `Temperature String`、`Tick String`，FacadeProbe `LineCount`／`Level`）；资源资产只记路径（FileDemo、FacadeProbe、LinesDemo、OpenFilesDemo、ScopeInstancesDemo、ScopeReuseDemo），读写的 handler 按路径打开文件；Crawler 去掉 `Generic`。
- OpenFilesDemo 与 ScopeInstancesDemo 原本检查真实 `Handle` 是否开着，改为由 Scoped 的 open 侧（资源 Context）创建、close 删除文件旁的 `<path>.open` 标记，检查语义与输出保持不变。ScopeReuseDemo 的三个写入者重叠时同时追加同一文件，GHC 的单进程文件锁会让后到者报 `resource busy`，写入者在方法体内局部重试。
- 限制：`Asset @T` 的 `T` 来自 `Typeable`，`FilePath` 等 `String` 同义词无法区分，按 `String` 接受；`Types.hs` 的字段按源码文本检查，必须写 `String`。下文“`Flow T`”的写法未采用，持续资产仍用 `Asset @T` 加 `stream = True`。LSP 的 DTO 协议本身不在本项范围内。
- 验证：重新生成全部 8 个命名空间，`cabal build all` 无警告；`scripts/check.ps1 -Skip crawler-demo` 全部通过（crawler-demo 需要网络，未运行；构建通过），FacadeProbe 按其 README 单独编译运行，输出与改写前相同。

**上下文（实施前）。** LSP 要把 before-gen 的资产声明双向转换成 DTO，需要一种可以唯一解析的写法。现在 `Types.hs` 允许 instance，资产的表示类型可以带 `IORef` 和 `Handle`。

**已定。**

- instance 不属于资产。资产是由 `String` 或 `[String]` 构造的值。
- LSP 只对 before-gen 的声明做 DTO，不对运行时内存做 DTO。
- LSP 能解析的固定形式由 LSP 协议规定。gen 能接受但不在固定形式内的手写代码仍然允许，LSP 只读展示。

**待确认。**

- 固定形式：
  - `Types.hs` 只写 `data` 和 `newtype`，固定 `deriving (Eq, Show)`，模块导出全部类型及构造器，不写 imports；
  - 字段类型只能是 `String`、`[String]` 或本模块的另一个表示类型；
  - 资产类型写成 `T`（值资产）或 `Flow T`（持续资产），`T` 可以直接是 `String` 或 `[String]`；
  - 不允许 instance、`type` 同义词、类型参数、GADT 语法、严格标记和中缀构造器。
- 现有 demo 有数字字段：`Total Int Int`、`Temperature Int Double [Double]`、`Level Int Int`，以及 `Asset @Int "Beat"`。要么改成 String 系，要么把 `Int`、`Double` 加进字段类型。
- `Handle` 这类真正的外部对象和来源游标，是否保留为单独一类资源资产，只给描述、不进 DTO。
- 由 gen 拒绝固定形式之外的资产，还是只在 LSP 协议里区分。

<a id="urgent-race"></a>
### U5　alternative 改为 race（同输入的 option 已实现）

**状态：同输入的 option 已实现（2026-11-21）；真 race 尚未实现，gen 拒绝。** 当前规则见[主设计：alternative 的依据](CORE_DESIGN.md#workflow)与[指南：alternative](GUIDE.md#workflow)。用户确认先做同输入的 option，和类型与分支契约整体删除（`SumTypes`、`effectBranches`、`BranchContract`、`CaseNotSelected`、`projectContext` 均已移除）。

- 静态（`Gen/Booter.hs`、`Prototype/Query.hs` 的 `candidateCases`）：各候选恰好 `requires` 一份由同一个 Excu 的输出直接或经 Pure 解析出的非持续资产，这些资产的 Context 互不相同；共同的 Excu 必须唯一；同一个 Excu 上的多个 alternative 必须判定同一组 Context。`AlternativeProto` 记录 `alternativeSource`（该 Excu）与 `alternativeCases`（候选 → 判定 Context）。
- 运行（`Runtime/Context.hs` 的 `chooseCase`）：执行一次该 Excu，把同一份原始输出按候选声明顺序交给各 Context 解析（`attemptOutput`），第一个成功的候选启动。判定 parser 的 `raise` 只表示这一支没有值，不是失败。都没有值时按 require 的等待协议等待任一判定 Context 发布，先有值的候选启动；已证明生产机会耗尽仍没有值时按普通缺值报 `ContextNotInitialized`（用户确认，2026-11-21：race 的本质是等值再分支，没有值就等待）。能等谁由 gen 确定：`Gen/Composition.hs` 的 `resolveSources` 为每个选择读取的判定资产登记 ReadPoint，来源是其他能到达该 Context 生产入口的链，选择链自身不算；没有其他来源时为 `FromOwnChain`，运行时不等待。
- demo：FileDemo 的 `TextState` 改为 `ReadFile` 下的 `BlankText`／`FilledText`；FacadeProbe 的 `FileState` 改为 `InspectReport` 下的 `ReportBlank`／`ReportFilled`。两个分支都实测过。
- 等待路径的验证（临时探针，未提交）：两个判定 parser 第一次都不成立、并行分支 1 秒后再执行同一 Excu 并解析成功时，选择读取等待后选中对应候选（连跑 3 次）；没有其他来源时立即报 `ContextNotInitialized`（0.16 秒）；并行的另一处也解析不出值时，等它结束后报 `ContextNotInitialized`。
- 未覆盖：选择时执行该 Excu 所处的帧内，该 Excu 下其他锚定的 Context 不随之注入；真 race（不同上游、按时序）、输家取消与 scope 收尾、lifelong 中的真 race 均未实现。

**上下文（实施前）。** 现在的 `alternative` 按和类型资产的当前构造器选择候选（[workflow](CORE_DESIGN.md#workflow) 的类型边界），所以标准资产里必须有和类型。`FileDemo` 中，`ReadFile` 的输出被解析成 `TextState = Blank | Written String`，`WriteFirstLine` 和 `AppendLine` 分别 `requires` 两个分支契约。`FacadeProbe` 的 `FileState` 也是这样。

**已定。** `alternative` 的依据是 effect 的差异，而不是细化资产的差异。在 effect 图中，取各候选链从 Root 起的共链段，在最短的差异位置之下，谁先有值就走哪条分支。option 是 race 的特例，race 不一定是 option，所以用 race 表达更强。和类型因此不再是 `alternative` 的必需条件。

**待确认。**

- 差异位置要把 demands 的生产链算进去，不能只看 Input 链。`FileDemo` 两个候选的 Input 都是 `FileSession`，差异在它们各自读取的资产由谁生产。改写后，`ReadFile` 的同一份输出挂两个 Context：一个只在内容为空时成功，另一个只在内容非空时成功，`TextState` 随之删除。
- gen 静态区分两种情形：分叉的各支解析**同一份上游输出**时是 option，按声明顺序取第一个成功的分支，结果确定，不依赖时序；分叉的各支来自**不同上游**时是真正的 race，按时序决定。建议先实现同输入的情形，它覆盖现有两个用例。
- 输掉的分支 `raise` 只算放弃，不向外传播。全部放弃时，race 失败，报声明顺序中的第一个失败。诊断要列出每个分支各自的原因，因为赢家的真实错误和放弃看起来一样。
- 静态保证变弱：和类型能在生成期保证覆盖完整、互斥，race 只能在运行时知道。
- 作为判定条件的 parser 是否必须不做 IO。真 race 中输家已经执行的 IO 不回滚，赢家确定后要取消输家，并关闭它打开的 scope。这是现有“未选候选从未启动”之外新增的收尾路径。
- lifelong 中每条交付都做一次判定。同输入的情形可以直接沿用，真 race 遇到持续来源时单独设计。

<a id="code-shape"></a>
## LSP 从哪份代码开始

LSP 面向开发者手写的 `Types.hs`、`Effects.hs`、`Handlers.hs`、`AST.hs` 和可选的 `Hanging.hs`。例如，定位一处 `require @T` 时，要结合当前 handler 的 effect 绑定和它声明的 demand；同一个 handler 可以被多个 effect 复用。Haskell 类型由 GHC 检查，资产来源和装配规则由 gen 确定。代码形态见[开发指南](GUIDE.md#code-shape)，已有的生成结果见[资产目录](ASSETS.md)与[静态图](EFFECT_GRAPH.md)。

<a id="middleware"></a>
<a id="superhandler"></a>
<a id="hanging-tree"></a>
### Middleware 的覆盖边界

当前 `intercept` 支持 Excu、Scoped、Pure 和 Stream 四类。`Hanging.hs` 指定生效分支，`hook` 读取到达该位置的操作。例如 parser 的 `rawinput` 可以触发上游类别的读取通知，parser 构造的业务 ADT 则没有单独的捕获点。扩大 effect 类别的覆盖时，先明确要观察的操作及其归属。[Middleware 写法](GUIDE.md#middleware)

<a id="deferred"></a>
## 留给后续的两个 SDK 专题

<a id="backpressure"></a>
### 持续交付的背压

慢消费者尚未领取的交付仍然可达，积压可以持续增长。这个专题要确定容量按什么计量、生产在哪一步等待，以及最后一个订阅者离开时如何唤醒生产方。一个必须处理的例子是同单元先发布、后领取：如果发布因容量已满而等待，后面的领取可能永远无法运行。设计时要保住已发布值的顺序、取消与排空，并让已有 scope GC 继续负责资源关闭。[U3](#urgent-backpressure) 中的惰性 `x:xs` 会把这个专题收窄为多读取方之间的容量策略。[交付保留](STREAM_LIFELONG.md#retention) · [资源交接](STREAM_LIFELONG.md#binding-retention)

<a id="ast-nesting"></a>
### AST 嵌套与 workflow 边界

现有 `chained`、`parallel` 和 `alternative` 可以嵌套，也可以放在 `lifelong` 内。gen 目前拒绝在 `lifelong` 的后代中再次挂载 `lifelong`。嵌套持续执行单独设计。以「每份订单启动一条消息流」为例，需要决定外层何时能接下一单、内层结束或取消传到哪里、哪个执行帧持有订阅和 scope。[静态规则](STREAM_LIFELONG.md#static) · [执行边界](STREAM_LIFELONG.md#execution-boundaries)

<a id="review"></a>
<a id="current-limits"></a>
## 使用 prebeta 时应知道的边界

- 含 `lifelong` 的程序仍按整次运行传播失败。普通 `require` 的等待结束与生成期缺值诊断只覆盖可证明的情形。[失败协议](STREAM_LIFELONG.md#failures) · [缺值诊断](EFFECT_GRAPH.md#missing-source)
- 待交付值和固定捕获按 Binding 已有的 ownership 保留资源。ScopeTree 对 Input 的依赖采取保守判断，长期存活的子实例可能连带保留先前共同使用的父实例。[资产保活](STREAM_LIFELONG.md#binding-retention) · [父引用边界](EFFECT_GRAPH.md#scope-parent-retention)
- 来源状态和 scope 路径仍可能随组合数量指数增长。现有示例覆盖常用路径，长期堆占用、高负载和跨平台取消的验证范围有限。[图与来源](EFFECT_GRAPH.md) · [会话保留成本](STREAM_LIFELONG.md#retention-cost)

<a id="baseline"></a>
## 已交付的设计去哪里查

Stage 1–7 在各自已确认的范围内完成。生成、编译和现有 demo 的回归方式见[开发指南](GUIDE.md#development)，历次验证记录保留在 Git 历史。

| 能力 | 现行规范 |
| --- | --- |
| <a id="stage-1"></a><a id="stage-2"></a>细化资产与原子 handler 复用 | [读取约束](CORE_DESIGN.md#demand-contract) · [入口装配](CORE_DESIGN.md#calls) |
| <a id="stage-2-await"></a><a id="stage-4"></a>共享供值与固定捕获 | [普通读取](CORE_DESIGN.md#await-visibility) · [持续读取](STREAM_LIFELONG.md#contracts) |
| <a id="stage-3"></a><a id="stage-6"></a><a id="stage-6-reuse"></a>持续驱动、结束与同次输出复用 | [执行边界](STREAM_LIFELONG.md#execution-boundaries) · [消费结束](STREAM_LIFELONG.md#consumer-end) · [派生与复用](STREAM_LIFELONG.md#derive) |
| <a id="stage-5"></a><a id="stage-7"></a><a id="scope-gc"></a>持续资产保活与 scope 回收 | [资源交接](STREAM_LIFELONG.md#binding-retention) · [可达性回收](CORE_DESIGN.md#scope-gc) |
| <a id="pure-pipeline"></a><a id="version-boundaries"></a>原子输入输出与 gen 分工 | [Pure 与原子输出](CORE_DESIGN.md#pure) · [编译器与 runtime](CORE_DESIGN.md#compiler) |

<a id="maintenance"></a>
本页只跟踪已选定的工作。正式协议和已实现写法分别维护在[主设计](CORE_DESIGN.md)与[指南](GUIDE.md)。
