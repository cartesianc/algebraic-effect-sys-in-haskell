# Algebraic Effect Sys in Haskell

用 Haskell 的声明与类型类组织业务架构：effect 注册描述能力和资产依赖，workflow 决定启动方式，原子操作写在原生 `instance` 中。生成器产出契约、静态原型和协议包装，解释器统一执行。

**当前处于接口探索阶段。** 已实现有限 workflow、Context 取值、资源自动清理和 Error 诊断；Stream／lifelong 已完成设计，尚未实现。SDK 随仓库示例编译，暂未发布独立 Cabal library。

## 运行第一个示例

需要 **GHC 9.12.x** 和 Cabal；CI 使用 GHC **9.12.2**，生成器依赖该系列的解析器 API。确保 `ghc`、`ghci`、`runghc`、`cabal` 在 PATH 中。

```sh
git clone https://github.com/cartesianc/algebraic-effect-sys-in-haskell.git
cd algebraic-effect-sys-in-haskell
cabal update
cabal build all
cabal run file-demo
```

所有命令在仓库根目录执行。仓库已包含生成代码，首次运行无需先生成。

FileDemo 会创建或追加 `demo/FileDemo/output.txt`，根据文件是否已有内容选择写入方式，并自动关闭文件。只查看静态结构可运行：

```sh
cabal run file-demo -- --structure
```

接着读[使用指南：读懂 FileDemo](docs/GUIDE.md#read-example)，从末端节点追到注册与方法体。

## 代码写在哪里

```text
demo/<程序>/
  Types.hs          业务 ADT
  Effects.hs        effect 注册、Input 与 demands
  AST.hs            workflow 入口
  Workflow/*.hs     具名 branch
  Handlers.hs        原子操作与显式类方法组合
  Main.hs            main = interpreter ast effects
  Generated/        生成的契约、包装和 Prototype
sdk/Framework/      共享 SDK
docs/               使用指南、设计规范与实施记录
```

手写方法在生成执行副本之前就必须能通过 GHC／HLS 检查；它们导入的生成契约需先存在。修改手写代码后重新生成，再运行：

```sh
cabal run effect-codegen -- workflow FileDemo
cabal run file-demo
```

完整编写顺序、资产约束与常见诊断见[使用指南](docs/GUIDE.md)。

## 从哪里继续

| 你要做什么 | 入口 |
| --- | --- |
| 跑示例、编写业务程序、查当前写法 | [使用指南](docs/GUIDE.md) |
| 理解整体架构与当前／未来语义边界 | [主设计文档](docs/LATEST_DESIGN.md) |
| 修改 SDK 或让 LLM 进入开发工作 | [开发约定与任务路由](AGENTS.md) |
| 查看实施阶段和未完成工作 | [TODO](docs/TODO.md) |

[主设计](docs/LATEST_DESIGN.md)统一保存设计原则与运行协议，并引用图、资产和 Stream 专题；[文档分工](docs/LATEST_DESIGN.md#documents)也在其中。

## 示例

| 示例 | 内容 | 命令 |
| --- | --- | --- |
| [FileDemo](demo/FileDemo) | 文件资源、按资产分支、自动清理 | `cabal run file-demo` |
| [Crawler](demo/Crawler) | 并行抓取、Context 解析、顺序消费；需要网络和 curl | `cabal run crawler-demo` |
| [OpenFilesDemo](demo/OpenFilesDemo) | 多文件资源的持有与重开 | `cabal run open-files-demo` |
| [ScopeInstancesDemo](demo/ScopeInstancesDemo) | 按参数区分、共享和重开资源实例 | `cabal run scope-instances-demo` |
| [ScopeReuseDemo](demo/ScopeReuseDemo) | 并行链共享同一资源实例 | `cabal run scope-reuse-demo` |

## License

[BSD-3-Clause](LICENSE)
