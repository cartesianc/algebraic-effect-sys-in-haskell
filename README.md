# Algebraic Effect Sys in Haskell

> 项目处于接口探索阶段，可以运行但接口仍可能变化，暂不提供独立的 Cabal library。

## 摘要

本项目是一套嵌入 Haskell 的 algebraic effect EDSL（嵌入式领域专用语言）。

- **架构写成 DSL 程序**：一个业务程序有哪些 effect、谁能调用谁、值从哪里来、按什么方式编排，都用 EDSL 的固定语法写成声明和 AST。它们是普通的 Haskell 数据，可以序列化。
- **行为用原生 Haskell 实现**：每个 effect 的具体操作写成 GHC／HLS 可以直接检查的 instance。
- **SDK 负责从解析到解释的整条语义支撑**：
  - 生成器 `effect-codegen` 是前端：解析声明和 handler 源码，做静态分析，产出类型接口、调用结构和协议包装；
  - 解释器 `interpreter` 是后端：对 AST 做 f-algebra 折叠，按 effect 协议执行。
- **语法事先规定、范围受限**：架构不运行也能被完整读出，便于外部工具读取、检查和生成，例如计划中的语言服务器（LSP）。

本文结构：

1. **引言、总体架构**：为什么把架构写成 DSL，SDK 分成哪几层。
2. **快速开始**：安装与运行示例。
3. **程序结构**：一个程序由哪四个模块组成，各自在 DSL 中的角色。
4. **四个模块**，逐项介绍可写的参数和枚举：
   - 一、effect 注册（`Effects.hs`）
   - 二、AST 书写（`AST.hs`、`Workflow/*.hs`）
   - 三、instance 书写（`Handlers.hs`）
   - 四、资产书写（`Types.hs`）
5. **运行时行为**：取值、挂接、资源和失败在运行时如何表现。
6. **SDK 如何处理这门 DSL**：前端、解释器，以及与 HLS、LSP 的分工。
7. **开发流程**、示例、当前限制与文档层级。

## 引言

在常见的 Haskell effect 写法里，组合关系散落在函数调用中：哪个操作调用了哪个、值经过哪条路径传递、资源何时开关，只有通读代码或实际运行才知道，工具也无法在不执行的情况下回答。本项目把这部分抽出来，当作一门语言来写：

- **架构就是 DSL 程序**：effect 注册（`EffectSpec` 记录）和 workflow（`node`、`chained`、`parallel`、`alternative`）都是一阶的 Haskell 数据值。写架构，就是用这门 DSL 写一个程序。
- **采用 parser 加 AST 的深嵌入**：组合关系被表示成数据，而不是直接执行的函数。所以同一份结构可以交给不同的解释：生成器分析它，运行时执行它，`--structure` 展示它。
- **语义叶子保持原生**：DSL 只规定方法之间怎么组合，不发明表达式语法。方法体是普通的 `do`、模式匹配和 IO，不使用调用字符串或专用伪语法，也不依赖生成器修复语法或类型。
- **语法为工具而定**：
  - 声明里的名字一律用字符串（effect 名、方法名、契约名），类型只出现在 `requester` 的 `@` 之后；方法体里则直接写生成的类型和方法，例如 `request @StartURL`；
  - 声明是有限、静态、无环的结构；
  - effect 调用和资产操作只能写在注册方法中，其余代码只做不涉及资产的普通计算。

  这些规则保证架构不运行也能被读懂，后续的 LSP 可以据此提供诊断、跳转和生成。

## 总体架构

一句话：**用户用 SDK 规定的 EDSL 语法配置四个手写模块和一行 `Main.hs`；其余都由 SDK 提供：前端 `effect-codegen` 把这些模块解析、检查并生成 `Generated/`，解释器 `interpreter` 再按生成的结构执行 AST。**

| 层 | 提供方 | 组成 | 职责 |
| --- | --- | --- | --- |
| 语法 | 用户配置 | `Types.hs`、`Effects.hs`、`AST.hs`／`Workflow/`、`Handlers.hs`、`Main.hs` | 用 EDSL 写出架构，方法体用原生 Haskell |
| 前端（parser） | SDK | `effect-codegen` | 读入声明与 handler 源码，检查组合规则，推导调用图与资源依赖，产出生成区 |
| 静态原型 | SDK | `Framework.Prototype`：注册、方法、workflow、链定义与挂载、调用图和 ScopeTree | 统一的纯数据模型，由生成器构建，运行时直接复用 |
| 生成区 | SDK 生成 | `Generated/` | 接口与契约、包装副本、入口与结构常量；不要手改 |
| 解释器 | SDK | `interpreter` 与运行载体 `App` | 校验生成的结构，对 AST 做一次折叠装配执行闭包，按协议运行 |
| 工具接口 | SDK | 固定语法、`--structure`、`Generated/Assets.hs` | 供 review、编辑器和后续 LSP 使用 |

