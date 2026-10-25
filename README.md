# Algebraic Effect Sys in Haskell

一个用 Haskell 描述、组合和执行 effect 的实验性 SDK。你用声明定义操作的能力与取值关系，用原生 Haskell 实现业务逻辑，再通过 workflow AST 组织顺序和并行执行。

SDK 生成类型类接口、Context 绑定和资源生命周期的入口包装，让业务代码保留普通 `data`、`instance` 和 `do` 写法。workflow 的启动入口是：

```haskell
main :: IO ()
main = interpreter ast effects
```

项目目前处于接口探索阶段，已提供可运行示例。建议从纯计算示例开始，再阅读文件资源与并行 workflow；完整的实现范围见下文。

## 快速开始

### 环境

- **GHC 9.12.x**：本地与 CI 使用 9.12.2。代码生成器依赖该系列的 GHC 解析器 API。
- **Cabal**：本地已验证版本为 3.16.0.0。
- **Git**。

可通过 [GHCup](https://www.haskell.org/ghcup/) 安装工具链。确保 `ghc`、`ghci`、`runghc` 和 `cabal` 在 PATH 中，并使用同一套 GHC 9.12.x。当前 CI 在 Windows 上执行。

### 克隆、构建、运行

以下命令均在仓库根目录执行：

```sh
git clone https://github.com/cartesianc/algebraic-effect-sys-in-haskell.git
cd algebraic-effect-sys-in-haskell
cabal update
cabal build all
cabal exec -- runghc -idemo -isdk demo/RequestBenchmark/Main.hs
```

纯计算示例读取初始值 `20`，加一，再生成文本。业务结果为：

```text
Succ (Rendered "number: 21")
```

它不访问网络或业务文件。仓库已经包含示例的 `Generated/` 源码，因此首次运行不必先生成代码。`RequestBenchmark` 没有单独的 Cabal executable，使用上面的 `runghc` 命令运行。

接着可以体验带资源生命周期的示例：

```sh
cabal run file-demo
```

它会打开、读取、追加写入并显式关闭 `demo/FileDemo/output.txt`；文件不存在时创建，后续运行继续追加。日志会显示打开、读写和关闭过程。

## 如何理解一个程序

业务代码分为四个部分：**数据类型、effect 注册、handler 实现、workflow**。以 [FileDemo](demo/FileDemo) 为例：

| 文件 | 你在这里定义什么 |
| --- | --- |
| [Types.hs](demo/FileDemo/Types.hs) | 原生业务 ADT，例如文件名、文件句柄和文本 |
| [Effects.hs](demo/FileDemo/Effects.hs) | effect 类别、方法名、能力依赖及 Context 取值来源 |
| [Handlers.hs](demo/FileDemo/Handlers.hs) | `instance` 方法中的计算、模式匹配与 IO |
| [AST.hs](demo/FileDemo/AST.hs) | 引用各 branch 模块，组织整个 workflow |
| [Workflow/OperateFile.hs](demo/FileDemo/Workflow/OperateFile.hs) | 一个具名 branch，内部选择末端 node；较大模块也可组合其他 branch |
| [Main.hs](demo/FileDemo/Main.hs) | 调用生成的 `interpreter ast effects` |
| `Generated/` | SDK 生成的接口、包装后的 handler 和末端登记 |

例如，纯计算示例的 handler 直接取得上游值并计算：

```haskell
instance Effect MakeNumber m => AddOneEffect m where
  addOne = do
    Number number <- makeNumber
    pure (Added (number + 1))
```

对应的注册声明从 `MakeNumber` 请求值；SDK 负责接入取值协议，业务方法负责计算。完整代码见 [注册](demo/RequestBenchmark/Effects.hs) 和 [实现](demo/RequestBenchmark/Handlers.hs)。

workflow 的 `node` 选择一条完整操作链的末端，`chained` 顺序执行并在失败时停止，`parallel` 等待全部分支完成。链内的上游操作由 handler 显式引用；声明能力依赖本身不会自动执行操作。节点的返回值也不会自动传给下一个节点。

### 按 branch 拆分 workflow

每个 branch 单独一个文件，导出业务名称；顶层通过普通 import 引用名称，不在组合表达式里写限定前缀。例如 [Crawler/AST.hs](demo/Crawler/AST.hs)：

```haskell
ast :: AST
ast = chained [parsePages, printPages, finishCrawl]
```

其中 [ParsePages.hs](demo/Crawler/Workflow/ParsePages.hs) 定义：

```haskell
parsePages :: AST
parsePages = parallel
  [ node "ExtractPage"
  , node "ExtractLinkedPage"
  ]
```

`node` 返回抽象的 `EffectNode`，完整 branch 返回抽象的 `AST`。同一次 `chained`／`parallel` 的列表只能全是 node 或全是 branch，混写会产生类型错误；裸 node 也不能作为 `ast`。单个 node 仍需包在 branch 中。空分支写作 `chained ([] :: [AST])` 或 `parallel ([] :: [EffectNode])`，执行仍成功并返回空结果。

分文件不创建新 interpreter、Context 或 scope；同一模块被引用两次代表两次执行。类型系统约束节点层级，独立文件与具名引用是声明格式约定，未来由 LSP 检查；当前没有模块源码索引或运行时模块 key。五个 workflow demo 均采用这种组织方式，纯 target 示例 RequestBenchmark 保留原入口。

### Effect 类别与业务值

| 类别 | 用途 | 当前方法的成功值 |
| --- | --- | --- |
| `Pure` | 无对外业务产物的纯操作 | `()` |
| `Excu` | 执行操作 | `()` |
| `Context` | 生产或读取跨 handler 使用的业务值 | 注册的业务 ADT |
| `Scoped` | 在同一 instance 中实现资源的 `open`／`close` | `()` |
| `Error` | 在同一 instance 中实现故障的 `detect`／`resolve` | `()` |

Context 的 `request` 每次重新生产，成功后保存绑定；`require` 读取已有成功绑定，不重新执行生产者，未绑定时失败。普通绑定限定在一次末端调用内，scope 开启期间的绑定可随同批运行句柄跨节点保存。

纯计算示例使用的 `Pure` **执行载体**与表中的 `Pure` **effect 类别**是两个概念：示例中的数字、文本生产操作仍注册为 `Context`。业务失败通过生成的错误类型和 `raise` 传播，运行边界返回 `Succ` 或 `Failed`。

Error 的 `input` 指向被检查的 Scoped，Root 在故障传播时按 scope 从上到下调用检测方法。`detect` 成功表示定位到该 scope，再调用可选的 `resolve`；检测失败则继续检查。SDK 保留原始失败及各次检测、处置结果，不自动重开资源、重放业务或恢复中断的位置。FileDemo 的 `FileRecovery` 展示了这一协议。

## 修改代码与重新生成

**修改 `Handlers.hs` 后也要重新生成。** 实际运行编译的是 `Generated/Handlers.hs`。公共 workflow／target 入口在创建 scope 或执行业务前，比对当前手写源码与生成时保存的指纹；源码变化或缺失会拒绝启动，并提示重新生成。纯 target 入口还会比对传入的 effect 注册和末端名称，防止静默执行旧目标。

这是运行入口检查，不会在 `cabal build` 时自动生成。运行时需从仓库根目录访问手写 `Handlers.hs`；直接求值底层 `benchmark` 不经过这项 IO 检查。`--generate` 跳过一致性检查，便于更新旧生成代码。

例如修改 FileDemo 的注册、业务契约、handler 或新增 AST 末端后：

```sh
cabal run effect-codegen -- workflow FileDemo
cabal build file-demo
cabal run file-demo
```

纯计算示例使用 `target` 模式：

```sh
cabal run effect-codegen -- target RequestBenchmark
cabal exec -- runghc -idemo -isdk demo/RequestBenchmark/Main.hs
```

生成命令只更新对应示例的 `Generated/Effects.hs`、`Generated/Handlers.hs` 和 `Generated/Program.hs`，不会执行业务操作或回写手写文件。请修改手写声明与实现，再重新生成；将生成源码一并提交，便于审阅接口与协议包装。

### 新增示例

1. 在 `demo/MyDemo/` 下定义 `Types.hs`、`Effects.hs`、`AST.hs` 和 `Workflow/*.hs`；每个 branch 独立定义并导出业务名，顶层 AST 只引用这些名称。模块名使用 `MyDemo.*`，分别导出所需业务类型、`effects` 和 `ast`。这些模块不导入 `Generated` 或 `Handlers`，确保首次生成可独立编译声明。
2. 运行 `cabal run effect-codegen -- workflow MyDemo` 生成接口。尚无 `Handlers.hs` 时，SDK 会先生成空的 handler 编译模块。
3. 根据 `Generated/Effects.hs` 的接口编写手写 `Handlers.hs`，再运行一次生成命令，并编写调用生成入口的 `Main.hs`。
4. 在 [Cabal 配置](algebraic-effect-sys-in-haskell.cabal) 中参考 FileDemo 增加 executable，调整模块列表、`-main-is` 和依赖，然后编译运行。handler 模块列表使用 `Generated.Handlers`。

没有 workflow 的纯计算示例可参考 RequestBenchmark，以 `Target.hs` 导出的 `target` 选择末端，并使用 `target` 生成模式。首次生成使用独立的 `effect-codegen` 命令；已有 Main 的 `--generate` 路径要求其导入链已能编译。

## 示例导航

| 示例 | 适合了解 | 运行方式 |
| --- | --- | --- |
| [RequestBenchmark](demo/RequestBenchmark) | 原生 ADT、Context 取值、纯计算链 | 见快速开始 |
| [FileDemo](demo/FileDemo) | 文件资源的开启、读写、关闭及 Error 注册 | `cabal run file-demo` |
| [Crawler](demo/Crawler) | 并行解析与顺序打印的 workflow | `cabal run crawler-demo` |
| [OpenFilesDemo](demo/OpenFilesDemo) | 多个文件句柄跨节点保持打开 | `cabal run open-files-demo` |
| [ScopeInstancesDemo](demo/ScopeInstancesDemo) | 按参数区分资源实例、复用与重开 | `cabal run scope-instances-demo` |
| [ScopeReuseDemo](demo/ScopeReuseDemo) | 并行节点复用同一个 scope | `cabal run scope-reuse-demo` |

Crawler 需要网络连接和 PATH 上的 `curl`；打印阶段会再次请求并解析页面。文件类示例在各自的 `demo/` 子目录下写入输出，已加入 Git 忽略规则。

## 当前范围

已实现五类 effect 的接口生成、原生 instance 包装、Context 的 request／require、App／IO 下的 scope 多实例复用、Root 的 Error 检测与处置，以及有限 workflow 的顺序和并行执行。

正在设计或尚未接入的能力包括资源自动收尾、使用与关闭的并发协调、Generic Map、loop／Hanging、middleware 和中断位置恢复。示例目前显式关闭资源；Error 的处置成功也不把原业务失败改成成功。

当前 SDK 随仓库内的 executable 编译，尚未提供独立 Cabal library。跨独立模块的运行时链接与跨 interpreter 的资源存续也未实现。完整边界见 [最新设计](docs/LATEST_DESIGN.md)。

## 开发与文档

```text
sdk/Framework/   SDK 契约、运行载体、workflow 与代码生成
demo/           手写示例及各自的 Generated 源码
docs/           当前设计方法与协议说明
checks/         已有的局部协议检查代码
archive/        旧实现与历史设计，不参与当前根项目构建
```

日常修改后执行与 CI 一致的普通编译：

```sh
cabal build all
cabal exec -- ghc -idemo -isdk -fno-code demo/RequestBenchmark/Main.hs
```

深入阅读：

- [设计方法](docs/DESIGN_METHOD.md)：组合描述与原子值操作的边界；修改架构前先读。
- [最新设计](docs/LATEST_DESIGN.md)：Context、scope、生成协议与待落实的能力。
- [SDK 入口](sdk/Framework/SDK.hs)：统一 facade 和命令行入口。
- [代码生成](sdk/Framework/Codegen.hs)：注册如何生成类型类接口与调用包装。
- [开发约定](AGENTS.md)：当前项目的实现与验证规则。
- [历史归档](archive/README.md)：旧版本的代码和设计背景。

## License

[BSD-3-Clause](LICENSE)
