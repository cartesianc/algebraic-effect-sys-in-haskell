# 实施计划与开放事项

更新：2026-11-01。本文件跟踪实施顺序、开放项与必要完成摘要；规范从[主设计](LATEST_DESIGN.md)进入。

| 阶段 | 状态 | 资料 |
| --- | --- | --- |
| Stage 1：Prototype 与 RuntimeGraph | 已实现 | [规范](EFFECT_GRAPH.md)、[历史验收](TODO.md#completed) |
| Stage 2：来源可见性与求值锁，以及 ownership／分析复杂度修复 | 已实现；外部穷举验证已在 LSP 仓库完成 | [规范](EFFECT_GRAPH.md)、[历史验收](TODO.md#completed) |
| Stage 3：Stream 与 lifelong | 已实现；lifelong 失败暂用临时规则 | [规范](STREAM_LIFELONG.md)、[实施记录](TODO.md#stage-3-record) |

## Stage 3：Stream 与 lifelong（依赖 Stage 2）

**状态**：2026-11-01 已实现（分支 `stage3-stream-lifelong`）。权威规则见 [Stream 与 lifelong](STREAM_LIFELONG.md)，写法见[使用指南第五节](GUIDE.md#stream)。本节取代旧的“方法体 stream @T 每调用一次领取一条”方案。

设计规范在实现前按用户确认作了三处修订，已写入规范：去掉“观察原链”（ObserveOrigin），只保留 Receive 与 RepeatRequest；`History` 读取类型由生产方注册（`stream = Just ()`）决定，不由消费方的 `streams` 决定；lifelong 中的失败在 close 语义设计前按临时规则终止整次运行。

### 规范入口

Stream 是[主设计第 7 章](LATEST_DESIGN.md#stream)的一部分。角色匹配、BootPlan、消费合法性、调度、历史和失败协议只在 [STREAM_LIFELONG](STREAM_LIFELONG.md) 维护，本计划不复制规则清单。

### 实施批次

- [x] 3.0 手工整理匹配规则、设计核心与文档入口；标明设计和实现状态。
- [x] 3.1 资产身份／固定方法名重构（`namedAsset`、`getT`／`readT`）；迁移五个 demo。外部工具需按新的 Context 字段（`asset`、`request`、`require`、`stream`）读取注册。
- [x] 3.2 Stream typing、Context 的 stream 角色与匹配表、`streams`、History 读取类型、parser 专属的 `inputT`。
- [x] 3.3 lifelong 构造、单元／订阅／会话的原型表示、合法性与启动依赖检查、`--structure` 展示。
- [x] 3.4 会话、完整历史、游标、frame、交付视图交接、interpreter 托管的会话与 `FromSession` 来源。
- [x] 3.5 单元调度与就绪检查、frame 内一次领取、显式 request 进入会话、临时失败规则与取消。
- [x] 3.6 StreamDemo 示例；会话跨步骤保持生产资源；文档同步。

### 延期

EOF／Done、Stream close、lifelong 的局部结束（当前由临时规则代替）、历史资源精细回收、嵌套 lifelong、多个持续来源组合触发、自动重试、周期声明、背压及通用外部 push callback 注册延期。持续示例通过失败或外部取消结束；有限 require 启动的持续会话由 interpreter 托管至退出。

<a id="stage-3-record"></a>
### 实施记录（2026-11-01）

每批完成后执行：`cabal build all`；重新生成六个程序（五个原有 demo 与 StreamDemo）并审阅生成差异；五个原有 demo 均返回 `Succ`（Crawler 需要网络）；LSP 仓库的可见性穷举回归计数与基线一致。以下场景在临时探针程序或 StreamDemo 上观察过，探针未加入仓库：

- 生成期：九种 Context／Stream 角色组合按匹配表接受或拒绝；lifelong 的嵌套、空分支、外部 `streams`、零个／多个订阅、读取其他持续资产、启动依赖均给出对应诊断；在解析器之外调用 `inputT` 被 GHC 拒绝。
- lifelong 外的有限读取：首次读取等到一条交付，同一调用内重读视图不变；后继节点看到更长的历史；请求序列资产按普通 require 取得单值；Stream 的生产失败以原失败结束程序。
- 游标：相等值两条、每次交付一条、两个单元各自推进、积压立即交付、会话失败唤醒等待方。
- lifelong：同一 frame 中 chained 的两个节点看到同一份视图；快慢两个单元独立推进且不丢条；alternative 单元每个 frame 重新选择并共享交付；显式 request 使本次视图增加一条；单元失败、并行的有限兄弟失败、会话解析失败都立即以原失败结束整次运行。
- 资源：Stream 方法每步打开的无参 scope 在会话内只打开一次，退出时关闭一次。
- 取消：StreamDemo 运行中发送中断（Windows Ctrl-Break），会话与单元停止，退出清理关闭传感器连接。

未覆盖：没有并发交错的系统性枚举；没有长时间运行的内存观察（完整历史按设计持续增长）；LSP 仓库的穷举模型尚未扩展到 Stream／lifelong；Ctrl-C 只在 Windows 上以 Ctrl-Break 方式验证。


## 其余开放设计

以下不作为 Stage 3 本版开工前提，进入对应专题时另行确认接口和保证：

- Pure 的语义及 IO 限制。过去的 Local／Body 候选尚未定案，当前仍使用统一 raise。
- Generic Map 的适配范围、失败接口与接入；当前没有可用自动适配。
- 独立 Middleware typing 与 Hanging；不沿用旧 loop 说明代替 lifelong 规范。
- 同一 handler／Scoped 注册服务多种细化类型；需一起调整 ScopeTree 身份、运行实例、绑定与 Error 导航。
- 多方法 effect 的入口与结果契约、独立生成模块的组合、跨语言 schema。
- 其他 cleanup policy、Linear 关闭凭证、任意逸出资源跟踪、未发布的部分获取恢复、跨独立 interpreter 存续。
- 已展开 continuation 的恢复、跨调用诊断范围；Error 处置成功当前仍传播原失败。

## 外部工具与后续验证

- [x] Stage 2 原 2.7：LSP 仓库的 `verify/visibility` 建立了独立的运行语义模型，穷举小规模 AST 与契约组合，并以真实 `buildPrototype` 核对静态来源；包含变异自检。2026-11-01 基线：一层 9,222、两层 209,480、三层 43,800、alternative 7,688 个程序及 50,000 个随机程序，均为“接受且一致”或“拒绝且有依据”，没有不一致。本仓库不新增测试门槛。
- [ ] 将上述穷举模型扩展到 Stream／lifelong（订阅、会话可见性与单元划分）。
- [ ] 外部 LSP 按自身需要消费 SDK 原型与诊断；协议和展示格式在工具侧设计，不为其增加 SDK 专用导出。
- [ ] 读取点来源、资产细化建议及模块引用索引的可视化。

完成批次后更新规范的实现状态和使用指南，将实际执行过的命令、日期及未覆盖范围记入本文件的完成摘要。


<a id="completed"></a>
## 已完成阶段与验证摘要

以下是 2026-10-31 的记录，本次文档整理没有重新执行这些命令。

- Stage 1/2、runtime graph 与 scope ownership 修复已完成。既有普通编译 `cabal build all`、五个 demo、结构展示及生成检查通过；五个 demo 返回 Succ。
- ownership 修复的普通回归通过，仍没有并发认领／使用交接的专项执行覆盖，也没有并发交错穷举。示例中的资源计数只是当次观察，不是所有调度下固定计数的保证。
- 来源分析裁剪修复通过 `cabal build all --offline`；五个 demo 重新生成，文本保持一致。该轮没有运行 demo 业务、没有性能实测；相关契约的组合仍可能产生指数状态，未宣称整体线性复杂度。
- Stage 2 外部穷举模型未完成，继续由上方任务跟踪。历史结果不扩大当前协议的保证范围。
