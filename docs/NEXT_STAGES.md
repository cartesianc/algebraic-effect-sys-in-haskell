# Next stages

更新：2026-11-18。本文是阶段计划与开放项的唯一入口，保存各阶段的目标、剩余工作和必要的完成摘要。当前协议在[主设计](LATEST_DESIGN.md)及其专题中维护；历史验证集中在[验证边界](#baseline)，不代表本次重新执行。

**当前进度：** handler 复用、scope 可达性回收、Stream 两侧结束、后继读取、交付保留和会话退役已落地。持续生产与有限取值的组合边界已经补齐，生成期无来源诊断、签名报错与组合设计收尾已完成；Receive 来源到 parser 的资源交接及示例 close 已修复，验证见[本轮记录](#receive-resource-verification)。[静态协议检查收口](#protocol-checks)已完成本轮范围，已补上既有 Binding ownership 的交付与执行保留；下一步确认业务资产内嵌资源的保证范围。

<a id="code-shape"></a>
## 代码长什么样

沿[指南的同一业务示例](GUIDE.md#code-shape)查看资产、注册、instance 和 workflow；当前完整写法不在计划中复制。原子 handler 以 `instance XxxLayer m => XxxHandler m` 实现，业务 effect 绑定它并声明 Input／demands，gen 装配前驱和读取路由，入口保持 `main = interpreter ast effects`。

持续执行的写法见[指南第五节](GUIDE.md#stream)：Stream handler 用 `streamEnd` 结束来源，自身声明 `streams` 的 Excu 用 `endStream` 结束订阅。后续阶段若调整接口，先给出受影响的 Types、Effects、Handlers 和 AST 代码形态，标明“待确认／未实现”，确认后才更新当前指南。

<a id="scope"></a>
## 目标与边界

目标是在现有架构内统一持续执行、资产访问和资源收尾。保持原子 handler、业务 effect、Context 解析与 workflow 驱动的分工，以及 Prototype／RuntimeGraph 和独立无环 ScopeTree；不为实现方便增加 effect 类别、手写装配层、资源寿命标签或 cleanup policy。

资产引用的内存回收与 `Scoped.close` 管理的资源释放分别处理。释放引用不能替代关闭资源，业务资产保存记录也不能自动保证其中引用的资源仍然可用。完整设计原则见[主设计](LATEST_DESIGN.md#principles)。

<a id="stages"></a>
## 阶段地图

Stage 1–7 是本轮的编号，与早期 Prototype／RuntimeGraph、来源可见性、Stream 初版的阶段编号区分。阶段按职责划分，实际交付可以交叉；不是“前一阶段所有事项完成，后一阶段才存在”。原 Stage 5 与 Stage 7 已合并为一项资源生命周期工作，沿用 5／7 编号，不再分别实施和验收。

| 阶段 | 目标 | 当前状态 |
| --- | --- | --- |
| [1：输入契约](#stage-1) | 资产来源明确，读取可检查 | 已完成；旧接收形态由 Stage 2 取代 |
| [2：handler 复用](#stage-2) | 原子操作与业务装配分开 | 已完成；[完整等待迁移](#stage-2-await)独立待实施 |
| [3：共同执行结构](#stage-3) | 对齐 Stream 与 lifelong 的推进、发布和结束边界 | 已有运行对应；持续生命周期的统一继续收敛 |
| [4：资产访问](#stage-4) | 固定取值与重复启动分别计算 | 已完成；持续资产的资源持有留给 Stage 5／7 |
| [5／7：持续资产的资源持有与自动回收](#stage-5) | 统一持有、交接、撤销与 scope close | 既有 ownership 的保留已接通；内嵌资源及撤销后的保证仍待确认 |
| [6：结束传播](#stage-6) | 生产结束、消费退出、排空和 workflow 返回 | 已实现；局部失败仍延期 |

<a id="composition-machine"></a>
### 统一组合计算

**已完成（2026-11-17）。** `Gen.Composition` 统一阶段转换、接口与装配事实，Emit 改为读取确定结果。声明、会话、绑定、构图与来源证明仍使用各自算法；这不是通用规则求解器，也未消除路径复杂度。设计依据见[组合逻辑的核心意义](COMPOSITION.md#why)，运行和资源协议保持不变。

本轮按以下顺序完成：

1. 核对原有规则和输入依赖，保留声明加载与首次契约生成的边界。
2. 将组合运算、内部工作状态和结果集中，输出阶段改用已确定的类型能力、读取视图与装配事实。
3. 同步设计与源码导航，删除被替代的算法模块，保留方法形状前端及各类输出模块。
4. 显式重新生成现有示例并做必要普通编译，核对 facade 与生成结果；实际结果记在验证摘要。

这项工作为后续组合判断提供单一落点，不新增用户语法、运行时调度机制、通用 IO 去重或额外资源持有规则。Stage 5／7 的业务边界继续单独收敛。

<a id="composition-review"></a>
### 当前收尾：组合检查与计算边界

**已完成（2026-11-17）。** 根据分支复查完成以下收尾；本轮生成与普通编译结果见[验证摘要](#baseline)：

1. 对已到达、在所有已分析路径均无合法供值或捕获的普通读取，增加生成期拒绝；条件生产、会话、资源与收尾仍保留原有处理，详细边界见[静态无来源诊断](EFFECT_GRAPH.md#missing-source)。不放宽可见性，也不新增语法。
2. 共享 handler 签名冲突重新显示业务作者能读懂的类型与能力约束；纯结构的 Show／Read 表示保留。
3. 将阶段专用助手收进对应计算入口的局部作用域，只保留必要的跨阶段关系查询；统一状态转换与既有阶段次序不变。
4. 吸收 `docs/composition-polymorphism` 的核心理念补充：README 与设计原则突出组合多态，COMPOSITION 保留理念、产物与规则定位，状态／检查点归主设计流水线，缓存归图规范。文档不把现有阶段机描述成逐元素解释表或通用求解器。

这批收尾不实现 Stage 5／7 的资源持有，也不把历史编译或其他分支的 demo 运行作为本轮验证。

<a id="protocol-checks"></a>
### 静态协议检查收口

**本轮完成（2026-11-17）。** 在 Stage 5／7 之前补齐既定读取契约的最低限度检查。按触发条件梳理 14 种运行时协议故障，区分结构违规、运行状态和 SDK 不变量；详细归属只在[图规范](EFFECT_GRAPH.md#protocol-faults)维护。

本轮新增：有资源的 Scoped 按 close 的方法绑定检查资源读取，open 或其他方法的读取不代替它。open 入口按 requests 生产并认领资源，方法体为空仍合法。沿用组合计算的类型路由，首次契约生成跳过、已有方法体时在图缓存前检查；无资源 scope 和可选 close 保持现有规则。参数生产身份、IO 顺序、条件路径和运行时防线保持原协议，不扩展 Shape 或引入新语法。

交付以这项检查和 14 种故障的边界说明为限；完整等待与资源保活仍分别推进。实际验证及未覆盖范围见[验证摘要](#protocol-checks-verification)。

<a id="composition-driving"></a>
### 持续生产与固定取值的组合

**已完成（2026-11-17）。** 按用户明确的组合语义，A 可以随 B 的持续交付继续生产，而普通链 C 只读取 A 的一次固定值。驱动不沿任意取值依赖传播。两种读取均使用资产声明的表示类型；累计记录等是业务节点的结果，不是 SDK 的特殊历史类型。

本轮落点：

1. 在 Gen.Composition 中统一计算生产计划和读取方的驱动关系；有限读取可按独立 Receive／Derive 计划建立所需上游，保留已有 ReuseOutput 的实际 AST 输出连接。
2. 去掉 SDK 给 streams 额外套历史类型的实现；handler 按声明 T 读取。旧实现把 streams 与完整历史前缀绑定，需要同步示例，不能把这项纠正描述成旧接口字面不变。
3. runtime 只执行计划：重复推进在生产会话或 lifelong 中发生，普通读取捕获一次值后继续；交付队列只保存未领取值与最新值。
4. 示例将计数、平均值或记录保存放回业务资产和原子 handler；不新增 effect 类别、声明关键字或 history 名称识别规则。

具体规则归 [Stream 读取与驱动](STREAM_LIFELONG.md#contracts)及[有限读取](STREAM_LIFELONG.md#production)。本轮不解决任意资产内嵌资源的持有、不放开 requests 持续资产、不引入容量背压。本轮生成、编译及未覆盖范围见[验证摘要](#composition-driving-verification)。

<a id="stage-1"></a>
### Stage 1：资产来源与接收契约

**已完成。** 保留的核心是：每个 refined asset 对应固定表示 ADT 和唯一 Context 来源；访问方式不另造资产身份，一个消费者可以依赖多个资产。当前约束见[资产来源与访问](LATEST_DESIGN.md#demand-contract)。

早期要求 handler 显式匹配生成资产构造器，后来妨碍同一原子操作在不同来源间复用。该接收检查和 Context 的 request 角色已由 Stage 2 取代，不再把旧写法作为候选接口保留。

<a id="stage-2"></a>
### Stage 2：原子 handler 与业务 effect 分离

**已完成（2026-11-08）。** 原子性落在 handler；多个业务 effect 可以绑定同一 handler，各自决定 Input 和 demands。生成器按“表示类型 + effect”路由读取，业务来源由注册明确指定，不按谁先生产来竞争。

这解决了“同一个写入操作因为来源不同而重复实现”的问题。alternative 处理同一资产的构造器分支，不能替代跨 Context 来源的装配；无需为复用新增 `resource`、`oneOf` 或链路 newtype。handler 定义共享不合并实际调用。

当前写法与检查分别见[指南：handler](GUIDE.md#handlers)、[注册契约](LATEST_DESIGN.md#registration)、[入口装配](LATEST_DESIGN.md#calls)和[源码资产约束](ASSETS.md)。SDK 四层分工见 [gen 是编译器](LATEST_DESIGN.md#compiler)。

<a id="stage-2-later"></a>
持续资产的取值与驱动归 [Stage 4](#stage-4)；Error 驱动链、来源调度扩展等归[开放事项](#deferred)。现有 socket／event／behavior 的单步写法见 [Stream 规范](STREAM_LIFELONG.md#drives)，不把自动分类或外部回调适配说成当前能力。

<a id="stage-3"></a>
### Stage 3：Stream 与 lifelong 的共同执行结构

**已有对应，生命周期边界继续收敛。** Stream 的生产步骤与 lifelong 单元都可以按“等待推进条件 → 有限执行 → 发布 → 继续或结束”理解。前者从 Context 需求启动，后者从 AST 启动；它们通过 Context 资产连接。

保留这项工作的理由是让结束、使用撤销和回收沿共同边界衔接。不能为统一实现把生产与消费压成一个串行循环，也不预设两种前端 ADT 已有一一同构证明。现行对应见[生产连接](STREAM_LIFELONG.md#bootplan)、[单元调度](STREAM_LIFELONG.md#scheduling)与[会话](STREAM_LIFELONG.md#sessions)。

**剩余交付：** 配合 Stage 5／7 明确两种入口的持续状态、在途执行与资源持有如何衔接；只提取真正相同的协议，保留原有 workflow 并发关系。

<a id="stage-4"></a>
### Stage 4：资产取值与驱动边界

**已完成（2026-11-17）。** requests 驱动普通资产生产；requires 只取值；streams 在持续执行位置接收增量驱动。handler 都按声明的表示类型 `require @T`，SDK 不附加历史业务类型。普通链读取派生持续资产时，gen 建立其独立生产计划，读取者不继承订阅。完整协议见 [Stream 读取](STREAM_LIFELONG.md#contracts)与[生产和有限读取](STREAM_LIFELONG.md#production)。

一次捕获保留原 Binding 的生产身份；之后的发布不改写本次值。T 若包含业务记录或累计状态，仍作为业务表示处理，不改变唯一 Context 来源。持续资产仍不能 requests。

剩余的资源问题归 Stage 5／7：区分未领取交付、已捕获值、伴随发布和业务数据中的资源引用，确定 SDK 应持有什么，而不再设计特殊的历史读取语法。

<a id="stage-5"></a>
<a id="stage-7"></a>
### Stage 5／7：持续资产的资源持有与自动回收

**部分已实现，业务内嵌资源仍待确认。** 将原来的“持续使用边界”和“自动清理”合成一项工作：谁持有资源与什么时候撤销持有共同决定 close，必须一起设计和验收。当前会话使用登记、轮执行帧、普通后继待用、持续值开启参数及会话退役已经接入 scope 可达性；本轮又补上已有 ownership 的持有与交接，下面的生命周期仍是整项工作的范围，不代表任意 ADT 已获保证。

**代码形态保持不变。** 沿用资产 ADT、Input／demands、原子 handler 和现有 Stream／lifelong 出口；业务仍只在 Scoped 的 close handler 中实现释放操作，不手写 layer、保活或释放调用。业务累计数据不作为 SDK 的特殊历史类型。

剩余工作按同一条生命周期展开：

1. **建立持有。** 分清待交付值及伴随发布、执行中已捕获值、合法后继可读的最新值、业务资产内嵌资源分别由谁保留。实例仍由原 Binding 的生产身份和唯一 ownership 定位，多个读取方分别承担义务；保存值引用本身不等于登记资源使用。
2. **完成交接。** 发布时先建立接收侧持有，再结束生产侧使用；领取时先建立执行侧持有，再撤销队列持有。游标前进只表示领取，不能当成处理完成。交接与回收预约沿用现有协调锁，取消不能留下无持有的窗口或永久登记。
3. **撤销持有。** 把队列裁剪、调用结束、订阅撤销、绑定替换及后继完成／跳过分别映射到对应义务的撤销。来源 end 只说明不再生产，不能据此撤销尚未消费或后继仍会读取的值所需的资源。仅为诊断保存的 scope 快照不能把实例自身永久保活。
4. **复用回收。** gen 的组合计算确定静态读取和待用依据，RuntimeGraph、执行帧与实际 Binding 补齐本次关系；撤销后调用已有 scope GC。仍按当前使用、待用和子实例判断，遵守子先父后与 close 失败只报告、不重试的协议。ScopeTree 保持独立无环，订阅及值持有不直接增加父子边，不另建回收器，也不在退役时等待包含自身的全部工作退出。

**本轮落地（2026-11-18）：** 用户授权既定语义下的内部工作直接实施。新增 Runtime.Retention 管理执行中的已知资源保留，Session 保存待交付资源索引，Graph 复用来源表、执行帧与现有 scope 回收。领取先交接再裁剪，调用、轮帧和派生步骤退出时撤销；合法后继与旧绑定替换使用原可见性。详细协议只在[资源边界](STREAM_LIFELONG.md#binding-retention)维护，验证见[本轮记录](#binding-retention-verification)。

**剩余实施：** 继续确认[内嵌资源与撤销后的保证](#review)，再扩展持有范围。生产会话跨步骤的 ScopeUser 保持原退役时机；不因为加了保留根就擅自提前撤销。

**完成标准：** 在确认的保证范围内，仍有合法使用义务时不会提前 close；全部义务撤销后进入现有回收器；多消费者、来源结束、消费退出、后继读取和取消使用同一持有协议。读取值、来源可见性和已捕获绑定保持现有规则，资源关闭后的旧绑定行为按确认结果写入规范。内存引用释放与资源 close 分别说明，不以取消读取或丢弃增量换取回收。

<a id="stage-5-foundation"></a>
**持续最新值参数（2026-11-17）：** gen 为会话参数保存显式开启计划；runtime 登记实际选中 Binding 的 `ActivationId` 与原生产帧，固定交付与后继读取按相同来源规则参与回收。handler、demand、AST 写法不变。完整规范见[开启计划与待用](EFFECT_GRAPH.md#scope-opening-retention)。业务资产内嵌资源的持有没有因此实现。

**已完成的基础（2026-11-16）：** 普通后继按实际当前／保留绑定参与待用判断；轮间发布交接与回收共用协调锁；并发停止会话等待同一收尾完成信号。详细规则见[开启计划与待用](EFFECT_GRAPH.md#scope-opening-retention)和[会话协议](STREAM_LIFELONG.md#sessions)。这不等于已经提供任意业务数据内嵌资源的保活。

<a id="stage-6"></a>
### Stage 6：结束与终止传播

**生产侧结束、消费侧结束及以下配套已实现（2026-11-14 至 17）。** 这解决了持续程序只能靠失败或取消退出的问题；正常结束可以让外层 workflow 继续。当前失败仍采用整次运行终止的临时规则，局部恢复未实现。

- **来源结束与 workflow 返回**：`streamEnd`、排空、单元结束和 lifelong 返回；规则见[正常结束](STREAM_LIFELONG.md#end)。
- **后继读取**：后继按既有可见性读取每个来源最新一次发布，单元内保持轮次隔离；规则仍见[正常结束](STREAM_LIFELONG.md#end)中的后继读取部分。

<a id="stage-6-retention"></a>
**引用保留基础（2026-11-14）：** 只保留仍有读取义务的数据；本轮改为交付队列与最新值，不再由 SDK 承诺完整业务历史。当前保留协议与复杂度见[会话保留](STREAM_LIFELONG.md#retention)。

<a id="stage-6-derive"></a>
**独立派生（2026-11-15）：** 由持续资产驱动的操作可以经 parser 产生另一份持续资产，补上消费结果再次成为资产的表达。原先禁止这类操作挂入 AST 的限制已由下一项输出复用取代。规则见[派生与输出复用](STREAM_LIFELONG.md#derive)。

<a id="stage-6-reuse"></a>
**同次输出复用（2026-11-15）：** gen 将消费操作的实际 AST 发布位置连接到挂接 parser，保留生产与消费分链，同时避免为解析重跑原操作。LinesDemo 的 `TextCounter`／`RunningTotal` 展示这一组合；完整写法见[指南](GUIDE.md#stream)，合法性见[生产连接](STREAM_LIFELONG.md#bootplan)。

<a id="stage-6-consumer-end"></a>
**消费结束与退役（2026-11-16 至 17）：** `endStream` 撤销当前订阅，按节点、单元和会话的读取关系协调停产；会话退役接入现有 scope 回收。规则与代码形态见[消费方结束](STREAM_LIFELONG.md#consumer-end)。

最后一轮修正的理由也保留在这里：同单元不证明生产已经完成，可能还有并行发布或尚未处理完的 Derive。因此只在本轮发布与派生处理稳定后跳过；发布节点结束须及时封口；取消不能把未完成的退役记为完成。完整判定维护在上述规范中，旧的“同单元一律不等待”方案已删除。

<a id="review"></a>
## 下一步需要确认什么

Stage 5／7 已合并；第一项按现有 ownership 落地，其余会影响资源保证范围，仍待确认：

1. **已实施的保活范围。** 合法待交付、在途捕获和后继读取按已有 Binding ownership 保留原实例，义务撤销后进入现有 GC。不增加读取许可、不合并 ownership、不检查任意 ADT 字段；来源 end 后仍沿用会话退役时撤销生产侧使用。
2. **内嵌资源如何确定。** gen 能取得资产读取关系，不能证明任意 ADT 字段实际保存了哪些句柄。可考虑沿受控读取保守继承资源依赖；它会延后部分 close，反复读取旧资产再发布时也可能持续保留已被业务丢弃的资源。是否接受该保守保证、外部别名与可变容器纳入多少范围，需要单独确定；不能把依赖候选当成精确字段引用。
3. **资源关闭后旧绑定怎样表现。** 建议受控读取沿用原实例的关闭／失败诊断，不自动换 owner、重开或重放生产；不带资源依赖的普通值保持现有读取行为。已逸出 SDK 的裸句柄操作不能由这条检查自动保护。

持续值的生产身份已沿用 Binding，无须新增身份规则。持有只能延长已合法取得资源的使用期，不能扩大资产可见性或替代首次获取。

普通等待的完整迁移和下面的开放专题分别处理；本文件整理不构成新接口或清理策略的批准。

<a id="current-limits"></a>
## 当前限制与检查边界

| 限制或未覆盖边界 | 归属 |
| --- | --- |
| 普通资产的 parallel 兄弟仍互不可见；保守等待结束不证明所有等待都可结束 | [完整等待迁移](#stage-2-await) |
| 持续值参数和已有 ownership 的交付保留已接通；任意 ADT 内嵌资源及撤销后的保证仍待定 | Stage 5／7 |
| 同单元直接或经 Derive 等待 Scoped.open 的复用输出被保守拒绝：复用实例不产生新输出；必定 fresh 的精确放行未做 | [输出复用规范](STREAM_LIFELONG.md#derive) |
| 未领取交付没有硬容量与背压上限；interpreter 托管会话和 ReuseOutput 不按读取方计数退役 | [交付保留](STREAM_LIFELONG.md#retention)、[退役规则](STREAM_LIFELONG.md#consumer-end) |
| 含 lifelong 程序的失败仍终止整次运行 | [临时失败协议](STREAM_LIFELONG.md#failures) |
| 生成期无来源诊断只覆盖已分析的普通读取点；合法来源在部分运行路径不发布仍由 runtime 处理，不证明全部等待可结束 | [本轮收尾](#composition-review)、[静态无来源诊断](EFFECT_GRAPH.md#missing-source) |
| 来源状态与 scope 路径仍可能指数增长；共享通知存在多余唤醒，尚无大规模性能与长期堆占用实测 | [图与来源](EFFECT_GRAPH.md)、[会话复杂度](STREAM_LIFELONG.md#retention-cost) |

<a id="stage-2-await"></a>
## 普通 require 的完整等待迁移

**最低限度的保守结束已实现；静态无来源拒绝在[本轮收尾](#composition-review)补齐，完整迁移已定方向、未实施。** 当前仍按 origin 保存普通资产，使用捕获与静态来源表；规则见[Context](LATEST_DESIGN.md#context)。目标可见性、确定性与帧语义仅在[完整等待方案](LATEST_DESIGN.md#await-visibility)维护。

后续实施落点：

1. gen 的可见关系纳入合法的 parallel 兄弟；来源分析按读取点检查可能生产者、无法取得值的等待和互等，保留对“读到哪次生产取决于调度”的拒绝。有先后关系的发布选择最后一次，不以合并来源集合牺牲确定性。
2. 普通发布迁到每执行帧、每资产一个 `TVar`，本次捕获仍优先；缺值沿本帧及外层帧读取，发布与来源结束在同一次 STM 等待中观察。lifelong 每轮新帧取代普通发布的 `resetOrigins`，会话伴随发布与资源 owner 定位保持各自协议。
3. 移除普通发布对多份 Origin 的运行时挑选，保留资源实例的歧义检查；同步生成期诊断、来源规范与指南。`stm`、更细的读取计划均属于这次后续迁移，尚未加入。

该工作不要求给 handler 方法体插桩，也不把最低限度的耗尽判断扩大为任意 IO 进展证明。现有生产身份与执行帧继续复用。

## 已完成的共用基础

<a id="gen-assembly-sharing"></a>
### gen 装配与共享分析（2026-11-16）

装配结果统一末端、选择器、会话步骤和输出连接，方法图按定义缓存归约摘要。其计算本轮并入[组合状态机](#composition-machine)，继续与 Emit 共用结果；没有引入通用调用去重、业务结果缓存或 scope 同值复用。规则见[装配与复用边界](EFFECT_GRAPH.md#reuse-boundary)。

<a id="pure-pipeline"></a>
### Pure 与 list 原子输出（2026-11-12）

Pure 成为生产链中的值变换，Excu／Scoped 的原子输出统一为 `[String]`；parser 继续负责把输出变成资产。它分开了值变换与细化解析的职责，取代旧守卫接口。当前写法、位置限制和失败协议见[主设计：Pure](LATEST_DESIGN.md#pure)，不重复迁移清单。

<a id="scope-gc"></a>
### scope 身份、回收与关闭诊断（2026-11-13）

Binding 的生产身份与执行帧支持单例／多例匹配和待用分析；ScopeTree 保持独立无环。close 可选，普通关闭失败只报告，取消在其余收尾后传播。当前规则见[实例身份](LATEST_DESIGN.md#scope-identity)与[可达性回收](LATEST_DESIGN.md#scope-gc)。这些已是持续执行清理的基础，后续不另建一套实例或回收器。

<a id="deferred"></a>
## 保留的开放专题

以下不作为持续资源清理的前置条件，也不因列在此处就批准新增语义。

| 专题 | 仍需确定 |
| --- | --- |
| 背压与交付容量 | 容量、溢出策略、慢消费者及反馈与有界队列的进展；业务自行保存的记录不受 SDK 队列裁剪控制 |
| 来源与调度 | 是否区分或自动推导 event／behavior／socket；自动重试、时间周期声明、通用外部 push callback 适配；已有单步写法见 [Stream](STREAM_LIFELONG.md#drives) |
| 持续组合 | 嵌套 lifelong、多来源组合触发同一 target、派生步骤跳过与显式反馈 |
| 值操作与适配 | 带类型的原子输出、嵌套输出结构、Pure 挂在 Stream 下、Generic Map；同注册多细化来源及同表示类型二元操作的其他写法 |
| 资源协议 | Stream close 接口是否需要；scope 同值复用、其他 cleanup policy、Linear 凭证、任意逸出资源、未发布的部分获取恢复、跨 interpreter 存续 |
| 故障恢复 | Error 驱动链、常驻 scope 失效与修复、局部失败、已展开 continuation 恢复及跨调用诊断；当前 resolve 不调用 close，处置成功仍传播原失败 |
| 内存与诊断 | 业务惰性状态链是否需要处理，以及关闭失败记录长期累积的报告策略；强制求值或改变报告时机须另行确认 |
| 模块与接口 | 多方法 effect 的入口／结果契约、独立生成模块组合、跨语言 schema |

<a id="middleware"></a>
### Middleware 与 Hanging

独立 Middleware typing、装卸策略及其与 [Root 入口包装](LATEST_DESIGN.md#calls)的关系单独设计，Hanging 随之确认。本轮不以新增 Middleware 类别为前提。

<a id="external-tools"></a>
### 外部工具与观察

LSP 仓库的来源可见性穷举模型尚未扩展到 Stream／lifelong；订阅、会话可见性、单元划分及来源可视化留在工具侧推进，不为其增加 SDK 专用导出。并发交错、资源认领交接、长期内存与跨平台取消的证据仍有限，不将这些观察项变成未经确认的新测试门槛。

<a id="baseline"></a>
## 完成与验证摘要

下表及已有验证段落各自注明所属工作，**不是后续修改的重跑结果**；当前资源交接修复的验证单独记在[本轮记录](#receive-resource-verification)。保留影响判断的结论与未覆盖范围，逐次探针、临时接口和被后续修复取代的方案查 Git 历史。历史编译与有限示例不能证明全部调度、任意业务 IO 或资源逃逸安全。

| 日期／工作 | 已有验证记录 | 仍需留意 |
| --- | --- | --- |
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

<a id="maintenance"></a>
## 怎样维护这份计划

每阶段先确认代码形态与协议；完成后将详细规则写回所属规范，GUIDE 只展示当前接口。这里保留状态、未完成项、必要理由和一条验证摘要；被取代的方案与探针过程交给 Git 历史，不另建归档文件或复制阶段清单。

2026-11-17 本轮仅将 Stage 5／7 合并为一项工作，集中剩余交付、确认点和完成标准；保留已有阶段链接。未修改 SDK、生成产物或 demo，未编译或运行业务；上述实现与验证记录均属于各自注明的轮次。

2026-11-17 前一轮仅整理文档：收敛计划、改用规范引用、修正指南过期描述，并核对引用与改动范围。没有修改 SDK、生成产物或 demo，没有重新编译或运行业务；上表均为历史记录。
