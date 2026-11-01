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
- facade／Handlers 在生成前保持原生 Haskell。先生成同步的契约接口，再写 instance；手写和 Generated/Handlers 分别加载，避免重复 instance。
- 业务 instance 写作 `instance XInputs m => XEffect m`。Input 提供能力，方法体显式调用；SDK 不补跑未引用的上游。
- effect 调用和显式资产操作写在注册 instance 方法中。普通函数、局部具名函数、泛型例外和构造器归属遵循 [ASSETS](docs/ASSETS.md)，不恢复旧的“全面禁止普通函数”规则。
- Context 通过 demands 接入。区分 original chain、Context chain、静态 NodeId、运行 Origin／ActivationId 与 Binding ownership。
- 取值的捕获、来源可见性、fallback 发布、资源认领和 once-spare 保证不能在重构中弱化。完整规则按下表阅读，不在本文件复制协议。
- Prototype 是纯结构，RuntimeGraph 保存活动关系，ScopeTree 独立且无环。生成、执行、展示共享同一静态模型。
- Generated 是派生产物；修改手写输入后显式生成，不在构建中隐式修改源码，不把手改生成结果当作持久权威。
- 当前实现六类 effect（含 Stream）与 lifelong。lifelong 中的失败采用临时规则（终止整次运行）；EOF、Stream close、局部结束等延期项不得描述成已提供的能力。

## 按任务读取规范

| 任务 | 必须读取 |
| --- | --- |
| 改注册、方法签名或 beforegen | [设计方法](docs/LATEST_DESIGN.md#principles)、[运行语义：注册](docs/LATEST_DESIGN.md#registration)、[指南](docs/GUIDE.md) |
| 改 request／require／注入 | [运行语义：Context](docs/LATEST_DESIGN.md#context)、[图与来源](docs/EFFECT_GRAPH.md) |
| 改 branch 或启动 | [运行语义：workflow](docs/LATEST_DESIGN.md#workflow)、[图与身份](docs/EFFECT_GRAPH.md) |
| 改 scope、归属、cleanup 或 Error | [运行语义：scope](docs/LATEST_DESIGN.md#scope)、[Error](docs/LATEST_DESIGN.md#error)、[ScopeTree](docs/EFFECT_GRAPH.md) |
| 改 codegen、结构、缓存或资产检查 | [图与生成](docs/EFFECT_GRAPH.md)、[资产约束](docs/ASSETS.md)、[运行语义：生成](docs/LATEST_DESIGN.md#generation) |
| 改 Stream／lifelong | [主设计第 7 章](docs/LATEST_DESIGN.md#stream)、[完整规范](docs/STREAM_LIFELONG.md)、[TODO](docs/TODO.md)，以及将修改的当前协议 |
| 修改文档 | [文档职责与维护规则](docs/LATEST_DESIGN.md#documents)，只在所属专题维护详细规范 |

## 源码定位

| 范围 | 入口 |
| --- | --- |
| 公共入口、原型核对与运行 | [SDK.hs](sdk/Framework/SDK.hs) |
| 注册和契约 | [Registration.hs](sdk/Framework/Effect/Registration.hs)、[Contract.hs](sdk/Framework/Effect/Contract.hs) |
| 静态原型、来源分析 | [Prototype.hs](sdk/Framework/Prototype.hs) |
| AST 与执行 algebra | [AST.hs](sdk/Framework/Workflow/AST.hs)、[Execution.hs](sdk/Framework/Workflow/Execution.hs) |
| Context 与绑定 | [Context.hs](sdk/Framework/Effect/Context.hs)、[Binding.hs](sdk/Framework/Effect/Binding.hs) |
| 实际执行、运行身份与图 | [App.hs](sdk/Framework/Effect/Runtime/App.hs)、[Identity.hs](sdk/Framework/Effect/Runtime/Identity.hs)、[Graph.hs](sdk/Framework/Effect/Runtime/Graph.hs) |
| scope | [Scope.hs](sdk/Framework/Effect/Scope.hs) |
| 持续执行：历史视图、会话、单元调度 | [History.hs](sdk/Framework/Effect/History.hs)、[Session.hs](sdk/Framework/Effect/Runtime/Session.hs)、[Runtime.hs](sdk/Framework/Effect/Runtime.hs)、[Execution.hs](sdk/Framework/Workflow/Execution.hs) |
| 生成与源码提取 | [Generate.hs](sdk/Framework/Generate.hs)、[Codegen](sdk/Framework/Codegen.hs)、[Handlers](sdk/Framework/Codegen/Handlers.hs)、[Structure](sdk/Framework/Codegen/Structure.hs)、[Assets](sdk/Framework/Codegen/Assets.hs) |

## 完成工作时

检查改动影响的当前协议和生成产物；按现有约定进行必要编译。更新所属规范与 TODO 状态，必要的完成日期、验证结果和未覆盖范围写入 TODO。最终说明改了什么、实际验证了什么，以及仍未覆盖的边界。

日常操作和生成命令见 [GUIDE](docs/GUIDE.md)。规范之间有冲突时，以用户已确认的语义重新核对并修正文档，不凭标题“最新”、旧样例或偶然时序作决定。
