# Next stages

<a id="stages"></a>
Middleware 首版已经实现，下一阶段处理[持续交付的容量与背压](#backpressure)；[AST 嵌套与 workflow 边界](#ast-nesting)单列为待设计阶段。两者都尚未实现，其他开放项见[专题清单](#deferred)。

<a id="code-shape"></a>
<a id="middleware"></a>
## Middleware：首版范围与后续事项

**首版已实现（2026-11-19）。** 现行规则写在 [CORE_DESIGN 的 Middleware](CORE_DESIGN.md#middleware)，组合依据登记在 [COMPOSITION](COMPOSITION.md#middleware)，写法见[开发指南](GUIDE.md#middleware)。已确认的取舍：

| 事项 | 首版决定 |
| --- | --- |
| 是什么 | 由 Root 级入口驱动的 Excu：在 Root 级调用点（交出值、`raw`、`raise`）上同步执行，不包住或推进原调用 |
| 注入时机 | 生成期：`middleware` 标注是给 gen 的标记。标签带 Middleware 列表类型参数，入口对它多态，调用点经生成入口的类型类约束 `Captures hooks` 注入；挂载登记时给出列表，GHC 编译期选定实例。运行时没有 Middleware 目录或分发，只按静态登记名选取 Target |
| 注册形态 | `EffectTyping` 增加 `Middleware { handler, intercept }`；`input` 写保留名 `"None"`，沿用 Input 的组合逻辑，表示没有 Input 注入；不另设 `MiddlewareSpec` |
| `intercept` | 能交出 raw output 的 `ExcuKind`、`ScopedKind`（open／close）、`PureKind`；`allEffects` 是三者的简写 |
| handler 能力 | `Hooks`（`hookedOutput`、`hookedRaw`、`hookedError`）、`Raises`、`MonadIO`；签名 `m [String]`；`Hooks` 只为 Middleware 的标签生成 |
| 捕获范围 | 由位置决定：启动位置被标注覆盖即捕获，会话步骤也按同一前缀规则 |
| 多个 Middleware | 按注册顺序同步执行，只读本次捕获，彼此不传值 |
| `raise` | 与普通 Excu 相同，失败从调用点传播 |
| demands | 首版不允许 |

**后续事项。**

- **`requires`。** 若允许 Middleware 读取配置资产，须把它计入来源证明与等待环分析：它在调用点同步执行，读取等待可能与被捕获调用所在的生产形成等待环。
- **更多捕获点与类型。** Context parser 交出的业务值、Stream 的原始输入、调用的进入等尚未捕获；若捕获值的类型随类别不同，可用 associated type 区分 `hookedOutput` 的结果类型。
- **mock。** SDK 目前没有 mock 运行模式；Middleware 的 `raise` 在正常运行时按普通失败传播。
- **Hanging 与装卸。** 与 Middleware 的挂起、恢复和装卸关系另行设计。

<a id="backpressure"></a>
## 延期专题：持续交付的容量与背压

**已确定需要解决，具体方案待收敛，尚未实现。** 当前已能裁剪不再有领取义务的交付，但慢消费者仍会让未领取积压持续增长；这些数据仍然可达，GC 不能替代流量协调。现有存储与读取义务见[交付保留](STREAM_LIFELONG.md#retention)。本阶段限制 SDK 交付积压，不裁剪业务资产自行保存的记录，也不把容量释放当成 scope close。

**代码形态目标：** 保持原子 handler、资产解析、Input／demands 与 workflow 的现有分工；handler 不手写队列、容量轮询或释放调用。容量配置尚未确定归属，不预先增加 facade 字段；若确需声明接口，先展示 Effects／AST 的具体写法并单独确认。

**实施顺序：**

1. **在 Composition 中确定等待关系。** 复用 Receive、Derive、ReuseOutput 的生产计划、订阅关系与 workflow 顺序，分析容量等待能否由独立推进的读取方解除。重点覆盖同单元“先发布、后领取”及派生链的局部等待环；可静态证明无法推进的组合由 gen 拒绝，不以增大默认容量掩盖问题，不要求证明任意业务 IO 都能结束。
2. **在 Session 中协调容量与交付。** 复用游标、会话状态和通知，区分尚未领取的交付、正在执行的固定捕获及最新值保留。确定容量许可取得／归还的位置，满时挂起而非忙轮询；领取、读取方离开或终止状态变化唤醒相关等待者。普通 require 仍按最新值与固定捕获协议读取，不额外制造逐条交付义务。
3. **接通结束与资源回收。** 容量等待必须能响应取消与会话退役；生产 end、消费退出和正常排空继续沿用既有协议。先完成绑定持有的交接，再撤销原有保留；队列空位与执行使用分别记账，资源只有在原有 scope GC 条件满足时才 close，不新增回收器。

**实现前需收敛的策略：**

| 决定 | 当前建议（未确认） |
| --- | --- |
| 容量的单位、默认值和配置位置 | 先按会话的未领取条数设计；同时说明在途执行不计入队列上限，条数上限不等于进程内存上限 |
| 满队列时的行为 | 首版考虑等待、不隐式丢弃或合并；容量能否配置为无界需明确 |
| 广播中的慢消费者 | 保全每个有效订阅者的交付时，按最慢游标约束共同来源；订阅撤销及时解除该义务 |
| 等待放在生产前还是发布时 | 分析容量预留与已完成 IO 的关系；既不回滚或重跑原子操作，也不让等待容量妨碍必要的消费启动 |

**完成边界：** 按确定的单位约束积压；等待期间保持取消、排空、捕获与 close 的既有保证；不通过无限新建等待任务转移积压。生产节奏与调度关系会受到背压影响，不能宣称只是不可观察的内存优化。通用外部 push 适配、持久化积压、丢弃／合并策略和业务记录压缩不随本阶段自动引入。确认后的详细协议写入 Stream 规范，组合解释与拒绝条件登记到 COMPOSITION；本节只保留计划与状态。

<a id="ast-nesting"></a>
## 独立阶段 · AST 嵌套与 workflow 边界

**状态为待设计。** 现有 AST 已经可以嵌套 `chained`、`parallel` 和 `alternative`。`lifelong` 也可以包含这些有限分支；直接子项为 `parallel` 时，该层会拆成独立消费单元。当前 gen 拒绝在一个 `lifelong` 的任何后代中再次挂载 `lifelong`。[现行生成规则](STREAM_LIFELONG.md#static)

本阶段讨论会建立新执行边界的嵌套。以“外层收到一条订单，内层持续处理该订单的消息”为例，需要先确定以下三件事。

1. **谁推进哪一层。** 同一次外层交付何时建立内层单元与会话，外层能否继续领取下一条订单，同一内层来源在不同外层轮次之间是否共享。
2. **结束和取消传到哪里。** 内层结束后外层何时进入后继，外层结束或被取消时要等待哪些内层调用、交付和清理。失败归属与局部恢复须衔接现有 Error 专题。
3. **资源归谁。** 哪个执行帧持有订阅、固定捕获与 scope 待用关系，退出时谁撤销它们。沿用现有的执行帧、会话退役和 scope GC。[执行边界](STREAM_LIFELONG.md#execution-boundaries) · [资源交接](STREAM_LIFELONG.md#binding-retention)

先列出获准与拒绝的嵌套形状及其启动、推进和退出轨迹；确认后由 `Gen.Composition／Booter` 生成静态边界，`Runtime.Execution／Frame／Session` 落实本次执行的关系。**在该阶段单独确认前保留现行嵌套限制。** Middleware 对一棵已有子树作透明标注，背压处理交付容量，两项工作都不决定嵌套执行策略。

<a id="deferred"></a>
## 其他开放专题

| 专题 | 仍需确定 |
| --- | --- |
| 来源与调度 | 是否区分或自动推导 event／behavior／socket；自动重试、时间周期声明、通用外部 push callback 适配；已有单步写法见 [Stream](STREAM_LIFELONG.md#drives) |
| 持续组合 | 多来源组合触发同一 target、派生步骤跳过与显式反馈 |
| 值操作与适配 | Pure 挂在 Stream 下、Generic Map |
| 资源协议 | Stream close 接口是否需要；scope 同值复用、其他 cleanup policy、未发布的部分获取恢复、跨 interpreter 存续；均不扩展为普通业务资产内嵌资源的自动追踪 |
| 故障恢复 | Error 驱动链、常驻 scope 失效与修复、局部失败、已展开 continuation 恢复及跨调用诊断；当前 resolve 不调用 close，处置成功仍传播原失败 |
| 内存与诊断 | 业务惰性状态链是否需要处理，以及关闭失败记录长期累积的报告策略；强制求值或改变报告时机须另行确认 |
| 模块与接口 | 独立生成模块组合、跨语言 schema |
| Hanging 与装卸 | 与 Middleware 的挂起、恢复、装卸关系另行设计，见 [Middleware 后续事项](#middleware)。 |
| 外部工具 | LSP 侧的订阅、会话、单元与来源可视化，及穷举模型对 Stream／lifelong 的覆盖。 |

<a id="review"></a>
<a id="current-limits"></a>
## 已知边界

- **资源与会话。** ScopeTree 保留从 Input 推导的宽依赖；长期子实例可能保留历次共同使用的父实例。生成产物层的人工精简边、interpreter 托管会话的提前停止，以及来源 end 后更早释放，均待单独设计。[父引用边界](EFFECT_GRAPH.md#scope-parent-retention) · [退役规则](STREAM_LIFELONG.md#consumer-end)
- **进度与失败。** 普通 require 的无来源诊断和保守等待只覆盖可证情形；同单元直接或经 Derive 等待 Scoped.open 复用输出的组合仍被保守拒绝，必定 fresh 时的精确放行尚未实现。含 lifelong 的程序目前仍按整次运行传播失败。 [缺值诊断](EFFECT_GRAPH.md#missing-source) · [派生与复用](STREAM_LIFELONG.md#derive) · [失败协议](STREAM_LIFELONG.md#failures)
- **规模。** 来源状态与 scope 路径仍可能指数增长，共享通知可能额外唤醒等待者。高负载、长期堆占用、资源认领交接与跨平台取消仍缺少充分实测。[图与来源](EFFECT_GRAPH.md) · [会话保留成本](STREAM_LIFELONG.md#retention-cost)

<a id="baseline"></a>
## 已交付能力去哪里查

Stage 1–7 在各自已确认的范围内完成。下面保留规范入口，已完成的实施清单和逐次验证记录归入 Git 历史。

| 已交付 | 现行规范 |
| --- | --- |
| <a id="stage-1"></a><a id="stage-2"></a>资产来源与原子 handler 复用 | [注册与读取约束](CORE_DESIGN.md#demand-contract) · [handler 写法](GUIDE.md#handlers) |
| <a id="stage-2-await"></a><a id="stage-4"></a>共享最新值、固定捕获与持续驱动 | [普通 require 的供值与等待](CORE_DESIGN.md#await-visibility) · [Stream 的读取与驱动](STREAM_LIFELONG.md#contracts) |
| <a id="stage-3"></a><a id="stage-6"></a><a id="stage-6-reuse"></a>Stream 与 lifelong 的执行、两侧结束及同次输出复用 | [执行边界](STREAM_LIFELONG.md#execution-boundaries) · [来源结束](STREAM_LIFELONG.md#end) · [消费结束](STREAM_LIFELONG.md#consumer-end) · [输出复用](STREAM_LIFELONG.md#derive) |
| <a id="stage-5"></a><a id="stage-7"></a><a id="scope-gc"></a>已知 ownership 的持续资产持有和 scope 回收 | [资源交接](STREAM_LIFELONG.md#binding-retention) · [可达性回收](CORE_DESIGN.md#scope-gc) |
| <a id="pure-pipeline"></a>Pure 与 list 原子输出 | [Pure 的位置、输入与输出](CORE_DESIGN.md#pure) |
| Middleware 首版：AST 标注挂载与 Root 级调用点捕获 | [Middleware](CORE_DESIGN.md#middleware) · [写法](GUIDE.md#middleware) |
| <a id="version-boundaries"></a>gen 内部职责与版本边界 | 共享供值改变了普通资产能读到哪次发布。其后的 Injector／Booter 重构统一静态装配与驱动事实，手写接口与该读取协议保持一致。[内部接口迁移](CORE_DESIGN.md#sdk-migration) |

最近一次 gen 修复已在 FileDemo 验证局部 `raw` 和重导出的 SDK 能力，两个文件分支均返回 `Succ`；八个命名空间生成结果无变化，离线编译通过。该记录只覆盖当时的修复。

<a id="maintenance"></a>
## 计划怎样更新

新语义先在本页展示写法与未决边界；确认后把正式协议写入所属规范，将组合依据登记到 [COMPOSITION](COMPOSITION.md)。实现并验证后，指南再展示可用接口。这里只保留开放事项、必要的完成摘要和验证边界。
