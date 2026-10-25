# 基本设计方法：可序列化组合与原子值操作

更新：2026-10-26。本文记录用户明确的设计方向，作为后续接口设计的依据。
当前实现集中在各 demo 目录与共享 SDK；可执行样例是实现证据，不反向固定新设计。

effect typing 仅有 Pure、Excu、Scoped、Error、Context 五类；旧 Request 类型已并入 Context。
request／require 是 Context 内的方法角色；消费者统一在 context 属性中声明 request／require 的来源与接收 ADT，不另设 Request typing。
独立 Middleware typing 与 AST／Hanging 挂载是后续扩展，当前只接通 Root 调用入口，不增加其注册构造。

最新设计见 [LATEST_DESIGN.md](LATEST_DESIGN.md)：固定 interpreter ast effects 入口，业务注册声明 request／require，SDK 装配执行闭包并复用已开启的可用 scope；Generic Map 作为内部结构适配，不新增 adapter 配置。对外产值的业务转换归 Context；Scoped 在同一个 effect 的 class／instance 内提供无产物的开启与关闭，信息由上游 Context 提供；Error 在同一个 effect 的 class／instance 内提供 detect 与 resolve。独立 Read 已取消。本文记录基本方法，具体语义与落实范围以上述文档为准。

当前工作聚焦 Algebraic Effect Sys in Haskell；设计声明、样例与方法文档在项目根目录的 sdk、demo 与 docs 中推进。
旧实现与设计材料保存在 [archive/legacy](../archive/README.md)，仅作背景参考，不默认同步改写历史文档。

## 1. 设计先于操作

设计阶段应当能够声明 effect、handler 契约及它们的关系，而不必先填写原子操作实现。
设计不设置独立 impl 层，也不要求每个 effect 注册一个 impl。原子传值、产值、请求匹配
与 IO 语义由 handler instance 提供。Input 由 effects 声明并落实为 handler 之间的
superclass 依赖；instance 直接引用上游类方法，Node algebra 只 lower 末端。SDK 的 interpreter
统一驱动。用户书写面分为 effect 注册、handler 实现和 AST 构建；业务组合 facade 限于
ast 和 effects，不要求业务编写节点执行器或闭包装配过程。

除原子值操作外，业务组合语义应高度抽象、可序列化：第三方工具、DSL 或语言服务只需理解
框架规定的结构与接口契约，就能生成固定模式的代码，无需理解任意 Haskell 业务函数的语义。
Haskell 类型检查仍负责生成代码的类型正确性；原子实现的行为由其作者负责。

## 2. 组合必须是可描述的关系

控制分支、Input 关系、值来源、成功与错误路由、mapping 调用、handler 引用、scope 归属、
生命周期策略和 middleware 挂载，应尽量表达为明确的构造、引用和契约。
新增一种组合语义时，先说明工具能读写的结构与含义，再确定 Haskell 表面写法。

组合描述不能依赖解析任意 lambda、函数组合、do 块或 IO 闭包来恢复业务关系。
例如 mapping 的描述保存原子转换的引用及输入输出连接，不把任意 a -> b 函数当作可序列化字段。
实现函数、类字典、线程和活资源由执行装配持有；描述通过约定的标识与接口关联它们。

Input 只表达句柄组合，不隐含业务值传递。手写 input 只允许 Root 或非 Context effect；Context 经 context.request／require 声明进入生成的 superclass。生产者自身仍可有 Input、消费其他 Context，也可直接作为 target。原 Input 与生产链的能力同时保留，不重挂来源注册；沿 Input 与 request 收集 scope，require 只读取绑定，不启动生产链。
后端 handler 可使用前端类方法，这是 superclass 字典形式的依赖注入。
句柄组合位于后端 instance 对 superclass handler 的引用中。SDK 不生成 withX、initializeX 或链式 runX，
不在外部按 Input 排序补跑方法。Generated 模块只登记末端句柄，Node 的 f-algebra 才将它 lower 成具体执行函数。
未被引用的上游不会执行；这一可达性规则不等于 GHC 会拒绝遗漏调用的方法体。
装配后的 impl 是 Node lowering 的结果，不另设用户组装层，也不要求启动占位参数。

