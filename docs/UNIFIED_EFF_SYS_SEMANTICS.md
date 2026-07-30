# Unified EffSys 语义修改说明

> **已被 L0 冻结语义取代：** 本文只保留为迁移实现记录。最高层级语义见
> [`L0_REFERENCED_AST_SEMANTICS.zh.md`](L0_REFERENCED_AST_SEMANTICS.zh.md)。
> “统一 EffSys、全局限定 HandleId、R 位于 input 图、完整嵌套 Blueprint”
> 均不是目标 façade，不得以本文覆盖 L0。

状态：迁移实现记录；本地 build 与 focused witnesses 曾通过，尚未执行 core promotion gate  
范围：EffSys facade、CURDE identity、AST authoring、lowering、validation、SDK schema  
不包含：Handler 业务实现、发布 promotion、self-artifact witness 执行

## 1. 决定摘要

框架只保留一个逻辑上的 `EffSys`。所有 `R/C/U/D/E` Handle、每个 Handle
至多一个的 `input` 前驱、schema、R source 和 observation contract 都注册到这
一个全局声明图中。

AST 负责：

- 业务模块的组合与布局；
- `Chain`、`Parallel`、`Fallback`、`Race` 等控制语义；
- 在 `Run` 叶子上把一个 `C/U/D/E` target 与一个惰性的 `RExpr` 参数绑定。

Handler Registry 继续独立负责后台函数实现。Runtime State 继续独立负责执行
状态、R 值、observation、validity 和 implementation 状态。

最终边界是：

```text
EffSys          = 全局 Handle 声明 + input 启动图
AST             = 模块组合 + 控制树 + Run(CUDE, RExpr)
HandlerRegistry = HandleId -> 后台函数
RuntimeState    = 一次 boot run 的动态状态
```

`EffectSystemName` 不再是每个 `r/c/u/d/e` 构造器的显式参数，也不再存在多个
Effect System 之间的 imports/private/exports 运行语义。

## 2. 修改前语义（V1）

当前代码把系统身份编码进每个 Handle：

```haskell
data HandleId = HandleId
  { handleIdEffectSystem :: EffectSystemName
  , handleIdLocalName :: String
  }
```

每个 CURDE 构造器都要求显式传入系统：

```haskell
r :: EffectSystemName -> ReadSpec value -> Handle name 'R () value
e :: EffectSystemName -> CommandSpec args observation
  -> Handle name 'E args observation
```

一个 `EffectSystem` 同时承担四种职责：

```haskell
data EffectSystem = EffectSystem
  { effectSystemName :: EffectSystemName
  , effectSystemImports :: [EffectSystemName]
  , effectSystemHandles :: [SomeHandleRef]
  , effectSystemPrivate :: [SomeHandleRef]
  , effectSystemExports :: [SomeHandleRef]
  }
```

因此当前 validator 需要处理：

- 重复 Effect System；
- system import；
- Handle 是否声明在正确 system；
- private/export 是否属于 system；
- 跨 system input 是否已 import/export；
- private observation 是否越过 system 边界。

当前 Core 也保存多个系统：

```haskell
data CURDECore = CURDECore
  { curdeCoreEffectSystems :: [EffectSystemDecl]
  , curdeCoreImplementations :: [ImplementationDecl]
  , curdeCoreAst :: AstBlueprint
  , curdeCoreDemandGraph :: DemandGraph
  }
```

### 2.1 已经符合最终决定的部分

以下语义不需要重写：

1. `RExpr` 已经只允许 R reference、literal 和 closed product/record。
2. `Implementation` 已经是 `C/U/D/E Handle + RExpr args`。
3. `ImplementationDecl` 已经直接出现在 AST 的 `Leaf` 或
   `WithImplementation`，lowering 不接受第四个全局 Implementation Registry。
4. DemandGraph 已经明确分开：
   - `InputDependency`：Handle 的 input 启动关系；
   - `ArgumentUse`：Implementation 对 R 数据的参数依赖；
   - `InvokeImplementation`：Handle 与参数绑定后的调用关系。
