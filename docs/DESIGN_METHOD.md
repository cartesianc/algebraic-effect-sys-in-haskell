# 基本设计方法：可序列化组合与原子值操作

更新：2026-10-27。本文记录用户明确的设计方向，作为后续接口设计的依据。
当前实现集中在各 demo 目录与共享 SDK；可执行样例是实现证据，不反向固定新设计。

effect typing 仅有 Pure、Excu、Scoped、Error、Context 五类；旧 Request 类型已并入 Context。
request／require 是 Context 内的方法角色；消费者统一在 demands 中声明需要的契约与取值模式，来源可省略并由生成器唯一解析，不另设 Request typing。
独立 Middleware typing 与 AST／Hanging 挂载是后续扩展，当前只接通 Root 调用入口，不增加其注册构造。

最新设计见 [LATEST_DESIGN.md](LATEST_DESIGN.md)：固定 interpreter ast effects 入口，业务注册声明 request／require，SDK 装配执行闭包并复用已开启的可用 scope；Generic Map 作为内部结构适配，不新增 adapter 配置。对外产值的业务转换归 Context；Scoped 在同一个 effect 的 class／instance 内提供无产物的开启与关闭，信息由上游 Context 提供；Error 在同一个 effect 的 class／instance 内提供 detect 与 resolve。独立 Read 已取消。本文记录基本方法，具体语义与落实范围以上述文档为准。

当前工作聚焦 Algebraic Effect Sys in Haskell；设计声明、样例与方法文档在项目根目录的 sdk、demo 与 docs 中推进。
旧实现、设计材料与旧版 RequestBenchmark 已删除，只在 Git 历史中保留。

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

### 生成前仍是原生 Haskell：核心约束

手写的 Types、Effects、AST／Target 和 Handlers 都是原生 Haskell 模块，使用显式声明的语言扩展。在生成业务执行副本之前，源码就必须能够由 GHC 解析、名称解析和类型检查，并进入 HLS 的诊断、补全与跳转流程。这是 EDSL 的设计边界，也是未来 agent／langserver 可以使用标准 Haskell 工具理解业务代码的前提。

handler 中的 effect 调用使用原生类方法，业务数据使用原生 ADT、模式匹配和 do 取值；不把调用改成字符串查找、生成器专用伪语法或需要改写后才成立的表达式。注册中的序列化名字属于声明元数据，不替代方法调用的 Haskell 类型关系。生成器可以提取结构、生成 MethodGen 身份并包装协议入口，但不能承担修复手写源码语法或类型的职责。

“生成前”指手写方法进入 Generated/Handlers 执行副本之前，不等于可以缺少导入的类型接口。Handlers 导入的 Generated/Effects 契约必须已存在且与声明同步；首次项目先从独立的 Types、Effects、AST／Target 生成契约，再编写 Handlers。只修改方法体时，可以先由 HLS 检查手写模块，再重新生成执行副本。手写模块和包含相同 instance 的 Generated/Handlers 分别作为检查与运行入口，不在同一业务导入链中同时引入两份 instance。

HLS／GHC 负责宿主语言的语法、名字、类型与方法实现检查；gencode 另外检查当前支持的 effect 组合结构、引用和图约束。合法 Haskell 不自动等于可静态提取的 effect 组合，类型检查通过也不证明完整的业务依赖、资源正确性或所有运行时协议。

## 2. 组合必须是可描述的关系

控制分支、Input 关系、值来源、成功与错误路由、mapping 调用、handler 引用、scope 归属、
生命周期策略和 middleware 挂载，应尽量表达为明确的构造、引用和契约。
新增一种组合语义时，先说明工具能读写的结构与含义，再确定 Haskell 表面写法。

生成器可以读取原生方法体中的显式 effect 方法引用，生成剥离业务值与 IO 的纯结构副本；不依赖解释任意 lambda、函数组合、do 块或 IO 闭包的业务语义来恢复关系。
例如 mapping 的描述保存原子转换的引用及输入输出连接，不把任意 a -> b 函数当作可序列化字段。
实现函数、类字典、线程和活资源由执行装配持有；描述通过约定的标识与接口关联它们。

方法身份由生成的 MethodGen 枚举表示，构造器为方法名首字母大写加 Gen；MethodDefinition.methodEffect 使用同一 effect 首个注册入口的 Gen 身份。原生业务方法不变，执行副本只加既有协议包装；纯结构副本独立记录引用和可能路径。具体定义与观察边界见 [EFFECT_GRAPH.md](EFFECT_GRAPH.md)。
source 结构支持显式 effect 调用、do、if／case 与已识别的标准组合。未知高阶 effect、隐藏 helper／局部 alias 组合、含 effect 的动态循环及递归 effect 引用报错，不静默形成空图；没有 effect 引用的原子业务表达式允许任意语法，在结构副本中擦除。catchError 用 Recover 保存正文正常路径及任意 scope 前缀后进入 recovery 的保守路径，不预先验证业务是否成功。