同一注册集合生成统一 Root、载体与 scope 句柄；Context 来源通过 superclass 传递整条生产链的能力，共享祖先不复制实例。直接重复约束按身份去重，传递能力由 GHC 求解；不去重实际 request 调用，也不改变来源的 Input。跨独立生成环境的 pipeline 链接另行设计。
SDK 的 Effect 类提供内部 `handler :: m value -> m value`；Root 转交 SDK 的 Failure 捕获协议，其余生成的 Effect instance 转交同一 Root。生成器在注册方法入口自动包装现有协议，涵盖普通方法、Context.request／require（含默认读取及覆盖实现）与 Scoped.open／close；业务不写 handler／super 前缀。Root 不替换业务 caller、不预执行 Context、不重新 boot；每次方法调用经过入口一次，scope 复用仍可跳过业务方法体。Error 回调由注册生成并接入 Root，不要求新增 AST 节点；独立 middleware 策略仍待设计，不保留旧 pipeline 路线或增加运行时 pipeline key。

注册保留可观察的依赖图，SDK 按这些关系组合 handler。普通函数可以是解释后得到的执行结果，
但不能成为工具无法观察的业务组合边界。框架内部的 fold、解释器和后端可以使用 Haskell
函数与 IO；这些实现细节不成为每个 effect 的用户必填项。

契约描述需要约定工具能识别的类型结构或不透明类型引用，不预设第三方工具可以分析任意
GADT、类型族或 Haskell 实现。具体 schema 与代码生成方式尚未确定。

## 3. Haskell 值语义收敛到原子 handler

ADT 构造、Require 模式匹配、字段提取、计算、解析与转换等具体值操作，收敛到足够细的
原子 handler 实现；当前倾向保留在对应 instance 中。业务组合层引用这些操作的契约。

一个局部模式匹配可以决定原子操作如何处理输入。如果匹配结果决定下一步调用哪些 effect，
应把选择结果交回组合描述，由可观察的分支关系决定调用，而不是在 handler 内隐藏业务流程。
这一职责划分不要求每个构造器或每次拆字段都新增一个 effect。

effect 各自声明需要什么、产生什么，不依赖特定生产者的实现。业务注册选择可调用入口，
并声明参数来源和输出连接；生产者以注册引用接入，不复制它的整条上游定义。
Input 的操作／能力关系与业务值连接分别表达，SDK 在执行装配时共同解析。

## 4. 产值与 Require 匹配不强制绑定 IO

Require、成功值和错误值首先是数据契约；构造成功值、构造错误值或匹配 Require 本身
不应强制要求 IO 环境、资源上下文或调度状态。

完成结果区分成功产值与失败原因，失败沿组合短路，不在每层再次包装成功。
失败协议由 SDK 统一生成：本地错误为 EffectNameError String，Error e 保留唯一归属，统一 raise 自动附加来源。
Failure 保存 origin、生成的 detail 分类和 message；传播不覆盖来源，不需要用户定义错误 ADT 或配置失败函数名。
当前 SDK 用纯状态或 Reader 传递的共享存储保存 Context，并以 Except 承接失败；Produce e 是 SDK 内部的成功类型，
Context 类方法返回 m (Produce e)，instance 通过上游类方法取得产物，
运行边界统一返回 Output，只包含成功与失败，不设 Pending。

需要文件、网络等外部能力的操作，通过明确的能力接口取得实现。业务数据的解释与外部
操作的执行在代码组织和类型接口上保持可分离；IO 的调度、资源获取释放与取消由执行层
根据显式声明处理。实际 IO 原语可以存在于原子实现或后端适配器中。

组合描述选择能力／实现引用，句柄能力通过类型类 superclass 字典传递。
SDK 已接通同份 scope 的开启状态和 Context 绑定，自动收尾仍待落实；不预设可在运行时任意替换同一类型的全局 instance。

只把 IO 写成一个类型参数不足以完成解耦。如果 Require 匹配与业务组合仍藏在同一个
执行函数中，工具依旧看不到所需结构。接口边界和可描述的关系优先于抽象技术的选择。

## 5. 值的来源与类型表达

在 effect 世界内，跨操作传递的业务值应来自 effect 的输出。设计层引用输出来源及其
成功／错误出口，而不是任意外部 env -> value 函数。初始配置、外部输入和常量如何进入，
需要明确的入口声明；现阶段不因此增加一个已定案的 Source 分类。

普通 Pure／Excu 只表达成功或失败，成功类型固定为 ()，不跨 handler 返回业务产物。
业务产值统一归 Context，即使具体计算是纯函数也不因此注册为 Pure；不另设 Map typing。成功值与错误负载都可以
参与显式连接；转换错误负载不会自动把原操作的失败状态改为成功。

