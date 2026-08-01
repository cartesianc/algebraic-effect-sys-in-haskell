# myframework 使用入门

## 1. 这份文档给谁看

本文服务于使用 myframework 编写业务程序的开发者。阅读完后，你可以：

- 从 MyFramework 单一入口导入 SDK；
- 声明名称、数据源和参数绑定；
- 声明 R 数据源；
- 注册 C/U/D/E Effect；
- 使用 chain、parallel、fallback 组织 AST；
- 注册后台 Handler；
- 验证、运行并读取结果快照；
- 理解 v5.2 的 schema elaboration、MAP、Loop 和 Scoped EffSys 目标语法。

框架内部实现、递归方案、RuntimeAction、demand graph、diagnosis 和自举机制放在
[框架开发者指南](DEVELOPER_GUIDE.zh.md)。稳定语义合同放在
[L0 框架规范](L0_EFFECT_LOOP_BOOTLOADER_SEMANTICS.zh.md)。

## 2. 先确认版本

仓库同时包含当前可运行表面和 v5.2 目标合同。

| 表面 | 状态 | 用途 |
|---|---|---|
| v2-compatible Facade | 当前可运行 | 本文第 3 至 12 节 |
| v5.2 Effect–MAP Facade | 目标设计 | 本文第 13 节 |

当前可运行表面包含：

- import MyFramework；
- 模块化 chain、parallel、fallback、race 声明；
- C/U/D/E Effect record；
- 独立 R registry；
- Effect input 句柄链；
- Handler 注册；
- 运行结果和状态快照。

当前 Facade 尚未提供正式 MAP Effect、Scoped EffSys FCE、hanging middleware、
callback graph patch、完整 Loop 反馈语法和 schema-free elaboration。目标示例会标记
DESIGN TARGET。

## 3. 构建并运行仓库示例

需要 GHC 9.6.7 和 Stack。

在仓库根目录执行：

    stack --work-dir .stack-work-codex build
    stack --work-dir .stack-work-codex exec crawler-facade-witness

crawler-facade-witness 是当前公开 Facade 的完整可执行示例。它只导入 MyFramework。

## 4. 七个核心对象

当前可运行 Facade 的装配顺序：

    Name
      -> Schema
      -> R
      -> Effect
      -> AST
      -> Handler
      -> Program

| 对象 | 作用 |
|---|---|
| Name | 给模块、Effect 和参数建立稳定名称 |
| SchemaIdentity | 描述运行时数据形状 |
| R | 声明惰性数据源 |
| Effect | 声明 command 类型、input 和参数绑定 |
| AST | 组织模块、顺序、并行和备选分支 |
| Handler | 提供实际 IO 实现 |
| ReferencedProgram | 汇总 AST、Effect module 和 R registry |

v5.2 业务 authoring 顺序：

    Name
      -> R / Effect
      -> AST
      -> Handler adapter
      -> SurfaceProgram
      -> elaborate
      -> validate / run

Schema 在 elaborate 阶段生成。普通业务代码不声明 SchemaIdentity。

## 5. 第一个程序

下面按声明顺序构造一个 hello 程序。

### 5.1 导入

业务文件只需要：

    module Main (main) where

    import MyFramework

### 5.2 声明名称

    app, hello, message :: Name

    app = name "app"
    hello = name "hello"
    message = name "message"

app 是 AST 模块名，hello 是模块内 Effect key，message 是参数名。

### 5.3 当前兼容 API：声明 schema

    textType :: SchemaIdentity
    textType = scalarType "Text"

常用构造器：

    scalarType "Url"

    recordType "Request"
      [ FieldName "url"     .= scalarType "Url"
      , FieldName "headers" .= scalarType "Headers"
      ]

    unitType

SchemaIdentity 参与静态检查和运行时 RuntimeData 校验。