前端和解释器的具体做法见「SDK 如何处理这门 DSL」，放在四个模块之后。

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

仓库已包含各示例生成好的代码，首次运行不需要先生成。所有命令都在仓库根目录执行。

## 程序结构

一个程序由四个手写模块和一行运行入口组成，四个模块分别承担 DSL 的不同角色：

| 模块 | 文件 | 在 DSL 中的角色 | 写什么 |
| --- | --- | --- | --- |
| 一、effect 注册 | `Effects.hs` | 声明：有哪些 effect 及其关系 | 每个 effect 的类别、方法名、能力继承、需要哪些值 |
| 二、AST 书写 | `AST.hs`、`Workflow/*.hs` | 编排：程序从哪里启动、如何组合 | 哪些操作链按什么方式执行 |
| 三、instance 书写 | `Handlers.hs` | 语义叶子：每个方法具体做什么 | 每个 effect 的 `instance`：计算、模式匹配和 IO |
| 四、资产书写 | `Types.hs` | 值的词汇：effect 之间传递什么 | 在 effect 之间传递的业务数据类型 |
| 运行入口 | `Main.hs` | 调用解释器 | 一行：`main = interpreter ast effects` |

- **生成入口 `effect-codegen`**：即总体架构中的前端，修改任何手写源码后都要重新运行。
- **运行入口 `Main.hs`**：`interpreter` 来自 `Generated/Program.hs`。每个 node 选择一个末端 effect，运行它的 instance 方法；方法体里显式调用上游 effect，或用 `request`／`require` 取值，整条操作链由此展开。
- **生成区**：`Generated/` 由生成器产出，不要手改。运行时编译的是 `Generated/Handlers.hs`，即你的方法体加上 SDK 的协议包装。

编写顺序：

1. 在 `Types.hs` 写表示类型（模块四）。
2. 在 `Effects.hs` 注册 effect（模块一），在 `AST.hs`／`Workflow/` 编排末端（模块二）。
3. 生成接口：`cabal run effect-codegen -- workflow 程序名`。
4. 按 `Generated/Effects.hs` 中的接口写 `Handlers.hs`（模块三）。
5. 再生成一次，运行。

## 一、effect 注册（`Effects.hs`）

`Effects.hs` 导出 `effects :: [EffectSpec]`。每个 `EffectSpec` 注册一个 effect，只描述类别、方法名和依赖，不写实现（节选自 [FileDemo](demo/FileDemo/Effects.hs)）：

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
| `typing` | `EffectTyping` | 类别（五选一）及该类别的方法名 |
| `input` | `String` | 能力继承：可以调用哪个 effect 的方法 |
| `demands` | `[Demand]` | 需要哪些 Context 值，以及取值方式 |

文件需开启 `DuplicateRecordFields`（多个类别共用字段名 `handler`）和 `TypeApplications`（`requester` 中的 `@类型`），从 `Framework.SDK` 导入 `EffectSpec(..)`、`EffectTyping(..)`、`requester`、`requests`、`requires`；用到 Error 时再导入 `Handles(..)`。

### `name`

- **唯一身份**：AST 的 `node`、其他 effect 的 `input`、Error 的 `handles` 都用这个名字引用它，在注册集合中不能重复。
- **生成的名字**：生成器据此产出类型类 `名字Effect`、能力约束 `名字Inputs`、错误构造器 `名字Error` 等，所以 `name` 须是大写字母开头的 Haskell 类型名。

### `typing`：五种类别

`typing` 是五选一的枚举，每种类别带自己的方法名字段：

| 枚举 | 字段 | 入口方法 | 方法签名 | 用途 |
| --- | --- | --- | --- | --- |
| `Context` | `request = requester "handler名" @表示类型` | handler 名 | `m 契约类型` | 生产在操作之间传递的业务值 |
| `Pure` | `handler :: Maybe String` | `handler` | `m ()` | 不产出业务值的检查 |
| `Excu` | `handler :: Maybe String` | `handler` | `m (Maybe String)` | 执行操作（原子句柄） |
| `Scoped` | `open`、`close :: Maybe String` | `open` | 均为 `m (Maybe String)` | 资源的开启与关闭（原子句柄） |
| `Error` | `detect`、`resolve :: Maybe String`；`handles :: [Handles]` | 无，由失败协议调用 | 均为 `m ()` | 对指定失败做诊断和处置 |

