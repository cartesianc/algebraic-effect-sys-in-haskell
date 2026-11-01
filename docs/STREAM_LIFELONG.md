# Stream 与 lifelong：资产驱动的自动装配

本文通过引用构成[主设计第 7 章](LATEST_DESIGN.md#stream)的完整规范。主设计负责架构地图，本页唯一维护 Stream 的匹配、交付和调度规则；实施进度在 [TODO](TODO.md)。


更新：2026-11-01。状态：Stage 3 设计规范已确定，SDK 实现尚未开始。

本文手工记录 Stream、Context 与 lifelong 的匹配规则，作为后续代码生成、解释器和开发文档共同遵守的规范。不是从当前代码反向生成的行为说明，也不表示以下接口已经可用。当前已实现的有限 workflow、Prototype、来源约束与 ScopeTree 见 [现有设计](LATEST_DESIGN.md) 和 [结构模型](EFFECT_GRAPH.md)；实施顺序见 [TODO](TODO.md)。

## 1. 目标：让原子方法独立于装配知识

业务作者按已经生成的类型和原生 Haskell 编写一次操作、一次解析或一次消费。SDK 根据注册、显式方法结构、资产契约和 AST 控制关系，自动生成生产、解析、交付和 target boot 的连接。

这套“榫卯规则”是语言和 SDK 的设计契约：

    声明与可提取的方法结构
    → 检查匹配前提
    → 生成唯一装配及其依据
    → interpreter 执行已经装配的闭包

业务作者需要知道本地输入输出、可用类方法、request／require 和 raise，不需要知道 BootPlan、会话、游标或调度循环。规则同样供声明工具使用；SDK 本轮不增加 LSP 协议。

自动装配依赖明确契约，不从任意 IO 恢复作者意图。匹配不唯一时生成期诊断，不按方法名相似度、运行速度或最后写入猜选。原子化约束保证组合可观察，不证明任意方法体足够细、无副作用或必然终止。

AST branch 继续规定何时、按何种顺序、选择哪些入口以及是否重复 boot。业务方法组合仍在 instance 内，AST 不成为业务值 pipeline。程序入口保持 interpreter ast effects。

## 2. 术语与职责

| 结构 | 职责 |
| --- | --- |
| Stream effect | 第六种 typing；持续生产节点，手写方法每次取得一份原始输入 |
| Context.request | 一次主动生产和解析，成功后发布资产 |
| Context.stream | 解析 Stream 已经交付的当前输入，成功后发布资产 |
| Context.require | 读取已有绑定／固定视图；缺值按合法生产能力求值 |
| streams demand | 消费方声明以某资产的新增量驱动；不是调用 parser 的语法 |
| lifelong | 安装订阅与受控回调，根据资产交付和控制位置 boot original target |
| BootPlan | 生成器推导的内部生产驱动方案，不是手写业务标签 |
| publication | 一次成功发布；保留值、出身和共享归属引用 |
| 消费单元 | lifelong 下独立推进的有限控制程序 |
| frame | 消费单元某次执行的绑定与普通来源解析范围 |

Stream 不直接进入 original chain，也不作为 AST target；通过 Context 资产需求进入生产链。original target 始终代表一条完整消费链的末端。

socket、event、behavior 可用于解释不同驱动关系，但不是新增类型标签。结构分析擦除原子 IO，不能据此证明它属于哪个业务类别。一次阻塞接收也可以由 request 实现；角色互斥是本版的声明约定。

## 3. 资产、方法与 beforegen

### 3.1 资产身份独立于方法身份

业务表示类型先在 Types.hs 中定义，资产声明引用其类型和业务名称。SDK 生成 refined 契约包装、访问接口与统一 History 视图，不推导业务字段或 Raw 到资产的解析算法。

资产名不再由生产方法名反推。目标接口以具名资产描述和三个 Maybe 角色表达；方法名从资产名 T 固定生成：

| 角色 | 名称 | 方法体职责 |
| --- | --- | --- |
| request | getT | 生产一个成功资产 |
| require | readT | 读取确定的资产视图，SDK 提供存储读取实现 |
| stream | streamT | 用当前原始输入解析一个成功资产 |

下列片段表示拟迁移的注册形状，不是当前 SDK 可运行示例：

    typing = Context
      { asset   = namedAsset "TemperatureSample" @Temperature
      , request = Just ()
      , require = Just ()
      , stream  = Nothing
      }

表示类型手写，两种供给方式的契约包装和 History 生成规则相同。首次生成契约后才编写 Handlers；新增类型、默认方法和 parser 输入能力必须在执行副本生成之前就存在。

### 3.2 Context 角色的匹配表

先检查被 streams 订阅的 Context 的直接输入和角色：

| Context.input | request | stream | 判断 |
| --- | --- | --- | --- |
| Stream effect | 必须没有 | 必须有 | 明确的 Stream 来源与 parser |
| 普通合法 effect／Root | 必须有 | 必须没有 | 可复用 request 的普通生产来源 |
| Stream effect | 任意 | 没有 | 报错：缺少 parser |
| Stream effect | 有 | 有 | 报错：两种生产角色冲突 |
| 普通合法 effect／Root | 任意 | 有 | 报错：parser 没有对应的 Stream 原始输入 |
| 普通合法 effect／Root | 没有 | 没有 | 被 streams 订阅时报错：缺少生产入口 |

request 与 stream 互斥；require 独立声明。未被持续消费的普通注册仍按其原有合法性规则检查，不因本表强迫所有注册提供生产入口。

Input 提供能力不等于方法一定被执行。表中 Stream 输入是明确的产出连接，不能因为任意祖先具有 Stream 能力就把它认作当前输入来源。

### 3.3 消费权限与固定类型

消费方写 streams "T"，方法体继续用 require @T 读取交付。streams 同时授予这项读取权限，不要求再写 requires "T"；对应读取角色必须存在。

只写 streams 不授予显式 request 权限。需要主动生产仍须声明 requests "T"；普通 requires 不建立持续回调。

原生 stream parser 存在，或者资产被声明为 streams 消费时，生成器在契约阶段将其识别为持续契约。持续契约的 getT／streamT 返回单个资产，readT 和 require @T 返回固定的 History T 视图；request @T 仍返回本次生产的资产。普通契约保留单值读取。

同一契约在一份生成接口中只有一种读取类型，不随消费者或运行时是否存在订阅变化。增加持续消费若改变原有读取接口，必须重新生成并由 GHC／HLS 检查受影响代码；需要独立单值契约时沿用资产细化，不暗中转换。

History 是从来源首次成功发布到确定发布位置的有限、不可变序列视图，不是业务手写的无限列表。相等值的两个 publication 仍是两个增量。无限的是 SDK 持续推进的过程。

### 3.4 原子输入与源码约束

Stream 手写方法一次返回一个 Raw，Context.stream 一次解析一个 Raw；parser 不再次请求生产入口。parser 输入读取能力只生成到对应 Context 接口，不加入公共 Root。泛型 Inputs 约束与源码结构检查共同限制调用位置。

业务只写原生 instance、类方法调用、ADT、局部计算和 raise。不要求手写 Yield、递归连接、publish、subscribe、acknowledge 或回调参数。现有资产显式引用约束继续适用；原始输入中的业务 ADT 也纳入类型目录，并将构造权限关联到实际生产它的注册方法。

当前 Excu／Scoped 的 Maybe String 仍表示可选信息，不能把 Nothing 改释为 EOF。Stream 的单步输入类型单独声明；正常结束协议本版延期。

## 4. 自动推导 BootPlan

### 4.1 两个不同判断

角色匹配确定“由哪个方法生产和解析”；BootPlan 再确定“谁已经负责驱动、是否需要 SDK 主动启动”。

在同一 lifelong 的共同来源范围内，对每个 refined 资产统一决定 BootPlan：

| 规则 | 可证明的前提 | 生成结构 | 运行行为 |
| --- | --- | --- | --- |
| B1 接收生产 | Context 明确连接 Stream，角色匹配合法 | 原始入口＋parser 的引用 | 启动受控接收会话，逐次获取、解析、发布 |
| B2 观察原链 | 普通来源已有唯一合法的原链生产职责，且能独立于本次待交付增量启动 | 原链来源／发布点＋观察关系 | 保留既有原链驱动，接入发布与故障通知 |
| B3 请求序列 | 能确定没有可复用的既有原链驱动，request 可合法独立启动 | request 入口引用 | SDK 连续执行完整 request |
| B4 诊断 | 来源、启动职责或生产前提不能唯一确定 | 冲突位置与推导证据 | 在业务运行前拒绝，不按时序猜选 |

内部名称 Receive／ObserveOrigin／RepeatRequest 仅用于实现和结构展示，不增加手写 socket／event／behavior 枚举。

B2 的“已有驱动”必须有控制流授权与合法来源依据，不能只用方法可达性。原链可能有条件调用，也可能只发布有限次；保留其条件，零次或有限次发布不自动意味着错误。

    C 中存在调用 P
    C 又必须先获得 P 的产物才能 boot

上述路径不能作为只监听的依据。生成器须确定合法的独立 request 启动方案，或者报告启动依赖环；不能先等待一个只有等待结束后才会产生的值。

“无法证明有驱动”不等于“已经证明没有驱动”。有多个候选或控制职责不明确时使用 B4，不偷偷退化为主动轮询。

### 4.2 分析范围与约束

- 复用原链和祖先控制结构、已确定的顺序前驱、产出挂接与跨链生产能力。
- parallel 旁支的偶然发布和 require 命中快照不是已有主动驱动的证据。
- 来源必须满足相应消费位置的可见性。共享会话不使普通兄弟资产互相可见。
- 不以最先到达消费者的私有参数初始化共同来源；生产前提无法合法统一时要求细化或报冲突。
- 不把 Input 能力关系变成必须执行的操作，不越过原调用条件补跑。
- 不删除、合并或重放原有显式 request。复用的是既有生产职责，不是把同名调用视为同一次。
- ObserveOrigin 没有新发布时等待，不因沉默自动切换为 RepeatRequest。
- 普通来源成为请求序列时不需要手写另一段 stream parser。

结构可以在不同 workflow 中为同一个 request 推导不同的 boot；结果属于当前装配，不能给资产类型永久贴业务模式标签。

## 5. 静态消费摘要与合法性

消费摘要沿以下关系生成：

    AST target
    → original chain 自身及其 Input 组合
    → streams demand
    → 基础资产契约
    → 唯一 Context
    → BootPlan

必须保留 original／Context 链边界。当前 chainReaches 包含 Context 缺值求值与生产链的传递可达方法，不能直接把其中全部 effect 的 streams demand 汇总成 target 的触发资产。生产链内部依赖另用于生产前提检查；仅过滤 Context 方法类别也不够。

生成器记录消费位置、完整链末端、资产、来源、单元划分和推导依据。runtime 初始化按引用装配订阅和闭包；每次发布只处理关联订阅者，不扫描整张运行图或检查 handler 是否为空。

lifelong 合法性规则：

1. 每个挂载的 original target 的完整链恰好声明一个可解析的 stream 基础资产；分支投影按基础契约归一化。
2. 只有普通 request／require 的挂载不得进入 lifelong；一次性准备模块放在外部 chained。链内普通上游原子方法仍允许。
3. Stream、Context 不作为 original target；消费者通过 demand 跨链进入生产。
4. 每个单元成功回到入口的路径至少推进一个尚未交付的 publication。普通快照重读不算；已有积压可立即领取，不要求线程真正阻塞。
5. 检查角色、输入类型、来源唯一性与启动依赖；首版拒绝嵌套 lifelong 和成功空转路径。
6. 若 alternative 前有必经的新交付，它可覆盖该单元后续路径；不要求每个候选重复领取。
7. 合法 Haskell 不自动等于结构可提取；未知高阶 effect、隐藏的 effect 循环等继续使用现有诊断。

这些检查不证明任意原子 IO 能够返回，也不证明即时采样会主动限速。生成期可以建立索引和复用摘要，但没有性能实测时不宣称整体分析成本可忽略或线性。

## 6. lifelong 的回调 boot 与控制流

### 6.1 单元划分

lifelong 的直接子项分别形成独立单元；直接子项为 parallel 时，只拆这一层。其余子树作为有限单元，不穿透 chained、alternative 或更深的 parallel。

    lifelong [parallel [chained [a, b], c]]

得到单元 chained [a, b] 和单元 c，两者独立推进。chained 内的 b 等待 a 本次调用成功；c 不等待 a、b 完成后才领取下一条。

    lifelong [chained [parallel [a, b], c]]

这是一个单元；内部 parallel 保留局部汇合，再执行 c。拆分边界写入 Prototype，不由 runtime 猜测或递归拉平。不存在整个 lifelong 的统一轮次。

### 6.2 两个完成边界

| 对象 | 完成含义 |
| --- | --- |
| 一次 target 调用 | 既有成功／失败协议；本次 original chain 完成 |
| 持续订阅／lifelong | 保持存续；本版没有正常 Succ，只因失败或取消退出 |

target 每次仍有自己的 Origin。订阅对象不能伪装成一个永远不返回的普通 target，否则 chained 无法推进。lifelong 安装订阅后也不能立即冒充整个 branch 的 Succ，否则外部 chained 无法表达完成依赖。

### 6.3 统一就绪检查

资产成功发布和前驱调用完成都只通知同一个调度入口：

    资产发布 ───────┐
                   ├→ 控制流允许＋本次交付已就绪＋尚未启动 → boot target
    前驱完成 ───────┘

发布不在生产者调用栈里同步执行消费业务，也不能越过 chained／alternative 启动全部消费者。

后继数据若在前驱执行期间已到达，前驱完成时仍须检查积压和已捕获视图，避免漏唤醒。两种通知并发到达时，只允许一次启动登记。

单元内部一次执行对同一资产只领取一次。后续节点、alternative 选择与候选复用同一视图；内部 parallel 同时首次领取时也由 SDK 协调为一次。每个单元的连续执行串行，不隐式重叠同单元的多次调用。

单元完成后撤销本次使用与捕获，推进到下一次待交付状态，并检查已有积压。当前生产任务仍独立运行。

### 6.4 外部组合

| 写法 | 行为 |
| --- | --- |
| parallel [monitor, otherWork] | 两者同时运行；monitor 等待增量不阻止 otherWork |
| chained [setup, monitor] | setup 成功后进入 monitor |
| chained [monitor, after] | after 等待 monitor 结束；本版 monitor 没有正常完成 |
| chained [parallel [monitor, otherWork], after] | 内层分支的完成仍是 after 的前提 |

monitor 表示 lifelong 模块。并发运行与整个 branch 已完成是不同概念。

## 7. 会话、历史、捕获和运行身份

| 状态 | 归属 |
| --- | --- |
| 会话与逻辑历史 | lifelong 实例＋refined 资产 |
| 交付游标 | 消费单元＋会话 |
| 本次固定视图 | 单元执行 frame＋资产 |
| target 执行 | NodeId＋新的 Origin |
| 生产／解析 activation | 实际入口及所属生产会话，不依附已结束的首轮消费 |
| scope 归属 | 既有 Binding ownership 与具体 scope 实例 |

同一边界同一资产共享会话，不同单元独立广播消费。不同 lifelong 的会话与进度独立；ObserveOrigin 可以分别引用同一合法原链，但不得因此复制原链的一次显式执行。

普通跨链来源解析使用本次 frame 和合法外层前驱，不能因为 NodeId 相同就读到上一轮的普通产物。stream 的跨次历史交付显式经过会话，不绕过来源约束。

运行初始化安装静态发布记录和路由，不预生产 Context。持续契约从合法来源首次成功发布起记录历史；lifelong 入场时绑定来源并形成会话视图，不能从目前仅保留最新值的 runtimeAssets 反向恢复过去全部记录。逻辑会话可以引用同一 publication，无需复制值或重新发布。

订阅登记与起点选择统一协调。首次交付当前最新历史视图；之后按序交付订阅范围内的每次新增量。保存全部历史不等于新订阅重新执行所有历史 callback。

每条 publication 保留原始 Binding、Execution 与共享 ownership；history 不是一个新的单一 owner。后台追加不会改写已捕获视图。require 不推进游标。

## 8. 生产、显式 request 与普通读取

### 8.1 两条主动生产路径

    Receive：
    Stream 单步取得 Raw
    → 安装 parser 当前输入
    → Context.stream 解析一次
    → SDK 发布一次
    → 继续生产

    RepeatRequest：
    执行既有 Context.request
    → 它完成生产、解析、发布
    → SDK 安排下一次 request

request 包装已经发布，外层会话不能再次发布返回值，也不能再调用一次 parser。每次生产建立新的局部捕获环境，不把首轮读取永久冒充后续读取；来源按合法边界环境解析，scope 实例仍按既有协议复用。

单步方法的阻塞／等待决定节奏。SDK 不解释 IO，也不擅自增加间隔。立即返回的 request 可能形成高频生产，完整历史允许积压增长；本版不提供隐式容量背压、丢弃或去重。

### 8.2 显式 request 仍可能产生反馈

原生 Stream 来源禁止 request，但请求序列 Context 仍有 request。消费者同时声明 streams "T" 和 requests "T" 时，callback 内的 request 仍会产生新的 publication；互斥规则没有消除这种反馈。

在 lifelong 内，对关联资产的显式 request 发布到选定会话；调用不合并。它可以替换当前 handler 调用的捕获，不原地改写单元固定交付或其他调用快照，也不推进订阅游标。新发布由后续交付处理，不在当前栈递归启动消费。

外部普通 request 按原有 origin 发布，不因类型相同就广播给所有 lifelong。若该 origin 本身就是某个 ObserveOrigin 计划选定的合法来源，其发布按已经建立的观察关系交付。

### 8.3 有限读取

普通 requires "T" 仍只执行一次消费，不因此进入 lifelong。已有值时读取固定视图；缺值遵循合法生产能力及既有诊断／资源缺值例外。

有 request 时可以按 thunk 求值一次；没有 request 的原生来源通过相应 Stream 会话取得首值，不伪造 request 方法。有限 require 若启动了持续会话，该会话由本次 interpreter 托管至退出；本版不以这次读取返回作为自动停源条件。

## 9. 故障、任务所有权与资源边界

### 9.1 发布和观察都接故障出口

主动生产或解析失败进入现有 Error 协议，不发布、不用旧值唤起新消费。

ObserveOrigin 的路由同时接成功和失败通知。不能因为原链的可选挂接原本吞掉 parser 故障，就让活动订阅永久等待。对应会话收到失败并停止；原链自身是否传播该注入故障仍遵守其既有规则。不二次解析、不重放生产，也不重复激活已处理的 Error。

### 9.2 退出只取消自己拥有的任务

任一单元失败后，停止所属 lifelong 的新 boot，取消其他单元，唤醒等待者，等待受控调用收尾后传播原失败。清理故障不覆盖原失败。

| BootPlan | lifelong 拥有什么 | 退出时的动作 |
| --- | --- | --- |
| Receive | 自己启动的接收／解析 worker | 取消并等待 worker，撤销自身使用 |
| RepeatRequest | 自己启动的请求序列 worker | 停止新请求、取消并等待在途工作 |
| ObserveOrigin | 观察关系、游标与消费任务 | 撤销观察；不能擅自取消外部 original chain |

包含长期任务的并行监督使用异步失败通知，不能先等一个永不结束的分支才看到另一个分支的失败。普通有限 parallel 保留既有汇合规则；不默认改变全部并行程序。

### 9.3 close 延期的含义

不新增 Stream close、next-use 或历史资源按元素关闭协议。没有增量表示等待，不表示 EOF、故障或关闭。

生产会话实际使用的资源不得因一次消费完成而释放。消费侧独有的有限 scope 继续 once-spare；运行退出继续采用现有 ScopeTree 清理兜底。在途交付先登记接收方使用，保留原 ownership，不复制或覆盖归属。

完整历史保留不等于可以把多份资源 owner 合成一个，也不能复活已关闭的资源。通用历史资源选择／关闭语义尚未设计，本版不宣称 SDK 能从纯模式匹配中看出业务选中了哪个 owner。生产会话及历史相关的运行期保留可能持续增长，不承诺有界资源占用。

## 10. 生成和运行的实现边界

沿用统一 Prototype、RuntimeGraph、ScopeTree：

- Prototype 保存角色、消费摘要、单元划分、BootPlan、来源及推导证据。
- 首次无 Handlers 时先生成类型契约；可执行方案必须在方法结构补全后通过启动和来源检查。
- 生成结构有限，使用 MethodGen 和已有静态位置引用，不产生业务手写 key。
- runtime 完整校验生成结构，一次 cata 装配闭包，再安装运行记录与执行。
- 新增会话、frame、历史和游标，但不累计完整方法调用历史或无限 workflow 结果。
- 不预展开无限 IO／AST，不要求业务手写 ana、comonad 或调度递归。
- --structure 展示采用哪条规则、消费位置、生产入口和来源证明；过期或不自洽的原型在业务前拒绝。
- ScopeTree 独立构建并保持无环，继续供清理和 Error 导航；callback／订阅关系不直接作为 scope 父边。

## 11. 实施与验收

实施顺序和完成状态统一见 [TODO 的 Stage 3 批次](TODO.md)。每批保持必要普通编译通过；本节只保存实现需要满足的场景和延期边界。

重点验收场景：

- 三种 boot 有明确推导证据；不以可达性冒充独立启动。
- 请求序列的 Context.stream 为 Nothing，仍可合法被 streams 消费。
- 消费摘要不混入 Context 生产链内部的依赖。
- 观察原链不额外执行原链，退出不取消其未拥有的任务。
- 请求序列只发布一次；相等值仍形成两个 publication。
- 同一边界共享会话，各单元独立推进；同一单元共享一次交付。
- 普通资产跨 frame 不串读；已捕获视图不被后台追加改写。
- B 的数据提前到达，A 完成后仍能启动 B；两类通知同时到达不重复 boot。
- parser 故障通知观察会话；失败与取消解除等待并等待受控收尾。
- 手写与生成 Handlers 分别接受 GHC 检查，不靠执行副本修复类型。

本仓库当前只进行必要普通编译、生成结果审阅和示例观察，不新增测试框架、负例或穷举门槛。示例没有正常 EOF，观察输出后手动取消；不会为演示增加 max-rounds。LSP 仓库的穷举模型扩展另行安排，不记为本仓库已完成保证。

本版明确延期：正常 EOF／Done、Stream close、历史资源精细关闭与回收、嵌套 lifelong、自动重试、时间周期声明、容量背压、任意外部 push callback 注册和跨 interpreter 存续。已有阻塞事件／队列读取、socket 接收及主动采样可作为单步来源；不据此宣称自动适配所有外部回调 API。
