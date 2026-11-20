# Next stages

<a id="stages"></a>
项目已进入 **prebeta**。手写业务代码的形态和已实现的运行语义构成 LSP 的基线。编辑器可以据此理解一个程序，后续涉及注册写法、handler 能力或可观察运行行为的变化仍须单独确认。

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

慢消费者尚未领取的交付仍然可达，积压可以持续增长。这个专题要确定容量按什么计量、生产在哪一步等待，以及最后一个订阅者离开时如何唤醒生产方。一个必须处理的例子是同单元先发布、后领取：如果发布因容量已满而等待，后面的领取可能永远无法运行。设计时要保住已发布值的顺序、取消与排空，并让已有 scope GC 继续负责资源关闭。[交付保留](STREAM_LIFELONG.md#retention) · [资源交接](STREAM_LIFELONG.md#binding-retention)

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