- **`Maybe String` 是方法名**：`Just "名字"` 生成这个方法，`Nothing` 不生成。名字可以缺失，不代表返回值使用 `Maybe`。入口为 `Nothing` 的 effect 只作为声明存在，不能被 AST 选为末端。
- **业务值只归 Context**：其他类别的方法只表示"完成"或"失败"。Excu 和 Scoped 返回的 `Maybe String` 是原子句柄交出的可选信息，只交给挂在这个句柄下的 Context 解析（见 `input`），调用这个句柄的其他方法不读取它。

#### `Context`

```haskell
typing = Context { request = requester "startURL" @PageURL }
```

- **`requester "handler名" @表示类型`**：同时声明生产方法和契约。生成器产出 `newtype StartURL = StartURL PageURL`，契约名就是 handler 名首字母大写。表示类型怎么写见「四、资产书写」。
- **读取方法**：生成器另外产出 `readStartURL`，供消费方 `require @StartURL` 使用。注册里不用写它，业务代码也不直接调用它。
- **必须有生产方法**：`request` 不能是 `Nothing`。
- **不能作为 AST 末端**：Context 在它挂接的句柄执行时产出，或在被 `request`／`require` 时产出。
- **命名**：handler 名同时决定契约名，要按业务含义起名（`startURL`，而不是 `loadStartURL`），不能与 effect 名、生成区固定名或 `Types.hs` 中的类型重名。

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
- **挂接**：Context 的 `input` 指向 Excu 或 Scoped 时，它就挂在这个句柄下，负责解析句柄入口方法（`handler`／`open`）交出的信息；`close` 没有挂接点。例如 [Crawler](demo/Crawler/Effects.hs) 的 `ExtractPage` 挂在 `FetchPage` 下，把抓到的正文解析成摘要。
- **限制**：
  - input 链不能成环；
  - 链上的 Scoped 必须同时声明 `open` 和 `close`；
  - Scoped 的资源 Context 不能挂在请求它的那个 Scoped 下。

### `demands`

```haskell
demands = [requests "StartURL", requires "CrawlSessionInfo"]
```

`demands` 是 `Demand` 列表，每一项用契约名声明一个需要的值及取值方式。契约类型在 `Effects.hs` 中看不到，所以用名字字符串引用；方法体里照常写类型。`Demand` 有两个枚举：

| 枚举 | 方法体中 | 含义 |
| --- | --- | --- |
| `requests "T"` | `x <- request @T` | 重新生产一次，并把结果保存为当前绑定 |
| `requires "T"` | `x <- require @T` | 读取已有的值，不重新生产；尚未生产过时自动生产一次并记住 |

- **来源自动确定**：契约名是生产方 handler 名首字母大写，而方法名在注册集合中唯一，所以每个契约恰好有一个生产方，生成器自动接上，不用指名生产方。
- **区分同类数据**：同一种数据有不同含义时，交给不同的 handler 产出。例如 Crawler 的起始页和链接页 URL 都是 `PageURL`，分别由 `startURL` 和 `linkedURL` 产出 `StartURL` 和 `LinkedURL`，类型上不能混用。
- **同一契约两种方式都可以声明**：例如 Scoped 的 `open` request 资源、`close` require 它；但同一契约的同一种方式只能声明一次。
- **限制**：Scoped 至多 `requests` 一个资源 Context；分支契约（见「四、资产书写」）只能 `requires`。
- **声明即权限**：方法体里取用了未声明的契约，生成器报错；运行时也会以 `UndeclaredContextAccess` 拒绝。

## 二、AST 书写（`AST.hs`、`Workflow/*.hs`）

AST 描述"哪些操作链、按什么方式执行"。`AST.hs` 导出 `ast :: AST`，运行入口写成 `main = interpreter ast effects`。

### 两种构件

| 构件 | 写法 | 类型 | 含义 |
| --- | --- | --- | --- |
| node | `node "effect名"` | `EffectNode` | 选择一条操作链的末端 effect |
| branch | `chained`、`parallel` 或 `alternative` 加子项列表 | `AST` | 组合 node 或其他 branch |

