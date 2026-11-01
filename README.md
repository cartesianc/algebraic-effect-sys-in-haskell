# Algebraic Effect Sys in Haskell

## Abstract

一个用原生 Haskell 表达、分析和执行业务组合的 effect 框架。程序以类型、注册和 workflow 描述结构，由 handler 实现原子操作，SDK 完成静态检查、装配与运行。

## Introduction

项目关注业务代码的组织方式：让操作关系、资产依赖和启动方式直接体现在源码中，便于开发者和工具阅读、检查与维护。设计围绕三个原则展开。

**声明式组合，原子化实现。** 资产、能力与 workflow 关系通过固定声明表达，原生 handler 实现具体行为，SDK 据此校验、装配和执行。详见[声明式设计](docs/LATEST_DESIGN.md#declarative-design)。

**代码即文档，文档即代码。** 代码的书写形态就是架构的一部分。设计、源码与示例应保持对应，让人和工具都能沿代码理解程序。详见[核心设计原则](docs/LATEST_DESIGN.md#code-as-documentation)。

**句柄操作和值操作分离。** 句柄组织可执行操作及其组合，资产契约表达业务数据及取值关系，workflow 决定何时启动。两者通过显式声明衔接，详见[句柄与值的分工](docs/LATEST_DESIGN.md#handles-and-values)。

项目目前处于接口探索阶段。现有示例可以运行，包括持续执行的 StreamDemo；进度和开放项见 [TODO](docs/TODO.md)。

<a id="code-shape"></a>
## 代码长什么样

程序入口可以概括为：

```haskell
main = interpreter ast effects
```

`ast` 描述 workflow，`effects` 声明操作及其关系，`interpreter` 将它们装配并运行。

从[安装与运行](docs/GUIDE.md#quickstart)可以准备环境并启动现有示例。开发过程中，生成代码、编译、运行业务和查看结构分别承担不同职责；[命令行与执行阶段](docs/GUIDE.md#commands)沿这条流程说明各入口的用途与启动方式。

## 基础组件

| 组件 | 负责什么 |
| --- | --- |
| [Asset（资产）](docs/GUIDE.md#types) | 以 Haskell ADT 与契约表达跨操作传递的业务数据。 |
| [Effect](docs/GUIDE.md#effects) | 声明操作的类别、可用的上游能力，以及所需资产。 |
| [Handler](docs/GUIDE.md#handlers) | 用原生 instance 方法实现操作、解析和显式调用。 |
| [Workflow／AST](docs/GUIDE.md#workflow) | 选择完整操作链的末端，规定这些链如何顺序、并行或按条件启动。 |

Effect 声明操作与依赖关系，handler 实现具体行为，asset 连接生产与消费，workflow 组织执行。

进入[使用指南：代码长什么样](docs/GUIDE.md#code-shape)，通过同一个例子展开各组件的 Haskell 写法；完整 Main 和导入关系见[运行入口](docs/GUIDE.md#运行入口mainhs)。

## 开发与维护

修改业务程序时，可以沿[使用指南](docs/GUIDE.md#development)中的编写顺序完成声明、原子实现与生成。需要理解这些代码为什么这样组织时，[主设计](docs/LATEST_DESIGN.md)说明架构原则和当前协议，并在对应章节连接资产约束、图结构与持续执行的详细规范。

参与 SDK 开发或让代码生成工具进入仓库时，[开发约定](AGENTS.md)说明需要保持的架构边界、阅读路径与变更要求。它与设计文档、可执行示例共同约束后续修改，使代码形态和运行语义保持对应。

## License

[BSD-3-Clause](LICENSE)