5. Runtime 已经在 demand R 时先 demand input，并且把 HandlerInput 限定为
   identity/status/validity；业务数据不会通过 input channel 传递。
6. AST 已经由 `Fix AstF` 和 `cata` lowering。

因此“Implementation 直接写在 AST 叶子上”和“input 与业务参数分离”并不是
全新运行语义，而是当前内部语义的 facade 收敛。

## 3. 最终语义

### 3.1 单一 EffSys

建议的 canonical 声明：

```haskell
data EffSysDecl = EffSysDecl
  { effSysHandles :: [HandleDecl]
  }
```

第一阶段可以继续把 input 保存在：

```haskell
handleDeclInput :: Maybe HandleId
```

这已经足以把所有 input 边注册到一张全局图。后续若需要更直接的图操作，可以
规范化为：

```haskell
data InputEdge = InputEdge
  { inputDependent :: HandleId
  , inputPrerequisite :: HandleId
  }

data EffSysDecl = EffSysDecl
  { effSysHandles :: [HandleDecl]
  , effSysInputEdges :: [InputEdge]
  }
```

无论物理表示选择哪一种，语义约束保持不变：

```text
每个 Handle 最多一个显式 input
所有 HandleId 在统一 EffSys 内唯一
所有 input 引用必须存在
统一 input 图无环
```

### 3.2 Handle 身份

删除 `HandleId` 中的 `EffectSystemName` 字段，但不能删除稳定身份本身。

建议使用全局限定名：

```haskell
newtype HandleId = HandleId
  { handleQualifiedName :: String
  }
```

例如：

```text
crawler.seed-url
crawler.fetch-page
crawler.fetched-page
storage.persist-page
```

`crawler` 和 `storage` 是业务模块路径，不是不同的 Effect System。

模块 scope 可以作为 AST authoring sugar：

```haskell
module_ @"crawler" $
  Run
    (e @"fetch-page")
    (record
      { url = r @"seed-url"
      })
```

在进入 canonical serialized AST 前展开为：

```text
e @"crawler.fetch-page"
r @"crawler.seed-url"
```

模块作用域不应使用 `step:0/branch:1` 这样的 AST 位置作为持久身份，因为插入
节点会改变位置。必须使用稳定模块名和稳定局部 Handle 名。

### 3.3 R facade

当前低层形式：

```haskell
r @"crawler.seed-url" currentSystem currentReadSpec
```

第一阶段删除重复 system 参数：

```haskell
r @"crawler.seed-url" currentReadSpec
```

第二阶段由 facade 推导 schema 和默认 source：

```haskell
seedUrl :: R Url
seedUrl = r @"crawler.seed-url"
```

必要的非默认来源继续显式标注：

```haskell
fetchedPage :: R Page
fetchedPage =
  r @"crawler.fetched-page"
    `fromObservationOf` e @"crawler.fetch-page"
```

R 的核心语义不改变：

```text
R = 具名、typed、lazy、single-flight、可缓存的公共 Fact
```

### 3.4 AST 中的直接 Implementation

已实现的 authoring 形式：

```haskell
run
  (fetchPage crawlerEffects)
  ( productRecord fetchArgsSchema
      [ FieldExpr
          (FieldName "url")
          (rRef (seedUrl crawlerEffects))
      ]
  )
```

类型关系：

```haskell
fetchPage crawlerEffects
  :: Handle "crawler.fetch-page" 'E FetchArgs FetchObservation
seedUrl crawlerEffects
  :: Handle "crawler.seed-url" 'R () Url
rRef (seedUrl crawlerEffects)
  :: RExpr Url
productRecord fetchArgsSchema [...]
  :: RExpr FetchArgs
```

前台不要求用户先声明：

```haskell
fetchImpl = implE fetchPage fetchArgs
```

`run target arguments` lowering 后仍然生成当前内部结构：

```haskell
ImplementationDecl
  { implementationDeclaredKind = E
  , implementationTarget = HandleId "crawler.fetch-page"
  , implementationArguments =
      RProductDecl
        fetchArgsSchema
        [ ("url", RReferenceDecl
            (HandleId "crawler.seed-url")
            urlSchema)
        ]
  }
```