- **node 不是 AST**：顶层和每个模块都必须是 branch，单个 node 也要包进一个 branch。
- **子项列表同质**：一个列表要么全是 node，要么全是 branch，不能混排。
- **空列表**：须标注元素类型，例如 `chained ([] :: [AST])`。

### node

- **只选原始句柄**：选中的 effect 必须是 Pure、Excu 或 Scoped，不能是 Context 或 Error。
- **运行即调用入口方法**：Pure／Excu 调用 `handler`，Scoped 调用 `open`。方法体里调用的上游随之执行，Input 链不需要在 AST 里重写。
- **node 结果不隐式传值**：一个 node 的结果不会交给下一个 node，值的传递只经 Context。后继 `require` 可读取 AST 因果顺序中唯一可见的发布来源；并行兄弟之间不按谁先完成决定读谁的值。

### branch 的三种类型

| branch | 子项如何执行 | 失败时 | 结果 |
| --- | --- | --- | --- |
| `chained` | 按顺序逐个执行 | 立即停止，后面的子项不执行 | 各子项结果按顺序拼接 |
| `parallel` | 同时执行 | 等全部子项结束，按声明顺序取第一个失败 | 全部成功时按声明顺序拼接 |
| `alternative` | 只执行一个候选 | 候选的失败原样传播 | 只有被选中候选的结果 |

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
- 分支契约怎么产生，见「四、资产书写」。

### 文件组织

- 每个 branch 放在 `Workflow/` 下单独的文件里，顶层 `AST.hs` 用非限定 import 只组合这些名字。
- `AST.hs` 和 `Workflow/*.hs` 不导入 `Generated` 或 `Handlers`。

### 运行与查看

- **运行**：`main = interpreter ast effects`，结果打印为 `Succ [...]` 或 `Failed ...`，例如 FileDemo 输出 `Succ [AppendLineResult ()]`。原子句柄交出的 `Maybe String` 不是业务产物，在结果中记为 `()`。
- **查看结构**：`cabal run file-demo -- --structure` 显示生成器推导的调用结构和资源依赖，不执行任何业务。

## 三、instance 书写（`Handlers.hs`）

每个注册的 effect 在 `Handlers.hs` 里写一个 instance，实现生成接口中的方法。它是普通 Haskell，编辑器（HLS）可以直接检查；运行时编译的是生成器加上协议包装的副本 `Generated/Handlers.hs`。

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
| Context | `request` 声明的 handler 名 | `m 契约类型` | 用契约构造器包装的值，例如 `pure (FileName path)` |
| Pure | `handler` | `m ()` | 正常结束即成功 |
| Excu | `handler` | `m (Maybe String)` | 交给挂接 Context 的信息，没有就 `pure Nothing` |
| Scoped | `open`、`close` | `m (Maybe String)` | 同上；`close` 的输出没有挂接点 |
| Error | `detect`、`resolve` | `m ()` | 见下文「Error 的写法」 |

Context 的读取方法（`read契约名`）由 SDK 提供默认实现，不用写。

### 方法体里的写法

| 写法 | 作用 |
| --- | --- |
| `openFileSession` | 调用 `input` 链上游的方法，上游随之执行 |
| `x <- request @T` | 重新生产契约 `T` 的值，须在 `demands` 中声明 `requests "T"` |
| `x <- require @T` | 读取 `T` 的已有值，须声明 `requires "T"` |
| `raise (ReadFileError "message")` | 以本 effect 的错误失败；错误构造器是 effect 名加 `Error` |
| `pure (Just info)` | Excu／Scoped 把信息交给挂接的 Context |
| `contents <- readFileContent` | 挂接的 Context 调用它挂接的句柄，取得句柄交出的信息 |
| `liftIO (...)` | 执行 IO |

- **取值的模式匹配**：单构造器可以直接写在 `<-` 左侧，例如 `OpenedFile (FileHandle path file) <- require @OpenedFile`；多构造器的值先绑定，再用普通 `case` 处理，失败用 `raise`。
- **挂接句柄的输出**：Context 在方法体里调用它挂接的句柄时，如果句柄已经在操作链里执行过，直接拿到那次的输出，不会再执行一次；尚未执行时才真正执行。

例如 [Crawler](demo/Crawler/Handlers.hs) 中挂在抓取句柄下的解析 Context：

