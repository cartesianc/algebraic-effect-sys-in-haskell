# effect 注册、request 与 SDK interpreter 最新设计

更新：2026-10-26。范围：Algebraic Effect Sys in Haskell。

本文记录已确认的设计，供声明、Haskell 接口和执行样例共同遵循。基本方法见 [DESIGN_METHOD.md](DESIGN_METHOD.md)。当前实现位于 demo 与 sdk/Framework；旧根项目的实现和设计保存在 [archive/legacy](../archive/README.md)，仅作历史参考。

本版统一记录固定入口、注册中的取值关系、request 前置调用、结构适配、scope 复用，以及内部控制与外部触发承接重复和反馈的定位。具体 Haskell 接口与序列化 schema 仍待落实；文中的关系示意不是已经实现的 API。当前代码的编译通过不代表新设计已实现。

## 已确认的架构边界

effect 声明自身契约与上游句柄依赖；Input 落实为 superclass，提供上游类方法。
业务组合发生在 instance 内的类方法引用中，不由 SDK 在外部生成另一份操作流水线。
Context 也是 effect，通过 context.request／require 引入生产链能力，手写 Input 不直接指向 Context，也不预设从 SDK 注入全局。
request 引用产值 effect，前插其能力且保留原 Input 前提；实际求值由 instance 引用生产类方法触发。

同一注册集合内，生成的 superclass 合并原 Input 与 Context 来源的传递能力，直接重复约束去重，共享统一 Root、载体和 scope 句柄；不重挂来源链，也不把能力去重当作执行去重。独立生成模块的环境合并尚不在此范围。
Root 统一调用入口已接通：`Effect.handler :: m value -> m value` 当前由 Root 实现为 `id`，其他生成 Effect instance 转交 Root。生成方法自动以 `handler @Root` 包住原协议，包括 Context 默认 require 与用户覆盖的 require；用户类方法名称、签名和引用写法不变。根入口不修改 caller，不提前求值，不另行 lower 上游。open／close 的复用也经过调用入口，但不重放资源操作。
Middleware 作为独立 typing、由 AST／Hanging 装卸是后续设计；计划在装配阶段合并、去重后统一接到最高 Root，不保存旧 pipeline 路线。当前未实现 middleware 注册、执行策略或 Hanging 分支；整次启动与单个方法的策略边界仍需分别定义。

Generated 模块只登记 AST 所选末端句柄。Target 保存未运行的 App／Pure 句柄及内部空存储，尚不是 impl。
Node 的 f-algebra 选择末端后 lower 为具体执行函数，branch 再组合这些函数；SDK 不遍历 Input 补跑上游。
withX、initializeX、链式 runX 和外部逐 effect impl 已取消。载体和 Target 构造器、裸运行器不导出。
未被引用的前驱不会执行；这不等于 Haskell 编译器能静态证明任意方法体使用了所有前驱。
Context 绑定已由 SDK 接通：request 成功发布新绑定、require 只读已捕获的绑定；不通过外部初始化建立业务 Context。普通绑定在一次末端启动内，scope 开启期绑定随同次 AST 的 scope 保存。

原子 effect 与 effect 链分属两个层级。AST 组织完整链的启动与执行控制，不描述节点的业务状态转移；业务值依赖与状态操作由 effect system 的声明、协议及 handler 承接。
chained、parallel、loop 是同级 branch；loop 的事件触发语义已确认，尚未实现。demo/Crawler/Main.hs 的 node 只挂载解析或打印链的末端，
URL 由 request 来源 CrawlerContext 类方法产生；Node 只 lower 对应末端。HTTP、HTML 内容解析与
输出留在 instance，连接由注册描述。chained 遇失败停止；parallel 等待全部子分支后汇总，
结果按声明顺序排列，有失败时保留声明顺序中首个失败的来源与负载。整棵 AST 只封装一次
Output；已完成的 IO 不回滚。SDK 已以 WorkflowF + Fix + cata 实现这两个有限分支的执行装配；爬虫先并行解析两页，再依次运行打印链。打印 instance 引用解析句柄，重新抓取、解析并消费新产物，不复用第一阶段的值。生成器按 AST 选择多个末端，分别登记末端句柄并生成结果总和 ADT；汇总产物不等于建立共享绑定。

业务入口固定为以下结构，具体类型签名由实现落实：

```haskell
main = interpreter ast effects
```

当前爬虫入口为 [Main.hs](../demo/Crawler/Main.hs)，手写配置 facade 与 Generated 生成代码分离；生成逻辑位于 SDK，demo 不另设 Codegen.hs。业务组合 facade 限于 ast 和 effects；interpreter 由 SDK 生成装配，不要求业务另写 Reader 配置、节点执行器或独立 impl。

- effects 收集注册声明。原子 effect 定义自己的契约和 handler；业务注册选择可调用入口，并声明 request／require、输出出口和必要的业务转换引用。
- ast 表达 workflow 的顺序、分支、scope 范围、middleware 挂载及成功／错误后续关系。具体执行 Node 挂载 effects 中选定的注册，一条链可以只写一个手选的目标节点。
- interpreter 解释 AST 和注册引用，启动已关联 scope 引用的末端；scope 状态检查由生成的 handler 包装负责，自动收尾另行设计。

可复用的链内取值关系放在注册声明中，不要求每次 AST 挂载都重写同一条链上的 n 个节点或逐个填写其参数。AST 可以组织多个目标节点，但不必展开目标内部的全部调用。解释器不自动猜测“最后一个 effect”。

AST 与注册关系均采用固定结构、引用和契约描述，供第三方工具读写和生成代码。配置本身可以是有类型的 Haskell 声明，不要求改成 YAML／JSON；选择下一业务操作的关系不能隐藏在任意宿主函数或 IO 闭包中。

解释后使用函数、闭包和局部执行状态，是框架的实现方式。声明保存操作引用、值引用和关系；不保存宿主函数、类字典、线程或活资源。可序列化的程序描述不等于运行中的资源也可以序列化。

