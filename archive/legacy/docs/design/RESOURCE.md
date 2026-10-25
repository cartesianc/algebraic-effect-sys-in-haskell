# 资源、作用域与错误范围

本文件定义 [EFFECT.md](EFFECT.md) 中 layer、scope、once、help 的共同语义。impl 通过 [handler 类方法](IMPL.md)取得资源能力，[INTERPRETER.md](INTERPRETER.md) 管理生命周期，[HANGING.md](HANGING.md) 遵守有效期。

## 1. 三个资源字段

| 字段 | 回答的问题 |
|---|---|
| layer | 当前操作需要哪个 scope 提供什么能力？ |
| scope | 当前资源拥有者用哪个 Close effect 结束作用域？ |
| once | 哪个操作或资源责任必须遵守线性使用协议？ |

layer 关联实际 effect 引用，基线形式为 need fileSession，表达当前 effect 对 scope 能力的要求。多个 scope 要求的组合 ADT 属于后续接口设计。

资源获取所需的文件路径等业务值由 require/Read/Map 提供，句柄在本次调用环境中使用这些值。

## 2. 开关归同一个资源拥有者

以下按当前 C5 列出资源与操作关系；layer、once 列保留后续设计方向：

| 注册 | Typing | Input | 使用的具名句柄 | 请求适配 | scope | layer 方向 | once 方向 |
|---|---|---|---|---|---|---|---|
| FileSession | Scope | Start | openFile | impl 匹配 OpenPath | CloseFile、ReportFileError | 无 | 取得关闭责任 |
| LoadText | Excu | FileSession | readChars | impl 匹配读取请求 | 无 | 使用 FileSession | 借用资源 |
| CloseFile | Close | FileSession | closeFile | impl 匹配 CloseNow | 无 | FileSession 的清理能力 | 消耗关闭责任 |

具体 effect 的 Handler instance 提供这些方法的 operation 解释，Exports 声明本层提供的方法集合。impl 通过 invoke 和当前 Context 按名称调用；库沿 Input 约束链选择提供者，再接入所需的本次资源。

FileSession 拥有文件资源并公开读取能力；CloseFile 的操作使用同一个拥有者的资源。写入操作也应沿用这个资源关系，读写先后由 AST 决定。多来源 layer 与线性责任属于后续接口。

closeFile 的 input 始终指向 fileSession。scope → closeFile 表达退出时的清理关联，清理使用已持有的资源。

## 3. once 是线性责任

once 的布尔字段声明线性要求，资源插件和运行器通过线性接口保存、转移和消耗责任。运行时去重另按执行身份管理调用共享。

成功获取资源后产生唯一的所有权或关闭凭证；关闭消耗该凭证。打开与关闭方法保持既定类型，调用过程创建并移交相应凭证。

实现遵循以下规则：

- 线性拥有者由专用接口管理，Free 描述、共享调用元数据和普通存在包保存受控引用。
- 转移、借用和消耗经过受控接口，使用权受 scope 限制。
- scope 退出先等待或取消使用者，使监听失效，再执行关闭。
- 正常结束、失败和取消均由运行时调度清理协议，线性接口约束责任的使用。
- 关闭后旧使用权失效，关闭失败进入明确的记录与处理路径。

类型机制参考 [GHC LinearTypes](https://ghc.gitlab.haskell.org/ghc/doc/users_guide/exts/linear_types.html)。异常清理协议参见 [Linear types and exceptions](https://www.tweag.io/blog/2020-02-19-linear-type-exception/)。

## 4. X 按 scope 处理错误

X 注册通过 help 指定处理范围：

```haskell
help = scopeOf fileSession
```

错误处理句柄由 X 分类 effect 的 Handler instance 提供，Effect instance 内的 impl 适配错误请求并调用它。C5 中 ReportFileError 的 impl 调用具名句柄 reportFileError，库自动恢复它需要的 Start 资源。

错误事件携带来源注册、执行身份、scope 身份和错误值。后端按这些身份匹配处理范围，并将相应错误交给句柄。

X 可以消费失败上游的错误，Close 在 scope 清理阶段执行；解释器按各分类的启动条件调度。

记录错误、恢复业务、转换失败和重试各有明确结果。嵌套 scope 的处理优先级、未处理错误传播、重试语义，以及针对单个 effect 的 help 扩展属于后续协议设计。
