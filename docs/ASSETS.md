# 源码资产约束

本文是[主设计](CORE_DESIGN.md)引用的源码约束规范。业务写法先读[指南](GUIDE.md)；本页负责资产集合、业务模块的顶层白名单和资产目录，不描述运行时 scope 归属。

更新：2026-11-26（U5：字段放开 Int、Integer、Double、Bool，表示类型不递归；字段语义由 GHC 在类型层求解）。2026-11-21（U4：Types.hs 的固定形式，资产只由 String 构造）。2026-11-08（Stage 2：顶层白名单取代普通函数的资产检查、构造器归属与接收形态检查）。

生成器只检查源码里显式写出的定义；不判断运行时值流向，也不记录 Context 来源或资源关闭归属。

## 集合从哪里来

生成器汇总当前注册集合中 Context 的表示类型和生成的资产类型。按真实 Haskell 类型身份去重，再沿业务 ADT 字段递归收集内嵌业务类型。例如 Crawler 的 `StartURL` 会带入 `PageURL`；同一类型无论出现在多少个资产中都只有一个条目。`String` 本身不因出现在字段内而变成资产。

持续资产使用同一套集合规则：handler 按资产声明的表示类型读取；业务保存记录或统计也仍是普通 ADT，按上述规则收集，不另建历史类型或资产目录。

类型、数据构造器和字段均保留模块身份与定义位置。名称解析由 GHC 9.12 完成，导入别名、重导出与同名局部变量不会被简单字符串匹配混淆。只在生成命令可见的业务源码范围内收集与检查，不扫描外部包的实现；SDK 和 Generated 模块不属于手写业务约束范围。

<a id="fixed-form"></a>

## 固定形式：资产是一阶、单态、有限的积

原始边界只有文本：`rawinput`、`rawoutput` 与 `rawemit` 都是 `String`／`[String]`。Context 的 parser 是文本变成业务值的唯一位置，它把一份原始输入细化为表示类型的值；字段可以是解析后的基础值，消费方读到的就是这个值，不再各自解析。`Types.hs` 只写单构造器的表示类型，gen 在生成期分两层检查，不符合即报错：

| 规则 | 拒绝的写法 | 检查方 |
| --- | --- | --- |
| 只有 `data`／`newtype` 声明，前缀或记录构造器 | `type` 同义词、instance、类声明、GADT 语法、中缀构造器 | gen（语法树） |
| 没有类型参数、存在量与上下文 | `data Box a = Box a` | gen（语法树） |
| 固定 `deriving (Eq, Show)` | 缺少 deriving、`deriving (Show, Read, Generic)`、独立 deriving | gen（语法树） |
| 没有 import；导出列表省略，或以 `T(..)` 列出全部类型 | `import System.IO (Handle)`、只导出类型不导出构造器 | gen（语法树） |
| 恰好一个构造器，至少一个字段，字段没有严格标记 | 和类型、无字段构造器、`!String` | GHC（类型层） |
| 字段是基础字段 `String`、`[String]`、`Int`、`Integer`、`Double`、`Bool`，或本模块的另一个表示类型 | `Maybe String`、`[Int]`、`Handle`、函数 | GHC（类型层） |
| 沿字段的引用不回到已经经过的类型 | `newtype Loop = Loop Loop`、`A` 与 `B` 互相引用 | GHC（类型层） |
| `Asset @T` 的 `T` 是 `String`、`[String]` 或 `Types.hs` 中的类型 | `Asset @Int "Beat"`、`Asset @[FileHandle] "Files"` | gen（`Typeable`） |

文件形式是 LSP 按源码读取声明的约定，所以在语法树上检查并给出源码位置。类型的语义交给 GHC：语法检查通过后，gen 在内存模块里为 `Types.hs` 的每个类型派生 `Generic`，断言 [`Framework.Language.AssetForm`](../sdk/Framework/Language/AssetForm.hs) 的 `AssetForm`。这是一组 DataKinds 上的封闭类型族，沿 `Rep` 检查构造器、字段与严格标记，并沿字段路径检查递归；违反时 GHC 报告其中的 `TypeError`，指出类型与字段，例如 `Loop -> Mutual -> Loop refer back to themselves through their fields`。字段类型按 GHC 的类型身份判断，`FilePath` 展开为 `String` 后被接受。

gen 按注册中 `Typeable` 的定义模块和编译单元核对 `Asset @T`。同一个本地类型可通过限定导入或重导出注册；其他模块即使也定义了同名、同字段的类型，仍会在生成期报错。`FilePath` 与 `String` 在类型身份上无法区分，所以注册里写 `Asset @FilePath` 仍按 `String` 接受。

**为什么这样约束。** 资产是在 effect 之间传递、被保存为历史、在受控调用间共享的数据。`Eq` 和 `Show` 供业务比较和显示，scope 实例复用按参数的生产身份判断。字段只是文本与少数一阶基础值，资产就总能比较、显示、记录，不会把活对象（句柄、连接、函数）带进 Binding、历史或快照。没有类型参数，`require @T` 才能在生成期路由到唯一的细化资产；没有递归，值总是有限的，比较、显示与求值都会结束。

