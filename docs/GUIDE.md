# 使用指南：代码形态与编写

状态：本文说明当前 SDK 可运行的接口，包括持续资产（Stream、`streams`、`lifelong`，见[第五节](#stream)）。完整的持续执行规则见 [Stream 与 lifelong](STREAM_LIFELONG.md)，尚未设计的部分见[当前限制](#limitations)。

从“代码长什么样”进入：先看到资产、注册、handler 和 workflow 的代码块，再按链接深入对应模块。想直接运行时可跳到快速开始。完整语义见[主设计](LATEST_DESIGN.md)，源码约束见[ASSETS](ASSETS.md)。

| 任务 | 阅读位置 |
| --- | --- |
| 先看同一业务在各模块中的代码形态 | [代码长什么样](#code-shape) |
| 定义表示类型和分支契约 | [资产书写](#types) |
| 查注册类别、Input 和 demands | [effect 注册](#effects) |
| 写 handler、读取与失败处理 | [handler 书写](#handlers) |
| 组织 chained、parallel、alternative | [workflow 书写](#workflow) |
| 接入持续数据源、编写 lifelong 监控 | [持续资产与 lifelong](#stream) |
| 构建并运行现有示例 | [快速开始](#quickstart) |
| 区分 gencode、runtime、结构查看及启动命令 | [命令行与执行阶段](#commands) |
| 明确文件分工与编写顺序 | [程序结构](#program-layout) |
| 重新生成、新增程序或处理诊断 | [开发流程](#development) |

<a id="code-shape"></a>
<a id="read-example"></a>
## 代码长什么样

下面用 FileDemo 展示同一组名字如何贯穿资产、注册、方法和 workflow。代码块均取自现有源码，省略模块头、导入以及未展示的注册与 instance；它们不是独立的完整程序。阅读顺序展示结构关系，首次编写时仍需先生成契约接口再写 Handlers。

### 1. Types.hs：先看到业务资产的结构

```haskell
data TextState = Blank | Written String
  deriving Show
```

文件状态只有 `Blank` 和 `Written` 两种构造，这个 ADT 说明数据长什么样。负责资产生产与解析的 effect 称为 **Context**：它把表示类型细化为具名资产，由绑定的 parser handler 产生值，消费方按资产名声明读取。下面通过 `ExtractFileText` 的注册和 handler 展示这层关系。

[完整 Types.hs](../demo/FileDemo/Types.hs) · [资产定义与使用规则](#types)

### 2. Effects.hs：为生产和消费写出关系

以下是 `effects` 列表中的两个注册。生产方声明资产名、表示类型、绑定的 parser handler，以及是否缓存：

```haskell
EffectSpec
  { name = "ExtractFileText"
  , typing = Context { asset = Asset @TextState "FileText", parser = Just "parseFileText", require = True, stream = False }
  , input = "ReadFile"
  , demands = []
  }
```

消费方绑定 handler，声明前驱和需要读取的资产：

```haskell
EffectSpec
  { name = "WriteFirstLine"
  , typing = Excu { handler = Just "writeFirstLine" }
  , input = "FileSession"
  , demands = [requires "FileTextBlank", requires "OpenedFile"]
  }
```

字段里写的是 handler 名：`parseFileText`、`writeFirstLine` 是下面 Handlers.hs 中的类方法。`input` 是前驱，gen 在 handler 之前执行它，这里先开启 `FileSession`；`demands` 选出要读的资产。`FileTextBlank` 是 `FileText` 的 `Blank` 分支契约，`OpenedFile` 提供文件资源。另一个候选 `AppendLine` 使用 `FileTextWritten`。

[完整 Effects.hs](../demo/FileDemo/Effects.hs) · [注册字段与类别](#effects)

### 3. Handlers.hs：让声明落到原生类方法

parser 挂在 `ReadFile` 下，用 `raw` 读取读取句柄本次交出的 list（这里是一段文本），返回表示类型的值：

```haskell
instance ParseFileTextLayer m => ParseFileTextHandler m where
  parseFileText = do
    contents <- raw
    text <- case contents of
      [whole] -> pure whole
      _ -> raise (ParseFileTextError "File read returned no text")
    pure (if null text then Blank else Written text)
```

消费方的 handler 只读取资源、执行写入；以下保留它的完整实现：

```haskell
instance WriteFirstLineLayer m => WriteFirstLineHandler m where
  writeFirstLine = do
    FileHandle path file <- require @FileHandle
    let line = "file-demo: the file was empty; this is the first line.\n"
    outcome <- liftIO $ tryIOError $ do
      putStrLn "[read] (empty file)"
      hSeek file SeekFromEnd 0
      hPutStr file line
      hFlush file
      putStrLn ("[write] " ++ path ++ ": " ++ line)
    either (raise . WriteFirstLineError . displayException) pure outcome
    pure []
```

`XxxLayer m => XxxHandler m` 由 handler 名生成，Layer 是方法体可用能力的边界：按表示类型的读取 `Reads T`、挂接 parser 与 Pure 的 `raw`、本 handler 的 `raise` 和 `MonadIO`。方法体里没有上游、scope 或资产名：`FileSession` 由 gen 在方法体之前开启；`require @FileHandle` 读的是 `OpenedFile`，这由绑定它的 effect 的 demands 决定。同一个 handler 可以注册到多个 effect，各自读到不同的资产。IO 和解析写在 handler 方法体内。

[完整 Handlers.hs](../demo/FileDemo/Handlers.hs) · [handler、读取与错误写法](#handlers)

### 4. Workflow 与 AST：把完整链组合成模块

`Workflow/OperateFile.hs` 定义一个具名 branch：

```haskell
operateFile :: AST
operateFile = alternative
  [ node "WriteFirstLine"
  , node "AppendLine"
  ]
```

`AST.hs` 引用这个模块：

```haskell
ast :: AST
ast = operateFile
```

`alternative` 的候选通过前面的分支契约对应 `Blank`／`Written`，AST 只列末端。每个末端代表自己的完整 original chain：gen 沿 Input 把前驱装配在 handler 之前，Context 的生产通过取值关系接入。

[OperateFile.hs](../demo/FileDemo/Workflow/OperateFile.hs) · [AST.hs](../demo/FileDemo/AST.hs) · [branch 与节点规则](#workflow)

### 5. Generated：看到声明派生出的契约

下面节选生成的资产类型和一个 handler 的契约，派生实例与其他接口见源码：

```haskell
newtype FileText = FileText (TextState)

-- handler writeFirstLine：绑定到 WriteFirstLine。
type WriteFirstLineLayer m = (SDK.Reads (()) m, SDK.Reads (FileHandle) m, SDK.Raises WriteFirstLineError m, MonadIO m)
class WriteFirstLineHandler m where
  writeFirstLine :: m [String]

newtype WriteFirstLineError = WriteFirstLineError String
```

资产类型把 `Asset @TextState "FileText"` 细化成具名资产，只在生成区使用；handler 契约由 handler 名和它的各个绑定推出。`Generated/Handlers.hs` 是运行副本：方法体原样复制，每个 effect 一个类型标签 `At "名字"` 和一个入口，读取由按标签区分的 instance 在编译期路由到细化资产：

```haskell
runWriteFirstLine = ⟨入口包装⟩ $
  openFileSession >> runAt @"WriteFirstLine" FrameworkGenerated.writeFirstLine

instance FrameworkRuntime.Reads (FileHandle) (At "WriteFirstLine") where
  require = At ((\(FrameworkGenerated.OpenedFile value) -> value) <$> readOpenedFile)
```

Generated/Effects 提供可检查的接口，Generated/Program 保存末端登记和静态 Prototype；运行副本及协议由生成器维护。

[Generated/Effects.hs](../demo/FileDemo/Generated/Effects.hs) · [Generated/Program.hs](../demo/FileDemo/Generated/Program.hs) · [生成与更新流程](#development)

<a id="quickstart"></a>

## 快速开始

需要 **GHC 9.12.x**（代码生成器依赖该版本的解析器 API，本地与 CI 使用 9.12.2）和 **Cabal**（已验证 3.16）。可通过 [GHCup](https://www.haskell.org/ghcup/) 安装，确保 `ghc`、`ghci`、`runghc`、`cabal` 在 PATH 中。

```sh
git clone https://github.com/cartesianc/algebraic-effect-sys-in-haskell.git
cd algebraic-effect-sys-in-haskell
cabal update
cabal build all
```

运行带文件资源的示例，它会打开、读取、追加写入 `demo/FileDemo/output.txt`，结束时由 SDK 自动关闭文件：

```sh
cabal run file-demo
```

仓库已包含各示例生成好的代码，首次运行不需要先生成。完成上面的 clone 与 cd 后，本文其余命令均在仓库根目录执行；生成器和运行入口都需要从这里定位源码。各阶段的用途见下节。

### 运行入口：Main.hs

前面的声明、方法和 workflow 由同一个入口运行。FileDemo 的完整 Main 如下：

```haskell
module FileDemo.Main (main) where

import FileDemo.AST (ast)
import FileDemo.Effects (effects)
import FileDemo.Generated.Program (interpreter)

main :: IO ()
main = interpreter ast effects
```

[Main.hs](../demo/FileDemo/Main.hs) 从手写模块导入 `ast` 和 `effects`，从生成模块导入绑定本程序契约与原型的 `interpreter`。`main :: IO ()` 是原生 Haskell 入口；这一行调用启动前面定义好的 workflow。

<a id="commands"></a>

## 命令行与执行阶段

**程序的业务入口始终只有一个：Main 中的 `interpreter ast effects`。** 命令行把生成、编译、结构查看和业务执行分开，让开发者能先检查结构，再执行实际 IO。

本文的 **gencode** 指代码生成阶段，对应可执行目标 `effect-codegen`；**runtime** 指业务运行阶段，对应 `file-demo` 等程序的无参数启动。它们不是额外的命令或 `--runtime` 开关。

### 命令总览

以下全部使用 FileDemo。`FileDemo` 是 Haskell 模块命名空间，`file-demo` 是 [Cabal 文件](../algebraic-effect-sys-in-haskell.cabal)中的 executable 名称；其他程序的对应关系见[示例](#examples)。

| 目的 | 命令 | 结果 | 执行 handler 业务 |
| --- | --- | --- | --- |
| gencode：生成或更新源码 | `cabal run effect-codegen -- workflow FileDemo` | 更新 `demo/FileDemo/Generated/` | 否 |
| 编译 | `cabal build all` | 编译生成器及所有示例 | 否 |
| runtime：运行 workflow | `cabal run file-demo` | 启动 AST，执行 IO、诊断与资源收尾，打印结果 | 是 |
| structure：查看静态结构 | `cabal run file-demo -- --structure` | 校验并打印已生成的 Prototype | 否 |
| 从已有程序转调生成器 | `cabal run file-demo -- --generate` | 转调第一行相同的生成命令，生成后退出 | 否 |

`cabal run` 会先按需要编译指定 executable，再启动它；这一步编译不会自动运行 gencode。`--` 把后面的参数传给被启动的程序：`workflow FileDemo` 交给生成器，`--structure`／`--generate` 交给 FileDemo 的 interpreter。后两者是互斥的启动模式，不与普通业务运行一起执行。

### 为什么生成有两个入口

独立生成器只需要加载声明、AST 与手写源码，**不依赖当前业务 Main 能否编译**。因此首次建立程序、Generated 缺失、注册或类型接口变化时，使用：

```sh
cabal run effect-codegen -- workflow FileDemo
```

生成器输出契约接口 `Effects.hs`、带协议包装的 `Handlers.hs`、保存静态原型与装配入口的 `Program.hs`、资产目录 `Assets.hs`，以及结构缓存 `.scope-cache`。第一次还没有手写 `Handlers.hs` 时先生成接口与空实现模块，随后填写 instance，再生成完整执行副本。

`--generate` 只是已有 Main 的快捷入口：Main 的导入链必须先能编译，interpreter 才能转调同一个生成器。它不会在生成后继续执行业务；下一次运行会编译更新后的代码。日常统一使用独立 `effect-codegen` 即可，不需要把两个生成入口都执行一遍。

gencode 是这个 EDSL 的编译器：依次读取声明、降级、绑定、提取 handler 方法体的读取形状、构图、输出源码，最后用 GHC 类型检查业务模块与输出并检查顶层白名单；任何一步报错都不写回 Generated，也不调用业务 handler。各阶段做什么、报告哪些错误见[编译流水线](LATEST_DESIGN.md#generation)。缓存命中只复用纯构图结果，其余阶段仍会执行，内容未变的文件不会重写。详见[生成缓存边界](EFFECT_GRAPH.md#内容缓存与重跑边界)。

### runtime：执行已经生成的程序

```sh
cabal run file-demo
```

默认启动先核对当前源码、注册和生成原型，再按 AST 装配并启动 workflow。实际运行调用已编译的 handler，并在内存中维护资产、活动 chain 和 scope；它复用静态 Prototype，不重新跑一遍 handler 来构图，也不会在源码过期时替你生成。

FileDemo 会创建或追加 `demo/FileDemo/output.txt`，完成后自动关闭资源，打印 `Succ [...]` 或 `Failed ...`。其他示例的业务行为见[示例](#examples)。

### structure：检查结构，不启动业务

```sh
cabal run file-demo -- --structure
```

它展示 `Generated/Program.hs` 中的同一份 `generatedPrototype`，先检查注册、手写源码指纹和 AST 是否与生成结果一致。输出可按下面的顺序阅读：

| 输出标题 | 查看内容 |
| --- | --- |
| `Workflow` | branch、末端与 AST 位置 NodeId |
| `Chain definitions`／`Chain mounts` | original／Context 链定义、挂载位置、可达方法、可能生产和读取 |
| `Asset sources` | 缺少捕获绑定时，各读取点许可的资产来源 |
| `Effect methods`／`Effect references` | 方法身份、角色、所属 effect 与引用边 |
| `Scope layers`／`Scope parents`／后续顺序证据 | scope 的层级、共享父节点、入口路径和顺序推导依据 |

这是静态结构视图，不是实时 RuntimeGraph 或业务执行日志。该模式不创建运行 scope 句柄、不执行 handler，也不更新 Generated；源码过期时先重新生成。字段与推导规则见 [EffectGraph](EFFECT_GRAPH.md#查看初始化结果)。

### 日常如何选择

- **第一次运行仓库内现有示例**：按[快速开始](#quickstart)构建后直接运行；仓库已带生成结果。
- **修改手写代码后**：先生成，再查看结构或运行。只改 handler 的原子 IO 也要生成，以更新执行副本与源码指纹。
- **新增程序或接口**：先生成契约，再写 instance；完整步骤见[新建一个程序](#新建一个程序)。
- **只想审查关系**：使用 `--structure`；它仍要求程序及生成模块可编译，但不触发文件读写等业务 IO。

修改 FileDemo 后的一组常用命令如下；结构查看按需执行，最后一行才会运行文件读写业务：

```sh
cabal run effect-codegen -- workflow FileDemo
cabal run file-demo -- --structure
cabal run file-demo
```

两条 `cabal run file-demo` 会按需编译该程序；准备检查整个仓库时另外使用 `cabal build all`。若看到源码／注册过期提示，重新生成；若在进入 Main 前已经编译失败、因而无法使用 `--generate`，直接使用独立生成器，并按诊断修正手写源码。

<a id="program-layout"></a>

## 程序结构

一个程序由四个手写模块和一行运行入口组成，四个模块分别承担 DSL 的不同角色：

| 模块 | 文件 | 在代码中读到什么 |
| --- | --- | --- |
| 一、资产 | `Types.hs` | 业务数据的构造器、字段和类型 |
| 二、effect 注册 | `Effects.hs` | 类别、绑定的 handler 名、前驱和读取关系 |
| 三、handler | `Handlers.hs` | 按表示类型读取、模式匹配、解析与 IO |
| 四、workflow | `AST.hs`、`Workflow/*.hs` | 具名 branch 与末端挂载 |
| 生成接口与结构 | `Generated/` | 类型契约、协议包装、Prototype |
| 运行入口 | `Main.hs` | interpreter 启动整份结构 |

- **生成入口 `effect-codegen`**：负责从手写源码生成契约、执行副本和静态原型；修改手写源码后显式运行，具体见[命令行与执行阶段](#commands)。
- **运行入口 `Main.hs`**：`interpreter` 来自 `Generated/Program.hs`。每个 node 选择一个末端 effect，运行 gen 为它装配的入口：先按 `requests` 驱动资产，再执行 Input 前驱，最后执行绑定的 handler；handler 用 `require` 读取资产，整条操作链由此展开。
- **生成区**：`Generated/` 由生成器产出，不要手改。运行时编译的是 `Generated/Handlers.hs`，即原样复制的 handler 方法体，加上 SDK 生成的入口、路由与协议包装。

编写顺序：

1. 在 `Types.hs` 写表示类型。
2. 在 `Effects.hs` 注册 effect，在 `AST.hs`／`Workflow/` 编排末端。
3. 生成接口：`cabal run effect-codegen -- workflow 程序名`。
4. 按 `Generated/Effects.hs` 中的接口写 `Handlers.hs`。
5. 再生成一次，运行。

<a id="types"></a>

## 一、资产书写（`Types.hs`）

FileDemo 的状态资产先写成这样的原生 ADT：

```haskell
data TextState = Blank | Written String
  deriving Show
```

下面展开类型、生成的资产类型和使用规则。资产是在 effect 之间传递的业务数据：Context 的产物、消费方读到的值，以及它们字段里递归包含的业务类型。`String`、`Handle` 等库类型不是资产。

### 表示类型（手写）

在 `Types.hs` 用原生 `data`／`newtype` 定义，作为 `Asset @表示类型 "资产名"` 中的表示类型：

```haskell
data PageURL = PageURL { pageAddress :: String }   -- 记录
data FileHandle = FileHandle FilePath Handle       -- 包装库类型
data TextState = Blank | Written String            -- 和类型
```

- **只写值的结构**：资产类型由生成器产出，不需要再手写一层 newtype。单值可以直接用 Prelude 类型，例如 `Asset @FilePath "FileName"`。
- **库类型**：含 `Handle` 等需要导入的库类型时，在 `Types.hs` 定义一个记录包装它。
- **scope 开启参数**：按绑定的生产身份共享，参数和资源都不因 scope 匹配而需要 `Eq`。
- **`Show`**：需要打印结果时派生。
- **不导入生成区**：`Types.hs` 不导入 `Generated` 或 `Handlers`。

### 细化资产（生成）

每个 `Asset @表示类型 "资产名"` 把表示类型细化为一个资产（refinement asset），生成器产出以资产名命名的类型：

```haskell
newtype StartURL = StartURL PageURL
```

- **为什么要细化**：同一个表示类型可能有几个来源，例如 Crawler 的起始页和链接页摘要都是 `PageSummary`。细化成 `StartPageSummary`、`LinkedPageSummary` 两个资产后，每个名字只对应一条生产链。消费方在注册里按资产名声明读取（`requires "StartPageSummary"`），handler 只写表示类型 `require @PageSummary`；gen 按“表示类型 + effect”把这次读取路由到唯一的细化资产，所以同一个 `printSummary` 注册到两个 effect 时各读各的摘要。原理见[主设计：细化资产](LATEST_DESIGN.md#refinement)。
- **一个 effect 内表示类型不重复**：同一个 effect 的 demands 里不能有两个表示类型相同的资产；需要两个同类型值的操作，用不同的表示类型（角色类型）区分。
- **只在生成区使用**：细化资产类型由 Generated 的存储、路由和入口使用，handler 不写它。字段和构造器仍是 `Types.hs` 里的表示类型；要看结构就看 `Types.hs`，或 `Generated/Assets.hs` 的资产目录。

- 资产名须是 Haskell 类型名，按业务含义起名；不能与 effect 名、生成区固定名或 `Types.hs` 中的类型重名。
- 表示类型有 `Eq`／`Show` 时，资产类型才有 `Eq`／`Show`；不派生 `Read`。
- 持续资产（`stream = True`）按访问方式读取：`streams` 得到 `require @(History 表示类型)`，`requires` 得到最新一条 `require @表示类型`，见[持续资产与 lifelong](#stream)。

### 分支契约（生成）

表示类型是和类型（至少两个构造器，每个构造器至多一个字段）时，生成器为每个构造器产出一个分支契约。以 FileDemo 的 `Asset @TextState "FileText"` 为例：

| 构造器 | 分支契约 |
| --- | --- |
| `Blank` | `newtype FileTextBlank = FileTextBlank ()` |
| `Written String` | `newtype FileTextWritten = FileTextWritten String` |

- **命名**：资产名加构造器名，包装该构造器的字段；没有字段时包装 `()`。
- **读取**：分支契约的表示类型就是构造器的字段类型（没有字段时是 `()`），handler 写 `require @String`、`require @()`。资产当前是这个构造器时才能取到值，否则报 `CaseNotSelected`。分支契约由基础资产的生产方提供，只能 `requires`。
- **用途**：`alternative` 据此决定启动哪个候选（见[workflow 书写](#workflow)）。候选声明的分支契约是选择依据，handler 不必读取它。

### 使用规则

生成器每次都会检查业务模块的顶层：

- **顶层只有声明**：`Types.hs`、`Handlers.hs` 的顶层只允许类型声明和 instance；`Effects.hs` 只定义 `effects`（局部辅助写在它的 `where` 里），`AST.hs` 与 `Workflow/*.hs` 只定义类型为 `AST` 的命名值，`Main.hs` 只定义 `main`。顶层普通函数、类声明、foreign 声明和 rewrite rule 都被拒绝。
- **值操作写在 handler 里**：所有值操作写进 handler 方法体，经注册进入 effect 链，才能被静态分析。方法体内的 `let`／`where` 局部函数与 lambda 不限制；需要在多处使用的逻辑注册成 handler，通过 effect 组合。
- **资产目录**：生成的 `Generated/Assets.hs` 列出资产的类型、构造器、字段及定义位置，供 review 和编辑器使用，运行时不加载。

完整规则见 [源码资产约束](ASSETS.md)。

<a id="effects"></a>

## 二、effect 注册（`Effects.hs`）

`Effects.hs` 导出 `effects :: [EffectSpec]`。每个 `EffectSpec` 注册一个 effect：类别、绑定的 handler 名、前驱和读取关系，不写实现（节选自 [FileDemo](../demo/FileDemo/Effects.hs)）：

```haskell
EffectSpec
  { name = "ReadFile"
  , typing = Excu { handler = Just "readFileContent" }
  , input = "FileSession"
  , demands = [requires "OpenedFile"]
  }
```

`EffectSpec` 有四个参数：

| 参数 | 类型 | 含义 |
| --- | --- | --- |
| `name` | `String` | effect 的注册名 |
| `typing` | `EffectTyping` | 类别（六选一）及绑定的 handler 名 |
| `input` | `String` | 前驱：gen 在 handler 之前执行哪个 effect |
| `demands` | `[Demand]` | 驱动或读取哪些资产 |

文件需开启 `DuplicateRecordFields`（多个类别共用字段名 `handler`）和 `TypeApplications`（`Asset @类型 "资产名"` 中的类型应用），从 `Framework.SDK` 导入 `EffectSpec(..)`、`EffectTyping(..)`、`Asset(..)`、`requests`、`requires`；订阅持续资产时导入 `streams`，用到 Error 时再导入 `Handles(..)`。

### `name`

- **唯一身份**：AST 的 `node`、其他 effect 的 `input`、Error 的 `ScopeFaultIn`／`ContextFaultIn` 都用这个名字引用它，在注册集合中不能重复。
- **生成的名字**：生成器据此产出类型标签 `At "名字"`、结果构造器 `名字Result` 和内部入口方法（见下表），所以 `name` 须是大写字母开头的 Haskell 类型名。handler 的类、Layer 与错误类型由 handler 名推出，不由 effect 名推出。

### `typing`：六种类别

`typing` 是六选一的枚举，每种类别的字段写它绑定的 handler 名：

| 枚举 | 字段 | handler 签名 | gen 生成的内部入口 | 用途 |
| --- | --- | --- | --- | --- |
| `Context` | `asset = Asset @表示类型 "T"`；`parser :: Maybe String`；`require`、`stream :: Bool` | parser 为 `m 表示类型` | `getT`；`require = True` 时另有 `readT`（持续资产为 `streamT`） | 生产在操作之间传递的业务值 |
| `Pure` | `handler :: Maybe String`（必填） | `m [String]` | `run名字` | 生产链中的纯值变换：去重、排序、过滤上层交出的 list |
| `Excu` | `handler :: Maybe String` | `m [String]` | `run名字` | 执行操作（原子句柄） |
| `Scoped` | `open`、`close :: Maybe String` | 均为 `m [String]` | `open名字`、`close名字` | 资源的开启与关闭（原子句柄） |
| `Error` | `detect`、`resolve :: Maybe String`；`handles :: [Handles]` | 均为 `m ()` | `detect名字`、`resolve名字`，由失败协议调用 | 对 scope 内的指定失败做诊断和处置 |
| `Stream` | `handler :: Maybe String` | `m String` | `next名字`，由生产会话调用 | 持续取得原始输入，交给挂在它下面的 Context 解析 |

- **字段写 handler 名**：`Just "名字"` 绑定 `Handlers.hs` 中同名的类方法，`Nothing` 不绑定。入口为 `Nothing` 的 effect 只作为声明存在，不能被 AST 选为末端。
- **handler 可以复用**：同一个 handler 可以绑定到多个 effect，前提是各绑定推出相同的签名和 Layer。例如 Crawler 的 `FetchPage`、`FetchLinkedPage` 共用 `fetchPage`，FacadeProbe 的两个 Scoped 共用 `openTextFile`／`closeTextFile`。
- **入口是内部名字**：上表的入口方法由 gen 按 effect 名或资产名生成，用户不写也不调用；handler 名不能与它们重名。
- **业务资产只归 Context**：Excu 和 Scoped 返回的 `[String]` 是原子句柄交出的输出，只交给挂接的 Context 解析，中间可以经过一串 Pure（见 `input`）；Stream 返回的原始输入交给对应的 Context 解析器。它们和 Pure 都不直接产出业务资产。

#### `Context`

```haskell
typing = Context { asset = Asset @PageURL "StartURL", parser = Just "startURL", require = True, stream = False }
```

- **`asset = Asset @表示类型 "资产名"`**：把表示类型细化为资产，生成器产出 `newtype StartURL = StartURL PageURL`；表示类型怎么写见[资产书写](#types)。
- **`parser`**（必填）：产出表示类型值的 handler，签名 `m 表示类型`，直接返回 `pure (PageURL ...)`，不包资产构造器。gen 生成 `getStartURL`：执行 Input 前驱和 parser，再包成资产发布。parser 是细化 parser：挂在句柄或 Pure 下时，它把 `raw` 读到的 list 解析成表示类型，作用类似 tokenize；值的变换交给 Pure。
- **`require`**：`True` 时 SDK 缓存最新值并生成读取方法 `readStartURL`，消费方才能 `requires` 它；`False` 不缓存，消费方不能 `requires`。
- **`stream`**：`True` 声明持续资产，SDK 缓存历史，读取方法是 `streamStartURL`。只能在 Input 是 Stream 时声明，且必须同时 `require = True`；挂在 Stream 下的 Context 必须 `stream = True`。见[持续资产与 lifelong](#stream)。
- **不能作为 AST 末端**：Context 在它挂接的句柄执行时产出，被 `requests` 驱动或被 alternative 的选择读取驱动时产出；被读取时不产出。
- **命名**：资产名决定资产类型和入口方法名，要按业务含义起名（`StartURL`，而不是 `LoadStartURL`），不能与 effect 名、生成区固定名或 `Types.hs` 中的类型重名。

#### `Pure`

```haskell
typing = Pure { handler = Just "validateFileName" }
```

生产链中的纯值变换，相当于对上层输出做 fmap：handler 用 `raw` 读直接 Input 交出的 list，返回变换后的 list，例如去重、排序、过滤；检查不通过时 `raise`。

- **只在生产链中**：`input` 必须是 Excu、Scoped 或另一个 Pure；以它为 `input` 的只能是 Context 或 Pure，且至少有一个，所以一串 Pure 最后一定落到一个 Context。
- **值只从 raw 来**：Pure 不写 demands，Layer 只有 `Raw` 和 `Raises`，没有 `MonadIO`，不能执行 IO，也不读资产。
- **不能当 AST 末端**，必须绑定 handler。
- **不挂在 Stream 下**：Stream 有自己的数据结构，下面只挂它的 parser Context。

写法与执行见[挂在句柄下的 Context](#runtime-anchored) 和[主设计：Pure](LATEST_DESIGN.md#pure)。

#### `Excu`

```haskell
typing = Excu { handler = Just "fetchPage" }
```

执行一次操作的原子句柄。它交出一个 `[String]`，供挂在它下面的 Context（可经一串 Pure）解析：没有信息时 `pure []`，一项是 `pure [info]`，一串操作或递归的结果在方法体里用 `:`、`concat` 组合。

#### `Scoped`

```haskell
typing = Scoped { open = Just "openSession", close = Just "closeSession" }
```

- **open 必填，close 可选**：可开启的 scope 声明 open；`close = Nothing` 时不生成关闭方法，实例不可达后只移出运行表。
- **资源是一个 Context**：Scoped 在 `demands` 里 `requests` 资源 Context（至多一个）并 `requires` 它；gen 在 `open` 之前驱动资源的生产，`open`／`close` 的 handler 用 `require` 读取资源。
- **开启参数**：资源 Context 的 parser 读取的上游 Context 就是开启参数，SDK 按它们决定共享还是新建实例（见「运行时行为」）。
- **实例跟随注册**：两个 Scoped 注册即使共用 open／close handler，也是两个独立的 scope。

#### `Stream`

```haskell
typing = Stream { handler = Just "nextReading" }
```

持续数据源：每次调用取得一份原始输入（`m String`），节奏由方法体自己的阻塞或等待决定。它不能作为 AST 末端，由生产会话驱动；恰好一个 Context 以它为 `input`，其 parser 用 `raw` 读取这份输入（单元素 list）。Stream 有自己的数据结构，不改成 list 输出，也不能在下面挂 Pure。写法见[持续资产与 lifelong](#stream)。

#### `Error`

```haskell
typing = Error
  { detect = Just "detectFileSession"
  , resolve = Just "resolveFileSession"
  , handles = [RaisedBy "readFileContent", RaisedBy "writeFirstLine", RaisedBy "appendLine"]
  }
```

- **`handles`**（必填，不能为空）：处理哪些失败，枚举见下表。
- **`detect`**（可选）：进一步判断这次失败是否归它处理。不写时直接调用 `resolve`。
- **`resolve`**：执行处置。Error 的处置是另一条驱动链，设计确定前 resolve 不操作 scope，不调用 close；FileDemo 的 resolve 暂时只是 `pure ()`。
- **只指向 scope**：生成器沿 `input`／`requests` 找最近的 Scoped 作为它关联的 scope，必须恰好一个，没有时报错。普通 effect 的错误靠提前 mock 排除，不设全局处置。同一 scope 下，同一种失败只能由一个 Error 处理。

`Handles` 有三个枚举：

| 枚举 | 匹配的失败 | 参数须是 |
| --- | --- | --- |
| `RaisedBy "x"` | handler `x` 在方法体里 `raise` 的业务失败，不论它绑定在哪个 effect | 已注册的 handler 名 |
| `ScopeFaultIn "X"` | Scoped `X` 的资源协议故障（开启参数、实例归属、关闭等，见 [SDK 协议故障](#sdk-faults)） | Scoped effect |
| `ContextFaultIn "X"` | Context `X` 的取值协议故障（缺值、多份可选的值、分支不匹配，见 [SDK 协议故障](#sdk-faults)） | Context effect |

Context 协议故障的来源一律记为生产方的注册名，不是契约名。

### `input`

```haskell
input = "FileSession"
```

- **取值**：`"Root"`（没有上游），或另一个**非 Context、非 Error** 的 effect 名。Context 只能经 `demands` 接入，不能写在 `input` 里。只有 Context 和 Pure 可以把 Pure 写在 `input` 里。
- **含义**：前驱。gen 在这个 effect 的入口中先执行 `input` 指向的 effect（连同它自己的前驱），再执行绑定的 handler；方法体不调用上游，也不捕获前驱的失败。前驱失败后的改道用 AST 的 `alternative`。
- **已开启的 scope 不重开**：前驱是 Scoped 时，同一条链里已开启的实例直接复用，不再执行 `open`。
- **挂接**：Context 的 `input` 指向 Excu、Scoped 或 Stream 时，它就挂在这个句柄下，parser 用 `raw` 读取句柄入口（`handler`／`open`）本次交出的 list；`close` 没有挂接点。挂接的 Context 不把句柄当作前驱重跑。例如 [FacadeProbe](../demo/FacadeProbe/Effects.hs) 的 `ReportCounter` 挂在 `ReadReport` 下，把读到的文本解析成行数。
- **经 Pure 挂接**：Context 或 Pure 的 `input` 指向 Pure 时，`raw` 读的是这个 Pure 变换后的 list；整串 Pure 的挂接点是最上面的句柄。例如 [Crawler](../demo/Crawler/Effects.hs) 的 `FetchPage` → `KeepPageBody`（Pure，去掉空白正文）→ `ExtractPage`（Context，解析成摘要）：抓取在 AST 中执行后，本次输出经 Pure 注入解析；[FileDemo](../demo/FileDemo/Effects.hs) 的 `LocateFile` → `ValidateFileName`（Pure）→ `FileLocation`（Context）则由 `requests` 驱动。
- **限制**：
  - input 链不能成环；
  - 链上的 Scoped 必须声明 `open`；`close` 可为 `Nothing`，此时实例不可达后只移出运行表；
  - Scoped 的资源 Context 不能挂在请求它的那个 Scoped 下。

### `demands`

```haskell
demands = [requests "StartURL", requires "CrawlSessionInfo"]
```

`demands` 是 `Demand` 列表，每一项用资产名声明驱动或读取一个资产。细化资产类型在 `Effects.hs` 中看不到，所以用名字字符串引用；handler 里只写表示类型。`Demand` 有三种写法：

| 枚举 | handler 中 | 含义 |
| --- | --- | --- |
| `requests "T"` | 不写 | 驱动：入口在 Input 之前重新生产一次 `T`，结果保存为当前绑定。单独的 `requests` 不带来读取权限 |
| `requires "T"` | `x <- require @表示类型` | 读取已有的值，不在入口驱动，也不在读取处生产；还没有值时等待之后的发布 |
| `streams "T"` | `xs <- require @(History 表示类型)` | 由持续资产 `T` 的新交付驱动，同时取得读取权限；只在 `lifelong` 内使用，见[持续资产与 lifelong](#stream) |

- **驱动与读取分开写**：既要刷新又要读取的资产写两项，例如 Crawler 的 `[requests "StartURL", requires "StartURL"]`。入口顺序是驱动 → Input → handler，因此 `requests` 驱动的值在前驱和 handler 中都已就绪。
- **来源自动确定**：每个资产恰好由一个 Context 声明，生成器按资产名自动接上，不用指名生产方。
- **读取按表示类型路由**：handler 的 `require @T` 由 gen 按“表示类型 + effect”路由到这个 effect 声明的那份细化资产；一个 effect 的 demands 里同一表示类型只能出现一次。同一种数据有不同含义时，声明成不同的资产，例如 Crawler 的 `StartURL` 和 `LinkedURL`，再由各自的 effect 选择。
- **同一资产可以声明多种合法访问方式**：同一资产的同一种方式只能声明一次。
- **限制**：Scoped 至多 `requests` 一个资源 Context；分支契约（见[资产书写](#types)）只能 `requires`；`requires` 需要生产方 `require = True`；挂在 Stream 下的资产不能 `requests`；`streams` 只能由 Excu、Scoped 声明，只能订阅持续资产的基础资产（`stream = True`）。
- **同一资产只有一个 Context 来源**：访问方式不改变资产的 ADT 或生产方；不限制一个消费者只能声明一个资产。
- **声明须有读取依据**：每个 `requires`／`streams` 的资产须在绑定的 handler 中读取，或参与现有 alternative 选择／streams 交付。
- **声明即权限**：handler 读取了 effect 没有声明的表示类型，生成器报错；读取实例只为声明了 `requires`／`streams` 的 effect 生成，运行时不再查声明表。

<a id="handlers"></a>

## 三、handler 书写（`Handlers.hs`）

先看一个完整 handler 的形态，模块头和导入在后文给出：

```haskell
instance ParseFileTextLayer m => ParseFileTextHandler m where
  parseFileText = do
    contents <- raw
    text <- case contents of
      [whole] -> pure whole
      _ -> raise (ParseFileTextError "File read returned no text")
    pure (if null text then Blank else Written text)
```

handler 是不带参数的类方法。注册里出现的每个 handler 名，在 `Handlers.hs` 中实现一个生成的类：Layer 指定方法体可用的能力，方法体写实际的读取、解析和 IO。方法体里不出现上游 effect、scope、细化资产或 effect 错误，这些由 gen 按注册装配。手写代码由 HLS 检查，运行时编译 `Generated/Handlers.hs` 中原样复制的方法体。下面依次展开文件头、instance 头和方法体规则。

### 文件头

```haskell
{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE UndecidableInstances #-}

{-# OPTIONS_GHC -Werror=missing-methods #-}

module FileDemo.Handlers () where

import Framework.SDK (Raises(..), Raw(..), Reads(..))   -- raise、raw、require
import FileDemo.Generated.Effects    -- 生成的 handler 类、Layer、错误类型
import FileDemo.Types
```

- `-Werror=missing-methods` 保证每个声明的方法都有实现。
- `Reads(..)`、`Raw(..)`、`Raises(..)` 按类导入：`require` 同时是注册字段名，按名字单独导入会产生歧义。只用到其中一部分时只导入需要的类；读取持续资产时另导入 `History` 与 `latest`、`historyEntries`、`historySize`。

### instance 头

```haskell
instance ReadFileContentLayer m => ReadFileContentHandler m where
```

- **`名字Handler m`**：由 handler 名（首字母大写）生成的类，只有这一个方法，签名由绑定方式决定。
- **`名字Layer m`**：生成的能力约束，由这个 handler 的各个绑定推出：

| 约束 | 什么时候有 | 方法体可写 |
| --- | --- | --- |
| `Reads T m` | 绑定它的 effect `requires` 了表示类型为 T 的资产 | `require @T` |
| `Reads (History T) m` | 绑定它的 effect `streams` 了持续资产 | `require @(History T)` |
| `Raw m` | 绑定成挂接的 parser 或 Pure | `raw` |
| `Raises 名字Error m` | 总是 | `raise (名字Error "...")` |
| `MonadIO m` | Pure 以外总是 | `liftIO` |

- **对载体 `m` 泛型**：Layer 不含 Input 的 effect 类、细化资产或其他 handler 的类，方法体只能使用上表的能力；越过 Layer 的读取，GHC 直接报错。单独的 `requests` 不带来 `Reads`。
- **一个 handler 一份 Layer**：同一个 handler 绑定到多个 effect 时，各绑定推出的签名和 Layer 必须一致，否则生成器报错。

### 各绑定方式的签名

| 绑定方式 | 签名 | 返回什么 |
| --- | --- | --- |
| Context.parser | `m 表示类型` | 表示类型的值，例如 `pure (Written text)` |
| Pure | `m [String]` | 变换后的 list，交给下面的 Pure 或 Context |
| Excu | `m [String]` | 交给挂接 Context 的 list，没有就 `pure []` |
| Scoped.open／close | `m [String]` | 同上；`close` 的输出没有挂接点 |
| Error.detect／resolve | `m ()` | 见下文「Error 的写法」 |
| Stream | `m String` | 一份原始输入 |

Context 的读取方法（`readT`／`streamT`）和全部入口由 SDK 生成，不用写。

### 方法体里的写法

| 写法 | 作用 |
| --- | --- |
| `x <- require @T`（普通资产） | 读取绑定的 effect 所声明、表示类型为 `T` 的资产；还没有值时等待发布，不生产 |
| `xs <- require @(History T)`（持续资产） | 取得本次交付为止的历史，用 `latest`／`historyEntries`／`historySize` 读取；须声明 `streams` |
| `output <- raw` | 挂接的 parser 或 Pure 读取直接 Input 本次交出的 `[String]`，句柄不再执行一遍；挂在 Stream 下时是会话本次取得的那份原始输入（单元素 list） |
| `raise (ReadFileContentError "message")` | 以本 handler 的错误失败；错误类型是 handler 名首字母大写加 `Error` |
| `pure [info]`、`pure (x : rest)` | Excu／Scoped／Pure 交出 list，交给挂在下面的 Pure 或 Context |
| `liftIO (...)` | 执行 IO（Pure 不可用） |

- **按表示类型读取**：`require` 必须显式写类型应用，例如 `FileHandle path file <- require @FileHandle`；可以直接在绑定处匹配表示类型的构造器，也可以先具名接收再 `case`。和类型的失败分支用 `raise`。
- **失败属于 handler**：错误类型由 handler 名决定，不随绑定改变；失败发生在哪个 effect 由 SDK 记录为 `origin`，Error 用 `RaisedBy "handler名"` 匹配。
- **刷新写在注册里**：方法体没有 `request`；需要重新生产的资产在注册里写 `requests`，由入口在 handler 之前驱动。

例如 [Crawler](../demo/Crawler/Handlers.hs) 中挂在抓取句柄下、由两个 Context 共用的 parser：

```haskell
instance ExtractSummaryLayer m => ExtractSummaryHandler m where
  extractSummary = do
    fetched <- raw                       -- 挂接句柄本次交出的 list：一页正文
    PageURL url <- require @PageURL      -- StartURL 或 LinkedURL，由绑定的 effect 决定
    html <- case fetched of
      [page] -> pure page
      _ -> raise (ExtractSummaryError (url ++ ": fetch returned no page body"))
    ...                                  -- 解析标题、段落和链接
    pure (PageSummary url title content links)
```

### Scoped 的写法

```haskell
instance OpenSessionLayer m => OpenSessionHandler m where
  openSession = pure []

instance CloseSessionLayer m => CloseSessionHandler m where
  closeSession = do
    FileHandle path file <- require @FileHandle
    outcome <- liftIO (tryIOError (hClose file))
    either (raise . CloseSessionError . displayException) pure outcome
    liftIO (putStrLn ("[close] " ++ path))
    pure []
```

- **资源获取写在资源 Context 的 parser**：FileDemo 中打开文件的是 `acquireFile`；Scoped 注册 `requests "OpenedFile"`，gen 在 `open` 之前驱动它，`open` 本身不必读取资源。
- **使用方不调用 `open`**：effect 的 `input` 是 Scoped 时，gen 在入口中开启它；实例已开启时 SDK 直接复用，跳过 `open` 的方法体。
- **不安排 `close`**：SDK 在使用闭包退出时自动清理（见「运行时行为」），handler 不调用 `close`。

### Error 的写法

```haskell
instance DetectFileSessionLayer m => DetectFileSessionHandler m where
  detectFileSession = do
    FileHandle _ file <- require @FileHandle
    outcome <- liftIO (tryIOError (hIsClosed file))
    closed <- either (raise . DetectFileSessionError . displayException) pure outcome
    unless closed $
      raise (DetectFileSessionError "File handle is still open; failure not located in FileSession")

-- TODO：Error 的处置是另一条驱动链，设计确定前 resolve 不做任何事。
instance ResolveFileSessionLayer m => ResolveFileSessionHandler m where
  resolveFileSession = pure ()
```

- **`detect`**：正常返回表示归此处，接着执行 `resolve`；`raise` 表示不归此处，继续检查其他 Error。
- **`resolve`**：设计确定前不操作 scope，也不重放读写。
- **处置之后**：原失败仍然继续传播。SDK 不会把失败变成成功，也不会自动重试或重开资源。

### 方法体的结构限制

生成器要从方法体中静态读出读取结构，所以：

- **不调用其他 handler**：方法体不能直接调用别的 handler 的类方法（包括同一模块里实现的），否则会绕过 effect 入口，丢失 Input、驱动和错误位置；生成器报错。组合写在注册（`input`、`demands`）和 AST 中。
- **读取直接写在方法体里**：支持 `do`、`if`／`case`、`when`、`catchError` 等常见写法；读取不能经未知的高阶组合传递。
- **普通计算**：不含读取的表达式使用原生 Haskell；方法体内的局部函数和 lambda 不限制，顶层不能定义普通函数（见[资产书写的使用规则](#types)）。

<a id="workflow"></a>

## 四、workflow 书写（`AST.hs`、`Workflow/*.hs`）

先看同一模块的两个文件。Workflow 定义具名 branch，AST 引用它：

```haskell
-- Workflow/OperateFile.hs
operateFile :: AST
operateFile = alternative
  [ node "WriteFirstLine"
  , node "AppendLine"
  ]

-- AST.hs
ast :: AST
ast = operateFile
```

这两段是 FileDemo 对应文件的节选。AST 描述哪些完整链按什么方式启动；node 只选择末端，链内的前驱与驱动由注册决定，gen 装配进末端的入口。

### 两种构件

| 构件 | 写法 | 类型 | 含义 |
| --- | --- | --- | --- |
| node | `node "effect名"` | `EffectNode` | 选择一条操作链的末端 effect |
| branch | `chained`、`parallel`、`alternative` 或 `lifelong` 加子项列表 | `AST` | 组合 node 或其他 branch |

- **node 不是 AST**：顶层和每个模块都必须是 branch，单个 node 也要包进一个 branch。
- **子项列表同质**：一个列表要么全是 node，要么全是 branch，不能混排。
- **空列表**：须标注元素类型，例如 `chained ([] :: [AST])`。

### node

- **只选原始句柄**：选中的 effect 必须是 Excu 或 Scoped，不能是 Pure、Context、Stream 或 Error。
- **运行即执行入口**：入口先按 `requests` 驱动资产，再执行 Input 链上的前驱，最后执行绑定的 handler（Scoped 末端执行 `open`）。Input 链不需要在 AST 里重写。
- **node 结果不隐式传值**：一个 node 的结果不会交给下一个 node，值的传递只经 Context。后继 `require` 可读取 AST 因果顺序中唯一可见的发布来源；并行兄弟之间不按谁先完成决定读谁的值。

### branch 的四种类型

| branch | 子项如何执行 | 失败时 | 结果 |
| --- | --- | --- | --- |
| `chained` | 按顺序逐个执行 | 立即停止，后面的子项不执行 | 各子项结果按顺序拼接 |
| `parallel` | 同时执行 | 等全部子项结束，按声明顺序取第一个失败 | 全部成功时按声明顺序拼接 |
| `alternative` | 只执行一个候选 | 候选的失败原样传播 | 只有被选中候选的结果 |
| `lifelong` | 各单元独立重复执行，到达 target 时等待其订阅资产的交付 | 终止整次运行（临时规则） | 没有正常结束 |

程序里含 `lifelong` 时，`parallel` 中任何子项失败也立即终止整次运行，不再等待其他子项结束。

#### `chained`

```haskell
-- Crawler/AST.hs：先并行抓取，全部成功后顺序打印
ast = chained [parsePages, printPages]
```

#### `parallel`

```haskell
-- Crawler/Workflow/ParsePages.hs
parsePages = parallel [node "FetchPage", node "FetchLinkedPage"]
```

#### `alternative`

```haskell
-- FileDemo/Workflow/OperateFile.hs：文件为空时写首行，否则追加
operateFile = alternative [node "WriteFirstLine", node "AppendLine"]
```

- **只列候选，不写条件**：选哪一个由一个和类型资产的当前构造器决定，AST 不暴露业务状态。
- **候选怎么对应构造器**：每个候选（末端及其 Input 链上游）在 `demands` 里 `requires` 恰好一个同一资产的分支契约，生成器据此推出它对应的构造器。候选必须覆盖全部构造器，且不能重复。FileDemo 中 `WriteFirstLine` 依赖 `FileTextBlank`，`AppendLine` 依赖 `FileTextWritten`。
- **运行时**：选择读取自己驱动这个资产，相当于写了 `requests`：先执行它的生产链（FileDemo 里是读文件再解析），再启动对应的候选，并把选择时取得的值交给候选；没被选中的候选不执行，也不出现在结果中。持续资产由会话驱动，选择读取领取本次交付。
- 分支契约怎么产生，见[资产书写](#types)。

#### `lifelong`

```haskell
-- StreamDemo/Workflow/Monitor.hs：每条新读数显示并分析一次，心跳单元独立推进
monitor = lifelong
  [ chained [node "ShowTemperature", node "CheckTrend"]
  , chained [node "ReportHeartbeat"]
  ]
```

- **单元**：直接子项各是一个独立推进的单元，上例的读数单元和心跳单元互不等待。
- **一次执行**：每个末端用 `streams` 订阅一个持续资产；执行到它时先领取一条新交付（没有就等待），本次执行完成后才开始下一次。
- **不会正常结束**：放在 lifelong 后面的 branch 不会执行；含 lifelong 的程序中任何失败都会结束整次运行（临时规则）。

单元划分、交付、会话与失败的完整写法见[持续资产与 lifelong](#stream)。

### 文件组织

- 每个 branch 放在 `Workflow/` 下单独的文件里，顶层 `AST.hs` 用非限定 import 只组合这些名字。
- `AST.hs` 和 `Workflow/*.hs` 不导入 `Generated` 或 `Handlers`。

### 运行与查看

- **运行**：`main = interpreter ast effects`，结果打印为 `Succ [...]` 或 `Failed ...`，例如 FileDemo 输出 `Succ [AppendLineResult ()]`。原子句柄交出的 `[String]` 不是业务产物，在结果中记为 `()`。
- **查看结构**：使用[命令行的 structure 模式](#commands)查看生成器推导的调用结构和资源依赖。

<a id="stream"></a>

## 五、持续资产与 lifelong（Stream）

前四节的程序是有限的：每个 node 执行一次。持续数据源（传感器、socket、消息队列、定时采样）同样通过 Context 对外提供资产：Stream effect 取得原始输入，挂在它下面的 Context 以 parser 解析并声明 `stream = True`，`lifelong` 根据交付就绪情况启动消费方。下面用 [StreamDemo](../demo/StreamDemo) 展示；完整规则见 [Stream 与 lifelong](STREAM_LIFELONG.md)。

### 注册：Stream 加 parser

以下节选 StreamDemo 的注册：

```haskell
EffectSpec
  { name = "TemperatureFeed"
  , typing = Stream { handler = Just "nextReading" }
  , input = "SensorLink"
  , demands = []
  }

EffectSpec
  { name = "TemperatureParser"
  , typing = Context { asset = Asset @Temperature "TemperatureSample", parser = Just "parseTemperature", require = True, stream = True }
  , input = "TemperatureFeed"
  , demands = []
  }

EffectSpec
  { name = "HeartbeatClock"
  , typing = Stream { handler = Just "nextBeat" }
  , input = "Root"
  , demands = []
  }

EffectSpec
  { name = "Heartbeat"
  , typing = Context { asset = Asset @Int "Beat", parser = Just "parseBeat", require = True, stream = True }
  , input = "HeartbeatClock"
  , demands = []
  }

EffectSpec
  { name = "ShowTemperature"
  , typing = Excu { handler = Just "showTemperature" }
  , input = "Root"
  , demands = [streams "TemperatureSample"]
  }
```

持续交付只由上游 Stream 驱动：会话反复执行 Stream 的 handler 取得原始输入，交给挂在下面的 parser 解析并发布。声明规则：

- **`stream = True` 当且仅当 Input 是 Stream**，且必须同时 `require = True`；挂在 Stream 下的 Context 必须声明 `stream = True`。
- **一个 Stream 恰好有一个 Context 以它为 `input`**，作为它的 parser。
- **挂在 Stream 下的资产只由会话生产**：消费方不能 `requests` 它。
- **订阅**：消费方写 `streams "T"`，表示由 T 的新交付驱动，同时取得读取权限，handler 用 `require @(History 表示类型)` 读取到本次交付为止的历史。
- **只读最新值**：`requires "T"` 读取持续资产时，handler 用 `require @表示类型` 取得最新一条，不由交付驱动。`stream` 缓存历史，`require` 缓存最新值。

### 驱动方式

持续数据通常以 socket（外部持续送来）、behavior（值一直存在，随时采样）或 event（离散发生）三种方式到来。它们在 SDK 中如何区分尚未确定，目前都写成 Stream 加 parser，节奏由 Stream handler 自己的阻塞或等待决定：

| 驱动关系 | 例子 | 现在怎么写 |
| --- | --- | --- |
| socket | 连接、消息队列、传感器 | Stream handler 阻塞接收一份原始输入（StreamDemo 的 `TemperatureFeed`＋`TemperatureParser`） |
| behavior | 时钟、心跳、状态轮询 | Stream handler 先等待采样间隔，再取当前值（StreamDemo 的 `HeartbeatClock`＋`Heartbeat`） |
| event | 事件队列、由回调转成的阻塞等待 | Stream handler 阻塞读取下一个事件 |

外部回调不能直接注册给 SDK，需要先转换成可阻塞读取的队列。详细规则见 [Stream 规范 4.1 节](STREAM_LIFELONG.md#drives)。

### handler：每次只处理一份

```haskell
instance NextReadingLayer m => NextReadingHandler m where
  nextReading = do
    liftIO (threadDelay 700000)
    seconds <- liftIO getMonotonicTime
    pure (printf "%.1f" (21 + 3 * sin (seconds / 3) :: Double))

instance ParseTemperatureLayer m => ParseTemperatureHandler m where
  parseTemperature = do
    reading <- concat <$> raw
    case reads reading of
      [(value, "")] -> pure (Temperature value)
      _ -> raise (ParseTemperatureError ("unreadable sensor output: " ++ reading))

instance ShowTemperatureLayer m => ShowTemperatureHandler m where
  showTemperature = do
    samples <- require @(History Temperature)
    case latest samples of
      Just (Temperature value) ->
        liftIO (printf "reading #%d: %.1f C\n" (length (historyEntries samples)) value)
      Nothing -> pure ()
    pure []
```

- **Stream handler**一次返回一份原始输入；节奏由方法体自己的阻塞或等待决定，SDK 不加间隔，立即返回的方法会持续高频运行。它的 Input（这里是 `SensorLink`）由 gen 作为前驱装配：传感器连接在第一次读数时开启，并在会话的各步骤间保持。
- **parser** 和挂在 Excu 下的 Context 写法相同：`raw` 是会话本次取得的那份原始输入（单元素 list，这里用 `concat` 取出），不会再执行 Stream handler 另取一份。发布、历史和交付都由 SDK 完成，方法体里不写循环、发布或回调。
- **`History T`**：从会话首条发布到本次交付为止的不可变序列。`latest` 取本次交付的那一条，`historyEntries` 取全部，`historySize` 取条数；相等的两次发布是两条。

[完整 Effects.hs](../demo/StreamDemo/Effects.hs) · [完整 Handlers.hs](../demo/StreamDemo/Handlers.hs)

### workflow：lifelong

```haskell
-- Workflow/Monitor.hs
monitor = lifelong
  [ chained [node "ShowTemperature", node "CheckTrend"]
  , chained [node "ReportHeartbeat"]
  ]

-- AST.hs：先执行一次准备，再进入持续监控
ast = chained [setup, monitor]
```

- **单元**：lifelong 的每个直接子项是一个单元；直接子项是 `parallel` 时拆开这一层，其子项分别是单元。各单元同时运行，互不等待。
- **一次执行**：控制流到达 target 时领取其订阅资产的交付，再 boot 该 target；单元本轮完整结束后才开始下一轮。有积压时立即领取，没有就挂起等待，不反复调用 handler 试探数据。一个单元内不同 target 可以由不同资产驱动，各自到达时等待对应交付。同一次执行里，每个资产只领取一次，后面的节点（包括并行节点、alternative 的选择与候选）读到同一份视图；StreamDemo 中 `ShowTemperature` 和 `CheckTrend` 看到的是同一条读数。
- **每次执行互相隔离**：上一次执行中产生的普通资产不会被这一次读到。
- **订阅规则**：lifelong 里的每个末端（连同它的 Input 链）恰好订阅一个持续资产，并且不再读取别的持续资产；`streams` 不能用在 lifelong 外的末端。lifelong 不能嵌套，内部不能有空分支。
- **会话**：同一个 lifelong 里订阅同一资产的单元共享一个生产会话，各自独立推进；不同 lifelong 的会话互相独立。会话在进入 lifelong 时启动；生产步骤用到的资源（例如 `SensorLink` 开启的连接）在各步骤间保持，退出时关闭。持续资产的生产不能依赖另一个持续资产。
- **外部组合**：`chained [setup, monitor]` 先执行 setup；lifelong 没有正常结束，排在它后面的节点不会执行；`parallel [monitor, otherWork]` 两者同时运行。

### 结束与失败

- **没有正常结束**：持续程序运行到被取消（Ctrl-C）为止。取消时 SDK 停止全部单元和会话，等它们收尾，再按 ScopeTree 关闭资源；StreamDemo 会打印 `[sensor] disconnected`。
- **失败（临时规则）**：程序里含 lifelong 时，结构化失败（生产、解析、某个单元或任何 branch）在完成 Error 诊断后终止整次运行：取消全部任务、等待收尾，最后报告最初的那个失败；原生异常直接进入监督并在收尾后重新抛出。lifelong 的 close 语义设计后再改为局部结束。
- **lifelong 外读取持续资产**：普通 `requires "T"` 只读取一次，取得最新一条。没有交付时，由 interpreter 托管的会话产出（至少等到一条）；这个会话保持到程序退出。

### 运行与查看

```sh
cabal run effect-codegen -- workflow StreamDemo
cabal run stream-demo -- --structure
cabal run stream-demo
```

`--structure` 的 `Workflow` 部分列出每个 lifelong 的单元、会话（生产方式与挂载位置）和订阅关系，`Interpreter sessions` 列出 lifelong 外读取时使用的会话。运行输出类似：

```text
Monitoring the sensor; press Ctrl-C to stop.
[sensor] connected
reading #1: 23.9 C
  trend: waiting for a second reading
reading #2: 24.0 C
  trend rising, average of the last 2: 23.95 C
[heartbeat] #1
...
[sensor] disconnected
```

<a id="runtime-behavior"></a>

## 运行时行为

以下是使用时需要了解的概述；完整协议及例外见[当前运行协议](LATEST_DESIGN.md#runtime)，来源与可见性见[EffectGraph](EFFECT_GRAPH.md)。

### 驱动与读取：`requests` 与 `require`

- **`requests` 驱动**：入口在 Input 之前执行资产的 `getT`，每次重新生产，成功后以当前入口的 origin 保存并替换该 origin 的绑定；生产失败时不覆盖旧值，原失败继续传播。
- **`require` 读取**：handler 的 `require @T` 经路由进入资产的 `readT`：先读当前调用已捕获的绑定，再查原型许可的唯一可见来源。读取不生产：仍没有值时，像 await 一样阻塞这条链，等之后的发布再读，不报错。第一次读取后绑定固定，其他调用的发布不原地改写它。
- **值从哪里来**：`requests` 驱动、alternative 的选择读取、挂接句柄的注入，以及 Stream 会话。要读的值必须有人驱动；例如 FileDemo 的 `FileResource` 写了 `[requests "FileName", requires "FileName"]`，取得文件前先驱动文件名的生产链（`LocateFile` → `ValidateFileName` → `FileLocation`），`acquireFile` 再读取它。
- **跨 node 保存**：发布时无资源 owner 的值按 origin 保存，后补 owner 保留原发布记录；open 内一开始就有 owner 的产物只留在 scope／当前调用。一个来源在 AST 中保证先于当前节点完成，或属于当前入口时才可见；并行兄弟互不可见。需要跨链解析的读取路径若有多个同时可见来源，就需细化契约或调整编排，生成器不会选“最后写入”的那个。
- **可见范围内没人生产就一直等**：并行兄弟互不可见，前驱已经完成；所以一个读取在可见范围内没有 `requests` 或会话生产时，这条链会一直等待，SDK 不替它补产，也不报错。资源、Error 诊断、自动收尾与 close 期间不等待，缺值时报 `ContextNotInitialized`。
- **部分路径已取值合法**：已经捕获值的分支直接使用该绑定，只有尚未取值的路径需要解析唯一来源。alternative 或可选生产的条件可证明这些路径的来源唯一；已捕获路径上允许多个节点共同发布，由已有快照确定读取值。

<a id="runtime-anchored"></a>

### 挂在句柄下的 Context

- **句柄在操作链里执行时**：句柄返回后，SDK 自动用这次的输出运行挂在下面的 parser（`raw` 由本次输出回答），产出的值保存起来，不会再执行一次句柄。调用句柄的那条链照常继续，不受影响；解析失败只留在这次注入里，值没有发布，之后读取它的位置等待下一次发布。
- **被驱动时**：`requests` 或 alternative 的选择读取进入 Context 的 `getT`，parser 的 `raw` 执行所挂句柄的入口，由此启动生产链。
- **中间有一串 Pure 时**：挂接点是最上面的句柄，句柄的输出依次经过每个 Pure 再交给 parser。注入时 Pure 读到的是本次输出，不重新执行句柄；被驱动时 Pure 的 `raw` 执行句柄入口。Pure 的 `raise` 按解析失败处理：注入时留在注入里，被驱动时向上传播。

所以 Crawler 先并行抓取，打印时直接 `require` 解析好的摘要，不再重新抓取。

### 资源：共享、新建与自动关闭

资源实例由 Scoped 注册与开启参数的那一次生产共同确定。`requests` 产生新身份，`requires` 引用已有身份；参数值相等并不意味着同一个实例，参数类型不需要 `Eq`。

| 写法 | 实际行为 |
| --- | --- |
| 资源没有开启参数 | 同一个 Scoped 共用注册级单例 |
| 前驱 `requests` 参数，后继及资源 parser 只 `requires` 它 | 读到同一次生产的开启共享实例，即使节点依次执行或并行分支没有实际重叠 |
| 每条开启链或资源 Context 各自 `requests` 参数 | 每次新生产对应新实例；后继仍可通过读取同一次生产共享它 |

ScopeReuseDemo 的字段节选展示共享写法：

```haskell
-- PrepareProbe 先生产一次 FilePaths。
EffectSpec { name = "PrepareProbe", typing = Excu { .. }, input = "Root", demands = [requests "FilePaths", requires "FilePaths"] }
-- 资源 parser 读取已有参数，writer 经 Input 开启同一个 scope。
EffectSpec { name = "FileResource", typing = Context { .. }, input = "Root", demands = [requires "FilePaths"] }
EffectSpec { name = "WriteFirst", typing = Excu { .. }, input = "SharedFileScope", demands = [requires "OpenedFile"] }
```

- **自动关闭**：SDK 等当前调用的业务、诊断和结果消费结束，再撤销使用；同时检查后续仍待用的节点及子 scope。全部不再触达实例时同步执行 close，完成后继续后继。嵌套 Context 生产返回不会提前关闭资源。
- **lifelong**：无参数或参数来自外层的实例跨轮保留；本轮新生产参数的实例属于本轮，轮内后继共享不改变归属，本轮结束回收。
- **资源读取**：消费资源的链须先经 Input 开启其所属 Scoped，否则生成期报错；不能因为别的链还开着某个实例就直接读取它。
- **close 可选**：handler 不手动调用 close。`close = Nothing` 时，不可达实例只移出运行表，不执行释放 IO。整次运行结束时同样遵守这条规则。
- **关闭失败**：close 的业务失败经 Error 诊断后单独记录、运行结束汇总，不改变业务结果，也不重试。取消发生在 close 中仍会停止后续工作，完成其余收尾后向外传播。

SDK 不主动检查健康，不自动恢复或重开失效实例。资源共享只交接带 owner 的绑定，scope 快照中的普通辅助值仍按来源表读取。诊断和 cleanup 中的新产物只留局部快照。

每次生产的绑定保留自己的值、生产身份、出身和共享 ownership。资源被 scope 首次认领后，已有引用看见同一个 owner；其他实例不能再次认领。SDK 同时接入仍活跃的使用者，防止认领后提前关闭；两次生产私下包装同一个底层 Handle 的物理别名仍不追踪。完整规则见[主设计：scope](LATEST_DESIGN.md#scope)。

### 失败与 Error 处置

- **失败的形态**：每个 handler 自动获得错误类型 `名字Error String`，用 `raise` 抛出，分类是 `名字Failure`，不随绑定改变。失败沿调用链原样传播，记录发生的 effect（`origin`）、分类和消息；程序最终返回 `Succ 结果` 或 `Failed 失败信息`。
- **Error 处置**：SDK 捕获失败后，按 `handles` 匹配失败路径上 scope 关联的 Error，沿资源依赖从外层到内层依次执行它们的 `detect`／`resolve`。不在任何 scope 中的失败不经 Error 处置。
- **处置不改变结果**：业务调用的原失败在处置后继续传播。自动 close 的失败处置后只进入关闭报告，不改变业务调用的结果。

<a id="sdk-faults"></a>
#### SDK 协议故障

除了 handler 自己 `raise` 的失败，SDK 在取值和资源生命周期出错时也报失败。这些故障只有两个类型，定义在 [Protocol.hs](../sdk/Framework/Runtime/Protocol.hs)；每个程序生成的 `Errors` 里各有一个固定构造器承载它们：

- **`ContextBindingError ContextFault`**：取值协议故障。`origin` 是生产这份资产的 Context 注册名（不是契约名），Error 用 `ContextFaultIn "该 Context"` 匹配。
- **`ScopeBindingError ScopeFault`**：资源协议故障。`origin` 是 Scoped 的注册名，Error 用 `ScopeFaultIn "该 Scoped"` 匹配。

它们按 scope 进入 Error 处置；发生在业务调用中时沿链传播并以 `Failed` 返回，发生在自动 close 中时只进入关闭报告。完整协议见[主设计：Context](LATEST_DESIGN.md#context)与 [scope](LATEST_DESIGN.md#scope)。

**取值故障（`ContextFault`）**

| 故障 | 什么时候报 | 怎么改 |
| --- | --- | --- |
| `ContextNotInitialized` | 在不等待的场合缺值：Error 诊断、自动收尾与 close 期间；读取 scope 的资源 Context，却没有本链已开启实例的绑定；持续资产在不能启动会话的场合（诊断、收尾）没有本次视图。普通业务读取缺值时等待发布，不报这个故障 | 在读取之前的链上用 `requests` 驱动它；资源只在 scope 内读取（Input 链上有对应的 Scoped） |
| `AmbiguousContextBinding` | 普通资产有多个已发布的可见来源，运行时无法确定唯一绑定；生成期通常已拦下 | 细化资产或调整 AST，确保实际来源唯一 |
| `CaseNotSelected 契约` | 读取和类型资产的分支契约（例如 `FileTextBlank`），资产当前却是另一个构造器 | 分支契约只在选中对应构造器的 alternative 候选中读取；其他地方读取基础资产再 `case` |

**资源故障（`ScopeFault`）**

close 由 SDK 的自动收尾调用，handler 不直接调用；下表中的 close 都指这个过程。

| 故障 | 什么时候报 | 怎么改 |
| --- | --- | --- |
| `ScopeInputsMissing [参数]` | 带开启参数的 scope 要在参数齐备后才能选定实例；资源发布或 open 结束时仍有参数没读到，例如资源 parser 先获取资源、后读取参数。持续资产作为开启参数时也会报，这是当前限制（见 [Stream 规范 9.3](STREAM_LIFELONG.md#failures)） | 先安排参数生产；资源 parser 先读参数，再获取资源。共享时读取前驱的同一次生产 |
| `ScopeInputAfterOpen 参数` | 实例选定之后，这次开启读到另一份参数生产；即使新旧值相等也不同 | 选定实例前确定全部参数；open 范围内不再刷新参数 |
| `ScopeContextMismatch 资源` | 一份资源绑定只能归一个实例：open 要认领的资源已属于另一个 scope 或同注册的另一个实例；或 close 读到的资源属于别的实例 | 不同实例各自驱动自己的资源，不共用同一次生产 |
| `ScopeContextMissing 资源` | open 结束时，选中的实例里没有资源绑定；或 close 定位不到要关闭的实例：本次调用没有这个 scope 的资源绑定，或 close 的 handler 没有读取资源 | Scoped 在 demands 里 `requests` 并 `requires` 资源；open／close 的 handler 用 `require` 读取资源 |
| `ScopeReentry` | 同一个 scope 在自己的 open 或 close 过程中又被 open 或 close。生成期的环检查通常会先拦下 | 调整 `input`／`demands`，让 scope 不依赖自身 |
| `ScopeCleanupInProgress` | 自动收尾或 close 执行期间，调用链又要开启 scope | close 经过的链上不开启 scope |
| `ScopeInUse` | SDK 内部使用、依赖或关闭预约不变量冲突；自动 close 应只处理不可达实例 | 按 SDK 问题报告，并附注册、workflow 与故障信息；不要据此添加业务重试 |
| `ScopeIsClosed` | 实例 close 之后，又读取本次调用早先捕获的、属于它的资源绑定 | 只在 scope 的使用范围内读取资源 |
| `ScopeInterrupted 原因` | open 或 close 被原生异常打断，实例失效；尚保留的同生产实例继续携带原失败 | 检查 IO；可预期错误用 `raise`，外部取消照常传播 |
| `ScopeCleanupInterrupted 原因` | 自动 close 被原生异常打断；记录后不重试，取消仍向外传播 | 检查 close 中的 IO，不将外部取消改成业务重试 |
| `ScopeNotOpen` | close 遇到从未开启的实例 | 自动收尾只为开启过的实例登记 close，正常写法不会触发；出现时按 SDK 问题报告 |

open 方法体自己 `raise` 时，实例同样失效；尚保留的同生产实例继续报告那次原失败。close 的失败只汇总报告，不重试已尝试的关闭。

**不走 Failure 的错误**：少数情况直接抛出 IO 异常，不进入 Error 处置。生成产物与当前程序不一致时（提示 `changed or has not been generated`，或 `Cannot initialize effect prototype`），按提示重新生成；运行结束时仍要启动会话、运行图中找不到生成的结构等，表示 SDK 内部约定被打破，重新生成后仍出现时按 SDK 问题报告。

<a id="development"></a>

## 开发流程

修改手写文件后，按[命令行与执行阶段](#commands)完成“生成 → 按需查看结构 → 运行”；整个仓库的编译使用 `cabal build all`。生成命令显式执行，普通构建不会更新 Generated。

- **编辑器支持**：`Handlers.hs` 是普通 Haskell，可以在编辑器里用 HLS 检查（配置见 `hie.yaml`，HLS 需匹配 GHC 9.12.2）。它依赖的 `Generated/Effects.hs` 要先生成出来。
- **新 effect 的顺序**：先注册、生成接口，再写 handler，然后再生成一次。复用已有 handler 的注册不需要新写 handler。
- **检查分工**：HLS／GHC 检查 Haskell 语法与类型（越过 Layer 的读取由 GHC 拒绝）；gencode 另检查注册、handler 绑定、读取路由、可提取的结构和顶层定义；运行与结构查看再核对生成快照是否仍与当前程序一致。

### 生成器会检查什么

生成器不只是生成代码，还会拒绝以下写法，并给出原因：

| 情况 | 处理方式 |
| --- | --- |
| effect 名重复，或用了保留名 `Root`；资产名与 effect 名、生成区名字重名；handler 名不是小写标识符，或与生成的入口方法名重名 | 换一个按业务含义起的 effect 名、资产名或 handler 名 |
| 两个 Context 声明同一资产名；资产名与某个和类型资产的分支契约重名 | 每个 refined asset 保留唯一来源；不同业务来源使用不同资产名 |
| 资产名不是类型名的形式；资产的表示类型是 SDK 的 `Output` | 资产名用大写开头的名字，如 `StartURL`；表示类型用业务 ADT |
| `demands` 里的资产名没有对应的生产方；同一项 demand 写了两次；`input` 或 `node` 引用了不存在的 effect | 检查名字：资产名就是生产方 `Asset` 声明的名字，effect 名就是注册的 `name`；删掉重复的 demand |
| Context、Pure 或 Stream 没有绑定 handler；作为 Input 的 Scoped 没有同时声明 `open` 和 `close` | 补上 handler 名 |
| Scoped `requests` 了多个资源 Context；资源 Context 的 `input` 挂在请求它的 Scoped 下 | 一个 Scoped 至多一个资源 Context；资源 Context 不挂在自己所属的 scope 下 |
| `input`／`demands` 形成环；handler 方法之间的调用成环；scope 之间的依赖成环 | 拆开环，让前驱、驱动和资源依赖只沿一个方向 |
| `requires` 了 `require = False` 的资产；`requests` 了挂在 Stream 下的资产 | 在生产方打开 `require`，或去掉这项 demand；持续资产由会话生产 |
| 一个 effect 的 demands 里有两个表示类型相同的资产 | 用不同的表示类型（角色类型）区分，或拆成两个 effect |
| handler 读取了绑定它的某个 effect 没有声明的表示类型；或非挂接的 handler 使用 `raw` | 在该 effect 的 demands 里补上声明；`raw` 只给挂接的 parser 与 Pure |
| Pure 写了 demands、`input` 是 Root 或 Stream、下面没有 Context 或 Pure，或被 Excu／Scoped／Stream／Error 当作 `input` | Pure 只在生产链中：值从上层句柄或 Pure 的 `raw` 来，交给下面的 Pure 或 Context |
| `require` 没有写类型应用 | 写成 `require @表示类型` |
| 同一个 handler 的各个绑定推出不同的签名或 Layer | 只在绑定方式与读取一致处复用 handler，否则拆成两个 handler |
| effect 声明的 `requires`／`streams` 资产，绑定的 handler 既不读取，也不参与 alternative 选择／streams 交付 | 读取它，或删掉无用声明 |
| handler 直接调用另一个 handler 的类方法 | 通过注册（`input`、`demands`）和 AST 组合 |
| 读取经未知的高阶组合传递；`require`／`raw` 出现在 guard、模式、`let`／`where`、`if` 条件或 `case` 的被匹配值中；混用运算符没加括号；方法体使用 `RebindableSyntax` | 先在 `do` 中用 `x <- require @T` 绑定，再使用；支持 `do`、`if`／`case`、`when`、`catchError` 等常见写法 |
| `Handlers.hs` 没有直接导入生成的 `Generated.Effects`，结构分析找不到 handler 类 | 直接 `import 程序名.Generated.Effects` |
| 业务模块顶层定义了普通函数、类、foreign 声明或 rewrite rule | 值操作移进 handler 方法体；`Effects.hs` 的辅助写进 `effects` 的 `where` |
| `input` 指向 Context 或 Error；Error 的 `handles` 为空、关联不到恰好一个 scope，或与同一 scope 下的另一个 Error 处理同一种失败；`RaisedBy` 写的不是已注册的 handler 名 | Context 经 demands 接入；Error 的 Input 链上要有 Scoped；同一 scope 下每种失败只由一个 Error 处理；`RaisedBy` 写 handler 名 |
| `alternative` 的候选没有依赖分支契约、依赖了多个，或候选没覆盖和类型的全部构造器；分支契约被写成 `requests` | 每个候选 `requires` 恰好一个分支契约，候选覆盖全部构造器；分支契约只能 `requires` |
| AST 的 node 选中了 Pure、Context、Error 或 Stream；别的方法直接调用到 Stream 的 handler | node 只挂 Excu 或 Scoped；Pure 与 Context 在生产链中由挂接、驱动、合法读取或生产会话带起；Stream 只由生产会话和挂在它下面的 parser 调用，Error 由失败协议调用 |
| 挂接的 Context 经别的方法、而不是直接或经 Pure 用 `raw` 到达它挂接的句柄 | parser 用 `raw` 读取挂接句柄，中间只经过 Pure |
| 某个 Context 从 AST 出发永远到不了：没有挂接句柄、`requests` 驱动或选择读取，也没有 lifelong 订阅生产会话带起它（只被 `requires` 读取不算） | 在读取它的链上写 `requests` 驱动它，或把带起它的消费链加进 AST，或删掉这个 Context |
| 尚未取值的读取路径上，同一资产有多个可能同时发布的可见来源 | 细化资产或调整 AST；alternative 和可选生产的条件可证明互斥时允许多个候选 |
| 持续资产的声明不成立：`stream = True` 的 Context 不在 Stream 下，或没有同时 `require = True`；Stream 下的 Context 没写 `stream = True`；Stream 下不是恰好一个 Context，或 parser 以外的 effect 以 Stream 为 `input`；`streams` 订阅了普通资产或分支契约，或由 Excu、Scoped 以外的 effect 声明 | 按[持续资产的声明规则](#stream)修正 |
| `streams` 写在 lifelong 外的末端上；lifelong 嵌套或含空分支；lifelong 里的末端没有恰好订阅一个持续资产，或另外读取了别的持续资产 | 按 [lifelong 的规则](#stream)调整注册或 AST |
| lifelong 中持续资产的生产链依赖另一个持续资产 | 首次交付会等待另一个 stream；改用普通资产作为生产前提 |
| lifelong 中读取生产会话步骤发布的普通资产（伴随发布），读取它的末端却不由这个持续资产驱动 | 只在由该持续资产驱动的末端读取，或在 lifelong 之前生产它 |

这些规则保证：组合关系总能从注册与 AST 中静态读出来，不会藏在任意函数里。生成器打印的英文消息给出具体的 effect、资产和位置；运行时才能发现的问题见 [SDK 协议故障](#sdk-faults)。

### 新建一个程序

1. **手写声明**：在 `demo/MyDemo/` 下写 `Types.hs`、`Effects.hs`、`AST.hs` 和 `Workflow/*.hs`。它们不能导入 `Generated` 或 `Handlers`。
2. **生成接口**：运行 `cabal run effect-codegen -- workflow MyDemo`。此时还没有 `Handlers.hs`，生成器会先产出可编译的空实现模块。
3. **写实现**：根据 `Generated/Effects.hs` 中的 handler 类与 Layer 编写 `Handlers.hs`，再生成一次，并写 `Main.hs`。
4. **加入构建**：参考 [cabal 文件](../algebraic-effect-sys-in-haskell.cabal) 中的 `file-demo` 增加一个 executable。

<a id="examples"></a>

## 示例

| 示例 | 演示内容 | 运行 |
| --- | --- | --- |
| [FileDemo](../demo/FileDemo) | 文件资源的开启、读写、自动关闭，Error 处置；按文件状态用 `alternative` 选择写首行或追加 | `cabal run file-demo` |
| [Crawler](../demo/Crawler) | 并行抓取、挂接的 Context 解析，顺序打印时读取解析结果；两条链共用抓取、解析与打印 handler，用不同资产区分同类数据 | `cabal run crawler-demo` |
| [OpenFilesDemo](../demo/OpenFilesDemo) | 一个资源持有多个文件；检查快照挂在释放链下，链结束后自动关闭与重开 | `cabal run open-files-demo` |
| [ScopeInstancesDemo](../demo/ScopeInstancesDemo) | 三条使用闭包共用一个 handler，按当前参数各自开启实例，退出时关闭，后一条重新开启 | `cabal run scope-instances-demo` |
| [ScopeReuseDemo](../demo/ScopeReuseDemo) | 并行的链共享同一个资源实例 | `cabal run scope-reuse-demo` |
| [StreamDemo](../demo/StreamDemo) | 持续读数与心跳（各为 Stream＋parser）、lifelong 的两个独立单元；会话跨步骤保持传感器连接 | `cabal run stream-demo`（持续运行，Ctrl-C 结束） |
| [FacadeProbe](../demo/FacadeProbe) | 原子 handler 复用：同一套打开、写入、读取、解析和打印 handler 服务报表与回复两条业务；不进入 Cabal 构建 | 见 [README](../demo/FacadeProbe/README.md) |

Crawler 需要网络和 PATH 上的 `curl`。文件类示例的输出写在各自目录下，已加入 Git 忽略。

<a id="limitations"></a>

## 当前限制

- **未实现的能力**：middleware、通用结构适配尚未实现。Stream／lifelong 的结束与清理进入本轮[六阶段计划](NEXT_STAGES.md#stages)，middleware 保留为[后续专题](NEXT_STAGES.md#middleware)。本指南只描述当前写法。
- **持续执行的延期项**：没有正常结束（EOF）、Stream close、嵌套 lifelong、自动重试和背压；lifelong 中的失败暂时终止整次运行；完整历史一直保留，持续运行时内存随发布增长。见 [Stream 规范的延期项](STREAM_LIFELONG.md#deferred)。
- **Stage 3 已知实现限制**：持续资产作为 scope 开启参数尚未接通。见 [Next stages](NEXT_STAGES.md#current-limits)。
- **handler 复用的边界**：同一个 handler 可以注册到多个 effect，但各绑定的方法类型与 Layer 必须一致；一个 effect 内同一表示类型只能读一份资产。Stream 的驱动方式和 Error 的驱动链仍待确定，见 [Stage 2：本阶段不处理](NEXT_STAGES.md#stage-2-later)。
- **资源清理范围**：自动清理覆盖交给 SDK 管理的资源；业务代码自己 `forkIO` 出的线程，或在 IO 中途获取、尚未交给 SDK 的资源，需要自行处理。实例按参数生产身份共享、按剩余程序可达性回收，见[主设计](LATEST_DESIGN.md#scope-identity)；持续资产作为开启参数、历史资源精细释放与正常 end 仍待后续阶段。
- **构建方式**：SDK 目前随仓库内的示例一起编译，不能作为独立依赖引入。