## effect typing 与同一 effect 的多方法契约

统一使用 EffectSpec 注册，effect typing 仅有 Pure、Excu、Scoped、Error、Context 五类。旧 Request 类型已并入 Context，request／require 是 Context 内的方法角色，不再计划独立 Request typing。所有方法名绑定放入 typing 对应的 ADT 构造器，不另设顶层 handlers。对外产值的业务转换归 Context，不另设 Map；独立 Read 已取消。

一个 effect 对应一个业务 handler typeclass，可以有多个具名类方法。Scoped 将开启与关闭归入同一个 effect、同一个 typeclass 和同一个用户 instance；Error 将 detect 与 resolve 归入同一个 effect、同一个 typeclass 和同一个用户 instance。Close、Detect、Resolve 不再分别注册为独立 effect 或独立 typing。

| 注册类别 | 同一 typeclass 中的方法职责 | SDK 执行责任 |
| --- | --- | --- |
| Pure | 无对外业务产物的纯计算／检查 | 成功类型固定为 ()，失败使用 SDK 统一协议 |
| Excu | 执行声明的操作 | 成功类型固定为 ()，接入能力并承接失败 |
| Scoped | 开启、关闭，均为 m () | 维护同份 scope 的状态，重复／并发 open 复用；信息来自上游 Context，自动收尾待接入 |
| Error | detect 检测、resolve 处置 | 注入原始故障，先检测，再按结果处置；保存原始与次生失败 |
| Context | request 产值、require 读取 | 包装 instance 入口；request 成功发布新绑定，require 只读，失败保留该来源旧值 |

各类别保持统一的 effect 抽象。Input 只组合被注入的操作句柄，不承载业务值；普通 Pure／Excu 返回 () 或 raise，不手写 Succ，也不新增每 effect 的状态表。跨 handler 的业务成功产值统一由 Context 提供，request 只能引用具有生产入口的 Context。Scoped 自身不产值，open／close 在 instance 中直接引用上游 Context 方法；只有 scope 具有 SDK 管理的存续状态。

### 注册构造示意（待 review）

注册使用普通 ADT 的不同构造器携带各自属性，不因字段不同而引入 type family 或 data family。普通方法名绑定使用 Maybe String，包括 Scoped.open／close；只有 Context.request 使用 Maybe Producer，将方法名和业务产物类型放在一起。Nothing 表示未绑定该方法，不把 handler 返回值改成 Maybe。Pure／Excu、Scoped 和 Context 的方法声明已生成；Context 绑定和 scope 的共享状态已接通，自动收尾与 Error 接口仍待接入。

```haskell
-- 普通注册也把主方法名放入 typing
typing = Excu { handler = Just "printPage" }
typing = Pure { handler = Just "checkPage" }
typing = Pure { handler = Nothing } -- 不声明本地调用入口

-- 同一 effect 内的开启与关闭类方法
typing = Scoped
  { open = Just "openReport"
  , close = Just "closeReport"
  }

-- 同一 Error effect 内的两个类方法
typing = Error
  { detect  = Just "detectReport"
  , resolve = Just "resolveReport"
  }

-- 同一 Context effect 内的产值与读取类方法
typing = Context
  { request = Just Producer
      { handler = "loadCrawlerConfig"
      , produces = typeRef @CrawlerConfig
      }
  , require = Just "readCrawlerConfig"
  }
```

typing 保存本 effect 内的方法声明，只有 Context.request 的 Producer 声明业务产物；消费方 context.request 引用其他 Context 生产者，两层通过嵌套 record 区分。Pure／Excu 以 handler 为普通入口，Scoped 以 open 为入口，Context 以 request 为产值入口；require 的类型由同一生产契约推导，缺少该契约时报错。Error 的普通入口仍待设计。

当前 handler = Nothing 不生成本地业务方法，保留类型契约与 Input 关系；被 target 选择时报没有入口。request 只允许引用具有生产方法的 Context。SDK 不猜测方法名，也不生成默认成功操作。其余多方法类别的缺省处置随协议另定，不能从 Nothing 自动推导出省略清理、吞掉错误或重新产值。

注册中的 EffectTyping 保存方法声明，关联 Typing 只保存 SDK 的 EffectKind 类别标签，不把运行时 String 搬入类型级。当前已实现 PureKind／ExcuKind／ScopedKind／ContextKind，Error 类别接口尚未加入。顶层 produces 已移除：只有 Context.request 声明业务产物，普通 Pure／Excu 与 Scoped 的成功值均为 ()。完成边界由 SDK 返回 Succ value 或 Failed failure，不含 Pending。

target 根据 typing 唯一确定调用入口，不要求 class 只有一个方法；request 固定选择 Context 的生产入口。Error 的故障路由不通过业务 request 表达，普通 target 的入口仍待设计；选择哪个 Error effect、覆盖单次操作还是整个 scope，也须明确声明。

Error 注册类别与关联 Error e 是不同概念：前者组织检测和处置方法；后者由 SDK 生成 EffectNameError String，类型唯一确定所属 effect。原始 Failure 保存来源、自动分类和消息，传播或次生失败不覆盖原故障；不新增逐方法的 raise 接口，也不要求用户声明错误 ADT。

使用 SDK 的 effect-codegen 输出普通 Haskell 源码，保留 Generated 模块供 review，避免 Template Haskell。生成类用 MINIMAL 和 -Werror=missing-methods 要求实现业务方法。Context.require 由 SDK 默认读取本次调用的成功绑定，不加入 MINIMAL；产值方法必须实现。Nothing 不生成该角色，缺少 open／close 不代表完整 scope 协议。只做必要的普通编译，不增加测试或额外检查门槛。

### 类方法契约细化草案（待 review）