Input 只表达句柄组合，不隐含业务值传递。手写 input 只允许 Root 或非 Context effect；Context 经 demands 接入，消费方类只以 Provides 契约作为 superclass，不指名生产方的类。生产者自身仍可有 Input、消费其他 Context，也可直接作为 target。原 Input 与生产链的能力同时保留，不重挂来源注册；沿 Input 与 request 收集 scope；require 在 state 无值时可能求值 request，结构分析把这条可能路径计入（scope 资源除外）。
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
GADT、类型族或 Haskell 实现。当前已有显式 Haskell 源码生成；跨语言 schema 与语言服务协议仍待确定。

## 3. Haskell 值语义收敛到原子 handler

Context 的产物及 request／require 接收契约共同导出一个 asset 集合，同一业务 ADT 只记一次，
不携带 Context 来源归属。递归收集契约内嵌的业务 ADT，并补全指向资产的类型别名；
库类型不会因成为字段而进入集合，例如 CrawlURLs 包含 PageURL，但 String、Handle 仍是通用类型。

普通函数不能在源码中显式使用这些资产，涵盖签名、类型应用、构造器引用、模式匹配和
字段访问／更新。禁止的依据是资产引用，不是出现了函数定义：泛型函数定义未显式依赖
资产，调用时即使接收该 ADT 也不拦截；只处理通用类型的 readCurl 等 helper 可以存在。
类型别名、qualified import 和局部遮蔽按真实名称解析判断，不做字符串匹配或值来源传播。

显式资产操作由注册的 instance 方法承载，方法不增加位置参数；业务复用通过注册类方法与
Context 契约完成。顶层值同样不能把资产构造移出方法；方法内的局部具名函数也检查显式
资产引用，包括 point-free 函数。匿名 lambda、局部数据绑定、计算与标准／外部库调用仍属于
方法实现，不要求每个表达式注册。data/newtype/type 声明与 deriving 是合法契约定义。
SDK 内部实现不在业务约束内。此规则取代“所有纯解析、转换和 IO 都不得抽成普通函数”的旧约定。

gencode 使用 GHC 的 renamed source 检查显式引用；类型检查只辅助名称解析和区分局部函数／
数据绑定，不以泛型调用推导出的实参类型认定违规。不解释函数的业务意义，不追踪投影后的
String，也不证明 handler 粒度足够细。effect 调用另受结构提取约束，不能藏入 helper。
GHC／HLS 单独通过不等于资产约束通过；详见 [源码资产检查](ASSETS.md)。

Generated/Assets.hs 显式导出 generatedAssets，包含类型、构造器、字段及定义位置，供源码审查
和未来 LSP 使用。它与检查器在本次生成内使用同一个集合，不是手写权威，不进入执行器、
ScopeTree 或 ContextStore；无需为尚无用途的运行时访问增加状态。

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
根据显式声明处理。显式依赖资产的 IO 操作写在注册 instance 内；不显式依赖资产的通用
IO helper 可以复用，但不能隐藏 effect 调用。SDK 内部执行后端不属于业务书写面。

组合描述选择能力／实现引用，句柄能力通过类型类 superclass 字典传递。业务 instance 对载体 m 泛型（instance XInputs m => XEffect m），生成的 XInputs 只含自身能力标记、Input 链与 demands 给出的能力及载体能力；能力标记只在载体上成立，GHC 因此拒绝越过 Input 链的调用，Input 链即实际的依赖注入边界。
SDK 保留 scope 状态与 Context 绑定，本轮按有限使用闭包落实 once-spare 自动收尾，interpreter 退出清理继续兜底；不预设可在运行时任意替换同一类型的全局 instance。

只把 IO 写成一个类型参数不足以完成解耦。如果 Require 匹配与业务组合仍藏在同一个
执行函数中，工具依旧看不到所需结构。接口边界和可描述的关系优先于抽象技术的选择。

## 5. 值的来源与类型表达

在 effect 世界内，跨操作传递的业务值应来自 effect 的输出。设计层引用输出来源及其
成功／错误出口，而不是任意外部 env -> value 函数。初始配置、外部输入和常量如何进入，
需要明确的入口声明；现阶段不因此增加一个已定案的 Source 分类。

