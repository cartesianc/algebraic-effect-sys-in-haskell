# 源码资产约束

本文是[主设计](LATEST_DESIGN.md)引用的源码约束规范。业务写法先读[指南](GUIDE.md)；本页负责资产集合、业务模块的顶层白名单和资产目录，不描述运行时 scope 归属。

更新：2026-11-08（Stage 2：顶层白名单取代普通函数的资产检查、构造器归属与接收形态检查）。

生成器只检查源码里显式写出的定义；不判断运行时值流向，也不记录 Context 来源或资源关闭归属。

## 集合从哪里来

生成器汇总当前注册集合中 Context 的表示类型和生成的资产类型。按真实 Haskell 类型身份去重，再沿业务 ADT 字段递归收集内嵌业务类型，并补全关联类型别名。例如 Crawler 的 `StartURL` 会带入 `PageURL`；同一类型无论出现在多少个资产中都只有一个条目。`String`、`Handle` 等库类型不因出现在字段内而变成资产。

持续资产使用同一套集合规则：`History T` 是 SDK 提供的读取视图，T 及其业务表示类型仍按上述规则收集，不另建资产目录。

类型、数据构造器和字段均保留模块身份与定义位置。名称解析由 GHC 9.12 完成，导入别名、重导出与同名局部变量不会被简单字符串匹配混淆。只在生成命令可见的业务源码范围内收集与检查，不扫描外部包的实现；SDK 和 Generated 模块不属于手写业务约束范围。

## 顶层白名单

所有值操作都写成 handler 的类方法，经注册进入 effect 链，才能被 SDK 驱动和静态分析。因此业务模块的顶层只允许：

| 模块 | 顶层允许 |
| --- | --- |
| `Types.hs`、`Handlers.hs` 及其他业务模块 | 类型声明（`data`／`newtype`／`type`）与 deriving、instance |
| `Effects.hs` | 以上声明，以及 `effects`；局部辅助写在 `effects` 的 `where` 里 |
| `AST.hs`、`Workflow/*.hs` | 以上声明，以及类型为 `AST` 的命名 workflow |
| `Main.hs` | 以上声明，以及 `main` |

顶层普通函数与顶层值、类声明（handler 类由注册生成）、foreign 声明和 rewrite rule 都被拒绝，诊断给出位置和建议。

方法体内的 `let`／`where` 局部函数、lambda 与局部数据计算不受限制：它们属于 handler，随 handler 进入 effect 链。需要在多处使用的逻辑注册成 handler，通过 effect 组合；以后无副作用的辅助逻辑由 Pure 承接（语义见 [Stage 2：本阶段不处理](NEXT_STAGES.md#stage-2-later)）。

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

GHC／HLS 的普通类型检查不自行执行这项架构检查。当前接入点是 gencode，尚未实现语言服务器诊断推送或编译器插件；修改业务模块后应重新生成。已有运行入口的过期检测仍核对 Handlers 指纹与注册快照，不是覆盖全部源码文件的安全证明。

## 显式生成目录

每个命名空间增加 `Generated/Assets.hs`，导出：

```haskell
generatedAssets :: [Asset]
```

`Asset`／`AssetSymbol` 定义在 SDK 的 `Framework.Effect.Asset`。目录记录类型、构造器和字段及其定义位置；不含业务值、Context 来源、权限 key 或 scope 实例。目录与检查使用同一次 GHC 名称解析，文件内容不变时不重写。目录是派生产物，下次生成会按源码恢复。

显式目录便于 review、LSP 建立引用索引与跨文件跳转，也可供后续 langserver 的描述接口使用。当前执行器不导入这份目录，因此不为它增加启动步骤、运行时状态或清理协议。未来需要可执行文件提供 introspection 时，可以按需导入；这份元数据本身不提供任意 ADT 的 JSON 编解码。
