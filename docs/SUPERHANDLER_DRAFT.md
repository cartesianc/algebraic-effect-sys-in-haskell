# 临时方案 · Root 的 superhandler 装配

**状态：待审查。** `super` 是 Root 提供的 superhandler。middleware 通过 `hookedEnter` 读取这次进入的 handler 名，两者对应同一次调用。本稿讨论如何把这套已有机制的静态装配收进 gen。现行协议见[主设计](CORE_DESIGN.md#middleware)，阶段入口见 [NEXT_STAGES](NEXT_STAGES.md#superhandler)。

## 代码长什么样

FileDemo 当前的 AST 是 `ast = operateFile`。下面第一段演示给它挂上日志，假设 `TraceFile` 已注册为拦截 `ScopedKind` 的 Middleware。后两段节选自当前 FileDemo 的手写和生成文件。[现有 AST](../demo/FileDemo/AST.hs) · [手写 handler](../demo/FileDemo/Handlers.hs) · [生成入口](../demo/FileDemo/Generated/Handlers.hs)

```haskell
-- AST.hs：给整个文件操作分支挂上日志
ast = middleware [node "TraceFile"] operateFile

-- Handlers.hs：业务作者写的仍是原方法
instance OpenSessionLayer m => OpenSessionHandler m where
  openSession = pure []

-- Generated/Handlers.hs：现有 openFileSession 入口内部的执行顺序
getOpenedFile >>
  runAt @"FileSession"
    (FrameworkRuntime.super "openSession" FrameworkGenerated.openSession)
```

`getOpenedFile` 先完成已声明的 request。随后 Root 收到 handler 名和待执行的 action。挂上示例日志后，gen 会把该挂载的 hooks 类型标签传给生成入口。进入时，日志方法可从 `hookedEnter` 读到 `Just "openSession"`；本次调用实际交出输出时，可从 `hookedOutput` 读到原输出。业务与 middleware 都由 SDK 推进。[当前生成逻辑](../sdk/Framework/Gen/Emit/Handlers.hs) · [Root 协议](../sdk/Framework/Runtime/Protocol.hs)

## 第一批要收拢什么

现在 Booter 已经算出每个挂载覆盖哪些 middleware，Injector 也知道绑定的捕获类别。生成的 `capturedAt kind event` 仍用 ``kind `elem` kinds`` 检查每个 middleware 的 `intercept`。这些信息在 gen 时已经齐全。[挂载查询](../sdk/Framework/Gen/Plan.hs) · [绑定装配](../sdk/Framework/Gen/Injector.hs)

建议在 `Gen.Injector` 下新增内部模块 `Framework.Gen.Injector.Super`，由现有组合流水线调用，分工如下。

1. **Booter** 提供挂载的 middleware 列表。同一 handler 绑定到两处时，各自沿用本次挂载的列表。
2. **Injector.Super** 按列表原有的注册顺序，为每个捕获点选出匹配的 middleware。进入、成功返回和显式 `raise` 取当前绑定的类别；`raw` 取被读原子调用的类别。例如 Context parser 从 Excu 读 `raw` 时，拦截 Excu 的日志仍应收到这次读取。前驱也按自己的类别选取。
3. **Emit.Handlers** 把选定结果生成为 Root 调用。空集合直接执行 action，有匹配时连接相应的日志方法；同一组结果可以共用生成代码。运行时负责执行闭包、交付真实输出和传播故障。

**怎么看出简化生效。** 让同一个 `openSession` 在两处挂载，一处覆盖日志、一处为空。从生成代码应能直接读出哪次调用日志，且热路径无需再用 `elem` 筛选注册类别。两次业务 IO 的次数、前驱失败时的行为、`raw` 回放和已预约的自动 close 均沿用现行协议。

## 哪些判断仍属于运行时

gen 能确定 `FileSession` 的开启和关闭方法。实际复用哪个实例要结合本次参数的 Binding 与生产身份；是否可以关闭还要看当前使用者和执行帧。取消到达自动 close 的哪个时刻也只有运行时知道。把这些动态事实保留在 scope 和执行协议中，`super` 只接管本次原子 action。[scope 回收](CORE_DESIGN.md#scope-gc)

第一批已有类型标签、实例字典和闭包足以表达，手写注册、handler 与 AST 沿用现行写法。只有出现“静态方法角色决定不同载荷类型”的实际契约时，再评估 associated type family；各角色确实需要独立数据表示时，再评估 associated data family。

## 后续可单独评估

普通 Context 的 parser 挂接表已由 gen 生成，`atomicScope` 在成功交付时仍按方法名取表。可以另行评估把已知 parser 闭包直接装到输出交付位置。验证时要区分三种情况：原子调用成功需要发布、parser 正在主动拉取来源、以及用同次输出回答 `raw` 回放。持续发布另受本次执行位置约束。这项探索独立于第一批的 middleware 筛选。[输出交付实现](../sdk/Framework/Runtime/Context.hs)

审查完成后，把采纳范围和进度归入 [NEXT_STAGES](NEXT_STAGES.md#superhandler)，正式协议变更归入[主设计](CORE_DESIGN.md#calls)，再删除本稿。
