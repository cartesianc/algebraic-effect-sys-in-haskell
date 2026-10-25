# 实现对应与后续工作

[目录](README.md)中的文件定义最新目标设计，阅读架构时以文档为准。发布代码采用早期试验架构，本次发布范围为文档；源码和 core 记录保持各自的版本。

## 1. 区分发布代码与本地试验参考

| 层次 | 状态 |
|---|---|
| 最新设计 | 本目录描述的目标架构与接口，优先阅读 |
| 当前远端代码 | 本次文档发布基于 303ae9c，包版本为 0.1.0.0；源码保持原样 |
| 本地试验参考 | 355d7d0，包版本为 0.2.0.0，包含 CURDE/v5.2 探索，保留在本地开发历史 |

下表记录本地试验代码可供后续复用的基础。路径定位上述本地参考版本，阅读发布代码时应使用对应版本的文件清单。

| 源码 | 可以复用的基础 | 目标差异 |
|---|---|---|
| src/MyFramework/Effect.hs | EffectRef、EffectSpec、EffectIR | 该版采用 C/U/R/D/E/MAP，目标采用新分类与统一 Free 前台 |
| src/MyFramework/Handler/Adapter.hs | 宿主函数与 codec 适配 | 该版为 input → IO (Either String output)，目标 impl 通过具体 effect 的类方法获得依赖 |
| src/MyFramework/Graph.hs | AST/Input/Value 三种关系 | 需按句柄组合重新核对 input 的解释 |
| src/MyFramework/Ast.hs、Recursion.hs | Fix、cata 与控制构造 | 该版以 Fix/cata 为基础，ana/hylo 保留为扩展方向 |
| src/MyFramework/Runtime/V52.hs | 执行身份、结果、调度、清理 | 需衔接 handler 字典、bind 调用、资源协议与模块后端 |
| src/MyFramework/Hook.hs、Callback.hs、Loop.hs | 事件、回调、监听策略 | 需与新 scope/once 对齐 |
| src/MyFramework/Schema.hs、Elaboration.hs | 参数契约、解码与验证 | 可承接配置和插件装配 |

上述本地参考提供 cleanup 和去重机制。目标 once 的线性所有权接口、具体 effect 的存在封装与 handler 字典传递、统一注册及 listen/mock/stress/log/show 后端列入后续实现工作。

## 2. 建议实现顺序

以 [C5 可执行示例](effect-sample/README.md) 为起点的实施提案统一放在 [ROADMAP.md](ROADMAP.md)。路线划分三个可交付里程碑：同步语言内核、完整的进程内执行模型、带工具和配置启动的框架；各阶段列出交付物、通过条件与暂缓项。

优先验证异构类型连接、资源责任跨闭包传递、真实与测试实现的装配。最小执行身份和事件在控制结构阶段建立，随后接入资源、等待、并发、观察和配置。内部递归表示由实际控制场景确定，当前 C5 的闭包连接作为已有基线。

按改动选择类型检查、资源使用负例和运行测试。现有 witness 仅证明其实际覆盖的试验版合同。

## 3. 后续接口细节

这些内容保留思考空间，按已经确定的文件职责继续设计：

- 按 [CONSTRUCTION.md](CONSTRUCTION.md) 扩展注册契约、分类专用内容及默认值。
- 多个 impl 的具体绑定形式；C5 已支持一个 impl 按名称使用多个本层及祖先方法。
- 存在包、内部 EffectIO 调用环境及 impl 返回 effect 的封装接口。
- 多 scope 要求、借用接口、关闭失败处理。
- 参数及流式结果的就绪粒度。
- parallel 失败传播、取消策略；loop 变化判定、重入与合并。
- 嵌套错误范围、恢复与重试协议、针对单个 effect 的 help。
- 动态 hook、外部工具协议、配置与插件版本兼容。

内部通过 GADT、associated families 和存在封装组织具体 effect 及其类型类字典；前台在 Effect instance 中集中声明契约并实现 impl。C5 按 Typing 自动组装注册，Scope 保留显式生命周期配置。invoke 按 Exports/Input 自动选择方法提供者和资源，impl 通过 Context e 取得本次调用上下文。connect/applyBound 沿用函数闭包连接；当前实现与验证限于 Effect 层，AST 的接入继续单独设计。

## 4. 运行已发布的旧试验代码

```powershell
stack --work-dir .stack-work-codex build
stack --work-dir .stack-work-codex exec curde-semantics-witness
stack --work-dir .stack-work-codex exec curde-runtime-witness
```

crawler-facade-witness、schema-elaboration-witness、effect-application-witness、facade-v52-witness 和 semantic-closure-witness 适用于上述本地试验参考版本。

AST 执行边界与普通发布检查分别使用：

```powershell
.\scripts\check-ast-execution-boundary.ps1
.\scripts\check-release.ps1
```

这些命令运行旧试验实现，目标 API 的落地情况由新的实现记录说明。本次验证覆盖文档链接、示例关系、术语和格式。

## 5. 既有产物维护边界

自举、TrustBase 和 SDK 属于现有实现的维护体系，与业务注册接口分开：

- 构建工具链、封闭 HostKernel、可轮换 framework core 是三个不同信任边界。
- TrustBaseRef 保存可序列化的身份与摘要；BoundTrustBase 是运行时存在封装，由 HostKernel 核对并加载。
- SDK materialization 需要匹配的 core manifest、已批准 promotion 和 current pointer，并验证生成文件摘要。
- 语义自解释与产物固定点是独立验证义务；每轮记录对应其自身源码，新设计需要对应的实现与验证。
- 普通构建和验证生成相应证据；current core 的批准与切换属于单独的维护动作。

现有产物身份、历史与证据继续保存在 [trustbase](../../trustbase/README.md)，本次文档整理保留其原有内容。当前目标设计统一由本目录描述。