```haskell
instance ExtractPageInputs m => ExtractPageEffect m where
  startPageSummary = do
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

- **资源获取写在资源 Context 的生产方**：FileDemo 中打开文件的是 `openedFile`，`open` 只 `request` 它。
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
- **普通计算不受限**：不含 effect 调用的表达式可以任意写。
- **不直接调用 Context 方法**：例如不能直接调用 `fileName`，改用 `request`／`require`。

## 四、资产书写（`Types.hs`）

资产是在 effect 之间传递的业务数据类型：Context 的产物、消费方取到的契约，以及它们字段里递归包含的业务类型。`String`、`Handle` 等库类型不是资产。

### 表示类型（手写）

在 `Types.hs` 用原生 `data`／`newtype` 定义，作为 `requester` 中的 `@表示类型`：

```haskell
data PageURL = PageURL { pageAddress :: String }   -- 记录
data FileHandle = FileHandle FilePath Handle       -- 包装库类型
data TextState = Blank | Written String            -- 和类型
```

- **只写值的结构**：契约由生成器产出，不需要再手写一层 newtype。单值可以直接用 Prelude 类型，例如 `requester "fileName" @FilePath`。
- **库类型**：含 `Handle` 等需要导入的库类型时，在 `Types.hs` 定义一个记录包装它。
- **`Eq`**：用作 scope 开启参数的类型需要 `Eq`（判断是否同参复用）；资源本身不需要。
- **`Show`**：需要打印结果时派生。
- **不导入生成区**：`Types.hs` 不导入 `Generated` 或 `Handlers`。

### 契约类型（生成）

每个 `requester "handler名" @表示类型` 生成一个契约类型：

```haskell
newtype StartURL = StartURL PageURL
```

- 契约名是 handler 名首字母大写。
- 表示类型有 `Eq`／`Show` 时，契约才有 `Eq`／`Show`；契约不派生 `Read`。

### 分支契约（生成）

表示类型是和类型（至少两个构造器，每个构造器至多一个字段）时，生成器为每个构造器产出一个分支契约。以 FileDemo 的 `requester "fileText" @TextState` 为例：

| 构造器 | 分支契约 |
| --- | --- |
| `Blank` | `newtype FileTextBlank = FileTextBlank ()` |
| `Written String` | `newtype FileTextWritten = FileTextWritten String` |

- **命名**：契约名加构造器名，包装该构造器的字段；没有字段时包装 `()`。
- **取值**：资产当前是这个构造器时，`require` 分支契约才能取到值，否则报 `CaseNotSelected`。分支契约由基础契约的生产方提供，只能 `requires`。
- **用途**：`alternative` 据此决定启动哪个候选（见「二、AST 书写」）。

### 使用规则

生成器每次都会检查资产在源码中的使用：

- **只在 instance 方法里操作资产**：普通顶层函数、顶层值和方法内的具名局部函数，不能在签名、构造、模式匹配、字段访问／更新中显式使用资产。匿名 lambda 和局部数据计算属于方法体，允许。
- **只有生产方能构造**：Context 产物类型的构造器只能在它的生产方方法里出现在表达式位置，记录更新也一样；其他 instance 只能模式匹配取用，例如 `StartURL (PageURL url) <- request @StartURL`。
- **允许的情况**：`data`／`newtype` 声明与 deriving；泛型函数（`map`、`show` 等）不因实参是资产而违规；只处理 `String`、`Handle` 等库类型的普通函数允许。
- **检查范围**：只看源码里显式写出的引用，不追踪值流向；`coerce`、泛型函数或派生 `read` 等不显式写出构造器的方式不会被拦下。
- **资产目录**：生成的 `Generated/Assets.hs` 列出资产的类型、构造器、字段及定义位置，供 review 和编辑器使用，运行时不加载。

完整规则见 [源码资产约束](docs/ASSETS.md)。

## 运行时行为

### 取值：`request` 与 `require`

- **`request`**：每次重新生产，成功后以当前入口的 origin 保存并替换该 origin 的绑定，返回同一个值；生产失败时不覆盖旧值，原失败继续传播。
- **`require`**：先读当前调用已捕获的绑定，再查原型许可的唯一可见来源；仍无值时在当前 origin 生产一次并发布。同一 origin、同一来源的并发按需求值共用锁，不同 origin 独立。第一次读取后绑定固定，其他调用的发布不原地改写它。
- **跨 node 保存**：无资源 owner 的值按 origin 保存。一个来源在 AST 中保证先于当前节点完成，或属于当前入口时才可见；并行兄弟互不可见。需要跨链解析的缺值路径若有多个同时可见来源，就需细化契约或调整编排，生成器不会选“最后写入”的那个。
- **缺值生产也能传递**：fallback 是普通 request，其结果可被 AST 可见后继复用。若前驱 A 没发布，B 的 `require` 生产了值，后继 C 可读取 B 的结果；生成器将这条条件生产路径纳入来源唯一性检查。
- **部分路径已取值合法**：已经捕获值的分支直接使用该绑定，只有缺值路径需要解析唯一来源。alternative 或缺值生产条件可证明这些路径的来源唯一；已捕获路径上允许多个节点共同发布，由已有快照确定读取值。
- 因此从调用点就能看出是否会重跑生产链。

### 挂在句柄下的 Context

- **句柄在操作链里执行时**：句柄返回后，SDK 自动用这次的输出运行挂在下面的 Context，产出的值保存起来，不会再执行一次句柄。调用句柄的那条链照常继续，不受影响；解析失败只留在这次注入里，之后有人 `require` 这个值时才按正常协议报出。
- **还没执行过、但有人 `require` 这个值时**：Context 自己调用句柄，把链跑起来。

所以 Crawler 先并行抓取，打印时直接 `require` 解析好的摘要，不再重新抓取。

### 资源：共享、新建与自动关闭

- **共享**：开启参数以 `require` 取得、值相等（`Eq`）时，复用同一个仍然有效的实例；没有开启参数的资源也共享。
- **新建**：开启参数是以 `request` 重新生产的，本次开启新的实例。
- **自动关闭**：SDK 为一次 AST 入口调用登记资源使用；整条操作链结束（包括出错）并完成诊断和结果消费后撤销这份登记，关闭没有其他入口在用、也没有子资源依赖的实例。嵌套 Context 生产继承同一份使用登记，生产方法返回不会提前关闭资源；程序退出时仍兜底清理。
- **显式关闭**：仍然可以手动调用 `close`；如果别的链还在用，关闭以 `ScopeInUse` 拒绝。
- SDK 不主动检查资源健康，也不自动重开已关闭或失效的实例。

资源共享例外只覆盖带 owner 的绑定。scope 快照中的无 owner 辅助值仍按 origin 来源表读取，不因复用资源而绕过可见性。诊断和自动 cleanup 中产生的新值只留在其局部快照，不发布成后续业务的来源。

### 失败与 Error 处置

- **失败的形态**：每个 effect 自动获得错误构造器 `名字Error String`，用 `raise` 抛出。失败沿调用链原样传播，记录来源、分类和消息；程序最终返回 `Succ 结果` 或 `Failed 失败信息`。
- **Error 处置**：SDK 捕获失败后，按 `handles` 匹配已注册的 Error，沿资源依赖从外层到内层依次执行它们的 `detect`／`resolve`，全局处置排在最后。
- **处置不改变结果**：处置之后原失败仍然继续传播。

## SDK 如何处理这门 DSL

### 前端 `effect-codegen`

- **读声明**：`Effects.hs`、`AST.hs` 由 GHC 编译求值。注册和 AST 快照进入同一份 `Prototype`，供运行时核对。
- **读源码**：用 GHC 9.12 解析器读出 `Handlers.hs` 的方法边界和显式 effect 引用，得到不含业务值与 IO 的纯结构，方法体不执行。`Types.hs` 同样经 GHC 解析取得和类型的构造器；资产约束在名称解析后的源码上检查。
- **分析与产出**：`Framework.Prototype` 统一解析取值来源、链定义与 AST 挂载，计算调用图和 ScopeTree。生成器读取这份原型，产出 `Generated/` 下的四个文件：
  - `Effects.hs`：接口与契约；
  - `Handlers.hs`：加上协议包装的方法副本；
  - `Program.hs`：运行入口与唯一的显式结构常量 `generatedPrototype :: SDK.Prototype MethodGen`；
  - `Assets.hs`：资产目录。

  生成的类型类也是 DSL 的类型签名，越过 `input` 的调用由 GHC 拒绝。

原型区分两种链定义：origin/excu 链由 AST 末端启动，ctx 链通过 Context 取值或挂接进入。定义身份使用方法名生成的 `MethodGen`；AST 中一次挂载另有 `NodeId`，即从根 `[]` 开始、子项从零编号的下标路径。重复挂载同一末端有不同路径；`alternative` 的选择读取链使用该分支路径加 `[-1]`。Context 链定义本身没有虚构的 AST 挂载位置。

结构缓存保存完整生成输入、纯原型及渲染文本，命中后仍校验原型、检查 Context 驱动和源码资产约束。生成文件内容相同就不写回。原型采用 Haskell ADT，SDK 当前不增加 JSON 导出或外部 LSP 协议。

### 解释器 `interpreter`

- **启动前检查**：核对源码指纹和注册快照，完整求值并校验 `generatedPrototype`，在装配中核对当前 AST 的位置、分支和末端；过期或不一致就拒绝启动。
- **一次折叠**：对 AST 做一次 `cata`，按 `NodeId` 读取原型中的链挂载与选择关系，装配动作；全部分支检查通过后才执行业务。
- **按协议执行**：运行图共享静态原型，记录活动 chain、scope 实例、入口使用登记和 Context 绑定出身，提供既有取值、注入、资源和失败协议。它不重跑 handler 构图，也不累计完整方法调用历史。`--structure` 核对当前 AST 后展示静态原型，不执行业务。

运行有两种链启动边界：AST 启动选定末端；Context 的 `request` 启动一次生产链，覆盖生产、成功发布到返回的全过程。后者记录本次启动及所属 origin，继承外层入口使用登记，不成为另一次独立清理边界。读取已有值的 `require` 不启动生产；缺值求值和挂接注入实际生产时使用同一生产协议。业务 handler 的写法不变。

活动记录在调用收尾后移除；绑定保留产生值时的执行出身，资源绑定另保留原有关闭归属。自动清理有独立的使用登记和 cleanup 出身，不把清理阶段的生产记作新的业务入口。

Stage 2 使用出身完成来源路由：生成器保存每链的可能生产、缺值读取及来源候选，runtime 按原型读取按 origin 保存的权威绑定。once-spare 和 Error 处置边界保留；现有 App 的 bind 取得值后继续执行，不增加 call/cc 或订阅调度器。stream／lifelong 仍是后续阶段，见 [TODO](docs/TODO.md)。

### 与 HLS、LSP 的分工

- **HLS**：检查 Haskell 语言层面，即语法、名称和类型。
- **生成器**：检查架构层面，即组合规则、取值来源、可达性和资产约束。
- **后续的 LSP**：直接读写固定的声明语法，把生成器的检查作为编辑器诊断，并借助 `Generated/Assets.hs` 提供跳转。

## 开发流程

修改任何手写文件后（包括只改 `Handlers.hs` 的方法体），都要重新生成：

```sh
cabal run effect-codegen -- workflow FileDemo
cabal build all
```

- **运行时检查**：运行时会核对 `Handlers.hs` 和注册是否与生成时一致，不一致就拒绝启动并提示重新生成，不会悄悄运行旧代码。
- **编辑器支持**：`Handlers.hs` 是普通 Haskell，可以在编辑器里用 HLS 检查（配置见 `hie.yaml`，HLS 需匹配 GHC 9.12.2）。它依赖的 `Generated/Effects.hs` 要先生成出来。
- **新 effect 的顺序**：先注册、生成接口，再写实现，然后再生成一次。
- **查看结构**：查看生成器推导出的调用结构和资源依赖，不执行任何业务：

```sh
cabal run crawler-demo -- --structure
```

### 生成器会检查什么

生成器不只是生成代码，还会拒绝以下写法，并给出原因：

| 情况 | 处理方式 |
| --- | --- |
| handler 名推出的契约名与 effect 名、生成区名字重名 | 换一个按业务含义起的 handler 名 |
| `demands` 里的契约名没有对应的生产方 | 检查名字：契约名 = 生产方 handler 名首字母大写 |
| 方法体里 `request @T`／`require @T` 的 `T` 没有在 `demands` 中声明 | 补上声明 |
| 直接调用其他 effect 的 Context 方法（如 `getFileName`） | 改用 `request @T`／`require @T` |
| 在生产方以外构造某个 Context 产物类型的值（例如在消费方写 `StartURL (...)`） | 值应由它的生产方产生；消费方用 `request`／`require` 取得，只做模式匹配 |
| 普通顶层函数显式使用业务类型、构造器或字段 | 把这部分操作移进注册的 instance 方法；只处理 `String` 等通用类型的普通函数可以保留 |
| 经普通函数、未知的高阶组合或循环间接调用 effect | 在方法体中直接调用；支持 `do`、`if`／`case`、`when`、`catchError` 等常见写法 |
| 方法体调用了自己 `input` 链以外的 effect 方法 | GHC 报错（缺少该 effect 的能力）；把它加进 `input` 链，或改用 Context 取值 |
| `alternative` 的候选没有依赖分支契约、依赖了多个，或候选没覆盖和类型的全部构造器；分支契约被写成 `requests` | 每个候选 `requires` 恰好一个分支契约，候选覆盖全部构造器；分支契约只能 `requires` |
| AST 的 node 选中了 Context 或 Error | node 只挂原始句柄；Context 由它挂接的句柄执行时产出，或被 `request`／`require` 时产出；Error 由失败协议调用 |
| 某个 Context 从 AST 出发永远到不了：既没有 node 带起它挂接的句柄，也没有被带起的链 `request`／`require` 它 | 把带起它的链加进 AST，或删掉这个 Context |
| 缺值读取路径上，同一契约有多个可能同时发布的可见来源 | 细化契约或调整 AST；alternative 和条件 fallback 可证明互斥时允许多个候选 |

这些规则保证：组合关系总能从源码中静态读出来，不会藏在任意函数里。

### 新建一个程序

1. **手写声明**：在 `demo/MyDemo/` 下写 `Types.hs`、`Effects.hs`、`AST.hs` 和 `Workflow/*.hs`。它们不能导入 `Generated` 或 `Handlers`。
2. **生成接口**：运行 `cabal run effect-codegen -- workflow MyDemo`。此时还没有 `Handlers.hs`，生成器会先产出可编译的空实现模块。
3. **写实现**：根据 `Generated/Effects.hs` 中的接口编写 `Handlers.hs`，再生成一次，并写 `Main.hs`。
4. **加入构建**：参考 [cabal 文件](algebraic-effect-sys-in-haskell.cabal) 中的 `file-demo` 增加一个 executable。

## 示例

| 示例 | 演示内容 | 运行 |
| --- | --- | --- |
| [FileDemo](demo/FileDemo) | 文件资源的开启、读写、自动关闭，Error 处置；按文件状态用 `alternative` 选择写首行或追加 | `cabal run file-demo` |
| [Crawler](demo/Crawler) | 并行抓取、挂接的 Context 解析，顺序打印时读取解析结果；用不同契约区分同类数据 | `cabal run crawler-demo` |
| [OpenFilesDemo](demo/OpenFilesDemo) | 一个资源持有多个文件，链结束后自动关闭与重开 | `cabal run open-files-demo` |
| [ScopeInstancesDemo](demo/ScopeInstancesDemo) | 按参数区分资源实例、复用与重开 | `cabal run scope-instances-demo` |
| [ScopeReuseDemo](demo/ScopeReuseDemo) | 并行的链共享同一个资源实例 | `cabal run scope-reuse-demo` |

Crawler 需要网络和 PATH 上的 `curl`。文件类示例的输出写在各自目录下，已加入 Git 忽略。

## 当前限制

- **未实现的能力**：loop（由资产驱动的轮询与监听）正在设计；middleware、通用结构适配尚未实现。
- **handler 复用**：同一段 handler 逻辑还不能服务多种数据类型，需要分别注册（Crawler 的两条链因此各有一份实现）。
- **资源清理范围**：自动清理覆盖交给 SDK 管理的资源；业务代码自己 `forkIO` 出的线程，或在 IO 中途获取、尚未交给 SDK 的资源，需要自行处理。
- **构建方式**：SDK 目前随仓库内的示例一起编译，不能作为独立依赖引入。

## 文档层级

```text
sdk/Framework/   SDK：契约、运行时、workflow、代码生成
demo/            示例程序及其生成代码
docs/            设计文档
```

文档按层级阅读，上层说明怎么用，下层说明为什么这样设计：

| 层级 | 文档 | 内容 |
| --- | --- | --- |
| 使用 | README（本文） | EDSL 的总体架构，四个模块怎么写，运行时如何表现 |
| 方法 | [设计方法](docs/DESIGN_METHOD.md) | 已确认的基本方法：声明与实现的分工、取值与资源的语义 |
| 设计 | [最新设计](docs/LATEST_DESIGN.md) | Context、资源、生成协议的完整说明与待办 |
| 专题 | [结构与资源依赖](docs/EFFECT_GRAPH.md) | 生成器如何推导调用结构和资源依赖 |
| 专题 | [源码资产约束](docs/ASSETS.md) | 业务类型的使用约束 |
| 约定 | [开发约定](AGENTS.md) | 参与开发时遵守的规则 |

## License

[BSD-3-Clause](LICENSE)
