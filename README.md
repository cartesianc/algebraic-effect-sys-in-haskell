# Algebraic Effect Sys in Haskell

更新：2026-10-26。仓库与 Cabal 包名为 `algebraic-effect-sys-in-haskell`。
本项目以 Haskell 实现 effect 契约、Context 绑定、scope 生命周期与 workflow 解释；共享 SDK 位于 `sdk/Framework`，业务样例位于 `demo`，设计依据位于 `docs`。
原 `docs/design/effect-sample` 已提升为项目根目录；旧根实现、工作流和设计保存在 [archive](archive/README.md)，仅作历史参考。

使用 GHC 9.12.x，在仓库根目录进行普通编译：

```powershell
cabal update
cabal build all
cabal exec -- ghc -idemo -isdk -fno-code demo/RequestBenchmark/Main.hs
```

RequestBenchmark 保持直接编译；其余 demo 和代码生成器由 Cabal 构建。生成与运行命令见下文“SDK 分工与运行”。

各 demo 已按职责分文件：

- 爬虫入口：[demo/Crawler/Main.hs](demo/Crawler/Main.hs)。
- 纯计算入口：[demo/RequestBenchmark/Main.hs](demo/RequestBenchmark/Main.hs)。
- 文件操作入口：[demo/FileDemo/Main.hs](demo/FileDemo/Main.hs)。
- 十文件存续验证：[demo/OpenFilesDemo/Main.hs](demo/OpenFilesDemo/Main.hs)。
- 按参数区分两份 scope：[demo/ScopeInstancesDemo/Main.hs](demo/ScopeInstancesDemo/Main.hs)。
- 三节点并发复用验证：[demo/ScopeReuseDemo/Main.hs](demo/ScopeReuseDemo/Main.hs)。

各目录采用相同布局；纯计算 mock 使用 Target.hs，不新增 AST。

| 文件 | 职责 |
| --- | --- |
| Main.hs | 启动入口 |
| AST.hs／Target.hs | workflow 结构／末端选择 |
| Effects.hs | 手写 effect 注册 |
| Types.hs | 业务 ADT |
| Handlers.hs | instance 与原子操作 |
| Generated/Effects.hs | 自动生成类方法契约与关联类型 |
| Generated/Program.hs | 自动生成末端登记、注册快照与执行入口 |
| Generated/Handlers.hs | SDK 包装后的 instance 与 scope 控制对象的创建；保留上游类方法引用 |

注册 Effects 只依赖业务 Types 与 SDK；Types、Effects、AST／Target 都不导入 Generated 或 Handlers。
生成后的运行依赖为 Types → Generated/Effects → Generated/Handlers → Generated/Program。
手写 Handlers.hs 是生成输入，不与编译副本同时编译；修改方法体后也须重新生成。
SDK 内部的 Codegen 只改写 Generated 目录，手写文件不会被覆盖；demo 不另设 Codegen.hs。
SDK 位于 sdk/Framework，设计文档位于 docs；工具入口配置仍留在根目录。
设计依据见 [DESIGN_METHOD.md](docs/DESIGN_METHOD.md) 与 [LATEST_DESIGN.md](docs/LATEST_DESIGN.md)。

## 文件操作 demo

[注册](demo/FileDemo/Effects.hs) 与 [instance](demo/FileDemo/Handlers.hs) 展示获取文件名、打开、读取、追加写入、关闭。AST 只有 `node "FileWorkflow"`，入口仍为 `main = interpreter ast effects`。

| 注册 | typing | 类方法的业务签名与职责 |
| --- | --- | --- |
| FileLocation | Context | `getFileName / readFileName :: m FileName`，产生路径／读取已绑定路径 |
| ValidateFileName | Pure | `validateFileName :: m ()`，纯检查路径，失败用 raise |
| FileResource | Context | `acquireFile / readOpenedFile :: m OpenedFile`，打开并产出 Handle／读取同一资源 |
| FileSession | Scoped | `openFileSession / closeFileSession :: m ()`，开启引用 acquireFile，关闭读取已有资源并 hClose |
| ReadFile | Context | `readFileText / readLastFileText :: m FileText`，重新读取文本／读取上次文本绑定 |
| WriteFile | Excu | `writeFileText :: m ()`，消费读取结果，追加一行并 flush |
| FileWorkflow | Excu | `runFileWorkflow :: m ()`，末端引用开启、读写与关闭方法 |

