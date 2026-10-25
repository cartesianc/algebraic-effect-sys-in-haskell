# 简版：有什么功能，怎么用

优先阅读文档理解最新设计。已发布代码保留早期试验实现；[C5 示例](effect-sample/README.md) 是当前可编译的 Effect 层。

## 功能

| 功能 | 用法 |
|---|---|
| 注册操作 | Effect instance 声明分类、上游、关联数据与 impl |
| 组合能力 | 声明一次 Input e 和自己的 Exports，库推导祖先约束 |
| 提供操作 | Handler instance 填写一份 Signature，operation 实现操作 |
| 使用句柄 | invoke @"方法名" context，库选择提供者与本次资源 |
| 实现业务 | 在同一个 instance 写 impl 的模式匹配方程，拆 Require 并调用句柄 |
| 返回状态与值 | succeeded、produced、pending、failed |
| 显式读取 | readValue 取得可选业务值 |
| 启动 | compile 参数表达式，由参数推断注册并得到执行闭包 |
| 管理资源 | Scope instance 填写 scope = Scope { close = closes CloseNow, onError = handles FileFailed } |

## 使用顺序

1. 读 [FileEffects.hs](effect-sample/FileEffects.hs)：契约与 impl、Handler 操作。
2. 读 [Program.hs](effect-sample/Program.hs)：Require 实参、readFrom ReadNow 与 mapped FormatReport 的组合。
3. 运行文件示例：

```powershell
cd D:\haskell\releaseversion\docs\design\effect-sample
runghc Main.hs "D:\path\example.txt" 2
```

文件 ABCD 时输出 read:AB。每步的用途和使用位置都写在源码注释中。

例如 PrepareReport 在自己的 Effect instance 中直接写：

```haskell
impl context FormatReport =
  PreparedReport (invoke @"formatReport" context)
```

分类写在 Typing 中，库自动构造注册并接入 impl。Source 使用环境入口，其他 effect 填写 impl；Scope 额外填写生命周期配置。

## 后续方向

AST 负责模块父子、串行、并行、分支和监听；Hanging 接入事件。middleware 围绕 AST 和闭包提供观察、mock、stress、log/show。统一入口保留 `main = interpreter ast effect` 的目标。当前 sample 实现与验证限于 Effect 层，AST 与 interpreter 继续单独设计。

layer、静态线性 once、Read/Map 最终策略和异构 JSON 配置启动继续评审。通用 Result 与闭包连接为后续选择保留独立接口。

原理见 [CONSTRUCTION.md](CONSTRUCTION.md)，文件关系见 [README.md](README.md)。
