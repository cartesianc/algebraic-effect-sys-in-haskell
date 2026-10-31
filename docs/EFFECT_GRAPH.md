# 静态 Prototype、运行图与 ScopeTree

业务入口仍为 `main = interpreter ast effects`，手写 handler 仍使用原生 Haskell 的 `instance`、`do`、模式匹配和方法引用。`Framework.Prototype` 在 gencode 阶段统一构建注册、方法、workflow、链定义与挂载、effect graph 和 ScopeTree，发射唯一的 `generatedPrototype :: SDK.Prototype MethodGen` 显式 ADT 常量。运行时校验并直接使用这份原型，不预执行 Context 或资源 IO。

生成前可由 GHC／HLS 检查手写模块是[核心设计约束](DESIGN_METHOD.md#生成前仍是原生-haskell核心约束)。已有契约接口提供类方法与 ADT 类型关系；生成器从合法 Haskell 中提取支持的结构，不要求先把业务源码转换成另一种语法。宿主语言类型正确与静态 effect 结构可提取需要分别满足。

初始化后的 `ScopeTree` 在 App／IO 中同时提供 Error 的祖先候选导航与有限执行自动收尾的保守清理前提。运行层仍按实际 scope 实例及使用登记判断能否关闭；静态图不判断故障归属或某份资源已经无人使用，也不新增 Error 的动态调用 tracing。

## 定义、挂载与运行实例

`Prototype` 只保存纯数据，不包含执行函数、类字典或活资源。它派生 `Eq`、`Show`、`Read`、`Generic` 并提供 `NFData`；方法身份在生成器中为 `String`，发射后为 `MethodGen`。

| 层次 | 原型字段／运行对象 | 身份与作用 |
| --- | --- | --- |
| 注册与方法 | `protoEffects`、`protoMethods` | 集中保存能力、取值路由、挂接和显式方法结构 |
| 链定义 | `protoChainDefinitions` | 用 `OriginChain` 与 `ContextChain` 区分原始操作链和 Context 生产／读取链；按入口方法识别 |
| AST 挂载 | `protoWorkflow`、`protoChains` | 每个 node 和 alternative 选择读取各一条挂载记录，按 `NodeId` 识别 |
| 运行实例 | 活动 chain、Context 绑定出身、scope 实例与入口使用登记 | 运行图共享静态原型，根据实际调用更新；不反向修改定义 |

`NodeId = [Int]` 是当前原型快照内的 AST 下标路径：根为 `[]`，普通子项从零编号；alternative 的选择读取链使用该分支路径加 `[-1]`。同一个 origin 末端挂载两次会有两个 `NodeId`，共享方法定义。Context 链经 demand 或挂接进入，定义本身没有虚构的 AST 位置。编辑 AST 后重新生成编号；这些路径不充当跨快照稳定 key 或运行调用序号。

链事实和标准查询由 `Framework.Prototype` 统一提供。Codegen 读取这些事实生成接口与包装，Execution 读取挂载关系装配闭包，运行图共享这份原型并保存活动实例关系。运行图不累计完整方法调用历史。Stage 2 由 `chainDrives`、`chainReads` 和 `protoSources` 保存可能生产、缺值读取与可见来源候选；runtime 按 origin 读取和加锁。清理与 Error 边界保留。SDK 当前采用 Haskell ADT，不增加 JSON 或外部 LSP 协议。

## 运行图与两种链启动

运行身份由 `Framework.Effect.Runtime.Identity` 定义，活动关系由 `Framework.Effect.Runtime.Graph` 管理。一次 interpreter 运行共享静态 Prototype 引用及运行图；活动 chain 引用其静态链定义，scope 实例引用其 Scoped 定义，Context 绑定保存产生它时的 `Execution`。

```haskell
data Origin = Origin { originNode :: NodeId, originSequence :: Integer }
newtype ActivationId = ActivationId Integer
data Boot = TargetedBoot NodeId | RequestBoot String
data Execution
  = BusinessExecution Origin
  | CleanupExecution Origin String Int
```

`Origin` 区分一次 AST 入口执行，`ActivationId` 区分运行图中的一次活动 chain。`RequestBoot` 的字符串是现有 Context effect 注册名；`CleanupExecution` 保存原业务 origin、scope 注册名及现有实例编号，不新增业务 key。Context 的嵌套生产有新的 activation，但普通生产沿用外层业务 origin。

`RuntimeGraph` 用存在类型包装保存实际的 `Prototype MethodGen` 和 `ChainDefinition MethodGen`，不把图转换为字符串副本。`runtimeScopes` 引用原有 scope 控制对象；`runtimeAssets` 按 origin 保存发布时无 owner 的业务绑定，后续 claim 保留该 publication 引用；open 内一开始就有 owner 的产物仍只保存在 scope／局部快照。`runtimeForcing` 按 origin 和 Context 来源分配求值锁。活动表中的每条 `Activation` 保存父 activation、启动方式、`Execution`、静态链定义、当前绑定 `IORef` 和 `ScopeUser`；执行器和活动表共享这些运行引用。

链有两种启动边界：

1. **AST 启动**：Node 或 alternative 的选择读取启动选定入口，建立本次 origin 及入口使用登记。
2. **Context 启动**：实际 `request` 生产建立 ctx chain 记录，包住生产、成功发布和返回。嵌套 ctx 启动继承外层 origin 和入口使用登记；返回只结束本次生产记录，不撤销整个入口对 scope 的使用。读取已有绑定的 `require` 没有新 activation；缺值求值和挂接注入实际生产时经过同一启动边界。

这里的“入口使用登记”是原有有限使用闭包的资源含义：一次 AST 入口内，实际 open／require 选中的 scope 计入同一份使用。`ScopeUser` 保留原有 `Unique` 协调身份，并新增 `scopeUserExecution`；同一入口的 ctx chain 使用同一个 `ScopeUser`。`scopeUsers` 同时携带使用者身份与 `Execution`，不以 AST 位置替代并发使用协调。

Context 的生产记录在生产、发布及返回结束后通过 `finally` 删除，失败或中断也撤销活动记录。AST 根活动记录覆盖业务、诊断、受控结果消费、入口使用撤销及其收尾；撤销使用后仍按 once-spare 决定关闭。清理使用独立的 `ScopeUser` 和 `CleanupExecution`，保留原始业务来源但不冒充一次新的业务入口；不会为后续清理复活已经结束的父 activation。活动表只保留当前记录，绑定和资源需要的来源身份可独立保存。

`Binding.bindingOrigin :: Execution` 保存不变的执行出身，`bindingOwnership` 是一次成功 request 独有的共享 `IORef`，保存可选 owner 与待认领的使用者。当前捕获、权威表、scope 快照和 Handoff 都共享该单元；owner 是实际实例引用。首次认领在 `scopeCoordinator` 内从无 owner 变为唯一实例，同实例重复认领幂等，其他实例拒绝；认领先于等待实例生命周期锁。值、origin 和既有 publication 不因认领改变，不删除来源或重发布。诊断和自动 cleanup 中的生产只更新局部快照，不写入业务 origin 的权威表。

无 owner 的资源绑定在发布／require 返回前登记当前 `ScopeUser`；认领把仍活跃的持有者接入实例，入口退出则撤销待认领登记与实例使用，三者共用 `scopeCoordinator`。普通资产不加入待认领集合，open 内正常生产已有 owner 的路径保持原协议。认领到保存绑定保持 masked，确保这段交接不会漏掉 cleanup。资源快照按共享归属单元去重，独立 request 不合并；两次生产包装同一物理 Handle 的别名不在此协议内。

ScopeTree 仍是独立的静态构树结果，保留路径分析、注册前提补全和无环检测。运行图关联实际 scope 实例与使用者，不从 ctx 调用嵌套关系重建 scope 父边；Error 导航和清理继续使用同一份补全后的 ScopeTree。静态定义、活动调用与资源依赖各有身份，不能用其中一层的边代替另一层。

## 资产来源与缺值路径

注册中的唯一 Context 生产方与运行中的唯一来源是两个层次：一个生产方法可能被多个 AST 入口调用，产物因此具有不同 origin。运行级保存按 origin 与 Context 来源区分，同一来源在不同入口中的值不再全局互相覆盖。

来源分析在生成期使用规范化、尚未并入挂接注入的方法体，以及未被手写覆盖的默认 require 集合，区分显式生产、挂接注入和缺值时的条件生产；这些是构建过程中的局部数据，不额外发射到 runtime。沿有限方法及 workflow 路径计算每链的 `chainDrives`、`chainReads`，为 `ReadPoint NodeId 基础契约` 保存：

```haskell
data Source = FromOwnChain | FromChains [NodeId]
```

`FromOwnChain` 表示缺值时按既有规则由当前入口生产；`FromChains` 保存许可的可见前驱候选。前驱必须由 AST 保证先于当前入口完成，alternative 选择读取先于其候选；parallel 兄弟互不可见。候选可有多个，生成期只要求在需要跨链解析的缺值路径上，同时可见的实际来源至多一个。已捕获绑定的其他路径上，这些节点可以共同发布，由当前快照确定读取值。证明考虑 alternative 和“上游没有发布才触发 fallback”的条件关系；不能以最后完成、距离最近或最后写入替代唯一性。

方法已经捕获绑定的路径不需要跨链解析；某些路径已捕获、其他路径尚未捕获是合法的。只对后者检查唯一来源。`Recover` 保留可能失败前缀，不假定正文生产全部完成。`Source` 只保存最终候选集合，不把路径证明伪装成已保存的数据；运行校验检查引用和可见性等字段自洽，不重跑来源分析，runtime 再核对本次实际已发布来源的唯一性。

分析状态只保存本链或后续 workflow 可能读取的基础契约。读取集合从已有 `chainReaches` 保守推导，包含默认／覆盖的读取方法，以及 consumer 的 require 声明将直接生产方法调用路由为读取的情况。每个方法出口先投影发布与捕获状态，再去重；顺序节点向后传递后续仍需的发布，parallel 的各分支仍从同一前置状态分析，结果先投影再组合。`chainDrives`、`chainReads` 与来源候选单独累计，裁剪不删除这些事实，也不改变 runtime 的绑定保存。方法失败仍携带相关状态供 `Recover`／吞错注入继续；workflow 失败没有恢复后继，发布组合可直接丢弃。

这样可消除独立、后续无人读取的可选发布造成的 `2^N` 状态组合；仍同时相关的契约保留原有路径关联，最坏状态数仍可能指数增长。本次优化不声称整体分析具有线性复杂度。

无 owner 资产运行时依次查当前捕获、静态许可的实际发布、当前 origin 的按需求值。候选本次没有值且既有协议允许生产时，fallback 是一次普通 request：生产、按当前 origin 发布、返回，后续 AST 可见的读取能复用它。因而 fallback 也必须进入后继的来源分析，不能只固定最初候选而禁止后来合法生产的值传播。资源契约即使保留读取点，也仍由 owner 协议定位，缺值时不因来源表为空而自动生产；诊断和自动 cleanup 的缺值例外同样保留。按需求值锁按当前 origin 与 Context 来源分配；显式 request 每次执行，不参与自动合并。

scope 的例外只覆盖具有 owner 的绑定，资源仍经实际实例定位和共享。实例快照中的无 owner 辅助值只从按 origin 保存的权威表取用，不通过资源复用绕过可见性。诊断及自动 cleanup 的新产物仅局部可见。现有 App 的 bind 在取得值后继续方法体，handler 写法、AST 语法和 ScopeTree 算法均不因此改变。

## 生成方法身份与纯结构副本

生成器为注册的方法生成 `MethodGen` 枚举身份：方法名首字母大写，再加 `Gen`，例如 `openFileSession` 对应 `OpenFileSessionGen`。结构中的调用边引用该身份，保留其所属 effect 和方法角色；同一个 effect 的 open、close、request、require 等方法分别识别。

`MethodDefinition.methodIdentity` 表示当前方法；`methodEffect` 使用同一 effect 的首个注册入口的 Gen 身份，将该 effect 的方法归为一组，不增加 effect key。例如 `openFileSession` 与 `closeFileSession` 的方法身份不同，但 `methodEffect` 都为 `OpenFileSessionGen`。scope 的静态身份使用其 open 方法身份。

生成器通过 GHC 解析器查看手写方法体中的显式 effect 方法引用，另行生成纯结构副本。副本剥离业务值、模式匹配所得数据、纯计算结果和实际 IO，只保留方法引用及其结构关系。调用顺序、分支和重复调用不能被简单的名称集合代替；静态分支保留可能路径，不执行条件表达式来选择业务分支。Context 生产方法在消费者中的 request／require 模式仍由注册决定，不能仅按方法名判断是否重新生产。

结构副本描述带包装的句柄：原子句柄（Excu.handler、Scoped.open）的生成入口在方法体返回后注入挂在它下面的 Context，构图时该句柄的定义因此在方法体之后接一个可选分支，内容是这些 Context 的方法体，其中对该句柄的直接调用记为空（注入期间由本次输出回答，不再执行）。注入路径由此进入 effect graph 与 ScopeTree，不形成环；挂接的 Context 经其他方法又回到该句柄时生成器报错。

业务执行副本仍只添加既有入口包装，原方法体表达式保持不变。这里不再使用“生成器完全不查看方法体”的限制；新的边界是读取显式引用并生成独立结构，不解释任意业务值语义、不改写业务表达式、不要求用户补写 layer 或另一份调用声明。结构提取也不证明任意 Haskell 函数的行为、动态调用次数或物理资源依赖。

当前 source 结构支持显式 effect 调用、原生 `do`、`if`／`case` 和已识别的标准组合，包括顺序／绑定运算、`when`／`unless`、`either`／`maybe` 及 `catchError`。条件和待匹配的值本身不能隐藏 effect 调用。未知高阶 effect 组合、经普通函数或局部别名间接调用 effect、含 effect 的循环组合（如 `forM_`／`replicateM_`）以及递归 effect 引用会报告错误，不静默生成空图。没有 effect 引用的原子业务表达式可在 instance 方法体内使用原生 Haskell 语法，结构副本将其擦除；方法内直接以标准组合完成 IO 迭代或数据计算，不受上述 effect 组合限制。[源码资产检查](ASSETS.md) 另行约束普通函数对业务 ADT 的显式使用，泛型函数或仅处理通用类型的普通函数允许；资产检查与 effect 图提取是两个不同边界。

`catchError body recovery` 使用独立的 `Recover` 结构。scope 分析保留正文的正常路径，并为每条正文路径的任意 scope 前缀接入 recovery 路径；前缀包括空前缀和完整前缀，不假定正文一定全部执行后才进入 recovery。这是保守的静态路径集合，不执行业务来验证成功条件，也不证明某个 scope 已成功获取资源。

## 生成期构图，运行期初始化与执行

生成阶段按以下顺序推进：

1. 加载注册、表示类型的和类型信息与完整 AST，由 `preparePrototype` 形成 `PrototypePlan`，集中解析声明关系并为 workflow 编号；同一次 Handlers 快照提供方法纯结构及业务包装副本。
2. `buildPreparedPrototype` 合并显式方法、默认读取和挂接注入，构建 origin／ctx 链定义及 AST 挂载。方法展开使用共享的 `expandChain`，图与 scope 路径通过 `zygo` 汇总。
3. 汇合独立入口的路径证据，把保守注册前提补入同一份 `ScopeTree`，完成原型自洽校验、Context 驱动检查和 alternative 覆盖检查。
4. 在内存中的候选接口上完成源码资产检查，再把整个 `generatedPrototype` 写入 `Generated.Program`；`Generated/Assets.hs` 仍是独立的源码资产目录。生成失败不发布新的结构。

运行时先核对注册与源码快照，执行 `evaluate (force generatedPrototype)` 和 `validatePrototype`，检查身份、引用、挂载、父子关系、层次与无环性；随后对当前 AST 做一次 `cata`，逐位置匹配 `protoWorkflow`，按 `NodeId` 读取入口和 alternative 对应关系，并装配尚未执行的 action。所有分支及挂载核对通过后，才安装 scope 关系并执行业务。`ProgramStructure`、`initializeGeneratedStructure` 和旧的分散结构常量已删除。运行时不重新展开方法、运行 `zygo` 或推导父边；AST 的位置或结构变化也须重新生成。

执行 fold 的结果为 `Either`，其中携带已收集的入口及尚未执行的 `ExceptT / IO` 动作。顺序和并行分支均先检查全部子分支，完成入口集合比较后才运行 action；不会靠执行业务来强制结构求值。创建 Target 仅分配空的运行状态，不打开资源，scope 实例、使用计数和锁仍按已有运行协议管理。

`Chained` 和 `Parallel` 可以汇总 Node 的结构，但不把不同 Node 的链拼成一条 scope 启动路径。尤其不能从 AST 中“Node A 先执行、Node B 后执行”推导其 scope 存在依赖。方法结构中的路径与 workflow 的节点调度是不同层级。

这里要求完成的是有限纯结构，不是提前强制业务产物或获取资源。生成期的 `zygo` 共享辅助归约与主归约的递归过程，不新增一套业务执行器。

## ScopeTree 的内部构树规则

保留每条静态 scope 路径及其来源；`EffectGraph.graphRootPaths` 记录每个入口及其 scope 路径，`graphScopePaths` 提供汇总路径。路径可以包含不同的 scope 集合；scope 记在其 open 方法体之后，即开启完成的位置，因此 open 内部开启的 scope 排在外层之前，嵌套 open 的方向与注册前提一致；每条路径按 scope 定义首次完成去重，仅用于定义层的导航，不据此推断多实例数量、重复 open 的效果或关闭后重开。

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

生成期的 `buildScopeTree` 形成路径观察结果，`completeScopeTree` 把注册前提补入同一份树并再次传递约简。结果保存在 `generatedPrototype` 的 `protoScopes` 字段；运行时直接读取，不增加另一份 scope 计划或持久化依赖图。

多条路径引用同一定义时，共享该节点；各路径证据仍分别保留。最终父边和 `layers` 表达采用的保守清理偏序，不因同层而断言资源使用互不影响，也不据此重排业务方法或提前执行 open。

## 注册前提与运行清理

生成期从 `EffectProto` 的方法、名字与 `effectScopeParents` 取得每个可开启 scope 的 open 方法身份、运行名字及保守前提。前提包括原有 `Input`／`request` 链上的 scope，以及声明的 `require` 来源可导航到的资源 Context owner 候选。这种结构补全不预执行来源生产者或打开 owner；运行时的 `require` 保留已有值直接读取、缺值按 thunk 求值以及资源 Context 禁止按需求值的原协议。关闭本 scope 自己声明的资源不会形成自依赖。实际实例归属仍由 Context 绑定中的 owner 决定。

生成期合并的是上述前提和 `buildScopeTree` 得到的共同前序，不使用 `scopeCandidates` 的并集。注册前提是依赖：上游 scope 必须比下游活得久，下游的 close 也可能调用上游。观察到的开启顺序是证据：共同前序按完整传递关系逐条补入，与注册前提及已补入的边构成相反方向的不作为父边，例如 handler 先开启 B、后开启 B 的 Input 上游 A 时以 A 为 B 的父节点。被推翻的顺序仍保留在 `scopeCandidates`，`--structure` 单列显示。所有可开启注册 scope 都进入最终树，包括本次结构没有出现 open 的注册；它们没有被执行就不会产生待清理资源。重复身份或名字、缺失映射、未知前提及注册前提自身的环均在生成时报告错误。

最终依赖只保存在 `ScopeTree` 的 `parents`／`children`／`layers` 中；`scopePaths`、`scopeCandidates`、`scopeOpposed` 与 `scopeUndetermined` 保留原路径证据，不能误读为新增的注册前提也已由路径证明。`protoScopeNames` 连接生成身份和运行名字；`scopeRelations prototype` 临时投影同一棵树的全部祖先可达关系为运行配置，不另存第二份依赖结构。这样即使 `A → B → C` 中 B 尚无活实例，C 仍会保留 A 的清理前提。

运行层按最终父边先清理子 scope，再清理其前提；独立项延续现有句柄顺序的逆序。是否已经满足清理条件仍由实际实例和受管理使用者决定。`scopePaths` 只包含 open，读已有资源的 require-only chain 可以没有 open；重复 open 在路径中也已去重，因此不能把路径长度或出现次数直接当作使用者引用计数。

## Error 与清理使用同一棵树

App／IO 的生成入口沿原有 Input／request 关系查找最近的 scope，遇到 Scoped 就停止，得到关联种子而非完整祖先名单。Root 捕获 Failure 时合并已有 `scopeTrace`、当前 `errorPath` 与 `scopeTargets` 中的 scope 名字；生命周期锁内只保留这些种子，退到锁外后才导航和诊断。

`scopeErrorPath` 直接读取各 `ScopeHandler.scopeParentNames`。这是自动清理也使用的同一棵 ScopeTree 的全部祖先投影，不读取另一份 schema 或新增用户 key。SDK 补齐种子的祖先，按父到子的层次去重排序；同层沿 ScopeHandler 名单顺序，同一 scope 的多个 Error 回调沿注册顺序。完成路径写入 `Failure.scopeTrace`，再按路径匹配既有 callback 注册表，不把 callback 表本身当作依赖图。

此次接线只改变 App／IO 的候选导航来源。实例定位、隔离绑定快照、detect／resolve 结果和原失败传播继续沿用既有协议；不增加轮询、动态调用 tracing 或自动业务恢复。App／IO 未安装树时只能使用显式种子；Pure 没有 ScopeTree 安装路径，本轮继续使用旧的完整候选名单协议。

手改生成树的父边会同时影响 App／IO 的 Error 祖先导航和自动清理。运行校验只证明字段一致、无环等结构自洽性，不证明手改关系符合业务资源前提或故障归属。

## 查看初始化结果

生成的 `Generated.Program` 导出静态的纯值：

```haskell
generatedPrototype :: SDK.Prototype MethodGen
```

现有 Main 无需修改，给 SDK 入口传 `--structure` 即可查看，例如：

```sh
cabal run crawler-demo -- --structure
```

该分支通过纯校验核对当前 AST 与原型快照，以可读格式显示带 `NodeId` 的 workflow、origin／ctx 链定义、链挂载、方法及其 effect 归属、方法引用、scope 层次与共享父节点、各入口路径，以及双向实证和未定关系。它读取同一份原型，不调用 `createEntries`，不创建运行 scope 句柄，也不装配或执行 handler。普通启动在自己的单次执行装配 fold 中核对相同挂载规则。修改注册、AST 或手写 handler 后须重新生成。

## 内容缓存与重跑边界

每次 gencode 仍加载声明并读取 Handlers 快照；结构分析和业务包装共用该快照，资产检查另用 GHC 名称解析同一快照，每次执行。`Generated/.scope-cache` 保存三项：输入 key、纯 `Prototype String`、已经渲染的 Haskell 源码。key 精确比较完整 `PrototypePlan`、规范化方法结构及算法源码：`Prototype.hs`、`Codegen.hs`、`Codegen/Plan.hs`、`Effect/Registration.hs`、`Effect/Contract.hs`、`Effect/Graph.hs`、`Recursion.hs`、`Workflow/AST.hs` 和 `Workflow/Structure.hs`。不用 mtime 判断命中，也不加载或执行 `Generated.Program` 读取缓存。

key 未变时复用纯原型和渲染文本，仍运行 `validatePrototype`、`checkDriven` 及源码资产检查；首次没有 Handlers 时仍按原协议跳过驱动检查、先提供契约。原子业务 IO 的修改若不改变方法结构，可复用原型，同时更新业务包装副本及源码指纹。每份生成文件都先比较完整内容，内容相同就不写回；这减少结构重算和无变化文件写入，不等于跳过整条生成命令，也不是逐方法热点生成、文件监听或运行中热重载。

`Generated.Program` 仍是派生产物。手改 `generatedPrototype` 中的 `protoScopes` 后，运行校验读取这些显式字段，不会重新推导父边；它只验证无环、字段一致等结构自洽性，不证明人工删边在业务上正确。下一次 gencode 会按源声明和方法结构恢复生成结果，缓存不把手改文件当作权威。不增加手工 edge override 层，也不承诺保留生成文件中的手改。

本轮沿用项目的普通编译要求，不新增测试、负例或检查门槛。
