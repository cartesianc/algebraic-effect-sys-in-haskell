# Stream 与 lifelong：资产驱动的自动装配

本文通过引用构成[主设计第 7 章](LATEST_DESIGN.md#stream)的完整规范。主设计负责架构地图，本页唯一维护 Stream 的匹配、交付和调度规则；实施记录在 [Next stages](NEXT_STAGES.md)，写法示例在[使用指南第五节](GUIDE.md#stream)。

更新：2026-11-14。状态：已实现（Stage 3 第 1–6 批；Stage 2 改为 Stream 加 parser、取消 RepeatRequest；Stage 6 第一步：Stream 的正常结束 `end`、排空、单元结束与 lifelong 返回，见[第 9.4 节](#end)）；当前实现限制见 [Next stages](NEXT_STAGES.md#current-limits)，延期项见[第 11 节](#deferred)。

本文手工记录 Stream、Context 与 lifelong 的匹配规则，作为代码生成、解释器和开发文档共同遵守的规范。下列规则与当前 SDK 一致；标明“延期”或“临时”的部分不是最终设计。

## 1. 目标：让原子方法独立于装配知识

业务作者按已经生成的类型和原生 Haskell 编写一次取得、一次解析或一次消费。SDK 根据注册、handler 的读取结构、资产和 AST 控制关系，自动生成生产、解析、交付和 target boot 的连接：

    声明与可提取的读取结构
    → 检查匹配前提
    → 生成唯一装配及其依据
    → interpreter 执行已经装配的闭包

业务作者需要知道本地输入输出、`require`、`raw`、`raise`，以及 Stream handler 报告来源结束的 `end`，不需要知道 BootPlan、会话、游标或调度循环。

自动装配只依赖明确契约，不从任意 IO 恢复作者意图。匹配不成立时生成期诊断，不按方法名相似度、运行速度或最后写入猜选。原子化约束保证组合可观察，不证明任意方法体足够细、无副作用或必然返回。

AST branch 继续规定何时、按何种顺序、选择哪些入口以及是否重复 boot。业务组合写在注册与 AST 中，AST 不成为业务值 pipeline。程序入口保持 `interpreter ast effects`。

## 2. 术语与职责

| 结构 | 职责 |
| --- | --- |
| Stream effect | 第六种 typing；绑定的 handler 每次取得一份原始输入（`String`），只由生产会话驱动；来源没有下一份输入时以 `end` 结束（[9.4](#end)） |
| parser | 挂在 Stream 下的 Context 绑定的 handler：用 `raw` 读取会话本次取得的原始输入，返回表示类型的值 |
| Context.stream | `True` 声明持续资产，缓存发布历史；只能挂在 Stream 下，且须同时 `require = True` |
| Context.require | `True` 缓存最新值；读取已有绑定或交付视图，不生产；普通资产缺值按[Context 的等待与结束规则](LATEST_DESIGN.md#context)处理，持续交付沿用本专题协议 |
| 持续资产 | `stream = True` 的资产：`streams` 读取 `History`，`requires` 读取最新一条，可以被 `streams` 订阅 |
| `streams "T"` | 消费方声明以资产 T 的新交付驱动，同时取得读取权限；不是调用 parser 的语法 |
| lifelong | 为其单元订阅会话，在交付就绪时 boot original target |
| BootPlan | 生成器按生产方注册推导的生产方式：当前只有 Receive，不是手写标签 |
| 会话 | 一个边界内某持续资产的生产任务与完整发布历史 |
| publication | 一次成功发布；保留值、出身和共享归属引用 |
| 消费单元 | lifelong 下独立推进的有限控制程序 |
| 游标 | 单元在某会话中已经领取的条数 |
| frame | 单元一次执行的交付视图与普通来源解析范围 |

Stream 不进入 original chain，也不作为 AST target；只通过它下面的 parser Context 进入生产。original target 始终代表一条完整消费链的末端。这条限制是确定的：持续资产的生产始终在会话里，与消费并发；Stream 不向 AST 返回 Succ，它的结束只由等待交付的单元和 lifelong 观察。

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

Excu／Scoped 交出的 `[String]` 是原子句柄的输出，不能把空 list 释为 EOF。来源的结束只由 Stream handler 用 `end` 报告，见 [9.4 节](#end)。

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
- 可见性：lifelong 的会话挂载先于它的全部单元。来源分析中，会话挂载按各消费单元的后续读取需求分别作为根分析，以进入 lifelong 时的交接（例如外层 alternative 选择时捕获的值）为已捕获绑定；运行时每个生产步骤也从这份交接开始（见 8.1）。单元的执行以订阅资产的交付作为已捕获绑定，出身是会话的生产步骤；单元读取生产步骤的其他普通发布时，读到的是所处理交付那一步的发布（伴随发布，见 7）。会话挂载的各个成功出口不合并：一条交付的伴随发布对应一次成功的生产步骤（Stream 单步与 parser 各一个成功出口），单元按每种交付状态分别分析。Stage 2 取消 lifelong 内的显式 request 后，不再出现“没有伴随发布”的交付状态。某条交付的伴随发布中没有辅助资产 X 时，单元中读取 X 的位置不补产，等待它的发布；需要这个值时按第 5.2 节第 7 条，由该会话的资产驱动读取位置，或在 lifelong 之前生产它。lifelong 有一个正常出口：进入 lifelong 之前可见的发布照常交给后继。lifelong 内部的发布（单元的普通产物、持续资产本身）交给后继读取尚未实现；后继的读取没有其他可见来源时，生成期报 `InvalidLifelong`，不留到运行时缺值或另行启动来源。
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
| 持续订阅／lifelong | 全部单元正常结束后返回一次 Succ，不带结果；来源不结束时不返回，另因失败或取消退出 |

lifelong 安装订阅后不冒充整个 branch 的 Succ，否则外部 chained 无法表达完成依赖。两个 Succ 各管一层：一次执行的 Succ 决定单元内的后继是否执行，lifelong 的 Succ 决定外层的后继是否执行。Stream 自己不给 Succ。

### 6.3 就绪与一次执行

每个单元逐次执行：一次执行结束后才开始下一次，同一单元的调用不重叠。一次执行就是一个 frame：

- **boot 条件**：控制流到达某个 target 时，若本 frame 尚未领取它订阅的资产，先领取一条新交付；有积压时立即领取，没有新发布时挂起等待。领取到交付后才 boot target。不在生产调用栈里同步执行消费业务，也不反复调用 handler 试探数据。
- **每个资产只领取一次**：同一 frame 中后续 target、alternative 的选择读取与候选、内部 parallel 中同时需要它的节点，都共享第一次领取的视图。alternative 的转折资产若是本 lifelong 的会话资产，选择读取先领取，候选共享；持续的和类型资产按本次交付的最新条目选择候选。lifelong 外的 alternative 以持续资产为转折时，同样按选择读取取得的视图的最新条目分派。
- **首次读取领取**：frame 中尚未领取的本 lifelong 会话资产，在第一次读取时领取（例如被生产链读取）。
- **结束**：单元的一次执行结束后，下一次执行开始前清除该单元子树上一次执行的 Origin 及其普通发布；本次没有执行到的位置不会读到上一次的普通产物。执行结果不累积。
- **来源耗尽**：领取时来源已结束且积压已领完，这个位置不 boot，单元正常结束，见 [9.4 节](#end)。

因为每个单元顺序推进，“数据在前驱执行期间已经到达”时，前驱完成后后继直接领取积压；同一位置在一个 frame 内只 boot 一次。

### 6.4 外部组合

| 写法 | 行为 |
| --- | --- |
| `parallel [monitor, otherWork]` | 两者同时运行；monitor 等待增量不阻止 otherWork |
| `chained [setup, monitor]` | setup 成功后进入 monitor |
| `chained [monitor, after]` | after 等待 monitor 结束：monitor 的全部单元正常结束后 after 执行；有来源始终不结束时 after 不执行 |
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
- 每条 publication 保留原始 Binding、生产 ActivationId、执行帧、Execution 与共享 ownership；history 不是一个新的 owner。后台追加不改写已经取得的视图；读取不推进游标。
- 会话驱动资产的发布进入会话历史，不写入按 Origin 的普通资产表；生产步骤发布的普通辅助资产仍按 Origin 保存，并在交付时保存其伴随引用。普通跨链读取继续遵守捕获和静态来源规则。
- 每条交付另带产生它的生产步骤已经发布的普通资产（伴随发布）。DeliveryFrame 领取交付后，伴随发布作为已捕获绑定交给本次执行中的调用，交接中已经捕获的值优先；运行时不再按会话挂载的当前 Origin 读取这些发布。因此处理第 n 条交付时读到第 n 步的辅助资产，不会读到之后步骤的产物，也不会因旧发布已被替换而重新生产。
- 运行初始化不预生产 Context；会话按需启动。

<a id="production"></a>
## 8. 生产与普通读取

### 8.1 生产路径

    Receive：Stream 单步取得原始输入 → 安装为 parser 的本次输入（raw） → parser 解析并发布一次 → 下一步

parser 的包装发布一次；会话不再次发布返回值，也不再调用一次 parser。每一步是一次独立的受控调用（自己的 Origin 与捕获环境），会话以发布写入历史。lifelong 的会话保存进入 lifelong 时的交接，每一步从它的新副本开始：外层已经捕获的值（例如 alternative 选择时读到的配置）在生产端与消费端一致，生产步骤不会另行生产一份。interpreter 托管的会话没有交接。

生产会话的各步骤共用会话的 scope 使用登记，一步结束不撤销会话对资源的使用。无开启参数的连接 scope 因此跨步骤共享。会话停止时撤销登记；运行结束撤销全部待用关系，按 ScopeTree 清理不可达且声明了 close 的实例，没有 close 的实例只移出运行表，见[主设计：按可达性回收](LATEST_DESIGN.md#scope-gc)。来源正常结束（`end`）后，会话不再生产，但使用登记保留到会话被停止：lifelong 的会话在 lifelong 返回时停止，interpreter 托管的会话在运行结束时停止，见 [9.4 节](#end)。

lifelong 单元每次执行建立独立的 ExecutionFrame。参数来自外层或没有参数的 scope 由外层帧保留；参数来自本轮的实例归本轮，轮内后继共享不改变归属，本轮结束回收。DeliveryFrame 仍负责本轮会话视图的领取；ExecutionFrame 只记录已经领取的普通伴随资产的生产身份，不复制值。根实例的待用查询包含活动子帧：即使后台会话已经发布下一步，本轮后继仍按固定交付身份保留同一实例。轮帧结束后清空并从父帧摘除。这不保留尚未领取的历史资源，也不接通持续资产直接作为 scope 参数的观察协议。

Stream handler 的阻塞／等待决定节奏，SDK 不加间隔；立即返回的生产会形成高频生产，完整历史随之增长。本版不提供容量背压、丢弃或去重。

### 8.2 显式驱动与反馈

Stage 2 起持续资产只挂在 Stream 下，由会话生产，消费方不能 `requests` 它；原先在 lifelong 内以 `request @T` 把新发布送进会话的反馈写法随 RepeatRequest 一起取消，待 Stream 的驱动方式确定后再设计。

lifelong 外的普通驱动按原有 origin 发布，不因类型相同就广播给任何会话。

### 8.3 lifelong 外的有限读取

普通 `requires "T"` 只执行一次消费，不进入 lifelong，handler 取得最新一条。本次调用已有视图时读取它；否则由 interpreter 托管的会话（`protoSessions`）交付：会话在第一次需要时启动，读取至少等到一条发布，取得当时的历史并捕获为本次视图，再取其最新一条。会话保持到 interpreter 退出；后续调用取得当时的历史，同一调用已经捕获的视图保持不变。

来源已经结束时，读取取得最后的完整历史，再取其最新一条，不重新启动来源；来源一条都没有发布就结束时没有可读的值，报 `ContextNotInitialized`，不继续等待。

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

外部取消（Ctrl-C）时，SDK 取消 AST 中的全部任务并等待其受控收尾，再停止全部会话（撤销会话的使用登记），最后由 interpreter 按 ScopeTree 关闭剩余资源。关闭失败（`raise` 或 close 中的普通 IO 异常）单独汇总，不改变原业务结果，也不重试。Ctrl-C 等取消在其余收尾后重新抛出；取消发生在同步 close 中也停止后续启动，不能降为仅报告的关闭失败。

创建会话时，启动生产任务与写回会话登记在同一个不可中断区内完成，取消不会落在两者之间。停止会话时先关闭会话登记，并在同一临界区取出全部会话：此后尚未停止的生产步骤不能再启动新会话（例如 interpreter 托管的依赖会话），请求方得到异常并随停止结束，不会留下逃出停止集合的生产任务。生产任务的启动与登记、失败报告、撤销使用登记和完成信号都在不可中断区内完成，生产时解除屏蔽，停止等待任务退出。这保证 SDK 的登记与完成信号交接不会被取消打断；任务能否退出仍依赖业务 IO 响应取消、诊断与收尾能够返回。

### 9.3 close 延期的含义

不新增 Stream close、next-use 或历史资源按元素关闭协议。没有增量表示等待，不表示结束、故障或关闭；结束只由 Stream handler 的 `end` 报告（9.4）。

来源结束后的资源清理（会话用过的 scope 何时关闭、历史中的资源引用、后继待用关系的交接）、lifelong 的局部失败、会话生产资源与历史资源的存续，以及持续资产作为 scope 开启参数，仍纳入本轮[七阶段计划](NEXT_STAGES.md#stages)，尚未实现。require 缓存最新值、stream 缓存历史已随 Stage 2 实现；正常 end 已实现，本页记录当前协议。

完整历史保留不等于可以把多份资源 owner 合成一个，也不能复活已关闭的资源。通用的历史资源选择／关闭语义尚未设计。会话历史在运行期间持续增长，不承诺有界内存。持续资产作为 scope 开启参数尚未接通 History 的参数观察协议，可能报 `ScopeInputsMissing`；现有跨轮 scope 复用不代表支持该用法，跟踪见 [Next stages](NEXT_STAGES.md#current-limits)。

<a id="end"></a>
### 9.4 正常结束（end）

**代码长什么样。** Stream handler 的签名不变，仍是 `m String`。gen 只在 Stream handler 的 Layer 里加入 `Ends`，方法体多一个出口 `end`：

    -- demo/LinesDemo/Generated/Effects.hs（生成）
    type NextLineLayer m = (SDK.Reads (InputFile) m, SDK.Ends m, SDK.Raises NextLineError m, MonadIO m)
    class NextLineHandler m where
      nextLine :: m String

    -- demo/LinesDemo/Handlers.hs（手写）
    instance NextLineLayer m => NextLineHandler m where
      nextLine = do
        InputFile _ file <- require @InputFile
        finished <- liftIO (hIsEOF file)
        if finished then end else liftIO (hGetLine file)

    -- demo/LinesDemo/AST.hs
    ast = chained
      [ chained [node "Announce"]
      , lifelong [chained [node "PrintLine"]]
      , chained [node "Report"]
      ]

注册、parser、消费方的 handler 与 AST 的写法都不变；不调用 `end` 的 Stream 行为与此前相同。LinesDemo 读完四行后 `end`，`PrintLine` 处理完这四行，`Report` 执行，输入文件在运行结束时关闭。parser、Excu、Scoped 的 Layer 里没有 `Ends`，在它们的方法体里写 `end` 由 GHC 拒绝。

**三个出口。** Stream handler 的方法体有三个出口：返回一份原始输入、`raise` 失败、`end` 正常结束。结束由来源在取下一份输入的这一步自己报告，不另设“是否结束”的查询方法。`raw` 不在其中：它是下一层（parser）读取第一种出口的方式。

| 出口 | 之后发生什么 |
| --- | --- |
| 返回值 | 会话把它交给 parser，解析后发布一条交付 |
| `raise` | 经 Error 协议诊断，按 9.1 的规则处理 |
| `end` | 本步没有原始输入，parser 不执行，不发布；会话正常结束 |

`end` 不是失败：不进入 Error 诊断，不通知运行监督，也不被方法体内的 `catchError` 接住。已经完成的 IO 和此前的发布不回滚。它只结束当前绑定所在的会话；同一个 handler 注册给其他 Stream 时，各自的会话互不影响。

**会话。** 会话记录“已结束”并封住发布，这两件事在同一临界区内完成，然后唤醒等待者。会话的历史就是这个持续资产的值：结束之前它随发布增长，`end` 之后它是一个完整、不再变化的有限序列，仍然保留。正常结束、失败、取消三者保持区别。

**排空。** 结束后已经发布的交付仍可领取：

| 状态 | 领取结果 |
| --- | --- |
| 还有未领取的交付 | 返回下一条，以及到这一条为止的历史视图 |
| 暂无交付，来源仍在运行 | 等待 |
| 来源已结束，游标到达末尾 | “已耗尽”（内部结果，不是失败） |
| 来源失败或运行被取消 | 沿原有的故障／取消协议 |

排空指会话保留并允许交付全部积压；同一会话的多个单元各自排空、各自结束。它不承诺每个单元都消费完所有来源的积压：多来源单元可能因为另一个来源先耗尽而退出。游标前进只表示领取，不表示处理完成。

**单元结束。** 单元要领取某个资产的交付、而它已耗尽时，这个位置不 boot，也不伪造一次节点成功，单元正常结束：

- chained：尚未执行的后继不再执行，已完成的前缀不回滚。
- alternative：选择读取耗尽时不启动候选。
- 单元内部的 parallel：某一路耗尽时通知本单元，唤醒尚未 boot、仍在等其他来源的路径并让它们退出；已经 boot 的有限链执行完再汇合。这项通知只针对等待交付的位置，不强制结束不返回的业务 IO。
- 已经 boot 的调用在方法体第一次读取时才领取交付、而它已耗尽：这次调用放弃，单元同样正常结束。

这种结束只传到单元边界，不进入 Error 协议，也不通知监督。

**lifelong 返回。** 全部单元正常结束后，SDK 停止本边界的生产任务（仍在生产的会话已经没有消费者；已结束的会话只需等待任务退出）并等待其收尾，lifelong 才返回一次 Succ，不带结果，外层后继继续执行。有来源始终不结束时 lifelong 不返回，这是该 workflow 的正常含义。单元全部退出之前，不提前停止个别已经无人订阅的生产任务。

**lifelong 之后的读取。** 后继可以读取进入 lifelong 之前就可见的资产。读取 lifelong 内部发布的资产尚未实现，生成期拒绝（见 5.3）。读到哪一份（最后一次执行的产物，或各来源各自的最后一次发布）尚未确定。

**资源。** 本步不改变任何清理规则，结束后的清理另行设计：

- 来源结束后，会话的使用登记保留到会话被停止，排空期间不会因为来源结束而提前关闭资源。
- 只在生产会话中开启的 scope（例如 StreamDemo 的 `SensorLink`）仍在整次运行结束时关闭：它的开启位置是会话挂载，不随任何节点退休而被检查。
- 单元自己开启的 scope 在 lifelong 的节点退休时，由现有的可达性回收照常处理；这是节点结束的既有规则，不是为 end 新增的清理。
- 历史条目中资源引用的生命周期没有保证。

**失败与取消。** 不变：含 lifelong 的程序中的失败仍按 9.1 终止整次运行。

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
| 生产任务、DeliveryFrame、交付视图的交接 | [Runtime.hs](../sdk/Framework/Runtime.hs) |
| 视图读取、最新值投影（`latestContext`）、parser 输入、会话发布路由 | [App.hs](../sdk/Framework/Runtime/App.hs)、[Context.hs](../sdk/Framework/Runtime/Context.hs) |
| 单元调度、就绪检查、运行监督 | [Execution.hs](../sdk/Framework/Runtime/Execution.hs) |
| 根帧／轮帧与节点进度、scope 待用查询 | [Frame.hs](../sdk/Framework/Runtime/Frame.hs)、[Graph.hs](../sdk/Framework/Runtime/Graph.hs) |
| `end` 能力类与 Stream Layer、标签实例 | [Handler.hs](../sdk/Framework/Language/Handler.hs)、[Gen/Bind.hs](../sdk/Framework/Gen/Bind.hs)、[Gen/Emit/Handlers.hs](../sdk/Framework/Gen/Emit/Handlers.hs) |
| 会话的已结束状态、排空与耗尽、等待者唤醒 | [Session.hs](../sdk/Framework/Runtime/Session.hs) |
| 生产任务识别 `end`、单元结束通知 | [Runtime.hs](../sdk/Framework/Runtime.hs)、[App.hs](../sdk/Framework/Runtime/App.hs) |
| 单元正常结束、并行汇合、lifelong 返回 | [Execution.hs](../sdk/Framework/Runtime/Execution.hs) |
| lifelong 的正常出口与后继读取的拒绝 | [Gen/Build/Sources.hs](../sdk/Framework/Gen/Build/Sources.hs) |
| 生成的读取方法与路由、Stream 入口的会话包装、`Raw` 实例、会话步骤登记 | [Gen/Emit/Handlers.hs](../sdk/Framework/Gen/Emit/Handlers.hs)、[Gen/Emit/Program.hs](../sdk/Framework/Gen/Emit/Program.hs)、[Context.hs](../sdk/Framework/Runtime/Context.hs)（`streamHandle`） |

ScopeTree 独立构建并保持无环；订阅与回调关系不作为 scope 父边。运行时不累计完整方法调用历史或无限 workflow 结果。

<a id="deferred"></a>
## 11. 验证与延期

本仓库按约定只做普通编译、生成结果审阅和示例观察，不新增测试框架、负例或穷举门槛。已有验证范围概述见 [Next stages](NEXT_STAGES.md#baseline)，逐次观察记录保留在 Git 历史。LSP 仓库的外部穷举模型尚未扩展到 Stream／lifelong。

本版明确延期：来源结束后的资源清理与 Stream close、后继读取 lifelong 内部的发布、消费方提前退出（例如只取前若干条）、lifelong 的局部失败（当前由 9.1 的临时规则代替）、历史资源精细关闭与回收、嵌套 lifelong、多个持续来源组合触发一个 target、自动重试、时间周期声明、容量背压、任意外部 push callback 注册和跨 interpreter 存续。已有阻塞事件／队列读取、socket 接收及主动采样可作为单步来源（写法见 [4.1 节](#drives)）；不据此宣称自动适配所有外部回调 API。其中与结束和资源存续相关的项目转入[下一阶段](NEXT_STAGES.md#stages)。