生成的 Context 签名写作 `m (Produce 对应Effect)`，关联类型分别指向表中的原生 ADT。分类取决于契约：打开文件的产值入口是 Context；Scoped 管理该操作的存续，不承担 Handle 产值。Error 是第五种设计类别，但 detect／resolve 尚未实现；本例的自动生成错误类型、raise 和 catchError 不冒充 Error typing。

实际调用由末端 instance 向上展开：open → acquireFile → validateFileName → getFileName；随后 require 路径并打开文件。路径和 Handle 在开启期间保存；读写及 close 都 require 同一个 Handle，不重复打开。writeFileText 通过 request 调用 readFileText，按读出文本的字符数生成追加内容；读取方法再次引用 open，SDK 会跳过已开启的方法体。

文件固定为 `demo/FileDemo/output.txt`，首次运行创建为空文件，后续运行保留原文并追加；只需改 getFileName 的实现即可更换路径。本例顺序使用活资源，生命周期 MVar 不等于并发读写锁。正常完成显式 close；已转成 Failure 的读写失败也在末端清理，关闭的次生错误输出到 stderr，原故障继续传播。SDK 自动收尾与异步取消时的资源释放仍待设计。

## 不调用 close 时的十文件验证

运行 `cabal run open-files-demo`。新例的 [AST](demo/OpenFilesDemo/AST.hs) 顺序启动 HoldFiles、InspectFiles、FinishInspection；[注册](demo/OpenFilesDemo/Effects.hs) 和 [instance](demo/OpenFilesDemo/Handlers.hs) 仍独立。

- FileLocations／FileResources 为 Context，分别提供十个路径和十个真实 Handle；FileSession 为 Scoped，一份 scope 持有整组资源。
- HoldFiles 为 Excu，只调用 open 后返回。InspectFiles 为 Excu，下一 Node 再引用 open 并 require 同一资源，检查十个 Handle 在前一 Node 返回后以及主动 GC 后仍打开，随后逐个写入并 flush。
- FinishInspection 为 Excu，最后显式引用同一 Scoped 的 close 方法，检查十个 Handle 全部关闭。此步骤是对照与测试收尾，不是 SDK 自动关闭。

测试有断言：文件不足十个、未 close 却已关闭、写入失败或 close 后仍未关闭都会 raise，不仅打印状态。文件保存在 `demo/OpenFilesDemo/output/`，重复运行追加内容。这里验证的是保留 scope 引用期间的存续；同份 scope 重复 open 只复用，不会产生十份 scope，按参数多实例的验证另见 ScopeInstancesDemo。普通串行获取完成后十个文件同时保持打开，不要求并发打开同一个资源。

## 三个 parallel 节点写同一个文件

运行 `cabal run scope-reuse-demo`。在 [AST](demo/ScopeReuseDemo/AST.hs) 中，准备操作之后是 `parallel [node "WriteFirst", node "WriteSecond", node "WriteThird"]`，全部完成后才检查并关闭。三个 Excu 的 input 都指向同一 SharedFileScope；各自 instance 直接调用 openSharedFile，再 require FileResource，执行一次写入。Scope 的 open／close 仍是同一个 class 的两个方法。

[Handlers.hs](demo/ScopeReuseDemo/Handlers.hs) 中的检测不实现资源去重：SDK 负责同份 scope 的开启互斥。独立的 events.txt 记录真实资源打开与 open 方法体成功执行次数，不因 Context 刷新而重置；Context 内的 IORef 只保存三个写入者使用过的 Handle。汇合后断言：未提前关闭、实际打开一次、open 方法体一次、三个 Handle 相同、first／second／third 各写入一次。写入顺序不固定，最后显式关闭作测试收尾。

每次运行重置 `demo/ScopeReuseDemo/output/shared.txt` 和 events.txt；断言失败通过 raise 返回 Failure。此例检查共享文件上的三次短写入，不把 scope 的生命周期锁当作任意多步业务操作的并发事务锁。当前普通下游失败也不自动判定 scope 失效。

VerifyReuse 在同一 instance 内连续调用两次 close，断言 close 方法体和实际 hClose 都只执行一次。[ScopeClose 检查](checks/ScopeClose.hs) 使用生成的同批 ScopeHandler，直接挂载生成后的 close 方法，先三个并发调用，再一次顺序调用，检查全部成功、仅关闭一次且最终仍为 Closed。它是 SDK 边界测试，不增加 AST 选择 close 的业务语法；成功关闭后可以在 instance 内显式 open 建立新一轮。

