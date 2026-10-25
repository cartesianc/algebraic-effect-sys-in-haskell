# 设计目录

这是 myframework 当前目标设计的唯一入口。设计整理日期：2026-09-23。

**设计状态：本目录中的设计文档均为待定方案。** 本轮 review 入口是 [C5 完整示例](effect-sample/README.md)：Input 自动传播祖先句柄的 superclass 约束，统一 newtype 包装注册 GADT，通用 Result 表达 Succ/Pending/Failed 与成功时的可选业务值。Read/Map 采用可替换的示例策略，库连接实际执行闭包。源码注释说明定义、用途和使用位置。[C2 sample benchmark](OVERALL_REVIEW_BENCHMARK.md) 保留早期业务基线；当前 Effect 接口以 C5 为准。

**请优先阅读本目录理解最新设计。** 已发布代码保留早期试验实现。设计示例放在本目录内独立运行，与发布代码保持各自版本。

Effect 是可读的操作中间表示（IR）：在同一个 instance 中声明操作、依赖和 impl，以 Exports 公开本层类型类方法，用 AST 声明模块控制流。impl 按方法名调用，库沿约束链选择提供者和本次资源，并自动组装注册。当前候选方向是将 effect 连接为可执行闭包，以 AST 和闭包外围的 middleware 承载监听、mock、stress 和 log/show。具体 sample 验证这条连接路线；各专题文档按此路线逐项评审。

本文档中的接口是目标写法。已发布代码、本地试验参考与后续实现计划的区别，集中说明在 [IMPLEMENTATION.md](IMPLEMENTATION.md)。

从 C5 推进完整目标的实施提案见 [ROADMAP.md](ROADMAP.md)：按同步内核、进程内执行模型、工具与交付三个里程碑安排阶段，并列出验收场景和暂缓项。

## 文件分工

```text
docs/design/
├── README.md          目录、文件关系、总约定
├── QUICKSTART.md      简版：有什么功能、怎么用
├── EFFECT.md          注册字段、分类、身份与操作组合
├── CONSTRUCTION.md    GADT、newtype、自动 input 与闭包连接
├── IMPL.md            handler、instance、存在封装、impl 依赖注入
├── AST.md             模块控制流、read/map/require 参数表达式
├── HANGING.md         回调、等待、监听与恢复
├── RESOURCE.md        layer、scope、线性 once、错误范围
├── INTERPRETER.md     执行、模块观测、mock/stress、配置启动
├── ROADMAP.md         从 C5 到完整目标的阶段、验收与范围
├── OVERALL_REVIEW_BENCHMARK.md  具体 DSL sample、闭包展开、评审结论
├── effect-sample/             C5：自动 input、newtype 与通用 Result
│   ├── README.md              阅读顺序、定义关系、运行方式与边界
│   ├── Result.hs              独立的通用结果协议与显式读取
│   ├── Effect.hs              库：typeclass、GADT、字典、lowering
│   ├── FileEffects.hs         用户：Effect 契约与 impl、Handler 操作
│   ├── Program.hs             调用参数、Read/Map 与 sample 闭包
│   ├── Main.hs                命令行启动
│   └── checks/
│       ├── Checks.hs              Effect 层运行行为检查
│       ├── InheritanceChecks.hs   多态 superclass 与祖先资源验证
│       └── TypeChecks.ps1         类型约束的编译失败检查
├── benchmark/
│   ├── Sample.hs              使用者：注册、调用参数与 impl
│   ├── FileHandles.hs         提供者：数据与类方法 instance
│   ├── Library.hs             库：类型机制与 lowering
│   ├── ClosureSample.hs       启动、观察与固定案例
│   └── LOWERING.md            内部展开与实现边界
└── IMPLEMENTATION.md  源码对应、实现顺序、尚未定稿的细节
```

使用方式集中在 [QUICKSTART.md](QUICKSTART.md)，在 Effect instance 内声明关联数据并实现 impl，Scope 额外填写 scope。GADT、newtype、effect 函数、自动注册与 input 的原理集中在 [CONSTRUCTION.md](CONSTRUCTION.md)。完整设计按以下文件关系阅读。

| 文件 | 与其他文件的关系 |
|---|---|
| [EFFECT.md](EFFECT.md) | 定义公共 IR 字段与操作关系；构造见 CONSTRUCTION，handler/impl 见 IMPL，资源字段见 RESOURCE |
| [CONSTRUCTION.md](CONSTRUCTION.md) | 定义注册 GADT、newtype、自动 input 和 effect 入口，承接 EFFECT 的字段及 IMPL 的类型关系 |
| [IMPL.md](IMPL.md) | 定义类型类句柄、实例解释、存在封装和 impl；消费 AST 准备的参数及 RESOURCE 提供的能力 |
| [AST.md](AST.md) | 引用 EFFECT 构造节点，并规定主控制树 |
| [HANGING.md](HANGING.md) | 补充 AST 之外的事件入口，生命周期受 RESOURCE 约束 |
| [RESOURCE.md](RESOURCE.md) | 为 EFFECT、IMPL 和 HANGING 规定资源与错误边界 |
| [INTERPRETER.md](INTERPRETER.md) | 汇合上述文件，规定统一运行及外部工具接口 |
| [IMPLEMENTATION.md](IMPLEMENTATION.md) | 将上述目标映射到现有源码与后续工作 |
| [ROADMAP.md](ROADMAP.md) | 以 C5 为起点安排实施阶段、风险验证与完成标准 |
| [OVERALL_REVIEW_BENCHMARK.md](OVERALL_REVIEW_BENCHMARK.md) | 从 [Sample.hs](benchmark/Sample.hs) 的实际写法检查声明、句柄与 impl，以库的 lowering 和固定业务结果评审整体变化 |

## 全局约定

框架有五个组成部分：Effect、Implementation、AST、Hanging、Interpreter。资源规则横跨这些部件，因此单独成文。

| 关系 | 由什么表达 |
|---|---|
| 从原子句柄组合出更大的操作 | 单一 input |
| impl 接受哪份业务参数 ADT | require |
| 业务参数值从哪里来、怎样转换 | Read、Map、节点参数表达式 |
| 模块的顺序、并行、选择、监听 | AST 与 Hanging |
| 使用什么资源、由谁关闭 | layer、scope、线性 once |

前台在 Effect instance 内填写契约和 impl 方程。阅读顺序为 **注册契约与请求适配 → Handler 实现操作 → 调用处提供参数**。

Handler 的 operation 类方法由 instance 提供 ad-hoc 解释，Effect 的 impl 类方法提供请求适配。库根据分类生成注册 GADT，在内部 bind 字段中保存 impl 及所需字典；Input 的 superclass 关系传播祖先能力。库统一的 invoke 类方法从 Context e 推断当前 effect，按名称选择最近的提供者，再取得对应资源。Result 独立保存状态及可选业务值。

入口保持：

```haskell
main = interpreter ast effect
```

这是完整架构的入口目标，其中 effect 表示注册集合。C5 使用 compile 参数表达式 获得执行闭包；compile 和 Read/Map、资源出口统一在库内部调用 effect 取得注册。Handler 用一份 Signature 声明业务参数与原始结果。当前实现与验证限于 Effect 层，AST/Hanging 及配置装配继续单独设计。