这一小节只适用于当前 v2-compatible Facade。显式 schema 已列入迁移表面。v5.2
Facade 会从类型、codec、literal、record 和 MAP 合同生成 SchemaCatalog。

### 5.4 声明 R

    messageR :: R
    messageR = r "message-source" textType

R 声明一个具名、带 schema、惰性求值的数据源。真实读取函数在 Handler registry
中注册。

### 5.5 声明 Effect

    appEffects :: EffectModule
    appEffects =
      effects app
        [ hello
            .= Effect
              { crude = E
              , input = none
              , params =
                  [ message .= fromR messageR
                  ]
              }
        ]

字段含义：

| 字段 | 当前 Facade 类型 | 作用 |
|---|---|---|
| crude | C、U、D、E | 选择 command 分类 |
| input | Maybe Name | 引用同一模块内的上游 Effect |
| params | [(Name, Binding)] | 声明 Handler 的输入 record |

Effect 左侧的 hello 已经提供身份。record 内没有 id 字段。

### 5.6 声明 AST

    appAst :: ControlDecl
    appAst =
      chain app [hello]

AST 模块 app 通过局部 key hello 引用 Effect。

### 5.7 汇总 Program

    appProgram :: ReferencedProgram
    appProgram =
      program
        app
        [appAst]
        [appEffects]
        (readRegistry [messageR])

此时已经得到完整、可检查的前台程序。

### 5.8 先验证

    programErrors :: [FrontendError]
    programErrors =
      validate appProgram

    resolvedProgram :: Either [FrontendError] ResolvedNode
    resolvedProgram =
      resolveAll appProgram

运行前应保证：

    null (validate appProgram)

### 5.9 注册 Handler

    helloHandler ::
      RuntimeData ->
      IO (Either String ())
    helloHandler currentArgs = do
      print currentArgs
      pure (Right ())

    appHandlers ::
      Either FrontendRegistryError FrontendHandlers
    appHandlers = do
      withMessage <-
        registerFrontendRead
          (readKeyOf messageR)
          (pure (Right (RuntimeText "hello")))
          emptyFrontendHandlers

      registerFrontendEffect
        (address app hello)
        helloHandler
        withMessage

R Handler 产生 RuntimeData。Effect Handler 接收已经绑定好的 RuntimeData record。

### 5.10 运行

    main :: IO ()
    main =
      case appHandlers of
        Left currentError ->
          print currentError

        Right currentHandlers -> do
          currentRun <-
            runReferencedProgram
              appProgram
              currentHandlers

          print (frontendRunOutcome currentRun)
          print (frontendRunSnapshot currentRun)

运行结果包含：

    frontendRunOutcome
      :: Either FrontendRuntimeFailure ()

    frontendRunSnapshot
      :: FrontendRuntimeSnapshot

快照记录每个 Effect occurrence 和 R 的执行状态。

## 6. 参数绑定

当前 Facade 使用 Binding 表达参数来源。

### 6.1 从 R 读取

    url .= fromR seedUrl

### 6.2 字面量

    limit .=
      literal
        (scalarType "Integer")
        (ParamInteger 20)

### 6.3 嵌套 record

    request .=
      record requestType
        [ url     .= fromR seedUrl
        , headers .= fromR requestHeaders
        ]

运行时会：

1. 惰性求值引用的 R；
2. 构造 RuntimeData record；
3. 按 ParamBinding schema 校验；
4. 把完整 record 传给 Effect Handler。

## 7. Effect input

input 声明同一模块内的上游 Effect：

    prepare
      .= Effect
        { crude = E
        , input = none
        , params = []
        }

    execute
      .= Effect
        { crude = E
        , input = after prepare
        , params = []
        }

执行 execute 时，runtime 先运行 prepare，再运行 execute。共享 input 在同一次运行
中使用 single-flight，多个依赖者会等待同一份完成结果。

input 传递句柄状态和启动关系。业务参数继续由 params/R 绑定。

## 8. AST 控制组合