所以 `ImplementationDecl` 应保留为 compiler IR，但从普通用户的 facade
中隐藏。

### 3.5 两张正交的依赖图

统一 EffSys 注册控制/状态依赖：

```text
network.ready -> crawler.fetch-page
```

AST Implementation 注册业务数据依赖：

```text
crawler.seed-url -> FetchArgs.url -> crawler.fetch-page
```

形式化表示：

```text
H      = 统一 EffSys 中的所有 Handle
I      = 从 AST Run 叶子收集的 Implementation
Einput = EffSys 中的 input 边
Euse   = Implementation RExpr 中的 R reference 边
Ebind  = Handle 到 Implementation 的调用绑定边
B      = AST demand roots

G = demandClosure(H union I, Einput union Euse union Ebind, B)
```

这与当前 DemandGraph 的基本形状一致，只是 `H` 不再来自多个
`EffectSystemDecl` 的拼接。

## 4. 是否比当前语义更强

结论：

> 新语义在计算表达能力上与当前语义基本等价；在组合能力、规范化能力、
> facade 清晰度和全局静态分析方面更强；在 Effect System 自身的封装和独立
> 部署维度上更弱，除非把这些职责明确移动到 AST module 或 SDK export policy。

### 4.1 更强的部分

#### 一个 canonical normal form

当前同一张逻辑 input 图可以被切成不同的 Effect Systems、imports 和 exports，
存在多种等价声明。统一 EffSys 后只有一个规范化表示，更适合：

- self-bootstrap fixed point 比较；
- schema digest；
- SDK artifact 生成；
- whole-program validation；
- 缓存、diff 和 reproducibility。

这属于“减少无意义表示自由度”，不是减少业务表达能力。

#### 全局 input 图分析

所有 input 边天然位于同一张图，可以直接进行：

- 全局循环检测；
- 全局 demand closure；
- unreachable Handle 检测；
- input fan-in/fan-out 分析；
- 统一诊断和可视化；
- 全局 schema/reference 完整性验证。

不再需要先解释 imports/exports 才能知道一条 input 边是否合法。

#### AST 组合更自然

AST subtree 可以自由组合，而不需要同步构造：

```text
EffectSystem import
EffectSystem export
EffectSystem private
```

模块是 AST authoring/composition 的概念；Effect 语义不再与源代码目录或业务
模块边界混合。

#### facade 更小

从：

```haskell
r @"seed-url" crawlerSystem seedSpec
e @"fetch-page" crawlerSystem fetchSpec
```

收敛为：

```haskell
r @"crawler.seed-url" seedSpec
e @"crawler.fetch-page" fetchSpec
```

或者在模块 scope 中：

```haskell
module_ @"crawler" $
  Run
    (e @"fetch-page")
    (record { url = r @"seed-url" })
```

用户只表达真正有业务意义的信息。

#### 更少的非法状态

以下错误类型会从核心模型消失：

- `DuplicateEffectSystem`
- `UnknownEffectSystemImport`
- `DuplicateEffectSystemImport`
- `HandleDeclaredInWrongSystem`
- `HandleInputSystemNotImported`
- `HandleInputNotExported`
- system 级 private/export 重叠

它们不再需要 runtime 或 compiler 证明，因为对应状态已经无法构造。

### 4.2 表达能力基本相同的部分

任何当前多系统声明，只要其 imports/exports 合法，都可以通过限定 HandleId
无损 flatten：

```text
old: EffectSystem "crawler", local "fetch-page"
new: HandleId "crawler.fetch-page"
```

input、R source、observation、schema 和 Handler binding 都可保持不变。因此普通
workflow 的计算表达能力没有增加，也没有丢失。

`Chain`、`Parallel`、`Fallback`、`Race`、R lazy demand、single-flight 和
Handler runtime 都不因该决定获得新的计算能力。

### 4.3 更弱或需要迁移的部分

统一 EffSys 删除了 Effect System 级别的：

