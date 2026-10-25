# Effect 构造原理：GADT、newtype 与自动 input

本页对应 [C5 源码](effect-sample/Effect.hs)。使用说明见 [QUICKSTART.md](QUICKSTART.md)，方法与 impl 见 [IMPL.md](IMPL.md)。

## 1. 统一包装和类型推断

```haskell
newtype Registered e =
  Registered (Registration (Typing e) e)

effect :: Effect e => Registered e
effect = Registered registration

sample = compile reportArguments
reader = readFrom ReadNow
```

Registered 的 newtype 包装与内部注册共享运行时表示。effect 从类字典取得自动组装的 registration 并包装。每种 effect 在 instance 中定义类型契约和 impl；compile、readFrom、mapped、closes、handles 内部统一调用 effect。

调用上下文确定具体类型：reportArguments 的类型确定 ReportRead，ReadNow 的类型 Require ReadLoaded 确定 ReadLoaded，closes CloseNow 中的 CloseNow 确定 CloseFile。GHC 据此选择对应的 Effect instance。直接操作注册时仍可用 (effect :: Registered LoadText)。

LoadText 提供类型身份，Require/Handle/Value/Failure 是关联数据。单字段采用关联 newtype 实例，多分支采用关联 data 实例。统一注册外壳由一份普通 newtype 覆盖。

## 2. 从 Input 计算 superclass

```haskell
class Inherited (Input e) => Effect e where
  type Typing e :: EffectKind
  type Typing e = 'KExcu
  type Input e :: Type
  type Input e = ()
  type Exports e :: [Symbol]
  type Exports e = '[]

  data Require e :: Type
  data Handle e :: Type
  data Value e :: Type
  data Failure e :: Type

  impl :: AllHandlers (Exports e) e
       => Context e -> Require e -> ImplReturn (IsStep (Typing e)) e
  default impl :: (Typing e ~ 'KSource, AllHandlers (Exports e) e)
               => Context e -> Require e -> ImplReturn (IsStep (Typing e)) e
  impl _ _ = ()

  scope :: ScopeConfig (Typing e) e
  default scope :: ScopeConfig (Typing e) e ~ () => ScopeConfig (Typing e) e
  scope = ()

  registration :: Registration (Typing e) e
  default registration :: BuildRegistration (IsStep (Typing e)) e
                       => Registration (Typing e) e
  registration = buildRegistration @(IsStep (Typing e)) @e

type family Inherited parent :: Constraint where
  Inherited () = ()
  Inherited parent =
    (Effect parent, AllHandlers (Exports parent) parent)

type family AllHandlers names e :: Constraint where
  AllHandlers '[] e = ()
  AllHandlers (name ': names) e =
    (Handler name e, AllHandlers names e)
```

Input 声明一次，默认 () 表达根节点。Exports 记录本 effect 公开的方法，上游 Effect 的 superclass 继续带入祖先。每条链在 () 结束，注册类型应形成有限、无环的上游链。

Typing 默认 Excu；其他分类显式声明。注册组装由库统一完成，业务 instance 填写 impl 方程。Source 由环境提供完成结果，默认 impl 返回单位值；默认签名中的 KSource 等式保证其他分类必须实现 impl。Scope 的 scope 方法必填，其他分类默认使用单位值。关联 data family 保留显式声明，空 data 表达该接口无构造器。

ConstraintKinds、TypeFamilies、UndecidableSuperClasses 和 UndecidableInstances 支持上述计算；Undecidable 扩展把终止性的设计责任交给库。

Exports 声明本层提供的方法名称。Effect 的 superclass 提供祖先字典，注册构造器提供本层字典。invoke 按这份声明查找方法，具体 operation 仍遵循 Haskell 实例解析规则；资源权限和关闭责任通过资源接口表达。

## 3. GADT 与绑定

```haskell
data Registration kind e where
  Source
    :: (Effect e, Typing e ~ 'KSource)
    => Registration 'KSource e
  Effect
    :: (Effect e, Effect (Input e), AllHandlers (Exports e) e,
        kind ~ Typing e, IsStep kind ~ 'True)
    => { typing  :: Shape kind e
       , bind    :: Impl e
       }
    -> Registration kind e
```

Shape 细化分类结构：Scope 携带 close/onError，Close/X 的输入关联 Scope。Effect 构造器保存本层方法字典和 Effect 字典；内部 bind 字段保存 impl 方法，通过 Impl e 的约束取得字典。

分类标记与绑定由库组装，前台只填写有业务含义的声明：

```haskell
type family ImplReturn step e where
  ImplReturn 'False e = ()
  ImplReturn 'True e = Action (Typing e) (ImplOutput (Typing e) e)

type family ScopeConfig kind e where
  ScopeConfig 'KScope e = Shape 'KScope e
  ScopeConfig kind e = ()

class BuildRegistration (step :: Bool) e where
  buildRegistration :: Registration (Typing e) e

instance (Effect e, Typing e ~ 'KSource) => BuildRegistration 'False e where
  buildRegistration = Source

instance ( Effect e, Effect (Input e), AllHandlers (Exports e) e
         , IsStep (Typing e) ~ 'True, KnownShape (Typing e) e
         ) => BuildRegistration 'True e where
  buildRegistration = Effect (knownShape @(Typing e) @e) (impl @e)
```

