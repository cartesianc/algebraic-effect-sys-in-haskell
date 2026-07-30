# L0 引用式 AST 与模块 Effect 语义宪章

## 0. 文档地位

```text
状态：FROZEN
层级：L0 / 最高语义层级
版本：v2
冻结日期：2026-07-31
```

本文档定义 `myframework` 的最高层前台语义。源码、内部 IR、SDK、
witness、其他架构文档和示例若与本文冲突，均视为实现债务，以本文为准。

本文冻结的是目标语义，不代表当前工作区已经完成对应实现，也不构成
core promotion。修改本文必须显式提出新的 L0 版本，不能通过修改 lowering、
runtime 或示例暗中改变。

优先级为：

```text
L0 本文
  > 版本化 schema / witness contract
  > 其他架构与设计文档
  > 当前源码和内部 IR
  > 示例与迁移兼容层
```

## 1. 冻结结论

框架的公开 AST 不是一张预先完全展开的 `Blueprint`，而是一组独立注册、
可寻址、可按需解析的模块控制节点。

最高层前台形态为：

```haskell
chain app
  [ a
  , b
  , foo
  , foo2
  ]

parallel a
  [ a1
  , a2
  , a3
  ]

fallback a1
  [ b1
  , b2
  ]
```

含义是：

```text
app : chain
├─ a : parallel
│  ├─ a1 : fallback
│  │  ├─ b1 : effect
│  │  └─ b2 : effect
│  ├─ a2 : effect
│  └─ a3 : effect
├─ b    : effect
├─ foo  : effect
└─ foo2 : effect
```

`app`、`a`、`a1` 既是控制节点名称，也是模块名称。它们不是内联子树，
而是对独立声明的引用。

### 1.1 实际 SDK façade

`import MyFramework` 是业务 authoring 的唯一正常入口。公开 authoring
层只存在一个 `Name` 域；同一个名称进入控制声明的模块位或子引用位，
由 resolver 再决定它是模块引用还是当前模块的 effect 引用。

因此实际代码不得要求业务用户写：

```haskell
m "crawler"
k "fetch"
ModuleName "crawler"
LocalKey "fetch"
```

实际代码先把 Haskell 变量绑定到名称：

```haskell
crawler, fetch, extract, persist :: Name
crawler = name "crawler"
fetch = name "fetch"
extract = name "extract"
persist = name "persist"
```

之后控制语义必须保持目标形态：

```haskell
chain crawler [fetch, extract, persist]
```

Haskell 的 `type` 是保留字，因此 effect record 在 Haskell façade 中使用
`crude` 字段承载 L0 的 `type = C/U/D/E` 语义：

```haskell
primary .= Effect
  { crude = E
  , input = none
  , params =
      [ url .= fromR seedUrl
      ]
  }
```

这不是额外的 effect ID：`primary` 仍是 record key，也是完整的模块内
effect ID。canonical schema/JSON 可以将 `crude` 编码为 `"type"`。

## 2. 引用式交互是一级语义

UI 初始只需要读取：

```haskell
chain app [a, b, foo, foo2]
```

用户左键点击 `a` 时，resolver 才读取：

```haskell
parallel a [a1, a2, a3]
```

继续点击 `a1` 时，resolver 才读取：

```haskell
fallback a1 [b1, b2]
```

因此，“逐层点击、逐层展开、逐层诊断”不是可选渲染技巧，而是 L0
语义要求。SDK、布局模型、运行时路径和诊断路径必须保留引用边界，不能要求
前台先提交一张完整嵌套树。

## 3. 控制节点就是模块边界

每个控制声明具有：

```text
控制种类 + 模块名 + 本地子引用列表
```

例如：

```haskell
chain app [...]
parallel a [...]
fallback a1 [...]
```

`chain`、`parallel`、`fallback`、`race` 等控制关键词负责定义模块的控制
代数。关键词后的参数是模块名，不是 effect system 名称的字符串前缀。

子引用只写 key：

```haskell
[a, b, foo, foo2]
```

不得在前台写成：

```haskell
["app.a", "app.b", "app.foo", "app.foo2"]
```

## 4. Effect 按模块分别注册

不存在一个把所有模块 flatten 后统一注册的 EffSys。每个模块拥有自己的
C/U/D/E effect record 和自己的 input 链。

示例：

```haskell
effects app
  { b =
      { type = E
      , input = none
      , params = {}
      }

  , foo =
      { type = C
      , input = b
      , params =
          { value = sourceFoo :: Foo
          }
      }

  , foo2 =
      { type = E
      , input = foo
      , params =
          { value = sourceFoo :: Foo
          }
      }
  }
```

```haskell
effects a
  { a2 =
      { type = E
      , input = none
      , params = {}
      }

  , a3 =
      { type = E
      , input = a2
      , params = {}
      }
  }
```

```haskell
effects a1
  { b1 =
      { type = E
      , input = none
      , params =
          { value = sourceValue :: Value
          }
      }

  , b2 =
      { type = E
      , input = b1
      , params =
          { value = sourceValue :: Value
          }
      }
  }
```

record key 已经是模块内 effect ID：

```haskell
foo = { ... }
```

因此严禁重复书写：

```haskell
foo =
  { id = "foo"
  , ...
  }
```

也严禁把模块名拼进 effect ID：

```haskell
id = "app.foo"
id = "crawler.fetch-page"
```

同名 effect 可以存在于不同模块。需要唯一解析时，resolver 产生结构化引用：

```haskell
ResolvedEffect
  { module = app
  , key = foo
  }
```

这个结构化结果由 AST scope 和本地 key 推导，用户不重复书写。

## 5. Effect record 是代码即文档

模块内每个 effect record 至少表达：