根 Effect 保留 Require、Produce、Error 关联契约和统一 raise，不新增统一业务 handle。Produce 是 SDK 内部成功类型，默认 ()；只有 Context.request 覆盖为业务 ADT，不含 Output。Input 注入上游方法，instance 直接引用；一个 effect 的多个协议方法仍可有不同签名。

当前普通句柄没有 SDK 注入的位置参数：Pure／Excu 返回 m ()，Context 返回 m (Produce e)。
实例内通过原生 `<-` 取得 Context 业务值，普通 case 只匹配已取得的值；声明 Input 不隐含传值。普通操作仍直接引用 superclass 方法。
资源、故障和检测结果的协议参数只有在明确声明后才加入，不由 typing 自动补入。

| 类别／方法 | 当前签名或候选 | 状态 |
| --- | --- | --- |
| Pure／Excu 主方法 | m () | 成功无业务产物；Pure 本地 IO 限制另定 |
| Context 生产／读取 | m (Produce e) | 类型来自 Producer.produces；生产成功保存，读取不重复执行 |
| Scoped 开启 | m () | 直接引用上游 Context 方法完成开启；SDK 保证同份有效 scope 不重复执行 |
| Scoped 关闭 | m () | 通过上游 require 读取信息，不重放生产；成功关闭不重复执行 |
| Error detect | Failure Errors -> m (Detection evidence) | 原始故障与检测证据契约待 review |
| Error resolve | Failure Errors -> Detection evidence -> m resolution | 同次故障和检测结果的处置契约待 review |

e 在同组方法内指同一个 effect。evidence 与 resolution 仍是待定协议契约的占位，不是已新增的关联类型或配置字段；Error 多方法结果需单独 review，不借用 Context 的产物契约。关闭、检测和处置的参数不来自重新执行生产者，不能用 request 重开资源或重放失败操作。

Detection 的固定结论层仍为提案，具体名称待 review：

```haskell
data Detection evidence
  = Usable evidence
  | Invalid evidence
  | Unknown evidence
```

Unknown 表示检查完成但证据不足，不是 Pending；检测方法自身失败仍使用所属 effect 的错误契约。以下展开业务 ADT，仅展示同一 class 内的两组方法，不表示资源和故障协议已经实现：

```haskell
-- 上游 SessionContext 产出会话信息，Scope 自身不产值。
class Effect SessionContext m => CrawlSessionEffect m where
  openCrawlSession  :: m ()
  closeCrawlSession :: m ()
  {-# MINIMAL openCrawlSession, closeCrawlSession #-}

-- 以下参数表示已显式声明的依值，具体注册语法仍待 review。
class Effect Report m => ReportFaultEffect m where
  detectReport :: Failure Errors -> ReportHandle
               -> m (Detection ReportEvidence)
  resolveReport :: Failure Errors -> Detection ReportEvidence
                -> m Resolution
  {-# MINIMAL detectReport, resolveReport #-}
```

资源依赖按真实需要声明，示例不要求所有 Error handler 都使用资源。类约束提供方法可用性，不证明哪一份资源仍可使用；绑定身份、失效、释放状态和收尾次序由 SDK 管理。同一 class 内的方法配对不再插入一个 Close／Detect／Resolve effect，也不构造相互继承的 Input 环。

爬虫目录的 SessionContext 产出原生 CrawlSessionInfo；CrawlSession.open 引用 createCrawlSession，close 引用 readCrawlSession，均返回 ()。两个 Fetch instance 直接引用 openCrawlSession，再读取会话信息用于 HTTP User-Agent。SDK 在同次 AST 中只开启一次，并保存开启期间生产的 Context 供多条链复用；自动关闭仍未接入，不新增 AST 结构。

Pure 的统一 raise 仍有一个尚未实施的 SDK 内部候选：

```haskell
-- Effect effect m 内的候选成员
type Body effect m :: Type -> Type
raise :: Error effect -> Body effect m value
```

生成器可为纯方法选择 Local m，为执行方法选择 m。此方案尚未解决全部 Reader 接入、字典选择及不同 Body 间显式重新 raise 的问题；当前代码仍使用 raise :: Error effect -> m value。SDK 传播上游 Failure 时保持原来源，不要求 handler 再 raise 一次。Local 与 Body 不因本次方法归组而定案。

后续只按小幅 review 推进，先展示对应注册、生成签名和用户 instance，再改生成器：

| 微任务 | 本次只确定什么 |
| --- | --- |
| T1a Pure | do／pure／raise 的用户形状与返回类型 |
| T1b Pure | 统一 raise、错误归属与普通执行方法的衔接 |
| T1c Pure | 固定 Reader 的接入与 Local 结果装配 |
| T2 Excu | 普通执行方法的参数、完成结果与能力约束 |
| T3 Context request | Context 内的生产方法与消费者 request 引用的对应，不另设类型 |
| T4 Context | 经 request／require 接入；普通绑定在单次启动内，scope 开启期绑定已随 scope 跨 Node 保存；跨入口存续另定 |
| T5a Scoped（已落实） | 同一 class 的 open／close 均为 m ()；信息来自上游 Context |
| T5b scope 绑定 | App／IO 已按同批 Scoped 注册及实际开启参数值共享多份状态与 Context；结束边界待定 |
| T6 Scoped 关闭 | 成功关闭去重，旧引用停止使用，显式 open 可重开；次生失败汇总和自动收尾待落实 |
| T7a Error | 同一注册中的 detect／resolve 方法名及各自的结果契约 |
| T7b Error 检测 | 原始故障、可选资源参数及检测结论 |
| T8 Error 处置 | 消费同次故障和检测证据，明确处置产物，不附带自动恢复 |

## 原子定义、业务注册与调用分离

注册定义契约、Input 能力依赖及生产者引用；instance 在这些可用能力内直接引用上游类方法。描述保持可序列化，不靠解析任意 Haskell 方法体恢复依赖；实际调用由 instance 表达，注册继承不等于自动执行。多份注册的句柄复用语法另行 review。