## Input 与 instance 内的句柄组合

手写 input 只允许 Root 或非 Context effect；Context 经 context.request／require 声明进入生成的 superclass。生产者自身仍可有 Input、消费其他 Context，也可直接作为 target。原 Input 与生产链的能力同时保留，不重挂来源注册；沿 Input 与 request 收集 scope，require 只读取绑定，不启动生产链。

同一注册集合共用 Root 和运行载体；能力传递及直接约束去重不代表去重实际调用。生成区自动用 Root 的 `handler` 类方法包装每个注册方法，包含 Context 默认 require 与 Scoped.open／close；用户不写额外前缀。Root 当前直接执行原动作，middleware 与 Hanging 尚未实现。可在 [根契约](sdk/Framework/Effect/Contract.hs) 与各 demo 的 Generated/Effects.hs、Generated/Handlers.hs review，手写注册、instance 和 Main 不变。

业务组合在 instance 内直接引用 superclass handler。例如：

```haskell
instance ExtractPageEffect App where
  extractPage = do
    page <- fetchPage
    pure (parsePage page)

instance PrintPageEffect App where
  printPage = do
    page@(PageSummary url _ _ _) <- extractPage
    outcome <- liftIO (printSummary page)
    either (\problem -> raise (PrintPageError (url ++ ": " ++ problem))) pure outcome
```

instance 使用原生 Haskell：在 do 中通过 `<-` 取得 Context 业务值，普通操作直接引用 superclass 方法。可确定匹配的单构造器模式可直接写在 `<-` 左侧；多构造器值先绑定再用普通 case 显式处理，失败通过 raise，不新增 MonadFail。SDK 在注册生成的 Context 入口连接 request 生产与 require 读取；生成器只解析模块／方法边界并包装入口，不改写表达式。方法不新增位置参数，取值顺序、次数与分支由手写方法体保留；运行仍编译 Generated/Handlers，修改实现后须重新生成。

Fetch 的 instance 用 `<-` 取得并匹配 `loadCrawlURLs` 的产物。URL 常量在 CrawlerContext 的 instance 中；SDK 不用外部 withX、initializeX 或 runX 补出调用链。
未被方法体引用的上游操作不会自动执行；这是一条执行可达性规则，不是 GHC 对方法体调用次数的静态证明。

scope 前提由 SDK 沿原 Input 与 request 生产链向上推导，注册不再填写 dependency；上游 Scoped 须同时声明 open／close。爬虫两个 Fetch instance 都直接引用 openCrawlSession；SDK 生成 open／close 包装，跨 Input 链引用同一个 ScopeHandler 的 MVar 和状态。成功开启后重复 open 跳过方法体，成功关闭后重复 close 同样跳过。沿链识别 scope 不自动执行方法；自动收尾仍待接入。

## Node algebra 只 lower 末端

```haskell
ast = chained
  [ parallel [node "ExtractPage", node "ExtractLinkedPage"]
  , chained  [node "PrintPage", node "PrintLinkedPage"]
  ]

main = interpreter ast effects
```

Generated/Handlers 创建各 Scoped 的空控制对象，Generated/Program 自动让所选末端捕获同一批引用，不执行 open 或业务 Context。Node 的 f-algebra 选择末端并 lower 为具体执行函数，branch 组合这些函数；algebra 不创建 scope 状态，也不遍历 Input 另排一份执行顺序。Main 仍为 IO ()，不增加用户装配。
`Target` 构造器、载体构造器和裸运行器不导出；登记 target 不会预先执行业务。纯计算 mock 也只 lower 选中的末端。

爬虫先并行抓取并解析两页，再顺序运行打印链。打印的 instance 再次调用解析句柄，因此重新抓取，不复用前阶段产物。全部成功完成后，最后的 FinishCrawl 节点直接引用 closeCrawlSession，关闭本次共享 scope。
抓取辅助函数显式用 UTF-8 解码页面，SDK 命令行入口用 UTF-8 输出，避免 Windows 的 CP936 默认编码导致页面读取或打印失败；当前样例面向 UTF-8 页面。
`chained` 失败即停止；`parallel` 等待全部分支，按声明顺序汇总或取首个失败。整棵 AST 最终只包装一层 Output，已发生的 IO 不回滚。