Pure／Excu 只表达成功或失败，不跨 handler 返回业务产物。Pure 的成功类型固定为 ()；Excu 与 Scoped.open／close 是原子句柄，返回 Maybe String 形式的可选信息，SDK 与成败合成内部 RawOutput，只交给挂在该句柄下的 Context 解析，没有挂接时丢弃。

Context 的 input 指向 Excu 或 Scoped 时挂在该句柄下，解析其入口方法（handler／open）的输出。生成器在原子句柄入口注入：句柄被原链调用并成功返回后，以根调用身份运行挂接的 Context.request，其中对该句柄的调用由本次输出回答、不重复执行，产值按 request 发布为资产；原链（A→B→Ctx→C 中的 C）不受影响，注入失败只留在注入内。尚未执行句柄而消费方 require 时，按需求值的 request 由 Context 调用句柄驱动整条链；Context 不会自行启动，只由依值消费方或 origin 链上的注入带起。构图时挂接句柄的结构后接一个可选分支，内容是挂接 Context 的方法体（其中对句柄的直接调用记为空），因此 effect graph 与 ScopeTree 包含注入路径。只有 Input 链在原子句柄下游的 effect 能调用它、取得输出，由生成的 XInputs 约束经 GHC 保证；是否进一步只允许挂接的 Context 绑定输出，留给未来 LSP。
业务产值统一归 Context，即使具体计算是纯函数也不因此注册为 Pure；不另设 Map typing。成功值与错误负载都可以
参与显式连接；转换错误负载不会自动把原操作的失败状态改为成功。

Context 在 typing.request 中以 requester "handler名" @表示类型 声明生产方法，契约类型由 handler 名生成。爬虫的 URL、抓取和解析通过 request 接入，CrawlSession 经 Input 提供操作能力；SDK 不预先生产全局 Context。
生产方的 typing = Context { request } 只声明生产方法；require 读取同一契约，读取方法由生成器命名为 read 加契约名，不在注册中声明。
消费方的 demands :: [Demand] 只声明需要的契约与取值模式：requests 重新求值，requires 读取已有绑定。
统一规则：每个 Context 的契约类型都由生成器按 handler 名产出。request = requester "currentUser" @UserId 生成 newtype CurrentUser = CurrentUser UserId；
消费方写 requests "CurrentUser"，handler 照常写 request @CurrentUser。契约类型在手写声明中不可见，因此消费方以名字引用，名字即生产方 handler 名首字母大写。
不同业务含义即使表示相同（例如当前用户与目标用户的 UserId），也由不同的 handler 产出不同的契约类型，不需要手写 newtype、额外标记或来源选择。
方法名在注册集合中唯一，每个契约恰好对应一个生产方；handler 名同时决定资产名，应按业务含义起名，不与 effect 名、生成区固定名或 Types.hs 中的类型重名。
Types.hs 只保留表示类型；只包一层的 newtype 由生成的契约取代，含 Handle 等需导入的库类型时定义为记录。生成的契约不派生 Read，值只能由其生产方构造。
误用在 GHC 类型检查时即被拒绝，不依赖 handler 内的值语义。曾设计过的独立角色层（Roles.hs、roleRef）、`from`、Gen 标记与 refine 均已取消，由按 handler 名生成契约的统一规则取代。
细化类型同时决定 scope 边界：细化后的资源、开启输入与 Scoped 是不同注册，ScopeTree 以注册为节点即可区分。一个 Scoped 注册服务多种细化类型尚无声明形式；引入时节点身份须改为（Scoped 注册，细化资源类型），运行时 scope 状态的各项记账随之改用该组合键。
消费配置形成关联 Require（按 demands 顺序的元组）和 Provides 契约约束，不能因该 effect 自身也是 Context 就省略其消费契约。
方法保持无位置参数。instance 使用原生 Haskell：在 do 中通过 `value <- request @T` 或 `value <- require @T` 取得业务值，调用点即说明是否重新生产；普通操作直接引用 superclass 方法。可确定匹配的单构造器模式可直接写在 `<-` 左侧；多构造器值先绑定再用普通 case 显式处理，失败通过 raise，不新增 MonadFail。SDK 在注册生成的 Context 入口连接 request 生产与 require 读取；生成器解析显式 effect 方法引用以生成纯结构副本；业务执行副本仍只包装入口，不改写原方法体表达式。不新增 Definition、consume 或独立 booter；嵌套取值共享本次 Context 和 scope。未进入的分支不取值，生成源码和创建 Target 不执行业务 IO；不使用 unsafePerformIO／unsafeInterleaveIO。