注册中的参数来源是可序列化的调用描述，不是 env -> value 函数或 IO 闭包。生产者通过注册引用连接；引用者无需复制生产者的定义及其整条上游声明。这份描述不是被重新引入的 impl 层，执行装配仍由 SDK 提供。

需要分别识别以下对象：

- 操作声明，确定契约和可选 handler。
- 业务注册，选择可调用入口并绑定参数来源，供 AST 或其他注册引用。
- 声明中的调用位置，确定输入来源和后续关系。
- 本次执行中的调用，确定输出所属的执行和 scope。
- 输出绑定，确定消费者引用的那份成功值或错误负载。

这些身份可由静态引用、执行上下文和闭包局部绑定共同表达，不要求引入全局异构结果表。具体标识格式未定。一份注册可以产生多次调用；普通业务结果的共享由输出绑定和 require 表达。已开启 scope 的能力复用按 scope 协议处理，不把它误作普通操作结果的自动缓存。

Input 继续表达操作或能力的前提关系。业务值来源单独表达，Context 转换不因为处理某个生产者的输出，就把生产者隐含为能力 Input；前提与取值声明分别核对。

## Context、request 与 require

手写 input 只允许 Root 或非 Context effect；Context 经 context.request／require 声明进入生成的 superclass。生产者自身仍可有 Input、消费其他 Context，也可直接作为 target。原 Input 与生产链的能力同时保留，不重挂来源注册；沿 Input 与 request 收集 scope，require 只读取绑定，不启动生产链。
爬虫通过 request 连接 URL、抓取、解析与打印，SDK 不预先生产全局 Context。

生产方与消费方分别描述，Context effect 自身也可以消费别的 Context：

```haskell
typing = Context
  { request = Just Producer
      { handler = "extractLinkedPage", produces = typeRef @PageSummary }
  , require = Just "readLinkedPageSummary"
  }
context = Just ContextInput
  { request = Just (From "FetchLinkedPage" (typeRef @FetchedPage))
  , require = Nothing
  }
```

typing 中是本 effect 提供的方法与生产契约；context 中是本 effect 消费的来源与接收 ADT。
context 为 Maybe ContextInput，其中 request／require 各为 Maybe ValueSource；From 保存来源 effect 与类型引用，
移除外层 requires／request。request 调用来源的生产入口，require 读取来源的已有绑定；两者不配置生产方的方法名。
Nothing 表示不声明对应输入，不表示业务值使用 Maybe。request 加入生产者能力，保留原 Input；不再要求生产者的祖先已经包含消费者原 Input。

输入契约与 typing 共同决定方法签名。当前生成器由 context 形成关联 Require，并在 superclass 中加入来源成功类型
与接收 ADT 的相等约束；单输入直接使用该 ADT，双输入按 request、require 排为二元组。
FetchedPage 是类型，FetchedHTML 是 instance 可匹配的构造器；typeRef 不描述某个构造器的子集。
instance 使用原生 Haskell：在 do 中通过 `value <- contextMethod` 取得业务值，普通操作直接引用 superclass 方法。可确定匹配的单构造器模式可直接写在 `<-` 左侧；多构造器值先绑定再用普通 case 显式处理，失败通过 raise，不新增 MonadFail。SDK 在注册生成的 Context 入口连接 request 生产与 require 读取；生成器只解析模块／方法边界并包装入口，不改写表达式。方法不新增位置参数、Definition、consume 或独立 booter；嵌套取值共享本次 Context 和 scope。未进入的分支不取值，生成源码和创建 Target 不执行业务 IO；不使用 unsafePerformIO／unsafeInterleaveIO。手写 Handlers 保持原生语法，运行仍编译 Generated/Handlers 的协议包装副本，修改实现后须重新生成。

request 每次重新生产，成功后将同一个值发布为当前调用的新绑定并返回；require 只读已捕获的成功绑定，未绑定时报 ContextNotInitialized。
刷新失败不覆盖该来源旧值，错误原样传播，其他已完成的操作不回滚。普通绑定限定在一次末端启动内；scope 开启期间生产的绑定随该运行句柄跨 Node 保存，不在独立创建的句柄之间隐式共享。
SDK 用局部 Reader 记录当前消费者，按注册选择上游生产方法引用的 request／require 模式；未声明的业务取值报 UndeclaredContextAccess。
根入口直接生产；同一消费者对同一来源同时声明两种模式时，生产方法引用按 request 执行，显式读取方法始终 require。
SDK 不预初始化 Context，Input 仍只提供类方法能力；未被引用的上游不执行。scope 多实例绑定见后文；普通 Context 多份调用绑定与跨入口存续另行设计。

AST 仍只决定链的启动次序。parallel 先解析两页，chained 再打印；打印方法重新引用解析、抓取句柄，
不读取第一阶段缓存。具体调用输出引用、跨节点共享与 Generic Map 仍待设计。

`Require e` 是 context 中 request／require 声明的 ADT 接收契约；`Produce e` 直接表示成功类型。
业务 ADT 在 Types.hs 用原生 data/newtype 单独定义，注册通过 typeRef 引用；Require、Produce 是 Effect 中的关联 type。
只有 Context 的 Produce 来自 Producer.produces，其余当前类别默认 ()；Error e 由 SDK 按 effect 名生成，不从产物提取。
它们以原子 effect 为索引，不要求另设契约类，也不因执行载体 m 改变而改变 ADT。
handler 方法是可调用句柄；部分调用产生业务值，但普通句柄组合不要求传递 Produce。
生成器不再定义业务构造器或解释 ADT/Constructor 字段语言，只生成类型关联、方法与装配。
原生 record、嵌套和参数化数据由 Haskell 定义；deriving 也由业务声明选择。
TypeRef 通过 Typeable 识别 SDK 的 Output 构造器以拒绝嵌套完成协议；不解析显示字符串。
其余业务类型保存显示名称，Generated 模块须能解析该类型名；它不保存完整数据定义，也不代表
任意 Haskell 类型结构都能被第三方工具解释或被 Generic Map 自动适配。
业务方法体与上游引用保留在用户 instance 中；DemoContext、MakeNumber、AddOne、RenderNumber 通过 request 形成产值组合，手写 input 均可为 Root。MakeNumber 引用 loadDemoInputs，AddOne 引用 makeNumber，RenderNumber 引用 addOne；
compiledTarget 只登记 renderNumber，纯计算入口 lower 它后得到 number: 21。RenderNumber 同时 request AddOne、require DemoContext；其 loadDemoInputs 引用复用 MakeNumber 先前保存的值。
review 面仍集中在两个 demo，SDK 提供契约、载体、末端登记与 Node lowering；不引入用户另写的 impl 层。

