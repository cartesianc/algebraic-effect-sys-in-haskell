# myframework

myframework 是一套使用 Haskell 实现的可序列化 EDSL、Effect 编译器和运行时。

## 从这里开始

按你的目标选择文档：

| 目标 | 文档 |
|---|---|
| 第一次运行项目、编写业务程序 | [使用入门](docs/GETTING_STARTED.zh.md) |
| 开发 AST、Effect、interpreter、runtime、diagnosis | [框架开发者指南](docs/DEVELOPER_GUIDE.zh.md) |
| 查看长期冻结的语义边界 | [L0 框架合同](docs/L0_EFFECT_LOOP_BOOTLOADER_SEMANTICS.zh.md) |
| 查看 Runtime 专题 | [Runtime](docs/RUNTIME.md) |
| 查看 TrustBase | [TrustBase](docs/TRUST_BASE.md) |
| 查看 SDK 生成 | [SDK Source Artifact](docs/SDK_SOURCE_ARTIFACT.md) |
| 查看自举 gate | [Self-bootstrap Gate](docs/SELF_BOOTSTRAP_GATE.md) |

使用文档、框架内部文档和 L0 合同承担不同职责。L0 文件路径长期保持稳定，并通过
版本号持续迭代。

## 当前状态

当前 `0.2.0.0` 业务 Facade 支持：

- import MyFramework 单一业务入口；
- schema-free typed R、command 和 MAP；
- `command $ MAP $ R` Application；
- 模块化 chain、parallel、fallback、race；
- C/U/R/D/E/MAP 统一 EffectRegistry；
- SurfaceProgram 到 ElaboratedProgram 的确定性 schema 求解；
- 独立 AST、InputGraph、ValueGraph；
- versioned Handler codec adapter；
- canonical SchemaCatalog 和 SHA-256 digest；
- defunctionalized ContinuationPlan；
- 四态 Input CPS、ValueGraph 值求解和统一 v5.2 Runtime；
- `BootRunId + AstPath + EffectRef` execution identity 与 occurrence single-flight。
- first-class `EffSysRef`、Scoped EffSys IR/live view/deterministic snapshot 和只读查询。

L0 v5.2 后续阶段继续实现：

- hanging middleware observation；
- callback PipelinePatch；
- Loop 完整状态反馈。

旧 `ReferencedProgram` 表面位于 `MyFramework.Legacy.*`，用于 v2 artifact 的显式迁移。
状态矩阵位于 L0 第 17 节。

## 构建

    stack --work-dir .stack-work-codex build

运行公开 Facade 爬虫示例：

    stack --work-dir .stack-work-codex exec crawler-facade-witness

运行主要局部 witness：

    stack --work-dir .stack-work-codex exec curde-semantics-witness
    stack --work-dir .stack-work-codex exec schema-elaboration-witness
    stack --work-dir .stack-work-codex exec effect-application-witness
    stack --work-dir .stack-work-codex exec facade-v52-witness
    stack --work-dir .stack-work-codex exec curde-runtime-witness
    .\scripts\check-ast-execution-boundary.ps1

普通 release pre-gate：

    .\scripts\check-release.ps1

Self-artifact 和 promotion 属于候选 core 发布流程。普通开发迭代不运行 promotion。

## 仓库边界

- myframework：语义源码、Runtime、TrustBase 和 SDK lowering；
- dsl-bootstrap：迁移参考和历史行为 oracle；
- dsl-sdk：生成产物。

业务代码只导入 MyFramework。Handler 实现、Runtime hooks、TrustBase 和 SDK
materializer 使用各自维护入口。

## 发布关系

    current core0
      -> FrameworkAsBusiness / core1
      -> core2 candidate
      -> semantic and artifact fixed points
      -> explicit approval
      -> next core0

通过 validation 或 self-artifact gate 只会生成证据。current core 的切换需要维护者
显式批准。
