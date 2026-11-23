# Stream 与 lifelong：资产驱动的自动装配

本文通过引用构成[主设计第 7 章](CORE_DESIGN.md#stream)的完整规范。主设计负责架构地图，本页唯一维护 Stream 的匹配、交付和调度规则；实施记录在 [Next stages](NEXT_STAGES.md)，写法示例在[使用指南第五节](GUIDE.md#stream)。SDK 没有流操作 API，各种流行为由组合推出；按行为列出的组合、运行时的分支依据，以及为方便理解给出的粗略类比，见[组合推导第 6 节](COMPOSITION.md#stream)。

更新：2026-11-24。闭包模型：lifelong 是交给 gen 的标记，发布即同步回调，没有会话与等待（[第 4 节](#bootplan)、[Next stages](NEXT_STAGES.md#closure-model)）。驱动方式的组合见[第 4.1 节](#drives)，生产侧结束见[第 9.4 节](#end)，消费侧结束见[第 9.5 节](#consumer-end)，历史保留见[第 7.1 节](#retention)。阶段状态和剩余缺口统一见 [Next stages](NEXT_STAGES.md#stages)。

本文手工记录 Stream、Context 与 lifelong 的匹配规则，作为代码生成、解释器和开发文档共同遵守的规范。输出复用、后继待用及来源结束均按下文现行规则解释；标明“延期”或“临时”的部分不扩展为最终保证。

## 1. 目标：让原子方法独立于装配知识

业务作者按已经生成的类型和原生 Haskell 编写一次取得、一次解析或一次消费。SDK 根据注册、handler 的读取结构、资产和 AST 控制关系，自动生成生产、解析、交付和 target boot 的连接：

    声明与可提取的读取结构
    → 检查匹配前提
    → 生成唯一装配及其依据
    → interpreter 执行已经装配的闭包

业务作者需要知道本地输入输出、`require`、`rawinput`、`raise`，Stream handler 报告来源结束的 `streamEnd`，以及消费方不再消费时的 `endStream`，不需要知道 BootPlan 或生成的回调表。

自动装配只依赖明确契约，不从任意 IO 恢复作者意图。匹配不成立时生成期诊断，不按方法名相似度、运行速度或最后写入猜选。原子化约束保证组合可观察，不证明任意方法体足够细、无副作用或必然返回。

AST branch 继续规定何时、按何种顺序、选择哪些入口以及是否重复 boot。业务组合写在注册与 AST 中，AST 不成为业务值 pipeline。程序入口保持 `interpreter ast effects`。

## 2. 术语与职责

| 结构 | 职责 |
| --- | --- |
| Stream effect | 第六种 typing；绑定的 handler 通过 `rawemit :: String -> m ()` 逐条提供原始输入，只由 lifelong 的 `Drive` 或 lifelong 外的静态运行调用；来源没有下一份输入时以 `streamEnd` 结束（[9.4](#end)） |
| parser | Context 绑定的 handler：用 `rawinput` 读取 Stream 本次取得的输入或原子句柄本次交出的输出，返回表示类型的值 |
| Context.stream | `True` 声明持续资产，它的 Input 链被持续驱动（挂在 Stream 下，或链上有 `streams` demand），且须同时 `require = True`；挂在 Stream 下而声明 `False` 的是 behavior（[第 4.1 节](#drives)） |
| Context.require | `True` 缓存最新值；读取已有绑定或交付视图，不生产，不等待；缺值立即报 `ContextNotInitialized`（[Context](CORE_DESIGN.md#context)） |
| 持续资产 | `stream = True` 的资产；每次发布保持声明的表示类型，读取是否带来重复执行由组合关系决定 |
| `streams "T"` | 声明以资产 T 的新交付驱动，同时取得读取权限；不是调用 parser 的语法。声明它的 effect 在 lifelong 挂载的消费链上，或在另一份持续资产的生产链上 |
| lifelong | 交给 gen 的标记：其单元是驱动资产每次发布后同步执行的回调；驱动方式由组合决定（socket、behavior、event），lifelong 之外的持续资产读取是 history |
| BootPlan | 生成器从生产方注册及本 lifelong 的挂载推导的生产连接：Receive、Derive 或 ReuseOutput，不是手写标签 |
| 回调 | 资产发布后在发布者调用栈里同步执行的闭包：lifelong 的单元，或派生的 parser 链 |
| publication | 一次成功发布；保留值、出身和共享归属引用 |
| 单元 | lifelong 的直接子项；驱动资产每发布一次执行一次 |
| frame | 一次回调的执行帧：交付视图与固定捕获 |

Stream 不进入 original chain，也不作为 AST target；它由 lifelong 的 `Drive` 或静态运行调用。original target 代表一条完整消费链的末端，其中有限执行的 Excu／Scoped 可以消费上游资产，同时把本次输出交给挂接的 Context 发布新资产。Stream 不向 AST 返回 Succ，它的结束由 `Drive` 观察；这不限制消费节点本身的产值。

socket、history、behavior、event 是同一组声明元素在不同组合下的四种驱动方式，由 gen 判定，见[第 4.1 节](#drives)。挂在 Stream 下的 Context 与挂在原子句柄下的 Context 写法相同：parser 用 `rawinput` 取得本次输入。

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
| `getT` | 执行 parser 并包装发布一个资产；来源每 `rawemit` 一次调用一次 |
| `streamT` | `require @T` 经类型路由读取固定交付的当前元素 |
| `historyT` | `stream @T` 经类型路由读取同一交付的 `Flow` 视图 |

Stream handler 每调用一次 `rawemit text`，SDK 就把 `[text]` 同步交给挂接的 parser。parser 的 `rawinput` 读这一份输入。一次 handler 调用可以多次交付，正常返回后生产循环才进入下一步。首次生成契约后即可编写两个 handler。

同一 refined asset 的所有访问方式共享固定表示 ADT 和唯一 Context 来源；读取的返回形态不同，不会产生第二种资产身份。声明与读取依据统一见[主设计：资产来源与访问约束](CORE_DESIGN.md#demand-contract)，包括 streams 在 Prototype 中的交付依据。

### 3.2 Context 声明的匹配表

持续资产的声明由 Context 自己的注册决定。`stream` 必须与它的 Input 链一致：Input 链上某个 effect 声明了 `streams` 时要求 `stream = True`；直接 input 是 Stream 时，`True` 是 socket／history 的持续资产，`False` 是 behavior。具体生产连接再结合本 lifelong 的 AST 挂载确定：来源单步、独立派生，或沿用消费节点的原子输出，见 [第 4 节](#bootplan)。

| Context 的 Input 链 | stream | require | 结果 |
| --- | --- | --- | --- |
| 直接 input 是 Stream | `True` | `True` | 持续资产，Receive：Stream 单步＋parser |
| 直接 input 是 Stream | `False` | `True` | behavior，Receive：相等的值只发布一次，读取方取最新一条（[第 4.1 节](#drives)） |
| 直接 input 是 Stream | `False` | `False` | 报错：behavior 需要 `require = True` |
| 链上有 `streams "U"`（恰好一份资产） | `True` | `True` | 持续资产：已有合法 AST 发布位置时 ReuseOutput，否则 Derive |
| 链上有 `streams "U"` | `False` | 任意 | 报错：被持续资产驱动的链每次交付产出一个值，须声明 `stream = True` |
| 链上的 `streams` 指向多份资产 | 任意 | 任意 | 报错：一条生产链只由一份资产驱动 |
| 直接 input 是 Stream，它的 Input 链上又有 `streams` | 任意 | 任意 | 报错：Stream 自己驱动，它的 Input 链不能再订阅 |
| 没有 Stream，也没有 `streams` | `True` | 任意 | 报错：没有持续驱动，不能声明 `stream = True` |
| 没有 Stream，也没有 `streams` | `False` | 任意 | 普通单值资产 |
| 以上任一持续资产 | `True` | `False` | 报错：`stream = True` 需要 `require = True` |

另外：Context 必须声明 parser；Stream 必须声明 handler；以 Stream 为 input 的必须恰好是一个 Context（它的 parser），其他 effect 不能直接取得原始输入。持续资产与 behavior 在 lifelong 内由回调交付，lifelong 外由 `requests "T"` 同步运行到结束（见[lifelong 外的读取](#finite-read)）。Stream 下的 parser 不把 Stream 当作前驱执行；挂在原子句柄下的 parser 用 `rawinput` 取得句柄输出，注入时由同次输出回答，不再执行句柄；挂在原子句柄下的 Context 不声明 demands（[输出联立](CORE_DESIGN.md#request-production)）。

### 3.3 消费权限与读取类型

资产表示类型由 Types.hs 与 Context 的声明确定。消费方在 demands 中写资产名，handler 按表示类型写 `require @T` 读取本次增量；以 `streams` 读取持续资产的 handler 还可以写 `stream @T` 读取 x:xs（见下文[按 x:xs 读取](#flow)）：

| 注册 | `require @T` | `stream @T` | 驱动关系 |
| --- | --- | --- | --- |
| `streams "Asset"` | 本次交付的 T | `x :> xs`：本次交付及更早的交付 | 在 lifelong 原始消费链或持续 Context 生产链上，由该资产的发布回调 |
| `requires "Asset"` | 本次已捕获的 T；尚未捕获时取运行级最新值，没有就报缺值 | 不提供 | 只读取，不驱动；lifelong 内是采样 |
| `requests "Asset"` | 不授予读取，与 `requires` 一起写 | 不提供 | lifelong 外：持续资产与 behavior 同步运行来源到结束，取静态历史；普通资产执行生产链。lifelong 内：behavior 与普通资产是订阅（behavior、event），不能 `requests` 持续资产 |

同一资产可声明多种访问方式；它们给出同一个表示类型和读取路由，不产生重复 Reads 实例。只有 Excu、Scoped 可以声明 streams；behavior 不能被 `streams` 订阅。

**生产持续性与消费重复性分别计算。** A 的 Input 链订阅 B 时，A 可以继续随 B 的新交付生产；普通链 C 只 `requires` A，就只取得一次确定的值。A 不需要额外挂入 AST 的 lifelong，C 也不因读取 A 而变成 lifelong。C 若要随 A 的新交付反复执行，仍按既有规则在 lifelong 中声明 streams。普通 Context 生产链同样可只 require 持续资产并发布一次普通产物。

`T` 遵循[资产表示类型的固定形式](ASSETS.md#fixed-form)。一次调用捕获一个 Binding，随后发布的新值只对后续捕获可见。

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

- **`x` 是本次，`xs` 是过去。** `x` 与同一调用中 `require @T` 取得的元素相同。`xs` 从新到旧列出这份资产在 `x` 之前已发布的元素，以 `Done` 收尾。`Done` 表示已读到这段历史的起点。来源从未发布就 `streamEnd` 时，订阅方不会收到一次内容为 `Done` 的交付。
  例如依次发布 `a`、`b`、`c`，处理 `b` 的调用读到 `b :> a :> Done`。即使 `c` 已经发布，该调用再次读取的仍是同一前缀。
- **历史边界。** lifelong 内（socket）历史从这次 `Drive` 的第一条发布算起，`Drive` 结束时放掉，最新一条保留给后继。lifelong 之外的静态运行（history）保留整段到运行结束，之后的 `stream @T` 仍读到整段（[第 4.1 节](#drives)）。
- **保留条件由 gen 计算。** `streams "T"` 决定 handler 可用的能力。gen 从方法体中的 `stream @T` 找到实际读取历史的资产，并在对应 Context 的原型上标记 `effectHistory = True`。只用 `require @T` 读取本次值不产生这个标记。见[保留范围](#retention)。
- **refine 在元素上。** 契约仍生成 `newtype TextLine = TextLine Line`；`Flow` 的参数是 representational 角色，生成的 `Streams` 实例直接把 `Flow TextLine` `coerce` 成 `Flow Line`。
- **空间与边界。** 标记了历史读取的资产保留已发布前缀。非终止来源的这部分存储会随发布次数增长，读取方只取五条也一样。窗口与容量另行设计。

### 3.4 原子输入与源码约束

Stream handler 类型为 `m ()`。每次 `rawemit text` 都同步执行挂接的 Context parser，parser 用 `rawinput` 读到 `[text]`，成功发布并执行完回调后来源方法继续。一次调用可以交付零条、一条或多条。来源正常返回时 `Drive` 再调用一次。前驱和 `requests` 按来源调用执行，详见[来源结束](#end)。

Excu／Scoped 交出的 `[String]` 是原子句柄的输出，不能把空 list 释为 EOF。来源的结束只由 Stream handler 用 `streamEnd` 报告，见 [9.4 节](#end)。

<a id="bootplan"></a>
## 4. 生产方式（BootPlan）

lifelong 是交给 gen 的标记，不是运行中的服务（用户确认，2026-11-24）。gen 把每个 lifelong 翻译成两样东西：workflow 闭包中的一个 `Drive` 位置，以及回调表里的若干条“资产发布之后执行什么”。运行时没有会话、交付队列、游标或消费线程，所有执行都在某个发布者的调用栈里同步发生。总览见 [Next stages：闭包模型](NEXT_STAGES.md#closure-model)。

| BootPlan | 静态依据 | 生成的闭包 |
| --- | --- | --- |
| Receive | Context 的直接 input 是 Stream | `Drive` 带一个 `StreamSource`：反复调用 Stream 方法，每次 `rawemit` 在来源的调用栈里执行 parser 并发布 |
| Derive | Context 的 Input 链上有 `streams "U"`，本 lifelong 没有可复用的 AST 发布位置 | 回调表里一条 `U → RunDerive`：U 每次发布后，在派生挂载上执行 parser 及其被驱动的 Input 链，成功则发布 |
| ReuseOutput | 同一 lifelong 已有 AST 位置执行 Context 所挂接的原子句柄 | 不另生成步骤：原子句柄成功后，`atomicScope` 执行挂在它下面的 parser 分支并发布（[输出联立](CORE_DESIGN.md#output-links)） |

event 没有 BootPlan：lifelong 内的 target 以 `requests` 订阅普通资产时，回调表里一条 `T → RunUnit`，T 不论从哪里发布都回调。behavior 是 Receive，比较函数写在生成的 `StreamSource` 里。

**统一驱动规则：发布即回调。** 资产每发布一次，`Graph.react` 在发布者的调用栈里依次执行回调表中对这份资产仍然有效的回调，全部返回后发布者才继续。来源的下一次 `rawemit`、锚点之后的 workflow 后继，都要等本次回调完成。运行时不判断值将来会不会来，读取不等待。

不成立的组合在生成期按 3.2 的匹配表报错，不在运行中猜测或退化为轮询。

<a id="drives"></a>
### 4.1 驱动方式的组合：socket、history、behavior、event

SDK 没有流操作 API。持续执行的驱动方式由三个声明元素的组合决定（用户确认，2026-11-24）：

- **S**：资产的 Context 挂在 Stream effect 下；
- **A**：资产声明 `stream = True`；
- **L**：消费的 target 挂在 lifelong 内。

判定的单位是“（资产，消费位置）”：同一份资产可以在一处是 socket，在另一处是 history。

| S | A | L | 驱动方式 | 消费方写法 | 生成的闭包 |
| --- | --- | --- | --- | --- | --- |
| ✓ | ✓ | ✓ | socket | `streams "T"` | `Drive` 运行来源；每次 `rawemit` → parser 发布 → 回调订阅单元，不去重；`Drive` 结束时放掉历史 |
| ✓ | ✓ | ✗ | history | `requests "T"` 加 `streams "T"`（或 `requires "T"`） | 第一次 `requests` 在当前位置同步运行来源到 `streamEnd`；`stream @T` 读整段，`require` 读最后一条；历史保留到运行结束 |
| ✓ | ✗ | ✓ | behavior | `requests "T"` 加 `requires "T"` | 同 socket，但与上一次回调的值相等时不回调 |
| ✓ | ✗ | ✗ | behavior 采样 | `requests "T"` 加 `requires "T"` | 同 history：来源运行到结束后读最新值 |
| ✗ | ✗ | ✓ | event | `requests "T"` 加 `requires "T"` | T 的每次发布（[输出联立](CORE_DESIGN.md#request-production)、其他 `requests`）都同步回调订阅单元，不去重，不回放此前的发布 |
| ✗ | ✗ | ✗ | 普通请求 | `requests "T"` 加 `requires "T"` | 执行 T 的生产链一次（[requests 剧本](CORE_DESIGN.md#request-production)） |
| ✗ | ✓ | 任意 | 非法 | — | 没有持续驱动不能声明 `stream = True`（Input 链上有 `streams` 的 Derive 除外，它按 socket 回调） |

lifelong 内 `requests` 普通资产或 behavior 是订阅，驱动 target；lifelong 内不能 `requests` `stream = True` 的资产，订阅它写 `streams`。`requires` 只读当前值，不驱动。一个单元恰好由一份资产驱动。

**代码长什么样。** 以下是写法示例（不在 demo 中），注册、handler 与 workflow 的形态都是现行接口：

```haskell
-- Effects.hs：behavior 挂在 Stream 下，stream = False
EffectSpec { name = "Sensor", typing = Stream { handler = Just "sense" }, input = "Root", demands = [] }
EffectSpec { name = "LevelParser"
           , typing = Context { asset = Asset @Level "SensorLevel", parser = Just "parseLevel", require = True, stream = False }
           , input = "Sensor", demands = [] }
EffectSpec { name = "ShowLevel", typing = Excu { handler = Just "showLevel" }, input = "Root"
           , demands = [requests "SensorLevel", requires "SensorLevel"] }
-- event：普通资产，锚点 Tick 在任何位置执行都发布一次
EffectSpec { name = "Tick", typing = Excu { handler = Just "tick" }, input = "Root", demands = [] }
EffectSpec { name = "TickParser"
           , typing = Context { asset = Asset @Count "TickCount", parser = Just "parseTick", require = True, stream = False }
           , input = "Tick", demands = [] }
EffectSpec { name = "Watch", typing = Excu { handler = Just "watch" }, input = "Root"
           , demands = [requests "TickCount", requires "TickCount"] }
-- history：stream = True 的资产在 lifelong 之外读取
EffectSpec { name = "ReadAll", typing = Excu { handler = Just "readAll" }, input = "Root"
           , demands = [requests "FeedItem", streams "FeedItem"] }

-- AST.hs：event 不需要 parallel，lifelong [Watch] 只是登记回调
ast = chain
  [ lifelong [chain [node "Watch"]]
  , chain [node "Tick", node "Tick", node "Tick", node "Tick"]
  , lifelong [chain [node "ShowLevel"]]
  , chain [node "ReadAll"]
  ]

-- Handlers.hs：lifelong 内的 behavior／event 订阅方同样有 endStream
instance WatchLayer m => WatchHandler m where
  watch = do
    Count count <- require @Count
    if count == "3" then endStream else rawoutput []
```

每次 `Tick` 成功后，`TickCount` 发布，`Watch` 在 `Tick` 的调用栈里执行一次，返回后才轮到下一个 `Tick`；第三次 `Watch` 调用 `endStream`，第四次 `Tick` 不再回调。`Sensor` 依次 `rawemit` `1 1 2 2 2 3 3` 时，`ShowLevel` 只回调 `1`、`2`、`3`。`ReadAll` 在来源结束后读到整段 `c :> b :> a :> Done`。

- **event 的回调读交付。** 回调把交付的资产记为本次执行已发布，target 入口里这份资产的 `requests` 生产链（锚点与 parser）由 `unlessPerformed` 跳过，`requires` 读交付本身；挂在 lifelong 之外时照常生产。
- **回调环。** 回调的执行（target、Input 链、`requests` 的传递闭包、输出联立、派生）可能再次发布它订阅的资产时，回调会无限递归。gen 在“资产 → 回调可能发布的资产”图上查环并拒绝；回调交付的资产不计入回调自身 `requests` 的闭包。检查按注册保守计算，不区分条件分支。
- **event 的有效期。** event 回调整次运行有效，直到订阅方 `endStream`。没有来源要运行，`Drive` 位置什么也不做，lifelong 不阻塞后继。
- **behavior 的去重** 比较本次与上一次回调的值（资产类型固定 `deriving (Eq, Show)`），相等时不回调。
- **history 的保留** 只针对 lifelong 之外的静态运行。lifelong 内的 socket 在 `Drive` 结束时放掉历史，最新值保留给后继。
- 节奏只由 Stream handler 的阻塞或等待决定，SDK 不加间隔。回调返回前来源不会产生下一条，慢回调就是慢来源，没有积压。
- 外部 push callback 不能直接注册给 SDK，需要先转换成可阻塞读取的队列，再作为单步来源；通用回调适配本版延期（见第 11 节）。
- StreamDemo 的温度与心跳是两个独立来源，写成 `parallel` 的两个 lifelong。LinesDemo 在一次来源调用内逐行 rawemit。

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
    ast = chain [chain [node "Announce"], monitorLines, chain [node "Report"]]
    monitorLines = lifelong
      [ chain [node "PrintLine", node "TextCounter"]
      , chain [node "ShowTotal"]
      ]

每读到一行，来源 `rawemit` → `TextLine` 发布 → 回调第一个单元：打印并执行 `TextCounter`。`TextCounter` 成功后，`atomicScope` 执行挂在它下面的 `CountParser`，`RunningTotal` 发布 → 回调第二个单元 `ShowTotal`。这一切都在来源的同一次 `rawemit` 里完成，所以每行之后紧跟着它的累计。原子方法仍然不知道它的输出将由谁消费。

**为什么产出声明为持续资产。** 链上有 `streams` demand，执行机会来自那份资产的发布，连续成功执行会产生一串增量。`stream = True` 把这个结构关系写在源码里；写成 `False` 由生成期拒绝。发布只发生于实际执行且成功解析的位置，alternative 未选中的位置不发布。

**规则。**

- **已有 AST 执行**：gen 在同一个 lifelong 内沿 target 自身及 original Input 链确定 Context 所挂原子句柄的发布位置，写入 `ReuseOutput [NodeId]`。原子入口成功后执行挂接的 parser，`rawinput` 由本次输出回答，parser 继承原节点的 Origin、执行帧和 ScopeUser。
- **独立派生**：没有上述 AST 发布位置时使用 Derive。上游每发布一次，回调在派生挂载上执行 parser 及其 Input 链，成功后发布一条，同步回调派生资产的订阅方。可以继续逐级派生。被驱动链 `endStream` 后，这条派生不再回调。
- **来源与驱动**：一条派生链只由一份持续资产驱动。一个单元只由一份资产驱动。
- **失败**：parser 或回调失败沿发布者的调用栈返回，最终结束整次运行（[9.1](#failures)）。已完成操作与之前的发布不回滚。
- **普通副产物**：原 AST 调用的普通发布写入运行级最新值，回调的单元按运行级最新值读取。
- **不提供**：手写跳过出口、多份持续资产合并驱动一条链、缓冲策略与窗口。

<a id="static"></a>
## 5. 静态结构与合法性

### 5.1 消费摘要

每个挂载的 target 的订阅只看 original chain 自身：末端 effect 及其 Input 祖先声明的 streams demand，或在 lifelong 内 `requests` 的 behavior／普通资产。

### 5.2 lifelong 合法性

1. lifelong 内每个单元恰好由一份资产驱动：`streams` 一份持续资产（socket），或 `requests` 一份 behavior 或普通资产（behavior、event）。Scoped 请求的资源 Context 是开启输入，不算订阅。
2. 一个 lifelong 至多一个 Stream 来源（Receive）。多个独立来源写成 `parallel [lifelong [...], lifelong [...]]`：参照 Effect-TS，并发须显式写出。
3. lifelong 内不能 `requests` `stream = True` 的资产；那是 lifelong 外的静态历史，订阅写 `streams`。
4. 回调图无环（[4.1](#drives)）。
5. 只有 `requires` 的末端没有驱动，不能进入 lifelong；一次性准备放在外部 chain。lifelong 之外的 `streams` 必须同时 `requests` 同一份资产（history）。
6. Stream、Context 不作为 target，Stream 也不能进入 original chain。
7. lifelong 不嵌套；lifelong 内不能有空分支。

这些检查不证明任意原子 IO 能够返回。gen 不再做读取可达性证明：`require` 只要求资产有来源（被 `requests`、挂在锚点下或是持续资产），运行时读不到值立即报 `ContextNotInitialized`。

### 5.3 原型中的表示

lifelong 写入统一 Prototype：

    LifelongAt NodeId LifelongProto [WorkflowTree]

    LifelongProto
      { lifelongUnits         :: [NodeId]            -- 单元：规范形式中的直接子项
      , lifelongSubscriptions :: [(NodeId, String)]  -- 每个挂载 target 订阅的资产
      , lifelongSessions      :: [SessionProto] }    -- 本 lifelong 的持续资产及其生产方式

    SessionProto { sessionAsset :: String, sessionPlan :: BootPlan, sessionMounts :: [NodeId] }
    BootPlan = Receive String | Derive String | ReuseOutput [NodeId]

- 生产挂载 NodeId 为 lifelong 路径加 `[-1, 序号, 步骤]`：Receive 的步骤 0 是 Stream 方法、步骤 1 是 parser；Derive 只有步骤 0（parser）。挂载参与构图与 ScopeTree。ReuseOutput 没有挂载，沿用 AST 位置。
- lifelong 外 `requests` 持续资产的静态运行挂载为 `[-2, 序号, 步骤]`。
- 名字里的 Session 是历史命名，表示“一份持续资产的生产方式”，运行时没有对应的会话对象。
- `Generated/Program.hs` 的 `compiledProgram` 由这些计划生成：`compiledWorkflow`、`compiledReactions`、`compiledStatic`。运行时执行它们，不再遍历 Prototype 的编排。
- `--structure` 在 Workflow 中列出每个 lifelong 的单元、持续资产（生产方式与挂载）和订阅。

<a id="scheduling"></a>
## 6. lifelong 的回调与控制流

### 6.1 单元划分

lifelong 的每个直接子项形成一个单元，单元是它的驱动资产每发布一次就执行一次的回调。单元内部是有限子树，parallel 在其中只是一次回调之内的并发。

    lifelong [chain [a, b], c]

得到回调 `chain [a, b]` 和回调 `c`。驱动资产不同时，各自在自己的资产发布时执行；同一份资产驱动两者时，按声明顺序先执行完 `chain [a, b]` 再执行 `c`。

### 6.2 lifelong 位置做什么

| lifelong 的内容 | 执行到 `Drive` 时 |
| --- | --- |
| 有 Stream 来源（socket、behavior、派生、复用输出） | 同步运行来源：来源方法正常返回就再调用一次，直到 `streamEnd`，或它驱动的单元全部 `endStream`；然后放掉本 lifelong 持续资产的历史，返回 Succ |
| 只有 event 订阅 | 立即返回；回调已登记，整次运行有效 |

来源运行期间，本 lifelong 的 socket、behavior 与派生回调有效；`Drive` 返回后失效。永不结束的来源使 `Drive` 不返回，后继不执行，与 StreamDemo 一样由业务负责。

### 6.3 一次回调

- 每次回调是单元的一次执行，在新的子执行帧里运行；交付的绑定和发布者已捕获的普通绑定作为固定捕获交给单元。
- 持续资产的回调另带到本条为止的历史，`stream @T` 读它。
- 单元的节点调用 `endStream` 后，这个节点之后不再执行；节点全部结束时，单元不再回调。
- 单元之内同一 `requests` 生产链不重复执行：交付的资产已记为发布。

### 6.4 外部组合

| 写法 | 行为 |
| --- | --- |
| `parallel [monitor, otherWork]` | 两者同时运行 |
| `chain [setup, monitor]` | setup 成功后进入 monitor |
| `chain [monitor, after]` | 有来源时 after 等 monitor 的来源结束；只有 event 时 after 立即执行，回调随 after 中的发布执行 |
| `parallel [lifelong [...], lifelong [...]]` | 两个独立来源并发运行 |

<a id="sessions"></a>
## 7. 交付、历史与执行帧

| 状态 | 归属 |
| --- | --- |
| 运行级最新值 | 每份资产一条，按发布覆盖 |
| 历史 | 原型带 `effectHistory` 的持续资产：本次运行中的发布序列；socket 在 `Drive` 结束时放掉，静态运行保留到运行结束 |
| 回调的固定捕获 | 一次回调的执行帧 |
| target 执行 | NodeId＋新的 Origin |
| 来源与 parser 的执行 | 生产挂载 NodeId＋每步新的 Origin；ReuseOutput 沿用原 AST 执行 |
| scope 归属 | 既有 Binding ownership 与具体 scope 实例 |

<a id="retention"></a>
### 7.1 保留多少发布

- 每份资产保留运行级最新值。
- 只有 gen 标记了 `effectHistory`（方法体里有 `stream @T`）的持续资产保留历史；socket 的历史在 `Drive` 结束时放掉，静态运行的历史保留到运行结束。
- 没有交付队列，也没有积压：回调返回前来源不会发布下一条。
- 调用已经取得的视图仍然有效。资源待用与 scope 开启按本次 Binding 的生产身份判断。向前遍历历史只读过去的业务值，不会为旧交付重新登记 scope 使用。

<a id="retention-cost"></a>
### 7.2 时间复杂度

N 为保留的历史条数，K 为对一份资产有效的回调数。

| 操作 | 代价 |
| --- | --- |
| 发布一条 | O(log N) 追加历史，加上依次执行 K 个回调本身 |
| `require @T` 读已经捕获的值 | 不随历史长度增长 |
| `stream @T` | 取得视图不复制；业务逐个访问历史元素 |

资源保留匹配、scope 回收和业务值的解析不在此列。历史随标记资产的发布次数增长；窗口与容量另行设计。

<a id="production"></a>
## 8. 生产与普通读取

### 8.1 生产路径

    Receive：调用来源 → 每次 rawemit 同步执行 parser 并发布 → 回调 → 继续当前方法 → 正常返回后再调用一次
    Derive：上游发布 → 回调在派生挂载执行 parser 与被驱动的句柄，发布一次 → 回调
    ReuseOutput：原 AST 位置执行原子句柄 → 挂接 parser 读取本次原始输出并发布一次 → 回调 → 原 workflow 继续

Receive 在交出原始输入时，也把同一步来源执行已捕获的资源 Binding 交给 parser；parser 的短期 ScopeUser 继承来源实际使用的实例，以保留父子 scope 关系。来源与每次 parser 分别登记使用，本步结束后撤销。资源与开启参数仍按[既有 scope 规则](CORE_DESIGN.md#scope)区分。

每次回调建立独立的子执行帧。参数来自外层或没有参数的 scope 由外层帧保留；参数来自本次回调的实例归本次，结束且没有合法后继待用时回收。具体规则见[图与来源](EFFECT_GRAPH.md#scope-opening-retention)。

<a id="finite-read"></a>
### 8.2 lifelong 外的读取

普通 `requires "T"` 只读一次：本次调用已捕获的值，或运行级最新值；都没有时立即报 `ContextNotInitialized`，不等待。

lifelong 外 `requests` 一份持续资产（history、behavior 采样）就是要一份静态历史：第一次 `requests` 在当前位置同步运行根来源（及派生链）直到 `streamEnd`；之后 `requires` 读最后一条，`streams` 的 `stream @T` 读整段。同一根来源在一次运行中只运行一次，并发的请求方等这一次运行结束；历史保留到运行结束。没有边读边执行。

- 已经运行过的 lifelong 留下的最新值，按普通读取规则可读；静态运行与 lifelong 内的同一来源是两次独立运行。
- 一条都没有发布就结束时，读取报 `ContextNotInitialized`。
- 收尾、诊断与 close 期间不启动静态运行。

<a id="execution-boundaries"></a>
### 8.3 模块边界

| 职责 | SDK 落点 |
| --- | --- |
| 确定单元、订阅、生产方式、拒绝多来源与回调环 | Gen.Booter、Gen.Composition |
| 生成 workflow 闭包、回调表与静态运行 | Gen.Emit.Program；入口里的输出联立与 `unlessPerformed` 由 Gen.Emit.Handlers 生成 |
| 发布后执行回调 | Runtime.App（`publishBinding`）、Runtime.Graph（`react`） |
| 执行闭包、运行来源、静态运行、behavior 比较 | Runtime.Execution（`runCompiled`、`runSource`、`staticRun`、`reactTo`） |
| 执行帧、scope 待用与回收 | Runtime.Frame、Retention、Graph、Scope |

`streamEnd`、`endStream`、正常返回和失败不合并成同一种结果。

<a id="failures"></a>
## 9. 故障、取消与资源边界

### 9.1 失败：临时规则

现有资源回收已接通；局部失败恢复尚未实现，继续采用下面的临时规则：

1. **适用范围**：只在 AST 中包含 lifelong 时生效；不包含 lifelong 的程序，失败处理保持现状。
2. **触发**：来源失败、解析失败、回调失败、AST 中任何 node 或 alternative 选择读取的失败，以及上述执行中的原生异常。回调的失败沿发布者的调用栈返回。
3. **处理**：结构化 Failure 先完成既有 Error 协议的诊断与处置，原生异常直接通知运行监督。随后终止整次运行：停止启动新工作，取消全部任务（运行中的来源、执行中的 target 与回调、其他并行分支）并等待受控收尾，走 interpreter 退出清理；结构化失败报告最初的 `Failed`，原生异常重新抛出。
4. **不做**：不只终止局部的 lifelong，不让外层 chain 继续执行后继，不重试。

失败在发生处直接通知运行监督，因此 `parallel [monitor, otherWork]` 中 otherWork 的失败不会因永不结束的 monitor 而被吞掉。

### 9.2 取消

外部取消（Ctrl-C）时，SDK 取消 AST 中的全部任务并等待其受控收尾。来源与回调都在 AST 任务的调用栈里执行，随之取消。最后由 interpreter 按 ScopeTree 关闭剩余资源。关闭失败（`raise` 或 close 中的普通 IO 异常）单独汇总，不改变原业务结果，也不重试。Ctrl-C 等取消在其余收尾后重新抛出；取消发生在同步 close 中也停止后续启动，不能降为仅报告的关闭失败。

lifelong 外的静态运行在取消或抛出原生异常时也填入结果，并发等待同一次运行的请求方不会悬挂。任务能否退出仍依赖业务 IO 响应取消、诊断与收尾能够返回。

<a id="binding-retention"></a>
### 9.3 已知资源的保留与 close 边界

不新增 Stream close、next-use 或业务集合按元素关闭协议。暂时没有输入不表示结束、故障或关闭；来源由 Stream handler 的 `streamEnd` 报告结束，Derive 随上游的 `Drive` 结束或被驱动链的 `endStream` 停止回调（9.4、9.5）。

**保证范围（2026-11-18 修订）：** 保留实际执行、持续待用和已有 Binding ownership 能定位的资源；注册指定的资源 Context 在认领前也保持同一归属单元。Context／Pure 把本次原子输出解析或变换成普通业务数据，不因此让新 ADT 继承生产方法用过的全部资源。资产、注册、handler 与 workflow 写法不变；保活不让链外资源读取变得合法；普通共享供值遵循独立的 Context 协议。

**资产契约的边界。** 原子操作交出 `[String]`，Stream 每次交出一个 `String`，Pure 可以变换原始字段，Context 将其解析成业务资产。`Types.hs` 的字段遵循[资产固定形式](ASSETS.md#fixed-form)。已声明资源的寿命由 SDK 跟踪其 Binding 的 ownership，历史中可读取的字符串描述本身不会延长资源的寿命。

| 持有者 | 保留到什么时候 |
| --- | --- |
| Receive 的来源与 parser、Derive 的本次处理 | 本步的业务、诊断和受控结果消费结束；来源在本次调用内持续持有，parser 的使用在该条解析完成后释放 |
| 回调单元在根帧里的未来位置 | 来源驱动的单元到 `Drive` 结束；event 单元到运行结束 |
| 一次回调的固定交付 | 本次回调内部全部受控执行结束，包括失败及取消收尾 |
| Derive 的一次回调 | 本次解析与发布结束；新产物只保留自己已有的 ownership，不推断内嵌字段 |
| 有限调用取得的固定值 | 调用、诊断和受控结果消费结束；alternative 的选择捕获保留到所选候选结束 |
| 合法后继可读的最新绑定 | 仍有执行帧待用；值被新发布替换、位置完成或跳过后重新判断 |

历史读取取得的 `x :> xs` 中，只有本次的 `x` 是当前交接的 Binding 和 scope 开启参数。`xs` 仍可读作历史数据，不保留其中的资源。

读取在 scope 关闭预约的共同协调锁内先登记保留，再返回值。撤销执行保留或替换旧绑定后，在锁外按原 owner 和其 ScopeTree 祖先调用现有回收器。冻结的 cleanup 快照不成为实例自己的保留根；订阅和值持有也不增加 ScopeTree 父子边。

**生产挂载的待用关系。** runtime 复用 Prototype 的生产挂载与 `protoScopeOpenings`：它们表示后续仍可能执行的生产位置，不把所有曾经打开的实例都视为仍在使用。普通参数按原生产身份匹配；持续参数按本次交付的生产身份判断。具体查询见[开启计划与待用](EFFECT_GRAPH.md#scope-opening-retention)。

**单例与多例共用关闭条件。** 新 request 只建立新的参数生产身份，不撤销旧实例的实际使用、待用或已有 ownership 保留。每步撤销实际使用后调用现有 scope GC；旧实例不再匹配任何合法后续使用，且没有使用者、值保留或保留它的子实例时才 close。比如数据库同参连接由持续待用保留；每步新参的临时实例可在失去用途后回收；新端口开启第二个浏览器时，旧浏览器若仍供其他受控执行或持续使用，就继续存活。以 `requests` 获取资源 Context 本身，不等于重新生产开启参数。

来源 end 不撤销执行中的保留。`Drive` 结束时撤销来源驱动的单元在根帧里的未来位置，再触发现有回收器。有其他使用、待用、值保留或子实例的 scope 继续存活。取消使用相同退出边界，关闭中的取消仍传播；运行退出等待全部受控工作停止后清理。Haskell GC 释放不可达的内存，资源 close 继续由现有 scope 协议负责。

轮询、event 与 socket 都使用这组结构规则：一次采样或收到一条消息不代表来源结束，暂时没有输入也不表示可以 close。BootPlan 决定驱动装配；SDK 不从原子 IO 推断这三个业务名称，也不按它们另选清理策略。现有写法见[第 4.1 节](#drives)。

资源关闭后的受控读取继续检查原 Binding 的 owner 与关闭／失败状态，不自动换 owner、重开或重放生产。外部别名不在本节保留保证内。含 lifelong 的程序按[现行失败协议](#failures)传播失败。

业务资产保存多份数据不等于可以把其中各资源的 owner 合成一个，也不能复活已关闭资源。持续值作为 scope 开启参数沿用本次 Binding 的生产身份和原生产帧；本次交付与合法后继按读取规则参与待用判断，详见[开启计划与待用](EFFECT_GRAPH.md#scope-opening-retention)。这不自动展开 T 中的资源引用或额外保活其内容。

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
    ast = chain [chain [node "Announce"], monitorLines, chain [node "Report"]]
    monitorLines = lifelong
      [ chain [node "PrintLine", node "TextCounter"]
      , chain [node "ShowTotal"]
      ]

LinesDemo 读完四行后 `streamEnd`。每行的打印、统计与累计显示都已在那一行的 `rawemit` 里同步完成，`Drive` 返回，`Report` 读取最终统计。原生文件由来源在 `bracket` 内逐行读取，离开读取操作时关闭，解析失败或取消也走同一释放路径。parser、Excu、Scoped 的 Layer 里没有 `StreamEnds`，在它们的方法体里写 `streamEnd` 由 GHC 拒绝。

| 来源的出口 | 之后发生什么 |
| --- | --- |
| `rawemit text` | 先通知匹配的 emit hook，再调用 parser；成功发布并执行完回调后，在同一次来源调用内继续 |
| 正常返回 `()` | 本次调用完成，`Drive` 再调用一次来源 |
| `raise` | 经 Error 协议诊断，按 9.1 的规则处理 |
| `streamEnd` | 来源结束，`Drive` 返回（静态运行同样结束） |

`streamEnd` 不是失败：不进入 Error 诊断，不通知运行监督，也不被方法体内的 `catchError` 接住。已经完成的 IO 和此前的发布不回滚。

**lifelong 之后的读取。** `require` 读运行级最新值，像 State monad 的 state：每次发布覆盖为最新，读取取当前值（同一次调用内第一次读取后固定）。lifelong 的持续资产在 `Drive` 结束时放掉历史，最新一条保留给后继；一条都没有发布时按缺值报 `ContextNotInitialized`，不等待。

**资源。** 只在来源中开启的 scope（例如 StreamDemo 的 `SensorLink`、LinesDemo 的输入文件）在来源结束、生产挂载的位置撤销后，按可达性回收；后继还会以同样参数开启的实例保留。单元在回调中开启的 scope 随回调的执行帧回收。

<a id="consumer-end"></a>
### 9.5 消费方结束（endStream）

**代码长什么样。** 注册、AST 与 handler 签名都不变。gen 给以 `streams` 订阅持续资产的 Excu，以及在 lifelong 内以 `requests` 订阅 behavior 或 event 的 Excu target 加入 `EndsStream`，方法体多一个出口 `endStream`：

    -- demo/LinesDemo/Generated/Effects.hs（生成）
    type PrintLineLayer m = (SDK.Reads Line m, SDK.EndsStream m, SDK.Raises PrintLineError m, MonadIO m)

    -- 手写（示意，示例本身不调用）：收到业务结束标记后离开
    instance PrintLineLayer m => PrintLineHandler m where
      printLine = do
        Line text <- require @Line
        if text == "stop" then endStream else liftIO (putStrLn text)
        rawoutput []

- 同一条链上的其他 effect（Input 前驱）和 lifelong 里不订阅的普通节点不给：它们是原子操作。handler 的签名不随所处的控制流改变。
- 只给 Excu：Scoped.open 被打断会使实例失效，Pure 是值变换，Stream 用 `streamEnd`。
- 没有 `EndsStream` 却调用 `endStream` 由 GHC 类检拒绝。

**调用之后。** `endStream` 不是失败：本次调用放弃，不交出结果；已经完成的 IO 和此前的发布不回滚。

| 位置 | 效果 |
| --- | --- |
| lifelong 单元中的节点 | 这个节点之后不再执行；同一次回调中其余位置照常执行。单元的节点全部结束时，单元不再回调 |
| 派生的被驱动链 | 这一步不发布，这条派生之后不再回调 |
| 来源驱动的单元全部结束 | `Drive` 在下一次 `rawemit` 之前结束来源 |

**`require` 与订阅无关。** `chain [A, D]` 中 A `endStream` 后，D 照常执行。D 若只 `require` A 本该产出的普通资产，按缺值规则报 `ContextNotInitialized`，确定失败，不挂起，也不读旧值。

<a id="implementation"></a>
## 10. 实现位置

| 内容 | 源码 |
| --- | --- |
| Stream typing、Context 声明 | [Registration.hs](../sdk/Framework/Language/Registration.hs) |
| 组合计算：访问权限、声明、来源检查 | [Gen/Composition.hs](../sdk/Framework/Gen/Composition.hs) |
| lifelong 单元、订阅、生产方式，多来源与回调环的拒绝 | [Gen/Booter.hs](../sdk/Framework/Gen/Booter.hs)（`numberWorkflow`、`planSessions`、`checkReactions`） |
| workflow 闭包、回调表、静态运行与 behavior 比较的生成 | [Gen/Emit/Program.hs](../sdk/Framework/Gen/Emit/Program.hs) |
| 入口里的输出联立、`unlessPerformed`、静态历史请求 | [Gen/Emit/Handlers.hs](../sdk/Framework/Gen/Emit/Handlers.hs)、[Context.hs](../sdk/Framework/Runtime/Context.hs) |
| 静态模型与自洽查询 | [Prototype/Types.hs](../sdk/Framework/Prototype/Types.hs)、[Prototype/Query.hs](../sdk/Framework/Prototype/Query.hs)、[Prototype/Validate.hs](../sdk/Framework/Prototype/Validate.hs) |
| 闭包与回调表的 IR | [Runtime.hs](../sdk/Framework/Runtime.hs)（`Compiled`、`Closure`、`StreamSource`、`Reaction`） |
| 发布、历史、回调入口 | [App.hs](../sdk/Framework/Runtime/App.hs)（`publishBinding`）、[Graph.hs](../sdk/Framework/Runtime/Graph.hs)（`publishAsset`、`react`、`readHistory`、`dropHistory`） |
| 交付视图与结束信号 | [Delivery.hs](../sdk/Framework/Runtime/Delivery.hs) |
| 执行闭包、运行来源、静态运行、回调、运行监督 | [Execution.hs](../sdk/Framework/Runtime/Execution.hs) |
| 执行帧、scope 待用查询 | [Frame.hs](../sdk/Framework/Runtime/Frame.hs)、[Graph.hs](../sdk/Framework/Runtime/Graph.hs) |
| 已知资源 Binding 的执行保留与撤销 | [Retention.hs](../sdk/Framework/Runtime/Retention.hs) |
| `StreamEnds`／`EndsStream` 能力类与绑定能力规则 | [Handler.hs](../sdk/Framework/Language/Handler.hs)、[Gen/Composition.hs](../sdk/Framework/Gen/Composition.hs)、[Gen/Emit/Handlers.hs](../sdk/Framework/Gen/Emit/Handlers.hs) |
| parser 输入 | [App.hs](../sdk/Framework/Runtime/App.hs)（`emitToParser`、`emittedInput`） |

ScopeTree 独立构建并保持无环；订阅与回调关系不作为 scope 父边。运行时不累计完整方法调用历史或无限 workflow 结果。

<a id="deferred"></a>
## 11. 验证与延期

本仓库按约定只做普通编译、生成结果审阅和示例观察，不新增测试框架、负例或穷举门槛。现有验证的边界见 [Next stages](NEXT_STAGES.md#current-limits)，逐次观察记录保留在 Git 历史。LSP 仓库的外部穷举模型尚未扩展到 Stream／lifelong。

当前缺口统一记录在 [Next stages 的限制与开放专题](NEXT_STAGES.md#current-limits)。持续值参数、既有 ownership 的交接与生产挂载的待用回收已接通；保留范围以[资产契约](#binding-retention)为界。容量背压与嵌套 workflow 分列为后续专题。已有单步来源的写法见[第 4.1 节](#drives)，不据此宣称已提供通用外部回调适配。