当前 benchmark 完成结果为 Succ value 或 Failed failure。SDK 自动生成 MakeNumberError String 等本地错误、
关联 Error e、raise 实现与 Errors 分类；用户写 raise (MakeNumberError message)。统一 Failure 保存 origin、detail 分类和 message，
不再需要业务错误 ADT、NoError 引用或错误配置。Error 的单射约束保持来源推导；Except 使普通 do 短路，
上游失败原样传播，lower 只解释登记的末端，最终边界只封装一次 Output。
当前不设 Pending；调用标识、传播路径与通用 IO 异常接入均未实现。

SDK 不在 handler、request 或 impl 内增加 Succ；生成器拒绝 Context.request 把 Output 声明为产物。
业务 ADT 内部字段保持不透明，不自动展开或改写；原子方法直接返回成功值，编译器核对其与契约一致。

## 注册关系装配成执行闭包

Input 与 request 共同表达依赖后，注册关系可以形成图。业务仍只提供 ast 和 effects，不因此增加一套图调度接口，也不要求把图上的每次调用写成 AST Node。

对于有限、静态、无环的依赖，SDK 可以在装配阶段解析注册引用和调用关系，再生成执行闭包。AST 的 fold 可在 Node 的 algebra 中装配所挂载的注册，branch 组合子节点的执行闭包。continuation 提供组合手段；调用次序、结果共享及 scope 归属仍按声明和 SDK 契约确定。

当前 SDK 的同一棵树分别经引用收集 algebra 与执行 algebra 解释。后者组合封闭 target 的启动动作，返回尚未执行的 ExceptT / IO：chained 顺序运行，parallel 并发运行；fold 本身不绑定 Reader 或执行 handler。空分支成功并返回空结果，有限的 chained／parallel 可组合；节点结果仅在完成边界汇总，不自动成为下一节点的输入。

注册起到程序描述的作用，解释器据此构造执行表达式。这可以发生在启动装配时，不要求 Template Haskell，也不提前运行 handler 或取得业务值。装配保留在 facade 的Generated 模块供 review，业务只填写 ast、effects 与 instance。

闭包可以持有本次输出绑定、scope 能力和必要的共享状态，不必先建立通用图调度 runtime 或全局异构结果表。显式共享的调用保留一份绑定，不能在展开时复制成多次执行。编成闭包不消除 scope 失效、取消和收尾所需的状态。

装配结果保留与注册、调用位置和 scope 描述的关联，供 middleware 和故障追踪使用。描述与执行装配分离：声明保持可序列化，函数、类字典、线程及活资源由运行部分持有。第一版先落实有限、静态、无环的单次调用依赖；重复与反馈按下述控制和触发关系解释，不在装配阶段无限展开。

## 内部控制与外部触发

node 表示一整条 effect 链的可调用入口；chained、parallel、loop 是同级的 branch 组织方式。
chained 按前一次成功完成推进，parallel 并发启动并等待全部完成，loop 按事件触发启动。
不把 loop 当作 chained 中等待完成的普通执行项；涉及 loop 及其他新增 branch 的嵌套规则另定。

“只负责启动逻辑，不负责状态转移”中的状态指业务状态。AST 不保存可变节点状态、上次产物或业务状态机，也不据此隐式传值；但完成、失败停止、并发汇合仍属于它的执行控制语义，运行记录由 SDK 持有。业务状态变化由 effect handler 执行。Context 按 request／require 引用，普通绑定与 scope 开启期绑定分别由 SDK 管理；scope 状态也属于 SDK，不引入节点业务状态机。

[Hanging 的既有设计](../archive/legacy/docs/design/HANGING.md) 是主控制树之外的事件 hook 树／列表，关联事件源、触发或恢复目标、所属执行与 scope。它可承接 loop 的订阅挂载，SDK 持有回调与有效期记录；loop 每次事件启动新调用，恢复旧调用属于另行声明的等待／恢复协议。Hanging 不承载节点业务状态机，也不要求自建协程调度器；当前尚未接入。

- loop 是执行方式的 transformer：将所属节点的入口装配为事件订阅与回调，不要求模块持续执行。
- 无条件：loop 不根据本轮业务结果设置继续判定；订阅有效时由事件触发调用，无事件则等待，所属范围结束时停止。
- 无状态：loop 与 node 不保存跨调用的业务产物，不自动更新 Reader 或把上次结果作为下次输入。值的来源、绑定与依赖由 effect system 的 request／require／Context 协议解决；订阅有效性和运行中调用属于 SDK 的执行管理状态。

loop 拟沿用 recursion scheme 的 algebra lower 为执行闭包：建立订阅、连接节点入口并绑定收尾。
装配时不执行业务 handler，不要求另建协程调度器或通用图 runtime。事件源由声明确定，不能仅凭节点入口猜测。

更一般的重复与反馈仍区分内部控制和外部触发，不因此把 loop 扩展为隐式的业务状态循环：

