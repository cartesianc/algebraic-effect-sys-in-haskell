# Stream 与 lifelong：资产驱动的自动装配

本文通过引用构成[主设计第 7 章](LATEST_DESIGN.md#stream)的完整规范。主设计负责架构地图，本页唯一维护 Stream 的匹配、交付和调度规则；实施记录在 [Next stages](NEXT_STAGES.md)，写法示例在[使用指南第五节](GUIDE.md#stream)。SDK 没有流操作 API，各种流行为由组合推出；按行为列出的组合、运行时的分支依据，以及为方便理解给出的粗略类比，见[组合推导第 6 节](COMPOSITION.md#stream)。

更新：2026-11-17。状态：已实现（Stage 3 第 1–6 批；Stage 2 改为 Stream 加 parser、取消 RepeatRequest；Stage 6 第一步：Stream 的正常结束 `streamEnd`、排空、单元结束与 lifelong 返回，见[第 9.4 节](#end)；消费方结束 `endStream` 与读取方计数归零时停产，见[第 9.5 节](#consumer-end)；会话历史按读取义务保留，见[第 7.1 节](#retention)；由持续资产驱动的持续资产，见[第 4.2 节](#derive)）；当前实现限制见 [Next stages](NEXT_STAGES.md#current-limits)，延期项见[第 11 节](#deferred)。

本文手工记录 Stream、Context 与 lifelong 的匹配规则，作为代码生成、解释器和开发文档共同遵守的规范。消费原子输出的持续发布（`ReuseOutput`）已实现；本轮补齐普通后继绑定的待用判断与会话停止的完成交接，范围与验证见 [Stage 5 基础整理](NEXT_STAGES.md#stage-5-foundation)。标明“延期”或“临时”的部分不是最终设计。

## 1. 目标：让原子方法独立于装配知识

业务作者按已经生成的类型和原生 Haskell 编写一次取得、一次解析或一次消费。SDK 根据注册、handler 的读取结构、资产和 AST 控制关系，自动生成生产、解析、交付和 target boot 的连接：

    声明与可提取的读取结构
    → 检查匹配前提
    → 生成唯一装配及其依据
    → interpreter 执行已经装配的闭包

业务作者需要知道本地输入输出、`require`、`raw`、`raise`，Stream handler 报告来源结束的 `streamEnd`，以及消费方不再消费时的 `endStream`，不需要知道 BootPlan、会话、游标或调度循环。

自动装配只依赖明确契约，不从任意 IO 恢复作者意图。匹配不成立时生成期诊断，不按方法名相似度、运行速度或最后写入猜选。原子化约束保证组合可观察，不证明任意方法体足够细、无副作用或必然返回。

AST branch 继续规定何时、按何种顺序、选择哪些入口以及是否重复 boot。业务组合写在注册与 AST 中，AST 不成为业务值 pipeline。程序入口保持 `interpreter ast effects`。

## 2. 术语与职责

| 结构 | 职责 |
| --- | --- |
| Stream effect | 第六种 typing；绑定的 handler 每次取得一份原始输入（`String`），只由生产会话驱动；来源没有下一份输入时以 `streamEnd` 结束（[9.4](#end)） |
| parser | Context 绑定的 handler：用 `raw` 读取 Stream 本次取得的输入或原子句柄本次交出的输出，返回表示类型的值 |
| Context.stream | `True` 声明持续资产，缓存发布历史；当且仅当它的 Input 链被持续驱动（挂在 Stream 下，或链上有 `streams` demand），且须同时 `require = True` |
| Context.require | `True` 缓存最新值；读取已有绑定或交付视图，不生产；普通资产缺值按[Context 的等待与结束规则](LATEST_DESIGN.md#context)处理，持续交付沿用本专题协议 |
| 持续资产 | `stream = True` 的资产：`streams` 读取 `History`，`requires` 读取最新一条，可以被 `streams` 订阅 |
| `streams "T"` | 声明以资产 T 的新交付驱动，同时取得读取权限；不是调用 parser 的语法。声明它的 effect 在 lifelong 挂载的消费链上，或在另一份持续资产的生产链上 |
| lifelong | 为其单元订阅会话，在交付就绪时 boot original target |
| BootPlan | 生成器从生产方注册及本 lifelong 的挂载推导的生产连接：Receive、Derive 或 ReuseOutput，不是手写标签 |
| 会话 | 一个边界内某持续资产的发布、结束与读取关系；可拥有独立生产任务，也可接收已有 AST 执行的输出 |
| publication | 一次成功发布；保留值、出身和共享归属引用 |
| 消费单元 | lifelong 下独立推进的有限控制程序 |
| 游标 | 单元在某会话中已经领取的条数 |
| frame | 单元一次执行的交付视图与普通来源解析范围 |

Stream 不进入 original chain，也不作为 AST target；它的持续运行由生产会话托管。original target 代表一条完整消费链的末端，其中有限执行的 Excu／Scoped 可以消费上游资产，同时把本次输出交给挂接的 Context 发布新资产。Stream 不向 AST 返回 Succ，它的结束由等待交付的单元和 lifelong 观察；这不限制消费节点本身的产值。

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

持续资产的声明由 Context 自己的注册决定。`stream` 必须与它的 Input 链一致：直接 input 是 Stream，或 Input 链上某个 effect 声明了 `streams`，都要求 `stream = True`。具体生产连接再结合本 lifelong 的 AST 挂载确定：来源单步、独立派生，或沿用消费节点的原子输出，见 [第 4 节](#bootplan)。

| Context 的 Input 链 | stream | require | 结果 |
| --- | --- | --- | --- |
| 直接 input 是 Stream | `True` | `True` | 持续资产，Receive：Stream 单步＋parser |
| 直接 input 是 Stream | `False` | 任意 | 报错：挂在 Stream 下的 Context 须声明 `stream = True` |
| 链上有 `streams "U"`（恰好一份资产） | `True` | `True` | 持续资产：已有合法 AST 发布位置时 ReuseOutput，否则 Derive |
| 链上有 `streams "U"` | `False` | 任意 | 报错：被持续资产驱动的链每次交付产出一个值，须声明 `stream = True` |
| 链上的 `streams` 指向多份资产 | 任意 | 任意 | 报错：一条生产链只由一份资产驱动 |
| 直接 input 是 Stream，它的 Input 链上又有 `streams` | 任意 | 任意 | 报错：Stream 自己驱动，它的 Input 链不能再订阅 |
| 没有 Stream，也没有 `streams` | `True` | 任意 | 报错：没有持续驱动，不能声明 `stream = True` |
| 没有 Stream，也没有 `streams` | `False` | 任意 | 普通单值资产 |
| 以上任一持续资产 | `True` | `False` | 报错：`stream = True` 需要 `require = True` |

另外：Context 必须声明 parser；Stream 必须声明 handler；以 Stream 为 input 的必须恰好是一个 Context（它的 parser），其他 effect 不能直接取得原始输入。持续资产经会话发布和交付，消费方不能声明 `requests "T"`。Stream 下的 parser 不把 Stream 当作前驱执行；挂在原子句柄下的 parser 用 `raw` 取得句柄输出，注入时由同次输出回答，不再执行句柄。

### 3.3 消费权限与读取类型

消费方写 `streams "T"`，handler 用 `require @(History 表示类型)` 读取交付。streams 同时授予这项读取权限，不必再写 `requires "T"`。

- 只有持续资产的基础资产可以被订阅；订阅分支契约时报错，应订阅其基础资产。
- 只有 Excu、Scoped 可以声明 streams。
- 声明 streams 的 effect 被那份持续资产驱动，可以在 lifelong 挂载的 original chain 上，也可以在一个 `stream = True` 的 Context 的 Input 链上；同一个原子操作可以同时承担消费和生产关系。前一种已有 AST 执行时，挂接 parser 沿用本次输出；没有这种挂载时由独立派生会话执行。被驱动链的 Context 必须声明 `stream = True`；普通资产的生产链需要持续资产时用 `requires` 读最新一条。
- `requires "T"` 读取持续资产时，handler 用 `require @表示类型` 取得最新一条，不由交付驱动。

读取类型按访问方式确定：streams 返回 `History 表示类型`，requires 返回最新一条；普通资产保持单值读取。`stream` 缓存历史，`require` 缓存最新值；两者是同一资产的不同结果形态，不是两个来源。若需要两个独立来源或独立持续能力，再细化为两个资产。分支契约投影本次交付的最新条目。读取历史另设方法（gen 已生成 `streamT`）的写法待定。

History 是从会话首条发布到确定交付位置的有限、不可变序列，由 SDK 构造：`latest`、`historyEntries`、`historySize` 读取。相等值的两个 publication 仍是两条。无限的是 SDK 持续推进的过程，不是业务手写的无限列表。History 包装共享发布序列，不逐条重建业务值；`latest` 取末项，`historySize` 取长度。领取一条交付还涉及序列前缀切分和伴随发布索引，因此不把整个领取过程承诺为常数时间；`historyEntries`、完整显示、比较或遍历可能访问全部条目。

### 3.4 原子输入与源码约束

Stream handler 一次返回一个原始输入，parser 一次解析一个。parser 的 `raw` 由会话本次取得的输入回答，不再执行 Stream handler 另取一份；Stream handler 由会话驱动，其他 handler 不能取得原始输入。Stream 有自己的数据结构：handler 仍是每次一份 `String`，不改成原子句柄的 list 输出，下面也不挂 Pure（[主设计：Pure](LATEST_DESIGN.md#pure)）。Stream 自己的 Input（例如传感器连接的 Scoped）作为前驱在 handler 之前执行，跨生产步骤保持（见 8.1）。业务只写原生 instance、读取、ADT、局部计算和 raise，不手写 yield、递归连接、publish、subscribe、acknowledge 或回调参数；顶层白名单继续适用（[ASSETS](ASSETS.md)）。

Excu／Scoped 交出的 `[String]` 是原子句柄的输出，不能把空 list 释为 EOF。来源的结束只由 Stream handler 用 `streamEnd` 报告，见 [9.4 节](#end)。

<a id="bootplan"></a>
## 4. 生产方式（BootPlan）

| BootPlan | 静态依据 | 生产步骤 |
| --- | --- | --- |
| Receive | Context 的直接 input 是 Stream，`stream = True` 且 `require = True` | Stream 单步取得原始输入 → parser 解析并发布 |
| Derive | Context 的 Input 链上有 `streams "U"`，本 lifelong 没有可复用的 AST 发布位置 | 领取一条 U 的交付 → parser 沿 Input 链执行被驱动的句柄，解析并发布 |
| ReuseOutput | 同一 lifelong 已有可静态确定的 AST 位置执行 Context 所挂接的原子句柄 | 沿用该次原始输出 → parser 解析并发布；不另开生产任务（见 [4.2 节](#derive)） |

Stage 2 取消了 RepeatRequest：持续交付只由持续的驱动产生，即上游 Stream，或（2026-11-15 起）另一份持续资产的交付；没有持续驱动的 Context 不能声明持续资产。原先用 RepeatRequest 表达的采样（StreamDemo 的心跳）改为 Stream 加 parser。

**统一驱动规则：首次需求建立运行，后续增量驱动执行。** 进入 lifelong 时建立会话、读取方和输出连接；独立来源可以在读取方登记完成之前生产，这期间发布完整保留，登记后再按读取义务裁剪。AST 单元在登记完成后才启动，因此 ReuseOutput 不会漏掉连接建立前的输出。B 发布后，订阅 B 的独立 Derive 生产链或 lifelong target 才能执行下一步；缺少增量时等待，不因等待而补跑 B。A 消费 B 后再产出资产，也是同一规则。运行时不在生产者调用栈中直接同步执行下游业务。

ReuseOutput 只绑定本 lifelong 内经过来源和启动检查的具体 AST 位置，不扫描全局资产表、任选先到的发布或合并同名 handler 的调用。gen 拆分 original chain 与 Context chain 时保留这次输出的连接；订阅下游不会因此重跑原操作。取消、读取方撤销与未来的背压仍可向上游传播，它们不构成一次新的业务生产驱动。

不成立的组合在生成期按 3.2 的匹配表报错，不在运行中猜测或退化为轮询。

**启动依赖**：lifelong 会话的生产链（Stream 单步、parser 及其读取可达的方法）不能读取其他持续资产，驱动它的那一份除外；ReuseOutput 的 parser 及其 requests 路径也遵守这条限制。gen 同时检查发布位置与领取顺序：不能先等待某资产、再执行唯一会发布它的位置。无法证明来源确定或启动可推进时生成失败，不退化为重复生产。interpreter 托管的 Receive 会话仍沿用 8.3 的规则。

<a id="drives"></a>
### 4.1 socket、event、behavior 的写法

这三个词描述外部数据怎样到来，帮助业务作者写 Stream handler；SDK 目前不识别它们，也不据此改变生产方式。三种驱动方式在 SDK 中如何区分仍待确定（见 [Stage 2：本阶段不处理](NEXT_STAGES.md#stage-2-later)），当前都写成 Stream 加 parser：

| 驱动关系 | 数据怎样到来 | 写法 |
| --- | --- | --- |
| socket | 外部持续送来原始数据，逐条接收：连接、消息队列、传感器读数 | Stream handler 阻塞接收一份原始输入（`m String`），parser 解析；连接等资源放在 Stream 的 Input 上游 scope 中，跨生产步骤保持（见 8.1） |
| behavior | 值一直存在，随时可以采样：时钟、心跳、状态轮询 | Stream handler 先等待采样间隔，再取当前值 |
| event | 离散地发生，每次发生得到一条 | Stream handler 阻塞读取下一个事件 |

- 节奏只由 Stream handler 的阻塞或等待决定，SDK 不加间隔；立即返回的 handler 会形成高频生产。
- 本 lifelong 内原子输出的持续发布由 ReuseOutput 接入；它复用具体 AST 执行的输出，不识别任意外部事件。lifelong 外的普通驱动不因资产名相同就广播给会话，也不恢复 RepeatRequest 的反馈写法。
- 外部 push callback 不能直接注册给 SDK，需要先转换成可阻塞读取的队列，再作为单步来源；通用回调适配本版延期（见第 11 节）。
- StreamDemo 中，`TemperatureFeed`＋`TemperatureParser` 是 socket 写法，`HeartbeatClock`＋`Heartbeat` 是 behavior 写法。

<a id="derive"></a>
### 4.2 消费节点的输出与独立派生

**代码长什么样。** LinesDemo 中，`TextCounter` 由 `TextLine` 驱动，下面挂着声明了 `stream = True` 的 Context，把本次统计输出解析为持续资产 `RunningTotal`：

    -- demo/LinesDemo/Effects.hs（节选）
    EffectSpec
      { name = "TextCounter"
      , typing = Excu { handler = Just "countText" }
      , input = "Root"
      , demands = [streams "TextLine"]
      }
    EffectSpec
      { name = "CountParser"
      , typing = Context { asset = Asset @Total "RunningTotal", parser = Just "parseTotal", require = True, stream = True }
      , input = "TextCounter"
      , demands = []
      }
    EffectSpec
      { name = "ShowTotal"
      , typing = Excu { handler = Just "showTotal" }
      , input = "Root"
      , demands = [streams "RunningTotal"]
      }
    EffectSpec
      { name = "Report"
      , typing = Excu { handler = Just "report" }
      , input = "Root"
      , demands = [requires "RunningTotal"]
      }

    -- demo/LinesDemo/Handlers.hs（节选）
    instance CountTextLayer m => CountTextHandler m where
      countText = do
        received <- require @(History Line)
        let sizes = [length text | Line text <- historyEntries received]
        pure [show (length sizes), show (sum sizes)]

    instance ParseTotalLayer m => ParseTotalHandler m where
      parseTotal = do
        fields <- raw
        case fields of
          [count, size] -> pure (Total (read count) (read size))
          _ -> raise (ParseTotalError "the counter gives a line count and a character count")

    -- demo/LinesDemo/AST.hs
    ast = chained
      [ chained [node "Announce"]
      , lifelong
          [ parallel
              [ chained [node "PrintLine", node "TextCounter"]
              , chained [node "ShowTotal"]
              ]
          ]
      , chained [node "Report"]
      ]

`countText` 与 `parseTotal` 是普通的 Excu handler 与 parser，没有新的 effect 类别、关键字或 handler 能力。AST 的一个单元打印并执行 `TextCounter`；gen 把 `RunningTotal` 装配为 ReuseOutput，会话接收这次原子输出经 `CountParser` 解析后的资产。另一个单元的 `ShowTotal` 领取该发布，不另行执行统计，显示与原行文本可以交错。原子方法仍然不知道它的输出将由谁消费。

**为什么产出声明为持续资产。** 链上有 `streams` demand，执行机会来自那份资产的交付，连续成功执行会产生一串增量。`stream = True` 把这个结构关系写在源码里；写成 `False` 或通过 `requests` 再驱动它由生成期拒绝。发布只发生于实际执行且成功解析的位置，alternative 未选中的位置不凭空产生交付。

**规则。**

- **已有 AST 执行**：gen 在同一个 lifelong 内沿 target 自身及 original Input 链确定 Context 所挂原子句柄的发布位置，写入 `ReuseOutput [NodeId]`；不把任意 requests 生产链中的同名操作算成全局复用者。会话没有独立 worker 或虚构的生产挂载；原子入口成功后调用挂接 parser，`raw` 由本次输出回答。parser 的生产记录继承原节点的 Origin、执行帧和 ScopeUser，资产保持这次生产的身份。不同独立调用不因 handler 名或值相同而合并。
- **独立派生**：没有上述 AST 发布位置时使用 Derive。会话每领取一条上游交付执行一次 parser 及其 Input 链，成功后发布一条；无新增量时等待，不能用 `requests` 补产。可以继续逐级派生。
- **来源与驱动**：一条派生链只由一份持续资产驱动，不再读取其他持续资产。ReuseOutput 默认只接受一个发布位置；多个位置须处于同一个重复单元，且两两是 alternative 的互斥候选。gen 另把 target 订阅、chained 前置和持续资产的 alternative 选择读取纳入启动依赖检查，保守拒绝存在启动环的候选组合，不依赖 IO 时序证明进展。Input／demand 的环也照常拒绝。
- **同单元的路径覆盖**：单元直接订阅或经独立 Derive 间接依赖自己产出的资产时，每条到达订阅的 workflow 路径必须此前已经过发布位置，或同轮有并行启动且必经的发布路径。alternative 只有每个候选都能供值才算必经，不能用其他候选可能发布来证明当前路径。跨单元的条件发布不要求每轮产出；读取方可以等待后续增量，或在发布单元结束并排空后退出。
- **scope 输出的边界**：Scoped.open 复用活实例时可以跳过方法体，没有新的原子输出。因此同单元直接订阅或经 Derive 等待这类 ReuseOutput 当前由 gen 保守拒绝；没有把“经过 open 位置”当成本轮必有新发布。跨单元仍可等待实际发布或来源结束，独立 Derive 不受这项拒绝影响；精确识别必定 fresh 的开启后放行留待后续。
- **结束**：Derive 在上游结束并排空、或被驱动链上的 Excu 调用 `endStream` 时，先封住自己的发布，再离开并按需退役上游。ReuseOutput 的发布位置按节点计，节点 `endStream` 时立即撤下，所在单元结束时撤下其余位置，全部撤下后封住发布并通知排空；单次 target 成功或单轮结束都不撤下。同单元读取等本轮发布及派生处理稳定后，仍无新交付才跳过；不会等本单元下一轮来补值。见 [9.5 节](#consumer-end)。
- **失败**：持续挂接 parser 失败进入现有 Stream 失败与监督协议，不能沿用普通 Context 注入失败只留在注入内的规则。已完成操作与之前的发布不回滚，失败不重跑原操作。普通 Context 的注入规则保持不变。
- **读取与保留**：两种派生资产均经会话交付，`streams` 读历史、`requires` 读最新一条，且没有 interpreter 托管的派生会话；读取位置在提供该会话的 lifelong 之内或之后。独立 Derive 登记上游历史读取方，ReuseOutput 沿用原消费单元的上游读取，不额外登记一份。历史仍按 7.1 的读取义务保留。
- **普通副产物的可见性**：ReuseOutput 只交付该持续资产，不把原 AST 调用中的普通 publication 自动附带到其他单元。普通资产留在真实 Origin，合法 chained 后继按原来源表读取；持续交付不扩大 parallel 兄弟之间的普通资产可见性。独立 Receive／Derive 已有的伴随发布协议保持不变。
- **仅供后继或暂时无人读取**：AST 挂接的持续副产物也进入本边界的会话集合，不要求一定有 `streams` 订阅者。没有历史读取义务时只保留最新一条，供合法后继 `requires` 读取；会话存储本身不驱动原子操作，也不产生额外生产任务。
- **不提供**：手写跳过出口、多份持续资产合并驱动一条链、缓冲策略与窗口。消费方结束与读取方计数归零时停产见 [9.5 节](#consumer-end)。

<a id="static"></a>
## 5. 静态结构与合法性

### 5.1 消费摘要

每个挂载的 target 的订阅只看 original chain 自身：末端 effect 及其 Input 祖先声明的 streams demand。不能汇总 `chainReaches`，它包含被驱动的 Context 与生产链内部的传递可达方法；生产链内部的依赖另用于启动依赖检查。

### 5.2 lifelong 合法性

1. lifelong 内每个挂载的 target 恰好订阅一个持续资产。
2. 这些 target 的 original chain 不再读取（requires／streams）其他持续资产；否则执行结果取决于读取时刻。分支契约按其基础契约计入：读取所订阅资产的分支是同一资产，读取其他持续资产的分支同样被拒绝。多个来源的触发组合另行设计。
3. 只有普通 requests／requires 的末端不能进入 lifelong；一次性准备放在外部 chained。streams 末端不能出现在 lifelong 之外。
4. Stream、Context 不作为 target，Stream 也不能进入 original chain；带 streams 的 Excu／Scoped 可以挂载到 AST 并向挂接 Context 提供同次输出。gen 按本 lifelong 的具体位置确定 ReuseOutput，不能证明来源唯一或启动可推进时拒绝。
5. lifelong 不嵌套；lifelong 内不能有空分支。因为每个 target 都订阅，单元每条成功路径都至少领取一条新交付。
6. 合法 Haskell 不自动等于结构可提取；未知高阶 effect、隐藏的 effect 循环等继续使用现有诊断。
7. 会话生产步骤顺带发布的普通资产（例如 parser 链上 `requests` 驱动的辅助资产 X）随每条交付保存为伴随发布（见 7）。lifelong 内以生产步骤为来源读取这类资产的位置，必须由该会话的资产驱动：订阅它的 target，或以它为转折资产的选择读取；否则生成期拒绝，因为读到哪一步的产物将取决于调度。需要各单元共享同一个值时，在 lifelong 之前生产它。
8. 同一单元订阅自己经 ReuseOutput 发布的资产（包括经 Derive 间接依赖）时，必须逐条 workflow 路径证明先有发布机会，或同轮有并行且必经的发布路径。parser 及其 requests 路径不得额外等待其他持续资产。规则拒绝可确定的启动互等，不证明任意原子 IO 都会返回。

这些检查不证明任意原子 IO 能够返回，也不证明即时采样会限速。

### 5.3 原型中的表示

lifelong 写入统一 Prototype，运行装配、来源分析与 `--structure` 读取同一份数据：

    LifelongAt NodeId LifelongProto [WorkflowTree]

    LifelongProto
      { lifelongUnits         :: [NodeId]            -- 单元：直接子项；直接子项是 parallel 时为它的子项
      , lifelongSubscriptions :: [(NodeId, String)]  -- 每个挂载 target 订阅的资产
      , lifelongSessions      :: [SessionProto] }    -- 订阅资产、上游资产及 AST 持续副产物各一份会话

    SessionProto { sessionAsset :: String, sessionPlan :: BootPlan, sessionMounts :: [NodeId] }
    BootPlan = Receive String | Derive String | ReuseOutput [NodeId]
    -- Receive：Stream 注册名；Derive：驱动资产；ReuseOutput：本 lifelong 的原子输出发布位置

- 会话挂载 NodeId 为 lifelong 路径加 `[-1, 会话序号, 步骤]`：步骤 0 是 Stream 单步、步骤 1 是 parser；Derive 只有步骤 0（parser）。挂载以 `SessionChain` 角色进入 `protoChains`，参与构图与 ScopeTree。ReuseOutput 的 `sessionMounts = []`，沿用所记录 AST 位置的 `NodeChain`，不为复用输出虚构一个独立执行。
- `protoSessions` 为每个 Receive 资产登记一份 interpreter 托管的会话，挂载为 `[-2, 序号, 步骤]`；它不属于 AST，不是任何读取点的可见前驱。Derive 与 ReuseOutput 资产没有托管会话。
- ReuseOutput 的位置来自同一 lifelong 的 original Input 链。即使没有订阅者、只供后继 `requires`，AST 挂接的持续副产物也纳入会话集合。`Gen.Sessions` 在生成期检查供值位置的唯一性以及订阅、顺序前驱、选择读取组成的启动图；运行时直接执行已确定的计划。
- 可见性：lifelong 的会话挂载先于它的全部单元。来源分析中，会话挂载按各消费单元的后续读取需求分别作为根分析，以进入 lifelong 时的交接（例如外层 alternative 选择时捕获的值）为已捕获绑定；运行时每个生产步骤也从这份交接开始（见 8.1）。单元的执行以订阅资产的交付作为已捕获绑定，出身是会话的生产步骤；单元读取生产步骤的其他普通发布时，读到的是所处理交付那一步的发布（伴随发布，见 7）。会话挂载的各个成功出口不合并：一条交付的伴随发布对应一次成功的生产步骤（Stream 单步与 parser 各一个成功出口），单元按每种交付状态分别分析。Stage 2 取消 lifelong 内的显式 request 后，不再出现“没有伴随发布”的交付状态。某条交付的伴随发布中没有辅助资产 X 时，单元中读取 X 的位置不补产，等待它的发布；需要这个值时按第 5.2 节第 7 条，由该会话的资产驱动读取位置，或在 lifelong 之前生产它。lifelong 有一个正常出口：进入 lifelong 之前可见的发布，以及单元内可能发布后继所读契约的位置，都交给后继。后继按每个来源最新一次发布读取（见 9.4）；同一单元内互斥位置发布同一契约时作为并存候选，运行时按轮次取最新，其余多来源情形仍按来源唯一规则报错。
- 分析裁剪：以 `lifelongUnits` 确定单元，不穿透单元内的 chained、alternative 或 parallel。每个生产挂载保留本单元可能读取的契约及生产链自身的读取依赖，成功出口再按单元相关契约投影、去重，然后逐步组合 Receive 的步骤和各会话状态。仍分析全部会话，避免遗漏其他会话造成的来源冲突；不把成功出口取并集。生产链的 read／drive 事实独立累计。
- 读取点来源新增 `FromSession`：持续资产经会话交付，不查询普通来源表。Receive 可由 interpreter 托管的会话回答；Derive 与 ReuseOutput 的读取点必须在有这份会话的 lifelong 之内或之后。ReuseOutput 的生产位置用于输出路由和启动证明，不能被解释为读取时补跑该位置的许可。
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
| 持续订阅／lifelong | 全部单元正常结束后返回一次 Succ，不带结果；仍有消费单元未结束时不正常返回，另因失败或取消退出 |

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
| `chained [monitor, after]` | after 等待 monitor 结束：monitor 的全部单元正常结束后 after 执行；仍有消费单元未结束时 after 不执行 |
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
| 独立生产步骤执行 | Receive／Derive 的会话挂载 NodeId＋每步新的 Origin；ReuseOutput 沿用原 AST 执行 |
| 生产资源的使用登记 | 独立生产任务按会话跨步骤保持；ReuseOutput 沿用原节点的使用登记（见 8.1） |
| scope 归属 | 既有 Binding ownership 与具体 scope 实例 |

运行时保存值与保留可操作的资源是两种关系，当前各处的职责如下：

| 持有位置 | 保存什么 | 何时撤销 |
| --- | --- | --- |
| 调用的 ScopeUser | 本次受控调用实际使用的实例与待认领绑定 | 业务、诊断及受控结果消费结束后 |
| 独立生产会话的 ScopeUser | Receive／Derive 跨步骤使用的实例 | worker 的收尾完成时：会话退役（读取方计数归零或 lifelong 返回）或运行结束；`streamEnd` 本身不撤销 |
| ExecutionFrame 与静态开启计划 | 节点待用、参数生产身份及允许的后继关系 | 节点退休、来源不再匹配或帧结束；合法外部后继的待用关系单独保留 |
| 会话历史、伴随发布、后继保留表 | 原 Binding 与已有 ownership 引用 | 按读取义务裁剪、替换或退出运行；仅保存引用不自动增加 scope 使用登记 |

ReuseOutput 沿用原调用的 ScopeUser，没有独立生产任务。此处不把任意 ADT 内嵌资源自动纳入 ownership，也不为历史条目增加尚未确定的保活语义。

- 同一边界同一资产共享会话，不同单元各自推进；不同 lifelong 的会话与进度独立。
- 进入 lifelong 时建立会话、读取方与输出连接；独立来源在登记期间已经产生的发布完整保留。单元在登记完成后启动，ReuseOutput 只接收实际 AST 执行的输出，不启动另一份任务。单元的游标从会话的第一条发布开始；每次领取推进一条，视图是会话历史到这一条为止的前缀。
- 每条 publication 保留原始 Binding、生产 ActivationId、执行帧、Execution 与共享 ownership；history 不是一个新的 owner。后台追加不改写已经取得的视图；读取不推进游标。
- 持续资产的发布进入会话历史，不写入按 Origin 的普通资产表；普通辅助资产仍按 Origin 保存。独立 Receive／Derive 的生产步骤保留原有伴随发布；ReuseOutput 的交付只含持续资产，不附带原 AST 调用中的普通产物。后者继续按真实 Origin 和静态来源表读取，不因订阅持续资产而扩大普通跨链可见性。
- 独立生产任务的每条交付另带该生产步骤已经发布的普通资产（伴随发布）。DeliveryFrame 领取交付后，伴随发布作为已捕获绑定交给本次执行中的调用，交接中已经捕获的值优先；运行时不再按会话挂载的当前 Origin 读取这些发布。因此处理第 n 条交付时读到第 n 步的辅助资产，不会读到之后步骤的产物，也不会因旧发布已被替换而重新生产。ReuseOutput 不建立这种普通资产交接。
- 运行初始化不预生产 Context；会话按需启动。

<a id="retention"></a>
### 7.1 会话保留多少发布

历史只通过持续资产读取：`streams` 取得 `History`，`requires` 只取最新一条。`streams` 只出现在 lifelong 挂载的 target 的 original chain 上，或同一个 lifelong 里 Derive 会话的生产链上（见 [3.3 节](#contracts)），所以历史的存续不超过这个 lifelong 里读取它的单元与会话。会话据此只保留仍有读取义务的发布，任何一次读取的结果都不因此改变：

| 会话的读取方 | 会话保留 |
| --- | --- |
| 还有按历史读取的读取方在运行：`streams` 订阅的单元，或由它驱动的 Derive 会话 | 全部发布 |
| 只剩读最新一条的单元（例如以它为转折资产的选择读取） | 这些单元尚未领取的积压，加上最新一条 |
| 没有单元读取：订阅它的单元都已结束、lifelong 已返回，或 lifelong 之外用 `requires` 读取的来源 | 最新一条 |

- **读取方登记**：进入 lifelong 时，每个会话按 Prototype 登记它的读取方：单元内有 `streams` 订阅的按历史读取，只有其他静态读取点或选择读取的只读最新一条，没有读取点的单元不登记，也不能从这个会话领取。由这份资产驱动的 Derive 会话同样登记为按历史读取的读取方，游标交给它的生产任务。ReuseOutput 没有独立上游游标，原消费单元已经承担该读取。登记完成之前的发布全部保留。
- **离开**：单元结束（所需来源结束并排空、全部节点 `endStream`、失败或取消），或单元里读取这个会话的节点都已 `endStream` 时，单元离开该会话，为它保留的历史与积压随即放掉。这是“读取方不再读取”的唯一入口。Derive 会话在生产任务退出时（上游结束并排空、被驱动链 `endStream`、失败或被停止）离开上游。
- **计数归零停产**：正常路径上的离开使已登记的读取方从有到无时，会话退役：停止生产任务、封住发布、回收只在会话中开启的 scope，见 [9.5 节](#consumer-end)。失败与取消路径只离开，停止交给 lifelong 返回或运行结束。会话的最新一条仍留给 lifelong 的后继读取。
- **伴随发布**只随交付领取：全部读取方都领取过的那一条，其伴随发布不再保留，与条目是否保留无关。
- **积压不合并**：每条发布仍然交付一次，保留规则不丢弃尚未领取的交付。
- **不设上限**：被 `streams` 订阅的来源在订阅单元运行期间保留全部历史，内存随发布增长；窗口、容量与背压属于另外的语义，未设计。
- 已经取得的视图是不可变快照，放掉会话中的条目不影响它。

<a id="retention-cost"></a>
### 7.2 保留与离开的时间复杂度

记号：R 是一个会话登记的读取方个数（读取它的单元加上由它驱动的 Derive 会话），由 Prototype 决定，与数据量无关；N 是会话当前保留的条目数；E 是一条流的发布总数。会话状态用 `Data.Sequence` 保存，读取方是一份游标表。以下按 2026-11-16 的 `Framework.Runtime.Session` 计算：

| 操作 | 代价 | 来源 |
| --- | --- | --- |
| 发布一条（`appendDelivery`） | O(R + log N) | 每次状态变化执行一次 `release`：读 R 个游标求最早位置，截取序列为 O(log N) |
| 领取一条（`takeDelivery`） | O(log N) + O(R + log N) | 视图是共享结构的前缀；游标前进后再执行一次 `release` |
| 一条发布被全部读取方领取 | O(R² + R·log N) | R 次领取各扫描一次 R 个游标 |
| 离开（`leaveSession`）、登记（`admitReaders`） | O(R) | 过滤或建立游标表，再执行一次 `release` |
| 取得 `History` 视图、`latest`、`historySize` | 不随 N 增长 | `History` 的 `fmap` 只叠加投影，不遍历条目 |
| `historyEntries` 与按 Foldable 遍历 | O(N) | 由读取方显式遍历 |

- **数据维度没有二次项**：R 固定时，每条发布在会话中的代价是 O(log N)，一条流合计 O(E log E)。R² 是程序结构上的二次，不随流增长；若某个资产的读取方很多，可以把游标位置维护成有序计数，降到每次领取 O(log R)，目前不需要。
- **轮次开销不随流增长**：lifelong 每轮开始时移出上一轮的 Origin 与发布，普通资产表、保留表和轮帧的大小受程序挂载数限制；本轮生产参数的 scope 实例在本轮结束且没有合法后继待用时回收。
- **业务遍历历史是读取方自己的代价**：每轮调用 `historyEntries` 的 handler 在第 k 条交付上花 O(k)，整条流 O(E²)，例如 LinesDemo 的 `CountText` 每行重算全部行。框架不改写这类算法；增量累计需要读取自身上一次输出，属于另外的设计。
- **内存**：仍有按历史读取的读取方时保留全部 N = E 条（[不设上限](#retention)）；否则只保留积压与最新一条。
- **协调锁**：普通资产的发布与读取在 scope／frame 协调锁内进行，并行单元在这几步上串行，这是常数级争用，不改变上表的复杂度。

<a id="production"></a>
## 8. 生产与普通读取

### 8.1 生产路径

    Receive：Stream 单步取得原始输入 → 安装为 parser 的本次输入（raw） → parser 解析并发布一次 → 下一步
    Derive：领取一条上游交付 → 到这一条为止的上游历史作为本步视图 → parser 沿 Input 链执行被驱动的句柄，解析并发布一次 → 下一步
    ReuseOutput：原 AST 位置执行原子句柄 → 挂接 parser 读取本次 raw 并发布一次 → 原 workflow 按已有控制流继续

parser 的包装发布一次；会话不再次发布返回值，也不再调用一次 parser。Receive／Derive 的每一步是一次独立的受控调用（自己的 Origin 与捕获环境），从进入 lifelong 时保存的交接新副本开始：外层已经捕获的值（例如 alternative 选择时读到的配置）在生产端与消费端一致。interpreter 托管的会话没有交接。ReuseOutput 的 parser 是原节点内的挂接调用，保留该节点的 Origin、执行帧与 ScopeUser；记录自己的 Context activation，但不另开一个根执行、不重放原子操作。

Receive／Derive 的生产步骤共用会话的 scope 使用登记，一步结束不撤销会话对资源的使用。无开启参数的连接 scope 因此跨步骤共享。会话停止时撤销登记；运行结束撤销全部待用关系，按 ScopeTree 清理不可达且声明了 close 的实例，没有 close 的实例只移出运行表，见[主设计：按可达性回收](LATEST_DESIGN.md#scope-gc)。来源正常结束后，独立会话不再生产，但使用登记保留到会话被停止：lifelong 的会话在 lifelong 返回时停止，interpreter 托管的会话在运行结束时停止，见 [9.4 节](#end)。ReuseOutput 没有额外的会话 ScopeUser，按原消费节点和执行帧的既有规则回收；这不增加历史资源保活或新的 close 策略。

lifelong 单元每次执行建立独立的 ExecutionFrame。参数来自外层或没有参数的 scope 由外层帧保留；参数来自本轮的实例归本轮，后继共享不改变归属，本轮结束且没有合法后继待用时回收。DeliveryFrame 仍负责本轮会话视图的领取；ExecutionFrame 记录已领取普通伴随资产的生产身份及所属 lifelong 边界，不复制值。根实例的待用查询包含活动子帧：即使后台会话已经发布下一步，本轮后继仍按固定交付身份保留同一实例。轮帧结束后清空进度并从父帧摘除；已经允许的 lifelong 外后继仍按静态来源和实际保留绑定判断待用，具体规则见[图与来源](EFFECT_GRAPH.md#scope-opening-retention)。这不保留尚未领取的历史资源，也不接通持续资产直接作为 scope 参数的观察协议。

Stream handler 的阻塞／等待决定节奏，SDK 不加间隔；立即返回的生产会形成高频生产，被 `streams` 订阅的来源的历史随之增长（保留规则见 [7.1 节](#retention)）。本版不提供容量背压、丢弃或去重。

### 8.2 显式驱动与反馈

持续资产的执行机会来自 Stream 来源或上游持续交付，发布统一进入会话；消费方不能 `requests` 它。ReuseOutput 接通的是已经由 lifelong 驱动的原子输出，不恢复原先以 `request @T` 把新发布送进会话的 RepeatRequest 反馈写法。

lifelong 外的普通驱动按原有 origin 发布，不因类型相同就广播给任何会话。

### 8.3 lifelong 外的有限读取

普通 `requires "T"` 只执行一次消费，不进入 lifelong，handler 取得最新一条。本次调用已有视图时读取它；否则由 interpreter 托管的会话（`protoSessions`）交付：会话在第一次需要时启动，读取至少等到一条发布，把当时的最新一条捕获为本次视图。会话保持到 interpreter 退出，并一直生产；它没有按历史读取的读取方，只保留最新一条（见 [7.1 节](#retention)）。后续调用取得当时的最新一条，同一调用已经捕获的视图保持不变。

来源已经结束时，读取取得最后一条，不重新启动来源；来源一条都没有发布就结束时没有可读的值，报 `ContextNotInitialized`，不继续等待。

Derive／ReuseOutput 资产没有托管会话，读取位置须在有它的 lifelong 之内或之后（见 [4.2 节](#derive)）。后继读取已结束会话的最后一条，不重新执行发布位置。

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

`stopSession` 统一使用“无 worker／运行中／停止中”的内部状态。首次停止登记停止中并取得任务，锁外发出取消并等待；并发或重复停止取得同一完成信号，也必须等待 worker 的 `finally` 撤销 ScopeUser 后返回，不能把“已经请求停止”当成“收尾完成”。停止状态只保存完成信号；首次停止方在锁外持有任务句柄直到完成，后续调用不重复取消。停止与等待不持有会话状态锁或 worker 目录锁；`endSession` 的封口、`leaveSession` 的读取方撤销仍是各自独立的事件；读取方计数归零时由离开方在锁外调用会话的退役动作（停止、封口、回收），见 [9.5 节](#consumer-end)。

### 9.3 close 延期的含义

不新增 Stream close、next-use 或历史资源按元素关闭协议。没有增量表示等待，不表示结束、故障或关闭；直接来源由 Stream handler 的 `streamEnd` 报告结束，Derive 由上游耗尽或被驱动链的 `endStream` 结束，ReuseOutput 在发布位置全部撤下后封口（9.4、9.5）。

会话停止的完成交接与已允许普通资产后继读取的待用判断已在 [Stage 5 基础整理](NEXT_STAGES.md#stage-5-foundation)补齐；会话退役（[9.5 节](#consumer-end)）新增了一个回收触发点：只在会话挂载中开启的 scope 在会话停止并且读取方计数归零后按可达性回收。历史中的资源引用、lifelong 的局部失败、会话生产资源与历史资源的存续，以及持续资产作为 scope 开启参数，仍纳入本轮[七阶段计划](NEXT_STAGES.md#stages)，尚未实现。require 缓存最新值、stream 缓存历史已随 Stage 2 实现；`streamEnd`、`endStream` 与计数停产已实现，本页记录当前协议。

完整历史保留不等于可以把多份资源 owner 合成一个，也不能复活已关闭的资源。通用的历史资源选择／关闭语义尚未设计。被 `streams` 订阅的会话在订阅单元运行期间保留全部历史，不承诺有界内存；其余情况只保留最新一条与未领取的积压，见 [7.1 节](#retention)。持续资产作为 scope 开启参数尚未接通 History 的参数观察协议，可能报 `ScopeInputsMissing`；现有跨轮 scope 复用不代表支持该用法，跟踪见 [Next stages](NEXT_STAGES.md#current-limits)。

<a id="end"></a>
### 9.4 来源正常结束（streamEnd）

**代码长什么样。** Stream handler 的签名不变，仍是 `m String`。gen 只在 Stream handler 的 Layer 里加入 `StreamEnds`，方法体多一个出口 `streamEnd`（2026-11-16 前名为 `Ends`／`end`）：

    -- demo/LinesDemo/Generated/Effects.hs（生成）
    type NextLineLayer m = (SDK.Reads (InputFile) m, SDK.StreamEnds m, SDK.Raises NextLineError m, MonadIO m)
    class NextLineHandler m where
      nextLine :: m String

    -- demo/LinesDemo/Handlers.hs（手写）
    instance NextLineLayer m => NextLineHandler m where
      nextLine = do
        InputFile _ file <- require @InputFile
        finished <- liftIO (hIsEOF file)
        if finished then streamEnd else liftIO (hGetLine file)

    -- demo/LinesDemo/AST.hs
    ast = chained
      [ chained [node "Announce"]
      , lifelong
          [ parallel
              [ chained [node "PrintLine", node "TextCounter"]
              , chained [node "ShowTotal"]
              ]
          ]
      , chained [node "Report"]
      ]

`streamEnd` 不改变注册、parser 与消费方 handler 的写法；不调用 `streamEnd` 的 Stream 行为与此前相同。LinesDemo 读完四行后 `streamEnd`，打印与统计单元排空后退出并封住 `RunningTotal`；显示单元领完统计增量后退出，lifelong 返回，`Report` 读取最终统计（输出复用见 [4.2 节](#derive)）。`TextLine` 的读取方全部离开时会话退役，输入文件随之关闭，早于 `Report`。parser、Excu、Scoped 的 Layer 里没有 `StreamEnds`，在它们的方法体里写 `streamEnd` 由 GHC 拒绝。

**三个出口。** Stream handler 的方法体有三个出口：返回一份原始输入、`raise` 失败、`streamEnd` 正常结束。结束由来源在取下一份输入的这一步自己报告，不另设“是否结束”的查询方法。`raw` 不在其中：它是下一层（parser）读取第一种出口的方式。

| 出口 | 之后发生什么 |
| --- | --- |
| 返回值 | 会话把它交给 parser，解析后发布一条交付 |
| `raise` | 经 Error 协议诊断，按 9.1 的规则处理 |
| `streamEnd` | 本步没有原始输入，parser 不执行，不发布；会话正常结束 |

`streamEnd` 不是失败：不进入 Error 诊断，不通知运行监督，也不被方法体内的 `catchError` 接住。已经完成的 IO 和此前的发布不回滚。它直接作用于资产，不看 AST 上有哪些消费方：只结束当前绑定所在的会话，各消费方排空后各自结束；同一个 handler 注册给其他 Stream 时，各自的会话互不影响。

**会话。** 会话记录“已结束”并封住发布，这两件事在同一临界区内完成，然后唤醒等待者。会话的历史就是这个持续资产的值：结束之前它随发布增长，`streamEnd` 之后它是一个完整、不再变化的有限序列，在订阅它的单元结束之前仍然保留（之后只留最新一条，见 [7.1 节](#retention)）。正常结束、失败、取消三者保持区别。

**排空。** 结束后已经发布的交付仍可领取：

| 状态 | 领取结果 |
| --- | --- |
| 还有未领取的交付 | 返回下一条，以及到这一条为止的历史视图 |
| 暂无交付，来源仍在运行 | 等待 |
| 来源已结束，游标到达末尾 | “已耗尽”（内部结果，不是失败） |
| 来源失败或运行被取消 | 沿原有的故障／取消协议 |

排空指会话保留并允许交付全部积压；同一会话的多个单元各自排空、各自结束。它不承诺每个单元都消费完所有来源的积压：多来源单元可能因为另一个来源先耗尽而退出。Derive 会话是上游的一个读取方：上游结束后它照常排空，然后自己正常结束，订阅它的单元由此继续排空。游标前进只表示领取，不表示处理完成。

**单元结束。** 单元要领取某个资产的交付、而它已耗尽时，这个位置不 boot，也不伪造一次节点成功，单元正常结束：

- chained：尚未执行的后继不再执行，已完成的前缀不回滚。
- alternative：选择读取耗尽时不启动候选。
- 单元内部的 parallel：某一路耗尽时通知本单元，唤醒尚未 boot、仍在等其他来源的路径并让它们退出；已经 boot 的有限链执行完再汇合。这项通知只针对等待交付的位置，不强制结束不返回的业务 IO。
- 已经 boot 的调用在方法体第一次读取时才领取交付、而它已耗尽：这次调用放弃，单元同样正常结束。

来源结束与单元结束是两件事，不能互相替代：

| 情况 | 行为 |
| --- | --- |
| 来源结束，消费者仍在运行 | 继续交付已发布的积压，排空后才得到“已耗尽” |
| 单元结束 | 不再启动新的位置，即使它等的来源随后又发布了数据 |

单元结束与启动一个位置之间只有一个判定点（启动许可）：交付到手之后、boot 之前检查一次单元是否已在结束。等待者无论被结束通知还是被新数据唤醒，都要经过它。通过判定的视作已启动，之后的结束通知不撤回它，单元等它完成；结束通知在先则不启动，已经领取的那条交付不再处理（游标只表示领取）。已经启动的调用继续使用它已有的交付视图；它在方法体内才第一次读取另一个来源时，有现成交付就取得并继续，需要等待则放弃。

这种结束只传到单元边界，不进入 Error 协议，也不通知监督。单元正常退出后，SDK 撤销它作为 ReuseOutput 发布者的登记；某会话的全部发布单元都已退出时，立即封住该会话的发布并唤醒领取方。单次节点返回、单轮完成不撤销发布登记，未选择的 alternative 发布位置也不会使会话过早结束。这样下游单元可以排空后退出，不必等待整个 lifelong 先返回。

**lifelong 返回。** 全部单元正常结束后，SDK 停止本边界的生产任务（仍在生产的会话已经没有消费者；已结束的会话只需等待任务退出）并等待其收尾，lifelong 才返回一次 Succ，不带结果，外层后继继续执行。仍有消费单元等待交付或执行时，lifelong 不正常返回；多来源单元可因其中一个所需来源耗尽而结束，无须等待所有来源自行 `streamEnd`。单元全部退出之前，读取方计数已经归零的会话已经退役（[9.5 节](#consumer-end)）；lifelong 返回时逆序退役其余会话并等待任务退出。

**lifelong 之后的读取。** `require` 读的是来源当前最新的值，像 State monad 的 state：每次生产覆盖为最新，读取取当前值（同一次调用内第一次读取后固定）。lifelong 结束不新增隔离边界，后继按这个语义读取：

- 单元的普通产物：每个位置保留它最新一次发布。新一轮开始时，上一轮的发布从轮内可见范围移出、按位置保留，所以单元内仍逐轮隔离；后继读到的是该位置最新的值，最后一轮没有执行到它时取更早的轮次。
- 同一单元内互斥的位置（不同 alternative 候选）发布同一资产：各轮是串行的，按轮次取最新的一份，不是在并发写入之间挑最后一个。
- 持续资产：读已结束的那个 lifelong 会话的最新一条（会话此时只保留这一条），不另行启动来源。先后排列的多个 lifelong 都有这个会话时读最近结束的那个。
- 零轮或从未发布：缺值按耗尽协议报 `ContextNotInitialized`，不等待。
- 生成期拒绝：两个并行单元都发布同一资产，同一单元内同一轮可能有两个位置都发布，lifelong 内外的来源并存，或两个互不先后的 lifelong 都有同一个持续资产。这些情形里“最新”要么取决于调度，要么违反来源唯一。

带资源归属的资产不经普通来源表，后继本来就读不到 lifelong 里的资源；把后继要用的实例接到它的待用关系上属于结束后的清理，另行设计。

**资源。**

- 来源结束后，会话的使用登记保留到会话退役，排空期间不会因为来源结束而提前关闭资源。
- 只在生产会话中开启的 scope（例如 StreamDemo 的 `SensorLink`、LinesDemo 的输入文件）在会话退役时按可达性回收：生产已经停止、读取方计数归零（或 lifelong 返回）；后继还会以同样参数开启的实例保留。见 [9.5 节](#consumer-end)。
- 单元自己开启的 scope 在 lifelong 的节点退休时，由现有的可达性回收照常处理；这是节点结束的既有规则。
- 历史条目中资源引用的生命周期没有保证。

**失败与取消。** 不变：含 lifelong 的程序中的失败仍按 9.1 终止整次运行。

<a id="consumer-end"></a>
### 9.5 消费方结束（endStream）与按读取方计数停产

一份持续资产只有一个生产方，消费方可以有多个。生产方结束直接作用于资产（9.4）；消费方结束只撤销自己的读取，生产是否停止由读取方的引用计数决定，与 Stream GC 用的是同一份读取方登记（[7.1 节](#retention)）。

**代码长什么样。** 注册、AST 与 handler 签名都不变。gen 给以 `streams` 订阅持续资产的 Excu 加入 `EndsStream`，方法体多一个出口 `endStream`：

    -- demo/LinesDemo/Generated/Effects.hs（生成）
    type PrintLineLayer m = (SDK.Reads (SDK.History (Line)) m, SDK.EndsStream m, SDK.Raises PrintLineError m, MonadIO m)

    -- 手写（示意，示例本身不调用）：只处理前若干行
    instance PrintLineLayer m => PrintLineHandler m where
      printLine = do
        received <- require @(History Line)
        if historySize received > 10 then endStream else pure ()
        ...

**谁拿到 `endStream`。** 自己以 `streams` 订阅持续资产的 Excu（`Gen/Bind.consumesStream`，2026-11-17 修订）。它是被这份资产驱动的消费方，`endStream` 结束的是它自己的订阅。`streams` 只出现在被驱动的位置：lifelong 节点的订阅（[5.2 节](#static)），或独立 Derive／ReuseOutput 被驱动的 Input 链。所以运行时按当前调用的位置就能确定订阅，业务不用说明结束哪一份资产。

- 同一条链上的其他 effect（Input 前驱）和 lifelong 里不订阅的普通节点不给：它们是原子操作，lifelong 只是插入它们的控制流。handler 的签名不随所处的控制流改变，可以在持续链与有限链之间复用。
- 只给 Excu：Scoped.open 被打断会使实例失效，Pure 是值变换，Stream 用 `streamEnd`。
- handler 绑定到多个 effect 时，各绑定的 Layer 仍须一致，否则按既有规则报签名不一致。没有 `EndsStream` 却调用 `endStream` 由 GHC 类检拒绝。

**调用之后。** `endStream` 不是失败：不进入 Error 诊断，不通知监督，不被 `catchError` 接住。本次调用放弃，不交出结果；已经完成的 IO 和此前的发布不回滚。

| 位置 | 立即效果 |
| --- | --- |
| lifelong 节点（含 ReuseOutput 的发布节点） | 本节点的订阅结束；同一轮中 chained 的后继、parallel 的其他路径照常执行 |
| Derive 会话的被驱动链 | 这一步不发布；派生会话先封住发布，再离开并按需退役上游；订阅它的单元仍可排空后结束 |

**三层计数。** 读取方逐层离开，上一层归零才影响下一层：

1. **节点**：订阅结束的节点在之后各轮跳过，不领取交付；候选节点全部结束的 alternative 不再做选择读取。
2. **单元**：两轮之间，单元离开不再有活读取位置的会话（活读取位置指尚未结束的订阅、其链上的读取点和仍有活候选的选择读取）；之后的 frame 不再领取它。本单元不读取、只经它发布的会话不离开。单元的节点全部结束订阅时，单元正常结束。
3. **会话**：已登记的读取方（单元与由它驱动的 Derive 会话）从有到无时，会话退役。

ReuseOutput 的发布位置同样按节点计：节点结束订阅时立即撤下它，不等下一轮；所在单元结束时撤下其余位置。全部撤下才封口，下游由此排空后结束。parallel 的分支互不影响：一个单元离开会话，只让计数减一。

**同单元的发布与读取（2026-11-17 修订）。** stream 是驱动关系。gen 允许此前已经发布，也允许同轮有必经的并行发布路径；同单元本身不证明发布已完成。读取先等本轮仍可能完成的发布，确定本轮不会再增加交付后才跳过：

- **本地范围**：直接 ReuseOutput 的全部发布位置须属于当前单元；沿 Prototype 的单一 Derive 上游递归追溯，只有根是本单元 ReuseOutput 的派生会话才同样属于本地。Receive 和其他单元的发布保持外部来源的等待规则。
- **本轮稳定**：实际轮 `ExecutionFrame` 中全部发布位置为 `Completed` 或 `Skipped`，才表示本轮不会再从这些位置发布。`Pending`、`Running` 与未知位置都继续等待；alternative 未选路径由既有的跳过记录体现。派生会话还须逐级完成上游已发布的全部步骤：只在一次解析与发布成功返回后推进 `stateProcessed`，与上游累计发布数 `stateBase + 历史长度` 比较，领取游标不证明处理完成。
- **交付优先**：已有交付立即领取；没有交付时，等待同一共享通知上的会话变化或节点退休。判定本轮稳定后再读会话状态，优先交付刚完成的发布或传播真实终态，仍无交付才返回 `Undriven`。这不会把尚在运行的并行生产或异步派生当成本轮没有输出。
- 订阅节点与转折资产的选择读取，收到 `Undriven` 时只跳过本轮；会话封口且排空时，这些位置的订阅结束（alternative 的候选都记为结束），不因此结束单元。多个互斥发布位置尚未全部结束时，后续轮次仍可由其他候选产生新交付。
- 只 `require` 本地资产的位置，在本轮稳定而无新交付、或会话封口排空时读已有的那一条；一条都没有发布过时按缺值报 `ContextNotInitialized`。

本轮稳定只免去等待本单元下一轮的发布，不停止外部来源，也不预测任意原子 IO 是否会返回。

**退役。** 同时只有一个调用执行退役，其他调用等待。只有全部步骤成功完成才记为 `Retired`；取消或异常使状态恢复为 `Unretired` 并唤醒等待方，后续调用可继续完成未完成的退役：

    停止生产任务（取消并等待它撤销会话的使用登记）
    → 封住发布（已发布的交付仍可领取，后继仍读最新一条）
    → 按可达性回收只在会话挂载中开启的 scope
    → 派生会话的上游若也没有读取方，随之退役

生产任务可能停在业务 IO 里（等待下一份输入），所以停止用取消，与 lifelong 返回时的停止相同；退役在会话状态锁外进行。恢复未完成的退役不重试业务 close，scope 仍按既有状态执行一次关闭。interpreter 托管的会话不登记读取方，不按计数退役；ReuseOutput 没有独立任务，计数归零不封口，仍按发布位置封口。lifelong 返回时逆序退役其余会话。失败与取消路径只离开、不退役，停止交给既有收尾；Derive 的生产任务失败时同样只离开上游，先报告监督。Derive 正常结束先封住自己的发布，再离开和退役上游；异常收尾覆盖处理及离开的全过程，取消不会遗留上游读取登记。

**`require` 与订阅无关。** 读取方计数只统计领取交付的位置。`chained [A, D]` 中 A `endStream` 后，D 照常执行：D 有自己的订阅，自己驱动。D 若 `requests` A 链上的资产，由自己驱动生产；若只 `require` A 这一轮的普通产物，A 被跳过后按缺值规则报 `ContextNotInitialized`，确定失败，不挂起，也不读旧值。

**代价。** 节点结束后的读取关系重新计算每轮最多一次；发布位置在节点结束时立即撤下。会话的计数判断与离开同在一次 `release` 内，为 O(R)（R 为该会话的读取方个数）。本轮稳定检查沿已生成的单上游关系查询发布节点进度和派生完成水位，只在唤醒后重查，不轮询；新增完成计数不随历史长度分配存储。

**不变与未做。** 读取方的历史读取方式在登记时确定，按历史读取的节点结束后，剩下只读最新一条的读取方仍让会话保留全部历史，直到单元离开。历史条目中的资源引用、背压与容量、局部失败仍未设计。

<a id="implementation"></a>
## 10. 实现位置

| 内容 | 源码 |
| --- | --- |
| Stream typing、Context 声明 | [Registration.hs](../sdk/Framework/Language/Registration.hs) |
| `streams` 与权限检查 | [Gen/Demand.hs](../sdk/Framework/Gen/Demand.hs) |
| 声明匹配、lifelong 合法性、单元／订阅／会话与启动依赖 | [Gen/Lower.hs](../sdk/Framework/Gen/Lower.hs)、[Gen/Sessions.hs](../sdk/Framework/Gen/Sessions.hs) |
| `protoSessions`、启动环检查、来源分析 | [Gen/Build.hs](../sdk/Framework/Gen/Build.hs)、[Gen/Build/Sources.hs](../sdk/Framework/Gen/Build/Sources.hs)、[Prototype/Query.hs](../sdk/Framework/Prototype/Query.hs)（`finiteSessions`、`bootPlan`） |
| History 视图 | [History.hs](../sdk/Framework/Language/History.hs) |
| 会话状态、历史、游标、读取方登记与保留范围 | [Session.hs](../sdk/Framework/Runtime/Session.hs) |
| Derive 的推导、会话集合、生产步骤与上游游标的交接 | [Prototype/Query.hs](../sdk/Framework/Prototype/Query.hs)（`drivingAssets`、`bootPlan`、`sessionAssets`）、[Gen/Lower.hs](../sdk/Framework/Gen/Lower.hs)、[Runtime.hs](../sdk/Framework/Runtime.hs)（`DeriveSteps`）、[Session.hs](../sdk/Framework/Runtime/Session.hs)（`feedSession`）、[Execution.hs](../sdk/Framework/Runtime/Execution.hs) |
| ReuseOutput 的发布位置、挂接与单元结束封口 | [Gen/Sessions.hs](../sdk/Framework/Gen/Sessions.hs)、[Gen/Build/Sources.hs](../sdk/Framework/Gen/Build/Sources.hs)、[Gen/Emit/Handlers.hs](../sdk/Framework/Gen/Emit/Handlers.hs)、[Context.hs](../sdk/Framework/Runtime/Context.hs)、[App.hs](../sdk/Framework/Runtime/App.hs)、[Execution.hs](../sdk/Framework/Runtime/Execution.hs) |
| 会话登记、Origin 清除 | [Graph.hs](../sdk/Framework/Runtime/Graph.hs) |
| 生产任务、DeliveryFrame、交付视图的交接 | [Runtime.hs](../sdk/Framework/Runtime.hs) |
| 视图读取、最新值投影（`latestContext`）、parser 输入、会话发布路由 | [App.hs](../sdk/Framework/Runtime/App.hs)、[Context.hs](../sdk/Framework/Runtime/Context.hs) |
| 单元调度、就绪检查、运行监督 | [Execution.hs](../sdk/Framework/Runtime/Execution.hs) |
| 根帧／轮帧与节点进度、scope 待用查询 | [Frame.hs](../sdk/Framework/Runtime/Frame.hs)、[Graph.hs](../sdk/Framework/Runtime/Graph.hs) |
| `StreamEnds`／`EndsStream` 能力类、Layer 规则（`consumesStream`）与标签实例 | [Handler.hs](../sdk/Framework/Language/Handler.hs)、[Gen/Bind.hs](../sdk/Framework/Gen/Bind.hs)、[Gen/Emit/Handlers.hs](../sdk/Framework/Gen/Emit/Handlers.hs) |
| 会话的已结束状态、排空与耗尽、共享唤醒、派生完成水位、读取方计数与退役完成协议 | [Session.hs](../sdk/Framework/Runtime/Session.hs) |
| 生产任务识别 `streamEnd`、Derive 识别 `endStream`、会话退役动作、单元结束通知 | [Runtime.hs](../sdk/Framework/Runtime.hs)、[App.hs](../sdk/Framework/Runtime/App.hs) |
| 单元正常结束、节点订阅结束、单元离开会话、发布位置撤下、并行汇合、lifelong 返回 | [Execution.hs](../sdk/Framework/Runtime/Execution.hs) |
| lifelong 的正常出口与后继读取的拒绝 | [Gen/Build/Sources.hs](../sdk/Framework/Gen/Build/Sources.hs) |
| 生成的读取方法与路由、Stream 入口的会话包装、`Raw` 实例、会话步骤登记 | [Gen/Emit/Handlers.hs](../sdk/Framework/Gen/Emit/Handlers.hs)、[Gen/Emit/Program.hs](../sdk/Framework/Gen/Emit/Program.hs)、[Context.hs](../sdk/Framework/Runtime/Context.hs)（`streamHandle`） |

ScopeTree 独立构建并保持无环；订阅与回调关系不作为 scope 父边。运行时不累计完整方法调用历史或无限 workflow 结果。

<a id="deferred"></a>
## 11. 验证与延期

本仓库按约定只做普通编译、生成结果审阅和示例观察，不新增测试框架、负例或穷举门槛。已有验证范围概述见 [Next stages](NEXT_STAGES.md#baseline)，逐次观察记录保留在 Git 历史。LSP 仓库的外部穷举模型尚未扩展到 Stream／lifelong。

本版明确延期：Stream close 与历史资源的清理、历史的窗口与容量上限、派生持续资产的跳过、“被驱动但只读最新一条”的声明、lifelong 之外的派生会话、lifelong 的局部失败（当前由 9.1 的临时规则代替）、历史资源精细关闭与回收、嵌套 lifelong、多个持续来源组合触发一个 target、自动重试、时间周期声明、容量背压、任意外部 push callback 注册和跨 interpreter 存续。已有阻塞事件／队列读取、socket 接收及主动采样可作为单步来源（写法见 [4.1 节](#drives)）；不据此宣称自动适配所有外部回调 API。其中与结束和资源存续相关的项目转入[下一阶段](NEXT_STAGES.md#stages)。
