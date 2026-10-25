# Overall Review Benchmark：声明一个文件报告

候选 C2 · 业务基准 B1 · 2026-09-22 · 持续评审中

**版本关系：本文记录 C2 的接口与业务基线。当前自动 Input superclass、newtype、通用 Result 和闭包连接见 [C5 Effect 示例](effect-sample/README.md)。** C5 自带逐步注释、运行检查与多态约束验证；Read/Map 的最终语义继续独立评审。

C5 的使用写法现为 compile reportArguments、readFrom ReadNow、mapped FormatReport；Handler 用一份 Signature 描述业务参数与原始结果。Effect instance 直接定义 impl 方程，库按 Typing 自动组装注册；impl 写 invoke @"名称" context，由库沿约束链选择提供者并取得资源。完整流程以该示例的 FileEffects.hs → Program.hs 为评审入口，验证范围限于 Effect 层。下文 C2 代码保留其历史接口。

**阅读目标：从注册看清依赖与参数 ADT，从调用处看清参数值来源，从 impl 看清参数解释，从 instance 看清具体操作。** 库根据声明连接执行闭包。

## 1. 这个 sample 做什么

```text
输入：文件 A（ABCD），请求 Take 2
输出：read:AB

能力：fileSession → loadText → reportRead
传值：loadText 的本次结果 → Read → Map → 报告参数
资源：fileSession 管理打开、错误处理和关闭
```

文件 B 内容为 `WXYZ`，相同声明输出 `read:WX`。`FirstChar` 请求输出首字符。

下面的使用代码可以直接对应 [Sample.hs](benchmark/Sample.hs)。这是已经能运行的最小注册子集；完整架构的字段和类型保证继续在内部设计中评审。

## 2. 使用者先写注册

入口将注册与本次调用的参数表达式交给库：

```haskell
sample start = compile reportRead reportArguments
```

注册放在这个函数的 `where` 中。`start` 提供外部能力；参数 ADT 定义一次，由 require 选定，供 impl 拆解。例如 `ReadRequest` 定义在 [FileHandles.hs](benchmark/FileHandles.hs)：

```haskell
data ReadRequest = FirstChar | Take Int
```

注册使用 `ofType @ReadRequest` 声明这一合同。`ofType` 是库提供的类型见证，`noRequire` 声明空参数 `()`。

```haskell
fileSession = Effect
  { typing = Excu, input = supplied start
  , require = ofType @FilePath
  , handler = handlers @"openFile", bind = openImpl
  , scope = closes closeFile reportFileError
  }

loadText = Effect
  { typing = Excu, input = fileSession
  , require = ofType @ReadRequest
  , handler = handlers @"readChars", bind = loadImpl
  , scope = noScope
  }

readLoaded = Effect
  { typing = Read, input = loadText, require = noRequire
  , handler = handlers @"readLoaded", bind = readLoadedImpl
  , scope = noScope
  }

prepareReport = Effect
  { typing = Map, input = readLoaded, require = noRequire
  , handler = handlers @"prepareReport", bind = prepareReportImpl
  , scope = noScope
  }

reportRead = Effect
  { typing = Excu, input = loadText
  , require = ofType @PrepareReport
  , handler = handlers @"writeReport", bind = reportImpl
  , scope = noScope
  }

closeFile = Effect
  { typing = Close, input = fileSession, require = noRequire
  , handler = handlers @"closeFile", bind = closeImpl
  , scope = noScope
  }

reportFileError = Effect
  { typing = X, input = fileSession, require = ofType @IOException
  , handler = handlers @"reportFileError", bind = errorImpl
  , scope = noScope
  }
```

这些语句直接表达：

- `input` 指定上游能力。库沿这条关系连接已绑定的操作。
- `require` 声明参数 ADT。`bind` 指定的 impl 接收这份 ADT 的值。
- `handler` 选定使用的具名类方法，`bind` 绑定业务适配函数。
- `scope` 声明资源边界。关闭和错误处理都获得该次打开的 `FileSession`。

`handlers @"readChars"` 表示按这个名字选择类型类方法。调用关系在 Haskell 类型和编译得到的闭包中连接。

调用处提供满足合同的实际值。主例从 `Request` 取路径和读取请求，再由 Read/Map 生成报告参数：

```haskell
fileArguments = withArgs (argument requestedPath) noArguments
loadArguments = withArgs (argument requestedRead) fileArguments
reportArguments =
  withArgs (mapped prepareReport (readFrom readLoaded)) loadArguments
```

这里每层 `withArgs` 对应声明的 input 链中的一层，`noArguments` 对应起点 `supplied start`。它们只描述参数供给；依赖和 impl 仍由 effect 注册确定。完整节点语法可以生成同样的参数连接。

例如 `Request path (Take 2)` 提供一个 `ReadRequest` 值，lowering 将它交给 `loadImpl`。同一注册可以搭配不同的取值表达式。错误分支的 `IOException` 由 scope 的错误出口提供。

## 3. impl 只解释参数、组装调用表达式

读取请求有两种业务写法：

```haskell
loadImpl :: FileSession -> ReadRequest -> IO LoadText
loadImpl upstream FirstChar = loadImpl upstream (Take 1)
loadImpl upstream (Take count) =
  LoadedText upstream <$> invoke @"readChars" upstream count
```

`FirstChar`、`Take count` 来自注册指定的 `ReadRequest`。impl 将其拆成类方法接受的 `Int`；类方法完成读取，`LoadedText` 包装返回结果。