| 层面 | 声明含义 | 例子 |
| --- | --- | --- |
| 内部控制 | 根据调用完成或判断结果选择后续启动；跨次业务值依赖由 effect system 声明 | 校验不通过后触发调整，再次校验 |
| 外部触发 | 声明事件来源或持续状态、变化条件与处理目标，激发新调用或恢复等待中的调用 | 新修改稿到达后再次审核 |

Alternative、race、resume 仍为待定构造；useState／useEffect 只作为触发与快照的类比，loop 不隐式修改 Context。loop 每次触发启动一次调用，不隐含恢复旧调用。node 无状态不妨碍观察本次完成／失败；loop 不设继续条件，也不意味着 AST 无法表达其他条件控制。

静态无环约束针对单次调用的能力与取值依赖；固定声明可动态产生多次调用并形成反馈，如 A₀ → B₀ → A₁。A₀ 与 B₀ 相互等待尚未产生的输出仍不构成可执行流程。Input、request／require 不隐含订阅或重放；require 始终读取确定的已有绑定，普通 Pure 的成功／失败也可参与执行控制。

loop 的事件源引用、监听范围、单次失败处置、事件重叠时的排队／取消／并发及收尾协议仍待落实。可用的同份 scope 按声明复用，失效或关闭后不自动重启。等待由 SDK 执行协议承接，不依赖 Haskell 惰性求值，也不向完成结果增加 Pending；loop 当前只确认设计边界，未新增其 facade 或实现。

## 业务纯转换与 SDK 内置结构适配

Read 的单纯取值职责由 require 和输出解析承担，取消独立 Read 注册和中间执行节点。实际文件读取仍是原子执行操作。

旧 Read 中的缺值处理、ADT 拆解和字段提取，需要各自归入输出契约或原子 handler，不能随着删除 Read 一并丢失。require 只解析声明的输出来源，不自动理解任意业务 ADT。

对外产值的业务纯转换注册为具名的 Context effect：声明输入输出契约，引用转换 handler，通过 request 或 require 接入输入，产出可继续绑定和消费的结果。合并 typing 不隐藏转换操作及其调用关系，也不要求用户补写 impl；转换失败由所属 Context 的错误契约表达。

普通值连接的结构适配由 SDK 内置 Generic Map 提供。在当前支持的 ADT 范围内，连接两端确定源输出契约和目标 Require 契约。GHC 编译类型化声明时检查结构约束，SDK 装配已编译的证据与转换实现，执行时转换实际值。结构适配不要求先有业务值，也不由它选择生产者、出口或消费者。

目前只有这一种结构适配规则，不新增 adapter 参数类目、策略枚举或 adapt: structural 配置。业务明确连接两端，即采用固定的结构对应规则；不要求手写 StructuralIso、forward，或为每一对包装类型另注册一个机械转换。SDK 将它装配为内置适配调用，保留执行关系供观察，不增加业务必须填写的 AST 节点或 Map typing。

固定规则按构造器和字段位置对应，保留字段类型和值。名称差异可以忽略；业务含义不会因此被证明相同。需要加前缀、解析、计算、重排或其他业务纯转换时，注册并引用 Context effect，不扩展第二套 adapter 分类。

旧 Generic Map 原型已清理，正式适配仍待接入；不因此假定任意嵌套 ADT 可转换，或任意 Generic 实例都满足互逆与完整观察语义。

以下为 Context 产值转换与输出共享的关系示意，不是逐个书写 AST Node 的要求：

```text
在本次 scope S 内
  调用 Context 生产者 P，绑定输出 p1
  调用 Context 转换 M，输入 require p1，绑定输出 m1
  消费者 A 使用 require m1
  消费者 B 使用 require m1
  消费者 C 使用 request 再次调用 P
```

这里 P 有两次调用，M 有一次调用，A 与 B 使用同一次转换结果。若只共享 p1，而分别声明两次转换调用，则不自动共享转换结果。

Context 转换可以处理成功值和错误负载。转换错误负载不会自动使原操作恢复成功；转换结果决定后续调用时，将结果交给明确的 workflow 分支。失败输出契约、缺值分支和转换自身的错误如何接入统一结果协议，仍需写成具体接口。

## scope 存续与可调用性

effect 不配置 dependency。SDK 沿原 Input 与 request 生产链收集 Scoped，能力仍由 superclass 注入；require 值引用不另增 scope 前提。SDK 不补跑 open／close，二者均为 m ()，实际调用在用户 instance 内。

同一 interpreter 自动创建一批 ScopeHandler，由所有末端 Target 捕获。每个 Scoped 注册持有按开启输入值区分的实例集合，每份实例独立保存 MVar、生命周期和开启期 Context。注册及 instance 语法不变，不增加 key、位置参数或用户装配，也没有进程全局单例。不同 Input 链取得相同参数即共享同份有效实例；不同参数各自独立。

当前 App／IO 协议采用已有文件链的结构：Scoped.request 引用资源 Context（如 FileResource），该资源 Context 声明消费的上游 Context（如 FileLocation）及其值前提构成开启参数。SDK 生成观察器，在 instance 真正引用这些方法并取得结果时记录原生 ADT 值，按来源、类型和 Eq 比较；参数 ADT 需要 Eq，资源产物不需要 Eq。参数在本次开启中必须保持一致。SDK 不在外部提前执行 Context，不从文件路径字符串、Show 或 Handle 身份猜测参数。

每次显式 open 仍按原取值声明取得本次参数；request 重新求值，require 只读。全部参数取得后：同参有效实例直接复用，跳过资源获取及 open 的剩余方法体；不同参数才实际开启。参数生产者自己的 IO 可以运行；open 范围中其他 IO 必须在参数齐备之后，否则报 ScopeInputsMissing。参数变化发生在选定之后则报 ScopeInputAfterOpen。该协议不分析任意 IO 闭包中的隐藏参数，也不将混在参数生产动作里的资源获取自动拆开。没有声明开启输入的资源按无参 scope 处理。纯计算 benchmark 不含 Scoped；多实例观察协议目前接在 App／IO 载体。

