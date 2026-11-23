# 静态 Prototype、运行图与 ScopeTree

本文是[主设计第 5 章](CORE_DESIGN.md)引用的详细规范，负责 Prototype、来源分析、RuntimeGraph、ScopeTree 与重跑边界。范围为 Stage 1/2 的协议；Stream／lifelong 在原型中的表示（`LifelongAt`、会话挂载、`protoSessions`、`FromSession`）见 [Stream 第 5.3 节](STREAM_LIFELONG.md#static)，运行接入见[第 7 节](STREAM_LIFELONG.md#sessions)。


业务入口仍为 `main = interpreter ast effects`，手写 handler 仍使用原生 Haskell 的 `instance`、`do`、模式匹配和读取（`require @T`、`rawinput`）。gen 的组合状态机（[Framework.Gen.Composition](../sdk/Framework/Gen/Composition.hs)）统一计算注册、方法、workflow、链定义与挂载、effect graph 和 ScopeTree，输出唯一的 `generatedPrototype :: SDK.Prototype MethodGen` 显式 ADT 常量；数据模型在 `Framework.Prototype`。运行时校验并直接使用这份原型，不预执行 Context 或资源 IO。

生成前可由 GHC／HLS 检查手写模块是[核心设计约束](CORE_DESIGN.md#beforegen)。已有契约接口提供类方法与 ADT 类型关系；生成器从合法 Haskell 中提取支持的结构，不要求先把业务源码转换成另一种语法。宿主语言类型正确与静态 effect 结构可提取需要分别满足。

初始化后的 `ScopeTree` 在 App／IO 中同时提供 Error 的祖先候选导航与有限执行自动收尾的保守清理前提。运行层仍按实际 scope 实例及使用登记判断能否关闭；静态图不判断故障归属或某份资源已经无人使用，也不新增 Error 的动态调用 tracing。

## 定义、挂载与运行实例

`Prototype` 只保存纯数据，不包含执行函数、类字典或活资源。它派生 `Eq`、`Show`、`Read`、`Generic` 并提供 `NFData`；方法身份在生成器中为 `String`，发射后为 `MethodGen`。

| 层次 | 原型字段／运行对象 | 身份与作用 |
| --- | --- | --- |
| 注册与方法 | `protoEffects`、`protoMethods` | 集中保存能力、取值路由、挂接和显式方法结构 |
| 链定义 | `protoChainDefinitions` | 用 `OriginChain` 与 `ContextChain` 区分原始操作链和 Context 生产／读取链；按入口方法识别 |
| AST 挂载 | `protoWorkflow`、`protoChains` | 每个 node、alternative 选择读取和会话生产步骤各一条挂载记录（`NodeChain`／`SelectorChain`／`SessionChain`），按 `NodeId` 识别 |
| 持续执行 | `protoWorkflow` 中的 `LifelongAt`、`protoSessions` | lifelong 的单元、订阅与会话；interpreter 托管的会话；见 [Stream 第 5.3 节](STREAM_LIFELONG.md#static) |
| scope 开启计划 | `protoScopeOpenings` | 每个开启位置的参数生产节点／会话来源及可能类别；不代替实际绑定 |
| 运行实例 | 活动 chain、Context 生产身份、执行帧、scope 实例与入口使用登记 | 运行图共享静态原型，根据实际调用更新；不反向修改定义 |

`NodeId = [Int]` 是当前原型快照内 AST [规范形式](CORE_DESIGN.md#workflow-normal-form)的下标路径：根为 `[]`，普通子项从零编号；alternative 的选择读取链使用该分支路径加 `[-1]`；lifelong 的会话步骤使用 lifelong 路径加 `[-1, 会话序号, 步骤]`，interpreter 托管的会话步骤使用 `[-2, 会话序号, 步骤]`。同一个 origin 末端挂载两次会有两个 `NodeId`，共享方法定义。Context 链经 demand 或挂接进入，定义本身没有虚构的 AST 位置。编辑 AST 后重新生成编号；这些路径不充当跨快照稳定 key 或运行调用序号。

链事实和标准查询由 `Framework.Prototype` 统一提供：`Prototype.Types` 保存纯模型，`Prototype.Graph` 保存方法图与 ScopeTree 的数据，`Prototype.Query` 提供只读查询，`Prototype.Validate` 校验自洽并核对 AST 快照。构建算法由 `Gen.Composition` 统一持有：从声明和方法形状逐步推导装配、图与来源，不让不同输出模块另行解释同一组合。内部状态与最终 Prototype 均不复制业务注册；gen 的输出阶段读取已确定事实生成接口与包装，Execution 读取挂载关系装配闭包，运行图共享这份原型并保存活动实例关系。运行图不累计完整方法调用历史。Stage 2 由 `chainDrives`、`chainReads` 和 `protoSources` 保存可能生产、缺值读取与供值机会；runtime 读取共享最新值，保留固定捕获。清理与 Error 边界保留。SDK 当前采用 Haskell ADT，不增加 JSON 或外部 LSP 协议。

<a id="driving-plan"></a>
## 编译驱动标记

`Gen.Booter.completeDriving` 在来源证明之后补齐 `protoDriving`，Emit 输出显式 ADT。它复用原有 NodeId、方法身份、SessionProto 与 ScopeTree，不另建运行图，也不推断业务值。

| 编译事实 | runtime 的使用 |
| --- | --- |
| NodeDrive：节点成员、订阅来源、lifelong 边界、alternative 捕获祖先与先前会话边界 | 直接定位读取和捕获；仍按实际结束位置、当前捕获与已登记会话决定本次操作 |
| NodeDrive 的 blocked publishers | 在已知供值候选中排除不能与当前等待同时推进的位置；仍检查实际帧进度，不限制普通最新值的共享 |
| UnitDrive：轮帧位置、读取义务、直接／间接本地来源 | 建立同一轮执行帧，判断实际活读取方；PublishedAt 等待位置退休，DerivedFrom 等待上游和派生步骤稳定 |
| SessionDrive：边界、Context 来源、资产及唯一派生上游 | 引用已有 SessionProto；不复制其 Receive／Derive／ReuseOutput 生产计划 |
| 根帧位置、输出发布位置与 Context 生产方法身份 | 装配入口、连接同次输出、登记 RequestBoot；不新增第三种 Boot |

标记由编译器一次生成，加载时校验覆盖和引用；缺失标记是过期／失配产物，不在 runtime 重算结构补救。`--structure` 展示单元和节点标记。当前采用列表查询，不宣称已优化到常数查找；元数据增加，但没有扩大来源分析的路径枚举。

runtime 仍用前缀匹配检查实际已结束位置、撤下发布者、清除 Origin 及跳过帧内待用节点。这些是在静态结构上更新动态状态，不是另一套驱动推导。会话退役、并发监督、锁与 scope close 的次序保持原协议。

## 运行图与链启动

运行身份由 `Framework.Runtime.Identity` 定义，活动关系由 `Framework.Runtime.Graph` 管理。一次 interpreter 运行共享静态 Prototype 引用及运行图；活动 chain 引用其静态链定义，scope 实例引用其 Scoped 定义，Context 绑定保存产生它时的 `Execution`、生产 `ActivationId` 与执行帧。

```haskell
data Origin = Origin { originNode :: NodeId, originSequence :: Integer }
newtype ActivationId = ActivationId Integer
data Boot = TargetedBoot NodeId | RequestBoot String
data Execution
  = BusinessExecution Origin
  | CleanupExecution Origin String Int
```

`Origin` 区分一次根入口执行（AST 入口或会话生产步骤），`ActivationId` 区分运行图中的一次活动 chain，也作为该次 Context 成功生产的身份保存在 Binding。`RequestBoot` 的字符串是现有 Context effect 注册名；`CleanupExecution` 保存原业务 origin、scope 注册名及现有实例编号，不新增业务 key。Context 的嵌套生产有新的 activation，但普通生产沿用外层业务 origin。

`RuntimeGraph` 用存在类型保存实际 `Prototype MethodGen` 和链定义，不转成字符串图。普通资产的 `runtimeLatest` 与步骤输出索引共享 Binding；发布与帧退休共用变化通知。活动记录仍保存父 activation、Boot、Execution、实际执行帧、当前绑定与 ScopeUser，和实际执行共享引用。资源、会话与普通发布分别执行已有协议。

有限 workflow 使用以下两种启动边界：

1. **AST 启动**：Node 或 alternative 的选择读取启动选定入口，建立本次 origin 及入口使用登记。
2. **Context 启动**：实际生产（`requests` 驱动的 getT）建立 ctx chain 记录，包住生产、成功发布和返回。嵌套 ctx 启动继承外层 origin 和入口使用登记；返回只结束本次生产记录，不撤销整个入口对 scope 的使用。读取不生产，也没有新 activation；alternative 的判定 Context、持续 Context 的挂接注入实际生产时经过同一启动边界。

Stage 3 复用这两个 Boot 构造：Receive／Derive 的每个独立生产步骤以 `TargetedBoot` 启动对应的 `SessionChain` 挂载，分配新的 Origin；其中实际发生的 Context 生产仍登记 `RequestBoot`。独立会话每次生产使用新的 ScopeUser，其中 Receive 的来源与逐条 parser 各自持有本次使用；跨步骤的待用由会话执行帧保持。lifelong 的消费 target 同样每次建立新的入口使用登记，详见 [Stream 运行协议](STREAM_LIFELONG.md#production)。

本轮 ReuseOutput 连接沿用已有 AST 执行：`SessionProto.sessionPlan` 保存 `ReuseOutput [NodeId]`，指向同一 lifelong 内的具体原子输出发布位置，`sessionMounts` 为空。gen 沿 target 自身与 original Input 链定位挂接句柄；所有这些持续副产物都进入会话集合，包括仅供后继读取的产物。gen 仍保留 original chain 与 Context chain 的独立定义；执行时挂接 parser 用同次原子输出，不另建根调用或生产 worker。parser 的 `RequestBoot` 继承原节点的 Origin、执行帧和 ScopeUser。其交付只含持续资产，原 AST 调用的普通产物写入运行级最新值，不作为该交付的固定伴随值。多个发布位置只允许同单元、两两 alternative 互斥；不按调度选取，不合并同名 handler 的独立调用。组合机器以订阅、chain 前置和持续 alternative 选择读取建立启动依赖，拒绝有环组合。完整规则见 [Stream 第 4.2 节](STREAM_LIFELONG.md#derive)，实现状态见 [Next stages](NEXT_STAGES.md#stage-6-reuse)。

启动图之外还检查同单元的路径覆盖：直接订阅或经独立 Derive 间接依赖自身输出时，每条到达订阅的 workflow 路径都须先经过发布位置，或同轮有并行且必经的发布路径；alternative 取各候选的必经交集。跨单元可以条件发布，无须每轮都产出。ReuseOutput parser 及其 requests 路径只允许读取原操作的驱动持续资产，避免挂接过程中再等待其他持续来源；普通资产读取仍按原来源协议检查。

Booter 把根为本单元 ReuseOutput 的直接及单上游 Derive 来源写成静态标记，运行时将标记关联到实际轮帧。全部发布位置已完成或跳过、且派生成功步骤已追平上游累计发布数时，才能确认本轮不会再有交付；领取游标不证明处理完成。未知位置继续等待，其他单元及 Receive 来源不使用本轮耗尽判断。会话提交和节点退休共用通知，判断后再次读取会话，避免漏掉刚完成的发布。

Scoped.open 可能复用实例而不交出新的原子输出，因此它的 AST 位置不能单独证明本轮必有发布。同单元直接或经 Derive 等待这种 ReuseOutput 时，gen 当前保守拒绝；跨单元等待与独立 Derive 仍保留。精确证明某次开启必为 fresh 后放行尚未实现。

这里的“入口使用登记”是原有有限使用闭包的资源含义：一次 AST 入口内，实际 open／require 选中的 scope 计入同一份使用。`ScopeUser` 保留原有 `Unique` 协调身份，并新增 `scopeUserExecution`；同一入口的 ctx chain 使用同一个 `ScopeUser`。`scopeUsers` 同时携带使用者身份与 `Execution`，不以 AST 位置替代并发使用协调。

Context 的生产记录在生产、发布及返回结束后通过 `finally` 删除，失败或中断也撤销活动记录。AST 根活动记录覆盖业务、诊断、受控结果消费与入口使用撤销；执行器随后完成节点进度并同步检查回收。活动表只保留当前记录，绑定单独保存仍需要的生产身份。清理使用独立的 `ScopeUser` 和 `CleanupExecution`，不复活已经结束的父 activation。

`Binding.bindingOrigin :: Execution` 保存不变的执行出身，`bindingProduction :: Maybe ActivationId` 保存成功生产身份，`bindingFrame :: ExecutionFrame` 保存归属帧。生产失败不替换旧绑定，无资源 scope 的内部占位绑定没有生产身份。`bindingOwnership` 是该次生产独有的共享 `IORef`，保存可选 owner 与待认领使用者。当前捕获、权威表、scope 快照和 Handoff 保留同一绑定；认领不改变值、生产身份、帧、origin 或 publication，scope 复用也不重新发布。

`Framework.Runtime.Frame` 保存有限运行根帧、lifelong 每轮子帧及独立生产会话的待用帧。实际执行按节点记录待执行、执行中、完成和跳过；会话帧保留后续生产挂载的待用预约到生产任务退出，不充当业务调用的执行结果。节点完成晚于诊断与受控结果消费；chain 短路、alternative 未选候选与取消撤销对应待用关系。ExecutionFrame 另保存本轮已领取的普通伴随资产的 `(生产节点, Context 来源, ActivationId)`，只保存生产身份，不复制值或资源表。父帧登记活动子帧；查询根实例的待用关系时同时检查子帧内的待用节点及其固定交付身份。帧结束清空进度、交付身份和子帧登记，并从父帧摘除，不累计历史帧或 activation。Runtime 中领取会话交付的 `DeliveryFrame` 仍管理视图领取，和这份执行进度分开。Frame 的根与子帧共享发布通知，`frameSignal` 取得当前信号，`notifyFrame` 在普通发布、会话状态提交或节点退休后唤醒等待者；Graph 的 `publicationSignal` 转发到同一通知。普通最新值在运行级共享；保守等待结束复用这些进度事实，不要求另建按帧资产表。

Scope 实例保存实际参数生产身份与归属帧，Graph 把待用查询装入 ScopeHandler。查询与节点进度、关闭预约共用 scope 协调锁：实例既无实际使用者，也不再被帧内待用节点或子 scope 保留时，Scope 同步清理。完整运行规则见[主设计](CORE_DESIGN.md#scope-gc)。

无 owner 的资源绑定在发布／读取返回前登记当前 `ScopeUser`；认领把仍活跃的持有者接入实例，入口退出则撤销待认领登记与实例使用，三者共用 `scopeCoordinator`。普通资产不加入待认领集合，open 内正常生产已有 owner 的路径保持原协议。认领到保存绑定保持 masked，确保这段交接不会漏掉 cleanup。资源快照按共享归属单元去重，独立生产不合并；两次生产指向同一外部资源（例如同一路径）的别名不在此协议内。

ScopeTree 仍是独立的静态构树结果，保留路径分析、注册前提补全和无环检测。运行图关联实际 scope 实例与使用者，不从 ctx 调用嵌套关系重建 scope 父边；Error 导航和清理继续使用同一份补全后的 ScopeTree。静态定义、活动调用与资源依赖各有身份，不能用其中一层的边代替另一层。

## 资产来源与缺值路径

refined asset 固定唯一 Context 和表示 ADT；该生产链可以由多个位置驱动。每次成功生产保留独立的 `ActivationId` 与 Binding，普通资产的运行级最新值按 Context 覆盖，已捕获 Binding 不随覆盖变化。AST 顺序控制启动，执行帧记录进度，二者不作为普通值的读取权限。

来源计算位于 `Gen.Composition.resolveSources`，输入是装配后的有限方法结构、workflow 和输出连接。它区分显式 requests、选择读取、普通 Context 的输出联立、持续 Context 的挂接注入与会话步骤（[requests 与输出联立](CORE_DESIGN.md#request-production)），读取本身不生产。`chainDrives`、`chainReads` 与 scope 开启计划来自同一次计算：

```haskell
data Source = FromOwnChain | FromChains [NodeId] | FromSession
```

`FromChains` 保存可能供值的位置，用于缺值耗尽和参数出身证明，不要求位置先于读取、不按此列表过滤普通最新值。`FromOwnChain` 表示没有已知生产候选，允许本次调用捕获；不是隐式生产。`FromSession` 保持持续资产的会话协议，包括固定交付与有限读取；后继在多个互不先后的 lifelong 会话之间的歧义仍由原有检查拒绝。

<a id="missing-source"></a>
### 静态供值固定点与最低限度拒绝

来源算法 v5（2026-11-18）先从空供值集推演 workflow。一次结构分析已经能够到达的发布位置形成有限的 `(NodeId, asset)` 事实；将这些事实作为普通共享供值重新分析，直到不再增加。`require` 无捕获也无供值时停止该成功路径，不自行启动生产。并行兄弟、其他已能启动的消费单元或生产步骤可以提供事实，不按 AST 可见性筛掉。

这能接受 `parallel [readX, produceX]`，也能逐步解开独立分支的依赖。只有 `chain [readX, produceX]`、没有其他 X 的生产时，后继不能启动，因此没有初始供值，gen 拒绝。互等且没有启动种子的分支同理。诊断指出读取资产、target 与 NodeId，要求提供可启动的生产路径，而非把“已经注册生产者”当作充分条件。

例如，`FileDemo` 的 `alternative` 只尝试 `BlankText` 和 `FilledText`。假设再给 `ReadFile` 挂一个普通 `AuditParser` 并在后继读取 `AuditText`，选择读取不会发布它；读取方须 `requests "AuditText"`，由自己的前驱执行 `ReadFile` 与 `AuditParser`。判定资产的等待来源也取自同一发布固定点，排除本次选择位置。

备用 interpreter 会话先不加入供值。只有结构推演到达有限持续读取，才分析它及其 Derive 上游；实际 lifelong 的会话在该边界能启动时分析。固定点收敛后，备用挂载仍单独生成结构和 scope 计划，但不反过来冒充实际运行的供值入口。

这是对有限形状的保守推演：不执行业务 IO，不证明条件可达、解析必成功或所有等待终止。它允许分支和多轮可能发布的过近似；同一读取点只要存在可能供值就不因其他缺值路径拒绝。资源读取和诊断、close 的局部规则单独检查；备用 SessionChain 的空环境也不用于证明业务必缺值。无需 `SiteRef`、方法体插桩或新的 facade 声明。

路径上的捕获、scope 参数与资源开启仍保留；普通读取有多个可能生产时按候选分别分析，不以多个发布位置或读取时序差异作为装配歧义；确定性约束的是[Context 来源与装配规则](CORE_DESIGN.md#composition-polymorphism)。每个出口先裁剪到本链和后续读取相关的资产，再组合、去重。固定点最多增加有限的挂载与资产对，但每轮路径状态仍可能指数增长，不能将其宣称为线性算法。

### 运行级最新值与 scope 待用

`RuntimeGraph.runtimeLatest` 每个普通 Context 保留一份最新 Binding；选择与写入在现有协调锁内完成。实际写入顺序决定最新值，Origin 序号只表示出身。`runtimeAssets` 和 `runtimeOrigins` 保留当前步骤输出索引，供 Receive／Derive 构造伴随交付；替换 Origin 或开始新一轮仅清理该索引，不清除共享最新值，不另外保存全量普通历史。

调用捕获优先；尚未捕获时读取共享值，并在同一协调锁内登记执行帧的捕获身份。生产身份、值与 owner 均沿用原 Binding。scope 待用从全部活动帧、实际根调用及常驻预约查询，先匹配本次捕获、alternative 交接或固定伴随发布，再匹配共享当前参数。确定需要本次新生产而尚未捕获的开启不保留旧参数实例；实例仍须同时满足无实际使用、无待用、无活子实例和无 Binding 保留义务，才由既有 GC close。

缺值时，Context 在读取前取得共享变化信号。`contextMayPublish` 查询生成候选和根帧下全部待用位置；已退休、同一顺序调用内阻塞之后的生产，以及等待当前调用完成的有限后继，不构成继续等待的理由。会话与持续机会证据不足时保守等待。耗尽后再次读取，仍无值才报 `ContextNotInitialized`，避免发布与退休之间丢值。普通发布与节点退休都会通知等待者。

资源不通过共享最新值查找，仍要求本链开启其所属 Scoped；旧资源 Binding 保持原 owner，不会自动换实例。诊断、cleanup 与 close 不等待新业务发布。持续资产与已捕获伴随值仍遵循[会话协议](STREAM_LIFELONG.md#sessions)。

<a id="lifecycle-reads"></a>
### close 方法的资源读取

`composeMethods` 按每个绑定检查有资源 Context 的 Scoped：已声明的 close 方法体必须包含该资源的读取。检查使用 `resolve` 已完成的表示类型到细化资产路由；另一生命周期方法的读取、入口自动装配的 requests、其他资产的读取都不能代替本方法的读取。同一个 handler 绑定到多个 effect 时，分别按各自资源检查。诊断包含 Scoped、close 角色、handler、资源资产及 Context 来源。

这落实的是 close 的实例定位契约。open 的资源已由生成入口按 requests 生产并认领，open 方法体可以不读取资源，例如 FileDemo 的 `openSession = rawoutput []`；close 则依赖读取来定位实例和取得关闭锁。无资源 Context 的 scope、未声明的 close 不需要这项读取。首次缺少 Handlers 的契约生成暂不检查；已有方法体时每次在图缓存查询之前检查。

检查只拒绝整个方法都没有该资源读取的情况，不枚举运行条件，不把“出现过 require”当成“所有成功路径都读过”或“读取先于 IO”的证明。Shape 当前擦除普通 IO、业务条件和没有读取的退出表达式；条件路径绕过读取、读取前执行 IO、实际归属缺失或错配继续由 runtime 防守。不为了消除运行时故障而拒绝整个条件分支或引入新的方法体位置标记。

<a id="protocol-faults"></a>
### 协议故障的判定归属

以下覆盖当前 `Runtime.Protocol` 的 2 个 ContextFault 和 11 个 ScopeFault。归属按触发条件划分，同一构造器可同时承载结构违规、运行状态或 SDK 不变量故障。生成成功只说明已完成这些静态检查；runtime 的防线全部保留。合法结构发生绑定丢失、重复关闭等问题时应修复 SDK，不能用新禁令拒绝业务组合。

| 故障 | gen 已处理的结构条件 | 留在 runtime 的条件与理由 |
| --- | --- | --- |
| `ContextNotInitialized` | [无来源诊断](#missing-source)覆盖的普通读取完全没有合法供值；资源读取缺少本链所属 scope；持续启动关系不合法 | 合法生产失败、零发布结束、条件路径未发布；会话／收尾局部快照缺值。已经生产的 Binding 因交接丢失属于 SDK 漏洞 |
| `AmbiguousContextBinding` | 普通资产改用共享最新值，不再以多次生产为歧义；持续后继的会话边界歧义仍由 gen 拒绝 | 当前普通读取路径不再产生此故障构造 |
| `ScopeNotOpen` | 自动 close 只为已取得实例登记，不提供业务直接驱动 close 的方法组合 | 关闭一个未开启实例；正常自动路径出现时检查 SDK 登记与状态不变量 |
| `ScopeIsClosed` | 资源业务读取要求本链开启所属 scope | 已捕获 Binding 的具体 owner 已关闭；实际存续与实例身份只能运行时检查，资源逃逸的扩展保证仍待设计 |
| `ScopeReentry` | Input／方法图的递归和 scope 依赖环拒绝；handler 直接调用其他 handler 被拒绝 | 同一实例处于 opening／closing 等不允许重入的状态；保留生命周期锁内的状态防线 |
| `ScopeInterrupted` | 无法从结构预知取消或原生 IO 异常 | 开启／关闭中断后记录具体实例失效及原因 |
| `ScopeContextMissing` | [逐方法资源读取](#lifecycle-reads)拒绝有资源的 close 完全未读自己的资源 | 实际路径未读取就做关闭 IO、冻结快照缺资源／owner；open 返回后资源绑定未保存也须防守。合法交接丢失属于 SDK 漏洞 |
| `ScopeContextMismatch` | 资源读取的本链所属 scope 与路由合法性 | 同一 Binding 被另一 scope 或不同参数实例认领、close 读到错误 owner；实际生产身份与认领不能由类型名代替 |
| `ScopeInputsMissing` | 检查声明来源、读取路由与声明的读取依据；原型保存所需开启参数 | 在需要选实例／执行资源 IO 时参数尚未观察齐备，或 Binding 没有生产身份；现有 Shape 不保留完整 IO 位置，开启计划本身不是齐备证明 |
| `ScopeInputAfterOpen` | 注册驱动与读取顺序进入方法结构，但本轮没有据此新增拒绝 | 已选实例后观察到另一份参数生产；当前抽象未表达实例选定时点与每次请求的动态身份，重复 require 同一绑定不能误报 |
| `ScopeCleanupInterrupted` | 无法预知 close／诊断中的原生 IO 异常或取消 | 记录清理故障；取消仍按现有收尾协议传播，不能由 gen 消除 |
| `ScopeCleanupInProgress` | close 不装配新的生产前驱，handler 不能直接调用其他 handler | 清理期间尝试开启资源；保留受限环境防线，正常自动路径触发时检查生成与运行协议 |
| `ScopeInUse` | ScopeTree／开启计划描述后续待用，不证明此刻没有使用者 | 关闭预约时仍有实际使用者、子实例或协调冲突；自动路径出现时按 SDK 不变量故障处理 |

本轮只新增 close 的逐方法资源读取检查；其余行记录既有覆盖与明确边界。参数 IO 顺序、分支必经读取、完整等待与任意 IO 终止不在这次检查中。进一步前移需要补充结构证据并单独评估，不能把“未证明合法”直接当作“已经证明非法”。

<a id="scope-opening-retention"></a>
## Scope 开启计划与待用查询

组合机器的来源分析在分析 open 时记录每个参数可能来自的生产节点，包括本链生产、前驱生产和 alternative 交接的捕获，写入同一 Prototype：

```haskell
data ScopeOpening = ScopeOpeningPlan
  { openingNode :: NodeId
  , openingScope :: String
  , openingSources :: [(String, Source)]
  , openingKinds :: [ScopeKind]
  }
data ScopeKind = RegistrationSingleton | ProductionSingleton | ExecutionMultiple
```

`openingSources` 用 `FromChains` 记录普通参数的候选节点，用 `FromSession` 记录持续参数；后者不能伪装成空候选并漏掉开启位置。

`protoScopeOpenings` 的候选覆盖各条合法路径，不要求每个位置固定一种类别，也不保存另一套分支相关性。每条读取路径继续满足已有的捕获与来源规则，候选不是任选来源的许可。`--structure` 展示候选出处和可能类别；Prototype 校验引用及字段自洽，运行时不重做来源证明。资源在本链对应 scope 开启前被读取时，生成期拒绝；业务读取不再扫描全部活实例来补资源。

运行时的实例身份是 Scoped 注册加各参数的实际 ActivationId。未开始的开启若确定会生产新参数，不保留旧实例；已捕获或通过 require 读取共享参数的开启按具体身份匹配。伴随交付保持固定，后台最新值不覆盖它。业务数据内嵌的其他资源不因此加入保活根。

轮帧记录所属 lifelong 的 NodeId，供持续协议定位。普通参数的待用则查询全部活动帧及常驻预约，固定捕获优先，其次按共享最新 Binding 匹配生产身份；不再使用按位置的 `runtimeRetained` 或 Origin 序号选择值。`resetOrigins` 只清理步骤输出索引，普通最新值保持。跨帧共享不提升实例归属；最新值替换与捕获身份登记在 scope 协调锁内完成。

参数本身属于其他 scope 的资源时，按原生产身份找到 owner 快照，再核对同一待用入口的上游开启计划；复用资源没有重新发布，不能假设它来自当前节点。这沿用普通资产与持续资产最新值的参数身份，不自动建立业务资产内嵌资源的持有关系。ScopeTree 保持独立且无环。

**持续参数（2026-11-17）。** 资源 parser 以现有 `requires "T"` 声明读取持续资产，方法体仍写 `require @T`。读取登记本次固定 Binding 的生产身份及原生产帧；后台更新不改写它，相等值的两次生产仍是不同身份。T 若包含业务保存的记录或资源引用，SDK 不把整个值展开成额外的资源保活根。

持续参数的待用匹配分两步：活动轮内先用本次调用或 alternative 交接的捕获，再用单元的固定交付；尚未领取时只预览该单元游标的下一条，既不推进也不生产。同单元本地来源的只读回退仍按会话现有最新值规则。领取正在交接时保守保留；跨单元广播按各自的实际游标比较生产身份。根帧对未来轮次的预约不保留旧交付实例；有限后继与真实读取共用“最近许可的先前 lifelong 会话，否则 interpreter 会话”的路由，只匹配所选最新值。

执行帧只记录身份和只读查询，不另建历史或值表；轮结束时撤销查询和捕获。查询在 scope 协调锁内读取已登记会话的只读目录快照，不等待会话装配锁，也不因目录忙而保留所有实例。新会话在 worker 启动前进入快照，停止时与目录一起撤下；快照不改变业务会话的唯一登记与停止协议。会话状态锁内不执行 handler、也不反向获取 scope 协调锁。实例仍使用原 Binding 的生产帧，跨单元或后继共享不提升归属。

**持续资源协调所复用的组合事实。** 静态计划与运行状态按下面的边界配合，runtime 不从 IO 识别轮询、event 或 socket。

| 已编译事实 | 决定的结构关系 | runtime 补充的实际信息 |
| --- | --- | --- |
| `SessionProto`／`BootPlan` | 哪些位置独立生产、由哪个上游驱动，或复用已有输出 | 活动会话、生产步骤、订阅与结束状态 |
| `ScopeOpening` | 每个生产／消费挂载可能开启的 scope 及参数候选 | 参数 Binding 的生产身份、原执行帧和实际实例 |
| `Source` | 普通生产机会或持续会话读取计划 | 普通读取捕获优先、否则共享最新值；持续读取沿所选交付 |
| `ScopeTree` | scope 注册间的无环父子候选 | 同一受控执行实际使用的父子实例、使用是否耗尽及关闭预约 |

**会话待用（2026-11-18）。** 独立 Receive／Derive 会话复用生成的 `sessionMounts` 建立待用帧；回收候选纳入实际活动的 SessionChain 预约，即使参数最初来自已经结束的轮帧，仍可按许可来源找到使用它的生产位置。匹配继续使用同一开启计划及实际捕获，不重建另一套资源图。会话启动时固定的捕获先按生产身份匹配，再考虑未捕获参数的实际发布；不能用后台最新值覆盖固定捕获。Derive 查询本步固定身份和上游游标下一条；领取选择与固定身份更新共用协调锁，更新完成后才推进游标，不把整个阻塞等待期解释为所有旧实例都待用。业务调用的 ScopeUser 在本步结束时撤销；预约只保留仍与后续使用匹配的实例，因此新参数的产生既不直接关闭旧实例，也不让所有旧实例随会话永久累积。预约在任务退出时摘除，资源 close 条件仍见[主设计](CORE_DESIGN.md#scope-gc)。

节点退休后检查该节点能开启的 scope 及 ScopeTree 祖先。已知资源 Binding 的保留撤销还会按实际 owner 触发同一回收器，覆盖调用 Input 链外的交接；保留范围见[Stream 资源边界](STREAM_LIFELONG.md#binding-retention)。后继的值保留继续读取 protoSources 和执行帧进度，并与实际读取共用 publicationAt／会话选择，不能把目录中存在某值当成合法读取依据。Binding 的资源标志来自注册已指定的资源 Context，不分析业务字段。close 的 `raise` 与普通 IO 异常都记录并汇总，不改节点结果、不重试；只有取消向外传播。没有 close 的实例不可达后只移出表。运行结束先让受控任务退出、撤销根帧待用关系，再按相同条件清理剩余实例。

## 生成方法身份与纯结构副本

生成器为注册的方法生成 `MethodGen` 枚举身份：方法名首字母大写，再加 `Gen`，例如 `openFileSession` 对应 `OpenFileSessionGen`。结构中的调用边引用该身份，保留其所属 effect 和方法角色；同一个 effect 的 open、close 以及 Context 的 get、read 等方法分别识别；这些是 gen 生成的内部入口，不是 handler 名。

`MethodDefinition.methodIdentity` 表示当前方法；`methodEffect` 使用同一 effect 的首个注册入口的 Gen 身份，将该 effect 的方法归为一组，不增加 effect key。例如 `openFileSession` 与 `closeFileSession` 的方法身份不同，但 `methodEffect` 都为 `OpenFileSessionGen`。scope 的静态身份使用其 open 方法身份。

生成器通过 GHC 解析器查看手写 handler 方法体中的读取：`require @T` 与 `stream @T` 均按表示类型路由。`stream @T` 还提供历史读取事实，组合阶段据此标记对应 Context 的 `effectHistory`。`rawinput` 在方法形状中记为挂接输入。再按每个绑定把表示类型代换成该 effect 声明的细化资产的读取方法、把 rawinput 代换成直接 Input 的入口，并在前面接上驱动（requests 的 getT）与 Input 前驱，组成 effect 方法的纯结构副本。表示类型按规范化的类型原文比较（例如 `String` 与 `[Char]` 视为同一类型）。副本剥离业务值、模式匹配所得数据、纯计算结果和实际 IO，只保留读取与入口引用及其结构关系。调用顺序、分支和重复读取不能被简单的名称集合代替；静态分支保留可能路径，不执行条件表达式来选择业务分支。驱动还是读取由注册决定，不能仅按方法名判断是否重新生产。

结构副本描述带包装的句柄：原子句柄（Excu.handler、Scoped.open）的生成入口在方法体返回后注入挂在它下面（可经一串 Pure）、有人读取的普通 Context（输出联立）与持续 Context，构图时该句柄的定义因此在方法体之后接一个可选分支，内容是这些 Context 的方法结构，其中对句柄的 rawinput 记为空（注入期间由本次输出回答，不再执行句柄），中间的 Pure 入口就地展开，同样回答到句柄为止。注入路径由此进入 effect graph 与 ScopeTree，不形成环；挂接的 Context 经 Pure 以外的方法又回到该句柄时生成器报错。Pure 的入口在来源分析和运行时都不改变调用者，句柄据此认出经 Pure 拉取它的 Context，不重复注入。

业务执行副本把方法体原样复制到按 effect 的类型标签 `Wrap "名字"` 上，另生成入口、按标签的路由与包装，不改写业务表达式。新的边界是读取 handler 的读取结构并按绑定生成独立结构，不解释任意业务值语义，不要求用户补写 layer 或另一份调用声明。结构提取也不证明任意 Haskell 函数的行为、动态调用次数或物理资源依赖。

当前 source 结构支持 `require @T`／`stream @T`／`rawinput` 读取、原生 `do`、`if`／`case` 和已识别的标准组合，包括顺序／绑定运算、`when`／`unless`、`either`／`maybe` 及 `catchError`。条件和待匹配的值本身不能隐藏读取。handler 直接调用其他 handler 或 effect 方法、未知高阶组合中的读取、含读取的循环组合（如 `forM_`／`replicateM_`）以及省略类型应用的 `require`／`stream` 会报告错误，不静默生成空图。没有读取的原子业务表达式可在 handler 方法体内使用原生 Haskell 语法，结构副本将其擦除；方法内直接以标准组合完成 IO 迭代或数据计算，不受上述限制。生成器还检查每个读取在每个绑定下都能路由到唯一资产、同一 handler 的各绑定推出相同签名与 Layer、声明的 requires／streams 都有读取依据。[源码资产检查](ASSETS.md) 另行约束业务模块的顶层定义；顶层检查与 effect 图提取是两个不同边界。

`catchError body recovery` 使用独立的 `Recover` 结构。scope 分析保留正文的正常路径，并为每条正文路径的任意 scope 前缀接入 recovery 路径；前缀包括空前缀和完整前缀，不假定正文一定全部执行后才进入 recovery。这是保守的静态路径集合，不执行业务来验证成功条件，也不证明某个 scope 已成功获取资源。

## 生成期构图，运行期初始化与执行

生成阶段按[主设计的编译流水线](CORE_DESIGN.md#generation)推进；本节只解释图与来源的产物关系，阶段状态和检查点不在这里另行定义。`Gen.Composition` 内部步骤可以使用 `Prototype.Query` 的共享纯关系查询：

1. **声明与挂载。** 解析注册、资产与 Input。AST 已用 `node` 指定末端，给每次挂载编号；检查 alternative 的共同 Excu 与判定 Context，定下持续会话与输出复用位置。末端不是从全图寻找的叶子。
2. **接口与方法组成。** 计算挂载、选择器、会话步骤、输出连接、有序 requests／Input、rawinput 来源和读取路由，并据此形成 handler 类型能力。前端用本次契约对手写 Handlers 做 GHC 名称解析与类型检查。`Gen.Frontend.Shape` 按原始语法提取控制流，按每个变量使用位置的 GHC `Name` 识别 SDK 的 `require` 和 `rawinput`。例如，`Payload{..} -> rawoutput [rawinput]` 中的 `rawinput` 是局部字段值；同一模块经重导出调用 SDK 的 `rawinput`，仍产生挂接输入的读取形状。机器再把形状代换成对应 effect 方法的结构，每个绑定保留各自的入口与路由。
3. **方法图。** 从同一装配结果建立挂接注入的分析副本，只消去对同次原子输出的再次索取。方法索引与活动栈检查引用，完成态摘要缓存 scope 路径与图。辅助／主 algebra 共用归约结果，不按调用次数复制展开树。
4. **ScopeTree。** 从方法图的路径求共同必经前序，补入注册前提并检查环。先有方法图及路径，再有 ScopeTree；实例共享与关闭仍由运行时的生产身份、实际使用和待用关系决定。
5. **来源、驱动标记与完成校验。** 结合方法结构、链挂载和 workflow 形成读取来源与 scope 开启计划，保留相关路径差异并裁剪无关状态。Booter 补齐单元与来源的运行关联；原型自洽和 Context 驱动检查完成后，结果才交给输出阶段。
6. **输出与类检。** Emit 读取结果，生成普通 Haskell 的契约、入口和 `generatedPrototype`。GHC 在内存中检查业务模块与本次契约、顶层白名单和源码资产，再写回 Generated；`Generated/Assets.hs` 是独立资产目录。生成的 Program、Prototype 与 Handlers 副本只是普通 Haskell，它们的类型检查交给构建，gencode 不重复。

各阶段使用不同的专门算法，按依赖关系消费前一步事实；统一状态转换控制次序，最终装配结果供生成和运行共用。分支路径、方法缓存和来源集合仍是各算法的工作数据。源码加载、语法提取、文件写入和 Haskell 渲染保持各自职责，不重新选择组合解释。

<a id="reuse-boundary"></a>
### 结构共享与执行复用

| 机制 | 复用依据 | 保留的执行语义 |
| --- | --- | --- |
| 方法目录、链定义共享 | 同一静态注册／方法身份 | 每个 AST 挂载仍有自己的 NodeId，每次调用仍执行 |
| 原子输出的挂接解析 | parser 正在接收这次调用的原始输出 | 解析不重新执行句柄；另一次独立驱动仍可执行句柄 |
| 持续资产的 ReuseOutput | 同一 lifelong 内已挂载的原子输出位置；多个位置须属于同一单元且互斥 | 保留原 AST 调用，不为订阅再启动派生生产 |
| alternative 的交接 | 共同 Excu 的同次输出按顺序只交给候选判定 parser。首个成功者发布；全失败时读取已有绑定或等待其他可供值的挂载 | 只启动选中候选并交接捕获；同一 Excu 上的其他普通 parser 须有独立的生产路径才能供值 |
| scope 实例共享 | 同一 Scoped 注册及相同参数生产身份，实例仍可用 | 由运行协议复用实例，ScopeTree 提供依赖与清理顺序 |
| 同一次调用内的重复到达 | 同一调用中已执行过的 Excu、Scoped.open、Pure 与已发布的 Context | 返回本次输出或捕获，不再执行；静态方法图仍按每处调用分别组合 |

同一次调用之内，同一 effect 只执行一次：请求方的消费链与各生产分支到达同一个 Excu、Scoped 或 Pure 时共用它本次的输出，见[消费链与生产分支](CORE_DESIGN.md#consumer-chain)。不同调用之间没有“寻找最长公共前缀，然后只执行一次”的优化。两条链共有一个 Excu 上游时，各自的调用仍各执行一次 IO；没有 requests 或 close 不构成幂等或可合并的证据。例如 A、B 都以 AppendAudit 为 Input，分别启动 A、B 会追加两次日志，按方法名跨调用去重会改变行为。即使某个外部操作幂等，省略调用也仍需保证返回值、失败和可观察时序符合原契约。

环也分层处理：方法调用递归和持续启动环报错；scope 先求路径的共同必经前序，再补不可删除的注册前提，只舍弃与前提冲突的观察边。没有一个统一的“删除环中任意边”阶段。

组合状态机入口及内部算法保留带版本的说明；未改变的算法证明沿用原版本。版本表示说明中的契约，不代替源码缓存键或 Git 历史。方法目录用 Map、活动栈用 Set，每个可达方法体只分析一次；缓存完成态，不以“已经见过”掩盖递归回边。设 N 为方法数、E 为入口与可达方法体的结构位置数，索引与引用检查约为 O((N+E) log(N+1))，不包含摘要合并和路径计算。Sequence 中重复的 Call 仍分别参与路径组合，顺序不变。

这只消除了按调用展开的重复分析。scope 路径数和相关来源状态数仍可能指数增长；摘要的列表去重、传递约简及未记忆化的 scope 祖先遍历也仍有开销。来源分析依赖挂载、捕获与前态，不能使用“只按方法身份”的缓存。按消费单元先裁剪再组合减少无关状态，不能据此宣称整体线性。这里是源码分析，未做性能实测。

### 编译期装配计划与运行边界

Assembly 是组合机器内部的装配结果，不是第二份业务注册或 RuntimeGraph，也不作为新的运行时表加载。类型能力、读取视图与入口形式同样先形成结构事实，再由 Emit 渲染；现有 Prototype、生成入口与注入表共同承载其结果。业务的资产、注册、instance、AST 和 Main 写法均不变。

| 解析结果 | 使用方 | 保留的含义 |
| --- | --- | --- |
| `EntryMount` | 组合机器的 ChainProto、Emit.Program 的入口登记 | NodeId、入口角色、结构末端、运行诊断标签、方法身份；相同方法的多个挂载仍独立 |
| `EntryStep` | 组合机器的方法组成、Emit.Handlers | 有序 RequestStep／InputStep；两处都使用 bindingBefore，不重新推导或去重 |
| `RawSource` | 结构中的 rawinput 引用、生成的 Raw 实例 | 直接 Input 的结构引用。Stream parser 的生成实例读本次 emit 的固定输入 [text]，静态来源仍指向该 Stream |
| `OutputConnection` | 组合机器的注入结构、驱动与来源证明；Emit 的注入表 | 当前 anchor → parser；`outputRole` 为 `ContextRequest` 是输出联立（每次执行都注入），`ContextStream` 是持续注入（只在原型指定的发布位置） |
| `BootPlan.ReuseOutput` | 组合结果、Prototype 与现有 runtime | 机器确定的具体 AST 输出位置，不新增独立生产步骤 |

完整方法结构仍保留顺序、分支和每次调用；最终方法目录共享定义，方法摘要在 gen 内共享。alternative 仍按契约选择并交接捕获，没有把公共前段提升到候选之外。runtime 只取得本次输出、Binding 与活 scope 实例，不重新寻找共线或尾部。scope 仍按参数生产身份匹配，本次不增加 Eq 约束或同值复用。

### 运行时初始化与执行

运行时先核对注册与源码快照，执行 `evaluate (force generatedPrototype)` 和 `validatePrototype`，检查身份、引用、挂载、父子关系、层次与无环性；随后对当前 AST 的规范形式做一次 `cata`（`foldAST` 先经同一个 `normalizeWorkflow`），逐位置匹配 `protoWorkflow`，按 `NodeId` 读取入口和 alternative 对应关系，并装配尚未执行的 action。所有分支及挂载核对通过后，才安装 scope 关系并执行业务。`ProgramStructure`、`initializeGeneratedStructure` 和旧的分散结构常量已删除。运行时不重新展开方法、运行 `zygo` 或推导父边；AST 的位置或结构变化也须重新生成。

执行 fold 的结果为 `Either`，其中携带已收集的入口及尚未执行的 `ExceptT / IO` 动作。顺序和并行分支均先检查全部子分支，完成入口集合比较后才运行 action；不会靠执行业务来强制结构求值。创建 Target 仅分配空的运行状态，不打开资源，scope 实例、使用计数和锁仍按已有运行协议管理。

`Chain` 和 `Parallel` 可以汇总 Node 的结构，但不把不同 Node 的链拼成一条 scope 启动路径。尤其不能从 AST 中“Node A 先执行、Node B 后执行”推导其 scope 存在依赖。方法结构中的路径与 workflow 的节点调度是不同层级。

这里要求完成的是有限纯结构，不是提前强制业务产物或获取资源。生成期保留 zygo 的辅助／主归约关系，按方法缓存完成的两份结果，不新增一套业务执行器。

## ScopeTree 的内部构树规则

保留每条静态 scope 路径及其来源；`EffectGraph.graphRootPaths` 记录每个入口及其 scope 路径，`graphScopePaths` 提供汇总路径。路径可以包含不同的 scope 集合；scope 记在其 open 方法体之后，即开启完成的位置，因此 open 内部开启的 scope 排在外层之前，嵌套 open 的方向与注册前提一致；每条路径按 scope 定义首次完成去重，仅用于定义层的导航，不据此推断多实例数量、重复 open 的效果或关闭后重开。

对所有路径中出现的 scope 定义 B，取所有包含 B 的路径，把各自位于 B 之前的 scope 集合求交：

```text
Pred(B) = intersection { before(B, path) | B occurs in path }
A ≺ B  iff  A belongs to Pred(B)
```

这一步只处理路径中出现的顶点，因此不存在空路径族上的全称判断。若 A ≺ B、B ≺ C，则每条含 C 的路径都先含 B，且这条路径又必须更早含 A，所以 A ≺ C。任何 scope 都不在自身之前，因此该观察关系传递且反自反，必然无环。后续补入的注册前提仍需独立校验合并结果，不能据此证明合并后也必然无环。

Pred 与由它得到的 `precedes` 只用于 `buildScopeTree` 的内部计算，随后通过传递约简形成父子边；不另行导出共同前序列表。

这定义的是“在给定静态路径族中，B 的共同必经前序”，不是物理资源依赖的证明。不能把一条路径中的普通先后全部当成必需依赖，也不能先合并所有候选边、再删除整个强连通分量来得到结果。

| 路径证据 | 内部共同前序 | 含义 |
| --- | --- | --- |
| `A B C`、`B C A` | `B ≺ C` | A 的位置可变，不应连同 B、C 一起删去 |
| `A B`、`B C`、`C A` | 无共同必经边 | 局部顺序不足以确定全局关系，不能宣称全部独立 |
| `A B C`、`B A C` | `A ≺ C`、`B ≺ C` | C 有两个前序，结果不一定是一棵单父树 |

公开结果只有 `ScopeTree`，其父子边表达构树结果，以下路径与候选证据直接保存在同一结构中：

- `scopePaths`：各独立 chain 的路径，而非跨 Node 拼接的运行顺序。
- `scopeCandidates`：原始候选关系，来自单条路径的前后关系，尚未当作必经边；入口来源见 `graphRootPaths`。
- `scopeOpposed`：存在两条分别包含 A、B 的路径，一条为 `A … B`，另一条为 `B … A`。这是无固定顺序的双向实证；不能用不同路径的边拼出的 union reachability 代替。
- `scopeUndetermined`：仅凭路径不能建立共同必经关系、又没有上述双向实证的未定关系。缺少共同路径或覆盖不足不等于独立；补充的注册前提可能进一步确定这些节点的清理关系。

中介不改变单条路径的顺序证据：`A X B` 已经表示这条路径上 A 先于 B。把一条路径的 `A X` 与另一条路径的 `X B` 拼成 `A B`，则不能冒充实际路径证据。新增路径可能削弱已知顶点间的共同前序；结论始终相对于所保留的路径族。

这里的双向实证来自所保留的静态路径，包括 Recover 的保守路径；它不是运行采样，也不要求证明这些业务分支一定能成功执行。

## ScopeTree 是共享节点的 DAG

对共同必经前序做传递约简，保留相同的可达关系，得到无冗余边的 DAG。`ScopeTree` 以共享节点、`parents`、`children` 和 `layers` 表达它，不强迫每个 scope 只有一个父节点。

生成期的 `buildScopeTree` 形成路径观察结果，`completeScopeTree` 把注册前提补入同一份树并再次传递约简。结果保存在 `generatedPrototype` 的 `protoScopes` 字段；运行时直接读取，不增加另一份 scope 计划或持久化依赖图。

多条路径引用同一定义时，共享该节点；各路径证据仍分别保留。最终父边和 `layers` 表达采用的保守清理偏序，不因同层而断言资源使用互不影响，也不据此重排业务方法或提前执行 open。

## 注册前提与运行清理

生成期从 `EffectProto` 的方法、名字与 `effectScopeParents` 取得每个可开启 scope 的 open 方法身份、运行名字及保守前提。前提包括 `Input`／`requests` 链上的 scope，以及声明的 `requires` 来源可导航到的资源 Context owner 候选。这种结构补全不预执行来源生产者或打开 owner；运行时的读取已有值直接读取，缺值时等待发布、不生产；资源 Context 缺值不等待，按 owner 协议报错。关闭本 scope 自己声明的资源不会形成自依赖。实际实例归属仍由 Context 绑定中的 owner 决定。

生成期合并的是上述前提和 `buildScopeTree` 得到的共同前序，不使用 `scopeCandidates` 的并集。注册前提是依赖：上游 scope 必须比下游活得久，下游的 close 也可能读取上游资源。观察到的开启顺序是证据：共同前序按完整传递关系逐条补入，与注册前提及已补入的边构成相反方向的不作为父边，例如结构中先开启 B、后开启 B 的 Input 上游 A 时以 A 为 B 的父节点。被推翻的顺序仍保留在 `scopeCandidates`，`--structure` 单列显示。所有可开启注册 scope 都进入最终树，包括本次结构没有出现 open 的注册；它们没有被执行就不会产生待清理资源。重复身份或名字、缺失映射、未知前提及注册前提自身的环均在生成时报告错误。

最终依赖只保存在 `ScopeTree` 的 `parents`／`children`／`layers` 中；`scopePaths`、`scopeCandidates`、`scopeOpposed` 与 `scopeUndetermined` 保留原路径证据，不能误读为新增的注册前提也已由路径证明。`protoScopeNames` 连接生成身份和运行名字；`scopeRelations prototype` 临时投影同一棵树的全部祖先可达关系为运行配置，不另存第二份依赖结构。这样即使 `A → B → C` 中 B 尚无活实例，C 仍会保留 A 的清理前提。

运行层按最终父边先清理子 scope，再清理其前提；独立项延续现有句柄顺序的逆序。ScopeTree 的祖先关系仅作实例关联的候选：同一受控链实际使用父、子实例时，在子实例的 `scopeParents` 中保存具体父引用；先出现子实例、后使用父实例也会补齐。子实例不会因为注册关系而保留该父注册下其他链的全部实例。清理条件同时读取这些实例引用、实际使用和执行帧的待用关系。`scopePaths` 只包含去重后的 open，不能把路径长度或出现次数当作使用计数；待用依据来自 `protoScopeOpenings` 和节点进度，资源业务读取须已在本链开启所属 scope。

<a id="scope-parent-retention"></a>
**具体父引用的当前边界。** 子实例存续期间，`scopeParents` 只追加，不随一次使用结束或参数更新撤销。长期存活的子实例先后与多个父实例在受控链中一起使用时，这些父实例可能一直保留到子实例关闭；每步独立的 ScopeUser 不会消除这条保留路径。它是当前的保守依赖记录，不证明每个历史引用仍是后续操作的必要条件。安全撤销须区分资源获取／关闭所需的依赖与单次执行的共同使用，见[后续设计项](NEXT_STAGES.md#review)；当前不能仅因出现新 request 就删除旧父引用。

## Error 与清理使用同一棵树

App／IO 的生成入口沿 Input／requests 关系查找最近的 scope，遇到 Scoped 就停止，得到关联种子而非完整祖先名单。Root 捕获 Failure 时合并已有 `scopeTrace`、当前 `errorPath` 与 `scopeTargets` 中的 scope 名字；生命周期锁内只保留这些种子，退到锁外后才导航和诊断。

`scopeErrorPath` 直接读取各 `ScopeHandler.scopeParentNames`。这是自动清理也使用的同一棵 ScopeTree 的全部祖先投影，不读取另一份 schema 或新增用户 key。SDK 补齐种子的祖先，按父到子的层次去重排序；同层沿 ScopeHandler 名单顺序，同一 scope 的多个 Error 回调沿注册顺序。完成路径写入 `Failure.scopeTrace`，再按路径匹配既有 callback 注册表，不把 callback 表本身当作依赖图。

此次接线只改变 App／IO 的候选导航来源。实例定位、隔离绑定快照、detect／resolve 结果和原失败传播继续沿用既有协议；不增加轮询、动态调用 tracing 或自动业务恢复。App／IO 未安装树时只能使用显式种子；Pure 没有 ScopeTree 安装路径，本轮继续使用旧的完整候选名单协议。

手改生成树的父边会同时影响 App／IO 的 Error 祖先导航和自动清理。运行校验只证明字段一致、无环等结构自洽性，不证明手改关系符合业务资源前提或故障归属。

## 查看初始化结果

生成的 `Generated.Prototype` 定义静态的纯值。`Generated.Program` 也导出同一个值，并把它交给 interpreter。

```haskell
generatedPrototype :: SDK.Prototype MethodGen
```

现有 Main 无需修改，选择 `--structure` 模式即可查看。具体命令及其与生成、业务运行的区别见[指南：命令行与执行阶段](GUIDE.md#commands)。

该分支通过纯校验核对当前 AST 与原型快照，以可读格式显示带 `NodeId` 的 workflow、origin／ctx 链定义、链挂载、方法及其 effect 归属、方法引用、scope 层次与共享父节点、各入口路径，以及双向实证和未定关系。它读取同一份原型，不调用 `createEntries`，不创建运行 scope 句柄，也不装配或执行 handler。普通启动在自己的单次执行装配 fold 中核对相同挂载规则。修改注册、AST 或手写 handler 后须重新生成。

<a id="cache"></a>
## 重跑边界

每次 gencode 都读取声明与 Handlers 快照，从头完成组合：结构分析和执行副本共用该快照，顶层检查与资产目录另用 GHC 名称解析同一快照。构图本身只需数毫秒，不设结构缓存（读取并比较缓存比重算更慢），`validatePrototype`、`checkDriven` 与源码资产检查每次执行；首次没有 Handlers 时仍按原协议跳过驱动检查、先提供契约。每份生成文件都先比较完整内容，内容相同就不写回，未变文件保留时间戳；这不是逐方法热点生成、文件监听或运行中热重载。

生成时间主要花在 GHC 会话上。会话只做类型检查（不生成代码），并把接口写入 `dist-newstyle/effect-codegen-interfaces`：SDK 与未改动的业务模块下次按源码哈希复用，源码或内存 target 变化时 GHC 照常重新检查该模块及其下游。接口里的名字不带源码位置，资产目录的定义位置因此取本次类型检查的结果。

`Generated.Prototype` 仍是派生产物。手改 `generatedPrototype` 中的 `protoScopes` 后，运行校验读取这些显式字段，不会重新推导父边；它只验证无环、字段一致等结构自洽性，不证明人工删边在业务上正确。下一次 gencode 会按源声明和方法结构恢复生成结果，不把手改文件当作权威。不增加手工 edge override 层，也不承诺保留生成文件中的手改。

本轮沿用项目的普通编译要求，不新增测试、负例或检查门槛。


## Context 的剧本驱动检查

AST node 末端必须是原始句柄，不能是 Context。gencode 从每个挂载末端沿显式方法引用求可达集合：读取方法不连到生产方法，生产只经 `requests` 驱动到达；挂接句柄可达时，其 Context 生产也视为可达；alternative 的选择读取末端执行共同的 Excu（及其判定 Context），同样作为起点。

任一 Context 的生产方法无法从这些入口到达时，生成器报错。挂接的 Context 经其他方法回到原句柄同样报错，不把直接输出回答与间接递归混为一谈。驱动检查与末端检查每次生成执行；首次缺少 Handlers、尚无方法结构时先生成契约，待方法实现后补齐完整检查。

这项静态检查证明存在允许的结构路径，不证明本次条件分支一定生产。Stream 的生产方式按 [BootPlan 规则](STREAM_LIFELONG.md#bootplan)只由生产方注册决定，不由可达性推出。
