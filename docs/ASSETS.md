# 源码资产约束

更新：2026-10-27。

资产约束检查普通定义在源码中是否显式依赖框架业务 ADT，并检查 Context 产物只在其生产方中构造；不判断运行时值流向，也不记录 Context 来源或资源关闭归属。

## 集合从哪里来

生成器汇总当前注册集合中 Context 的产物类型，以及消费者 request／require 的接收类型。按真实 Haskell 类型身份去重，再沿业务 ADT 字段递归收集内嵌业务类型，并补全关联类型别名。例如 Crawler 的 StartURL 会带入 PageURL；同一类型无论出现在多少个契约中都只有一个资产条目。String、Handle 等库类型不因出现在字段内而变成资产。

类型、数据构造器和字段均保留模块身份与定义位置。名称解析由 GHC 9.12 完成，导入别名、重导出与同名局部变量不会被简单字符串匹配混淆。只在生成命令可见的业务源码范围内收集与检查，不扫描外部包的实现；SDK 和 Generated 模块不属于手写业务约束范围。

## 哪些定义允许使用资产

- 注册类方法的 instance 实现允许显式构造、匹配、读取和更新资产；但 Context 产物类型只能在其生产方的方法中构造，见下文“构造器归属”。匿名 lambda、局部数据绑定与计算属于方法体。
- 普通顶层函数和顶层值，以及方法内的具名局部函数，不得在签名或方法体中显式引用资产类型、构造器或字段。局部 point-free 函数也检查；GHC 类型信息只用来区分函数绑定与数据绑定，不用于推导资产传播。
- data/newtype/type 声明及 deriving 属于契约定义。注册入口 `Namespace.Effects.effects` 可以通过 `requester "名字" @Asset` 引用表示类型；该模块的其他普通函数并不因此获豁免。
- 泛型函数的定义未显式依赖资产，调用时不会因为实参是资产类型而违规。`identity :: a -> a`、`map`、`show` 等适用同一规则。只处理 String、Handle 等通用类型的普通函数也允许。

例如以下普通函数会被拒绝：

```haskell
parsePage :: FetchedPage -> PageSummary
parsePage ... = ...

-- 删掉签名不能消除构造器的显式引用。
extractHTML (FetchedHTML _ html) = html
```

而 `identity page` 不会因为 `page` 恰好是 FetchedPage 而违规。将资产字段投影成 String 后，约束不继续跟踪该 String。它也不判断某段仅处理通用类型的代码是否在业务意义上值得成为独立 effect。

effect 方法调用另受结构分析约束：effect 组合只能直接写在注册方法体中，不能经普通函数间接进行。这与允许不显式依赖资产的普通函数并不冲突。

## 构造器归属

值来自表达式求值，产生某类值的表达式就是该类型的 Context 生产方：request 重新求值并更新绑定，require 复用已求出的值。若消费方在自己的方法里直接构造这个类型，就等于藏了一个未注册的生产方，绕过了 request／require 的绑定与更新。因此：

- Context 产物类型 T 的构造器只能在 T 的生产方 instance 方法中出现在表达式位置（构造值，包括把构造器当函数使用和记录构造）。
- 对 T 的记录更新同样产生新值，也只能在生产方中进行。
- 其他 instance 可以在模式中使用 T 的构造器取出内容，例如 `StartURL (PageURL url) <- request @StartURL`；视图模式里的表达式部分仍按表达式检查。

例如 Crawler 中，下面的写法若出现在 FetchLinkedPage 的方法里会被拒绝，因为 StartURL 只能由 StartPage 产生：

```haskell
let url = StartURL (PageURL address)
```

Context 的契约类型都由生成器按 handler 名产出，同样受此约束；它们也是资产，普通函数不得显式使用，且不派生 Read。规则只保护产物类型本身的构造器与字段。产物内部的类型（如 StartURL 里的 PageURL）若自身不是 Context 产物，可以在方法体内作为局部数据计算构造。普通顶层函数本来就不能显式使用资产，因此这条规则只在注册 instance 方法之间区分归属。同一类型若有多个生产方（只在没有消费方需要它时允许），这些生产方都可以构造它。

检查只看显式引用，不追踪值流向。已知缺口：`coerce`、泛型函数和派生的 `read` 等不显式写出构造器的方式不会被拦下。生成类型没有 Read 实例，不受 `read` 影响；手写在 Types.hs 中且派生了 Read 的产物类型仍可被 `read "..."` 构造，是否禁止契约类型派生 Read 尚待决定。

## 生成与检查

使用现有命令，例如：

```text
cabal run effect-codegen -- workflow Crawler
```

生成器先从声明形成候选契约和纯结构，再用 GHC 的无代码生成模式取得手写源码的名称解析结果。候选 Generated 文件和本次读取的 Handlers 快照以内存 target 供分析使用；检查成功后才写回生成区。它不会调用 handler 或运行业务 IO。首次没有 Handlers 时，只分析可用声明与契约，仍可先生成接口；实现后再次生成才检查完整业务源码。

检查覆盖命名空间目录内的手写 Haskell 模块，以及其导入链上的本地业务模块；GHC 需要它们的语法、导入和类型成立。使用 Cabal 项目 package environment 解析依赖，不维护外部函数白名单。资产检查每次生成都执行，scope 结构缓存命中不会跳过它。

GHC／HLS 的普通类型检查不自行执行这项架构检查。当前接入点是 gencode，尚未实现语言服务器诊断推送或编译器插件；修改契约、业务模块或普通函数后应重新生成。已有运行入口的过期检测仍核对 Handlers 指纹与注册快照，不是覆盖全部源码文件的资产安全证明。

## 显式生成目录

每个命名空间增加 `Generated/Assets.hs`，导出：

```haskell
generatedAssets :: [Asset]
```

`Asset`／`AssetSymbol` 定义在 SDK 的 `Framework.Effect.Asset`。目录记录类型、构造器和字段及其定义位置；不含业务值、Context 来源、权限 key 或 scope 实例。检查和发射目录使用同一份资产集合，文件内容不变时不重写。目录是派生产物，下次生成会按源码恢复。

显式目录便于 review、LSP 建立引用索引与跨文件跳转，也可供后续 langserver 的描述接口使用。当前执行器不导入这份目录，因此不为它增加启动步骤、运行时状态或清理协议。未来需要可执行文件提供 introspection 时，可以按需导入；这份元数据本身不提供任意 ADT 的 JSON 编解码。