底层 ContextBinding 保存不可变的值快照与 scope 实例引用，二者一起传递；App 已删除 selectedScopes／lookupSelected。require 首先读取本次调用已经捕获的绑定，不因另一条链发布新值而改变。显式 request 发布并替换当前调用的来源绑定；开启期间建立的绑定由 scope 保存供跨链复用，其他已捕获绑定不被原地改写。普通 Context 仍按 Node 隔离。

close 不预先选择 scope，也不预执行 Context。生成包装先进入关闭协议，用户 instance 原有的 require 引用取得 ContextBinding 后，SDK 从该绑定的归属取得生命周期锁，再继续关闭方法体。找不到绑定／归属即失败；关闭期间不能改用另一份归属。open 为实际生产的资源绑定附加本次归属；有效 scope 复用时传递原绑定。重新开启产生新实例，旧绑定仍指向旧的已关闭实例，不会误关新资源。

跨链第一次 require 尚无本地绑定时，只接受唯一可解析的来源绑定并将其捕获；多份来源且没有明确关联时报 AmbiguousContextBinding。此规则不解决任意历史绑定的用户寻址，不能把同一个无参方法解释成“任选过去第几份值”。同一份已绑定句柄重复 require 稳定，与同一注册结构创建多份调用环境是两回事。

同参并发 open 等待同份实例的锁，异参各自独立。开启失败／中断后失效，close 失败允许再清理，成功关闭后重复 close 跳过。关闭方法须先引用已有 Context，再做释放 IO；参数／资源生产失败不触发外部补跑。普通下游失败不自动等同于 scope 失效。

ScopeInstancesDemo 在一次 interpreter 中验证两份文件：同参复用、异参独立、跨 Input 链复用、require／close 选择一致、关闭后重开；五次 open 取得五次参数、实际获取三次资源。ScopeReuseDemo 与 ScopeClose 检查继续覆盖同参并发开启和重复关闭。

状态分配不执行业务，AST 返回也不自动 close。重新创建一批运行句柄不共享状态；跨独立 interpreter 的存续不在当前范围。生命周期锁不覆盖取出 Handle 后的任意业务使用；使用与关闭并发协调、自动收尾、异步取消清理、Error 检测接入及 Linear 凭证仍待设计。

这使“同一绑定保持同一值与资源归属”成为底层表示和 ContextStore 原语的约束，而不是额外 adaptor 的约定。但架构尚未成为能静态证明所有业务公理的系统：生成包装仍提供运行时协议，GHC 不证明 instance 必须使用 DI；App 中的任意 liftIO 不因句柄描述纯而变纯，Pure typing 也尚无完整的 IO 排除约束。Error 的 detect／resolve 仍待实现，不能用它假定外部执行总是确定。此次未增加新语法或形式化验证门槛。

## Error 的检测、处置与失效传播

detect 和 resolve 是同一个 Error effect 的两个原子 handler，生成在同一个 typeclass 内，由同一 instance 提供实现，不再各自注册一个 effect。SDK interpreter 根据明确的故障路由调用这两个方法；AST 不重复声明其内部方法角色，处理范围仍须由声明确定。

已确认的事件顺序为：

```text
业务操作失败
  → 当前失败分支停止推进
  → 沿相关 scope 关系调用选定 Error effect 的 detect
  → 根据检测结论判定对应 scope 的状态
  → 失效沿依赖关系向下传播，停止受影响的业务节点
  → 调用该 Error effect 的 resolve，并完成必要收尾
```

resolve 表示处置，不承诺恢复。最新设计采用故障后停止受影响执行的规则，不要求轮询、自动重试或自动恢复。停止下游由 SDK 根据依赖关系统一执行，resolve 方法不重新编排一次整条停止流程。

业务故障、对被检查条件的检测结论，以及检测操作自身的失败，需要保留区别。建议检测结果明确表达条件成立、条件不成立和无法判断；这是待落实的结果协议，具体构造器与错误类型尚未定案。

显式 pipeline 提供排查范围、路径和故障归属依据。实际检测取得的证据决定可以得出多强的结论；检测当前正常不能证明原故障没有发生，也不能仅凭一次检测失败保证定位了唯一根因。原始失败保持独立，检测、处置和清理的次生结果作为后续证据保留。

用于检测的原子操作应按检测契约执行。重复检测不默认重放有副作用的原业务操作。

失效传播阻止未开始的业务调用，受影响的运行任务进入取消或停止协议。诊断、处置和释放路径必须仍可按协议完成，但不能因此使用已经释放的资源或绕过它们真正依赖的能力条件。

检测正常后向上检查的规则、无法判断时影响哪一层 scope，以及检测或处置自身失败时如何收尾，仍需明确。它们决定停止范围和结果归属，不改变已经确定的故障停止原则。

## 当前实现

[sdk/Framework/SDK.hs](../sdk/Framework/SDK.hs) 保留统一入口；[Effect.hs](../sdk/Framework/Effect.hs) 下分 Contract、Registration、Context 与 Runtime，
分别负责契约、注册解析、存储原语和末端句柄描述／lower。[Recursion.hs](../sdk/Framework/Recursion.hs) 只提供纯 Fix／cata；
[Workflow/AST.hs](../sdk/Framework/Workflow/AST.hs) 保存结构，[Workflow/Execution.hs](../sdk/Framework/Workflow/Execution.hs) 提供执行 algebra 与并发汇合；
[Codegen.hs](../sdk/Framework/Codegen.hs) 负责源码生成。拆分不改变 boot 范围或 IO 权限，本次文件分离不改变 handler 签名或执行语义。
[Generate.hs](../sdk/Framework/Generate.hs) 提供统一首次生成命令，只编译 Types、Effects 和 AST／Target；用 GHC 9.12 解析器读取 Handlers.hs 的模块与方法边界。
它们不导入 Generated 或 Handlers；effect 标记与错误类型自动生成，无须用户手写空 data。
首次运行 cabal run effect-codegen -- workflow Crawler 或 -- target RequestBenchmark，生成接口后填写 handler，再次生成并编译 Main。缺少 Handlers.hs 时先生成空编译模块；不加载或执行业务实现。
编译入口只导入 Generated/Handlers，SDK 包装方法入口，保留原生取值与业务表达式；不回写手写源码或新增业务类型类。手写实现变更后须重新生成。
已有 Main --generate 仍要求导入链可编译，新增 effect 或缺少生成文件时使用独立 SDK 命令。
[demo/Crawler/Main.hs](../demo/Crawler/Main.hs) 和 [demo/RequestBenchmark/Main.hs](../demo/RequestBenchmark/Main.hs) 分别演示 IO 与纯计算；
两者的手写入口、注册、handler 与生成模块分别可 review；
仍使用的并发辅助函数已并入当前 SDK。

