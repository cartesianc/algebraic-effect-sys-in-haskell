# Effect graph 与 scope 初始化结构

业务入口仍为 `main = interpreter ast effects`，手写 handler 仍使用原生 Haskell 的 `instance`、`do`、模式匹配和方法引用。SDK 在 gencode 阶段计算 effect graph 与 ScopeTree，将结果写成可查看的显式 ADT；运行时校验并使用这些生成值。这份结构不替代原业务方法，也不预执行 Context 或资源 IO。

生成前可由 GHC／HLS 检查手写模块是[核心设计约束](DESIGN_METHOD.md#生成前仍是原生-haskell核心约束)。已有契约接口提供类方法与 ADT 类型关系；生成器从合法 Haskell 中提取支持的结构，不要求先把业务源码转换成另一种语法。宿主语言类型正确与静态 effect 结构可提取需要分别满足。

初始化后的 `ScopeTree` 在 App／IO 中同时提供 Error 的祖先候选导航与有限执行自动收尾的保守清理前提。运行层仍按实际 scope 实例及使用登记判断能否关闭；静态图不判断故障归属或某份资源已经无人使用，也不新增 Error 的动态调用 tracing。

## 生成方法身份与纯结构副本

生成器为注册的方法生成 `MethodGen` 枚举身份：方法名首字母大写，再加 `Gen`，例如 `openFileSession` 对应 `OpenFileSessionGen`。结构中的调用边引用该身份，保留其所属 effect 和方法角色；同一个 effect 的 open、close、request、require 等方法分别识别。

`MethodDefinition.methodIdentity` 表示当前方法；`methodEffect` 使用同一 effect 的首个注册入口的 Gen 身份，将该 effect 的方法归为一组，不增加 effect key。例如 `openFileSession` 与 `closeFileSession` 的方法身份不同，但 `methodEffect` 都为 `OpenFileSessionGen`。scope 的静态身份使用其 open 方法身份。

生成器通过 GHC 解析器查看手写方法体中的显式 effect 方法引用，另行生成纯结构副本。副本剥离业务值、模式匹配所得数据、纯计算结果和实际 IO，只保留方法引用及其结构关系。调用顺序、分支和重复调用不能被简单的名称集合代替；静态分支保留可能路径，不执行条件表达式来选择业务分支。Context 生产方法在消费者中的 request／require 模式仍由注册决定，不能仅按方法名判断是否重新生产。

业务执行副本仍只添加既有入口包装，原方法体表达式保持不变。这里不再使用“生成器完全不查看方法体”的限制；新的边界是读取显式引用并生成独立结构，不解释任意业务值语义、不改写业务表达式、不要求用户补写 layer 或另一份调用声明。结构提取也不证明任意 Haskell 函数的行为、动态调用次数或物理资源依赖。

当前 source 结构支持显式 effect 调用、原生 `do`、`if`／`case` 和已识别的标准组合，包括顺序／绑定运算、`when`／`unless`、`either`／`maybe` 及 `catchError`。条件和待匹配的值本身不能隐藏 effect 调用。未知高阶 effect 组合、把 effect 藏入 helper 或局部 alias、含 effect 的循环组合（如 `forM_`／`replicateM_`）以及递归 effect 引用会报告错误，不静默生成空图。没有 effect 引用的原子业务表达式可在 instance 方法体内使用原生 Haskell 语法，结构副本将其擦除；方法内直接以标准组合完成 IO 迭代或数据计算，不受上述 effect 组合限制。[源码资产检查](ASSETS.md) 另行约束普通函数对业务 ADT 的显式使用，泛型或仅处理通用类型的 helper 允许；资产检查与 effect 图提取是两个不同边界。

`catchError body recovery` 使用独立的 `Recover` 结构。scope 分析保留正文的正常路径，并为每条正文路径的任意 scope 前缀接入 recovery 路径；前缀包括空前缀和完整前缀，不假定正文一定全部执行后才进入 recovery。这是保守的静态路径集合，不执行业务来验证成功条件，也不证明某个 scope 已成功获取资源。

## 生成期构图，运行期初始化与执行

生成阶段按以下顺序推进：

1. 加载注册与选定末端，形成 `GraphPlan`；同一次读取和 GHC 解析的 Handlers 快照提供方法纯结构及业务包装副本。
2. `initializeStructure` 枚举各独立入口，方法结构使用 `zygo`：辅助 algebra 汇总 scope 路径，主 algebra 利用子结构的辅助结果与图结果完成 effect graph 汇总。
3. 汇合各条独立 chain 的路径证据，把保守的注册前提补入同一份 `ScopeTree`，校验身份、引用与无环性。
4. 在内存中的候选接口上完成源码资产检查，再将 `generatedEffectGraph` 与 `generatedScopeTree` 的显式 ADT 写入 `Generated.Program`，同时写入独立 `Generated/Assets.hs` 目录。生成失败不发布新的结构。

运行时的 `programStructure` 调用 `initializeGeneratedStructure entries scopeNames generatedEffectGraph generatedScopeTree`。第一次 `cata` 只初始化当前 workflow 的 Node 位置和控制结构；SDK 检查 AST 的入口集合与生成 graph 一致，并校验生成结构的身份、引用、父子关系、层次与无环性。它不重新展开方法、不执行 `zygo`、不推导或修正 scope 父边。结构合法且严格完成后，第二次 `cata` 才装配原业务 action，随后沿既有 handler、Context、scope 和 Error 协议执行。新增或移除末端入口须重新生成。

`Chained` 和 `Parallel` 可以汇总 Node 的结构，但不把不同 Node 的链拼成一条 scope 启动路径。尤其不能从 AST 中“Node A 先执行、Node B 后执行”推导其 scope 存在依赖。方法结构中的路径与 workflow 的节点调度是不同层级。

这里要求完成的是有限纯结构，不是提前强制业务产物或获取资源。生成期的 `zygo` 共享辅助归约与主归约的递归过程，不新增一套业务执行器。

## ScopeTree 的内部构树规则

保留每条静态 scope 路径及其来源；`EffectGraph.graphRootPaths` 记录每个入口及其 scope 路径，`graphScopePaths` 提供汇总路径。路径可以包含不同的 scope 集合；每条路径按 scope 定义首次出现去重，仅用于定义层的导航，不据此推断多实例数量、重复 open 的效果或关闭后重开。

对所有路径中出现的 scope 定义 B，取所有包含 B 的路径，把各自位于 B 之前的 scope 集合求交：

```text
Pred(B) = intersection { before(B, path) | B occurs in path }
A ≺ B  iff  A belongs to Pred(B)
```

这一步只处理路径中出现的顶点，因此不存在空路径族上的全称判断。若 A ≺ B、B ≺ C，则每条含 C 的路径都先含 B，且这条路径又必须更早含 A，所以 A ≺ C。任何 scope 都不在自身之前，因此该观察关系传递且反自反，必然无环。后续补入的注册前提仍需独立校验合并结果，不能据此证明合并后也必然无环。

Pred 与由它得到的 `precedes` 只用于 `buildScopeTree` 的内部计算，随后通过传递约简形成父子边；不另行导出共同前序列表。

这定义的是“在给定静态路径族中，B 的共同必经前序”，不是物理资源依赖的证明。不能把一条路径中的普通先后全部当成必需依赖，也不能先合并所有候选边、再删除整个强连通分量来得到结果。

| 路径证据 | 内部共同前序 | 含义 |
| --- | --- | --- |
| `A B C`、`B C A` | `B ≺ C` | A 的位置可变，不应连同 B、C 一起删去 |
| `A B`、`B C`、`C A` | 无共同必经边 | 局部顺序不足以确定全局关系，不能宣称全部独立 |
| `A B C`、`B A C` | `A ≺ C`、`B ≺ C` | C 有两个前序，结果不一定是一棵单父树 |

公开结果只有 `ScopeTree`，其父子边表达构树结果，以下路径与候选证据直接保存在同一结构中：

- `scopePaths`：各独立 chain 的路径，而非跨 Node 拼接的运行顺序。
- `scopeCandidates`：raw 候选关系，来自单条路径的前后关系，尚未当作必经边；入口来源见 `graphRootPaths`。
- `scopeOpposed`：存在两条分别包含 A、B 的路径，一条为 `A … B`，另一条为 `B … A`。这是无固定顺序的双向实证；不能用不同路径的边拼出的 union reachability 代替。
- `scopeUndetermined`：仅凭路径不能建立共同必经关系、又没有上述双向实证的未定关系。缺少共同路径或覆盖不足不等于独立；补充的注册前提可能进一步确定这些节点的清理关系。

中介不改变单条路径的顺序证据：`A X B` 已经表示这条路径上 A 先于 B。把一条路径的 `A X` 与另一条路径的 `X B` 拼成 `A B`，则不能冒充实际路径证据。新增路径可能削弱已知顶点间的共同前序；结论始终相对于所保留的路径族。

这里的双向实证来自所保留的静态路径，包括 Recover 的保守路径；它不是运行采样，也不要求证明这些业务分支一定能成功执行。

## ScopeTree 是共享节点的 DAG

对共同必经前序做传递约简，保留相同的可达关系，得到无冗余边的 DAG。`ScopeTree` 以共享节点、`parents`、`children` 和 `layers` 表达它，不强迫每个 scope 只有一个父节点。

生成期的 `buildScopeTree` 形成路径观察结果，`completeScopeTree` 把注册前提补入同一份树并再次传递约简。结果发射为 `generatedScopeTree`；运行时 `ProgramStructure.structureScopes` 直接保存这份 `ScopeTree`，不增加另一份 scope 计划或持久化依赖图。

多条路径引用同一定义时，共享该节点；各路径证据仍分别保留。最终父边和 `layers` 表达采用的保守清理偏序，不因同层而断言资源使用互不影响，也不据此重排业务方法或提前执行 open。

## 注册前提与运行清理

生成期的 `GraphPlan.planScopes` 为每个可开启 scope 提供其 open 方法身份、现有运行 scope 名字及保守前提。前提包括原有 `Input`／`request` 链上的 scope，以及声明的 `require` 来源可导航到的资源 Context owner 候选。`require` 仍只读取绑定，不因此执行来源生产者或打开 owner；关闭本 scope 自己声明的资源不会形成自依赖。实际实例归属仍由 Context 绑定中的 owner 决定，静态声明不替代该检查。

生成期合并的是上述前提和 `buildScopeTree` 得到的共同前序父边，不使用 `scopeCandidates` 的并集。所有可开启注册 scope 都进入最终树，包括本次结构没有出现 open 的注册；它们没有被执行就不会产生待清理资源。重复身份或名字、缺失映射、未知前提及合并形成的环均在生成时报告错误，不通过删除冲突边继续运行。

最终依赖只保存在 `ScopeTree` 的 `parents`／`children`／`layers` 中；`scopePaths`、`scopeCandidates`、`scopeOpposed` 与 `scopeUndetermined` 保留原路径证据，不能误读为新增的注册前提也已由路径证明。`ProgramStructure.structureScopeNames` 仅连接生成身份和现有运行名字；`scopeRelations structure` 临时投影同一棵树的全部祖先可达关系为运行配置，不另存第二份依赖结构。这样即使 `A → B → C` 中 B 尚无活实例，C 仍会保留 A 的清理前提。

运行层按最终父边先清理子 scope，再清理其前提；独立项延续现有句柄顺序的逆序。是否已经满足清理条件仍由实际实例和受管理使用者决定。`scopePaths` 只包含 open，读已有资源的 require-only chain 可以没有 open；重复 open 在路径中也已去重，因此不能把路径长度或出现次数直接当作使用者引用计数。

## Error 与清理使用同一棵树

App／IO 的生成入口沿原有 Input／request 关系查找最近的 scope，遇到 Scoped 就停止，得到关联种子而非完整祖先名单。Root 捕获 Failure 时合并已有 `scopeTrace`、当前 `errorPath` 与 `scopeTargets` 中的 scope 名字；生命周期锁内只保留这些种子，退到锁外后才导航和诊断。

`scopeErrorPath` 直接读取各 `ScopeHandler.scopeParentNames`。这是自动清理也使用的同一棵 ScopeTree 的全部祖先投影，不读取另一份 schema 或新增用户 key。SDK 补齐种子的祖先，按父到子的层次去重排序；同层沿 ScopeHandler 名单顺序，同一 scope 的多个 Error 回调沿注册顺序。完成路径写入 `Failure.scopeTrace`，再按路径匹配既有 callback 注册表，不把 callback 表本身当作依赖图。

此次接线只改变 App／IO 的候选导航来源。实例定位、隔离绑定快照、detect／resolve 结果和原失败传播继续沿用既有协议；不增加轮询、动态调用 tracing 或自动业务恢复。App／IO 未安装树时只能使用显式种子；Pure 没有 ScopeTree 安装路径，本轮继续使用旧的完整候选名单协议。

手改生成树的父边会同时影响 App／IO 的 Error 祖先导航和自动清理。运行校验只证明字段一致、无环等结构自洽性，不证明手改关系符合业务资源前提或故障归属。

## 查看初始化结果

生成的 `Generated.Program` 导出纯函数：

```haskell
programStructure
  :: AST
  -> Either (StructureError MethodGen) (ProgramStructure MethodGen)
```

现有 Main 无需修改，给 SDK 入口传 `--structure` 即可查看，例如：

```sh
cabal run crawler-demo -- --structure
```

该分支以可读格式显示 workflow、方法及其 effect 归属、方法引用、scope 层次与共享父节点、各入口路径，以及双向实证和未定关系，不重复输出内部共同前序。它读取同一份生成结构，不调用 `createEntries`，不创建运行 scope 句柄，不执行 handler 或业务 IO。普通启动使用同一份运行校验规则，完成结构后再装配执行动作。修改注册或手写 handler 后仍须重新生成，生成源码继续作为 review 面。

## 内容缓存与重跑边界

每次 gencode 仍加载声明并读取 Handlers 快照；结构分析和业务包装共用该快照，资产检查另用 GHC 名称解析同一快照，每次执行。命名空间的 `Generated/.scope-cache` 保存结构阶段的内容缓存，key 精确比较完整 `GraphPlan`、规范化后的 handler shapes，以及 `Effect/Graph.hs`、`Recursion.hs`、`Workflow/AST.hs`、`Workflow/Structure.hs`、`Codegen/Plan.hs` 的源码内容。不用 mtime 判断命中，也不通过加载或执行 `Generated.Program` 读取缓存。

key 未变时复用已经发射的纯 graph／tree ADT 文本。原子业务 IO 的修改若不改变 shapes，可复用结构结果，同时更新业务包装副本。每份生成文件都先比较完整内容，内容相同就不写回；这减少结构重算和无变化文件写入，不等于跳过整条生成命令，也不是逐方法热点生成、文件监听或运行中热重载。

`Generated.Program` 仍是派生产物。手改 `generatedScopeTree` 后，运行校验读取这些显式字段，不会重新推导父边；它只验证无环、字段一致等结构自洽性，不证明人工删边在业务上正确。下一次 gencode 会按源声明和方法结构恢复生成结果，缓存不把手改文件当作权威。不增加手工 edge override 层，也不承诺保留生成文件中的手改。

本轮沿用项目的普通编译要求，不新增测试、负例或检查门槛。
