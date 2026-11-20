# 源码资产约束

本文是[主设计](CORE_DESIGN.md)引用的源码约束规范。业务写法先读[指南](GUIDE.md)；本页负责资产集合、业务模块的顶层白名单和资产目录，不描述运行时 scope 归属。

更新：2026-11-21（U4：Types.hs 的固定形式，资产只由 String 构造）。2026-11-08（Stage 2：顶层白名单取代普通函数的资产检查、构造器归属与接收形态检查）。

生成器只检查源码里显式写出的定义；不判断运行时值流向，也不记录 Context 来源或资源关闭归属。

## 集合从哪里来

生成器汇总当前注册集合中 Context 的表示类型和生成的资产类型。按真实 Haskell 类型身份去重，再沿业务 ADT 字段递归收集内嵌业务类型。例如 Crawler 的 `StartURL` 会带入 `PageURL`；同一类型无论出现在多少个资产中都只有一个条目。`String` 本身不因出现在字段内而变成资产。

持续资产使用同一套集合规则：handler 按资产声明的表示类型读取；业务保存记录或统计也仍是普通 ADT，按上述规则收集，不另建历史类型或资产目录。

类型、数据构造器和字段均保留模块身份与定义位置。名称解析由 GHC 9.12 完成，导入别名、重导出与同名局部变量不会被简单字符串匹配混淆。只在生成命令可见的业务源码范围内收集与检查，不扫描外部包的实现；SDK 和 Generated 模块不属于手写业务约束范围。

<a id="fixed-form"></a>

## 固定形式：资产只由 String 构造

一切资产本质上都是不同形式的字符串。`Types.hs` 只写单构造器的表示类型，gen 在生成期检查，不符合即报错并给出位置：

| 规则 | 拒绝的写法 |
| --- | --- |
| 只有 `data`／`newtype` 声明，每个类型恰好一个构造器（前缀或记录写法） | 和类型、`type` 同义词、instance、类声明、GADT 语法、中缀构造器 |
| 至少一个字段；字段类型只写 `String`、`[String]` 或本模块的另一个类型 | `Int`、`Double`、`Handle`、`FilePath`、`Maybe String`、严格标记 `!String` |
| 没有类型参数、存在量与上下文 | `data Box a = Box a` |
| 固定 `deriving (Eq, Show)` | 缺少 deriving、`deriving (Show, Read, Generic)`、独立 deriving |
| 没有 import；导出列表省略，或以 `T(..)` 列出全部类型 | `import System.IO (Handle)`、只导出类型不导出构造器 |
| `Asset @T` 的 `T` 是 `String`、`[String]` 或 `Types.hs` 中的类型 | `Asset @Int "Beat"`、`Asset @[FileHandle] "Files"` |

gen 按注册中 `Typeable` 的定义模块和编译单元核对 `Asset @T`。同一个本地类型可通过限定导入或重导出注册；其他模块即使也定义了同名、同字段的类型，仍会在生成期报错。`FilePath` 与 `String` 在类型身份上无法区分，所以注册里写 `Asset @FilePath` 仍按 `String` 接受；`Types.hs` 的字段按源码文本检查，必须写成 `String`。

**为什么这样约束。** 资产是在 effect 之间传递、被保存为历史、在 scope 间共享并按值比较的数据。只由字符串构造，资产就总能比较、显示、记录，不会把活对象（句柄、连接、函数）带进 Binding、历史或快照。几种结果的区分交给 effect：一个 Excu 的输出挂几个 Context，各自只在自己的情况下解析成功，`alternative` 按哪个成功选择候选（[主设计：alternative](CORE_DESIGN.md#workflow)），不需要和类型。

**原生对象属于 handler。** 文件句柄等 OS 资源只在 handler 自己的执行中打开和关闭；资源资产只记路径。句柄作为 handler 本身的一部分由运行时持有，不作为资产被持有。需要表示“开启中”时，由 Scoped 的 open／close handler 维护可观察的外部状态（例如 demo 中文件旁的 `<path>.open` 标记）。数字等值保存原文本，读取方在 handler 内解析。

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
cabal run effect-codegen -- workflow Crawler
```

生成器先从声明形成候选契约和纯结构，再用 GHC 的无代码生成模式取得手写源码的名称解析结果。候选 Generated 文件和本次读取的 Handlers 快照以内存 target 供分析使用；检查成功后才写回生成区。它不会调用 handler 或运行业务 IO。首次没有 Handlers 时，只分析可用声明与契约，仍可先生成接口；实现后再次生成才检查完整业务源码。

检查覆盖命名空间目录内的手写 Haskell 模块，以及其导入链上的本地业务模块；GHC 需要它们的语法、导入和类型成立。使用 Cabal 项目 package environment 解析依赖，不维护外部函数白名单。顶层检查每次生成都执行，scope 结构缓存命中不会跳过它。

GHC／HLS 的普通类型检查不自行执行这项架构检查。当前接入点是 gencode，尚未实现语言服务器诊断推送或编译器插件。修改业务模块后应重新生成。启动时核对的源码依赖见[主设计](CORE_DESIGN.md#compiler)。

## 显式生成目录

每个命名空间增加 `Generated/Assets.hs`，导出：

```haskell
generatedAssets :: [Asset]
```

`Asset`／`AssetSymbol` 定义在编译产物层的 `Framework.Prototype.Catalog`；`Framework.Gen.Check.Assets` 类检并提取结构化目录，`Framework.Gen.Emit.Assets` 输出目录文本。目录记录类型、构造器和字段及其定义位置；不含业务值、Context 来源、权限 key 或 scope 实例。目录与检查使用同一次 GHC 名称解析，文件内容不变时不重写。目录是派生产物，下次生成会按源码恢复。

显式目录便于 review、LSP 建立引用索引与跨文件跳转，也可供后续 langserver 的描述接口使用。当前执行器不导入这份目录，因此不为它增加启动步骤、运行时状态或清理协议。未来需要可执行文件提供 introspection 时，可以按需导入；这份元数据本身不提供任意 ADT 的 JSON 编解码。
