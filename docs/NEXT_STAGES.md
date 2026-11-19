# Next stages

<a id="stages"></a>
下一阶段设计 [Middleware 的环绕调用](#middleware)。[AST 嵌套与 workflow 边界](#ast-nesting)单列为待设计阶段；[持续交付的容量与背压](#backpressure)保留原计划。三者都尚未实现各自拟议的扩展，其他开放项见[专题清单](#deferred)。

<a id="code-shape"></a>
## 代码长什么样

下面是 Middleware 的**接口提案**。SDK 目前没有 `middleware`、`MiddlewareSpec` 或 `proceed`。现有可运行的注册、instance 和具名 workflow 见[开发指南](GUIDE.md#code-shape)。

```haskell
-- Effects.hs · effects :: [EffectSpec] 中的一项（拟议）
MiddlewareSpec
  { name      = "TraceOutput"
  , handler   = Just "traceOutput"
  , intercept = [ExcuKind, ScopedKind]
  }

-- Handlers.hs · 对确实交出 raw 的调用，示意前置和后置操作
instance TraceOutputLayer m => TraceOutputHandler m where
  traceOutput = do
    liftIO (putStrLn "start")
    proceed
    fields <- raw
    liftIO (print fields)

-- AST.hs · 用具名 branch 保留方括号写法，作用域里只有一棵子树
reportBranch :: AST
reportBranch = chained [node "Prepare", node "WriteReport"]

ast :: AST
ast = parallel
  [ middleware [node "TraceOutput"] reportBranch
  , chained [node "WriteReport"]
  ]
```

建议签名为 `middleware :: [EffectNode] -> AST -> AST`。节点列表引用 Middleware 注册名，第二个参数接一棵已经写明驱动方式的 branch。要包住多项，由作者在这棵树上选择 `chained` 或 `parallel`。因此不需要另造 `nodelist` 标记，也没有子树列表的隐式执行顺序。上例两支复用一个 `WriteReport`，只有左支经过 `TraceOutput`。

<a id="middleware"></a>
## Middleware 怎样包住一次调用

**槽位只包住本单元的原子调用。** gen 保留生成入口已有的执行顺序：先按声明执行 `requests` 和 Input 前驱，然后把本单元的 `runAt @"X" handler` 作为尚未执行的 action 交给 Root 的 `superhandler`。以 FileDemo 为例，拟议的生成片段如下，省略现有的外层协议包装。

```haskell
runReadFile = do
  openFileSession
  superhandler readFileEntry (runAt @"ReadFile" FrameworkGenerated.readFileContent)
```

`openFileSession` 经过自己的入口；只有确实执行 open 方法体时，才进入它自己的原子槽位。前驱失败时不会进入 ReadFile 的槽位。前驱成功后，Root 按本次挂载计划进入 ReadFile 的 hook，`proceed` 推进同一槽位的下一层，最内层才调用 `readFileContent`。ReadFile 的推进次数和计时范围均不包含前驱。空 hook 计划直接执行该次原子调用。错误路径、scope 生命周期锁、Context 注入与发布保持原有入口顺序。[现有入口装配](CORE_DESIGN.md#calls)

**推进次数。** 正常完成时，各层各推进一次，原子调用总计一次。若将来允许前置 `raise`，推进前失败意味着原子调用零次；原调用或后置操作失败不会重跑已经执行的 IO。业务 handler 只取得受控的 `proceed`，原结果由 SDK 保管并交回调用者。取消和必须执行的资源清理沿用 SDK 的协议。

**raw 的交接。** `withMiddleware :: Entry -> m a -> m a` 原样传回结果 `a`。业务 `raw :: m [String]` 读取独立的只读旁路通道。Injector 只在已知能交出原始输出的位置接线，由本次原子调用交接一次输出；同一槽位的后置 hook 与原 parser 都可读取它。通用派发层无需检查、转换或覆盖 `a`，也不会为读取 raw 再执行 action。业务交出 `[]` 是一次有效输出；scope 复用时没有执行 open 方法体，也就没有本次 open 的 raw。

**gen 的次序检查。** Middleware 方法主 `do` 序列中必须有且仅有一处直接的 SDK `proceed`。它须在每一条能执行 SDK `raw` 的路径上先成功返回；前置代码读取 `raw`、某个分支绕过推进后再读、将推进或读取藏在无法证明顺序的局部 action 里，都在生成期报错。Source／Shape 按使用位置的 GHC `Name` 识别两个能力，合法的重导出和同名局部变量遵循 Haskell 作用域。到达后置位置只证明时序正确；该注册是否能读 raw 还要满足挂载角色的能力约束。

### 一个 superclass 怎么接多个注册

下面只表示 SDK 的目标类型关系，`Entry` 表示调用入口。Superclass 为 Root 提供环绕能力，gen 为一个程序合成派发实现。

```haskell
class Monad m => Middleware m where
  withMiddleware :: Entry -> m a -> m a

class Middleware m => Root m where
  superhandler :: Entry -> m a -> m a
```

例如 `TraceOutput` 和 `Metrics` 分别绑定自己的原子 handler 类。gen 将注册身份分别接到各自的 handler，在程序的 `withMiddleware` 实现里按挂载计划组合它们。Root 始终只依赖 `Middleware m`，注册列表和匹配结果留在编译产物里。派发 hook 本身走内部入口，避免 hook 再拦截自己；并发分支使用各自的计划。现有 SDK 的 Root 职责由多个生成包装共同承担，上述两个类仍是拟议接口。

### 实施顺序与模块

| 步骤 | 模块 | 交付与待定边界 |
| --- | --- | --- |
| 1. 注册与 AST | `Language.Registration`、`Language.AST`、`Framework.SDK` | Middleware 注册没有 Input。建议首版也不提供 `demands`，因而不读取配置资产，也不触发 `requests`。若以后开放 `requires`，须把它计入来源与等待环分析。注册构造器的选择见下表。 |
| 2. 挂载合法性 | `Gen.Composition`、`Gen.Booter`、`Prototype` | 在两种位置分别校验同一种 `EffectNode`。hook 列表只接受已注册的 Middleware；普通业务节点列为 hook 时拒绝。普通 workflow 的 `node` 仍遵循现有末端规则，Middleware 注册名出现在该位置时也拒绝。未知名称在两处都报错，诊断指出挂载位置和期望角色。合法挂载才进入静态 hook 计划。 |
| 3. 提取与装配 | `Gen.Frontend.Source／Shape`、`Gen.Composition`、`Gen.Injector`、`Gen.Emit` | 前端提取已解析的能力使用及控制流，gen 校验推进次数与 raw 读取次序。Injector 把槽位接在本单元的原子调用上，按输出角色接 raw 通道；Emit 渲染已定计划。 |
| 4. 执行与验收 | runtime 的入口与执行环境 | 用并发分支复用同一 handler 的例子核对 hook 隔离；用 FileDemo 核对前驱和原子调用各自的次数、同次 raw 与原 parser 的交接。透明标注保持 `lifelong` 对直接 `parallel` 子项的拆分。 |

### 需要用户决定的三项

| 待定项 | 建议与实际代价 |
| --- | --- |
| **待定 · 注册形态** | 建议给现有 `data EffectSpec` 增加并列构造器 `MiddlewareSpec`，保留 `effects :: [EffectSpec]` 的写法。这样类型直接排除 Middleware 的 Input，但现有 `typing`、`input`、`demands` 记录选择器在新构造器上将成为部分函数，处理所有注册的代码须先按构造器匹配。另一方案是在 `EffectTyping` 增加类别，再由 gen 强制 `input = "Root"`；类型层仍允许写出其他 Input。 |
| **待定 · 首版是否提供 `Raises`** | 建议首版暂不给 Middleware 的 Layer 提供这项能力。若业务需要在推进前主动拒绝调用，须同时确认下面的故障归属和自动 close 的保护。无论选哪种，原子 handler 自身已支持的失败仍按原协议传播。 |
| **待定 · Middleware 自身失败的归属** | 若开放 `raise`，建议保留 Middleware handler 为故障来源，并附实际拦截的挂载位置。现有 `RaisedBy` 按 handler 匹配，Error 注册须关联唯一 scope。还需决定缺少适用 scope 的挂载如何处理、后置失败如何报告、以及诊断或 close 怎样完成。Middleware 自身没有 Input，不能据此挑选其他 scope 实例。[现有 Error 协议](CORE_DESIGN.md#error) |

**`intercept` 留待细化。** 类别列表沿用 `EffectKind`，保留 `AllEffect` 表示覆盖所有业务 effect 类别的简写意图。在原子槽位边界内，各类别的方法角色、可提供的能力、多 hook 顺序、嵌套标注和跨链归属另议。特别是多个子树共享生产会话时，应按明确的结构关系装配，不能由先到达的消费者决定 hook。Hanging 与装卸策略继续独立设计。

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

先列出获准与拒绝的嵌套形状及其启动、推进和退出轨迹；确认后由 `Gen.Composition／Booter` 生成静态边界，`Runtime.Execution／Frame／Session` 落实本次执行的关系。**在该阶段单独确认前保留现行嵌套限制。** Middleware 对一棵已有子树作透明标注，背压处理交付容量，两项工作都不预先决定嵌套执行策略。

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
| Hanging 与装卸 | 与 Middleware 的挂起、恢复、装卸关系另行设计。 |
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
| <a id="version-boundaries"></a>gen 内部职责与版本边界 | 共享供值改变了普通资产能读到哪次发布。其后的 Injector／Booter 重构统一静态装配与驱动事实，手写接口与该读取协议保持一致。[内部接口迁移](CORE_DESIGN.md#sdk-migration) |

最近一次 gen 修复已在 FileDemo 验证局部 `raw` 和重导出的 SDK 能力，两个文件分支均返回 `Succ`；八个命名空间生成结果无变化，离线编译通过。该记录只覆盖当时的修复，Middleware 仍处于设计阶段。

<a id="maintenance"></a>
## 计划怎样更新

新语义先在本页展示写法与未决边界；确认后把正式协议写入所属规范，将组合依据登记到 [COMPOSITION](COMPOSITION.md)。实现并验证后，指南再展示可用接口。这里只保留开放事项、必要的完成摘要和验证边界。
