# 工作约定

项目：Algebraic Effect Sys in Haskell。工作主体为 `sdk/`、`demo/`、`docs/`。开始架构工作前先读[主设计的设计原则](docs/LATEST_DESIGN.md#principles)，再按下表进入任务所属章节。

## 协作与变更边界

- 使用用户的语言交流。需求可能不完整；先核对语义和证据，必要时确认实质歧义。
- 保持设计简单，遵循附近风格；源码和样例是证据，不是不可改变的设计权威。
- 设计先于实现。声明语法变更单独确认，不为实现方便增加语法、特殊情况或兼容层。
- 当前探索阶段只做必要的普通编译，不自行新增测试、负例或额外检查门槛。历史验证不能冒充本次验证。
- 不自动使用 agent-browser；需要视觉检查时请用户协助。
- commit 使用 Conventional Commits。提交、推送及其他发布动作遵守用户本轮授权。

## 必须保持的架构边界

- 文档用独立“代码长什么样”章节作为较早的阅读入口。README 以自然语言分层介绍这是什么框架、能做什么、为什么这样设计、代码长什么样及如何开始；开篇概括项目，正文解释设计要解决的问题，以一行 Main 与 asset、effect、handler、workflow 的关系概述引导到指南；Context 等具体 effect 类别、完整模块声明与 import 在指南展示；具体环境准备、生成、编译、运行和结构查看命令集中在指南，README 随正文中的相关概念和开发步骤自然引入文档链接。指南再以同一业务的原生 Haskell 代码块展开各子模块，标明文件与节选边界并链接详细规则。
- 代码的书写形态属于架构契约。新增功能先展示受影响的资产、注册、instance 与 workflow 写法，再说明装配语义；重构保持关系的源码可见性与可提取性。同步实际接口、示例与设计说明，目标接口标明未实现；详见[代码即文档](docs/LATEST_DESIGN.md#code-as-documentation)。
- 程序只有 workflow 入口，保持 `main = interpreter ast effects`；不提供绕过 AST 的单末端业务入口。
- Handlers 在生成前保持原生 Haskell。先生成同步的契约接口，再写 instance；手写和 Generated/Handlers 分别加载，避免重复 instance。
- handler 是不带参数的原子类方法，写作 `instance XxxLayer m => XxxHandler m`：按表示类型 `require`，挂接的 parser 用 `raw`，失败用本 handler 的 `raise`。一个 handler 可注册到多个 effect。Input 前驱与 `requests` 驱动由 gencode 装配进 effect 入口；方法体不调用上游、其他 handler 或 effect 方法，SDK 不补跑未声明的上游。
- 业务模块顶层只允许类型声明、instance、`effects`、具名 AST 与 `main`，禁止顶层普通函数；值操作写在 handler 方法体内，方法体内的局部函数与 lambda 不限制。规则见 [ASSETS](docs/ASSETS.md)。
- 每个 refined asset 对应固定表示 ADT 和唯一 Context 来源；同一资产可声明多种合法访问方式，一个消费者可依赖多个资产。读取按“表示类型 + effect”路由到唯一资产，一个 effect 内表示类型不重复，见[资产来源与访问约束](docs/LATEST_DESIGN.md#demand-contract)；不新增位置参数或提前取值。
- Error 只指向 scope：`RaisedBy` 写 handler 名，必须关联恰好一个 scope；resolve 暂不操作 scope（Error 驱动链待定）。
- Context 通过 demands 接入。区分 original chain、Context chain、静态 NodeId、运行 Origin／ActivationId 与 Binding ownership。
- 取值的捕获、来源可见性、缺值等待（require 不生产）、资源认领和 once-spare 保证不能在重构中弱化。完整规则按下表阅读，不在本文件复制协议。
- gen 是这个 EDSL 的编译器。SDK 分为源语言（`Framework/Language/`）、gen（`Framework/Gen/`）、编译产物（`Framework/Prototype/`、Generated）与运行时（`Framework/Runtime/`）四层，依赖只从上往下：gen 不导入运行时，运行时不导入 gen。能在生成期判定的组合、读取路由与合法性问题由 gen 报错，不留给运行时；新增检查放进流水线的对应阶段，见 [gen 是编译器](docs/LATEST_DESIGN.md#compiler)与[编译流水线](docs/LATEST_DESIGN.md#generation)。
- Prototype 是纯结构，RuntimeGraph 保存活动关系，ScopeTree 独立且无环。生成、执行、展示共享同一静态模型。
- Generated 是派生产物；修改手写输入后显式生成，不在构建中隐式修改源码，不把手改生成结果当作持久权威。
- 当前实现六类 effect（含 Stream）与 lifelong。lifelong 中的失败采用临时规则（终止整次运行）；EOF、Stream close、局部结束等延期项不得描述成已提供的能力。本轮已完成输入契约及 SDK 分工整理（Stage 1）与 handler 复用（Stage 2）；Pure 的值管道语义、Stream 的驱动方式（event／behavior／socket）与 Error 的驱动链待定，持续执行同构、资产访问、scope 边界、结束与清理仍按阶段确认；Middleware 保留为后续专题，均不得写成当前能力。

## 按任务读取规范

| 任务 | 必须读取 |
| --- | --- |
| 改注册、方法签名或 beforegen | [设计方法](docs/LATEST_DESIGN.md#principles)、[运行语义：注册](docs/LATEST_DESIGN.md#registration)、[指南](docs/GUIDE.md) |
| 改 requests／require／raw／注入 | [运行语义：Context](docs/LATEST_DESIGN.md#context)、[入口装配](docs/LATEST_DESIGN.md#calls)、[图与来源](docs/EFFECT_GRAPH.md) |
| 改 branch 或启动 | [运行语义：workflow](docs/LATEST_DESIGN.md#workflow)、[图与身份](docs/EFFECT_GRAPH.md) |
| 改 scope、归属、cleanup 或 Error | [运行语义：scope](docs/LATEST_DESIGN.md#scope)、[Error](docs/LATEST_DESIGN.md#error)、[ScopeTree](docs/EFFECT_GRAPH.md) |
| 改 gen：流水线阶段、结构、缓存或资产检查 | [gen 是编译器](docs/LATEST_DESIGN.md#compiler)、[编译流水线](docs/LATEST_DESIGN.md#generation)、[图与生成](docs/EFFECT_GRAPH.md)、[资产约束](docs/ASSETS.md) |
| 改 Stream／lifelong | [主设计第 7 章](docs/LATEST_DESIGN.md#stream)、[完整规范](docs/STREAM_LIFELONG.md)、[Next stages](docs/NEXT_STAGES.md)，以及将修改的当前协议 |
| 设计持续执行的结束与清理 | [六阶段计划](docs/NEXT_STAGES.md#stages)、[主设计第 7 章](docs/LATEST_DESIGN.md#stream)、[运行语义：scope](docs/LATEST_DESIGN.md#scope) |
| 设计 Middleware 与 Hanging | [后续专题](docs/NEXT_STAGES.md#middleware)、[Root 入口包装](docs/LATEST_DESIGN.md#calls) |
| 修改文档 | [文档职责与维护规则](docs/LATEST_DESIGN.md#documents)，只在所属专题维护详细规范 |

## 源码定位

| 范围 | 入口 |
| --- | --- |
| 源语言：手写业务门面、注册、AST、handler 能力类与历史视图 | [SDK.hs](sdk/Framework/SDK.hs)、[Registration](sdk/Framework/Language/Registration.hs)、[AST](sdk/Framework/Language/AST.hs)、[Handler](sdk/Framework/Language/Handler.hs)、[History](sdk/Framework/Language/History.hs) |
| gen 流水线与命令行 | [Gen.hs](sdk/Framework/Gen.hs)、[Main](sdk/Framework/Gen/Main.hs) |
| gen：读取、降级、资产来源规则与派生名字 | [Source](sdk/Framework/Gen/Source.hs)、[Lower](sdk/Framework/Gen/Lower.hs)、[Demand](sdk/Framework/Gen/Demand.hs)、[Names](sdk/Framework/Gen/Names.hs) |
| gen：绑定、方法体形状与组成 | [Bind](sdk/Framework/Gen/Bind.hs)、[Shape](sdk/Framework/Gen/Shape.hs) |
| gen：构图与来源证明 | [Build](sdk/Framework/Gen/Build.hs)、[Build/Graph](sdk/Framework/Gen/Build/Graph.hs)、[Build/Sources](sdk/Framework/Gen/Build/Sources.hs) |
| gen：输出与类检 | [Emit/Effects](sdk/Framework/Gen/Emit/Effects.hs)、[Emit/Handlers](sdk/Framework/Gen/Emit/Handlers.hs)、[Emit/Program](sdk/Framework/Gen/Emit/Program.hs)、[Emit/Prototype](sdk/Framework/Gen/Emit/Prototype.hs)、[Assets](sdk/Framework/Gen/Assets.hs)、[Catalog](sdk/Framework/Gen/Catalog.hs) |
| 编译产物：Prototype 模型、查询、校验与展示 | [Prototype.hs](sdk/Framework/Prototype.hs)、[Types](sdk/Framework/Prototype/Types.hs)、[Graph](sdk/Framework/Prototype/Graph.hs)、[Query](sdk/Framework/Prototype/Query.hs)、[Validate](sdk/Framework/Prototype/Validate.hs)、[Structure](sdk/Framework/Prototype/Structure.hs) |
| 生成代码门面与运行入口 | [Generated.hs](sdk/Framework/Generated.hs)、[Program.hs](sdk/Framework/Program.hs) |
| 运行时：协议、Context 与绑定 | [Protocol](sdk/Framework/Runtime/Protocol.hs)、[Context](sdk/Framework/Runtime/Context.hs)、[Binding](sdk/Framework/Runtime/Binding.hs) |
| 运行时：实际执行、运行身份与图 | [App](sdk/Framework/Runtime/App.hs)、[Identity](sdk/Framework/Runtime/Identity.hs)、[Graph](sdk/Framework/Runtime/Graph.hs) |
| 运行时：scope | [Scope](sdk/Framework/Runtime/Scope.hs) |
| 运行时：执行 algebra、会话与单元调度 | [Execution](sdk/Framework/Runtime/Execution.hs)、[Runtime.hs](sdk/Framework/Runtime.hs)、[Session](sdk/Framework/Runtime/Session.hs) |

完整目录与阅读路线见[主设计：SDK 分工](docs/LATEST_DESIGN.md#sdk-layout)。

## 完成工作时

检查改动影响的当前协议和生成产物；按现有约定进行必要编译。更新所属规范与 Next stages 状态，必要的完成日期、验证结果和未覆盖范围写入 [Next stages](docs/NEXT_STAGES.md#maintenance)。最终说明改了什么、实际验证了什么，以及仍未覆盖的边界。

日常操作和生成命令见 [GUIDE](docs/GUIDE.md)。规范之间有冲突时，以用户已确认的语义重新核对并修正文档，不凭标题“最新”、旧样例或偶然时序作决定。