底层以 Context 的一次成功绑定为单位保存值快照与资源归属。固定绑定且没有 request／重新绑定时，require 重复读取同一份值；Input 组合保留这种关联。
request 每次重新生产，成功后发布新绑定、替换当前调用中该来源的绑定并返回同一个值；require 也是表达式：它读取 state，值只来自 request；state 中已有值时直接返回，不重新生产；尚无值时求值一次同一个 request 并写入 state，相当于 thunk。按需求值以来源加锁，并发 require 只求值一次；诊断、收尾期间以及 scope 资源 Context（只能经 open 取得）不按需求值，仍报 ContextNotInitialized。按需求值触发的生产对 scope 开启参数仍按 require 观察（同参共享）。
其他调用已经捕获的旧绑定不会被原地改写；不再通过刷新 scope 的共享值表来改变它们。
刷新失败不覆盖该来源的旧值，原始错误继续传播，其他已经完成的操作不回滚。
不属于 scope 实例的资产绑定在一次 interpreter 运行内跨 Node 保存于运行级 state；scope 开启期间生产的 Context 随实际实例保存，只在该实例仍被使用或依赖保留期间供其他链 require。后续 Node 不预约前一链的活资源；旧绑定不因新一轮 open 自动换 owner。不预初始化业务 Context，不在独立创建的运行句柄之间隐式共享。
根调用进入生产；链内 request @T／require @T 由生成的 Provides instance 按当前消费者分派到解析出的来源方法，默认及覆盖的显式读取入口同样校验来源声明，未声明的取值报错。
gencode 在结构分析时把 request @T／require @T 解析为来源方法，拒绝未在 demands 中声明的契约，也拒绝直接调用其他 effect 的 Context 方法，接线因此只存在于声明层。
调用身份和 scope 可见性由 SDK 的局部 Reader 传递，保存值由执行载体持有；同次 AST 的 scope 绑定已共享，更细的范围与跨入口存续另行设计。

在受支持的 ADT 范围内，连接两端确定后由 SDK 内置 Generic Map 完成结构适配。
目前只有一种固定规则，不新增 adapter 类目或 adapt 配置，也不要求用户为每对类型
手写转换证据或机械转换注册。有业务含义且对外产值的纯转换使用显式注册的 Context effect。

业务表示类型在 Types.hs 用原生 data/newtype 单独定义，注册以 requester 的类型参数引用，
不再用 ADT/Constructor 重述字段。Require、Produce 是 Effect 中的关联 type，以原子 effect 为索引。
移除顶层 produces 和错误契约配置；只有 Context.request 以 requester 声明表示类型。
Require 引用原生输入类型，Produce 表示 Context 的业务产物，其余类别默认 ()，不包含 Output。
Pure 方法返回 m ()，Excu 与 Scoped.open／close 返回 m (Maybe String)，Context 返回业务成功值；handler 不手写 Succ 包装。
SDK 按 effect 名生成本地错误类型、关联 Error e、分类和 raise，实现来源推导；用户只填写错误消息。
生成阶段产生类型关联、方法接口与装配；业务数据定义及方法体仍由用户提供。
各类别统一注册，所有方法名绑定放入 typing 对应的普通 ADT 构造器，包括 Pure 和 Excu，
不再另设顶层 handlers 重复声明。同一 effect 可以有多个不同签名的类方法。
普通调用需能唯一确定入口，不要求 class 只有一个方法。多方法的输出契约与注册字段仍待设计。
普通方法名绑定采用 Maybe String，包括 Scoped.open／close；只有 Context.request 使用 requester "方法名" @表示类型，同时提供方法名与契约。
Nothing 表示未绑定该方法，不改变业务返回值的类型；require 缺少生产契约时无法推导读取类型，生成器明确报错。
当前 Pure／Excu 已落实：Nothing 不生成本地方法，被 target 引用时报告没有可调用入口；
不猜测名字或提供默认业务实现。request 必须引用具有产值入口的 Context，不用普通 effect 的 () 传值。
Scoped 也已按同一 class 生成 open／close，由同一 instance 实现；
open／close 均为 m (Maybe String)，通过 instance 内的 superclass 方法引用完成开启／关闭；资源信息仍由上游 Context 生产与读取。
Context 的 request 由用户实现，require 默认由 SDK 读取绑定，不提供默认业务生产。
Error 的 detect／resolve 均以 Maybe String 声明并返回 m ()，handles 声明处理的故障类型；没有 detect 时类型匹配即调用 resolve。
继续显式生成普通 Haskell 源码并保留 review 区，避免引入 Template Haskell。
类型引用保存可序列化名称，不包含完整业务数据声明；第三方工具仍需提供或引用相应类型定义。Output 识别只用于拒绝嵌套完成协议。
SDK 不在链内构造 Output，完成边界只封装一次；生成器拒绝将另一层 Output 直接作为成功类型。
爬虫的 FetchPage 以 request 取得起始 URL，ExtractPage 挂在 FetchPage 下解析其输出，PrintPage 以 require 读取解析出的摘要；摘要已在抓取阶段由注入产出时不再次执行生产。

