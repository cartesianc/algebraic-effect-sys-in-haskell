# Next stages

更新：2026-11-19。本文是阶段计划与开放项的唯一入口，保存各阶段的目标、剩余工作和必要的完成摘要。当前协议在[主设计](CORE_DESIGN.md)及其专题中维护；历史验证集中在[验证边界](#baseline)，不代表本次重新执行。

**当前进度：** handler 复用、scope 可达性回收、Stream 两侧结束、后继读取、交付保留和会话退役已落地。持续生产与有限取值的组合边界已经补齐，生成期无来源诊断、签名报错与组合设计收尾已完成；Receive 来源到 parser 的资源交接及示例 close 已修复，验证见[本轮记录](#receive-resource-verification)。[静态协议检查收口](#protocol-checks)已完成本轮范围，已补上既有 Binding ownership 的交付与执行保留，并进一步按会话待用帧回收不再使用的具体实例。Stage 5／7 已接通当前资产契约内的资源持有与回收，范围与验证见[阶段说明](#stage-5)；[普通 require 共享供值](#stage-2-await)也已实现。本轮已完成 [gen 决定归位](#gen-classification)，整理前端、Injector／Booter、计划与输出；[Stage 3](#stage-3)已按当前执行协议收尾，明确静态事实与动态生命周期的责任；[容量与背压](#backpressure)保留为延期专题，策略尚未确定。

<a id="code-shape"></a>
## 代码长什么样

沿[指南的同一业务示例](GUIDE.md#code-shape)查看资产、注册、instance 和 workflow；当前完整写法不在计划中复制。原子 handler 以 `instance XxxLayer m => XxxHandler m` 实现，业务 effect 绑定它并声明 Input／demands，gen 装配前驱和读取路由，入口保持 `main = interpreter ast effects`。

持续执行的写法见[指南第五节](GUIDE.md#stream)：Stream handler 用 `streamEnd` 结束来源，自身声明 `streams` 的 Excu 用 `endStream` 结束订阅。后续阶段若调整接口，先给出受影响的 Types、Effects、Handlers 和 AST 代码形态，标明“待确认／未实现”，确认后才更新当前指南。

<a id="scope"></a>
## 目标与边界

目标是在现有架构内统一持续执行、资产访问和资源收尾。保持原子 handler、业务 effect、Context 解析与 workflow 驱动的分工，以及 Prototype／RuntimeGraph 和独立无环 ScopeTree；不为实现方便增加 effect 类别、手写装配层、资源寿命标签或 cleanup policy。

资产引用的内存回收与 `Scoped.close` 管理的资源释放分别处理。释放引用不能替代关闭资源。完整设计原则见[主设计](CORE_DESIGN.md#principles)。

**资产边界（2026-11-18 确认）：** “任意业务 ADT 内嵌资源的自动追踪与保活”已移出当前阶段及开放任务，既有资源 Binding 的持有与 close 保证保留。详细范围统一维护在[资源契约](STREAM_LIFELONG.md#binding-retention)，字符串 rawoutput 与解析接口见[入口装配](CORE_DESIGN.md#calls)和[Context](CORE_DESIGN.md#context)。

<a id="stages"></a>
## 阶段地图

Stage 1–7 是本轮的编号，与早期 Prototype／RuntimeGraph、来源可见性、Stream 初版的阶段编号区分。阶段按职责划分，实际交付可以交叉；不是“前一阶段所有事项完成，后一阶段才存在”。原 Stage 5 与 Stage 7 已合并为一项资源生命周期工作，沿用 5／7 编号，不再分别实施和验收。

| 阶段 | 目标 | 当前状态 |
| --- | --- | --- |
| [1：输入契约](#stage-1) | 资产来源明确，读取可检查 | 已完成；旧接收形态由 Stage 2 取代 |
| [2：handler 复用](#stage-2) | 原子操作与业务装配分开 | 已完成；[共享供值与保守等待](#stage-2-await)也已实现 |
| [3：共同执行结构](#stage-3) | 对齐 Stream 与 lifelong 的推进、发布和结束边界 | 当前协议范围已收尾；静态事实与动态责任分别明确，验证范围见下文 |
| [4：资产访问](#stage-4) | 固定取值与重复启动分别计算 | 已完成；持续资产的资源持有留给 Stage 5／7 |
| [5／7：持续资产的资源持有与自动回收](#stage-5) | 统一持有、交接、撤销与 scope close | 当前契约范围已接通；不新增业务数据的资源依赖 |
| [6：结束传播](#stage-6) | 生产结束、消费退出、排空和 workflow 返回 | 已实现；局部失败仍延期 |
| [延期：容量与背压](#backpressure) | 限制未领取交付的积压，协调生产与消费进度 | 已确定需要解决；策略待收敛、未实现 |

<a id="composition-machine"></a>
### 统一组合计算

**已完成（2026-11-17）。** `Gen.Composition` 统一阶段转换、接口与装配事实，Emit 改为读取确定结果。声明、会话、绑定、构图与来源证明仍使用各自算法；这不是通用规则求解器，也未消除路径复杂度。设计依据见[组合逻辑的核心意义](COMPOSITION.md#why)，运行和资源协议保持不变。

本轮按以下顺序完成：

1. 核对原有规则和输入依赖，保留声明加载与首次契约生成的边界。
2. 将组合运算、内部工作状态和结果集中，输出阶段改用已确定的类型能力、读取视图与装配事实。
3. 同步设计与源码导航，删除被替代的算法模块，保留方法形状前端及各类输出模块。
4. 显式重新生成现有示例并做必要普通编译，核对 facade 与生成结果；实际结果记在验证摘要。

这项工作为后续组合判断提供单一落点，不新增用户语法、运行时调度机制、通用 IO 去重或额外资源持有规则。资源持有的当前完成范围见 [Stage 5／7](#stage-5)。

<a id="composition-review"></a>
### 当前收尾：组合检查与计算边界

**已完成（2026-11-17）。** 根据分支复查完成以下收尾；本轮生成与普通编译结果见[验证摘要](#baseline)：

1. 对已到达、在所有已分析路径均无合法供值或捕获的普通读取，增加生成期拒绝；条件生产、会话、资源与收尾仍保留原有处理，详细边界见[静态无来源诊断](EFFECT_GRAPH.md#missing-source)。该次收口没有改写取值规则；现行普通供值已由[共享供值阶段](#stage-2-await)更新，声明写法未变。
2. 共享 handler 签名冲突重新显示业务作者能读懂的类型与能力约束；纯结构的 Show／Read 表示保留。
3. 将阶段专用助手收进对应计算入口的局部作用域，只保留必要的跨阶段关系查询；统一状态转换与既有阶段次序不变。
4. 吸收 `docs/composition-polymorphism` 的核心理念补充：README 与设计原则突出组合多态，COMPOSITION 保留理念、产物与规则定位，状态／检查点归主设计流水线，缓存归图规范。文档不把现有阶段机描述成逐元素解释表或通用求解器。

这批收尾不实现 Stage 5／7 的资源持有，也不把历史编译或其他分支的 demo 运行作为本轮验证。

<a id="protocol-checks"></a>
### 静态协议检查收口

**本轮完成（2026-11-17）。** 在 Stage 5／7 之前补齐既定读取契约的最低限度检查。按触发条件梳理 14 种运行时协议故障，区分结构违规、运行状态和 SDK 不变量；详细归属只在[图规范](EFFECT_GRAPH.md#protocol-faults)维护。

本轮新增：有资源的 Scoped 按 close 的方法绑定检查资源读取，open 或其他方法的读取不代替它。open 入口按 requests 生产并认领资源，方法体为空仍合法。沿用组合计算的类型路由，首次契约生成跳过、已有方法体时在图缓存前检查；无资源 scope 和可选 close 保持现有规则。参数生产身份、IO 顺序、条件路径和运行时防线保持原协议，不扩展 Shape 或引入新语法。

该次交付以这项检查和 14 种故障的边界说明为限；后续共享供值与资源持有的完成状态分别见[等待阶段](#stage-2-await)和 [Stage 5／7](#stage-5)。实际验证及未覆盖范围见[验证摘要](#protocol-checks-verification)。

<a id="composition-driving"></a>
### 持续生产与固定取值的组合

**已完成（2026-11-17）。** 按用户明确的组合语义，A 可以随 B 的持续交付继续生产，而普通链 C 只读取 A 的一次固定值。驱动不沿任意取值依赖传播。两种读取均使用资产声明的表示类型；累计记录等是业务节点的结果，不是 SDK 的特殊历史类型。

本轮落点：

1. 在 Gen.Composition 中统一计算生产计划和读取方的驱动关系；有限读取可按独立 Receive／Derive 计划建立所需上游，保留已有 ReuseOutput 的实际 AST 输出连接。
2. 去掉 SDK 给 streams 额外套历史类型的实现；handler 按声明 T 读取。旧实现把 streams 与完整历史前缀绑定，需要同步示例，不能把这项纠正描述成旧接口字面不变。
3. runtime 只执行计划：重复推进在生产会话或 lifelong 中发生，普通读取捕获一次值后继续；交付队列只保存未领取值与最新值。
4. 示例将计数、平均值或记录保存放回业务资产和原子 handler；不新增 effect 类别、声明关键字或 history 名称识别规则。

具体规则归 [Stream 读取与驱动](STREAM_LIFELONG.md#contracts)及[有限读取](STREAM_LIFELONG.md#production)。该次工作未放开 requests 持续资产，也未引入容量背压。本轮生成、编译及未覆盖范围见[验证摘要](#composition-driving-verification)。

<a id="stage-1"></a>
### Stage 1：资产来源与接收契约

**已完成。** 保留的核心是：每个 refined asset 对应固定表示 ADT 和唯一 Context 来源；访问方式不另造资产身份，一个消费者可以依赖多个资产。当前约束见[资产来源与访问](CORE_DESIGN.md#demand-contract)。

早期要求 handler 显式匹配生成资产构造器，后来妨碍同一原子操作在不同来源间复用。该接收检查和 Context 的 request 角色已由 Stage 2 取代，不再把旧写法作为候选接口保留。

<a id="stage-2"></a>
### Stage 2：原子 handler 与业务 effect 分离

**已完成（2026-11-08）。** 原子性落在 handler；多个业务 effect 可以绑定同一 handler，各自决定 Input 和 demands。生成器按“表示类型 + effect”路由读取，业务来源由注册明确指定，不按谁先生产来竞争。

这解决了“同一个写入操作因为来源不同而重复实现”的问题。alternative 处理同一资产的构造器分支，不能替代跨 Context 来源的装配；无需为复用新增 `resource`、`oneOf` 或链路 newtype。handler 定义共享不合并实际调用。

当前写法与检查分别见[指南：handler](GUIDE.md#handlers)、[注册契约](CORE_DESIGN.md#registration)、[入口装配](CORE_DESIGN.md#calls)和[源码资产约束](ASSETS.md)。SDK 四层分工见 [gen 是编译器](CORE_DESIGN.md#compiler)。

<a id="stage-2-later"></a>
持续资产的取值与驱动归 [Stage 4](#stage-4)；Error 驱动链、来源调度扩展等归[开放事项](#deferred)。现有 socket／event／behavior 的单步写法见 [Stream 规范](STREAM_LIFELONG.md#drives)，不把自动分类或外部回调适配说成当前能力。

<a id="stage-3"></a>
### Stage 3：Stream 与 lifelong 的共同执行结构

**当前协议范围已收尾（2026-11-18）。** Stream 的生产步骤与 lifelong 单元都按“等待推进条件 → 有限执行 → 发布 → 继续或结束”组织；前者从 Context 需求启动，后者从 AST 启动，通过资产连接并独立推进。

本阶段的完成标准是：静态驱动事实有唯一来源；两侧实际调用复用身份与固定捕获协议；实际使用、未来待用和 Binding 保留各有撤销边界；结束、失败与取消之后进入既有收尾和 scope GC。Booter 完成第一项，Runtime／Execution 及 Stage 5／7 的共用基础承接后三项。模块与协议的对应只在 [Stream：共同执行结构](STREAM_LIFELONG.md#execution-boundaries) 维护。

本轮源码核对后保留已有算法，只修正 Runtime、Execution、App 的职责注释与过期文档；未新增共同调度器，不把两种循环串行化，也不宣称前端 ADT 已有同构证明。当前范围完成不代表背压、局部失败恢复、嵌套 lifelong 或新的释放策略已经实现，它们仍在各自专题中。

**本轮验证边界：** 仅核对既有调用、捕获、结束／退役与回收路径，检查改动范围；没有修改可执行逻辑、facade、demo 或 Generated。未重新编译、运行 demo 或并发探针；源码核对不是全部调度交错的运行证明。

<a id="stage-4"></a>
### Stage 4：资产取值与驱动边界

**已完成（2026-11-17）。** requests 驱动普通资产生产；requires 只取值；streams 在持续执行位置接收增量驱动。handler 都按声明的表示类型 `require @T`，SDK 不附加历史业务类型。普通链读取派生持续资产时，gen 建立其独立生产计划，读取者不继承订阅。完整协议见 [Stream 读取](STREAM_LIFELONG.md#contracts)与[生产和有限读取](STREAM_LIFELONG.md#production)。

一次捕获保留原 Binding 的生产身份；之后的发布不改写本次值。T 若包含业务记录或累计状态，仍作为业务表示处理，不改变唯一 Context 来源。持续资产仍不能 requests。

资源持有已由 Stage 5／7 接通：协调未领取交付、已捕获值、伴随发布中已知的 ownership，与实际执行和持续待用的关系；不设计特殊的历史读取语法，也不为普通解析数据增加资源依赖。

<a id="stage-5"></a>
<a id="stage-7"></a>
### Stage 5／7：持续资产的资源持有与自动回收

**本轮范围已经收敛并接通实现（2026-11-18），验证见[会话实例回收记录](#session-scope-verification)。** Stage 5／7 合并处理实际执行、持续待用与已有 Binding ownership 的持有、交接、撤销和 close。本阶段按上述 rawoutput 资产边界完成；普通 parser／Pure 的产物不因生产使用过资源就继承其寿命。

**代码形态保持不变。** 沿用资产 ADT、Input／demands、原子 handler 和现有 Stream／lifelong 出口；业务仍只在 Scoped 的 close handler 中实现释放操作，不手写 layer、保活或释放调用。业务累计数据不作为 SDK 的特殊历史类型。

本轮完成以下内部工作，详细协议只在[资源边界](STREAM_LIFELONG.md#binding-retention)和[图的待用查询](EFFECT_GRAPH.md#scope-opening-retention)维护：

1. **已知绑定的交接。** 保留 Runtime.Retention 的执行捕获与队列资源索引，限定在既有 ownership 和声明资源的共享归属单元；领取先建立执行保留，再撤销队列保留。普通解析数据不建立额外依赖。
2. **生产步骤与持续待用分开。** Receive 的来源与 parser 共用本步 ScopeUser，Derive 每次处理独立登记；本步完成后撤销实际使用。会话复用生成的挂载与开启计划，建立后续步骤的待用帧，以固定捕获和实际参数生产身份匹配具体实例，不累积持有所有历次实例。
3. **统一回收条件。** 新 request 不直接关闭旧实例；仍有实际使用、合法待用、已有 ownership 保留或保留它的子实例就继续保留。参数不再匹配的旧实例在失去这些关系后进入现有 scope GC。source end 保持已有排空与退役边界，任务退出时撤销会话预约；重复停止继续等待收尾。
4. **会话目录与回收协调。** GC 读取在 worker 启动前已登记的会话快照，不因目录装配暂忙而无条件保留不相关实例。沿用 ScopeTree、关闭预约、取消传播与关闭失败只报告、不重试的协议，不另建回收器。
5. **规范组合计算的使用。** 对照 `SessionProto`、`ScopeOpening`、`Source` 与 `ScopeTree` 写明每项资源行为的静态依据和动态落实，复用已有产物，不在 runtime 再推导结构或猜测业务类别。维护规则集中在 [COMPOSITION](COMPOSITION.md#maintenance)，事实分工归[图规范](EFFECT_GRAPH.md#scope-opening-retention)；本轮没有新增 gen 算法或三种来源的自动分类。

**完成标准与边界。** 单例／多例只描述实例与参数生产的关系，使用是否耗尽决定 close。轮询、event、socket 按相同结构规则覆盖，不宣称 SDK 已从原子 IO 自动识别三种业务。读取值、来源可见性、已捕获 Binding 的身份与归属保持不变；旧资源绑定仍检查原 owner 的关闭／失败状态，不自动重开或换 owner。编译与源码核对不能证明全部取消交错、任意外部 IO 或资源逃逸安全。

<a id="stage-5-foundation"></a>
**持续最新值参数（2026-11-17）：** gen 为会话参数保存显式开启计划；runtime 登记实际选中 Binding 的 `ActivationId` 与原生产帧，固定交付与后继读取按相同来源规则参与回收。handler、demand、AST 写法不变。完整规范见[开启计划与待用](EFFECT_GRAPH.md#scope-opening-retention)。此项只观察既有 Binding 的身份，不扩展资产传递契约。

**已完成的基础（2026-11-16）：** 普通后继按实际当前／保留绑定参与待用判断；轮间发布交接与回收共用协调锁；并发停止会话等待同一收尾完成信号。详细规则见[开启计划与待用](EFFECT_GRAPH.md#scope-opening-retention)和[会话协议](STREAM_LIFELONG.md#sessions)。持有范围沿用既有资源绑定协议。

<a id="stage-6"></a>
### Stage 6：结束与终止传播

**生产侧结束、消费侧结束及以下配套已实现（2026-11-14 至 17）。** 这解决了持续程序只能靠失败或取消退出的问题；正常结束可以让外层 workflow 继续。当前失败仍采用整次运行终止的临时规则，局部恢复未实现。

- **来源结束与 workflow 返回**：`streamEnd`、排空、单元结束和 lifelong 返回；规则见[正常结束](STREAM_LIFELONG.md#end)。
- **后继读取**：普通资产按[共享供值](#stage-2-await)读取最新发布，调用捕获保持固定，切轮不清空共享普通值；持续资产的结束会话与固定交付仍按[正常结束](STREAM_LIFELONG.md#end)协议读取。

<a id="stage-6-retention"></a>
**引用保留基础（2026-11-14）：** 只保留仍有读取义务的数据；本轮改为交付队列与最新值，不再由 SDK 承诺完整业务历史。当前保留协议与复杂度见[会话保留](STREAM_LIFELONG.md#retention)。

<a id="stage-6-derive"></a>
**独立派生（2026-11-15）：** 由持续资产驱动的操作可以经 parser 产生另一份持续资产，补上消费结果再次成为资产的表达。原先禁止这类操作挂入 AST 的限制已由下一项输出复用取代。规则见[派生与输出复用](STREAM_LIFELONG.md#derive)。

<a id="stage-6-reuse"></a>
**同次输出复用（2026-11-15）：** gen 将消费操作的实际 AST 发布位置连接到挂接 parser，保留生产与消费分链，同时避免为解析重跑原操作。LinesDemo 的 `TextCounter`／`RunningTotal` 展示这一组合；完整写法见[指南](GUIDE.md#stream)，合法性见[生产连接](STREAM_LIFELONG.md#bootplan)。

<a id="stage-6-consumer-end"></a>
**消费结束与退役（2026-11-16 至 17）：** `endStream` 撤销当前订阅，按节点、单元和会话的读取关系协调停产；会话退役接入现有 scope 回收。规则与代码形态见[消费方结束](STREAM_LIFELONG.md#consumer-end)。

最后一轮修正的理由也保留在这里：同单元不证明生产已经完成，可能还有并行发布或尚未处理完的 Derive。因此只在本轮发布与派生处理稳定后跳过；发布节点结束须及时封口；取消不能把未完成的退役记为完成。完整判定维护在上述规范中，旧的“同单元一律不等待”方案已删除。

<a id="gen-classification"></a>
## 本轮：gen 决定归位与 Injector／Booter

本节记录 `136c1b8` 相对 `4874ee8` 的编译器重构：保持 facade、原子 handler 与当时已有的运行协议。共享最新值是前一项工作的改变，见[版本边界](#version-boundaries)。先按下表迁移决定，再整理模块；多个合法运行分支不等于歧义，只拒绝既有语义不能确定解释的组合。

| 决定／事实 | 重构前归属 | 本轮归属 | 静态／动态与完成条件 |
| --- | --- | --- | --- |
| Haskell 解析、声明加载、源码位置 | Source | Frontend.Source | 静态输入；沿用 GHC，不执行业务 |
| require/raw 与控制结构提取 | Shape | Frontend.Shape | 静态输入；不解释资产来源 |
| typing 对应的方法角色、绑定与名字 | Names、Composition | Composition；Names 仅拼名 | 静态解释只有一处 |
| 表示类型、Layer、读取路由、前驱与 raw 来源 | Composition.bindProgram | Injector | 静态装配；不重读原注册来另选策略 |
| scope/Error 回调与入口包装 | Composition、Emit.Handlers | Injector 的计划；Emit 渲染 | 静态装配；保持包装顺序与错误处理 |
| AST 编号、选择器、会话与输出复用挂载 | Composition | Booter | 静态驱动；沿用 NodeId、BootPlan 和 Assembly |
| 单元成员、帧位置、订阅与经 Derive 的本地来源 | Execution | Booter → Prototype | 静态驱动；runtime 直接读标记 |
| 读取位置的会话边界、选择捕获祖先、供值进展关系 | Graph、Runtime | Booter → Prototype | 静态关联；不改变捕获优先及共享供值 |
| 交付、游标、已结束位置、活动 Origin 与 scope 持有 | runtime | runtime | 动态状态；不前移、不新增调度器 |
| 源码约束检查与资产目录提取 | Assets | Check.Assets | GHC 类检；返回结构化目录 |
| Haskell 文本与资产目录文本 | Emit、Assets | Emit | 允许渲染构造器，不重新选择解释 |
| 资产目录的纯元数据类型 | Gen.Catalog | Prototype.Catalog | 编译产物不依赖 gen |
| 缓存、检查点、原子方法原文与文件写入 | Gen、Source、Emit | 原职责保留并更新依赖 | 不跳过检查，不隐式生成 |

**实施状态：** 清单中的模块迁移、Injector 装配与 Booter 静态驱动标记已接入，显式生成与全项目普通编译通过；具体范围见[本轮验证](#gen-classification-verification)。内部计划与 Prototype 可以有阶段转换，但不独立维护两份相同决定。静态关联迁移不替换取消、锁、会话退役或 scope 回收协议。

**验收边界：** 必要的显式生成和普通编译；允许模块路径、元数据与计划接线改变生成文本，不把字节变化等同于语义变化。不新增测试或负例。该次重构只完成 Stage 3 的静态驱动部分；后续的生命周期核对与完成范围见 [Stage 3](#stage-3)，不把 Booter 重构当作全部运行协议的实现。

<a id="version-boundaries"></a>
### 与共享供值之前版本的边界对照

比较基线为 `aadc8be`；共享供值由 `4874ee8` 引入，编译器重构为 `136c1b8`，`1255849` 合入 main 文档并明确确定性的范围。

| 范围 | 变化及保留 |
| --- | --- |
| 业务写法与能力 | 六种 effect、workflow、handler 复用、beforegen 接口与运行入口保持；本轮没有移除这些能力 |
| 普通资产 | 从 AST 许可来源改为运行级共享最新值；普通值跨 AST 位置与轮次共享，调用捕获仍固定。具体版本可受调度影响，见[共享供值](CORE_DESIGN.md#await-visibility) |
| scope | 关闭条件与生产身份不变；待用匹配改为固定捕获或共享最新参数，因此实例保留时间可随实际使用改变，见[可达性回收](CORE_DESIGN.md#scope-gc) |
| 持续交付与资源 | 会话、游标、结束、退役及 owner 定位保留；普通共享供值没有取消持续会话的选择约束，也没有开放链外资源读取 |
| gen 与 runtime | Injector／Booter 接管静态决定，runtime 读取 Prototype 标记；实际交付、取消、使用与回收仍由 runtime 执行 |
| 内部接口 | 部分 gen 模块路径和 Prototype 格式改变；工具调整 import、程序重新生成，见[内部接口迁移](CORE_DESIGN.md#sdk-migration) |

按帧 TVar 迁移不再是共享供值的实施前提，它此前属于计划而非已交付能力。背压、嵌套 lifelong、局部失败等仍按[开放专题](#deferred)管理。此表记录语义与结构边界；运行验证的覆盖范围以各提交记录为准。

<a id="gen-classification-verification"></a>
**本轮验证（2026-11-18）：** 八个命名空间已显式重新生成，最终 `cabal build all --offline -j1 -v0` 通过，退出码 0。对照本轮修改前保存的生成产物，八份 `Generated/Effects.hs` 和八份 `Generated/Handlers.hs` 均未变化；`Generated/Program.hs` 仅增加 `protoDriving`，`Generated/Assets.hs` 仅改为导入 `Prototype.Catalog`。手写 facade 与业务 handler 未修改。按工作约定未新增测试、负例或运行业务 demo；运行关系的迁移做了源码对照，取消交错、会话退役及 scope 回收未做本次运行实测，普通编译不能代替这些验证。

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

<a id="review"></a>
## 哪些仍需要单独设计

本轮 Stage 5／7 不再等待新的业务选项。既有 ownership、执行使用、持续待用及关闭后的原绑定检查沿已确认协议实施；持有只能延长合法资源的使用期，不能扩大读取许可或替代首次获取。

下面这些涉及尚未区分的使用关系或新的保证范围，需要单独设计：

- **ScopeTree 的保守父依赖。** 按已确认方向保留由 Input 推导的宽依赖关系，不自动断边或按新参数替换旧父引用；[长期子实例保留历史父实例](EFFECT_GRAPH.md#scope-parent-retention)继续作为已知代价。将来在生成产物层人工精简边的能力不在本轮处理，也不作为背压的前置任务。
- **更早停止或更早释放的策略。** interpreter 托管会话的停止时机、来源 end 后绕过现有退役边界的提前释放，以及新 cleanup policy，均不包含在此次内部回收修正中。
- **持续调度与恢复。** 背压作为[延期专题](#backpressure)；自动重试、event／behavior／socket 的业务分类以及 lifelong 局部失败继续独立设计。

普通共享供值的进度见[等待阶段](#stage-2-await)；本次不改变 facade 或增加用户寿命标签。

<a id="current-limits"></a>
## 当前限制与检查边界

| 限制或未覆盖边界 | 归属 |
| --- | --- |
| 普通供值已跨 AST 位置共享；固定点与保守耗尽仍不证明所有等待都可结束 | [共享供值与等待](#stage-2-await) |
| 长期子实例可能保留历次共同使用的父实例；当前保留宽依赖，不自动断边 | [父引用边界](EFFECT_GRAPH.md#scope-parent-retention)、[待设计项](#review) |
| 同单元直接或经 Derive 等待 Scoped.open 的复用输出被保守拒绝：复用实例不产生新输出；必定 fresh 的精确放行未做 | [输出复用规范](STREAM_LIFELONG.md#derive) |
| 未领取交付没有硬容量与背压上限 | [延期：容量与背压](#backpressure) |
| interpreter 托管会话和 ReuseOutput 各自沿用已有停止规则 | [退役规则](STREAM_LIFELONG.md#consumer-end) |
| 含 lifelong 程序的失败仍终止整次运行 | [临时失败协议](STREAM_LIFELONG.md#failures) |
| 生成期无来源诊断只覆盖已分析的普通读取点；合法来源在部分运行路径不发布仍由 runtime 处理，不证明全部等待可结束 | [本轮收尾](#composition-review)、[静态无来源诊断](EFFECT_GRAPH.md#missing-source) |
| 来源状态与 scope 路径仍可能指数增长；共享通知存在多余唤醒，尚无大规模性能与长期堆占用实测 | [图与来源](EFFECT_GRAPH.md)、[会话复杂度](STREAM_LIFELONG.md#retention-cost) |

<a id="stage-2-await"></a>
## 普通 require 的共享供值与等待

**语义边界已确认（2026-11-18）：** 保留共享最新值；确定性约束 refined asset 对应唯一 Context 来源及装配规则，不要求每次捕获同一次生产。并发更新导致的取值差异按现有协议处理，不新增拒绝这类普通读取的检查。原则见[主设计](CORE_DESIGN.md#composition-polymorphism)。

**已实现（2026-11-18）。** 根据本轮确认，任意位置实际生产的同一 refined asset 都可供普通 require 使用。gen 以有限供值固定点替代 AST 可见性过滤，保留最低限度的无来源／无法启动诊断；RuntimeGraph 维护每资产最新 Binding，调用捕获优先。执行帧继续支撑进度、参数生产身份与 scope 待用，切轮不清空共享普通值。详细协议与算法只在[主设计](CORE_DESIGN.md#await-visibility)和[图规范](EFFECT_GRAPH.md#missing-source)维护。

不改变 handler、注册或 AST 写法；Stream 固定交付、资源 owner 定位及清理协议保留。按帧 TVar 迁移不再作为任务前提。完整等待环分析、任意业务 IO 进展与性能测量仍不承诺。

本轮八个命名空间已显式重新生成，仅 ScopeReuseDemo 的来源与开启计划发生变化；最终 `cabal build all --offline -j1 -v0` 通过，退出码 0。按工作约定未新增测试、负例或运行业务 demo；共享供值的并发交接、参数替换后的回收及保守等待结束仅作源码核对，不将编译通过记作运行验证。

## 已完成的共用基础

<a id="gen-assembly-sharing"></a>
### gen 装配与共享分析（2026-11-16）

装配结果统一末端、选择器、会话步骤和输出连接，方法图按定义缓存归约摘要。其计算本轮并入[组合状态机](#composition-machine)，继续与 Emit 共用结果；没有引入通用调用去重、业务结果缓存或 scope 同值复用。规则见[装配与复用边界](EFFECT_GRAPH.md#reuse-boundary)。

<a id="pure-pipeline"></a>
### Pure 与 list 原子输出（2026-11-12）

Pure 成为生产链中的值变换，Excu／Scoped 的原子输出统一为 `[String]`；parser 继续负责把输出变成资产。它分开了值变换与细化解析的职责，取代旧守卫接口。当前写法、位置限制和失败协议见[主设计：Pure](CORE_DESIGN.md#pure)，不重复迁移清单。

<a id="scope-gc"></a>
### scope 身份、回收与关闭诊断（2026-11-13）

Binding 的生产身份与执行帧支持单例／多例匹配和待用分析；ScopeTree 保持独立无环。close 可选，普通关闭失败只报告，取消在其余收尾后传播。当前规则见[实例身份](CORE_DESIGN.md#scope-identity)与[可达性回收](CORE_DESIGN.md#scope-gc)。这些已是持续执行清理的基础，后续不另建一套实例或回收器。

<a id="deferred"></a>
## 保留的开放专题

以下不作为持续资源清理的前置条件，也不因列在此处就批准新增语义。

| 专题 | 仍需确定 |
| --- | --- |
| 来源与调度 | 是否区分或自动推导 event／behavior／socket；自动重试、时间周期声明、通用外部 push callback 适配；已有单步写法见 [Stream](STREAM_LIFELONG.md#drives) |
| 嵌套 workflow | 单开专题讨论嵌套边界的驱动与结束。当前 `lifelong` 内可组合 `chained`、`parallel` 和 `alternative`；`lifelong` 内再次挂载 `lifelong` 由 gen 拒绝。见[现行规则](STREAM_LIFELONG.md#static)。 |
| 持续组合 | 多来源组合触发同一 target、派生步骤跳过与显式反馈 |
| 值操作与适配 | Pure 挂在 Stream 下、Generic Map |
| 资源协议 | Stream close 接口是否需要；scope 同值复用、其他 cleanup policy、未发布的部分获取恢复、跨 interpreter 存续；均不扩展为普通业务资产内嵌资源的自动追踪 |
| 故障恢复 | Error 驱动链、常驻 scope 失效与修复、局部失败、已展开 continuation 恢复及跨调用诊断；当前 resolve 不调用 close，处置成功仍传播原失败 |
| 内存与诊断 | 业务惰性状态链是否需要处理，以及关闭失败记录长期累积的报告策略；强制求值或改变报告时机须另行确认 |
| 模块与接口 | 独立生成模块组合、跨语言 schema |

<a id="middleware"></a>
### Middleware 与 Hanging

独立 Middleware typing、装卸策略及其与 [Root 入口包装](CORE_DESIGN.md#calls)的关系单独设计，Hanging 随之确认。本轮不以新增 Middleware 类别为前提。

<a id="external-tools"></a>
### 外部工具与观察

LSP 仓库的来源可见性穷举模型尚未扩展到 Stream／lifelong；订阅、会话可见性、单元划分及来源可视化留在工具侧推进，不为其增加 SDK 专用导出。并发交错、资源认领交接、长期内存与跨平台取消的证据仍有限，不将这些观察项变成未经确认的新测试门槛。

<a id="baseline"></a>
## 完成与验证摘要

下表及已有验证段落各自注明所属工作，**不是后续修改的重跑结果**；当前资源交接修复的验证单独记在[本轮记录](#receive-resource-verification)。保留影响判断的结论与未覆盖范围，逐次探针、临时接口和被后续修复取代的方案查 Git 历史。历史编译与有限示例不能证明全部调度、任意业务 IO 或资源逃逸安全。

| 日期／工作 | 已有验证记录 | 仍需留意 |
| --- | --- | --- |
| 2026-11-19，gen 源码契约 | 八个命名空间重新生成，全部 Cabal 目标离线编译通过；FileDemo 的 `--structure` 显示原有两个 alternative 分支 | 本轮未运行示例的业务 IO |
| 2026-11-01，早期 Prototype／来源基础 | 外部有限来源模型完成既有基线核对；会话登记、ownership 与来源裁剪等修复记录了生成和编译结果 | 外部模型未覆盖 Stream；来源状态仍可能指数增长 |
| 2026-11-04 至 08，Stage 1／2 与四层分工 | 生成契约、HLS/GHC 类型检查、普通编译；七个程序生成并与迁移前输出对照 | 旧接收形态已被取代；业务输出对照不证明全部错误路径 |
| 2026-11-12，Pure／list 输出 | 生成与编译通过；有限示例、Stream 中断和 Crawler 经 Pure 注入记录了运行结果 | 当时未触发 Pure 的 raise、多项 list 及全部生成期拒绝 |
| 2026-11-13 至 14，scope GC／关闭诊断／保守等待 | 生成、编译、有限 demo；受控探针覆盖缺值唤醒、取消、close 普通异常及诊断期间取消；旧版对照复现吞取消与本链自锁 | 未穷举并发交错、所有多参数与条件发布组合；会话链等待未完整迁移 |
| 2026-11-14，来源 end／后继读取／历史保留 | 编译、生成、LinesDemo 和有限 demo；临时探针观察排空、半截执行、启动许可、零发布、后继最新值及历史保留 | 没有堆测量；早期仅来源 end 的资源时机已被会话退役取代 |
| 2026-11-15，Derive／ReuseOutput | 八个命名空间生成、编译；派生与两级派生观察，LinesDemo 四行统计及最终 4 行／40 字符，结构显示无独立 ReuseOutput worker | 当时未逐项实测失败、取消及 Scoped 同单元拒绝 |
| 2026-11-15 至 16，构建整理／gen 装配共享 | 普通编译；装配重构后八个命名空间重新生成均无文件更新 | 未做性能实测，不宣称消除指数上界 |
| 2026-11-16，普通后继待用／停止交接 | `cabal build all --offline -j1` 通过；源码核对来源、帧归属与协调锁 | 当次未运行 demo 或取消探针，未加入历史资源保活 |
| 2026-11-16 至 17，消费结束／会话退役 | 生成、编译与有限 demo；临时探针观察部分节点退出、全部退出和持续来源停产；LinesDemo 的 close 提前到 Report 之前 | interpreter 托管会话与 ReuseOutput 有各自停止规则，不扩大为全局无人读取即停产 |
| 2026-11-17，`4e33914` 及后续复核记录 | 编译和八个命名空间生成无变化；同单元并行、串行与经 Derive 依赖的探针对照旧版漏消费／挂住，修复版正常结束 | 取消退役的接续只经源码审查；共享唤醒代价与 require 在发布之前的边界未实测确认 |

**上一轮实现验证（2026-11-17）：** 持续资产最新值的 scope 参数登记、会话开启计划及待用匹配已接通。八个现有命名空间显式重新生成；最终 `cabal build all --offline -j1` 通过，退出码 0，`git diff --check` 通过。未改手写业务模块，未新增测试或负例，未运行业务 demo 或并发探针；交接窗口与锁顺序仅做源码核对。整份 History 的参数含义、历史资源持有及长期堆占用仍未覆盖。

**组合状态机整理的历史验证（2026-11-17）：** 已迁移八个原算法模块到 `Gen.Composition`，删除旧模块；读取路由、能力、入口包装、选择器与会话入口以纯 ADT 交给输出阶段。最终 `cabal build all --offline -j1` 通过，退出码 0。八个现有命名空间（FileDemo、ScopeInstancesDemo、ScopeReuseDemo、OpenFilesDemo、StreamDemo、Crawler、FacadeProbe、LinesDemo）用最终生成器显式重新生成，均为 `0 files updated`；手写业务和 Generated 无改动。补丁格式检查通过。未新增测试、负例或业务 demo 执行，未做性能测量或并发探针；首次无 Handlers 与缓存命中的路径只做源码核对。该次整理未改变 runtime 协议，也未补齐额外资源持有；本轮驱动边界修正不沿用它作为验证结果。

<a id="composition-driving-verification"></a>
**持续生产与固定取值验证（2026-11-17）：** 八个现有命名空间显式重新生成，生成器的 beforegen 与生成副本类型检查通过；五个普通示例的生成文件无变化，StreamDemo、FacadeProbe、LinesDemo 各更新四份生成文件。`cabal build all --offline -j1` 通过，退出码 0。静态交叉复查有限 Derive 的装配、取消、游标交接与 Binding 生产身份。未新增测试或负例，未运行业务 demo，未做并发或内存测量。LinesDemo 的 `snapshotAst` 仅作为声明参与编译，没有选作 `ast` 重新生成或执行；因此本轮编译不作为其运行结果的证明。

**本轮组合检查收尾验证（2026-11-17）：** 新增真实 workflow 读取根的最低限度无来源诊断、可读签名冲突信息及阶段助手的词法封装；同步组合设计与文档分工。八个现有命名空间显式重新生成并通过生成器的类型检查，均为 `0 files updated`；最终 `cabal build all --offline -j1` 通过，退出码 0，补丁格式检查通过。runtime、手写 demo 与生成文件均未修改。未新增或执行负例、测试及业务 demo；缺值与冲突诊断的具体失败路径、本次首次无 Handlers 与缓存路径只做源码核对，不能把普通编译当作这些路径的实测。检查仍按 ReadPoint 聚合，并排除 SessionChain 等既有协议，完整边界见[图规范](EFFECT_GRAPH.md#missing-source)。

<a id="receive-resource-verification"></a>
**Receive 资源交接修复与验证（2026-11-17）：** 来源步骤向紧接的 parser 交接本次已捕获的资源 Binding，保留生产身份与 ownership；两步共用会话使用登记。普通 Handoff 继续过滤资源，来源的普通捕获和交付视图不额外透传，不跨轮缓存。StreamDemo 的 close 在 IO 前读取资源；scope 的单例／多例分类未改变。规则见 [Stream 生产路径](STREAM_LIFELONG.md#81-生产路径)。

本轮显式重新生成 StreamDemo，更新两份生成文件，并通过生成器的 beforegen 与生成副本类型检查；`cabal build all --offline -j1` 通过，退出码 0。file、open-files、scope-reuse、scope-instances、lines、crawler 六个现有有限示例均返回 `Succ`；scope-reuse 记录实际开启／关闭各一次，LinesDemo 在最终报告前关闭文件，后继读到 4 行／40 字符。StreamDemo 输出 24 条温度与 8 次心跳，连接只开启一次；Ctrl-C 后打印一次断开信息，无缺值或关闭失败，取消运行退出码为 1，不记为正常 `Succ`。补丁格式检查通过。未新增测试或负例，未穷举取消交错、多参数实例与解析失败路径，未做长期内存测量。

<a id="protocol-checks-verification"></a>
**静态协议检查验证（2026-11-17）：** 新增 close 按绑定检查资源读取，并按触发条件归类 3 种 ContextFault 与 11 种 ScopeFault。八个现有命名空间显式重新生成并通过生成器类型检查，均为 `0 files updated`；`cabal build all --offline -j1` 通过，退出码 0。runtime、手写 demo 和生成文件均未修改。现有 FileDemo 的空 open 保持合法；资源的分支投影仍可用于 close 定位。本轮按工作约定未新增测试、负例或运行业务 demo；遗漏 close 读取的拒绝路径、分支资源投影、首次无 Handlers 与缓存检查次序仅作源码核对，不将编译通过记作这些路径的实测。检查不证明所有条件路径或 IO 顺序，亦未实现 Stage 5／7 的资源持有。

<a id="binding-retention-verification"></a>
**既有 ownership 保留（2026-11-18）：** 新增 Runtime.Retention，接入交付队列、有限捕获、alternative 交接、轮帧和派生步骤；保留撤销及最新绑定替换调用现有 scope GC。未改 Language、Gen.Composition、Prototype、handler、demo 或 Generated，不新增来源规则、历史类型、背压与资源别名推断。`cabal build all --offline -j1` 通过，退出码 0。按工作约定未新增测试、负例或运行业务 demo；取消交错、慢消费者、资源队列和后继资源读取只做源码核对，未做内存测量，编译通过不代表这些运行边界已经实测。Stage 5／7 整体仍未完成。

<a id="session-scope-verification"></a>
**会话实例待用与回收（2026-11-18）：** 生产步骤改用独立 ScopeUser，Receive 来源与 parser 仍共用本步登记；长期会话待用复用现有 SessionChain 挂载、开启计划与 ExecutionFrame，按固定捕获及参数生产身份保留具体实例。Derive 在领取的协调区内固定选择，再推进游标；等待只查询本步及下一条的具体身份。Graph 的 GC 查询使用启动前登记的会话快照，移除目录忙时的无条件保留；步骤清理中的意外取消进入既有会话失败通知。保留既有 ownership 交接，不增加普通解析数据的资源依赖；Gen.Composition 与 Prototype 只补事实职责注释，未改组合算法或数据形状，Language、handler、demo 与 Generated 均未修改。最终 `cabal build all --offline -j1` 通过，退出码 0，无编译警告。按工作约定未新增测试、负例或运行业务 demo；并发交接、取消、条件分支的多例回收只经源码核对，长期堆占用未实测，编译不等于这些运行路径已验证。

<a id="maintenance"></a>
## 怎样维护这份计划

2026-11-18 本轮仅调整阶段文档：按 rawoutput 资产边界移除任意 ADT 内嵌资源的待办，保留 ScopeTree 宽依赖，将背压列为下一阶段并区分已确认目标与待定策略；同步共享供值的阶段状态。未修改 SDK、生成产物或 demo，未编译或运行业务。

2026-11-18 合并收尾只补充父实例引用的保留边界和后续设计项，未修改 SDK，未重复编译或运行业务示例。外部审查者提供的运行结果不记作本轮执行记录。

每阶段先确认代码形态与协议；完成后将详细规则写回所属规范，GUIDE 只展示当前接口。这里保留状态、未完成项、必要理由和一条验证摘要；被取代的方案与探针过程交给 Git 历史，不另建归档文件或复制阶段清单。

2026-11-17 本轮仅将 Stage 5／7 合并为一项工作，集中剩余交付、确认点和完成标准；保留已有阶段链接。未修改 SDK、生成产物或 demo，未编译或运行业务；上述实现与验证记录均属于各自注明的轮次。

2026-11-17 前一轮仅整理文档：收敛计划、改用规范引用、修正指南过期描述，并核对引用与改动范围。没有修改 SDK、生成产物或 demo，没有重新编译或运行业务；上表均为历史记录。

2026-11-18 文档同步：合入 main 的 `5b10644`，保留主设计改名 `CORE_DESIGN.md`、“业务即 DSL”及 algebraic effect 两节，同时保留本分支的共享供值、Injector／Booter 与阶段边界。按用户确认统一确定性的含义；本次仅修改文档，未改 SDK、生成产物或 facade，未重复编译或运行业务示例。

2026-11-18 文档收尾：补充共享供值与编译器重构的版本边界、SDK 职责与内部迁移说明；把任意业务 ADT 内嵌资源的过期待办统一改为资产契约的范围说明，修正指南中待交付 ownership 尚有缺口、消费节点结束后必定缺少本轮普通值的旧表述，并让主设计的订阅结束摘要引用现行协议。仅修改文档，未修改 SDK 或生成产物，未重新编译或运行业务示例。