库中的 `require :: Requirement args` 与 `bind` 的入参共用同一个 `args`，调用参数表达式也产出这个类型。注册写出 `ofType @ReadRequest` 后，这三处就关联到同一份 ADT。

报告 impl 收到上游 effect 和已经连接好的报告参数：

```haskell
reportImpl :: LoadText -> PrepareReport -> IO ReportRead
reportImpl upstream (ReportArgs message) =
  invoke @"writeReport" upstream (ReportArgs message)
```

这里把模式匹配保留下来，展示业务参数如何进入句柄。直接转发的 impl 可以写成 point-free：

```haskell
openImpl          = invoke @"openFile"
readLoadedImpl    = invoke @"readLoaded"
prepareReportImpl = invoke @"prepareReport"
closeImpl         = invoke @"closeFile"
errorImpl         = invoke @"reportFileError"
```

完整类型签名见 [Sample.hs](benchmark/Sample.hs)。该文件中的 impl 使用具体 effect 类型；执行上游、准备参数和资源清理由库连接。

## 4. 句柄提供者实现具体操作

提供者在 [FileHandles.hs](benchmark/FileHandles.hs) 中定义数据和 instance。每个实例声明名字、分类、能力来源、参数和结果，再实现类方法。

```haskell
instance Handler "readChars" 'KExcu FileSession Int String where
  invoke (FileSession _ file trace _) count = do
    trace "read"
    replicateM count (hGetChar file)

instance Handler "writeReport" 'KExcu LoadText PrepareReport ReportRead where
  invoke (LoadedText (FileSession _ _ trace sink) _) (ReportArgs message) = do
    trace "report"
    sink message
    pure (ReportRead message)
```

`do` 中的具体操作集中在这些 instance。Read/Map 的 instance 提供纯变换：

```haskell
instance Handler "readLoaded" 'KRead LoadText () ReadLoaded where
  invoke (LoadedText _ text) () = ReadLoaded text

instance Handler "prepareReport" 'KMap ReadLoaded () PrepareReport where
  invoke (ReadLoaded text) () = ReportArgs ("read:" ++ text)
```

## 5. 库怎样承担从上到下的连接

库从最终的 `reportRead` 注册开始，读到 `input = loadText`，继续连接它的 `fileSession`。随后形成一个包含依赖的执行闭包。

```text
读取声明的方向：reportRead → loadText → fileSession → start
执行依赖的顺序：打开文件 → 读取 → Read/Map 准备参数 → 报告 → 关闭
```

交给 `reportImpl` 时，库已经启动上游，并把本次 `LoadText` 绑定为局部值。Read 和报告句柄使用这个值；纯参数表达式按需求值。两次读取同一结果复用该值，两次独立调用各自执行。

实际消费 record 的实现位于 [Library.hs](benchmark/Library.hs)。内部签名、闭包展开与边界集中在 [LOWERING.md](benchmark/LOWERING.md)。

## 6. 本轮变化与验证

| 部位 | C2 的写法与责任 |
|---|---|
| 注册 | require 选定参数 ADT，bind 绑定接收该 ADT 的 impl |
| impl | 具体 effect 入参、准备好的参数、模式匹配和调用表达式 |
| instance | 具名操作的实际实现，外部 IO 放在这里 |
| lowering | 衔接 input、Read/Map、impl 和 scope，生成闭包 |
| 参数表达式 | 调用处以 withArgs 提供取值或 Read/Map 表达式，产出 require 声明的 ADT |
| 类型关联 | require、impl 入参与调用参数表达式共享 args 类型 |
| 内部机制 | 类型族、字典和资源控制集中在 Library.hs |

GHC 9.12.2 的 `-Wall -Werror` 类型检查与以下 9 个案例通过：

| 场景 | 观察结果 |
|---|---|
| A / Take 2 | read:AB；打开、读取、报告、关闭各一次 |
| B / Take 2 | read:WX；复用相同注册和 impl |
| A / FirstChar | read:A；业务参数适配生效 |
| 读取超过 EOF | 报告错误，随后关闭原 scope |
| 同一闭包调用两次 | 两次独立打开、读取和关闭 |
| 两个 Read 参数表达式 | 共享一次上游读取，输出 read:AB\|AB |
| 同一注册搭配两种参数表达式 | 同一打开的文件先读 A、再读 BC；复用 ReadRequest 合同和 loadImpl |
| 读取入口注入取消异常 | 异常向外传播，scope 执行关闭 |
| middleware 包装 | 增加进入、退出记录，业务结果保持一致 |

另以编译失败案例确认：require 声明 ReadRequest 而 impl 接收 Int、调用处提供 Int、缺少该层参数绑定，均被类型检查拒绝。

准备内容恰为 `ABCD`、`WXYZ` 的两个文件，在项目根目录运行：

```powershell
runghc -idocs/design/benchmark docs/design/benchmark/ClosureSample.hs --verify fileA.txt fileB.txt
```

**当前结论：这个运行子集已接通“声明 → lowering → 闭包 → instance 操作”。** 静态线性 `once`、完整 layer 约束、异构存在封装和正式框架集成继续待实现，详见内部说明。

后续局部优化仍修改同一个 sample，并一起检查：使用者写法发生了什么变化、库接走了什么责任、业务结果是否保持。

## 文件关系

```text
Sample.hs          使用者：effect 注册、调用参数和 impl
    ↓ 使用
FileHandles.hs     提供者：业务数据、类方法 instance
    ↓ 依赖
Library.hs         库：统一 record、类型机制、lowering

ClosureSample.hs   运行以上声明，验证固定业务案例
LOWERING.md       内部原理与当前实现范围
```
