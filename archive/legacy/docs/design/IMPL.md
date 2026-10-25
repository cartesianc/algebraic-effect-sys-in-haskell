# Handler 与 impl：自动选择方法与资源

本页对应 [C5 示例](effect-sample/FileEffects.hs)。类型构造见 [CONSTRUCTION.md](CONSTRUCTION.md)。

## 分工

| 角色 | 工作 |
|---|---|
| Effect instance | 声明类型、上游、数据接口、公开句柄，并实现 impl |
| Handler instance | 用 operation 类方法解释具名操作，填写真实外部 IO |
| 库的 Invoke instance | 按名称选择提供者，投影本次资源，再调用 operation |
| Effect 的 impl 类方法 | 接收 Context，模式匹配 Require，调用 invoke，包装该分类的结果 |

Handle e 是资源数据；handler 指 Handler 的操作类方法及其字典。impl 是请求适配方法，operation 是具名操作方法。资源值与操作实现分别注入。

## 注册中直接定义 impl

```haskell
instance Effect LoadText where
  type Input LoadText = FileSession
  data Require LoadText = LoadFirstCharacter | LoadCharacters Int
  data Handle LoadText = LoadCompleted
  newtype Value LoadText = LoadedText String
  newtype Failure LoadText = ReadFailed IOException deriving Show

  impl context LoadFirstCharacter =
    impl context (LoadCharacters 1)
  impl context (LoadCharacters count) =
    either
      (\failure -> failed (ReadFailed failure))
      (\text -> produced LoadCompleted (LoadedText text))
      <$> invoke @"readChars" context count
```

FileSession 的 Exports 为 '["openFile", "readChars"]。Effect LoadText 自动获得相应 superclass 约束。impl 的归属由 instance 确定，库按 Typing 自动生成分类标记和 Registration，并在内部 bind 字段保存 impl。方法选择由调用表达式中的名称确定。

Source 从环境取得入口结果，可以省略 impl；其默认方法返回单位值，Source 启动分支直接使用环境结果。其他分类必须提供 impl。Scope 还需填写 scope = Scope { close = …, onError = … }。

## 类方法定义操作

```haskell
class Effect owner => Handler name owner where
  type OpInput name owner :: Type
  type OpInput name owner = HandlerInput (Typing owner) owner
  type Signature name owner :: Type
  operation :: OpInput name owner
         -> Operation (Typing owner) (Signature name owner)

type family Operation kind signature where
  Operation kind (argument -> rest) = argument -> Operation kind rest
  Operation kind result = Action kind result
```

Signature 用普通函数类型描述业务参数与原始结果。库保留各个箭头参数，并按 Typing 为最终结果接入 IO 或纯返回。零参数方法直接写结果类型。函数结果需要保留为数据时，用业务 Value 包装它。

OpInput 的默认值由 HandlerInput 推导：Source 使用自己的 Ready，Map 使用上游 Value，其他分类使用上游 Ready。操作已建立的资源时，声明为 Ready owner：

```haskell
instance Handler "readChars" FileSession where
  type OpInput "readChars" FileSession = Ready FileSession
  type Signature "readChars" FileSession = Int -> Either IOException String

  operation upstream count =
    let OpenedFile file trace = handleOf upstream
    in try $ do
      trace "read"
      replicateM count (hGetChar file)
```

一个 provider 可以提供多个具名方法，Exports 声明自身与下游可以按名字使用的操作。上例的异常类型已经由 Signature 确定，try 自动推断为 IOException。

例如关闭句柄写 Signature "closeFile" CloseFile = Either IOException ()，类方法直接写 operation upstream = …；Read 的零参数方法同样直接返回其纯结果。

## impl 适配参数

上例的 impl 方程直接模式匹配 Require LoadText。Context LoadText 包装本次上游输入，并让 invoke 推断当前 effect。实例化后的方法类型在本例展开为：

```haskell
Effect LoadText
  => Context LoadText
  -> Require LoadText
  -> IO (Result LoadText)
```

LoadText 的 Exports 默认为空，因此自身方法约束为空；readChars 的字典来自 Effect LoadText 的 superclass。等号右侧的 invoke 是库统一实现的类方法，它转发到选定 Handler 的 operation。impl 负责参数适配，operation 的 do 负责 IO；这种书写分工由代码规范维持。

ReadFailed、LoadCompleted、LoadedText 的类型已经确定目标 effect，因此结果构造自动推断 e。一次 impl 可以通过多个 invoke 调用多个方法，提供者从当前上下文推导。

## 自动继承与实际资源

Effect ReportRead 沿 Input 推导 Start 的 writeReport 约束。Context 保留本次输入，库自动找到方法与对应祖先资源：

```haskell
invoke @"writeReport" context message
```

查找规则固定为：当前 effect 优先，其后沿 Input 选择最近的提供者。每层使用 Exports 决定哪些名称参与查找。找不到名称时编译报错；找到的方法所需资源也必须能够从本次输入取得。

方法字典提供实现，资源投影连接本次操作对象，Require 提供业务参数。Owner、RouteTo 在类型层确定这条路径，库再通过普通函数与闭包调用 operation。具体原理见 [CONSTRUCTION.md](CONSTRUCTION.md)。

[InheritanceChecks.hs](effect-sample/checks/InheritanceChecks.hs) 使用未知 backend 验证：泛型函数声明 Effect e、分类、公开方法集合和 Input 关系，即可自动取得祖先方法和资源。它还验证当前层覆盖、最近祖先选择，以及一个 impl 调用多个方法。

当前类型决定实例解释，入口注入资源支持同一闭包的不同调用。运行时替换相同类型的全局 instance、静态线性资源以及 Read/Map 最终语义继续独立设计。

## 代码组织

统一写法把契约和参数解释集中在同一个 instance，省去独立函数名与转接绑定；库增加分类恢复与注册组装的实现。较大的适配逻辑可提取普通辅助函数，保留 Impl e 作为函数类型别名，并在 instance 中写 impl = helper。每个具体 instance 提供一份适配实现；跨场景变化通过注入资源、参数化类型或已编译解释表达。
