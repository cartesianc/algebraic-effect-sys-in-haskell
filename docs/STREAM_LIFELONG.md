# Stream 与 lifelong：资产驱动的自动装配

本文通过引用构成[主设计第 7 章](CORE_DESIGN.md#stream)的完整规范。主设计负责架构地图，本页唯一维护 Stream 的匹配、交付和调度规则；实施记录在 [Next stages](NEXT_STAGES.md)，写法示例在[使用指南第五节](GUIDE.md#stream)。SDK 没有流操作 API，各种流行为由组合推出；按行为列出的组合、运行时的分支依据，以及为方便理解给出的粗略类比，见[组合推导第 6 节](COMPOSITION.md#stream)。

更新：2026-11-17。本文描述当前协议：生产侧结束见[第 9.4 节](#end)，消费侧结束与会话退役见[第 9.5 节](#consumer-end)，交付保留见[第 7.1 节](#retention)。阶段状态和剩余缺口统一见 [Next stages](NEXT_STAGES.md#stages)。

本文手工记录 Stream、Context 与 lifelong 的匹配规则，作为代码生成、解释器和开发文档共同遵守的规范。输出复用、后继待用及会话停止均按下文现行规则解释；标明“延期”或“临时”的部分不扩展为最终保证。

## 1. 目标：让原子方法独立于装配知识

业务作者按已经生成的类型和原生 Haskell 编写一次取得、一次解析或一次消费。SDK 根据注册、handler 的读取结构、资产和 AST 控制关系，自动生成生产、解析、交付和 target boot 的连接：

    声明与可提取的读取结构
    → 检查匹配前提
    → 生成唯一装配及其依据
    → interpreter 执行已经装配的闭包

业务作者需要知道本地输入输出、`require`、`rawinput`、`raise`，Stream handler 报告来源结束的 `streamEnd`，以及消费方不再消费时的 `endStream`，不需要知道 BootPlan、会话、游标或调度循环。

自动装配只依赖明确契约，不从任意 IO 恢复作者意图。匹配不成立时生成期诊断，不按方法名相似度、运行速度或最后写入猜选。原子化约束保证组合可观察，不证明任意方法体足够细、无副作用或必然返回。

AST branch 继续规定何时、按何种顺序、选择哪些入口以及是否重复 boot。业务组合写在注册与 AST 中，AST 不成为业务值 pipeline。程序入口保持 `interpreter ast effects`。

## 2. 术语与职责

| 结构 | 职责 |
| --- | --- |
| Stream effect | 第六种 typing；绑定的 handler 通过 `rawemit :: String -> m ()` 逐条提供原始输入，只由生产会话驱动；来源没有下一份输入时以 `streamEnd` 结束（[9.4](#end)） |
| parser | Context 绑定的 handler：用 `rawinput` 读取 Stream 本次取得的输入或原子句柄本次交出的输出，返回表示类型的值 |
| Context.stream | `True` 声明持续资产；当且仅当它的 Input 链被持续驱动（挂在 Stream 下，或链上有 `streams` demand），且须同时 `require = True` |
| Context.require | `True` 缓存最新值；读取已有绑定或交付视图，不生产；普通资产缺值按[Context 的等待与结束规则](CORE_DESIGN.md#context)处理，持续交付沿用本专题协议 |
| 持续资产 | `stream = True` 的资产；每次发布保持声明的表示类型，读取是否带来重复执行由组合关系决定 |
| `streams "T"` | 声明以资产 T 的新交付驱动，同时取得读取权限；不是调用 parser 的语法。声明它的 effect 在 lifelong 挂载的消费链上，或在另一份持续资产的生产链上 |
| lifelong | 为其单元订阅会话，在交付就绪时 boot original target |
| BootPlan | 生成器从生产方注册及本 lifelong 的挂载推导的生产连接：Receive、Derive 或 ReuseOutput，不是手写标签 |
| 会话 | 一个边界内某持续资产的发布、结束与读取关系；可拥有独立生产任务，也可接收已有 AST 执行的输出 |
| publication | 一次成功发布；保留值、出身和共享归属引用 |
| 消费单元 | lifelong 下独立推进的有限控制程序 |
| 游标 | 单元在某会话中已经领取的条数 |
| frame | 单元一次执行的交付视图与普通来源解析范围 |

Stream 不进入 original chain，也不作为 AST target；它的持续运行由生产会话托管。original target 代表一条完整消费链的末端，其中有限执行的 Excu／Scoped 可以消费上游资产，同时把本次输出交给挂接的 Context 发布新资产。Stream 不向 AST 返回 Succ，它的结束由等待交付的单元和 lifelong 观察；这不限制消费节点本身的产值。

socket、event、behavior 描述业务来源的取值方式。三种来源的现行写法见[第 4.1 节](#drives)。挂在 Stream 下的 Context 与挂在原子句柄下的 Context 写法相同：parser 用 `rawinput` 取得本次输入。

<a id="contracts"></a>
## 3. 资产、方法与 beforegen

### 3.1 资产身份独立于方法身份

业务表示类型先在 Types.hs 定义，Context 把它细化为一个资产（refinement asset，意义见[主设计 4.3](CORE_DESIGN.md#refinement)），并绑定 parser。挂在 Stream `TemperatureFeed` 下的 Context 写作：

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
| `streamT` | `require @T` 经类型路由读取固定交付的当前元素 |
| `historyT` | `stream @T` 经类型路由读取同一交付的 `Flow` 视图 |

Stream handler 每调用一次 `rawemit text`，SDK 就把 `[text]` 同步交给挂接的 parser。parser 的 `rawinput` 读这一份输入。一次 handler 调用可以多次交付，正常返回后生产循环才进入下一步。首次生成契约后即可编写两个 handler。

同一 refined asset 的所有访问方式共享固定表示 ADT 和唯一 Context 来源；读取的返回形态不同，不会产生第二种资产身份。声明与读取依据统一见[主设计：资产来源与访问约束](CORE_DESIGN.md#demand-contract)，包括 streams 在 Prototype 中的交付依据。

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

另外：Context 必须声明 parser；Stream 必须声明 handler；以 Stream 为 input 的必须恰好是一个 Context（它的 parser），其他 effect 不能直接取得原始输入。持续资产经会话发布和交付，消费方不能声明 `requests "T"`。Stream 下的 parser 不把 Stream 当作前驱执行；挂在原子句柄下的 parser 用 `rawinput` 取得句柄输出，注入时由同次输出回答，不再执行句柄。

### 3.3 消费权限与读取类型

资产表示类型由 Types.hs 与 Context 的声明确定。消费方在 demands 中写资产名，handler 按表示类型写 `require @T` 读取本次增量；以 `streams` 读取持续资产的 handler 还可以写 `stream @T` 读取 x:xs（见下文[按 x:xs 读取](#flow)）：

| 注册 | `require @T` | `stream @T` | 驱动关系 |
| --- | --- | --- | --- |
| `streams "Asset"` | 本次交付的 T | `x :> xs`：本次交付及同一会话中更早的交付 | 在 lifelong 原始消费链或持续 Context 生产链上，由该资产的交付推进 |
| `requires "Asset"` | 本次已捕获的 T；尚未捕获时取得许可来源的当前值 | 不提供 | 只读取，不因此重复启动当前链 |

同一资产可声明两种访问方式；它们给出同一个表示类型和读取路由，不产生重复 Reads 实例。普通资产保持原来的读取协议；持续资产不能声明 `requests`。只有 Excu、Scoped 可以声明 streams。

**生产持续性与消费重复性分别计算。** A 的 Input 链订阅 B 时，A 可以继续随 B 的新交付生产；普通链 C 只 `requires` A，就只取得一次确定的值。A 不需要额外挂入 AST 的 lifelong，C 也不因读取 A 而变成 lifelong。C 若要随 A 的新交付反复执行，仍按既有规则在 lifelong 中声明 streams。普通 Context 生产链同样可只 require 持续资产并发布一次普通产物。

`T` 遵循[资产表示类型的固定形式](ASSETS.md#fixed-form)。一次调用捕获一个 Binding，后台随后发布的新值只对后续捕获可见。

<a id="flow"></a>
**按 x:xs 读取。** `stream = True` 的 `Asset @Line "TextLine"` 逐条发布 `Line`。注册和 `demands` 仍然使用资产名，以 `streams "TextLine"` 订阅的 handler 同时具有 `SDK.Reads Line m` 与 `SDK.Streams Line m`。后一项提供历史视图：

```haskell
-- Framework.Language.Handler，经 Framework.SDK 导出
data Flow a = a :> Flow a | Done
  deriving (Eq, Show, Functor, Foldable, Traversable)
infixr 5 :>

class Streams value m where
  stream :: m (Flow value)

-- demo/LinesDemo/Handlers.hs（节选）
countText = do
  seen <- stream @Line                      -- 本次交付 :> 更早的交付
  rawoutput [show (length seen), show (sum [length text | Line text <- toList seen])]
```

- **`x` 是本次，`xs` 是过去。** `x` 与同一调用中 `require @T` 取得的元素相同。`xs` 从新到旧列出这个会话在 `x` 之前已发布的元素，以 `Done` 收尾。`Done` 表示已读到这段历史的起点。生产会话由 `streamEnd` 结束；从未发布过的会话结束时，消费者不会收到一次内容为 `Done` 的交付。
  例如依次发布 `a`、`b`、`c`，处理 `b` 的调用读到 `b :> a :> Done`。即使 `c` 已经发布，该调用再次读取的仍是同一前缀。
- **会话边界与 end GC。** 历史从会话开头算起，与读取方何时登记无关。来源停止（`streamEnd`、失败或退役）且读取方全部离开后，会话不再有交付可领取，历史随之放掉；会话仍留在登记表中，lifelong 之后的有限读取读到的是最新一条。要在流结束后保存数据，属于 [结束后保存完整记录的延期设计](NEXT_STAGES.md#urgent-history)，暂不设计。
- **保留条件由 gen 计算。** `streams "T"` 决定 handler 可用的能力。gen 从方法体中的 `stream @T` 找到实际读取历史的资产，并在对应 Context 的原型上标记 `effectHistory = True`。只用 `require @T` 读取本次值不产生这个标记。见[保留范围](#retention)。
- **refine 在元素上。** 契约仍生成 `newtype TextLine = TextLine Line`；`Flow` 的参数是 representational 角色，生成的 `Streams` 实例直接把 `Flow TextLine` `coerce` 成 `Flow Line`。
- **空间与边界。** 标记了历史读取的会话在运行期间保留已发布前缀。非终止来源的这部分存储会随发布次数增长，读取方只取五条也一样。等待未来元素的尾部和生产者背压留作[独立专题](NEXT_STAGES.md#urgent-backpressure)。

### 3.4 原子输入与源码约束

Stream handler 类型为 `m ()`。每次 `rawemit text` 都同步启动挂接的 Context parser，parser 用 `rawinput` 读到 `[text]`，成功发布后来源方法继续。一轮可以交付零条、一条或多条。来源正常返回时会话启动下一轮。前驱和 `requests` 按来源调用执行，详见[结束与排空](#end)。

Excu／Scoped 交出的 `[String]` 是原子句柄的输出，不能把空 list 释为 EOF。来源的结束只由 Stream handler 用 `streamEnd` 报告，见 [9.4 节](#end)。

<a id="bootplan"></a>
## 4. 生产方式（BootPlan）

| BootPlan | 静态依据 | 生产步骤 |
| --- | --- | --- |
| Receive | Context 的直接 input 是 Stream，`stream = True` 且 `require = True` | 每次 rawemit → parser 解析并发布 |
| Derive | Context 的 Input 链上有 `streams "U"`，本 lifelong 没有可复用的 AST 发布位置 | 领取一条 U 的交付 → parser 沿 Input 链执行被驱动的句柄，解析并发布 |
| ReuseOutput | 同一 lifelong 已有可静态确定的 AST 位置执行 Context 所挂接的原子句柄 | 沿用该次原始输出 → parser 解析并发布；不另开生产任务（见 [4.2 节](#derive)） |

Stage 2 取消了 RepeatRequest：持续交付只由持续的驱动产生，即上游 Stream，或（2026-11-15 起）另一份持续资产的交付；没有持续驱动的 Context 不能声明持续资产。原先用 RepeatRequest 表达的采样（StreamDemo 的心跳）改为 Stream 加 parser。

**统一驱动规则：首次需求建立运行，后续增量驱动执行。** 进入 lifelong 时建立会话、读取方和输出连接；独立来源可以在读取方登记完成之前生产，这期间发布完整保留，登记后再按读取义务裁剪。AST 单元在登记完成后才启动，因此 ReuseOutput 不会漏掉连接建立前的输出。B 发布后，订阅 B 的独立 Derive 生产链或 lifelong target 才能执行下一步；缺少增量时等待，不因等待而补跑 B。A 消费 B 后再产出资产，也是同一规则。运行时不在生产者调用栈中直接同步执行下游业务。

ReuseOutput 只绑定本 lifelong 内经过来源和启动检查的具体 AST 位置，不扫描全局资产表、任选先到的发布或合并同名 handler 的调用。gen 拆分 original chain 与 Context chain 时保留这次输出的连接；订阅下游不会因此重跑原操作。取消、读取方撤销与未来的背压仍可向上游传播，它们不构成一次新的业务生产驱动。

不成立的组合在生成期按 3.2 的匹配表报错，不在运行中猜测或退化为轮询。

**启动依赖**：lifelong 会话的生产链（Stream 单步、parser 及其读取可达的方法）不能读取其他持续资产，驱动它的那一份除外；ReuseOutput 的 parser 及其 requests 路径也遵守这条限制。gen 同时检查发布位置与领取顺序：不能先等待某资产、再执行唯一会发布它的位置。无法证明来源确定或启动可推进时生成失败，不退化为重复生产。interpreter 托管的 Receive／Derive 会话沿用同一生产计划及 8.3 的读取规则。

<a id="drives"></a>
### 4.1 socket、event、behavior 的写法

这三个词描述外部数据怎样到来，帮助业务作者写 Stream handler；当前都写成 Stream 加 parser。SDK 根据注册和链的组合确定驱动方式。

| 驱动关系 | 数据怎样到来 | 写法 |
| --- | --- | --- |
| socket | 外部持续送来原始数据，逐条接收：连接、消息队列、传感器读数 | Stream handler 每收到一帧就调用 `rawemit`，parser 逐帧解析；连接等资源放在 Stream 的 Input 上游 scope 中，跨生产步骤保持（见 8.1） |
| behavior | 值一直存在，随时可以采样：时钟、心跳、状态轮询 | Stream handler 等待间隔、采样、rawemit，正常返回后开始下一步 |
| event | 离散地发生，每次发生得到一条 | Stream handler 取得事件后调用 rawemit |

- 节奏只由 Stream handler 的阻塞或等待决定，SDK 不加间隔；立即返回的 handler 会形成高频生产。
- 本 lifelong 内原子输出的持续发布由 ReuseOutput 接入；它复用具体 AST 执行的输出，不识别任意外部事件。lifelong 外的普通驱动不因资产名相同就广播给会话，也不恢复 RepeatRequest 的反馈写法。
- 外部 push callback 不能直接注册给 SDK，需要先转换成可阻塞读取的队列，再作为单步来源；通用回调适配本版延期（见第 11 节）。
- StreamDemo 的温度与心跳都由定时采样驱动。LinesDemo 则在一次来源调用内逐行 rawemit。

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
        seen <- stream @Line
        rawoutput [show (length seen), show (sum [length text | Line text <- toList seen])]

    instance ParseTotalLayer m => ParseTotalHandler m where
      parseTotal = do
        fields <- rawinput
        case fields of
          [count, size] -> pure (Total count size)
          _ -> raise (ParseTotalError "the counter gives a line count and a character count")

    -- demo/LinesDemo/AST.hs
    ast = chained [chained [node "Announce"], monitorLines, chained [node "Report"]]
    monitorLines = lifelong
      [ parallel
          [ chained [node "PrintLine", node "TextCounter"]
          , chained [node "ShowTotal"]
          ]
      ]

`countText` 以 `stream @Line` 读取本次及更早的行算出累计，`parseTotal` 只解析本次原子输出。两者是普通的 Excu handler 与 parser，派生装配复用已有的 `streams` 声明与 AST 入口。AST 的一个单元打印并执行 `TextCounter`；gen 把 `RunningTotal` 装配为 ReuseOutput，会话接收这次原子输出经 `CountParser` 解析后的资产。另一个单元的 `ShowTotal` 领取该发布，不另行执行统计，显示与原行文本可以交错。原子方法仍然不知道它的输出将由谁消费。

**为什么产出声明为持续资产。** 链上有 `streams` demand，执行机会来自那份资产的交付，连续成功执行会产生一串增量。`stream = True` 把这个结构关系写在源码里；写成 `False` 或通过 `requests` 再驱动它由生成期拒绝。发布只发生于实际执行且成功解析的位置，alternative 未选中的位置不凭空产生交付。

**规则。**

- **已有 AST 执行**：gen 在同一个 lifelong 内沿 target 自身及 original Input 链确定 Context 所挂原子句柄的发布位置，写入 `ReuseOutput [NodeId]`；不把任意 requests 生产链中的同名操作算成全局复用者。会话没有独立 worker 或虚构的生产挂载；原子入口成功后调用挂接 parser，`rawinput` 由本次输出回答。parser 的生产记录继承原节点的 Origin、执行帧和 ScopeUser，资产保持这次生产的身份。不同独立调用不因 handler 名或值相同而合并。
- **独立派生**：没有上述 AST 发布位置时使用 Derive。会话每领取一条上游交付执行一次 parser 及其 Input 链，成功后发布一条；无新增量时等待，不能用 `requests` 补产。可以继续逐级派生。
- **来源与驱动**：一条派生链只由一份持续资产驱动，不再读取其他持续资产。ReuseOutput 默认只接受一个发布位置；多个位置须处于同一个重复单元，且两两是 alternative 的互斥候选。gen 另把 target 订阅、chained 前置和持续资产的 alternative 选择读取纳入启动依赖检查，保守拒绝存在启动环的候选组合，不依赖 IO 时序证明进展。Input／demand 的环也照常拒绝。
- **同单元的路径覆盖**：单元直接订阅或经独立 Derive 间接依赖自己产出的资产时，每条到达订阅的 workflow 路径必须此前已经过发布位置，或同轮有并行启动且必经的发布路径。alternative 只有每个候选都能供值才算必经，不能用其他候选可能发布来证明当前路径。跨单元的条件发布不要求每轮产出；读取方可以等待后续增量，或在发布单元结束并排空后退出。
- **scope 输出的边界**：Scoped.open 复用活实例时可以跳过方法体，没有新的原子输出。因此同单元直接订阅或经 Derive 等待这类 ReuseOutput 当前由 gen 保守拒绝；没有把“经过 open 位置”当成本轮必有新发布。跨单元仍可等待实际发布或来源结束，独立 Derive 不受这项拒绝影响；精确识别必定 fresh 的开启后放行留待后续。
- **结束**：Derive 在上游结束并排空、或被驱动链上的 Excu 调用 `endStream` 时，先封住自己的发布，再离开并按需退役上游。ReuseOutput 的发布位置按节点计，节点 `endStream` 时立即撤下，所在单元结束时撤下其余位置，全部撤下后封住发布并通知排空；单次 target 成功或单轮结束都不撤下。同单元读取等本轮发布及派生处理稳定后，仍无新交付才跳过；不会等本单元下一轮来补值。见 [9.5 节](#consumer-end)。
- **失败**：持续挂接 parser 失败进入现有 Stream 失败与监督协议，不能沿用普通 Context 注入失败只留在注入内的规则。已完成操作与之前的发布不回滚，失败不重跑原操作。普通 Context 的注入规则保持不变。
- **读取与保留**：两种派生资产均交付声明表示类型的值。`streams` 在驱动位置领取本次交付，`requires` 只捕获一次值；普通链可在 lifelong 外按独立 Derive 计划建立生产关系。独立 Derive 登记上游读取方，ReuseOutput 沿用原消费单元的上游读取，不额外登记一份。交付按 7.1 的读取义务保留。
- **普通副产物**：ReuseOutput 只交付持续资产；原 AST 调用的普通发布写入运行级最新值。它不自动成为其他单元的固定捕获；独立 Receive／Derive 的伴随发布仍按交付固定。
- **仅供后继或暂时无人读取。** AST 挂接的持续副产物也进入本边界的会话集合。没有待领取项时，交付队列保留最新绑定供合法后继 `requires` 读取。标记了历史读取的会话同时遵循[历史保留规则](#retention)。保存绑定本身不会额外执行原子操作。
- **不提供**：手写跳过出口、多份持续资产合并驱动一条链、缓冲策略与窗口。消费方结束与读取方计数归零时停产见 [9.5 节](#consumer-end)。

<a id="static"></a>
## 5. 静态结构与合法性

### 5.1 消费摘要

每个挂载的 target 的订阅只看 original chain 自身：末端 effect 及其 Input 祖先声明的 streams demand。不能汇总 `chainReaches`，它包含被驱动的 Context 与生产链内部的传递可达方法；生产链内部的依赖另用于启动依赖检查。

### 5.2 lifelong 合法性

1. lifelong 内每个挂载的 target 恰好订阅一个持续资产。
2. 这些 target 的 original chain 不再读取（requires／streams）其他持续资产；否则执行结果取决于读取时刻。多个来源的触发组合另行设计。
3. 只有普通 requests／requires 的末端不能进入 lifelong；一次性准备放在外部 chained。streams 末端不能出现在 lifelong 之外。
4. Stream、Context 不作为 target，Stream 也不能进入 original chain；带 streams 的 Excu／Scoped 可以挂载到 AST 并向挂接 Context 提供同次输出。gen 按本 lifelong 的具体位置确定 ReuseOutput，不能证明来源唯一或启动可推进时拒绝。
5. lifelong 不嵌套；lifelong 内不能有空分支。因为每个 target 都订阅，单元每条成功路径都至少领取一条新交付。
6. 合法 Haskell 不自动等于结构可提取；未知高阶 effect、隐藏的 effect 循环等继续使用现有诊断。
7. 会话步骤的普通辅助资产仍随交付保存为伴随发布，领取方使用该步的固定捕获。没有相应捕获的普通读取按运行级最新值取值，不因读取方不订阅该会话而拒绝；缺值按共享供值协议等待。
8. 同一单元订阅自己经 ReuseOutput 发布的资产（包括经 Derive 间接依赖）时，必须逐条 workflow 路径证明先有发布机会，或同轮有并行且必经的发布路径。parser 及其 requests 路径不得额外等待其他持续资产。规则拒绝可确定的启动互等，不证明任意原子 IO 都会返回。

这些检查不证明任意原子 IO 能够返回，也不证明即时采样会限速。

### 5.3 原型中的表示

lifelong 写入统一 Prototype，运行装配、来源分析与 `--structure` 读取同一份数据：

    LifelongAt NodeId LifelongProto [WorkflowTree]

    LifelongProto
      { lifelongUnits         :: [NodeId]            -- 单元：规范形式中的直接子项（源码中直接子项的 parallel 已拆开）
      , lifelongSubscriptions :: [(NodeId, String)]  -- 每个挂载 target 订阅的资产
      , lifelongSessions      :: [SessionProto] }    -- 订阅资产、上游资产及 AST 持续副产物各一份会话

    SessionProto { sessionAsset :: String, sessionPlan :: BootPlan, sessionMounts :: [NodeId] }
    BootPlan = Receive String | Derive String | ReuseOutput [NodeId]
    -- Receive：Stream 注册名；Derive：驱动资产；ReuseOutput：本 lifelong 的原子输出发布位置

- 会话挂载 NodeId 为 lifelong 路径加 `[-1, 会话序号, 步骤]`：步骤 0 是 Stream 单步、步骤 1 是 parser；Derive 只有步骤 0（parser）。挂载以 `SessionChain` 角色进入 `protoChains`，参与构图与 ScopeTree。ReuseOutput 的 `sessionMounts = []`，沿用所记录 AST 位置的 `NodeChain`，不为复用输出虚构一个独立执行。
- `protoSessions` 保存独立 Receive／Derive 的 interpreter 托管计划，挂载为 `[-2, 序号, 步骤]`。首次有限持续需求启动对应上游，读取者不因此订阅；备用计划本身不等于已启动的供值。ReuseOutput 仍只连接具体 lifelong 的 AST 位置。
- ReuseOutput 的位置来自同一 lifelong 的 original Input 链。即使没有订阅者、只供后继 `requires`，AST 挂接的持续副产物也纳入会话集合。`Gen.Composition` 在生成期检查供值位置的唯一性以及订阅、顺序前驱、选择读取组成的启动图；运行时直接执行已确定的计划。
- 来源分析仍按消费单元裁剪生产步骤的成功出口并保留固定伴随捕获；普通供值另外通过运行级固定点传播，允许独立分支共享。同次交付中的已有捕获优先于普通最新值，缺失辅助值时不补产。普通读取不再按生产挂载与读取位置的先后过滤；算法只在[图规范](EFFECT_GRAPH.md#missing-source)维护。
- 分析裁剪：以 `lifelongUnits` 确定单元，不穿透单元内的 chained、alternative 或 parallel。每个生产挂载保留本单元可能读取的契约及生产链自身的读取依赖，成功出口再按单元相关契约投影、去重，然后逐步组合 Receive 的步骤和各会话状态。仍分析全部会话，避免遗漏其他会话造成的来源冲突；不把成功出口取并集。生产链的 read／drive 事实独立累计。
- 读取点来源 `FromSession` 表示持续资产经会话交付，不查询普通来源表。读取已捕获的交付优先；合法先前 lifelong 的会话优先于独立托管计划。有限读取不复用尚未发生的 AST 输出，也不能把 ReuseOutput 位置解释成补跑该位置的许可。
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
- **每个资产只领取一次**：同一 frame 中后续 target、alternative 的选择读取与候选、内部 parallel 中同时需要它的节点，都共享第一次领取的视图。alternative 的选择读取执行共同的 Excu，它读到的持续资产与候选共享本次领取；判定 Context 只能是非持续资产。
- **首次读取领取**：frame 中尚未领取的本 lifelong 会话资产，在第一次读取时领取（例如被生产链读取）。
- **结束**：单元每轮新建调用捕获和交付视图；开始新一轮时清理旧步骤的 Origin 输出索引，运行级普通最新值继续保留，执行结果不累积。
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
## 7. 会话、交付、游标和 frame

| 状态 | 归属 |
| --- | --- |
| 会话与待交付值 | （lifelong 边界，生产该资产的 Context 注册名）；interpreter 托管的会话边界为空 |
| 交付游标 | 消费单元＋会话 |
| 本次固定视图 | 单元执行 frame＋资产 |
| target 执行 | NodeId＋新的 Origin |
| 独立生产步骤执行 | Receive／Derive 的会话挂载 NodeId＋每步新的 Origin；ReuseOutput 沿用原 AST 执行 |
| 生产资源的使用登记 | Receive 的来源与每次 parser 调用各自持有本次使用，Derive 每步独立登记；跨步骤待用由会话 ExecutionFrame 保持；ReuseOutput 沿用原节点（见 8.1） |
| scope 归属 | 既有 Binding ownership 与具体 scope 实例 |

运行时保存值与保留可操作的资源是两种关系，当前各处的职责如下：

| 持有位置 | 保存什么 | 何时撤销 |
| --- | --- | --- |
| 调用的 ScopeUser | 本次受控调用实际使用的实例与待认领绑定 | 业务、诊断及受控结果消费结束后 |
| 独立生产步骤的 ScopeUser | Receive／Derive 本步实际使用的实例；来源与每次 parser 调用分别登记 | 本步业务、诊断与受控结果消费结束后，失败或取消也撤销 |
| 独立生产会话的 ExecutionFrame | 后续步骤的待用预约及固定／下一条参数身份查询 | worker 退出时摘除；来源封口不直接撤销，仍沿既有会话退役边界 |
| ExecutionFrame 与静态开启计划 | 节点待用、参数生产身份及允许的后继关系 | 节点退休、来源不再匹配或帧结束；合法外部后继的待用关系单独保留 |
| 交付队列、固定捕获与合法后继的待用 | 原 Binding；已声明资源的 ownership 参与保留查询 | 按领取、执行结束、替换及待用耗尽撤销；先交接后撤销，详细规则见 [9.3](#binding-retention) |

ReuseOutput 沿用原调用的 ScopeUser，没有独立生产任务；资源按[已登记的 Binding ownership](#binding-retention)保留。

- 同一边界同一资产共享会话，不同单元各自推进；不同 lifelong 的会话与进度独立。
- 进入 lifelong 时建立会话、读取方与输出连接；独立来源在登记期间已经产生的发布完整保留。单元在登记完成后启动，ReuseOutput 只接收实际 AST 执行的输出，不启动另一份任务。单元的游标从会话的第一条发布开始，每次领取一条固定交付。
- 每条 publication 保留原始 Binding、生产 ActivationId、执行帧、Execution 与共享 ownership；领取与捕获不创建新的 owner。后台追加不替换已经捕获的 Binding，读取不推进本次已领取的游标。
- 持续资产进入会话交付队列；普通辅助资产写入共享最新值，同时按 Origin 保留当前步骤输出，供独立 Receive／Derive 组装伴随交付。ReuseOutput 只交付持续资产，不建立这种普通资产交接。
- 独立生产任务的每条交付另带该生产步骤已经发布的普通资产（伴随发布）。DeliveryFrame 领取交付后，伴随发布作为已捕获绑定交给本次执行中的调用，交接中已经捕获的值优先；运行时不再按会话挂载的当前 Origin 读取这些发布。因此处理第 n 条交付时读到第 n 步的辅助资产，不会读到之后步骤的产物，也不会因旧发布已被替换而重新生产。ReuseOutput 不建立这种普通资产交接。
- 运行初始化不预生产 Context；会话按需启动。

<a id="retention"></a>
### 7.1 会话保留多少发布

一次发布涉及两类读取义务。交付队列按各读取方的游标保留未领取增量、随交付传递的绑定和最新值。需要 `stream @T` 的会话还保存各次发布的元素，用来构造固定的历史前缀。两者的释放时机分别如下。

| 读取关系 | 保留范围 |
| --- | --- |
| 原型带 `effectHistory` 标记（见[按 x:xs 读取](#flow)） | 另存从首条发布到本条的元素。游标前进时仍可读取前缀。来源停止且所有登记的读取方离开后，会话释放这部分历史，保留最新绑定 |
| lifelong 的单元与独立 Derive 会话 | 最慢游标之后的未领取交付，加上最新一条 |
| 没有未领取交付，或只有普通有限读取 | 最新一条 |
| lifelong 尚在完成初始读取方登记 | 暂保留已经发布的交付，登记完成后按游标裁剪 |

- **登记**：lifelong 按 Prototype 一次登记各单元和派生会话的游标，从首条交付开始。interpreter 托管的 Derive 在首次建立时登记上游游标：已有发布时，从登记瞬间最新一条开始；没有发布时，等待首条。之后按序领取未来交付，不重放登记以前的完整发布序列。
- **离开**：单元或派生会话不再读取时，撤销其游标；不会删掉其他读取方尚未领取的增量。ReuseOutput 没有独立上游游标，原消费单元已经承担该读取。
- **停止**：lifelong 内的独立会话按[读取方计数](#consumer-end)退役；interpreter 托管会话保持到运行结束，避免后续有限读取意外重启来源。
- **伴随发布**只随交付领取：全部读取方领取过后，SDK 放掉该条伴随发布的引用。
- **积压不合并**：相等值的两次发布仍是两次交付。不丢弃尚未领取的值，也不因没有新交付而补跑来源。
- **积压与历史的空间开销。** 慢消费者可以造成无界积压。即使游标都已赶上，标记了 `effectHistory` 的活动会话仍保留前缀。
- **固定捕获与资源寿命。** 调用已经取得的视图仍然有效。资源待用与 scope 开启按本次 Binding 的生产身份判断。向前遍历历史只读过去的业务值，不会为旧交付重新登记 scope 使用。

<a id="retention-cost"></a>
### 7.2 保留与离开的时间复杂度

R 为一个会话当前登记的读取方数量，N 为保留的条目数。会话用 `Data.Sequence` 保存交付，读取方保存在游标表中。

| 操作 | 代价 | 来源 |
| --- | --- | --- |
| 发布一条 | O(R + log N) | 追加条目后，扫描游标并裁剪已领取前缀 |
| 领取一条 | O(R + log N) | 定位一条交付、推进游标并裁剪 |
| 登记或离开读取方 | O(R + log N) | 更新游标表并重新计算保留位置 |
| 通过 `require @T` 取得已经捕获的当前值 | 不随队列长度增长 | 直接读取固定 Binding。通过 `stream @T` 遍历整段前缀时，业务还需逐个访问历史元素 |

上述代价只描述交付队列的基础操作，不包含资源保留匹配、scope 回收和业务值的解析、求值或累计数据操作。资源保留另有仅包含已声明资源的索引；裁剪只处理移出的资源项，回收查询仍会扫描保留的资源项和活动读取义务，未承诺常数时间。普通资产积压不进入该索引。R 个读取方各领取一次会有 R 次游标扫描，不能将一次发布的全部交付承诺为 O(R)。交付队列随积压增长，历史前缀随标记会话的发布次数增长。窗口、容量与背压另行设计。

<a id="production"></a>
## 8. 生产与普通读取

### 8.1 生产路径

    Receive：调用来源 → 每次 rawemit 同步解析并发布 → 继续当前方法 → 正常返回后开始下一步
    Derive：领取一条上游交付 → 将该交付固定为本步输入 → parser 沿 Input 链执行被驱动的句柄，解析并发布一次 → 下一步
    ReuseOutput：原 AST 位置执行原子句柄 → 挂接 parser 读取本次原始输出并发布一次 → 原 workflow 按已有控制流继续

parser 的包装发布一次；会话不再次发布返回值，也不再调用一次 parser。Receive 的每次来源调用、每次 emit 驱动的 parser，以及 Derive 的每个步骤各有自己的 Origin 与捕获环境，从进入 lifelong 时保存的交接新副本开始：外层已经捕获的值（例如 alternative 选择时读到的配置）在生产端与消费端一致。interpreter 托管的会话没有交接。ReuseOutput 的 parser 是原节点内的挂接调用，保留该节点的 Origin、执行帧与 ScopeUser；记录自己的 Context activation，但不另开一个根执行、不重放原子操作。

Receive 在交出原始输入时，也把同一步来源执行已捕获的资源 Binding 交给 parser；parser 的 rawinput 使用这次输入，因此不重跑来源来恢复资源。交接保留原 Binding 的生产身份、执行帧与共享 ownership，来源在解析期间继续持有其资源，parser 的短期 ScopeUser 继承来源实际使用的实例，以保留父子 scope 关系。这是同一生产步骤内的资源交接，不放宽普通跨入口 Handoff 对资源绑定的过滤，普通资产按共享供值协议读取；不能扫描其他打开的实例来补值。资源与开启参数仍按[既有 scope 规则](CORE_DESIGN.md#scope)区分，不因来源在会话里运行而重分类。

Receive 的来源与每次 parser 分别登记使用，Derive 每次解析使用独立登记；本步的业务、诊断与受控结果消费结束后撤销。跨步骤的复用由会话的待用执行帧保持，按实际参数生产身份匹配实例，不再让一份 ScopeUser 累积持有全部历次实例。来源正常结束时仍保留会话待用预约到退役；详细边界见[第 9.3 节](#binding-retention)，停止与退役时机见[第 9.5 节](#consumer-end)。ReuseOutput 沿原消费节点与执行帧回收，没有额外生产任务或会话预约。

lifelong 单元每次执行建立独立的 ExecutionFrame。参数来自外层或没有参数的 scope 由外层帧保留；参数来自本轮的实例归本轮，后继共享不改变归属，本轮结束且没有合法后继待用时回收。DeliveryFrame 仍负责本轮会话视图的领取；ExecutionFrame 记录已领取普通伴随资产的生产身份及所属 lifelong 边界，不复制值。根实例的待用查询包含活动子帧：即使后台会话已经发布下一步，本轮后继仍按固定交付身份保留同一实例。轮帧结束后清空进度并从父帧摘除；已经允许的 lifelong 外后继仍按静态来源和实际保留绑定判断待用，具体规则见[图与来源](EFFECT_GRAPH.md#scope-opening-retention)。持续值作为 scope 参数的身份观察已接通；已知 Binding ownership 的保留及资产契约的范围见[资源边界](#binding-retention)。

Stream handler 的阻塞／等待决定节奏，SDK 不加间隔；立即返回的生产会形成高频生产，慢于来源的读取方可能持续积压（保留规则见 [7.1 节](#retention)）。本版不提供容量背压、丢弃或去重。

### 8.2 显式驱动与反馈

持续资产的执行机会来自 Stream 来源或上游持续交付，发布统一进入会话；消费方不能 `requests` 它。ReuseOutput 接通的是已经由 lifelong 驱动的原子输出，不恢复原先以 `request @T` 把新发布送进会话的 RepeatRequest 反馈写法。

lifelong 外的普通驱动按原有 origin 发布，不因类型相同就广播给任何会话。

### 8.3 lifelong 外的有限读取

普通 `requires "T"` 只执行一次消费，handler 按表示类型取得固定值。它既可以直接读取持续资产，也可以出现在一条普通 Context 生产链中：该链捕获 T 后完成一次原子操作和解析，发布自己的结果，不继承 T 的重复驱动。

gen 为独立 Receive／Derive 生产关系生成 interpreter 托管计划。首次有限需求没有现成视图或合法先前 lifelong 会话时，runtime 按计划建立所需上游，再启动派生生产。A 消费 B 并持续发布，C 只读取 A：B 的增量驱动 A，C 获得一次值后继续自己的 workflow。SDK 不需要知道 A 做的是记录保存、统计还是其他计算。

- **固定取值**：本次已有捕获时复用；否则至少等待一次发布，捕获读取时可取得的最新值。之后后台更新不修改这个捕获。
- **派生起点**：首次登记 Derive 上游游标时，已有发布从当时最新一条开始，没有发布则等首条；之后按序处理新交付。它不承诺追溯登记前的所有发布。
- **边界独立**：托管会话不共享另一个正在运行的 lifelong 的会话；合法先前 lifelong 已有该资产时，读取该会话的最后值，不重新启动来源。
- **存续**：普通读取返回不会停止托管生产。后续有限调用仍可读取新值，任务由 interpreter 退出统一停止。
- **结束与缺值**：来源已结束但有过发布时读取最后一条；一条都没有发布就结束时报告 `ContextNotInitialized`。失败按现有协议传播。
- **不补跑 AST**：ReuseOutput 的位置只在所属 lifelong 实际执行时供值。有限读取建立的是已生成的独立生产计划，不执行或借用未来的 AST 挂载。
- **收尾限制**：诊断、自动收尾与 close 期间不启动新会话。

这项组合只把生产计划与读取方的启动关系分开；不放开对持续资产的 `requests`，也不把普通链的 `streams` 自动解释成有限读取。

<a id="execution-boundaries"></a>
### 8.4 共同执行结构与模块边界

Stream 的独立生产步骤与 lifelong 的消费轮次都由 SDK 在推进条件满足后启动有限调用，再决定继续或结束。Stage 3 统一的是这些调用的身份、捕获和收尾责任；生产与消费仍各自推进，不等待对方整轮完成，也不要求两者使用同一个循环或状态 ADT。

| 共同责任 | 独立生产步骤 | lifelong 消费轮次 | SDK 落点 |
| --- | --- | --- | --- |
| 使用已确定的驱动关系 | Receive／Derive 挂载；ReuseOutput 直接复用原节点 | 单元、订阅节点、本地发布与派生关系 | Composition 组织计算；Booter 输出 Prototype 驱动事实；Injector 给出入口装配 |
| 为实际调用建立身份与固定捕获 | 每次 lower 创建 Origin／Activation；Receive 在本步交接原始输入和资源 | 交付由 DeliveryFrame 固定，各 target 有各自的调用身份 | Runtime、Runtime.App；Binding 的原生产身份不因交接改变 |
| 区分实际使用、未来待用与绑定保留 | 本步 ScopeUser／Retention，会话未来使用帧 | 调用 ScopeUser、本轮 Retention／ExecutionFrame 及外层待用 | Runtime.Frame、Retention、Graph 与 Scope，详见 [8.1](#production)、[9.3](#binding-retention) |
| 结束只影响其所属边界 | 来源封口后仍可排空；退役才撤销会话预约 | 节点结束订阅、单元结束、lifelong 返回各自处理 | Runtime.sessionLauncher、Execution.repeatUnit、Session；详见 [正常结束](#end)、[消费方结束](#consumer-end) |
| 退出后再判断资源是否不可达 | 步骤撤销实际使用，退役停止并等待 worker | 受控子任务汇合，轮帧结束，撤销执行保留 | 两侧均进入现有 Graph／Scope 回收；失败、取消见 [第 9 节](#failures) |

`streamEnd`、`endStream`、正常返回和失败不合并成同一种结果。来源封口不等于生产线程已退出，生产线程退出也不意味着所有消费者持有的资源可以关闭。当前独立来源封口后保留会话预约，等待既定退役或运行退出；ReuseOutput 没有独立 worker 或会话预约。

本节是当前协议的实现对照。Source／Shape 读取 Haskell 结构，Emit 渲染已定计划；它们不决定上述动态状态。容量等待留给[背压专题](NEXT_STAGES.md#backpressure)，现行失败传播见[失败协议](#failures)。

<a id="failures"></a>
## 9. 故障、取消与资源边界

### 9.1 失败：临时规则

现有资源回收已接通；局部失败恢复尚未实现，继续采用下面的临时规则：

1. **适用范围**：只在 AST 中包含 lifelong 时生效；不包含 lifelong 的程序，失败处理保持现状（interpreter 会话的生产失败只传给等待它的读取方）。
2. **触发**：生产失败、解析失败、消费单元失败、AST 中任何 node 或 alternative 选择读取的失败，以及上述任务中的原生异常。
3. **处理**：结构化 Failure 先完成既有 Error 协议的诊断与处置，原生异常直接通知运行监督。随后终止整次运行：停止启动新工作，取消全部任务（会话、等待中的单元、执行中的 target、其他并行分支）并等待受控收尾，走 interpreter 退出清理；结构化失败报告最初的 `Failed`，原生异常重新抛出。
4. **不做**：不只终止局部的 lifelong，不让外层 chained 继续执行后继，不重试。

失败在发生处直接通知运行监督，因此 `parallel [monitor, otherWork]` 中 otherWork 的失败不会因等待永不结束的 monitor 而被吞掉。失败的会话不再接受新发布，等待它的读取方收到原失败。

### 9.2 取消

外部取消（Ctrl-C）时，SDK 取消 AST 中的全部任务并等待其受控收尾，再停止全部会话（撤销在途步骤使用与会话待用预约），最后由 interpreter 按 ScopeTree 关闭剩余资源。关闭失败（`raise` 或 close 中的普通 IO 异常）单独汇总，不改变原业务结果，也不重试。Ctrl-C 等取消在其余收尾后重新抛出；取消发生在同步 close 中也停止后续启动，不能降为仅报告的关闭失败。

创建会话时，启动生产任务与写回会话登记在同一个不可中断区内完成，取消不会落在两者之间。停止会话时先关闭会话登记，并在同一临界区取出全部会话：此后尚未停止的生产步骤不能再启动新会话（例如 interpreter 托管的依赖会话），请求方得到异常并随停止结束，不会留下逃出停止集合的生产任务。生产任务的启动与登记、失败报告、撤销使用登记和完成信号都在不可中断区内完成，生产时解除屏蔽，停止等待任务退出。这保证 SDK 的登记与完成信号交接不会被取消打断；任务能否退出仍依赖业务 IO 响应取消、诊断与收尾能够返回。

`stopSession` 统一使用“无 worker／运行中／停止中”的内部状态。首次停止登记停止中并取得任务，锁外发出取消并等待；并发或重复停止取得同一完成信号，也必须等待 worker 的 `finally` 撤销在途步骤使用与会话待用预约后返回，不能把“已经请求停止”当成“收尾完成”。停止状态只保存完成信号；首次停止方在锁外持有任务句柄直到完成，后续调用不重复取消。停止与等待不持有会话状态锁或 worker 目录锁；`endSession` 的封口、`leaveSession` 的读取方撤销仍是各自独立的事件；lifelong 独立会话的读取方计数归零时，由离开方在锁外调用已安装的退役动作（停止、封口、回收）；interpreter 托管会话不安装该动作，见 [9.5 节](#consumer-end)。

<a id="binding-retention"></a>
### 9.3 已知资源的保留与 close 边界

不新增 Stream close、next-use 或业务集合按元素关闭协议。没有增量表示等待，不表示结束、故障或关闭；直接来源由 Stream handler 的 `streamEnd` 报告结束，Derive 由上游耗尽或被驱动链的 `endStream` 结束，ReuseOutput 在发布位置全部撤下后封口（9.4、9.5）。

**保证范围（2026-11-18 修订）：** 保留实际执行、持续待用和已有 Binding ownership 能定位的资源；注册指定的资源 Context 在认领前也保持同一归属单元。Context／Pure 把本次原子输出解析或变换成普通业务数据，不因此让新 ADT 继承生产方法用过的全部资源。资产、注册、handler 与 workflow 写法不变；保活不让链外资源读取变得合法；普通共享供值遵循独立的 Context 协议。

**资产契约的边界。** 原子操作交出 `[String]`，Stream 每次交出一个 `String`，Pure 可以变换原始字段，Context 将其解析成业务资产。`Types.hs` 的字段遵循[资产固定形式](ASSETS.md#fixed-form)。已声明资源的寿命由 SDK 跟踪其 Binding 的 ownership，历史中可读取的字符串描述本身不会延长资源的寿命。

| 持有者 | 保留到什么时候 |
| --- | --- |
| Receive 的来源与 parser、Derive 的本次处理 | 本步的业务、诊断和受控结果消费结束；来源在本次调用内持续持有，parser 的使用在该条解析完成后释放 |
| 会话后续步骤的待用预约 | 会话停止并退出；期间只保留与已生成开启计划及实际参数生产身份相匹配的实例 |
| 待交付队列中的资源 Binding 及伴随绑定 | 仍有游标未领取，或初始读取方尚未登记完成；领取前先交给执行持有 |
| lifelong 本轮的固定交付 | 本轮内部全部受控执行结束，包括等待结束、失败及取消收尾 |
| Derive 的一次领取 | 本次解析与发布结束；新产物只保留自己已有的 ownership，不推断内嵌字段 |
| 有限调用取得的固定值 | 调用、诊断和受控结果消费结束；alternative 的选择捕获保留到所选候选结束 |
| 合法后继可读的最新绑定 | 仍有执行帧待用；值被新发布替换、位置完成或跳过后重新判断 |

历史读取取得的 `x :> xs` 中，只有本次的 `x` 是当前交接的 Binding 和 scope 开启参数。`xs` 仍可读作历史数据。队列中另有游标尚未领取的条目及其伴随绑定，继续按各自的交付义务保留。

领取和有限快照读取在 scope 关闭预约的共同协调锁内先登记保留，再推进游标或返回值。队列裁剪只撤销队列的义务，不把领取当成执行完成。撤销执行保留、裁剪资源条目或替换旧绑定后，在锁外按原 owner 和其 ScopeTree 祖先调用现有回收器。冻结的 cleanup 快照不成为实例自己的保留根；订阅和值持有也不增加 ScopeTree 父子边。

**会话的待用关系。** runtime 复用 Prototype 的会话挂载与 `protoScopeOpenings`，在根帧下登记一份会话待用帧。它表示后续仍可能执行的生产位置，不把所有曾经打开的实例都视为仍在使用。启动时已经固定的普通参数优先按原生产身份匹配；Derive 的持续参数按本次固定交付及游标下一条的具体生产身份判断；领取时在同一协调锁内更新固定身份后才推进游标，等待期间不把全部旧实例视作待用。会话预约不成为参数的新生产帧，也不改变原 Binding 的归属；具体查询见[开启计划与待用](EFFECT_GRAPH.md#scope-opening-retention)。

**单例与多例共用关闭条件。** 新 request 只建立新的参数生产身份，不撤销旧实例的实际使用、待用或已有 ownership 保留。每步撤销实际使用后调用现有 scope GC；旧实例不再匹配任何合法后续使用，且没有使用者、值保留或保留它的子实例时才 close。比如数据库同参连接由持续待用保留；每步新参的临时实例可在失去用途后回收；新端口开启第二个浏览器时，旧浏览器若仍供其他受控执行或持续使用，就继续存活。以 `requests` 获取资源 Context 本身，不等于重新生产开启参数。

来源 end 不撤销待交付和执行中的保留。正常结束仍按既有排空与退役协议，保留会话待用帧到生产任务退出；退役先等待本步收尾，再撤销预约并触发现有回收器。有其他使用、待用、值保留或子实例的 scope 继续存活。取消使用相同退出边界，关闭中的取消仍传播；运行退出等待全部受控工作停止后放弃剩余交付并清理。Haskell GC 释放不可达的内存，资源 close 继续由现有 scope 协议负责。

轮询、event 与 socket 都使用这组结构规则：一次采样或收到一条消息不代表来源结束，暂时没有输入也不表示可以 close。BootPlan 决定驱动装配；SDK 不从原子 IO 推断这三个业务名称，也不按它们另选清理策略。现有写法见[第 4.1 节](#drives)。

资源关闭后的受控读取继续检查原 Binding 的 owner 与关闭／失败状态，不自动换 owner、重开或重放生产。外部别名不在本节保留保证内。含 lifelong 的程序按[现行失败协议](#failures)传播失败。

业务资产保存多份数据不等于可以把其中各资源的 owner 合成一个，也不能复活已关闭资源。持续值作为 scope 开启参数沿用本次 Binding 的生产身份和原生产帧；已领取交付、游标下一条与合法后继按读取规则参与待用判断，详见[开启计划与待用](EFFECT_GRAPH.md#scope-opening-retention)。这不自动展开 T 中的资源引用或额外保活其内容。

<a id="end"></a>
### 9.4 来源正常结束（streamEnd）

**代码长什么样。** Stream handler 的结果为 `m ()`，Layer 提供 `Emits` 与 `StreamEnds`。以下是 LinesDemo 的来源和外层 workflow。

    -- demo/LinesDemo/Generated/Effects.hs（生成）
    type NextLineLayer m = (SDK.Reads InputFile m, SDK.Emits m, SDK.StreamEnds m, SDK.MonadMask m, SDK.Raises NextLineError m, MonadIO m)
    class NextLineHandler m where
      nextLine :: m ()

    -- demo/LinesDemo/Handlers.hs（手写）
    instance NextLineLayer m => NextLineHandler m where
      nextLine = do
        InputFile path <- require @InputFile
        bracket (liftIO (openFile path ReadMode)) (liftIO . hClose) $ \file -> do
          let readLines = do
                finished <- liftIO (hIsEOF file)
                if finished then streamEnd else do
                  line <- liftIO (hGetLine file)
                  rawemit line
                  readLines
          readLines

    -- demo/LinesDemo/AST.hs
    ast = chained [chained [node "Announce"], monitorLines, chained [node "Report"]]
    monitorLines = lifelong
      [ parallel
          [ chained [node "PrintLine", node "TextCounter"]
          , chained [node "ShowTotal"]
          ]
      ]

LinesDemo 读完四行后 `streamEnd`，打印与统计单元排空后退出并封住 `RunningTotal`；显示单元领完统计增量后退出，lifelong 返回，`Report` 读取最终统计（输出复用见 [4.2 节](#derive)）。原生文件由来源在 `bracket` 内逐行读取，离开读取操作时关闭，解析失败或取消也走同一释放路径。`TextLine` 的读取方全部离开后会话退役，再由 scope GC 判断是否调用 `InputSession` 的 close。parser、Excu、Scoped 的 Layer 里没有 `StreamEnds`，在它们的方法体里写 `streamEnd` 由 GHC 拒绝。

**交付与结束。** 一次来源调用可以反复交付。只有 `streamEnd` 表示来源主动正常结束；失败与取消各走原协议。

| 出口 | 之后发生什么 |
| --- | --- |
| `rawemit text` | 先通知匹配的 emit hook，再调用 parser。成功发布后在同一次来源调用内继续，消费单元独立领取 |
| 正常返回 `()` | 本次调用完成，会话启动下一次来源调用 |
| `raise` | 经 Error 协议诊断，按 9.1 的规则处理 |
| `streamEnd` | 当前会话封口。此前的每次成功发布都可排空，包括本次调用内的发布 |

`streamEnd` 不是失败：不进入 Error 诊断，不通知运行监督，也不被方法体内的 `catchError` 接住。已经完成的 IO 和此前的发布不回滚。它直接作用于资产，不看 AST 上有哪些消费方：只结束当前绑定所在的会话，各消费方排空后各自结束；同一个 handler 注册给其他 Stream 时，各自的会话互不影响。

**会话。** 会话记录“已结束”并封住发布，这两件事在同一临界区内完成，然后唤醒等待者。已经发布、尚未领取的交付仍有效；排空后只保留供合法有限读取使用的最后值（见 [7.1 节](#retention)）。正常结束、失败、取消三者保持区别。

**排空。** 结束后已经发布的交付仍可领取：

| 状态 | 领取结果 |
| --- | --- |
| 还有未领取的交付 | 返回下一条固定交付 |
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

- 单元的普通产物：每个普通 Context 保留最新发布。切轮和结束不撤销它；没有固定捕获的后继或其他单元可读取。
- 多个位置发布同一普通资产：按实际成功提交顺序更新共享最新值；任一调用已经捕获的 Binding 不变。
- 持续资产：读已结束的那个 lifelong 会话的最新一条（会话此时只保留这一条），不另行启动来源。先后排列的多个 lifelong 都有这个会话时读最近结束的那个。
- 零轮或从未发布：缺值按耗尽协议报 `ContextNotInitialized`，不等待。
- 生成期仍拒绝后继在两个互不先后的 lifelong 会话之间选择持续资产；这条会话路由规则不用于普通资产的多处发布。

带资源归属的资产不经普通来源表，不能凭上述后继规则在链外读取资源。普通资产作为开启参数时的后继待用已经接入[scope 开启计划](EFFECT_GRAPH.md#scope-opening-retention)；持续值参数与已知 ownership 的[交付保留](#binding-retention)已接通，保证范围遵循该节的资产契约。

**资源。**

- 来源结束后，会话的使用登记保留到会话退役，排空期间不会因为来源结束而提前关闭资源。
- 只在生产会话中开启的 scope（例如 StreamDemo 的 `SensorLink`、LinesDemo 的输入文件）在会话退役时按可达性回收：生产已经停止、读取方计数归零（或 lifelong 返回）；后继还会以同样参数开启的实例保留。见 [9.5 节](#consumer-end)。
- 单元自己开启的 scope 在 lifelong 的节点退休时，由现有的可达性回收照常处理；这是节点结束的既有规则。
- 交付按[已知 Binding ownership](#binding-retention)保留资源；不承诺任意业务数据内嵌资源的生命周期。

**失败与取消。** 不变：含 lifelong 的程序中的失败仍按 9.1 终止整次运行。

<a id="consumer-end"></a>
### 9.5 消费方结束（endStream）与按读取方计数停产

一份持续资产只有一个生产方，消费方可以有多个。生产方结束直接作用于资产（9.4）；消费方结束只撤销自己的读取，生产是否停止由读取方的引用计数决定，与 Stream GC 用的是同一份读取方登记（[7.1 节](#retention)）。

**代码长什么样。** 注册、AST 与 handler 签名都不变。gen 给以 `streams` 订阅持续资产的 Excu 加入 `EndsStream`，方法体多一个出口 `endStream`：

    -- demo/LinesDemo/Generated/Effects.hs（生成）
    type PrintLineLayer m = (SDK.Reads Line m, SDK.EndsStream m, SDK.Raises PrintLineError m, MonadIO m)

    -- 手写（示意，示例本身不调用）：收到业务结束标记后离开
    instance PrintLineLayer m => PrintLineHandler m where
      printLine = do
        Line text <- require @Line
        if text == "stop" then endStream else liftIO (putStrLn text)
        rawoutput []

**谁拿到 `endStream`。** 自己以 `streams` 订阅持续资产的 Excu（`Gen.Composition` 的绑定能力规则，2026-11-17 修订）。它是被这份资产驱动的消费方，`endStream` 结束的是它自己的订阅。`streams` 只出现在被驱动的位置：lifelong 节点的订阅（[5.2 节](#static)），或独立 Derive／ReuseOutput 被驱动的 Input 链。所以运行时按当前调用的位置就能确定订阅，业务不用说明结束哪一份资产。

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
3. **会话**：lifelong 边界内的独立 Receive／Derive 会话，在已登记的读取方（单元与由它驱动的 Derive 会话）从有到无时退役。interpreter 托管会话与 ReuseOutput 的停止边界见下文。

ReuseOutput 的发布位置同样按节点计：节点结束订阅时立即撤下它，不等下一轮；所在单元结束时撤下其余位置。全部撤下才封口，下游由此排空后结束。parallel 的分支互不影响：一个单元离开会话，只让计数减一。

**同单元的发布与读取（2026-11-17 修订）。** stream 是驱动关系。gen 允许此前已经发布，也允许同轮有必经的并行发布路径；同单元本身不证明发布已完成。读取先等本轮仍可能完成的发布，确定本轮不会再增加交付后才跳过：

- **本地范围**：直接 ReuseOutput 的全部发布位置须属于当前单元；沿 Prototype 的单一 Derive 上游递归追溯，只有根是本单元 ReuseOutput 的派生会话才同样属于本地。Receive 和其他单元的发布保持外部来源的等待规则。
- **本轮稳定**：实际轮 `ExecutionFrame` 中全部发布位置为 `Completed` 或 `Skipped`，才表示本轮不会再从这些位置发布。`Pending`、`Running` 与未知位置都继续等待；alternative 未选路径由既有的跳过记录体现。派生会话还须逐级完成上游已发布的全部步骤：只在一次解析与发布成功返回后推进 `stateProcessed`，与上游累计发布数 `stateBase + 队列长度` 比较，领取游标不证明处理完成。
- **交付优先**：已有交付立即领取；没有交付时，等待同一共享通知上的会话变化或节点退休。判定本轮稳定后再读会话状态，优先交付刚完成的发布或传播真实终态，仍无交付才返回 `Undriven`。这不会把尚在运行的并行生产或异步派生当成本轮没有输出。
- 订阅节点收到 `Undriven` 时只跳过本轮；会话封口且排空时，这些位置的订阅结束，不因此结束单元。多个互斥发布位置尚未全部结束时，后续轮次仍可由其他候选产生新交付。
- 只 `require` 本地资产的位置，在本轮稳定而无新交付、或会话封口排空时读已有的那一条；一条都没有发布过时按缺值报 `ContextNotInitialized`。

本轮稳定只免去等待本单元下一轮的发布，不停止外部来源，也不预测任意原子 IO 是否会返回。

**退役。** 同时只有一个调用执行退役，其他调用等待。只有全部步骤成功完成才记为 `Retired`；取消或异常使状态恢复为 `Unretired` 并唤醒等待方，后续调用可继续完成未完成的退役：

    停止生产任务（取消并等待本步使用与会话待用预约撤销）
    → 封住发布（已发布的交付仍可领取，后继仍读最新一条）
    → 按可达性回收只在会话挂载中开启的 scope
    → 派生会话离开上游；上游属于 lifelong 的独立会话且已无读取方时，随之退役

生产任务可能停在业务 IO 里（等待下一份输入），所以停止用取消，与 lifelong 返回时的停止相同；退役在会话状态锁外进行。恢复未完成的退役不重试业务 close，scope 仍按既有状态执行一次关闭。interpreter 托管的 Derive 同样登记并撤销上游游标，供逐条交付和队列保留使用；普通有限 require 本身不登记订阅。托管会话不安装按读取方计数执行的退役动作，读取方归零也不提前停止，仍在 interpreter 退出时收尾。ReuseOutput 没有独立任务，计数归零不封口，仍按发布位置封口。lifelong 返回时逆序退役其余会话。失败与取消路径只离开、不退役，停止交给既有收尾；Derive 的生产任务失败时同样只离开上游，先报告监督。Derive 正常结束先封住自己的发布，再离开上游；只有满足上述 lifelong 边界与读取方条件的上游才随之退役，托管上游只撤销读取登记；异常收尾覆盖处理及离开的全过程，取消不会遗留上游读取登记。

**`require` 与订阅无关。** 读取方计数只统计领取交付的位置。`chained [A, D]` 中 A `endStream` 后，D 照常执行：D 有自己的订阅，自己驱动。D 若 `requests` A 链上的资产，由自己驱动生产；若只 `require` A 这一轮的普通产物，A 被跳过后按缺值规则报 `ContextNotInitialized`，确定失败，不挂起，也不读旧值。

**代价。** 节点结束后的读取关系重新计算每轮最多一次；发布位置在节点结束时立即撤下。会话的计数判断与离开同在一次 `release` 内，为 O(R)（R 为该会话的读取方个数）。本轮稳定检查沿已生成的单上游关系查询发布节点进度和派生完成水位，只在唤醒后重查，不轮询；新增完成计数不随发布总数分配存储。

**不变与未做。** 读取方的游标只描述领取进度，不替业务定义数据保留方式。已有 ownership 的交付保留见[资源边界](#binding-retention)；背压与容量、局部失败仍待设计。

<a id="implementation"></a>
## 10. 实现位置

| 内容 | 源码 |
| --- | --- |
| Stream typing、Context 声明 | [Registration.hs](../sdk/Framework/Language/Registration.hs) |
| 组合计算：访问权限、声明、lifelong 单元与订阅、持续连接、启动依赖、来源证明 | [Gen/Composition.hs](../sdk/Framework/Gen/Composition.hs) |
| 静态模型与自洽查询 | [Prototype/Types.hs](../sdk/Framework/Prototype/Types.hs)、[Prototype/Query.hs](../sdk/Framework/Prototype/Query.hs)、[Prototype/Validate.hs](../sdk/Framework/Prototype/Validate.hs) |
| 会话状态、交付、游标、读取方登记与保留范围 | [Session.hs](../sdk/Framework/Runtime/Session.hs) |
| 已知资源 Binding 的执行保留与撤销 | [Retention.hs](../sdk/Framework/Runtime/Retention.hs) |
| Derive 的推导、会话集合、生产步骤与上游游标的交接 | [Gen/Composition.hs](../sdk/Framework/Gen/Composition.hs)、[Runtime.hs](../sdk/Framework/Runtime.hs)（`DeriveSteps`）、[Session.hs](../sdk/Framework/Runtime/Session.hs)（`feedSession`）、[Execution.hs](../sdk/Framework/Runtime/Execution.hs) |
| ReuseOutput 的发布位置、挂接与单元结束封口 | [Gen/Composition.hs](../sdk/Framework/Gen/Composition.hs)、[Gen/Emit/Handlers.hs](../sdk/Framework/Gen/Emit/Handlers.hs)、[Context.hs](../sdk/Framework/Runtime/Context.hs)、[App.hs](../sdk/Framework/Runtime/App.hs)、[Execution.hs](../sdk/Framework/Runtime/Execution.hs) |
| 会话登记、Origin 清除 | [Graph.hs](../sdk/Framework/Runtime/Graph.hs) |
| 生产任务、DeliveryFrame、交付视图的交接 | [Runtime.hs](../sdk/Framework/Runtime.hs) |
| 视图读取、最新值投影（`latestContext`）、parser 输入、会话发布路由 | [App.hs](../sdk/Framework/Runtime/App.hs)、[Context.hs](../sdk/Framework/Runtime/Context.hs) |
| 单元调度、就绪检查、运行监督 | [Execution.hs](../sdk/Framework/Runtime/Execution.hs) |
| 根帧／轮帧与节点进度、scope 待用查询 | [Frame.hs](../sdk/Framework/Runtime/Frame.hs)、[Graph.hs](../sdk/Framework/Runtime/Graph.hs) |
| `StreamEnds`／`EndsStream` 能力类、绑定能力规则与标签实例 | [Handler.hs](../sdk/Framework/Language/Handler.hs)、[Gen/Composition.hs](../sdk/Framework/Gen/Composition.hs)、[Gen/Emit/Handlers.hs](../sdk/Framework/Gen/Emit/Handlers.hs) |
| 会话的已结束状态、排空与耗尽、共享唤醒、派生完成水位、读取方计数与退役完成协议 | [Session.hs](../sdk/Framework/Runtime/Session.hs) |
| 生产任务识别 `streamEnd`、Derive 识别 `endStream`、会话退役动作、单元结束通知 | [Runtime.hs](../sdk/Framework/Runtime.hs)、[App.hs](../sdk/Framework/Runtime/App.hs) |
| 单元正常结束、节点订阅结束、单元离开会话、发布位置撤下、并行汇合、lifelong 返回 | [Execution.hs](../sdk/Framework/Runtime/Execution.hs) |
| lifelong 的正常出口与后继读取的拒绝 | [Gen/Composition.hs](../sdk/Framework/Gen/Composition.hs) |
| 生成的读取方法与路由、Stream 入口的会话包装、`Raw` 实例、会话步骤登记 | [Gen/Emit/Handlers.hs](../sdk/Framework/Gen/Emit/Handlers.hs)、[Gen/Emit/Program.hs](../sdk/Framework/Gen/Emit/Program.hs)、[App.hs](../sdk/Framework/Runtime/App.hs)（`emitToParser`、`emittedInput`） |

ScopeTree 独立构建并保持无环；订阅与回调关系不作为 scope 父边。运行时不累计完整方法调用历史或无限 workflow 结果。

<a id="deferred"></a>
## 11. 验证与延期

本仓库按约定只做普通编译、生成结果审阅和示例观察，不新增测试框架、负例或穷举门槛。现有验证的边界见 [Next stages](NEXT_STAGES.md#current-limits)，逐次观察记录保留在 Git 历史。LSP 仓库的外部穷举模型尚未扩展到 Stream／lifelong。

当前缺口统一记录在 [Next stages 的限制与开放专题](NEXT_STAGES.md#current-limits)。持续值参数、既有 ownership 的交接与会话实例的待用回收已接通；保留范围以[资产契约](#binding-retention)为界。容量背压与嵌套 workflow 分列为后续专题。已有单步来源的写法见[第 4.1 节](#drives)，不据此宣称已提供通用外部回调适配。