Context 在 typing.request 的 Producer 中声明 handler 名与 produces 业务类型。爬虫的 URL、抓取和解析通过 request 接入，CrawlSession 经 Input 提供操作能力；SDK 不预先生产全局 Context。
生产方的 typing = Context { request, require } 声明方法角色；request = Just Producer { handler, produces }，require 从同一生产契约取得读取类型。
消费方的 context :: Maybe ContextInput 保存两种依值声明：request 重新求值，require 读取已有绑定；
每项以 From 来源 (typeRef @输入ADT) 同时指定来源与接收契约，移除外层 requires／request。
消费配置形成关联 Require 和来源成功类型约束，不能因该 effect 自身也是 Context 就省略其消费契约。
方法保持无位置参数。instance 使用原生 Haskell：在 do 中通过 `value <- contextMethod` 取得业务值，普通操作直接引用 superclass 方法。可确定匹配的单构造器模式可直接写在 `<-` 左侧；多构造器值先绑定再用普通 case 显式处理，失败通过 raise，不新增 MonadFail。SDK 在注册生成的 Context 入口连接 request 生产与 require 读取；生成器只解析模块／方法边界并包装入口，不改写表达式。不新增 Definition、consume 或独立 booter；嵌套取值共享本次 Context 和 scope。未进入的分支不取值，生成源码和创建 Target 不执行业务 IO；不使用 unsafePerformIO／unsafeInterleaveIO。

底层以 Context 的一次成功绑定为单位保存值快照与资源归属。固定绑定且没有 request／重新绑定时，require 重复读取同一份值；Input 组合保留这种关联。
request 每次重新生产，成功后发布新绑定、替换当前调用中该来源的绑定并返回同一个值；require 不执行生产，未绑定报 ContextNotInitialized。
其他调用已经捕获的旧绑定不会被原地改写；不再通过刷新 scope 的共享值表来改变它们。
刷新失败不覆盖该来源的旧值，原始错误继续传播，其他已经完成的操作不回滚。
普通绑定限定在一次末端启动内；scope 开启期间生产的 Context 随该运行句柄保存，可由引用同份 scope 的多条链通过 require 读取。不预初始化业务 Context，不在独立创建的运行句柄之间隐式共享。
根调用进入生产，链内生产方法引用按当前消费者的 context 声明选择 request／require；默认及覆盖的显式读取入口同样校验来源声明，未声明的取值报错。
同一消费者对同一来源同时声明两种模式时，生产方法引用选择 request，显式读取方法始终 require。
调用身份和 scope 可见性由 SDK 的局部 Reader 传递，保存值由执行载体持有；同次 AST 的 scope 绑定已共享，更细的范围与跨入口存续另行设计。

在受支持的 ADT 范围内，连接两端确定后由 SDK 内置 Generic Map 完成结构适配。
目前只有一种固定规则，不新增 adapter 类目或 adapt 配置，也不要求用户为每对类型
手写转换证据或机械转换注册。有业务含义且对外产值的纯转换使用显式注册的 Context effect。

业务 ADT 在 Types.hs 用原生 data/newtype 单独定义，注册用 typeRef @BusinessType 引用，
不再用 ADT/Constructor 重述字段。Require、Produce 是 Effect 中的关联 type，以原子 effect 为索引。
移除顶层 produces 和错误契约配置；只有 Context.request 在 Producer 中声明产物类型。
Require 引用原生输入类型，Produce 表示 Context 的业务产物，其余类别默认 ()，不包含 Output。
普通 Pure／Excu 方法返回 m ()，Context 返回业务成功值；handler 不手写 Succ 包装。
SDK 按 effect 名生成本地错误类型、关联 Error e、分类和 raise，实现来源推导；用户只填写错误消息。
生成阶段产生类型关联、方法接口与装配；业务数据定义及方法体仍由用户提供。
各类别统一注册，所有方法名绑定放入 typing 对应的普通 ADT 构造器，包括 Pure 和 Excu，
不再另设顶层 handlers 重复声明。同一 effect 可以有多个不同签名的类方法。
普通调用需能唯一确定入口，不要求 class 只有一个方法。多方法的输出契约与注册字段仍待设计。
普通方法名绑定采用 Maybe String，包括 Scoped.open／close；只有 Context.request 使用 Maybe Producer，Just 同时提供方法名和产物类型。
Nothing 表示未绑定该方法，不改变业务返回值的类型；require 缺少生产契约时无法推导读取类型，生成器明确报错。
当前 Pure／Excu 已落实：Nothing 不生成本地方法，被 target 引用时报告没有可调用入口；
不猜测名字或提供默认业务实现。request 必须引用具有产值入口的 Context，不用普通 effect 的 () 传值。
Scoped 也已按同一 class 生成 open／close，由同一 instance 实现；
open／close 均为 m ()，通过 instance 内的 superclass 方法引用完成开启／关闭；信息仍由上游 Context 生产与读取。
Context 的 request 由用户实现，require 默认由 SDK 读取绑定，不提供默认业务生产。
Error 的 detect／resolve 均以 Maybe String 声明并返回 m ()，input 直接指向被检查的 Scoped；没有 detect 时不自动调用 resolve。
继续显式生成普通 Haskell 源码并保留 review 区，避免引入 Template Haskell。
类型引用保存可序列化名称，不包含完整业务数据声明；第三方工具仍需提供或引用相应类型定义。Output 识别只用于拒绝嵌套完成协议。
SDK 不在链内构造 Output，完成边界只封装一次；生成器拒绝将另一层 Output 直接作为成功类型。
当前 benchmark 的 DemoContext 通过 request 接入，MakeNumber 用 `<-` 取得并匹配 loadDemoInputs 的产物，
AddOne 调用 makeNumber，RenderNumber 调用 addOne。SDK 只登记并 lower renderNumber。
RenderNumber 还声明 require DemoContext；其 loadDemoInputs 引用复用 MakeNumber 先前保存的值，不再次执行生产。

