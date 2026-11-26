# Next stages

<a id="stages"></a>
项目已进入 **prebeta**。手写业务代码的形态和已实现的运行语义构成 LSP 的基线。编辑器可以据此理解一个程序，后续涉及注册写法、handler 能力或可观察运行行为的变化仍须单独确认。

<a id="urgent"></a>
## Prebeta 的持续读取、资产与分支选择

这次合入 `main` 的变更确定了三处业务写法。LSP 可以按下表识别现行程序，延期项单列在表后。

| 阶段 | 已实现的业务写法与检查 | 规范与示例 |
| --- | --- | --- |
| <a id="urgent-flow"></a>U1 持续读取 | 注册仍写 `Asset @Line "TextLine"`。消费方声明 `streams "TextLine"` 后，`require @Line` 读本条，`stream @Line` 读本条及更早发布的固定前缀。gen 根据方法体对历史的实际读取标记来源。 | [读取与保留](STREAM_LIFELONG.md#flow) · [LinesDemo](../demo/LinesDemo/Handlers.hs) |
| <a id="urgent-assets"></a>U4 资产表示 | `Types.hs` 定义由字符串构成的单构造器类型。gen 核对注册使用的定义模块和编译单元；重导出的同一类型有效，其他模块的同名类型不能替代它。 | [固定形式](ASSETS.md#fixed-form) · [FileDemo](../demo/FileDemo/Types.hs) |
| <a id="urgent-race"></a>U5 同一输出选分支 | `alternative` 按候选顺序让判定 parser 尝试同一次 Excu 输出。若全部拒绝，选择读取检查已有绑定；没有时按 [C1](#closure-1) 等待别的分支发布，否则报缺值。 | [选择与交接](CORE_DESIGN.md#alternative-selection) · [来源证明](EFFECT_GRAPH.md#missing-source) |

**从旧版迁移。** 旧版将多个状态写成一个和类型，再用分支契约投影给候选。现在给同一份原始输出挂多个 Context，每个 parser 构造自己的单构造器资产，候选用 `requires` 写出所需资产。旧的 `SumTypes`、`BranchContract` 和 `projectContext` 已移除。[FileDemo 的完整写法](GUIDE.md#workflow)

**已有验证记录（2026-11-21）。** U4 重新生成了八个命名空间并通过构建。同名 `FileHandle` 来自另一模块时 gen 拒绝，重导出原类型时生成结果相同。FileDemo 的空文件与非空文件分别命中对应候选。选择入口的等待探针覆盖了其他位置稍后发布，以及该位置结束后仍无值两种结果。

<a id="urgent-history"></a>
**U2 结束后的完整历史保存：由 history 组合给出（2026-11-24）。** lifelong 之外以 `requests` 启动的 interpreter 托管会话结束后不放掉历史，之后的 `stream @T` 仍读到整段；lifelong 内的 socket 会话仍在来源停止且读取方离开后释放历史前缀，后继用 `requires` 读最后一条。[驱动方式的组合](STREAM_LIFELONG.md#drives) · [会话保留规则](STREAM_LIFELONG.md#retention)

<a id="urgent-backpressure"></a>
**U3 背压暂缓。** `x :> xs` 的尾部是已经发布的过去。消费方遍历它时，上游可以继续生产；队列容量和按需求暂停生产仍在[背压专题](#backpressure)讨论。

**不同上游之间的 race 暂缓。** 当前 gen 要求候选共享一个判定 Excu。若引入不同生产链竞争，还须确定胜者、输家取消和已执行 IO、scope 的收尾规则。这些选择不属于已实现的 U5。

<a id="request-chains"></a>
## requests 剧本化

消费链按剧本编译：`requests` 是前驱，`requires` 是被动读取。运行时的资产匹配提前到 gen 期。以下语义由用户确认，完成于 2026-11-21。

| 阶段 | 已实现 | 规范 |
| --- | --- | --- |
| <a id="request-phase-1"></a>R1 requests 前驱 | gen 把被请求资产唯一的生产链展开进请求方入口；每个请求方每次执行各走一遍，成功值写入该资产的当前值。`requires` 只读这个值，被读取的普通资产必须有 effect `requests` 它（`Asset never requested`）。句柄单独执行不再注入挂在它下面的普通 Context（2026-11-24 由 [O1 输出联立](#output-link-1)恢复为 gen 期闭包）。alternative 候选只 `requires` 自己的判定资产。 | [requests 与输出联立](CORE_DESIGN.md#request-production) · [Crawler](../demo/Crawler/Effects.hs) |
| <a id="request-phase-2"></a>R2 运行时按身份寻址 | interpreter 启动时一次建索引。资产与 scope 按 gen 分配的 effect 编号存取，生成入口直接写出编号；执行位置按先序坐标寻址，子树判断是一次区间比较。普通 Context 的注入代码与 gen 中对应的分析分支已删除。 | [运行索引](CORE_DESIGN.md#request-production) |

<a id="request-phase-3"></a>
**R3 持续资产。** 对持续资产 `requests` 启动或加入它的会话，取当前一条固定给本次调用；`requires` 只读已有会话，不再启动会话，没人 requests 也没人 streams 的持续资产同样报 `Asset never requested`。此前 lifelong 边界的查找顺序在 gen 期排好。lifelong 订阅与 `ReuseOutput`（持续 Context 复用 lifelong 消费节点的同次输出）保留原协议。[持续资产的 requests](CORE_DESIGN.md#request-production) · [有限读取](STREAM_LIFELONG.md#finite-read)

<a id="request-phase-4"></a>
**R4 消费链与生产分支。** requests 的资产生产链上的 Excu／Scoped（锚点）注入为请求方的前驱，与声明的 Input 合并后约简，Pure 与 Context 是从锚点分出的生产分支；同一次调用中同一 effect 只执行一次，挂在同一锚点下的多份资产共用一次执行。互不在对方上游的父节点之间没有依赖，执行顺序只取声明顺序。[消费链与生产分支](CORE_DESIGN.md#consumer-chain)

**编辑器读剧本。** `effect-codegen console` 的每个 binding 带 `before`（入口在方法体前依次执行的 input、anchor、requests、session 步骤）与 `raw`（rawinput 读到的原子调用）。`chains` 按 Excu／Scoped 给出约简后的父节点（`via` 为 `input` 或 `anchor`）与生产分支（`anchor`、自锚点之下的 `steps`、`session`），编辑器直接据此画消费链与生产分支，不必从注册重新推导。

**运行时仍按名字查的位置。** 这些查找都不在资产读写路径上：

- 原子句柄的回放表，只在持续注入和选择判定期间使用；
- alternative 选中后按 Context 名找候选分支，每次选择一次；
- 会话步骤按标签取入口，每个会话启动一次；
- Error 回调登记与 `Failure` 记录，属于诊断展示。

requests 展开的前驱作为请求方入口里的静态代码执行，运行时没有它们各自的坐标。

<a id="output-links"></a>
## 输出联立与持续执行的组合多态

**状态：已实现（2026-11-24），分支 `feat/output-injection-and-stream-modes`。** 用户确认以下语义，两部分在同一分支完成。

| 阶段 | 语义 | 工作计划 |
| --- | --- | --- |
| <a id="output-link-1"></a>O1 原子输出联立 | 锚点（Excu／Scoped.open）在任何位置执行，挂在它下面的生产分支（一串 Pure 与 Context）都读这次输出，成功值写入运行级最新值表；不只在 `requests` 时更新。生产分支是纯内部函数：Pure 与挂在锚点下的 Context 不能声明 demands。只给有人读取的分支挂闭包；alternative 的判定资产不注入，仍由选择读取生产。注入中的解析失败一律 raise，沿原链传播并停止程序（Error effect 完成前的处理）。被 `requires` 的普通资产有 requests，或锚点由 workflow 执行并注入时都合法。 | Composition：声明检查（分支无 demands）、`checkRequested` 放宽、来源分析恢复普通注入；Booter：`OutputConnection` 恢复普通角色并按读取筛选；Emit：入口包装带上普通分支；Runtime：`atomicScope` 注入普通分支，失败不吞；Crawler 由锚点把 URL 放进原始输出。 |
| <a id="output-link-2"></a>O2 持续执行的组合多态 | 由 Stream effect（S）、stream 资产（A）与 lifelong（L）的组合决定：S+A+L 是 socket（每次 `rawemit` 唤起，不去重，结束时 GC 历史）；S+A 不在 lifelong 是 history（`requests` 启动，结束后保留整段历史）；S 而资产非 stream 是 behavior（第一次 request 启动生产，值按相等去重；lifelong 内值变化才唤起，lifelong 外只采样最新值）；没有 S 与 A 而在 lifelong 内 `requests` 普通资产是 event（O1 的每次发布唤起，不回放订阅前的发布，照常写最新值表）；没有 S 而资产是 stream 仍非法。lifelong 内 `requests` 是订阅，`requires` 是采样；event 位置已有交付时不再执行生产链；订阅单元自己执行该资产锚点时 gen 拒绝。 | Composition：按 S/A/L 判定并放开 lifelong 内的 requests 端点；Booter：event 会话计划与自激检查、behavior 会话计划；Runtime：event 会话接收注入发布、behavior 会话去重并只交付最新值、history 会话结束后不 GC；文档：STREAM_LIFELONG、CORE_DESIGN、COMPOSITION、GUIDE。 |

**验证（2026-11-24）。** `scripts/check.ps1` 重新生成八个命名空间并编译运行全部 demo：O1 之后只有 Crawler（地址随抓取输出交给 parser）与挂接入口的生成结果变化，O2 之后现有 demo 的生成结果不变，七个 demo 均通过（crawler 需要网络）。在仓库外用 `--source-dir` 生成并运行了一个覆盖四种组合的探针：event 订阅方在每次锚点执行后被唤起一次、未重跑生产链并以 `endStream` 结束；只 `requires`、不 `requests` 的读取方读到联立发布的最新值；behavior 来源依次发出 `1 1 2 2 2 3 3` 时订阅方只被 `1 2 3` 唤起，lifelong 外采样到最新值；history 在来源结束后的第二个读取方仍读到整段。

**未覆盖。** event 订阅方不调用 `endStream` 而锚点不再执行时 lifelong 一直等待，按约定由业务负责；event 自激的拒绝只检查订阅 lifelong 内的 target、Input 链与直接 `requests`，不追踪更深的 requests 传递闭包；behavior 去重只比较相邻两次发布；联立中的解析失败暂按停止程序处理，待 Error effect 设计后细化。

<a id="closure-model"></a>
## 闭包模型：执行控制收回 gen 期

**状态：已实现（2026-11-24），分支 `feat/output-injection-and-stream-modes`，未合入 main。** 用户确认：handler 是不带参数的类方法，effect 之间的组合关系由 gen 在编译期编成执行闭包；运行时只执行闭包，不调度 handler、不在 handler 之间转运数据、不判断值将来会不会来。唯一的并发是 AST 显式写出的 `parallel`。lifelong 是交给 gen 的标记，帮助生成闭包，本身不是一个服务。此前的实现把 handler 当成由运行时解释器调度的函数（会话队列、消费线程、缺值等待与耗尽证明），本阶段整体改写；O2 中建立在会话上的 event 与 behavior 一并重做。

| 阶段 | 语义 |
| --- | --- |
| <a id="closure-1"></a>C1 取值 · 未就绪时等待 | `require @T` 读本次调用的固定捕获或运行级最新值；有值就继续。没有值、但别的 `parallel` 分支仍可能发布时，只挂起这一次调用，发布后从读取点继续一次；没有这样的分支（或分支都已退出）时报 `ContextNotInitialized`。各分支可能发布的资产由 gen 写在 `Concurrent` 闭包上，运行时不做来源推导。gen 只做来源检查：资产有 effect `requests`，或挂在锚点的 rawoutput 下（输出联立），或是持续资产；不检查可达性。alternative 的判定全部拒绝时按同一规则等待。删除耗尽证明和来源固定点的拒绝。（2026-11-24 修订：初版误作“缺值立即失败”，见 [require 的等待](#closure-await)。） |
| <a id="closure-2"></a>C2 发布即回调 | 资产每次发布后，gen 写好的订阅回调在发布方的调用栈里同步执行，按 lifelong 单元的声明顺序。socket：Stream 每次 `rawemit` → parser 发布 → 回调订阅单元；派生：上游发布 → 派生 parser 链发布 → 回调；复用输出：锚点执行 → 挂接的持续 parser 发布 → 回调；event：锚点的输出联立发布 → 回调；behavior：parser 发布的值与上一次相等时不回调。一次回调是单元的一次执行（登记的单元有新的执行帧，见[回收无关的单元](#untracked-units)），本次发布作为固定捕获交给单元，`stream @T` 读到本条为止的历史。没有会话、交付队列、游标和消费线程。 |
| <a id="closure-3"></a>C3 lifelong 是标记 | gen 按 lifelong 生成回调表。执行到 lifelong 的位置时只做一件事：有 Stream 来源时同步运行它，来源 `streamEnd` 或订阅方全部 `endStream` 后返回；没有 Stream 来源（只有 event 订阅）时什么也不做。一个 lifelong 至多一个 Stream 来源：参照 Effect-TS 的并发须显式，多个独立来源写 `parallel [lifelong [...], lifelong [...]]`。单元内的 target 由同一份资产驱动。event 回调在整次运行中有效，直到订阅方 `endStream`；socket、behavior 与派生回调只回应所属 lifelong 作用范围里的发布。 |
| <a id="closure-4"></a>C4 lifelong 外的持续资产 | `requests` 不再取持续资产的“当前一条”。lifelong 外 `requests` 一份持续资产就是要一份静态历史：第一次 `requests` 在当前位置同步运行来源（及派生链）直到 `streamEnd`，之后 `requires` 读最后一条，`streams` 读整段；同一次运行只跑一次，历史保留到运行结束。lifelong 内不能 `requests` `stream = True` 的资产，订阅它要写 `streams`。behavior 只在 lifelong 内回调；lifelong 外同样跑到结束后读最新值。 |
| <a id="closure-5"></a>C5 回调环 | 订阅回调经自身的执行（target、Input 链、`requests` 的传递闭包、输出联立、持续挂接、派生）可能再次发布它订阅的资产时，回调会无限递归。gen 在“资产 → 回调可能发布的资产”图上查环并拒绝，取代原 event 自激检查和同单元的路径覆盖规则。 |
| <a id="closure-6"></a>C6 IR 即闭包 | gen 在 `Generated/Program.hs` 写出组合好的 workflow 闭包（顺序、并行、选择、来源运行）和回调表；interpreter 只核对 AST 与原型一致，在运行开始时把这些闭包数据编成执行函数一次，然后执行它，不在运行期遍历 Prototype 编排，也不按坐标查询来源计划（见[每次调用的执行路径](#call-path)）。输出联立由 gen 生成的调用序列完成，不在运行时改写调用者状态。 |

**实现。**

- **Gen**：Composition 删除来源固定点的拒绝（`checkReadSupply`、`successorRead`），只保留来源检查。Booter 删除 Listen 与等待相关的启动、覆盖检查，按 lifelong 计算单元的驱动资产，拒绝一个单元由多份资产驱动、一个 lifelong 有多个 Stream 来源、lifelong 内 `requests` stream = True 的资产，并在编号后用 `checkReactions` 查回调环。回调交付的资产不计入回调自身 `requests` 的传递闭包，因为那里读的是交付。
- **Emit**：`Generated/Program.hs` 写出 `compiledProgram`，包括 `compiledWorkflow`（`Step`／`Serial`／`Concurrent`／`Choose`／`Drive`）、`compiledReactions`（资产 → 单元或派生步骤，作用范围为整次运行或某个 lifelong）和 `compiledStatic`（lifelong 外的根来源）。behavior 的比较函数在生成代码里写成表示类型的相等。`Generated/Handlers.hs` 的输出联立写成 `atomicHandle`／`atomicScope` 的闭包分支；`requests` 的生产链包在 `unlessPerformed` 里，回调里交付的资产已记为发布，生产链不再执行。
- **Runtime**：Session 换成 [Delivery](../sdk/Framework/Runtime/Delivery.hs)，只剩交付视图与两个结束信号。`publishBinding` 在发布者调用栈里同步调用 `Graph.react`。Execution 的 `runCompiled` 只执行闭包：`Drive` 同步运行来源到结束或订阅方全部 `endStream`，再丢弃该 lifelong 的历史；静态运行按根来源记忆，历史保留到运行结束。`readContext`、`chooseCase` 与持续读取按 C1 等待。删除的有会话队列、消费线程、`contextMayPublish`、`unlessDelivered` 与输出回放。
- **Demo**：StreamDemo 与 FacadeProbe 的多来源 lifelong 改为 `parallel` 的多个 lifelong。

**验证（2026-11-24，仓库外的探针与本地回归，记录不进仓库）。**

- event：`chain [lifelong [Watch], Tick ×4, Peek]`，没有 `parallel`。每次 Tick 后同步打印一次 Watch，计数 3 时 `endStream`，第 4 次 Tick 不再唤起，共 4 次 Tick。Peek 只 `requires`，读到最新值 4。
- behavior：Sensor 发出 `1 1 2 2 2 3 3`，lifelong 内的 ShowLevel 回调 3 次（1、2、3）。
- 静态历史：lifelong 外 SampleLevel 读到 3；ReadAll 与 ReadAgain 都读到整段 `["c","b","a"]`，来源只运行一次。
- `scripts/check.ps1`：file、open-files、scope-reuse、scope-instances、lines、stream 通过。crawler 需要网络，本次未覆盖。lines 的输出显示同步回调：每行打印后立即打印累计。

<a id="closure-await"></a>
**require 的等待与两项修正（2026-11-24 修订）。** 合并前评估指出三处问题，设计者确认 `require` 的契约是“取值 · 未就绪时等待”。

- **等待**：gen 用 `Booter.publishedWithin` 为 `parallel` 的每个分支计算它执行期间可能发布的资产（节点与选择读取的执行、`requests` 闭包、输出联立、lifelong 的持续资产及其来源与 parser 入口执行时可能发布的资产，例如 Stream 来源 `requests` 的普通资产；持续资产总是从根来源开始生产，因此还包括驱动它的上游资产，例如静态 `requests` 派生资产 `RunningTotal` 会发布根资产 `TextLine`；再沿回调表取传递闭包），写成 `Concurrent [(slots, closure)]`。运行时在分支开始前登记、退出时撤销，每次执行带着自己所在的分支（`Place`）。`require`、`stream @T` 与 alternative 全部拒绝后的读取缺值时，先取发布编号再查值：编号已变就重查；仍有别的分支可能发布就挂起，发布或分支退出后重查；没有就报缺值。读取方自己所在的分支不计入，`chain [read, produce]` 不会自等。诊断、收尾、close 与资源读取不等待。回调继承发布方的分支。
- **互相等待按缺值处理**：运行时用 STM 记录执行中的线程数（根线程与 parallel 的各分支，不含等待子分支的父线程）和其中挂起的线程数（等待 require 的，以及等待别人的共享静态运行结束的）。所有执行中的线程都挂起时，没有线程还能发布，等待 require 的一方报 `ContextNotInitialized`；它所在的分支退出后，其余等待者重查，没有可能的发布者时同样报缺值。两个分支都先读后产同一份资产时，因此以 `ContextNotInitialized` 结束，而不是被 GHC 报 `BlockedIndefinitelyOnMVar`。
- **计数不留空档**：发布与分支变化在同一事务里放行全部等待 require 的线程并清零它们的计数，已放行而尚未调度的线程不会被当作仍在等待；最后一个子分支退出时把执行名额直接交还父线程，汇合后的生产者在任何时刻都计为执行中；共享静态运行结束时在同一事务里放行等它的调用。因此无环的生产链不会被误判为互等。
- **作用范围的读取分开**：每个 lifelong 与每个静态运行各自保存持续资产的发布：`stream @T` 读取的保存整段，其余只保存本作用范围的最后一条。来源开始与 `Drive` 结束时放掉自己的一份。静态运行的读取只读本作用范围：一条都没有发布就是缺值，不拿 lifelong 或别的运行的值顶替。普通 `requires` 仍读本次捕获或运行级最新值。
- **behavior 的比较按作用范围分开**：上一次回调的值按（资产，作用范围）保存，每次来源运行重新开始。回调只回应自己作用范围里的发布。

验证（仓库外探针）：

| 用例 | 结果 |
| --- | --- |
| `parallel [Reader, Publisher]`，读取先于发布（Provider 在 `getLine` 等 1.5 秒后的输入） | `reader entered`，随后 `resumed: ready`，`Succ` |
| `chain [Publisher, Reader]` | 直接读到值，`Succ` |
| `chain [Reader, Publisher]` | 没有别的分支可能发布，立即 `Failed`（`ContextNotInitialized`），不挂起 |
| 同一来源 4 行：静态读取 → lifelong 累计 → 再静态读取 | `4`、`1/2/3/4`、`4` |
| `parallel [chain [Reader], lifelong [Sink]]`，Sink 的 Stream 来源 `requests "Value"`，Provider 在 `getLine` 等 1.5 秒后的输入 | 生成的分支槽含 `Provider`；`reader entered`、`sink: tick`、`resumed: ready`，`Succ` |
| `chain [lifelong [Sink], chain [Reader]]` | `sink: tick`、`reader entered`、`resumed: ready`，`Succ` |
| `ShowA → lifelong [ShowB] → ShowA`，只读末值，静态运行产出 10，lifelong 产出 20 | `A 10`、`B 20`、`A 10` |
| lifelong 发布一行后，`Report` 以 `requests` + `streams` 启动的静态来源直接 `streamEnd` | `Failed`（`ContextNotInitialized`） |
| `parallel [chain [ReaderOne, MakerOne], chain [ReaderTwo, MakerTwo]]`，两侧都先读后产 | 连续 20 次都 `Failed`（`ContextNotInitialized`），不挂起 |
| `parallel [Reader, Publisher, Starter]`，`Starter → Permit → Provider(Value) → Reader` 无环 | `-N1`、`-N2` 各 180 次全部 `Succ` |
| `parallel [chain [Reader], chain [parallel [WorkOne, WorkTwo], chain [Publisher]]]`，两个工作节点各延时 1.5 ms | `-N1`、`-N2` 各 200 次全部 `Succ` |
| LinesDemo 的生产链：`parallel [PrintLine, Report]`，PrintLine 只 `requires "TextLine"`，Report `requests` + `requires "RunningTotal"`，输入延迟 1.5 秒 | Report 分支的槽含 `LineParser`；`total: 4 lines`、`line: last line`，`Succ` |
| `parallel [chain [ReadA], chain [ReadB, Issue]]`，两侧共享一次静态运行，来源要先读 Issue 才产出的 Ticket（循环依赖） | 20 次都 `Failed`（`ContextNotInitialized`），退出码 0，不挂起 |
| 两个先后的 lifelong 订阅同一 behavior 来源，各发布 `10, 10` | 各回调一次 |
| event／behavior／静态历史探针 | 与上面的验证一致，触发次数不变 |

**未覆盖与已知边界。**

- 各分支可能发布的资产按注册保守计算；多算只会让读取方等到该分支退出后再报缺值。
- “查到缺值”与“开始等待”之间的发布由先取编号再查值保证，没有单独构造这个时序的探针。
- 互相等待只在所有执行中的线程都挂起时判定；还有线程在执行（哪怕不会发布这份资产）时，等待者继续等，直到该线程退出或所有线程都挂起。线程在 require 与共享静态运行之外的阻塞（例如 handler 自己的 IO）计为执行中，判定偏保守，不会误报。
- gen 不分析分支内部读取与生产的先后；两侧都先读后产时按缺值失败，而不是推断出某种执行顺序。
- 生产者失败时整次运行终止，等待者随之取消；分支被取消时同样唤醒并重查。
- 回调环检查按注册保守计算，不区分两个回调是否同时有效，也不证明条件分支。
- lifelong 外的静态运行与 lifelong 内的同一来源是两次独立运行。
- event 回调的有效期是整次运行，直到订阅方 `endStream`。
- lifelong 的历史在 `Drive` 结束时丢弃，最新值保留。
- parser 失败沿发布者调用栈传播，结束整次运行。

<a id="compiler-runtime-review"></a>
**编译器与运行时审查的修正（2026-11-24）。** 审查对照同一业务源码的 Handler、Prototype、Program 与实际执行，指出 gen 的认识与实际执行之间的三处缝隙。

- **实现身份**：gen 曾按方法名取第一个同名实现，未挂载的具体实例（例如 `CountTextHandler IO`）写在泛型 Handler 之前时，gen 分析的不是 GHC 执行的那份，`TextLine` 因此漏掉历史保留。现在每个 handler 类只接受一份 `instance XxxLayer m => XxxHandler m`，具体类型上的实例在生成前按源码位置拒绝。
- **方法图的引用类别**：`Call` 带 `CallKind`（`Invoke`、`Deliver`、`ReadOutput`、`ReadCurrent`、`ReadHistory`），保留 gen 已经区分过的调用方向与读取方式；`Prototype.Query.callbackEdges` 列出发布后的回调及触发方式；`--structure` 标出两者。见[图与生成](EFFECT_GRAPH.md)。
- **运行时的静态查找**：回调表、比较器、作用范围的单元与成员、lifelong 的会话资产与静态运行在运行开始时按键排一次，链定义在建索引时确定；发布、交付、激活与静态请求不再遍历整张表。
- **close 的实例定位**：close 由运行时在实例不可达时调用，现在对所有 scope 都在执行方法体之前定位实例并取得关闭锁；close 不必读取资源，gen 不再检查这项读取，只在部分分支读取或读取前先做 IO 也不会在运行期报 `ScopeContextMissing`。

验证（仓库外探针与 `scripts/check.ps1`）：未挂载的 `CountTextHandler IO` 写在泛型 Handler 之前或之后都在生成前报出位置；LinesDemo 的 Prototype 标出 `GetTextLineGen → NextLineFeedGen (deliver)`、`RunPrintLineGen → StreamTextLineGen (current)`、`RunTextCounterGen → StreamTextLineGen (history)`；FileDemo 的 close 不读资源、读取前先做 IO 都返回 `Succ` 且关闭次数与原示例相同；本页 require 等待与静态读取的全部探针结果不变。

未改：Scope 故障路径的排序（只在失败时执行，且同层顺序有约定）与可达性查询（静态部分已来自 `PrototypeIndex`，其余依赖现场快照）；启动校验保留，用于发现过期的生成产物。

<a id="untracked-units"></a>
**回收无关的单元不登记（2026-11-24）。** 16 个订阅方的扇出基准中，每次交付约 4.9 µs，其中约 3.6 µs 落在一个订阅方退出到下一个进入之间；那段时间做的帧、保留根、Origin 索引、活动目录与 scope 使用登记只有可达性回收会读，而该负载没有 scope 也没有资源。现在由 gen 判定哪些 lifelong 单元与回收无关，运行时对它们跳过这些登记，语义不变。判定条件与保留的语义见 [Stream：回收无关的单元](STREAM_LIFELONG.md#untracked)。

- **Gen**：`Booter.untrackedUnits` 读完成的 Prototype（经 `PrototypeIndex` 的开启、来源、资源与开启参数表），Composition 在校验后算出，Emit 在回调表写 `RunUnit 路径 Tracked|Untracked 闭包`。
- **Runtime**：`Graph.Tracking`；Execution 的 Untracked 回调不建帧、不重置 Origin、不登记保留根，`Step`、`Choose` 与子树退出不改帧进度；`runAppIn` 只发放 Origin 序号，不登记活动目录。另外两处对所有执行都成立的精简：`keepBindings` 没有资源时不进协调锁；按 Origin 的索引只收资源（它本来只用于交出要回收的资源）。

验证（仓库外探针，记录不进仓库）：demo 中 file、lines、open-files、scope-instances、scope-reuse 返回 `Succ`，输出与之前一致；stream 是无限运行，单元为 Tracked，未单独运行。event、behavior、历史、静态读取与 require 等待探针的输出与修改前的构建逐字节相同，只有 `parallel [Reader, lifelong [Sink]]` 中两个分支首行的先后变了，属于合法的调度交错。新探针与 `cf3d870` 的构建逐字节相同：单元发布 Scoped 开启参数时它和开启 scope 的单元都判为 Tracked，每次交付各开一个实例；Untracked 单元中途 `endStream` 后其余单元照常、中途 `raise` 时整次运行以该失败结束。16 路基准挂 middleware 计数时，每个 Operation 的次数与之前相同。

性能（10 万条，`-O1 -threaded`，`-N1`，与 `cf3d870` 交错各 5 轮取中位数）：16 路 7.658 → 4.533 秒，每次交付 4.79 → 2.83 µs，累计分配 39.4 → 26.3 GB；其后对调用路径的精简见[每次调用的执行路径](#call-path)。

<a id="call-path"></a>
**每次调用的执行路径（2026-11-25）。** 不登记之后，剩余开销在每次 handler 调用固定要走的路径上。下面五项都不改声明、AST、handler 写法与 Prototype，只改 gen 输出与运行时执行已定事实的方式。

- **特化**：SDK 的运行模块与 gen 写出的 Generated 模块（Effects、Handlers 副本、Program）带 `-fexpose-all-unfoldings -fspecialise-aggressively`。生成代码只在具体的 `App` 上调用多态的 handler 与 SDK 函数，GHC 据此特化，消掉类型类字典调用并内联 monad 栈。手写业务模块不需要这条选项，Handlers 的编译副本已带上。
- **调用入口**：Untracked 的调用共用运行图里一个从不登记实例的 scope 使用者，不建立、撤销；不屏蔽取消、不交接保留根（没有要配对撤销的登记）；读取不把捕获写进执行帧，最新值直接读运行级表。根调用的初始环境由 `callEnvironment` 统一构造。
- **入口包装与结果求值**：没有输出联立分支的原子句柄不再包 `atomicHandle`，它在交出前的那次输出记录没有读者，输出仍由 `runOnce` 记录（2026-11-27 起只在入口会被再次到达时记录，见[调用路径的冗余记录](#call-path-redundancy)）。结果在撤销使用登记前完整求值，成功值改用 `NFData`（生成的 `Results` 派生；2026-11-27 起 gen 直接写出 `rnf`），失败仍完整展开；不再把每个结果渲染成字符串。
- **监督与交付**：Untracked 的回调在入口处整体受监督一次，不逐层包装；同一次发布的交付视图对它的所有回调只组装一次（回调不能再发布它订阅的资产，视图在回调之间不变）。选择读取的捕获只在 alternative 交给候选时过滤资源，普通 Step 不再过滤。
- **闭包编成函数**：运行开始时把 Generated/Program.hs 的闭包数据（workflow 与回调表）各编成执行函数一次（`Execution.stage`、`respond`）：坐标、成员、帧节点、作用范围与候选位置在函数之外算好，每次执行只做本次的工作。生成的 Program 仍是可读的闭包数据，没有改成生成 Haskell 函数：编成函数连同上一项的入口精简，16 路只从 2.02 秒降到 1.91 秒，闭包遍历不是主要开销，改写生成形式换不来与静态结构相称的收益。成功值的求值不给业务类型增加约束：gen 交给 target 的总是 `Results` 或 `()`，handler 的返回值先以 `<$` 替换。

性能（10 万条，`-O1 -threaded`，`-N1`，与 `cf3d870` 交错各 5 轮取中位数；同机另有一组长期基准在跑；每轮核对全部订阅方的条数与校验和）：

| 负载 | `cf3d870` | 不登记（`122f0e3`） | 本节之后 |
| --- | --- | --- | --- |
| 单订阅方 | 0.631 s | 0.465 s | 0.296 s |
| 4 路 | 1.855 s | 1.199 s | 0.605 s |
| 16 路 | 7.637 s（4.77 µs／交付，24.6 KB） | 4.503 s | 1.905 s（1.19 µs／交付，8.3 KB） |

16 路剩下的 1.19 µs 里约 0.53 µs 是基准 handler 自己的 `read`（标准库的通用语法解析，原生 Haskell 用它时同样耗时）；框架约 0.66 µs，主要在调用入口、读取路径与 handler 的 monad 层。

验证（仓库外，记录不进仓库）：file、lines、open-files、scope-instances、scope-reuse 五个 demo 与 `cf3d870` 的构建从同一初始状态运行，输出逐字节相同；event、behavior、历史、静态读取、require 等待与三个回收无关探针的输出与修改前相同（ModeProbe 的计数器跨运行累计，结构相同）；16 路基准挂 middleware 计数，100 条与 10 万条的每种 Operation 次数相同。

未覆盖：event 单元与订阅源头在 Scoped 下的单元（LinesDemo、StreamDemo）照旧登记，走原来的调用路径；Tracked 路径的调用入口未精简；stream-demo 是无限运行，未单独运行。

<a id="call-path-redundancy"></a>
**调用路径的冗余记录（2026-11-27）。** ticky 统计显示 16 路基准每次回调分配约 3.1 KB，其中大半是没有读者的记录与环境复制。下面几项都不改声明、AST、handler 写法、Prototype 与 Program 的闭包形状，只去掉生成期已能判定无用的包装和运行时的冗余分配：

- **`runOnce` 只包在会被再次到达的入口上**：同一次调用里 Excu 与 Pure 的入口只有被别的入口调用时才会再次到达（前驱或锚点、rawinput 读回、输出联立的锚点、选择读取共同执行的句柄）。只从根进入的入口不包 `runOnce`，也不记录输出；没有输出联立分支的句柄因此不再有任何输出记录。Scoped.open 照旧包。
- **`enterHandler` 只写在方法体会调用别的入口时**：调用者只由 atomicScope 读取，用来跳过调用者自己的生产分支；方法体没有前驱、锚点、生产分支，rawinput 也不读回上游时，其中不会执行 atomicScope。Excu 与 Stream 来源的入口据此省掉一次 25 个字段的环境复制。
- **`Results` 的 `rnf` 由 gen 写出**：每个构造器只带 `()`，求值到构造器即完整求值，不再经 `Generic` 的通用实现。
- **运行时**：没有 Error 回调时 `withErrorHandlers` 不复制环境；`require` 先查值，缺值时才取发布编号再查一次并等待，编号仍先于等待前的那次查值取得，不会漏掉唤醒；一次发布的回调直接按表执行，不先构建动作列表；交接里没有资源时不拼出待保留的列表；Environment、Launch 与 Run 的字段改为严格。

另外试过按单元是否登记在启动时分别编出 Step（Untracked 的 Step 不经 `managed`、`tracked`、`retained` 的逐次判断）：分配少了 0.33 GB，时间没有变化，没有保留。

性能（10 万条，`-O1 -threaded`，`-N1`，与 `fe17e7a` 交错各 5 轮取中位数；负载是 parser 解析一次的 `Sample Int`，每轮核对全部订阅方的条数与校验和）：单订阅方 0.295 → 0.279 秒，4 路 0.406 → 0.356 秒，16 路 0.919 → 0.671 秒；16 路累计分配 6.53 → 4.56 GB。

验证（仓库外，记录不进仓库）：8 个 demo 重新生成，`cabal build all` 通过。file、lines、open-files、scope-instances、scope-reuse 与 FacadeProbe 六个 demo，以及 event、behavior、历史、静态读取、require 等待、回收无关单元等 13 个探针，与 `fe17e7a` 的构建从同一初始输入运行：生成日志、输出与写出的文件逐字节相同，只有两处例外：读 stdin 的三个探针在输入结束时两边抛出同样的异常，回溯里的源码路径不同；FacadeProbe 带 `parallel`，`fe17e7a` 自己连跑 6 次就有 6 种输出顺序，新的输出也落在这些顺序之中。

未覆盖：stream-demo 与 crawler-demo 未运行；Stream 来源与它的 parser 每一步仍走登记路径（建 Origin 索引、scope 使用者、保留根，退出时扫描回收），是否由 gen 判定后不登记尚待决定。

<a id="asset-base-fields"></a>
**资产的基础字段（U5，2026-11-26）。** 字段只能是 `String` 时，数值以文本保存，每个读取方都要知道文本格式并各自解析。16 路基准每条数据解析 16 次，`read` 占墙钟时间的 54%。现在字段可以是 `Int`、`Integer`、`Double`、`Bool`：parser 解析一次，读取方直接读值。表示类型仍是一阶、单态、有限的积。文件形式仍由 gen 在语法树上检查；构造器个数、字段类型、严格标记与递归改由 GHC 求解 `Framework.Language.AssetForm` 的封闭类型族（DataKinds），不再按源码拼写比对，同时补上了原检查漏掉的自身引用与互相引用。StreamDemo 的 `Temperature` 改为 `Double`，`CheckTrend` 不再 `read`。规则见[资产固定形式](ASSETS.md#fixed-form)。

LSP 待跟进：server 的类型候选与新表示类型的字段校验（`codegen/authoring.py`）、handler 提示词中的能力推断与 parser 写法（`agent/prompt.py`），以及 webapp 两个对话框的类型选项和 parser 草稿（`authoring-dialog.tsx`、`registration-dialog.tsx`）仍只认 `String`／`[String]`。

<a id="code-shape"></a>
## LSP 从哪份代码开始

网页添加注册时，`effect-codegen registration-slot Namespace` 从 GHC 解析树给出显式列表闭括号所在行（从 1 起）与行内字符偏移（从 0 起）。列表内已有的局部 helper 可保留。后端调用 `console Namespace --source-root DIR`，在本地项目的 Cabal 环境中分析候选副本。

单条 Effect 注册的语法读取已落地。`effect-codegen read-effect` 从 UTF-8 标准输入解析 v1 表达式并输出 JSON。`effect-codegen read-effects Namespace` 按源码顺序读取已保存的注册，遇到 helper 构造的声明时从受信任模块求值并提供只读视图。`effect-codegen console Namespace` 在同一工作树完成组合分析，导出注册、直接方法引用、Handler 绑定及源码、有序 Workflow AST（规范形式，与 `ast` 的 `workflow` 相同），供可视化面板读取。三条命令都不会更新生成区。

AST 的读取已可单独使用：`effect-codegen ast Namespace` 只加载 AST、Workflow 与 Hanging，输出原样结构及源码范围、规范形式与 NodeId、Hanging 挂载、结构诊断和源码文件的 MD5；完整生成把同样内容写入 `Generated/Workflow.json`，编辑器据 MD5 判断它是否仍对应当前源码，见[只分析 AST](GUIDE.md#ast-command)。

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

[闭包模型](#closure-model)之后，交付在发布者调用栈里同步回调，回调返回前来源不会产生下一条，不再有积压的交付队列，原先的背压问题随之消失。仍待设计的是 `parallel` 的多个 lifelong 之间是否需要限速或公平性。

<a id="ast-nesting"></a>
### AST 嵌套与 workflow 边界

同类嵌套、单子项与空 branch 已按[规范形式](CORE_DESIGN.md#workflow-normal-form)化简：gen 与运行时共用 `normalizeWorkflow`，`NodeId` 取自规范形式，Hanging 挂载随之迁移。lifelong 的单元就是它的直接子项，parallel 不再划分单元；alternative 的候选须是 node，至少两个（用户确认，2026-11-21）。现有 `chain`、`parallel` 和 `alternative` 可以嵌套，也可以放在 `lifelong` 内。gen 目前拒绝在 `lifelong` 的后代中再次挂载 `lifelong`。嵌套持续执行单独设计。以「每份订单启动一条消息流」为例，需要决定外层何时能接下一单、内层结束或取消传到哪里、哪个执行帧持有订阅和 scope。[静态规则](STREAM_LIFELONG.md#static) · [执行边界](STREAM_LIFELONG.md#execution-boundaries)

<a id="review"></a>
<a id="current-limits"></a>
## 使用 prebeta 时应知道的边界

- 含 `lifelong` 的程序仍按整次运行传播失败。`require` 缺值时只等别的 `parallel` 分支；gen 只检查来源存在，不证明执行到读取时一定已有值。[失败协议](STREAM_LIFELONG.md#failures) · [来源检查](EFFECT_GRAPH.md#missing-source)
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
| requests 前驱与运行时编号、坐标 | [requests 与输出联立](CORE_DESIGN.md#request-production) · [剧本化阶段](#request-chains) |
| 输出联立与 socket／history／behavior／event | [输出联立](CORE_DESIGN.md#output-links) · [驱动方式的组合](STREAM_LIFELONG.md#drives) · [阶段](#output-links) |
| 消费链与生产分支 | [锚点注入与一次执行](CORE_DESIGN.md#consumer-chain) |
| gencode 的读取与重跑 | [只分析 AST](GUIDE.md#ast-command) · [重跑边界与接口缓存](EFFECT_GRAPH.md#cache) |

<a id="maintenance"></a>
本页只跟踪已选定的工作。正式协议和已实现写法分别维护在[主设计](CORE_DESIGN.md)与[指南](GUIDE.md)。
