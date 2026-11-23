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
| <a id="urgent-race"></a>U5 同一输出选分支 | `alternative` 按候选顺序让判定 parser 尝试同一次 Excu 输出。若全部拒绝，选择读取检查已有绑定，有合法的其他供值机会时等待。 | [选择与交接](CORE_DESIGN.md#alternative-selection) · [来源证明](EFFECT_GRAPH.md#missing-source) |

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

慢消费者尚未领取的交付仍然可达，积压可以持续增长。后续需确定容量按会话还是读取方计量、哪些读取方参与限流、生产在哪一步等待，以及订阅结束怎样唤醒生产方。尤其要处理同一单元先发布、后领取的情形，避免生产等待本单元尚未获准执行的领取。已发布交付的顺序、取消与排空规则继续适用。[交付保留](STREAM_LIFELONG.md#retention) · [资源交接](STREAM_LIFELONG.md#binding-retention)

<a id="ast-nesting"></a>
### AST 嵌套与 workflow 边界

同类嵌套、单子项与空 branch 已按[规范形式](CORE_DESIGN.md#workflow-normal-form)化简：gen 与运行时共用 `normalizeWorkflow`，`NodeId` 取自规范形式，Hanging 挂载随之迁移。lifelong 的单元就是它的直接子项，parallel 不再划分单元；alternative 的候选须是 node，至少两个（用户确认，2026-11-21）。现有 `chain`、`parallel` 和 `alternative` 可以嵌套，也可以放在 `lifelong` 内。gen 目前拒绝在 `lifelong` 的后代中再次挂载 `lifelong`。嵌套持续执行单独设计。以「每份订单启动一条消息流」为例，需要决定外层何时能接下一单、内层结束或取消传到哪里、哪个执行帧持有订阅和 scope。[静态规则](STREAM_LIFELONG.md#static) · [执行边界](STREAM_LIFELONG.md#execution-boundaries)

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
| requests 前驱与运行时编号、坐标 | [requests 与输出联立](CORE_DESIGN.md#request-production) · [剧本化阶段](#request-chains) |
| 输出联立与 socket／history／behavior／event | [输出联立](CORE_DESIGN.md#output-links) · [驱动方式的组合](STREAM_LIFELONG.md#drives) · [阶段](#output-links) |
| 消费链与生产分支 | [锚点注入与一次执行](CORE_DESIGN.md#consumer-chain) |
| gencode 的读取与重跑 | [只分析 AST](GUIDE.md#ast-command) · [重跑边界与接口缓存](EFFECT_GRAPH.md#cache) |

<a id="maintenance"></a>
本页只跟踪已选定的工作。正式协议和已实现写法分别维护在[主设计](CORE_DESIGN.md)与[指南](GUIDE.md)。
