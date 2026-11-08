# Algebraic Effect Sys in Haskell

这是一个用原生 Haskell 描述、检查和执行业务组合的 effect 框架。业务数据用类型表达，操作及依赖关系写进声明，具体行为由 handler 实现，workflow 组织这些操作链的启动。

开发者编写的是有固定结构的 Haskell 程序。SDK 的生成器是这门嵌入式语言的编译器：它从声明和 handler 的读取中提取组合关系，在生成期检查并定下链的组合与数据来源，输出可阅读的契约与执行代码，再由 interpreter 装配和运行。

## 能用它做什么

你可以把文件操作、网页抓取等业务组织成可复用的操作链，再用 workflow 安排顺序执行、并行执行和按业务状态选择分支。对于持续输入，也可以由资产更新驱动消费链反复执行。这些组合的代码形态见[workflow 指南](docs/GUIDE.md#workflow)，持续执行的例子见[Stream 指南](docs/GUIDE.md#stream)。

框架还提供资产依赖与来源检查、资源共享和自动清理，以及失败检测与处置，让业务方法沿用统一的取值和资源管理协议。具体保证见[运行时行为](docs/GUIDE.md#runtime-behavior)。项目目前处于接口探索阶段，现有示例可以运行；已有基础、开放问题和下一轮计划记录在 [Next stages](docs/NEXT_STAGES.md) 中；本轮从 Stream 与 lifelong 的共同执行结构出发，分阶段收敛输入契约、资产访问、结束与资源清理。

## 为什么这样设计

业务组合扩大后，开发者需要看清操作之间的关系、数据从哪里来，以及哪些模块会被启动。因此，框架采用[声明式组合与原子实现](docs/LATEST_DESIGN.md#declarative-design)：把组合关系写成固定声明，让[生成器作为编译器](docs/LATEST_DESIGN.md#compiler)检查和装配，问题在生成期报告，不留到运行时；具体 IO、解析与计算由原生 Haskell 的原子 handler 完成，同一个 handler 可以服务多条业务链。

操作调用和业务数据也需要各自清楚的表达方式。[句柄操作和值操作分离](docs/LATEST_DESIGN.md#handles-and-values)，让前驱描述操作按什么顺序组合，让资产描述产生什么数据、怎样读取。阅读一段业务时，可以分别追踪前驱关系和数据依赖。

这些关系直接体现在源码中，就是[代码即文档，文档即代码](docs/LATEST_DESIGN.md#code-as-documentation)的含义：设计说明给出实际的 Haskell 写法，示例与实现保持对应。原生类型、类方法和 instance 让开发者与 HLS 能理解这份代码；明确的结构与局部契约也让代码生成工具和 agent 有据可循。

<a id="code-shape"></a>
## 代码长什么样

程序入口可以概括为：

```haskell
main = interpreter ast effects
```

`ast` 描述 workflow，`effects` 声明操作及其关系，`interpreter` 将它们装配并运行。入口背后有四个基本组件：

| 组件 | 负责什么 |
| --- | --- |
| [Asset（资产）](docs/GUIDE.md#types) | 用 Haskell ADT 表达跨操作传递的业务数据，按名字细化成各自来源的资产。 |
| [Effect](docs/GUIDE.md#effects) | 声明操作的类别、绑定的 handler、前驱，以及驱动或读取的资产。 |
| [Handler](docs/GUIDE.md#handlers) | 用原生类方法实现原子的读取、解析和 IO，可以注册到多个 effect。 |
| [Workflow／AST](docs/GUIDE.md#workflow) | 选择完整操作链的末端，规定这些链何时、以什么方式启动。 |

Effect 声明操作与依赖关系，handler 实现具体行为，asset 连接生产与消费，workflow 组织执行。[使用指南](docs/GUIDE.md#code-shape)用同一个文件操作例子展开这些组件，展示它们分别写在哪个文件、怎样连接成一个程序。

## 从哪里开始

### 运行一个示例

从[安装与运行](docs/GUIDE.md#quickstart)准备环境，运行已有示例，再沿指南查看对应源码。

### 了解各个命令的用途

生成代码、编译、运行业务和查看结构是开发过程中的不同步骤。[命令行与执行阶段](docs/GUIDE.md#commands)说明每种入口的用途和具体用法。

### 编写自己的程序

按[开发流程](docs/GUIDE.md#development)逐步完成声明、handler 与 workflow。

### 理解框架设计

[主设计](docs/LATEST_DESIGN.md)从代码形态进入运行协议，说明各层如何配合，并在相关章节连接资产约束、图结构和持续执行的详细规范。

### 参与 SDK 开发

修改 SDK 或让 agent 进入仓库工作时，从[开发约定](AGENTS.md)按任务定位要读的设计和源码，使后续改动继续保持代码形态与运行语义的一致。

## 许可证

[BSD-3-Clause](LICENSE)