## 6. 统一外部入口驱动

原子 effect 与 effect 链是不同层级：链内由注册、superclass 与 SDK 生成的调用装配组合 handler，impl 只调用
末端；AST 组织链的启动与执行控制，不维护节点业务状态机，结果依赖和业务状态操作由 effect system 解决。完成、失败停止与并发汇合仍属于执行控制，不能一并排除。chained、parallel、loop 为同级 branch。当前爬虫的每个
node 只选择完整链的末端，分别挂载解析链和打印链；context 来源放在 effect 注册中。chained 顺序执行并在
失败时停止，parallel 并发执行并等待全部子分支后汇总，成功值按声明顺序排列。
SDK 已用 WorkflowF + Fix + cata 将这两个有限分支装配为未执行的动作；fold 不执行 handler，节点产物不自动传给后继节点。URL 由 Context 产值；抓取是 Excu，交出网页正文，解析 Context 挂在抓取句柄下。先并行抓取（同时注入解析，摘要发布为运行级资产），再顺序打印；打印 require 摘要，不再抓取。

workflow 以具名 branch 为模块：每个 branch 在 Workflow 下独立文件定义，顶层 AST 通过普通 import 组合业务名称，不在表达式中使用模块限定前缀。node 返回抽象 EffectNode，branch 返回抽象 AST；同一 chained／parallel 列表只接受一种子项类型，禁止裸 node 与 branch 混排，裸 node 不能作为 AST。单个 node 也先组成 branch；空列表须标注元素类型，原有空分支成功语义不变。SDK 内部保留 WorkflowF、Fix 与 cata，隐藏 AST 构造与内部子项转换。

模块拆分不改变调用次数、控制顺序或 Context／scope 边界；重复引用同一模块仍是重复执行。声明采用固定构造、显式列表和直接符号引用，引用关系有限无环。分文件与具名引用是源码格式约定，不由 AST 类型证明；未来 LSP 原型需保存定义、引用及源码位置，不能从展开后的执行树反推模块身份，也不因此增加运行时 pipeline key。SDK 仍保留无 workflow 的纯 target 入口，目前没有 demo 使用。

gencode 先进行纯结构分析：枚举选定末端的独立 effect chain，方法结构用 zygo 同次归约辅助 scope 路径与图，汇合路径、补全注册前提并校验后，发射显式 generatedEffectGraph 与 generatedScopeTree ADT。运行时校验并完整求值生成常量，随后直接对当前 AST 做一次 cata，同时解析 Node、收集入口并装配尚未执行的 action。所有分支及入口集合检查完成后才安装 scope 关系并执行业务；不创建 InitializedF 中间树，不重跑 handler 构图或推导 scope 父边。Target 创建只分配空状态，不获取业务资源。跨 Node 的 Chained 执行先后不产生 scope 依赖。
ScopeTree 保存共享节点的 DAG，而非强制单父树。生成期的 buildScopeTree 对每个 B 求所有含 B 路径的前序集合交集 Pred(B)，再作传递约简；共同前序只用于构树，不作为另一份公开结果。ProgramStructure.structureScopes 直接保存生成的 ScopeTree，其 parents、children 和 layers 用于导航，路径、raw 候选、scopeOpposed 与 scopeUndetermined 证据也保存在其中；graphRootPaths 继续保存各入口路径来源。仅由 open 顺序不能证明覆盖全部资源前提，尤其不能遗漏 require 复用的已有资源；生成期补全清理依赖后约束 once-spare，子 scope 仍保留前提时不得关闭它。不新增 Error tracing。
Generated.Program 的 programStructure 是不接收 AST 的静态 Either 值，调用 initializeGeneratedStructure entries scopeNames generatedEffectGraph generatedScopeTree；ProgramStructure 保存入口映射、图与 scope tree，不持有 workflow 副本。现有 Main 的 --structure 分支对当前 AST 做纯展示 fold 并核对入口，打印同一份生成结构，不调用 createEntries 或业务方法。业务启动仍使用同一手写入口，不增加 layer 或用户装配。

