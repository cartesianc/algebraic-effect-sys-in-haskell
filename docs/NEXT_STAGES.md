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
**U2 结束后的完整历史保存暂缓。** 当前会话在来源停止且所有读取方离开后释放历史前缀，正常结束后的合法后继仍可用 `requires` 读最后一条。若以后需要独立保存整段数据，还须决定保存者的启动时机、归属会话和读取方式。[会话保留规则](STREAM_LIFELONG.md#retention)

<a id="urgent-backpressure"></a>
**U3 背压暂缓。** `x :> xs` 的尾部是已经发布的过去。消费方遍历它时，上游可以继续生产；队列容量和按需求暂停生产仍在[背压专题](#backpressure)讨论。

**不同上游之间的 race 暂缓。** 当前 gen 要求候选共享一个判定 Excu。若引入不同生产链竞争，还须确定胜者、输家取消和已执行 IO、scope 的收尾规则。这些选择不属于已实现的 U5。

<a id="request-chains"></a>
## requests 剧本化

消费链按剧本编译：`requests` 是前驱，`requires` 是被动读取。运行时的资产匹配提前到 gen 期。以下语义由用户确认，完成于 2026-11-21。

| 阶段 | 已实现 | 规范 |
| --- | --- | --- |
| <a id="request-phase-1"></a>R1 requests 前驱 | gen 把被请求资产唯一的生产链展开进请求方入口；每个请求方每次执行各走一遍，成功值写入该资产的当前值。`requires` 只读这个值，被读取的普通资产必须有 effect `requests` 它（`Asset never requested`）。句柄单独执行不再注入挂在它下面的普通 Context。alternative 候选只 `requires` 自己的判定资产。 | [普通资产只经 requests 生产](CORE_DESIGN.md#request-production) · [Crawler](../demo/Crawler/Effects.hs) |
| <a id="request-phase-2"></a>R2 运行时按身份寻址 | interpreter 启动时一次建索引。资产与 scope 按 gen 分配的 effect 编号存取，生成入口直接写出编号；执行位置按先序坐标寻址，子树判断是一次区间比较。普通 Context 的注入代码与 gen 中对应的分析分支已删除。 | [运行索引](CORE_DESIGN.md#request-production) |

<a id="request-phase-3"></a>
**R3 持续资产未改。** Stream 会话、lifelong 订阅与 `ReuseOutput` 仍按原协议驱动，持续 Context 继续挂在句柄输出上。用户已确定持续资产也要随剧本化调整，具体设计待写并确认后实现。

**运行时仍按名字查的位置。** 这些查找都不在资产读写路径上：

- 原子句柄的回放表，只在持续注入和选择判定期间使用；
- alternative 选中后按 Context 名找候选分支，每次选择一次；
- 会话步骤按标签取入口，每个会话启动一次；
- Error 回调登记与 `Failure` 记录，属于诊断展示。

requests 展开的前驱作为请求方入口里的静态代码执行，运行时没有它们各自的坐标。

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
| requests 前驱与运行时编号、坐标 | [普通资产只经 requests 生产](CORE_DESIGN.md#request-production) · [剧本化阶段](#request-chains) |

<a id="maintenance"></a>
本页只跟踪已选定的工作。正式协议和已实现写法分别维护在[主设计](CORE_DESIGN.md)与[指南](GUIDE.md)。
