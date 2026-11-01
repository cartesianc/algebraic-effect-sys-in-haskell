# 实施计划与开放事项

更新：2026-11-01。本文件跟踪实施顺序、开放项与必要完成摘要；规范从[主设计](LATEST_DESIGN.md)进入。

| 阶段 | 状态 | 资料 |
| --- | --- | --- |
| Stage 1：Prototype 与 RuntimeGraph | 已实现 | [规范](EFFECT_GRAPH.md)、[历史验收](TODO.md#completed) |
| Stage 2：来源可见性与求值锁，以及 ownership／分析复杂度修复 | 已实现；外部穷举模型未完成 | [规范](EFFECT_GRAPH.md)、[历史验收](TODO.md#completed) |
| Stage 3：Stream 与 lifelong | 设计已确定，实现未开始 | [规范](STREAM_LIFELONG.md)、下列实施批次 |

## Stage 3：Stream 与 lifelong（依赖 Stage 2）

**状态**：2026-11-01 已整理设计规范；SDK 实现尚未开始。权威规则见 [Stream 与 lifelong](STREAM_LIFELONG.md)，本节取代旧的“方法体 stream @T 每调用一次领取一条”方案。

### 规范入口

Stream 是[主设计第 7 章](LATEST_DESIGN.md#stream)的一部分。角色匹配、BootPlan、消费合法性、调度、历史和失败协议只在 [STREAM_LIFELONG](STREAM_LIFELONG.md) 维护，本计划不复制规则清单。

### 实施批次

- [x] 3.0 手工整理匹配规则、设计核心与文档入口；标明设计和实现状态。
- [ ] 3.1 资产身份／固定方法名重构；迁移五个 demo，记录外部工具接口影响。
- [ ] 3.2 Stream 与 Context 契约、History、parser 专属输入能力、beforegen 接口。
- [ ] 3.3 消费摘要、BootPlan、启动／可见性检查、缓存和 --structure。
- [ ] 3.4 发布记录、会话、独立游标、frame、捕获与观察路由。
- [ ] 3.5 回调调度、控制流推进、失败监督与受控取消。
- [ ] 3.6 生成结果、最小示例和使用文档同步。

### 验收与延期

按现有约定做必要普通编译、生成结果审阅和示例观察，不新增测试框架、负例或穷举门槛。核对三种 boot 依据、无重复生产／发布、同源独立消费、frame 隔离、提前到达／并发通知、观察故障和任务所有权。完整场景见专题文档。

EOF／Done、Stream close、历史资源精细回收、嵌套 lifelong、自动重试、周期声明、背压及通用外部 push callback 注册延期，不列为本版开工前必须补齐的能力。持续示例通过失败或外部取消结束；有限 require 启动的持续会话由 interpreter 托管至退出。LSP 仓库的穷举模型另行扩展。


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

- [ ] Stage 2 原 2.7：在 LSP 仓库建立运行时语义模型，枚举小规模 AST／交错，核对静态来源与实际读取；本仓库未完成这种穷举，也不新增测试门槛。
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