## Context 与输出契约的边界

分类仅 Pure、Excu、Scoped、Error、Context；request／require 是 Context 的方法角色，没有独立 Request typing。
当前 demo 先直接引用 Context 生产方法；不预设 Context 从 SDK 注入全局，也不预设在 boot 前统一生产。

SDK 已接通绑定：request 每次执行生产方法，成功后发布并替换当前调用的来源绑定，返回同一个值；require 只读取已捕获的成功绑定，未绑定时报 ContextNotInitialized。
该来源刷新失败时保留旧值并传播原始失败；已完成的其他操作不回滚。普通绑定限定在一次末端启动内；scope 开启期间生产的绑定随该运行句柄跨 Node 保存，仅向依赖它的调用提供，不在独立创建的句柄之间隐式共享。
SDK 从注册生成调用路由，并包装 instance 方法体；业务 instance 不写缓存、回调或额外的 consume。根入口执行生产；链内的生产方法引用按当前消费者的 context.request／require 选择模式，未声明的业务取值报错。
若同一消费者对同一来源同时声明两种模式，生产方法引用采用 request，显式读取方法采用 require。
生产方的方法名放在 typing；消费方统一写在 context，例如：

```haskell
context = Just ContextInput
  { request = Just (From "FetchLinkedPage" (typeRef @FetchedPage))
  , require = Nothing
  }
```

每种消费方式都声明来源与接收 ADT，移除旧的外层 requires／request。
生成器据此生成 Require、注入来源能力并检查成功类型。方法不新增位置参数，instance 用原生 `<-` 取得业务值；SDK 在来源入口接管取值模式，保留方法体中的取值位置。
数字 demo 的 RenderNumber 同时 request AddOne、require DemoContext；方法体仍直接调用 addOne 和 loadDemoInputs，后者读取 MakeNumber 先前建立的绑定。

业务 ADT 使用原生 data/newtype；顶层 produces 已移除，Context 的生产入口声明业务产物：

```haskell
typing = Context
  { request = Just Producer
      { handler = "fetchPage"
      , produces = typeRef @FetchedPage
      }
  , require = Just "readFetchedPage"
  }
```

request 与 require 共用这份业务类型。SDK 内部的关联 Produce 直接表示成功类型，普通 Pure／Excu 为 ()。
SDK 自动生成 effect 标记、`FetchPageError String` 这类本地错误及统一分类；用户写 `raise (FetchPageError message)`。
统一 Failure 保存 origin、detail 分类与 message，原始失败沿链短路，最终只包装一次 Output。

Scoped 只声明开启／关闭方法名，两者都不产值；信息由上游 Context 提供：

```haskell
typing = Scoped
  { open = Just "openCrawlSession"
  , close = Just "closeCrawlSession"
  }

openCrawlSession  :: m ()
closeCrawlSession :: m ()

-- 用户 instance 仍直接引用 superclass handler。
openCrawlSession = do
  CrawlSessionInfo name _ <- createCrawlSession
  liftIO (putStrLn ("[scope] open " ++ name))
```

createCrawlSession 属于上游 SessionContext，此例没有开启输入，按无参 scope 复用。SDK 保存开启期 Context，供依赖链 require 读取。开启失败／中断后失效；成功 close 不重复执行，之后显式 open 可重开。公开 interpreter 自动创建本次共享句柄，不做跨启动全局缓存。

