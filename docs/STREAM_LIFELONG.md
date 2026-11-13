# Stream 与 lifelong：资产驱动的自动装配

本文通过引用构成[主设计第 7 章](LATEST_DESIGN.md#stream)的完整规范。主设计负责架构地图，本页唯一维护 Stream 的匹配、交付和调度规则；实施记录在 [Next stages](NEXT_STAGES.md)，写法示例在[使用指南第五节](GUIDE.md#stream)。

更新：2026-11-08。状态：已实现（Stage 3 第 1–6 批；Stage 2 改为 Stream 加 parser、取消 RepeatRequest）；当前实现限制见 [Next stages](NEXT_STAGES.md#current-limits)，延期项见[第 11 节](#deferred)。

本文手工记录 Stream、Context 与 lifelong 的匹配规则，作为代码生成、解释器和开发文档共同遵守的规范。下列规则与当前 SDK 一致；标明“延期”或“临时”的部分不是最终设计。

## 1. 目标：让原子方法独立于装配知识

业务作者按已经生成的类型和原生 Haskell 编写一次取得、一次解析或一次消费。SDK 根据注册、handler 的读取结构、资产和 AST 控制关系，自动生成生产、解析、交付和 target boot 的连接：

    声明与可提取的读取结构
    → 检查匹配前提
    → 生成唯一装配及其依据
    → interpreter 执行已经装配的闭包

业务作者需要知道本地输入输出、`require`、`raw` 和 `raise`，不需要知道 BootPlan、会话、游标或调度循环。

自动装配只依赖明确契约，不从任意 IO 恢复作者意图。匹配不成立时生成期诊断，不按方法名相似度、运行速度或最后写入猜选。原子化约束保证组合可观察，不证明任意方法体足够细、无副作用或必然返回。

AST branch 继续规定何时、按何种顺序、选择哪些入口以及是否重复 boot。业务组合写在注册与 AST 中，AST 不成为业务值 pipeline。程序入口保持 `interpreter ast effects`。

## 2. 术语与职责

| 结构 | 职责 |
| --- | --- |
| Stream effect | 第六种 typing；绑定的 handler 每次取得一份原始输入（`String`），只由生产会话驱动 |
| parser | 挂在 Stream 下的 Context 绑定的 handler：用 `raw` 读取会话本次取得的原始输入，返回表示类型的值 |
| Context.stream | `True` 声明持续资产，缓存发布历史；只能挂在 Stream 下，且须同时 `require = True` |
| Context.require | `True` 缓存最新值；读取已有绑定或交付视图，不生产，普通资产还没有值时等待发布 |
| 持续资产 | `stream = True` 的资产：`streams` 读取 `History`，`requires` 读取最新一条，可以被 `streams` 订阅 |
| `streams "T"` | 消费方声明以资产 T 的新交付驱动，同时取得读取权限；不是调用 parser 的语法 |
| lifelong | 为其单元订阅会话，在交付就绪时 boot original target |
| BootPlan | 生成器按生产方注册推导的生产方式：当前只有 Receive，不是手写标签 |
| 会话 | 一个边界内某持续资产的生产任务与完整发布历史 |
| publication | 一次成功发布；保留值、出身和共享归属引用 |
| 消费单元 | lifelong 下独立推进的有限控制程序 |
| 游标 | 单元在某会话中已经领取的条数 |
| frame | 单元一次执行的交付视图与普通来源解析范围 |

Stream 不进入 original chain，也不作为 AST target；只通过它下面的 parser Context 进入生产。original target 始终代表一条完整消费链的末端。

socket、event、behavior 用来解释不同的驱动关系，但不是类型标签；它们在 SDK 中如何区分仍待确定，目前的写法见 [4.1 节](#drives)。挂在 Stream 下的 Context 与挂在原子句柄下的 Context 写法相同：parser 用 `raw` 取得本次输入。

<a id="contracts"></a>
## 3. 资产、方法与 beforegen

### 3.1 资产身份独立于方法身份

业务表示类型先在 Types.hs 定义，Context 把它细化为一个资产（refinement asset，意义见[主设计 4.3](LATEST_DESIGN.md#refinement)），并绑定 parser。挂在 Stream `TemperatureFeed` 下的 Context 写作：

    typing = Context
      { asset   = Asset @Temperature "TemperatureSample"
      , parser  = Just "parseTemperature"
      , require = True
      , stream  = True
      }

生成器产出 `newtype TemperatureSample = TemperatureSample Temperature`，方法名由资产名 T 固定生成，用户不写也不调用：

| 方法 | 职责 |
| --- | --- |
| `getT` | 执行 parser 并包装发布一个资产；会话每取得一份原始输入调用一次 |
| `streamT` | 读取确定的历史视图（SDK 实现，消费方经路由的 `require` 使用） |

parser 没有另外的输入方法：`raw` 由会话本次取得的输入回答，读作单元素 list（`(: []) <$> next名字`），不再执行 Stream handler，与挂在原子句柄下的 Context 读取句柄输出相同（[主设计 4.3](LATEST_DESIGN.md#context) 的原子输出挂接）。首次生成契约后才编写 Handlers。

同一 refined asset 的所有访问方式共享固定表示 ADT 和唯一 Context 来源；读取的返回形态不同，不会产生第二种资产身份。声明与读取依据统一见[主设计：资产来源与访问约束](LATEST_DESIGN.md#demand-contract)，包括 streams 在 Prototype 中的交付依据。

### 3.2 Context 声明的匹配表

生产方式只看 Context 自己的注册：

| Context.input | stream | require | 结果 |
| --- | --- | --- | --- |
| Stream effect | `True` | `True` | 持续资产，Receive：Stream 单步＋parser |
| Stream effect | `False` | 任意 | 报错：挂在 Stream 下的 Context 须声明 `stream = True` |
| Stream effect | `True` | `False` | 报错：`stream = True` 需要 `require = True` |
| Root 或普通 effect | `True` | 任意 | 报错：`stream = True` 只能挂在 Stream 下 |
| Root 或普通 effect | `False` | 任意 | 普通单值资产 |

另外：Context 必须声明 parser；Stream 必须声明 handler；以 Stream 为 input 的必须恰好是一个 Context（它的 parser），其他 effect 不能直接取得原始输入。挂在 Stream 下的资产只由会话生产，消费方不能声明 `requests "T"`。只有直接 input 算数；Stream 下的 parser 不把 Stream 当作前驱执行。

### 3.3 消费权限与读取类型

消费方写 `streams "T"`，handler 用 `require @(History 表示类型)` 读取交付。streams 同时授予这项读取权限，不必再写 `requires "T"`。

- 只有持续资产的基础资产可以被订阅；订阅分支契约时报错，应订阅其基础资产。
- 只有 Excu、Scoped 可以声明 streams。
- `requires "T"` 读取持续资产时，handler 用 `require @表示类型` 取得最新一条，不由交付驱动。

读取类型按访问方式确定：streams 返回 `History 表示类型`，requires 返回最新一条；普通资产保持单值读取。`stream` 缓存历史，`require` 缓存最新值；两者是同一资产的不同结果形态，不是两个来源。若需要两个独立来源或独立持续能力，再细化为两个资产。分支契约投影本次交付的最新条目。读取历史另设方法（gen 已生成 `streamT`）的写法待定。

History 是从会话首条发布到确定交付位置的有限、不可变序列，由 SDK 构造：`latest`、`historyEntries`、`historySize` 读取。相等值的两个 publication 仍是两条。无限的是 SDK 持续推进的过程，不是业务手写的无限列表。History 包装共享发布序列，不逐条重建业务值；`latest` 取末项，`historySize` 取长度。领取一条交付还涉及序列前缀切分和伴随发布索引，因此不把整个领取过程承诺为常数时间；`historyEntries`、完整显示、比较或遍历可能访问全部条目。

### 3.4 原子输入与源码约束

Stream handler 一次返回一个原始输入，parser 一次解析一个。parser 的 `raw` 由会话本次取得的输入回答，不再执行 Stream handler 另取一份；Stream handler 由会话驱动，其他 handler 不能取得原始输入。Stream 有自己的数据结构：handler 仍是每次一份 `String`，不改成原子句柄的 list 输出，下面也不挂 Pure（[主设计：Pure](LATEST_DESIGN.md#pure)）。Stream 自己的 Input（例如传感器连接的 Scoped）作为前驱在 handler 之前执行，跨生产步骤保持（见 8.1）。业务只写原生 instance、读取、ADT、局部计算和 raise，不手写 yield、递归连接、publish、subscribe、acknowledge 或回调参数；顶层白名单继续适用（[ASSETS](ASSETS.md)）。

Excu／Scoped 交出的 `[String]` 是原子句柄的输出，不能把空 list 释为 EOF；正常结束协议本版延期。

<a id="bootplan"></a>
## 4. 生产方式（BootPlan）

| BootPlan | 前提（只看生产方注册） | 生产步骤 |
| --- | --- | --- |
| Receive | Context 的直接 input 是 Stream，`stream = True` 且 `require = True` | Stream 单步取得原始输入 → parser 解析并发布 |

Stage 2 取消了 RepeatRequest：不在 Stream 下的 Context 不能声明持续资产，持续交付只由上游 Stream 驱动。原先用 RepeatRequest 表达的采样（StreamDemo 的心跳）改为 Stream 加 parser。

不推导“观察既有原链”的生产方式：被观察的原链要持续产出，只能与 lifelong 并行，而并行兄弟互不可见；若改为观察排在前面的有限前驱，它只发布有限次。更重要的是，“是否已有别的原链生产 T”是全局事实，别处新增一个驱动节点就会让这里的生产方式悄悄改变。生产方式因此只看资产自己的注册，任何别处的改动都不会改变它。

不成立的组合在生成期按 3.2 的匹配表报错，不在运行中猜测或退化为轮询。

**启动依赖**：lifelong 会话的生产链（Stream 单步、parser 及其读取可达的方法）不能读取其他持续资产，否则首次交付要先等待另一个 stream，生成期拒绝。interpreter 托管的会话（8.3）不受此限。

<a id="drives"></a>
### 4.1 socket、event、behavior 的写法

这三个词描述外部数据怎样到来，帮助业务作者写 Stream handler；SDK 目前不识别它们，也不据此改变生产方式。三种驱动方式在 SDK 中如何区分仍待确定（见 [Stage 2：本阶段不处理](NEXT_STAGES.md#stage-2-later)），当前都写成 Stream 加 parser：

| 驱动关系 | 数据怎样到来 | 写法 |
| --- | --- | --- |
| socket | 外部持续送来原始数据，逐条接收：连接、消息队列、传感器读数 | Stream handler 阻塞接收一份原始输入（`m String`），parser 解析；连接等资源放在 Stream 的 Input 上游 scope 中，跨生产步骤保持（见 8.1） |
| behavior | 值一直存在，随时可以采样：时钟、心跳、状态轮询 | Stream handler 先等待采样间隔，再取当前值 |
| event | 离散地发生，每次发生得到一条 | Stream handler 阻塞读取下一个事件 |

- 节奏只由 Stream handler 的阻塞或等待决定，SDK 不加间隔；立即返回的 handler 会形成高频生产。
- 不提供“观察 AST 中某条原链的发布”作为事件来源，理由见本节上方；lifelong 外的普通驱动也不广播给任何会话。lifelong 内部产生事件的反馈写法随 RepeatRequest 一起取消，待驱动方式确定后再设计。
- 外部 push callback 不能直接注册给 SDK，需要先转换成可阻塞读取的队列，再作为单步来源；通用回调适配本版延期（见第 11 节）。
- StreamDemo 中，`TemperatureFeed`＋`TemperatureParser` 是 socket 写法，`HeartbeatClock`＋`Heartbeat` 是 behavior 写法。

<a id="static"></a>
## 5. 静态结构与合法性

### 5.1 消费摘要

每个挂载的 target 的订阅只看 original chain 自身：末端 effect 及其 Input 祖先声明的 streams demand。不能汇总 `chainReaches`，它包含被驱动的 Context 与生产链内部的传递可达方法；生产链内部的依赖另用于启动依赖检查。

### 5.2 lifelong 合法性

1. lifelong 内每个挂载的 target 恰好订阅一个持续资产。
2. 这些 target 的 original chain 不再读取（requires／streams）其他持续资产；否则执行结果取决于读取时刻。分支契约按其基础契约计入：读取所订阅资产的分支是同一资产，读取其他持续资产的分支同样被拒绝。多个来源的触发组合另行设计。
3. 只有普通 requests／requires 的末端不能进入 lifelong；一次性准备放在外部 chained。streams 末端不能出现在 lifelong 之外。
4. Stream、Context 不作为 target。
5. lifelong 不嵌套；lifelong 内不能有空分支。因为每个 target 都订阅，单元每条成功路径都至少领取一条新交付。
6. 合法 Haskell 不自动等于结构可提取；未知高阶 effect、隐藏的 effect 循环等继续使用现有诊断。
7. 会话生产步骤顺带发布的普通资产（例如 parser 链上 `requests` 驱动的辅助资产 X）随每条交付保存为伴随发布（见 7）。lifelong 内以生产步骤为来源读取这类资产的位置，必须由该会话的资产驱动：订阅它的 target，或以它为转折资产的选择读取；否则生成期拒绝，因为读到哪一步的产物将取决于调度。需要各单元共享同一个值时，在 lifelong 之前生产它。

这些检查不证明任意原子 IO 能够返回，也不证明即时采样会限速。

### 5.3 原型中的表示

lifelong 写入统一 Prototype，运行装配、来源分析与 `--structure` 读取同一份数据：

    LifelongAt NodeId LifelongProto [WorkflowTree]

    LifelongProto
      { lifelongUnits         :: [NodeId]            -- 单元：直接子项；直接子项是 parallel 时为它的子项
      , lifelongSubscriptions :: [(NodeId, String)]  -- 每个挂载 target 订阅的资产
      , lifelongSessions      :: [SessionProto] }    -- 被订阅的每个资产一份会话

    SessionProto { sessionAsset :: String, sessionPlan :: BootPlan, sessionMounts :: [NodeId] }
    BootPlan = Receive String                       -- 记录 Stream 的注册名；RepeatRequest 已取消

- 会话挂载 NodeId 为 lifelong 路径加 `[-1, 会话序号, 步骤]`：步骤 0 是 Stream 单步、步骤 1 是 parser。挂载以 `SessionChain` 角色进入 `protoChains`，参与构图与 ScopeTree。
- `protoSessions` 为每个 Receive 资产登记一份 interpreter 托管的会话，挂载为 `[-2, 序号, 步骤]`；它不属于 AST，不是任何读取点的可见前驱。
- 可见性：lifelong 的会话挂载先于它的全部单元。来源分析中，会话挂载按各消费单元的后续读取需求分别作为根分析，以进入 lifelong 时的交接（例如外层 alternative 选择时捕获的值）为已捕获绑定；运行时每个生产步骤也从这份交接开始（见 8.1）。单元的执行以订阅资产的交付作为已捕获绑定，出身是会话的生产步骤；单元读取生产步骤的其他普通发布时，读到的是所处理交付那一步的发布（伴随发布，见 7）。会话挂载的各个成功出口不合并：一条交付的伴随发布对应一次成功的生产步骤（Stream 单步与 parser 各一个成功出口），单元按每种交付状态分别分析。Stage 2 取消 lifelong 内的显式 request 后，不再出现“没有伴随发布”的交付状态。某条交付的伴随发布中没有辅助资产 X 时，单元中读取 X 的位置不补产，等待它的发布；需要这个值时按第 5.2 节第 7 条，由该会话的资产驱动读取位置，或在 lifelong 之前生产它。lifelong 之后的后继按“没有正常结束”处理。
- 分析裁剪：以 `lifelongUnits` 确定单元，不穿透单元内的 chained、alternative 或 parallel。每个生产挂载保留本单元可能读取的契约及生产链自身的读取依赖，成功出口再按单元相关契约投影、去重，然后逐步组合 Receive 的步骤和各会话状态。仍分析全部会话，避免遗漏其他会话造成的来源冲突；不把成功出口取并集。生产链的 read／drive 事实独立累计。
- 读取点来源新增 `FromSession`：持续资产在没有本次交付时由 interpreter 托管的会话交付，不查询普通来源表。
- `--structure` 在 Workflow 中列出每个 lifelong 的单元、会话（生产方式与挂载）和订阅，并单独列出 interpreter 会话。

<a id="scheduling"></a>
## 6. lifelong 的回调 boot 与控制流

### 6.1 单元划分

lifelong 的直接子项分别形成独立单元；直接子项为 parallel 时，只拆这一层。其余子树作为有限单元，不穿透 chained、alternative 或更深的 parallel。

    lifelong [parallel [chained [a, b], c]]

得到单元 `chained [a, b]` 和单元 `c`，两者独立推进：b 等待 a 本次调用成功；c 不等待 a、b 完成才领取下一条。

    lifelong [chained [parallel [a, b], c]]

这是一个单元；内部 parallel 保留局部汇合，再执行 c。拆分边界写入 Prototype（`lifelongUnits`），运行时不推测或递归拉平。不存在整个 lifelong 的统一轮次。

### 6.2 两个完成边界

| 对象 | 完成含义 |
| --- | --- |
| 一次 target 调用 | 既有成功／失败协议；本次 original chain 完成，有自己的 Origin |
| 持续订阅／lifelong | 本版没有正常 Succ，只因失败或取消退出 |

lifelong 安装订阅后不冒充整个 branch 的 Succ，否则外部 chained 无法表达完成依赖。

### 6.3 就绪与一次执行

每个单元逐次执行：一次执行结束后才开始下一次，同一单元的调用不重叠。一次执行就是一个 frame：

- **boot 条件**：控制流到达某个 target 时，若本 frame 尚未领取它订阅的资产，先领取一条新交付；有积压时立即领取，没有新发布时挂起等待。领取到交付后才 boot target。不在生产调用栈里同步执行消费业务，也不反复调用 handler 试探数据。
- **每个资产只领取一次**：同一 frame 中后续 target、alternative 的选择读取与候选、内部 parallel 中同时需要它的节点，都共享第一次领取的视图。alternative 的转折资产若是本 lifelong 的会话资产，选择读取先领取，候选共享；持续的和类型资产按本次交付的最新条目选择候选。lifelong 外的 alternative 以持续资产为转折时，同样按选择读取取得的视图的最新条目分派。
- **首次读取领取**：frame 中尚未领取的本 lifelong 会话资产，在第一次读取时领取（例如被生产链读取）。
- **结束**：单元的一次执行结束后，下一次执行开始前清除该单元子树上一次执行的 Origin 及其普通发布；本次没有执行到的位置不会读到上一次的普通产物。执行结果不累积。

因为每个单元顺序推进，“数据在前驱执行期间已经到达”时，前驱完成后后继直接领取积压；同一位置在一个 frame 内只 boot 一次。

### 6.4 外部组合

| 写法 | 行为 |
| --- | --- |
| `parallel [monitor, otherWork]` | 两者同时运行；monitor 等待增量不阻止 otherWork |
| `chained [setup, monitor]` | setup 成功后进入 monitor |
| `chained [monitor, after]` | after 等待 monitor 结束；本版 monitor 没有正常完成，after 不执行 |
| `chained [parallel [monitor, otherWork], after]` | 内层分支的完成仍是 after 的前提 |

monitor 表示 lifelong 模块。并发运行与整个 branch 已完成是不同概念。

<a id="sessions"></a>
## 7. 会话、历史、游标和 frame

| 状态 | 归属 |
| --- | --- |
| 会话与发布历史 | （lifelong 边界，生产该资产的 Context 注册名）；interpreter 托管的会话边界为空 |
| 交付游标 | 消费单元＋会话 |
| 本次固定视图 | 单元执行 frame＋资产 |
| target 执行 | NodeId＋新的 Origin |
| 生产步骤执行 | 会话挂载 NodeId＋每步新的 Origin |
| 生产资源的使用登记 | 会话（跨步骤保持，见 8.1） |
| scope 归属 | 既有 Binding ownership 与具体 scope 实例 |

- 同一边界同一资产共享会话，不同单元各自推进；不同 lifelong 的会话与进度独立。
- 会话在进入 lifelong 时取得并启动生产；单元的游标从会话的第一条发布开始。每次领取推进一条，视图是会话历史到这一条为止的前缀。
- 每条 publication 保留原始 Binding、Execution 与共享 ownership；history 不是一个新的 owner。后台追加不改写已经取得的视图；读取不推进游标。
- 会话驱动资产的发布进入会话历史，不写入按 Origin 的普通资产表；生产步骤发布的普通辅助资产仍按 Origin 保存，并在交付时保存其伴随引用。普通跨链读取继续遵守捕获和静态来源规则。
- 每条交付另带产生它的生产步骤已经发布的普通资产（伴随发布）。frame 领取交付后，伴随发布作为已捕获绑定交给本次执行中的调用，交接中已经捕获的值优先；运行时不再按会话挂载的当前 Origin 读取这些发布。因此处理第 n 条交付时读到第 n 步的辅助资产，不会读到之后步骤的产物，也不会因旧发布已被替换而重新生产。
- 运行初始化不预生产 Context；会话按需启动。

<a id="production"></a>
## 8. 生产与普通读取

### 8.1 生产路径

    Receive：Stream 单步取得原始输入 → 安装为 parser 的本次输入（raw） → parser 解析并发布一次 → 下一步

parser 的包装发布一次；会话不再次发布返回值，也不再调用一次 parser。每一步是一次独立的受控调用（自己的 Origin 与捕获环境），会话以发布写入历史。lifelong 的会话保存进入 lifelong 时的交接，每一步从它的新副本开始：外层已经捕获的值（例如 alternative 选择时读到的配置）在生产端与消费端一致，生产步骤不会另行生产一份。interpreter 托管的会话没有交接。

生产会话的各步骤共用会话的 scope 使用登记：一步结束不会按 once-spare 关闭生产用到的资源，下一步按既有协议复用（例如无开启参数的连接 scope）。会话停止时撤销这份登记，资源交给 interpreter 退出清理。下一步的回收规则已确定、尚未实现：会话是可达性的根，运行结束时关闭声明了 close 的实例，见[主设计：按可达性回收](LATEST_DESIGN.md#scope-gc)。

Stream handler 的阻塞／等待决定节奏，SDK 不加间隔；立即返回的生产会形成高频生产，完整历史随之增长。本版不提供容量背压、丢弃或去重。

### 8.2 显式驱动与反馈

Stage 2 起持续资产只挂在 Stream 下，由会话生产，消费方不能 `requests` 它；原先在 lifelong 内以 `request @T` 把新发布送进会话的反馈写法随 RepeatRequest 一起取消，待 Stream 的驱动方式确定后再设计。

lifelong 外的普通驱动按原有 origin 发布，不因类型相同就广播给任何会话。

### 8.3 lifelong 外的有限读取

普通 `requires "T"` 只执行一次消费，不进入 lifelong，handler 取得最新一条。本次调用已有视图时读取它；否则由 interpreter 托管的会话（`protoSessions`）交付：会话在第一次需要时启动，读取至少等到一条发布，取得当时的历史并捕获为本次视图，再取其最新一条。会话保持到 interpreter 退出；后续调用取得当时的历史，同一调用已经捕获的视图保持不变。

诊断、自动收尾与 close 期间不启动会话。

<a id="failures"></a>
## 9. 故障、取消与资源边界

### 9.1 失败：临时规则

lifelong 的 close 语义设计之前，采用下面的临时规则：

1. **适用范围**：只在 AST 中包含 lifelong 时生效；不包含 lifelong 的程序，失败处理保持现状（interpreter 会话的生产失败只传给等待它的读取方）。
2. **触发**：生产失败、解析失败、消费单元失败、AST 中任何 node 或 alternative 选择读取的失败，以及上述任务中的原生异常。
3. **处理**：结构化 Failure 先完成既有 Error 协议的诊断与处置，原生异常直接通知运行监督。随后终止整次运行：停止启动新工作，取消全部任务（会话、等待中的单元、执行中的 target、其他并行分支）并等待受控收尾，走 interpreter 退出清理；结构化失败报告最初的 `Failed`，原生异常重新抛出。
4. **不做**：不只终止局部的 lifelong，不让外层 chained 继续执行后继，不重试。

失败在发生处直接通知运行监督，因此 `parallel [monitor, otherWork]` 中 otherWork 的失败不会因等待永不结束的 monitor 而被吞掉。失败的会话不再接受新发布，等待它的读取方收到原失败。

### 9.2 取消

外部取消（Ctrl-C）时，SDK 取消 AST 中的全部任务并等待其受控收尾，再停止全部会话（撤销会话的使用登记），最后由 interpreter 按 ScopeTree 关闭剩余资源。对于结构化 Failure，清理故障附在原失败之后；对于 Ctrl-C 等原生异常，清理故障单独报告后重新抛出原异常。

创建会话时，启动生产任务与写回会话登记在同一个不可中断区内完成，取消不会落在两者之间。停止会话时先关闭会话登记，并在同一临界区取出全部会话：此后尚未停止的生产步骤不能再启动新会话（例如 interpreter 托管的依赖会话），请求方得到异常并随停止结束，不会留下逃出停止集合的生产任务。生产任务的启动与登记、失败报告、撤销使用登记和完成信号都在不可中断区内完成，生产时解除屏蔽，停止等待任务退出。这保证 SDK 的登记与完成信号交接不会被取消打断；任务能否退出仍依赖业务 IO 响应取消、诊断与收尾能够返回。

### 9.3 close 延期的含义

不新增 Stream close、next-use 或历史资源按元素关闭协议。没有增量表示等待，不表示 EOF、故障或关闭。

Stream close、lifelong 的局部结束、会话生产资源与历史资源的存续，以及持续资产作为 scope 开启参数，纳入本轮[六阶段计划](NEXT_STAGES.md#stages)。计划以 Stream effect 与 lifelong 的共同运行协议为基础；require 缓存最新值、stream 缓存历史已随 Stage 2 实现，单一 demand 与正常 end 尚未实现，本页记录当前协议。

完整历史保留不等于可以把多份资源 owner 合成一个，也不能复活已关闭的资源。通用的历史资源选择／关闭语义尚未设计。会话历史在运行期间持续增长，不承诺有界内存。持续资产作为 scope 开启参数尚未接通 History 的参数观察协议，可能报 `ScopeInputsMissing`；现有跨轮 scope 复用不代表支持该用法，跟踪见 [Next stages](NEXT_STAGES.md#current-limits)。

<a id="implementation"></a>
## 10. 实现位置

| 内容 | 源码 |
| --- | --- |
| Stream typing、Context 声明 | [Registration.hs](../sdk/Framework/Language/Registration.hs) |
| `streams` 与权限检查 | [Gen/Demand.hs](../sdk/Framework/Gen/Demand.hs) |
| 声明匹配、lifelong 合法性、单元／订阅／会话 | [Gen/Lower.hs](../sdk/Framework/Gen/Lower.hs) |
| `protoSessions`、启动环检查、来源分析 | [Gen/Build.hs](../sdk/Framework/Gen/Build.hs)、[Gen/Build/Sources.hs](../sdk/Framework/Gen/Build/Sources.hs)、[Prototype/Query.hs](../sdk/Framework/Prototype/Query.hs)（`finiteSessions`、`bootPlan`） |
| History 视图 | [History.hs](../sdk/Framework/Language/History.hs) |
| 会话状态、历史、游标 | [Session.hs](../sdk/Framework/Runtime/Session.hs) |
| 会话登记、Origin 清除 | [Graph.hs](../sdk/Framework/Runtime/Graph.hs) |
| 生产任务、frame、交付视图的交接 | [Runtime.hs](../sdk/Framework/Runtime.hs) |
| 视图读取、最新值投影（`latestContext`）、parser 输入、会话发布路由 | [App.hs](../sdk/Framework/Runtime/App.hs)、[Context.hs](../sdk/Framework/Runtime/Context.hs) |
| 单元调度、就绪检查、运行监督 | [Execution.hs](../sdk/Framework/Runtime/Execution.hs) |
| 生成的读取方法与路由、Stream 入口的会话包装、`Raw` 实例、会话步骤登记 | [Gen/Emit/Handlers.hs](../sdk/Framework/Gen/Emit/Handlers.hs)、[Gen/Emit/Program.hs](../sdk/Framework/Gen/Emit/Program.hs)、[Context.hs](../sdk/Framework/Runtime/Context.hs)（`streamHandle`） |

ScopeTree 独立构建并保持无环；订阅与回调关系不作为 scope 父边。运行时不累计完整方法调用历史或无限 workflow 结果。

<a id="deferred"></a>
## 11. 验证与延期

本仓库按约定只做普通编译、生成结果审阅和示例观察，不新增测试框架、负例或穷举门槛。已有验证范围概述见 [Next stages](NEXT_STAGES.md#baseline)，逐次观察记录保留在 Git 历史。LSP 仓库的外部穷举模型尚未扩展到 Stream／lifelong。

本版明确延期：正常 EOF／Done、Stream close、lifelong 的局部结束（当前由 9.1 的临时规则代替）、历史资源精细关闭与回收、嵌套 lifelong、多个持续来源组合触发一个 target、自动重试、时间周期声明、容量背压、任意外部 push callback 注册和跨 interpreter 存续。已有阻塞事件／队列读取、socket 接收及主动采样可作为单步来源（写法见 [4.1 节](#drives)）；不据此宣称自动适配所有外部回调 API。其中与结束和资源存续相关的项目转入[下一阶段](NEXT_STAGES.md#stages)。