## 6. 统一外部入口驱动

原子 effect 与 effect 链是不同层级：链内由注册、superclass 与 SDK 生成的调用装配组合 handler，impl 只调用
末端；AST 组织链的启动与执行控制，不维护节点业务状态机，结果依赖和业务状态操作由 effect system 解决。完成、失败停止与并发汇合仍属于执行控制，不能一并排除。chained、parallel、loop 为同级 branch。当前爬虫的每个
node 只选择完整链的末端，分别挂载解析链和打印链；context 来源放在 effect 注册中。chained 顺序执行并在
失败时停止，parallel 并发执行并等待全部子分支后汇总，成功值按声明顺序排列。
SDK 已用 WorkflowF + Fix + cata 将这两个有限分支装配为未执行的动作；fold 不执行 handler，节点产物不自动传给后继节点。URL、抓取与解析由 Context 产值并保存；先并行解析，再顺序打印。打印仍通过 request 重新抓取、解析，返回 ()；改为消费第一阶段缓存的调用关系另行设计。

入口结构固定为 main = interpreter ast effects，爬虫 demo 已接入这一入口。
Generated 模块将选定末端类方法登记为不透明 Target，保留未执行的句柄；它不是已经 lower 的 impl。
Node algebra 取得 Target 后才提供内部载体环境并 lower；上游调用完全沿 instance 内引用发生。
内部空存储不等于已生产的业务 Context。构造器和裸运行器不导出，公开Generated 模块不能额外补出链路。
纯计算 mock 没有 AST，但同样只解释选定末端，不生成另一份上游执行流水线。

统一驱动需要设计中明确以下关系：

- 某个操作引用使用哪个 handler 契约，以及实现与所需能力如何接入。
- Require 来自哪一个已声明输出，消费成功值还是错误负载，是否经过 mapping。
- 哪些控制、资源与就绪条件约束本次调用，以及结果应沿哪条声明关系继续。

handler 可用不等于所有可用 handler 都应执行；签名相容也不唯一决定具体调用。
这些选择在设计描述中表达。instance 内引用上游类方法，取得值后完成本层操作；
Node 只 lower 末端，实际可达的引用带起整条链；不要求在 impl 或 AST 重新列出链内全部方法。

值的路由与执行组织由声明和解释器承接，具体匹配、转换和外部操作由 handler instance
提供。它们仍遵循前文的 IO 解耦要求，不因为共享入口就合并成一个大的 IO 函数。

静态、有限、无环的注册依赖可以在装配阶段生成执行闭包；关系成图不要求先建立
通用图调度 runtime。闭包保留必要的输出绑定、scope 状态及描述关联，供共享、诊断
和 middleware 使用。装配过程不提前执行 handler。

