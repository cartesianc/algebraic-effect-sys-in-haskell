# myframework 0.2 使用入门

## 1. 适用范围

本文面向使用 `MyFramework` 编写业务程序的开发者。当前公开 Facade 对应 L0 v5.2
Stage 3，提供 schema elaboration、六种 Effect、Application 和三图 lowering。Input CPS
执行将在 Stage 4 接入。

框架内部结构见[开发者指南](DEVELOPER_GUIDE.zh.md)，长期语义边界见
[L0 合同](L0_EFFECT_LOOP_BOOTLOADER_SEMANTICS.zh.md)。

## 2. 构建

需要 GHC 9.6.7 和 Stack。在仓库根目录执行：

    stack --work-dir .stack-work-codex build
    stack --work-dir .stack-work-codex exec crawler-facade-witness

业务入口只有：

```haskell
import MyFramework
```

## 3. 编程对象

一个程序按以下顺序装配：

    Haskell data type / HasSchema
      -> typed R、command、MAP
      -> Application
      -> Effect module
      -> AST module
      -> program
      -> ElaboratedProgram + SchemaCatalog + three graphs

| 对象 | 作用 |
|---|---|
| `R value` | 声明惰性值来源，进入统一 EffectRegistry |
| `EffectRef kind input output` | 保存稳定 Effect key 与类型合同 |
| `Application` | 固定连接 command、MAP、R |
| `EffectModule` | 把 Application 注册到 AST 模块 |
| `ControlDecl` | 使用 chain、parallel、fallback、race 调度模块或叶子 |
| `PreparedRuntime` | 保存 surface、elaborated program 和三类 graph |

## 4. 定义业务类型

record 使用 `Generic` 提供字段名和字段类型：

```haskell
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DeriveGeneric #-}

import GHC.Generics (Generic)
import MyFramework

data FetchArgs = FetchArgs
  { fetchHeaders :: String
  , fetchUrl     :: String
  }
  deriving (Generic)

instance HasSchema FetchArgs
```

`HasSchema` 默认派生会生成 record 证据。Bool、Integer、Int、Double、String 和 Unit
已有实例。动态 JSON、FFI 和外部协议通过 versioned `Codec` 描述。

## 5. 声明六种 Effect

command 构造函数：

```haskell
createUser = c "create-user" none
updateUser = u "update-user" none
deleteUser = d "delete-user" none
emitAudit  = e "emit-audit" none
```

R 和 MAP：

```haskell
requestSource :: R FetchArgs
requestSource = r "request-source"

requestMap :: EffectRef 'MAP FetchArgs FetchArgs
requestMap = mapping "request-map"
```

input 引用句柄前置链：

```haskell
persistPage :: EffectRef 'C FetchArgs ()
persistPage = c "persist-page" none

emitAudit :: EffectRef 'E FetchArgs ()
emitAudit = e "emit-audit" (after persistPage)
```

input 传递执行结果状态。业务参数沿 ValueGraph 进入 MAP 和 command。

## 6. 组成 Application

```haskell
fetchPage :: EffectRef 'E FetchArgs ()
fetchPage = e "fetch-page" none

fetch :: Application
fetch = apply fetchPage requestMap requestSource
```

`apply` 的类型保证三个位置为：

    command $ MAP $ R

command 参数类型、MAP 输出类型和 R 值类型在 Haskell 层建立约束；lowering 继续检查
字段、arity、schema ID 和 transform registry。

## 7. 注册模块和 AST

```haskell
crawler, fetchModule, parseModule :: Name
crawler     = name "crawler"
fetchModule = name "fetch"
parseModule = name "parse"

crawlerAst = chain crawler [fetchModule, parseModule]
fetchAst   = fallback fetchModule [primary, mirror]
parseAst   = parallel parseModule [parseLinks, parseContent]

fetchEffects = effects fetchModule [primary, mirror]
parseEffects = effects parseModule [parseLinks, parseContent]
```

AST 模块名承担结构分区。Application 的 command key 是模块内叶子名。Lowering 为
EffectRef 生成确定性 qualified identity。

## 8. 构建程序

```haskell
crawlerProgram :: Either [ProgramError] PreparedRuntime
crawlerProgram =
  program
    crawler
    [crawlerAst, fetchAst, parseAst]
    [fetchEffects, parseEffects]
```

`program` 完成：

    SurfaceProgram
      -> elaborateProgram
      -> graph validation
      -> AST/Input/Value lowering
      -> prepareRuntime

失败返回全部已发现的 `ProgramError`。此过程是纯计算，不调用 Handler。

成功后可以读取：

```haskell
programSchemaCatalog currentProgram
programSchemaDigest currentProgram
resolveAll currentProgram
effectRegistryOf currentProgram
transformRegistryOf currentProgram
graphProgramOf (preparedRuntimeProgram currentProgram)
```

## 9. Handler adapter

过程函数保持普通 Haskell 函数：

```haskell
fetchHandler :: FetchArgs -> IO (Either String ())
fetchHandler currentArgs = do
  -- HTTP client、数据库或文件系统调用
  pure (Right ())
```

adapter 绑定 EffectRef 和 versioned codec：

```haskell
fetchAdapter =
  handlerAdapter
    fetchPage
    fetchArgsCodec
    unitCodec
    fetchHandler
```

`HandlerContract` 可进入验证和 artifact。函数 closure 留在 Runtime registry。函数名不
参与 Effect identity。

## 10. SchemaCatalog

Schema 证据来自：

- `HasSchema` 和 Generic；
- literal 与 record；
- MAP 输入输出；
- Handler codec；
- imported catalog；
- versioned dynamic boundary。

record descriptor 按字段 key canonicalize。Handler 参数列表保留 Haskell record 的声明
顺序。catalog 使用 canonical encoding 和 SHA-256 digest。

## 11. 常见错误

| 错误 | 含义 |
|---|---|
| `SchemaUnresolved` | 值边缺少类型、codec 或 imported evidence |
| `SchemaConflict` | 多个证据给出不同结构 |
| `SchemaCodecMissing` | 动态边界没有 versioned codec |
| `ChildReferenceMissing` | AST child 未解析为模块或本模块 Application |
| `EffectReferenceMissing` | input、R 或 MAP 引用了未注册 Effect |
| `EffectInputCycle` | 普通 input graph 成环 |
| `ApplicationParamMismatch` | MAP output 与 command params 不一致 |
| `TransformMissing` | MAP 的 TransformRef 未注册 |

所有静态错误在 Handler 启动前返回。

## 12. 当前阶段边界

已实现：

- schema-free 默认 Facade；
- Surface/Elaborated 分层；
- canonical SchemaCatalog；
- C/U/R/D/E/MAP；
- command/MAP/R Application；
- AST、InputGraph、ValueGraph；
- occurrence 和 AstPath provenance；
- Handler codec adapter；
- v2 显式 migration adapter。

后续阶段：

- defunctionalized Input CPS Runtime；
- Scoped EffSys；
- hanging Middleware；
- Callback PipelinePatch；
- Loop feedback；
- v5.2 promotion 和 `0.2.0-core0` SDK。

旧 artifact 通过 `MyFramework.Legacy.Migration`、`MyFramework.Legacy.Elaboration` 和
`MyFramework.Legacy.Application` 转换。默认 `MyFramework` 不重导出旧表面。