生成命令每次仍加载声明并读取 Handlers 快照，分析和业务包装共用该快照；资产检查另用 GHC 名称解析同一快照，每次执行。结构缓存 Generated/.scope-cache 精确比较完整 GraphPlan、规范化 handler shapes 及 Graph.hs、Recursion.hs、Workflow/AST.hs、Workflow/Structure.hs、Codegen/Plan.hs 的源码内容；key 相同才复用已发射的纯 graph／tree ADT，不依赖 mtime 或执行 Generated 模块。业务原子 IO 改动而 shapes 不变时可复用结构。各生成文件内容相同则不写回，但不宣称跳过整条命令、逐方法热点生成或热重载。运行校验只验证无环、字段一致等结构自洽性，不证明人工删边在业务上正确。Generated 是派生产物，手改树在下一次 gencode 按源声明恢复；缓存不以手改文件为权威，不新增 edge override 层。

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

沿 Input 取得前提不等于重放全部前置操作。开启输入以 require 取得时，同参活实例可共享；
任何用于 scope 匹配的开启输入实际以 request 取得时，本次 open 默认 fresh，即使 Eq 相等也新建实例。
资源 producer 自身为了生产资源而使用 request，不因此一律 fresh；无开启输入的 scope 仍可共享。
不要求主动健康轮询，require 不自动重开失效或关闭实例。普通业务结果的共享仍由输出绑定与 require 表达。

Scope 描述存续、共享范围与结束边界；open／close 均为 m (Maybe String)，不配置产物。
open 可直接引用上游 Context 的生产方法，close 可读取其保存值，Input 继承本身不传值。
SDK 包装这两个方法，保存未开启、开启中、有效、关闭中、失效和已关闭状态；选择共享的同份有效实例不重复开启，
共享调用等待首次开启，失败或中断后保存故障并禁止自动重开。成功关闭不重复执行，之后显式 open 可以开启新一轮。
生成的 Handlers 为每个 Scoped 注册创建 ScopeHandler；App／IO 保存多份实例，各有 MVar、状态及开启期 Context，实际开启输入模式决定新建还是共享。
参数由 instance 内的原有方法引用取得，require 输入按原生 ADT 的 Eq 比较；不新增 key 或外部预执行。资源 IO 在参数齐备后执行，共享时跳过资源获取及剩余 open 方法体；request 输入的新实例与同值旧实例可并存。
Context 绑定把值与所属 scope 实例一同保存，SDK 不设置“最近选中”的 scope 指针。close 在 instance 实际 require 到这份绑定时才取得目标和锁；重复关闭读取同一归属并跳过操作，不需先 open 来选择。
一个资源绑定只有唯一关闭归属，普通 require 只读、不转移归属。open 可以首次认领无归属绑定；已有同一实例归属时保持原绑定，另一个 scope 或同注册的不同实例认领它则报 ScopeContextMismatch。拒绝发生在等待原 owner 生命周期锁之前，不覆盖原绑定，也不为冲突实例登记该资源的 cleanup。
此检查约束已有归属，不为不同调用对同一无归属值的首次认领提供全局仲裁；也不证明不同绑定的业务值没有共享外部资源。
该规则约束绑定身份，不分析任意业务 ADT 是否私下含有同一个 Handle；不增加 layer、位置参数或借用／转移协议。
require 优先复用本次调用已捕获的绑定，跨链首次读取只接受唯一可解析的来源绑定；多份来源且没有绑定关联时报 AmbiguousContextBinding，不按时间猜测。显式 request 可以替换当前调用的绑定，旧绑定仍指向旧实例。
这项保证属于 ContextStore 与执行载体，不增加 adaptor、key、Method 注册或用户位置参数；具体观察边界见 LATEST_DESIGN.md。
Generated/Program 自动让各末端捕获同一批 scope 引用；Node algebra 只 lower 末端，runAST 不创建或重置 scope。
同批运行句柄跨 Input 链和 Node 共享运行表，但不预约未来 Node 的资源存续，重新创建一批则独立。Main 仍为 IO ()，
不增加 Program 载体、用户装配、手写 layer 或全局单例。普通业务 Context 按 Node 隔离，自动跨独立入口存续另行设计。
本轮自动收尾以有限使用闭包为边界：每个 Node lower 的末端完整 chain 是一个闭包，实际 open／require 选中实例时加入使用，包括等待 opening 的调用；同一闭包对同一实例只加入一次。
完整 chain 返回并完成诊断及 SDK 受控的结果消费后撤销使用。最后使用者离开且子 scope 不再保留时，once-spare 调用已有 close 实际清理；不等待未来 Node。后续 Node 要继续使用时显式 open 新一轮，旧绑定仍指向旧 owner。不同参数或 fresh 同参实例可同时被当前闭包持有，request 切换绑定本身不关闭仍被持有的旧实例。

