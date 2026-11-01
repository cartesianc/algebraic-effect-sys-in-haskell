# 使用指南：代码形态与编写

状态：本文说明当前 SDK 可运行的接口，包括持续资产（Stream、`streams`、`lifelong`，见[第五节](#stream)）。完整的持续执行规则见 [Stream 与 lifelong](STREAM_LIFELONG.md)，尚未设计的部分见[当前限制](#limitations)。

从“代码长什么样”进入：先看到资产、注册、instance 和 workflow 的代码块，再按链接深入对应模块。想直接运行时可跳到快速开始。完整语义见[主设计](LATEST_DESIGN.md)，源码约束见[ASSETS](ASSETS.md)。

| 任务 | 阅读位置 |
| --- | --- |
| 先看同一业务在各模块中的代码形态 | [代码长什么样](#code-shape) |
| 定义表示类型和分支契约 | [资产书写](#types) |
| 查注册类别、Input 和 demands | [effect 注册](#effects) |
| 写原子操作、取值与失败处理 | [instance 书写](#handlers) |
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

文件状态只有 `Blank` 和 `Written` 两种构造，这个 ADT 说明数据长什么样。负责资产生产与解析的 effect 称为 **Context**：它声明具名的业务契约，handler 产生对应资产，消费方按声明的契约取用。下面通过 `ExtractFileText` 的注册和方法展示这层关系。

[完整 Types.hs](../demo/FileDemo/Types.hs) · [资产定义与使用规则](#types)

### 2. Effects.hs：为生产和消费写出关系

以下是 `effects` 列表中的两个注册。生产方声明资产名、表示类型和自己承担的方法角色：

```haskell
EffectSpec
  { name = "ExtractFileText"
  , typing = Context { asset = namedAsset "FileText" @TextState, request = Just (), require = Just (), stream = Nothing }
  , input = "ReadFile"
  , demands = []
  }
```

消费方声明可用的上游能力，以及需要读取的资产：

```haskell
EffectSpec
  { name = "WriteFirstLine"
  , typing = Excu { handler = Just "writeFirstLine" }
  , input = "FileSession"
  , demands = [requires "FileTextBlank", requires "OpenedFile"]
  }
```

`input` 提供类方法能力，`demands` 指定取值契约。`FileTextBlank` 是 `FileText` 的 `Blank` 分支契约，`OpenedFile` 提供文件资源；它们的实际读取发生在下面的方法体中。另一个候选 `AppendLine` 使用 `FileTextWritten`。

[完整 Effects.hs](../demo/FileDemo/Effects.hs) · [注册字段与类别](#effects)

### 3. Handlers.hs：让声明落到原生类方法

解析方法引用 `ReadFile` 提供的句柄，产生声明过的资产：

```haskell
instance ExtractFileTextInputs m => ExtractFileTextEffect m where
  getFileText = do
    contents <- readFileContent
    text <- maybe (raise (ExtractFileTextError "File read returned no text")) pure contents
    pure (FileText (if null text then Blank else Written text))
```

消费方法显式开启 scope、读取契约、执行写入；以下保留该方法的完整实现：

```haskell
instance WriteFirstLineInputs m => WriteFirstLineEffect m where
  writeFirstLine = do
    openFileSession
    _ <- require @FileTextBlank
    OpenedFile (FileHandle path file) <- require @OpenedFile
    let line = "file-demo: the file was empty; this is the first line.\n"
    outcome <- liftIO $ tryIOError $ do
      putStrLn "[read] (empty file)"
      hSeek file SeekFromEnd 0
      hPutStr file line
      hFlush file
      putStrLn ("[write] " ++ path ++ ": " ++ line)
    either (raise . WriteFirstLineError . displayException) pure outcome
    pure Nothing
```

`XInputs m => XEffect m` 是方法可用能力的边界；`openFileSession` 是实际调用，`require @T` 是实际取值。IO 和解析写在注册方法内部。

[完整 Handlers.hs](../demo/FileDemo/Handlers.hs) · [instance、取值与错误写法](#handlers)

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

`alternative` 的候选通过前面的分支契约对应 `Blank`／`Written`，AST 只列末端。每个末端代表自己的完整 original chain，Context 的生产通过取值关系接入。

[OperateFile.hs](../demo/FileDemo/Workflow/OperateFile.hs) · [AST.hs](../demo/FileDemo/AST.hs) · [branch 与节点规则](#workflow)

### 5. Generated：看到声明派生出的契约

下面只节选生成的契约定义，派生实例与其他接口见源码：

```haskell
newtype FileText = FileText (TextState)
newtype FileTextBlank = FileTextBlank (())
newtype FileTextWritten = FileTextWritten (String)
```

它们把 `namedAsset "FileText" @TextState`、业务 ADT、消费方的 `requires` 和方法体中的类型应用连接起来。Generated/Effects 提供可检查的接口，Generated/Program 保存末端登记和静态 Prototype；运行副本及协议由生成器维护。

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

生成过程提取方法结构并检查资产约束，不调用业务 handler。缓存命中只复用纯构图结果；生成检查仍会进行，内容未变的文件不会重写。详见[生成缓存边界](EFFECT_GRAPH.md#内容缓存与重跑边界)。

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
| 二、effect 注册 | `Effects.hs` | 类别、方法名、能力和取值关系 |
| 三、instance | `Handlers.hs` | 显式调用、模式匹配、解析与 IO |
| 四、workflow | `AST.hs`、`Workflow/*.hs` | 具名 branch 与末端挂载 |
| 生成接口与结构 | `Generated/` | 类型契约、协议包装、Prototype |
| 运行入口 | `Main.hs` | interpreter 启动整份结构 |

- **生成入口 `effect-codegen`**：负责从手写源码生成契约、执行副本和静态原型；修改手写源码后显式运行，具体见[命令行与执行阶段](#commands)。
- **运行入口 `Main.hs`**：`interpreter` 来自 `Generated/Program.hs`。每个 node 选择一个末端 effect，运行它的 instance 方法；方法体里显式调用上游 effect，或用 `request`／`require` 取值，整条操作链由此展开。
- **生成区**：`Generated/` 由生成器产出，不要手改。运行时编译的是 `Generated/Handlers.hs`，即你的方法体加上 SDK 的协议包装。

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

下面展开类型、生成契约和使用规则。资产是在 effect 之间传递的业务数据类型：Context 的产物、消费方取到的契约，以及它们字段里递归包含的业务类型。`String`、`Handle` 等库类型不是资产。

### 表示类型（手写）

在 `Types.hs` 用原生 `data`／`newtype` 定义，作为 `namedAsset` 中的 `@表示类型`：

```haskell
data PageURL = PageURL { pageAddress :: String }   -- 记录
data FileHandle = FileHandle FilePath Handle       -- 包装库类型
data TextState = Blank | Written String            -- 和类型
```

- **只写值的结构**：契约由生成器产出，不需要再手写一层 newtype。单值可以直接用 Prelude 类型，例如 `namedAsset "FileName" @FilePath`。
- **库类型**：含 `Handle` 等需要导入的库类型时，在 `Types.hs` 定义一个记录包装它。
- **`Eq`**：用作 scope 开启参数的类型需要 `Eq`（判断是否同参复用）；资源本身不需要。
- **`Show`**：需要打印结果时派生。
- **不导入生成区**：`Types.hs` 不导入 `Generated` 或 `Handlers`。

### 契约类型（生成）

每个 `namedAsset "资产名" @表示类型` 生成一个契约类型，契约名就是资产名：

```haskell
newtype StartURL = StartURL PageURL
```

- 资产名须是 Haskell 类型名，按业务含义起名；不能与 effect 名、生成区固定名或 `Types.hs` 中的类型重名。
- 表示类型有 `Eq`／`Show` 时，契约才有 `Eq`／`Show`；契约不派生 `Read`。
- 持续资产（`stream = Just ()`）的 `require` 返回 `History 契约`，见[持续资产与 lifelong](#stream)。

### 分支契约（生成）

表示类型是和类型（至少两个构造器，每个构造器至多一个字段）时，生成器为每个构造器产出一个分支契约。以 FileDemo 的 `namedAsset "FileText" @TextState` 为例：

| 构造器 | 分支契约 |
| --- | --- |
| `Blank` | `newtype FileTextBlank = FileTextBlank ()` |
| `Written String` | `newtype FileTextWritten = FileTextWritten String` |

- **命名**：契约名加构造器名，包装该构造器的字段；没有字段时包装 `()`。
- **取值**：资产当前是这个构造器时，`require` 分支契约才能取到值，否则报 `CaseNotSelected`。分支契约由基础契约的生产方提供，只能 `requires`。
- **用途**：`alternative` 据此决定启动哪个候选（见[workflow 书写](#workflow)）。

### 使用规则

生成器每次都会检查资产在源码中的使用：

- **只在 instance 方法里操作资产**：普通顶层函数、顶层值和方法内的具名局部函数，不能在签名、构造、模式匹配、字段访问／更新中显式使用资产。匿名 lambda 和局部数据计算属于方法体，允许。
- **只有生产方能构造**：Context 产物类型的构造器只能在它的生产方方法里出现在表达式位置，记录更新也一样；其他 instance 只能模式匹配取用，例如 `StartURL (PageURL url) <- request @StartURL`。
- **允许的情况**：`data`／`newtype` 声明与 deriving；泛型函数（`map`、`show` 等）不因实参是资产而违规；只处理 `String`、`Handle` 等库类型的普通函数允许。
- **检查范围**：只看源码里显式写出的引用，不追踪值流向；`coerce`、泛型函数或派生 `read` 等不显式写出构造器的方式不会被拦下。
- **资产目录**：生成的 `Generated/Assets.hs` 列出资产的类型、构造器、字段及定义位置，供 review 和编辑器使用，运行时不加载。

完整规则见 [源码资产约束](ASSETS.md)。

<a id="effects"></a>

## 二、effect 注册（`Effects.hs`）

`Effects.hs` 导出 `effects :: [EffectSpec]`。每个 `EffectSpec` 注册一个 effect，只描述类别、方法名和依赖，不写实现（节选自 [FileDemo](../demo/FileDemo/Effects.hs)）：

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
| `typing` | `EffectTyping` | 类别（六选一）及该类别的方法名或角色 |
| `input` | `String` | 能力继承：可以调用哪个 effect 的方法 |
| `demands` | `[Demand]` | 需要哪些 Context 值，以及取值方式 |

文件需开启 `DuplicateRecordFields`（多个类别共用字段名 `handler`）和 `TypeApplications`（`namedAsset` 中的 `@类型`），从 `Framework.SDK` 导入 `EffectSpec(..)`、`EffectTyping(..)`、`namedAsset`、`requests`、`requires`；订阅持续资产时导入 `streams`，用到 Error 时再导入 `Handles(..)`。

### `name`

- **唯一身份**：AST 的 `node`、其他 effect 的 `input`、Error 的 `handles` 都用这个名字引用它，在注册集合中不能重复。
- **生成的名字**：生成器据此产出类型类 `名字Effect`、能力约束 `名字Inputs`、错误构造器 `名字Error` 等，所以 `name` 须是大写字母开头的 Haskell 类型名。

### `typing`：六种类别

`typing` 是六选一的枚举，每种类别带自己的方法名或角色字段：

| 枚举 | 字段 | 入口方法 | 方法签名 | 用途 |
| --- | --- | --- | --- | --- |
| `Context` | `asset = namedAsset "T" @表示类型`；`request`、`require`、`stream :: Maybe ()` | 由资产名生成：`getT`、`readT`、`streamT` | `getT`／`streamT` 为 `m T` | 生产在操作之间传递的业务值 |
| `Pure` | `handler :: Maybe String` | `handler` | `m ()` | 不产出业务值的检查 |
| `Excu` | `handler :: Maybe String` | `handler` | `m (Maybe String)` | 执行操作（原子句柄） |
| `Scoped` | `open`、`close :: Maybe String` | `open` | 均为 `m (Maybe String)` | 资源的开启与关闭（原子句柄） |
| `Error` | `detect`、`resolve :: Maybe String`；`handles :: [Handles]` | 无，由失败协议调用 | 均为 `m ()` | 对指定失败做诊断和处置 |
| `Stream` | `handler :: Maybe String` | 无，由生产会话调用 | `m String` | 持续取得原始输入，交给挂在它下面的 Context 解析 |

- **`Maybe String` 是方法名**：`Just "名字"` 生成这个方法，`Nothing` 不生成。名字可以缺失，不代表返回值使用 `Maybe`。入口为 `Nothing` 的 effect 只作为声明存在，不能被 AST 选为末端。
- **业务资产只归 Context**：Excu 和 Scoped 返回的 `Maybe String` 是原子句柄交出的可选信息，只交给挂接的 Context 解析（见 `input`）；Stream 返回的原始输入交给对应的 Context 解析器。它们都不直接产出业务资产。

#### `Context`

```haskell
typing = Context { asset = namedAsset "StartURL" @PageURL, request = Just (), require = Just (), stream = Nothing }
```

- **`asset = namedAsset "资产名" @表示类型`**：声明资产。资产名就是契约名，生成器产出 `newtype StartURL = StartURL PageURL`；表示类型怎么写见[资产书写](#types)。
- **三个角色，方法名由资产名生成**：`request = Just ()` 生成生产方法 `getStartURL`，需要手写实现；`require = Just ()` 生成读取方法 `readStartURL`，由 SDK 实现，供消费方 `require @StartURL` 使用，业务代码不直接调用；`stream = Just ()` 声明持续资产，见[持续资产与 lifelong](#stream)。`Nothing` 不生成对应方法，消费方也不能声明相应的 `requests`／`requires`。
- **必须有生产入口**：普通 Context 须声明 `request = Just ()`；挂在 Stream 下的解析器改用 `stream` 角色。
- **持续资产的方法**：`stream = Just ()` 时，`readT` 返回 `History 契约`；挂在 Stream 下时另生成解析器 `streamT`（手写）和 `inputT`（读取本次原始输入），见[持续资产与 lifelong](#stream)。
- **不能作为 AST 末端**：Context 在它挂接的句柄执行时产出，或在被 `request`／`require` 时产出。
- **命名**：资产名决定契约名和方法名，要按业务含义起名（`StartURL`，而不是 `LoadStartURL`），不能与 effect 名、生成区固定名或 `Types.hs` 中的类型重名。

#### `Pure`

```haskell
typing = Pure { handler = Just "validateFileName" }
```

不产出业务值的检查：正常结束即成功，失败用 `raise`。Pure 的确切语义（例如是否允许 IO）仍待确定。

#### `Excu`

```haskell
typing = Excu { handler = Just "fetchStartPage" }
```

执行一次操作的原子句柄。它可以交出一段可选信息（`pure (Just info)`，没有就 `pure Nothing`），供挂在它下面的 Context 解析。

#### `Scoped`

```haskell
typing = Scoped { open = Just "openFileSession", close = Just "closeFileSession" }
```

- **两个方法都要声明**：`open` 和 `close` 写在同一个 instance 里；自动清理需要 `close`，所以两者缺一不可。
- **资源是一个 Context**：Scoped 在 `demands` 里 `requests` 资源 Context（至多一个），`open` 用 `request` 取得它，`close` 用 `require` 读回它。
- **开启参数**：资源 Context 的生产方取用的上游 Context 就是开启参数，SDK 按它们决定共享还是新建实例（见「运行时行为」）。

#### `Stream`

```haskell
typing = Stream { handler = Just "nextReading" }
```

持续数据源：每次调用取得一份原始输入（`m String`），节奏由方法体自己的阻塞或等待决定。它不能作为 AST 末端，也不能被普通方法调用；恰好一个 Context 以它为 `input`，作为解析器读取这份输入。写法见[持续资产与 lifelong](#stream)。

#### `Error`

```haskell
typing = Error
  { detect = Just "detectFileSession"
  , resolve = Just "resolveFileSession"
  , handles = [RaisedBy "ReadFile", RaisedBy "WriteFirstLine", RaisedBy "AppendLine"]
  }
```

- **`handles`**（必填，不能为空）：处理哪些失败，枚举见下表。
- **`detect`**（可选）：进一步判断这次失败是否归它处理。不写时直接调用 `resolve`。
- **`resolve`**：执行处置，例如关闭资源。
- **作用范围**：生成器沿 `input`／`request` 找最近的 Scoped 作为它关联的 scope；至多一个，没有则是全局处置。同一 scope 下，同一种失败只能由一个 Error 处理。

`Handles` 有三个枚举：

| 枚举 | 匹配的失败 | 参数须是 |
| --- | --- | --- |
| `RaisedBy "X"` | effect `X` 在方法体里 `raise` 的业务失败 | 任意已注册的 effect |
| `ScopeFaultIn "X"` | Scoped `X` 的资源协议故障（开启、关闭、实例冲突等） | Scoped effect |
| `ContextFaultIn "X"` | Context `X` 的取值协议故障（尚未初始化、未声明的取值、分支不匹配等） | Context effect |

Context 协议故障的来源一律记为生产方的注册名，不是契约名。

### `input`

```haskell
input = "FileSession"
```

- **取值**：`"Root"`（没有上游），或另一个**非 Context** 的 effect 名。Context 只能经 `demands` 接入，不能写在 `input` 里。
- **含义**：能力继承。这个 effect 的 instance 可以调用 `input` 指向的 effect 及其上游链上的全部方法，在 Haskell 里体现为 superclass。
- **不自动执行**：继承只提供"可以调用"的能力，上游只在方法体里显式调用时才会运行。
- **挂接**：Context 的 `input` 指向 Excu 或 Scoped 时，它就挂在这个句柄下，负责解析句柄入口方法（`handler`／`open`）交出的信息；`close` 没有挂接点。例如 [Crawler](../demo/Crawler/Effects.hs) 的 `ExtractPage` 挂在 `FetchPage` 下，把抓到的正文解析成摘要。
- **限制**：
  - input 链不能成环；
  - 链上的 Scoped 必须同时声明 `open` 和 `close`；
  - Scoped 的资源 Context 不能挂在请求它的那个 Scoped 下。

### `demands`

```haskell
demands = [requests "StartURL", requires "CrawlSessionInfo"]
```

`demands` 是 `Demand` 列表，每一项用契约名声明一个需要的值及取值方式。契约类型在 `Effects.hs` 中看不到，所以用名字字符串引用；方法体里照常写类型。`Demand` 有三种写法：

| 枚举 | 方法体中 | 含义 |
| --- | --- | --- |
| `requests "T"` | `x <- request @T` | 重新生产一次，并把结果保存为当前绑定 |
| `requires "T"` | `x <- require @T` | 读取已有的值，不重新生产；尚未生产过时自动生产一次并记住 |
| `streams "T"` | `xs <- require @T` | 由持续资产 `T` 的新交付驱动，同时取得读取权限；只在 `lifelong` 内使用，见[持续资产与 lifelong](#stream) |

- **来源自动确定**：契约名就是生产方声明的资产名，每个资产恰好由一个 Context 声明，生成器自动接上，不用指名生产方。
- **区分同类数据**：同一种数据有不同含义时，声明成不同的资产。例如 Crawler 的起始页和链接页 URL 都是 `PageURL`，分别声明为资产 `StartURL` 和 `LinkedURL`，类型上不能混用。
- **同一契约可以声明多种合法取值方式**：例如 Scoped 的 `open` request 资源、`close` require 它；持续消费方也可同时声明 `streams` 和 `requests`（生产方须支持 request）。同一契约的同一种方式只能声明一次。
- **限制**：Scoped 至多 `requests` 一个资源 Context；分支契约（见[资产书写](#types)）只能 `requires`；`streams` 只能由 Pure、Excu、Scoped 声明，只能订阅 `stream = Just ()` 的基础契约。
- **声明即权限**：方法体里取用了未声明的契约，生成器报错；运行时也会以 `UndeclaredContextAccess` 拒绝。

<a id="handlers"></a>

## 三、instance 书写（`Handlers.hs`）

先看一个完整方法的形态，模块头和导入在后文给出：

```haskell
instance ExtractFileTextInputs m => ExtractFileTextEffect m where
  getFileText = do
    contents <- readFileContent
    text <- maybe (raise (ExtractFileTextError "File read returned no text")) pure contents
    pure (FileText (if null text then Blank else Written text))
```

每个注册的 effect 在 `Handlers.hs` 中实现生成接口；`Inputs` 指定能力，方法体写实际调用和操作。手写代码由 HLS 检查，运行时编译入口带协议包装的 `Generated/Handlers.hs`。下面依次展开文件头、instance 约束和方法体规则。

### 文件头

```haskell
{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE UndecidableInstances #-}
{-# OPTIONS_GHC -Werror=missing-methods #-}

module FileDemo.Handlers () where

import Framework.SDK (Effect(..))     -- raise
import FileDemo.Generated.Effects    -- 生成的类、契约类型、错误构造器
import FileDemo.Types
```

`-Werror=missing-methods` 保证每个声明的方法都有实现。

### instance 头

```haskell
instance ReadFileInputs m => ReadFileEffect m where
```

- **`名字Effect m`**：生成的类型类，方法由 `typing` 决定。
- **`名字Inputs m`**：生成的能力约束，包括这个 effect 自身的能力标记、`input` 链上全部上游 effect 的类、`demands` 中各契约的 `Provides`，以及 `MonadIO m`。
- **对载体 `m` 泛型**：能力标记只在本程序的载体上有实例，所以方法体只能调用 `input` 链上的方法；越过 Input 的调用，GHC 直接报错。

### 各类别要实现的方法

| 类别 | 方法 | 签名 | 返回什么 |
| --- | --- | --- | --- |
| Context | `getT`（request 角色）或 `streamT`（stream 角色） | `m T` | 用契约构造器包装的值，例如 `pure (FileName path)` |
| Pure | `handler` | `m ()` | 正常结束即成功 |
| Excu | `handler` | `m (Maybe String)` | 交给挂接 Context 的信息，没有就 `pure Nothing` |
| Scoped | `open`、`close` | `m (Maybe String)` | 同上；`close` 的输出没有挂接点 |
| Error | `detect`、`resolve` | `m ()` | 见下文「Error 的写法」 |
| Stream | `handler` | `m String` | 一份原始输入 |

Context 的读取方法（`read契约名`）由 SDK 提供默认实现，不用写；解析器读取原始输入的 `input契约名` 也由 SDK 提供，只生成在该 Context 的类中。

### 方法体里的写法

| 写法 | 作用 |
| --- | --- |
| `openFileSession` | 调用 `input` 链上游的方法，上游随之执行 |
| `x <- request @T` | 重新生产契约 `T` 的值，须在 `demands` 中声明 `requests "T"` |
| `x <- require @T` | 读取 `T`，缺值时按需求值；须声明 `requests "T"` 或 `requires "T"` |
| `xs <- require @T`（持续资产） | 取得 `History T`：本次交付为止的历史，用 `latest`／`historyEntries` 读取；须声明 `streams "T"` 或 `requires "T"` |
| `raw <- inputT` | 解析器 `streamT` 读取本次原始输入 |
| `raise (ReadFileError "message")` | 以本 effect 的错误失败；错误构造器是 effect 名加 `Error` |
| `pure (Just info)` | Excu／Scoped 把信息交给挂接的 Context |
| `contents <- readFileContent` | 挂接的 Context 调用它挂接的句柄，取得句柄交出的信息 |
| `liftIO (...)` | 执行 IO |

- **取值的模式匹配**：单构造器可以直接写在 `<-` 左侧，例如 `OpenedFile (FileHandle path file) <- require @OpenedFile`；多构造器的值先绑定，再用普通 `case` 处理，失败用 `raise`。
- **挂接句柄的输出**：本次成功句柄的挂接注入期间，Context 对该句柄的直接调用由本次输出回答，不重复执行。显式 request 或缺值补产仍正常执行生产方法；这不是链级调用缓存。

例如 [Crawler](../demo/Crawler/Handlers.hs) 中挂在抓取句柄下的解析 Context：

```haskell
instance ExtractPageInputs m => ExtractPageEffect m where
  getStartPageSummary = do
    fetched <- fetchStartPage            -- 挂接句柄交出的正文
    StartURL (PageURL url) <- require @StartURL
    html <- maybe (raise (ExtractPageError (url ++ ": fetch returned no page body"))) pure fetched
    ...                                  -- 解析标题、段落和链接
    pure (StartPageSummary (PageSummary url title content links))
```

### Scoped 的写法

```haskell
instance FileSessionInputs m => FileSessionEffect m where
  openFileSession = do
    _ <- request @OpenedFile
    pure Nothing

  closeFileSession = do
    OpenedFile (FileHandle path file) <- require @OpenedFile
    liftIO (hClose file)
    pure Nothing
```

- **资源获取写在资源 Context 的生产方**：FileDemo 中打开文件的是 `getOpenedFile`，`open` 只 `request` 它。
- **使用方显式调用 `open`**：例如 `readFileContent` 先调用 `openFileSession`。实例已开启时 SDK 直接复用，跳过 `open` 的方法体。
- **不用自己安排 `close`**：SDK 会自动清理（见「运行时行为」），也可以显式调用。

### Error 的写法

```haskell
instance FileRecoveryInputs m => FileRecoveryEffect m where
  detectFileSession = do
    OpenedFile (FileHandle _ file) <- require @OpenedFile
    closed <- liftIO (hIsClosed file)
    unless closed $
      raise (FileRecoveryError "File handle is still open; failure not located in FileSession")

  resolveFileSession = do
    closeFileSession
    pure ()
```

- **`detect`**：正常返回表示归此处，接着调用 `resolve`；`raise` 表示不归此处，继续检查其他 Error。
- **原失败**：`caughtFailure` 可以取得原失败（`Failure` 的来源、分类和消息）。
- **处置之后**：原失败仍然继续传播。SDK 不会把失败变成成功，也不会自动重试或重开资源。

### 方法体的结构限制

生成器要从方法体中静态读出调用结构，所以：

- **effect 调用直接写在方法体里**：支持 `do`、`if`／`case`、`when`、`catchError` 等常见写法。
- **不能间接调用**：不能经普通函数、局部别名、未知的高阶组合或含 effect 的循环间接调用 effect，也不能递归调用 effect。
- **普通计算**：不含 effect 调用的表达式可以使用原生 Haskell，仍须遵守下文的资产约束。
- **不直接调用 Context 方法**：例如不能直接调用 `getFileName`，改用 `request`／`require`。

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

这两段是 FileDemo 对应文件的节选。AST 描述哪些完整链按什么方式启动；node 只选择末端，链内调用仍写在 instance 中。

### 两种构件

| 构件 | 写法 | 类型 | 含义 |
| --- | --- | --- | --- |
| node | `node "effect名"` | `EffectNode` | 选择一条操作链的末端 effect |
| branch | `chained`、`parallel`、`alternative` 或 `lifelong` 加子项列表 | `AST` | 组合 node 或其他 branch |

- **node 不是 AST**：顶层和每个模块都必须是 branch，单个 node 也要包进一个 branch。
- **子项列表同质**：一个列表要么全是 node，要么全是 branch，不能混排。
- **空列表**：须标注元素类型，例如 `chained ([] :: [AST])`。

### node

- **只选原始句柄**：选中的 effect 必须是 Pure、Excu 或 Scoped，不能是 Context 或 Error。
- **运行即调用入口方法**：Pure／Excu 调用 `handler`，Scoped 调用 `open`。方法体里调用的上游随之执行，Input 链不需要在 AST 里重写。
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
- **运行时**：先 `require` 这个资产（已有值就直接用，没有就按需生产一次），再启动对应的候选，并把选择时读到的值交给候选；没被选中的候选不执行，也不出现在结果中。
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

- **运行**：`main = interpreter ast effects`，结果打印为 `Succ [...]` 或 `Failed ...`，例如 FileDemo 输出 `Succ [AppendLineResult ()]`。原子句柄交出的 `Maybe String` 不是业务产物，在结果中记为 `()`。
- **查看结构**：使用[命令行的 structure 模式](#commands)查看生成器推导的调用结构和资源依赖。

<a id="stream"></a>

## 五、持续资产与 lifelong（Stream）

前四节的程序是有限的：每个 node 执行一次。持续数据源（传感器、socket、消息队列、定时采样）同样通过 Context 对外提供资产：可以由 Stream effect 取得原始输入再交给 Context 解析，也可以由 Context request 反复生产。Context 以 `stream = Just ()` 声明持续资产，`lifelong` 根据交付就绪情况启动消费方。下面用 [StreamDemo](../demo/StreamDemo) 展示这两种生产方式；完整规则见 [Stream 与 lifelong](STREAM_LIFELONG.md)。

### 注册：两种生产方式

以下节选 StreamDemo 的四个注册：

```haskell
EffectSpec
  { name = "TemperatureFeed"
  , typing = Stream { handler = Just "nextReading" }
  , input = "SensorLink"
  , demands = []
  }

EffectSpec
  { name = "TemperatureParser"
  , typing = Context { asset = namedAsset "TemperatureSample" @Temperature, request = Nothing, require = Just (), stream = Just () }
  , input = "TemperatureFeed"
  , demands = []
  }

EffectSpec
  { name = "Heartbeat"
  , typing = Context { asset = namedAsset "Beat" @Int, request = Just (), require = Just (), stream = Just () }
  , input = "Root"
  , demands = []
  }

EffectSpec
  { name = "ShowTemperature"
  , typing = Excu { handler = Just "showTemperature" }
  , input = "Root"
  , demands = [streams "TemperatureSample"]
  }
```

`stream = Just ()` 声明持续资产，生产方式只由这份注册决定，不看谁在消费：

| Context 的 `input` | `request` | `stream` | 生产方式 |
| --- | --- | --- | --- |
| Stream effect | `Nothing` | `Just ()` | **接收**：会话反复调用 Stream 的方法取得原始输入，交给解析器 `streamT` 解析并发布 |
| Root 或普通 effect | `Just ()` | `Just ()` | **请求序列**：会话反复执行 `getT`，每次成功即一条新发布 |
| Root 或普通 effect | `Just ()` | `Nothing` | 普通单值资产，不能被 `streams` 订阅 |

其他组合由生成器拒绝：Stream 下的 Context 不能声明 `request`，必须声明 `stream`；`stream = Just ()` 不在 Stream 下时必须有 `request`；一个 Stream 恰好有一个 Context 以它为 `input`。

- **读取类型**：持续资产的 `require @T` 在所有地方都返回 `History T`，普通资产仍返回 `T`；有没有消费方订阅不会改变它。
- **订阅**：消费方写 `streams "T"`，表示由 T 的新交付驱动，同时取得 `require @T` 的权限，但不授予 `request`。

### 按驱动关系选择写法

持续数据通常以三种方式到来，分别落到上表的写法。这三个词只帮助选择注册，生成器和运行时不识别它们：

| 驱动关系 | 例子 | 怎么写 |
| --- | --- | --- |
| socket：外部持续送来，逐条接收 | 连接、消息队列、传感器 | Stream 方法阻塞接收一份原始输入，挂在下面的 Context 用 `streamT` 解析（StreamDemo 的 `TemperatureFeed`＋`TemperatureParser`） |
| behavior：值一直存在，随时采样 | 时钟、心跳、状态轮询 | Context 声明 `request = Just ()` 与 `stream = Just ()`，`getT` 取得当前值并自己等待采样间隔（StreamDemo 的 `Heartbeat`） |
| event：离散发生，每次一条 | 事件队列、由回调转成的阻塞等待 | 阻塞读取下一个事件：要解析原始文本就写成 Stream＋解析器，直接得到业务值就写成请求序列。lifelong 内部产生的事件，由消费者声明 `streams "T"` 与 `requests "T"` 后执行 `request @T`，进入同一会话 |

外部回调不能直接注册给 SDK，需要先转换成可阻塞读取的队列。详细规则见 [Stream 规范 4.1 节](STREAM_LIFELONG.md#drives)。

### 方法：每次只处理一份

```haskell
instance TemperatureFeedInputs m => TemperatureFeedEffect m where
  nextReading = do
    _ <- connectSensor
    liftIO (threadDelay 700000)
    seconds <- liftIO getMonotonicTime
    pure (printf "%.1f" (21 + 3 * sin (seconds / 3) :: Double))

instance TemperatureParserInputs m => TemperatureParserEffect m where
  streamTemperatureSample = do
    raw <- inputTemperatureSample
    case reads raw of
      [(value, "")] -> pure (TemperatureSample (Temperature value))
      _ -> raise (TemperatureParserError ("unreadable sensor output: " ++ raw))

instance ShowTemperatureInputs m => ShowTemperatureEffect m where
  showTemperature = do
    samples <- require @TemperatureSample
    case latest samples of
      Just (TemperatureSample (Temperature value)) ->
        liftIO (printf "reading #%d: %.1f C\n" (length (historyEntries samples)) value)
      Nothing -> pure ()
    pure Nothing
```

- **Stream 方法**一次返回一份原始输入；节奏由方法体自己的阻塞或等待决定，SDK 不加间隔，立即返回的方法会持续高频运行。
- **解析器 `streamT`** 用 `inputT` 读取本次原始输入并返回一个资产。`inputT` 只生成在这个 Context 的类里，其他 handler 调用不到。解析器不要直接调用 Stream 方法：会话已经取得本次输入，再调用会另取一份，生成器会拒绝。发布、历史和交付都由 SDK 完成，方法体里不写循环、发布或回调。
- **请求序列**的 `getT` 与普通 request 的写法相同（StreamDemo 的 `getBeat`）。
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
- **会话**：同一个 lifelong 里订阅同一资产的单元共享一个生产会话，各自独立推进；不同 lifelong 的会话互相独立。会话在进入 lifelong 时启动；生产步骤用到的资源（例如 `connectSensor` 打开的连接）在各步骤间保持，退出时关闭。持续资产的生产不能依赖另一个持续资产。
- **显式 request**：单元里声明了 `requests "T"` 的节点执行 `request @T` 时，新值发布进本 lifelong 的会话，并接在本次调用自己的视图末尾。
- **外部组合**：`chained [setup, monitor]` 先执行 setup；lifelong 没有正常结束，排在它后面的节点不会执行；`parallel [monitor, otherWork]` 两者同时运行。

### 结束与失败

- **没有正常结束**：持续程序运行到被取消（Ctrl-C）为止。取消时 SDK 停止全部单元和会话，等它们收尾，再按 ScopeTree 关闭资源；StreamDemo 会打印 `[sensor] disconnected`。
- **失败（临时规则）**：程序里含 lifelong 时，结构化失败（生产、解析、某个单元或任何 branch）在完成 Error 诊断后终止整次运行：取消全部任务、等待收尾，最后报告最初的那个失败；原生异常直接进入监督并在收尾后重新抛出。lifelong 的 close 语义设计后再改为局部结束。
- **lifelong 外读取持续资产**：普通 `requires "T"` 只读取一次。挂在 Stream 下的资产没有交付时，由 interpreter 托管的会话产出（至少等到一条），返回当时的历史；这个会话保持到程序退出。请求序列资产按普通 require 取得一个值，呈现为只有一条的历史。

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

### 取值：`request` 与 `require`

- **`request`**：每次重新生产，成功后以当前入口的 origin 保存并替换该 origin 的绑定，返回同一个值；生产失败时不覆盖旧值，原失败继续传播。
- **`require`**：先读当前调用已捕获的绑定，再查原型许可的唯一可见来源；仍无值时在当前 origin 生产一次并发布。同一 origin、同一来源的并发按需求值共用锁，不同 origin 独立。第一次读取后绑定固定，其他调用的发布不原地改写它。
- **跨 node 保存**：发布时无资源 owner 的值按 origin 保存，后补 owner 保留原发布记录；open 内一开始就有 owner 的产物只留在 scope／当前调用。一个来源在 AST 中保证先于当前节点完成，或属于当前入口时才可见；并行兄弟互不可见。需要跨链解析的缺值路径若有多个同时可见来源，就需细化契约或调整编排，生成器不会选“最后写入”的那个。
- **缺值生产也能传递**：fallback 是普通 request，其结果可被 AST 可见后继复用。若前驱 A 没发布，B 的 `require` 生产了值，后继 C 可读取 B 的结果；生成器将这条条件生产路径纳入来源唯一性检查。
- **部分路径已取值合法**：已经捕获值的分支直接使用该绑定，只有缺值路径需要解析唯一来源。alternative 或缺值生产条件可证明这些路径的来源唯一；已捕获路径上允许多个节点共同发布，由已有快照确定读取值。
- 调用点确定取值模式；require 是否补产还取决于本次捕获、可见绑定及资源等协议例外。

### 挂在句柄下的 Context

- **句柄在操作链里执行时**：句柄返回后，SDK 自动用这次的输出运行挂在下面的 Context，产出的值保存起来，不会再执行一次句柄。调用句柄的那条链照常继续，不受影响；解析失败只留在这次注入里，之后有人 `require` 这个值时才按正常协议报出。
- **资产缺值、允许按需求值时**：require 进入 Context 生产方法，由它调用句柄启动生产链；资源与诊断等缺值例外见运行协议。

所以 Crawler 先并行抓取，打印时直接 `require` 解析好的摘要，不再重新抓取。

### 资源：共享、新建与自动关闭

- **共享**：开启参数以 `require` 取得、值相等（`Eq`）时，复用同一个仍然有效的实例；没有开启参数的资源也共享。
- **新建**：开启参数是以 `request` 重新生产的，本次开启新的实例。
- **自动关闭**：SDK 为一次 AST 入口调用登记资源使用；整条操作链结束（包括出错）并完成诊断和结果消费后撤销这份登记，关闭没有其他入口在用、也没有子资源依赖的实例。嵌套 Context 生产继承同一份使用登记，生产方法返回不会提前关闭资源；程序退出时仍兜底清理。
- **显式关闭**：仍然可以手动调用 `close`；如果别的链还在用，关闭以 `ScopeInUse` 拒绝。
- SDK 不主动检查资源健康，也不自动重开已关闭或失效的实例。

资源共享例外只覆盖带 owner 的绑定。scope 快照中的无 owner 辅助值仍按 origin 来源表读取，不因复用资源而绕过可见性。诊断和自动 cleanup 中产生的新值只留在其局部快照，不发布成后续业务的来源。

每次 request 产生独立绑定，所有捕获和交接共享它的资源归属。资源先在 open 外生产、再被 scope 认领时，已有引用也能看到同一个 owner；其他实例不能再次认领。SDK 同时把仍在使用这份绑定的入口登记到实例，避免认领后提前关闭。认领保留原来的值、出身和发布记录，不要求更改 handler 或添加 key；两次 request 私下包装同一个底层 Handle 的物理别名仍不追踪。

### 失败与 Error 处置

- **失败的形态**：每个 effect 自动获得错误构造器 `名字Error String`，用 `raise` 抛出。失败沿调用链原样传播，记录来源、分类和消息；程序最终返回 `Succ 结果` 或 `Failed 失败信息`。
- **Error 处置**：SDK 捕获失败后，按 `handles` 匹配已注册的 Error，沿资源依赖从外层到内层依次执行它们的 `detect`／`resolve`，全局处置排在最后。
- **处置不改变结果**：处置之后原失败仍然继续传播。

<a id="development"></a>

## 开发流程

修改手写文件后，按[命令行与执行阶段](#commands)完成“生成 → 按需查看结构 → 运行”；整个仓库的编译使用 `cabal build all`。生成命令显式执行，普通构建不会更新 Generated。

- **编辑器支持**：`Handlers.hs` 是普通 Haskell，可以在编辑器里用 HLS 检查（配置见 `hie.yaml`，HLS 需匹配 GHC 9.12.2）。它依赖的 `Generated/Effects.hs` 要先生成出来。
- **新 effect 的顺序**：先注册、生成接口，再写实现，然后再生成一次。
- **检查分工**：HLS／GHC 检查 Haskell 语法与类型；gencode 另检查可提取的结构和资产约束；运行与结构查看再核对生成快照是否仍与当前程序一致。

### 生成器会检查什么

生成器不只是生成代码，还会拒绝以下写法，并给出原因：

| 情况 | 处理方式 |
| --- | --- |
| 资产名与 effect 名、生成区名字重名 | 换一个按业务含义起的资产名 |
| `demands` 里的契约名没有对应的生产方 | 检查名字：契约名就是生产方声明的资产名 |
| 声明了 `request`／`require` 中没有的角色却去 `requests`／`requires` | 在生产方补上角色，或去掉这项 demand |
| 方法体里 `request @T`／`require @T` 的 `T` 没有在 `demands` 中声明 | 补上声明 |
| 直接调用其他 effect 的 Context 方法（如 `getFileName`） | 改用 `request @T`／`require @T` |
| 在生产方以外构造某个 Context 产物类型的值（例如在消费方写 `StartURL (...)`） | 值应由它的生产方产生；消费方用 `request`／`require` 取得，只做模式匹配 |
| 普通顶层函数显式使用业务类型、构造器或字段 | 把这部分操作移进注册的 instance 方法；只处理 `String` 等通用类型的普通函数可以保留 |
| 经普通函数、未知的高阶组合或循环间接调用 effect | 在方法体中直接调用；支持 `do`、`if`／`case`、`when`、`catchError` 等常见写法 |
| 方法体调用了自己 `input` 链以外的 effect 方法 | GHC 报错（缺少该 effect 的能力）；把它加进 `input` 链，或改用 Context 取值 |
| `alternative` 的候选没有依赖分支契约、依赖了多个，或候选没覆盖和类型的全部构造器；分支契约被写成 `requests` | 每个候选 `requires` 恰好一个分支契约，候选覆盖全部构造器；分支契约只能 `requires` |
| AST 的 node 选中了 Context、Error 或 Stream | node 只挂可选作末端的原始句柄；Context 由挂接、合法取值或生产会话带起；Stream 由生产会话调用，Error 由失败协议调用 |
| 某个 Context 从 AST 出发永远到不了：没有挂接句柄、合法取值链或 lifelong 订阅生产会话带起它 | 把带起它的消费链加进 AST，或删掉这个 Context |
| 缺值读取路径上，同一契约有多个可能同时发布的可见来源 | 细化契约或调整 AST；alternative 和条件 fallback 可证明互斥时允许多个候选 |
| 持续资产的声明不成立：Stream 下的 Context 写了 `request` 或缺少 `stream = Just ()`；`stream = Just ()` 既不在 Stream 下也没有 `request`；Stream 下不是恰好一个 Context；`streams` 订阅了普通资产或分支契约 | 按[持续资产的声明规则](#stream)修正 |
| `streams` 写在 lifelong 外的末端上；lifelong 嵌套或含空分支；lifelong 里的末端没有恰好订阅一个持续资产，或另外读取了别的持续资产 | 按 [lifelong 的规则](#stream)调整注册或 AST |
| lifelong 中持续资产的生产链依赖另一个持续资产 | 首次交付会等待另一个 stream；改用普通资产作为生产前提 |

这些规则保证：组合关系总能从源码中静态读出来，不会藏在任意函数里。

### 新建一个程序

1. **手写声明**：在 `demo/MyDemo/` 下写 `Types.hs`、`Effects.hs`、`AST.hs` 和 `Workflow/*.hs`。它们不能导入 `Generated` 或 `Handlers`。
2. **生成接口**：运行 `cabal run effect-codegen -- workflow MyDemo`。此时还没有 `Handlers.hs`，生成器会先产出可编译的空实现模块。
3. **写实现**：根据 `Generated/Effects.hs` 中的接口编写 `Handlers.hs`，再生成一次，并写 `Main.hs`。
4. **加入构建**：参考 [cabal 文件](../algebraic-effect-sys-in-haskell.cabal) 中的 `file-demo` 增加一个 executable。

<a id="examples"></a>

## 示例

| 示例 | 演示内容 | 运行 |
| --- | --- | --- |
| [FileDemo](../demo/FileDemo) | 文件资源的开启、读写、自动关闭，Error 处置；按文件状态用 `alternative` 选择写首行或追加 | `cabal run file-demo` |
| [Crawler](../demo/Crawler) | 并行抓取、挂接的 Context 解析，顺序打印时读取解析结果；用不同契约区分同类数据 | `cabal run crawler-demo` |
| [OpenFilesDemo](../demo/OpenFilesDemo) | 一个资源持有多个文件，链结束后自动关闭与重开 | `cabal run open-files-demo` |
| [ScopeInstancesDemo](../demo/ScopeInstancesDemo) | 按参数区分资源实例、复用与重开 | `cabal run scope-instances-demo` |
| [ScopeReuseDemo](../demo/ScopeReuseDemo) | 并行的链共享同一个资源实例 | `cabal run scope-reuse-demo` |
| [StreamDemo](../demo/StreamDemo) | 持续读数（Stream＋解析器）、请求序列心跳、lifelong 的两个独立单元；会话跨步骤保持传感器连接 | `cabal run stream-demo`（持续运行，Ctrl-C 结束） |

Crawler 需要网络和 PATH 上的 `curl`。文件类示例的输出写在各自目录下，已加入 Git 忽略。

<a id="limitations"></a>

## 当前限制

- **未实现的能力**：middleware、通用结构适配尚未实现。middleware 与 Stream 的 scope 化（Stream close、lifelong 的局部结束、会话资源存续等）是下一阶段的设计主题，见 [TODO](TODO.md#next-stage)。
- **持续执行的延期项**：没有正常结束（EOF）、Stream close、嵌套 lifelong、自动重试和背压；lifelong 中的失败暂时终止整次运行；完整历史一直保留，持续运行时内存随发布增长。见 [Stream 规范的延期项](STREAM_LIFELONG.md#deferred)。
- **Stage 3 已知实现限制**：持续资产作为 scope 开启参数尚未接通。见 [TODO](TODO.md#stage-3-limitations)。
- **handler 复用**：同一段 handler 逻辑还不能服务多种数据类型，需要分别注册（Crawler 的两条链因此各有一份实现）。
- **资源清理范围**：自动清理覆盖交给 SDK 管理的资源；业务代码自己 `forkIO` 出的线程，或在 IO 中途获取、尚未交给 SDK 的资源，需要自行处理。
- **构建方式**：SDK 目前随仓库内的示例一起编译，不能作为独立依赖引入。
