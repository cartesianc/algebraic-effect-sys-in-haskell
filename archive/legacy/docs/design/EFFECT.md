# Effect：注册与操作 IR

本页对应 [C5 可执行示例](effect-sample/README.md)。Effect instance 集中声明分类、依赖、公开方法、数据接口及 impl，库据此生成注册并连接执行闭包。已发布代码保留早期试验实现。

## 注册内容

| 内容 | 当前表达 | 用途 |
|---|---|---|
| 身份 | LoadText 等具体类型 | 关联注册、请求、结果和类方法 |
| 分类 | Typing e | 默认 Excu；库生成分类标记及注册结构 |
| 上游 | Input e | 唯一的句柄依赖来源，默认根节点 () |
| 公开句柄 | Exports e | 本层提供的方法，自身和下游均可按名称使用，默认空 |
| 请求 | Require e | 调用者构造、impl 拆解的 ADT |
| 操作资源 | Handle e | 本次执行形成的资源或操作状态 |
| 业务值 | Value e | Result 可封装的业务数据 |
| 失败 | Failure e | 本 effect 可产生的失败 |
| 使用句柄 | invoke @"名称" context | 库从当前层及 Input 链推导提供者与资源 |
| 请求适配 | impl 方法方程 | 归属于当前 instance，库将它绑定到内部注册 |
| 生命周期 | scope = Scope { close, onError } | Scope 的关闭与错误报告声明 |

Effect instance 汇合这些定义。单字段关联数据可以使用 newtype，多分支请求使用 data，空 data 表达无构造器的接口。Source 从环境取得完成结果，可省略 impl；其他分类填写 impl，Scope 额外填写 scope。统一 Registered e 以 newtype 包装自动生成的注册 GADT，调用函数按请求与上下文取得注册。

## input 的正式语义

Input e 选择上游 effect。Effect e 的 superclass 自动带入上游 Effect 字典和 Exports 中的 Handler 字典，再沿祖先递归展开。根节点使用 Input e = () 终止。

```text
Effect ReportRead
  → Effect LoadText
  → Effect FileSession + Handler "openFile" FileSession + Handler "readChars" FileSession
  → Effect Start       + Handler "writeReport" Start
```

每个 effect 声明直接上游和自己的公开句柄。库根据 Input 取得上游注册；lowering 为每次成功执行建立 Ready，并接入实际使用的上游 Ready。invoke 自动完成提供者选择与祖先资源投影。相同名称由当前层或最近上游解释。

约束传播提供方法实现，Ready 提供本次资源，Require 提供业务参数。完整定义见 [CONSTRUCTION.md](CONSTRUCTION.md)。业务值来源由调用参数表达式表达；多来源 scope 需求保留在 layer 的后续设计中。

## handler 与 impl

Handler instance 的 operation 类方法提供实际操作。一份 Signature 描述业务参数和原始返回类型，库按分类生成最终方法类型。库自动实现 Invoke 的 invoke 类方法，按名称和 Context e 连接实际操作。Effect instance 的 impl 类方法解释请求；库在内部注册的 bind 字段中保存这个方法。

LoadText 使用 FileSession 的 readChars，ReportRead 使用 Start 的 writeReport。impl 对 Require 模式匹配，在等号右侧调用 invoke，并封装 Result。一次 impl 可以使用当前约束链中的多个方法。详见 [IMPL.md](IMPL.md)。

## 通用 Result

[Result.hs](effect-sample/Result.hs) 定义独立的 Result failure handle value。Effect 层适配为：

```haskell
type Result e = R.Result FailureInfo (Handle e) (Value e)
```

- succeeded handle：成功，业务值为空。
- produced handle value：成功，封装业务值。
- pending：本次尚未完成。
- failed failure：本次失败。

两种成功均显示 Succ，同一种 effect 可以产生任意一种。readValue 显式读取 Maybe value，状态观察保持业务值封装。

FailureInfo 保留原始错误类型和值供异构链传播。resultStatus 生成文本视图，failureAs 恢复匹配的错误类型。Pending 当前作为不可变快照传播；等待、恢复、重试及 Read/Map 的最终语义保持为独立决策。

## 分类与方向

当前 sample 用 GADT 表达 Source、Scope、Excu、Read、Map、Close、X。Scope 填写生命周期声明，Close/X 的 Input 关联 Scope。Read/Map 的纯适配用于当前文件报告示例，通用 Result 支持后续策略调整。

once 的方向是静态线性释放责任，layer 的方向是额外 scope 能力需求。AST 声明模块父子、顺序与分支，Hanging 承载事件入口。middleware 在 AST 和执行闭包外围提供监听、mock、stress、log/show。

注册 IR 服务代码阅读和模块观察。配置启动需要将外部声明装配为已编译的具名能力；异构存在封装、配置格式及加载协议继续设计。