当前 core 固定采用 once-spare，尚无可切换的 cleanup policy、next-use 或延迟保留策略。这是 SDK 生命周期协调层的选择，handler 仍只定义原生 open／close；后续策略变化应保留这层业务接口。interpreter 退出清理是兜底，不是另一种可选保留策略。
生成器登记 close 回调，清理服从补全后的 scope 依赖；interpreter 完成、失败或取消后的全局退出清理保留兜底。Main、Effects 和 Handlers 的 open／close 写法不变，无需手写清理层。
显式 close 已成功的实例跳过；某次清理失败仍继续其余实例，保留原错误和清理故障。资源 producer 返回到 SDK 发布绑定采用 masked 交接，open 失败或中断时，已发布资源仍会清理；任意业务 IO 内尚未发布的部分获取由其自身负责。
本轮使用协议协调受控完整链与关闭：显式 close 只可排除当前闭包自己的使用，仍有其他使用者或未释放子 scope 时以 ScopeInUse 拒绝，不等待当前调用退出；关闭预约期间不接纳新使用。裸 forkIO 自动追踪、任意逸出资源使用和跨独立 interpreter 存续尚未实现。
Error 已接入 Root 故障入口；检测定位不自动改变 scope 状态，生命周期操作由 resolve 显式引用 open／close 完成。运行结束的自动收尾独立于是否配置或触发 Error 检测。

effect 注册不设 dependency；SDK 沿原 Input 和 request 生产链收集 Scoped，能力由 superclass 继承提供，不另加一份 scope 连接。作为上游前提的 Scoped 须同时声明 open／close，生成器继续检查 Input 环。SDK 在选定实例的开启、绑定读取及关闭时检查状态，实际调用仍来自 instance 的显式引用。workflow 层若需要 dependency，另行定义其控制流语义。Linear 关闭凭证接口另行 review，当前不增加用户位置参数。

Error 注册在同一 effect 的 class 内声明可选 detect／resolve，均为无位置参数的 m ()，并以 handles 声明处理的故障类型：RaisedBy 匹配某 effect 的业务 raise，ScopeFaultIn／ContextFaultIn 匹配对应 effect 的 SDK 协议故障。
"出错就收拾资源"已由 once-spare 自动清理承担，Error 的用途是业务层面的诊断与处置，因此按故障类型分派；定位从非结构化的 detect 值检查移到结构化声明。
input 只表达 resolve 所需的能力；关联 scope 由生成器沿 Input／request 推导最近的 Scoped，至多一个，没有则为不定位实例的全局处置。同一 scope 下同一故障类型只能有一个 Error，避免多个 resolve 冲突。
App／IO 的生成入口沿 Input／request 找最近 scope，遇到 Scoped 停止，只登记关联种子。Root 捕获传播到生成入口的 Failure，合并 scopeTrace、errorPath 和 scopeTargets 的 scope 种子；退出生命周期锁后，读取 ScopeHandler.scopeParentNames，沿自动清理也使用的同一棵 ScopeTree 的祖先投影补齐候选。按父到子的层次去重排序，同层沿 ScopeHandler 名单顺序，再按 handles 匹配故障，有关联 scope 的回调须位于该路径上；同一 scope 的多个回调沿注册顺序，全局回调随后执行。
完成路径保存到 Failure.scopeTrace。这里没有另一份 Error graph，不读取新 schema、不新增用户 key，也不做轮询或动态调用 tracing。手改树父边会同时影响 App／IO 的 Error 祖先导航与自动清理；结构自洽不证明故障归属。App／IO 未安装树时仅使用显式种子；Pure 无 ScopeTree 安装路径，继续保留旧的完整候选名单协议。
detect 是可选的值级细化：未注册时类型匹配即调用 resolve；返回 () 表示归此处，SDK 记录 Succ () 并调用 resolve；raise 表示不归此处，记录 Failed 后继续检查。
一次处置完成或失败后仍检查其余相关 scope。Nothing 不生成对应方法。
原失败通过 caughtFailure 读取，检测和处置结果追加到原 Failure.errorHandling，原始来源、分类和消息保留。
诊断使用隔离的 Context 快照；普通故障按捕获资源的归属定位，open／close 故障使用本次实际选定实例或未选定的证据，不能回落到其他实例的旧成功产物。
不重新 boot、不猜测其他实例、不为诊断预执行 Context；同实例诊断串行化。
生命周期持锁期间只收集路径，退出后再诊断；诊断自身失败不递归激活，同次失败的多层 Root 包装不重复处理。
失败 scope 的绑定仅在匹配实例的诊断上下文中可读取；resolve 仍通过既有 scope 方法改变状态。
SDK 不因定位成功自动 invalidate、reopen、重放或把原失败变成功；也不捕获任意底层 IO 异常或恢复已展开的 continuation。

