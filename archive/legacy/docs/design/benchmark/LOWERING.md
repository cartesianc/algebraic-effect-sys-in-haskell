# C2 内部说明：参数 ADT 合同与闭包连接

本文件对应 C2。当前自动 Input superclass、newtype 与通用 Result 的可编译定义见 [C5 Effect 示例](../effect-sample/README.md)。

使用方式见 [具体 sample](../OVERALL_REVIEW_BENCHMARK.md)。本文件记录实现机制和候选边界。

## 1. require 确定 impl 的参数 ADT

参数 ADT 定义一次，注册选择这份 ADT，impl 对其值做模式匹配。例如 `require = ofType @ReadRequest` 对应 `loadImpl :: FileSession -> ReadRequest -> IO LoadText`。

库内部的类型见证为：

```haskell
data Requirement args = Requirement

ofType :: forall args. Requirement args
ofType = Requirement

noRequire :: Requirement ()
noRequire = Requirement
```

`Effect` 的 `require :: Requirement args` 和 `bind` 的参数共享 `args`。选择 ReadRequest 后，impl 的对应参数类型也固定为 ReadRequest。这个业务 ADT 可以经 impl 拆解成句柄接受的操作参数，例如 `Take count` 对应读取句柄的 `Int`。

上游执行、调用参数表达式连接和 scope 清理由库承担。业务 impl 取得已完成的上游 effect 视图及合同规定的参数，再调用类方法。`loadImpl` 中的结果包装用纯映射表达。

`PrepareReport` 是本例 Map 的具体结果 ADT，构造器 `ReportArgs String` 同时提供报告所需参数。主例使用单一资源 scope，`LoadText` 保存该次 `FileSession` 的能力视图。

## 2. 统一 record 与句柄字典

[Library.hs](Library.hs) 定义普通、参数化的 `Effect` record；具体上游类型保留在类型参数中，由 `input` 推导。字段为 `typing`、`input`、`require`、`handler`、`bind`、`scope`。

`Handlers` 是携带类型类约束证据的 GADT。`Handler` 用名字和 source 类型确定分类、操作参数与结果，`Action` 类型族区分纯结果和 IO 结果。`bind` 的字段类型可在该约束下使用具体类方法。

在这个具体类型 sample 中，方法实例在 Haskell 类型检查时选定。lowering 打开注册的字典，将具体上游能力与参数注入已绑定的 impl；运行时执行捕获的函数。C2 验证静态绑定路线。相同具体类型的实例在运行时动态替换属于另外的接口设计。

这里的 `Effect` record 与 `Handlers` 字典承担不同层次；全体 effect 的分类类型类、异构注册的存在封装仍需后续整合。前台使用代码保持统一 record。

## 3. 最小 lowering

`Arguments env node` 保存一次调用的参数表达式，按声明的 input 链逐层关联。`WithArgs` 的表达式产出 `args`，其余参数对应上游；`NoArguments` 对应 `Supplied` 起点。业务参数 ADT 与这份内部连接结构各自只有一份职责。

注册类型 `Effect` 已独立于调用环境 `env`。同一个注册可以连接接受不同环境的参数表达式，表达式的结果类型由 require 的合同确定。

`connect` 同时消费声明和参数表达式，递归连接上游，再把这一层的 impl 接到下游 continuation。核心实现如下：

```haskell
connect (Effect kind upstream Requirement Handlers implementation lifetime)
        (WithArgs parameters upstreamArguments) =
  let parent = connect upstream upstreamArguments
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

`compile reportRead reportArguments` 从顶层声明开始连接；实际 IO 按依赖顺序执行。这里采用普通 CPS：continuation 表达“取得当前 effect 之后继续做什么”。

## 4. Read/Map 使用同一次上游结果

注册中的 `require = ofType @PrepareReport` 确定报告参数的 ADT。调用处的 `withArgs (mapped prepareReport (readFrom readLoaded)) loadArguments` 提供产出该 ADT 的表达式。它编译成接收本次 `LoadText` 的纯参数函数。

`readFrom` 提取 Read 注册的字典与 impl；`mapped` 接上 Map 注册的字典与 impl。它们处理库已绑定的 `ready` 值。`combine` 可以把两个纯参数表达式应用于同一个 `ready`，测试因此能检查“两次 Read、一次实际读取”。

Read/Map 的上游类型在连接时匹配。本例的调用身份由这一条 input 链上的词法绑定确定。对相同结果类型、多个同级调用进行任意引用时，还需要明确作用域和调用引用规则。

本例以 `withArgs` 显式展示调用层的参数绑定。完整节点语法可以生成这份连接。参数结构按声明的 input 链定位各层参数，运行时执行已经连接好的闭包；同层多个调用的引用语法继续待设计。

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

类型关系要求这两个注册接受该资源类型。scope 打开后得到的具体 `session` 直接传给它们。关闭注册以 `noRequire` 声明空参数；错误注册以 `ofType @IOException` 声明参数合同，库在错误出口提供实际异常值。

主例整体展开的核心形状为：

```haskell
bracket (openImpl start path) (\session -> closeImpl session ()) $ \session ->
  (do
    loaded <- loadImpl session request
    let prepared = prepareReportImpl (readLoadedImpl loaded ()) ()
    Right <$> reportImpl loaded prepared)
  `catch` (\err -> Left <$> errorImpl session err)
```

这个执行结构来自库消费注册及调用参数，业务 Sample.hs 填写声明、参数表达式和适配函数。

## 6. 验证范围

| 已有证据 | 当前边界 |
|---|---|
| 单 input 链由真实 record 连接到执行闭包 | 正式工程的 Free/统一 IR 后端集成待完成 |
| require、impl 与调用参数共享 ADT 类型；不匹配时编译失败 | 业务值范围等更细合同另行设计 |
| 同一注册连接不同环境和参数表达式 | 完整节点表面语法继续待设计 |
| 具名句柄、分类对应的调用形状 | 每类必须提供的整组方法、开放插件注册待完善 |
| Read/Map 参数复用本次完成结果 | 动态跨节点共享和并发场景待扩展 sample |
| scope 正常、IOException、取消异常出口清理 | 静态线性 once 尚未实现 |
| 词法捕获同一次 FileSession | 通用 layer 求解与资源逃逸限制尚未实现 |
| 统一参数化 record、具体 impl 类型 | 异构存在封装与完整 Effect 类型类关系待整合 |

本例通过 scope 字段携带资源策略，以类型参数携带结果类型。完整设计中的 once、layer、result 合同和 X/help 等字段，继续作为后续实现要求。独立 scope 引用以 `closes` 表达，错误范围由该连接确定。

异常测试覆盖作用域内抛出的 `UserInterrupt`；跨线程取消时序尚待验证。主体的 `IOException` 在作用域内报告；打开失败和关闭失败向外传播。

测试记录器使用 IORef 收集观察事件。库执行路径由函数、闭包和资源组合器构成；框架 VM 调度表的需求为零。宿主 Haskell 运行时仍负责 IO、内存和异常。惰性参数按需求值，IO 结果共享由显式的局部绑定建立。

本轮通过 9 个执行案例，并确认错误 impl 参数类型、错误调用参数类型、缺少参数绑定三种情况均被类型检查拒绝。完整消除 IR 分配、字典和闭包包装的优化结论，需另外检查 GHC 优化产物。