loop 是事件触发的执行方式 transformer，不作为 chained 中等待完成的普通执行项；涉及 loop 及其他新增 branch 的嵌套规则另定。
无条件指不按本轮业务结果判断是否继续：订阅有效时事件到达即触发调用，无事件等待，范围结束停止。
无状态指 loop 与 node 不保存跨调用业务产物、不自动改写 Reader；取值与绑定由 effect system 负责，
订阅与运行中调用的管理状态归 SDK。每次触发启动一次调用，不隐含恢复旧调用。
AST 的 recursion scheme／algebra 可将其 lower 为订阅与回调闭包，不要求另建协程调度器或通用图 runtime。
无环约束仍针对单次依赖；内部反馈与外部触发不自动改写依赖图。loop 尚未实现，
事件源引用、监听范围、失败与重叠事件处置及收尾协议待设计，详见 LATEST_DESIGN.md。
Hanging 保留为主控制树之外的事件入口描述，可承接 loop 的订阅及 scope 归属；启动新调用与恢复旧调用分开声明。回调和有效期记录由 SDK 持有，不作为节点业务状态；当前尚未接入。

沿 Input 取得前提不等于重放全部前置操作。同一份 scope 已成功开启且未被判定失效
或关闭时，默认能力可用，后续 request 直接复用；不因每次数据库操作重新启动数据库，
也不要求主动健康轮询。失效或关闭后不能继续使用或自动重启。普通业务结果的共享
仍由输出绑定与 require 表达，不因 scope 复用而自动缓存。

Scope 描述存续、共享范围与结束边界；open／close 均为 m ()，不配置产物。
open 可直接引用上游 Context 的生产方法，close 可读取其保存值，Input 继承本身不传值。
SDK 包装这两个方法，保存未开启、开启中、有效、关闭中、失效和已关闭状态；同份有效 scope 不重复开启，
并发调用等待首次开启，失败或中断后保存故障并禁止自动重开。成功关闭不重复执行，之后显式 open 可以重新开启。
生成的 Handlers 为每个 Scoped 注册创建 ScopeHandler；App／IO 按资源 Context 声明消费的上游参数值保存多份实例，各有 MVar、状态及开启期 Context。
参数由 instance 内的原有方法引用取得，按原生 ADT 的 Eq 比较；不新增 key 或外部预执行。资源 IO 在参数齐备后执行，同参复用时跳过资源获取及剩余 open 方法体。
Context 绑定把值与所属 scope 实例一同保存，SDK 不设置“最近选中”的 scope 指针。close 在 instance 实际 require 到这份绑定时才取得目标和锁；重复关闭读取同一归属并跳过操作，不需先 open 来选择。
require 优先复用本次调用已捕获的绑定，跨链首次读取只接受唯一可解析的来源绑定；多份来源且没有绑定关联时报 AmbiguousContextBinding，不按时间猜测。显式 request 可以替换当前调用的绑定，旧绑定仍指向旧实例。
这项保证属于 ContextStore 与执行载体，不增加 adaptor、key、Method 注册或用户位置参数；具体观察边界见 LATEST_DESIGN.md。
Generated/Program 自动让各末端捕获同一批 scope 引用；Node algebra 只 lower 末端，runAST 不创建或重置 scope。
同批运行句柄跨 Input 链共享状态；重复解释同批句柄仍复用，重新创建一批则独立。Main 仍为 IO ()，
不增加 Program 载体、用户装配或全局单例。普通业务 Context 按 Node 隔离，自动跨独立入口存续另行设计。
Error 已接入 Root 故障入口；检测定位不自动改变 scope 状态，生命周期操作由 resolve 显式引用 open／close 完成。范围退出时自动 close 尚未落实。

effect 注册不设 dependency；SDK 沿原 Input 和 request 生产链收集 Scoped，能力由 superclass 继承提供，不另加一份 scope 连接。作为上游前提的 Scoped 须同时声明 open／close，生成器继续检查 Input 环。SDK 在选定实例的开启、绑定读取及关闭时检查状态，实际调用仍来自 instance 的显式引用。workflow 层若需要 dependency，另行定义其控制流语义。Linear 关闭凭证接口另行 review，当前不增加用户位置参数。