### 8.1 Chain

    chain crawler [fetch, parse, persist]

children 按顺序执行。前一个 child 失败后，后续 child 不再启动。

### 8.2 Parallel

    parallel parse [links, content]

当前 Frontend runtime 使用 Haskell lightweight thread 并发执行 children，等待全部
完成后汇总失败。

### 8.3 Fallback

    fallback fetch [primary, mirror]

按声明顺序尝试。primary 失败后启动 mirror。任一 child 成功后结束。

### 8.4 Race

    race query [remote, local]

Facade 可以声明 Race。当前简化 Frontend runtime 会返回
FrontendControlUnsupported。完整 typed runtime 已有 worker race、取消和 drain
基础设施。

### 8.5 模块引用

    chain crawler [fetch, parse, persist]
    fallback fetch [primary, mirror]
    parallel parse [links, content]

crawler 的 children 解析为子模块；fetch 和 parse 的 children 解析为各自模块内
Effect。AST 层级提供模块边界。

## 9. C、U、R、D、E、MAP

### 9.1 当前可运行类型

| 类型 | 当前表示 | 运行行为 |
|---|---|---|
| C | Effect.crude = C | 调用注册的 command Handler |
| U | Effect.crude = U | 调用注册的 command Handler |
| D | Effect.crude = D | 调用注册的 command Handler |
| E | Effect.crude = E | 调用注册的 command Handler |
| R | 独立 R + ReadRegistry | 惰性读取 RuntimeData |
| MAP | 尚未进入当前 Facade | 当前由 ParamBinding/record 完成值对齐 |

C/U/D/E 目前是四个类型化 command tag。框架不会根据字母自动添加数据库 CRUD、
重试、事务或幂等行为。项目可以制定自己的业务命名约定。

### 9.2 R

R 负责值来源：

- 外部输入；
- 配置；
- Handler 环境；
- 未来的 command observation；
- 未来的 Scoped EffSys 状态查询。

R 的读取是惰性的，并在一次运行内使用 single-flight。

### 9.3 MAP

v5 将 MAP 提升为正式 Effect。MAP 负责：

- 读取一个或多个 R；
- 执行具名 transform；
- 产生 record；
- 对齐 command.params。

当前写法：

    Effect
      { crude = E
      , input = none
      , params =
          [ url     .= fromR seedUrl
          , headers .= fromR requestHeaders
          ]
      }

v5 目标写法：

    fetchPage $ requestMap $ requestSource

两种写法表达相同的参数来源关系。v5 会把这条关系独立保存为数据赋值图。

## 10. Handler 编写原则

Handler 管理真实过程：

- HTTP 请求；
- 数据库访问；
- 文件读写；
- SDK 调用；
- 序列化库；
- 网络客户端；
- 业务算法。

前台 Effect record 管理：

- key；
- command type；
- input；
- 参数 schema；
- 值来源；
- AST 可达性。

Handler 应返回显式失败：

    pure (Left "network unavailable")

同步异常会被 runtime 捕获并转换为 FrontendHandlerThrew。

## 11. 查看错误与状态

### 11.1 静态错误

常见 FrontendError：

- 根模块缺失；
- child 引用缺失或歧义；
- Effect input 缺失；
- Effect input 成环；
- R key 缺失；
- schema 不一致；
- 重复模块、Effect key 或参数 key。

先调用：

    validate appProgram

需要完整解析树时调用：

    resolveAll appProgram

### 11.2 运行错误

常见 FrontendRuntimeFailure：

- Handler 未注册；
- R Handler 未注册；
- R 值 schema 错误；
- Effect 参数 schema 错误；
- Handler 返回失败；
- Handler 抛出异常；
- Fallback 耗尽；
- Parallel 某些分支失败；
- 当前 runtime 尚未支持某个 ControlKind。

### 11.3 状态快照

    frontendSnapshotEffects
      (frontendRunSnapshot currentRun)

    frontendSnapshotReads
      (frontendRunSnapshot currentRun)