同次 AST 的 scope 共享状态已接入；自动收尾、Error 检测处置、Generic Map 和 loop／Hanging 尚未接入，不能把已生成方法签名当作这些协议已实现。

## 第一版实现范围

建议第一版先落实顺序主链，单次调用的能力与取值依赖采用有限、静态、无环的声明，能力前提沿 Input 表达，值来源在业务注册中通过独立引用连接。SDK 将依赖装配成执行闭包；内部控制与外部触发按相应协议扩展重复、恢复和反馈，不提前建立通用图调度器或全局节点存储。

一个完整样例应覆盖以下过程：

1. 定义原子契约和 handler，在 effects 注册可调用入口及参数来源；保持 main = interpreter ast effects。
2. AST 挂载一个选定目标，由其注册中的 request 带入产值前置，不在 AST 复写整条链。
3. 开启一个 scope；多次业务 request 使用同一份可用能力，不重复开启它。
4. 接入内置结构适配和 Context 产值转换，明确一次产值的绑定，让多个消费者 require 同一份结果；另一次 request 产生新结果。
5. 故障后调用 Error effect 的 detect，判定失效并停止依赖该 scope 的剩余业务调用，再调用同一 Error effect 的 resolve；scope 收尾调用所属 effect 的 close。

Input 继承、instance 内引用、末端登记与 Node lowering 已接入；普通 Context 按单次启动绑定，scope 开启期 Context 随同次 AST 的 scope 共享。跨入口存续、自动收尾与 Error 协议继续细化。Generic Map 尚未接入，当前读取连接要求同一业务 ADT。handler 已实现不等于应自动执行，统一入口只驱动声明可达并满足条件的调用。

当前只做必要的普通编译，不新增测试、负例或额外检查门槛。现有检查和 mock 不反向决定新接口。后续并发、等待和跨入口存续的实现，必须在相应语义明确后展开。

## 仍需落实的契约

| 项目 | 已确定 | 仍需落实 |
| --- | --- | --- |
| facade 与注册 | 固定 interpreter ast effects；注册保存可调用入口和取值关系，AST 可只挂载链目标 | 注册引用的类型与 schema、入口数据绑定、异构注册集合的接口 |
| 注册类别与方法 | 分类仅 Pure／Excu／Scoped／Error／Context；已生成 Pure／Excu／Scoped／Context 方法，Context 读取有 SDK 默认实现 | Scoped 自动收尾；Error 方法接口与执行协议 |
| request 与输出绑定 | request 组合新的产值调用；require 读已有输出；两者不重放可用 scope | 多操作 effect 的入口选择、调用与输出引用格式、缺值和未就绪的表达 |
| Context | 经 request／require 接入；普通绑定在 Node 内，scope 保存开启期绑定；require 读取固定快照，request 显式替换当前绑定 | 跨入口存续、多份绑定与更细的有效范围 |
| Node lowering | Target 保存未运行的末端与生成 scope 引用；Node algebra 只 lower，普通 Context 仍独立；构造器与裸运行器不导出 | 自动收尾、更细范围与跨入口存续 |
| 句柄内 DI | 两个 demo 已直接引用 superclass 类方法；已移除外部 withX／initializeX／链式 runX | 不将执行可达性误作编译器对任意方法体的强制证明 |
| 闭包装配 | Node algebra 只 lower 所选末端，实例内引用带起上游；不要求通用图 runtime | Context／scope 存续及显式共享引用 |
| 控制与触发 | AST 负责启动与执行控制，不维护业务状态转移；chained／parallel 已以 cata 装配；loop 与二者同级，无条件、无跨调用业务状态；Hanging 承接事件入口 | loop／Hanging 接入、监听范围、单次失败与重叠处理、停止收尾；其余 branch 构造及嵌套规则 |
| scope 边界 | open／close 均为 m ()，SDK 生成状态检查；同批句柄按开启参数跨 Input 链共享 MVar 状态，同参有效实例复用，显式 open 可重开已关闭实例 | 使用与关闭协调、自动收尾与取消清理、跨入口存续 |
| 诊断与处置 | 同一 Error effect 内 detect 在前、resolve 在后，不要求自动恢复；原错误与本 effect 自身错误分开 | 处理范围、检测证据与处置产物、排查次序、不确定结论的停止范围、次生失败与收尾 |
| 值转换 | Generic Map 为 SDK 内置适配，不新增 adapter 配置或 Map typing；对外产值的业务纯转换注册为 Context | 原型接入注册、支持的契约结构、转换的失败输出接口 |
| 序列化 | 保存结构、引用和契约，不保存执行闭包与活资源 | 固定 schema、类型引用及 SDK 协议识别方式 |

这些空缺不构成架构方向上的阻塞，可以从最小声明与统一调用接口开始落实。涉及 scope 业务边界或停止范围的选择，应在对应执行逻辑实现前明确；能由 SDK 内部统一完成的装配细节，可直接选择简单实现，不增加业务必须填写的新层。