- imports；
- private；
- exports；
- 独立 system validation；
- 独立 system artifact 的潜在发布边界。

如果这些能力仍然是公司 SDK 的要求，应该移动到独立的非运行时策略：

```haskell
data ModulePolicy = ModulePolicy
  { moduleName :: ModuleName
  , moduleMembers :: [HandleId]
  , moduleExports :: [HandleId]
  }
```

它可以控制 SDK 对外表面和源码组织，但不得改变 EffSys input/demand 语义。

private observation 的安全性仍由以下核心规则保证：

```text
C/U/D/E observation 不是公共 RExpr value；
必须先经声明的 R 暴露，才能成为业务参数。
```

因此删除 system private 并不意味着 command observation 自动公开。

### 4.4 变化规模判断

| 层 | 变化规模 | 原因 |
|---|---:|---|
| 用户 facade | 大 | 删除 system 参数，隐藏 Implementation 构造 |
| Handle identity/schema | 大且 breaking | `HandleId` serialized shape 改变 |
| Effect validation | 大 | imports/private/exports 规则被移除或迁移 |
| AST internal control | 小 | `Fix AstF`、cata、控制节点可保留 |
| Implementation/RExpr IR | 小到中 | IR 可保留，增加 `Run target args` facade |
| DemandGraph | 小 | 从单一 EffSys 建 index，边类型不变 |
| Runtime demand/handler | 小 | 仍按 HandleId、input、RExpr demand |
| SDK/self-bootstrap artifact | 大 | canonical surface 和 digest 必须版本化 |

总体不是运行时重写，而是一次 **breaking facade + identity/schema migration**。

## 5. 一个必须冻结的限制

当前：

```haskell
newtype ImplementationId =
  ImplementationId HandleId
```

这意味着一个 CUDE target 在一个 Core 中只能对应一份 canonical 参数绑定。
同一个 target 在不同 AST 位置绑定不同 `RExpr` 会触发
`ConflictingImplementation`。

本提案第一版保持该约束：

```text
同一 HandleId 的所有 AST Run 出现必须 lower 成同一个 ImplementationDecl。
```

如果未来要允许：

```haskell
Run (e @"crawler.fetch-page") seedUrl
Run (e @"crawler.fetch-page") nextUrl
```

成为两次具有不同参数和状态的独立调用，则必须另外引入稳定的
`InvocationId`/`ActionId`，并把 RuntimeState 从单纯按 HandleId 记状态升级为
按调用实例记状态。这是另一个语义扩展，不应偷偷混入本次统一 EffSys 修改。

## 6. 已实现 API

### 6.1 Typed authoring

```haskell
data CrawlerEffects = CrawlerEffects
  { seedUrl :: Handle "crawler.seed-url" 'R () Url
  , fetchPage :: Handle "crawler.fetch-page" 'E FetchArgs PageObservation
  , fetchedPage :: Handle "crawler.fetched-page" 'R () Page
  , persistPage :: Handle "storage.persist-page" 'E PersistArgs NoObservation
  }

crawlerEffects :: CrawlerEffects
crawlerEffects =
  CrawlerEffects
    { seedUrl =
        r @"crawler.seed-url" seedReadSpec
    , fetchPage =
        e @"crawler.fetch-page" fetchCommandSpec
    , fetchedPage =
        r @"crawler.fetched-page"
          fetchedPageReadSpec
    , persistPage =
        e @"storage.persist-page" persistCommandSpec
    }

effSys :: Either [RecordError] EffSysDecl
effSys =
  effSysFromRecord crawlerEffects
```

记录可以继续按源代码模块分开，最终只 flatten 成一个 `EffSysDecl`。

### 6.2 AST authoring

```haskell
crawlerAst =
  SeedChain
    [ run
        (fetchPage crawlerEffects)
        ( productRecord fetchArgsSchema
            [ FieldExpr
                (FieldName "url")
                (rRef (seedUrl crawlerEffects))
            ]
        )
    , run
        (persistPage crawlerEffects)
        ( productRecord persistArgsSchema
            [ FieldExpr
                (FieldName "page")
                (rRef (fetchedPage crawlerEffects))
            ]
        )
    ]
```