完整 typed runtime 还提供 execution、read、validity、implementation、observation、
event 和 diagnosis 多通道信息。详见开发者指南。

## 12. 当前爬虫结构

一个典型爬虫使用四个模块：

    chain crawler [fetch, extract, persist]
    fallback fetch [primary, mirror]
    parallel extract [links, content]
    chain persist [page, links]

各模块分别注册 Effect：

    effects fetch
      [ primary .= Effect { ... }
      , mirror  .= Effect { ... }
      ]

    effects extract
      [ links   .= Effect { ... }
      , content .= Effect { ... }
      ]

    effects persist
      [ page  .= Effect { ... }
      , links .= Effect { input = after page, ... }
      ]

完整源码位于：

[CrawlerFacadeWitness.hs](../app/CrawlerFacadeWitness.hs)

运行：

    stack --work-dir .stack-work-codex exec crawler-facade-witness

## 13. v5.2 编程模型预览

本节状态为 DESIGN TARGET。当前源码不能直接编译这些声明。

### 13.1 业务前台不声明 Schema

    type R value = Effect 'R Unit value

    seedUrl :: R Url
    seedUrl = r "seed-url"

    requestHeaders :: R Headers
    requestHeaders = r "request-headers"

    request =
      record
        [ url     .= fromR seedUrl
        , headers .= fromR requestHeaders
        ]

Url、Headers 和 record 字段通过 typed declaration、Generic 或 codec catalog elaboration。
普通业务代码不调用 scalarType、recordType 或 unitType。R 是六种 Effect 中 R kind 的
typed facade alias。

动态或外部数据在 Handler adapter 注册 versioned codec：

    registerRead seedUrl urlCodec readSeedUrl

codec 是序列化边界合同。readSeedUrl 的过程实现保持独立。

### 13.2 六种 Effect 统一注册

    Effect seedUrl =
      { type   = R
      , input  = crawlerInput
      }

    Effect requestMap =
      { type   = MAP
      , input  = seedUrl
      , output = [url, headers]
      }

    Effect fetchPage =
      { type   = C
      , input  = openSession
      , params = [url, headers]
      }

SchemaRef 在 elaborated IR 中生成，不写入上述 Source Effect record。

### 13.3 Application

    primary =
      fetchPage $ requestMap $ seedUrl

AST 叶子显式记录：

    command
    mapper
    reader

input 继续记录句柄启动链。

### 13.4 Scoped EffSys

    crawlerEffects =
      effectsOf crawler

crawlerEffects 是可序列化、带 AST 作用域的 EffSysRef。Middleware 可以查询其
Effect pipeline 和运行状态。

### 13.5 Middleware

    middleware crawlerMetrics crawlerEffects
      run (recordMetrics $ metricsMap $ crawlerScopeR)

### 13.6 Callback

    callback injectAuth (continuationOf fetch)
      run (authPatch $ authPatchMap $ fetchScopeR)

Callback 返回受检的 input graph patch。

### 13.7 Loop

    loop liveSearch
    chain liveSearch [fetch, parse, persist]

Loop 只有一个 child reference。它提供局部反馈和重新求值权。Loop 外的 Application
按一次 boot demand 执行一次。

## 14. 下一步读什么

| 目标 | 文档 |
|---|---|
| 继续理解内部编译和运行 | [框架开发者指南](DEVELOPER_GUIDE.zh.md) |
| 查看长期冻结语义 | [L0 框架规范](L0_EFFECT_LOOP_BOOTLOADER_SEMANTICS.zh.md) |
| 了解当前 runtime 边界 | [Runtime](RUNTIME.md) |
| 了解 SDK 生成 | [SDK Source Artifact](SDK_SOURCE_ARTIFACT.md) |
| 了解 TrustBase | [TrustBase](TRUST_BASE.md) |