有参数时，SDK 从资源 Context 的依值声明确定参数来源，观察 instance 内真实返回的 ADT 值，以 Eq 区分实例；不增加 key，不提前执行 Context。每次 open 仍取得本次参数，资源 IO 必须在参数齐备后执行。复用有效实例时传递原 Context 绑定，跳过资源获取和剩余 open 方法体。ContextBinding 保存值快照及 scope 归属；require 读取已捕获的绑定，close 在 instance 实际 require 时从绑定取得关闭目标和锁，无需先 open 选中。另一条链的发布不会改写已捕获快照；显式 request 则替换当前调用的绑定。跨链首次读取存在多份候选且没有关联时，报 AmbiguousContextBinding，不猜测最近一份。不识别任意 IO 闭包内的隐藏参数，具体边界见 [scope 设计](docs/LATEST_DESIGN.md#scope-存续与可调用性)。

运行 `cabal run scope-instances-demo`：一个 interpreter 内，文件一真实打开／关闭 1 次，文件二 2 次（包含关闭后重开）；验证同参同 Handle、异参独立、跨 Node 复用、require 和 close 对应同份。五次 open 恰好执行五次参数 request，没有外部额外取值。[注册](demo/ScopeInstancesDemo/Effects.hs) 与 [instance](demo/ScopeInstancesDemo/Handlers.hs) 保持原有写法；参数 FileName 只需原生 `deriving (Eq, Show)`。

生命周期锁不代替使用与关闭的并发协调。Error 检测、自动收尾和取消清理仍未实现；本次多实例协议接在 App／IO，纯计算 benchmark 不含 Scoped。

## SDK 分工与运行

| 模块 | 职责 |
| --- | --- |
| [SDK.hs](sdk/Framework/SDK.hs) | 统一入口与命令行 |
| [Effect.hs](sdk/Framework/Effect.hs) | Effect 入口，内部细分契约、注册、Context 原语与 Runtime |
| [Effect/Binding.hs](sdk/Framework/Effect/Binding.hs) | Context 值快照与资源归属，按绑定传递 |
| [Effect/Scope.hs](sdk/Framework/Effect/Scope.hs) | scope 实例集合、状态协议与生命周期锁 |
| [Effect/Runtime/App.hs](sdk/Framework/Effect/Runtime/App.hs) | IO 载体、实际输入观察、Context 绑定读取与生命周期路由 |
| [Recursion.hs](sdk/Framework/Recursion.hs) | 纯 Fix、Algebra、cata |
| [Workflow/AST.hs](sdk/Framework/Workflow/AST.hs) | AST 结构与目标收集 |
| [Workflow/Execution.hs](sdk/Framework/Workflow/Execution.hs) | Node lowering 与 branch 执行 algebra |
| [Codegen.hs](sdk/Framework/Codegen.hs) | 生成契约、superclass、调用路由与末端登记，不生成外部操作链 |
| [Codegen/Handlers.hs](sdk/Framework/Codegen/Handlers.hs) | 用 GHC 解析模块与方法边界，生成包装后的 instance 副本 |
| [Generate.hs](sdk/Framework/Generate.hs) | 独立生成命令，编译声明并解析 handler 源码 |

在项目根目录运行：

```powershell
cabal run effect-codegen -- workflow Crawler
cabal build crawler-demo
cabal run crawler-demo

cabal run effect-codegen -- workflow FileDemo
cabal build file-demo
cabal run file-demo

cabal run effect-codegen -- workflow OpenFilesDemo
cabal run open-files-demo

cabal run effect-codegen -- workflow ScopeReuseDemo
cabal run scope-reuse-demo
runghc -idemo -isdk checks/ScopeClose.hs

cabal run effect-codegen -- workflow ScopeInstancesDemo
cabal run scope-instances-demo

cabal run effect-codegen -- target RequestBenchmark
ghc -idemo -isdk -fno-code demo/RequestBenchmark/Main.hs
runghc -idemo -isdk demo/RequestBenchmark/Main.hs
```

首次先定义业务 ADT、注册与 AST／Target，再运行 SDK 生成命令，依据生成接口实现 handler，最后编译运行。
effect-codegen 在 Generated 完全缺失或 handler 尚未实现时也可使用；它通过 GHCi 编译纯声明，用当前 GHC 9.12 的解析器读取已有 Handlers.hs 的语法边界，不分析方法体业务语义、不回写手写源码、不使用 Template Haskell。缺少 Handlers.hs 时先生成空编译模块，实现后再次生成。
已有工程的 Main --generate 仍可重生成，但需要 Main 的导入链能编译；首次生成或新增 effect 时使用上面的 SDK 命令。
两种入口统一经过 SDK 命令，只重写 Generated 下的 Effects.hs、Program.hs、Handlers.hs，不执行业务。
当前只要求普通编译，不新增测试或额外检查门槛。CrawlSession 仍是会话操作 mock，已接通 SDK 的共享状态与开启期 Context；自动收尾、Error 检测处置、Generic Map、loop／Hanging 及跨入口存续仍待落实。

Context 绑定规则已进入底层表示与执行原语；注册、手写 instance 与 Main 保持不变，没有新增 key 或 Method。固定绑定的 require 稳定不等于实际 IO 纯化：任意业务 instance 的纯性、完整 Error 协议与自动收尾尚未获得架构保证。