Context 绑定稳定是框架内部必须实现的语义规则，不能仅由“句柄是纯的”推导。操作描述与组合可保持纯构造，但实际 IO、资源开关仍有状态；重复返回 () 不证明重复执行没有外部影响。当前 App 原语已约束绑定读取、发布与生命周期归属；Error 使用显式检测条件，不证明外部执行确定。任意 instance 的纯性、必须调用上游方法仍无完整静态保证，不把编译通过当作公理已被证明。

## 7. 当前样例的地位与下一步

入口为 demo/Crawler/Main.hs、demo/FileDemo/Main.hs 等各 demo 的 Main.hs；sdk/Framework/SDK.hs 为统一 SDK 入口，内部按 Effect、Recursion、Workflow 与 Codegen 拆分。
每个 demo 保留 Main、AST／Target、Effects、Types、Handlers；workflow demo 另以 Workflow 下的独立文件定义各 branch，AST 只组合模块名称。生成接口、末端登记和包装后的 instance 分为 Generated/Effects、Generated/Program 和 Generated/Handlers；Generated/Assets 单独保存静态资产目录。
分离边界是手写配置 facade 与生成代码；生成逻辑属于 SDK，demo 不另设 Codegen.hs。AST 不填写 Reader。
Types、Effects、AST／Target 独立于 Generated 与 Handlers；effect 标记和错误类型都由 SDK 生成，无须手写空 data。
首次生成使用 cabal run effect-codegen -- workflow Crawler（纯 target 用 -- target 加命名空间）。先加载声明并解析 Handlers 的模块／方法边界及显式 effect 引用；资产检查再以 GHC 无代码生成模式分析手写源码和内存中的候选接口，不执行 handler。没有 Handlers 时仍可先生成契约。
手写 instance 使用原生 Haskell，运行仍编译 Generated/Handlers 的协议包装副本，另有纯结构供初始化与查看；修改实现后须重新生成。不新增业务 class，不使用 Template Haskell，codegen 不回写手写源码，也不改写业务执行副本的原方法体表达式。
生成副本保存实际解析的手写源码指纹，公共运行入口在业务执行前比对当前 Handlers.hs；缺失或变更时拒绝启动并提示重新生成。workflow 与纯 target 都比对注册快照，纯 target 另比对所选末端。此检查要求从仓库根目录访问手写源，不替代显式生成或编译。
已有 Main --generate 仍要求导入链能编译，不能替代独立首次生成入口。
各 demo 都演示 instance 内沿 Input 引用类方法；爬虫由 Node algebra lower 末端，组织并行抓取（同时注入解析）与顺序打印。生成时检查末端不是 Context，且每个 Context 都能从末端到达（经调用、require 的按需求值或挂接句柄的注入）。
文件 demo 同样只选择末端；路径、活文件句柄与文本归 Context，校验归 Pure、写入归 Excu，Scoped 的 open／close 均为 m (Maybe String)。ReadFile 的 input 是 FileSession，因此按新规则挂在 openFileSession 下：剧本开启文件时注入读取一次，WriteFile 的 request 再读取一次；拆成读取 Excu 加挂接 Context 留待 Context 不直接做 IO 一项。FileWorkflow 在本链先 request 稳定路径，校验及开启参数 require 该绑定，链结束后自动清理；FileRecovery 仍检测已捕获的文件并显式引用 closeFileSession。
OpenFilesDemo 改为每条链显式 open：InspectFiles 观察当前链及 GC 期间十个文件的存续，FinishInspection 开启自己的新一轮并演示显式关闭；不再要求前一 Node 的活资源自动留给后一 Node。
ScopeInstancesDemo 在每条链先取得稳定参数，保留链内同参 require 共享、异参独立和显式关闭；后续 Node 显式开启新一轮，不读取或改写旧 owner。
ScopeReuseDemo 的三个 writer 各自先 request 参数，scope 内 require；只有实际重叠的使用可以共享，不能固定断言整个 parallel 批次只开一次。汇合后用已有日志和输出核对获取／关闭计数匹配及三次写入，不再 require 已结束闭包的资源；追加模式保留多个开闭周期的内容。
按 AST 末端登记句柄及结果总和 ADT，完成边界只包装一次 Output；结果汇总不隐含跨节点缓存。
本轮以使用闭包 once-spare、require 共享／request fresh 和补全后的依赖约束迁移运行载体与样例，并由使用协议协调显式关闭；以上是实现协议，不以旧样例通过宣称本轮已验证。App／IO 的 Root Error 祖先导航接入同一 ScopeTree，实例定位、detect／resolve 和原错传播保留，Pure 维持旧候选名单，不自动恢复业务；内置结构适配及 loop／Hanging 尚待落实。
当前探索阶段只要求普通编译通过，不自行增加测试、类型负例或额外验证门槛。