```text
type    C / U / D / E 中的哪一种
input   同模块 CUDE 启动链中的直接前驱
params  handler 所需参数契约及其 R 数据绑定
```

`params` 同时回答：

```text
这个 effect 需要哪些字段？
每个字段是什么类型？
本次叶子实现从哪个 R 获得数据？
```

因此 AST 控制列表不再内联：

```haskell
run fetchPage $
  record
    { url = ref seedUrl
    }
```

effect 叶子的完整定义已经位于所属模块的 effect record 中。控制 AST 只引用
其 key。

后台 handler 实现仍然独立，不进入可序列化前台；框架只校验 handler 的输入
契约与 effect record 一致，不规定 handler 的内部代码结构。

## 6. R 与 CUDE 链分离

R 是独立的、typed、lazy 数据域，不属于 C/U/D/E effect input 链。

示例：

```haskell
reads
  { sourceFoo   :: R Foo
  , sourceValue :: R Value
  }
```

冻结约束：

- R 不作为 `chain`、`parallel`、`fallback` 等控制节点启动的 action。
- R 不出现在 CUDE `input` 边中。
- Effect 的 `params` 可以引用 R。
- 执行 effect 前，runtime 按需解析其参数所引用的 R。
- R 的后台获取方式属于独立 read handler，不改变 CUDE 控制结构。

执行顺序为：

```text
resolver 定位模块 effect
  -> 按需求值 params 中的 R
  -> 组装 handler 参数 record
  -> 沿模块内 CUDE input 链自底向上启动
  -> 执行当前 effect
```

## 7. 子引用解析规则

对于：

```haskell
chain app [a, b, foo, foo2]
```

resolver 在 `app` scope 中逐项解析：

1. 若 key 对应一个独立控制模块，例如 `a`，则产生 `ModuleRef a`。
2. 否则 key 必须存在于 `effects app`，并产生 `EffectRef key`。
3. 同一 scope 中，一个 key 不得同时是子模块名和本地 effect key。
4. 缺失、歧义和循环引用均为静态错误。

canonical IR 必须区分：

```haskell
data LocalRef
  = ModuleRef ModuleName
  | EffectRef EffectKey
```

前台可以保持简洁 key 列表，lowering 必须在进入 runtime 前完成无歧义解析。

## 8. 规范化存储，而非大 Blueprint

语义上的 canonical source 接近：

```haskell
data AstIndex = AstIndex
  { root :: ModuleRef
  , controls :: Map ModuleName ControlDecl
  , effects :: Map ModuleName EffectRecord
  , reads :: ReadRegistry
  }

data ControlDecl
  = ChainDecl [LocalRef]
  | ParallelDecl [LocalRef]
  | FallbackDecl [LocalRef]
  | RaceDecl [LocalRef]
```

例如：

```haskell
root = app

controls =
  { app = ChainDecl [a, b, foo, foo2]
  , a   = ParallelDecl [a1, a2, a3]
  , a1  = FallbackDecl [b1, b2]
  }
```

物理存储可以使用文件、数据库、JSON-RPC 或 map，但每个声明必须保持独立地址
能力。一个 manifest 可以建立索引，但不能迫使 authoring、UI 或 runtime
使用一张内联 `AstBlueprintSeed`。

## 9. 递归解释与 occurrence

resolver 从 `root` 开始按引用提供递归视图；cata 继续负责控制代数解释。
实现可以按需展开并折叠，也可以在内部融合解析与折叠，但不得把“大 Blueprint”
重新暴露为前台要求。

必须区分：

```text
a                         模块定义身份
app/a/a1/b1               AST occurrence path
```

同一模块定义可以被复用；每次引用产生独立 occurrence path。runtime 状态、
布局光标、失败诊断和调用实例不得只按模块名或 effect key 合并。

## 10. L0 校验约束

至少必须验证：

- root 模块存在；
- 模块名唯一；
- effect key 在所属模块内唯一；
- 同一 scope 中模块引用与 effect key 不冲突；
- 所有子引用可解析；
- 控制模块引用无非法循环；
- effect `type` 只能是 C/U/D/E；
- effect `input` 只能形成所属模块内的合法无环启动链；
- `params` 字段完整、无多余字段且类型一致；
- `params` 引用的 R 存在且类型匹配；
- handler 注册与 effect 参数契约一致；
- occurrence path 在一次解析/执行中稳定。

## 11. 明确废弃的前台形态

以下形态与 L0 冻结语义冲突：

```text
一个全局统一 EffSys
全局限定字符串 HandleId，例如 "crawler.fetch-page"
effect record 内重复的 id 字段
把 R 放进 CUDE input 链
要求用户书写 ReadSpec / CommandSpec
run fetchPage $ record { url = ref seedUrl }
SeedChain [SeedParallel [...]] 形式的一张嵌套 Blueprint
UI 必须先加载整棵 AST 才能显示根节点
用模块名代替 occurrence path 记录 runtime 状态
```

它们可以暂时存在于迁移实现中，但不能继续被描述为目标 façade，也不能作为
core2 promotion 已完成的证据。

## 12. 完成标准

只有同时满足以下条件，才能声称实现符合本文：

1. SDK 能直接书写独立的 `chain app [...]`、`parallel a [...]` 等声明。
2. 每个模块单独注册 effect record。
3. record key 是 effect ID，无重复 `id` 和限定名。
4. R 独立于 CUDE input 链。
5. UI 能按左键逐层解析，而无需完整 Blueprint。
6. runtime 与诊断使用稳定 occurrence path。
7. semantic witness 覆盖引用解析、模块隔离、参数/R 类型校验和循环拒绝。
8. self-model 使用相同 façade 描述自身。
9. promotion gate 另行执行并通过。