**格式知识只在 parser 里。** 字段只能是 `String` 时，数值以文本保存，每个读取方都要知道生产方的文本格式并各自解析：一次发布有 k 个回调就解析 k 次，格式错误也在各读取方以 `error` 暴露。字段带基础类型后，parser 解析一次并在格式不对时 `raise`，读取方只依赖“这是一个数”。需要原文的读取方由 parser 同时保留文本字段，例如 `Sample { sampleText :: String, sampleValue :: Int }`。基础值改变 behavior 的比较：`"07"` 与 `"7"` 是不同的文本，却是相等的 `Int`。几种结果的区分交给 effect：一个 Excu 的输出挂几个 Context，各自只在自己的情况下解析成功，`alternative` 按哪个成功选择候选（[主设计：alternative](CORE_DESIGN.md#workflow)），不需要和类型。

**原生对象由获取它的 handler 管理。** `FileHandle String` 可以描述一个文件路径。读写操作按该路径打开文件，并用 `bracket` 或自带关闭逻辑的 IO 函数管理实际句柄。SDK 另外跟踪注册指定的资源 Binding 和 scope 实例。比如 `OpenFilesDemo` 在获取成功后由 scope 的 close 删除 `.open` 标记，获取中途失败则由本次获取清理已经创建的标记。[获取与关闭示例](GUIDE.md#runtime-behavior)

## 顶层白名单

所有值操作都写成 handler 的类方法，经注册进入 effect 链，才能被 SDK 驱动和静态分析。因此业务模块的顶层只允许：

| 模块 | 顶层允许 |
| --- | --- |
| `Types.hs` | 固定形式的 `data`／`newtype`，见[固定形式](#fixed-form) |
| `Handlers.hs` 及其他业务模块 | 类型声明（`data`／`newtype`／`type`）与 deriving、instance |
| `Effects.hs` | 以上声明，以及 `effects`；局部辅助写在 `effects` 的 `where` 里 |
| `AST.hs`、`Workflow/*.hs` | 以上声明，以及类型为 `AST` 的命名 workflow |
| `Hanging.hs`（可选） | 以上声明，以及 `hangingTree :: HangingTree` |
| `Main.hs` | 以上声明，以及 `main` |

顶层普通函数与顶层值、类声明（handler 类由注册生成）、foreign 声明和 rewrite rule 都被拒绝，诊断给出位置和建议。

方法体内的 `let`／`where` 局部函数、lambda 与局部数据计算不受限制：它们属于 handler，随 handler 进入 effect 链。需要在多处使用的逻辑注册成 handler，通过 effect 组合；生产链中对句柄输出的纯变换（去重、排序、过滤）由 Pure 承接，见[主设计：Pure](CORE_DESIGN.md#pure)。

例如以下顶层函数会被拒绝，即使它只处理 `String`：

```haskell
countLinesOf :: String -> Int
countLinesOf = length . lines
```

改写成方法体内的局部计算，或绑定到 effect 的 handler。

## 细化资产不进入 handler

handler 只按表示类型读取（`require @PageURL`），由 gen 按“表示类型 + effect”路由到唯一的细化资产；生成的资产类型只在 Generated 的存储、路由和入口中使用。Context 的 parser 返回表示类型的值，由生成的 `getT` 包成资产发布。因此 Stage 1 的构造器归属检查（资产类型只能在生产方构造）与接收形态检查（显式匹配资产包装构造器）随之取消：handler 不写资产类型，也就没有需要保护的构造与匹配位置。

检查只看显式引用，不追踪值流向；handler 若绕过 Layer 自行导入并使用 Generated 中的资产类型，不在本检查范围内。

## 生成与检查

使用现有命令，例如：

```text
cabal run effect-codegen -- compiler Crawler
```

生成器先从声明形成候选契约和纯结构，再用 GHC 的无代码生成模式取得手写源码的名称解析结果。本次契约（候选 `Generated/Effects.hs`）和读取的 Handlers 快照以内存 target 供分析使用；检查成功后才写回生成区。生成的 Program、Prototype 与 Handlers 副本以及手写 Main 是普通 Haskell，gencode 不再对它们做类型检查，类型错误由随后的构建报告。它不会调用 handler 或运行业务 IO。首次没有 Handlers 时，只分析可用声明与契约，仍可先生成接口；实现后再次生成才检查完整业务源码。

检查覆盖命名空间目录内的手写 Haskell 模块，以及其导入链上的本地业务模块；GHC 需要它们的语法、导入和类型成立。手写 Handlers 在读取方法体时已用本次契约做过类型检查，它的顶层检查使用那次结果；Main 导入生成的 Program，只按语法检查它的顶层。使用 Cabal 项目 package environment 解析依赖，不维护外部函数白名单。顶层检查每次生成都执行。

GHC／HLS 的普通类型检查不自行执行这项架构检查。当前接入点是 gencode，尚未实现语言服务器诊断推送或编译器插件。修改业务模块后应重新生成。启动时核对的源码依赖见[主设计](CORE_DESIGN.md#compiler)。

## 显式生成目录

每个命名空间增加 `Generated/Assets.hs`，导出：

```haskell
generatedAssets :: [Asset]
```

`Asset`／`AssetSymbol` 定义在编译产物层的 `Framework.Prototype.Catalog`；`Framework.Gen.Check.Assets` 类检并提取结构化目录，`Framework.Gen.Emit.Assets` 输出目录文本。目录记录类型、构造器和字段及其定义位置；不含业务值、Context 来源、权限 key 或 scope 实例。目录与检查使用同一次 GHC 名称解析，文件内容不变时不重写。目录是派生产物，下次生成会按源码恢复。

显式目录便于 review、LSP 建立引用索引与跨文件跳转，也可供后续 langserver 的描述接口使用。当前执行器不导入这份目录，因此不为它增加启动步骤、运行时状态或清理协议。未来需要可执行文件提供 introspection 时，可以按需导入；这份元数据本身不提供任意 ADT 的 JSON 编解码。