Error 注册在同一 effect 的 class 内声明可选 detect／resolve，均为无位置参数的 m ()，input 直接引用被检查的 Scoped。
Root 捕获传播到生成入口的 Failure，按 Input 与 request 生产链的 scope 顺序从 Root 向下检查；同层独立路径按生成顺序排列。
detect 返回 () 表示已定位，SDK 记录 Succ () 并调用可选 resolve；raise 表示未定位，记录 Failed 后继续检查。
一次处置完成或失败后仍检查其余相关 scope。Nothing 不生成对应方法，无 detect 不自动 resolve。
原失败通过 caughtFailure 读取，检测和处置结果追加到原 Failure.errorHandling，原始来源、分类和消息保留。
诊断使用隔离的 Context 快照；普通故障按捕获资源的归属定位，open／close 故障使用本次实际选定实例或未选定的证据，不能回落到其他实例的旧成功产物。
不重新 boot、不猜测其他实例、不为诊断预执行 Context；同实例诊断串行化。
生命周期持锁期间只收集路径，退出后再诊断；诊断自身失败不递归激活，同次失败的多层 Root 包装不重复处理。
失败 scope 的绑定仅在匹配实例的诊断上下文中可读取；resolve 仍通过既有 scope 方法改变状态。
SDK 不因定位成功自动 invalidate、reopen、重放或把原失败变成功；也不捕获任意底层 IO 异常或恢复已展开的 continuation。

Context 绑定稳定是框架内部必须实现的语义规则，不能仅由“句柄是纯的”推导。操作描述与组合可保持纯构造，但实际 IO、资源开关仍有状态；重复返回 () 不证明重复执行没有外部影响。当前 App 原语已约束绑定读取、发布与生命周期归属；Error 使用显式检测条件，不证明外部执行确定。任意 instance 的纯性、必须调用上游方法仍无完整静态保证，不把编译通过当作公理已被证明。

## 7. 当前样例的地位与下一步

入口为 demo/RequestBenchmark/Main.hs、demo/Crawler/Main.hs 与 demo/FileDemo/Main.hs；sdk/Framework/SDK.hs 为统一 SDK 入口，内部按 Effect、Recursion、Workflow 与 Codegen 拆分。
每个 demo 保留 Main、AST／Target、Effects、Types、Handlers；生成接口、末端登记和包装后的 instance 分为 Generated/Effects、Generated/Program 和 Generated/Handlers。
分离边界是手写配置 facade 与生成代码；生成逻辑属于 SDK，demo 不另设 Codegen.hs。AST 不填写 Reader。
Types、Effects、AST／Target 独立于 Generated 与 Handlers；effect 标记和错误类型都由 SDK 生成，无须手写空 data。
首次生成使用 cabal run effect-codegen -- workflow Crawler 或 -- target RequestBenchmark，只编译声明；已有 Handlers.hs 由 GHC 解析模块／方法边界，不加载或执行业务。
手写 instance 使用原生 Haskell，编译只使用 Generated/Handlers 的协议包装副本；修改实现后须重新生成。不新增业务 class，不使用 Template Haskell，codegen 不回写手写源码，也不改写方法体表达式。
生成副本保存实际解析的手写源码指纹，公共运行入口在业务执行前比对当前 Handlers.hs；缺失或变更时拒绝启动并提示重新生成。workflow 与纯 target 都比对注册快照，纯 target 另比对所选末端。此检查要求从仓库根目录访问手写源，不替代显式生成或编译。
已有 Main --generate 仍要求导入链能编译，不能替代独立首次生成入口。
数字 benchmark 与爬虫都演示 instance 内沿 Input 引用类方法；爬虫再由 Node algebra lower 末端，组织并行解析与顺序打印。
文件 demo 同样只选择末端；路径、活文件句柄与文本归 Context，校验归 Pure、写入归 Excu，Scoped 的 open／close 均为 m ()。FileRecovery 以 Error 注册，检测已捕获的文件是否意外关闭，定位后引用 closeFileSession；正常读写及显式关闭保持不变。demo 内的 catchError 清理仍不等同于 SDK 自动收尾。
OpenFilesDemo 按用户要求验证同份 scope 持有十个文件：Node 返回及主动 GC 后检查仍打开并可写，再显式 close 检查关闭。它验证跨 Node 存续，不增加 scope 多实例或自动收尾协议。
ScopeInstancesDemo 在一个 interpreter 中验证按两个文件名分实例、同参复用、跨链读取与关闭、关闭后重开。
ScopeReuseDemo 按用户要求让三个 parallel 写入 Node 直接引用同份 scope，汇合后检查实际打开一次、使用同一 Handle 且各写入一次，最后显式关闭；观察记录不承担业务互斥，不修改 SDK 协议。
按 AST 末端登记句柄及结果总和 ADT，完成边界只包装一次 Output；结果汇总不隐含跨节点缓存。
同次 AST 内的 scope 状态保护、绑定复用与 Root 的 Error 检测／处置已接通；自动收尾、使用与关闭协调、内置结构适配及 loop／Hanging 尚待落实。
当前探索阶段只要求普通编译通过，不自行增加测试、类型负例或额外验证门槛。
