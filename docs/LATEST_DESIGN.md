# 主设计：Algebraic Effect Sys in Haskell

更新：2026-11-08（Stage 2：原子 handler 与业务 effect 分离，`requires` 不生产、缺值等待；SDK 按“源语言 → gen → 编译产物 → 运行时”重组）。本文统一保存设计原则与当前运行协议，并引用图、资产和 Stream 专题作为完整规范。

运行和书写示例见 [GUIDE](GUIDE.md)，工作约束见 [AGENTS](../AGENTS.md)。

按任务跳转：[代码长什么样](#code-shape) · [核心对象](#model) · [设计原则](#principles) · [代码即文档](#code-as-documentation) · [声明式设计](#declarative-design) · [句柄与值](#handles-and-values) · [生成前类型检查](#beforegen) · [gen 是编译器](#compiler) · [注册](#registration) · [Context](#context) · [workflow](#workflow) · [scope](#scope) · [Error](#error) · [生成](#generation) · [SDK 分工](#sdk-layout) · [Stream](#stream)。

## 1. 范围与实现状态

本项目用原生 Haskell 表达可分析的 effect 组合。先看下一节中的代码形态：资产定义、注册字段、原子 handler 和具名 workflow 分别承担一种结构关系；运行入口只负责启动这份组合。

| 范围 | 状态 | 详细规范 |
| --- | --- | --- |
| Pure、Excu、Scoped、Error、Context；有限 workflow | 当前已实现；原子句柄与 Pure 交出 `[String]`，Pure 是生产链中的值变换（2026-11-12）；Error 的驱动链仍待设计 | [运行语义](LATEST_DESIGN.md#runtime) |
| 统一 Prototype、运行图、静态来源与缺值等待 | Stage 1/2 已实现 | [图与来源](EFFECT_GRAPH.md) |
| parallel 兄弟可见、等不到或读不确定的读取在生成期报错、按执行帧的资产 state 与等待的结束 | 已确定，未实现 | [可见范围与等待的结束](#await-visibility) |
| scope 的单例与多例：`requires` 引用已有的一次生产、`requests` 发起新的生产，由此决定实例的共享与清理；按可达性回收、运行结束关闭、close 可选 | 已确定，未实现 | [单例与多例](#scope-identity)、[按可达性回收](#scope-gc) |
| 资产目录与业务模块的顶层白名单 | 当前已实现（Stage 2 取代普通函数的资产检查与构造器归属） | [源码资产](ASSETS.md) |
| Stream 与挂在它下面的解析器 Context、持续资产的历史视图与 lifelong | 已实现（Stage 3）；lifelong 中的失败暂按临时规则终止整次运行 | [第 7 章](#stream)及[完整规范](STREAM_LIFELONG.md) |
| 原子 handler 复用、前驱与驱动装配、按标签路由 | 已实现（Stage 2，2026-11-08）；本文第 4 章即当前协议 | [Next stages](NEXT_STAGES.md#stage-2) |
| gen 作为编译器：SDK 分为源语言、gen、编译产物、运行时四层，生成按阶段执行 | 已实现（2026-11-08） | [gen 是编译器](#compiler)、[编译流水线](#generation)、[SDK 分工](#sdk-layout) |
| 输入契约、持续执行同构、资产访问、结束与资源清理 | Stage 1、2 已实现；后续阶段继续收敛 | [Next stages](NEXT_STAGES.md#stages) |
| 嵌套 lifelong、背压与历史容量等 | 后续专题，本轮不扩展 | [开放事项](NEXT_STAGES.md#deferred) |
| Middleware、Generic Map、Hanging、跨 interpreter 存续 | 尚未实现，具体语义需继续收敛 | [开放事项](NEXT_STAGES.md#deferred) |

实现状态说明代码已接入的范围，不代表全部并发交错或资源逃逸已获证明。过去的编译及 demo 结果概述见 [已有基础与验证边界](NEXT_STAGES.md#baseline)。

<a id="code-shape"></a>
## 2. 代码长什么样

从资产、注册、handler 与 workflow 的代码形态进入各层语义。[完整的 FileDemo 代码导览](GUIDE.md#code-shape)按这个顺序展开；以下用解析这一组声明与实现定位本页的协议章节。

### 2.1 从一组注册与 handler 进入

`Effects.hs` 的 `effects` 列表节选：

```haskell
EffectSpec
  { name = "ExtractFileText"
  , typing = Context { asset = Asset @TextState "FileText", parser = Just "parseFileText", require = True, stream = False }
  , input = "ReadFile"
  , demands = []
  }
```

`Handlers.hs` 中它绑定的 handler，模块头和导入见 FileDemo 源码：

```haskell
instance ParseFileTextLayer m => ParseFileTextHandler m where
  parseFileText = do
    contents <- raw
    text <- case contents of
      [whole] -> pure whole
      _ -> raise (ParseFileTextError "File read returned no text")
    pure (if null text then Blank else Written text)
```

注册给出类别、绑定、前驱与产物，handler 给出原子的读取、解析和 IO。`raw` 是读取句柄这次交出的 list，parser 把它细化成资产的表示类型。沿代码中出现的结构进入对应子模块：

| 看到的代码形态 | 继续阅读 |
| --- | --- |
| `data TextState = Blank \| Written String` | [资产写法](GUIDE.md#types)、[资产约束](ASSETS.md) |
| `EffectSpec`、`typing`、`input`、`demands` | [注册写法](GUIDE.md#effects)、[方法契约](#registration) |
| `instance XxxLayer m => XxxHandler m where` | [handler 写法](GUIDE.md#handlers)、[handler 契约](#registration)、[入口装配](#calls) |
| `requests`、`require @T`、`raw` | [Context 驱动与读取](#context)、[Pure](#pure) |
| `Scoped { open, close }`、`raise` | [scope](#scope)、[Error](#error) |
| `alternative [node "WriteFirstLine", node "AppendLine"]` | [workflow 写法](GUIDE.md#workflow)、[启动协议](#workflow) |
| 生成契约、`generatedPrototype` | [生成与源码同步](#generation)、[图与来源](EFFECT_GRAPH.md) |

<a id="model"></a>
### 2.2 核心对象与层次

| 对象 | 表达什么 | 不应承担的职责 |
| --- | --- | --- |
| EffectSpec／typing | 操作类别、绑定的 handler、前驱与资产访问 | 原子业务方法体 |
| Input | 前驱：gen 在 handler 之前装配执行的 effect；挂接的 Context 与 Pure 用 raw 读它交出的 list | 隐式传值，或被方法体调用 |
| Pure | 生产链中的纯值变换：从上层的 raw 取 list，变换后交给下面的 Pure 或 Context | IO、读取资产，或作为 AST 末端 |
| asset／契约 | Context 对外发布的具名业务值类型：表示类型的细化，按名字解析唯一来源 | 运行时 scope 所有权本身 |
| demands | 驱动或读取哪份资产 | 指定随运行时序变化的生产者 |
| handler | 不带参数的原子类方法：按表示类型读取、执行 IO、解析；可注册到多个 effect | 调用上游或其他 handler，隐藏一套框架外的组合 |
| original chain | 以原始操作为末端的调用组合 | Context 生产链的 AST 替身 |
| Context chain | 因取值或挂接解析而进入的生产／读取链 | 独立放进 AST 的 Context target |
| AST node／branch | 挂载完整链末端，决定启动与执行控制 | 展开每个 Input 方法或传递业务产物 |
| Prototype | 注册、方法结构、workflow、图及来源等纯事实 | 函数、线程或活资源 |
| RuntimeGraph | 实际活动、执行出身、绑定与资源关联 | 重新推导静态图或完整调用历史 |
| ScopeTree | scope 依赖的共享节点 DAG | workflow 先后顺序或普通 callback 图 |

业务组合分成两个层次：注册的 Input 与 demands 组合一条链，gen 把它装配进末端的入口；AST 通过尾部 target 启动这条链，再组合多条链。生成器能提取 handler 的读取结构，不解释原子 IO 的业务意图。

```mermaid
flowchart LR
    F[Types / Effects / Workflow] --> G[gen：编译器]
    H[原生 Handlers] --> G
    G --> P[Generated 契约、包装、Prototype]
    P --> I[interpreter：校验与一次 cata 装配]
    I --> T[AST target 启动 original chain]
    T --> C[驱动进入 Context chain]
    T --> R[RuntimeGraph / scope 使用登记]
    C --> R
```

首次没有 Handlers 时先生成契约，再编写原生 handler instance。执行副本与手写模块分别接受检查，不能在同一导入链重复引入相同 instance。

<a id="principles"></a>
## 3. 设计原则

<a id="code-as-documentation"></a>
### 3.1 代码即文档，文档即代码

代码的书写形态是框架的设计契约。读者应能沿原生 Haskell 的类型、声明、引用和方法体，读出程序的资产词汇、能力边界、取值关系、启动方式与原子操作；人、HLS 和 agent 共同面对这份源码。

“代码即文档”要求架构信息落在可阅读、可定位、可检查的结构中。Effects 的 typing／Input／demands、Workflow 的具名 branch、Handlers 的原子方法体各自表达对应关系；命名使用业务概念，相关方法归入相应 instance。需要为理解一段组合而另找隐藏注册、外部 impl 或约定俗成的调用顺序时，应检查是否缺少明确的结构表达。

“文档即代码”要求功能设计具体到开发者实际会写的 Haskell 形态。设计说明应给出相互对应的资产、注册、instance 和 workflow，解释生成器从哪里取得证据、interpreter 怎样装配，并区分当前可用代码、节选和待实现接口。这是语义与书写契约的对应要求；Markdown 本身不成为新的执行语言，也不承诺文档自动往返生成任意业务实现。

| 阅读层 | 应直接读出的信息 | 对应边界 |
| --- | --- | --- |
| Types 与生成契约 | 业务资产的结构、名称与细化身份 | 原生 ADT 与类型检查；源码资产规则另行检查 |
| Effects | 类别、绑定的 handler、Input 前驱、demands 驱动与读取 | 声明解析、入口装配与生成的 Layer |
| Handlers | 按表示类型读取、解析、IO 与 raise | 原生 Haskell；读取结构提取与顶层白名单 |
| AST／Workflow | 挂载的完整链末端和 branch 启动关系 | workflow 类型与 Prototype 校验 |
| Generated／--structure | 派生接口、协议包装、静态装配事实与推导证据 | 可审查的普通 Haskell 和同一 Prototype；派生产物不另立手写权威 |

文档的主要阅读入口使用独立标题“代码长什么样”，放在项目介绍之后、详细协议之前。README 用自然语言分层介绍这是什么框架、能做什么、为什么这样设计、代码长什么样及如何开始。开篇概括项目，正文从业务组织的问题解释设计选择及其作用，再以一行 Main 和 asset、effect、handler、workflow 的职责与关系引入使用指南。标题服务于读者的阅读路径，概括、介绍等结构提示不直接固定成栏目名。Context 等具体 effect 类别在指南中结合代码引入，完整模块声明与 import 也在指南展示。各模块的技术细节与具体启动命令在指南展开，README 随正文中的相关概念和开发步骤自然引入文档链接。指南以同一个业务例子的原生 Haskell 代码块依次展示资产、注册、instance 和 workflow，每块标明所属文件、节选范围和继续阅读的位置，再展开字段与运行语义。

新增功能须先展示上述层次中实际受影响的写法，再说明新增语义及其依据。已有机制可表达的关系沿用已有写法，原子方法作者只需理解本方法的契约、可用能力和固定协议。重构除保持执行语义外，还要保持架构关系在源码中的可见性与可提取性；把值操作移出 handler 方法体，或把组合藏进方法体，不能仅以运行结果相同作为依据。

注释说明意图、取舍和边界，结构承载可检查的关系。方法可调用不证明它必然执行；结构可提取不证明任意业务 IO 正确或可由 gencode 判断。文档中仍需记录 SDK 的生命周期、故障等通用协议及当前保证范围。

更新接口时同步其示例、语义说明及相关生成产物。可运行示例优先引用现有源码，节选标明省略范围；设计方案标明未实现状态。接口与文档不一致时明确差异并修正，不用“代码即文档”把偶然实现行为升级为设计决定。

<a id="declarative-design"></a>
### 3.2 声明式组合与原子实现

声明式设计负责表达业务组合的结构与契约：资产类型描述业务数据，Effects 声明操作类别、绑定的 handler、Input 前驱与 demands 驱动／读取关系，Workflow／AST 描述挂载位置和启动方式。业务作者以固定声明和原生方法引用表达这些关系，生成器提取并检查结构，interpreter 按确定的协议装配和执行。

原子行为由 handler 方法实现，包括 IO、解析、ADT 模式匹配和局部计算；handler 不调用上游，也不调用其他 handler。Input 声明前驱，gencode 把它装配进入口、在方法体之前执行；demands 声明驱动与读取，requests 在入口驱动生产，handler 的 require 按表示类型读取；AST branch 规定完整链何时启动。多个 effect 可以共享一个原子 handler，各自的 Input 与 demands 决定它在哪条链上、读哪份资产。声明、原子实现与 SDK 执行责任因此都有明确边界。

例如 `demands = [requires "FileTextWritten"]` 声明读取，handler 中的 `require @String` 经路由读到该分支资产；workflow 再选择该消费链的末端并组织启动。声明可以被静态检查、序列化和第三方工具生成，实际返回值、IO 成败及阻塞行为仍由原子实现和运行协议决定。声明式结构不要求 handler 全部是纯函数；SDK 只执行声明的前驱与驱动。

这一原则与另外两项设计相互衔接：“代码即文档”要求组合关系直接可读、可提取；“句柄操作和值操作分离”让前驱与资产依赖分别表达。保持生成前的原生 Haskell，业务作者按本地契约实现原子行为，通用装配、来源路由与生命周期协调由 SDK 提供。

设计新功能时，先明确组合语义、生产与消费职责、启动和结束边界，再决定注册字段与 Haskell 接口。组合关系应保持为有限的结构、引用和契约，即使它描述的是持续执行的程序。

原子方法保存无法由框架穷尽解释的业务值操作和外部 IO。生成器提供确定的结构连接；不通过解释任意 IO 或让 LLM 理解完整 runtime 来恢复连接。新增语义尽量收敛在已有层次内，不为实现便利增加用户 key、手写 layer 或独立 impl；Layer 由 gen 从绑定推出，用户不手写。

现有源码、demo 和历史编译结果是实现证据；不反过来固定新设计。需求不清或与证据冲突时先查缺口；声明语法变更单独确认，不添加未约定的兼容层或特殊情况。

<a id="handles-and-values"></a>
### 3.3 句柄操作和值操作分离

框架分别表达“执行哪些操作、按什么前驱组合”和“产生什么业务值、怎样按资产读取”。这里的句柄指原子句柄类 effect（Excu、Scoped）及其 handler；文件、连接等资源对象则由对应资产表达。

**句柄操作**由注册的 Input 组合：gen 把 Input 装配为前驱，在 handler 之前执行；方法体不调用上游。Input 不传递业务值；前驱失败原样传播，改道写在 AST 的 alternative 中。

**值操作**由 Context 的生产、解析与资产承载，消费方通过 demands 声明驱动与读取。生产链中对句柄输出的纯变换（去重、排序、过滤）由 Pure 承担，Context 只做细化解析。requests 在入口驱动生产，require 按既有来源与捕获读取，不生产，还没有值时等待发布；持续资产的读取返回本次确定的 History 视图。handler 用原生 ADT 模式匹配和计算处理这些值；值只经资产流动，跨 handler 的业务产值通过 Context 发布。资产来源与 scope 的资源关闭归属分别管理。

两者通过 Context 衔接：Excu.handler／Scoped.open 交出的 `[String]` 交给挂接的 Context 解析为业务资产，中间可以经过一串 Pure；Stream 的原始输入交给挂在它下面的 Context 解析，写法与挂在原子句柄下的 Context 相同。比如 FileDemo 中，`readFileContent` 执行读取操作，挂在它下面的 `parseFileText` 用 `raw` 把读取结果解析为 `FileText`，消费方通过 `requires "FileTextBlank"` 或 `requires "FileTextWritten"` 读取对应分支资产。前驱关系和资产读取关系都能从注册与 handler 的读取中读出，详见[原子输出挂接](#context)与[持续生产](#stream)。

这种分离是职责与契约的划分，不新增独立 impl 层。值操作写在 handler 方法体内，业务模块顶层不定义普通函数，见[源码资产约束](ASSETS.md)；同一个 handler 可以先读取，再用读到的值完成原子操作。

AST 挂载完整 original chain 的末端，并规定启动和执行控制。Context chain 由驱动、读取或挂接解析带起。Node algebra 只 lower 选定末端；末端入口按注册装配驱动、前驱与 handler，不补跑未声明的上游。

业务入口保持 `interpreter ast effects`。闭包、Reader、线程和锁属于 SDK 执行装配，不能变成每个业务 handler 的额外装配工作。

<a id="beforegen"></a>
### 3.4 生成前仍是原生 Haskell

手写 Types、Effects、AST／Workflow 和 Handlers 必须能由 GHC／HLS 直接解析、名称解析和类型检查。类方法调用与 ADT 使用保持原生 Haskell；不依赖字符串调用、专用伪语法或生成器修复类型。

“生成前”指生成业务执行副本之前，仍需要已存在且同步的 Generated/Effects 契约。首次先从声明生成接口，再写 Handlers。手写模块与 Generated/Handlers 含同一批 instance，应分别作为检查和运行入口，不能在同一业务导入链重复引入。

生成器可以提取读取结构、生成 MethodGen、入口与按标签的路由；运行副本原样保留方法体。HLS 类型检查、gencode 结构提取和顶层白名单检查是不同边界，不能互相替代。

### 3.5 可观察组合与原子方法

组合写在注册与 AST 中，handler 方法体只含读取、raise 与原子计算。纯结构提取识别 `require @T`、`raw`、分支和标准组合，擦除不含读取的业务值计算，再按绑定代换成 effect 方法的读取结构；handler 直接调用其他 handler 或 effect 方法、读取经未知高阶组合传递时必须诊断，不能默认为空图。

所有值操作写成 handler 的类方法并注册，才能被 SDK 驱动和静态分析：业务模块顶层不允许普通函数，方法体内的局部函数与 lambda 不限制。资产集合、顶层白名单与资产目录统一见 [ASSETS](ASSETS.md)。这些约束不追踪值来源，也不证明原子方法的 IO 粒度、业务正确性或所有资源别名。

### 3.6 静态描述与运行状态分开

Prototype 保存结构和事实，不能保存执行函数、类字典或活资源。运行时共享 Prototype，另保存活动 chain、执行出身、资产绑定和 scope 实例。静态位置、运行调用、资产 publication 与资源 owner 必须区分。

ScopeTree 单独构造并保持无环，供依赖清理和 Error 祖先导航使用。AST 先后顺序或 callback 关系不能直接冒充资源父子关系。完整算法归 [EFFECT_GRAPH](EFFECT_GRAPH.md)。

声明的可序列化性不意味着运行中的资源也可以序列化。解释器内部使用函数、闭包和 IO 是正常实现方式，不需要把这些内部对象变成 facade 语法。

### 3.7 自动装配必须有明确依据

规则按“输入前提 → 推导结构 → 运行行为 → 无法判定时的诊断”书写。能力去重不等于实际调用去重，结构可达不等于本次生产或后续持续推进；等待也不能自动解释为失败。

资源的共享与清理同样只凭声明推导，不用 key 或寿命标签：`requests` 发起一次新的生产，`requires` 引用已有的一次生产，开启参数以哪种方式进入 scope，决定这次开启是多例还是单例，也决定实例何时关闭。规则见[单例与多例](#scope-identity)（已确定，未实现）。

Stream 的目标是让原子方法作者只需理解本方法的输入输出。gencode 静态推导 BootPlan，interpreter 执行它；不在运行中猜测业务属于 socket、event 还是 behavior，三种驱动关系目前的写法见 [Stream 第 4.1 节](STREAM_LIFELONG.md#drives)。完整匹配与回调规则作为[主设计第 7 章](LATEST_DESIGN.md#stream)的一部分维护。

### 3.8 约束、保证与开放问题

方法签名、生成期结构检查、运行时协议和外部 IO 保证必须分别说明。绑定稳定性由 ContextStore 及共享 ownership 实现，不能从“描述是纯的”直接推导出重复 IO 幂等或资源安全。

Error 的驱动链、Generic Map、跨独立 interpreter 存续、任意逃逸资源和恢复已展开 continuation 等仍有开放边界；状态见 [Next stages](NEXT_STAGES.md)。不以旧候选接口充当已接受的当前 API。

新增功能先给出 facade、生成契约、runtime 责任及 failure／cleanup 边界，再分批实现。当前探索阶段只做必要普通编译，不自行新增测试、负例或额外检查门槛。

<a id="compiler"></a>
### 3.9 gen 是这个 EDSL 的编译器

框架分成四层，gen 居中：

| 层 | 是什么 | SDK 位置 |
| --- | --- | --- |
| 源语言 | 用户写的 Types、Effects（注册）、AST 与 Handlers，全部是原生 Haskell | `Framework.SDK`、`Framework/Language/` |
| 编译器（gen） | 读取源程序，降级为一张图，在生成期定下链的组合、读取路由与合法性，输出 Generated | `Framework.Gen`、`Framework/Gen/` |
| 编译产物 | Generated 下交给 GHC 的 Haskell（契约、入口、按标签的路由）与其中的 Prototype（静态结构） | `Framework.Prototype`、`Framework/Prototype/`、`Framework.Generated` |
| 运行时 | 执行编译产物：取值、scope、Error、会话与 workflow 调度 | `Framework.Program`、`Framework.Runtime`、`Framework/Runtime/` |

依赖只从上往下：源语言不导入其他层；gen 导入源语言与 Prototype 的数据模型，不导入运行时；运行时导入源语言与 Prototype，不导入 gen。demo 的可执行程序不链接 `Framework.Gen.*`，`effect-codegen` 不链接 `Framework.Runtime.*`。Generated/Assets.hs 是审查用的资产目录，不进入运行导入链。

能在生成期判定的组合、读取路由与合法性问题，都由 gen 报错，不留给运行时。运行时启动前只核对编译产物与当前源码是同一份——注册快照、Handlers 指纹、AST 的层级——并校验 Prototype 自洽，不重新推导结构。读取同样只执行编译结果：按生成的来源表取值，缺值时等待发布而不生产；读取权限在生成期确定，运行时不查声明表。

流水线的阶段、输入输出与各阶段的检查见 [4.9 编译流水线](#generation)，源码目录见 [SDK 分工](#sdk-layout)。

<a id="runtime"></a>
## 4. 当前运行协议

本章描述有限执行的当前协议。Stream 的新增角色、历史视图和持续执行由第 7 章单独规定。

<a id="registration"></a>
### 4.1 注册与 handler 契约

统一使用 EffectSpec 注册，effect typing 有 Pure、Excu、Scoped、Error、Context、Stream 六类；Stream 是持续数据源，只由生产会话驱动，规则见第 7 章。typing 的字段写 handler 名：handler 是不带参数的原子类方法，一个 handler 可以注册到多个 effect。effect 是业务配置，给出类别、绑定、前驱（input）与资产访问（demands）；effect 自身的入口方法名由 gen 内部生成，用户不写也不调用。对外产值的细化解析归 Context，生产链中的纯值变换归 Pure，不另设 Map。

| 注册类别 | 绑定的 handler | handler 签名 | gen 生成的内部入口 | SDK 执行责任 |
| --- | --- | --- | --- | --- |
| Pure | handler（必填） | m [String]，Layer 只有 Raw、Raises，不含 MonadIO | run名字 | 只在生产链中：用 raw 读上层交出的 list，结果只交给下面的 Pure 或 Context；不声明 demands，不作为 AST 末端，见 [Pure](#pure) |
| Excu | handler | m [String] | run名字 | 交出的 list 只交给挂接的 Context（可经 Pure）；入口装配驱动与前驱并承接失败 |
| Scoped | open、close | 均为 m [String] | open名字、close名字 | 开启参数读取同参共享／驱动 fresh；完整链持有实际实例，末个使用者退出且无子 scope 保留时 once-spare |
| Error | detect、resolve | 均为 m () | detect名字、resolve名字 | 只处理关联 scope 的失败；沿 ScopeTree 祖先顺序检测，Succ 后调用可选 resolve，保存原始与次生失败 |
| Context | parser | m 表示类型 | getT；`require = True` 时 readT，`stream = True` 时为 streamT | getT 执行前驱与 parser 并包装发布；读取先用 state，无值时等待发布，不生产；失败保留该来源旧值；持续资产见第 7 章 |
| Stream | handler | m String | next名字 | 只由生产会话驱动；不作为 AST target |

#### 注册构造

```haskell
typing = Excu { handler = Just "printSummary" }
typing = Excu { handler = Nothing } -- 不声明入口
typing = Pure { handler = Just "validateFileName" }

typing = Scoped { open = Just "openSession", close = Just "closeSession" }

typing = Error
  { detect = Just "detectFileSession"
  , resolve = Just "resolveFileSession"
  , handles = [RaisedBy "readFileContent", RaisedBy "writeFirstLine"]
  }

-- 生成 getCrawlSessionInfo、readCrawlSessionInfo
typing = Context { asset = Asset @SessionInfo "CrawlSessionInfo", parser = Just "sessionInfo", require = True, stream = False }

-- 持续数据源：每次取得一份原始输入，由挂在它下面的 Context 的 parser 解析
typing = Stream { handler = Just "nextReading" }
```

注册使用普通 ADT 的不同构造器携带各自属性，不因字段不同而引入 type family 或 data family。handler 名绑定使用 Maybe String，Nothing 表示未绑定，不把返回值改成 Maybe；handler = Nothing 的 effect 保留 Input 关系，被 target 选中时报没有入口；Pure 没有可选的入口，必须绑定 handler。SDK 不猜测 handler 名，也不生成默认成功操作。

Context 以 `asset = Asset @表示类型 "资产名"` 声明资产，parser 必填；`require :: Bool` 决定是否缓存最新值并生成 readT；`stream :: Bool` 声明持续资产，缓存历史，读取方法为 streamT。`stream = True` 当且仅当 Input 是 Stream，且必须同时 `require = True`。Context 的 request 角色与 RepeatRequest 已取消：驱动由消费方的 requests 或上游 Stream 表达。

消费方 demands 以 requests／requires／streams "资产名" 引用资产，访问方式须对应生产方的声明：requires 需要 `require = True`，streams 需要 `stream = True`，挂在 Stream 下的资产不能 requests。Error 以 handles 声明处理的故障：RaisedBy 写 handler 名，ScopeFaultIn／ContextFaultIn 写 effect 名；关联 scope 沿 Input／requests 推导最近的 Scoped，必须恰好一个。Error 由 Root 的故障协议调用，不作为 Node target，其他 effect 的 Input 不能指向 Error。

注册中的 EffectTyping 保存 handler 绑定，关联 Typing 只保存 SDK 的 EffectKind 类别标签，不把运行时 String 搬入类型级。只有 Context 的 asset 声明业务产物；原子句柄与 Pure 交出的 `[String]`、Stream 的原始输入 String 都不是业务产物。完成边界由 SDK 返回 Succ value 或 Failed failure，不含 Pending。

使用 SDK 的 effect-codegen 输出普通 Haskell 源码，保留 Generated 模块供 review，避免 Template Haskell。手写模块用 -Werror=missing-methods 要求实现 handler 方法。只做必要的普通编译，不增加测试或额外检查门槛。

#### handler 契约

每个 handler 名生成一个只有该方法的类 `XxxHandler`、一份能力约束 `XxxLayer` 和错误类型 `XxxError String`。业务 instance 对载体 m 泛型：`instance XxxLayer m => XxxHandler m`。

| 约束 | 什么时候有 | 方法体可写 |
| --- | --- | --- |
| `Reads T m` | 绑定它的 effect requires 了表示类型为 T 的资产 | `require @T` |
| `Reads (History T) m` | 绑定它的 effect streams 了持续资产 | `require @(History T)` |
| `Raw m` | 绑定成挂接的 parser 或 Pure | `raw :: m [String]` |
| `Raises XxxError m` | 总是 | `raise (XxxError "...")` |
| `MonadIO m` | Pure 以外总是 | `liftIO` |

Layer 不含 Input 的 effect 类、effect 能力标记、细化资产、其他 handler 的类或 request；单独的 requests 不带来 Reads。一个 handler 只有一份 Layer，各绑定推出的方法类型与 Layer 必须一致，否则 gencode 报错。`Reads`、`Raw`、`Raises` 定义在 Framework.Language.Handler，由 Framework.SDK 导出；`Raw`、`Raises` 是暂定名。

失败属于 handler：raise 的错误类型由 handler 名决定，不随绑定改变，Errors 中的分类是 `XxxFailure`；发生在哪个 effect 由 SDK 记为 Failure.origin，只是诊断位置。原始 Failure 保存 origin、detail 分类和 message，传播或次生失败不覆盖原故障；不要求用户声明错误 ADT。

资源依赖按真实需要声明。类约束提供读取可用性，不证明哪一份资源仍可使用；绑定身份、失效、释放状态和收尾次序由 SDK 管理。

#### 类型标签与按标签路由

生成副本为每个 effect 引入类型标签：

```haskell
newtype At (effect :: Symbol) value = At { runAt :: App value }
```

handler 方法体原样复制，在 `At "名字"` 上实例化。Reads、Raw、Raises 按标签生成 instance：`Reads T (At "E")` 把读取路由到 E 的 demands 中表示类型为 T 的那份细化资产，普通资产解包 readT，分支契约经 projectContext 投影当前构造器，持续资产解包 streamT，只 requires 一个持续资产时经 latestContext 取最新一条；`Raw (At "E")` 由 E 的直接 Input 回答；`Raises XxxError (At "E")` 转成 Errors 中的 XxxFailure。GHC 在编译期按标签选定读取，运行时不按调用者查表。

```haskell
instance FrameworkRuntime.Reads (FileHandle) (At "WriteFirstLine") where
  require = At ((\(FrameworkGenerated.OpenedFile value) -> value) <$> readOpenedFile)

instance FrameworkRuntime.Raw (At "ExtractFileText") where
  raw = At (runReadFile)
```

<a id="calls"></a>
### 4.2 入口装配与实际调用

注册定义契约与前驱，gen 把它们装配进每个 effect 的入口；handler 只写原子操作。入口顺序是**驱动 → Input → 方法体**：

```haskell
-- Crawler：先驱动 URL，再开启会话，最后运行共用的 fetchPage
runFetchPage = ⟨入口包装⟩ $
  getStartURL >> openCrawlSession >> runAt @"FetchPage" FrameworkGenerated.fetchPage

-- Context：执行 parser 并包装成资产
getStartURL = ⟨入口包装⟩ $
  (FrameworkGenerated.StartURL <$> runAt @"StartPage" FrameworkGenerated.startURL)
```

- **驱动**：effect 的 requests 依次执行对应资产的 getT，重新生产并发布当前 origin 的绑定。
- **Input**：前驱的入口在方法体之前执行；方法体不调用上游，也不捕获前驱的失败，失败后的改道用 AST 的 alternative。Scoped 前驱已开启时复用实例，跳过 open 的方法体。
- **方法体**：在 `At "名字"` 上运行绑定的 handler；Context 的入口再把结果包成资产。
- **挂接**：Input 是 Excu、Scoped、Pure 或 Stream 的 Context，以及 Pure 自身，不把 Input 当作前驱执行，raw 由 Input 的入口回答：注入时由本次输出回答，被驱动时执行该入口，Stream 下为 `(: []) <$> next名字`。Pure 的入口只是 raw 的中间一段，不改变调用者身份。
- **只运行 handler 的入口**：close、detect、resolve 不驱动，也不执行前驱。

生成器读取方法体中的读取（`require @T`、`raw`），形成每个 handler 的原子形状；再按绑定把表示类型代换成该 effect 的细化资产读取，与入口的驱动和前驱一起组成 effect 方法的纯结构。它不解释任意 Haskell 业务值语义。handler 方法体不能直接调用其他 handler 或 effect 的方法，gencode 报错：那样会绕过 effect 入口，丢失 Input、驱动和错误位置。

需要分别识别以下对象：

- 原子 handler，确定方法类型与 Layer。
- 业务注册（effect），选择类别、绑定 handler，并声明前驱和资产访问，供 AST 或其他注册引用。
- 声明中的调用位置，确定输入来源和后续关系。
- 本次执行中的调用，确定输出所属的执行和 scope。
- 输出绑定，确定消费者读取的那份成功值或错误负载。

这些身份由静态引用、执行上下文和闭包局部绑定共同表达：Origin 为 NodeId 加执行序号，ActivationId 识别一次活动调用；无 owner 绑定按 origin 与 Context 来源保存在运行权威表。一份注册可以产生多次调用，读取按原型许可来源共享结果。已开启 scope 的能力复用按 owner 协议处理，不把它误作普通操作结果的自动缓存。

Input 表达操作的前提关系，业务值来源单独由 demands 表达；Context 挂接某个句柄解析其输出，不因此把句柄的输出变成隐式传值。

#### Root 的统一入口包装

生成入口统一包装原协议：withErrorPath 记录失败路径上的 scope，handleFailure 接入 Failure 捕获与 Error 处置，atomicHandle／atomicScope 与 openScope／closeScope 包装原子句柄和 scope 生命周期，streamHandle 包装 Stream，callContext／readContext 包装 Context 的生产、挂接注入与读取。业务不写 handler／super 前缀。

根入口不修改业务方法体、不预执行未声明的 Context、不另行 boot 或 lower 上游。scope 复用仍经过调用入口，但可以跳过资源方法体。独立 Middleware typing 及装卸策略保留为后续专题，尚未实现，见 [Next stages](NEXT_STAGES.md#middleware)。

<a id="context"></a>
### 4.3 Context、驱动与读取

手写 input 只允许 Root 或非 Context、非 Error 的 effect；Context 经 demands 接入。生产者自身仍可有 Input、消费其他 Context，但不能作为 AST node 的末端。沿 Input 与 requests 收集 scope；读取不执行 getT，还没有值时等待发布。input 指向 Excu、Scoped 或 Stream 的 Context 挂在该句柄下，由句柄入口注入解析其输出。

生产方与消费方分别描述，Context effect 自身也可以消费别的 Context：

```haskell
typing = Context { asset = Asset @PageSummary "LinkedPageSummary", parser = Just "extractSummary", require = True, stream = False }
input = "FetchLinkedPage"
demands = [requires "LinkedURL"]
```

typing 中是本 effect 绑定的 parser 与生产的资产；demands 中是本 effect 驱动或读取的资产，不指名生产方。来源在注册集合中按资产名唯一解析，多个生产方即报错；生成器不会按距离或拓扑替用户选择来源。

<a id="refinement"></a>
#### 细化资产：同一表示类型的来源键

```haskell
-- Crawler/Types.hs：表示类型，只描述数据结构
data PageSummary = PageSummary
  { summaryURL :: String
  , summaryTitle :: String
  , summaryContent :: String
  , summaryLinks :: [String]
  } deriving (Show, Read, Generic)

-- Effects.hs：把同一个表示类型细化为两个资产，共用一个 parser
typing = Context { asset = Asset @PageSummary "StartPageSummary", parser = Just "extractSummary", require = True, stream = False }
typing = Context { asset = Asset @PageSummary "LinkedPageSummary", parser = Just "extractSummary", require = True, stream = False }

-- Generated/Effects.hs：每个资产一个名义类型
newtype StartPageSummary = StartPageSummary PageSummary
newtype LinkedPageSummary = LinkedPageSummary PageSummary
```

`Asset @表示类型 "资产名"` 把表示类型细化（refine）为一个资产（refinement asset）。生成的 newtype 是零开销、可 coerce 的包装，不改变数据，只引入一个新的名义类型（nominal type）；字段和构造器仍由表示类型决定。

资产的读取是按类型寻址的依赖注入：消费方在 demands 中只写资产名（`requires "StartPageSummary"`），handler 以表示类型读取（`require @PageSummary`），不指名生产方。生成器以“表示类型 + effect”为键生成按标签的 Reads 实例，路由到这个 effect 声明的唯一细化资产；运行时同一资产的读取按静态来源表选择发布。按类型寻址要求一致性（coherence）：一个 effect 内一个表示类型恰好对应一份资产，一份资产恰好对应一个生产方。

同一表示类型往往有不同来源和含义，例如起始页与链接页的摘要都是 PageSummary。细化为两个名义类型后，每份资产只有一个生产方，读取被锁定到注册选择的来源（来源锁）。同一个 handler 注册到两个 effect 时，由各自的 demands 决定读哪一份；一个 effect 内不能读两份同表示类型的资产，需要两个同类型值的操作用不同的表示类型（角色类型）区分。

细化只分配身份，不承担数据结构。和类型的分支契约是在细化资产之上按构造器再细化（`FileTextBlank`、`FileTextWritten`），表示类型是构造器的字段，无字段时为 ()。资产名同时决定生成的方法名（getT、readT、streamT）；同一份数据需要两个独立来源时，各自细化为不同资产。

<a id="demand-contract"></a>
#### 资产来源与访问约束

**每个 refined asset 固定一个表示 ADT 和唯一 Context 来源。** 这一点对普通和持续资产相同，也检查当前没有消费者的声明。requests、requires、streams 是同一资产的访问方式；同一消费者可以为同一资产声明多种合法方式，也可以依赖多个不同资产。访问方式和不同运行时 publication 不创建新的静态来源身份。分支契约继续由基础资产的唯一生产方投影。

```haskell
-- 同一个资源资产：开启前驱动生产，open／close 读取
-- Effects.hs 节选
demands = [requests "OpenedFile", requires "OpenedFile"]

-- Handlers.hs 节选
instance CloseSessionLayer m => CloseSessionHandler m where
  closeSession = do
    FileHandle path file <- require @FileHandle
    outcome <- liftIO (tryIOError (hClose file))
    either (raise . CloseSessionError . displayException) pure outcome
    liftIO (putStrLn ("[close] " ++ path))
    pure []
```

handler 直接在 `<-` 左侧匹配表示类型的构造器，或先具名绑定再 case；和类型的业务分支用 case 或 lambda-case 表达，失败用 raise。SDK 不增加 MonadFail，不把类型类约束当作执行过模式匹配的证明。Stage 1 对资产包装构造器的接收形态检查已随 Stage 2 取消：handler 不写资产类型。持续读取的 History 是抽象视图，通过 latest／historyEntries／historySize 观察。

每个 requires／streams 声明的资产须有读取依据：绑定的 handler 中对该表示类型的读取，或现有 Prototype 中 alternative 选择／streams 交付的控制读取。完全没有依据的声明在 gencode 报错。检查以 effect 和资产为单位，不强制每条路径都读一次。

当前返回形态：普通资产的读取返回表示类型，分支契约返回当前构造器的字段；持续资产按访问方式，streams 返回 `History 表示类型`（本次交付为止的历史），requires 返回最新一条。T 与 History T 是同一个资产的不同结果形态，不是两个来源；读取写法与视图位置的收敛归 [Stage 4](NEXT_STAGES.md#stage-4)。

Gen.Demand 保存唯一来源、访问解析与结果形态的纯规则；Prototype 保存解析事实；Gen.Bind 按绑定检查读取路由与读取依据；运行时继续执行已确定的捕获、可见性、缺值等待与 ownership 协议。结构检查不移动取值、不提前求值、不合并重复驱动，也不证明所有路径、字段使用、case 穷尽或业务计算正确。

手写 Handlers 保持原生语法，运行仍编译 Generated/Handlers 的副本，修改实现后须重新生成。

#### 驱动与读取的运行协议

驱动（requests）每次重新生产，成功后将同一个值发布为当前 origin 的新绑定。读取先使用当前捕获，再按 protoSources 查本次唯一已发布的可见来源。读取不生产：仍没有值时，它像 await 一样阻塞当前链，等之后的一次普通发布再按同一来源表重读，不报错。值只来自 `requests` 驱动、alternative 的选择读取（见 [workflow](#workflow)）、挂接注入与 Stream 会话。当前可见范围只有 AST 保证先完成的前驱与本入口自己的发布，parallel 兄弟互不可见，所以可见范围内没有生产的读取会一直等待，注册需要写出驱动它的 `requests`。诊断、自动 cleanup、close 期间及 scope 资源 Context 缺值不等待，报 `ContextNotInitialized`；这些阶段的显式生产仅更新局部快照。生产的值按 request 被 scope 开启参数观察，读取到的值按读取观察。

刷新失败不覆盖旧绑定，错误原样传播，已完成操作不回滚。普通无 owner 绑定按 origin 保存在一次 interpreter 的权威表，current capture 固定已读取值。scope 例外只覆盖资源 owner 绑定；实例快照里的无 owner 辅助值不能通过资源复用绕过静态来源路由。

读取权限在生成期确定：gencode 拒绝 handler 读取未声明的表示类型，只为声明了 requires／streams 的 effect 生成读取实例，运行时不按当前消费者查声明表。SDK 不预初始化 Context，未声明的上游不执行。

AST 组织链的启动次序，也为跨链来源提供因果可见性。Crawler 中 parallel 先抓取并注入解析两页，chained 再打印；共用的打印 handler 读取第一阶段发布的摘要，按各自唯一来源读取，不重复抓取。Generic Map 仍待设计。

业务表示类型在 Types.hs 用原生 data/newtype 单独定义，注册以 `Asset @表示类型 "资产名"` 引用并细化为资产。TypeRef 通过 Typeable 识别 SDK 的 Output 构造器以拒绝嵌套完成协议，不解析显示字符串；其余业务类型保存显示名称，Generated 模块须能解析该类型名。它不保存完整数据定义，也不代表任意 Haskell 类型结构都能被第三方工具解释或被 Generic Map 自动适配。

当前完成结果为 Succ value 或 Failed failure。SDK 按 handler 生成错误类型、按标签的 Raises 实例与 Errors 分类；用户写 `raise (ExtractSummaryError message)`。Except 使普通 do 短路，上游失败原样传播，lower 只解释登记的末端，最终边界只封装一次 Output。当前不设 Pending；运行图提供活动 chain 的调用身份与关联，逐方法传播历史及通用 IO 异常接入仍未实现。

#### 消费声明与读取权限

同一消费者对同一资产的同一访问方式只能声明一次。requires "T" 或 streams "T" 授予读取权限，读取本身不刷新；requests "T" 只驱动，不授予读取权限；挂在 Stream 下的资产只由会话生产，不能 requests。Scoped 至多 requests 一个资源 Context。声明检查由生成器执行。

#### 原子输出挂接与失败隔离

Excu.handler／Scoped.open 成功后，SDK 以根调用身份执行挂接 Context 的 getT；parser 的 raw 由本次输出回答（中间可以经过一串 Pure，见 [Pure](#pure)），不重复执行句柄。挂在 Stream 下的 parser 沿用同一写法：会话每取得一份原始输入调用一次 parser，raw 由这份输入回答（见第 7 章）。注入失败留在注入内部，不进入原链也不触发 Error；资产没有发布，之后读取它的位置等待下一次发布。

parser 被 requests 驱动或被选择读取驱动时，raw 直接执行句柄入口，不再次注入；复用 open、重复 close、诊断与自动收尾不产生新的挂接注入。close 没有挂接点；scope 的资源 Context 不能挂在请求它的 Scoped 下。生成入口通过 atomicHandle／atomicScope 包装，挂接目录为 contextInjections。

这是有限执行的基线；持续生产中 parser 的故障不在注入内隔离，会话失败并通知等待方，见 [Stream 第 9 节](STREAM_LIFELONG.md#failures)。

<a id="pure"></a>
#### Pure：生产链中的值变换

**状态：已实现（2026-11-12）。** 迁移与验证见 [Next stages](NEXT_STAGES.md#pure-pipeline)。

FileDemo 的文件名生产链：句柄交出路径，Pure 检查后原样交下去，Context 解析成文件名资产。

```haskell
-- Effects.hs 节选
EffectSpec { name = "LocateFile", typing = Excu { handler = Just "locateFile" }, input = "Root", demands = [] }
EffectSpec { name = "ValidateFileName", typing = Pure { handler = Just "validateFileName" }, input = "LocateFile", demands = [] }
EffectSpec { name = "FileLocation"
           , typing = Context { asset = Asset @FilePath "FileName", parser = Just "parseFileName", require = True, stream = False }
           , input = "ValidateFileName", demands = [] }

-- Handlers.hs 节选
instance LocateFileLayer m => LocateFileHandler m where
  locateFile = pure ["demo" </> "FileDemo" </> "output.txt"]

instance ValidateFileNameLayer m => ValidateFileNameHandler m where
  validateFileName = do
    paths <- raw
    unless (all (\path -> not (null path) && '\0' `notElem` path) paths) $
      raise (ValidateFileNameError "File name must be nonempty and contain no NUL character")
    pure paths

instance ParseFileNameLayer m => ParseFileNameHandler m where
  parseFileName = do
    paths <- raw
    case paths of
      [path] -> pure path
      _ -> raise (ParseFileNameError "Expected exactly one file name")
```

**原子输出统一是 list。** Excu 与 Scoped 的 open／close 交出 `[String]`：没有信息时是 `pure []`，一项是 `pure [x]`，一串操作或递归的结果在方法体里用 `:`、`concat` 组合。list 是自由幺半群，只承诺顺序与拼接；别的组合方式（计数、集合、拼成一段文本）都能从它用一次 `foldMap` 得到，所以在句柄这一层先用 list 收集，不提前丢掉信息。它不保留嵌套：需要层次时在元素里编码（例如完整路径），由 parser 还原。Stream 有自己的数据结构，仍是每次一份 `String`，挂在它下面的 parser 读到的 raw 是单元素 list。

**Pure 是对上层输出的 fmap。** Pure 用 `raw` 读直接 Input 交出的 list，返回变换后的 list：去重、排序、过滤都是整个 list 上的普通函数，检查不通过时 `raise`。它没有 IO（Layer 不含 `MonadIO`），也不读资产（不声明 demands，Layer 不含 `Reads`）：值只从上层的 raw 来，和 Context 接收句柄输出一样不走 demands，因此不会出现 demands 的循环依赖。

**Pure 只在生产链中。**

- Pure 的 input 是 Excu、Scoped 或另一个 Pure；不能是 Root，也不能是 Stream（Stream 下只挂它的 parser Context）。
- 以 Pure 为 input 的只能是 Context 或 Pure，且至少有一个；一串 Pure 因此总是落到一个 Context。Excu、Scoped、Stream、Error 都不能以 Pure 为 input。
- Pure 不作为 AST 末端，必须绑定 handler，不声明 demands。

**Context 是细化 parser。** Context 把 raw 细化成资产的表示类型，作用类似 tokenize：即使解析结果仍是 list，也要经过 Context 才成为资产、才能被读取。值的变换写在 Pure 里，Context 不承担；这是写法上的分工，gen 不检查 parser 方法体做了什么。

**执行。** 挂在一串 Pure 下的 Context，挂接点是这串 Pure 最上面的原子句柄：

- **注入**：句柄在操作链里成功返回后，SDK 以根调用身份执行挂接 Context 的 getT；parser 的 raw 经这串 Pure 读到句柄本次的输出，句柄不再执行。
- **驱动**：requests 或 alternative 的选择读取进入 getT 时，parser 的 raw 执行 Pure 的入口，Pure 的 raw 再执行句柄入口，由此启动整条生产链。
- **调用者**：Pure 的入口不改变调用者身份，句柄据此认出是被挂接的 Context 自己经 Pure 拉取，不重复注入。生成期的注入副本把中间的 Pure 就地展开，同样回答到句柄为止。
- **失败**：Pure 的 `raise` 与 parser 失败相同：注入时留在注入内部，资产不发布；被驱动时沿驱动方传播。

**不在本次范围**：带类型的原子输出（需要注册声明输出类型）、交出嵌套结构（森林）、Pure 挂在 Stream 下，都需要另行设计。

<a id="await-visibility"></a>
#### 可见范围与等待的结束（已确定，未实现）

**状态：设计已确认（2026-11-08，读不确定的报错于 2026-11-12 补充），尚未实现；实现前以上述当前协议为准。** 推进见 [Next stages](NEXT_STAGES.md#stage-2-await)。

资产是细化的，每份资产只有一个生产方，又与消费链分离。细化固定的是生产链，不是每一次驱动：同一条生产链可以被多处驱动，每次驱动是一次独立的激活，值可能不同（生产链读外部状态，或它自己的读取按驱动方的捕获解析）；同一资产的两次生产能否互换，gen 看不出来。require 读的是 request 的 state：request 的回调写入它，require 把它分离出来读取，运行时不在多份发布之间挑选。生成期回答两件事：这次读取能不能等到值，以及读到的是不是确定的一次驱动。

- **可见范围**：AST 保证先完成的前驱（chained 中排在前面的节点，alternative 的选择读取之于候选，lifelong 的会话之于单元），本入口在这次读取之前的发布，以及与读取并发的 parallel 兄弟。alternative 的其他候选、lifelong 的其他单元和 AST 中排在后面的节点不可见；持续资产仍由会话交付。
- **生成期**：每个读取点在可见范围内至少要有一个可能的生产者，即 `requests` 驱动、选择读取、挂接注入或会话；没有时 gen 报错，指出这里永远等不到该资产。兄弟各自在发布之前等对方的资产（A 等 B 的 X，B 等 A 的 Y）同样等不到，一并报错。这报的是“不可能”，不是“还没有”。
- **读不确定**：本次调用已经捕获该资产的读取（例如本入口自己 request 过）直接用捕获。其余读取，可见范围内可能的生产者必须能确定读到哪一次：生产者全部由 AST 保证先于读取完成、且彼此有先后时，读取得到最后一次；没有先完成的生产者、只有一个与读取并发的生产者时，读取等它。两个以上生产者彼此没有先后（例如 parallel 的两个分支都 `requests` 同一资产，之后的读取只 `requires`），或者已有先完成的生产者、又有与读取并发的生产者时，读到哪一次取决于调度，gen 报错，要求细化资产或调整 workflow。这是现有“有多个可见来源”报错保留下来的部分，只放开有先后的生产者。
- **资产 state**：同一执行帧里每份资产一个 state。request 每次成功先写入本次调用的捕获（现有行为），再直接覆盖 state，不加锁，也不记录顺序。require 先用本次调用的捕获，再读 state 的当前值，读到后本次调用固定使用它。读不确定的读取已在生成期排除，没有捕获的读取看到的总是确定的那一次，所以运行时不按来源表或可见范围过滤普通发布，也不报多个生产者。兄弟并发覆盖同一 state 只出现在各分支都读自己捕获的写法中，例如 ScopeReuseDemo 的三个写入分支各自 `requests "FilePaths"`。
- **执行帧**：整次有限运行是一帧；lifelong 单元的每次执行各是一帧，开始时为空，单元之间、各次执行之间互不可见。本帧读不到时依次读外层帧。会话挂载的普通发布照旧只作为伴随发布随交付交给单元。
- **等待**：本帧和外层帧都没有值时等待，任何一层被写入都会叫醒它重读。
- **等待的结束**：可见范围内可能的生产者都已结束（成功或失败）且都没有发布时，确定等不到，读取结束等待并报 `ContextNotInitialized`。parallel 中一个分支失败，等待它的兄弟随之结束，汇合不会卡住；parallel 的失败语义不变。
- **不变的部分**：资源不走资产 state，仍由 owner 协议定位，认领仍是原子的；诊断、自动收尾与 close 期间不等待；持续资产的视图位置归 [Stage 4](NEXT_STAGES.md#stage-4)。

<a id="assembly"></a>
### 4.4 原型与闭包装配

gencode 通过统一 Prototype 保存注册、纯方法结构、workflow、链定义与挂载、EffectGraph、ScopeTree 和静态来源。运行时求值并校验生成原型、注册和源码，在一次 cata 中装配闭包；全部结构通过后才执行业务。

Target 保留未执行末端和内部空状态；Node algebra 负责 lower。Context 的实际生产有独立 RequestBoot 活动记录，继承外层 Execution 和 ScopeUser，不新增提前 cleanup 的边界。

本节引用 [EFFECT_GRAPH.md](EFFECT_GRAPH.md) 作为完整结构规范，包含 NodeId／Origin／ActivationId、绑定出身、来源证明、ScopeTree 构树、源码结构提取、缓存与运行校验。这里不再复制这些算法。

<a id="workflow"></a>
### 4.5 Workflow branch

branch 是 workflow 的模块单位，node 是其内部挂载 effect 链的叶子。每个 branch 在 `Workflow/*.hs` 单独定义，导出有业务含义的名称；`AST.hs` 只组合这些名称。使用非限定 import，组合表达式保持 `chained [parsePages, printPages]`，不写模块前缀。模块名称区别于 chained／parallel 这种控制类别；空闲 scope 由 SDK 自动清理，不为此新增收尾 branch。

SDK 将 node 与 branch 分成两个抽象类型：

```haskell
node :: String -> EffectNode
chained, parallel, alternative, lifelong :: BranchChild child => [child] -> AST
```

BranchChild 为不导出的 SDK 内部约束，只提供 EffectNode 与 AST 两个实例；业务不增加 class、instance 或转换调用。同一列表只能全是 node 或全是 branch，裸 node 不能赋给 AST，原始 AST 构造器与子项转换不公开。单节点模块用 `chained [node "目标"]`，空分支需如 `chained ([] :: [AST])` 的类型标注，仍成功返回空结果。内部递归表示与 algebra 不变，通过 foldAST 使用 cata。

这项类型约束不证明分支来自独立文件，也不禁止内联子分支或直接构造叶模块。独立文件、顶层只引用模块名属于声明格式：正文采用固定 branch 构造、显式列表、node 与直接模块引用，不借任意 lambda／map／条件计算隐藏结构，引用保持有限无环。未来 LSP 保存模块定义、引用和源码位置，并检查该格式；当前执行 AST 不保留源码身份，不新增运行时模块 key。

分文件不建立新 interpreter、注册环境、Context 或 scope。同一模块多次挂载意味着多次执行，不去重调用；原有串行短路、并发汇合与资源共享规则保持。六个 workflow demo（含 StreamDemo）已按此拆分。chained、parallel、alternative 是有限 branch；lifelong 用于持续执行，见本节末的 [lifelong 的控制流](#lifelong-control)。

#### 有限执行的完成规则

chained 按声明顺序执行，遇失败停止；parallel 并发执行，等待全部分支后汇总，结果按声明顺序排列。有失败时保留声明顺序中首个失败的来源和负载，不按完成先后选择，不自动取消已运行的其他有限分支。已完成 IO 不回滚。

空 branch 成功并返回空结果。AST 只在最终边界封装一次 Output，汇总产物不隐含共享绑定或自动传给后继。节点结果与 Context 发布是不同通道。

#### alternative 的类型边界

当前支持至少两个构造器、每个构造器至多一个字段的和类型；无字段分支包装 ()。每个候选的完整 Input 链恰好依赖同一基础资产的一个分支契约，并覆盖全部构造器。分支契约只能 require；当前构造器不匹配时报 CaseNotSelected，不新增业务状态。

#### alternative 的选择与交接

AST 只列候选，不写条件。gencode 将转折契约、选择读取路径和候选 NodeId 到构造器的关系保存为 WorkflowTree 的 AlternativeProto；分支契约目录保存在 EffectProto。

选择读取自己驱动转折资产，相当于写了 `requests`：运行时先执行它的生产链并发布，再只启动匹配构造器的候选，其他候选不执行。挂在 Stream 下的持续资产由会话驱动，选择读取领取本次交付。选择阶段捕获的无 owner 绑定经 Handoff 交给候选，两段读取同一快照，其他调用的驱动不改写它。执行只在已装配的闭包间选择，不在链中间重组。

选择读取有独立入口使用登记，以契约名登记末端，NodeId 为 alternative 路径加 [-1]，参与构图与 ScopeTree。validatePrototype 核对转折契约、构造器唯一及覆盖完整；执行 fold 与 --structure 使用同一原型匹配当前 AST，不一致时在业务前拒绝。

<a id="lifelong-control"></a>
#### lifelong 的控制流

lifelong 是第四种 branch，在交付就绪时反复 boot 其中的 target。完整规则见 [Stream 第 6 节](STREAM_LIFELONG.md#scheduling)；这里说明它与有限 branch 的关系：

```haskell
-- StreamDemo：先完成一次准备，再进入持续监控
ast = chained [setup, monitor]
monitor = lifelong
  [ chained [node "ShowTemperature", node "CheckTrend"]
  , chained [node "ReportHeartbeat"]
  ]
```

- **单元**：直接子项各为一个单元，直接子项是 parallel 时只拆这一层；单元之间独立推进、互不等待。拆分写入 Prototype，运行时不推测。
- **一次执行**：单元逐次执行，每次执行是一个 frame。控制流到达 target 时先领取其订阅资产的一条新交付（有积压立即领取，没有就挂起），再 boot target；同一 frame 内每个资产只领取一次，各调用共享这份视图。target 调用按上文的有限完成规则结束，本次执行结束后才开始下一次，上一次的普通产物不带入下一次。
- **没有正常结束**：lifelong 不返回 Succ。`chained [setup, monitor]` 先完成 setup；`chained [monitor, after]` 中 after 不执行；`parallel [monitor, otherWork]` 两者同时运行。
- **失败**：含 lifelong 的程序中，任何失败按临时规则终止整次运行（[Stream 第 9 节](STREAM_LIFELONG.md#failures)），不同于有限 parallel 不取消其他分支的规则。lifelong 的局部结束属于本轮[结束传播阶段](NEXT_STAGES.md#stage-6)，其与故障传播的关系仍需确认。
- **合法性**：lifelong 不嵌套、不含空分支；其中每个 target 恰好用 `streams` 订阅一个持续资产，见 [Stream 第 5.2 节](STREAM_LIFELONG.md#static)。

<a id="mapping"></a>
### 4.6 业务转换与尚未实现的适配

对外产生业务值的纯转换注册为 Context；不新增 Map typing。当前取值连接要求已声明的契约，Generic Map 尚未接入。

后续结构适配的方向是在 SDK 内部实现固定规则，不增加业务 adapter 配置；支持的类型范围、失败接口及接入仍需确定。状态统一在 [Next stages](NEXT_STAGES.md) 跟踪，不把旧候选解释成当前能力。

<a id="scope"></a>
### 4.7 Scope 存续、归属与自动清理

本节记录本轮定案的有限使用闭包协议；运行载体和旧样例按此迁移，不以旧版编译或运行结果宣称本轮已验证。下一步已确定、尚未实现：以 `requires` 与 `requests` 进入 scope 的方式区分[单例与多例](#scope-identity)，并[按可达性回收](#scope-gc)，取代按 Eq 共享实例、once-spare 与 interpreter 退出兜底。

effect 不配置 dependency。SDK 沿 Input 与 requests 收集 Scoped；读取不执行 getT，所读值的生产链已有的资源前提仍纳入清理依赖。open 由入口按 Input 装配，handler 不调用 open／close，二者均为 m [String]；使用闭包撤销使用后由 SDK 按 once-spare 调用登记的 close，interpreter 退出保留兜底。

同一 interpreter 自动创建一批 ScopeHandler，由所有末端 Target 捕获。每个 Scoped 注册持有实例集合，每份实例独立保存 MVar、生命周期和开启期 Context；实际开启输入是被驱动还是被读取，决定新建还是共享。两个 Scoped 注册共用 open／close handler 时仍是两个独立的 scope。Main、Effects 和 Handlers 不增加 key、位置参数、用户装配或手写 layer，也没有进程全局单例。运行表可跨 Node 共享，但不预约未来 Node 的活资源。运行表只保留还可能被选中或等待清理的实例：已关闭的实例，以及没有使用者、没有登记清理的非共享实例移出运行表；旧绑定直接持有实例引用，旧引用仍报已关闭；同参共享的失效实例保留，同参 open 继续报原失败，显式 close 后移出。

当前 App／IO 协议采用已有文件链的结构：Scoped 的 requests 资源 demand 引用资源 Context（如 FileResource），该资源 Context 声明消费的上游 Context（如 FileLocation）及其值前提构成开启参数。SDK 生成观察器，在资源 parser 真正读取这些资产并取得结果时记录原生 ADT 值，按来源、类型和 Eq 比较；参数 ADT 需要 Eq，资源产物不需要 Eq。参数在本次开启中必须保持一致。SDK 不在外部提前执行 Context，不从文件路径字符串、Show 或 Handle 身份猜测参数。

每次 open 按取值声明取得本次参数。作为 scope 匹配参数的开启输入全部实际以读取取得时，可按 Eq 共享同参活实例，跳过资源获取及 open 的剩余方法体；任何这样的输入在本次被驱动重新生产时，本次 open 默认 fresh，即使值相同也创建新实例，同值旧实例保留并存。这里区分的是开启参数取值，Scoped 驱动资源本身的 requests 不一律触发 fresh；没有开启输入的 scope 仍可共享。

需要共享时，业务在当前完整链先由 requests 驱动稳定参数，资源 parser 与 scope 内的 handler 读取该绑定。参数生产者自己的 IO 可以运行；open 范围中其他 IO 必须在参数齐备之后，否则报 ScopeInputsMissing。参数变化发生在选定之后则报 ScopeInputAfterOpen。该协议不分析任意 IO 闭包中的隐藏参数，也不将混在参数生产动作里的资源获取自动拆开。本轮协议限定 App／IO 下受管理的有限完整链。

底层 Binding 保存不可变值快照、Execution 出身与共享的 bindingOwnership IORef。每次生产成功产生新绑定；当前捕获、权威表、scope 快照和 alternative 的 Handoff 共用该绑定的归属单元。读取首先使用本次捕获，不因另一条链发布新值而改变。驱动发布并替换当前 origin 的来源绑定。复用实例只接入带 owner 的资源绑定，不把无 owner 辅助快照补入当前调用；后者从按 origin 保存的权威表、按原型许可来源读取。资源关闭后，后续 Node 经 Input 开启新一轮；旧资源绑定不自动换 owner。

close 不预先选择 scope，也不预执行 Context。生成包装先进入关闭协议，close handler 的读取取得 ContextBinding 后，SDK 从该绑定的归属取得生命周期锁，再继续关闭方法体。找不到绑定／归属即失败；关闭期间不能改用另一份归属。重新开启产生新实例，旧绑定仍指向旧的已关闭实例，不会误关新资源。

一个资源绑定只有唯一关闭归属，普通 require 只读取原绑定，不转移资源归属。open 在 scopeCoordinator 内将共享单元从无 owner 首次认领为实际实例，同一实例重复认领幂等。另一个 scope 或同注册的不同实例认领同一绑定时，SDK 在等待实例生命周期锁之前报告 ScopeContextMismatch，不覆盖 owner，也不为冲突实例登记该资源的 cleanup。所有捕获副本观察同一次认领；有效 scope 复用仍传递原绑定。

资源 Context 在 open 外产生无 owner 绑定时，发布／require 返回前登记当前 ScopeUser。认领在同一 scopeCoordinator 内把仍活跃的持有者转入实例使用集合；入口退出在该锁内同时撤销待认领与实例使用，防止漏记使用者或复活已经结束的入口。普通资产不保存待认领使用者；open 内正常生产已有 owner 的路径不变。认领到保存资源绑定保持 masked，资源已被认领后不会因这一交接窗口中断而漏掉 cleanup。

认领保留原来的 publication、值和 origin，不删除来源记录或重新发布；因此 Stage 2 的静态来源事实不因 owner 后补而撤回。资源快照按共享归属单元去重，不合并独立生产。两次生产即使私下包装同一个底层 Handle，也仍是不同绑定；SDK 不追踪这种物理别名。不新增用户 key、layer、位置参数或借用／转移协议，不改变 handler 写法和 ScopeTree 算法。

跨链第一次读取尚无本地绑定时，只接受唯一可解析的来源绑定并将其捕获；多份来源且没有明确关联时报 AmbiguousContextBinding。此规则不解决任意历史绑定的用户寻址，不能把同一个无参方法解释成“任选过去第几份值”。同一份已绑定句柄重复读取稳定，与同一注册结构创建多份调用环境是两回事。

选择共享的并发 open 等待同份实例，等待 opening 的调用也先加入使用，不能因另一调用结束而把其即将使用的资源关闭。驱动 fresh 和不同参数实例各自独立。开启失败／中断后失效，close 失败允许再清理，成功关闭后重复 close 跳过。close handler 须先读取已有资源，再做释放 IO；参数／资源生产失败不触发外部补跑。普通下游失败不自动等同于 scope 失效。

现有 demo 按此协议书写：FileDemo 的校验与资源 parser 读取同一路径，Input 先开启文件。ScopeInstancesDemo 的三条使用闭包共用 `checkSelection`，各自由 requests 刷新参数、经 Input 开启实例，闭包退出时关闭，后一条按当前参数开启新实例；它不再演示一条链内重复开启。OpenFilesDemo 观察当前链及 GC 期间的十个文件，检查快照挂在只在最后一段运行的 ReleaseFiles 下，再在 scope 关闭后检查。ScopeReuseDemo 的 writer 先驱动参数、scope 内读取；仅实际重叠时共享，不能固定断言整个 parallel 只开一次。它在全部链清理后读取已有日志和追加输出，不读取旧资源。上述是适配说明，不是新增测试。

状态分配不执行业务。原有有限使用闭包以入口使用登记表达：每个 Node lower 的末端完整 chain 建立一份登记；实际 open／读取选中实例时加入使用，同一闭包对同一实例只加入一次。chain 正常返回、失败或取消后，完成相应诊断和 SDK 受控的结果消费，再撤销这次使用。最后使用者离开且子 scope 不再保留它时，once-spare 执行登记的 close。后续尚未开始的 Node 不占用使用名额，资源不会仅因它可能再次使用而留到 interpreter 末尾。

once-spare 当前是 core 固定策略，不提供 policy 配置，也未实现 next-use、超时保留或运行时切换。策略位于 SDK 生命周期协调层，用户原生 open／close 方法的接口独立于这一选择；interpreter 退出时仍执行兜底清理。

生成器登记原有 close 回调，SDK 为实际实例保存清理动作和绑定。清理服从补全后的 scope 依赖，子 scope 仍保留其前提时不得先关闭前提；相等参数的 fresh 实例仍分别持有和释放。显式切换当前绑定不立即关闭同一闭包已经持有的其他实例。公开 interpreter 完成、失败或取消时的全局清理继续作为兜底，不替代闭包退出时的实际回收。

显式 close 已成功的实例跳过，close 失败的实例仍可在退出时清理。某次清理失败不阻止其余实例，原执行失败与各次清理故障均保留；没有原执行失败时，清理失败也不能报告为成功。资源 producer 返回到 SDK 发布绑定采用 masked 交接，open 失败／中断时已经发布的资源仍纳入清理。不为清理重新执行资源生产者，也不因一次驱动改选参数而关闭仍被其他绑定引用的实例。

可开启的 Scoped 须声明 close，缺失时生成阶段报错。退出清理期间拒绝再次 open，避免收尾中新建未纳入本轮结束范围的资源；此时 close 的 Error 路径由自己的生成入口建立，不沿用开启时的下游调用路径。普通收尾失败附在原 Failure.cleanupFailures；原生异常在其余清理尝试完毕后重新抛出，并报告同时发生的清理故障。

重新创建一批运行句柄不共享状态；跨独立 interpreter 的存续不在当前范围。本轮使用计数只覆盖 SDK 管理的完整链及受控结果消费，不追踪任意逸出 Handle。SDK 的显式关闭协议保留（handler 不再调用 close）：只可排除当前闭包自己的使用，仍有其他使用者或未释放子 scope 时以 ScopeInUse 拒绝，不等待当前调用退出；关闭预约期间不接纳新使用。裸 forkIO 自动追踪、任意业务 IO 内尚未发布的部分获取恢复及 Linear 凭证尚未实现。Error 的同实例检测／处置串行化继续沿用原协议，使用与关闭由本轮使用协议协调。

这使“同一绑定保持同一值与资源归属”成为底层表示和 ContextStore 原语的约束，而不是额外 adaptor 的约定。但架构尚未成为能静态证明所有业务公理的系统：生成包装仍提供运行时协议；App 中的任意 liftIO 不因句柄描述纯而变纯。Pure 的 Layer 不含 MonadIO，但其值管道语义尚未确定。Error 使用用户定义的定位条件，不能用它假定外部执行总是确定。

#### 细化契约与节点身份

当前不同细化资源、开启输入及 Scoped 使用不同注册，ScopeTree 因而以 Scoped 注册识别节点；实例再以输入来源、类型与 Eq 值区分。Stage 2 中两个 Scoped 注册可以共用 open／close handler（FacadeProbe 的 ReportScope、ReplyScope），它们仍是两个节点；同一个 Scoped 注册服务多种细化资源尚无声明形式。

若以后引入该形式，静态节点、实例表、ownership、close、cleanup 与 Error 导航必须共同改用“Scoped 注册＋细化资源类型”，不能只修改资产命名。

<a id="scope-identity"></a>
#### 单例与多例：require 与 request 进入 scope（已确定，未实现）

**状态：设计已确认（2026-11-13），尚未实现；实现前以上述当前协议为准。** 这是 scope 资源清理的出发点：实例的身份、共享、存续和关闭时机都由它推出，[按可达性回收](#scope-gc)只是执行它的机制。

scope 的资源怎样清理，取决于开启参数以哪种方式进入 scope。`requests` 与 `requires` 是两种不同的进入方式：

- **`requests` 发起一次新的生产，得到新的身份。** 这次开启要的是属于自己的资源。
- **`requires` 引用已有的一次生产，身份与它相同。** 这次开启要的是别人已经确定下来的那一份。

[资产细化](#refinement)固定的是生产链，不是每一次驱动：同一条生产链的两次驱动是两份不同的东西，即使值相等。scope 实例的身份就是开启参数来自的那一次生产，所以不需要 key，不比较参数值，也不看 Handle。

每个开启位置（哪个节点的链在开启哪个 Scoped）由此属于下面三类之一：

| 开启参数怎样进入 | 类别 | 实例归谁、何时清理 | 业务含义 | 写法见 |
| --- | --- | --- | --- | --- |
| 没有开启参数：资源 Context 没有上游，或 Scoped 没有资源 | 注册级单例 | 不属于任何一条链。同一时刻至多一个实例；剩余程序里没有节点还会用这个 Scoped 时关闭 | 整个程序共用的连接、会话 | Crawler 的 `CrawlSession`、StreamDemo 的 `SensorLink` |
| `requires`：本次开启只读取已有的一次生产 | 单例（按那一次生产） | 属于那一次生产。读到同一次生产的开启共享同一个实例；剩余程序里没有节点还会读到这次生产时关闭 | 连接池、多条链共用的文件 | ScopeReuseDemo 的目标写法 |
| `requests`：本次开启发起了新的生产，资源 Context 驱动参数，或开启链自己先驱动参数 | 多例 | 属于发起生产的这一次执行。每次开启一个实例；这次执行结束、且没有后续节点读取这次生产时关闭 | 事务、每个请求各自的句柄 | FileDemo、ScopeInstancesDemo、OpenFilesDemo |

- **类别属于开启位置，不是 Scoped 注册的固定属性。** 同一个 Scoped，在自己驱动参数的链上是多例；后续节点只读取这次驱动时，与它共享同一个实例。
- **多个开启参数逐个判断。** 任一参数在本次开启中是新的生产，这次开启就是多例；全部引用已有的生产时，实例由这组生产共同确定。
- **决定类别的是开启参数，不是 Scoped 自己的 demand。** 开启参数是资源 Context 的 parser 读取的上游 Context。Scoped 对资源 Context 总是写 `requests` 与 `requires`：资源在 open 协议内获取，认领不出现无主的窗口；共享已有实例时这次获取被跳过。
- **清理的区别。** 多例有明确的主人，随发起它的那次执行结束。单例没有单一的主人，活到没有人还能触达它为止；在 lifelong 里各轮都会再用到它，因此常驻，多例则每轮回收。整次运行结束时两类都关闭。

三类写法的节选，声明语法不变：

```haskell
-- 注册级单例：资源 Context 没有上游（Crawler）
EffectSpec { name = "SessionContext", typing = Context { asset = Asset @SessionInfo "CrawlSessionInfo", .. }, input = "Root", demands = [] }
EffectSpec { name = "CrawlSession", typing = Scoped { .. }, input = "Root", demands = [requests "CrawlSessionInfo", requires "CrawlSessionInfo"] }

-- 多例：资源 Context 在开启时驱动参数（FileDemo）
EffectSpec { name = "FileResource", typing = Context { asset = Asset @FileHandle "OpenedFile", .. }, input = "Root", demands = [requests "FileName", requires "FileName"] }

-- 多例：资源 Context 只读取参数，开启链自己先驱动它（ScopeInstancesDemo）
EffectSpec { name = "FileResource", typing = Context { asset = Asset @FileHandle "OpenedFile", .. }, input = "Root", demands = [requires "FileName"] }
EffectSpec { name = "UseFirst", typing = Excu { .. }, input = "FileSession", demands = [requests "FileName", requires "FileName", requires "OpenedFile"] }

-- 单例（按一次生产）：资源 Context 只读取参数，开启链也不驱动它，读的是 PrepareProbe 的那次生产（ScopeReuseDemo 的目标写法）
EffectSpec { name = "PrepareProbe", typing = Excu { .. }, input = "Root", demands = [requests "FilePaths", requires "FilePaths"] }
EffectSpec { name = "FileResource", typing = Context { asset = Asset @SharedFile "OpenedFile", .. }, input = "Root", demands = [requires "FilePaths"] }
EffectSpec { name = "WriteFirst", typing = Excu { .. }, input = "SharedFileScope", demands = [requires "OpenedFile"] }
```

SDK 的分工：

- **gen** 在每个开启位置记录各开启参数的生产出处（本节点自己的生产，还是哪个节点的生产），据此给出类别，写入 Prototype，`--structure` 展示。
- **运行时** 为每次成功生产的绑定保存生产身份；open 用参数绑定的生产身份选择实例，不比较值，参数 ADT 不再需要 `Eq`。
- **清理** 按类别决定谁还能触达实例，见下一节。

<a id="scope-gc"></a>
#### 按可达性回收（已确定，未实现）

**状态：设计已确认（2026-11-13），尚未实现；实现前以上述当前协议为准。** 推进见 [Next stages](NEXT_STAGES.md#scope-gc)。实例的身份与类别见[单例与多例](#scope-identity)；本节规定实例何时关闭。

once-spare 只数此刻的持有者：前一条链退出、下一条尚未开始时计数归零，资源随即关闭，下一条再重新开启；Crawler 的两次抓取、ScopeReuseDemo 的三个写入是否共享，都取决于它们是否实际重叠。程序只有一个 AST，资源只经 Input 与 demands 到达，引用全部静态声明，ScopeTree 与 effect graph 无环；因此改为按剩余程序的可达性回收：仍可能被触达的实例不关闭，不可达的实例立即关闭。计数仍是 SDK 内部的引用计数，但计的是剩余程序中可能触达实例的节点，由 gen 静态得出、只减不增，归零的时点由程序结构决定；图无环，这样的计数与追踪式回收等价。写法不变：handler 只实现怎样关闭，何时关闭由 SDK 推出，不新增声明、AST 节点、key 或寿命标签。

- **可达**：下列任一成立时实例可达：正在执行的链捕获或使用它；所属执行帧里仍待用的节点有一个与它身份相同的开启位置（注册级单例按注册，其余按参数的生产出处）；它有可达的子 scope 实例；它的 Error 诊断尚未结束；持续生产会话正在使用它。普通值的快照不是可达边，读取资源生产链产出的普通资产不延长资源的存续。业务自行保存的 Handle 与裸 `forkIO` 不在追踪范围。
- **资源只在开启它的链内读取**：资源 Context 只能在已经开启其所属 Scoped 的链内读取，否则生成期报错。现有协议在本链没有捕获时由“仍开着的实例”提供资源，读到哪个实例取决于此刻谁还活着；按可达性回收要求先知道谁会读，才能决定谁活着，因此取消这条路径。close 与 Error 诊断读取自己实例的资源不受影响。
- **静态部分**：来源分析在分析到 open 时，记录这个开启位置各开启参数的生产出处：本节点自己的生产，或其他节点的生产，后者包括 alternative 的选择读取交接给候选的捕获。现有来源表只记录没有捕获时的读取，分不清这两种，因此出处作为 Prototype 的新字段写出，开启位置的类别由它得出。读不确定的生成期报错保证每个读取对应确定的一次生产。
- **运行部分**：运行时只追踪节点进度，不追踪整张 effect graph。进度按执行帧记录：整次有限运行是一帧，lifelong 单元的每次执行各是一帧。帧开始时帧内每个节点都是待用；节点结束（含诊断与受控结果消费）、被 chained 短路跳过、在 alternative 中未被选中后不再待用，只减不增。实例的待用计数是所属帧里仍待用、且有与它身份相同的开启位置的节点数：参数全部来自帧外的生产或没有参数的实例记在外层帧，lifelong 单元对外层帧的持有不随每轮结束而撤销；参数来自本帧生产的实例记在本帧，随本帧结束而不可达。计数在现有协调锁内更新；归零且没有当前使用者、没有可达的子 scope 实例时关闭。节点进度与[可见范围内的等待](#await-visibility)共用同一份记录，不另建一套。
- **执行**：close 在使计数归零的事件所在的线程中同步执行，完成后才开始下一个节点；parallel 中由最后减到零的分支执行。沿用关闭预约、子先于父、一份失败不阻止其余实例，不另设后台清理线程。
- **lifelong**：注册级单例，以及参数来自 lifelong 之外那次生产的单例，记在外层帧，运行期间常驻；多例和参数来自本轮生产的实例属于本轮的帧，本轮执行结束即回收。连接池（参数生产一次、各轮 `requires`）因此跨轮存续，事务（每轮 `requests`）单轮结束，参数变化时不累计历次实例。
- **运行结束**：整次运行正常结束、失败或取消时没有节点仍待用，全部声明了 close 的实例按依赖逆序关闭，包括 lifelong 用到的单例。这是同一条可达性规则的结果，不是另设的兜底：ScopeTree 只在内存中，重启后为空，留下的外部资源新的运行看不到，状态无法确定。进程被强制终止时 close 无法执行。
- **close 可选**：Scoped 的 close 不再必填，生成期不再要求可开启的 Scoped 声明 close。没有 close 的实例不可达时只移出运行表，不执行 IO，运行结束时也不关闭。
- **close 失败**：close 的 `raise` 与中断照常进入关联该 scope 的 Error 诊断；之后只记录，运行结束时汇总报告，不改变任何节点的结果，不触发短路，也不停止运行，整次运行的结果仍是业务结果。失败的实例标为失效并移出运行表，不重试 close。close 失败是资源问题，不是作用域问题：实例已经不可达，不会再被任何节点使用。
- **取代的部分**：once-spare 及“后续尚未开始的 Node 不占用使用名额”；按 Eq 跨生产共享与参数 ADT 的 `Eq` 要求；本链没有捕获时由仍开着的实例提供资源；可开启的 Scoped 必须声明 close；interpreter 退出兜底作为独立机制，以及 close 失败的实例退出时再清理；面向业务的 ScopeInUse（关闭只发生在不可达的实例上，再出现即可达性分析的内部错误）；close 失败附到节点的 `Failure.cleanupFailures`，以及业务成功而清理失败时把结果报告为失败。
- **不变的部分**：资源认领、masked 交接、子 scope 先于父关闭、旧绑定仍报已关闭、Error 的实例定位与诊断。关闭预约等内部机制保留：常驻的单例失效后需要作废并重新开启，这留给 Error 的驱动链设计。持续资产作为开启参数仍待 [Stage 5](NEXT_STAGES.md#stage-5) 接通；Stream 会话何时不再使用实例由 [Stage 6](NEXT_STAGES.md#stage-6) 的 end 决定。
- **demo 的预期变化**：Crawler 的 `CrawlSession` 是注册级单例，两次并行抓取确定共享一个实例，parallel 汇合后关闭。ScopeInstancesDemo 的 UseFirst、UseSecond、ReopenFirst 各自驱动 `FileName`，都是多例，各得一个实例并在本节点结束时关闭，输出不变，依据由时序变为结构。OpenFilesDemo 的每个节点经 HoldFiles 驱动 `FileNames`，同样是多例；FinishInspection 读取的是普通快照，不延长存续。FileDemo 的资源 Context 在开启时驱动参数，是多例。ScopeReuseDemo 的三个写入现在各自 `requests "FilePaths"`，是多例，将得到三个实例；要共享，写入改为只读 PrepareProbe 的那次生产，成为单例，在 parallel 汇合后关闭。StreamDemo 的 `SensorLink` 是注册级单例，运行期间常驻，运行结束时断开。

<a id="error"></a>
### 4.8 Error 检测、处置与失败传播

detect 和 resolve 是同一个 Error effect 绑定的两个 handler，均以 Maybe String 声明、签名为 m ()；handles 声明处理的故障类型：RaisedBy 写 handler 名，ScopeFaultIn、ContextFaultIn 写 effect 名。Error 只指向 scope：关联 scope 由生成器沿 Input／requests 推导最近的 Scoped，必须恰好一个，没有时生成器报错；没有关联 scope 的全局处置已取消，普通 effect 的错误靠提前 mock 排除。Error 独立注册，SDK 将回调装配到 Root，不加入正常业务调用链或 AST，其他 effect 的 Input 不能指向它；注册不提前执行检测。

App／IO 的生成入口沿 Input／requests 找最近的 scope，遇到 Scoped 停止，只提供关联种子。Root 捕获传播到生成入口的 Failure 时，合并 scopeTrace、当前 errorPath 和 scopeTargets 中的 scope 名字；生命周期持锁期间只保留种子，退到锁外再由 scopeErrorPath 读取 ScopeHandler.scopeParentNames。这是自动清理也使用的同一棵 ScopeTree 的全部祖先投影：补齐祖先、按父到子的层次去重，同层沿 ScopeHandler 名单顺序，再按 handles 匹配故障，回调的关联 scope 须位于该路径上；同一 scope 的多个回调沿注册顺序执行。

完成路径写入 Failure.scopeTrace。候选依赖不是故障归属证明；类型匹配完成粗定位，detect 是可选的值级细化。未注册 detect 时直接调用 resolve；detect 正常完成为 Succ ()，随后调用 resolve；raise 得到 Failed，表示不归此处。无论该项完成或失败，继续处理其余相关 scope。

App／IO 的祖先导航与清理共用生成树，不另存 Error graph，不读取新的 schema 或用户 key，不增加轮询或动态调用 tracing。人工调整生成树父边会同时影响两者；运行校验只检查结构自洽，不证明删边在业务上正确。App／IO 未安装树时仅使用显式种子；Pure 的旧候选名单协议已取消。

SDK 的 `caughtFailure :: m (Maybe (Failure cause))` 仍保存当前诊断上下文的原始故障，但不在 Layer 中，detect／resolve 的 handler 目前不能读取它，待 Error 驱动链确定。SDK 把检测／处置的 Succ 或 Failed 结果保存到原 Failure.errorHandling，保留 origin、detail、message；最终仍传播原失败，不因处置成功把失败业务当作完成。scopeTrace 只保存候选路径，已处理标记防止多层 Root 重复检测，检测和处置的次生失败不递归激活自己。

诊断使用故障时绑定的隔离快照。普通故障按已捕获资源绑定的归属确定实例；open／close 故障优先使用本次生命周期实际选定的实例证据，并隔离其他实例的旧绑定。尚未选定实例时不猜测，也不拿最近一次成功产物代替此次失败资源。SDK 不扫描其他实例、不预执行 Context、不重新 boot；匹配实例的失败绑定可供检测和清理读取，其他绑定保留正常状态检查。

open／close 内部持锁时延后诊断，退到生命周期锁外再执行；同实例用独立 MVar 串行化检测和处置，生命周期锁不跨回调持有。检测与普通业务 IO 不自动互斥。被业务在锁内 catch 后消化、没有继续传播到安全 Root 边界的故障，不承诺进入自动诊断；任意未转换为 Failure 的 IO 异常也不由此协议捕获。

Error 是另一条驱动链：resolve 不调用 close，也不重放业务方法，设计确定前 FileDemo 的 resolve 为 `pure ()`（TODO）。Error 协议不因定位成功自动 invalidate、close、reopen 或重放业务方法。定位成功只表示用户的检测条件成立，实际 scope 状态仍由生命周期操作决定。完整链的 once-spare 及 interpreter 退出兜底独立于是否配置 Error 检测；撤销链的使用须等待本次诊断结束。现有 ExceptT 的失败短路仍保留，不自动恢复已展开的 continuation，也不因业务 Failure 取消其他已经运行的并行分支。

FileDemo 的 FileRecovery 演示：handles 写 `RaisedBy "readFileContent"` 等 handler 名；detect 读取文件句柄，用 hIsClosed 检查意外关闭，已关闭时返回 ()，否则 raise 表示未定位；resolve 暂不操作 scope。正常路径不注入故障，文件读写仍由原末端执行。

#### 匹配身份与唯一性

handles 按 Failure 的 detail 分类与 origin 匹配：RaisedBy 按 handler 的 `XxxFailure` 分类匹配，不论失败发生在哪个绑定；ScopeFaultIn／ContextFaultIn 按 effect 名匹配。Context 协议故障，包括未声明的读取及 CaseNotSelected，origin 使用生产方 effect 注册名，不使用资产名。同一 scope 下同一故障类型只允许一个 Error 注册。

<a id="generation"></a>
### 4.9 编译流水线、运行入口与源码同步

[gen 是编译器](#compiler)。手写业务只导入 [Framework.SDK](../sdk/Framework/SDK.hs)：注册、handler 能力、故障观察和 AST 组合，定义在 `Framework/Language/`；Types、Effects、AST 不导入 Generated 或 Handlers，handler 的类、Layer 与错误类型由 gen 生成，无须手写。生成代码只导入 [Framework.Generated](../sdk/Framework/Generated.hs)：Prototype 的数据模型、运行协议与装配操作，以及程序命令的适配。Generated.Program 绑定程序元数据后，业务仍写 `interpreter ast effects`。

[Framework.Gen](../sdk/Framework/Gen.hs) 按阶段执行编译，[Gen/Main.hs](../sdk/Framework/Gen/Main.hs) 是 `effect-codegen` 的命令行入口。每个阶段一个模块，失败即停止；全部通过后才写回 Generated，未变的文件保留时间戳。整个过程不执行 handler 业务：

| 阶段 | 模块 | 输入 → 输出 | 这一阶段报告的错误 |
| --- | --- | --- | --- |
| 读取 | [Gen.Source](../sdk/Framework/Gen/Source.hs) | Types.hs → 和类型；在独立的 ghci 进程中求值 `effects` 与 `ast` | 声明不能加载或求值 |
| 降级 | [Gen.Lower](../sdk/Framework/Gen/Lower.hs)、[Gen.Demand](../sdk/Framework/Gen/Demand.hs) | 注册与 workflow → PrototypePlan：effect 原型（含 Context 经 Pure 链的挂接句柄）、每个 demand 的唯一生产方、WorkflowTree | 资产来源与访问方式；Input、Pure、Scoped、Context、Stream、Error 的注册规则；AST 末端、alternative 候选与 lifelong 订阅 |
| 绑定 | [Gen.Bind](../sdk/Framework/Gen/Bind.hs)、[Gen.Names](../sdk/Framework/Gen/Names.hs) | PrototypePlan → 每个 handler 绑定的前驱、驱动、raw 来源与读取路由；handler 的方法类型与 Layer | 生成名字冲突；一个 effect 内表示类型重复；同一 handler 的绑定推出不同的签名或 Layer |
| 形状 | [Gen.Shape](../sdk/Framework/Gen/Shape.hs) | Handlers.hs 的语法树 → 各 handler 方法体的读取形状（`require @T`、`raw`） | handler 调用其他 handler 或 effect 方法；`require` 没有类型应用；读取经不支持的高阶组合传递 |
| 组成 | Gen.Bind 的 `composeMethods` | 形状 × 绑定 → effect 方法的结构 | 读取的表示类型没有声明；`raw` 用在挂接 parser 与 Pure 之外；声明的读取没有被方法体或控制流使用 |
| 构图 | [Gen.Build](../sdk/Framework/Gen/Build.hs)、[Build.Graph](../sdk/Framework/Gen/Build/Graph.hs)、[Build.Sources](../sdk/Framework/Gen/Build/Sources.hs) | PrototypePlan + 方法结构 → Prototype：EffectGraph、ScopeTree、链挂载与资产来源 | 注入经 Pure 以外的方法绕到句柄；直接调用 Stream 方法；持续资产的启动环；读取有多个可见来源；Context 没有被驱动 |
| 输出 | `Gen.Emit.*`（[Effects](../sdk/Framework/Gen/Emit/Effects.hs)、[Handlers](../sdk/Framework/Gen/Emit/Handlers.hs)、[Program](../sdk/Framework/Gen/Emit/Program.hs)、[Prototype](../sdk/Framework/Gen/Emit/Prototype.hs)） | 绑定与 Prototype → Generated/Effects、Handlers、Program 的源码 | 只渲染，不再判定 |
| 类检 | [Gen.Assets](../sdk/Framework/Gen/Assets.hs) | 业务模块与输出副本（在内存中）→ 资产目录 Generated/Assets | GHC 类型错误；顶层白名单 |

只有降级在独立的 ghci 进程里执行：`effects` 与 `ast` 是 Haskell 值，必须加载业务模块才能求值；PrototypePlan 经 Show/Read 交回，之后的阶段都在生成器进程内读取这份计划。Handlers.hs 只解析，不加载；类检阶段把业务模块与刚输出的副本放在内存中，交给 GHC 无代码生成模式检查。构图结果按 PrototypePlan、方法结构与构图相关的 SDK 源码缓存在 Generated/.scope-cache，命中时仍校验 Prototype；驱动检查每次执行。

首次没有 Handlers.hs 时，形状为空，不检查读取与驱动，只生成契约和空的 Handlers 模块；填写 handler 后再次生成并编译 Main，命令与使用顺序见[指南：命令行与执行阶段](GUIDE.md#commands)。业务执行编译 Generated/Handlers：handler 方法体原样复制到按 effect 的类型标签上，后接 gen 生成的入口与路由；不回写手写源码或新增业务类型类。手写实现变更后须重新生成。

[Framework.Program](../sdk/Framework/Program.hs) 是运行入口：强制并校验 Prototype、执行 workflow 和退出清理；它不读取命令行或推导 demo 路径。[Framework.Generated](../sdk/Framework/Generated.hs) 负责程序命令及源码指纹适配，手写源码路径由生成器显式传入。生成的 Handlers 保存解析时的源码指纹；公共 workflow 入口在启动业务前核对注册快照与当前手写源，缺失或过期则拒绝执行；执行时逐层核对 AST 与编译时的 WorkflowTree。Main 写法不变。

业务启动与 --structure 都从仓库根目录读取源码并校验生成快照；--structure 只展示静态原型，不创建运行 scope 句柄或执行业务。已有 Main 的 --generate 转调同一独立生成器，仍要求导入链可编译；新增 effect 或缺少生成文件时直接使用独立生成器。普通构建只编译，不隐式生成；这些模式保持同一个 workflow 业务入口。
[demo/Crawler/Main.hs](../demo/Crawler/Main.hs) 等 demo 演示 IO workflow；
各 demo 的手写入口、注册、handler 与生成模块分别可 review；
仍使用的并发辅助函数已并入当前 SDK。

同次 AST 的运行表保留，本轮迁移到有限使用闭包 once-spare、读取共享／驱动 fresh 及补全后的清理依赖，并由使用协议协调显式关闭。App／IO 的 Root Error 祖先导航使用同一 ScopeTree，实例定位、detect／resolve 与原错传播保留，不自动恢复业务。具体实现与普通编译结果须按本轮代码核对，不由旧样例推断已验证；Stream／lifelong 的协议见 [Stream 规范](STREAM_LIFELONG.md)；其他开放项见 [Next stages](NEXT_STAGES.md)。

## 5. 静态原型与动态运行

gencode 生成 `generatedPrototype :: SDK.Prototype MethodGen`。它合并 effect 注册、方法结构、WorkflowTree、origin／Context 链定义和挂载、EffectGraph、ScopeTree 与来源表。

`NodeId = [Int]` 是当前 AST 快照的位置；`Origin` 加入本次执行序号；`ActivationId` 标识活动 chain。绑定保存自己的 Execution 出身和共享 ownership，不能用节点位置替代实际实例身份。

运行时先求值并校验原型、注册与源码，再一次 cata 装配当前 AST。RuntimeGraph 复用静态定义并保存活动关系；ScopeTree 单独保持无环。不重跑 handler 建图，也不记录无限方法历史。

结构、来源证明、ScopeTree 算法及缓存细节统一引用 [EFFECT_GRAPH.md](EFFECT_GRAPH.md)。

<a id="sdk-layout"></a>
### SDK 的职责与阅读顺序

SDK 按[四层](#compiler)组织，gen 居中：

```text
sdk/Framework/
  SDK.hs                    源语言门面：手写业务只导入它
  Language/                 源语言
    Registration.hs         注册 ADT：EffectSpec、EffectTyping、Asset、Demand、Handles、EffectKind
    AST.hs                  workflow 组合子与 WorkflowF
    Handler.hs              handler 能力类（Reads、Raw、Raises）与完成结果（Failure、Output）
    History.hs              持续资产的历史视图
  Gen.hs                    编译器：按阶段执行的流水线
  Gen/
    Main.hs                 effect-codegen 命令行入口
    Source.hs               读取：解析 Types.hs、Handlers.hs，在 ghci 中求值声明
    Lower.hs / Demand.hs    降级：注册与 workflow → PrototypePlan；demand 解析与资产来源规则
    Names.hs                gen 派生的全部名字
    Bind.hs                 绑定与组成：前驱、驱动、raw、读取路由、签名与 Layer；effect 方法结构
    Shape.hs                形状：handler 方法体的读取结构
    Build.hs                构图：Prototype 构建与驱动检查
    Build/
      Graph.hs              EffectGraph 与 ScopeTree 算法
      Sources.hs            资产来源证明，保留路径相关性
    Emit/
      Effects.hs            Generated/Effects.hs
      Handlers.hs           Generated/Handlers.hs：方法体副本、At 路由与 effect 方法
      Program.hs            Generated/Program.hs 的程序部分
      Prototype.hs          Prototype 的 Haskell 值渲染
    Assets.hs / Catalog.hs  类检：类型检查、顶层白名单与资产目录
  Prototype.hs              编译产物门面：生成、执行、展示共用的静态模型
  Prototype/
    Types.hs                Prototype 的纯 ADT
    Graph.hs                方法结构、EffectGraph 与 ScopeTree 的数据
    Query.hs                只读结构、可见性与启动查询
    Validate.hs             Prototype 自洽与 AST 快照核对
    Structure.hs            静态结构展示与 scope 祖先投影
  Generated.hs              生成代码门面、程序命令与源码同步适配
  Program.hs                运行入口：原型初始化、workflow 执行与退出收尾
  Runtime.hs                Target、frame、交接与会话装配
  Runtime/
    Protocol.hs             ContextStore／ScopeStore／ErrorStore 协议与协议故障
    Context.hs              取值、分支投影与原子入口包装
    Binding.hs              绑定身份与共享归属
    Scope.hs                scope 实例、使用登记与物理清理
    App.hs                  各存储协议在 App 上的实现
    Identity.hs             Origin、ActivationId、Execution
    Graph.hs                活动链、发布与发布信号、会话登记
    Session.hs              发布历史、游标、通知与任务停止
    Execution.hs            执行 algebra、分支组合与调度
  Recursion.hs              Fix、cata、zygo
```

改声明语法从 Language.Registration 进入，再沿流水线 Lower → Bind → Build → Emit；改读取路由或入口生成从 Gen.Bind 与 Gen.Emit.Handlers 进入；改取值从 Runtime.Context → Runtime.App → Binding／Runtime.Graph 进入；改生命周期从 Runtime.Execution → Runtime → Scope／Session 进入。Gen.Build.Sources 是生成期证明，Runtime.Graph 是本次实际活动关系，Runtime.Scope 独立持有资源生命周期；三者不复制彼此的状态。

模块头说明职责和边界；关键锁、所有权、取消窗口及清理顺序在实现处保留注释。App 仍集中实现共享同一执行 frame 的存储协议，以章节分组，不为行数拆出互相依赖的状态容器。

<a id="documents"></a>
## 6. 文档分工与维护

| 文件 | 唯一职责 |
| --- | --- |
| [README](../README.md) | 项目整体介绍、一行 Main、基础组件关系和阅读入口；详细写法与操作通过引用进入指南 |
| [AGENTS](../AGENTS.md) | 工作约束、任务路由和源码定位 |
| [GUIDE](GUIDE.md) | 当前代码形态、环境准备、生成／编译／运行／结构查看及开发流程 |
| 本文 | 设计原则、当前协议和新语义的统一入口 |
| [EFFECT_GRAPH](EFFECT_GRAPH.md) | Prototype、来源分析、运行图、ScopeTree 和缓存 |
| [ASSETS](ASSETS.md) | 源码资产集合、顶层白名单和资产目录 |
| [STREAM_LIFELONG](STREAM_LIFELONG.md) | 第 7 章引用的持续执行完整规范 |
| [Next stages](NEXT_STAGES.md) | 唯一阶段计划入口，保存待审查摘要、开放项与必要的完成摘要 |

新手从 README 和 GUIDE 进入；维护者或 LLM 从 AGENTS 按任务进入本页章节及相关专题。不要为同一规则另建摘要文件或复制一份规范。

新语义先更新所属规范，GUIDE 随实际可用接口更新；明确区分当前实现、已确定但未实现、待设计和历史证据。冲突按用户已确认的语义核对，不能靠文件日期或旧 demo 的一次成功裁决。

文档保持 docs/*.md 平铺，与当前 Cabal 源码包清单一致。

<a id="stream"></a>
## 7. Stream 与 lifelong

**[STREAM_LIFELONG.md](STREAM_LIFELONG.md)是本章的完整规范，通过引用并入主设计。** 本章不重新维护另一份匹配表或调度规则；写法示例见[使用指南第五节](GUIDE.md#stream)。

增加的语义集中在三处：

1. Stream effect 提供持续来源；挂在它下面的 Context 声明 `stream = True`，会话每取得一份原始输入就调用一次 parser 逐条解析（Receive），写法与挂在原子句柄下的 Context 相同。`stream = True` 当且仅当 Input 是 Stream，且须同时 `require = True`；RepeatRequest 已取消，持续交付只由上游 Stream 驱动。生产方式只看资产自己的注册，不靠识别方法体里是 socket、event 还是 behavior，也不随别处是否有节点产出同一资产而改变。
2. 持续资产按访问方式读取：`streams "T"` 声明持续消费并授予读取权限，handler 以 `require @(History 表示类型)` 取得本次交付为止的历史；`requires "T"` 只读最新一条（`require @表示类型`），不由交付驱动。`stream` 缓存历史，`require` 缓存最新值。读取本身不领取下一个增量。
3. lifelong 的每个单元在本次执行领到订阅资产的新交付后 boot original-chain target；每次 target 调用仍有限完成，单元逐次重复，lifelong 本身没有正常结束。含 lifelong 的程序中任何失败暂按临时规则终止整次运行。

| 主题 | 本章所属规范 |
| --- | --- |
| 资产命名、Context 声明匹配、读取类型与 beforegen | [Stream 第 3 节](STREAM_LIFELONG.md#contracts) |
| Receive 的推导与启动依赖 | [Stream 第 4 节](STREAM_LIFELONG.md#bootplan) |
| 消费摘要、lifelong 合法性与原型中的表示 | [Stream 第 5 节](STREAM_LIFELONG.md#static) |
| 单元、就绪检查与有限完成边界 | [Stream 第 6 节](STREAM_LIFELONG.md#scheduling) |
| 会话、完整历史、独立游标与 frame | [Stream 第 7 节](STREAM_LIFELONG.md#sessions) |
| 生产路径与 lifelong 外的读取 | [Stream 第 8 节](STREAM_LIFELONG.md#production) |
| 失败的临时规则、取消与 close 延期边界 | [Stream 第 9 节](STREAM_LIFELONG.md#failures) |
| socket、event、behavior 各自的写法 | [Stream 第 4.1 节](STREAM_LIFELONG.md#drives) |

当前实现限制见 [Next stages](NEXT_STAGES.md#current-limits)，持续资产作为 scope 开启参数尚未接通。本轮先收敛资产来源与接收契约、分离原子 handler 与业务 effect，再处理 Stream effect 与 lifelong 的共同运行协议、资产访问、scope 使用、结束传播与清理，见[阶段计划](NEXT_STAGES.md#stages)。唯一资产来源与访问约束见[资产来源与访问约束](#demand-contract)；require 缓存最新值、stream 缓存历史已随 Stage 2 实现，Stream 的驱动方式（event、behavior、socket）仍待确定，正常 end 仍属后续设计；是否调整临时失败规则须在结束传播阶段确认。来源分析按消费单元提前裁剪再组合，相关性与复杂度边界见[图与来源](EFFECT_GRAPH.md)。

这次扩展继续使用 Prototype、RuntimeGraph 和独立 ScopeTree。业务方法不新增游标、yield、调度器或无限递归写法；声明不成立时生成期诊断，不在运行中猜测生产方式。

## 8. 计划与证据

实施批次、开放问题和必要验证摘要统一保存在 [Next stages](NEXT_STAGES.md)。新阶段推进时同步更新本文状态、所属规范与实际接口指南，不能把计划写成已实现能力。验证摘要保留日期和未覆盖范围，不代表本次重新执行。