这里展示的是已实现 facade。`AstF` 内部仍使用
`Leaf (ImplementationTarget decl)`。

### 6.3 Handler

Handler API 原则上不改变：

```haskell
handlers =
  registerR seedUrl loadSeedUrl
    >=> registerE fetchPage fetchPageHandler
    >=> registerE persistPage persistPageHandler
```

Handler Registry 通过新的全局 `HandleId` 绑定。Handler 函数仍然不会进入
serialized frontend。

## 7. 已实施源码修改地图

### `MyFramework.CURDE.Types`

- `EffectSystemName` 从 Handle identity 和构造器参数中移除；
- `HandleId` 改为全局限定名；
- `EffectSystem`/`EffectSystemDecl` 替换为单一 `EffSys`/`EffSysDecl`；
- 保留 Handle 的 kind/schema/input/source/observation contract；
- `r/c/u/d/e` 删除 system 参数。

### `MyFramework.CURDE.Record`

- `effectSystemFromRecord` 改为 `effSysFromRecord`，多模块片段使用 `mergeEffSysDecls` 合并；
- 删除 `RecordHandleSystemMismatch`；
- 多个业务模块 record 合并时执行全局 HandleId 去重；
- record selector 与 type-level Symbol 的一致性检查可以保留。

### `MyFramework.CURDE.Validate`

- `validateEffectSystems` 改为 `validateEffSys`；
- 删除 system import/private/export 相关错误；
- 保留并全局执行 duplicate Handle、unknown input、input cycle、R source、
  observation、schema 和 Implementation 验证；
- `PrivateObservationCrossSystem` 改写为与 system 无关的 observation
  visibility 规则。

### `MyFramework.CURDE.Core`

```haskell
data CURDECore = CURDECore
  { curdeCoreEffSys :: EffSysDecl
  , curdeCoreImplementations :: [ImplementationDecl]
  , curdeCoreAst :: AstBlueprint
  , curdeCoreDemandGraph :: DemandGraph
  }
```

DemandNode、DemandEdgeKind 和 demand closure 可以保留。

### `MyFramework.CURDE.Lowering`

```haskell
lowerCURDE
  :: EffSys
  -> AstBlueprintSeed
  -> LoweringResult
```

handle index 直接从单一 EffSys 构造。AST cata 收集 Implementation 的逻辑
不变。

增加 facade adapter：

```haskell
run
  :: Handle name kind args observation
  -> RExpr args
  -> AstSeed
```

它直接生成 `SeedLeaf (ImplementationTarget ...)`，不增加新的 runtime AST
节点。

### `MyFramework.Ast`

第一阶段不需要修改 `AstF`。`Run` 可以是 facade smart constructor。

若需要 `module_ @"crawler"`，应把它实现为进入 serialized canonical AST 前的
名称 elaboration，不应成为新的 runtime action。

### Runtime 和 Handler

- 把所有旧 `HandleId` 字段访问改为新的 qualified identity；
- Demand 顺序、R single-flight、ExecutionPermit、HandlerInput 和
  RuntimeState channel 不改变；
- 保留 Implementation 和 Handle 状态分离。

### SDK、自举和 TrustBase

- 旧的多 Effect System canonical surface 从列表改为单一 EffSys；
- source artifact schema 必须升版本；
- digest、manifest、SdkCoreLock 和固定点 witness 期望值必须重新生成；
- `dsl-sdk` 仍然只能由 lowering 生成，不直接手改；
- 普通实现和 focused witness 完成后，promotion 仍需走独立 heavy gate。

## 8. 兼容迁移

当前实现采用显式 breaking V2：公共 facade 和 SDK source artifact 不自动接受
V1 多 system 声明，也没有把兼容 adapter 放进运行时。若需要迁移历史业务配置，
应提供一个独立的离线 V1 到 V2 adapter：

```haskell
flattenEffectSystems
  :: [EffectSystemDeclV1]
  -> Either [MigrationError] EffSysDeclV2
```

