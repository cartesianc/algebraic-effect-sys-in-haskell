# Algebraic Effect Sys in Haskell

用原生 Haskell 的声明与类型类组织业务：描述程序结构，实现原子操作，由框架完成装配与执行。

**代码即文档，文档即代码。** 代码的书写形态就是架构的一部分。设计、源码与示例应保持对应，让人和工具都能沿代码理解程序。详见[核心设计原则](docs/LATEST_DESIGN.md#code-as-documentation)。

**句柄操作和值操作分离。** 句柄组织可执行操作及其组合，Context 负责业务值的生产与解析，消费方按资产契约取值；workflow 决定何时启动。两者通过显式声明衔接，详见[句柄与值的分工](docs/LATEST_DESIGN.md#handles-and-values)。

项目目前处于接口探索阶段。现有示例可以运行，包括持续执行的 StreamDemo；进度和开放项见 [TODO](docs/TODO.md)。

<a id="code-shape"></a>
## 代码长什么样

程序入口可以概括为：

```haskell
main = interpreter ast effects
```

`ast` 描述 workflow，`effects` 声明操作及其关系，`interpreter` 将它们装配并运行。

## 基础组件

| 组件 | 负责什么 |
| --- | --- |
| [Asset（资产）](docs/GUIDE.md#types) | 以 Haskell ADT 与契约表达跨操作传递的业务数据。 |
| [Effect](docs/GUIDE.md#effects) | 声明操作的类别、可用的上游能力，以及所需资产。 |
| [Handler](docs/GUIDE.md#handlers) | 用原生 instance 方法实现操作、解析和显式调用。 |
| [Workflow／AST](docs/GUIDE.md#workflow) | 选择完整操作链的末端，规定这些链如何顺序、并行或按条件启动。 |

Context 是负责资产生产与解析的一类 effect：它的 handler 产生资产，消费方 handler 按声明的契约取用。持续数据可由 Stream effect 取得原始输入后经 Context 解析，也可由 Context request 重复生产；`lifelong` 在新数据到达时启动消费链（见[持续资产与 lifelong](docs/GUIDE.md#stream)）。Effect 声明关系，handler 实现行为，asset 连接生产与消费，workflow 组织执行。

进入[使用指南：代码长什么样](docs/GUIDE.md#code-shape)，通过同一个例子展开各组件的 Haskell 写法；完整 Main 和导入关系见[运行入口](docs/GUIDE.md#运行入口mainhs)。

## 继续阅读

- [安装与运行](docs/GUIDE.md#quickstart)：环境准备和首次运行。
- [命令行与执行阶段](docs/GUIDE.md#commands)：生成、编译、运行及结构查看的区别与用法。
- [使用指南](docs/GUIDE.md#code-shape)：代码形态、各模块的写法与开发流程。
- [主设计](docs/LATEST_DESIGN.md)：架构原则、语义与实现边界。
- [开发约定](AGENTS.md)：维护 SDK 或让 LLM 进入工作。
- [实施计划](docs/TODO.md)：当前阶段和未完成事项。

## License

[BSD-3-Clause](LICENSE)
