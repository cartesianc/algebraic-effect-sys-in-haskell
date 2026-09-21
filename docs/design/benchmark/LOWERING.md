# C1 内部说明：从注册连接到闭包

使用方式见 [具体 sample](../OVERALL_REVIEW_BENCHMARK.md)。本文件记录实现机制和候选边界。

## 1. 这一轮真正移动的责任

`reportImpl` 的接口由

```haskell
IO LoadText -> (LoadText -> ReportArgs) -> IO ReportRead
```

变为

```haskell
LoadText -> PrepareReport -> IO ReportRead
```

上游执行、参数表达式连接和 scope 清理由库承担。业务 impl 取得已完成的上游 effect 视图，通过模式匹配适配参数，再调用类方法。`loadImpl` 中的结果包装用纯映射表达。

`PrepareReport` 是本例 Map 的具体结果 ADT，构造器 `ReportArgs String` 同时提供报告所需参数。主例使用单一资源 scope，`LoadText` 保存该次 `FileSession` 的能力视图。

## 2. 统一 record 与句柄字典

[Library.hs](Library.hs) 定义普通、参数化的 `Effect` record；具体上游类型保留在类型参数中，由 `input` 推导。字段为 `typing`、`input`、`require`、`handler`、`bind`、`scope`。

`Handlers` 是携带类型类约束证据的 GADT。`Handler` 用名字和 source 类型确定分类、操作参数与结果，`Action` 类型族区分纯结果和 IO 结果。`bind` 的字段类型可在该约束下使用具体类方法。

在这个具体类型 sample 中，方法实例在 Haskell 类型检查时选定。lowering 打开注册的字典，将具体上游能力与参数注入已绑定的 impl；运行时执行捕获的函数。C1 验证静态绑定路线。相同具体类型的实例在运行时动态替换属于另外的接口设计。

这里的 `Effect` record 与 `Handlers` 字典承担不同层次；全体 effect 的分类类型类、异构注册的存在封装仍需后续整合。前台使用代码保持统一 record。

## 3. 最小 lowering

`connect` 对上游声明递归连接，然后把这一层的 impl 接到下游 continuation。核心实现如下：

```haskell
connect (Effect kind upstream parameters Handlers implementation lifetime) =
  let parent = connect upstream
  in \env next -> parent env $ \ready ->
    let action = liftAction kind
          (implementation ready (prepare parameters env ready))
    in case lifetime of
      NoScope -> action >>= next
      Managed release recover ->
        bracket action release $ \resource ->
          next resource `catch` (\err -> Left <$> recover resource err)
```

上述代码为省略类型应用的阅读版，精确可编译版本见源文件。字典、impl、参数表达式和上游闭包成为这一层闭包的捕获值。

`compile reportRead` 从顶层声明开始连接；实际 IO 按依赖顺序执行。这里采用普通 CPS：continuation 表达“取得当前 effect 之后继续做什么”。

## 4. Read/Map 使用同一次上游结果

`require = mapped prepareReport (readFrom readLoaded)` 编译成接收本次 `LoadText` 的纯参数函数。

`readFrom` 提取 Read 注册的字典与 impl；`mapped` 接上 Map 注册的字典与 impl。它们处理库已绑定的 `ready` 值。`combine` 可以把两个纯参数表达式应用于同一个 `ready`，测试因此能检查“两次 Read、一次实际读取”。

Read/Map 的上游类型在连接时匹配。本例的调用身份由这一条 input 链上的词法绑定确定。对相同结果类型、多个同级调用进行任意引用时，还需要明确作用域和调用引用规则。

本例把调用参数表达式直接放入 `require`，以便独立验证 effect 层。未来节点表面语法可以将表达式连接到这个槽；require 的静态合同与调用时提供的表达式如何分开，仍作为接口设计点保留。

## 5. scope 回指如何成为闭包

注册关系为：

```text
fileSession 的 scope       → closes closeFile reportFileError
closeFile 的 input         → fileSession
reportFileError 的 input   → fileSession
```

以上为字段关系示意。`closes` 把关闭、错误注册编译成使用已有资源的函数：

```haskell
release session = closeImpl session ()
recover session err = errorImpl session err
```

类型关系要求这两个注册接受该资源类型。scope 打开后得到的具体 `session` 直接传给它们。错误参数由 `caughtError` 声明，库在错误出口提供。

主例整体展开的核心形状为：

```haskell
bracket (openImpl start path) (\session -> closeImpl session ()) $ \session ->
  (do
    loaded <- loadImpl session request
    let prepared = prepareReportImpl (readLoadedImpl loaded ()) ()
    Right <$> reportImpl loaded prepared)
  `catch` (\err -> Left <$> errorImpl session err)
```

这个执行结构来自库消费注册，业务 Sample.hs 只填写声明和适配函数。

## 6. 验证范围

| 已有证据 | 当前边界 |
|---|---|
| 单 input 链由真实 record 连接到执行闭包 | 正式工程的 Free/统一 IR 后端集成待完成 |
| 具名句柄、分类对应的调用形状 | 每类必须提供的整组方法、开放插件注册待完善 |
| Read/Map 参数复用本次完成结果 | 动态跨节点共享和并发场景待扩展 sample |
| scope 正常、IOException、取消异常出口清理 | 静态线性 once 尚未实现 |
| 词法捕获同一次 FileSession | 通用 layer 求解与资源逃逸限制尚未实现 |
| 统一参数化 record、具体 impl 类型 | 异构存在封装与完整 Effect 类型类关系待整合 |

本例通过 scope 字段携带资源策略，以类型参数携带结果类型。完整设计中的 once、layer、result 合同和 X/help 等字段，继续作为后续实现要求。独立 scope 引用以 `closes` 表达，错误范围由该连接确定。

异常测试覆盖作用域内抛出的 `UserInterrupt`；跨线程取消时序尚待验证。主体的 `IOException` 在作用域内报告；打开失败和关闭失败向外传播。

测试记录器使用 IORef 收集观察事件。库执行路径由函数、闭包和资源组合器构成；框架 VM 调度表的需求为零。宿主 Haskell 运行时仍负责 IO、内存和异常。惰性参数按需求值，IO 结果共享由显式的局部绑定建立。

本轮检查类型和可观察执行结果。完整消除 IR 分配、字典和闭包包装的优化结论，需另外检查 GHC 优化产物。