迁移规则：

1. 把 `(EffectSystemName, localName)` 编码为稳定的 qualified HandleId；
2. 重写所有 input、private observation source、RExpr 和 AST HandleRef；
3. 验证原 imports/exports；
4. 验证通过后删除 imports/private/exports 声明；
5. 对 flatten 后的全局 input 图重新做 cycle/reference validation；
6. 比较 V1/V2 demand closure 和 runtime trace。

旧 identity 必须使用无歧义的 segment encoding，不能简单用未经转义的
`system ++ "." ++ local`，否则名字自身包含点时会发生碰撞。

## 9. 验证与 witness

完整迁移/发布阶段应覆盖以下 evidence 目标：

1. 两个旧 systems flatten 后的 input closure 与旧语义一致；
2. 全局重复 HandleId 被拒绝；
3. 跨旧 system 的合法 input 在 V2 不再需要 import/export；
4. 全局 input cycle 被拒绝；
5. `Run target args` 与手工 `ImplementationDecl` lower 结果相同；
6. RExpr schema mismatch 仍然被拒绝；
7. C/U/D/E observation 仍然不能直接进入 RExpr；
8. 同一 target 的不同 RExpr 仍触发 `ConflictingImplementation`；
9. Runtime handler invocation trace 与 V1 等价；
10. V2 serialized surface round-trip 稳定；
11. Stage1/Stage2 source artifact 在新 schema 下可重现；
12. 旧 SDK artifact 因 schema version 不同而明确失败，而不是被误接受。

本次普通架构迭代已通过：

```powershell
stack --work-dir .stack-work-codex build
stack --work-dir .stack-work-codex exec curde-semantics-witness
stack --work-dir .stack-work-codex exec curde-runtime-witness
.\scripts\check-ast-execution-boundary.ps1
stack --work-dir .stack-work-codex exec sdk-package-witness
stack --work-dir .stack-work-codex exec core-self-interpret-witness
```

其中 semantic evidence 已升级到 `curde-semantics-evidence.v2`，显式建立
`curde-unified-effsys` 和 `curde-ast-inline-run` 两项声明；SDK source artifact /
report 与 lowering-semantics digest 也升级到 V2。完整 V1 adapter 对比、重型
Stage1/Stage2 self-artifact reproduction 和 core promotion 仍属于后续迁移/发布
工作，本次普通迭代没有运行，也没有修改 current core pointer。

普通架构迭代只运行相关 build、semantic witness、runtime witness 和 boundary
script。该修改本身不自动批准或替换当前 promoted core。

## 10. 接受标准

本提案完成时应满足：

- public `r/c/u/d/e` 不再要求 `EffectSystemName`；
- Core 中只有一个 EffSys 声明；
- 所有 input 边可从单一 EffSys 得到；
- AST 直接 author `Run(CUDE, RExpr)`；
- Handler 实现仍然完全位于 serialized frontend 外；
- input channel 仍然只传 identity/status/validity；
- RExpr 仍然是唯一的业务参数依赖通道；
- 当前 `Fix AstF`、cata、DemandGraph 和 runtime permit 边界得到保留；
- 模块化不重新变成第二套 Effect System；
- schema/SDK migration 是显式版本升级；
- 未运行 promotion gate 时不会改变 current core pointer。

## 11. 最终评价

统一 EffSys 的主要增强不是“可以执行以前不能执行的程序”，而是：

```text
更少的概念轴
+ 一个全局规范形
+ 更直接的 AST authoring
+ 更强的 whole-program validation
+ 更稳定的自举与 SDK lowering 输入
```

它把原来混在 `EffectSystem` 中的“effect dependency”和“业务模块封装”拆开：

```text
effect dependency -> Unified EffSys
module composition -> AST authoring
data dependency   -> AST RExpr
implementation    -> Handler Registry
```

这是更强的架构分层和更小的 EDSL，而不是更强的底层计算模型。代价是一次明确的
identity/schema breaking change，以及把 imports/private/exports 的产品需求
重新安置到 AST module metadata 或 SDK export policy。