KnownShape 的库内实例将 KExcu/KRead/KMap 恢复为对应标记，将 KScope 恢复为用户填写的 scope，并在 KClose/KX 上保留上游必须为 Scope 的约束。Source 直接组装为 Source 构造器，其启动分支从环境取得结果。

ImplReturn 只细化返回部分，Context e 和 Require e 始终保留在方法的显式参数中。因此 impl 递归处理另一个请求时，编译器仍能从参数推断 e。普通步骤的方法类型与原有 Impl e 函数类型一致。

具体 effect 身份是普通类型，方法提供者通过类型族求出。当前存在封装用于 FailureInfo、Finalizer、Recovery；未来异构 AST 可进一步封装 Registered e。

```haskell
input :: IsStep (Typing e) ~ 'True
      => Registered e -> Registered (Input e)
input (Registered (Effect _ _)) = effect
```

关联类型声明决定上游，库函数 input 恢复对应注册。当前每个具体类型使用其 instance 自动生成的一份注册；运行参数和入口资源承载每次调用的差异。

### 方法解析与资源投影

```haskell
newtype Context e = Context (ImplInput (Typing e) e)

type Impl e =
  (Effect e, AllHandlers (Exports e) e)
  => Context e -> Require e
  -> Action (Typing e) (ImplOutput (Typing e) e)
```

Context 是库统一的 newtype，标记正在执行的 e，并包装本次已取得的上游输入。impl 通过这个参数调用 invoke @"方法名"，编译器据此推断 e。

Owner 通过类型族从当前 e 的 Exports 开始查找，再沿 Input 选择最近的上游。同名方法由最近层解释，链终点缺少名字时产生类型错误。库统一提供 Invoke instance，按 Owner 取得 Handler 的 operation 类方法。

RouteTo 类型族比较当前输入与该方法的 OpInput。输入相同就直接传递；两者都是 Ready 时沿类型化父链投影。适配只能使用当前已取得的资源。查找路径由类型计算确定，执行时应用对应的字典与投影函数。

纯 Map 的 Value 输入走同值适配。整条调用路径由类型计算、类方法字典与普通函数应用组成，最终连接为可执行闭包。

## 4. 可归约的闭包连接

```haskell
compile :: Effect e => Arguments env e -> env -> IO (Result e)
```

connect 沿 input 组合 continuation。每层从注册取得 impl 和字典，在上游成功后准备 Require 并调用 impl。Pending/Failed 直接传播；成功构造 Ready，保存本次结果和上游 Ready，交给下一层。

普通 Excu 的语义展开为：

```haskell
\env next ->
  parent env $ \upstream -> do
    outcome <- implementation (Context upstream) (prepare parameters env upstream)
    continueOnSuccess upstream outcome next
```

continueOnSuccess 概括源码中的成功分支匹配。注册、字典和函数通过普通 Haskell 应用组合；invoke 内部使用类型确定的 inputOf 投影。不可变 Ready 链随闭包携带资源，启动过程由 connect 的表达式定义。

Scope 将 acquisition 与清理安装放在同一异常屏蔽区域，恢复正常屏蔽状态执行下游，随后或异常时关闭同一资源。主操作成功时，关闭失败成为最终 Result；主操作已失败时保留原始失败。次生错误聚合仍待设计。

GHC 的实际内联和字典消除程度由优化决定；sample 验证闭包执行及静态依赖关系。静态线性 once 与 scope 逃逸限制继续由资源设计承接。

## 5. Result 与读取策略

Result.hs 独立于 Effect 和 IO，定义通用状态、完成值与显式读取。Effect.hs 关联 Handle e、Value e 和类型化 FailureInfo，并为成功执行建立 Ready。

ReadLoaded 使用 readValue 取得 Maybe value，PrepareReport 将它转为请求。Parameters 的 Functor/Applicative 实例通过 fmap、pure、<*> 组合共享同一环境和上游的纯表达式。这些纯适配和缺值处理属于本例策略。等待、恢复、continuation 和最终 Read/Map 语义可围绕通用 Result 单独设计。

## 6. Free 与后续 IR

Free 保留为递归描述、组合和序列化前端的候选。采用它时需要确定单层 functor、递归位置及结果参数，并验证 lowering 保持声明含义。

当前 C5 通过类型化 Input 与统一 Registration 连接闭包。有限上游关系具备明确展开规则，各操作共享一个 newtype 包装。AST 递归方案、异构封装和配置加载按各自需要继续设计。

IR 可读性和模块 middleware 持续指导后续工作：源码保留声明关系，闭包外围提供观察、mock、stress 和日志入口。
