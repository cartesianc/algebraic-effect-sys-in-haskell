# Next stages

更新：2026-11-13。**状态：Stage 1 已实现，其中接收形态与 Context 的 request 角色由 Stage 2 取代；Stage 2 已实现（2026-11-08），其中[可见范围内的等待](#stage-2-await)已确定、尚未实现；[Pure 的值管道与 list 原子输出](#pure-pipeline)已实现（2026-11-12）；[scope 的单例与多例、按可达性回收](#scope-gc)已确定、尚未实现（2026-11-13）；Stage 3–7 继续逐阶段收敛。**

本轮目标是在框架现有概念内，先分离原子 handler 与业务 effect，使 handler 可以复用、前驱由声明装配；再统一 Stream effect 与 lifelong 的持续执行协议，完成正常结束、停止传播和资源收尾。每阶段先收敛设计与代码形态，再实现；本文记录推进顺序、待确认事项及开放边界，不替代[主设计](LATEST_DESIGN.md)和[当前 Stream 规范](STREAM_LIFELONG.md)。

本文件是唯一的阶段计划与开放项入口。以下 Stage 1–7 是本轮编号，与已经完成的 Prototype／RuntimeGraph、来源可见性、Stream 初版三个历史阶段区分。

<a id="scope"></a>
## 本轮收敛什么

只收敛已提出的输入契约、handler 复用与前驱装配、资产访问、持续执行、结束和资源释放。不新增 effect 类别、boot 类别、手写装配层、资源寿命标签或可选 cleanup policy，不以新增配置掩盖尚未确定的持有关系。Stage 2 的 `XxxLayer` 是生成的约束别名，不是手写装配。

保持六类 effect、AST targeted boot 与 Context 资产 boot、原生 instance、独立无环 ScopeTree，以及统一 Prototype／RuntimeGraph。Context 继续承载跨 handler 的业务产值；来源可见性、捕获稳定性和唯一 ownership 不能因重构弱化。Stage 2 起 Input 由生成装配为实际执行的前驱，不再只提供句柄能力。

本轮有接口与协议调整，不等于现有行为不变。Stage 1、Stage 2 的规则已经确认；end 的手写接口等后续接口仍须先确认，再同步生成契约和实现；生成前代码始终能由 GHC／HLS 解析、名称解析和类型检查。

<a id="stages"></a>
## 七个阶段

    输入契约
    → handler 复用与前驱装配
    → 共同执行结构
    → 资产与发布
    → 使用边界
    → 结束传播
    → 资源清理

<a id="stage-1"></a>
### Stage 1：收敛资产来源与 handler 接收契约

**状态：已实现；接收形态与 Context 的 request 角色由 [Stage 2](#stage-2) 取代。**

“单一”约束的是每个 refined asset：同一个资产名对应同一个表示 ADT、唯一一个 Context 生产方。request、require、streams 是访问方式，可以同时声明，不生成另一种资产身份；一个消费者仍可依赖多个不同资产，Scoped 的单资源 request 限制保持。

Effects 以 Asset 声明来源，demands 选择资产和访问权限；空 demands 不产生资产接收义务。生成的 Provides 与方法结果类型约束取得的值；instance 通过原生 `request @T`／`require @T` 取值，并显式匹配生成资产的值构造器。没有新增位置参数，也不提前移动取值。普通单构造器可以直接写 `T value <- require @T`，和类型先取得值，再用原生 case 处理；不要求展开所有字段或证明业务使用字段。

每个声明的资产须有注册 instance 中的显式读取，或 Prototype 中已有的 alternative 选择／streams 交付依据。检查以 instance 与资产为单位，不要求每个协议方法、每一种访问模式或每条运行路径都读取。允许 open request、close require 同一资产；重复的显式 request 仍重复执行。完整规则见[主设计：资产接收契约](LATEST_DESIGN.md#demand-contract)。

本阶段保留当前访问结果：普通 request／require 返回 T；持续资产的 require 返回 History T，streams 授予本次交付视图的 require 权限；尚不增加 `stream @T`，也不改变来源可见性、缺值等待或资源 ownership。

**实现落点：** 纯规则集中在 Gen.Demand；Prototype 保存唯一的静态来源；声明依据由 gen 的绑定阶段（Gen.Bind）检查，接收结构检查已由 Stage 2 取消。SDK 门面与执行入口分开，Prototype 只保存模型、查询与校验，来源分析在 gen 的构图阶段（Gen.Build.Sources）；不新建一套资产或 runtime 图。

**交付：** 一致的声明、生成签名、原生 instance、源码检查、六个示例及文档。生成前仍由 GHC／HLS 检查原生 Haskell；架构接收约束由 gencode 检查。

**由 Stage 2 取代的部分：**

- 显式匹配生成资产的值构造器：handler 改为按表示类型读取，细化资产的构造器只出现在生成代码中，接收形态检查随之取消。
- Context 的 request 角色：Context 只声明一个 parser，取值方式全部属于 demand 端。
- 单独声明 requests 也要求读取：requests 表示驱动，不再要求 handler 读取。

保留的部分：每个 refined asset 唯一来源、访问方式须对应生产方已声明的角色、requires／streams 须有读取或 alternative／streams 依据，以及 SDK 门面与 Prototype 的分工。

<a id="stage-2"></a>
### Stage 2：分离原子 handler 与业务 effect

**状态：已实现（2026-11-08）。本节写法与当前 SDK 一致（原子句柄的输出已由 [Pure 的值管道](#pure-pipeline) 从 `Maybe String` 改为 `[String]`），完整写法见[指南](GUIDE.md)；实现范围、验证与未覆盖见[实现与验证](#stage-2-status)。**

effect 是业务装配，handler 是可复用的原子操作。多个 effect 可以绑定同一个 handler；Input 与 demands 由 gencode 装配，不进入 handler 文本。gencode 是这个 EDSL 的编译器：它把分散的注册关系化成一张图，在生成期解决链的组合、读取路由和合法性检查；生成的 Haskell 是交给 GHC 编译的中间表示，这些问题不留给运行时。SDK 据此分为源语言、gen、编译产物、运行时四层，见[主设计：gen 是编译器](LATEST_DESIGN.md#compiler)。

<a id="stage-2-history"></a>
#### 问题如何演变

- **起点：固定 demand 限制了来源复用。** demand 指定具体 refined asset，由资产确定唯一 Context 来源。它保证工厂装配明确，也把消费者绑定到具体生产链：同一个写入操作分别消费报表和回复时，要写两份方法体，固定的 `require @ReportText` 不会因挂到另一条链而改变来源。Input 只描述句柄能力，不携带“本次使用应绑定哪个来源”的信息。
- **澄清：alternative 不是跨来源装配。** alternative 从同一基础资产的分支投影推导候选，按该资产的构造器选择流程。`FileTextBlank`、`FileTextWritten` 来自同一个 `FileText`、同一个 Context，属于同源状态分派，不能当作跨 Context 来源多态的证据，也不按“谁先生产就选谁”竞争。
- **曾经的困难：坚持同一个 effect 只注册一次。** 同时复用方法体和 effect 注册，使讨论转向来源参数、模块绑定、链路 newtype 和 `resource`。这些方向都缺少同一份信息：使用处只写 `input = "EffectA"`，没有来源实例化信息，类型兼容、挂载身份和生产时序都不能补出业务选择。
- **转向：原子性落在 handler，effect 可以业务化。** 原子操作由 handler 实现；effect 是业务装配，可以有不同的 Input、demands 和运行身份；多个 effect 绑定同一个 handler，来源由注册区分。不新增 `resource`、`oneOf` 或链路 newtype。此前“一个原子操作只能对应一个 effect 注册”的要求已被替代。

<a id="stage-2-roles"></a>
#### 职责边界

| 层次 | 职责 |
| --- | --- |
| 原子 handler | 实现操作：按表示类型读取注入的值，交出结果或自身的失败 |
| 业务 effect | 绑定 handler，声明 Input、具体资产需求及驱动关系 |
| gencode | 编译：组合链、路由读取、生成契约和静态图，并做生成期检查 |
| runtime | 执行编译结果，管理绑定、scope、注入与故障 |

共享 handler 不通过模块名、调用时序或链路位置判断业务来源。handler 定义共享不合并实际调用或运行实例。

<a id="stage-2-code"></a>
#### 代码长什么样

以 [FacadeProbe](../demo/FacadeProbe/README.md) 的报表与回复为例：两者共用打开、写入、读取和解析，只是资产和前驱不同。

`Types.hs` 只写数据结构，不变：

```haskell
data TextFile = TextFile FilePath Handle deriving Show
newtype Body = Body String deriving Show
newtype LineCount = LineCount Int deriving Show
```

`Effects.hs`：注册里的名字指向 handler；同一个 handler 绑定多次，Input 与 demand 各不相同。

```haskell
EffectSpec { name = "ReportFile"
           , typing = Context { asset = Asset @TextFile "OpenedReport", parser = Just "acquireFile", require = True, stream = False }
           , input = "Root", demands = [requests "ReportPath", requires "ReportPath"] }
EffectSpec { name = "ReportScope"
           , typing = Scoped { open = Just "openTextFile", close = Just "closeTextFile" }
           , input = "Root", demands = [requests "OpenedReport", requires "OpenedReport"] }
EffectSpec { name = "WriteReport", typing = Excu { handler = Just "writeText" }
           , input = "ReportScope", demands = [requests "ReportBody", requires "OpenedReport", requires "ReportBody"] }
EffectSpec { name = "WriteReply", typing = Excu { handler = Just "writeText" }
           , input = "ReplyScope", demands = [requests "ReplyBody", requires "OpenedReply", requires "ReplyBody"] }
EffectSpec { name = "ReportCounter"
           , typing = Context { asset = Asset @LineCount "ReportStats", parser = Just "countLines", require = True, stream = False }
           , input = "ReadReport", demands = [] }
```

`Handlers.hs`：每个 handler 一个类。方法体不出现 Input、细化资产、effect 名或 request。

```haskell
instance WriteTextLayer m => WriteTextHandler m where
  writeText = do
    TextFile path file <- require @TextFile
    Body text <- require @Body
    liftIO (hPutStr file text >> hFlush file)
    pure []

instance CountLinesLayer m => CountLinesHandler m where
  countLines = do
    output <- raw
    contents <- case output of
      [text] -> pure text
      _ -> raise (CountLinesError "no text")
    pure (LineCount (length (lines contents)))
```

`AST.hs` 不变，仍按 effect 名挂节点。

生成的契约与装配：每个 effect 一个类型标签 `At "名字"`，handler 方法体原样复制，读取由按标签区分的 instance 在编译期选定，运行时不按调用者查表。

```haskell
-- Generated/Effects.hs
type WriteTextLayer m = (SDK.Reads (Body) m, SDK.Reads (TextFile) m, SDK.Raises WriteTextError m, MonadIO m)
class WriteTextHandler m where
  writeText :: m [String]
newtype WriteTextError = WriteTextError String

-- Generated/Handlers.hs 入口：驱动 → Input → 方法体；外层是入口包装
runWriteReport = ⟨入口包装⟩ $
  openReportScope >> runAt @"WriteReport" FrameworkGenerated.writeText
getReportStats = ⟨入口包装⟩ $
  (FrameworkGenerated.ReportStats <$> runAt @"ReportCounter" FrameworkGenerated.countLines)

-- 路由：表示类型 + effect → 唯一的细化资产
instance FrameworkRuntime.Reads (TextFile) (At "WriteReport") where
  require = At ((\(FrameworkGenerated.OpenedReport value) -> value) <$> readOpenedReport)

-- raw：直接 Input 的入口；注入时由本次输出回答，被驱动时执行该入口
instance FrameworkRuntime.Raw (At "ReportCounter") where
  raw = At (runReadReport)
```

2026-11-08 的标签探针先确认：两个 effect 共用一份 `writeText`、两个 parser 共用一份 `countLines` 时，GHC 按标签选出各自的读取，方法体不改写；实现后 FacadeProbe 以生成代码得到同样的结果。

<a id="stage-2-decisions"></a>
#### 已确认的决定

| 主题 | 决定 |
| --- | --- |
| handler | 类方法，不带参数，写作 `instance XxxLayer m => XxxHandler m`；类名、Layer、错误类型和方法类型由 gen 从 handler 名与绑定方式推出 |
| Input | gen 在入口中把 Input 装配为前驱，在方法体之前执行；方法体不调用上游，也不捕获 Input 的失败，失败后的改道用 AST 的 alternative |
| 挂接 parser | Input 是 Excu、Scoped.open 或 Stream 时，parser 以 `raw` 读取直接 Input 的本次输出，沿用现有注入与回放协议；`raw` 现为 `m [String]`，Pure 同样用它，见 [Pure 的值管道](#pure-pipeline) |
| 驱动 | `requests` 驱动对应资产沿 Input 的整条 Context 链；`requires` 只读取，不驱动，也不在读取处生产，还没有值时等待发布；alternative 的选择读取驱动转折资产，相当于 `requests`；`streams` 由持续交付驱动。入口顺序是驱动 → Input → 方法体；handler 只写 `require` |
| 读取 | handler 按表示类型读取；gen 按“表示类型 + effect”路由到唯一的细化资产，一个 effect 内表示类型不重复；需要两个同类型值的操作用角色类型区分 |
| 值传递 | 值只经资产流动；原子句柄和 Stream 的输出只交给挂在其下的 parser |
| Context | `Context { asset, parser, require :: Bool, stream :: Bool }`；`getT`、`readT`、`streamT` 由 gen 按资产名生成；`require` 缓存最新值，`stream` 缓存历史 |
| 持续资产 | `stream = True` 当且仅当 Input 是 Stream，且必须同时 `require = True`；持续交付只由上游 Stream 驱动，RepeatRequest 取消 |
| 注册名字 | Pure、Excu、Scoped、Stream、Context.parser、Error.detect／resolve 都写 handler 名；effect 方法名由 gen 内部生成，用户不写也不调用 |
| 失败 | 属于 handler：`raise (XxxError "...")`，不随绑定改变；发生在哪个节点只是诊断位置 |
| Error | 只指向 scope；`RaisedBy` 写 handler 名，`ScopeFaultIn`／`ContextFaultIn` 仍写 effect 名；没有关联 scope 时由 gen 报错；普通 effect 的错误靠提前 mock 排除 |
| scope | 实例跟随注册：两个 Scoped 注册共用 open／close，仍是两个独立 scope |
| 普通函数 | 禁止用户在顶层定义普通函数，所有值操作写成类方法并注册；方法体内的局部函数与 lambda 不限制 |
| 替换 | 全面替换旧写法，不保留兼容层 |

<a id="stage-2-layer"></a>
#### Layer 包含什么

| 约束 | 什么时候有 | 方法体可写 |
| --- | --- | --- |
| `Reads T m` | 绑定它的 effect `requires` 了表示类型为 T 的资产 | `require @T` |
| `Reads (History T) m` | 绑定它的 effect `streams` 了持续资产 | `require @(History T)` |
| `Raw m` | 绑成挂接的 parser 或 Pure | `raw` |
| `Raises XxxError m` | 总是 | `raise (XxxError "...")` |
| `MonadIO m` | Pure 以外总是 | `liftIO` |

单独的 `requests` 不带来 `Reads`。Layer 不含 Input 的 effect 类、effect 自身的能力标记、细化资产、其他 handler 的类或 request。一个 handler 只有一份 Layer，各绑定推出的内容必须一致。`Raw`、`Raises` 是暂定名。

| 绑定方式 | 方法类型 |
| --- | --- |
| Pure | `m [String]`（见 [Pure 的值管道](#pure-pipeline)） |
| Excu、Scoped.open／close | `m [String]`（Stage 2 时为 `m (Maybe String)`） |
| Context.parser | `m T`，T 是 `Asset @T` 的表示类型 |
| Stream | `m String` |
| Error.detect／resolve | `m ()` |

<a id="stage-2-checks"></a>
#### 生成期检查

以下都是编译错误，由 gencode 在生成前报告：

- 每个读取在每个绑定下解析到唯一的细化资产；一个 effect 的 demands 里同一表示类型只出现一次。
- 同一个 handler 的各个绑定推出相同的方法类型与 Layer。
- handler 方法体不调用其他 handler 或 effect 的方法；FacadeProbe 实测中 GHC 放过的“调用另一个 handler 的类方法”也由 gencode 拒绝。
- requires 需要的资产能沿已有来源分析得到驱动依据。
- 顶层只允许类型声明、instance、`effects`、`ast` 与 `main`。
- Context 的 `stream`、`require` 与 Input 组合合法；挂在 Stream 下的资产不能 `requests`。
- Error 必须关联一个 scope。
- handler 名推出的类、Layer、错误类型与其他生成名字冲突。
- 沿用 Stage 1：每个细化资产唯一来源；访问方式对应生产方已声明的角色；requires／streams 须有读取或 alternative／streams 依据。

<a id="stage-2-migration"></a>
#### 迁移与取代

| 现有写法 | 新写法 |
| --- | --- |
| 方法体第一行调用 Input | gen 在入口装配 |
| 方法体里的 `request`，包括只为刷新的 `_ <- request @T` | 注册里的 `requests` |
| 按 effect 生成的 `raise (XxxError ...)` | 按 handler 生成 |
| parser 调用 Input 的方法 | `raw` |
| `finishInspection`、`checkIndependent`、`checkReopen` 在方法体中间或重复开关资源 | 拆成多个 effect，由 AST 安排顺序；`FinishInspection` 声明的 Input 是 `InspectFiles`，方法体却只调用 `holdFiles`，迁移时按实际依赖改声明，不悄悄新增执行 |
| FileDemo 的 `validateFileName` 作为守卫 | Stage 2 时仍是 `FileResource` 的 Input；现在是挂在 `LocateFile` 下的 Pure，见 [Pure 的值管道](#pure-pipeline) |
| StreamDemo 的 `Beat`（不在 Stream 下的持续资产） | Stream effect 加 parser |
| FileDemo 的 `resolveFileSession` 调用 `closeFileSession` | resolve 暂不操作 scope，见下文 Error 驱动链 |
| Crawler 两个抓取、两个打印的重复方法体 | 共享 handler |

取消的现行规则：Stage 1 的接收形态检查；Context 的 request 角色；RepeatRequest；没有关联 scope 的全局 Error 处置；Pure 的旧候选名单协议；普通函数的资产检查与具名局部函数限制（改为顶层白名单）；AGENTS.md 中“业务 instance 写作 `instance XInputs m => XEffect m`，方法体显式调用 Input”与“不恢复全面禁止普通函数”两条。以上迁移与取消已于 2026-11-08 全部完成，见[实现与验证](#stage-2-status)。

<a id="stage-2-later"></a>
#### 本阶段不处理

- **Pure 的语义**：Stage 2 只定了方向（没有外部性的值管道，值直接进入下一个 effect）；返回类型、下游读取方式与能否 raise 已由 [Pure 的值管道](#pure-pipeline) 确定并实现（2026-11-12）。
- **Stream 的驱动方式**：event、behavior（轮询）与 socket 三种方式待定；持续资产的读取类型是继续用 `History` 还是直接暴露标准序列待定。
- **Error 驱动链**：Error 是另一条驱动链，resolve 不应调用 close；Error 如何驱动 scope 的修复待定。
- **读取历史的写法**：`streamT` 由 gen 生成；handler 中暂沿用 `require @(History T)`，是否另设读取方法待定。

<a id="stage-2-delivery"></a>
**交付（已完成）：** 一致的注册、生成契约、原生 handler、生成装配与检查；六个 demo 与 FacadeProbe 全部迁移并与迁移前输出对照；同步主设计、指南、ASSETS、EFFECT_GRAPH、STREAM_LIFELONG、AGENTS 与 README。

<a id="stage-2-status"></a>
#### 实现与验证（2026-11-08）

全面替换旧写法，不保留兼容层：

- **注册与检查**：`Context { asset, parser, require, stream }`；删除 Context 的 request 角色、RepeatRequest、没有关联 scope 的全局 Error 与 Stage 1 的接收形态检查。降级阶段（Gen.Lower）新增：Input 不能指向 Error、Error 恰好关联一个 scope、`RaisedBy` 写已注册的 handler 名；Gen.Demand 新增 `requires` 需要 `require = True`、`streams` 只订阅持续资产等访问规则；绑定阶段（Gen.Bind）拒绝与生成的入口重名的 handler 名。
- **生成**：每个 handler 一份 `XxxLayer`／`XxxHandler`／`XxxError`；运行副本在 `At "名字"` 标签上原样复制方法体，生成按标签的 `Reads`／`Raw`／`Raises` 实例与“驱动 → Input → 方法体”的入口。结构分析提取 `require @T`／`raw` 的原子形状，按绑定代换后组成 effect 方法结构，并检查读取路由、同一 handler 各绑定的签名与 Layer、读取依据与 handler 互调。资产检查（Gen.Assets）改为顶层白名单与资产目录。
- **读取**：`requires` 不生产。读取先用本次捕获，再查静态来源表；还没有值时阻塞当前链，等之后的发布再重读，不报错。资源、诊断、自动收尾与 close 期间不等待，缺值报 `ContextNotInitialized`。alternative 的选择读取驱动转折资产，相当于 `requests`；持续资产领取会话交付。读取权限只在生成期检查，运行时没有读取声明表。
- **demo**：六个 demo 与 FacadeProbe 全部迁移。Crawler 两条链共用 `fetchPage`、`extractSummary`、`printSummary`；StreamDemo 的心跳改为 `HeartbeatClock`（Stream）＋`Heartbeat`（parser）；OpenFilesDemo 增加 `ReleaseFiles`（绑定 `holdFiles`）与挂在它下面的 `InspectionSnapshot`，`FinishInspection` 改为 Input Root、requires 快照，按实际依赖声明；ScopeInstancesDemo 拆成共用 `checkSelection` 的 `UseFirst`／`UseSecond`／`ReopenFirst`，以及 `SelectSecond`／`SelectFirst` 与 `CheckJournal`；FileDemo 的 `resolveFileSession` 改为 `pure ()`（TODO）；FacadeProbe 改为真实注册与 handler，删除手写的 Contracts.hs、Facade.hs。

**验证**（本次实际执行）：

- `cabal build all --offline -j1` 通过；七个程序均用 `effect-codegen` 重新生成；FacadeProbe 按其 README 的 ghc 命令编译。
- 与迁移前代码的输出对照（迁移前的输出在同日、动手前从干净输出目录采集；FacadeProbe 用 2026-11-07 的原型程序）。有限 demo 从干净输出目录各运行两次：FileDemo、ScopeReuseDemo 输出相同，ScopeReuseDemo 的 `shared.txt` 行序随并行写入变化，迁移前两次运行也不同；Crawler 的结构与结果相同，只有页面中随请求变化的链接参数不同。StreamDemo 在终端运行约 11 秒后 Ctrl-C，读数、趋势、心跳节奏与 `[sensor] disconnected` 收尾和迁移前一致。
- 预期的输出变化：OpenFilesDemo 的检查行由 “after explicit close” 改为 “after the scope closed”，结果多一项 `ReleaseFilesResult ()`；ScopeInstancesDemo 改为三条使用闭包，检查日志的逐条顺序与开关计数（文件 1 为 2/2，文件 2 为 1/1）；FacadeProbe 的失败 `detail` 由 `ShowAFailure` 变为 handler 的 `ShowLevelFailure`，`origin` 仍为 `"ShowA"`，两个 lifelong 单元的交错顺序随时序变化，写出的文件内容相同。

**未覆盖**：

- 没有新增测试或负例；生成期检查只在七个程序的合法写法上运行过，各条报错路径没有逐一触发。
- 七个程序中没有真正进入等待的读取。parallel 兄弟互不可见，可见范围内没人生产的读取会一直等待；对应的设计已确定、尚未实现，见[可见范围内的等待](#stage-2-await)。
- detect／resolve 的 Layer 不含 `caughtFailure`，handler 读不到原失败；Error 驱动链待定。
- Pure 当时仍是 `m ()` 守卫，已由 [Pure 的值管道](#pure-pipeline) 取代；Stream 的驱动方式未区分；lifelong 内的显式反馈随 RepeatRequest 取消，没有替代写法；`streamT` 已生成，handler 读取历史仍写 `require @(History T)`。
- Stream 的背压与资源释放不在本次范围；并发交错、长时间内存与 Windows 以外的取消仍未观察。

<a id="stage-2-await"></a>
#### 可见范围内的等待（已确定，未实现）

**状态：设计已确认（2026-11-08，读不确定的报错于 2026-11-12 补充），尚未实现。** 规则见[主设计：可见范围与等待的结束](LATEST_DESIGN.md#await-visibility)。

现在 `requires` 缺值时已经等待发布，但可见范围只有先完成的前驱与本入口自己，parallel 兄弟互不可见：可见范围内没人生产的读取会一直等，兄弟的发布也叫不醒它。确认的分工是：

- **唯一性**：细化保证生产链唯一，不保证每次驱动的值相同。require 读的是 request 的 state；生成期保留“有多个可见来源”报错中读不确定的部分（彼此无先后的生产者，或先完成的生产者加上与读取并发的生产者），有先后的生产者读最后一次。
- **可见性**在生成期判断这次等待能不能等到、读到的是不是确定的一次；parallel 兄弟纳入可见范围。运行时的隔离由执行帧负责。
- **生成期**报“永远等不到”与“读不确定”：读取点在可见范围内没有可能的生产者，或兄弟之间互等；或者可见的生产者不能确定读到哪一次。
- **运行时**按执行帧为每份资产保存一个 state：request 直接覆盖，require 读当前值，不在多份发布之间挑选；可能的生产者都已结束仍没有值时，结束等待并报 `ContextNotInitialized`。

**实现落点：**

- gen：Query 的可见关系纳入 parallel 兄弟；来源分析记录每个读取点在可见范围内的可能生产者。顺序节点上后一次发布取代前一次，parallel 合并时各分支的发布并存；“有多个可见来源”的报错改为只拦读不确定的读取，另检查等不到的读取与兄弟互等。
- 运行时：普通发布从按 Origin 分组的整张表，改为每个执行帧、每份资产一个 `TVar`。request 用一次 `writeTVar` 直接覆盖，写入即唤醒，去掉整表的 `atomicModifyIORef'`、`uninterruptibleMask_` 与全局发布信号；require 依次读本帧和外层帧，都空时 `retry`。普通发布不再按来源表挑选 Origin，去掉普通发布的 `AmbiguousContextBinding`（资源实例的歧义检查保留）。lifelong 单元每次执行建立新帧，取代 `resetOrigins`；会话挂载的发布照旧作为伴随发布交付。等待的结束：可能的生产者的结束记录与 state 在同一次 `retry` 中检查。cabal 加入 GHC 自带的 `stm`。
- 文档：主设计 4.3 节与 EFFECT_GRAPH 的来源一节改为当前协议，GUIDE 补充兄弟之间读取的写法。

<a id="pure-pipeline"></a>
### Pure 的值管道与 list 原子输出

**状态：已实现（2026-11-12）。** 规则与代码形态见[主设计：Pure](LATEST_DESIGN.md#pure)，写法见[指南](GUIDE.md#pure)。这一项不属于 Stage 1–7 的持续执行计划，是 Stage 2 留下的 Pure 语义的收敛。

**确认的决定：**

| 主题 | 决定 |
| --- | --- |
| 原子输出 | Excu、Scoped.open／close 交出 `[String]`，取代 `Maybe String`：没有信息是 `[]`，一项是 `[x]`，一串操作或递归的结果用 `:`、`concat` 组合。list 是自由幺半群，只承诺顺序与拼接，不保留嵌套 |
| Pure | 生产链中的纯值变换，对上层输出做 fmap：签名 `m [String]`，用 `raw` 读直接 Input；Layer 只有 `Raw`、`Raises`，没有 `MonadIO`；可以 `raise`；不声明 demands，不作为 AST 末端，必须绑定 handler |
| 位置 | Pure 的 input 是 Excu、Scoped 或 Pure；以 Pure 为 input 的只能是 Context 或 Pure，且至少一个，一串 Pure 总是落到一个 Context |
| Context | 细化 parser，作用类似 tokenize：把 raw 解析成表示类型；即使结果仍是 list，也要经过 Context 才成为资产。值的变换写在 Pure 里 |
| 取值 | Pure 与 Context 都从直接 Input 的 raw 取值，不走 demands，避免 demands 的循环依赖 |
| Stream | 有自己的数据结构：handler 仍是 `m String`，parser 的 raw 读作单元素 list；下面不挂 Pure |

**实现：**

- **源语言**：`Raw` 的 `raw :: m [String]`。
- **降级（Gen.Lower）**：Pure 的注册规则；Context 的挂接句柄沿一串 Pure 向上找到 Excu 或 Scoped；"资源 Context 不能挂在请求它的 scope 下"按这个句柄检查；`streams` 只由 Excu、Scoped 声明；AST 末端不能是 Pure。
- **绑定（Gen.Bind）**：Context 的 parser 与 Pure 读 raw，由直接 Input 的入口回答，Input 不作为前驱执行；Excu、Scoped、Pure 的方法类型为 `[String]`；Stream 下的 raw 为 `(: []) <$> next名字`。
- **构图（Gen.Build、Build.Sources）**：注入副本把中间的 Pure 就地展开到句柄为止，图中不成环；"注入经其他方法绕到句柄"的检查允许经 Pure；来源分析中 Pure 不改变调用者。
- **输出（Emit.Handlers）**：Pure 的入口没有原子句柄包装，也不进入 handler 身份，因此不改变调用者；Raw 实例也为 Pure 生成。
- **运行时**：`RawOutput` 的 `info` 为 `[String]`；`atomicHandle`／`atomicScope` 交出 list，handler 没有执行（复用实例、重复 close）时为 `[]`。

**迁移：**

- 七个程序中 Excu／Scoped 的 handler 改为 `pure []`／`pure [x]`（43 处），六个读 `raw` 的 parser 改为匹配 list；Stream 下的 parser 用 `concat <$> raw`。
- FileDemo：`locateFile` 改为 Excu `LocateFile`，交出路径；`ValidateFileName` 改为挂在它下面的 Pure，检查后原样交出；新增 parser `parseFileName`，`FileLocation` 挂在 Pure 下；`FileResource`、`FileSession` 的 input 改为 Root，文件名仍由 `FileResource` 的 `requests "FileName"` 驱动，经过检查后才打开文件。
- Crawler：`FetchPage`、`FetchLinkedPage` 与各自的解析 Context 之间加入 Pure `KeepPageBody`、`KeepLinkedPageBody`，共用 `dropBlankBodies`，去掉空白正文；抓取在 AST 中执行，解析经 Pure 注入，覆盖经 Pure 的注入路径。正文全是空白时，解析现在报 `ExtractSummaryError`（此前会解析出空摘要）。
- 顺带修正 Crawler、FileDemo 中两处仍写"require 时驱动"的旧注释，以及 GUIDE 中 `requires` 仍写"生产一次并记住"的旧描述。

**验证**（本次实际执行）：

- `cabal build all` 通过；七个程序均用 `effect-codegen` 重新生成；FacadeProbe 按其 README 的 ghc 命令编译。
- 与改动前（main，0651829）对照：在 `dist-newstyle/bl` 的 worktree 中编译 main，两边从同一份 `output.txt` 开始各运行一次。FileDemo、OpenFilesDemo、ScopeReuseDemo、ScopeInstancesDemo 输出相同，FileDemo 写出的文件相同；Crawler 除随请求变化的链接签名外相同；StreamDemo 两版同时在终端运行到第 56 条读数左右，读数、趋势与心跳节奏一致，新版另运行一次，Ctrl-C 后以 `[sensor] disconnected` 收尾；FacadeProbe 输出行相同（parallel 的交错顺序不同），写出的文件相同，仍以 `ShowLevelFailure` 结束。
- Crawler 加入 Pure 后再次 `cabal build all`、重新生成并运行：两页摘要都由经 Pure 的注入发布并打印，输出共 100 行，与之前的运行相比只有网页本身随时间变化的链接不同（Google 的链接签名、百度的热搜链接）。

**未覆盖：**

- 没有新增测试或负例；Pure 的各条生成期报错没有逐一触发。
- Pure 的 `raise` 没有触发过；经 Pure 的注入只在 Crawler 的成功路径上运行过，注入中的 Pure 失败没有观察。
- 没有 handler 交出多于一项的 list；递归组合、去重与排序只在文档示例中出现。
- 带类型的原子输出、嵌套结构（森林）与 Pure 挂在 Stream 下待另行设计。

<a id="scope-gc"></a>
### Scope 的单例与多例、按可达性回收（已确定，未实现）

**状态：设计已确认（2026-11-13），尚未实现。** 规则见[主设计：单例与多例](LATEST_DESIGN.md#scope-identity)和[按可达性回收](LATEST_DESIGN.md#scope-gc)。这一项不占 Stage 1–7 的编号，它给出 [Stage 5](#stage-5) 的持有依据与 [Stage 7](#stage-7) 的关闭条件。

**确认的决定：**

| 主题 | 决定 |
| --- | --- |
| 单例与多例 | 整个设计的出发点。`requests` 发起一次新的生产，得到新身份；`requires` 引用已有的一次生产，身份相同。开启参数被 `requests` 的开启是多例，每次开启一个实例，随发起它的那次执行结束；只 `requires` 的开启是单例，读到同一次生产的开启共享一个实例，活到没有人还能读到这次生产；没有开启参数的是注册级单例 |
| 实例身份 | Scoped 注册加开启参数来自的那一次生产，不用 key，不比较值，参数 ADT 不再需要 `Eq`。类别属于开启位置，不是 Scoped 注册的固定属性；Scoped 自己对资源 Context 的 `requests` 不决定类别 |
| 关闭时机 | SDK 按剩余程序的可达性推出：仍可能被触达的实例不关闭，不可达即关闭。业务只实现 close handler，不声明何时关闭，不新增 `closes`、AST 节点、key 或寿命标签 |
| 资源读取 | 资源 Context 只能在已经开启其所属 Scoped 的链内读取，否则生成期报错；取消“本链没有捕获时由仍开着的实例提供” |
| 计数 | gen 在每个开启位置记录参数的生产出处；运行时按执行帧记录节点进度，节点结束或被跳过后不再待用，只减不增。有限运行一帧，lifelong 单元每次执行一帧 |
| 执行 | close 在使计数归零的线程中同步执行，完成后才继续下一个节点，不另设后台线程 |
| lifelong | 单例记在外层帧，常驻；多例属于本轮的帧，本轮结束即回收：连接池跨轮存续，事务单轮结束 |
| 运行结束 | 正常结束、失败或取消时，全部声明了 close 的实例关闭，包括 lifelong 用到的单例；ScopeTree 只在内存中，不把外部资源留给下一次运行 |
| close | 不再必填；没有 close 的实例不可达时只移出运行表，运行结束时也不关闭 |
| close 失败 | 先进入关联 scope 的 Error 诊断，之后只记录并在运行结束时汇总报告；不改变节点结果，不短路，不停止运行，运行结果仍是业务结果；不重试 |

**实施顺序：** 分两个可编译的交付点，先增加事实，再改变回收行为；[可见范围内的等待](#stage-2-await)在这之后另行推进，复用同一份生产身份与节点进度。本次不引入按位置的读取计划、方法体内的登记或 STM 资产 state，生成副本中的业务方法体保持原样。

第一步，增加公共运行事实，行为不变：

- **生产身份**：每次 Context 生产已有的 `ActivationId` 存入成功发布的绑定。同一节点两次生产身份不同；生产失败不替换旧绑定；读取、交接、scope 快照和认领传递同一个绑定；scope 复用旧资源时保留原身份；没有资源的 scope 的内部占位绑定没有生产身份。Origin 表达业务出身，ownership 表达关闭归属，三者不互相替代。
- **执行帧**：有限运行一个根帧，lifelong 单元每次执行一个子帧，帧结束后释放进度记录。现有领取会话交付的 `Frame` 先改名，避免与执行帧混用；普通资产的存储不迁移。
- **节点进度**：在执行 algebra 中登记待执行、执行中、完成（成功、失败或取消）和跳过：chained 短路跳过其余兄弟的子树，alternative 选定后跳过未选中的候选，parallel 各分支独立完成。节点的完成晚于业务、诊断和受控结果消费；更新幂等，异常与取消不遗漏。
- **验收**：新信息正确记录；普通读取、按 Eq 的实例匹配、once-spare 的关闭时点和业务结果都不变。

第二步，切换实例匹配与回收：

- **gen**：来源分析在分析到 open 时，按参数记录可能的来源节点（本节点自己的生产、其他节点的生产、alternative 交接来的捕获），作为 Prototype 的新字段，并给出开启位置的类别（注册级单例、单例、多例），`--structure` 展示。不要求保留完整的分支相关性：没有执行的分支没有发布，同一节点多次生产以它当前发布的那一份为准，精确性由运行时的生产身份保证。新增“资源只在开启它的链内读取”的检查；取消“可开启的 Scoped 须声明 close”的检查；更新 Prototype 校验与生成缓存。
- **实例匹配**：实例键由参数值改为 Scoped 注册加各开启参数绑定的生产身份，去掉参数观察中的 `Eq` 比较。
- **待用关系**：帧开始时由 Prototype 为帧内节点建立，节点完成或被跳过后撤销，只减不增。判断某个仍待用的节点是否触达实例时，比较实例的参数绑定与来源节点当前发布的那一份的生产身份，不需要在来源确定后另行落实，也没有交接间隙。lifelong 单元的每一轮按同一套规则作为一帧；参数来自 lifelong 之外或没有参数的开启，待用关系记在根帧，lifelong 存续期间不撤销。
- **关闭**：`cleanupAvailable` 的关闭条件加入“没有仍待用的节点触达它”；节点结束时只检查它会触达的 Scoped 及其父 scope，不另建索引；运行结束时先让受控工作退出，再统一回收。close 失败不再并入节点或运行结果，也不重试；ScopeInUse 改为内部不变量错误，关闭预约等内部机制保留；会话继续以自己的使用登记持有实例，Stream end、历史资源与背压仍归 Stream 专题。
- **验收**：读同一次生产的开启共享实例，两次独立生产即使同值也不共享；顺序节点之间实例保留到最后一个待用节点结束；parallel 分支没有实际重叠也共享；未选分支、短路和取消不留下待用关系；同一节点多次生产、多个开启参数不混淆实例；诊断与结果消费结束前不回收；lifelong 的单例常驻、多例每轮回收；可选 close、close 失败和运行结束符合上表。

**其余落点：**

- demo：ScopeReuseDemo 的写入去掉 `requests "FilePaths"`，改读 PrepareProbe 的那次生产以保持共享；其余 demo 核对注释与预期输出。
- 文档：主设计 4.7 改写为当前协议；GUIDE 增加单例与多例的写法，更新共享与新建、自动关闭、`Eq` 要求、close 必填与故障表；AGENTS 的回收保证去掉 once-spare。

<a id="stage-3"></a>
### Stage 3：确定 Stream 与 lifelong 的共同执行结构

统一 lower 后的持续执行模型：等待执行条件、完成一次有限操作、发布本次实际产生的资产、继续或进入结束协议。这里的“同构”指共同运行协议的对应，不先宣称两种前端 ADT 已有一一同构证明。

| 共同环节 | Stream effect 所在生产链 | lifelong 中的重复执行单元 |
| --- | --- | --- |
| 启动来源 | Context 资产 boot | AST boot |
| 推进条件 | 来源获取操作就绪 | 所依赖的 Context 增量就绪 |
| 一次有限执行 | 原始输入获取与 Context 解析 | 一次有限 workflow 及其挂接解析 |
| 业务产值 | Context 发布 | Context 发布 |
| 持续状态 | 生产进度、绑定和资源使用 | 消费进度、绑定和资源使用 |
| 结束与收尾 | 停止推进、结束发布、撤销使用 | 停止推进、结束发布、撤销使用 |

生产和消费继续独立推进。lifelong 可以承载完整 workflow；它的各重复单元遵守共同协议，branch 保留现有组合关系和并发，不能为统一实现把整个 lifelong 压成一个串行生产循环。单次成功和某轮没有产值，都不等于持续执行结束。

**交付：** 共同执行协议、两种入口的映射，以及有限调用与持续推进的边界。后续阶段基于这一协议处理状态与清理，不分别维护两套生命周期。

<a id="stage-4"></a>
### Stage 4：统一生产、当前值和历史

收敛目标访问语义：

| 访问 | 目标含义 |
| --- | --- |
| request | 有主动生产能力时，生产一次并返回本次值 |
| require | 读取当前调用确定的值 |
| stream | 读取截至同一确定位置的历史 |

Stage 2 已确定：request 是消费链对生产链的驱动，写在注册里；Context 的 `require` 缓存最新值、`stream` 缓存历史。本阶段在此基础上收敛发布与视图位置。

本轮交付后，后台的新发布不改写当前调用的值或历史视图。显式 request 是否以及怎样更新当前视图，须与已有刷新、来源和捕获协议一起确认；有持续来源不意味着它一定支持消费方主动 request。

Stream 生产链和 lifelong 中反复执行的 original chain 均通过 Context 发布。lifelong 内节点既可消费也可产值；已有 workflow 产生的输出不能再被另起的生产循环重复执行。发布沿用合法来源与会话身份，不因资产同名变成全局广播。

**当前差异：** Stage 2 后 `streams` 读取 History、`requires` 读取最新一条；handler 读取历史仍写 `require @(History T)`，gen 已生成的 `streamT` 尚未作为 handler 的读取写法，视图位置的拆分尚未实现。读取历史的目标是读到确定位置为止的历史，不是每调用一次就领取下一条增量。

**交付：** 统一的发布、当前值与历史协议，明确每次读取的出身和视图。区分普通历史数据、伴随发布和有资源归属的绑定，为后续释放建立依据。

<a id="stage-5"></a>
### Stage 5：建立持续边界与 scope 的使用关系

将生产会话、lifelong 单元、有限调用与实际 scope 实例接入现有 RuntimeGraph。ScopeTree 继续独立维护无环资源依赖；订阅和 callback 关系不能直接变成 scope 父子边。

确定实际使用何时建立、跨越哪些执行阶段、何时撤销。demand 表达资产依赖，不自动授予整个生产会话的关闭权；多个订阅者共享来源时分别撤销使用。scope 与持续执行的联动沿用已有资产依赖，不要求新增资源寿命标签。

连接池跨轮存续与事务单次结束由[单例与多例](#scope-gc)解释（已确定，未实现）：参数只生产一次、各轮 `requires` 的开启是单例，常驻；每轮 `requests` 的开启是多例，本轮结束即回收，参数变化时不累计历次实例。本阶段把生产会话与 lifelong 单元接入这份可达性的根集，不靠运行时猜测或新增寿命标签。

同时接通持续资产作为 scope 开启参数的观察路径，修复可能出现的 ScopeInputsMissing。

**交付：** 具有结构依据的持有与撤销规则，包括共享会话、实际实例、排队交付和历史资源的关系。规则明确后再进入清理实现。

<a id="stage-6"></a>
### Stage 6：实现 end 与终止传播

区分来源正常结束、失败、取消和消费者退出。确定停止发布、处理已接受增量、结束消费单元、结束派生输出之间的顺序，以及等待数据的任务如何被唤醒。

定义 lifelong 结束后如何向外层 chained／parallel 返回；一个消费者退出时，其他消费者仍在使用的来源应保持存续。正常结束是否排空、end 的手写接口及作用范围、多来源单元遇到结束的行为都须先确认，不能把此前的建议写成已定协议。

当前含 lifelong 程序的失败仍按临时规则终止整次运行。是否改动故障传播范围须在本阶段明确；增加正常结束不自动意味着已经具备局部故障恢复、回滚或自动重试。

**交付：** 正常结束、失败和取消各自的完整传播路径。持续程序能够正常结束，外层 workflow 可以按定义继续；暂时无数据、单次成功和整条流结束有明确区别。

<a id="stage-7"></a>
### Stage 7：接通自动清理

把退出路径接回 Scoped.close、[按可达性回收](#scope-gc)和 ScopeTree：

    停止新增执行
    → 协调在途工作
    → 撤销订阅与资源持有
    → 减去不再可达的待用计数
    → 执行 close

统一处理共享资源、待交付绑定、历史中的资源引用与关闭失败。会话停止与物理释放的调用关系须明确，不能在回调内等待包含自身的全部回调退出。

历史保存引用不自动证明底层资源仍可操作。可用历史资源的持有、释放后旧绑定的行为，以及普通数据历史的保留须分别明确。某个 scope 释放失败时，仍处理其余可安全清理的资源；失败只记录并报告，不改变业务结果。

**交付：** Stream effect 与 lifelong 共用按可达性回收的收尾协议，不提前释放。同步所属规范、生成结果、结构展示和 demo。

<a id="review"></a>
## 实现前需要收敛的接口

| 事项 | 所属阶段 | 审查产物 |
| --- | --- | --- |
| 每个资产唯一来源与显式接收形态 | Stage 1（已确认，接收形态由 Stage 2 取代） | Effects、类签名、instance 和检查规则 |
| handler 复用、前驱装配与读取路由 | Stage 2（已实现） | 注册、生成契约、handler、生成装配与检查规则 |
| 可见范围内的等待：parallel 兄弟可见、等不到的读取、按执行帧的资产 state 与等待结束 | Stage 2（已确定，未实现） | 可见关系、来源分析与运行时读取规则 |
| scope 的单例与多例（`requires`／`requests` 进入 scope）、按可达性回收、运行结束关闭、close 可选 | 独立于阶段（已确定，未实现） | 开启位置的类别、实例身份、可达的边与计数的更新时点 |
| 共同执行协议与两种入口的对应 | Stage 3 | 单步、推进、发布和边界的关系 |
| 当前值、历史与显式刷新 | Stage 4 | 访问权限、视图位置与发布规则 |
| 会话与 lifelong 单元接入可达性的根集 | Stage 5 | 根集的建立、撤销与持续资产作为开启参数 |
| end 接口、退出范围与交付收尾 | Stage 6 | 正常结束、失败、取消和 branch 返回规则 |
| 历史资源与自动回收 | Stage 7 | 共用的关闭条件及释放顺序 |

这些是待审查的接口与协议，不是已经批准实施的具体语法。线程、锁、等待者唤醒和使用登记的内部实现由 SDK 承担，不要求原子 handler 作者管理调度。

<a id="current-limits"></a>
## 当前限制如何纳入本轮

| 当前事实或缺口 | 本轮处理位置 |
| --- | --- |
| 多个资产／访问方式合法；方法体主动取值，检查显式接收形态，不添加位置参数 | Stage 1，接收形态由 Stage 2 取代 |
| handler 绑定在 Input 链上：方法体显式调用上游，同一操作按 effect 重复书写 | Stage 2（已解决：handler 可复用，前驱由 gencode 装配） |
| parallel 兄弟互不可见，读取不能被并发发布唤醒；可见范围内没人生产的读取一直等待 | Stage 2（[已确定，未实现](#stage-2-await)） |
| 持续资产的当前值与历史读取 | Stage 2 已实现缓存语义（requires 读最新值，streams 读历史）；Stage 4 收敛视图与读取写法 |
| readHistory 未经过 scope 开启参数观察，可能报 ScopeInputsMissing | Stage 4–5 |
| 会话步骤共用 scope 使用登记；停止后主要依赖 interpreter 退出清理 | Stage 5、7；运行结束时的回收见[按可达性回收](#scope-gc) |
| 无正常 EOF／Done，lifelong 只能因失败或取消退出 | Stage 6 |
| 含 lifelong 程序的失败使用整次运行终止的临时规则 | Stage 6 明确保留或调整范围 |
| 历史资源缺少精细持有和释放协议 | Stage 4、5、7 |
| 完整历史持续增长，没有容量背压 | 本轮只明确退出与资源释放；容量和历史策略另议 |

<a id="deferred"></a>
## 本轮之外保留的开放事项

以下从原计划迁入，不作为本轮实现的前置条件，也不因记录在此就视为决定新增语义。

| 专题 | 保留的问题 |
| --- | --- |
| 背压与历史容量 | 容量、溢出策略、历史窗口、慢消费者、无订阅者行为，以及同步 request 回馈与有界队列的进展问题；完整历史不承诺有界内存 |
| workflow 扩展 | 嵌套 lifelong、多个持续来源组合触发一个 target |
| 来源与调度 | Stream 的 event、behavior（轮询）、socket 三种驱动方式；自动重试、时间周期声明、通用外部 push callback 注册；阻塞单步来源可用不代表任意回调 API 已自动适配 |
| Pure 与原子输出 | Pure 作为生产链中的值变换已实现（[Pure 的值管道](#pure-pipeline)）；带类型的原子输出（注册声明输出类型）、交出嵌套结构（森林）、Pure 挂在 Stream 下仍待设计 |
| Generic Map | 适配范围、失败接口和接入；当前没有可用自动适配 |
| 多细化资产 | 同一个 handler 服务多种细化资产已由 Stage 2 以多份注册解决；同一个注册服务多种细化资产仍不支持 |
| 同类二元操作 | 一次操作需要两个同表示类型的值时，Stage 2 先用角色类型区分；是否需要其他写法待定 |
| 模块与接口 | 多方法 effect 的入口与结果契约、独立生成模块组合、跨语言 schema |
| 资源协议扩展 | 其他 cleanup policy、Linear 关闭凭证、任意逸出资源跟踪、未发布部分获取恢复、跨独立 interpreter 存续 |
| 故障恢复 | Error 驱动链：resolve 如何驱动 scope 修复（Stage 2 起 resolve 不调用 close）；已展开 continuation 的恢复、跨调用诊断范围；当前 Error 处置成功仍传播原失败 |

<a id="middleware"></a>
### Middleware 与 Hanging

独立 Middleware typing、装卸策略及其与 [Root 入口包装](LATEST_DESIGN.md#calls)的关系，保留为后续独立专题。Hanging 随之确认；不沿用旧 loop 说明替代 lifelong 规范。本轮七个阶段不以新增 Middleware 类别为前提。

<a id="external-tools"></a>
### 外部工具与后续观察

- 将 LSP 仓库已有的来源可见性穷举模型扩展到 Stream／lifelong，覆盖订阅、会话可见性和单元划分。
- 外部 LSP 按自身需要消费 SDK 原型与诊断；协议和展示格式在工具侧设计，不为其增加 SDK 专用导出。
- 读取点来源、资产细化建议与模块引用索引的可视化。
- 并发交错、认领与使用交接、长时间内存及跨平台取消仍有观察边界，不把这些开放项转成未经确认的新测试门槛。

<a id="baseline"></a>
## 已有基础与验证边界

以下压缩自原计划的历史记录，不代表本次重新执行。逐次修复与探针细节保留在 Git 历史。

- 原 Stage 1/2 已实现统一 Prototype、RuntimeGraph、来源路由和 ownership 修复；原 Stage 3 已实现 Stream／lifelong 初版，当前保证见 [STREAM_LIFELONG](STREAM_LIFELONG.md)。
- 2026-11-01：Stage 2 外部来源可见性穷举模型已完成既有基线核对；尚未扩展到 Stream／lifelong。原计划中更早的“Stage 2 外部模型未完成”已被此记录取代。
- 2026-11-01：会话启动登记、完成信号、停止期间新建会话与伴随发布等修复已记录验证；来源分析按消费单元裁剪再组合的修复通过生成与普通编译。相关状态组合仍可能指数增长，没有整体线性复杂度保证。
- 2026-11-02：资产声明改为 Asset @表示类型 "资产名"；Stream 下的解析器以 getT 直接引用原始 Stream 方法，由会话提供本次输入。原计划记录普通编译、六个程序生成、五个有限 demo 及 StreamDemo 中断观察通过。
- 2026-11-04：本轮 Stage 1 落地每个 refined asset 的唯一来源、统一访问结果规则与 GHC 源码接收检查；整理 SDK／Generated／Program 门面和 Prototype 内部分工，六个 demo 已重新生成，`cabal build all --offline -j1` 通过。生成包含手写模块的 GHC 类型检查与资产接收检查；未新增测试、未运行业务 demo，未验证全部 GADT 匹配或并发交错。现有来源分析与 runtime 调度算法保持。
- 2026-11-07：[FacadeProbe](../demo/FacadeProbe/README.md) 以手写的生成结果验证共享 handler：同一 handler 配不同 Input 与 demand、共享 Scoped 开关、挂接 parser、Stream parser 与 lifelong 消费者均可运行，非交错输出与显式写法一致。这次验证没有修改生成器；Stage 2 的读取路由改为编译期标签。
- 2026-11-08：Stage 2 设计确认；独立的标签探针以 GHC 9.12 编译运行，确认按 effect 标签选择读取与 `raw` 时方法体无需改写。
- 2026-11-08：Stage 2 实现并全面替换旧写法；`cabal build all --offline -j1` 通过，七个程序重新生成并与迁移前输出对照，详见[实现与验证](#stage-2-status)。
- 2026-11-08：SDK 按[源语言、gen、编译产物、运行时四层](LATEST_DESIGN.md#compiler)重组，生成拆为读取、降级、绑定、形状、组成、构图、输出、类检八个阶段，[流水线](LATEST_DESIGN.md#generation)在 `Framework.Gen`；声明加载进程只执行降级，绑定与输出改在生成器进程内读取 PrototypePlan；生成代码只经 `Framework.Generated` 引用 SDK。验证：`cabal build all --offline -j1` 通过；七个程序重新生成，除生成代码的模块别名与资产目录的导入外，Generated 与重组前逐字相同；FileDemo、OpenFilesDemo、ScopeReuseDemo、ScopeInstancesDemo 各运行两次，输出与写出的文件和重组前相同，StreamDemo 在终端运行到第 33 条读数后 Ctrl-C，读数、趋势、心跳节奏与 `[sensor] disconnected` 收尾和重组前一致，Crawler 除随请求变化的链接行外相同；FacadeProbe 按 README 编译运行，仍以 `ShowLevelFailure` 结束。重组不改运行行为。
- 2026-11-08：`requires` 改为不生产、缺值等待，读取权限只在生成期检查，规则见 Stage 2 [实现与验证](#stage-2-status)的“读取”。gen 侧读取方法不连到生产方法，来源分析中没有可见发布的读取路径不返回，生产入口每次调用都生产；运行时以发布信号唤醒等待的读取。FileDemo 的 `FileResource` 补 `requests "FileName"`，FacadeProbe 的 `ReportFile`／`ReplyFile` 补 `requests` 路径、`WriteReport`／`WriteReply` 补 `requests` 正文。验证：`cabal build all --offline -j1` 通过；七个程序重新生成，生成的来源表中没有 `FromOwnChain` 读取；FileDemo、OpenFilesDemo、ScopeReuseDemo、ScopeInstancesDemo 各运行两次，输出与写出的文件和本次改动前相同；Crawler 除随请求变化的链接行外相同；StreamDemo 在终端运行到第 48 条读数后 Ctrl-C，读数、趋势、心跳节奏与 `[sensor] disconnected` 收尾一致；FacadeProbe 按 README 编译运行，输出行相同（parallel 的交错顺序不同），写出的文件相同，仍以 `ShowLevelFailure` 结束。未覆盖：没有触发过真正等待的读取；兄弟间可见与等待的结束见[可见范围内的等待](#stage-2-await)。
- 2026-11-12：Pure 改为生产链中的值变换，Excu／Scoped 的输出改为 `[String]`，见 [Pure 的值管道与 list 原子输出](#pure-pipeline)。验证：`cabal build all` 通过；七个程序重新生成，与 main 对照运行，行为一致（Crawler 只差随请求变化的链接签名，FacadeProbe 只差 parallel 交错顺序）。Crawler 随后在抓取与解析之间加入 Pure，经 Pure 的注入在运行中走通。未覆盖：Pure 的 `raise` 与交出多项 list 的 handler。
- 历史验证未系统枚举全部并发交错，未观察长时间内存；Stream 外部模型未完成；取消只记录过 Windows Ctrl-Break。已通过编译和示例不能扩大资源逃逸、任意底层 IO 或所有调度的保证。

<a id="maintenance"></a>
## 阶段推进时怎样维护

每阶段先确认受影响的代码形态与协议，再实施；本文件更新状态和必要完成摘要，当前能力写回所属规范，GUIDE 随实际接口更新。不要将计划直接覆盖成当前运行保证，也不要另建重复的阶段清单。

只记录实际执行过的验证、日期和未覆盖范围，沿用仓库对普通编译及验证工作的约定。Stage 1、Stage 2 的结果见上方记录；历史验证不代表本次已经重跑。
